import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

class BggCollectionProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  final Set<int> _ownedIds = {};
  bool _loading = false;
  String? _error;
  DateTime? _fetchedAt;

  Set<int> get ownedIds => _ownedIds;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _fetchedAt != null;

  bool isInBggCollection(int? bggId) {
    if (bggId == null || bggId <= 0) return false;
    return _ownedIds.contains(bggId);
  }

  void markOwned(int bggId) {
    if (bggId <= 0) return;
    if (_ownedIds.add(bggId)) {
      notifyListeners();
    }
  }

  void markOwnedMany(Iterable<int> ids) {
    var changed = false;
    for (final id in ids) {
      if (id > 0 && _ownedIds.add(id)) changed = true;
    }
    if (changed) notifyListeners();
  }

  void unmarkOwnedMany(Iterable<int> ids) {
    var changed = false;
    for (final id in ids) {
      if (_ownedIds.remove(id)) changed = true;
    }
    if (changed) notifyListeners();
  }

  void clear() {
    _ownedIds.clear();
    _error = null;
    _fetchedAt = null;
    notifyListeners();
  }

  Future<bool> fetchOwnedIds({bool force = false}) async {
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
      _fetchedAt = DateTime.now();
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _loading = false;
      _error = 'No se pudo cargar la colección de BGG';
      notifyListeners();
      return false;
    }
  }
}
