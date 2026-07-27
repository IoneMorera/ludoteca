import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'outbox_dao.dart';

class CategoriaRow {
  final int localId;
  final int? serverId;
  final String nombre;
  final String? descripcion;

  CategoriaRow({
    required this.localId,
    required this.serverId,
    required this.nombre,
    this.descripcion,
  });

  factory CategoriaRow.fromMap(Map<String, dynamic> map) {
    return CategoriaRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'descripcion': descripcion,
      };
}

class CategoriaRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  CategoriaRepository(this._dbService, this._outbox);

  Future<List<CategoriaRow>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query('categorias', orderBy: 'nombre');
    return rows.map(CategoriaRow.fromMap).toList();
  }

  /// Returns a map of categoria local_id -> count of games in that category.
  Future<Map<int, int>> getJuegoCountByCategoria() async {
    final db = await _dbService.database;
    // Contamos considerando ambas vías de asociación: la tabla pivote
    // (juego_categoria) y la columna heredada juegos.categoria_local_id (que
    // rellena la importación de BGG). Así el número coincide con lo que muestra
    // el filtro por categoría.
    final rows = await db.rawQuery('''
      SELECT cat_id AS categoria_local_id, COUNT(DISTINCT juego_local_id) AS cnt
      FROM (
        SELECT jc.categoria_local_id AS cat_id, jc.juego_local_id AS juego_local_id
        FROM juego_categoria jc
        INNER JOIN juegos j ON j.local_id = jc.juego_local_id
        WHERE jc.categoria_local_id IS NOT NULL
        UNION
        SELECT j.categoria_local_id AS cat_id, j.local_id AS juego_local_id
        FROM juegos j
        WHERE j.categoria_local_id IS NOT NULL
      )
      GROUP BY cat_id
    ''');
    final result = <int, int>{};
    for (final r in rows) {
      final catLocalId = r['categoria_local_id'] as int?;
      if (catLocalId != null) {
        result[catLocalId] = (r['cnt'] as int?) ?? 0;
      }
    }
    return result;
  }

  Future<CategoriaRow?> getById(int localId) async {
    final db = await _dbService.database;
    final rows = await db.query('categorias',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return null;
    return CategoriaRow.fromMap(rows.first);
  }

  Future<CategoriaRow?> getByServerId(int serverId) async {
    final db = await _dbService.database;
    final rows = await db.query('categorias',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (rows.isEmpty) return null;
    return CategoriaRow.fromMap(rows.first);
  }

  Future<int> create({required String nombre, String? descripcion}) async {
    final db = await _dbService.database;
    final localId = await db.insert('categorias', {
      'nombre': nombre,
      'descripcion': descripcion,
      'dirty': 1,
      'pending_action': 'create',
    });
    await _outbox.enqueue(
      table: 'categorias',
      action: SyncAction.create,
      localId: localId,
      payload: {'nombre': nombre, 'descripcion': descripcion},
    );
    return localId;
  }

  Future<void> update(int localId, {required String nombre, String? descripcion}) async {
    final db = await _dbService.database;
    final existing = await db.query('categorias',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    await db.update('categorias', {
      'nombre': nombre,
      'descripcion': descripcion,
      'dirty': 1,
      'pending_action': 'update',
    }, where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'categorias',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {'nombre': nombre, 'descripcion': descripcion},
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  Future<void> delete(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query('categorias',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    await db.delete('categorias', where: 'local_id = ?', whereArgs: [localId]);
    if (serverId != null) {
      await _outbox.enqueue(
        table: 'categorias',
        action: SyncAction.delete,
        localId: localId,
        serverId: serverId,
      );
    } else {
      await _outbox.removeForLocalRow('categorias', localId);
    }
  }

  /// Upsert directo desde el snapshot del servidor (no genera outbox).
  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final existing = await db.query('categorias',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (existing.isEmpty) {
      await db.insert('categorias', {
        'server_id': serverId,
        'nombre': data['nombre'],
        'descripcion': data['descripcion'],
        'updated_at': data['updated_at'],
        'dirty': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update(
        'categorias',
        {
          'nombre': data['nombre'],
          'descripcion': data['descripcion'],
          'updated_at': data['updated_at'],
          'dirty': 0,
          'pending_action': null,
        },
        where: 'server_id = ?',
        whereArgs: [serverId],
      );
    }
  }

  Future<void> deleteByServerIds(List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('categorias',
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }
}
