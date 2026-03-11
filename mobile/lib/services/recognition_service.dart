import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'api_service.dart';

class RecognitionService {
  final _textRecognizer = TextRecognizer();
  final _api = ApiService();

  Future<List<Map<String, dynamic>>> recognizeGame(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognized = await _textRecognizer.processImage(inputImage);

    final allText = recognized.blocks.map((b) => b.text).join(' ');

    if (allText.trim().isEmpty) return [];

    // Search BGG with the extracted text
    try {
      final response =
          await _api.get('/bgg/search', params: {'query': allText.trim()});
      return (response.data['games'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          [];
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
