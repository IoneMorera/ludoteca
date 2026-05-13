import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../models/juego.dart';
import '../widgets/game_image.dart';

class JuegosListScreen extends StatefulWidget {
  const JuegosListScreen({super.key});

  @override
  State<JuegosListScreen> createState() => _JuegosListScreenState();
}

class _JuegosListScreenState extends State<JuegosListScreen> {
  final _searchController = TextEditingController();
  SyncStatus? _lastSyncStatus;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<JuegosProvider>();
      provider.clearBusqueda();
      provider.fetchJuegos();
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                        if (juego.esExpansion)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Exp.',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (juego.categoria != null) ...[
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
