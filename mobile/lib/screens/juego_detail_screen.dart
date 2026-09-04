import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../data/bgg_expansion_repository.dart';
import '../data/sync_service.dart';
import '../models/juego.dart';
import '../providers/bgg_collection_provider.dart';
import '../providers/juegos_provider.dart';
import '../widgets/expansion_faltante_actions.dart';
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
  List<BggExpansionRow> _faltantes = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<JuegosProvider>();
      if (widget.juegoLocalId != null) {
        await provider.fetchJuego(widget.juegoLocalId!);
      } else if (widget.juegoServerId != null) {
        await provider.fetchJuego(widget.juegoServerId!, isServerId: true);
      }
      await _loadFaltantes();
    });
  }

  Future<void> _loadFaltantes() async {
    final juego = context.read<JuegosProvider>().juegoDetalle;
    if (juego?.bggId == null || juego!.esExpansion) {
      if (mounted) setState(() => _faltantes = []);
      return;
    }
    final faltantes = await context
        .read<JuegosProvider>()
        .faltantesExpansiones(juego.bggId!);
    if (mounted) setState(() => _faltantes = faltantes);
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
          content: RadioGroup<String>(
            groupValue: selectedEstado,
            onChanged: (v) {
              if (v == null) return;
              setDialogState(() => selectedEstado = v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...['disponible', 'en_venta', 'vendido'].map((estado) {
                  return RadioListTile<String>(
                    title: Text(_formatEstado(estado)),
                    value: estado,
                  );
                }),
                if (selectedEstado == 'en_venta') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: precioCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Precio',
                      prefixText: '€ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
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
    var ubicaciones = await provider.ubicacionRepository.getAll();
    final canUseCajaBase = juego.esExpansion;

    String selectedKey;
    if (juego.enCajaBase && canUseCajaBase) {
      selectedKey = 'en_caja_base';
    } else if (juego.ubicacionLocalId != null) {
      selectedKey = 'ubicacion:${juego.ubicacionLocalId}';
    } else {
      selectedKey = 'sin_asignar';
    }

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Cambiar ubicación')),
              IconButton(
                icon: const Icon(Icons.add, size: 22),
                tooltip: 'Añadir ubicación',
                onPressed: () async {
                  final created = await _showCreateUbicacionFlow(ctx);
                  if (created == true) {
                    final updated = await provider.ubicacionRepository.getAll();
                    setDialogState(() => ubicaciones = updated);
                  }
                },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: RadioGroup<String>(
              groupValue: selectedKey,
              onChanged: (v) {
                if (v == null) return;
                setDialogState(() => selectedKey = v);
              },
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (canUseCajaBase)
                    const RadioListTile<String>(
                      title: Text('En la caja del base'),
                      value: 'en_caja_base',
                    ),
                  const RadioListTile<String>(
                    title: Text('Sin asignar',
                        style: TextStyle(color: Colors.grey)),
                    value: 'sin_asignar',
                  ),
                  ...ubicaciones.map((u) => RadioListTile<String>(
                        title: Text(u.rutaCompleta),
                        value: 'ubicacion:${u.localId}',
                      )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedKey),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      if (result == 'en_caja_base') {
        await provider.juegoRepository.updateUbicacion(
          juego.localId!,
          enCajaBase: true,
        );
      } else if (result == 'sin_asignar') {
        await provider.juegoRepository.updateUbicacion(
          juego.localId!,
          ubicacionLocalId: null,
          enCajaBase: false,
        );
      } else if (result.startsWith('ubicacion:')) {
        final localId = int.parse(result.substring('ubicacion:'.length));
        await provider.juegoRepository.updateUbicacion(
          juego.localId!,
          ubicacionLocalId: localId,
          enCajaBase: false,
        );
      }
      SyncService().syncAll();
      await provider.refreshDetail();
    }
  }

  Future<bool?> _showCreateUbicacionFlow(BuildContext parentCtx) async {
    final provider = context.read<JuegosProvider>();
    final repo = provider.ubicacionRepository;
    final habitaciones = await repo.listHabitaciones();
    final muebles = await repo.listMuebles();

    if (habitaciones.isEmpty) {
      if (parentCtx.mounted) {
        ScaffoldMessenger.of(parentCtx).showSnackBar(
          const SnackBar(content: Text('Primero crea una habitación desde Ubicaciones')),
        );
      }
      return false;
    }
    if (muebles.isEmpty) {
      if (parentCtx.mounted) {
        ScaffoldMessenger.of(parentCtx).showSnackBar(
          const SnackBar(content: Text('Primero crea un mueble desde Ubicaciones')),
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
                  onRefresh: () async {
                    await provider.refreshDetail();
                    await _loadFaltantes();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                    children: [
                      _buildHeader(juego, theme),
                      const SizedBox(height: 20),
                      _buildInfoGrid(juego, theme),
                      if (juego.propietarios.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildPropietariosSection(juego, theme),
                      ],
                      if (juego.expansiones.isNotEmpty || _faltantes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _buildExpansionesSection(juego, theme),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildExpansionesSection(Juego juego, ThemeData theme) {
    final errorColor = theme.colorScheme.error;
    final total = juego.expansiones.length + _faltantes.length;
    final baseLocalId = juego.localId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expansiones ($total)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_faltantes.isNotEmpty)
              TextButton(
                onPressed: () => ExpansionFaltanteActions.ignorarTodas(
                  context,
                  expansiones: _faltantes,
                  onChanged: _loadFaltantes,
                ),
                child: const Text('Ignorar todas'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Column(
          children: [
          ...juego.expansiones.map(
            (exp) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension, size: 20),
              title: Text(exp.nombre, style: const TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.of(context)
                  .pushNamed('/juego', arguments: exp.localId),
            ),
          ),
          ..._faltantes.map(
            (exp) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.extension, size: 20, color: errorColor),
              title: Text(
                exp.nombre,
                style: TextStyle(fontSize: 14, color: errorColor),
              ),
              subtitle: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: errorColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Faltante',
                      style: TextStyle(
                        fontSize: 11,
                        color: errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (exp.anio != null) ...[
                    const SizedBox(width: 8),
                    Text('${exp.anio}', style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
              trailing: baseLocalId == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => ExpansionFaltanteActions.showMenu(
                        context,
                        expansion: exp,
                        juegoBaseLocalId: baseLocalId,
                        onChanged: _loadFaltantes,
                      ),
                    ),
            ),
          ),
          ],
        ),
      ],
    );
  }

  bool _isCompartido(Juego juego) {
    return juego.propietarios.length > 1 && !juego.variasCopias;
  }

  Widget _detailBadge(String label, Color? bgColor, Color? textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildHeaderBadges(Juego juego) {
    final badges = <Widget>[];
    final inBgg =
        context.watch<BggCollectionProvider>().isInBggCollection(juego.bggId);
    if (inBgg) {
      badges.add(_detailBadge('✓ En BGG', Colors.green[50], Colors.green[700]));
    }
    if (juego.esExpansion) {
      badges.add(_detailBadge('Expansi\u00f3n', Colors.blue[50], Colors.blue[700]));
    }
    if (juego.autojugable) {
      badges.add(
          _detailBadge('Autojugable', Colors.indigo[50], Colors.indigo[700]));
    }
    if (juego.sinAbrir) {
      badges.add(_detailBadge('Por estrenar', Colors.teal[50], Colors.teal[700]));
    }
    if (juego.printAndPlay) {
      badges.add(
          _detailBadge('Print and Play', Colors.brown[50], Colors.brown[700]));
    }
    return badges;
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
              Builder(builder: (_) {
                final badges = _buildHeaderBadges(juego);
                if (badges.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: badges,
                  ),
                );
              }),
              if (juego.descripcion != null &&
                  juego.descripcion!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(juego.descripcion!,
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13, height: 1.4)),
              ],
              if (juego.esExpansion &&
                  (juego.juegoBase != null || juego.juegoBaseLocalId != null)) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    final baseLocalId =
                        juego.juegoBase?.localId ?? juego.juegoBaseLocalId;
                    if (baseLocalId == null) return;
                    Navigator.of(context)
                        .pushNamed('/juego', arguments: baseLocalId);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 14,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                          'Juego base: ${juego.juegoBase?.nombre ?? 'Ver juego base'}',
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

  Widget _buildPropietariosSection(Juego juego, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Propietarios',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        if (_isCompartido(juego)) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: juego.propietarios
              .map((p) => Chip(label: Text(p.nombre)))
              .toList(),
        ),
      ],
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
  final VoidCallback? onTap;
  _InfoItem(this.label, this.value, this.icon, {this.onTap});
}

