import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'api_service.dart';

class RecognitionResult {
  final List<Map<String, dynamic>> games;
  final String extractedText;
  final List<String> triedQueries;

  RecognitionResult({
    required this.games,
    required this.extractedText,
    required this.triedQueries,
  });
}

class RecognitionService {
  final _textRecognizer = TextRecognizer();
  final _api = ApiService();

  /// Reconoce un juego a partir de una foto.
  ///
  /// Extrae texto con ML Kit, construye varias consultas priorizando los
  /// bloques más grandes (normalmente el título del juego en la caja) y
  /// consulta el endpoint `/bgg/search` hasta obtener resultados.
  Future<RecognitionResult> recognizeGame(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    final extractedText = recognized.text.trim();
    final queries = _buildQueries(recognized);

    if (queries.isEmpty) {
      return RecognitionResult(
        games: [],
        extractedText: extractedText,
        triedQueries: const [],
      );
    }

    final tried = <String>[];
    for (final query in queries) {
      tried.add(query);
      try {
        final response =
            await _api.get('/bgg/search', params: {'query': query});
        final games = (response.data['games'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        if (games.isNotEmpty) {
          return RecognitionResult(
            games: games,
            extractedText: extractedText,
            triedQueries: tried,
          );
        }
      } catch (e) {
        debugPrint('RECOGNITION SEARCH ERROR ("$query"): $e');
        rethrow;
      }
    }

    return RecognitionResult(
      games: [],
      extractedText: extractedText,
      triedQueries: tried,
    );
  }

  /// Construye una lista priorizada de consultas a partir del OCR.
  ///
  /// 1. La línea con mayor altura visual (suele ser el título).
  /// 2. Las 3 líneas más grandes concatenadas.
  /// 3. El primer bloque completo (máx. 60 chars).
  List<String> _buildQueries(RecognizedText recognized) {
    final lines = <_ScoredLine>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = _cleanText(line.text);
        if (text.length < 3) continue;
        final height = line.boundingBox.height;
        lines.add(_ScoredLine(text: text, height: height));
      }
    }

    lines.sort((a, b) => b.height.compareTo(a.height));

    final queries = <String>{};

    if (lines.isNotEmpty) {
      queries.add(lines.first.text);
    }

    if (lines.length >= 2) {
      final top = lines.take(3).map((l) => l.text).join(' ');
      queries.add(_cleanText(top));
    }

    if (recognized.blocks.isNotEmpty) {
      final firstBlock = _cleanText(recognized.blocks.first.text);
      if (firstBlock.length > 60) {
        queries.add(firstBlock.substring(0, 60));
      } else if (firstBlock.isNotEmpty) {
        queries.add(firstBlock);
      }
    }

    return queries
        .where((q) => q.isNotEmpty)
        .map((q) => q.length > 80 ? q.substring(0, 80) : q)
        .toList();
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
  final double height;
  _ScoredLine({required this.text, required this.height});
}
