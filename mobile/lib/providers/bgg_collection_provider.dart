import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class BggCollectionProvider extends ChangeNotifier {
  static const _pendingOwnedKey = 'bgg_pending_owned_ids';
  static const _pendingPrevOwnedKey = 'bgg_pending_prevowned_ids';

  final ApiService _api = ApiService();

  final Set<int> _ownedIds = {};
  final Set<int> _pendingOwnedIds = {};
  final Set<int> _pendingPrevOwnedIds = {};
  final Set<String> _ownedNames = {};
  final Set<String> _prevOwnedNames = {};
  bool _loading = false;
  bool _pendingLoaded = false;
  String? _error;
  DateTime? _fetchedAt;

  Set<int> get ownedIds => {..._ownedIds, ..._pendingOwnedIds};
  Set<int> get prevOwnedIds => {..._pendingPrevOwnedIds};
  Set<String> get ownedNames => {..._ownedNames};
  Set<String> get prevOwnedNames => {..._prevOwnedNames};
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _fetchedAt != null;

  bool isInBggCollection(int? bggId, {String? nombre}) {
    if (bggId != null && bggId > 0 && ownedIds.contains(bggId)) {
      return true;
    }
    final name = normalizeGameName(nombre);
    return name.isNotEmpty && _ownedNames.contains(name);
  }

  static String normalizeGameName(String? name) {
    if (name == null) return '';
    var value = name.trim().toLowerCase();
    const map = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    map.forEach((from, to) => value = value.replaceAll(from, to));
    return value.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  void markOwned(int bggId, {String? nombre}) {
    if (bggId <= 0 && (nombre == null || nombre.isEmpty)) return;
    _pendingPrevOwnedIds.remove(bggId);
    var changed = false;
    if (bggId > 0) {
      changed = _ownedIds.add(bggId) | _pendingOwnedIds.add(bggId);
    }
    final name = normalizeGameName(nombre);
    if (name.isNotEmpty && _ownedNames.add(name)) changed = true;
    if (changed) {
      notifyListeners();
      _persistPending();
    }
  }

  void markOwnedMany(Iterable<int> ids) {
    var changed = false;
    for (final id in ids) {
      if (id <= 0) continue;
      _pendingPrevOwnedIds.remove(id);
      if (_ownedIds.add(id)) changed = true;
      if (_pendingOwnedIds.add(id)) changed = true;
    }
    if (changed) {
      notifyListeners();
      _persistPending();
    }
  }

  void unmarkOwnedMany(Iterable<int> ids) {
    var changed = false;
    for (final id in ids) {
      if (id <= 0) continue;
      _pendingOwnedIds.remove(id);
      if (_ownedIds.remove(id)) changed = true;
      if (_pendingPrevOwnedIds.add(id)) changed = true;
    }
    if (changed) {
      notifyListeners();
      _persistPending();
    }
  }

  void clear() {
    _ownedIds.clear();
    _pendingOwnedIds.clear();
    _pendingPrevOwnedIds.clear();
    _ownedNames.clear();
    _prevOwnedNames.clear();
    _error = null;
    _fetchedAt = null;
    notifyListeners();
    _persistPending();
  }

  Future<void> syncForExport(String? username) async {
    await _ensurePendingLoaded();
    final tasks = <Future<void>>[
      fetchOwnedIds(force: true).then((_) {}),
    ];
    if (username != null && username.trim().isNotEmpty) {
      tasks.add(_ingestCollectionLists(username.trim()));
    }
    await Future.wait(tasks);
  }

  Future<bool> fetchOwnedIds({bool force = false}) async {
    await _ensurePendingLoaded();
    if (!force &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 10)) {
      return true;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.get('/bgg/owned-ids');
      final ids = (response.data['ids'] as List?)
              ?.map((e) => (e as num).toInt())
              .where((e) => e > 0) ??
          const <int>[];
      _ownedIds
        ..clear()
        ..addAll(ids);
      _pendingOwnedIds.removeWhere(_ownedIds.contains);
      _fetchedAt = DateTime.now();
      _loading = false;
      notifyListeners();
      _persistPending();
      return true;
    } catch (e) {
      _loading = false;
      _error = 'No se pudo cargar la colección de BGG';
      notifyListeners();
      return false;
    }
  }

  Future<void> _ingestCollectionLists(String username) async {
    Future<List<Map<String, dynamic>>> load(String path, String listKey) async {
      try {
        final response = await _api.get(path);
        final data = response.data;
        if (data is! Map) return const [];
        return (data[listKey] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            const [];
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      load('/bgg/collection/$username', 'games'),
      load('/bgg/expansions/$username', 'expansions'),
    ]);

    var changed = false;
    for (final item in [...results[0], ...results[1]]) {
      final id = (item['bgg_id'] as num?)?.toInt();
      if (id != null && id > 0 && _ownedIds.add(id)) changed = true;
      final name = normalizeGameName(item['name']?.toString());
      if (name.isNotEmpty && _ownedNames.add(name)) changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _ensurePendingLoaded() async {
    if (_pendingLoaded) return;
    _pendingLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingOwnedIds.addAll(
        (prefs.getStringList(_pendingOwnedKey) ?? const [])
            .map(int.tryParse)
            .whereType<int>()
            .where((id) => id > 0),
      );
      _pendingPrevOwnedIds.addAll(
        (prefs.getStringList(_pendingPrevOwnedKey) ?? const [])
            .map(int.tryParse)
            .whereType<int>()
            .where((id) => id > 0),
      );
    } catch (_) {}
  }

  Future<void> _persistPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _pendingOwnedKey,
        _pendingOwnedIds.map((id) => id.toString()).toList(),
      );
      await prefs.setStringList(
        _pendingPrevOwnedKey,
        _pendingPrevOwnedIds.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }
}
