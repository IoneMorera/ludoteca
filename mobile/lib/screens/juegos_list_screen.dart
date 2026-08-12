import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart';
import '../data/categoria_repository.dart';
import '../providers/bgg_collection_provider.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../models/juego.dart';
import '../widgets/game_image.dart';

class JuegosListScreen extends StatefulWidget {
  final String? initialEstado;
  final bool? initialEsExpansion;
  final int? categoriaLocalId;
  final int? tipoFundaLocalId;
  final int? ubicacionLocalId;
  final VoidCallback? onBack;

  const JuegosListScreen({
    super.key,
    this.initialEstado,
    this.initialEsExpansion,
    this.categoriaLocalId,
    this.tipoFundaLocalId,
    this.ubicacionLocalId,
    this.onBack,
  });

  @override
  State<JuegosListScreen> createState() => _JuegosListScreenState();
}

class _JuegosListScreenState extends State<JuegosListScreen> {
  final _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;
  String? _estadoFilter;
  bool? _esExpansionFilter;
  int? _categoriaLocalId;
  int? _tipoFundaLocalId;
  int? _ubicacionLocalId;
  List<CategoriaRow> _categorias = [];
  String? _categoriaNombre;
  String? _tipoFundaNombre;
  String? _ubicacionNombre;

  @override
  void initState() {
    super.initState();
    _estadoFilter = widget.initialEstado;
    _esExpansionFilter = widget.initialEsExpansion;
    _categoriaLocalId = widget.categoriaLocalId;
    _tipoFundaLocalId = widget.tipoFundaLocalId;
    _ubicacionLocalId = widget.ubicacionLocalId;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<JuegosProvider>();
      provider.resetFilters();
      if (_estadoFilter != null ||
          _esExpansionFilter != null ||
          _categoriaLocalId != null ||
          _tipoFundaLocalId != null ||
          _ubicacionLocalId != null) {
        provider.setFilters(
          estado: _estadoFilter,
          esExpansion: _esExpansionFilter,
          categoriaLocalId: _categoriaLocalId,
          tipoFundaLocalId: _tipoFundaLocalId,
          ubicacionLocalId: _ubicacionLocalId,
        );
      }
      provider.fetchJuegos(
        estado: _estadoFilter,
        esExpansion: _esExpansionFilter,
        categoriaLocalId: _categoriaLocalId,
        tipoFundaLocalId: _tipoFundaLocalId,
        ubicacionLocalId: _ubicacionLocalId,
      );
      _lastSyncStatus = context.read<SyncProvider>().status;
      context.read<SyncProvider>().addListener(_onSyncChanged);
      _loadCategorias();
      _loadTipoFunda();
      _loadUbicacion();
    });
  }

  Future<void> _loadCategorias() async {
    final cats = await context.read<JuegosProvider>().categoriaRepository.getAll();
    if (mounted) {
      setState(() => _categorias = cats);
      if (_categoriaLocalId != null) {
        final match = cats.where((c) => c.localId == _categoriaLocalId);
        if (match.isNotEmpty) {
          setState(() => _categoriaNombre = match.first.nombre);
        }
      }
    }
  }

  Future<void> _loadTipoFunda() async {
    if (_tipoFundaLocalId == null) return;
    final tipo = await context
        .read<JuegosProvider>()
        .tipoFundaRepository
        .getByLocalId(_tipoFundaLocalId!);
    if (mounted && tipo != null) {
      setState(() => _tipoFundaNombre = tipo.nombre);
    }
  }

  Future<void> _loadUbicacion() async {
    if (_ubicacionLocalId == null) return;
    final ubic = await context
        .read<JuegosProvider>()
        .ubicacionRepository
        .getByLocalId(_ubicacionLocalId!);
    if (mounted && ubic != null) {
      setState(() => _ubicacionNombre = ubic.rutaCompleta);
    }
  }

  void _onSyncChanged() {
    if (!mounted) return;
    final syncStatus = context.read<SyncProvider>().status;
    if (_lastSyncStatus == SyncStatus.syncing && syncStatus == SyncStatus.idle) {
      context.read<JuegosProvider>().fetchJuegos();
    }
    _lastSyncStatus = syncStatus;
  }

  void _applyFilters() {
    final provider = context.read<JuegosProvider>();
    provider.setFilters(
      estado: _estadoFilter,
      esExpansion: _esExpansionFilter,
      categoriaLocalId: _categoriaLocalId,
      tipoFundaLocalId: _tipoFundaLocalId,
      ubicacionLocalId: _ubicacionLocalId,
    );
    provider.fetchJuegos(
      estado: _estadoFilter,
      esExpansion: _esExpansionFilter,
      categoriaLocalId: _categoriaLocalId,
      tipoFundaLocalId: _tipoFundaLocalId,
      ubicacionLocalId: _ubicacionLocalId,
    );
  }

  void _clearAllFilters() {
    setState(() {
      _estadoFilter = null;
      _esExpansionFilter = null;
      _categoriaLocalId = null;
      _categoriaNombre = null;
      _tipoFundaLocalId = null;
      _tipoFundaNombre = null;
      _ubicacionLocalId = null;
      _ubicacionNombre = null;
    });
    _applyFilters();
  }

  bool get _hasActiveFilters =>
      _estadoFilter != null ||
      _esExpansionFilter != null ||
      _categoriaLocalId != null ||
      _tipoFundaLocalId != null ||
      _ubicacionLocalId != null;

  Future<void> _confirmDelete(Juego juego) async {
    if (juego.localId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar juego'),
        content: Text(
          '¿Eliminar "${juego.nombre}"? Esta acción no se puede deshacer.',
        ),
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

    if (confirm != true || !mounted) return;

    try {
      await context.read<JuegosProvider>().deleteJuego(juego.localId!);
      SyncService().syncAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${juego.nombre}" eliminado')),
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

  void _showFilterSheet() {
    String? tempEstado = _estadoFilter;
    bool? tempEsExpansion = _esExpansionFilter;
    int? tempCategoriaId = _categoriaLocalId;
    String? tempCategoriaNombre = _categoriaNombre;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Filtros',
                              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                tempEstado = null;
                                tempEsExpansion = null;
                                tempCategoriaId = null;
                                tempCategoriaNombre = null;
                              });
                            },
                            child: const Text('Limpiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Estado',
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: tempEstado == null,
                            onSelected: (_) => setSheetState(() => tempEstado = null),
                          ),
                          ChoiceChip(
                            label: Text('Disponible',
                                style: TextStyle(
                                    color: tempEstado == 'disponible'
                                        ? Colors.green[800]
                                        : null,
                                    fontWeight: tempEstado == 'disponible'
                                        ? FontWeight.w600
                                        : null)),
                            selected: tempEstado == 'disponible',
                            selectedColor: Colors.green[100],
                            avatar: tempEstado == 'disponible'
                                ? Icon(Icons.check_circle,
                                    size: 18, color: Colors.green[700])
                                : null,
                            onSelected: (_) =>
                                setSheetState(() => tempEstado = 'disponible'),
                          ),
                          ChoiceChip(
                            label: Text('En venta',
                                style: TextStyle(
                                    color: tempEstado == 'en_venta'
                                        ? Colors.orange[900]
                                        : null,
                                    fontWeight: tempEstado == 'en_venta'
                                        ? FontWeight.w600
                                        : null)),
                            selected: tempEstado == 'en_venta',
                            selectedColor: Colors.orange[100],
                            avatar: tempEstado == 'en_venta'
                                ? Icon(Icons.sell,
                                    size: 18, color: Colors.orange[800])
                                : null,
                            onSelected: (_) =>
                                setSheetState(() => tempEstado = 'en_venta'),
                          ),
                          ChoiceChip(
                            label: Text('Vendido',
                                style: TextStyle(
                                    color: tempEstado == 'vendido'
                                        ? Colors.red[800]
                                        : null,
                                    fontWeight: tempEstado == 'vendido'
                                        ? FontWeight.w600
                                        : null)),
                            selected: tempEstado == 'vendido',
                            selectedColor: Colors.red[100],
                            avatar: tempEstado == 'vendido'
                                ? Icon(Icons.do_not_disturb_on,
                                    size: 18, color: Colors.red[700])
                                : null,
                            onSelected: (_) =>
                                setSheetState(() => tempEstado = 'vendido'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Tipo de juego',
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: tempEsExpansion == null,
                            onSelected: (_) =>
                                setSheetState(() => tempEsExpansion = null),
                          ),
                          ChoiceChip(
                            label: Text('Base',
                                style: TextStyle(
                                    color: tempEsExpansion == false
                                        ? Colors.indigo[800]
                                        : null,
                                    fontWeight: tempEsExpansion == false
                                        ? FontWeight.w600
                                        : null)),
                            selected: tempEsExpansion == false,
                            selectedColor: Colors.indigo[100],
                            avatar: tempEsExpansion == false
                                ? Icon(Icons.casino,
                                    size: 18, color: Colors.indigo[700])
                                : null,
                            onSelected: (_) =>
                                setSheetState(() => tempEsExpansion = false),
                          ),
                          ChoiceChip(
                            label: Text('Expansión',
                                style: TextStyle(
                                    color: tempEsExpansion == true
                                        ? Colors.purple[800]
                                        : null,
                                    fontWeight: tempEsExpansion == true
                                        ? FontWeight.w600
                                        : null)),
                            selected: tempEsExpansion == true,
                            selectedColor: Colors.purple[100],
                            avatar: tempEsExpansion == true
                                ? Icon(Icons.extension,
                                    size: 18, color: Colors.purple[700])
                                : null,
                            onSelected: (_) =>
                                setSheetState(() => tempEsExpansion = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Categoría',
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: tempCategoriaId == null,
                            onSelected: (_) => setSheetState(() {
                              tempCategoriaId = null;
                              tempCategoriaNombre = null;
                            }),
                          ),
                          ..._categorias.map((cat) => ChoiceChip(
                                label: Text(cat.nombre),
                                selected: tempCategoriaId == cat.localId,
                                onSelected: (_) => setSheetState(() {
                                  tempCategoriaId = cat.localId;
                                  tempCategoriaNombre = cat.nombre;
                                }),
                              )),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _estadoFilter = tempEstado;
                            _esExpansionFilter = tempEsExpansion;
                            _categoriaLocalId = tempCategoriaId;
                            _categoriaNombre = tempCategoriaNombre;
                          });
                          _applyFilters();
                        },
                        child: const Text('Aplicar filtros'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    context.read<SyncProvider>().removeListener(_onSyncChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JuegosProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_categoriaNombre ?? 'Juegos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.of(context).pushNamed('/juego/nuevo');
          if (created == true && context.mounted) {
            provider.fetchJuegos();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar juegos...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                provider.fetchJuegos(buscar: '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      provider.fetchJuegos(buscar: value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: _hasActiveFilters,
                  child: IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: _showFilterSheet,
                    tooltip: 'Filtros',
                  ),
                ),
              ],
            ),
          ),
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._buildActiveFilterChips(),
                    const SizedBox(width: 4),
                    ActionChip(
                      avatar: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Limpiar'),
                      onPressed: _clearAllFilters,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          if (provider.loading && provider.juegos.isEmpty)
            const Expanded(
                child: Center(child: CircularProgressIndicator()))
          else if (provider.juegos.isEmpty)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.casino, size: 64, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No se encontraron juegos',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => provider.fetchJuegos(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: provider.juegos.length + 1,
                  itemBuilder: (context, index) {
                    if (index == provider.juegos.length) {
                      return _buildPagination(provider);
                    }
                    return _buildJuegoCard(context, provider.juegos[index]);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildActiveFilterChips() {
    final chips = <Widget>[];
    if (_estadoFilter != null) {
      String label;
      Color color;
      Color textColor;
      IconData icon;
      switch (_estadoFilter) {
        case 'disponible':
          label = 'Disponible';
          color = Colors.green[100]!;
          textColor = Colors.green[800]!;
          icon = Icons.check_circle;
          break;
        case 'en_venta':
          label = 'En venta';
          color = Colors.orange[100]!;
          textColor = Colors.orange[900]!;
          icon = Icons.sell;
          break;
        case 'vendido':
          label = 'Vendido';
          color = Colors.red[100]!;
          textColor = Colors.red[800]!;
          icon = Icons.do_not_disturb_on;
          break;
        default:
          label = _estadoFilter!;
          color = Colors.grey[200]!;
          textColor = Colors.grey[800]!;
          icon = Icons.info;
      }
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
          avatar: Icon(icon, size: 16, color: textColor),
          backgroundColor: color,
          onDeleted: () {
            setState(() => _estadoFilter = null);
            _applyFilters();
          },
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    if (_esExpansionFilter != null) {
      final isExp = _esExpansionFilter!;
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(isExp ? 'Expansión' : 'Base',
              style: TextStyle(
                  color: isExp ? Colors.purple[800] : Colors.indigo[800],
                  fontWeight: FontWeight.w600)),
          avatar: Icon(isExp ? Icons.extension : Icons.casino,
              size: 16, color: isExp ? Colors.purple[700] : Colors.indigo[700]),
          backgroundColor: isExp ? Colors.purple[100] : Colors.indigo[100],
          onDeleted: () {
            setState(() => _esExpansionFilter = null);
            _applyFilters();
          },
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    if (_categoriaLocalId != null) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(_categoriaNombre ?? 'Categoría',
              style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.w600)),
          avatar: Icon(Icons.category, size: 16, color: Colors.teal[700]),
          backgroundColor: Colors.teal[100],
          onDeleted: () {
            setState(() {
              _categoriaLocalId = null;
              _categoriaNombre = null;
            });
            _applyFilters();
          },
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    if (_tipoFundaLocalId != null) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(_tipoFundaNombre ?? 'Funda',
              style: TextStyle(
                  color: Colors.deepOrange[800], fontWeight: FontWeight.w600)),
          avatar:
              Icon(Icons.style, size: 16, color: Colors.deepOrange[700]),
          backgroundColor: Colors.deepOrange[100],
          onDeleted: () {
            setState(() {
              _tipoFundaLocalId = null;
              _tipoFundaNombre = null;
            });
            _applyFilters();
          },
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    if (_ubicacionLocalId != null) {
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(_ubicacionNombre ?? 'Ubicación',
              style: TextStyle(
                  color: Colors.brown[800], fontWeight: FontWeight.w600)),
          avatar: Icon(Icons.location_on, size: 16, color: Colors.brown[700]),
          backgroundColor: Colors.brown[100],
          onDeleted: () {
            setState(() {
              _ubicacionLocalId = null;
              _ubicacionNombre = null;
            });
            _applyFilters();
          },
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    return chips;
  }

  Widget _buildJuegoCard(BuildContext context, Juego juego) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context)
            .pushNamed('/juego', arguments: juego.localId ?? juego.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                children: [
                  GameImage(
                    juego: juego,
                    width: 56,
                    height: 56,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  if (context
                      .watch<BggCollectionProvider>()
                      .isInBggCollection(juego.bggId))
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade600,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(juego.nombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (juego.categorias.isNotEmpty) ...[
                          Icon(Icons.category,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                                juego.categorias.map((c) => c.nombre).join(', '),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 12),
                        ] else if (juego.categoria != null) ...[
                          Icon(Icons.category,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(juego.categoria!.nombre,
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Icon(Icons.people,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text(juego.jugadoresTexto,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                    Builder(builder: (_) {
                      final badges = _buildBadges(juego);
                      if (badges.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: badges,
                        ),
                      );
                    }),
                    if (juego.fundas.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: juego.fundas.take(2).map((funda) {
                          final color = funda.enfundadas
                              ? Colors.green
                              : Colors.orange;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${funda.cantidadCartas} ${funda.enfundadas ? 'enfundadas' : 'faltan'}',
                              style: TextStyle(
                                color: color[700],
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'delete') _confirmDelete(juego);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color? bgColor, Color? textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: textColor, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildBadges(Juego juego) {
    final badges = <Widget>[];
    final inBgg = context.watch<BggCollectionProvider>().isInBggCollection(juego.bggId);
    if (inBgg) {
      badges.add(_badge('✓ BGG', Colors.green[50], Colors.green[700]));
    }
    if (juego.propietarios.length > 1 && !juego.variasCopias) {
      badges.add(_badge('Compartido', Colors.lightBlue[50], Colors.lightBlue[700]));
    }
    if (juego.esExpansion) {
      badges.add(_badge('Exp.', Colors.purple[50], Colors.purple[700]));
    }
    if (juego.autojugable) {
      badges.add(_badge('Autojugable', Colors.indigo[50], Colors.indigo[700]));
    }
    if (juego.sinAbrir) {
      badges.add(_badge('Por estrenar', Colors.teal[50], Colors.teal[700]));
    }
    if (juego.printAndPlay) {
      badges.add(_badge('P&P', Colors.brown[50], Colors.brown[700]));
    }
    final estado = juego.estado;
    switch (estado) {
      case 'disponible':
        badges.add(_badge('Disponible', Colors.green[50], Colors.green[700]));
        break;
      case 'en_venta':
        badges.add(_badge('En venta', Colors.orange[50], Colors.orange[700]));
        break;
      case 'vendido':
        badges.add(_badge('Vendido', Colors.red[50], Colors.red[700]));
        break;
    }
    return badges;
  }

  Widget _buildPagination(JuegosProvider provider) {
    if (provider.lastPage <= 1) return const SizedBox(height: 16);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: provider.currentPage > 1
                ? () => provider.fetchJuegos(page: provider.currentPage - 1)
                : null,
          ),
          Text('${provider.currentPage} / ${provider.lastPage}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: provider.currentPage < provider.lastPage
                ? () => provider.fetchJuegos(page: provider.currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
