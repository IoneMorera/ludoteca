import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/juegos_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      context.read<JuegosProvider>().fetchStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final juegosProvider = context.watch<JuegosProvider>();
    final stats = juegosProvider.stats;
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => juegosProvider.fetchStats(),
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
            const SizedBox(height: 24),
            _buildStatsGrid(stats, theme),
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
          icon: Icons.qr_code_scanner,
          title: 'Escanear juego',
          subtitle: 'Añade un juego escaneando su código',
          color: Colors.teal,
          onTap: () => Navigator.of(context).pushNamed('/scanner'),
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
