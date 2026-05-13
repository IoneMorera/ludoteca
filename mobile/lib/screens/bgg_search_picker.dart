import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Hoja modal para buscar un juego en BGG y devolver el seleccionado.
///
/// Devuelve un mapa con las claves: bgg_id, name, year, image, thumbnail,
/// min_players, max_players, description, playing_time.
class BggSearchPicker extends StatefulWidget {
  const BggSearchPicker({super.key, this.initialQuery});

  final String? initialQuery;

  static Future<Map<String, dynamic>?> show(BuildContext context,
      {String? initialQuery}) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => BggSearchPicker(initialQuery: initialQuery),
      ),
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
      setState(() => _error = 'Error al buscar en BGG: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Buscar en BGG',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              decoration: InputDecoration(
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(
                    child: Text(
                      'Escribe un nombre y pulsa enter para buscar.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1),
                    itemBuilder: (_, idx) {
                      final game = _results[idx];
                      return ListTile(
                        leading: game['thumbnail'] != null &&
                                (game['thumbnail'] as String).isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  game['thumbnail'],
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
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
      ),
    );
  }
}
