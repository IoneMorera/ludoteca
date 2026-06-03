import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../models/juego.dart';
import '../widgets/game_image.dart';

class JuegosListScreen extends StatefulWidget {
  final String? initialEstado;
  final bool? initialEsExpansion;
  final int? categoriaLocalId;

  const JuegosListScreen({super.key, this.initialEstado, this.initialEsExpansion, this.categoriaLocalId});

  @override
  State<JuegosListScreen> createState() => _JuegosListScreenState();
}

class _JuegosListScreenState extends State<JuegosListScreen> {
  final _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;
  String? _estadoFilter;
  bool? _esExpansionFilter;
  int? _categoriaLocalId;

  bool get _isStandaloneRoute =>
      widget.initialEstado != null ||
      widget.initialEsExpansion != null ||
      widget.categoriaLocalId != null;

  @override
  void initState() {
    super.initState();
    _estadoFilter = widget.initialEstado;
    _esExpansionFilter = widget.initialEsExpansion;
    _categoriaLocalId = widget.categoriaLocalId;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<JuegosProvider>();
      provider.clearBusqueda();
      provider.setFilters(estado: _estadoFilter, esExpansion: _esExpansionFilter);
      provider.fetchJuegos(estado: _estadoFilter, esExpansion: _esExpansionFilter, categoriaLocalId: _categoriaLocalId);
      _lastSyncStatus = context.read<SyncProvider>().status;
      context.read<SyncProvider>().addListener(_onSyncChanged);
    });
  }

  void _onSyncChanged() {
    if (!mounted) return;
    final syncStatus = context.read<SyncProvider>().status;
    if (_lastSyncStatus == SyncStatus.syncing && syncStatus == SyncStatus.idle) {
      context.read<JuegosProvider>().fetchJuegos();
    }
    _lastSyncStatus = syncStatus;
  }

  void _applyFilter(String? estado, bool? esExpansion) {
    setState(() {
      _estadoFilter = estado;
      _esExpansionFilter = esExpansion;
    });
    final provider = context.read<JuegosProvider>();
    provider.setFilters(estado: estado, esExpansion: esExpansion);
    provider.fetchJuegos(estado: estado, esExpansion: esExpansion);
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
      appBar: _isStandaloneRoute
          ? AppBar(
              title: const Text('Juegos'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
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
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar juegos...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Todos'),
                    selected: _estadoFilter == null && _esExpansionFilter == null,
                    onSelected: (_) => _applyFilter(null, null),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Disponible'),
                    selected: _estadoFilter == 'disponible',
                    selectedColor: Colors.green[100],
                    onSelected: (_) => _applyFilter('disponible', null),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('En venta'),
                    selected: _estadoFilter == 'en_venta',
                    selectedColor: Colors.orange[100],
                    onSelected: (_) => _applyFilter('en_venta', null),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Vendido'),
                    selected: _estadoFilter == 'vendido',
                    selectedColor: Colors.red[100],
                    onSelected: (_) => _applyFilter('vendido', null),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Expansiones'),
                    selected: _esExpansionFilter == true,
                    selectedColor: Colors.purple[100],
                    onSelected: (_) => _applyFilter(null, true),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Juegos base'),
                    selected: _esExpansionFilter == false,
                    onSelected: (_) => _applyFilter(null, false),
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
              GameImage(
                juego: juego,
                width: 56,
                height: 56,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(juego.nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                        ),
                        ..._buildBadges(juego),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (juego.categorias.isNotEmpty) ...[
                          Icon(Icons.category,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(juego.categorias.map((c) => c.nombre).join(', '),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(width: 12),
                        ] else if (juego.categoria != null) ...[
                          Icon(Icons.category,
                              size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(juego.categoria!.nombre,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
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
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBadges(Juego juego) {
    final badges = <Widget>[];
    if (juego.propietarios.length > 1 && !juego.variasCopias) {
      badges.add(Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.lightBlue[50],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('Compartido',
            style: TextStyle(
                fontSize: 11,
                color: Colors.lightBlue[700],
                fontWeight: FontWeight.w600)),
      ));
    }
    if (juego.esExpansion) {
      badges.add(Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple[50],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('Exp.',
            style: TextStyle(
                fontSize: 11,
                color: Colors.purple[700],
                fontWeight: FontWeight.w600)),
      ));
    }
    final estado = juego.estado;
    Color? badgeColor;
    Color? textColor;
    String? label;
    switch (estado) {
      case 'disponible':
        badgeColor = Colors.green[50];
        textColor = Colors.green[700];
        label = 'Disponible';
        break;
      case 'en_venta':
        badgeColor = Colors.orange[50];
        textColor = Colors.orange[700];
        label = 'En venta';
        break;
      case 'vendido':
        badgeColor = Colors.red[50];
        textColor = Colors.red[700];
        label = 'Vendido';
        break;
    }
    if (label != null) {
      badges.add(Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: textColor,
                fontWeight: FontWeight.w600)),
      ));
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
