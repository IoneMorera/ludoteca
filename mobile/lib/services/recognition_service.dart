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
  /// Coincidencia local (un juego ya en la BBDD). Vac\u00edo si no hubo match
  /// suficientemente fiable.
  final List<LocalMatch> localMatches;

  /// Candidatos venidos del backend (BGG / Vision API). Solo se rellena si
  /// el matching local falla.
  final List<Map<String, dynamic>> bggGames;

  /// Texto bruto detectado por OCR (informativo / editable).
  final String extractedText;
  final List<String> triedQueries;
  final RecognitionSource source;

  RecognitionResult({
    required this.localMatches,
    required this.bggGames,
    required this.extractedText,
    required this.triedQueries,
    required this.source,
  });

  bool get hasLocal => localMatches.isNotEmpty;
  bool get hasAny => localMatches.isNotEmpty || bggGames.isNotEmpty;
}

enum RecognitionSource { none, ocrFuzzy, phash, vision, bggSearch, manual }

class LocalMatch {
  /// localId del juego ya en la BBDD.
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

/// Servicio de reconocimiento en cascada:
///
/// 1. OCR (ML Kit) -> matching difuso contra los juegos locales.
/// 2. pHash de la foto -> distancia Hamming contra `juegos.phash`.
/// 3. Vision API (OpenAI) -> nombre identificado -> b\u00fasqueda BGG.
class RecognitionService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _api = ApiService();
  late final _juegos = JuegoRepository(
    DatabaseService(),
    OutboxDao(DatabaseService()),
  );

  static const double _fuzzyThresholdHigh = 0.82;
  static const double _fuzzyThresholdLow = 0.65;
  static const int _phashMaxDistance = 14;

  /// Pipeline completo: OCR + local fuzzy + pHash + (opcional) Vision API.
  Future<RecognitionResult> recognizeGame(File imageFile) async {
    String extractedText = '';
    final tried = <String>[];

    try {
      final recognized = await _textRecognizer
          .processImage(InputImage.fromFile(imageFile));
      extractedText = recognized.text.trim();
      final queries = _buildQueries(recognized);
      tried.addAll(queries);

      // 1) Matching local difuso usando OCR.
      if (queries.isNotEmpty) {
        final local = await _searchLocalByText(queries);
        if (local.isNotEmpty && local.first.score >= _fuzzyThresholdHigh) {
          return RecognitionResult(
            localMatches: local,
            bggGames: const [],
            extractedText: extractedText,
            triedQueries: tried,
            source: RecognitionSource.ocrFuzzy,
          );
        }
        // Si el mejor candidato local tiene score medio, guardarlo como
        // sugerencia mientras seguimos con pHash y Vision.
        if (local.isNotEmpty) {
          final phash = await _phashMatches(imageFile);
          final combined = _combineMatches(local, phash);
          if (combined.first.score >= _fuzzyThresholdHigh ||
              phash.isNotEmpty && phash.first.score >= 0.78) {
            return RecognitionResult(
              localMatches: combined,
              bggGames: const [],
              extractedText: extractedText,
              triedQueries: tried,
              source: phash.isNotEmpty
                  ? RecognitionSource.phash
                  : RecognitionSource.ocrFuzzy,
            );
          }
        }
      }

      // 2) pHash puro (sin texto).
      final phash = await _phashMatches(imageFile);
      if (phash.isNotEmpty && phash.first.score >= 0.78) {
        return RecognitionResult(
          localMatches: phash,
          bggGames: const [],
          extractedText: extractedText,
          triedQueries: tried,
          source: RecognitionSource.phash,
        );
      }

      // 3) BGG por texto (sin local). Lo intentamos antes de Vision para
      // ahorrar llamadas pagadas si OCR estaba razonable.
      if (queries.isNotEmpty) {
        final bgg = await _runBggQueries(queries);
        if (bgg.isNotEmpty) {
          return RecognitionResult(
            localMatches: const [],
            bggGames: bgg,
            extractedText: extractedText,
            triedQueries: tried,
            source: RecognitionSource.bggSearch,
          );
        }
      }

      // 4) Vision API fallback.
      final vision = await _visionFallback(imageFile);
      if (vision != null && vision.isNotEmpty) {
        return RecognitionResult(
          localMatches: const [],
          bggGames: vision,
          extractedText: extractedText,
          triedQueries: tried,
          source: RecognitionSource.vision,
        );
      }
    } catch (e) {
      debugPrint('RECOGNITION ERROR: $e');
    }

    return RecognitionResult(
      localMatches: const [],
      bggGames: const [],
      extractedText: extractedText,
      triedQueries: tried,
      source: RecognitionSource.none,
    );
  }

  /// B\u00fasqueda manual a partir de un texto introducido por el usuario.
  /// Usa primero el matching local, luego BGG.
  Future<RecognitionResult> searchByText(String rawText) async {
    final cleaned = _cleanText(rawText);
    if (cleaned.isEmpty) {
      return RecognitionResult(
        localMatches: const [],
        bggGames: const [],
        extractedText: rawText.trim(),
        triedQueries: const [],
        source: RecognitionSource.none,
      );
    }
    final queries = [cleaned, ..._variantsOf(cleaned)];
    final local = await _searchLocalByText(queries);
    if (local.isNotEmpty && local.first.score >= _fuzzyThresholdLow) {
      return RecognitionResult(
        localMatches: local,
        bggGames: const [],
        extractedText: rawText.trim(),
        triedQueries: queries,
        source: RecognitionSource.manual,
      );
    }
    final bgg = await _runBggQueries(queries);
    return RecognitionResult(
      localMatches: local,
      bggGames: bgg,
      extractedText: rawText.trim(),
      triedQueries: queries,
      source: bgg.isNotEmpty ? RecognitionSource.bggSearch : RecognitionSource.manual,
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
      String via = 'fuzzy';
      for (final q in queries) {
        final s = FuzzyMatcher.similarity(q, nombre);
        if (s > best) {
          best = s;
          via = 'fuzzy';
        }
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
    final seen = <String>{};
    for (final q in queries) {
      final query = q.trim();
      if (query.isEmpty) continue;
      if (!seen.add(query.toLowerCase())) continue;
      try {
        final response =
            await _api.get('/bgg/search', params: {'query': query});
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        if (games.isNotEmpty) return games;
      } catch (e) {
        debugPrint('BGG search error: $e');
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>?> _visionFallback(File file) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(file.path),
        'lookup_bgg': true,
      });
      final response = await _api.upload('/vision/recognize', formData);
      final data = response.data as Map<String, dynamic>;
      final bgg = (data['bgg_games'] as List?)?.cast<Map<String, dynamic>>();
      if (bgg != null && bgg.isNotEmpty) return bgg;
      // Si no hay match en BGG, devolvemos los candidatos textuales de la IA
      final candidates =
          (data['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return candidates
          .map((c) => {
                'name': c['name'],
                'year': c['year'],
                'bgg_id': null,
                'thumbnail': null,
                'description': c['reasoning'],
              })
          .toList();
    } on DioException catch (e) {
      debugPrint('VISION ERROR: ${e.message}');
      return null;
    }
  }

  // ---------- helpers de OCR (mantienen las heur\u00edsticas previas) ----------

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
    // palabras sueltas largas (suelen ser t\u00edtulos de una palabra)
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
