import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../data/sync_verify_service.dart';
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

  Future<void> _verifySyncIntegrity() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Verificando integridad...')),
          ],
        ),
      ),
    );

    final result = await SyncVerifyService().verify();

    if (!mounted) return;
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.isFullySync ? Icons.check_circle : Icons.warning_amber,
              color: result.isFullySync ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.isFullySync
                    ? 'Todo sincronizado'
                    : 'Discrepancias detectadas',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _buildVerifyContent(result),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyContent(SyncVerifyResult result) {
    if (result.error != null) {
      return Text(
        'Error al verificar: ${result.error}',
        style: const TextStyle(color: Colors.red),
      );
    }

    final items = <Widget>[];

    if (result.outboxPending > 0) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const Icon(Icons.outbox, size: 18, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              '${result.outboxPending} operaciones pendientes en outbox',
              style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.blue),
            ),
          ],
        ),
      ));
    }

    for (final table in result.tables) {
      final isOk = table.isOk;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isOk ? Icons.check : Icons.error_outline,
                    size: 16,
                    color: isOk ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatTableName(table.tableName),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isOk ? null : Colors.orange[800],
                      ),
                    ),
                  ),
                  Text(
                    '${table.localCount}/${table.remoteCount}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isOk ? Colors.grey : Colors.orange[800],
                    ),
                  ),
                ],
              ),
              if (!isOk) ...[
                if (table.missingInLocal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      'Faltan en local (IDs): ${_formatIds(table.missingInLocal)}',
                      style: TextStyle(fontSize: 11, color: Colors.red[700]),
                    ),
                  ),
                if (table.missingInRemote.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      'Faltan en servidor (IDs): ${_formatIds(table.missingInRemote)}',
                      style: TextStyle(fontSize: 11, color: Colors.red[700]),
                    ),
                  ),
                if (table.dataDiffs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${table.dataDiffs.length} registro(s) con datos distintos:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange[800]),
                        ),
                        ...table.dataDiffs.take(10).map((rd) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rd.recordName != null
                                    ? 'ID ${rd.serverId} (${rd.recordName})'
                                    : 'ID ${rd.serverId}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                              ),
                              ...rd.diffs.take(5).map((d) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '${d.field}: local="${d.localValue}" vs servidor="${d.remoteValue}"',
                                  style: TextStyle(fontSize: 10, color: Colors.red[600]),
                                ),
                              )),
                              if (rd.diffs.length > 5)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    '... +${rd.diffs.length - 5} campos más',
                                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  ),
                                ),
                            ],
                          ),
                        )),
                        if (table.dataDiffs.length > 10)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '... +${table.dataDiffs.length - 10} registros más',
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (table.pendingCreates > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      '${table.pendingCreates} creates pendientes de subir',
                      style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                    ),
                  ),
                if (table.pendingDeletes > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 22, top: 2),
                    child: Text(
                      '${table.pendingDeletes} deletes pendientes de subir',
                      style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      ),
    );
  }

  String _formatTableName(String name) {
    return name.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'^[a-z]'),
          (m) => m.group(0)!.toUpperCase(),
        );
  }

  String _formatIds(List<int> ids) {
    if (ids.length <= 5) return ids.join(', ');
    return '${ids.take(5).join(', ')} ... (+${ids.length - 5} más)';
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
                onTap: () => sync.syncNow(fullPull: true),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Verificar integridad'),
            subtitle: const Text('Compara datos locales con el servidor'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _verifySyncIntegrity,
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
