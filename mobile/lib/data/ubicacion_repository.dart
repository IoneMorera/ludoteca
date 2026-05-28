import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'outbox_dao.dart';

class HabitacionRow {
  final int localId;
  final int? serverId;
  final String nombre;

  HabitacionRow({
    required this.localId,
    required this.serverId,
    required this.nombre,
  });

  factory HabitacionRow.fromMap(Map<String, dynamic> map) {
    return HabitacionRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      nombre: map['nombre'] as String,
    );
  }
}

class MuebleRow {
  final int localId;
  final int? serverId;
  final int? habitacionServerId;
  final int? habitacionLocalId;
  final String nombre;

  MuebleRow({
    required this.localId,
    required this.serverId,
    required this.habitacionServerId,
    required this.habitacionLocalId,
    required this.nombre,
  });

  factory MuebleRow.fromMap(Map<String, dynamic> map) {
    return MuebleRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      habitacionServerId: map['habitacion_server_id'] as int?,
      habitacionLocalId: map['habitacion_local_id'] as int?,
      nombre: map['nombre'] as String,
    );
  }
}

class UbicacionRow {
  final int localId;
  final int? serverId;
  final int? muebleServerId;
  final int? muebleLocalId;
  final String nombre;
  final MuebleRow? mueble;
  final HabitacionRow? habitacion;

  UbicacionRow({
    required this.localId,
    required this.serverId,
    required this.muebleServerId,
    required this.muebleLocalId,
    required this.nombre,
    this.mueble,
    this.habitacion,
  });

  String get rutaCompleta {
    if (mueble == null) return nombre;
    final habNombre = habitacion?.nombre ?? '';
    return '$habNombre \u203a ${mueble!.nombre} \u203a $nombre';
  }

  factory UbicacionRow.fromMap(Map<String, dynamic> map) {
    return UbicacionRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      muebleServerId: map['mueble_server_id'] as int?,
      muebleLocalId: map['mueble_local_id'] as int?,
      nombre: map['nombre'] as String,
    );
  }
}

class UbicacionRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  UbicacionRepository(this._dbService, this._outbox);

  Future<List<HabitacionRow>> listHabitaciones() async {
    final db = await _dbService.database;
    final rows = await db.query('habitaciones', orderBy: 'nombre');
    return rows
        .map((r) => HabitacionRow(
              localId: r['local_id'] as int,
              serverId: r['server_id'] as int?,
              nombre: r['nombre'] as String,
            ))
        .toList();
  }

  Future<List<MuebleRow>> listMuebles() async {
    final db = await _dbService.database;
    final rows = await db.query('muebles', orderBy: 'nombre');
    return rows.map((r) => MuebleRow.fromMap(r)).toList();
  }

  Future<int> createHabitacion({required String nombre}) async {
    final db = await _dbService.database;
    final localId = await db.insert('habitaciones', {
      'nombre': nombre,
      'dirty': 1,
      'pending_action': 'create',
    });
    await _outbox.enqueue(
      table: 'habitaciones',
      action: SyncAction.create,
      localId: localId,
      payload: {'nombre': nombre},
    );
    return localId;
  }

  Future<int> createMueble({
    required int habitacionLocalId,
    required String nombre,
  }) async {
    final db = await _dbService.database;
    final hab = await db.query('habitaciones',
        where: 'local_id = ?', whereArgs: [habitacionLocalId], limit: 1);
    if (hab.isEmpty) {
      throw StateError('La habitaci\u00f3n no existe en la base local');
    }
    final habServerId = hab.first['server_id'] as int?;

    final localId = await db.insert('muebles', {
      'habitacion_local_id': habitacionLocalId,
      'habitacion_server_id': habServerId,
      'nombre': nombre,
      'dirty': 1,
      'pending_action': 'create',
    });
    await _outbox.enqueue(
      table: 'muebles',
      action: SyncAction.create,
      localId: localId,
      payload: {
        'nombre': nombre,
        ...?(habServerId != null ? {'habitacion_id': habServerId} : null),
      },
    );
    return localId;
  }

  Future<int> createUbicacion({
    required int muebleLocalId,
    required String nombre,
  }) async {
    final db = await _dbService.database;
    final rows = await db.query('muebles',
        where: 'local_id = ?', whereArgs: [muebleLocalId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('El mueble no existe en la base local');
    }
    final muebleServerId = rows.first['server_id'] as int?;

    final localId = await db.insert('ubicaciones', {
      'mueble_local_id': muebleLocalId,
      'mueble_server_id': muebleServerId,
      'nombre': nombre,
      'dirty': 1,
      'pending_action': 'create',
    });
    await _outbox.enqueue(
      table: 'ubicaciones',
      action: SyncAction.create,
      localId: localId,
      payload: {
        'nombre': nombre,
        ...?(muebleServerId != null ? {'mueble_id': muebleServerId} : null),
      },
    );
    return localId;
  }

  Future<List<UbicacionRow>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT u.local_id, u.server_id, u.mueble_server_id, u.mueble_local_id,
             u.nombre,
             m.local_id AS m_local, m.server_id AS m_server,
             m.habitacion_server_id AS m_hab_server,
             m.habitacion_local_id AS m_hab_local, m.nombre AS m_nombre,
             h.local_id AS h_local, h.server_id AS h_server, h.nombre AS h_nombre
      FROM ubicaciones u
      LEFT JOIN muebles m ON m.local_id = u.mueble_local_id
      LEFT JOIN habitaciones h ON h.local_id = m.habitacion_local_id
      ORDER BY h.nombre, m.nombre, u.nombre
    ''');
    return rows.map((r) {
      MuebleRow? mueble;
      HabitacionRow? habitacion;
      if (r['m_local'] != null) {
        mueble = MuebleRow(
          localId: r['m_local'] as int,
          serverId: r['m_server'] as int?,
          habitacionServerId: r['m_hab_server'] as int?,
          habitacionLocalId: r['m_hab_local'] as int?,
          nombre: r['m_nombre'] as String,
        );
      }
      if (r['h_local'] != null) {
        habitacion = HabitacionRow(
          localId: r['h_local'] as int,
          serverId: r['h_server'] as int?,
          nombre: r['h_nombre'] as String,
        );
      }
      return UbicacionRow(
        localId: r['local_id'] as int,
        serverId: r['server_id'] as int?,
        muebleServerId: r['mueble_server_id'] as int?,
        muebleLocalId: r['mueble_local_id'] as int?,
        nombre: r['nombre'] as String,
        mueble: mueble,
        habitacion: habitacion,
      );
    }).toList();
  }

  Future<UbicacionRow?> getByServerId(int serverId) async {
    final all = await getAll();
    try {
      return all.firstWhere((u) => u.serverId == serverId);
    } catch (_) {
      return null;
    }
  }

  Future<UbicacionRow?> getByLocalId(int localId) async {
    final all = await getAll();
    try {
      return all.firstWhere((u) => u.localId == localId);
    } catch (_) {
      return null;
    }
  }

  // upsert para los tres niveles (habitaciones, muebles, ubicaciones).
  Future<void> upsertHabitacionFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final existing = await db.query('habitaciones',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    final values = {
      'server_id': serverId,
      'nombre': data['nombre'],
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    if (existing.isEmpty) {
      await db.insert('habitaciones', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update('habitaciones', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> upsertMuebleFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final habServerId = data['habitacion_id'] as int?;
    int? habLocalId;
    if (habServerId != null) {
      final hab = await db.query('habitaciones',
          where: 'server_id = ?', whereArgs: [habServerId], limit: 1);
      if (hab.isNotEmpty) habLocalId = hab.first['local_id'] as int;
    }
    final existing = await db.query('muebles',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    final values = {
      'server_id': serverId,
      'habitacion_server_id': habServerId,
      'habitacion_local_id': habLocalId,
      'nombre': data['nombre'],
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    if (existing.isEmpty) {
      await db.insert('muebles', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update('muebles', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> upsertUbicacionFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final muebleServerId = data['mueble_id'] as int?;
    int? muebleLocalId;
    if (muebleServerId != null) {
      final m = await db.query('muebles',
          where: 'server_id = ?', whereArgs: [muebleServerId], limit: 1);
      if (m.isNotEmpty) muebleLocalId = m.first['local_id'] as int;
    }
    final existing = await db.query('ubicaciones',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    final values = {
      'server_id': serverId,
      'mueble_server_id': muebleServerId,
      'mueble_local_id': muebleLocalId,
      'nombre': data['nombre'],
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    if (existing.isEmpty) {
      await db.insert('ubicaciones', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update('ubicaciones', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> deleteByServerIds(String table, List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete(table,
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }
}
