import 'package:sqflite/sqflite.dart';

import '../models/evento.dart';
import '../services/database_service.dart';
import 'outbox_dao.dart';

class EventoRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  EventoRepository(this._dbService, this._outbox);

  Future<List<Evento>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query('eventos', orderBy: 'fecha_inicio ASC');
    return _hydrateAll(rows);
  }

  Future<List<Evento>> getFuturos() async {
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'eventos',
      where: "estado = ? AND fecha_fin >= ?",
      whereArgs: [EventoEstado.abierto, now],
      orderBy: 'fecha_inicio ASC',
    );
    return _hydrateAll(rows);
  }

  Future<List<Evento>> getPasados() async {
    await _promoteExpiredAbiertos();
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'eventos',
      where: "fecha_fin < ? OR estado IN (?, ?)",
      whereArgs: [now, EventoEstado.pendienteColocar, EventoEstado.cerrado],
      orderBy: 'fecha_fin DESC',
    );
    return _hydrateAll(rows);
  }

  /// Eventos futuros (abiertos) + eventos cerrados.
  Future<int> countFuturosYCerrados() async {
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM eventos
      WHERE (estado = ? AND fecha_fin >= ?) OR estado = ?
      ''',
      [EventoEstado.abierto, now, EventoEstado.cerrado],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countPendientesColocar() async {
    await _promoteExpiredAbiertos();
    final db = await _dbService.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM eventos WHERE estado = ?",
      [EventoEstado.pendienteColocar],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Evento?> getProximoEvento() async {
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'eventos',
      where: "estado = ? AND fecha_fin >= ?",
      whereArgs: [EventoEstado.abierto, now],
      orderBy: 'fecha_inicio ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final list = await _hydrateAll(rows);
    return list.firstOrNull;
  }

  Future<Evento?> getByLocalId(int localId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'eventos',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final list = await _hydrateAll(rows);
    return list.firstOrNull;
  }

  Future<int> save(Evento evento) async {
    final db = await _dbService.database;
    final values = evento.toMap();
    final isCreate = evento.localId == null;

    int localId;
    if (isCreate) {
      values['dirty'] = 1;
      values['pending_action'] = 'create';
      localId = await db.insert('eventos', values);
      await _outbox.enqueue(
        table: 'eventos',
        action: SyncAction.create,
        localId: localId,
        payload: _payloadForServer(values),
      );
    } else {
      localId = evento.localId!;
      values['dirty'] = 1;
      values['pending_action'] = 'update';
      await db.update('eventos', values,
          where: 'local_id = ?', whereArgs: [localId]);

      final existing = await db.query('eventos',
          where: 'local_id = ?', whereArgs: [localId], limit: 1);
      final serverId = existing.first['server_id'] as int?;
      final baseUpdatedAt = existing.first['updated_at'] as String?;

      if (serverId != null) {
        await _outbox.enqueue(
          table: 'eventos',
          action: SyncAction.update,
          localId: localId,
          serverId: serverId,
          payload: _payloadForServer(values),
          baseUpdatedAt: baseUpdatedAt,
        );
      } else {
        await _outbox.removeForLocalRow('eventos', localId);
        await _outbox.enqueue(
          table: 'eventos',
          action: SyncAction.create,
          localId: localId,
          payload: _payloadForServer(values),
        );
      }
    }
    return localId;
  }

  Future<void> addJuego(int eventoLocalId, int juegoLocalId) async {
    final db = await _dbService.database;

    final existing = await db.query(
      'evento_juegos',
      where: 'evento_local_id = ? AND juego_local_id = ?',
      whereArgs: [eventoLocalId, juegoLocalId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final eventoRow = await db.query('eventos',
        where: 'local_id = ?', whereArgs: [eventoLocalId], limit: 1);
    if (eventoRow.isEmpty) return;
    final eventoServerId = eventoRow.first['server_id'] as int?;

    final juegoRow = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [juegoLocalId], limit: 1);
    if (juegoRow.isEmpty) return;
    final juegoServerId = juegoRow.first['server_id'] as int?;

    final localId = await db.insert('evento_juegos', {
      'evento_local_id': eventoLocalId,
      'evento_server_id': eventoServerId,
      'juego_local_id': juegoLocalId,
      'juego_server_id': juegoServerId,
      'dirty': 1,
      'pending_action': 'create',
    });

    await _outbox.enqueue(
      table: 'evento_juegos',
      action: SyncAction.create,
      localId: localId,
      payload: {
        'evento_id': eventoServerId,
        'juego_id': juegoServerId,
      },
    );
  }

  Future<void> removeJuego(int eventoLocalId, int juegoLocalId) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'evento_juegos',
      where: 'evento_local_id = ? AND juego_local_id = ?',
      whereArgs: [eventoLocalId, juegoLocalId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final localId = rows.first['local_id'] as int;
    final serverId = rows.first['server_id'] as int?;

    await db.delete('evento_juegos',
        where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'evento_juegos',
        action: SyncAction.delete,
        localId: localId,
        serverId: serverId,
      );
    } else {
      await _outbox.removeForLocalRow('evento_juegos', localId);
    }
  }

  Future<void> cerrarEvento(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query('eventos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;

    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    await db.update(
      'eventos',
      {
        'estado': EventoEstado.cerrado,
        'dirty': 1,
        'pending_action': 'update',
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'eventos',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {'estado': EventoEstado.cerrado},
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  Future<void> delete(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query('eventos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;

    final serverId = existing.first['server_id'] as int?;

    final pivotRows = await db.query('evento_juegos',
        where: 'evento_local_id = ?', whereArgs: [localId]);
    for (final row in pivotRows) {
      final pivotLocalId = row['local_id'] as int;
      final pivotServerId = row['server_id'] as int?;
      await db.delete('evento_juegos',
          where: 'local_id = ?', whereArgs: [pivotLocalId]);
      if (pivotServerId != null) {
        await _outbox.enqueue(
          table: 'evento_juegos',
          action: SyncAction.delete,
          localId: pivotLocalId,
          serverId: pivotServerId,
        );
      } else {
        await _outbox.removeForLocalRow('evento_juegos', pivotLocalId);
      }
    }

    await db.delete('eventos', where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'eventos',
        action: SyncAction.delete,
        localId: localId,
        serverId: serverId,
      );
    } else {
      await _outbox.removeForLocalRow('eventos', localId);
    }
  }

  Future<void> upsertEventoFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final values = {
      'server_id': serverId,
      'nombre': data['nombre'],
      'fecha_inicio': data['fecha_inicio'],
      'fecha_fin': data['fecha_fin'],
      'localizacion': data['localizacion'],
      'estado': data['estado'] ?? EventoEstado.abierto,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    final existing = await db.query('eventos',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);

    if (existing.isEmpty) {
      await db.insert('eventos', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final isDirty = ((existing.first['dirty'] as int?) ?? 0) == 1;
      if (isDirty) {
        values.remove('estado');
        values.remove('dirty');
        values.remove('pending_action');
      }
      await db.update('eventos', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> upsertEventoJuegoFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final eventoLocalId = await _localIdFor(db, 'eventos', data['evento_id']);
    final juegoLocalId = await _localIdFor(db, 'juegos', data['juego_id']);

    final values = {
      'server_id': serverId,
      'evento_server_id': data['evento_id'],
      'evento_local_id': eventoLocalId,
      'juego_server_id': data['juego_id'],
      'juego_local_id': juegoLocalId,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    Map<String, dynamic>? targetRow;
    int? targetLocalId;

    final byServer = await db.query('evento_juegos',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (byServer.isNotEmpty) {
      targetRow = byServer.first;
      targetLocalId = targetRow['local_id'] as int;
    } else if (eventoLocalId != null && juegoLocalId != null) {
      final byPair = await db.query(
        'evento_juegos',
        where: 'evento_local_id = ? AND juego_local_id = ?',
        whereArgs: [eventoLocalId, juegoLocalId],
        orderBy: 'local_id ASC',
      );
      if (byPair.isNotEmpty) {
        targetRow = byPair.first;
        targetLocalId = targetRow['local_id'] as int;
      }
    }

    if (targetLocalId != null && targetRow != null) {
      final hadNoServerId = (targetRow['server_id'] as int?) == null;
      await db.update('evento_juegos', values,
          where: 'local_id = ?', whereArgs: [targetLocalId]);
      if (hadNoServerId) {
        await _outbox.removeForLocalRow('evento_juegos', targetLocalId);
      }
      return;
    }

    await db.insert('evento_juegos', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByServerIds(String table, List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete(table,
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }

  Future<void> commitServerId({
    required String table,
    required int localId,
    required int serverId,
    String? updatedAt,
  }) async {
    final db = await _dbService.database;
    await db.update(
      table,
      {
        'server_id': serverId,
        'updated_at': updatedAt,
        'dirty': 0,
        'pending_action': null,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> markClean({
    required String table,
    required int localId,
    String? updatedAt,
  }) async {
    final db = await _dbService.database;
    await db.update(
      table,
      {'dirty': 0, 'pending_action': null, 'updated_at': updatedAt},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<void> _promoteExpiredAbiertos() async {
    final db = await _dbService.database;
    final now = DateTime.now().toIso8601String();
    final expired = await db.query(
      'eventos',
      where: "estado = ? AND fecha_fin < ?",
      whereArgs: [EventoEstado.abierto, now],
    );

    for (final row in expired) {
      final localId = row['local_id'] as int;
      final serverId = row['server_id'] as int?;
      final baseUpdatedAt = row['updated_at'] as String?;

      await db.update(
        'eventos',
        {
          'estado': EventoEstado.pendienteColocar,
          'dirty': 1,
          'pending_action': 'update',
        },
        where: 'local_id = ?',
        whereArgs: [localId],
      );

      if (serverId != null) {
        await _outbox.enqueue(
          table: 'eventos',
          action: SyncAction.update,
          localId: localId,
          serverId: serverId,
          payload: {'estado': EventoEstado.pendienteColocar},
          baseUpdatedAt: baseUpdatedAt,
        );
      }
    }
  }

  Future<List<Evento>> _hydrateAll(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    final db = await _dbService.database;
    final localIds = rows.map((r) => r['local_id'] as int).toList();
    final placeholders = List.filled(localIds.length, '?').join(',');

    final juegosByEvento = <int, List<EventoJuego>>{};
    final ejRows = await db.rawQuery('''
      SELECT ej.*, j.nombre AS juego_nombre, j.imagen AS juego_imagen
      FROM evento_juegos ej
      INNER JOIN juegos j ON j.local_id = ej.juego_local_id
      WHERE ej.evento_local_id IN ($placeholders)
      ORDER BY j.nombre_norm, j.nombre
    ''', localIds);

    for (final r in ejRows) {
      final eventoLocalId = r['evento_local_id'] as int;
      juegosByEvento.putIfAbsent(eventoLocalId, () => []).add(
            EventoJuego.fromMap(r),
          );
    }

    return rows
        .map((r) {
          final localId = r['local_id'] as int;
          return Evento.fromMap(r, juegos: juegosByEvento[localId] ?? const []);
        })
        .toList();
  }

  Future<int?> _localIdFor(
      Database db, String table, dynamic serverId) async {
    if (serverId == null) return null;
    final rows = await db.query(table,
        columns: ['local_id'],
        where: 'server_id = ?',
        whereArgs: [serverId],
        limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['local_id'] as int?;
  }

  Map<String, dynamic> _payloadForServer(Map<String, dynamic> values) {
    return {
      'nombre': values['nombre'],
      'fecha_inicio': values['fecha_inicio'],
      'fecha_fin': values['fecha_fin'],
      'localizacion': values['localizacion'],
      'estado': values['estado'],
    };
  }
}
