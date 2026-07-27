import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/juego_repository.dart';
import '../data/sync_service.dart';
import '../data/tipo_funda_repository.dart';
import '../providers/juegos_provider.dart';

class TiposFundaScreen extends StatefulWidget {
  const TiposFundaScreen({super.key});

  @override
  State<TiposFundaScreen> createState() => _TiposFundaScreenState();
}

class _TiposFundaScreenState extends State<TiposFundaScreen> {
  List<TipoFundaRow> _tipos = [];
  Map<int, int> _usoCount = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<JuegosProvider>().tipoFundaRepository;
      final tipos = await repo.getAll();
      tipos.sort((a, b) => JuegoRepository.normalizeText(a.nombre)
          .compareTo(JuegoRepository.normalizeText(b.nombre)));
      final uso = await repo.getUsoCount();
      if (!mounted) return;
      setState(() {
        _tipos = tipos;
        _usoCount = uso;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TIPOS FUNDA ERROR: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showFormDialog({TipoFundaRow? tipo}) async {
    final nombreCtrl = TextEditingController(text: tipo?.nombre ?? '');
    final anchoCtrl =
        TextEditingController(text: tipo != null ? tipo.anchoMm.toString() : '');
    final altoCtrl =
        TextEditingController(text: tipo != null ? tipo.altoMm.toString() : '');
    final isEditing = tipo != null;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar funda' : 'Nueva funda'),
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
                  const SizedBox(width: 12),
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
                      final ancho = int.tryParse(anchoCtrl.text.trim()) ?? 0;
                      final alto = int.tryParse(altoCtrl.text.trim()) ?? 0;
                      if (nombre.isEmpty || ancho <= 0 || alto <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Rellena el nombre y unas medidas válidas.')),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final repo = context
                            .read<JuegosProvider>()
                            .tipoFundaRepository;
                        if (isEditing) {
                          await repo.update(
                            tipo.localId,
                            nombre: nombre,
                            anchoMm: ancho,
                            altoMm: alto,
                          );
                        } else {
                          await repo.create(
                            nombre: nombre,
                            anchoMm: ancho,
                            altoMm: alto,
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

    if (result == true) _fetch();
  }

  Future<void> _confirmDelete(TipoFundaRow tipo) async {
    final count = _usoCount[tipo.localId] ?? 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar funda'),
        content: Text(count > 0
            ? '"${tipo.nombre}" se usa en $count juego(s). Si la eliminas, esas fundas quedarán sin tipo asignado.'
            : '¿Eliminar "${tipo.nombre}"?'),
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
        final repo = context.read<JuegosProvider>().tipoFundaRepository;
        await repo.delete(tipo.localId);
        SyncService().syncAll();
        _fetch();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Funda eliminada')),
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
      appBar: AppBar(title: const Text('Fundas')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tipos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.style_outlined,
                          size: 56, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No hay fundas',
                          style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _tipos.length,
                    itemBuilder: (context, index) {
                      final tipo = _tipos[index];
                      final count = _usoCount[tipo.localId] ?? 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 3),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Icon(Icons.style,
                                color: theme.colorScheme.onPrimaryContainer,
                                size: 20),
                          ),
                          title: Text('${tipo.nombre} ($count)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text('${tipo.anchoMm} x ${tipo.altoMm} mm',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') {
                                _showFormDialog(tipo: tipo);
                              }
                              if (action == 'delete') _confirmDelete(tipo);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: 'edit', child: Text('Editar')),
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
