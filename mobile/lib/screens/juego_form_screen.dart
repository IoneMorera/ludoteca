import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/categoria_repository.dart';
import '../data/juego_repository.dart';
import '../data/propietario_repository.dart';
import '../data/tipo_funda_repository.dart';
import '../data/ubicacion_repository.dart';
import '../models/juego.dart';
import '../providers/juegos_provider.dart';
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

  int? _categoriaLocalId;
  int? _ubicacionLocalId;
  bool _ubicacionEnCajaBase = false;
  final Set<int> _propietariosLocalIds = {};
  int? _juegoBaseLocalId;
  String? _fechaCompra;
  String? _estado;
  String? _imagenPath;
  File? _newImageFile;
  int? _bggId;
  bool _noEnfundar = false;
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
        _categoriaLocalId = _existing!.categoria != null
            ? _findCategoriaLocalIdFromJuego()
            : null;
        _ubicacionLocalId = _existing!.ubicacion != null
            ? _findUbicacionLocalIdFromJuego()
            : null;
        _juegoBaseLocalId = _existing!.juegoBaseLocalId;
        _fechaCompra = _existing!.fechaCompra;
        _estado = _existing!.estado;
        _imagenPath = _existing!.imagen;
        _bggId = _existing!.bggId;
        _noEnfundar = _existing!.noEnfundar;
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
    if (_categoriaLocalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una categor\u00eda')),
      );
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<JuegosProvider>();

    int? ubicacionLocalIdToUse = _ubicacionLocalId;
    if (_ubicacionEnCajaBase && _juegoBaseLocalId != null) {
      final base = await provider.juegoRepository.getByLocalId(_juegoBaseLocalId!);
      if (base != null && base.ubicacion != null) {
        final baseUbic = _ubicaciones.firstWhere(
          (u) =>
              u.serverId == base.ubicacion!.id || u.localId == -base.ubicacion!.id,
          orElse: () => _ubicaciones.isEmpty
              ? throw StateError('empty')
              : _ubicaciones.first,
        );
        if (_ubicaciones.any((u) =>
            u.serverId == base.ubicacion!.id ||
            u.localId == -base.ubicacion!.id)) {
          ubicacionLocalIdToUse = baseUbic.localId;
        }
      }
    }

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
      categoriaLocalId: _categoriaLocalId,
      ubicacionLocalId: ubicacionLocalIdToUse,
      juegoBaseLocalId: _juegoBaseLocalId,
      estado: _estado ?? 'disponible',
      fechaCompra: _fechaCompra,
      bggId: _bggId,
      imagen: _imagenPath,
      noEnfundar: _noEnfundar,
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
          DropdownButtonFormField<int>(
            initialValue: _categoriaLocalId,
            decoration: const InputDecoration(
              labelText: 'Categor\u00eda *',
              border: OutlineInputBorder(),
            ),
            items: _categorias
                .map((c) => DropdownMenuItem(
                    value: c.localId, child: Text(c.nombre)))
                .toList(),
            onChanged: (v) => setState(() => _categoriaLocalId = v),
          ),
          const SizedBox(height: 16),
          _buildJuegoBaseSection(),
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

  Widget _buildJuegoBaseSection() {
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
            Text('Juego base (si es expansi\u00f3n)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            const SizedBox(height: 8),
            _JuegoBasePicker(
              initialLocalId: _juegoBaseLocalId,
              onChanged: (id) {
                setState(() {
                  _juegoBaseLocalId = id;
                  if (id == null) _ubicacionEnCajaBase = false;
                });
              },
            ),
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
                  icon: const Icon(Icons.add),
                  tooltip: 'A\u00f1adir',
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
              Text('Sin tama\u00f1os de fundas asociados.',
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
