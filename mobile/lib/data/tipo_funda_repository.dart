import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'outbox_dao.dart';

class TipoFundaRow {
  final int localId;
  final int? serverId;
  final String nombre;
  final int anchoMm;
  final int altoMm;

  TipoFundaRow({
    required this.localId,
    required this.serverId,
    required this.nombre,
    required this.anchoMm,
    required this.altoMm,
  });

  factory TipoFundaRow.fromMap(Map<String, dynamic> map) {
    return TipoFundaRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      nombre: map['nombre'] as String,
      anchoMm: (map['ancho_mm'] as int?) ?? 0,
      altoMm: (map['alto_mm'] as int?) ?? 0,
    );
  }

  String get textoCompleto => '$nombre ($anchoMm x $altoMm mm)';
}

class TipoFundaRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  TipoFundaRepository(this._dbService, this._outbox);

  Future<int> create({
    required String nombre,
    required int anchoMm,
    required int altoMm,
  }) async {
    final db = await _dbService.database;
    final localId = await db.insert('tipos_funda', {
      'nombre': nombre,
      'ancho_mm': anchoMm,
      'alto_mm': altoMm,
      'dirty': 1,
      'pending_action': 'create',
    });
    await _outbox.enqueue(
      table: 'tipos_funda',
      action: SyncAction.create,
      localId: localId,
      payload: {'nombre': nombre, 'ancho_mm': anchoMm, 'alto_mm': altoMm},
    );
    return localId;
  }

  Future<void> update(
    int localId, {
    required String nombre,
    required int anchoMm,
    required int altoMm,
  }) async {
    final db = await _dbService.database;
    final existing = await db.query('tipos_funda',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    await db.update('tipos_funda', {
      'nombre': nombre,
      'ancho_mm': anchoMm,
      'alto_mm': altoMm,
      'dirty': 1,
      'pending_action': 'update',
    }, where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'tipos_funda',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {'nombre': nombre, 'ancho_mm': anchoMm, 'alto_mm': altoMm},
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  Future<void> delete(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query('tipos_funda',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    await db.delete('tipos_funda', where: 'local_id = ?', whereArgs: [localId]);
    if (serverId != null) {
      await _outbox.enqueue(
        table: 'tipos_funda',
        action: SyncAction.delete,
        localId: localId,
        serverId: serverId,
      );
    } else {
      await _outbox.removeForLocalRow('tipos_funda', localId);
    }
  }

  /// Devuelve el nº de fundas de juego que usan cada tipo (local_id -> count),
  /// sumando tanto fundas a nivel de juego como por copia de propietario.
  Future<Map<int, int>> getUsoCount() async {
    final db = await _dbService.database;
    final result = <int, int>{};
    final rows = await db.rawQuery('''
      SELECT tipo_funda_local_id AS tid, COUNT(*) AS c FROM juego_fundas
      WHERE tipo_funda_local_id IS NOT NULL
      GROUP BY tipo_funda_local_id
    ''');
    for (final r in rows) {
      final tid = r['tid'] as int?;
      if (tid != null) result[tid] = (r['c'] as int?) ?? 0;
    }
    final rows2 = await db.rawQuery('''
      SELECT tipo_funda_local_id AS tid, COUNT(*) AS c FROM juego_propietario_fundas
      WHERE tipo_funda_local_id IS NOT NULL
      GROUP BY tipo_funda_local_id
    ''');
    for (final r in rows2) {
      final tid = r['tid'] as int?;
      if (tid != null) result[tid] = (result[tid] ?? 0) + ((r['c'] as int?) ?? 0);
    }
    return result;
  }

  Future<List<TipoFundaRow>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query('tipos_funda', orderBy: 'alto_mm, ancho_mm, nombre');
    return rows.map(TipoFundaRow.fromMap).toList();
  }

  Future<TipoFundaRow?> getByServerId(int serverId) async {
    final db = await _dbService.database;
    final rows = await db.query('tipos_funda',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (rows.isEmpty) return null;
    return TipoFundaRow.fromMap(rows.first);
  }

  Future<TipoFundaRow?> getByLocalId(int localId) async {
    final db = await _dbService.database;
    final rows = await db.query('tipos_funda',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return null;
    return TipoFundaRow.fromMap(rows.first);
  }

  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final existing = await db.query('tipos_funda',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    final values = {
      'server_id': serverId,
      'nombre': data['nombre'],
      'ancho_mm': data['ancho_mm'],
      'alto_mm': data['alto_mm'],
      'descripcion': data['descripcion'],
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    if (existing.isEmpty) {
      await db.insert('tipos_funda', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update('tipos_funda', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> deleteByServerIds(List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('tipos_funda',
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }
}
