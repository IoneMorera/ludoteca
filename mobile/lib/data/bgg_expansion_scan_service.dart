import 'dart:async';

import 'package:dio/dio.dart';

import '../services/api_service.dart';
import '../services/error_log_service.dart';
import '../services/foreground_scan_keeper.dart';
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

  /// Reintentos por lote fallido.
  static const int _maxRetries = 4;

  /// Pausa entre reintentos de un lote (segundos).
  static const int _retryDelaySecs = 5;

  static bool _active = false;
  static bool get isRunning => _active;

  final ApiService _api = ApiService();
  final ErrorLogService _errorLog = ErrorLogService();

  Future<void> runScan({
    required String modo,
    void Function(String message)? onProgress,
  }) async {
    _active = true;
    await ForegroundScanKeeper.start(
      title: 'Comprobando expansiones',
      text: 'El escaneo continúa en segundo plano',
    );
    try {
      await _runPhase(modo: modo, fase: 'links', onProgress: onProgress);
      await _runPhase(modo: modo, fase: 'detalles', onProgress: onProgress);
      await SyncService().syncAll(fullPull: false);
    } finally {
      await ForegroundScanKeeper.stop();
      _active = false;
    }
  }

  void _reportProgress(void Function(String)? onProgress, String message) {
    onProgress?.call(message);
    unawaited(ForegroundScanKeeper.update(message));
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
    var consecutiveErrors = 0;

    while (true) {
      Map<String, dynamic>? data;
      var attempt = 0;

      while (true) {
        try {
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
          data = response.data as Map<String, dynamic>;
          consecutiveErrors = 0;
          break;
        } catch (e, stack) {
          if (attempt < _maxRetries && _isRetryableError(e)) {
            attempt++;
            _reportProgress(
              onProgress,
              '$etiqueta · Reintentando lote (intento ${attempt + 1})...',
            );
            await Future.delayed(
              Duration(seconds: _retryDelaySecs * attempt),
            );
            continue;
          }

          consecutiveErrors++;
          await _errorLog.log(
            context: 'BggExpansionScan.$fase',
            error: e,
            stackTrace: stack,
            extra: {
              'modo': modo,
              'fase': fase,
              'cursor': cursor,
              'attempt': attempt + 1,
              'procesados': procesados,
            },
          );

          if (consecutiveErrors >= 3) {
            _reportProgress(
              onProgress,
              '$etiqueta · Demasiados errores consecutivos, abortando.',
            );
            rethrow;
          }

          _reportProgress(
            onProgress,
            '$etiqueta · Error en lote, saltando al siguiente...',
          );
          cursor += _tamanoLote;
          data = null;
          break;
        }
      }

      if (data == null) continue;

      final nuevoCursor = (data['cursor'] as num?)?.toInt() ?? cursor;
      procesados += (data['procesados'] as num?)?.toInt() ?? 0;
      total ??= (data['total'] as num?)?.toInt() ?? 0;

      _reportProgress(
        onProgress,
        '$etiqueta · $procesados de $total $unidad',
      );

      if (data['terminado'] == true) return;

      if (nuevoCursor <= cursor) return;
      cursor = nuevoCursor;
    }
  }

  bool _isRetryableError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) {
        return true;
      }
      final code = e.response?.statusCode;
      if (code != null && code >= 500) return true;
    }
    return false;
  }
}
