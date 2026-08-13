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
  bool _saveInProgress = false;

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
  bool _autojugable = false;
  List<String> _idiomas = [];
  final _idiomaOtroCtrl = TextEditingController();
  bool _independienteIdioma = false;
  bool _tradumaquetado = false;
  bool _tradumaquetadoParcial = false;
  final _tradumaquetadoNotasCtrl = TextEditingController();
  bool _variasCopias = false;
  bool _sinAbrir = false;
  bool _printAndPlay = false;
  List<_FundaDraft> _fundas = [];
  final Map<int, _CopiaDraft> _copias = {};
  final Set<int> _copiasExpanded = {};
  int? _expansionBaseOwnerLocalId;
  final _precioCtrl = TextEditingController();

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
    _precioCtrl.dispose();
    for (final c in _copias.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final provider = context.read<JuegosProvider>();
    _categorias = await provider.categoriaRepository.getAll();
    _propietarios = await provider.propietarioRepository.getAll();
    _ubicaciones = await provider.ubicacionRepository.getAll();
    _tiposFunda = _sortTiposFunda(await provider.tipoFundaRepository.getAll());

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
        _precioCtrl.text = _existing!.precio?.toString() ?? '';
        _imagenPath = _existing!.imagen;
        _bggId = _existing!.bggId;
        _noEnfundar = _existing!.noEnfundar;
        _esExpansion = _existing!.esExpansionFlag;
        _autojugable = _existing!.autojugable;
        _idiomas = List.from(_existing!.idiomas);
        _idiomaOtroCtrl.text = _existing!.idiomaOtro ?? '';
        _independienteIdioma = _existing!.independienteIdioma;
        _tradumaquetado = _existing!.tradumaquetado;
        _tradumaquetadoParcial = _existing!.tradumaquetadoParcial;
        _tradumaquetadoNotasCtrl.text = _existing!.tradumaquetadoParcialNotas ?? '';
        _variasCopias = _existing!.variasCopias;
        _sinAbrir = _existing!.sinAbrir;
        _printAndPlay = _existing!.printAndPlay;
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
        // Load per-owner copy data from pivot
        if (_variasCopias && _existing!.localId != null) {
          final copiaData = await provider.juegoRepository
              .getCopiaData(_existing!.localId!);
          for (final entry in copiaData.entries) {
            _copias[entry.key] = _CopiaDraft.fromRepository(entry.value);
            _propietarioUbicaciones[entry.key] = entry.value.ubicacionLocalId;
          }
          if (_fechaCompra != null) {
            final principal = _copias.values
                .where((c) => c.esPrincipal)
                .firstOrNull;
            if (principal != null && principal.fechaCompra == null) {
              principal.fechaCompra = _fechaCompra;
            }
          }
          _copiasExpanded.addAll(_copias.keys);
        } else if (_existing!.localId != null) {
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
        if (_esExpansion && _juegoBaseLocalId != null) {
          _juegoBaseData =
              await provider.juegoRepository.getByLocalId(_juegoBaseLocalId!);
          if (!_variasCopias && _propietariosLocalIds.length == 1) {
            _expansionBaseOwnerLocalId = _propietariosLocalIds.first;
          }
          if (_variasCopias) {
            for (final propId in _propietariosLocalIds) {
              final copia = _copias[propId];
              if (copia != null) {
                copia.linkedBaseOwnerLocalId ??= propId;
                if (copia.esPrincipal && _ubicacionEnCajaBase) {
                  copia.enCajaBase = true;
                }
              }
            }
          }
        }
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

  int? _propLocalIdForServerPropietario(int serverPropId) {
    final match = _propietarios.where(
      (lp) => lp.serverId == serverPropId || lp.localId == -serverPropId,
    );
    return match.isEmpty ? null : match.first.localId;
  }

  bool get _baseHasMultipleOwners =>
      _juegoBaseData != null &&
      _juegoBaseData!.variasCopias &&
      _juegoBaseData!.propietarios.length > 1;

  bool get _expansionIsMultiOwner =>
      _variasCopias && _propietariosLocalIds.length > 1;

  Widget _buildBaseOwnerChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.indigo.shade100,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: selected ? Colors.indigo.shade700 : Colors.grey.shade400,
        width: selected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.indigo.shade900 : Colors.grey.shade800,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      showCheckmark: true,
      checkmarkColor: Colors.indigo.shade900,
      onSelected: onSelected,
    );
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

  _CopiaDraft _copiaFromGlobal(int propId) {
    return _CopiaDraft(
      propietarioLocalId: propId,
      ubicacionLocalId: _propietarioUbicaciones[propId] ?? _ubicacionLocalId,
      enCajaBase: _ubicacionEnCajaBase,
      linkedBaseOwnerLocalId: propId,
      esPrincipal: false,
      estado: _estado,
      fechaCompra: _fechaCompra,
      noEnfundar: _noEnfundar,
      idiomas: List.from(_idiomas),
      idiomaOtro: _idiomaOtroCtrl.text.trim().isEmpty
          ? null
          : _idiomaOtroCtrl.text.trim(),
      tradumaquetado: _tradumaquetado,
      tradumaquetadoParcial: _tradumaquetadoParcial,
      tradumaquetadoParcialNotas: _tradumaquetadoNotasCtrl.text.trim().isEmpty
          ? null
          : _tradumaquetadoNotasCtrl.text.trim(),
      fundas: _fundas
          .map((f) => _FundaDraft(
                tipoFundaLocalId: f.tipoFundaLocalId,
                cantidadCartas: f.cantidadCartas,
                enfundadas: f.enfundadas,
              ))
          .toList(),
    );
  }

  void _ensureCopiasInitialized() {
    for (final propId in _propietariosLocalIds) {
      _copias.putIfAbsent(propId, () => _copiaFromGlobal(propId));
    }
    _copias.removeWhere((k, _) => !_propietariosLocalIds.contains(k));
    if (_variasCopias && !_copias.values.any((c) => c.esPrincipal)) {
      final first = _propietariosLocalIds.firstOrNull;
      if (first != null) _copias[first]?.esPrincipal = true;
    }
  }

  void _onVariasCopiasChanged(bool value) {
    if (value) {
      for (final propId in _propietariosLocalIds) {
        _copias.putIfAbsent(propId, () => _copiaFromGlobal(propId));
      }
      if (!_copias.values.any((c) => c.esPrincipal)) {
        final first = _propietariosLocalIds.firstOrNull;
        if (first != null) _copias[first]?.esPrincipal = true;
      }
      _copiasExpanded.addAll(_propietariosLocalIds);
      _variasCopias = true;
    } else {
      _collapseCopiasToPrincipal();
      _variasCopias = false;
      _copias.clear();
      _copiasExpanded.clear();
    }
  }

  void _collapseCopiasToPrincipal() {
    final principal = _copias.values.where((c) => c.esPrincipal).firstOrNull ??
        (_copias.values.isNotEmpty ? _copias.values.first : null);
    if (principal == null) return;
    _ubicacionLocalId = principal.ubicacionLocalId;
    _ubicacionEnCajaBase = principal.enCajaBase;
    _estado = principal.estado ?? _estado;
    _fechaCompra = principal.fechaCompra;
    _noEnfundar = principal.noEnfundar;
    _idiomas = List.from(principal.idiomas);
    _idiomaOtroCtrl.text = principal.idiomaOtroCtrl.text;
    _tradumaquetado = principal.tradumaquetado;
    _tradumaquetadoParcial = principal.tradumaquetadoParcial;
    _tradumaquetadoNotasCtrl.text = principal.tradNotasCtrl.text;
    _fundas = principal.fundas
        .map((f) => _FundaDraft(
              tipoFundaLocalId: f.tipoFundaLocalId,
              cantidadCartas: f.cantidadCartas,
              enfundadas: f.enfundadas,
            ))
        .toList();
    _propietarioUbicaciones[principal.propietarioLocalId] =
        principal.ubicacionLocalId;
  }

  void _setPrincipalCopia(int propId) {
    for (final c in _copias.values) {
      c.esPrincipal = c.propietarioLocalId == propId;
    }
  }

  _CopiaDraft? get _principalCopia =>
      _copias.values.where((c) => c.esPrincipal).firstOrNull ??
      (_copias.values.isNotEmpty ? _copias.values.first : null);

  Future<bool?> _showCreateUbicacionFlow() async {
    final provider = context.read<JuegosProvider>();
    final repo = provider.ubicacionRepository;
    final habitaciones = await repo.listHabitaciones();
    final muebles = await repo.listMuebles();

    if (habitaciones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Primero crea una habitación desde Ubicaciones')),
        );
      }
      return false;
    }
    if (muebles.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Primero crea un mueble desde Ubicaciones')),
        );
      }
      return false;
    }

    final ctrl = TextEditingController();
    int muebleLocalId = muebles.first.localId;
    bool saving = false;

    String habitacionNombre(int? habLocalId) {
      if (habLocalId == null) return '?';
      try {
        return habitaciones.firstWhere((h) => h.localId == habLocalId).nombre;
      } catch (_) {
        return '?';
      }
    }

    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nuevo estante'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: muebleLocalId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mueble *',
                  border: OutlineInputBorder(),
                ),
                items: muebles
                    .map((m) => DropdownMenuItem(
                          value: m.localId,
                          child: Text(
                            '${m.nombre} (${habitacionNombre(m.habitacionLocalId)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => muebleLocalId = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Balda 1',
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
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
                      if (ctrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        await repo.createUbicacion(
                          muebleLocalId: muebleLocalId,
                          nombre: ctrl.text.trim(),
                        );
                        SyncService().syncAll();
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addUbicacionFromForm({ValueChanged<int?>? onSelected}) async {
    final created = await _showCreateUbicacionFlow();
    if (created == true) {
      final repo = context.read<JuegosProvider>().ubicacionRepository;
      final updated = await repo.getAll();
      final newest = updated.isNotEmpty ? updated.last.localId : null;
      setState(() => _ubicaciones = updated);
      if (newest != null) {
        onSelected?.call(newest);
      }
    }
  }

  Future<void> _pickFechaCompra({_CopiaDraft? copia}) async {
    final now = DateTime.now();
    final currentStr = copia?.fechaCompra ?? _fechaCompra;
    final current = currentStr != null
        ? DateTime.tryParse(currentStr) ?? now
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: now,
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        if (copia != null) {
          copia.fechaCompra = formatted;
        } else {
          _fechaCompra = formatted;
        }
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
    if (_saveInProgress || _saving) return;

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
    if (_esExpansion &&
        _baseHasMultipleOwners &&
        !_expansionIsMultiOwner &&
        _expansionBaseOwnerLocalId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecciona la copia del juego base')),
      );
      return;
    }
    if (_esExpansion &&
        _baseHasMultipleOwners &&
        _expansionIsMultiOwner) {
      _ensureCopiasInitialized();
      final missing = _propietariosLocalIds.where(
        (id) => _copias[id]?.linkedBaseOwnerLocalId == null,
      );
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Indica la copia del juego base en cada copia de la expansión')),
        );
        return;
      }
    }

    final provider = context.read<JuegosProvider>();

    if (_existing == null) {
      final exists = await provider.juegoRepository.existsWithNombre(
        _nombre.text.trim(),
      );
      if (exists && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Juego duplicado'),
            content: Text(
              'Ya existe un juego llamado "${_nombre.text.trim()}". '
              '¿Quieres crearlo de todas formas?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Crear igualmente'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    _saveInProgress = true;
    setState(() => _saving = true);

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
    String estadoToUse = _estado ?? 'disponible';
    double? precioToUse;
    bool noEnfundarToUse = _noEnfundar;
    String? fechaCompraToUse = _fechaCompra;
    List<String> idiomasToUse = _idiomas;
    String? idiomaOtroToUse =
        _idiomas.contains('otros') ? _idiomaOtroCtrl.text.trim() : null;
    bool independienteToUse = _independienteIdioma;
    bool traduToUse = _tradumaquetado;
    bool traduParcialToUse = _tradumaquetadoParcial;
    String? traduNotasToUse =
        _tradumaquetadoParcial ? _tradumaquetadoNotasCtrl.text.trim() : null;
    List<_FundaDraft> fundasToUse = _fundas;
    bool sinAbrirToUse = _sinAbrir;
    bool printAndPlayToUse = _printAndPlay;

    Map<int, CopiaPropietarioDraft>? copiasData;
    if (_variasCopias) {
      _ensureCopiasInitialized();
      final principal = _principalCopia;
      if (principal != null) {
        _ubicacionEnCajaBase = principal.enCajaBase;
        ubicacionLocalIdToUse =
            principal.enCajaBase ? null : principal.ubicacionLocalId;
        estadoToUse = principal.estado ?? estadoToUse;
        noEnfundarToUse = principal.noEnfundar;
        fechaCompraToUse = principal.fechaCompra;
        idiomasToUse = List.from(principal.idiomas);
        idiomaOtroToUse = principal.idiomas.contains('otros')
            ? principal.idiomaOtroCtrl.text.trim()
            : null;
        traduToUse = principal.tradumaquetado;
        traduParcialToUse = principal.tradumaquetadoParcial;
        traduNotasToUse = principal.tradumaquetadoParcial
            ? principal.tradNotasCtrl.text.trim()
            : null;
        fundasToUse = principal.fundas;
        // El nivel juego refleja la copia principal, igual que el resto de
        // datos mostrados en la pantalla de detalle/listado.
        sinAbrirToUse = principal.sinAbrir;
        printAndPlayToUse = principal.printAndPlay;
      }
      copiasData = {
        for (final entry in _copias.entries)
          entry.key: entry.value.toRepositoryDraft(
            independienteIdioma: _independienteIdioma,
          ),
      };
      for (final entry in _copias.entries) {
        _propietarioUbicaciones[entry.key] =
            entry.value.enCajaBase ? null : entry.value.ubicacionLocalId;
      }
    }

    if (estadoToUse == 'en_venta') {
      if (_variasCopias && _principalCopia != null) {
        precioToUse =
            double.tryParse(_principalCopia!.precioCtrl.text.trim());
      } else {
        precioToUse = double.tryParse(_precioCtrl.text.trim());
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
      categoriaLocalId: _categoriaLocalIds.isNotEmpty ? _categoriaLocalIds.first : null,
      ubicacionLocalId: ubicacionLocalIdToUse,
      juegoBaseLocalId: _esExpansion ? _juegoBaseLocalId : null,
      estado: estadoToUse,
      precio: precioToUse,
      fechaCompra: fechaCompraToUse,
      bggId: _bggId,
      imagen: _imagenPath,
      noEnfundar: noEnfundarToUse,
      esExpansionFlag: _esExpansion,
      autojugable: _esExpansion && _autojugable,
      idiomas: idiomasToUse,
      idiomaOtro: idiomaOtroToUse,
      independienteIdioma: independienteToUse,
      tradumaquetado: traduToUse,
      tradumaquetadoParcial: traduParcialToUse,
      tradumaquetadoParcialNotas: traduNotasToUse,
      variasCopias: _variasCopias,
      enCajaBase: _ubicacionEnCajaBase,
      sinAbrir: sinAbrirToUse,
      printAndPlay: printAndPlayToUse,
    );

    final fundas = fundasToUse
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
        copiasData: copiasData,
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
        final message = e is StateError
            ? e.message
            : 'Error al guardar: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      _saveInProgress = false;
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
          if (!_variasCopias) ...[
            _buildIdiomasSection(),
            const SizedBox(height: 16),
            _buildUbicacionSection(),
            const SizedBox(height: 16),
          ],
          _buildPropietariosSection(),
          if (_variasCopias) ...[
            const SizedBox(height: 16),
            _buildCopiasSection(),
          ],
          if (!_variasCopias) ...[
            const SizedBox(height: 16),
            _buildFundasSection(),
            if (_existing != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildEstadoSection(),
                ),
              ),
            ],
          ],
          if (!_variasCopias) ...[
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
          ],
          SwitchListTile(
            title: const Text('Independiente del idioma'),
            value: _independienteIdioma,
            onChanged: (v) => setState(() => _independienteIdioma = v),
          ),
          if (!_variasCopias) ...[
            SwitchListTile(
              title: const Text('Sin abrir'),
              subtitle: const Text('El juego a\u00fan est\u00e1 por estrenar'),
              value: _sinAbrir,
              onChanged: (v) => setState(() => _sinAbrir = v),
            ),
            SwitchListTile(
              title: const Text('Print and Play'),
              subtitle: const Text('Juego de impresi\u00f3n casera'),
              value: _printAndPlay,
              onChanged: (v) => setState(() => _printAndPlay = v),
            ),
          ],
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
                  _expansionBaseOwnerLocalId = null;
                }
              }),
            ),
            if (_esExpansion) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Autojugable'),
                subtitle: const Text(
                    'Se puede jugar sin el juego base. Contará también como juego básico.'),
                value: _autojugable,
                onChanged: (v) => setState(() => _autojugable = v),
              ),
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
                      _expansionBaseOwnerLocalId = null;
                    }
                  });
                  if (id != null) {
                    final provider = context.read<JuegosProvider>();
                    final base = await provider.juegoRepository.getByLocalId(id);
                    if (mounted) {
                      setState(() {
                        _juegoBaseData = base;
                        _expansionBaseOwnerLocalId = null;
                      });
                    }
                  }
                },
              ),
              // Expansión con una sola copia y base multi-propietario
              if (_baseHasMultipleOwners && !_expansionIsMultiOwner) ...[
                const SizedBox(height: 12),
                Text('Propietario de la copia base',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 4),
                Text('¿De qué copia del juego base es esta expansión?',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _juegoBaseData!.propietarios.map((p) {
                    final propLocalId = _propLocalIdForServerPropietario(p.id);
                    if (propLocalId == null) return const SizedBox.shrink();
                    final selected = _expansionBaseOwnerLocalId == propLocalId;
                    return _buildBaseOwnerChip(
                      label: p.nombre,
                      selected: selected,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() {
                          _expansionBaseOwnerLocalId = propLocalId;
                          _propietariosLocalIds
                            ..clear()
                            ..add(propLocalId);
                          _variasCopias = false;
                          _copias.clear();
                          _copiasExpanded.clear();
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              if (_baseHasMultipleOwners && _expansionIsMultiOwner) ...[
                const SizedBox(height: 12),
                Text('Copias del juego base',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700])),
                const SizedBox(height: 4),
                Text(
                  'Indica en cada copia de la expansión a qué copia del juego base corresponde.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
            Row(
              children: [
                Expanded(
                  child: Text('Ubicaci\u00f3n',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700])),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Nueva ubicación',
                  onPressed: () => _addUbicacionFromForm(
                    onSelected: (id) => setState(() => _ubicacionLocalId = id),
                  ),
                ),
              ],
            ),
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
                        if (_variasCopias) {
                          _copias.putIfAbsent(
                              p.localId, () => _copiaFromGlobal(p.localId));
                          _copias[p.localId]!.linkedBaseOwnerLocalId ??=
                              p.localId;
                          _copiasExpanded.add(p.localId);
                        }
                      } else {
                        _propietariosLocalIds.remove(p.localId);
                        _propietarioUbicaciones.remove(p.localId);
                        _copias.remove(p.localId);
                        _copiasExpanded.remove(p.localId);
                        if (_expansionBaseOwnerLocalId == p.localId) {
                          _expansionBaseOwnerLocalId = null;
                        }
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
                onChanged: (v) => setState(() => _onVariasCopiasChanged(v)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoSection({_CopiaDraft? copia}) {
    if (_existing == null && copia == null) return const SizedBox.shrink();

    final isCopia = copia != null;
    final estado = isCopia ? (copia.estado ?? 'disponible') : (_estado ?? 'disponible');
    final precioCtrl = isCopia ? copia.precioCtrl : _precioCtrl;

    void setEstado(String? v) {
      setState(() {
        if (isCopia) {
          copia.estado = v;
        } else {
          _estado = v;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estado',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            ChoiceChip(
              label: const Text('Disponible'),
              selected: estado == 'disponible',
              onSelected: (_) => setEstado('disponible'),
            ),
            ChoiceChip(
              label: const Text('En venta'),
              selected: estado == 'en_venta',
              onSelected: (_) => setEstado('en_venta'),
            ),
            ChoiceChip(
              label: const Text('Vendido'),
              selected: estado == 'vendido',
              onSelected: (_) => setEstado('vendido'),
            ),
          ],
        ),
        if (estado == 'en_venta') ...[
          const SizedBox(height: 8),
          TextField(
            controller: precioCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Precio (€)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCopiasSection() {
    _ensureCopiasInitialized();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _propietariosLocalIds.map((propId) {
        final prop = _propietarios.firstWhere((p) => p.localId == propId);
        final copia = _copias[propId]!;
        final expanded = _copiasExpanded.contains(propId);
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              ListTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text('Copia de ${prop.nombre}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (copia.esPrincipal)
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                  ],
                ),
                subtitle: copia.esPrincipal
                    ? const Text('Copia principal')
                    : null,
                trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                onTap: () => setState(() {
                  if (expanded) {
                    _copiasExpanded.remove(propId);
                  } else {
                    _copiasExpanded.add(propId);
                  }
                }),
              ),
              if (expanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('Principal'),
                            selected: copia.esPrincipal,
                            avatar: copia.esPrincipal
                                ? const Icon(Icons.star, size: 16)
                                : null,
                            onSelected: (_) =>
                                setState(() => _setPrincipalCopia(propId)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_esExpansion &&
                          _baseHasMultipleOwners &&
                          _expansionIsMultiOwner) ...[
                        Text('Copia del juego base',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700])),
                        const SizedBox(height: 4),
                        Text(
                          '¿De qué copia del juego base es la expansión de ${prop.nombre}?',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children:
                              _juegoBaseData!.propietarios.map((baseProp) {
                            final basePropLocalId =
                                _propLocalIdForServerPropietario(baseProp.id);
                            if (basePropLocalId == null) {
                              return const SizedBox.shrink();
                            }
                            final selected =
                                copia.linkedBaseOwnerLocalId == basePropLocalId;
                            return _buildBaseOwnerChip(
                              label: baseProp.nombre,
                              selected: selected,
                              onSelected: (v) {
                                if (!v) return;
                                setState(() => copia.linkedBaseOwnerLocalId =
                                    basePropLocalId);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildCopiaUbicacion(copia),
                      const SizedBox(height: 12),
                      _buildCopiaIdiomas(copia),
                      const SizedBox(height: 12),
                      _buildCopiaFundas(copia),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _pickFechaCompra(copia: copia),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha de compra',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(copia.fechaCompra ?? 'Sin fecha'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('No enfundar'),
                        value: copia.noEnfundar,
                        onChanged: (v) =>
                            setState(() => copia.noEnfundar = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sin abrir'),
                        subtitle: const Text('Esta copia a\u00fan est\u00e1 por estrenar'),
                        value: copia.sinAbrir,
                        onChanged: (v) => setState(() => copia.sinAbrir = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Print and Play'),
                        subtitle: const Text('Copia de impresi\u00f3n casera'),
                        value: copia.printAndPlay,
                        onChanged: (v) =>
                            setState(() => copia.printAndPlay = v),
                      ),
                      if (_existing != null) ...[
                        const SizedBox(height: 8),
                        _buildEstadoSection(copia: copia),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCopiaUbicacion(_CopiaDraft copia) {
    final showEnCajaBase = _esExpansion && _juegoBaseLocalId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Ubicación',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
            ),
            if (!copia.enCajaBase)
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: 'Nueva ubicación',
                onPressed: () => _addUbicacionFromForm(
                  onSelected: (id) => setState(() {
                    copia.ubicacionLocalId = id;
                    _propietarioUbicaciones[copia.propietarioLocalId] = id;
                  }),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (showEnCajaBase)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('En la caja del juego base'),
            value: copia.enCajaBase,
            onChanged: (v) => setState(() {
              copia.enCajaBase = v ?? false;
              if (copia.enCajaBase) {
                copia.ubicacionLocalId = null;
                _propietarioUbicaciones[copia.propietarioLocalId] = null;
              }
            }),
          ),
        if (!copia.enCajaBase)
          DropdownButtonFormField<int?>(
            initialValue: copia.ubicacionLocalId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Estante',
              border: OutlineInputBorder(),
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
            onChanged: (v) => setState(() {
              copia.ubicacionLocalId = v;
              _propietarioUbicaciones[copia.propietarioLocalId] = v;
            }),
          ),
      ],
    );
  }

  Widget _buildCopiaIdiomas(_CopiaDraft copia) {
    const opciones = [
      'castellano',
      'catalan',
      'ingles',
      'frances',
      'aleman',
      'portugues',
      'otros'
    ];
    const labels = {
      'castellano': 'Castellano',
      'catalan': 'Catalán',
      'ingles': 'Inglés',
      'frances': 'Francés',
      'aleman': 'Alemán',
      'portugues': 'Portugués',
      'otros': 'Otros',
    };
    final showTradu =
        !copia.idiomas.contains('castellano') && !copia.idiomas.contains('catalan');

    return Column(
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
            final selected = copia.idiomas.contains(idioma);
            return FilterChip(
              label: Text(labels[idioma] ?? idioma),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) {
                  copia.idiomas.add(idioma);
                } else {
                  copia.idiomas.remove(idioma);
                }
              }),
            );
          }).toList(),
        ),
        if (copia.idiomas.contains('otros')) ...[
          const SizedBox(height: 8),
          TextField(
            controller: copia.idiomaOtroCtrl,
            decoration: const InputDecoration(
              labelText: 'Especificar idioma',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (showTradu && copia.idiomas.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tradumaquetado'),
            value: copia.tradumaquetado,
            onChanged: (v) => setState(() {
              copia.tradumaquetado = v;
              if (v) copia.tradumaquetadoParcial = false;
            }),
          ),
          if (!copia.tradumaquetado) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tradumaquetado Parcial'),
              value: copia.tradumaquetadoParcial,
              onChanged: (v) => setState(() => copia.tradumaquetadoParcial = v),
            ),
            if (copia.tradumaquetadoParcial) ...[
              const SizedBox(height: 8),
              TextField(
                controller: copia.tradNotasCtrl,
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
    );
  }

  Widget _buildCopiaFundas(_CopiaDraft copia) {
    return Column(
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
                        copia.fundas.add(_FundaDraft(
                          tipoFundaLocalId: _tiposFunda.first.localId,
                          cantidadCartas: 0,
                          enfundadas: false,
                        ));
                      }),
            ),
          ],
        ),
        if (copia.fundas.isEmpty)
          Text('Sin tamaños de fundas asociados.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13))
        else
          ...copia.fundas.asMap().entries.map(
                (e) => _buildFundaRow(e.key, e.value, onRemove: () {
                  setState(() => copia.fundas.removeAt(e.key));
                }),
              ),
      ],
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
      final updated = _sortTiposFunda(await repo.getAll());
      setState(() => _tiposFunda = updated);
    }
  }

  List<TipoFundaRow> _sortTiposFunda(List<TipoFundaRow> tipos) {
    tipos.sort((a, b) =>
        a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return tipos;
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
              ..._fundas.asMap().entries.map(
                    (e) => _buildFundaRow(
                      e.key,
                      e.value,
                      onRemove: () => setState(() => _fundas.removeAt(e.key)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildFundaRow(int idx, _FundaDraft draft, {VoidCallback? onRemove}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: draft.tipoFundaLocalId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Tipo de funda',
              border: OutlineInputBorder(),
            ),
            items: _tiposFunda
                .map((t) => DropdownMenuItem(
                      value: t.localId,
                      child: Text(t.textoCompleto,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              if (v != null) draft.tipoFundaLocalId = v;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.cantidadCartas.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cartas',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    draft.cantidadCartas = int.tryParse(v) ?? 0;
                  },
                ),
              ),
              Checkbox(
                value: draft.enfundadas,
                onChanged: (v) =>
                    setState(() => draft.enfundadas = v ?? false),
              ),
              const Text('Enfundadas', style: TextStyle(fontSize: 13)),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onRemove ?? () => setState(() => _fundas.removeAt(idx)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopiaDraft {
  final int propietarioLocalId;
  int? ubicacionLocalId;
  bool enCajaBase;
  int? linkedBaseOwnerLocalId;
  bool esPrincipal;
  String? estado;
  String? fechaCompra;
  bool noEnfundar;
  List<String> idiomas;
  bool tradumaquetado;
  bool tradumaquetadoParcial;
  bool sinAbrir;
  bool printAndPlay;
  List<_FundaDraft> fundas;
  late final TextEditingController idiomaOtroCtrl;
  late final TextEditingController tradNotasCtrl;
  late final TextEditingController precioCtrl;

  _CopiaDraft({
    required this.propietarioLocalId,
    this.ubicacionLocalId,
    this.enCajaBase = false,
    this.linkedBaseOwnerLocalId,
    this.esPrincipal = false,
    this.estado,
    this.fechaCompra,
    this.noEnfundar = false,
    List<String>? idiomas,
    String? idiomaOtro,
    this.tradumaquetado = false,
    this.tradumaquetadoParcial = false,
    String? tradumaquetadoParcialNotas,
    this.sinAbrir = false,
    this.printAndPlay = false,
    String? precio,
    List<_FundaDraft>? fundas,
  })  : idiomas = idiomas ?? [],
        fundas = fundas ?? [] {
    idiomaOtroCtrl = TextEditingController(text: idiomaOtro ?? '');
    tradNotasCtrl =
        TextEditingController(text: tradumaquetadoParcialNotas ?? '');
    precioCtrl = TextEditingController(text: precio ?? '');
  }

  factory _CopiaDraft.fromRepository(CopiaPropietarioDraft draft) {
    return _CopiaDraft(
      propietarioLocalId: draft.propietarioLocalId,
      ubicacionLocalId: draft.ubicacionLocalId,
      linkedBaseOwnerLocalId: draft.propietarioLocalId,
      esPrincipal: draft.esPrincipal,
      estado: draft.estado,
      fechaCompra: draft.fechaCompra,
      noEnfundar: draft.noEnfundar,
      idiomas: List.from(draft.idiomas),
      idiomaOtro: draft.idiomaOtro,
      tradumaquetado: draft.tradumaquetado,
      tradumaquetadoParcial: draft.tradumaquetadoParcial,
      tradumaquetadoParcialNotas: draft.tradumaquetadoParcialNotas,
      sinAbrir: draft.sinAbrir,
      printAndPlay: draft.printAndPlay,
      fundas: draft.fundas
          .map((f) => _FundaDraft(
                tipoFundaLocalId: f.tipoFundaLocalId,
                cantidadCartas: f.cantidadCartas,
                enfundadas: f.enfundadas,
              ))
          .toList(),
    );
  }

  CopiaPropietarioDraft toRepositoryDraft({required bool independienteIdioma}) {
    return CopiaPropietarioDraft(
      propietarioLocalId: propietarioLocalId,
      ubicacionLocalId: ubicacionLocalId,
      esPrincipal: esPrincipal,
      estado: estado,
      fechaCompra: fechaCompra,
      noEnfundar: noEnfundar,
      idiomas: List.from(idiomas),
      idiomaOtro: idiomaOtroCtrl.text.trim().isEmpty
          ? null
          : idiomaOtroCtrl.text.trim(),
      independienteIdioma: independienteIdioma,
      tradumaquetado: tradumaquetado,
      tradumaquetadoParcial: tradumaquetadoParcial,
      tradumaquetadoParcialNotas: tradNotasCtrl.text.trim().isEmpty
          ? null
          : tradNotasCtrl.text.trim(),
      sinAbrir: sinAbrir,
      printAndPlay: printAndPlay,
      fundas: fundas
          .map((f) => JuegoFundaDraft(
                tipoFundaLocalId: f.tipoFundaLocalId,
                cantidadCartas: f.cantidadCartas,
                enfundadas: f.enfundadas,
              ))
          .toList(),
    );
  }

  void dispose() {
    idiomaOtroCtrl.dispose();
    tradNotasCtrl.dispose();
    precioCtrl.dispose();
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
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedLocalId = widget.initialLocalId;
    _loadName();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          controller: _searchCtrl,
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
