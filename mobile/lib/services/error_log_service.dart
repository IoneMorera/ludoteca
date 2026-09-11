import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'api_service.dart';
import 'device_context.dart';

/// Servicio centralizado de registro de errores.
///
/// Almacena los errores en SQLite y los envía al backend automáticamente
/// tras un breve debounce para agrupar ráfagas de errores.
class ErrorLogService {
  static final ErrorLogService _instance = ErrorLogService._();
  factory ErrorLogService() => _instance;
  ErrorLogService._();

  static const String _table = 'error_logs';
  static const int _maxLocalLogs = 500;
  static const int _flushBatchSize = 50;

  /// Espera tras el último log antes de enviar (agrupa ráfagas).
  static const Duration _flushDebounce = Duration(seconds: 5);

  Database? _db;
  String _appVersion = '';
  bool _flushing = false;
  Timer? _flushTimer;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await DatabaseService().database;
    return _db!;
  }

  /// Inicializa el servicio. Llamar una vez en main().
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {}
    unawaited(DeviceContext.warmUp());

    final db = await _database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        level TEXT NOT NULL DEFAULT 'error',
        context TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        extra TEXT,
        sent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    unawaited(_pruneOldLogs());
    unawaited(flush());
  }

  /// Registra un error con contexto y programa el envío automático.
  Future<void> log({
    required String context,
    required Object error,
    StackTrace? stackTrace,
    String level = 'error',
    Map<String, dynamic>? extra,
  }) async {
    try {
      final device = await DeviceContext.capture();
      final mergedExtra = {...device, ...?extra};
      final db = await _database;
      await db.insert(_table, {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'level': level,
        'context': context,
        'message': error.toString(),
        'stack_trace': stackTrace?.toString(),
        'extra': jsonEncode(mergedExtra),
        'sent': 0,
      });
      _scheduleFlush();
    } catch (e) {
      debugPrint('ErrorLogService.log failed: $e');
    }
  }

  /// Registra un warning (no crítico) y programa el envío.
  Future<void> warn({
    required String context,
    required String message,
    Map<String, dynamic>? extra,
  }) {
    return log(
      context: context,
      error: message,
      level: 'warning',
      extra: extra,
    );
  }

  /// Programa el envío tras un debounce. Si se registran varios errores
  /// seguidos, solo se hace una petición agrupada.
  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDebounce, () => unawaited(flush()));
  }

  /// Envía los errores pendientes al backend.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final db = await _database;
      final rows = await db.query(
        _table,
        where: 'sent = 0',
        orderBy: 'id ASC',
        limit: _flushBatchSize,
      );
      if (rows.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final userName = prefs.getString('user_name');

      final logs = rows.map((r) {
        Map<String, dynamic>? extra;
        if (r['extra'] != null) {
          try {
            extra = jsonDecode(r['extra'] as String) as Map<String, dynamic>;
          } catch (_) {}
        }
        return {
          'timestamp': r['timestamp'],
          'level': r['level'],
          'context': r['context'],
          'message': r['message'],
          'stack_trace': r['stack_trace'],
          'extra': extra,
          'device_model': extra?['device_model'],
          'os_version': extra?['os_version'],
          'connection_type': extra?['connection_type'],
          'free_memory': extra?['free_memory'],
        };
      }).toList();

      final latestDevice = await DeviceContext.capture();
      await ApiService().post('/error-logs', data: {
        'user_id': userId,
        'user_name': userName,
        'app_version': _appVersion,
        ...latestDevice,
        'logs': logs,
      });

      final ids = rows.map((r) => r['id'] as int).toList();
      await db.update(
        _table,
        {'sent': 1},
        where: 'id IN (${ids.join(',')})',
      );

      // Si quedan más pendientes, programar otro envío.
      final remaining = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM $_table WHERE sent = 0',
        ),
      );
      if (remaining != null && remaining > 0) {
        _scheduleFlush();
      }
    } catch (e) {
      debugPrint('ErrorLogService.flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  /// Elimina logs antiguos ya enviados para no crecer indefinidamente.
  Future<void> _pruneOldLogs() async {
    try {
      final db = await _database;
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $_table'),
      );
      if (count != null && count > _maxLocalLogs) {
        final excess = count - _maxLocalLogs;
        await db.rawDelete(
          'DELETE FROM $_table WHERE id IN '
          '(SELECT id FROM $_table WHERE sent = 1 ORDER BY id ASC LIMIT ?)',
          [excess],
        );
      }
    } catch (_) {}
  }
}
