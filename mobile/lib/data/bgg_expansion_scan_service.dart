import 'package:dio/dio.dart';

import '../services/api_service.dart';
import 'sync_service.dart';

/// Ejecuta el escaneo de expansiones BGG por lotes contra el backend.
class BggExpansionScanService {
  /// Cada lote hace una consulta a la API de BGG, que el backend deja correr
  /// hasta 45 s, más las escrituras en base de datos. El timeout global de Dio
  /// (60 s) se queda corto; nginx corta a los 300 s.
  static const Duration _timeoutLote = Duration(minutes: 3);

  /// Lotes pequeños: el XML que devuelve BGG crece con cada juego pedido y es
  /// la parte más lenta de la petición.
  static const int _tamanoLote = 10;

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
    final esFaseLinks = fase == 'links';
    final etiqueta = esFaseLinks ? 'Fase 1/2' : 'Fase 2/2';
    final unidad = esFaseLinks ? 'juegos' : 'expansiones';

    var cursor = 0;
    var procesados = 0;
    int? total;

    while (true) {
      final response = await _api.post(
        '/bgg/expansions/scan',
        data: {
          'modo': modo,
          'fase': fase,
          'cursor': cursor,
          'limite': _tamanoLote,
        },
        options: Options(
          receiveTimeout: _timeoutLote,
          sendTimeout: _timeoutLote,
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final nuevoCursor = (data['cursor'] as num?)?.toInt() ?? cursor;
      procesados += (data['procesados'] as num?)?.toInt() ?? 0;
      total ??= (data['total'] as num?)?.toInt() ?? 0;

      onProgress?.call('$etiqueta · $procesados de $total $unidad');

      if (data['terminado'] == true) return;

      // Sin avance del cursor el mismo lote se repetiría indefinidamente.
      if (nuevoCursor <= cursor) return;
      cursor = nuevoCursor;
    }
  }
}
