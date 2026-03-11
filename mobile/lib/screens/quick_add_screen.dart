import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../models/juego.dart';

class QuickAddScreen extends StatefulWidget {
  final Map<String, dynamic>? bggGame;
  const QuickAddScreen({super.key, this.bggGame});

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final _api = ApiService();
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _jugadoresMinController = TextEditingController();
  final _jugadoresMaxController = TextEditingController();
  final _edadMinimaController = TextEditingController();

  int _currentStep = 0;
  File? _imageFile;
  List<Categoria> _categorias = [];
  List<Ubicacion> _ubicaciones = [];
  List<Propietario> _propietarios = [];
  int? _categoriaId;
  int? _ubicacionId;
  final Set<int> _propietarioIds = {};
  DateTime? _fechaCompra;
  bool _saving = false;
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.bggGame != null) {
      _nombreController.text = widget.bggGame!['name'] ?? '';
      _jugadoresMinController.text =
          '${widget.bggGame!['min_players'] ?? ''}';
      _jugadoresMaxController.text =
          '${widget.bggGame!['max_players'] ?? ''}';
    }
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _api.get('/categorias'),
        _api.get('/ubicaciones'),
        _api.get('/propietarios'),
      ]);
      setState(() {
        _categorias = (results[0].data as List)
            .map((c) => Categoria.fromJson(c))
            .toList();
        _ubicaciones = (results[1].data as List)
            .map((u) => Ubicacion.fromJson(u))
            .toList();
        _propietarios = (results[2].data as List)
            .map((p) => Propietario.fromJson(p))
            .toList();
        final principal = _propietarios.where((p) => p.esPrincipal).firstOrNull;
        if (principal != null) {
          _propietarioIds.add(principal.id);
        }
        _dataLoaded = true;
      });
    } catch (e) {
      debugPrint('QUICK_ADD LOAD ERROR: $e');
      setState(() => _dataLoaded = true);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _pickFechaCompra() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _fechaCompra ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
      locale: const Locale('es', 'ES'),
    );
    if (date != null) {
      setState(() => _fechaCompra = date);
    }
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  String _formatDateApi(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_nombreController.text.isEmpty) return;
    setState(() => _saving = true);

    try {
      final map = <String, dynamic>{
        'nombre': _nombreController.text,
        'descripcion': _descripcionController.text,
        'num_jugadores_min': _jugadoresMinController.text,
        'num_jugadores_max': _jugadoresMaxController.text,
        'edad_minima': _edadMinimaController.text,
        'categoria_id': _categoriaId,
        'estado': 'disponible',
      };

      if (_ubicacionId != null) {
        map['ubicacion_id'] = _ubicacionId;
      }
      if (_fechaCompra != null) {
        map['fecha_compra'] = _formatDateApi(_fechaCompra!);
      }
      if (_imageFile != null) {
        map['imagen'] = await MultipartFile.fromFile(_imageFile!.path);
      }

      for (int i = 0; i < _propietarioIds.length; i++) {
        map['propietario_ids[$i]'] = _propietarioIds.elementAt(i);
      }

      final formData = FormData.fromMap(map);
      await _api.upload('/juegos', formData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Juego añadido correctamente')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _jugadoresMinController.dispose();
    _jugadoresMaxController.dispose();
    _edadMinimaController.dispose();
    super.dispose();
  }

  static const _totalSteps = 4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Añadir juego')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < _totalSteps - 1) {
            setState(() => _currentStep++);
          } else {
            _save();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep--);
        },
        controlsBuilder: (context, details) {
          final isLast = _currentStep == _totalSteps - 1;
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isLast ? 'Guardar' : 'Siguiente'),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Atrás'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          _buildInfoStep(),
          _buildPropietarioStep(),
          _buildFotoStep(),
          _buildUbicacionStep(),
        ],
      ),
    );
  }

  Step _buildInfoStep() {
    return Step(
      title: const Text('Información'),
      isActive: _currentStep >= 0,
      content: Column(
        children: [
          TextField(
            controller: _nombreController,
            decoration: const InputDecoration(
              labelText: 'Nombre del juego *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descripcionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jugadoresMinController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jug. mín',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _jugadoresMaxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jug. máx',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _edadMinimaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Edad mín',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _categoriaId,
            decoration: const InputDecoration(
              labelText: 'Categoría',
              border: OutlineInputBorder(),
            ),
            items: _categorias
                .map((c) =>
                    DropdownMenuItem(value: c.id, child: Text(c.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _categoriaId = v),
          ),
        ],
      ),
    );
  }

  Step _buildPropietarioStep() {
    return Step(
      title: const Text('Propietario y fecha'),
      isActive: _currentStep >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Propietarios',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 8),
          if (!_dataLoaded)
            const Center(child: CircularProgressIndicator())
          else if (_propietarios.isEmpty)
            Text('No hay propietarios configurados',
                style: TextStyle(color: Colors.grey[500], fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _propietarios.map((p) {
                final selected = _propietarioIds.contains(p.id);
                return FilterChip(
                  label: Text(p.nombre),
                  selected: selected,
                  avatar: p.esPrincipal
                      ? const Icon(Icons.star, size: 16)
                      : null,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _propietarioIds.add(p.id);
                      } else {
                        _propietarioIds.remove(p.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
          Text('Fecha de compra',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickFechaCompra,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(
                _fechaCompra != null ? _formatDate(_fechaCompra!) : 'Seleccionar fecha',
                style: TextStyle(
                  color: _fechaCompra != null ? null : Colors.grey[500],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Step _buildFotoStep() {
    return Step(
      title: const Text('Foto'),
      isActive: _currentStep >= 2,
      content: Column(
        children: [
          if (_imageFile != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(_imageFile!,
                  height: 200, fit: BoxFit.cover),
            )
          else
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                  child: Icon(Icons.photo_camera,
                      size: 48, color: Colors.grey)),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Cámara'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 800,
                    imageQuality: 80,
                  );
                  if (picked != null) {
                    setState(() => _imageFile = File(picked.path));
                  }
                },
                icon: const Icon(Icons.photo_library),
                label: const Text('Galería'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Step _buildUbicacionStep() {
    return Step(
      title: const Text('Ubicación'),
      isActive: _currentStep >= 3,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_dataLoaded)
            const Center(child: CircularProgressIndicator())
          else if (_ubicaciones.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No hay estantes configurados. Puedes crearlos desde Ubicaciones en el menú Más.',
                      style: TextStyle(fontSize: 13, color: Colors.orange[900]),
                    ),
                  ),
                ],
              ),
            )
          else
            DropdownButtonFormField<int>(
              value: _ubicacionId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('Sin ubicación', style: TextStyle(color: Colors.grey)),
                ),
                ..._ubicaciones.map((u) => DropdownMenuItem(
                    value: u.id,
                    child: Text(u.rutaCompleta, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _ubicacionId = v),
            ),
        ],
      ),
    );
  }
}
