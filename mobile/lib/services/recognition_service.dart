import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/juego_repository.dart';
import '../data/outbox_dao.dart';
import '../services/database_service.dart';
import 'api_service.dart';
import 'fuzzy_matcher.dart';
import 'phash_service.dart';

class RecognitionResult {
  /// Coincidencias locales (juegos ya en la BBDD).
  final List<LocalMatch> localMatches;

  /// Candidatos de BGG (texto OCR y/o IA de visión), siempre que haya red.
  final List<Map<String, dynamic>> bggGames;

  /// Texto bruto detectado por OCR (informativo / editable).
  final String extractedText;
  final List<String> triedQueries;

  /// Fuentes que aportaron resultados (puede haber varias a la vez).
  final Set<RecognitionSource> sources;

  /// Aviso si Vision falló pero hay otros resultados parciales.
  final String? visionWarning;

  RecognitionResult({
    required this.localMatches,
    required this.bggGames,
    required this.extractedText,
    required this.triedQueries,
    required this.sources,
    this.visionWarning,
  });

  /// Fuente principal (compatibilidad con UI antigua).
  RecognitionSource get source {
    if (sources.isEmpty) return RecognitionSource.none;
    if (sources.length == 1) return sources.first;
    return RecognitionSource.combined;
  }

  bool get hasLocal => localMatches.isNotEmpty;
  bool get hasAny => localMatches.isNotEmpty || bggGames.isNotEmpty;
}

enum RecognitionSource {
  none,
  ocrFuzzy,
  phash,
  vision,
  bggSearch,
  manual,
  combined,
}

class LocalMatch {
  final int juegoLocalId;
  final int? juegoServerId;
  final String nombre;
  final double score;
  final String matchedVia;

  LocalMatch({
    required this.juegoLocalId,
    required this.juegoServerId,
    required this.nombre,
    required this.score,
    required this.matchedVia,
  });
}

class _VisionResult {
  final List<Map<String, dynamic>> games;
  final String? warning;

  const _VisionResult({required this.games, this.warning});
}

/// Servicio de reconocimiento en paralelo:
///
/// 1. OCR (ML Kit) -> matching difuso contra juegos locales.
/// 2. aHash de la foto -> distancia Hamming contra `juegos.phash`.
/// 3. BGG por texto OCR.
/// 4. Vision API (OpenAI) -> identificación visual -> BGG.
///
/// Siempre devuelve coincidencias locales y candidatos BGG juntos.
class RecognitionService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _api = ApiService();
  late final _juegos = JuegoRepository(
    DatabaseService(),
    OutboxDao(DatabaseService()),
  );

  static const double _fuzzyThresholdLow = 0.65;
  static const int _phashMaxDistance = 14;

  /// Pipeline completo: OCR + local + pHash + BGG + Vision en paralelo.
  Future<RecognitionResult> recognizeGame(File imageFile) async {
    String extractedText = '';
    final tried = <String>[];

    try {
      final recognized = await _textRecognizer
          .processImage(InputImage.fromFile(imageFile));
      extractedText = recognized.text.trim();
      final queries = _buildQueries(recognized);
      tried.addAll(queries);

      final fuzzyFuture = queries.isNotEmpty
          ? _searchLocalByText(queries)
          : Future<List<LocalMatch>>.value(const []);
      final phashFuture = _phashMatches(imageFile);
      final bggFuture = queries.isNotEmpty
          ? _runBggQueries(queries)
          : Future<List<Map<String, dynamic>>>.value(const []);
      final visionFuture = _visionFallback(imageFile);

      final results = await Future.wait([
        fuzzyFuture,
        phashFuture,
        bggFuture,
        visionFuture,
      ]);

      final fuzzy = results[0] as List<LocalMatch>;
      final phash = results[1] as List<LocalMatch>;
      final bggText = results[2] as List<Map<String, dynamic>>;
      final vision = results[3] as _VisionResult;

      final localMatches = _combineMatches(fuzzy, phash);
      final bggGames = _mergeBggGames([bggText, vision.games]);
      final sources = _buildSources(
        fuzzy: fuzzy,
        phash: phash,
        bggText: bggText,
        vision: vision,
      );

      return RecognitionResult(
        localMatches: localMatches,
        bggGames: bggGames,
        extractedText: extractedText,
        triedQueries: tried,
        sources: sources,
        visionWarning: vision.warning,
      );
    } catch (e) {
      debugPrint('RECOGNITION ERROR: $e');
    }

    return RecognitionResult(
      localMatches: const [],
      bggGames: const [],
      extractedText: extractedText,
      triedQueries: tried,
      sources: const {RecognitionSource.none},
    );
  }

  /// Búsqueda manual: siempre local + BGG en paralelo.
  Future<RecognitionResult> searchByText(String rawText) async {
    final cleaned = _cleanText(rawText);
    if (cleaned.isEmpty) {
      return RecognitionResult(
        localMatches: const [],
        bggGames: const [],
        extractedText: rawText.trim(),
        triedQueries: const [],
        sources: const {RecognitionSource.none},
      );
    }
    final queries = [cleaned, ..._variantsOf(cleaned)];

    final results = await Future.wait([
      _searchLocalByText(queries),
      _runBggQueries(queries),
    ]);

    final local = results[0] as List<LocalMatch>;
    final bgg = results[1] as List<Map<String, dynamic>>;

    final sources = <RecognitionSource>{RecognitionSource.manual};
    if (local.isNotEmpty) sources.add(RecognitionSource.ocrFuzzy);
    if (bgg.isNotEmpty) sources.add(RecognitionSource.bggSearch);

    return RecognitionResult(
      localMatches: local,
      bggGames: bgg,
      extractedText: rawText.trim(),
      triedQueries: queries,
      sources: sources,
    );
  }

  Future<List<LocalMatch>> _searchLocalByText(List<String> queries) async {
    final allJuegos = await _juegos.getAllForRecognition();
    if (allJuegos.isEmpty) return const [];

    final matches = <LocalMatch>[];
    for (final row in allJuegos) {
      final nombre = (row['nombre'] as String?) ?? '';
      if (nombre.isEmpty) continue;
      double best = 0;
      const via = 'fuzzy';
      for (final q in queries) {
        final s = FuzzyMatcher.similarity(q, nombre);
        if (s > best) best = s;
      }
      if (best >= _fuzzyThresholdLow) {
        matches.add(LocalMatch(
          juegoLocalId: row['local_id'] as int,
          juegoServerId: row['server_id'] as int?,
          nombre: nombre,
          score: best,
          matchedVia: via,
        ));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(5).toList();
  }

  Future<List<LocalMatch>> _phashMatches(File file) async {
    final hash = await PhashService.hashFile(file);
    if (hash == null) return const [];
    final allJuegos = await _juegos.getAllForRecognition();
    final matches = <LocalMatch>[];
    for (final row in allJuegos) {
      final existing = row['phash'] as String?;
      if (existing == null || existing.isEmpty) continue;
      final dist = PhashService.hammingDistanceHex(hash, existing);
      if (dist <= _phashMaxDistance) {
        final score = 1 - (dist / 64.0);
        matches.add(LocalMatch(
          juegoLocalId: row['local_id'] as int,
          juegoServerId: row['server_id'] as int?,
          nombre: (row['nombre'] as String?) ?? '',
          score: score,
          matchedVia: 'phash',
        ));
      }
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(5).toList();
  }

  List<LocalMatch> _combineMatches(
      List<LocalMatch> fuzzy, List<LocalMatch> phash) {
    final byId = <int, LocalMatch>{};
    for (final m in fuzzy) {
      byId[m.juegoLocalId] = m;
    }
    for (final m in phash) {
      final existing = byId[m.juegoLocalId];
      if (existing == null) {
        byId[m.juegoLocalId] = m;
      } else {
        final combinedScore = (existing.score + m.score) / 2 + 0.1;
        byId[m.juegoLocalId] = LocalMatch(
          juegoLocalId: m.juegoLocalId,
          juegoServerId: m.juegoServerId,
          nombre: existing.nombre,
          score: combinedScore.clamp(0.0, 1.0),
          matchedVia: '${existing.matchedVia}+phash',
        );
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.take(5).toList();
  }

  Future<List<Map<String, dynamic>>> _runBggQueries(
      List<String> queries) async {
    final seenQueries = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final q in queries) {
      final query = q.trim();
      if (query.isEmpty) continue;
      if (!seenQueries.add(query.toLowerCase())) continue;
      try {
        final response =
            await _api.get('/bgg/search', params: {'query': query});
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        merged.addAll(games);
      } catch (e) {
        debugPrint('BGG search error: $e');
      }
    }

    return _mergeBggGames([merged]);
  }

  List<Map<String, dynamic>> _mergeBggGames(
      List<List<Map<String, dynamic>>> lists) {
    final byKey = <String, Map<String, dynamic>>{};

    for (final list in lists) {
      for (final game in list) {
        final key = _bggGameKey(game);
        byKey.putIfAbsent(key, () => game);
      }
    }

    return byKey.values.toList();
  }

  String _bggGameKey(Map<String, dynamic> game) {
    final bggId = game['bgg_id'];
    if (bggId != null) return 'id:$bggId';
    final name = (game['name']?.toString() ?? '').toLowerCase().trim();
    return 'name:$name';
  }

  Set<RecognitionSource> _buildSources({
    required List<LocalMatch> fuzzy,
    required List<LocalMatch> phash,
    required List<Map<String, dynamic>> bggText,
    required _VisionResult vision,
  }) {
    final sources = <RecognitionSource>{};

    if (fuzzy.isNotEmpty) sources.add(RecognitionSource.ocrFuzzy);
    if (phash.isNotEmpty) sources.add(RecognitionSource.phash);
    if (bggText.isNotEmpty) sources.add(RecognitionSource.bggSearch);
    if (vision.games.isNotEmpty) sources.add(RecognitionSource.vision);

    if (sources.isEmpty) sources.add(RecognitionSource.none);
    return sources;
  }

  Future<_VisionResult> _visionFallback(File file) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(file.path),
        'lookup_bgg': true,
      });
      final response = await _api.upload('/vision/recognize', formData);
      final data = response.data as Map<String, dynamic>;
      final bgg = (data['bgg_games'] as List?)?.cast<Map<String, dynamic>>();
      if (bgg != null && bgg.isNotEmpty) {
        return _VisionResult(games: bgg);
      }
      final candidates =
          (data['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final games = candidates
          .map((c) => {
                'name': c['name'],
                'year': c['year'],
                'bgg_id': null,
                'thumbnail': null,
                'description': c['reasoning'],
              })
          .toList();
      return _VisionResult(games: games);
    } on DioException catch (e) {
      debugPrint('VISION ERROR: ${e.message}');
      final status = e.response?.statusCode;
      String? warning;
      if (status == 503) {
        warning = 'La IA de visión no está configurada en el servidor.';
      } else if (status == 502) {
        warning = 'No se pudo contactar con la IA de visión.';
      } else if (status == 401) {
        warning = 'Sesión caducada; no se pudo usar la IA de visión.';
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        warning = 'Tiempo de espera agotado al consultar la IA de visión.';
      } else if (e.type == DioExceptionType.connectionError) {
        warning = 'Sin conexión; no se pudo usar la IA de visión.';
      } else {
        warning = 'Error al consultar la IA de visión.';
      }
      return _VisionResult(games: const [], warning: warning);
    }
  }

  List<String> _buildQueries(RecognizedText recognized) {
    final lines = <_ScoredLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = _cleanText(line.text);
        if (text.length < 3) continue;
        final box = line.boundingBox;
        final area = box.width * box.height;
        lines.add(_ScoredLine(text: text, area: area));
      }
    }
    lines.sort((a, b) => b.area.compareTo(a.area));

    final queries = <String>{};
    if (lines.isNotEmpty) {
      queries.add(lines.first.text);
      queries.addAll(_variantsOf(lines.first.text));
    }
    if (lines.length >= 2) {
      queries.add(_cleanText('${lines[0].text} ${lines[1].text}'));
    }
    for (final line in lines.take(4).skip(1)) {
      queries.add(line.text);
      queries.addAll(_variantsOf(line.text));
    }
    final words = <String>{};
    for (final line in lines.take(3)) {
      for (final w in line.text.split(RegExp(r'\s+'))) {
        final wc = _cleanText(w);
        if (wc.length >= 5) words.add(wc);
      }
    }
    final wordList = words.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    queries.addAll(wordList.take(3));
    return queries
        .where((q) => q.isNotEmpty)
        .map((q) => q.length > 80 ? q.substring(0, 80) : q)
        .toList();
  }

  Iterable<String> _variantsOf(String text) sync* {
    final base = _cleanText(text);
    if (base.isEmpty) return;
    final trimmed = base.replaceAll(RegExp(r'[^\p{L}\p{N}]+$', unicode: true), '');
    if (trimmed != base && trimmed.isNotEmpty) yield trimmed;
    var sub = base
        .replaceAll('|', 'I')
        .replaceAll('!', 'I')
        .replaceAll('\u00a1', 'I');
    sub = sub.replaceAllMapped(
      RegExp(r'([A-Za-z\u00c1\u00c9\u00cd\u00d3\u00da\u00e1\u00e9\u00ed\u00f3\u00fa\u00d1\u00f1\u00dc\u00fc])0([A-Za-z\u00c1\u00c9\u00cd\u00d3\u00da\u00e1\u00e9\u00ed\u00f3\u00fa\u00d1\u00f1\u00dc\u00fc])'),
      (m) => '${m[1]}O${m[2]}',
    );
    sub = sub.replaceAllMapped(
      RegExp(r'([A-Za-z\u00c1\u00c9\u00cd\u00d3\u00da\u00e1\u00e9\u00ed\u00f3\u00fa\u00d1\u00f1\u00dc\u00fc])1([A-Za-z\u00c1\u00c9\u00cd\u00d3\u00da\u00e1\u00e9\u00ed\u00f3\u00fa\u00d1\u00f1\u00dc\u00fc])'),
      (m) => '${m[1]}I${m[2]}',
    );
    if (sub != base) yield sub;
    final words = base.split(RegExp(r'\s+'));
    if (words.length >= 2) {
      yield words.sublist(0, words.length - 1).join(' ');
      yield words.sublist(1).join(' ');
    }
  }

  String _cleanText(String text) {
    return text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _ScoredLine {
  final String text;
  final double area;
  _ScoredLine({required this.text, required this.area});
}
