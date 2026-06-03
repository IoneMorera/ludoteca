import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/sync_service.dart';
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

  Future<void> _openEditor(BuildContext context, Juego juego) async {
    if (juego.localId == null) return;
    final result = await Navigator.of(context)
        .pushNamed('/juego/editar', arguments: juego.localId);
    if (!mounted) return;
    if (result == true) {
      await this.context.read<JuegosProvider>().refreshDetail();
    }
  }

  Future<void> _showEstadoDialog(Juego juego) async {
    if (juego.localId == null) return;
    String selectedEstado = juego.estado ?? 'disponible';
    final precioCtrl = TextEditingController(
      text: juego.precio != null ? juego.precio!.toStringAsFixed(2) : '',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cambiar estado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...['disponible', 'en_venta', 'vendido'].map((estado) {
                return RadioListTile<String>(
                  title: Text(_formatEstado(estado)),
                  value: estado,
                  groupValue: selectedEstado,
                  onChanged: (v) => setDialogState(() => selectedEstado = v!),
                );
              }),
              if (selectedEstado == 'en_venta') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: precioCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio',
                    prefixText: '€ ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final p = selectedEstado == 'en_venta'
                    ? double.tryParse(precioCtrl.text)
                    : null;
                Navigator.pop(ctx, {'estado': selectedEstado, 'precio': p});
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final provider = context.read<JuegosProvider>();
      await provider.juegoRepository.updateEstado(
        juego.localId!,
        estado: result['estado'] as String,
        precio: result['precio'] as double?,
      );
      SyncService().syncAll();
      await provider.refreshDetail();
    }
  }

  Future<void> _showUbicacionDialog(Juego juego) async {
    if (juego.localId == null) return;
    final provider = context.read<JuegosProvider>();
    final ubicaciones = await provider.ubicacionRepository.getAll();
    int? selectedLocalId = juego.ubicacionLocalId;

    if (!mounted) return;
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cambiar ubicación'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                RadioListTile<int?>(
                  title: const Text('Sin asignar',
                      style: TextStyle(color: Colors.grey)),
                  value: null,
                  groupValue: selectedLocalId,
                  onChanged: (v) => setDialogState(() => selectedLocalId = v),
                ),
                ...ubicaciones.map((u) => RadioListTile<int?>(
                      title: Text(u.rutaCompleta),
                      value: u.localId,
                      groupValue: selectedLocalId,
                      onChanged: (v) =>
                          setDialogState(() => selectedLocalId = v),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedLocalId ?? -1),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final newUbicLocalId = result == -1 ? null : result;
      await provider.juegoRepository.updateUbicacion(
        juego.localId!,
        ubicacionLocalId: newUbicLocalId,
      );
      SyncService().syncAll();
      await provider.refreshDetail();
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
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

  bool _isCompartido(Juego juego) {
    return juego.propietarios.length > 1 && !juego.variasCopias;
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
              if (juego.esExpansion || _isCompartido(juego)) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    if (juego.esExpansion)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
                    if (_isCompartido(juego))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.lightBlue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Compartido',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.lightBlue[700],
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
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
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      Navigator.of(context).pushReplacementNamed('/juego',
                          arguments: juego.juegoBase!.localId);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('Juego base: ${juego.juegoBase!.nombre}',
                          style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoGrid(Juego juego, ThemeData theme) {
    final bool tieneCastellanoOCatalan = juego.idiomas.any(
        (i) => i.toLowerCase() == 'castellano' || i.toLowerCase() == 'catalán' || i.toLowerCase() == 'catalan');

    String ubicacionTexto;
    if (juego.enCajaBase) {
      ubicacionTexto = 'En la caja del base';
    } else {
      ubicacionTexto = juego.ubicacion?.rutaCompleta ?? 'Sin asignar';
    }

    String estadoTexto = _formatEstado(juego.estado);
    if (juego.estado == 'en_venta' && juego.precio != null) {
      estadoTexto += ' (${juego.precio!.toStringAsFixed(2)} €)';
    }

    final items = <_InfoItem>[
      _InfoItem('Ubicación', ubicacionTexto, Icons.location_on,
          onTap: () => _showUbicacionDialog(juego)),
      _InfoItem('Categorías',
          juego.categorias.isNotEmpty
              ? juego.categorias.map((c) => c.nombre).join(', ')
              : juego.categoria?.nombre ?? '-',
          Icons.category),
      _InfoItem('Jugadores', juego.jugadoresTexto, Icons.people),
      _InfoItem('Edad', juego.edadTexto, Icons.child_care),
      _InfoItem('Idioma',
          juego.idiomas.isNotEmpty ? juego.idiomas.join(', ') : '-',
          Icons.language),
      _InfoItem('Ind. idioma',
          juego.independienteIdioma ? 'Sí' : 'No', Icons.translate),
      if (!tieneCastellanoOCatalan && juego.idiomas.isNotEmpty)
        _InfoItem('Tradumaquetado',
            juego.tradumaquetado
                ? 'Sí'
                : juego.tradumaquetadoParcial
                    ? 'Parcial${juego.tradumaquetadoParcialNotas != null && juego.tradumaquetadoParcialNotas!.isNotEmpty ? ': ${juego.tradumaquetadoParcialNotas}' : ''}'
                    : 'No',
            Icons.auto_stories),
      _InfoItem('Estado', estadoTexto, Icons.info_outline,
          onTap: () => _showEstadoDialog(juego)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.5,
          children: items.map((item) {
            final child = Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Icon(item.icon, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(item.label,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (item.onTap != null) ...[
                        const Spacer(),
                        Icon(Icons.edit_outlined, size: 12,
                            color: theme.colorScheme.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.value,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2),
                ],
              ),
            );
            if (item.onTap != null) {
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: item.onTap,
                child: child,
              );
            }
            return child;
          }).toList(),
        ),
        // Cartas y fundas
        if (juego.fundas.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSection('Cartas y fundas', theme,
              child: Column(
                children: juego.fundas
                    .map((funda) => Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
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
                                funda.enfundadas ? 'Enfundadas' : 'Sin enfundar',
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
      ],
    );
  }

  String _formatEstado(String? estado) {
    if (estado == null || estado.isEmpty) return '-';
    switch (estado) {
      case 'disponible':
        return 'Disponible';
      case 'en_venta':
        return 'En venta';
      case 'vendido':
        return 'Vendido';
      default:
        return estado;
    }
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
  final VoidCallback? onTap;
  _InfoItem(this.label, this.value, this.icon, {this.onTap});
}

