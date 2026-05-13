import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/juego.dart';
import '../providers/juegos_provider.dart';
import '../widgets/game_image.dart';

/// Detalle de un juego.
///
/// Se identifica preferentemente por `juegoLocalId`. Si se navega con un
/// `juegoServerId` se resuelve el local a partir de \u00e9l.
class JuegoDetailScreen extends StatefulWidget {
  final int? juegoLocalId;
  final int? juegoServerId;
  const JuegoDetailScreen({super.key, this.juegoLocalId, this.juegoServerId});

  @override
  State<JuegoDetailScreen> createState() => _JuegoDetailScreenState();
}

class _JuegoDetailScreenState extends State<JuegoDetailScreen> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<JuegosProvider>();
      if (widget.juegoLocalId != null) {
        provider.fetchJuego(widget.juegoLocalId!);
      } else if (widget.juegoServerId != null) {
        provider.fetchJuego(widget.juegoServerId!, isServerId: true);
      }
    });
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    final parts = dateStr.split('-');
    if (parts.length != 3) return dateStr;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  Future<void> _openEditor(BuildContext context, Juego juego) async {
    if (juego.localId == null) return;
    final result = await Navigator.of(context)
        .pushNamed('/juego/editar', arguments: juego.localId);
    if (!mounted) return;
    if (result == true) {
      await this.context.read<JuegosProvider>().refreshDetail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JuegosProvider>();
    final juego = provider.juegoDetalle;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(juego?.nombre ?? 'Cargando...'),
        actions: [
          if (juego != null)
            IconButton(
              tooltip: 'Editar',
              onPressed: () => _openEditor(context, juego),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : juego == null
              ? const Center(child: Text('Juego no encontrado'))
              : RefreshIndicator(
                  onRefresh: () => provider.refreshDetail(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeader(juego, theme),
                      const SizedBox(height: 20),
                      _buildInfoGrid(juego, theme),
                      if (juego.propietarios.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('Propietarios', theme,
                            child: Wrap(
                              spacing: 8,
                              children: juego.propietarios
                                  .map((p) => Chip(label: Text(p.nombre)))
                                  .toList(),
                            )),
                      ],
                      if (juego.fundas.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection('Cartas y fundas', theme,
                            child: Column(
                              children: juego.fundas
                                  .map((funda) => Card(
                                        elevation: 0,
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          leading: CircleAvatar(
                                            backgroundColor: (funda.enfundadas
                                                    ? Colors.green
                                                    : Colors.orange)
                                                .withValues(alpha: 0.1),
                                            child: Icon(
                                              Icons.style,
                                              color: funda.enfundadas
                                                  ? Colors.green
                                                  : Colors.orange,
                                            ),
                                          ),
                                          title: Text(
                                            funda.tipoTexto,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${funda.cantidadCartas} cartas',
                                          ),
                                          trailing: Chip(
                                            label: Text(
                                              funda.enfundadas
                                                  ? 'Enfundadas'
                                                  : 'Faltan',
                                            ),
                                            backgroundColor: (funda.enfundadas
                                                    ? Colors.green
                                                    : Colors.orange)
                                                .withValues(alpha: 0.1),
                                            labelStyle: TextStyle(
                                              color: funda.enfundadas
                                                  ? Colors.green[700]
                                                  : Colors.orange[700],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            )),
                      ],
                      if (juego.expansiones.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildSection(
                          'Expansiones (${juego.expansiones.length})',
                          theme,
                          child: Column(
                            children: juego.expansiones
                                .map((exp) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.extension,
                                          size: 20),
                                      title: Text(exp.nombre,
                                          style:
                                              const TextStyle(fontSize: 14)),
                                      trailing: const Icon(Icons.chevron_right,
                                          size: 18),
                                      onTap: () => Navigator.of(context)
                                          .pushNamed('/juego',
                                              arguments: exp.localId),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(Juego juego, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GameImage(
          juego: juego,
          width: 120,
          height: 120,
          borderRadius: BorderRadius.circular(12),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(juego.nombre,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  if (juego.dirty)
                    const Tooltip(
                      message: 'Cambios pendientes de sincronizar',
                      child: Icon(Icons.sync_problem,
                          color: Colors.orange, size: 18),
                    ),
                ],
              ),
              if (juego.esExpansion) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Expansi\u00f3n',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600)),
                ),
              ],
              if (juego.descripcion != null &&
                  juego.descripcion!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(juego.descripcion!,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13, height: 1.4)),
              ],
              if (juego.esExpansion && juego.juegoBase != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => Navigator.of(context).pushNamed('/juego',
                      arguments: juego.juegoBase!.localId),
                  child: Text('Juego base: ${juego.juegoBase!.nombre}',
                      style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(Juego juego, ThemeData theme) {
    final items = <_InfoItem>[
      _InfoItem('Categor\u00eda', juego.categoria?.nombre ?? '-', Icons.category),
      _InfoItem('Jugadores', juego.jugadoresTexto, Icons.people),
      _InfoItem('Edad', juego.edadTexto, Icons.child_care),
      _InfoItem('Estado', juego.estado ?? '-', Icons.info_outline),
      _InfoItem('Fecha compra', _formatDate(juego.fechaCompra),
          Icons.calendar_today),
      _InfoItem('Ubicaci\u00f3n',
          juego.ubicacion?.rutaCompleta ?? 'Sin asignar', Icons.location_on),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.5,
      children: items.map((item) {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(item.icon, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(item.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(item.value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSection(String title, ThemeData theme, {required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  final IconData icon;
  _InfoItem(this.label, this.value, this.icon);
}
