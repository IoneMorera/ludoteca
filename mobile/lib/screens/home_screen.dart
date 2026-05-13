import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../providers/auth_provider.dart';
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
      _lastSyncStatus = context.read<SyncProvider>().status;
      context.read<SyncProvider>().addListener(_onSyncChanged);
    });
  }

  void _onSyncChanged() {
    if (!mounted) return;
    final syncStatus = context.read<SyncProvider>().status;
    if (_lastSyncStatus == SyncStatus.syncing && syncStatus == SyncStatus.idle) {
      context.read<JuegosProvider>().fetchStats();
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
    final syncProvider = context.watch<SyncProvider>();
    final stats = juegosProvider.stats;
    final fundasFaltantes = _asList(
      stats['fundasFaltantes'] ?? stats['fundas_faltantes'],
    );
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await syncProvider.syncNow();
          await juegosProvider.fetchStats();
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
            _buildStatsGrid(stats, theme),
            if (!auth.noEnfundo && fundasFaltantes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildFundasFaltantesCard(fundasFaltantes, theme),
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

  Widget _buildStatsGrid(Map<String, dynamic> stats, ThemeData theme) {
    final items = [
      _StatItem('Juegos', '${stats['totalJuegos'] ?? 0}', Icons.casino,
          Colors.blue),
      _StatItem('Disponibles', '${stats['juegosDisponibles'] ?? 0}',
          Icons.check_circle, Colors.green),
      _StatItem('Expansiones', '${stats['totalExpansiones'] ?? 0}',
          Icons.extension, Colors.orange),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.95,
      children: items.map((item) {
        return Card(
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
        const SizedBox(height: 8),
        _ActionTile(
          icon: Icons.casino,
          title: 'Planificar partida',
          subtitle: 'Busca el juego perfecto para hoy',
          color: Colors.deepPurple,
          onTap: () => Navigator.of(context).pushNamed('/game-night'),
        ),
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
  _StatItem(this.label, this.value, this.icon, this.color);
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
