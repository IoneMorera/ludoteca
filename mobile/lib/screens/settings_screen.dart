import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion = '${info.version}+${info.buildNumber}');
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '?');
    }
  }

  Future<void> _editServerUrl() async {
    final ctrl = TextEditingController(text: ApiConfig.serverUrl);
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Servidor API'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'URL del servidor',
                  border: const OutlineInputBorder(),
                  hintText: ApiConfig.defaultServerUrl,
                  helperText: 'Ej: http://192.168.1.100:8000',
                  helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                autofocus: true,
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
                      final url = ctrl.text.trim();
                      if (url.isEmpty) return;
                      setDialogState(() => saving = true);
                      await ApiConfig.setServerUrl(url);
                      ApiService().updateBaseUrl(url);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL del servidor actualizada. Cierra sesión para aplicar los cambios completamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      auth.userName.isNotEmpty
                          ? auth.userName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(auth.userName,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(auth.user?['email'] ?? '',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Mi perfil'),
            subtitle: const Text('Nombre, usuario BGG y preferencias'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/profile'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Categorías'),
            subtitle: const Text('Gestiona las categorías de juegos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/categorias'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Propietarios'),
            subtitle: const Text('Gestiona los propietarios de juegos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/propietarios'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.location_on),
            title: const Text('Ubicaciones'),
            subtitle: const Text('Habitaciones, muebles y estantes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/ubicaciones'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sports_esports),
            title: const Text('Planificar partida'),
            subtitle: const Text('Busca juegos por jugadores y edad'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/game-night'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('BGG'),
            subtitle: const Text('Importar desde BoardGameGeek'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/bgg'),
          ),
          const Divider(),
          Consumer<SyncProvider>(
            builder: (context, sync, _) {
              final s = sync.snapshot;
              final String subtitle;
              if (s.status == SyncStatus.syncing) {
                subtitle = 'Sincronizando...';
              } else if (s.lastError != null) {
                subtitle = 'Ultimo error: ${s.lastError}';
              } else if (s.lastSyncedAt != null) {
                final hora =
                    '${s.lastSyncedAt!.hour.toString().padLeft(2, '0')}:${s.lastSyncedAt!.minute.toString().padLeft(2, '0')}';
                final pending = s.pendingOps > 0
                    ? '  -  ${s.pendingOps} pendientes'
                    : '';
                subtitle = 'Sincronizado a las $hora$pending';
              } else {
                subtitle = 'Sin sincronizar todavia';
              }
              return ListTile(
                leading: Icon(
                  s.status == SyncStatus.error
                      ? Icons.sync_problem
                      : Icons.sync,
                  color: s.status == SyncStatus.error ? Colors.red : null,
                ),
                title: const Text('Sincronizacion'),
                subtitle: Text(subtitle),
                trailing: s.status == SyncStatus.syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onTap: s.status == SyncStatus.syncing
                    ? null
                    : () => sync.syncNow(fullPull: true),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servidor API'),
            subtitle: Text(ApiConfig.serverUrl,
                style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.edit_outlined, size: 20),
            onTap: _editServerUrl,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Versión'),
            subtitle: Text(_appVersion.isEmpty ? '…' : _appVersion),
          ),
          const SizedBox(height: 32),
          FilledButton.tonalIcon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

}
