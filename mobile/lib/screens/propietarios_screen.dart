import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/propietario_repository.dart';
import '../data/sync_service.dart';
import '../providers/juegos_provider.dart';

class PropietariosScreen extends StatefulWidget {
  const PropietariosScreen({super.key});

  @override
  State<PropietariosScreen> createState() => _PropietariosScreenState();
}

class _PropietariosScreenState extends State<PropietariosScreen> {
  List<PropietarioRow> _propietarios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPropietarios();
  }

  Future<void> _fetchPropietarios() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<JuegosProvider>().propietarioRepository;
      final propietarios = await repo.getAll();
      if (!mounted) return;
      setState(() {
        _propietarios = propietarios;
        _loading = false;
      });
    } catch (e) {
      debugPrint('PROPIETARIOS ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFormDialog({PropietarioRow? propietario}) async {
    final nombreCtrl = TextEditingController(text: propietario?.nombre ?? '');
    final bggCtrl =
        TextEditingController(text: propietario?.bggUsername ?? '');
    final isEditing = propietario != null;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar propietario' : 'Nuevo propietario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bggCtrl,
                decoration: const InputDecoration(
                  labelText: 'Usuario BGG',
                  border: OutlineInputBorder(),
                  hintText: 'Opcional',
                ),
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
                      if (nombreCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        final repo = context
                            .read<JuegosProvider>()
                            .propietarioRepository;
                        final bgg = bggCtrl.text.trim().isEmpty
                            ? null
                            : bggCtrl.text.trim();
                        if (isEditing) {
                          await repo.update(
                            propietario.localId,
                            nombre: nombreCtrl.text.trim(),
                            bggUsername: bgg,
                          );
                        } else {
                          await repo.create(
                            nombre: nombreCtrl.text.trim(),
                            bggUsername: bgg,
                          );
                        }
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _fetchPropietarios();
  }

  Future<void> _confirmDelete(PropietarioRow propietario) async {
    if (propietario.esPrincipal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se puede eliminar el propietario principal')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar propietario'),
        content: Text('¿Eliminar "${propietario.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        final repo = context.read<JuegosProvider>().propietarioRepository;
        await repo.delete(propietario.localId);
        SyncService().syncAll();
        _fetchPropietarios();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Propietario eliminado')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Propietarios')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _propietarios.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No hay propietarios',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchPropietarios,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _propietarios.length,
                    itemBuilder: (context, index) {
                      final prop = _propietarios[index];
                      final esPrincipal = prop.esPrincipal;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: esPrincipal
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primaryContainer,
                            child: Icon(
                              esPrincipal ? Icons.star : Icons.person,
                              color: esPrincipal
                                  ? Colors.white
                                  : theme.colorScheme.onPrimaryContainer,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(prop.nombre,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                              ),
                              if (esPrincipal)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Principal',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.primary)),
                                ),
                            ],
                          ),
                          subtitle: prop.bggUsername != null &&
                                  prop.bggUsername!.isNotEmpty
                              ? Text('BGG: ${prop.bggUsername}',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]))
                              : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showFormDialog(propietario: prop);
                              }
                              if (action == 'delete') _confirmDelete(prop);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Editar')),
                              if (!esPrincipal)
                                const PopupMenuItem(
                                    value: 'delete', child: Text('Eliminar')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
