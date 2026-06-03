import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/categoria_repository.dart';
import '../data/juego_repository.dart';
import '../data/propietario_repository.dart';
import '../data/sync_service.dart';
import '../data/tipo_funda_repository.dart';
import '../data/ubicacion_repository.dart';
import '../models/juego.dart';
import '../providers/juegos_provider.dart';
import '../services/api_service.dart';
import 'bgg_search_picker.dart';

/// Pantalla \u00fanica para crear y editar juegos.
///
/// - Modo creaci\u00f3n: `juego` y `juegoLocalId` son null.
/// - Modo edici\u00f3n: cargar mediante `juegoLocalId`.
/// - `bggPrefill`: datos iniciales provenientes de una b\u00fasqueda BGG.
class JuegoFormScreen extends StatefulWidget {
  final int? juegoLocalId;
  final Map<String, dynamic>? bggPrefill;

  const JuegoFormScreen({super.key, this.juegoLocalId, this.bggPrefill});

  @override
  State<JuegoFormScreen> createState() => _JuegoFormScreenState();
}

class _JuegoFormScreenState extends State<JuegoFormScreen> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _jugMin = TextEditingController();
  final _jugMax = TextEditingController();
  final _edadMin = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  Juego? _existing;
  List<CategoriaRow> _categorias = [];
  List<PropietarioRow> _propietarios = [];
  List<UbicacionRow> _ubicaciones = [];
  List<TipoFundaRow> _tiposFunda = [];

  final Set<int> _categoriaLocalIds = {};
  int? _ubicacionLocalId;
  bool _ubicacionEnCajaBase = false;
  final Set<int> _propietariosLocalIds = {};
  final Map<int, int?> _propietarioUbicaciones = {};
  int? _juegoBaseLocalId;
  String? _fechaCompra;
  String? _estado;
  String? _imagenPath;
  File? _newImageFile;
  int? _bggId;
  bool _noEnfundar = false;
  bool _esExpansion = false;
  List<String> _idiomas = [];
  final _idiomaOtroCtrl = TextEditingController();
  bool _independienteIdioma = false;
  bool _tradumaquetado = false;
  bool _tradumaquetadoParcial = false;
  final _tradumaquetadoNotasCtrl = TextEditingController();
  bool _variasCopias = false;
  List<_FundaDraft> _fundas = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _jugMin.dispose();
    _jugMax.dispose();
    _edadMin.dispose();
    _idiomaOtroCtrl.dispose();
    _tradumaquetadoNotasCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final provider = context.read<JuegosProvider>();
    _categorias = await provider.categoriaRepository.getAll();
    _propietarios = await provider.propietarioRepository.getAll();
    _ubicaciones = await provider.ubicacionRepository.getAll();
    _tiposFunda = await provider.tipoFundaRepository.getAll();

    if (widget.juegoLocalId != null) {
      _existing = await provider.juegoRepository.getByLocalId(widget.juegoLocalId!);
      if (_existing != null) {
        _nombre.text = _existing!.nombre;
        _descripcion.text = _existing!.descripcion ?? '';
        _jugMin.text = _existing!.numJugadoresMin?.toString() ?? '';
        _jugMax.text = _existing!.numJugadoresMax?.toString() ?? '';
        _edadMin.text = _existing!.edadMinima?.toString() ?? '';
        // Categories (multi)
        for (final c in _existing!.categorias) {
          final found = _categorias.where(
            (cat) => cat.serverId == c.id || cat.localId == -c.id,
          );
          if (found.isNotEmpty) _categoriaLocalIds.add(found.first.localId);
        }
        if (_categoriaLocalIds.isEmpty && _existing!.categoria != null) {
          final catLocal = _findCategoriaLocalIdFromJuego();
          if (catLocal != null) _categoriaLocalIds.add(catLocal);
        }
        _ubicacionLocalId = _existing!.ubicacion != null
            ? _findUbicacionLocalIdFromJuego()
            : null;
        _ubicacionEnCajaBase = _existing!.enCajaBase;
        _juegoBaseLocalId = _existing!.juegoBaseLocalId;
        _fechaCompra = _existing!.fechaCompra;
        _estado = _existing!.estado;
        _imagenPath = _existing!.imagen;
        _bggId = _existing!.bggId;
        _noEnfundar = _existing!.noEnfundar;
        _esExpansion = _existing!.esExpansionFlag;
        _idiomas = List.from(_existing!.idiomas);
        _idiomaOtroCtrl.text = _existing!.idiomaOtro ?? '';
        _independienteIdioma = _existing!.independienteIdioma;
        _tradumaquetado = _existing!.tradumaquetado;
        _tradumaquetadoParcial = _existing!.tradumaquetadoParcial;
        _tradumaquetadoNotasCtrl.text = _existing!.tradumaquetadoParcialNotas ?? '';
        _variasCopias = _existing!.variasCopias;
        for (final p in _existing!.propietarios) {
          final localProp = _propietarios.firstWhere(
            (lp) => lp.serverId == p.id || lp.localId == -p.id,
            orElse: () =>
                _propietarios.isEmpty ? throw StateError('empty') : _propietarios.first,
          );
          if (_propietarios.any((lp) =>
              lp.serverId == p.id || lp.localId == -p.id)) {
            _propietariosLocalIds.add(localProp.localId);
          }
        }
        // Load per-owner locations from pivot
        if (_variasCopias && _existing!.localId != null) {
          final pivotUbicaciones = await provider.juegoRepository
              .getPropietarioUbicaciones(_existing!.localId!);
          _propietarioUbicaciones.addAll(pivotUbicaciones);
        }
        _fundas = _existing!.fundas.map((f) {
          final tipo = _tiposFunda.firstWhere(
            (t) => t.serverId == f.tipoFundaId || t.localId == -f.tipoFundaId,
            orElse: () => _tiposFunda.isEmpty
                ? throw StateError('empty')
                : _tiposFunda.first,
          );
          return _FundaDraft(
            tipoFundaLocalId: tipo.localId,
            cantidadCartas: f.cantidadCartas,
            enfundadas: f.enfundadas,
          );
        }).toList();
      }
    } else {
      _estado = 'disponible';
      final principal = _propietarios.where((p) => p.esPrincipal).firstOrNull;
      if (principal != null) _propietariosLocalIds.add(principal.localId);
    }

    if (widget.bggPrefill != null) {
      _applyBggPrefill(widget.bggPrefill!);
    }

    if (mounted) setState(() => _loading = false);
  }

  int? _findCategoriaLocalIdFromJuego() {
    final c = _existing?.categoria;
    if (c == null) return null;
    final found = _categorias.firstWhere(
      (cat) => cat.serverId == c.id || cat.localId == -c.id,
      orElse: () => _categorias.first,
    );
    return _categorias.any((cat) => cat.serverId == c.id || cat.localId == -c.id)
        ? found.localId
        : null;
  }

  int? _findUbicacionLocalIdFromJuego() {
    final u = _existing?.ubicacion;
    if (u == null) return null;
    final found = _ubicaciones.firstWhere(
      (ub) => ub.serverId == u.id || ub.localId == -u.id,
      orElse: () => _ubicaciones.first,
    );
    return _ubicaciones.any((ub) => ub.serverId == u.id || ub.localId == -u.id)
        ? found.localId
        : null;
  }

  void _applyBggPrefill(Map<String, dynamic> game) {
    _nombre.text = game['name'] ?? _nombre.text;
    _descripcion.text = game['description'] ?? _descripcion.text;
    final minP = game['min_players'];
    final maxP = game['max_players'];
    if (minP != null && minP != 0) _jugMin.text = '$minP';
    if (maxP != null && maxP != 0) _jugMax.text = '$maxP';
    if (game['bgg_id'] != null) _bggId = game['bgg_id'] as int;
    if (game['image'] != null && (game['image'] as String).isNotEmpty) {
      _imagenPath = game['image'];
    } else if (game['thumbnail'] != null) {
      _imagenPath = game['thumbnail'];
    }
  }

  Future<void> _pickFechaCompra() async {
    final now = DateTime.now();
    final current = _fechaCompra != null
        ? DateTime.tryParse(_fechaCompra!) ?? now
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: now,
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _fechaCompra =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _newImageFile = File(picked.path));
    }
  }

  Future<void> _openBggPicker() async {
    final game = await BggSearchPicker.show(context,
        initialQuery: _nombre.text.trim());
    if (game != null) {
      setState(() => _applyBggPrefill(game));
    }
  }

  Future<void> _save() async {
    if (_nombre.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El nombre es obligatorio')),
      );
      return;
    }
    if (_categoriaLocalIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos una categoría')),
      );
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<JuegosProvider>();

    // Upload new image if taken from camera/gallery
    if (_newImageFile != null) {
      try {
        final formData = FormData.fromMap({
          'image': await MultipartFile.fromFile(
            _newImageFile!.path,
            filename: _newImageFile!.path.split('/').last,
          ),
        });
        final response = await ApiService().upload('/juegos/upload-image', formData);
        if (response.statusCode == 200 && response.data['url'] != null) {
          _imagenPath = response.data['url'] as String;
        }
      } catch (e) {
        debugPrint('Image upload failed (will save without image): $e');
      }
    }

    int? ubicacionLocalIdToUse = _ubicacionEnCajaBase ? null : _ubicacionLocalId;

    final juego = Juego(
      id: _existing?.id ?? 0,
      localId: _existing?.localId,
      serverId: _existing?.serverId,
      nombre: _nombre.text.trim(),
      descripcion:
          _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
      edadMinima: int.tryParse(_edadMin.text),
      numJugadoresMin: int.tryParse(_jugMin.text),
      numJugadoresMax: int.tryParse(_jugMax.text),
      categoriaLocalId: _categoriaLocalIds.isNotEmpty ? _categoriaLocalIds.first : null,
      ubicacionLocalId: ubicacionLocalIdToUse,
      juegoBaseLocalId: _esExpansion ? _juegoBaseLocalId : null,
      estado: _estado ?? 'disponible',
      fechaCompra: _fechaCompra,
      bggId: _bggId,
      imagen: _imagenPath,
      noEnfundar: _noEnfundar,
      esExpansionFlag: _esExpansion,
      idiomas: _idiomas,
      idiomaOtro: _idiomas.contains('otros') ? _idiomaOtroCtrl.text.trim() : null,
      independienteIdioma: _independienteIdioma,
      tradumaquetado: _tradumaquetado,
      tradumaquetadoParcial: _tradumaquetadoParcial,
      tradumaquetadoParcialNotas: _tradumaquetadoParcial ? _tradumaquetadoNotasCtrl.text.trim() : null,
      variasCopias: _variasCopias,
      enCajaBase: _ubicacionEnCajaBase,
    );

    final fundas = _fundas
        .map((f) => JuegoFundaDraft(
              tipoFundaLocalId: f.tipoFundaLocalId,
              cantidadCartas: f.cantidadCartas,
              enfundadas: f.enfundadas,
            ))
        .toList();

    try {
      await provider.saveJuego(
        juego,
        propietarioLocalIds: _propietariosLocalIds.toList(),
        fundas: fundas,
        categoriaLocalIds: _categoriaLocalIds.toList(),
        propietarioUbicaciones: _propietarioUbicaciones,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_existing == null
                ? 'Juego creado'
                : 'Cambios guardados'),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_existing == null ? 'Nuevo juego' : 'Editar juego'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'Nuevo juego' : 'Editar juego'),
        actions: [
          IconButton(
            tooltip: 'Buscar en BGG',
            onPressed: _openBggPicker,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildImage(),
          const SizedBox(height: 16),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descripcion,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripci\u00f3n',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _jugMin,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jug. m\u00edn',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _jugMax,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jug. m\u00e1x',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _edadMin,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Edad',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCategoriasSection(),
          const SizedBox(height: 16),
          _buildExpansionSection(),
          const SizedBox(height: 16),
          _buildIdiomasSection(),
          const SizedBox(height: 16),
          _buildUbicacionSection(),
          const SizedBox(height: 16),
          _buildPropietariosSection(),
          const SizedBox(height: 16),
          _buildFundasSection(),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickFechaCompra,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de compra',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(_fechaCompra ?? 'Sin fecha'),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('No enfundar este juego'),
            subtitle: const Text('Oculta avisos de fundas para este juego'),
            value: _noEnfundar,
            onChanged: (v) => setState(() => _noEnfundar = v),
          ),
          SwitchListTile(
            title: const Text('Independiente del idioma'),
            value: _independienteIdioma,
            onChanged: (v) => setState(() => _independienteIdioma = v),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save),
            label: Text(_existing == null ? 'Crear juego' : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: _newImageFile != null
                ? Image.file(_newImageFile!, fit: BoxFit.cover)
                : (_imagenPath != null && _imagenPath!.isNotEmpty
                    ? Image.network(_imagenPath!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported, size: 40))
                    : const Icon(Icons.casino, size: 40, color: Colors.grey)),
          ),
          Positioned(
            bottom: 4,
            right: 4,
            child: PopupMenuButton<ImageSource>(
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
              ),
              onSelected: _pickImage,
              itemBuilder: (_) => const [
                PopupMenuItem(value: ImageSource.camera, child: Text('C\u00e1mara')),
                PopupMenuItem(value: ImageSource.gallery, child: Text('Galer\u00eda')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Juego? _juegoBaseData;

  Widget _buildExpansionSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Es expansión'),
              value: _esExpansion,
              onChanged: (v) => setState(() {
                _esExpansion = v;
                if (!v) {
                  _juegoBaseLocalId = null;
                  _juegoBaseData = null;
                }
              }),
            ),
            if (_esExpansion) ...[
              const SizedBox(height: 8),
              Text('Juego base',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
              const SizedBox(height: 8),
              _JuegoBasePicker(
                initialLocalId: _juegoBaseLocalId,
                onChanged: (id) async {
                  setState(() {
                    _juegoBaseLocalId = id;
                    if (id == null) {
                      _ubicacionEnCajaBase = false;
                      _juegoBaseData = null;
                    }
                  });
                  if (id != null) {
                    final provider = context.read<JuegosProvider>();
                    final base = await provider.juegoRepository.getByLocalId(id);
                    if (mounted) {
                      setState(() => _juegoBaseData = base);
                      if (base != null && base.variasCopias && base.propietarios.isNotEmpty) {
                        _propietariosLocalIds.clear();
                        final allProps = await provider.propietarioRepository.getAll();
                        final firstOwner = base.propietarios.first;
                        final match = allProps.where(
                          (lp) => lp.serverId == firstOwner.id || lp.localId == -firstOwner.id,
                        );
                        if (match.isNotEmpty && mounted) {
                          setState(() => _propietariosLocalIds.add(match.first.localId));
                        }
                      }
                    }
                  }
                },
              ),
              if (_juegoBaseData != null && _juegoBaseData!.variasCopias && _juegoBaseData!.propietarios.length > 1) ...[
                const SizedBox(height: 12),
                Text('Propietario de la copia base',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _juegoBaseData!.propietarios.map((p) {
                    final match = _propietarios.where(
                      (lp) => lp.serverId == p.id || lp.localId == -p.id,
                    );
                    if (match.isEmpty) return const SizedBox.shrink();
                    final propLocalId = match.first.localId;
                    final selected = _propietariosLocalIds.contains(propLocalId);
                    return ChoiceChip(
                      label: Text(p.nombre),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        _propietariosLocalIds.clear();
                        if (v) _propietariosLocalIds.add(propLocalId);
                      }),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showNewCategoriaDialog() async {
    final nombreCtrl = TextEditingController();
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nueva categoría'),
          content: TextField(
            controller: nombreCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nombreCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        final repo = context.read<JuegosProvider>().categoriaRepository;
                        final localId = await repo.create(nombre: nombreCtrl.text.trim());
                        SyncService().syncAll();
                        if (ctx.mounted) Navigator.pop(ctx, true);
                        final updated = await repo.getAll();
                        setState(() {
                          _categorias = updated;
                          _categoriaLocalIds.add(localId);
                        });
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final repo = context.read<JuegosProvider>().categoriaRepository;
      final updated = await repo.getAll();
      setState(() => _categorias = updated);
    }
  }

  Widget _buildCategoriasSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Categorías *',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Nueva categoría',
                  onPressed: _showNewCategoriaDialog,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _categorias.map((c) {
                final selected = _categoriaLocalIds.contains(c.localId);
                return FilterChip(
                  label: Text(c.nombre),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _categoriaLocalIds.add(c.localId);
                    } else {
                      _categoriaLocalIds.remove(c.localId);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdiomasSection() {
    const opciones = ['castellano', 'catalan', 'ingles', 'frances', 'aleman', 'portugues', 'otros'];
    const labels = {
      'castellano': 'Castellano',
      'catalan': 'Catalán',
      'ingles': 'Inglés',
      'frances': 'Francés',
      'aleman': 'Alemán',
      'portugues': 'Portugués',
      'otros': 'Otros',
    };
    final showTradu = !_idiomas.contains('castellano') && !_idiomas.contains('catalan');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Idiomas',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: opciones.map((idioma) {
                final selected = _idiomas.contains(idioma);
                return FilterChip(
                  label: Text(labels[idioma] ?? idioma),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _idiomas.add(idioma);
                    } else {
                      _idiomas.remove(idioma);
                    }
                  }),
                );
              }).toList(),
            ),
            if (_idiomas.contains('otros')) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _idiomaOtroCtrl,
                decoration: const InputDecoration(
                  labelText: 'Especificar idioma',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (showTradu && _idiomas.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              Text('Tradumaquetación',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tradumaquetado'),
                value: _tradumaquetado,
                onChanged: (v) => setState(() {
                  _tradumaquetado = v;
                  if (v) _tradumaquetadoParcial = false;
                }),
              ),
              if (!_tradumaquetado) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tradumaquetado Parcial'),
                  value: _tradumaquetadoParcial,
                  onChanged: (v) => setState(() => _tradumaquetadoParcial = v),
                ),
                if (_tradumaquetadoParcial) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tradumaquetadoNotasCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas de traducción parcial',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUbicacionSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ubicaci\u00f3n',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            if (_juegoBaseLocalId != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('En la caja del juego base'),
                value: _ubicacionEnCajaBase,
                onChanged: (v) => setState(() {
                  _ubicacionEnCajaBase = v ?? false;
                  if (_ubicacionEnCajaBase) _ubicacionLocalId = null;
                }),
              ),
            if (!_ubicacionEnCajaBase)
              DropdownButtonFormField<int>(
                initialValue: _ubicacionLocalId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Estante',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Sin asignar',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  ..._ubicaciones.map((u) => DropdownMenuItem(
                        value: u.localId,
                        child: Text(u.rutaCompleta,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _ubicacionLocalId = v),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropietariosSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Propietarios',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            if (_propietarios.isEmpty)
              Text('No hay propietarios.',
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: 13))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _propietarios.map((p) {
                  final selected = _propietariosLocalIds.contains(p.localId);
                  return FilterChip(
                    label: Text(p.nombre),
                    selected: selected,
                    avatar: p.esPrincipal
                        ? const Icon(Icons.star, size: 16)
                        : null,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _propietariosLocalIds.add(p.localId);
                      } else {
                        _propietariosLocalIds.remove(p.localId);
                        _propietarioUbicaciones.remove(p.localId);
                      }
                    }),
                  );
                }).toList(),
              ),
            if (_propietariosLocalIds.length > 1) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Varias copias'),
                subtitle: const Text('Una copia por propietario'),
                value: _variasCopias,
                onChanged: (v) => setState(() => _variasCopias = v),
              ),
              if (_variasCopias)
                ..._propietariosLocalIds.map((propId) {
                  final prop = _propietarios.firstWhere((p) => p.localId == propId);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: DropdownButtonFormField<int?>(
                      value: _propietarioUbicaciones[propId],
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Ubicación de ${prop.nombre}',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Sin asignar', style: TextStyle(color: Colors.grey)),
                        ),
                        ..._ubicaciones.map((u) => DropdownMenuItem<int?>(
                              value: u.localId,
                              child: Text(u.rutaCompleta, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _propietarioUbicaciones[propId] = v),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showNewTipoFundaDialog() async {
    final nombreCtrl = TextEditingController();
    final anchoCtrl = TextEditingController();
    final altoCtrl = TextEditingController();
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nuevo tamaño de carta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej: Standard, Mini Euro...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: anchoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ancho (mm) *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: altoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Alto (mm) *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final nombre = nombreCtrl.text.trim();
                      final ancho = int.tryParse(anchoCtrl.text.trim());
                      final alto = int.tryParse(altoCtrl.text.trim());
                      if (nombre.isEmpty || ancho == null || alto == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Completa todos los campos')),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final repo = context.read<JuegosProvider>().tipoFundaRepository;
                        await repo.create(nombre: nombre, anchoMm: ancho, altoMm: alto);
                        SyncService().syncAll();
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final repo = context.read<JuegosProvider>().tipoFundaRepository;
      final updated = await repo.getAll();
      setState(() => _tiposFunda = updated);
    }
  }

  Widget _buildFundasSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Cartas y fundas',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                ),
                IconButton(
                  icon: const Icon(Icons.playlist_add, size: 20),
                  tooltip: 'Nuevo tamaño de carta',
                  onPressed: _showNewTipoFundaDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Añadir fila',
                  onPressed: _tiposFunda.isEmpty
                      ? null
                      : () => setState(() {
                            _fundas.add(_FundaDraft(
                              tipoFundaLocalId: _tiposFunda.first.localId,
                              cantidadCartas: 0,
                              enfundadas: false,
                            ));
                          }),
                ),
              ],
            ),
            if (_fundas.isEmpty)
              Text('Sin tamaños de fundas asociados.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 13))
            else
              ..._fundas.asMap().entries.map((e) => _buildFundaRow(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildFundaRow(int idx, _FundaDraft draft) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: draft.tipoFundaLocalId,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              items: _tiposFunda
                  .map((t) => DropdownMenuItem(
                      value: t.localId,
                      child: Text(t.textoCompleto,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setState(() {
                if (v != null) draft.tipoFundaLocalId = v;
              }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: draft.cantidadCartas.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cartas',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              onChanged: (v) {
                draft.cantidadCartas = int.tryParse(v) ?? 0;
              },
            ),
          ),
          Checkbox(
            value: draft.enfundadas,
            onChanged: (v) => setState(() => draft.enfundadas = v ?? false),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => setState(() => _fundas.removeAt(idx)),
          ),
        ],
      ),
    );
  }
}

class _FundaDraft {
  int tipoFundaLocalId;
  int cantidadCartas;
  bool enfundadas;

  _FundaDraft({
    required this.tipoFundaLocalId,
    required this.cantidadCartas,
    required this.enfundadas,
  });
}

class _JuegoBasePicker extends StatefulWidget {
  final int? initialLocalId;
  final ValueChanged<int?> onChanged;

  const _JuegoBasePicker({this.initialLocalId, required this.onChanged});

  @override
  State<_JuegoBasePicker> createState() => _JuegoBasePickerState();
}

class _JuegoBasePickerState extends State<_JuegoBasePicker> {
  int? _selectedLocalId;
  String? _selectedNombre;
  List<Juego> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _selectedLocalId = widget.initialLocalId;
    _loadName();
  }

  Future<void> _loadName() async {
    if (_selectedLocalId == null) return;
    final provider = context.read<JuegosProvider>();
    final j = await provider.juegoRepository.getByLocalId(_selectedLocalId!);
    if (mounted) setState(() => _selectedNombre = j?.nombre);
  }

  Future<void> _search(String q) async {
    final provider = context.read<JuegosProvider>();
    if (q.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    final results =
        await provider.juegoRepository.search(buscar: q, perPage: 20, soloBase: true);
    if (mounted) setState(() => _suggestions = results);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedLocalId != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Chip(
              label: Text(_selectedNombre ?? 'Juego base seleccionado'),
              avatar: const Icon(Icons.casino, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedLocalId = null;
                  _selectedNombre = null;
                });
                widget.onChanged(null);
              },
            ),
          ),
        TextField(
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Buscar juego base...',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: _search,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              children: _suggestions
                  .map((j) => ListTile(
                        dense: true,
                        title: Text(j.nombre),
                        onTap: () {
                          setState(() {
                            _selectedLocalId = j.localId;
                            _selectedNombre = j.nombre;
                            _suggestions = [];
                          });
                          widget.onChanged(j.localId);
                        },
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}
