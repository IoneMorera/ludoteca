import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/juego.dart';
import '../services/database_service.dart';
import 'outbox_dao.dart';
import 'ubicacion_repository.dart';

/// Repositorio de juegos sobre la BBDD local.
///
/// Devuelve modelos `Juego` ya enriquecidos con sus relaciones (categor\u00eda,
/// ubicaci\u00f3n con jerarqu\u00eda completa, propietarios y fundas).
///
/// Toda escritura escribe primero en local y encola la operaci\u00f3n en el
/// `sync_outbox` para que `SyncService` la propague al servidor.
class JuegoRepository {
  final DatabaseService _dbService;
  final OutboxDao _outbox;

  JuegoRepository(this._dbService, this._outbox);

  // ---------- lectura ----------

  Future<int> count({String? buscar, String? estado, bool? esExpansion, int? categoriaLocalId}) async {
    final db = await _dbService.database;
    final where = <String>[];
    final args = <dynamic>[];
    if (buscar != null && buscar.isNotEmpty) {
      where.add('j.nombre LIKE ?');
      args.add('%$buscar%');
    }
    if (estado != null && estado.isNotEmpty) {
      where.add('j.estado = ?');
      args.add(estado);
    }
    if (esExpansion == true) {
      where.add('j.es_expansion = 1');
    } else if (esExpansion == false) {
      where.add('j.es_expansion = 0');
    }
    if (categoriaLocalId != null) {
      where.add('EXISTS (SELECT 1 FROM juego_categoria jc WHERE jc.juego_local_id = j.local_id AND jc.categoria_local_id = ?)');
      args.add(categoriaLocalId);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM juegos j $whereSql', args);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Juego>> search({
    String? buscar,
    int page = 1,
    int perPage = 50,
    bool soloBase = false,
    String? estado,
    bool? esExpansion,
    int? categoriaLocalId,
  }) async {
    final db = await _dbService.database;
    final where = <String>[];
    final args = <dynamic>[];
    if (buscar != null && buscar.isNotEmpty) {
      where.add('j.nombre LIKE ?');
      args.add('%$buscar%');
    }
    if (soloBase) {
      where.add('j.es_expansion = 0');
    }
    if (estado != null && estado.isNotEmpty) {
      where.add('j.estado = ?');
      args.add(estado);
    }
    if (esExpansion == true) {
      where.add('j.es_expansion = 1');
    } else if (esExpansion == false) {
      where.add('j.es_expansion = 0');
    }
    if (categoriaLocalId != null) {
      where.add('EXISTS (SELECT 1 FROM juego_categoria jc WHERE jc.juego_local_id = j.local_id AND jc.categoria_local_id = ?)');
      args.add(categoriaLocalId);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final offset = (page - 1) * perPage;
    final rows = await db.rawQuery(
      'SELECT j.* FROM juegos j $whereSql ORDER BY j.nombre LIMIT ? OFFSET ?',
      [...args, perPage, offset],
    );
    return _hydrateAll(rows);
  }

  Future<Juego?> getByLocalId(int localId) async {
    final db = await _dbService.database;
    final rows = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (rows.isEmpty) return null;
    final list = await _hydrateAll(rows);
    return list.firstOrNull;
  }

  Future<Juego?> getByServerId(int serverId) async {
    final db = await _dbService.database;
    final rows = await db.query('juegos',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (rows.isEmpty) return null;
    final list = await _hydrateAll(rows);
    return list.firstOrNull;
  }

  /// Returns extended per-owner copy data for a game.
  Future<Map<int, CopiaPropietarioDraft>> getCopiaData(int juegoLocalId) async {
    final db = await _dbService.database;
    final rows = await db.query('juego_propietario',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);
    final result = <int, CopiaPropietarioDraft>{};
    for (final r in rows) {
      final propLocal = r['propietario_local_id'] as int?;
      if (propLocal == null) continue;
      final jpLocalId = r['local_id'] as int;
      final fundaRows = await db.query('juego_propietario_fundas',
          where: 'juego_propietario_local_id = ?', whereArgs: [jpLocalId]);
      final fundas = <JuegoFundaDraft>[];
      for (final fr in fundaRows) {
        final tipoLocal = await _tipoFundaLocalIdForRow(db, fr);
        if (tipoLocal == null) continue;
        fundas.add(JuegoFundaDraft(
          tipoFundaLocalId: tipoLocal,
          cantidadCartas: fr['cantidad_cartas'] as int? ?? 0,
          enfundadas: (fr['enfundadas'] as int?) == 1,
        ));
      }
      var idiomas = <String>[];
      final idiomasRaw = r['idiomas'] as String?;
      if (idiomasRaw != null && idiomasRaw.isNotEmpty) {
        try {
          idiomas = (jsonDecode(idiomasRaw) as List).cast<String>();
        } catch (_) {}
      }
      result[propLocal] = CopiaPropietarioDraft(
        propietarioLocalId: propLocal,
        ubicacionLocalId: r['ubicacion_local_id'] as int?,
        esPrincipal: (r['es_principal'] as int?) == 1,
        estado: r['estado'] as String?,
        fechaCompra: r['fecha_compra'] as String?,
        noEnfundar: (r['no_enfundar'] as int?) == 1,
        idiomas: idiomas,
        idiomaOtro: r['idioma_otro'] as String?,
        independienteIdioma: (r['independiente_idioma'] as int?) == 1,
        tradumaquetado: (r['tradumaquetado'] as int?) == 1,
        tradumaquetadoParcial: (r['tradumaquetado_parcial'] as int?) == 1,
        tradumaquetadoParcialNotas: r['tradumaquetado_parcial_notas'] as String?,
        fundas: fundas,
      );
    }
    return result;
  }

  /// Returns a map of propietario_local_id -> ubicacion_local_id for a game's pivot.
  Future<Map<int, int?>> getPropietarioUbicaciones(int juegoLocalId) async {
    final db = await _dbService.database;
    final rows = await db.query('juego_propietario',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);
    final result = <int, int?>{};
    for (final r in rows) {
      final propLocal = r['propietario_local_id'] as int?;
      if (propLocal != null) {
        result[propLocal] = r['ubicacion_local_id'] as int?;
      }
    }
    return result;
  }

  Future<List<Juego>> getExpansionesOf(int juegoLocalId) async {
    final db = await _dbService.database;
    final rows = await db.query('juegos',
        where: 'juego_base_local_id = ?', whereArgs: [juegoLocalId]);
    return _hydrateAll(rows);
  }

  Future<List<Map<String, dynamic>>> fundasFaltantesAgrupadas() async {
    final db = await _dbService.database;
    return db.rawQuery('''
      SELECT
        tf.local_id AS tipo_local_id,
        tf.server_id AS tipo_server_id,
        tf.nombre AS tipo_nombre,
        tf.ancho_mm,
        tf.alto_mm,
        SUM(jf.cantidad_cartas) AS cantidad_total,
        json_group_array(json_object(
          'juego_local_id', j.local_id,
          'juego_server_id', j.server_id,
          'juego_nombre', j.nombre,
          'cantidad_cartas', jf.cantidad_cartas
        )) AS juegos_json
      FROM juego_fundas jf
      INNER JOIN juegos j ON j.local_id = jf.juego_local_id
      INNER JOIN tipos_funda tf ON tf.local_id = jf.tipo_funda_local_id
      WHERE jf.enfundadas = 0 AND COALESCE(j.no_enfundar, 0) = 0
      GROUP BY tf.local_id
      ORDER BY tf.alto_mm, tf.ancho_mm
    ''');
  }

  Future<Map<String, dynamic>> stats() async {
    final db = await _dbService.database;
    final total = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM juegos WHERE es_expansion = 0');
    final disponibles = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM juegos WHERE estado = 'disponible' AND es_expansion = 0");
    final enVenta = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM juegos WHERE estado = 'en_venta' AND es_expansion = 0");
    final vendidos = await db.rawQuery(
        "SELECT COUNT(*) AS c FROM juegos WHERE estado = 'vendido' AND es_expansion = 0");
    final exp = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM juegos WHERE es_expansion = 1');
    return <String, dynamic>{
      'totalJuegos': Sqflite.firstIntValue(total) ?? 0,
      'juegosDisponibles': Sqflite.firstIntValue(disponibles) ?? 0,
      'juegosEnVenta': Sqflite.firstIntValue(enVenta) ?? 0,
      'juegosVendidos': Sqflite.firstIntValue(vendidos) ?? 0,
      'totalExpansiones': Sqflite.firstIntValue(exp) ?? 0,
    };
  }

  Future<bool> existsWithNombre(String nombre, {int? excludeLocalId}) async {
    final db = await _dbService.database;
    final args = <dynamic>[nombre.trim()];
    var excludeSql = '';
    if (excludeLocalId != null) {
      excludeSql = 'AND local_id != ?';
      args.add(excludeLocalId);
    }
    final rows = await db.rawQuery(
      '''
      SELECT local_id FROM juegos
      WHERE LOWER(TRIM(nombre)) = LOWER(TRIM(?))
      $excludeSql
      LIMIT 1
      ''',
      args,
    );
    return rows.isNotEmpty;
  }

  // ---------- escritura ----------

  /// Crea o actualiza un juego completo (con propietarios y fundas).
  /// Si `juego.localId` est\u00e1 presente, se considera edici\u00f3n.
  /// Encola las operaciones necesarias en el outbox.
  Future<int> save(Juego juego, {
    required List<int> propietarioLocalIds,
    required List<JuegoFundaDraft> fundas,
    List<int> categoriaLocalIds = const [],
    Map<int, int?> propietarioUbicaciones = const {},
    Map<int, CopiaPropietarioDraft>? copiasData,
  }) async {
    final db = await _dbService.database;

    var isCreate = juego.localId == null;
    int? reuseLocalId;

    if (isCreate && juego.bggId != null) {
      final bggDup = await db.query(
        'juegos',
        where: 'bgg_id = ?',
        whereArgs: [juego.bggId],
        limit: 1,
      );
      if (bggDup.isNotEmpty) {
        throw StateError('Ya existe un juego con este ID de BGG en la ludoteca.');
      }
    }

    if (isCreate) {
      final pendingDup = await db.rawQuery(
        '''
        SELECT local_id FROM juegos
        WHERE LOWER(TRIM(nombre)) = LOWER(TRIM(?))
          AND dirty = 1
          AND pending_action = 'create'
        LIMIT 1
        ''',
        [juego.nombre],
      );
      if (pendingDup.isNotEmpty) {
        reuseLocalId = pendingDup.first['local_id'] as int;
        isCreate = false;
      }
    }

    final values = await _serializeJuego(juego);

    int localId;
    if (isCreate) {
      values['dirty'] = 1;
      values['pending_action'] = 'create';
      localId = await db.insert('juegos', values);
      await _outbox.enqueue(
        table: 'juegos',
        action: SyncAction.create,
        localId: localId,
        payload: _payloadForServer(values),
      );
    } else {
      localId = reuseLocalId ?? juego.localId!;
      values['dirty'] = 1;
      values['pending_action'] = 'update';
      await db.update('juegos', values,
          where: 'local_id = ?', whereArgs: [localId]);

      final existing = await db
          .query('juegos', where: 'local_id = ?', whereArgs: [localId], limit: 1);
      final baseUpdatedAt = existing.first['updated_at'] as String?;
      final serverId = existing.first['server_id'] as int? ?? juego.serverId;

      if (serverId != null) {
        await _outbox.enqueue(
          table: 'juegos',
          action: SyncAction.update,
          localId: localId,
          serverId: serverId,
          payload: _payloadForServer(values),
          baseUpdatedAt: baseUpdatedAt,
        );
      } else {
        // a\u00fan no se ha sincronizado el create; basta con que el create
        // pendiente lleve el payload m\u00e1s reciente.
        await _outbox.removeForLocalRow('juegos', localId);
        await _outbox.enqueue(
          table: 'juegos',
          action: SyncAction.create,
          localId: localId,
          payload: _payloadForServer(values),
        );
      }
    }

    final savedRow = await db.query(
      'juegos',
      where: 'local_id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    final effectiveServerId =
        savedRow.isEmpty ? juego.serverId : savedRow.first['server_id'] as int?;

    final effectiveCopias = <int, CopiaPropietarioDraft>{};
    if (copiasData != null && copiasData.isNotEmpty) {
      effectiveCopias.addAll(copiasData);
    } else {
      for (final propId in propietarioLocalIds) {
        effectiveCopias[propId] = CopiaPropietarioDraft(
          propietarioLocalId: propId,
          ubicacionLocalId: propietarioUbicaciones[propId],
        );
      }
    }

    await _syncPropietarios(
      localId,
      effectiveServerId,
      propietarioLocalIds,
      effectiveCopias,
      variasCopias: juego.variasCopias,
    );
    await _syncFundas(localId, effectiveServerId, fundas);
    await _syncCategorias(localId, effectiveServerId, categoriaLocalIds);

    return localId;
  }

  /// Updates only the estado and precio fields (quick update from detail screen).
  Future<void> updateEstado(int localId, {required String estado, double? precio}) async {
    final db = await _dbService.database;
    final existing = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    await db.update('juegos', {
      'estado': estado,
      'precio': precio,
      'dirty': 1,
      'pending_action': 'update',
    }, where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'juegos',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {'estado': estado, 'precio': precio},
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  /// Updates only the ubicacion (quick update from detail screen).
  Future<void> updateUbicacion(
    int localId, {
    int? ubicacionLocalId,
    bool? enCajaBase,
  }) async {
    final db = await _dbService.database;
    final existing = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    final baseUpdatedAt = existing.first['updated_at'] as String?;

    int? ubicacionServerId;
    if (ubicacionLocalId != null) {
      final row = await db.query('ubicaciones',
          where: 'local_id = ?', whereArgs: [ubicacionLocalId], limit: 1);
      ubicacionServerId = row.isEmpty ? null : row.first['server_id'] as int?;
    }

    final resolvedEnCajaBase = enCajaBase ??
        (ubicacionLocalId != null
            ? false
            : ((existing.first['en_caja_base'] as int?) ?? 0) == 1);

    await db.update('juegos', {
      'ubicacion_local_id': resolvedEnCajaBase ? null : ubicacionLocalId,
      'ubicacion_server_id': resolvedEnCajaBase ? null : ubicacionServerId,
      'en_caja_base': resolvedEnCajaBase ? 1 : 0,
      'dirty': 1,
      'pending_action': 'update',
    }, where: 'local_id = ?', whereArgs: [localId]);

    if (serverId != null) {
      await _outbox.enqueue(
        table: 'juegos',
        action: SyncAction.update,
        localId: localId,
        serverId: serverId,
        payload: {
          'ubicacion_id': resolvedEnCajaBase ? null : ubicacionServerId,
          'en_caja_base': resolvedEnCajaBase,
        },
        baseUpdatedAt: baseUpdatedAt,
      );
    }
  }

  Future<void> delete(int localId) async {
    final db = await _dbService.database;
    final existing = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [localId], limit: 1);
    if (existing.isEmpty) return;
    final serverId = existing.first['server_id'] as int?;
    await db.delete('juego_propietario_fundas',
        where:
            'juego_propietario_local_id IN (SELECT local_id FROM juego_propietario WHERE juego_local_id = ?)',
        whereArgs: [localId]);
    await db.delete('juego_propietario',
        where: 'juego_local_id = ?', whereArgs: [localId]);
    await db.delete('juego_fundas',
        where: 'juego_local_id = ?', whereArgs: [localId]);
    await db.delete('juego_categoria',
        where: 'juego_local_id = ?', whereArgs: [localId]);
    await db.delete('juegos', where: 'local_id = ?', whereArgs: [localId]);
    if (serverId != null) {
      await _outbox.enqueue(
        table: 'juegos',
        action: SyncAction.delete,
        localId: localId,
        serverId: serverId,
      );
    } else {
      await _outbox.removeForLocalRow('juegos', localId);
    }
  }

  // ---------- upsert desde servidor ----------

  Future<void> upsertJuegoFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final categoriaLocalId = await _localIdFor(db, 'categorias', data['categoria_id']);
    final ubicacionLocalId = await _localIdFor(db, 'ubicaciones', data['ubicacion_id']);
    final juegoBaseLocalId = await _localIdFor(db, 'juegos', data['juego_base_id']);

    // Serialize idiomas to JSON string for SQLite
    String? idiomasJson;
    if (data['idiomas'] != null) {
      idiomasJson = data['idiomas'] is String
          ? data['idiomas']
          : jsonEncode(data['idiomas']);
    }

    final existing = await db.query('juegos',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);

    final enCajaBase = data.containsKey('en_caja_base')
        ? (data['en_caja_base'] == true || data['en_caja_base'] == 1)
        : (existing.isNotEmpty
            ? ((existing.first['en_caja_base'] as int?) ?? 0) == 1
            : false);

    final precio = data.containsKey('precio') && data['precio'] is num
        ? (data['precio'] as num).toDouble()
        : (existing.isNotEmpty ? existing.first['precio'] as double? : null);

    final values = {
      'server_id': serverId,
      'nombre': data['nombre'],
      'descripcion': data['descripcion'],
      'edad_minima': data['edad_minima'],
      'edad_maxima': data['edad_maxima'],
      'num_jugadores_min': data['num_jugadores_min'],
      'num_jugadores_max': data['num_jugadores_max'],
      'categoria_server_id': data['categoria_id'],
      'categoria_local_id': categoriaLocalId,
      'ubicacion_server_id': data['ubicacion_id'],
      'ubicacion_local_id': ubicacionLocalId,
      'estado': data['estado'],
      'fecha_compra': data['fecha_compra'],
      'imagen': data['imagen'],
      'bgg_id': data['bgg_id'],
      'juego_base_server_id': data['juego_base_id'],
      'juego_base_local_id': juegoBaseLocalId,
      'no_enfundar': (data['no_enfundar'] == true) ? 1 : 0,
      'es_expansion': (data['es_expansion'] == true) ? 1 : 0,
      'idiomas': idiomasJson,
      'idioma_otro': data['idioma_otro'],
      'independiente_idioma': (data['independiente_idioma'] == true) ? 1 : 0,
      'tradumaquetado': (data['tradumaquetado'] == true) ? 1 : 0,
      'tradumaquetado_parcial': (data['tradumaquetado_parcial'] == true) ? 1 : 0,
      'tradumaquetado_parcial_notas': data['tradumaquetado_parcial_notas'],
      'varias_copias': (data['varias_copias'] == true) ? 1 : 0,
      'precio': precio,
      'en_caja_base': enCajaBase ? 1 : 0,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    if (existing.isEmpty) {
      await db.insert('juegos', values,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      final isDirty = ((existing.first['dirty'] as int?) ?? 0) == 1;
      if (isDirty) {
        // Only update non-conflicting fields; preserve local changes
        // that haven't been pushed yet.
        values.remove('estado');
        values.remove('precio');
        values.remove('ubicacion_local_id');
        values.remove('ubicacion_server_id');
        values.remove('en_caja_base');
        values.remove('categoria_local_id');
        values.remove('categoria_server_id');
        values.remove('dirty');
        values.remove('pending_action');
      }
      await db.update('juegos', values,
          where: 'server_id = ?', whereArgs: [serverId]);
    }
  }

  Future<void> upsertJuegoFundaFromServer(Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final juegoLocalId = await _localIdFor(db, 'juegos', data['juego_id']);
    final tipoLocalId = await _localIdFor(db, 'tipos_funda', data['tipo_funda_id']);
    final values = {
      'server_id': serverId,
      'juego_server_id': data['juego_id'],
      'juego_local_id': juegoLocalId,
      'tipo_funda_server_id': data['tipo_funda_id'],
      'tipo_funda_local_id': tipoLocalId,
      'cantidad_cartas': data['cantidad_cartas'],
      'enfundadas': (data['enfundadas'] == true) ? 1 : 0,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    // Evitar duplicar filas (mismo juego + tipo): antes se insertaba una fila
    // nueva por server_id sin fusionar la fila local pendiente (server_id null).
    Map<String, dynamic>? targetRow;
    int? targetLocalId;

    final byServer = await db.query('juego_fundas',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (byServer.isNotEmpty) {
      targetRow = byServer.first;
      targetLocalId = targetRow['local_id'] as int;
    } else if (juegoLocalId != null && tipoLocalId != null) {
      final byJuegoTipo = await db.query(
        'juego_fundas',
        where: 'juego_local_id = ? AND tipo_funda_local_id = ?',
        whereArgs: [juegoLocalId, tipoLocalId],
        orderBy: 'local_id ASC',
      );
      if (byJuegoTipo.isNotEmpty) {
        targetRow = byJuegoTipo.first;
        targetLocalId = targetRow['local_id'] as int;
        for (var i = 1; i < byJuegoTipo.length; i++) {
          final dupLocalId = byJuegoTipo[i]['local_id'] as int;
          await db.delete('juego_fundas',
              where: 'local_id = ?', whereArgs: [dupLocalId]);
        }
      }
    }

    if (targetLocalId != null && targetRow != null) {
      final hadNoServerId = (targetRow['server_id'] as int?) == null;
      await db.update(
        'juego_fundas',
        values,
        where: 'local_id = ?',
        whereArgs: [targetLocalId],
      );
      if (hadNoServerId) {
        await _outbox.removeForLocalRow('juego_fundas', targetLocalId);
      }
      if (juegoLocalId != null && tipoLocalId != null) {
        await db.delete(
          'juego_fundas',
          where:
              'juego_local_id = ? AND tipo_funda_local_id = ? AND local_id != ?',
          whereArgs: [juegoLocalId, tipoLocalId, targetLocalId],
        );
      }
      return;
    }

    await db.insert('juego_fundas', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertJuegoPropietarioFromServer(
      Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final juegoLocalId = await _localIdFor(db, 'juegos', data['juego_id']);
    final propLocalId = await _localIdFor(db, 'propietarios', data['propietario_id']);
    final ubicLocalId = await _localIdFor(db, 'ubicaciones', data['ubicacion_id']);
    final idiomas = data['idiomas'];
    final values = {
      'server_id': serverId,
      'juego_server_id': data['juego_id'],
      'juego_local_id': juegoLocalId,
      'propietario_server_id': data['propietario_id'],
      'propietario_local_id': propLocalId,
      'ubicacion_server_id': data['ubicacion_id'],
      'ubicacion_local_id': ubicLocalId,
      'es_principal': (data['es_principal'] == true) ? 1 : 0,
      'estado': data['estado'],
      'fecha_compra': data['fecha_compra'],
      'no_enfundar': (data['no_enfundar'] == true) ? 1 : 0,
      'idiomas': idiomas is List ? jsonEncode(idiomas) : null,
      'idioma_otro': data['idioma_otro'],
      'independiente_idioma': (data['independiente_idioma'] == true) ? 1 : 0,
      'tradumaquetado': (data['tradumaquetado'] == true) ? 1 : 0,
      'tradumaquetado_parcial': (data['tradumaquetado_parcial'] == true) ? 1 : 0,
      'tradumaquetado_parcial_notas': data['tradumaquetado_parcial_notas'],
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    final existing = await db.query('juego_propietario',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (existing.isNotEmpty) {
      await db.update('juego_propietario', values,
          where: 'server_id = ?', whereArgs: [serverId]);
      return;
    }

    // Reuse local row created before sync (no server_id yet).
    if (juegoLocalId != null && propLocalId != null) {
      final local = await db.query('juego_propietario',
          where: 'juego_local_id = ? AND propietario_local_id = ?',
          whereArgs: [juegoLocalId, propLocalId],
          limit: 1);
      if (local.isNotEmpty) {
        final localId = local.first['local_id'] as int;
        await db.update('juego_propietario', values,
            where: 'local_id = ?', whereArgs: [localId]);
        await _outbox.removeForLocalRow('juego_propietario', localId);
        return;
      }
    }

    await db.insert('juego_propietario', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertJuegoPropietarioFundaFromServer(
      Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final jpLocalId =
        await _localIdFor(db, 'juego_propietario', data['juego_propietario_id']);
    final tipoLocalId =
        await _localIdFor(db, 'tipos_funda', data['tipo_funda_id']);
    final values = {
      'server_id': serverId,
      'juego_propietario_server_id': data['juego_propietario_id'],
      'juego_propietario_local_id': jpLocalId,
      'tipo_funda_server_id': data['tipo_funda_id'],
      'tipo_funda_local_id': tipoLocalId,
      'cantidad_cartas': data['cantidad_cartas'],
      'enfundadas': (data['enfundadas'] == true) ? 1 : 0,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };

    Map<String, dynamic>? targetRow;
    int? targetLocalId;

    final byServer = await db.query('juego_propietario_fundas',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (byServer.isNotEmpty) {
      targetRow = byServer.first;
      targetLocalId = targetRow['local_id'] as int;
    } else if (jpLocalId != null && tipoLocalId != null) {
      final byJpTipo = await db.query(
        'juego_propietario_fundas',
        where: 'juego_propietario_local_id = ? AND tipo_funda_local_id = ?',
        whereArgs: [jpLocalId, tipoLocalId],
        orderBy: 'local_id ASC',
      );
      if (byJpTipo.isNotEmpty) {
        targetRow = byJpTipo.first;
        targetLocalId = targetRow['local_id'] as int;
        for (var i = 1; i < byJpTipo.length; i++) {
          await db.delete('juego_propietario_fundas',
              where: 'local_id = ?', whereArgs: [byJpTipo[i]['local_id']]);
        }
      }
    }

    if (targetLocalId != null && targetRow != null) {
      final hadNoServerId = (targetRow['server_id'] as int?) == null;
      await db.update('juego_propietario_fundas', values,
          where: 'local_id = ?', whereArgs: [targetLocalId]);
      if (hadNoServerId) {
        await _outbox.removeForLocalRow('juego_propietario_fundas', targetLocalId);
      }
      return;
    }

    await db.insert('juego_propietario_fundas', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertJuegoCategoriaFromServer(
      Map<String, dynamic> data) async {
    final db = await _dbService.database;
    final serverId = data['id'] as int;
    final juegoLocalId = await _localIdFor(db, 'juegos', data['juego_id']);
    final catLocalId = await _localIdFor(db, 'categorias', data['categoria_id']);
    final values = {
      'server_id': serverId,
      'juego_server_id': data['juego_id'],
      'juego_local_id': juegoLocalId,
      'categoria_server_id': data['categoria_id'],
      'categoria_local_id': catLocalId,
      'updated_at': data['updated_at'],
      'dirty': 0,
      'pending_action': null,
    };
    final existing = await db.query('juego_categoria',
        where: 'server_id = ?', whereArgs: [serverId], limit: 1);
    if (existing.isNotEmpty) {
      await db.update('juego_categoria', values,
          where: 'server_id = ?', whereArgs: [serverId]);
      return;
    }

    // Reuse row created by local migration (no server_id yet).
    if (juegoLocalId != null && catLocalId != null) {
      final migrated = await db.query('juego_categoria',
          where: 'juego_local_id = ? AND categoria_local_id = ?',
          whereArgs: [juegoLocalId, catLocalId],
          limit: 1);
      if (migrated.isNotEmpty) {
        final localId = migrated.first['local_id'] as int;
        await db.update('juego_categoria', values,
            where: 'local_id = ?', whereArgs: [localId]);
        await _outbox.removeForLocalRow('juego_categoria', localId);
        return;
      }
    }

    await db.insert('juego_categoria', values,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteByServerIds(String table, List<int> serverIds) async {
    if (serverIds.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = List.filled(serverIds.length, '?').join(',');
    await db.delete(table,
        where: 'server_id IN ($placeholders)', whereArgs: serverIds);
  }

  /// Asigna `server_id` y limpia `dirty/pending_action` tras un push exitoso.
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

  /// Actualiza el pHash y la ruta local de la imagen tras descargarla.
  Future<void> setPhash({
    required int localId,
    required String? phash,
    required String? imageLocalPath,
  }) async {
    final db = await _dbService.database;
    await db.update(
      'juegos',
      {'phash': phash, 'image_local_path': imageLocalPath},
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllForRecognition() async {
    final db = await _dbService.database;
    return db.rawQuery(
      'SELECT local_id, server_id, nombre, phash, image_local_path, imagen FROM juegos',
    );
  }

  // ---------- privados ----------

  Future<List<Juego>> _hydrateAll(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    final db = await _dbService.database;
    final localIds = rows.map((r) => r['local_id'] as int).toList();
    final placeholders = List.filled(localIds.length, '?').join(',');

    final propietariosByJuego = <int, List<Propietario>>{};
    final propRows = await db.rawQuery(
      '''
      SELECT jp.juego_local_id AS juego_local_id,
             p.local_id, p.server_id, p.nombre, p.bgg_username, p.es_principal
      FROM juego_propietario jp
      INNER JOIN propietarios p ON p.local_id = jp.propietario_local_id
      WHERE jp.juego_local_id IN ($placeholders)
      ''',
      localIds,
    );
    for (final r in propRows) {
      final juegoLocalId = r['juego_local_id'] as int;
      propietariosByJuego.putIfAbsent(juegoLocalId, () => []).add(Propietario(
            id: (r['server_id'] as int?) ?? -(r['local_id'] as int),
            nombre: r['nombre'] as String,
            bggUsername: r['bgg_username'] as String?,
            esPrincipal: ((r['es_principal'] as int?) ?? 0) == 1,
          ));
    }

    final fundasByJuego = <int, List<JuegoFunda>>{};
    final fundaRows = await db.rawQuery(
      '''
      SELECT jf.local_id AS f_local, jf.server_id AS f_server,
             jf.juego_local_id, jf.cantidad_cartas, jf.enfundadas,
             tf.local_id AS tf_local, tf.server_id AS tf_server,
             tf.nombre AS tf_nombre, tf.ancho_mm, tf.alto_mm
      FROM juego_fundas jf
      LEFT JOIN tipos_funda tf ON tf.local_id = jf.tipo_funda_local_id
      WHERE jf.juego_local_id IN ($placeholders)
      ''',
      localIds,
    );
    for (final r in fundaRows) {
      final juegoLocalId = r['juego_local_id'] as int;
      fundasByJuego.putIfAbsent(juegoLocalId, () => []).add(JuegoFunda(
            id: (r['f_server'] as int?) ?? -(r['f_local'] as int),
            tipoFundaId: (r['tf_server'] as int?) ?? -(r['tf_local'] as int? ?? 0),
            cantidadCartas: (r['cantidad_cartas'] as int?) ?? 0,
            enfundadas: ((r['enfundadas'] as int?) ?? 0) == 1,
            tipoFunda: r['tf_nombre'] != null
                ? TipoFunda(
                    id: (r['tf_server'] as int?) ?? -(r['tf_local'] as int? ?? 0),
                    nombre: r['tf_nombre'] as String,
                    anchoMm: (r['ancho_mm'] as int?) ?? 0,
                    altoMm: (r['alto_mm'] as int?) ?? 0,
                  )
                : null,
          ));
    }

    final ubicacionRepo = UbicacionRepository(_dbService, _outbox);
    final ubicaciones = await ubicacionRepo.getAll();
    final ubicByLocal = {for (final u in ubicaciones) u.localId: u};

    final categoriasRows = await db.query('categorias');
    final categoriaByLocal = {
      for (final c in categoriasRows)
        (c['local_id'] as int): Categoria(
          id: (c['server_id'] as int?) ?? -(c['local_id'] as int),
          nombre: c['nombre'] as String,
        ),
    };

    // Load categorias from pivot table
    final categoriasByJuego = <int, List<Categoria>>{};
    final jcRows = await db.rawQuery(
      '''
      SELECT jc.juego_local_id, jc.categoria_local_id
      FROM juego_categoria jc
      WHERE jc.juego_local_id IN ($placeholders)
      ''',
      localIds,
    );
    for (final r in jcRows) {
      final juegoLocalId = r['juego_local_id'] as int;
      final catLocalId = r['categoria_local_id'] as int?;
      if (catLocalId != null && categoriaByLocal.containsKey(catLocalId)) {
        final cat = categoriaByLocal[catLocalId]!;
        final list = categoriasByJuego.putIfAbsent(juegoLocalId, () => []);
        if (!list.any((c) => c.id == cat.id)) {
          list.add(cat);
        }
      }
    }
    for (final list in categoriasByJuego.values) {
      list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    }

    final juegosByServerId = <int, Juego>{};
    final result = <Juego>[];
    for (final r in rows) {
      final localId = r['local_id'] as int;
      final serverId = r['server_id'] as int?;
      Categoria? cat;
      final catLocal = r['categoria_local_id'] as int?;
      if (catLocal != null) cat = categoriaByLocal[catLocal];

      Ubicacion? ubic;
      final ubicLocal = r['ubicacion_local_id'] as int?;
      if (ubicLocal != null) {
        final u = ubicByLocal[ubicLocal];
        if (u != null) {
          ubic = Ubicacion(
            id: u.serverId ?? -u.localId,
            nombre: u.nombre,
            mueble: u.mueble == null
                ? null
                : Mueble(
                    id: u.mueble!.serverId ?? -u.mueble!.localId,
                    nombre: u.mueble!.nombre,
                    habitacion: u.habitacion == null
                        ? null
                        : Habitacion(
                            id: u.habitacion!.serverId ?? -u.habitacion!.localId,
                            nombre: u.habitacion!.nombre,
                          ),
                  ),
          );
        }
      }

      // Parse idiomas JSON
      List<String> idiomas = const [];
      final idiomasRaw = r['idiomas'];
      if (idiomasRaw is String && idiomasRaw.isNotEmpty) {
        try {
          idiomas = (jsonDecode(idiomasRaw) as List).cast<String>();
        } catch (_) {}
      }

      final juego = Juego(
        id: serverId ?? -localId,
        localId: localId,
        serverId: serverId,
        nombre: r['nombre'] as String,
        descripcion: r['descripcion'] as String?,
        imagen: r['imagen'] as String?,
        edadMinima: r['edad_minima'] as int?,
        edadMaxima: r['edad_maxima'] as int?,
        numJugadoresMin: r['num_jugadores_min'] as int?,
        numJugadoresMax: r['num_jugadores_max'] as int?,
        categoriaId: cat?.id,
        estado: r['estado'] as String?,
        fechaCompra: r['fecha_compra'] as String?,
        juegoBaseId: r['juego_base_server_id'] as int? ??
            (r['juego_base_local_id'] != null
                ? -(r['juego_base_local_id'] as int)
                : null),
        juegoBaseLocalId: r['juego_base_local_id'] as int?,
        juegoBaseServerId: r['juego_base_server_id'] as int?,
        bggId: r['bgg_id'] as int?,
        noEnfundar: ((r['no_enfundar'] as int?) ?? 0) == 1,
        esExpansionFlag: ((r['es_expansion'] as int?) ?? 0) == 1,
        idiomas: idiomas,
        idiomaOtro: r['idioma_otro'] as String?,
        independienteIdioma: ((r['independiente_idioma'] as int?) ?? 0) == 1,
        tradumaquetado: ((r['tradumaquetado'] as int?) ?? 0) == 1,
        tradumaquetadoParcial: ((r['tradumaquetado_parcial'] as int?) ?? 0) == 1,
        tradumaquetadoParcialNotas: r['tradumaquetado_parcial_notas'] as String?,
        variasCopias: ((r['varias_copias'] as int?) ?? 0) == 1,
        precio: r['precio'] != null ? (r['precio'] as num).toDouble() : null,
        enCajaBase: ((r['en_caja_base'] as int?) ?? 0) == 1,
        phash: r['phash'] as String?,
        imageLocalPath: r['image_local_path'] as String?,
        updatedAt: r['updated_at'] as String?,
        dirty: ((r['dirty'] as int?) ?? 0) == 1,
        categoria: cat,
        categorias: categoriasByJuego[localId] ?? const [],
        ubicacion: ubic,
        propietarios: propietariosByJuego[localId] ?? const [],
        fundas: fundasByJuego[localId] ?? const [],
      );
      result.add(juego);
      if (serverId != null) juegosByServerId[serverId] = juego;
    }

    // Resolver juego base como objeto enlazado y expansiones (un nivel).
    final allRows = await db.query('juegos');
    final byLocalId = {for (final r in allRows) (r['local_id'] as int): r};
    final expansionesByBaseLocal = <int, List<Juego>>{};

    // Para cada juego, si es expansi\u00f3n, asignar juegoBase si est\u00e1 en cache.
    for (var i = 0; i < result.length; i++) {
      final juego = result[i];
      if (juego.juegoBaseLocalId != null) {
        final baseRow = byLocalId[juego.juegoBaseLocalId];
        if (baseRow != null) {
          final base = Juego(
            id: (baseRow['server_id'] as int?) ?? -(baseRow['local_id'] as int),
            localId: baseRow['local_id'] as int,
            serverId: baseRow['server_id'] as int?,
            nombre: baseRow['nombre'] as String,
          );
          result[i] = juego.copyWithJuegoBase(base);
        }
      }
    }

    // Si los resultados incluyen juegos base, cargar expansiones cortas.
    for (final juego in result) {
      if (juego.localId == null) continue;
      final exps = allRows
          .where((r) => r['juego_base_local_id'] == juego.localId)
          .map((r) => Juego(
                id: (r['server_id'] as int?) ?? -(r['local_id'] as int),
                localId: r['local_id'] as int,
                serverId: r['server_id'] as int?,
                nombre: r['nombre'] as String,
              ))
          .toList();
      if (exps.isNotEmpty) {
        expansionesByBaseLocal[juego.localId!] = exps;
      }
    }

    return result
        .map((j) => j.localId != null && expansionesByBaseLocal.containsKey(j.localId)
            ? j.copyWithExpansiones(expansionesByBaseLocal[j.localId!]!)
            : j)
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

  Future<Map<String, dynamic>> _serializeJuego(Juego juego) async {
    final db = await _dbService.database;

    int? categoriaLocalId;
    int? categoriaServerId;
    if (juego.categoriaLocalId != null) {
      categoriaLocalId = juego.categoriaLocalId;
      final row = await db.query('categorias',
          where: 'local_id = ?',
          whereArgs: [categoriaLocalId],
          limit: 1);
      categoriaServerId = row.isEmpty ? null : row.first['server_id'] as int?;
    }

    int? ubicacionLocalId = juego.ubicacionLocalId;
    int? ubicacionServerId;
    if (ubicacionLocalId != null) {
      final row = await db.query('ubicaciones',
          where: 'local_id = ?',
          whereArgs: [ubicacionLocalId],
          limit: 1);
      ubicacionServerId =
          row.isEmpty ? null : row.first['server_id'] as int?;
    }

    int? juegoBaseLocalId = juego.juegoBaseLocalId;
    int? juegoBaseServerId;
    if (juegoBaseLocalId != null) {
      final row = await db.query('juegos',
          where: 'local_id = ?',
          whereArgs: [juegoBaseLocalId],
          limit: 1);
      juegoBaseServerId =
          row.isEmpty ? null : row.first['server_id'] as int?;
    }

    return {
      'nombre': juego.nombre,
      'descripcion': juego.descripcion,
      'edad_minima': juego.edadMinima,
      'edad_maxima': juego.edadMaxima,
      'num_jugadores_min': juego.numJugadoresMin,
      'num_jugadores_max': juego.numJugadoresMax,
      'categoria_local_id': categoriaLocalId,
      'categoria_server_id': categoriaServerId,
      'ubicacion_local_id': ubicacionLocalId,
      'ubicacion_server_id': ubicacionServerId,
      'estado': juego.estado ?? 'disponible',
      'fecha_compra': juego.fechaCompra,
      'imagen': juego.imagen,
      'bgg_id': juego.bggId,
      'juego_base_local_id': juegoBaseLocalId,
      'juego_base_server_id': juegoBaseServerId,
      'no_enfundar': juego.noEnfundar ? 1 : 0,
      'es_expansion': juego.esExpansionFlag ? 1 : 0,
      'idiomas': juego.idiomas.isNotEmpty ? jsonEncode(juego.idiomas) : null,
      'idioma_otro': juego.idiomaOtro,
      'independiente_idioma': juego.independienteIdioma ? 1 : 0,
      'tradumaquetado': juego.tradumaquetado ? 1 : 0,
      'tradumaquetado_parcial': juego.tradumaquetadoParcial ? 1 : 0,
      'tradumaquetado_parcial_notas': juego.tradumaquetadoParcialNotas,
      'varias_copias': juego.variasCopias ? 1 : 0,
      'precio': juego.precio,
      'en_caja_base': juego.enCajaBase ? 1 : 0,
    };
  }

  Map<String, dynamic> _payloadForServer(Map<String, dynamic> values) {
    // Parse idiomas back from JSON string for the server payload
    dynamic idiomasForServer;
    if (values['idiomas'] is String) {
      try {
        idiomasForServer = jsonDecode(values['idiomas'] as String);
      } catch (_) {
        idiomasForServer = null;
      }
    }

    return {
      'nombre': values['nombre'],
      'descripcion': values['descripcion'],
      'edad_minima': values['edad_minima'],
      'edad_maxima': values['edad_maxima'],
      'num_jugadores_min': values['num_jugadores_min'],
      'num_jugadores_max': values['num_jugadores_max'],
      'categoria_id': values['categoria_server_id'],
      'ubicacion_id': values['ubicacion_server_id'],
      'estado': values['estado'],
      'fecha_compra': values['fecha_compra'],
      'imagen': values['imagen'],
      'bgg_id': values['bgg_id'],
      'juego_base_id': values['juego_base_server_id'],
      'no_enfundar': values['no_enfundar'] == 1,
      'es_expansion': values['es_expansion'] == 1,
      'idiomas': idiomasForServer,
      'idioma_otro': values['idioma_otro'],
      'independiente_idioma': values['independiente_idioma'] == 1,
      'tradumaquetado': values['tradumaquetado'] == 1,
      'tradumaquetado_parcial': values['tradumaquetado_parcial'] == 1,
      'tradumaquetado_parcial_notas': values['tradumaquetado_parcial_notas'],
      'varias_copias': values['varias_copias'] == 1,
      'precio': values['precio'],
      'en_caja_base': values['en_caja_base'] == 1,
    };
  }

  Future<void> _syncPropietarios(
    int juegoLocalId,
    int? juegoServerId,
    List<int> propLocalIds,
    Map<int, CopiaPropietarioDraft> copiasData, {
    required bool variasCopias,
  }) async {
    final db = await _dbService.database;
    final existing = await db.query('juego_propietario',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);

    final existingByPropLocal = {
      for (final r in existing) (r['propietario_local_id'] as int): r,
    };
    final desired = propLocalIds.toSet();

    Future<void> deletePivotFundas(int jpLocalId) async {
      final fundaRows = await db.query('juego_propietario_fundas',
          where: 'juego_propietario_local_id = ?', whereArgs: [jpLocalId]);
      for (final fr in fundaRows) {
        final localId = fr['local_id'] as int;
        final serverId = fr['server_id'] as int?;
        await db.delete('juego_propietario_fundas',
            where: 'local_id = ?', whereArgs: [localId]);
        if (serverId != null) {
          await _outbox.enqueue(
            table: 'juego_propietario_fundas',
            action: SyncAction.delete,
            localId: localId,
            serverId: serverId,
          );
        } else {
          await _outbox.removeForLocalRow('juego_propietario_fundas', localId);
        }
      }
    }

    for (final entry in existingByPropLocal.entries) {
      if (!desired.contains(entry.key)) {
        final localId = entry.value['local_id'] as int;
        await deletePivotFundas(localId);
        final serverId = entry.value['server_id'] as int?;
        await db.delete('juego_propietario',
            where: 'local_id = ?', whereArgs: [localId]);
        if (serverId != null) {
          await _outbox.enqueue(
            table: 'juego_propietario',
            action: SyncAction.delete,
            localId: localId,
            serverId: serverId,
          );
        } else {
          await _outbox.removeForLocalRow('juego_propietario', localId);
        }
      }
    }

    for (final propLocalId in propLocalIds) {
      final copia = copiasData[propLocalId] ??
          CopiaPropietarioDraft(propietarioLocalId: propLocalId);
      final propRow = await db.query('propietarios',
          where: 'local_id = ?', whereArgs: [propLocalId], limit: 1);
      if (propRow.isEmpty) continue;
      final propServerId = propRow.first['server_id'] as int?;

      int? ubicServerId;
      if (copia.ubicacionLocalId != null) {
        final ubicRow = await db.query('ubicaciones',
            where: 'local_id = ?', whereArgs: [copia.ubicacionLocalId], limit: 1);
        if (ubicRow.isNotEmpty) {
          ubicServerId = ubicRow.first['server_id'] as int?;
        }
      }

      final rowValues = _copiaDraftToPivotRow(
        copia,
        ubicServerId: ubicServerId,
      );

      if (existingByPropLocal.containsKey(propLocalId)) {
        final existingRow = existingByPropLocal[propLocalId]!;
        final localId = existingRow['local_id'] as int;
        if (_pivotRowChanged(existingRow, rowValues)) {
          await db.update('juego_propietario', {
            ...rowValues,
            'dirty': 1,
            'pending_action': 'update',
          }, where: 'local_id = ?', whereArgs: [localId]);
          final sid = existingRow['server_id'] as int?;
          if (sid != null) {
            await _outbox.enqueue(
              table: 'juego_propietario',
              action: SyncAction.update,
              localId: localId,
              serverId: sid,
              payload: await _propietarioPivotPayload(
                db,
                {...existingRow, ...rowValues},
                juegoServerId: juegoServerId,
              ),
            );
          }
        }
        if (variasCopias) {
          await _syncPropietarioFundas(
            localId,
            existingRow['server_id'] as int?,
            copia.fundas,
          );
        } else {
          await deletePivotFundas(localId);
        }
        continue;
      }

      final newLocalId = await db.insert('juego_propietario', {
        'juego_server_id': juegoServerId,
        'juego_local_id': juegoLocalId,
        'propietario_server_id': propServerId,
        'propietario_local_id': propLocalId,
        ...rowValues,
        'dirty': 1,
        'pending_action': 'create',
      });
      await _outbox.enqueue(
        table: 'juego_propietario',
        action: SyncAction.create,
        localId: newLocalId,
        payload: await _propietarioPivotPayload(
          db,
          {
            'juego_server_id': juegoServerId,
            'propietario_server_id': propServerId,
            'ubicacion_server_id': ubicServerId,
            ...rowValues,
          },
          juegoServerId: juegoServerId,
        ),
      );
      if (variasCopias) {
        await _syncPropietarioFundas(newLocalId, null, copia.fundas);
      }
    }
  }

  Map<String, dynamic> _copiaDraftToPivotRow(
    CopiaPropietarioDraft copia, {
    int? ubicServerId,
  }) {
    return {
      'ubicacion_local_id': copia.ubicacionLocalId,
      'ubicacion_server_id': ubicServerId,
      'es_principal': copia.esPrincipal ? 1 : 0,
      'estado': copia.estado,
      'fecha_compra': copia.fechaCompra,
      'no_enfundar': copia.noEnfundar ? 1 : 0,
      'idiomas':
          copia.idiomas.isEmpty ? null : jsonEncode(copia.idiomas),
      'idioma_otro': copia.idiomaOtro,
      'independiente_idioma': copia.independienteIdioma ? 1 : 0,
      'tradumaquetado': copia.tradumaquetado ? 1 : 0,
      'tradumaquetado_parcial': copia.tradumaquetadoParcial ? 1 : 0,
      'tradumaquetado_parcial_notas': copia.tradumaquetadoParcialNotas,
    };
  }

  bool _pivotRowChanged(
      Map<String, dynamic> existing, Map<String, dynamic> desired) {
    const keys = [
      'ubicacion_local_id',
      'es_principal',
      'estado',
      'fecha_compra',
      'no_enfundar',
      'idiomas',
      'idioma_otro',
      'independiente_idioma',
      'tradumaquetado',
      'tradumaquetado_parcial',
      'tradumaquetado_parcial_notas',
    ];
    for (final key in keys) {
      if (existing[key] != desired[key]) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _propietarioPivotPayload(
    Database db,
    Map<String, dynamic> row, {
    int? juegoServerId,
  }) async {
    List<dynamic>? idiomasForServer;
    final idiomasRaw = row['idiomas'] as String?;
    if (idiomasRaw != null && idiomasRaw.isNotEmpty) {
      try {
        idiomasForServer = jsonDecode(idiomasRaw) as List<dynamic>;
      } catch (_) {}
    }
    return {
      'juego_id': juegoServerId ?? row['juego_server_id'],
      'propietario_id': row['propietario_server_id'],
      'ubicacion_id': row['ubicacion_server_id'],
      'es_principal': (row['es_principal'] as int?) == 1,
      'estado': row['estado'],
      'fecha_compra': row['fecha_compra'],
      'no_enfundar': (row['no_enfundar'] as int?) == 1,
      'idiomas': idiomasForServer,
      'idioma_otro': row['idioma_otro'],
      'independiente_idioma': (row['independiente_idioma'] as int?) == 1,
      'tradumaquetado': (row['tradumaquetado'] as int?) == 1,
      'tradumaquetado_parcial': (row['tradumaquetado_parcial'] as int?) == 1,
      'tradumaquetado_parcial_notas': row['tradumaquetado_parcial_notas'],
    };
  }

  Future<void> _syncPropietarioFundas(
    int jpLocalId,
    int? jpServerId,
    List<JuegoFundaDraft> drafts,
  ) async {
    final db = await _dbService.database;
    var existing = await db.query('juego_propietario_fundas',
        where: 'juego_propietario_local_id = ?', whereArgs: [jpLocalId]);

    final desiredByTipoLocal = {
      for (final d in drafts) d.tipoFundaLocalId: d,
    };

    for (final r in existing) {
      final tipoLocal = await _tipoFundaLocalIdForRow(db, r);
      final shouldKeep =
          tipoLocal != null && desiredByTipoLocal.containsKey(tipoLocal);
      if (shouldKeep) continue;
      final localId = r['local_id'] as int;
      final serverId = r['server_id'] as int?;
      await db.delete('juego_propietario_fundas',
          where: 'local_id = ?', whereArgs: [localId]);
      if (serverId != null) {
        await _outbox.enqueue(
          table: 'juego_propietario_fundas',
          action: SyncAction.delete,
          localId: localId,
          serverId: serverId,
        );
      } else {
        await _outbox.removeForLocalRow('juego_propietario_fundas', localId);
      }
    }

    existing = await db.query('juego_propietario_fundas',
        where: 'juego_propietario_local_id = ?', whereArgs: [jpLocalId]);
    final existingByTipoLocal = <int, Map<String, dynamic>>{};
    for (final r in existing) {
      final tipoLocal = await _tipoFundaLocalIdForRow(db, r);
      if (tipoLocal != null) existingByTipoLocal[tipoLocal] = r;
    }

    for (final draft in drafts) {
      final tipoRow = await db.query('tipos_funda',
          where: 'local_id = ?', whereArgs: [draft.tipoFundaLocalId], limit: 1);
      if (tipoRow.isEmpty) continue;
      final tipoServerId = tipoRow.first['server_id'] as int?;

      if (existingByTipoLocal.containsKey(draft.tipoFundaLocalId)) {
        final existingRow = existingByTipoLocal[draft.tipoFundaLocalId]!;
        final localId = existingRow['local_id'] as int;
        final changed = (existingRow['cantidad_cartas'] as int?) !=
                draft.cantidadCartas ||
            ((existingRow['enfundadas'] as int?) == 1) != draft.enfundadas;
        if (changed) {
          await db.update('juego_propietario_fundas', {
            'cantidad_cartas': draft.cantidadCartas,
            'enfundadas': draft.enfundadas ? 1 : 0,
            'dirty': 1,
            'pending_action': 'update',
          }, where: 'local_id = ?', whereArgs: [localId]);
          final sid = existingRow['server_id'] as int?;
          if (sid != null) {
            await _outbox.enqueue(
              table: 'juego_propietario_fundas',
              action: SyncAction.update,
              localId: localId,
              serverId: sid,
              payload: {
                'juego_propietario_id': jpServerId,
                'tipo_funda_id': tipoServerId,
                'cantidad_cartas': draft.cantidadCartas,
                'enfundadas': draft.enfundadas,
              },
            );
          }
        }
        continue;
      }

      final newLocalId = await db.insert('juego_propietario_fundas', {
        'juego_propietario_server_id': jpServerId,
        'juego_propietario_local_id': jpLocalId,
        'tipo_funda_server_id': tipoServerId,
        'tipo_funda_local_id': draft.tipoFundaLocalId,
        'cantidad_cartas': draft.cantidadCartas,
        'enfundadas': draft.enfundadas ? 1 : 0,
        'dirty': 1,
        'pending_action': 'create',
      });
      await _outbox.enqueue(
        table: 'juego_propietario_fundas',
        action: SyncAction.create,
        localId: newLocalId,
        payload: {
          'juego_propietario_id': jpServerId,
          'tipo_funda_id': tipoServerId,
          'cantidad_cartas': draft.cantidadCartas,
          'enfundadas': draft.enfundadas,
        },
      );
    }
  }

  Future<void> _syncCategorias(
      int juegoLocalId, int? juegoServerId, List<int> catLocalIds) async {
    final db = await _dbService.database;
    final existing = await db.query('juego_categoria',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);

    final existingByCatLocal = <int, Map<String, dynamic>>{};
    final orphanRows = <Map<String, dynamic>>[];
    for (final r in existing) {
      final catLocal = r['categoria_local_id'] as int?;
      if (catLocal != null) {
        existingByCatLocal[catLocal] = r;
      } else {
        orphanRows.add(r);
      }
    }

    // Include legacy categoria_id when there is no pivot row yet (common for
    // imports BGG or rows created by the local migration before sync).
    final juegoRows = await db.query('juegos',
        where: 'local_id = ?', whereArgs: [juegoLocalId], limit: 1);
    if (juegoRows.isNotEmpty) {
      final legacyCatLocal = juegoRows.first['categoria_local_id'] as int?;
      if (legacyCatLocal != null &&
          !existingByCatLocal.containsKey(legacyCatLocal)) {
        existingByCatLocal[legacyCatLocal] = {
          'local_id': null,
          'server_id': null,
          'categoria_local_id': legacyCatLocal,
          'categoria_server_id': juegoRows.first['categoria_server_id'],
          'juego_server_id':
              juegoRows.first['server_id'] ?? juegoServerId,
          'juego_local_id': juegoLocalId,
          '_legacy_only': 1,
        };
      }
    }

    final desired = catLocalIds.toSet();

    // Remove categories no longer desired
    for (final entry in existingByCatLocal.entries) {
      if (!desired.contains(entry.key)) {
        final row = entry.value;
        final legacyOnly = (row['_legacy_only'] as int?) == 1;
        final localId = row['local_id'] as int?;
        if (!legacyOnly && localId != null) {
          await db.delete('juego_categoria',
              where: 'local_id = ?', whereArgs: [localId]);
        }
        await _enqueueCategoriaPivotDelete(
          db,
          row,
          localId: localId,
          juegoServerId: juegoServerId,
        );
      }
    }

    // Clean up orphan rows (no local category resolved)
    for (final r in orphanRows) {
      final localId = r['local_id'] as int;
      final serverId = r['server_id'] as int?;
      final catServerId = r['categoria_server_id'] as int?;
      // Check if this orphan corresponds to a desired category by server_id
      bool matchesDesired = false;
      if (catServerId != null) {
        final catRow = await db.query('categorias',
            where: 'server_id = ?', whereArgs: [catServerId], limit: 1);
        if (catRow.isNotEmpty) {
          final resolvedLocalId = catRow.first['local_id'] as int;
          if (desired.contains(resolvedLocalId)) {
            // Fix the orphan row
            await db.update('juego_categoria',
                {'categoria_local_id': resolvedLocalId},
                where: 'local_id = ?', whereArgs: [localId]);
            existingByCatLocal[resolvedLocalId] = r;
            matchesDesired = true;
          }
        }
      }
      if (!matchesDesired) {
        await db.delete('juego_categoria',
            where: 'local_id = ?', whereArgs: [localId]);
        if (serverId != null) {
          await _outbox.enqueue(
            table: 'juego_categoria',
            action: SyncAction.delete,
            localId: localId,
            serverId: serverId,
          );
        } else {
          await _enqueueCategoriaPivotDelete(
            db,
            r,
            localId: localId,
            juegoServerId: juegoServerId,
          );
        }
      }
    }

    for (final catLocalId in catLocalIds) {
      if (existingByCatLocal.containsKey(catLocalId)) continue;
      final catRow = await db.query('categorias',
          where: 'local_id = ?', whereArgs: [catLocalId], limit: 1);
      if (catRow.isEmpty) continue;
      final catServerId = catRow.first['server_id'] as int?;

      final newLocalId = await db.insert('juego_categoria', {
        'juego_server_id': juegoServerId,
        'juego_local_id': juegoLocalId,
        'categoria_server_id': catServerId,
        'categoria_local_id': catLocalId,
        'dirty': 1,
        'pending_action': 'create',
      });
      await _outbox.enqueue(
        table: 'juego_categoria',
        action: SyncAction.create,
        localId: newLocalId,
        payload: {
          'juego_id': juegoServerId,
          'categoria_id': catServerId,
        },
      );
    }
  }

  /// Encola el borrado de una fila pivot juego_categoria en el servidor.
  /// Si no conocemos el server_id del pivot, usa juego_id + categoria_id.
  Future<void> _enqueueCategoriaPivotDelete(
    Database db,
    Map<String, dynamic> row, {
    int? localId,
    int? juegoServerId,
  }) async {
    final pivotServerId = row['server_id'] as int?;
    if (pivotServerId != null) {
      await _outbox.enqueue(
        table: 'juego_categoria',
        action: SyncAction.delete,
        localId: localId,
        serverId: pivotServerId,
      );
      return;
    }

    var juegoSid = row['juego_server_id'] as int? ?? juegoServerId;
    var catSid = row['categoria_server_id'] as int?;

    if (catSid == null) {
      final catLocal = row['categoria_local_id'] as int?;
      if (catLocal != null) {
        final catRow = await db.query('categorias',
            where: 'local_id = ?', whereArgs: [catLocal], limit: 1);
        if (catRow.isNotEmpty) {
          catSid = catRow.first['server_id'] as int?;
        }
      }
    }

    if (juegoSid == null) {
      final juegoLocal = row['juego_local_id'] as int?;
      if (juegoLocal != null) {
        final jRow = await db.query('juegos',
            where: 'local_id = ?', whereArgs: [juegoLocal], limit: 1);
        if (jRow.isNotEmpty) {
          juegoSid = jRow.first['server_id'] as int?;
        }
      }
    }

    if (juegoSid != null && catSid != null) {
      await _outbox.enqueue(
        table: 'juego_categoria',
        action: SyncAction.delete,
        localId: localId,
        payload: {
          'juego_id': juegoSid,
          'categoria_id': catSid,
        },
      );
    } else if (localId != null) {
      await _outbox.removeForLocalRow('juego_categoria', localId);
    }
  }

  Future<int?> _tipoFundaLocalIdForRow(
      Database db, Map<String, dynamic> r) async {
    final direct = r['tipo_funda_local_id'] as int?;
    if (direct != null) return direct;
    final sid = r['tipo_funda_server_id'] as int?;
    if (sid == null) return null;
    return _localIdFor(db, 'tipos_funda', sid);
  }

  Future<void> _syncFundas(
    int juegoLocalId,
    int? juegoServerId,
    List<JuegoFundaDraft> drafts,
  ) async {
    final db = await _dbService.database;
    var existing = await db.query('juego_fundas',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);

    final desiredByTipoLocal = {
      for (final d in drafts) d.tipoFundaLocalId: d,
    };

    // Varias filas con el mismo tipo (p.ej. tras sincronizaciones fallidas).
    final byTipo = <int, List<Map<String, dynamic>>>{};
    for (final r in existing) {
      final tipoLocal = await _tipoFundaLocalIdForRow(db, r);
      if (tipoLocal == null) continue;
      byTipo.putIfAbsent(tipoLocal, () => []).add(r);
    }
    for (final rows in byTipo.values) {
      if (rows.length <= 1) continue;
      rows.sort((a, b) {
        final sa = a['server_id'] as int?;
        final sb = b['server_id'] as int?;
        if (sa != null && sb == null) return -1;
        if (sa == null && sb != null) return 1;
        return (a['local_id'] as int).compareTo(b['local_id'] as int);
      });
      for (var i = 1; i < rows.length; i++) {
        final dup = rows[i];
        final localId = dup['local_id'] as int;
        final serverId = dup['server_id'] as int?;
        await db.delete('juego_fundas',
            where: 'local_id = ?', whereArgs: [localId]);
        if (serverId != null) {
          await _outbox.enqueue(
            table: 'juego_fundas',
            action: SyncAction.delete,
            localId: localId,
            serverId: serverId,
          );
        } else {
          await _outbox.removeForLocalRow('juego_fundas', localId);
        }
      }
    }
    existing = await db.query('juego_fundas',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);

    // eliminar los que sobran (incluye filas con tipo_funda_local_id null)
    for (final r in existing) {
      final tipoLocal = await _tipoFundaLocalIdForRow(db, r);
      final shouldKeep =
          tipoLocal != null && desiredByTipoLocal.containsKey(tipoLocal);
      if (shouldKeep) continue;
      final localId = r['local_id'] as int;
      final serverId = r['server_id'] as int?;
      await db.delete('juego_fundas',
          where: 'local_id = ?', whereArgs: [localId]);
      if (serverId != null) {
        await _outbox.enqueue(
          table: 'juego_fundas',
          action: SyncAction.delete,
          localId: localId,
          serverId: serverId,
        );
      } else {
        await _outbox.removeForLocalRow('juego_fundas', localId);
      }
    }

    existing = await db.query('juego_fundas',
        where: 'juego_local_id = ?', whereArgs: [juegoLocalId]);
    final existingByTipoLocal = <int, Map<String, dynamic>>{};
    for (final r in existing) {
      final tipoLocal = await _tipoFundaLocalIdForRow(db, r);
      if (tipoLocal != null) existingByTipoLocal[tipoLocal] = r;
    }

    // upsert
    for (final draft in drafts) {
      final tipoRow = await db.query('tipos_funda',
          where: 'local_id = ?',
          whereArgs: [draft.tipoFundaLocalId],
          limit: 1);
      if (tipoRow.isEmpty) continue;
      final tipoServerId = tipoRow.first['server_id'] as int?;

      final existingRow = existingByTipoLocal[draft.tipoFundaLocalId];
      if (existingRow == null) {
        final newLocalId = await db.insert('juego_fundas', {
          'juego_server_id': juegoServerId,
          'juego_local_id': juegoLocalId,
          'tipo_funda_server_id': tipoServerId,
          'tipo_funda_local_id': draft.tipoFundaLocalId,
          'cantidad_cartas': draft.cantidadCartas,
          'enfundadas': draft.enfundadas ? 1 : 0,
          'dirty': 1,
          'pending_action': 'create',
        });
        await _outbox.enqueue(
          table: 'juego_fundas',
          action: SyncAction.create,
          localId: newLocalId,
          payload: {
            'juego_id': juegoServerId,
            'tipo_funda_id': tipoServerId,
            'cantidad_cartas': draft.cantidadCartas,
            'enfundadas': draft.enfundadas,
          },
        );
      } else {
        final fundaLocalId = existingRow['local_id'] as int;
        final fundaServerId = existingRow['server_id'] as int?;
        await db.update(
          'juego_fundas',
          {
            'cantidad_cartas': draft.cantidadCartas,
            'enfundadas': draft.enfundadas ? 1 : 0,
            'dirty': 1,
            'pending_action': 'update',
          },
          where: 'local_id = ?',
          whereArgs: [fundaLocalId],
        );
        if (fundaServerId != null) {
          await _outbox.enqueue(
            table: 'juego_fundas',
            action: SyncAction.update,
            localId: fundaLocalId,
            serverId: fundaServerId,
            payload: {
              'cantidad_cartas': draft.cantidadCartas,
              'enfundadas': draft.enfundadas,
            },
          );
        }
      }
    }
  }
}

class JuegoFundaDraft {
  final int tipoFundaLocalId;
  final int cantidadCartas;
  final bool enfundadas;

  JuegoFundaDraft({
    required this.tipoFundaLocalId,
    required this.cantidadCartas,
    required this.enfundadas,
  });
}

class CopiaPropietarioDraft {
  final int propietarioLocalId;
  final int? ubicacionLocalId;
  final bool esPrincipal;
  final String? estado;
  final String? fechaCompra;
  final bool noEnfundar;
  final List<String> idiomas;
  final String? idiomaOtro;
  final bool independienteIdioma;
  final bool tradumaquetado;
  final bool tradumaquetadoParcial;
  final String? tradumaquetadoParcialNotas;
  final List<JuegoFundaDraft> fundas;

  CopiaPropietarioDraft({
    required this.propietarioLocalId,
    this.ubicacionLocalId,
    this.esPrincipal = false,
    this.estado,
    this.fechaCompra,
    this.noEnfundar = false,
    this.idiomas = const [],
    this.idiomaOtro,
    this.independienteIdioma = false,
    this.tradumaquetado = false,
    this.tradumaquetadoParcial = false,
    this.tradumaquetadoParcialNotas,
    this.fundas = const [],
  });

  CopiaPropietarioDraft copyWith({
    int? ubicacionLocalId,
    bool? esPrincipal,
    String? estado,
    String? fechaCompra,
    bool? noEnfundar,
    List<String>? idiomas,
    String? idiomaOtro,
    bool? independienteIdioma,
    bool? tradumaquetado,
    bool? tradumaquetadoParcial,
    String? tradumaquetadoParcialNotas,
    List<JuegoFundaDraft>? fundas,
  }) {
    return CopiaPropietarioDraft(
      propietarioLocalId: propietarioLocalId,
      ubicacionLocalId: ubicacionLocalId ?? this.ubicacionLocalId,
      esPrincipal: esPrincipal ?? this.esPrincipal,
      estado: estado ?? this.estado,
      fechaCompra: fechaCompra ?? this.fechaCompra,
      noEnfundar: noEnfundar ?? this.noEnfundar,
      idiomas: idiomas ?? this.idiomas,
      idiomaOtro: idiomaOtro ?? this.idiomaOtro,
      independienteIdioma: independienteIdioma ?? this.independienteIdioma,
      tradumaquetado: tradumaquetado ?? this.tradumaquetado,
      tradumaquetadoParcial:
          tradumaquetadoParcial ?? this.tradumaquetadoParcial,
      tradumaquetadoParcialNotas:
          tradumaquetadoParcialNotas ?? this.tradumaquetadoParcialNotas,
      fundas: fundas ?? this.fundas,
    );
  }
}
