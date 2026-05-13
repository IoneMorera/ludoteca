import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';

/// Acci\u00f3n de sincronizaci\u00f3n pendiente.
enum SyncAction { create, update, delete }

String syncActionToString(SyncAction action) => switch (action) {
      SyncAction.create => 'create',
      SyncAction.update => 'update',
      SyncAction.delete => 'delete',
    };

/// Operaci\u00f3n pendiente en la cola `sync_outbox`.
class OutboxOperation {
  final int id;
  final String clientOpId;
  final String table;
  final SyncAction action;
  final int? localId;
  final int? serverId;
  final Map<String, dynamic> payload;
  final String? baseUpdatedAt;
  final int attempts;
  final String? lastError;
  final String createdAt;

  OutboxOperation({
    required this.id,
    required this.clientOpId,
    required this.table,
    required this.action,
    required this.localId,
    required this.serverId,
    required this.payload,
    required this.baseUpdatedAt,
    required this.attempts,
    required this.lastError,
    required this.createdAt,
  });

  factory OutboxOperation.fromMap(Map<String, dynamic> map) {
    return OutboxOperation(
      id: map['id'] as int,
      clientOpId: map['client_op_id'] as String,
      table: map['table_name'] as String,
      action: _parseAction(map['action'] as String),
      localId: map['local_id'] as int?,
      serverId: map['server_id'] as int?,
      payload: map['payload_json'] != null
          ? Map<String, dynamic>.from(
              jsonDecode(map['payload_json'] as String) as Map)
          : <String, dynamic>{},
      baseUpdatedAt: map['base_updated_at'] as String?,
      attempts: (map['attempts'] as int?) ?? 0,
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  static SyncAction _parseAction(String s) => switch (s) {
        'create' => SyncAction.create,
        'update' => SyncAction.update,
        'delete' => SyncAction.delete,
        _ => SyncAction.update,
      };
}

/// DAO para la cola de operaciones pendientes (`sync_outbox`).
class OutboxDao {
  final DatabaseService _dbService;
  OutboxDao(this._dbService);

  Future<int> enqueue({
    required String table,
    required SyncAction action,
    int? localId,
    int? serverId,
    Map<String, dynamic>? payload,
    String? baseUpdatedAt,
  }) async {
    final db = await _dbService.database;
    return db.insert('sync_outbox', {
      'client_op_id': _generateOpId(),
      'table_name': table,
      'action': syncActionToString(action),
      'local_id': localId,
      'server_id': serverId,
      'payload_json': payload != null ? jsonEncode(payload) : null,
      'base_updated_at': baseUpdatedAt,
      'attempts': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<OutboxOperation>> pending({int limit = 100}) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'sync_outbox',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(OutboxOperation.fromMap).toList();
  }

  Future<void> remove(int id) async {
    final db = await _dbService.database;
    await db.delete('sync_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markError(int id, String error) async {
    final db = await _dbService.database;
    await db.rawUpdate(
      'UPDATE sync_outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  /// Reasigna `server_id` en operaciones encoladas que apuntan al `localId`
  /// indicado. Necesario tras un create cuando otras operaciones dependen
  /// del registro reci\u00e9n creado.
  Future<void> assignServerId({
    required String table,
    required int localId,
    required int serverId,
  }) async {
    final db = await _dbService.database;
    await db.rawUpdate(
      'UPDATE sync_outbox SET server_id = ? WHERE table_name = ? AND local_id = ? AND server_id IS NULL',
      [serverId, table, localId],
    );
  }

  Future<int> count() async {
    final db = await _dbService.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS c FROM sync_outbox');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  String _generateOpId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now & 0xFFFFFF).toRadixString(36);
    return 'op_${now.toRadixString(36)}_$rand';
  }
}
