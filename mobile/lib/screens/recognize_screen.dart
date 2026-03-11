import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/recognition_service.dart';

class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  final RecognitionService _recognitionService = RecognitionService();
  File? _imageFile;
  bool _processing = false;
  List<Map<String, dynamic>> _results = [];
  String? _error;

  @override
  void dispose() {
    _recognitionService.dispose();
    super.dispose();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1200);
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _processing = true;
      _results = [];
      _error = null;
    });

    try {
      final results = await _recognitionService.recognizeGame(_imageFile!);
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _error = 'No se pudo identificar el juego. Intenta con otra foto.';
        }
      });
    } catch (e) {
      setState(() => _error = 'Error al procesar la imagen');
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reconocer juego')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Toma una foto de la caja o componentes del juego',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          if (_imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_imageFile!, height: 250, fit: BoxFit.cover),
            )
          else
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_camera, size: 56, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Sin imagen', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cámara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galería'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_processing)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Analizando imagen...',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          if (_error != null)
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style: TextStyle(color: Colors.orange[800])),
              ),
            ),
          if (_results.isNotEmpty) ...[
            Text('Posibles coincidencias:',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...(_results.take(5).map((game) => Card(
                  child: ListTile(
                    title: Text(game['name'] ?? 'Sin nombre'),
                    subtitle: Text('BGG ID: ${game['bgg_id'] ?? '-'}'),
                    trailing: FilledButton(
                      onPressed: () {
                        Navigator.of(context)
                            .pushNamed('/quick-add', arguments: game);
                      },
                      child: const Text('Añadir'),
                    ),
                  ),
                ))),
          ],
        ],
      ),
    );
  }
}
