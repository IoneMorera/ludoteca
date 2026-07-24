import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../data/sync_service.dart';
import '../models/juego.dart';
import '../providers/sync_provider.dart';
import '../services/api_service.dart';
import '../services/image_cache_manager.dart';

class BggScreen extends StatefulWidget {
  const BggScreen({super.key});

  @override
  State<BggScreen> createState() => _BggScreenState();
}

class _BggScreenState extends State<BggScreen> {
  final ApiService _api = ApiService();
  List<Propietario> _propietarios = [];
  Propietario? _selectedOwner;
  List<Map<String, dynamic>> _bggGames = [];
  bool _loadingOwners = true;
  bool _loadingCollection = false;
  bool _importing = false;
  String? _importMessage;

  @override
  void initState() {
    super.initState();
    _fetchPropietarios();
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
      if (data['omitted'] != null &&
          (data['omitted'] as List).isNotEmpty) {
        msg = '$msg\nSin juego base: ${(data['omitted'] as List).join(', ')}';
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('BGG')),
      body: _loadingOwners
          ? const Center(child: CircularProgressIndicator())
          : _propietarios.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_off, size: 56, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No hay propietarios con usuario de BGG configurado.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Añade un nombre de usuario BGG en la sección de Propietarios de la web.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Selecciona un usuario de BGG',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
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
                            child: FilledButton.icon(
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
