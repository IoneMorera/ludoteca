import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../data/sync_service.dart' show SyncStatus;
import '../data/bgg_expansion_scan_service.dart';
import '../data/sync_verify_service.dart';
import '../providers/auth_provider.dart';
import '../providers/juegos_provider.dart';
import '../providers/sync_provider.dart';
import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  bool get _isDev => AppEnvironment.isDev;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '?');
    }
  }

  Future<void> _showExpansionScanMenu() async {
    final modo = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Escaneo rápido'),
              subtitle: const Text(
                'Revisa juegos nuevos y los que llevan más tiempo sin comprobar',
              ),
              onTap: () => Navigator.pop(ctx, 'incremental'),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Escaneo completo'),
              subtitle: const Text(
                'Revisa todo el catálogo; puede tardar varios minutos',
              ),
              onTap: () => Navigator.pop(ctx, 'completo'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || modo == null) return;
    await _scanBggExpansions(modo: modo);
  }

  Future<void> _scanBggExpansions({required String modo}) async {
    if (!mounted) return;

    final progreso = ValueNotifier<String>('Comprobando expansiones BGG...');

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progreso,
                builder: (_, mensaje, _) => Text(mensaje),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await BggExpansionScanService().runScan(
        modo: modo,
        onProgress: (mensaje) => progreso.value = mensaje,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final juegos = context.read<JuegosProvider>();
        Navigator.of(context).pop();
        await juegos.fetchStats();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Comprobación de expansiones completada'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mensajeErrorEscaneo(e))),
        );
      }
    }
  }

  String _mensajeErrorEscaneo(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        // Cada lote comprobado queda guardado, así que reintentar no repite trabajo.
        return 'BGG tardó demasiado en responder. Reinténtalo: el escaneo '
            'continuará donde se quedó.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'No se pudo conectar con el servidor.';
      }
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return 'Error al comprobar expansiones: $e';
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

  Future<void> _cloneProdDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clonar BBDD de producción'),
        content: const Text(
          'Se sustituirán todos los datos locales de esta app Dev por una copia de la BBDD local de Ludoteca (prod).\n\n'
          'La sesión y la URL del servidor no cambian. La app se cerrará al terminar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clonar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Clonando BBDD de producción...')),
          ],
        ),
      ),
    );

    String? error;
    try {
      await DatabaseService().close();
      const channel = MethodChannel('com.ludoteca.ludoteca_mobile/db_clone');
      await channel.invokeMethod('cloneFromProd');
    } on PlatformException catch (e) {
      error = switch (e.code) {
        'prod_not_installed' =>
          'No está instalada la app de producción (Ludoteca).',
        'no_database' =>
          'La app de producción no tiene BBDD local todavía.',
        'permission_denied' =>
          'No se pudo acceder a la BBDD de producción. Reinstala ambas apps firmadas con la misma clave.',
        _ => e.message ?? 'No se pudo clonar la BBDD.',
      };
    } catch (e) {
      error = e.toString();
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (error != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No se pudo clonar'),
          content: Text(error!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('BBDD clonada'),
        content: const Text(
          'Los datos locales de Dev ya son una copia de Prod. La app se cerrará; ábrela de nuevo.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar app'),
          ),
        ],
      ),
    );
    exit(0);
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.userName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(auth.user?['email'] ?? '',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13)),
                        const SizedBox(height: 6),
                        _BggStatusBadge(connected: auth.bggConnected, username: auth.bggUsername),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Mi perfil'),
            subtitle: const Text('Nombre, conexión BGG y preferencias'),
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
            leading: const Icon(Icons.style),
            title: const Text('Fundas'),
            subtitle: const Text('Gestiona los tipos de funda'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/tipos-funda'),
          ),
          const Divider(),
          if (AppEnvironment.isDev) ...[
            ListTile(
              leading: const Icon(Icons.sports_esports),
              title: const Text('Planificar partida'),
              subtitle: const Text('Busca juegos por jugadores y edad'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pushNamed('/game-night'),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('BGG'),
            subtitle: const Text('Importar / exportar colección'),
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
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Comprobar expansiones en BGG'),
            subtitle: const Text(
              'Busca expansiones de BGG que no están en tu ludoteca',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showExpansionScanMenu,
          ),
          if (AppEnvironment.isDev) ...[
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
          ],
          if (_isDev) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Clonar BBDD de producción'),
              subtitle: const Text(
                'Sustituye los datos locales de Dev por los de Prod',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _cloneProdDatabase,
            ),
          ],
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

class _BggStatusBadge extends StatelessWidget {
  const _BggStatusBadge({
    required this.connected,
    this.username,
  });

  final bool connected;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        connected ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant;
    final bg = connected
        ? Colors.green.shade50
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.check_circle : Icons.link_off,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              connected
                  ? 'BGG · ${username ?? ''}'
                  : 'BGG no conectado',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
