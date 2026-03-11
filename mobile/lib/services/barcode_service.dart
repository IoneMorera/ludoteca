import 'api_service.dart';

class BarcodeService {
  final ApiService _api = ApiService();

  /// Searches BGG by barcode (EAN/UPC) or name
  Future<List<Map<String, dynamic>>> searchByBarcode(String barcode) async {
    try {
      final response =
          await _api.get('/bgg/search', params: {'query': barcode});
      final games = response.data['games'] as List?;
      return games?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchByName(String name) async {
    try {
      final response =
          await _api.get('/bgg/search', params: {'query': name});
      final games = response.data['games'] as List?;
      return games?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {
      return [];
    }
  }
}
