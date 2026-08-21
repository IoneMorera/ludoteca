import 'package:sqflite/sqflite.dart';

import '../services/database_service.dart';
import 'outbox_dao.dart';

class BggExpansionRow {
  final int localId;
  final int? serverId;
  final int baseBggId;
  final int expansionBggId;
  final String nombre;
  final int? anio;
  final String? imagen;
  final int? minJugadores;
  final int? maxJugadores;
  final bool ignorada;

  BggExpansionRow({
    required this.localId,
    required this.serverId,
    required this.baseBggId,
    required this.expansionBggId,
    required this.nombre,
    this.anio,
    this.imagen,
    this.minJugadores,
    this.maxJugadores,
    this.ignorada = false,
  });

  factory BggExpansionRow.fromMap(Map<String, dynamic> map) {
    return BggExpansionRow(
      localId: map['local_id'] as int,
      serverId: map['server_id'] as int?,
      baseBggId: map['base_bgg_id'] as int,
      expansionBggId: map['expansion_bgg_id'] as int,
      nombre: map['nombre'] as String,
      anio: map['anio'] as int?,
      imagen: map['imagen'] as String?,
      minJugadores: map['min_jugadores'] as int?,
      maxJugadores: map['max_jugadores'] as int?,
      ignorada: (map['ignorada'] as int? ?? 0) == 1,
    );
  }

  String? get imagenUrl {
    final img = imagen;
    if (img == null || img.isEmpty) return null;
    if (img.startsWith('http://') || img.startsWith('https://')) return img;
    return null;
  }

  Map<String, dynamic> toBggPrefill({required int juegoBaseLocalId}) {
    return {
      'name': nombre,
      'bgg_id': expansionBggId,
      'year': anio,
      'image': imagen,
      'min_players': minJugadores,
      'max_players': maxJugadores,
      'es_expansion': true,
      'juego_base_local_id': juegoBaseLocalId,
    };
  }
}

class BggExpansionGroup {
  final int baseBggId;
  final String baseNombre;
  final int? baseLocalId;
  final List<BggExpansionRow> expansiones;

  BggExpansionGroup({
    required this.baseBggId,
    required this.baseNombre,
    required this.baseLocalId,
    required this.expansiones,
  });
}

class BggExpansionRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  BggExpansionRepository(this._dbService, this._outbox);

  static const String _faltantesWhere = '''
    e.ignorada = 0
    AND NOT EXISTS (
      SELECT 1 FROM juegos j WHERE j.bgg_id = e.expansion_bgg_id
    )
  ''';

  Future<List<BggExpansionRow>> faltantesDe(int baseBggId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery('''
      SELECT e.* FROM bgg_expansiones e
      WHERE e.base_bgg_id = ?
        AND $_faltantesWhere
      ORDER BY e.nombre COLLATE NOCASE
    ''', [baseBggId]);
    return rows.map(BggExpansionRow.fromMap).toList();
  }

  Future<int> countNuevasDelAnio() async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final currentYear = now.year;
    final nextYear = currentYear + 1;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM bgg_expansiones e
      WHERE $_faltantesWhere
        AND e.anio IS NOT NULL
        AND e.anio IN (?, ?)
    ''', [currentYear, nextYear]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<BggExpansionGroup>> nuevasDelAnioAgrupadas() async {
    final db = await _dbService.database;
    final now = DateTime.now();
    final currentYear = now.year;
    final nextYear = currentYear + 1;
    final rows = await db.rawQuery('''
      SELECT e.*, j.local_id AS base_local_id, j.nombre AS base_nombre
      FROM bgg_expansiones e
      INNER JOIN juegos j ON j.bgg_id = e.base_bgg_id
      WHERE $_faltantesWhere
        AND e.anio IS NOT NULL
        AND e.anio IN (?, ?)
      ORDER BY j.nombre COLLATE NOCASE, e.nombre COLLATE NOCASE
    ''', [currentYear, nextYear]);

    final groups = <int, BggExpansionGroup>{};
    for (final row in rows) {
      final baseBggId = row['base_bgg_id'] as int;
      final expansion = BggExpansionRow.fromMap(row);
      final existing = groups[baseBggId];
      if (existing == null) {
        groups[baseBggId] = BggExpansionGroup(
          baseBggId: baseBggId,
          baseNombre: row['base_nombre'] as String? ?? 'Juego base',
          baseLocalId: row['base_local_id'] as int?,
          expansiones: [expansion],
        );
      } else {
        groups[baseBggId] = BggExpansionGroup(
          baseBggId: existing.baseBggId,
          baseNombre: existing.baseNombre,
          baseLocalId: existing.baseLocalId,
          expansiones: [...existing.expansiones, expansion],
        );
      }
    }
    return groups.values.toList();
  }

  Future<void> marcarIgnorada(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query(
      'bgg_expansiones',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (existing.isEmpty) return;

    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    await db.update(
      'bgg_expansiones',
      {
        'ignorada': 1,
        'dirty': 1,
        'pending_action': 'update',
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'bgg_expansiones',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {'ignorada': true},
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  Future<void> upsertFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = (data['id'] as num).toInt();
    final values = {
      'server_id': serverId,
      'base_bgg_id': (data['base_bgg_id'] as num).toInt(),
      'expansion_bgg_id': (data['expansion_bgg_id'] as num).toInt(),
      'nombre': data['nombre'],
      'anio': data['anio'] as int?,
      'imagen': data['imagen'],
      'min_jugadores': data['min_jugadores'] as int?,
      'max_jugadores': data['max_jugadores'] as int?,
      'ignorada': (data['ignorada'] == true) ? 1 : 0,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    final existing = await db.query(
      'bgg_expansiones',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert(
        'bgg_expansiones',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        'bgg_expansiones',
        values,
        where: 'server_id = ?',
        whereArgs: [serverId],
      );
    }
  }

  Future<void> deleteByServerIds(List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete(
      'bgg_expansiones',
      where: 'server_id IN ($placeholders)',
      whereArgs: serverIds,
    );
  }
}
