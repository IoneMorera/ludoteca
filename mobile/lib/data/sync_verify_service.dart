import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/api_service.dart';
import '../services/database_service.dart';

class FieldDiff {
  final String field;
  final String? localValue;
  final String? remoteValue;

  FieldDiff({required this.field, this.localValue, this.remoteValue});
}

class RecordDiff {
  final int serverId;
  final String? recordName;
  final List<FieldDiff> diffs;

  RecordDiff({required this.serverId, this.recordName, required this.diffs});
}

class TableVerifyResult {
  final String tableName;
  final int localCount;
  final int remoteCount;
  final List<int> missingInLocal;
  final List<int> missingInRemote;
  final List<RecordDiff> dataDiffs;
  final int pendingCreates;
  final int pendingDeletes;

  TableVerifyResult({
    required this.tableName,
    required this.localCount,
    required this.remoteCount,
    required this.missingInLocal,
    required this.missingInRemote,
    required this.dataDiffs,
    this.pendingCreates = 0,
    this.pendingDeletes = 0,
  });

  bool get isOk =>
      missingInLocal.isEmpty &&
      missingInRemote.isEmpty &&
      dataDiffs.isEmpty &&
      localCount == remoteCount;
}

class SyncVerifyResult {
  final List<TableVerifyResult> tables;
  final int outboxPending;
  final String? error;

  SyncVerifyResult({
    required this.tables,
    this.outboxPending = 0,
    this.error,
  });

  bool get isFullySync =>
      error == null && tables.every((t) => t.isOk) && outboxPending == 0;

  int get totalDiffs => tables.fold(0, (sum, t) =>
      sum + t.missingInLocal.length + t.missingInRemote.length + t.dataDiffs.length);
}

class SyncVerifyService {
  final ApiService _api = ApiService();

  static const Map<String, List<String>> _tableFields = {
    'categorias': ['nombre', 'descripcion'],
    'propietarios': ['nombre', 'bgg_username', 'es_principal'],
    'habitaciones': ['nombre'],
    'muebles': ['habitacion_id', 'nombre'],
    'ubicaciones': ['mueble_id', 'nombre'],
    'tipos_funda': ['nombre', 'ancho_mm', 'alto_mm', 'descripcion'],
    'juegos': [
      'nombre', 'descripcion', 'edad_minima', 'edad_maxima',
      'num_jugadores_min', 'num_jugadores_max', 'ubicacion_id',
      'estado', 'fecha_compra', 'imagen', 'bgg_id', 'juego_base_id',
      'no_enfundar', 'es_expansion', 'idiomas', 'idioma_otro',
      'independiente_idioma', 'tradumaquetado', 'tradumaquetado_parcial',
      'tradumaquetado_parcial_notas', 'varias_copias', 'precio', 'en_caja_base',
      'sin_abrir', 'print_and_play',
    ],
    'juego_fundas': ['juego_id', 'tipo_funda_id', 'cantidad_cartas', 'enfundadas'],
    'juego_propietario': [
      'juego_id', 'propietario_id', 'ubicacion_id', 'es_principal',
      'estado', 'fecha_compra', 'no_enfundar', 'idiomas', 'idioma_otro',
      'independiente_idioma', 'tradumaquetado', 'tradumaquetado_parcial',
      'tradumaquetado_parcial_notas', 'sin_abrir', 'print_and_play',
    ],
    'juego_propietario_fundas': [
      'juego_propietario_id', 'tipo_funda_id', 'cantidad_cartas', 'enfundadas',
    ],
    'juego_categoria': ['juego_id', 'categoria_id'],
  };

  /// Campos que en local se almacenan como `campo_server_id` en lugar de `campo_id`.
  static const Map<String, Map<String, String>> _localFieldMapping = {
    'muebles': {'habitacion_id': 'habitacion_server_id'},
    'ubicaciones': {'mueble_id': 'mueble_server_id'},
    'juegos': {
      'ubicacion_id': 'ubicacion_server_id',
      'juego_base_id': 'juego_base_server_id',
    },
    'juego_fundas': {
      'juego_id': 'juego_server_id',
      'tipo_funda_id': 'tipo_funda_server_id',
    },
    'juego_propietario': {
      'juego_id': 'juego_server_id',
      'propietario_id': 'propietario_server_id',
      'ubicacion_id': 'ubicacion_server_id',
    },
    'juego_propietario_fundas': {
      'juego_propietario_id': 'juego_propietario_server_id',
      'tipo_funda_id': 'tipo_funda_server_id',
    },
    'juego_categoria': {
      'juego_id': 'juego_server_id',
      'categoria_id': 'categoria_server_id',
    },
  };

  /// Campos booleanos que el servidor envía como true/false y SQLite guarda como 1/0.
  static const Map<String, List<String>> _boolFields = {
    'propietarios': ['es_principal'],
    'juegos': [
      'no_enfundar', 'es_expansion', 'independiente_idioma',
      'tradumaquetado', 'tradumaquetado_parcial', 'varias_copias', 'en_caja_base',
      'sin_abrir', 'print_and_play',
    ],
    'juego_fundas': ['enfundadas'],
    'juego_propietario': [
      'es_principal', 'no_enfundar', 'independiente_idioma',
      'tradumaquetado', 'tradumaquetado_parcial', 'sin_abrir', 'print_and_play',
    ],
    'juego_propietario_fundas': ['enfundadas'],
  };

  Future<SyncVerifyResult> verify() async {
    try {
      final response = await _api.get('/sync/verify');
      final remoteTables = response.data['tables'] as Map<String, dynamic>;

      final db = await DatabaseService().database;
      final results = <TableVerifyResult>[];

      for (final table in _tableFields.keys) {
        final remoteRecords = remoteTables[table] as List<dynamic>?;
        if (remoteRecords == null) continue;

        final remoteById = <int, Map<String, dynamic>>{};
        for (final r in remoteRecords) {
          final record = r as Map<String, dynamic>;
          remoteById[(record['id'] as num).toInt()] = record;
        }

        final localRows = await db.query(
          table,
          where: "server_id IS NOT NULL AND (pending_action IS NULL OR pending_action != 'delete')",
        );
        final localById = <int, Map<String, dynamic>>{};
        for (final row in localRows) {
          final sid = row['server_id'] as int?;
          if (sid != null) localById[sid] = row;
        }

        final remoteIds = remoteById.keys.toSet();
        final localIds = localById.keys.toSet();

        final missingInLocal = remoteIds.difference(localIds).toList()..sort();
        final missingInRemote = localIds.difference(remoteIds).toList()..sort();

        final commonIds = remoteIds.intersection(localIds);
        final dataDiffs = <RecordDiff>[];

        for (final id in commonIds) {
          final remoteRecord = remoteById[id]!;
          final localRecord = localById[id]!;

          final diffs = _compareRecord(table, localRecord, remoteRecord);
          if (diffs.isNotEmpty) {
            dataDiffs.add(RecordDiff(
              serverId: id,
              recordName: (remoteRecord['nombre'] ?? localRecord['nombre'])?.toString(),
              diffs: diffs,
            ));
          }
        }

        final pendingCreates = await _countPending(db, table, 'create');
        final pendingDeletes = await _countPending(db, table, 'delete');

        results.add(TableVerifyResult(
          tableName: table,
          localCount: localIds.length,
          remoteCount: remoteIds.length,
          missingInLocal: missingInLocal,
          missingInRemote: missingInRemote,
          dataDiffs: dataDiffs,
          pendingCreates: pendingCreates,
          pendingDeletes: pendingDeletes,
        ));
      }

      final outboxCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM sync_outbox'),
          ) ??
          0;

      return SyncVerifyResult(tables: results, outboxPending: outboxCount);
    } catch (e) {
      return SyncVerifyResult(tables: [], error: e.toString());
    }
  }

  List<FieldDiff> _compareRecord(
    String table,
    Map<String, dynamic> localRecord,
    Map<String, dynamic> remoteRecord,
  ) {
    final fields = _tableFields[table] ?? [];
    final fieldMapping = _localFieldMapping[table] ?? {};
    final boolFields = _boolFields[table] ?? [];
    final diffs = <FieldDiff>[];

    for (final field in fields) {
      final localField = fieldMapping[field] ?? field;
      final localVal = localRecord[localField];
      final remoteVal = remoteRecord[field];

      if (_valuesAreEqual(localVal, remoteVal, boolFields.contains(field))) {
        continue;
      }

      diffs.add(FieldDiff(
        field: field,
        localValue: _formatValue(localVal),
        remoteValue: _formatValue(remoteVal),
      ));
    }

    return diffs;
  }

  bool _valuesAreEqual(dynamic local, dynamic remote, bool isBoolField) {
    if (local == null && remote == null) return true;

    if (isBoolField) {
      return _toBool(local) == _toBool(remote);
    }

    // Normalizar para comparación
    final localStr = _normalize(local);
    final remoteStr = _normalize(remote);
    return localStr == remoteStr;
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  String? _normalize(dynamic value) {
    if (value == null) return null;
    // Listas (ej. `idiomas` que el servidor envía como array nativo): se
    // canonicalizan a JSON para poder compararlas con el texto JSON local.
    if (value is List || value is Map) {
      if (value is List && value.isEmpty) return null;
      if (value is Map && value.isEmpty) return null;
      return jsonEncode(value);
    }
    if (value is String) {
      if (value.isEmpty) return null;
      // Texto que representa un array/objeto JSON almacenado en SQLite
      // (ej. `idiomas` = '["castellano"]'): decodificar y recodificar para
      // obtener la misma forma canónica que el array nativo del servidor.
      final trimmed = value.trim();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List && decoded.isEmpty) return null;
          if (decoded is Map && decoded.isEmpty) return null;
          return jsonEncode(decoded);
        } catch (_) {}
      }
      return value;
    }
    if (value is double) {
      if (value == value.truncateToDouble()) return value.toInt().toString();
      return value.toString();
    }
    return value.toString();
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    final str = value.toString();
    if (str.length > 50) return '${str.substring(0, 50)}...';
    return str;
  }

  Future<int> _countPending(Database db, String table, String action) async {
    return Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM sync_outbox WHERE table_name = ? AND action = ?',
          [table, action],
        )) ??
        0;
  }
}
