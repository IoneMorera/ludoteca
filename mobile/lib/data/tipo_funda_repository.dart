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
  // ignore: unused_field
  final OutboxDao _outbox;

  TipoFundaRepository(this._dbService, this._outbox);

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
