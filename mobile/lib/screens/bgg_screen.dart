import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../data/juego_repository.dart';
import '../data/outbox_dao.dart';
import '../data/sync_service.dart';
import '../models/juego.dart';
import '../providers/auth_provider.dart';
import '../providers/bgg_collection_provider.dart';
import '../providers/sync_provider.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/image_cache_manager.dart';

class BggScreen extends StatefulWidget {
  const BggScreen({super.key});

  @override
  State<BggScreen> createState() => _BggScreenState();
}

class _BggScreenState extends State<BggScreen> {
  final ApiService _api = ApiService();
  late final JuegoRepository _juegos =
      JuegoRepository(DatabaseService(), OutboxDao(DatabaseService()));
  List<Propietario> _propietarios = [];
  Propietario? _selectedOwner;
  List<Map<String, dynamic>> _bggGames = [];
  bool _loadingOwners = true;
  bool _loadingCollection = false;
  bool _importing = false;
  bool _exportPreviewLoading = false;
  String? _importMessage;

  @override
  void initState() {
    super.initState();
    _fetchPropietarios();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.bggConnected) {
        context.read<BggCollectionProvider>().fetchOwnedIds();
      }
    });
  }

  Future<void> _fetchPropietarios() async {
    try {
      final response = await _api.get('/propietarios');
      final owners = (response.data as List)
          .map((p) => Propietario.fromJson(p))
          .where((p) => p.bggUsername != null && p.bggUsername!.isNotEmpty)
          .toList();
      setState(() {
        _propietarios = owners;
        _loadingOwners = false;
      });
    } catch (_) {
      setState(() => _loadingOwners = false);
    }
  }

  Future<void> _fetchCollection(String username) async {
    setState(() {
      _loadingCollection = true;
      _bggGames = [];
      _importMessage = null;
    });
    try {
      final response = await _api.get('/bgg/collection/$username');
      final data = response.data;
      final games = data is Map<String, dynamic>
          ? (data['games'] as List?)?.cast<Map<String, dynamic>>() ?? []
          : (data as List).cast<Map<String, dynamic>>();
      setState(() => _bggGames = games);
    } catch (e) {
      setState(() => _importMessage = 'Error al cargar colecci\u00f3n: $e');
    }
    setState(() => _loadingCollection = false);
  }

  /// Descarga en el servidor las im\u00e1genes de los juegos importados desde BGG.
  /// El backend expone `/bgg/import-images` (m\u00e1x. 30 por lote), que baja cada
  /// imagen y actualiza el campo `imagen` del juego.
  Future<Map<String, int>> _downloadPendingImages(List<dynamic> pending) async {
    const batchSize = 30;
    var ok = 0;
    var fail = 0;
    for (var i = 0; i < pending.length; i += batchSize) {
      final end =
          (i + batchSize) < pending.length ? i + batchSize : pending.length;
      final batch = pending.sublist(i, end);
      try {
        final res =
            await _api.post('/bgg/import-images', data: {'images': batch});
        final d = res.data;
        ok += (d['succeeded'] as num?)?.toInt() ?? 0;
        fail += (d['failed'] as num?)?.toInt() ?? 0;
      } catch (_) {
        fail += batch.length;
      }
    }
    return {'ok': ok, 'fail': fail};
  }

  Future<void> _importGames() async {
    if (_selectedOwner == null || _bggGames.isEmpty) return;
    setState(() {
      _importing = true;
      _importMessage = null;
    });
    try {
      final response = await _api.post('/bgg/import', data: {
        'games': _bggGames,
        'bgg_username': _selectedOwner!.bggUsername,
      });
      final data = response.data;
      var msg =
          'Importados: ${data['imported'] ?? 0}, ya exist\u00edan: ${data['skipped'] ?? 0}';
      final pending = (data['images_pending'] as List?) ?? [];
      if (pending.isNotEmpty) {
        if (mounted) {
          setState(() => _importMessage = '$msg\nDescargando im\u00e1genes...');
        }
        final imgRes = await _downloadPendingImages(pending);
        msg = '$msg\nIm\u00e1genes: ${imgRes['ok']} descargadas'
            '${(imgRes['fail'] ?? 0) > 0 ? ', ${imgRes['fail']} fallidas' : ''}';
      }
      if (mounted) setState(() => _importMessage = msg);
      // Sincroniza DESPU\u00c9S de descargar im\u00e1genes para traer el campo `imagen`.
      if (mounted) {
        context.read<SyncProvider>().syncNow(fullPull: false);
      } else {
        SyncService().syncAll();
      }
    } catch (e) {
      if (mounted) setState(() => _importMessage = 'Error al importar');
    }
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _importExpansions() async {
    if (_selectedOwner == null) return;
    setState(() {
      _importing = true;
      _importMessage = null;
    });
    try {
      final fetched = await _api
          .get('/bgg/expansions/${_selectedOwner!.bggUsername}');
      final fetchedData = fetched.data;
      final expansions = fetchedData is Map<String, dynamic>
          ? (fetchedData['expansions'] as List?)?.cast<Map<String, dynamic>>() ??
              []
          : (fetchedData as List).cast<Map<String, dynamic>>();

      if (expansions.isEmpty) {
        setState(() => _importMessage = 'No hay expansiones en BGG para este usuario.');
        return;
      }

      final response = await _api.post('/bgg/import-expansions', data: {
        'expansions': expansions,
        'bgg_username': _selectedOwner!.bggUsername,
      });
      final data = response.data;
      var msg =
          'Expansiones importadas: ${data['imported'] ?? 0}, omitidas: ${data['skipped'] ?? 0}';
      final pending = (data['images_pending'] as List?) ?? [];
      if (pending.isNotEmpty) {
        if (mounted) {
          setState(() => _importMessage = '$msg\nDescargando im\u00e1genes...');
        }
        final imgRes = await _downloadPendingImages(pending);
        msg = '$msg\nIm\u00e1genes: ${imgRes['ok']} descargadas'
            '${(imgRes['fail'] ?? 0) > 0 ? ', ${imgRes['fail']} fallidas' : ''}';
      }
      if (mounted) setState(() => _importMessage = msg);
      if (mounted) {
        context.read<SyncProvider>().syncNow(fullPull: false);
      } else {
        SyncService().syncAll();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importMessage = 'Error al importar expansiones: $e');
      }
    }
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _startExportFlow() async {
    final auth = context.read<AuthProvider>();
    if (!auth.bggConnected) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Conecta BGG'),
          content: const Text(
            'Para exportar tu colección necesitas conectar tu cuenta de BoardGameGeek en el perfil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ir al perfil'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        Navigator.of(context).pushNamed('/profile');
      }
      return;
    }

    setState(() => _exportPreviewLoading = true);
    Map<String, dynamic>? preview;
    String? error;
    try {
      final response = await _api.post('/bgg/export/preview');
      preview = Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      error = 'No se pudo preparar la exportación';
      try {
        final data = (e as dynamic).response?.data;
        if (data is Map && data['message'] is String) {
          error = data['message'] as String;
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _exportPreviewLoading = false);

    if (preview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Error al preparar la exportación')),
      );
      return;
    }

    final result = await showDialog<_ExportPreviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExportPreviewDialog(preview: preview!),
    );

    if (result == null || !result.accepted || !mounted) return;

    final ignored = result.ignoredIds;
    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    final toUpload = (preview['to_upload'] as List?)
            ?.cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) {
              final id = asInt(e['id']);
              return id == null || !ignored.contains(id);
            })
            .toList() ??
        [];
    final toPrevOwned = (preview['to_prev_owned'] as List?)
            ?.cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) {
              final id = asInt(e['id']);
              return id == null || !ignored.contains(id);
            })
            .toList() ??
        [];
    final queue = [...toUpload, ...toPrevOwned];

    if (queue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios que exportar a BGG')),
      );
      return;
    }

    await _runExport(queue);
  }

  Future<void> _runExport(List<Map<String, dynamic>> toUpload) async {
    final progress = ValueNotifier<_ExportProgress>(
      _ExportProgress(
        total: toUpload.length,
        current: 0,
        currentName: toUpload.first['nombre']?.toString() ?? '',
        log: const [],
      ),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExportProgressDialog(progress: progress),
    );

    var ok = 0;
    var fail = 0;
    final bggProvider = context.read<BggCollectionProvider>();
    final uploadedIds = <int>[];
    final prevOwnedIds = <int>[];
    final rateLimitedRetry = <Map<String, dynamic>>[];

    Future<_ExportItemResult> exportOne(Map<String, dynamic> item) async {
      final juegoId = item['id'];
      try {
        final response = await _api.post('/bgg/export/item', data: {
          'juego_id': juegoId,
        });
        final data = response.data as Map;
        final success = data['success'] == true;
        final msg = data['message']?.toString() ??
            (success ? 'OK' : 'Error desconocido');
        final rateLimited = data['rate_limited'] == true ||
            msg.contains('403') ||
            msg.contains('bloqueó temporalmente');
        return _ExportItemResult(
          success: success,
          message: msg,
          rateLimited: rateLimited,
          data: data,
        );
      } catch (e) {
        var msg = 'Error de red';
        var rateLimited = false;
        try {
          final data = (e as dynamic).response?.data;
          if (data is Map && data['message'] is String) {
            msg = data['message'] as String;
            rateLimited = data['rate_limited'] == true ||
                msg.contains('403') ||
                msg.contains('bloqueó temporalmente');
          }
        } catch (_) {}
        return _ExportItemResult(
          success: false,
          message: msg,
          rateLimited: rateLimited,
          data: const {},
        );
      }
    }

    void applySuccess(Map<String, dynamic> item, _ExportItemResult result) {
      ok++;
      final isPrevOwned = item['action']?.toString() == 'prevowned';
      final bggId = (item['bgg_id'] as num?)?.toInt();
      final juegoId = item['id'];
      final returnedBggId =
          (result.data['bgg_id'] as num?)?.toInt() ?? bggId;
      final bggIdSaved = result.data['bgg_id_saved'] == true;
      if (returnedBggId != null) {
        if (result.data['action']?.toString() == 'prevowned' || isPrevOwned) {
          prevOwnedIds.add(returnedBggId);
        } else {
          uploadedIds.add(returnedBggId);
        }
      }
      if (bggIdSaved && returnedBggId != null && juegoId is int) {
        // ignore: unawaited_futures
        _juegos.applyServerBggId(serverId: juegoId, bggId: returnedBggId);
      }
    }

    // Pasada 1
    for (var i = 0; i < toUpload.length; i++) {
      final item = toUpload[i];
      final nombre = item['nombre']?.toString() ?? 'Juego';
      final isPrevOwned = item['action']?.toString() == 'prevowned';

      progress.value = progress.value.copyWith(
        current: i + 1,
        currentName: isPrevOwned ? '$nombre (Previously Owned)' : nombre,
      );

      var result = await exportOne(item);

      // Un reintento inmediato del mismo juego tras 403.
      if (!result.success && result.rateLimited) {
        progress.value = progress.value.copyWith(
          currentName: '403 en $nombre — reintento en 25s…',
        );
        await Future<void>.delayed(const Duration(seconds: 25));
        progress.value = progress.value.copyWith(
          currentName: 'Reintentando $nombre…',
        );
        result = await exportOne(item);
      }

      if (result.success) {
        applySuccess(item, result);
        final matched = result.data['matched_name']?.toString();
        final detail = matched != null && matched.isNotEmpty
            ? '${result.message} ($matched)'
            : result.message;
        progress.value = progress.value.copyWith(
          log: [
            ...progress.value.log,
            _ExportLogLine(nombre: nombre, ok: true, message: detail),
          ],
        );
      } else if (result.rateLimited) {
        rateLimitedRetry.add(item);
        progress.value = progress.value.copyWith(
          log: [
            ...progress.value.log,
            _ExportLogLine(
              nombre: nombre,
              ok: false,
              message: '${result.message} (se reintentará al final)',
            ),
          ],
        );
      } else {
        fail++;
        progress.value = progress.value.copyWith(
          log: [
            ...progress.value.log,
            _ExportLogLine(nombre: nombre, ok: false, message: result.message),
          ],
        );
      }

      if (i < toUpload.length - 1) {
        await Future<void>.delayed(
          Duration(seconds: result.rateLimited ? 12 : 8),
        );
      }
    }

    // Pasada 2: solo los 403, tras una pausa larga.
    if (rateLimitedRetry.isNotEmpty) {
      progress.value = progress.value.copyWith(
        currentName:
            'Pausa 60s antes de reintentar ${rateLimitedRetry.length} con 403…',
      );
      await Future<void>.delayed(const Duration(seconds: 60));

      for (var i = 0; i < rateLimitedRetry.length; i++) {
        final item = rateLimitedRetry[i];
        final nombre = item['nombre']?.toString() ?? 'Juego';
        progress.value = progress.value.copyWith(
          current: toUpload.length,
          currentName:
              'Reintento 403 ${i + 1}/${rateLimitedRetry.length}: $nombre',
        );

        final result = await exportOne(item);
        if (result.success) {
          applySuccess(item, result);
          progress.value = progress.value.copyWith(
            log: [
              ...progress.value.log,
              _ExportLogLine(
                nombre: nombre,
                ok: true,
                message: 'OK en reintento final',
              ),
            ],
          );
        } else {
          fail++;
          progress.value = progress.value.copyWith(
            log: [
              ...progress.value.log,
              _ExportLogLine(
                nombre: nombre,
                ok: false,
                message: result.message,
              ),
            ],
          );
        }

        if (i < rateLimitedRetry.length - 1) {
          await Future<void>.delayed(const Duration(seconds: 20));
        }
      }
    }

    bggProvider.markOwnedMany(uploadedIds);
    bggProvider.unmarkOwnedMany(prevOwnedIds);
    // ignore: unawaited_futures
    bggProvider.fetchOwnedIds(force: true);

    progress.value = progress.value.copyWith(
      done: true,
      successCount: ok,
      failCount: fail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('BGG')),
      body: _loadingOwners
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Exportar a BoardGameGeek',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          auth.bggConnected
                              ? 'Sube a BGG solo los juegos de tu ludoteca que aún no estén en tu colección online.'
                              : 'Conecta tu cuenta BGG en el perfil para poder exportar.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: (_exportPreviewLoading || _importing)
                              ? null
                              : _startExportFlow,
                          icon: _exportPreviewLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.upload),
                          label: Text(
                            _exportPreviewLoading
                                ? 'Preparando...'
                                : 'Exportar colección a la BGG',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Importar desde BGG',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (_propietarios.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No hay propietarios con usuario de BGG configurado para importar.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                else ...[
                  Text('Selecciona un usuario de BGG',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _propietarios.map((p) {
                      final selected = _selectedOwner?.id == p.id;
                      return ChoiceChip(
                        label: Text('${p.nombre} (${p.bggUsername})'),
                        selected: selected,
                        onSelected: (sel) {
                          if (!sel) return;
                          setState(() => _selectedOwner = p);
                          _fetchCollection(p.bggUsername!);
                        },
                      );
                    }).toList(),
                  ),
                ],
                if (_loadingCollection) ...[
                  const SizedBox(height: 24),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_bggGames.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${_bggGames.length} juegos en BGG',
                            style: theme.textTheme.titleSmall),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _importing ? null : _importGames,
                          icon: const Icon(Icons.download),
                          label: const Text('Importar juegos'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importing ? null : _importExpansions,
                          icon: const Icon(Icons.extension),
                          label: const Text('Importar exp.'),
                        ),
                      ),
                    ],
                  ),
                  if (_importing) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_importMessage != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_importMessage!,
                            style: TextStyle(color: Colors.green[800])),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ...(_bggGames.map((game) => Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        elevation: 0,
                        child: ListTile(
                          leading: game['thumbnail'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(
                                    cacheManager: ImageCacheManager.instance,
                                    imageUrl: game['thumbnail'],
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    maxWidthDiskCache: 200,
                                    errorWidget: (_, e, s) =>
                                        const Icon(Icons.casino),
                                  ),
                                )
                              : const Icon(Icons.casino),
                          title: Text(game['name'] ?? '',
                              style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                              'BGG ID: ${game['bgg_id'] ?? '-'}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500])),
                        ),
                      ))),
                ],
              ],
            ),
    );
  }
}

class _ExportPreviewResult {
  const _ExportPreviewResult({
    required this.accepted,
    required this.ignoredIds,
  });

  final bool accepted;
  final Set<int> ignoredIds;
}

class _ExportPreviewDialog extends StatefulWidget {
  const _ExportPreviewDialog({required this.preview});

  final Map<String, dynamic> preview;

  @override
  State<_ExportPreviewDialog> createState() => _ExportPreviewDialogState();
}

class _ExportPreviewDialogState extends State<_ExportPreviewDialog> {
  final Set<int> _ignoredIds = {};

  List<Map<String, dynamic>> _maps(String key) {
    return (widget.preview[key] as List?)
            ?.cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
  }

  int? _itemId(Map<String, dynamic> item) {
    final id = item['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final counts = Map<String, dynamic>.from(preview['counts'] as Map? ?? {});
    final toUploadAll = _maps('to_upload');
    final toPrevOwnedAll = _maps('to_prev_owned');
    final omitted = _maps('omitted');

    final toUpload =
        toUploadAll.where((e) => !_ignoredIds.contains(_itemId(e))).toList();
    final toPrevOwned =
        toPrevOwnedAll.where((e) => !_ignoredIds.contains(_itemId(e))).toList();

    final uploadCount = toUpload.length;
    final prevOwnedCount = toPrevOwned.length;
    final already = (counts['already_in_bgg'] as num?)?.toInt() ?? 0;
    final uploadByName =
        toUpload.where((e) => e['match_by_name'] == true).length;
    final prevByName =
        toPrevOwned.where((e) => e['match_by_name'] == true).length;
    final totalChanges = uploadCount + prevOwnedCount;
    final ignoredCount = _ignoredIds.length;
    final propietario = preview['propietario'] is Map
        ? Map<String, dynamic>.from(preview['propietario'] as Map)
        : null;
    final propietarioNombre = propietario?['nombre']?.toString();
    final bggUsername = preview['username']?.toString() ??
        propietario?['bgg_username']?.toString();
    final coleccionLocal = (counts['coleccion_local'] as num?)?.toInt();

    return AlertDialog(
      title: const Text('Revisión de exportación'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (propietarioNombre != null || bggUsername != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Colección de ${propietarioNombre ?? 'propietario'}'
                    '${bggUsername != null ? ' (BGG: $bggUsername)' : ''}'
                    '${coleccionLocal != null ? ' · $coleccionLocal juegos locales' : ''}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              Text(
                'Cambios previstos: $totalChanges',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              if (ignoredCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$ignoredCount ignorados (no se exportarán)',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
              const SizedBox(height: 12),
              _PreviewStatRow(
                icon: Icons.upload,
                color: Colors.blue,
                title: 'Altas nuevas en BGG',
                value: uploadCount,
                detail: uploadByName > 0
                    ? 'De ellas, $uploadByName sin ID se buscarán por nombre'
                    : null,
              ),
              const SizedBox(height: 8),
              _PreviewStatRow(
                icon: Icons.sell_outlined,
                color: Colors.orange,
                title: 'Vendidos → Previously Owned',
                value: prevOwnedCount,
                detail: prevByName > 0
                    ? 'De ellas, $prevByName sin ID se buscarán por nombre'
                    : null,
              ),
              const SizedBox(height: 8),
              _PreviewStatRow(
                icon: Icons.check_circle_outline,
                color: Colors.green,
                title: 'Ya en BGG (sin cambios)',
                value: already,
                detail: 'Incluye owned y Previously Owned ya correctos',
              ),
              if (omitted.isNotEmpty) ...[
                const SizedBox(height: 8),
                _PreviewStatRow(
                  icon: Icons.info_outline,
                  color: Colors.grey,
                  title: 'Omitidos',
                  value: omitted.length,
                ),
              ],
              if (toUploadAll.isNotEmpty || toPrevOwnedAll.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => _ExportChangesListDialog(
                        toUpload: toUploadAll,
                        toPrevOwned: toPrevOwnedAll,
                        ignoredIds: _ignoredIds,
                        onIgnoredChanged: (ids) {
                          setState(() {
                            _ignoredIds
                              ..clear()
                              ..addAll(ids);
                          });
                        },
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Ver listado completo de cambios'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: totalChanges == 0
              ? null
              : () => Navigator.of(context).pop(
                    _ExportPreviewResult(
                      accepted: true,
                      ignoredIds: Set<int>.from(_ignoredIds),
                    ),
                  ),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

class _PreviewStatRow extends StatelessWidget {
  const _PreviewStatRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title: $value',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportChangesListDialog extends StatefulWidget {
  const _ExportChangesListDialog({
    required this.toUpload,
    required this.toPrevOwned,
    required this.ignoredIds,
    required this.onIgnoredChanged,
  });

  final List<Map<String, dynamic>> toUpload;
  final List<Map<String, dynamic>> toPrevOwned;
  final Set<int> ignoredIds;
  final ValueChanged<Set<int>> onIgnoredChanged;

  @override
  State<_ExportChangesListDialog> createState() =>
      _ExportChangesListDialogState();
}

class _ExportChangesListDialogState extends State<_ExportChangesListDialog> {
  late Set<int> _ignored;

  @override
  void initState() {
    super.initState();
    _ignored = Set<int>.from(widget.ignoredIds);
  }

  void _toggle(int? id) {
    if (id == null) return;
    setState(() {
      if (_ignored.contains(id)) {
        _ignored.remove(id);
      } else {
        _ignored.add(id);
      }
    });
    widget.onIgnoredChanged(Set<int>.from(_ignored));
  }

  int? _itemId(Map<String, dynamic> item) {
    final id = item['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final activeUpload =
        widget.toUpload.where((e) => !_ignored.contains(_itemId(e))).length;
    final activePrev =
        widget.toPrevOwned.where((e) => !_ignored.contains(_itemId(e))).length;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.75,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Listado de cambios',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (_ignored.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_ignored.length} ignorados',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13),
                    ),
                  ),
                ),
              TabBar(
                tabs: [
                  Tab(text: 'Altas ($activeUpload/${widget.toUpload.length})'),
                  Tab(
                      text:
                          'Vendidos ($activePrev/${widget.toPrevOwned.length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ChangesList(
                      items: widget.toUpload,
                      emptyLabel: 'No hay altas nuevas',
                      ignoredIds: _ignored,
                      onToggleIgnore: _toggle,
                      subtitleFor: (item) {
                        final byName = item['match_by_name'] == true;
                        final bggId = item['bgg_id'];
                        if (byName) {
                          return 'Buscar por nombre → añadir como Owned';
                        }
                        return 'BGG #$bggId → añadir como Owned';
                      },
                    ),
                    _ChangesList(
                      items: widget.toPrevOwned,
                      emptyLabel: 'No hay cambios de vendidos',
                      ignoredIds: _ignored,
                      onToggleIgnore: _toggle,
                      subtitleFor: (item) {
                        final byName = item['match_by_name'] == true;
                        final bggId = item['bgg_id'];
                        if (byName) {
                          return 'Buscar por nombre → Previously Owned';
                        }
                        return 'BGG #$bggId → Previously Owned';
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangesList extends StatelessWidget {
  const _ChangesList({
    required this.items,
    required this.emptyLabel,
    required this.subtitleFor,
    required this.ignoredIds,
    required this.onToggleIgnore,
  });

  final List<Map<String, dynamic>> items;
  final String emptyLabel;
  final String Function(Map<String, dynamic> item) subtitleFor;
  final Set<int> ignoredIds;
  final ValueChanged<int?> onToggleIgnore;

  int? _itemId(Map<String, dynamic> item) {
    final id = item['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyLabel, style: TextStyle(color: Colors.grey[600])),
      );
    }

    final sorted = [...items]
      ..sort(
        (a, b) => (a['nombre']?.toString() ?? '')
            .toLowerCase()
            .compareTo((b['nombre']?.toString() ?? '').toLowerCase()),
      );

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = sorted[index];
        final id = _itemId(item);
        final ignored = id != null && ignoredIds.contains(id);
        final nombre = item['nombre']?.toString() ?? 'Juego';
        return ListTile(
          dense: true,
          title: Text(
            nombre,
            style: TextStyle(
              fontSize: 14,
              decoration: ignored ? TextDecoration.lineThrough : null,
              color: ignored ? Colors.grey : null,
            ),
          ),
          subtitle: Text(
            ignored ? 'Ignorado — no se exportará' : subtitleFor(item),
            style: TextStyle(
              fontSize: 12,
              color: ignored ? Colors.orange[800] : Colors.grey[600],
            ),
          ),
          trailing: TextButton(
            onPressed: () => onToggleIgnore(id),
            child: Text(ignored ? 'Incluir' : 'Ignorar'),
          ),
        );
      },
    );
  }
}

class _ExportItemResult {
  const _ExportItemResult({
    required this.success,
    required this.message,
    required this.rateLimited,
    required this.data,
  });

  final bool success;
  final String message;
  final bool rateLimited;
  final Map data;
}

class _ExportProgress {
  const _ExportProgress({
    required this.total,
    required this.current,
    required this.currentName,
    required this.log,
    this.done = false,
    this.aborted = false,
    this.abortReason,
    this.successCount = 0,
    this.failCount = 0,
  });

  final int total;
  final int current;
  final String currentName;
  final List<_ExportLogLine> log;
  final bool done;
  final bool aborted;
  final String? abortReason;
  final int successCount;
  final int failCount;

  _ExportProgress copyWith({
    int? total,
    int? current,
    String? currentName,
    List<_ExportLogLine>? log,
    bool? done,
    bool? aborted,
    String? abortReason,
    int? successCount,
    int? failCount,
  }) {
    return _ExportProgress(
      total: total ?? this.total,
      current: current ?? this.current,
      currentName: currentName ?? this.currentName,
      log: log ?? this.log,
      done: done ?? this.done,
      aborted: aborted ?? this.aborted,
      abortReason: abortReason ?? this.abortReason,
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
    );
  }
}

class _ExportLogLine {
  const _ExportLogLine({
    required this.nombre,
    required this.ok,
    required this.message,
  });

  final String nombre;
  final bool ok;
  final String message;
}

class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog({required this.progress});

  final ValueNotifier<_ExportProgress> progress;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_ExportProgress>(
      valueListenable: progress,
      builder: (context, value, _) {
        final ratio = value.total == 0 ? 0.0 : value.current / value.total;
        return AlertDialog(
          title: Text(value.done
              ? (value.aborted ? 'Exportación interrumpida' : 'Exportación terminada')
              : 'Exportando a BGG'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!value.done) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  Text(
                    'Subiendo ${value.current} de ${value.total}: ${value.currentName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: ratio),
                ] else ...[
                  Text(
                    'Correctos: ${value.successCount} · Fallidos: ${value.failCount}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (value.abortReason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      value.abortReason!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: value.log.length,
                    itemBuilder: (context, index) {
                      final line = value.log[value.log.length - 1 - index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          line.ok ? Icons.check_circle : Icons.error_outline,
                          color: line.ok ? Colors.green : Colors.red,
                          size: 18,
                        ),
                        title: Text(line.nombre, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(line.message, style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (value.done)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
          ],
        );
      },
    );
  }
}
