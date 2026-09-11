import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../services/image_cache_manager.dart';
import '../utils/friendly_error.dart';
import '../widgets/scrollable_modal_sheet.dart';

/// Hoja modal para buscar un juego en BGG y devolver el seleccionado.
///
/// Devuelve un mapa con las claves: bgg_id, name, year, image, thumbnail,
/// min_players, max_players, description, playing_time.
class BggSearchPicker extends StatefulWidget {
  const BggSearchPicker({super.key, this.initialQuery});

  final String? initialQuery;

  static Future<Map<String, dynamic>?> show(BuildContext context,
      {String? initialQuery}) {
    return showScrollableModalSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => BggSearchPicker(initialQuery: initialQuery),
    );
  }

  @override
  State<BggSearchPicker> createState() => _BggSearchPickerState();
}

class _BggSearchPickerState extends State<BggSearchPicker> {
  final _ctrl = TextEditingController();
  final _api = ApiService();
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').isNotEmpty) {
      _ctrl.text = widget.initialQuery!;
      _search();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.get('/bgg/search', params: {'query': query});
      final games =
          (response.data['games'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() => _results = games);
    } catch (e) {
      setState(() => _error = friendlyError(e, contexto: 'No se pudo buscar en BGG'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Buscar en BGG',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Nombre del juego',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${_results.length} resultados',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
        Expanded(
          child: _results.isEmpty && !_loading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Escribe un nombre y pulsa buscar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: ClampingScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, idx) {
                    final game = _results[idx];
                    return ListTile(
                      dense: true,
                      leading: game['thumbnail'] != null &&
                              (game['thumbnail'] as String).isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                cacheManager: ImageCacheManager.instance,
                                imageUrl: game['thumbnail'],
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                maxWidthDiskCache: 200,
                                fadeInDuration:
                                    const Duration(milliseconds: 150),
                                errorWidget: (_, _, _) =>
                                    const Icon(Icons.casino),
                              ),
                            )
                          : const Icon(Icons.casino),
                      title: Text(game['name'] ?? 'Sin nombre'),
                      subtitle: Text([
                        if (game['year'] != null && game['year'] != 0)
                          '${game['year']}',
                        'BGG #${game['bgg_id'] ?? '-'}',
                      ].join(' \u00b7 ')),
                      onTap: () => Navigator.of(context).pop(game),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
