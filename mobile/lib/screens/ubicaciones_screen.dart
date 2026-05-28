import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/ubicacion_repository.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';

class UbicacionesScreen extends StatefulWidget {
  const UbicacionesScreen({super.key});

  @override
  State<UbicacionesScreen> createState() => _UbicacionesScreenState();
}

class _UbicacionesScreenState extends State<UbicacionesScreen> {
  List<HabitacionRow> _habitaciones = [];
  List<MuebleRow> _muebles = [];
  List<UbicacionRow> _ubicaciones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _loadLocal());
  }

  Future<void> _loadLocal() async {
    setState(() => _loading = true);
    final repo = context.read<JuegosProvider>().ubicacionRepository;
    try {
      final h = await repo.listHabitaciones();
      final m = await repo.listMuebles();
      final u = await repo.getAll();
      if (mounted) {
        setState(() {
          _habitaciones = h;
          _muebles = m;
          _ubicaciones = u;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('UBICACIONES ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncIfPossible() async {
    try {
      await context.read<SyncProvider>().syncNow();
    } catch (e) {
      debugPrint('sync ubicaciones: $e');
    }
    if (mounted) await _loadLocal();
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Añadir ubicación',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Habitación'),
              subtitle: const Text('Ej: Salón, Despacho, Dormitorio'),
              onTap: () {
                Navigator.pop(ctx);
                _showHabitacionDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Mueble'),
              subtitle: const Text('Ej: Estantería Kallax, Vitrina'),
              onTap: () {
                Navigator.pop(ctx);
                _showMuebleDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.shelves),
              title: const Text('Estante'),
              subtitle: const Text('Ej: Balda 1, Cajón superior'),
              onTap: () {
                Navigator.pop(ctx);
                _showEstanteDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showHabitacionDialog() async {
    final ctrl = TextEditingController();
    bool saving = false;
    final repo = context.read<JuegosProvider>().ubicacionRepository;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nueva habitación'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
              hintText: 'Ej: Salón',
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
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
                        await repo.createHabitacion(nombre: ctrl.text.trim());
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
    if (result == true) {
      await _syncIfPossible();
    }
  }

  Future<void> _showMuebleDialog() async {
    if (_habitaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea una habitación')),
      );
      return;
    }

    final ctrl = TextEditingController();
    int habitacionLocalId = _habitaciones.first.localId;
    bool saving = false;
    final repo = context.read<JuegosProvider>().ubicacionRepository;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nuevo mueble'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: habitacionLocalId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Habitación *',
                  border: OutlineInputBorder(),
                ),
                items: _habitaciones
                    .map((h) => DropdownMenuItem(
                          value: h.localId,
                          child: Text(h.nombre,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() {
                  if (v != null) habitacionLocalId = v;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: Kallax 5x5',
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
                        await repo.createMueble(
                          habitacionLocalId: habitacionLocalId,
                          nombre: ctrl.text.trim(),
                        );
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
    if (result == true) {
      await _syncIfPossible();
    }
  }

  Future<void> _showEstanteDialog() async {
    if (_muebles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea un mueble')),
      );
      return;
    }

    final ctrl = TextEditingController();
    int muebleLocalId = _muebles.first.localId;
    bool saving = false;
    final repo = context.read<JuegosProvider>().ubicacionRepository;

    final result = await showDialog<bool>(
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
                items: _muebles
                    .map((m) => DropdownMenuItem(
                          value: m.localId,
                          child: Text(
                            '${m.nombre} (${_habitacionNombre(m.habitacionLocalId)})',
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
    if (result == true) {
      await _syncIfPossible();
    }
  }

  String _habitacionNombre(int? habitacionLocalId) {
    if (habitacionLocalId == null) return '?';
    try {
      return _habitaciones
          .firstWhere((h) => h.localId == habitacionLocalId)
          .nombre;
    } catch (_) {
      return '?';
    }
  }

  List<MuebleRow> _mueblesDeHabitacion(int habitacionLocalId) {
    return _muebles
        .where((m) => m.habitacionLocalId == habitacionLocalId)
        .toList();
  }

  List<UbicacionRow> _ubicacionesDeMueble(int muebleLocalId) {
    return _ubicaciones
        .where((u) => u.muebleLocalId == muebleLocalId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Ubicaciones')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _habitaciones.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_off,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay ubicaciones configuradas',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _syncIfPossible,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar desde el servidor'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _syncIfPossible,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _habitaciones.length,
                    itemBuilder: (context, index) =>
                        _buildHabitacionCard(_habitaciones[index], theme),
                  ),
                ),
    );
  }

  Widget _buildHabitacionCard(HabitacionRow habitacion, ThemeData theme) {
    final muebles = _mueblesDeHabitacion(habitacion.localId);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading:
              Icon(Icons.home_outlined, color: theme.colorScheme.primary),
          title: Text(
            habitacion.nombre,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${muebles.length} ${muebles.length == 1 ? 'mueble' : 'muebles'}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          children: muebles.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'Sin muebles',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ),
                ]
              : muebles.map((m) => _buildMuebleTile(m, theme)).toList(),
        ),
      ),
    );
  }

  Widget _buildMuebleTile(MuebleRow mueble, ThemeData theme) {
    final ubicacionesList = _ubicacionesDeMueble(mueble.localId);

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: ExpansionTile(
        leading: Icon(Icons.inventory_2_outlined,
            size: 20, color: Colors.grey[600]),
        title: Text(
          mueble.nombre,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: ubicacionesList.isNotEmpty
            ? Text(
                '${ubicacionesList.length} ${ubicacionesList.length == 1 ? 'estante' : 'estantes'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              )
            : null,
        children: ubicacionesList.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
                  child: Text(
                    'Sin estantes definidos',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ),
              ]
            : ubicacionesList
                .map((u) => ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.only(left: 40, right: 16),
                      leading: Icon(Icons.shelves,
                          size: 18, color: Colors.grey[500]),
                      title: Text(
                        u.nombre,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ))
                .toList(),
      ),
    );
  }
}
