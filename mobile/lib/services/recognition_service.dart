import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
  final List<String> candidateNames;
  final String? warning;

  const _VisionResult({
    required this.games,
    this.candidateNames = const [],
    this.warning,
  });
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
  /// Máximo de consultas BGG por texto OCR (cada una es lenta).
  static const int _maxBggQueries = 2;
  static const Duration _visionTimeout = Duration(seconds: 120);

  /// Pipeline completo: OCR + local + pHash + BGG + Vision en paralelo.
  Future<RecognitionResult> recognizeGame(File imageFile) async {
    String extractedText = '';
    final tried = <String>[];
    File? ocrPreprocessed;

    try {
      ocrPreprocessed = await _preprocessForOcr(imageFile);
      final recognized = await _bestOcrResult(imageFile, ocrPreprocessed);
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

      var fuzzy = results[0] as List<LocalMatch>;
      final phash = results[1] as List<LocalMatch>;
      final bggText = results[2] as List<Map<String, dynamic>>;
      final vision = results[3] as _VisionResult;

      // Si OCR fue pobre pero Vision identificó el juego, rematch local por nombre.
      if (vision.candidateNames.isNotEmpty) {
        final fromVision = await _searchLocalByText(vision.candidateNames);
        fuzzy = _combineMatches(fuzzy, fromVision);
      }

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
    } finally {
      if (ocrPreprocessed != null) {
        try {
          await ocrPreprocessed.delete();
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
    var attempted = 0;

    for (final q in queries) {
      final query = q.trim();
      if (query.isEmpty) continue;
      if (!seenQueries.add(query.toLowerCase())) continue;
      if (attempted >= _maxBggQueries) break;
      attempted++;
      try {
        final response =
            await _api.get('/bgg/search', params: {'query': query});
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        // Primera consulta con resultados basta: BGG ya trae varios candidatos.
        if (games.isNotEmpty) return _mergeBggGames([games]);
      } catch (e) {
        debugPrint('BGG search error: $e');
      }
    }

    return const [];
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
    File? compressed;
    try {
      compressed = await _compressForVision(file);
      final uploadFile = compressed ?? file;
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          uploadFile.path,
          filename: 'cover.jpg',
        ),
        'lookup_bgg': true,
      });
      final response = await _api.dio.post(
        '/vision/recognize',
        data: formData,
        options: Options(
          sendTimeout: _visionTimeout,
          receiveTimeout: _visionTimeout,
        ),
      );
      final data = response.data as Map<String, dynamic>;
      final candidates =
          (data['candidates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final candidateNames = candidates
          .map((c) => (c['name']?.toString() ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();
      final bgg = (data['bgg_games'] as List?)?.cast<Map<String, dynamic>>();
      if (bgg != null && bgg.isNotEmpty) {
        return _VisionResult(games: bgg, candidateNames: candidateNames);
      }
      final games = candidates
          .map((c) => {
                'name': c['name'],
                'year': c['year'],
                'bgg_id': null,
                'thumbnail': null,
                'description': c['reasoning'],
              })
          .toList();
      return _VisionResult(games: games, candidateNames: candidateNames);
    } on DioException catch (e) {
      debugPrint('VISION ERROR: ${e.message}');
      return _VisionResult(games: const [], warning: _visionErrorMessage(e));
    } finally {
      if (compressed != null && compressed.path != file.path) {
        try {
          await compressed.delete();
        } catch (_) {}
      }
    }
  }

  String _visionErrorMessage(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    String? serverMsg;
    if (body is Map && body['message'] is String) {
      serverMsg = body['message'] as String;
    }

    if (status == 503) {
      return serverMsg ??
          'La IA de visión no está configurada en el servidor.';
    }
    if (status == 502) {
      return serverMsg ?? 'No se pudo contactar con la IA de visión.';
    }
    if (status == 401) {
      return 'Sesión caducada; no se pudo usar la IA de visión.';
    }
    if (status == 413) {
      return 'La imagen es demasiado grande para la IA de visión.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return 'Tiempo de espera agotado al consultar la IA de visión.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Sin conexión; no se pudo usar la IA de visión.';
    }
    return serverMsg ?? 'Error al consultar la IA de visión.';
  }

  /// Reduce la portada a JPEG ~1280px para subir más rápido a Vision.
  Future<File?> _compressForVision(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final compressed = await compute(_encodeVisionJpeg, bytes);
      if (compressed == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/vision_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(compressed, flush: true);
      return out;
    } catch (e) {
      debugPrint('VISION compress error: $e');
      return null;
    }
  }

  List<String> _buildQueries(RecognizedText recognized) {
    // Estimamos altura de la imagen a partir de los boxes para priorizar
    // el tercio superior (donde suele estar el título).
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
        final topBias = 1.0 - (box.top / maxBottom); // 1 = arriba
        final score = area * (0.45 + 0.55 * letterRatio) * (0.55 + 0.45 * topBias);
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
    // Tres mejores líneas sueltas (títulos multilínea).
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

    // Orden: queries más "título" primero (longitud razonable + letras).
    final list = queries
        .where((q) => q.isNotEmpty)
        .map((q) => q.length > 80 ? q.substring(0, 80) : q)
        .toList();
    list.sort((a, b) {
      final sa = _queryPriority(a);
      final sb = _queryPriority(b);
      return sb.compareTo(sa);
    });
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
    // Solo dígitos / puntuación → ruido (edades, contadores).
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

    // Letras sueltas separadas: "W I N G S P A N" → "WINGSPAN"
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
      RegExp(
        r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])0([A-Za-zÁÉÍÓÚáéíóúÑñÜü])',
      ),
      (m) => '${m[1]}O${m[2]}',
    );
    sub = sub.replaceAllMapped(
      RegExp(
        r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])1([A-Za-zÁÉÍÓÚáéíóúÑñÜü])',
      ),
      (m) => '${m[1]}I${m[2]}',
    );
    sub = sub.replaceAllMapped(
      RegExp(
        r'([A-Za-zÁÉÍÓÚáéíóúÑñÜü])5([A-Za-zÁÉÍÓÚáéíóúÑñÜü])',
      ),
      (m) => '${m[1]}S${m[2]}',
    );
    // Errores típicos de tipografía estilizada.
    final rnFixed = sub.replaceAll(RegExp(r'rn', caseSensitive: false), 'm');
    final vvFixed = sub.replaceAll(RegExp(r'vv', caseSensitive: false), 'w');
    if (rnFixed != sub) yield rnFixed;
    if (vvFixed != sub) yield vvFixed;
    if (sub != base) yield sub;

    final noPunct = base.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ');
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

  /// Elige el mejor OCR entre original y versión preprocesada.
  Future<RecognizedText> _bestOcrResult(File original, File? preprocessed) async {
    final futures = <Future<RecognizedText>>[
      _textRecognizer.processImage(InputImage.fromFile(original)),
    ];
    if (preprocessed != null) {
      futures.add(
        _textRecognizer.processImage(InputImage.fromFile(preprocessed)),
      );
    }
    final results = await Future.wait(futures);
    if (results.length == 1) return results.first;
    return _ocrQuality(results[0]) >= _ocrQuality(results[1])
        ? results[0]
        : results[1];
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

  /// Contraste + escala para tipografías de portada difíciles.
  Future<File?> _preprocessForOcr(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final processed = await compute(_encodeOcrJpeg, bytes);
      if (processed == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(processed, flush: true);
      return out;
    } catch (e) {
      debugPrint('OCR preprocess error: $e');
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _ScoredLine {
  final String text;
  final double area;
  final double score;
  _ScoredLine({required this.text, required this.area, this.score = 0});
}

Uint8List? _encodeVisionJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = decoded;
  const maxSide = 1280;
  if (image.width > maxSide || image.height > maxSide) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxSide);
    } else {
      image = img.copyResize(image, height: maxSide);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 70));
}

Uint8List? _encodeOcrJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var image = decoded;

  // Upscale si la portada recortada es pequeña (OCR mejora mucho).
  const minSide = 1200;
  if (image.width < minSide && image.height < minSide) {
    final scale = minSide / (image.width < image.height ? image.width : image.height);
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  // Escala de grises + contraste alto: tipografías decorativas leen mejor.
  image = img.grayscale(image);
  image = img.adjustColor(image, contrast: 1.45, brightness: 1.05);

  // Ligera nitidez.
  image = img.convolution(
    image,
    filter: [
      0, -1, 0,
      -1, 5, -1,
      0, -1, 0,
    ],
  );

  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}
