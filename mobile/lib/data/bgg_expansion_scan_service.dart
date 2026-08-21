import '../services/api_service.dart';
import 'sync_service.dart';

/// Ejecuta el escaneo de expansiones BGG por lotes contra el backend.
class BggExpansionScanService {
  final ApiService _api = ApiService();

  Future<void> runScan({
    required String modo,
    void Function(String message)? onProgress,
  }) async {
    await _runPhase(modo: modo, fase: 'links', onProgress: onProgress);
    await _runPhase(modo: modo, fase: 'detalles', onProgress: onProgress);
    await SyncService().syncAll(fullPull: false);
  }

  Future<void> _runPhase({
    required String modo,
    required String fase,
    void Function(String message)? onProgress,
  }) async {
    var cursor = 0;
    var terminado = false;

    while (!terminado) {
      final response = await _api.post('/bgg/expansions/scan', data: {
        'modo': modo,
        'fase': fase,
        'cursor': cursor,
        'limite': 20,
      });

      final data = response.data as Map<String, dynamic>;
      cursor = (data['cursor'] as num?)?.toInt() ?? cursor;
      terminado = data['terminado'] == true;
      final total = (data['total'] as num?)?.toInt() ?? 0;

      onProgress?.call(
        'Fase ${fase == 'links' ? '1' : '2'}/2 · $cursor de $total',
      );

      if (terminado) {
        break;
      }
    }
  }
}
