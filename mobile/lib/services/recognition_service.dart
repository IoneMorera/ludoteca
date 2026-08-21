import 'dart:io';

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
  final List<LocalMatch> localMatches;
  final List<Map<String, dynamic>> bggGames;

  /// Mejor título detectado (editable en la UI).
  final String extractedText;

  /// Alternativas de título (texto grande), para que el usuario elija.
  final List<String> titleCandidates;

  final List<String> triedQueries;
  final Set<RecognitionSource> sources;
  final String? visionWarning;

  RecognitionResult({
    required this.localMatches,
    required this.bggGames,
    required this.extractedText,
    this.titleCandidates = const [],
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

/// Reconocimiento por foto: OCR (título) + local + BGG.
/// Vision AI desactivado temporalmente por cuota OpenAI.
class RecognitionService {
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _api = ApiService();
  late final _juegos = JuegoRepository(
    DatabaseService(),
    OutboxDao(DatabaseService()),
  );

  static const double _fuzzyThresholdLow = 0.65;
  static const int _phashMaxDistance = 14;
  /// Varias consultas: título OCR y, si falla, palabras clave.
  static const int _maxBggQueries = 4;

  Future<RecognitionResult> recognizeGame(File imageFile) async {
    String extractedText = '';
    final tried = <String>[];
    final ocrTemps = <File>[];

    try {
      final ocr = await _runOcr(imageFile, ocrTemps);
      extractedText = ocr.displayText;
      final queries = ocr.queries;
      tried.addAll(queries);
      final titleCandidates = ocr.titleCandidates;

      final results = await Future.wait([
        queries.isNotEmpty
            ? _searchLocalByText(queries)
            : Future<List<LocalMatch>>.value(const []),
        _phashMatches(imageFile),
        queries.isNotEmpty
            ? _runBggQueries(queries)
            : Future<List<Map<String, dynamic>>>.value(const []),
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
        titleCandidates: titleCandidates,
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
    final merged = <Map<String, dynamic>>[];
    final seenIds = <Object>{};

    for (final q in queries) {
      final query = q.trim();
      if (query.isEmpty) continue;
      if (!seenQueries.add(query.toLowerCase())) continue;
      if (attempted >= _maxBggQueries) break;
      attempted++;
      try {
        final response = await _api.get('/bgg/search', params: {
          'query': query,
          'light': '1',
          'limit': '8',
        });
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        for (final g in games) {
          final id = g['bgg_id'];
          if (id != null) {
            if (!seenIds.add(id)) continue;
          }
          merged.add(g);
        }
        // Si el título OCR falla, seguimos con keywords/bigramas.
        if (merged.length >= 4) break;
      } catch (e) {
        debugPrint('BGG search error: $e');
      }
    }

    return merged.take(8).toList();
  }

  /// OCR centrado en el título (suele estar abajo): franja inferior + original.
  Future<_OcrBundle> _runOcr(File original, List<File> temps) async {
    final band = await _writeTitleBand(original);
    if (band != null) temps.add(band);

    final jobs = <Future<RecognizedText>>[
      _textRecognizer.processImage(InputImage.fromFile(original)),
    ];
    final bandIndexes = <int>{};

    if (band != null) {
      bandIndexes.add(jobs.length);
      jobs.add(_textRecognizer.processImage(InputImage.fromFile(band)));

      final bandBoost =
          await _writeOcrVariant(band, _OcrVariant.colorBoost);
      if (bandBoost != null) {
        temps.add(bandBoost);
        bandIndexes.add(jobs.length);
        jobs.add(
          _textRecognizer.processImage(InputImage.fromFile(bandBoost)),
        );
      }

      final bandMono =
          await _writeOcrVariant(band, _OcrVariant.monoContrast);
      if (bandMono != null) {
        temps.add(bandMono);
        bandIndexes.add(jobs.length);
        jobs.add(
          _textRecognizer.processImage(InputImage.fromFile(bandMono)),
        );
      }
    }

    final recognizedList = await Future.wait(jobs);
    final candidates = <_ScoredLine>[];

    for (var i = 0; i < recognizedList.length; i++) {
      final r = recognizedList[i];
      // Filtra por tamaño DENTRO de cada imagen (escalas distintas entre pasadas).
      final lines = _extractTitleLines(
        r,
        fromTitleBand: bandIndexes.contains(i),
      );
      candidates.addAll(_keepLargeTitleLines(lines));
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    final withMulti = _expandMultiLineTitles(candidates);
    withMulti.sort((a, b) => b.score.compareTo(a.score));

    final titleCandidates = _titleCandidateList(withMulti);
    final titleQueries = _queriesFromTitleLines(withMulti);
    // Keywords solo desde candidatos de título (no desde todo el OCR).
    final keywordQueries = _keywordQueries(titleCandidates);

    final queries = <String>[
      ...titleQueries,
      ...keywordQueries.where(
        (k) => !titleQueries.any((t) => t.toLowerCase() == k.toLowerCase()),
      ),
    ];

    final display = titleCandidates.isNotEmpty
        ? titleCandidates.first
        : _pickDisplayTitle(withMulti, titleQueries, recognizedList);

    return _OcrBundle(
      displayText: display,
      titleCandidates: titleCandidates,
      queries: queries.take(10).toList(),
    );
  }

  /// Conserva líneas cuyo tamaño de letra es comparable al título más grande.
  List<_ScoredLine> _keepLargeTitleLines(List<_ScoredLine> lines) {
    if (lines.isEmpty) return lines;
    final maxH =
        lines.map((l) => l.height).reduce((a, b) => a > b ? a : b);
    // El título suele ser el texto más alto; ignora letras pequeñas.
    final filtered =
        lines.where((l) => l.height >= maxH * 0.58).toList();
    if (filtered.isNotEmpty) return filtered;
    // Fallback: top 3 por altura.
    final byH = List<_ScoredLine>.from(lines)
      ..sort((a, b) => b.height.compareTo(a.height));
    return byH.take(3).toList();
  }

  /// Lista corta de posibles títulos para la UI (sin ruido).
  List<String> _titleCandidateList(List<_ScoredLine> lines) {
    if (lines.isEmpty) return const [];
    final ranked = List<_ScoredLine>.from(lines)
      ..sort((a, b) {
        final wa =
            a.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final wb =
            b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        // Preferir título completo (varias palabras) si el score es razonable.
        final scoreA = a.score + (wa >= 2 ? a.score * 0.15 : 0);
        final scoreB = b.score + (wb >= 2 ? b.score * 0.15 : 0);
        return scoreB.compareTo(scoreA);
      });

    final out = <String>[];
    final seen = <String>{};
    for (final line in ranked) {
      final t = line.text.trim();
      if (t.isEmpty || t.length > 60) continue;
      final key = t.toLowerCase();
      if (!seen.add(key)) continue;
      // Evita candidatos que son solo una palabra muy genérica corta.
      final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words == 1 && t.length < 4) continue;
      out.add(t);
      if (out.length >= 4) break;
    }
    return out;
  }

  /// Elige el título a mostrar: prioriza textos con varias palabras/líneas.
  String _pickDisplayTitle(
    List<_ScoredLine> lines,
    List<String> titleQueries,
    List<RecognizedText> recognizedList,
  ) {
    if (lines.isNotEmpty) {
      final ranked = List<_ScoredLine>.from(lines);
      ranked.sort((a, b) {
        final wa = a.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final wb = b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        // Multilínea / multi-palabra primero.
        if (wa != wb) return wb.compareTo(wa);
        if (a.text.length != b.text.length) {
          return b.text.length.compareTo(a.text.length);
        }
        return b.score.compareTo(a.score);
      });
      // Entre los top por score, quédate con el más completo.
      final topScore = lines.first.score;
      final amongTop = ranked
          .where((l) => l.score >= topScore * 0.35 || l.text.split(RegExp(r'\s+')).length >= 2)
          .toList();
      if (amongTop.isNotEmpty) return amongTop.first.text;
      return ranked.first.text;
    }
    if (titleQueries.isNotEmpty) return titleQueries.first;
    if (recognizedList.isNotEmpty) {
      for (final block in recognizedList.first.blocks) {
        for (final line in block.lines) {
          final t = _cleanText(line.text);
          if (_looksLikeTitle(t)) return t;
        }
      }
    }
    return '';
  }

  /// Une 2–3 líneas cercanas verticalmente para títulos multilínea.
  List<_ScoredLine> _expandMultiLineTitles(List<_ScoredLine> lines) {
    if (lines.isEmpty) return lines;

    final byPos = List<_ScoredLine>.from(lines.take(10))
      ..sort((a, b) => a.top.compareTo(b.top));
    final extras = <_ScoredLine>[];

    for (var i = 0; i < byPos.length; i++) {
      final a = byPos[i];
      if (i + 1 < byPos.length) {
        final b = byPos[i + 1];
        final gapAb = b.top - (a.top + a.height);
        final similarSize = b.height >= a.height * 0.55 &&
            b.height <= a.height * 1.85;
        if (similarSize &&
            gapAb < a.height * 2.5 &&
            gapAb > -a.height * 0.35) {
          final two = _cleanText('${a.text} ${b.text}');
          if (_looksLikeTitle(two)) {
            extras.add(_ScoredLine(
              text: two,
              area: a.area + b.area,
              // Bonus por ser título compuesto (varias líneas).
              score: (a.score + b.score) * 1.25,
              top: a.top,
              height: (b.top + b.height) - a.top,
              confidence: (a.confidence + b.confidence) / 2,
            ));
          }
          if (i + 2 < byPos.length) {
            final c = byPos[i + 2];
            final gapBc = c.top - (b.top + b.height);
            final similarSizeC = c.height >= b.height * 0.55 &&
                c.height <= b.height * 1.85;
            if (similarSizeC &&
                gapBc < b.height * 2.5 &&
                gapBc > -b.height * 0.35) {
              final three = _cleanText('$two ${c.text}');
              if (_looksLikeTitle(three)) {
                extras.add(_ScoredLine(
                  text: three,
                  area: a.area + b.area + c.area,
                  score: (a.score + b.score + c.score) * 1.35,
                  top: a.top,
                  height: (c.top + c.height) - a.top,
                  confidence: (a.confidence + b.confidence + c.confidence) / 3,
                ));
              }
            }
          }
        }
      }
    }

    final byText = <String, _ScoredLine>{};
    for (final line in [...lines, ...extras]) {
      final key = line.text.toLowerCase();
      final existing = byText[key];
      if (existing == null || line.score > existing.score) {
        byText[key] = line;
      }
    }
    return byText.values.toList();
  }

  /// Palabras/bigramas para BGG cuando el título OCR completo no funciona.
  List<String> _keywordQueries(List<String> texts) {
    final wordCounts = <String, int>{};
    final bigrams = <String>{};

    for (final text in texts) {
      final words = _cleanText(text)
          .split(RegExp(r'\s+'))
          .map(_cleanText)
          .where((w) => w.length >= 4)
          .where((w) => _letterRatio(w) >= 0.6)
          .where((w) => !_isStopWord(w))
          .toList();

      for (final w in words) {
        final key = w.toLowerCase();
        wordCounts[key] = (wordCounts[key] ?? 0) + 1;
      }
      for (var i = 0; i < words.length - 1; i++) {
        final bi = '${words[i]} ${words[i + 1]}';
        if (bi.length >= 8 && bi.length <= 40) bigrams.add(bi);
      }
    }

    final sortedWords = wordCounts.keys.toList()
      ..sort((a, b) {
        final ca = wordCounts[a]!;
        final cb = wordCounts[b]!;
        if (cb != ca) return cb.compareTo(ca);
        return b.length.compareTo(a.length);
      });

    final out = <String>[];
    out.addAll(bigrams.take(3));
    for (final w in sortedWords.take(4)) {
      out.add(w[0].toUpperCase() + w.substring(1));
    }
    return out;
  }

  bool _isStopWord(String w) {
    const stop = {
      'the',
      'and',
      'for',
      'with',
      'from',
      'this',
      'that',
      'game',
      'juego',
      'mesa',
      'edition',
      'edicion',
      'edición',
      'board',
      'cards',
      'card',
      'pack',
      'promo',
    };
    return stop.contains(w.toLowerCase());
  }

  Future<File?> _writeTitleBand(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final encoded = await compute(_encodeTitleBand, bytes);
      if (encoded == null) return null;
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/ocr_band_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(encoded, flush: true);
      return out;
    } catch (e) {
      debugPrint('OCR title band error: $e');
      return null;
    }
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

  List<_ScoredLine> _extractTitleLines(
    RecognizedText recognized, {
    bool fromTitleBand = false,
  }) {
    double imageBottom = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.boundingBox.bottom > imageBottom) {
          imageBottom = line.boundingBox.bottom;
        }
      }
    }
    if (imageBottom <= 0) imageBottom = 1;

    final raw = <_ScoredLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = _cleanText(line.text);
        if (!_looksLikeTitle(text)) continue;

        final box = line.boundingBox;
        final height = box.height.abs().clamp(1.0, 10000.0);
        final width = box.width.abs().clamp(1.0, 10000.0);
        final letterRatio = _letterRatio(text);
        final bottomRatio = (box.bottom / imageBottom).clamp(0.0, 1.0);
        // Título suele estar abajo; en franja recortada no penalizamos posición.
        final verticalWeight = fromTitleBand
            ? 1.2
            : (bottomRatio >= 0.45
                ? (0.55 + bottomRatio)
                : (0.25 + 0.4 * bottomRatio));
        final confidence = (line.confidence ?? 0.55).clamp(0.2, 1.0);
        final score = height *
            height *
            (0.45 + 0.55 * letterRatio) *
            verticalWeight *
            confidence;

        raw.add(_ScoredLine(
          text: text,
          area: width * height,
          score: score,
          top: box.top,
          height: height,
          confidence: confidence,
        ));
      }
    }

    if (raw.isEmpty) return raw;
    raw.sort((a, b) => a.top.compareTo(b.top));

    final merged = <_ScoredLine>[];
    var i = 0;
    while (i < raw.length) {
      var combined = raw[i];
      var j = i + 1;
      while (j < raw.length) {
        final next = raw[j];
        final gap = next.top - (combined.top + combined.height);
        final combinedBottom = (combined.top + combined.height) / imageBottom;
        final sameBand = fromTitleBand ||
            combinedBottom >= 0.4 ||
            next.top / imageBottom >= 0.4;
        final similarSize = next.height >= combined.height * 0.55 &&
            next.height <= combined.height * 1.85;
        if (sameBand &&
            similarSize &&
            gap >= -combined.height * 0.35 &&
            gap < combined.height * 2.5) {
          final text = _cleanText('${combined.text} ${next.text}');
          final lineCount =
              text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          combined = _ScoredLine(
            text: text,
            area: combined.area + next.area,
            // Bonus creciente por cada línea/palabra añadida.
            score: (combined.score + next.score) * (1.1 + 0.08 * lineCount),
            top: combined.top,
            height: (next.top + next.height) - combined.top,
            confidence: (combined.confidence + next.confidence) / 2,
          );
          j++;
        } else {
          break;
        }
      }
      if (_looksLikeTitle(combined.text)) merged.add(combined);
      i = j > i + 1 ? j : i + 1;
    }

    final byText = <String, _ScoredLine>{};
    for (final line in [...merged, ...raw]) {
      final key = line.text.toLowerCase();
      final existing = byText[key];
      if (existing == null || line.score > existing.score) {
        byText[key] = line;
      }
    }
    return byText.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  List<String> _queriesFromTitleLines(List<_ScoredLine> lines) {
    if (lines.isEmpty) return const [];

    final queries = <String>{};
    // Ordenar por score, pero anteponer los multilínea (más palabras).
    final top = List<_ScoredLine>.from(lines)
      ..sort((a, b) {
        final wa = a.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final wb = b.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (wa >= 2 && wb < 2) return -1;
        if (wb >= 2 && wa < 2) return 1;
        return b.score.compareTo(a.score);
      });

    for (final line in top.take(6)) {
      queries.add(line.text);
      queries.addAll(_variantsOf(line.text));
    }

    // Une también las 2–3 mejores por posición vertical.
    final byPos = List<_ScoredLine>.from(lines.take(8))
      ..sort((a, b) => a.top.compareTo(b.top));
    if (byPos.length >= 2) {
      final joined2 = _cleanText('${byPos[0].text} ${byPos[1].text}');
      if (_looksLikeTitle(joined2)) {
        queries.add(joined2);
        queries.addAll(_variantsOf(joined2));
      }
    }
    if (byPos.length >= 3) {
      final joined3 =
          _cleanText('${byPos[0].text} ${byPos[1].text} ${byPos[2].text}');
      if (_looksLikeTitle(joined3) && joined3.length <= 80) {
        queries.add(joined3);
        queries.addAll(_variantsOf(joined3));
      }
    }

    final list = queries
        .where((q) => q.isNotEmpty && _looksLikeTitle(q))
        .map((q) => q.length > 80 ? q.substring(0, 80) : q)
        .toList();

    double scoreOf(String q) {
      final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      final match = lines.where((l) => l.text.toLowerCase() == q.toLowerCase());
      final ocr = match.isEmpty ? 0.0 : match.first.score;
      // Prioriza títulos con varias palabras (multilínea unida).
      return ocr + q.length.clamp(1, 40) * _letterRatio(q) + words * 12.0;
    }

    list.sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
    return list.take(10).toList();
  }

  bool _looksLikeTitle(String text) {
    final t = text.trim();
    if (t.length < 2) return false;
    final lower = t.toLowerCase();

    if (RegExp(r'^\d+\s*[-–—]\s*\d+(\s*(players?|jugadores?))?$')
        .hasMatch(lower)) {
      return false;
    }
    if (RegExp(r'^(ages?|a[nñ]os?)\s*:?\s*\d+').hasMatch(lower)) {
      return false;
    }
    if (RegExp(r'^\d+\+?\s*(years?|años?|anos?)?$').hasMatch(lower)) {
      return false;
    }
    if (RegExp(r'^\d+\s*(min|mins|minutes|minutos)\.?$').hasMatch(lower)) {
      return false;
    }
    const exactNoise = {
      'players',
      'jugadores',
      'copyright',
      'all rights reserved',
      'board game',
      'juego de mesa',
      'expansion',
      'expansión',
      'incluye',
    };
    if (exactNoise.contains(lower)) return false;
    if (lower.startsWith('www.') || lower.startsWith('http')) return false;
    if (RegExp(r'^[\d\W_]+$').hasMatch(t)) return false;
    if (_letterRatio(t) < 0.3) return false;
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

    final collapsedSpaces = base.replaceAllMapped(
      RegExp(
        r'(?:(?<=^)|(?<=\s))(\p{L})(?:\s+(\p{L})){1,}(?=\s|$)',
        unicode: true,
      ),
      (m) => m[0]!.replaceAll(RegExp(r'\s+'), ''),
    );
    if (collapsedSpaces != base) yield _cleanText(collapsedSpaces);

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

  void dispose() {
    _textRecognizer.close();
  }
}

class _OcrBundle {
  final String displayText;
  final List<String> titleCandidates;
  final List<String> queries;
  const _OcrBundle({
    required this.displayText,
    this.titleCandidates = const [],
    required this.queries,
  });
}

enum _OcrVariant { colorBoost, monoContrast }

class _ScoredLine {
  final String text;
  final double area;
  final double score;
  final double top;
  final double height;
  final double confidence;

  _ScoredLine({
    required this.text,
    required this.area,
    this.score = 0,
    this.top = 0,
    this.height = 0,
    this.confidence = 0.5,
  });
}

Uint8List? _encodeTitleBand(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Franja inferior (~58%): en muchas cajas el título va abajo.
  final bandHeight =
      (decoded.height * 0.58).round().clamp(1, decoded.height);
  final y = (decoded.height - bandHeight).clamp(0, decoded.height - 1);
  var image = img.copyCrop(
    decoded,
    x: 0,
    y: y,
    width: decoded.width,
    height: bandHeight,
  );

  const minSide = 1600;
  if (image.width < minSide || image.height < minSide * 0.35) {
    final scale = minSide / image.width;
    image = img.copyResize(
      image,
      width: minSide,
      height: (image.height * scale).round().clamp(1, 4000),
      interpolation: img.Interpolation.cubic,
    );
  }

  image = img.adjustColor(image, contrast: 1.25, brightness: 1.04);
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

Uint8List? _encodeOcrVariant(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final variant = _OcrVariant.values[args['variant'] as int];
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var image = decoded;

  const minSide = 1600;
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
      image = img.adjustColor(image, contrast: 1.4, saturation: 1.15);
      break;
    case _OcrVariant.monoContrast:
      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.7, brightness: 1.1);
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
