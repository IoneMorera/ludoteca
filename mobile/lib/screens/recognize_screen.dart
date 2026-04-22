import 'dart:io';
import 'package:dio/dio.dart';
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
  String? _extractedText;
  List<String> _triedQueries = [];

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
      _extractedText = null;
      _triedQueries = [];
    });

    try {
      final result = await _recognitionService.recognizeGame(_imageFile!);
      setState(() {
        _results = result.games;
        _extractedText = result.extractedText;
        _triedQueries = result.triedQueries;
        if (result.extractedText.isEmpty) {
          _error =
              'No se detectó texto en la imagen. Intenta con una foto más cercana al título.';
        } else if (result.games.isEmpty) {
          _error = 'No se encontraron juegos en BGG con el texto detectado.';
        }
      });
    } on DioException catch (e) {
      setState(() {
        _error = _friendlyDioError(e);
      });
    } catch (e) {
      setState(() => _error = 'Error al procesar la imagen: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  String _friendlyDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return 'Tu sesión ha caducado. Vuelve a iniciar sesión.';
    }
    if (status == 404) {
      return 'El servidor no tiene el endpoint /bgg/search. Actualiza el backend.';
    }
    if (status == 502 || status == 503) {
      return 'BGG no está disponible ahora mismo. Inténtalo de nuevo más tarde.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Tiempo de espera agotado al contactar con el servidor.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No se pudo conectar con el servidor. Comprueba la URL configurada y tu conexión.';
    }
    return 'Error al buscar en BGG${status != null ? ' (HTTP $status)' : ''}.';
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
          if (_extractedText != null && _extractedText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Texto detectado',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: Colors.grey[700])),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_extractedText!,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[800])),
                  ),
                  if (_triedQueries.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          'Consultas probadas: ${_triedQueries.join(" · ")}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                ],
              ),
            ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Posibles coincidencias:',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...(_results.take(10).map((game) => Card(
                  child: ListTile(
                    leading: (game['thumbnail'] != null &&
                            (game['thumbnail'] as String).isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              game['thumbnail'],
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.casino),
                            ),
                          )
                        : const Icon(Icons.casino),
                    title: Text(game['name'] ?? 'Sin nombre'),
                    subtitle: Text([
                      if (game['year'] != null && game['year'] != 0)
                        '${game['year']}',
                      'BGG #${game['bgg_id'] ?? '-'}',
                    ].join(' · ')),
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
