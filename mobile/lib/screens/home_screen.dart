import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../config/app_environment.dart';
import '../models/evento.dart';
import '../providers/auth_provider.dart';
import '../providers/eventos_provider.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SyncStatus? _lastSyncStatus;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      context.read<JuegosProvider>().fetchStats();
      context.read<EventosProvider>().fetchEventosResumen();
      _lastSyncStatus = context.read<SyncProvider>().status;
      context.read<SyncProvider>().addListener(_onSyncChanged);
    });
  }

  void _onSyncChanged() {
    if (!mounted) return;
    final syncStatus = context.read<SyncProvider>().status;
    if (_lastSyncStatus == SyncStatus.syncing && syncStatus == SyncStatus.idle) {
      context.read<JuegosProvider>().fetchStats();
      context.read<EventosProvider>().fetchEventosResumen();
    }
    _lastSyncStatus = syncStatus;
  }

  @override
  void dispose() {
    context.read<SyncProvider>().removeListener(_onSyncChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final juegosProvider = context.watch<JuegosProvider>();
    final eventosProvider = context.watch<EventosProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final stats = juegosProvider.stats;
    final fundasFaltantes = _asList(
      stats['fundasFaltantes'] ?? stats['fundas_faltantes'],
    );
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
        onRefresh: () async {
          final eventos = context.read<EventosProvider>();
          await syncProvider.syncNow();
          if (!context.mounted) return;
          await juegosProvider.fetchStats();
          await eventos.fetchEventosResumen();
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Hola, ${auth.userName}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text('Tu ludoteca en un vistazo',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey[600])),
            if (syncProvider.isSyncing) ...[
              const SizedBox(height: 8),
              _buildSyncBanner(theme),
            ],
            const SizedBox(height: 24),
            _buildStatsGrid(stats, theme, eventosProvider.totalEventosResumen),
            if (eventosProvider.eventosPendientesCount > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Eventos pendientes',
                subtitulo:
                    '${eventosProvider.eventosPendientesCount} eventos por colocar',
                icon: Icons.event_busy,
                color: Colors.amber,
                onTap: () => Navigator.of(context).pushNamed(
                  '/eventos',
                  arguments: {'initialTab': 1},
                ),
              ),
            ] else if (eventosProvider.proximoEvento != null) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Próximo evento',
                subtitulo: _proximoEventoSubtitulo(eventosProvider.proximoEvento!),
                icon: Icons.event,
                color: Colors.blue,
                onTap: () => Navigator.of(context).pushNamed(
                  '/evento',
                  arguments: eventosProvider.proximoEvento!.localId,
                ),
              ),
            ],
            if (!auth.noEnfundo && fundasFaltantes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildFundasFaltantesCard(fundasFaltantes, theme),
            ],
            if (!auth.ocultarPorEstrenar &&
                _asInt(stats['juegosPorEstrenar']) > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Juegos Por Estrenar',
                subtitulo:
                    '${_asInt(stats['juegosPorEstrenar'])} juegos sin abrir',
                icon: Icons.card_giftcard,
                color: Colors.teal,
                route: '/juegos-por-estrenar',
              ),
            ],
            if (!auth.ocultarFaltanTraduccion &&
                _asInt(stats['juegosFaltanTraduccion']) > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Faltan Traducciones',
                subtitulo:
                    '${_asInt(stats['juegosFaltanTraduccion'])} juegos por tradumaquetar',
                icon: Icons.translate,
                color: Colors.indigo,
                route: '/faltan-traducciones',
              ),
            ],
            if (!auth.ocultarExpansionOtroIdioma &&
                _asInt(stats['juegosExpansionOtroIdioma']) > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Expansiones en Otro Idioma',
                subtitulo:
                    '${_asInt(stats['juegosExpansionOtroIdioma'])} juegos con expansiones en otro idioma',
                icon: Icons.language,
                color: Colors.deepOrange,
                route: '/expansiones-otro-idioma',
              ),
            ],
            if (!auth.ocultarPorColocar &&
                _asInt(stats['juegosPorColocar']) > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Juegos por Colocar',
                subtitulo:
                    '${_asInt(stats['juegosPorColocar'])} juegos sin ubicación',
                icon: Icons.inventory_2_outlined,
                color: Colors.brown,
                route: '/juegos-por-colocar',
              ),
            ],
            if (!auth.ocultarNuevasExpansiones &&
                _asInt(stats['expansionesNuevas']) > 0) ...[
              const SizedBox(height: 16),
              _buildAvisoCard(
                titulo: 'Nuevas expansiones',
                subtitulo:
                    '${_asInt(stats['expansionesNuevas'])} expansiones BGG recientes',
                icon: Icons.new_releases_outlined,
                color: Colors.red,
                route: '/nuevas-expansiones',
              ),
            ],
            const SizedBox(height: 28),
            Text('Acciones rápidas',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildQuickActions(context, theme),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSyncBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Sincronizando con la nube...',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildFundasFaltantesCard(
    List<dynamic> fundasFaltantes,
    ThemeData theme,
  ) {
    final total = fundasFaltantes.fold<int>(0, (sum, item) {
      final funda = _asMap(item);
      return sum + _asInt(funda['cantidad_total']);
    });

    return Card(
      elevation: 0,
      color: Colors.orange.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.15),
          child: const Icon(Icons.style, color: Colors.orange),
        ),
        title: const Text(
          'Faltan Fundas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '$total fundas pendientes en ${fundasFaltantes.length} tamaños',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed('/fundas-faltantes'),
      ),
    );
  }

  String _proximoEventoSubtitulo(Evento evento) {
    final inicio = evento.fechaInicio;
    final fecha =
        '${inicio.day.toString().padLeft(2, '0')}/${inicio.month.toString().padLeft(2, '0')}/${inicio.year}';
    return '${evento.nombre} · $fecha';
  }

  Widget _buildAvisoCard({
    required String titulo,
    required String subtitulo,
    required IconData icon,
    required Color color,
    String? route,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ??
            (route != null
                ? () => Navigator.of(context).pushNamed(route)
                : null),
      ),
    );
  }

  void _navigateToJuegos({String? estado, bool? esExpansion}) {
    Navigator.of(context).pushNamed('/juegos', arguments: {
      'estado': estado,
      'esExpansion': esExpansion,
    });
  }

  Widget _buildStatsGrid(
    Map<String, dynamic> stats,
    ThemeData theme,
    int totalEventos,
  ) {
    final items = [
      _StatItem('Juegos', '${stats['totalJuegos'] ?? 0}', Icons.casino,
          Colors.blue, () => _navigateToJuegos()),
      _StatItem('Disponibles', '${stats['juegosDisponibles'] ?? 0}',
          Icons.check_circle, Colors.green, () => _navigateToJuegos(estado: 'disponible')),
      _StatItem('En venta', '${stats['juegosEnVenta'] ?? 0}',
          Icons.sell, Colors.orange, () => _navigateToJuegos(estado: 'en_venta')),
      _StatItem('Vendidos', '${stats['juegosVendidos'] ?? 0}',
          Icons.money_off, Colors.red, () => _navigateToJuegos(estado: 'vendido')),
      _StatItem('Expansiones', '${stats['totalExpansiones'] ?? 0}',
          Icons.extension, Colors.purple, () => _navigateToJuegos(esExpansion: true)),
      _StatItem('Eventos', '$totalEventos', Icons.event,
          Colors.teal, () => Navigator.of(context).pushNamed('/eventos')),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: items.map((item) {
        return GestureDetector(
          onTap: item.onTap,
          child: Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: item.color.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(item.icon, color: item.color, size: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: item.color,
                          )),
                      Text(item.label,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuickActions(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.camera_alt,
          title: 'Reconocer por foto',
          subtitle: 'Identifica un juego con la cámara',
          color: Colors.teal,
          onTap: () => Navigator.of(context).pushNamed('/recognize'),
        ),
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.add_circle_outline,
          title: 'Añadir juego',
          subtitle: 'Crea un juego nuevo manualmente',
          color: Colors.indigo,
          onTap: () async {
            final saved =
                await Navigator.of(context).pushNamed('/juego/nuevo');
            if (saved == true && context.mounted) {
              context.read<JuegosProvider>().fetchStats();
            }
          },
        ),
        if (AppEnvironment.isDev) ...[
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.casino,
            title: 'Planificar partida',
            subtitle: 'Busca el juego perfecto para hoy',
            color: Colors.deepPurple,
            onTap: () => Navigator.of(context).pushNamed('/game-night'),
          ),
        ],
      ],
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  return [];
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

class _StatItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  _StatItem(this.label, this.value, this.icon, this.color, [this.onTap]);
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
