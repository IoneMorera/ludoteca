import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/bgg_expansion_repository.dart';
import '../providers/juegos_provider.dart';
import '../widgets/expansion_faltante_actions.dart';

class NuevasExpansionesScreen extends StatefulWidget {
  const NuevasExpansionesScreen({super.key});

  @override
  State<NuevasExpansionesScreen> createState() => _NuevasExpansionesScreenState();
}

class _NuevasExpansionesScreenState extends State<NuevasExpansionesScreen> {
  List<BggExpansionGroup> _grupos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final provider = context.read<JuegosProvider>();
    final grupos = await provider.bggExpansionRepository.nuevasDelAnioAgrupadas();
    if (mounted) {
      setState(() {
        _grupos = grupos;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevas expansiones'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _grupos.isEmpty
              ? const Center(child: Text('No hay expansiones nuevas pendientes'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _grupos.length,
                    itemBuilder: (context, index) {
                      final grupo = _grupos[index];
                      final baseLocalId = grupo.baseLocalId;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                grupo.baseNombre,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...grupo.expansiones.map((exp) {
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.extension,
                                    size: 20,
                                    color: errorColor,
                                  ),
                                  title: Text(
                                    exp.nombre,
                                    style: TextStyle(
                                      color: errorColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: exp.anio != null
                                      ? Text('Año ${exp.anio}')
                                      : null,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.more_vert),
                                    onPressed: baseLocalId == null
                                        ? null
                                        : () => ExpansionFaltanteActions.showMenu(
                                              context,
                                              expansion: exp,
                                              juegoBaseLocalId: baseLocalId,
                                              onChanged: _load,
                                            ),
                                  ),
                                  onTap: () => ExpansionFaltanteActions.abrirEnBgg(
                                    context,
                                    expansion: exp,
                                  ),
                                );
                              }),
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
