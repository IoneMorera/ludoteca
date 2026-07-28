import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../services/recognition_service.dart';

class RecognizeScreen extends StatefulWidget {
  const RecognizeScreen({super.key});

  @override
  State<RecognizeScreen> createState() => _RecognizeScreenState();
}

class _RecognizeScreenState extends State<RecognizeScreen> {
  final RecognitionService _service = RecognitionService();
  final TextEditingController _manualController = TextEditingController();
  File? _imageFile;
  bool _processing = false;
  RecognitionResult? _result;
  String? _error;

  @override
  void dispose() {
    _service.dispose();
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 100);
    if (picked == null) return;
    final cropped = await _cropImage(picked.path);
    if (cropped == null) return;

    setState(() {
      _imageFile = cropped;
      _processing = true;
      _result = null;
      _error = null;
      _manualController.clear();
    });

    try {
      final result = await _service.recognizeGame(cropped);
      _applyResult(result);
    } on DioException catch (e) {
      setState(() => _error = _friendlyDioError(e));
    } catch (e) {
      setState(() => _error = 'Error al procesar la imagen: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<File?> _cropImage(String path) async {
    final cropper = ImageCropper();
    final cropped = await cropper.cropImage(
      sourcePath: path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 95,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recorta la portada',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Theme.of(context).colorScheme.primary,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Recorta la portada',
          aspectRatioLockEnabled: false,
        ),
      ],
    );
    if (cropped == null) return null;
    return File(cropped.path);
  }

  Future<void> _searchManually() async {
    final text = _manualController.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final result = await _service.searchByText(text);
      _applyResult(result, manual: true);
    } catch (e) {
      setState(() => _error = 'Error al buscar: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _applyResult(RecognitionResult result, {bool manual = false}) {
    setState(() {
      _result = result;
      if (!manual && _manualController.text.isEmpty) {
        _manualController.text = result.extractedText;
      }
      if (result.localMatches.isEmpty && result.bggGames.isEmpty) {
        _error = manual
            ? 'No se ha encontrado nada con "${_manualController.text.trim()}".'
            : 'No se ha podido identificar el juego. Prueba a editar el texto detectado.';
      } else {
        _error = result.visionWarning;
      }
    });
  }

  String _friendlyDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) return 'Tu sesi\u00f3n ha caducado. Vuelve a iniciar sesi\u00f3n.';
    if (status == 503) return 'El servicio de visi\u00f3n no est\u00e1 configurado.';
    if (status == 404) return 'Endpoint no disponible. Actualiza el backend.';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Tiempo de espera agotado.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No se pudo conectar con el servidor.';
    }
    return 'Error al buscar (HTTP $status).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Reconocer juego')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Recorta solo el t\u00edtulo/portada y procura buena luz. '
            'Si el OCR falla, la IA y BGG siguen buscando.',
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _buildImagePreview(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _pickAndRecognize(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('C\u00e1mara'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _pickAndRecognize(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galer\u00eda'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_processing)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Analizando local + BGG + IA\u2026'),
                  ],
                ),
              ),
            ),
          if (_error != null && !_processing) ...[
            Card(
              color: Colors.orange[50],
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.orange[800]),
                ),
              ),
            ),
          ],
          if (result != null && !_processing) ...[
            _buildManualSearchCard(theme, result),
            const SizedBox(height: 16),
            if (result.localMatches.isNotEmpty)
              _buildLocalMatches(theme, result),
            if (result.bggGames.isNotEmpty) _buildBggGames(theme, result),
            if (result.sources.isNotEmpty &&
                !result.sources.contains(RecognitionSource.none)) ...[
              const SizedBox(height: 8),
              Text(
                'Fuentes: ${_sourcesLabel(result.sources)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_imageFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(_imageFile!, height: 220, fit: BoxFit.cover),
      );
    }
    return Container(
      height: 220,
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
    );
  }

  Widget _buildManualSearchCard(ThemeData theme, RecognitionResult result) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Texto detectado (editable)',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualController,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Escribe o corrige el t\u00edtulo',
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchManually(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _processing ? null : _searchManually,
              icon: const Icon(Icons.search),
              label: const Text('Buscar con este texto'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalMatches(ThemeData theme, RecognitionResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('En tu ludoteca',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...result.localMatches.map((m) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                  child: Icon(
                    m.matchedVia.contains('phash')
                        ? Icons.image_search
                        : Icons.text_fields,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: Text(m.nombre),
                subtitle: Text('Coincidencia ${(m.score * 100).toStringAsFixed(0)}% \u00b7 ${m.matchedVia}'),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/juego', arguments: m.juegoLocalId),
                  child: const Text('Abrir'),
                ),
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBggGames(ThemeData theme, RecognitionResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('En BGG (a\u00f1adir)',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...result.bggGames.take(10).map((game) => Card(
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
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.casino),
                        ),
                      )
                    : const Icon(Icons.casino),
                title: Text(game['name']?.toString() ?? 'Sin nombre'),
                subtitle: Text([
                  if (game['year'] != null && game['year'] != 0)
                    '${game['year']}',
                  if (game['bgg_id'] != null) 'BGG #${game['bgg_id']}',
                ].join(' \u00b7 ')),
                trailing: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamed('/juego/nuevo', arguments: game),
                  child: const Text('A\u00f1adir'),
                ),
              ),
            )),
      ],
    );
  }

  String _sourceLabel(RecognitionSource s) {
    return switch (s) {
      RecognitionSource.ocrFuzzy => 'OCR + ludoteca local',
      RecognitionSource.phash => 'similitud visual de portada',
      RecognitionSource.bggSearch => 'BGG por texto',
      RecognitionSource.vision => 'IA de visi\u00f3n + BGG',
      RecognitionSource.manual => 'b\u00fasqueda manual',
      RecognitionSource.combined => 'varias fuentes',
      RecognitionSource.none => 'sin resultado',
    };
  }

  String _sourcesLabel(Set<RecognitionSource> sources) {
    final labels = sources
        .where((s) => s != RecognitionSource.none && s != RecognitionSource.combined)
        .map(_sourceLabel)
        .toList();
    if (labels.isEmpty) return _sourceLabel(RecognitionSource.none);
    return labels.join(', ');
  }
}
