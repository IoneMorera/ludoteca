import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../data/juego_repository.dart';
import '../data/outbox_dao.dart';
import '../services/database_service.dart';
import 'api_service.dart';
import 'fuzzy_matcher.dart';
import 'phash_service.dart';

class RecognitionResult {
  /// Coincidencias locales (juegos ya en la BBDD).
  final List<LocalMatch> localMatches;

  /// Candidatos de BGG por texto OCR.
  final List<Map<String, dynamic>> bggGames;

  /// Texto bruto detectado por OCR (informativo / editable).
  final String extractedText;
  final List<String> triedQueries;

  /// Fuentes que aportaron resultados (puede haber varias a la vez).
  final Set<RecognitionSource> sources;

  /// Aviso opcional (p. ej. Vision desactivada / error parcial).
  final String? visionWarning;

  RecognitionResult({
    required this.localMatches,
    required this.bggGames,
    required this.extractedText,
    required this.triedQueries,
    required this.sources,
    this.visionWarning,
  });

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

/// Reconocimiento por foto: OCR + local + BGG.
///
/// Vision AI desactivado temporalmente por cuota OpenAI.
/// Para reactivar: restaurar la llamada a `/vision/recognize` en paralelo.
class RecognitionService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _api = ApiService();
  late final _juegos = JuegoRepository(
    DatabaseService(),
    OutboxDao(DatabaseService()),
  );

  static const double _fuzzyThresholdLow = 0.65;
  static const int _phashMaxDistance = 14;
  /// Una sola consulta BGG (la más prometedora del OCR).
  static const int _maxBggQueries = 1;
  /// Umbral bajo → se intenta una 2ª pasada OCR preprocesada.
  static const int _ocrRetryThreshold = 40;

  Future<RecognitionResult> recognizeGame(File imageFile) async {
    String extractedText = '';
    final tried = <String>[];
    final ocrTemps = <File>[];

    try {
      final ocr = await _runOcr(imageFile, ocrTemps);
      extractedText = ocr.displayText;
      final queries = ocr.queries;
      tried.addAll(queries);

      final results = await Future.wait([
        queries.isNotEmpty
            ? _searchLocalByText(queries)
            : Future<List<LocalMatch>>.value(const []),
        _phashMatches(imageFile),
        queries.isNotEmpty
            ? _runBggQueries(queries)
            : Future<List<Map<String, dynamic>>>.value(const []),
        // Vision AI desactivado por cuota:
        // _enableVisionAi
        //     ? _visionFallback(imageFile, ocrHint: extractedText)
        //     : Future.value(const _VisionResult(games: [])),
      ]);

      final fuzzy = results[0] as List<LocalMatch>;
      final phash = results[1] as List<LocalMatch>;
      final bggText = results[2] as List<Map<String, dynamic>>;

      final localMatches = _combineMatches(fuzzy, phash);
      final sources = <RecognitionSource>{};
      if (fuzzy.isNotEmpty) sources.add(RecognitionSource.ocrFuzzy);
      if (phash.isNotEmpty) sources.add(RecognitionSource.phash);
      if (bggText.isNotEmpty) sources.add(RecognitionSource.bggSearch);
      if (sources.isEmpty) sources.add(RecognitionSource.none);

      return RecognitionResult(
        localMatches: localMatches,
        bggGames: bggText,
        extractedText: extractedText,
        triedQueries: tried,
        sources: sources,
      );
    } catch (e) {
      debugPrint('RECOGNITION ERROR: $e');
    } finally {
      for (final f in ocrTemps) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    return RecognitionResult(
      localMatches: const [],
      bggGames: const [],
      extractedText: extractedText,
      triedQueries: tried,
      sources: const {RecognitionSource.none},
    );
  }

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
          matchedVia: 'fuzzy',
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
    var attempted = 0;

    for (final q in queries) {
      final query = q.trim();
      if (query.isEmpty) continue;
      if (!seenQueries.add(query.toLowerCase())) continue;
      if (attempted >= _maxBggQueries) break;
      attempted++;
      try {
        final response = await _api.get('/bgg/search', params: {
          'query': query,
          // Modo ligero: menos detalles de /thing → más rápido.
          'light': '1',
          'limit': '8',
        });
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        if (games.isNotEmpty) return games.take(8).toList();
      } catch (e) {
        debugPrint('BGG search error: $e');
      }
    }

    return const [];
  }

  // ---------------------------------------------------------------------------
  // Vision AI — DESACTIVADO por cuota. Código conservado para reactivar.
  // ---------------------------------------------------------------------------
  //
  // Future<_VisionResult> _visionFallback(File file, {String? ocrHint}) async {
  //   ... llamada a POST /vision/recognize ...
  // }

  /// OCR adaptativo: 1 pasada; si el resultado es pobre, reintenta con contraste.
  Future<_OcrBundle> _runOcr(File original, List<File> temps) async {
    final first = await _textRecognizer
        .processImage(InputImage.fromFile(original));
    final recognizedList = <RecognizedText>[first];

    if (_ocrQuality(first) < _ocrRetryThreshold) {
      final boosted = await _writeOcrVariant(original, _OcrVariant.colorBoost);
      if (boosted != null) {
        temps.add(boosted);
        recognizedList.add(
          await _textRecognizer.processImage(InputImage.fromFile(boosted)),
        );
      }
      // Solo si sigue pobre: B&N con contraste alto.
      if (recognizedList.every((r) => _ocrQuality(r) < _ocrRetryThreshold)) {
        final mono =
            await _writeOcrVariant(original, _OcrVariant.monoContrast);
        if (mono != null) {
          temps.add(mono);
          recognizedList.add(
            await _textRecognizer.processImage(InputImage.fromFile(mono)),
          );
        }
      }
    }

    RecognizedText best = recognizedList.first;
    var bestScore = _ocrQuality(best);
    for (final r in recognizedList.skip(1)) {
      final s = _ocrQuality(r);
      if (s > bestScore) {
        best = r;
        bestScore = s;
      }
    }

    final querySet = <String>{};
    for (final r in recognizedList) {
      querySet.addAll(_buildQueries(r));
    }
    final queries = querySet.toList()
      ..sort((a, b) => _queryPriority(b).compareTo(_queryPriority(a)));

    // Para BGG solo necesitamos pocas; local puede usar más.
    final capped = queries.take(6).toList();

    final display = _bestDisplayText(best, capped);

    return _OcrBundle(displayText: display, queries: capped);
  }

  String _bestDisplayText(RecognizedText best, List<String> queries) {
    final fromBest = _buildQueries(best);
    if (fromBest.isNotEmpty) return fromBest.first;
    if (queries.isNotEmpty) return queries.first;
    return best.text.trim();
  }

  Future<File?> _writeOcrVariant(File file, _OcrVariant variant) async {
    try {
      final bytes = await file.readAsBytes();
      final encoded = await compute(_encodeOcrVariant, {
        'bytes': bytes,
        'variant': variant.index,
      });
      if (encoded == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/ocr_${variant.name}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(encoded, flush: true);
      return out;
    } catch (e) {
      debugPrint('OCR variant error ($variant): $e');
      return null;
    }
  }

  List<String> _buildQueries(RecognizedText recognized) {
    double maxBottom = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final bottom = line.boundingBox.bottom;
        if (bottom > maxBottom) maxBottom = bottom;
      }
    }
    if (maxBottom <= 0) maxBottom = 1;

    final lines = <_ScoredLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = _cleanText(line.text);
        if (!_looksLikeTitle(text)) continue;
        final box = line.boundingBox;
        final area = box.width * box.height;
        final letterRatio = _letterRatio(text);
        final topBias = 1.0 - (box.top / maxBottom);
        final score =
            area * (0.45 + 0.55 * letterRatio) * (0.55 + 0.45 * topBias);
        lines.add(_ScoredLine(text: text, area: area, score: score));
      }
    }
    lines.sort((a, b) => b.score.compareTo(a.score));

    final queries = <String>{};
    if (lines.isNotEmpty) {
      queries.add(lines.first.text);
      queries.addAll(_variantsOf(lines.first.text));
    }
    if (lines.length >= 2) {
      final joined = _cleanText('${lines[0].text} ${lines[1].text}');
      if (_looksLikeTitle(joined)) {
        queries.add(joined);
        queries.addAll(_variantsOf(joined));
      }
    }
    for (final line in lines.take(3).skip(1)) {
      queries.add(line.text);
      queries.addAll(_variantsOf(line.text));
    }
    final words = <String>{};
    for (final line in lines.take(3)) {
      for (final w in line.text.split(RegExp(r'\s+'))) {
        final wc = _cleanText(w);
        if (wc.length >= 4 && _letterRatio(wc) >= 0.6) words.add(wc);
      }
    }
    final wordList = words.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    queries.addAll(wordList.take(3));

    final list = queries
        .where((q) => q.isNotEmpty)
        .map((q) => q.length > 80 ? q.substring(0, 80) : q)
        .toList();
    list.sort((a, b) => _queryPriority(b).compareTo(_queryPriority(a)));
    return list;
  }

  double _queryPriority(String q) {
    final len = q.length.clamp(1, 40);
    return len * _letterRatio(q);
  }

  bool _looksLikeTitle(String text) {
    if (text.length < 3) return false;
    final lower = text.toLowerCase();
    const noise = [
      'ages',
      'años',
      'anos',
      'players',
      'jugadores',
      'minutos',
      'minutes',
      'mins',
      'copyright',
      'all rights',
      'www.',
      'http',
      'board game',
      'juego de mesa',
      'incluye',
      'expansion',
      'expansión',
    ];
    for (final n in noise) {
      if (lower.contains(n)) return false;
    }
    if (RegExp(r'^[\d\W_]+$').hasMatch(text)) return false;
    if (_letterRatio(text) < 0.35) return false;
    return true;
  }

  double _letterRatio(String text) {
    if (text.isEmpty) return 0;
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(text).length;
    return letters / text.length;
  }

  Iterable<String> _variantsOf(String text) sync* {
    final base = _cleanText(text);
    if (base.isEmpty) return;

    final trimmed = base.replaceAll(
      RegExp(r'[^\p{L}\p{N}]+$', unicode: true),
      '',
    );
    if (trimmed != base && trimmed.isNotEmpty) yield trimmed;

    final spacedLetters = RegExp(
      r'^(?:\p{L}\s+){2,}\p{L}$',
      unicode: true,
    );
    if (spacedLetters.hasMatch(base)) {
      yield base.replaceAll(RegExp(r'\s+'), '');
    }

    var sub = base
        .replaceAll('|', 'I')
        .replaceAll('!', 'I')
        .replaceAll('\u00a1', 'I')
        .replaceAll('€', 'E')
        .replaceAll('§', 'S');
    sub = sub.replaceAllMapped(
      RegExp(r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])0([A-Za-zÁÉÍÓÚáéíóúÑñÜü])'),
      (m) => '${m[1]}O${m[2]}',
    );
    sub = sub.replaceAllMapped(
      RegExp(r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])1([A-Za-zÁÉÍÓÚáéíóúÑñÜü])'),
      (m) => '${m[1]}I${m[2]}',
    );
    sub = sub.replaceAllMapped(
      RegExp(r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])5([A-Za-zÁÉÍÓÚáéíóúÑñÜü])'),
      (m) => '${m[1]}S${m[2]}',
    );
    final rnFixed = sub.replaceAll(RegExp(r'rn', caseSensitive: false), 'm');
    final vvFixed = sub.replaceAll(RegExp(r'vv', caseSensitive: false), 'w');
    if (rnFixed != sub) yield rnFixed;
    if (vvFixed != sub) yield vvFixed;
    if (sub != base) yield sub;

    final noPunct =
        base.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ');
    final collapsed = _cleanText(noPunct);
    if (collapsed.isNotEmpty && collapsed != base) yield collapsed;

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

  int _ocrQuality(RecognizedText text) {
    var letters = 0;
    var titleLines = 0;
    for (final block in text.blocks) {
      for (final line in block.lines) {
        final t = _cleanText(line.text);
        letters += RegExp(r'\p{L}', unicode: true).allMatches(t).length;
        if (_looksLikeTitle(t)) titleLines++;
      }
    }
    return letters + titleLines * 20;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _OcrBundle {
  final String displayText;
  final List<String> queries;
  const _OcrBundle({required this.displayText, required this.queries});
}

enum _OcrVariant { colorBoost, monoContrast }

class _ScoredLine {
  final String text;
  final double area;
  final double score;
  _ScoredLine({required this.text, required this.area, this.score = 0});
}

Uint8List? _encodeOcrVariant(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final variant = _OcrVariant.values[args['variant'] as int];
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var image = decoded;

  const minSide = 1400;
  if (image.width < minSide && image.height < minSide) {
    final scale =
        minSide / (image.width < image.height ? image.width : image.height);
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  switch (variant) {
    case _OcrVariant.colorBoost:
      image = img.adjustColor(image, contrast: 1.25, saturation: 1.1);
      break;
    case _OcrVariant.monoContrast:
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.55, brightness: 1.08);
      image = img.convolution(
        image,
        filter: [
          0, -1, 0,
          -1, 5, -1,
          0, -1, 0,
        ],
      );
      break;
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}
