import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/categoria_repository.dart';
import '../data/sync_service.dart';
import '../providers/juegos_provider.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  List<CategoriaRow> _categorias = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCategorias();
  }

  Future<void> _fetchCategorias() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<JuegosProvider>().categoriaRepository;
      final cats = await repo.getAll();
      setState(() {
        _categorias = cats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('CATEGORIAS ERROR: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _showFormDialog({CategoriaRow? categoria}) async {
    final nombreCtrl = TextEditingController(text: categoria?.nombre ?? '');
    final descripcionCtrl = TextEditingController(text: categoria?.descripcion ?? '');
    final isEditing = categoria != null;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar categoría' : 'Nueva categoría'),
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
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
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
                      if (nombreCtrl.text.trim().isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        final repo = context.read<JuegosProvider>().categoriaRepository;
                        if (isEditing) {
                          await repo.update(
                            categoria.localId,
                            nombre: nombreCtrl.text.trim(),
                            descripcion: descripcionCtrl.text.trim().isEmpty
                                ? null
                                : descripcionCtrl.text.trim(),
                          );
                        } else {
                          await repo.create(
                            nombre: nombreCtrl.text.trim(),
                            descripcion: descripcionCtrl.text.trim().isEmpty
                                ? null
                                : descripcionCtrl.text.trim(),
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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEditing ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );

    if (result == true) _fetchCategorias();
  }

  Future<void> _confirmDelete(CategoriaRow categoria) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${categoria.nombre}"? Los juegos de esta categoría quedarán sin categoría.'),
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
      try {
        final repo = context.read<JuegosProvider>().categoriaRepository;
        await repo.delete(categoria.localId);
        SyncService().syncAll();
        _fetchCategorias();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Categoría eliminada')),
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
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _categorias.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.category_outlined, size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No hay categorías', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchCategorias,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _categorias.length,
                    itemBuilder: (context, index) {
                      final cat = _categorias[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(Icons.category, color: theme.colorScheme.onPrimaryContainer, size: 20),
                          ),
                          title: Text(cat.nombre,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: cat.descripcion != null && cat.descripcion!.isNotEmpty
                              ? Text(cat.descripcion!, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))
                              : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') _showFormDialog(categoria: cat);
                              if (action == 'delete') _confirmDelete(cat);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Editar')),
                              const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
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
