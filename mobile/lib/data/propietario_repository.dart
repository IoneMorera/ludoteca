import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'outbox_dao.dart';

class PropietarioRow {
  final int localId;
  final int? serverId;
  final String nombre;
  final String? bggUsername;
  final bool esPrincipal;

  PropietarioRow({
    required this.localId,
    required this.serverId,
    required this.nombre,
    this.bggUsername,
    this.esPrincipal = false,
  });

  factory PropietarioRow.fromMap(Map<String, dynamic> map) {
    return PropietarioRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      nombre: map['nombre'] as String,
      bggUsername: map['bgg_username'] as String?,
      esPrincipal: (map['es_principal'] as int? ?? 0) == 1,
    );
  }
}

class PropietarioRepository {
  final DatabaseService _dbService;
  // ignore: unused_field
  final OutboxDao _outbox;

  PropietarioRepository(this._dbService, this._outbox);

  Future<List<PropietarioRow>> getAll() async {
    final db = await _dbService.database;
    final rows = await db.query('propietarios', orderBy: 'nombre');
    return rows.map(PropietarioRow.fromMap).toList();
  }

  Future<PropietarioRow?> getByServerId(int serverId) async {
    final db = await _dbService.database;
    final rows = await db.query('propietarios',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (rows.isEmpty) return null;
    return PropietarioRow.fromMap(rows.first);
  }

  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final existing = await db.query('propietarios',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    final values = {
      'server_id': serverId,
      'nombre': data['nombre'],
      'bgg_username': data['bgg_username'],
      'es_principal': (data['es_principal'] == true) ? 1 : 0,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    if (existing.isEmpty) {
      await db.insert('propietarios', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.update('propietarios', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> deleteByServerIds(List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete('propietarios',
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }
}
