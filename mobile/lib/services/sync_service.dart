import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'database_service.dart';

class SyncService {
  final ApiService _api = ApiService();
  final DatabaseService _db = DatabaseService();

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> syncJuegos() async {
    if (!await isOnline()) return;

    try {
      final response = await _api.get('/juegos', params: {'per_page': 9999});
      final data = response.data;
      final juegos = (data['data'] as List?)?.cast<Map<String, dynamic>>() ??
          (data as List?)?.cast<Map<String, dynamic>>() ??
          [];
      await _db.cacheJuegos(juegos);
    } catch (_) {}
  }
}
