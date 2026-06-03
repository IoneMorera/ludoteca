import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/phash_service.dart';
import 'categoria_repository.dart';
import 'juego_repository.dart';
import 'outbox_dao.dart';
import 'propietario_repository.dart';
import 'tipo_funda_repository.dart';
import 'ubicacion_repository.dart';

enum SyncStatus { idle, syncing, error }

class SyncSnapshot {
  final SyncStatus status;
  final String? lastError;
  final DateTime? lastSyncedAt;
  final int pendingOps;

  const SyncSnapshot({
    this.status = SyncStatus.idle,
    this.lastError,
    this.lastSyncedAt,
    this.pendingOps = 0,
  });

  SyncSnapshot copyWith({
    SyncStatus? status,
    String? lastError,
    DateTime? lastSyncedAt,
    int? pendingOps,
  }) {
    return SyncSnapshot(
      status: status ?? this.status,
      lastError: lastError,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pendingOps: pendingOps ?? this.pendingOps,
    );
  }
}

/// Servicio singleton de sincronizaci\u00f3n bidireccional con el backend.
///
/// Implementa el patr\u00f3n outbox: cualquier escritura local encola una
/// operaci\u00f3n en `sync_outbox`, que se drena al servidor cuando hay red.
/// La descarga es incremental por `updated_at` y aplica tombstones.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final ApiService _api = ApiService();
  final DatabaseService _dbService = DatabaseService();
  late final OutboxDao _outbox = OutboxDao(_dbService);
  late final CategoriaRepository _categorias =
      CategoriaRepository(_dbService, _outbox);
  late final PropietarioRepository _propietarios =
      PropietarioRepository(_dbService, _outbox);
  late final UbicacionRepository _ubicaciones =
      UbicacionRepository(_dbService, _outbox);
  late final TipoFundaRepository _tiposFunda =
      TipoFundaRepository(_dbService, _outbox);
  late final JuegoRepository _juegos = JuegoRepository(_dbService, _outbox);

  final StreamController<SyncSnapshot> _controller =
      StreamController<SyncSnapshot>.broadcast();
  SyncSnapshot _current = const SyncSnapshot();
  bool _running = false;

  Stream<SyncSnapshot> get stream => _controller.stream;
  SyncSnapshot get snapshot => _current;

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> syncAll({bool fullPull = false}) async {
    if (_running) return;
    _running = true;
    _emit(_current.copyWith(status: SyncStatus.syncing, lastError: null));
    try {
      if (!await isOnline()) {
        _emit(_current.copyWith(
          status: SyncStatus.idle,
          lastError: 'sin_conexion',
        ));
        return;
      }
      await _push();
      if (!fullPull) {
        final db = await _dbService.database;
        final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM juegos'));
        if (count == null || count == 0) fullPull = true;
      }
      await _pull(fullPull: fullPull);
      // Tras sincronizar metadatos, calcular pHashes que falten.
      unawaited(_indexPendingPhashes());
      final pending = await _outbox.count();
      _emit(_current.copyWith(
        status: SyncStatus.idle,
        lastSyncedAt: DateTime.now(),
        pendingOps: pending,
        lastError: null,
      ));
    } catch (e, st) {
      debugPrint('SYNC ERROR: $e\n$st');
      final pending = await _outbox.count();
      _emit(_current.copyWith(
        status: SyncStatus.error,
        lastError: e.toString(),
        pendingOps: pending,
      ));
    } finally {
      _running = false;
    }
  }

  Future<void> _push() async {
    final pending = await _outbox.pending(limit: 200);
    if (pending.isEmpty) return;

    final db = await _dbService.database;
    final toSend = <OutboxOperation>[];
    for (final op in pending) {
      // Discard ops that have failed too many times (stale/unrecoverable).
      if (op.attempts >= 3) {
        debugPrint('SYNC: discarding stuck op ${op.clientOpId} '
            '(${op.table}/${op.action}, ${op.attempts} attempts, '
            'error: ${op.lastError})');
        await _outbox.remove(op.id);
        continue;
      }

      if (op.action == SyncAction.create && op.localId != null) {
        final rows = await db.query(op.table,
            where: 'local_id = ?',
            whereArgs: [op.localId],
            limit: 1);
        // Row already synced.
        if (rows.isNotEmpty && rows.first['server_id'] != null) {
          await _outbox.remove(op.id);
          continue;
        }
        // Row was deleted locally.
        if (rows.isEmpty) {
          await _outbox.remove(op.id);
          continue;
        }
        // Orphan duplicate in pivot tables.
        if (await _isDuplicatePivotRow(db, op.table, rows.first)) {
          await db.delete(op.table,
              where: 'local_id = ?', whereArgs: [op.localId]);
          await _outbox.remove(op.id);
          continue;
        }
      }

      // Discard UPDATE/DELETE ops whose local row no longer exists.
      if (op.localId != null && op.action != SyncAction.create) {
        final rows = await db.query(op.table,
            columns: ['local_id'],
            where: 'local_id = ?',
            whereArgs: [op.localId],
            limit: 1);
        if (rows.isEmpty) {
          await _outbox.remove(op.id);
          continue;
        }
      }

      toSend.add(op);
    }
    if (toSend.isEmpty) return;

    final operations = <Map<String, dynamic>>[];
    for (final op in toSend) {
      final data = await _enrichedPayload(op);
      final action = syncActionToString(op.action);
      operations.add({
        'client_op_id': op.clientOpId,
        'table': op.table,
        'action': action,
        if (op.serverId != null) 'server_id': op.serverId,
        if (op.baseUpdatedAt != null) 'base_updated_at': op.baseUpdatedAt,
        if (data.isNotEmpty) 'data': data,
      });
    }

    final response =
        await _api.post('/sync/push', data: {'operations': operations});
    final results =
        (response.data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final byOpId = {for (final op in toSend) op.clientOpId: op};

    for (final result in results) {
      final clientOpId = result['client_op_id'] as String?;
      if (clientOpId == null) continue;
      final op = byOpId[clientOpId];
      if (op == null) continue;
      final status = result['status'] as String?;
      final serverId = result['server_id'] as int?;
      final updatedAt = result['updated_at'] as String?;

      switch (status) {
        case 'ok':
        case 'conflict_server_wins':
          if (op.action == SyncAction.create && serverId != null && op.localId != null) {
            await _juegos.commitServerId(
              table: op.table,
              localId: op.localId!,
              serverId: serverId,
              updatedAt: updatedAt,
            );
            // propagar el serverId reci\u00e9n asignado al resto de operaciones
            // pendientes que lo necesitan (p.ej. fundas creadas antes que el juego).
            await _outbox.assignServerId(
              table: op.table,
              localId: op.localId!,
              serverId: serverId,
            );
            // Si la fila contiene FK a esta tabla (p.ej. juego_fundas.juego_local_id),
            // tambi\u00e9n hay que rellenar el server_id de la FK en filas locales.
            await _backfillForeignKeyServerIds(
              table: op.table,
              localId: op.localId!,
              serverId: serverId,
            );
          } else if (op.action == SyncAction.update && op.localId != null) {
            await _juegos.markClean(
              table: op.table,
              localId: op.localId!,
              updatedAt: updatedAt,
            );
          }
          await _outbox.remove(op.id);
          break;
        case 'not_found':
          // El servidor ya no tiene el registro; descartamos la operaci\u00f3n.
          await _outbox.remove(op.id);
          break;
        case 'error':
        default:
          await _outbox.markError(op.id, result['error']?.toString() ?? status ?? 'error');
          break;
      }
    }
  }

  /// Rellena FK y campos desde SQLite para operaciones encoladas antes de que
  /// existiera el server_id del padre (reintento tras un push parcial).
  Future<Map<String, dynamic>> _enrichedPayload(OutboxOperation op) async {
    final merged = Map<String, dynamic>.from(op.payload);
    final localId = op.localId;
    if (localId == null) return merged;
    final db = await _dbService.database;

    switch (op.table) {
      case 'muebles':
        final rows = await db.query('muebles',
            where: 'local_id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final h = rows.first['habitacion_server_id'] as int?;
          if (h != null) merged['habitacion_id'] = h;
          merged['nombre'] = rows.first['nombre'] as String;
        }
        break;
      case 'ubicaciones':
        final rows = await db.query('ubicaciones',
            where: 'local_id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final m = rows.first['mueble_server_id'] as int?;
          if (m != null) merged['mueble_id'] = m;
          merged['nombre'] = rows.first['nombre'] as String;
        }
        break;
      case 'juego_fundas':
        final rows = await db.query('juego_fundas',
            where: 'local_id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final j = rows.first['juego_server_id'] as int?;
          final t = rows.first['tipo_funda_server_id'] as int?;
          if (j != null) merged['juego_id'] = j;
          if (t != null) merged['tipo_funda_id'] = t;
          merged['cantidad_cartas'] = rows.first['cantidad_cartas'];
          merged['enfundadas'] =
              ((rows.first['enfundadas'] as int?) ?? 0) == 1;
        }
        break;
      case 'juego_propietario':
        final rows = await db.query('juego_propietario',
            where: 'local_id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final j = rows.first['juego_server_id'] as int?;
          final p = rows.first['propietario_server_id'] as int?;
          final u = rows.first['ubicacion_server_id'] as int?;
          if (j != null) merged['juego_id'] = j;
          if (p != null) merged['propietario_id'] = p;
          if (u != null) merged['ubicacion_id'] = u;
        }
        break;
      case 'juego_categoria':
        final rows = await db.query('juego_categoria',
            where: 'local_id = ?', whereArgs: [localId], limit: 1);
        if (rows.isNotEmpty) {
          final j = rows.first['juego_server_id'] as int?;
          final c = rows.first['categoria_server_id'] as int?;
          if (j != null) merged['juego_id'] = j;
          if (c != null) merged['categoria_id'] = c;
        }
        break;
    }
    return merged;
  }

  /// Returns true if [row] in a pivot table is an orphan duplicate — i.e.
  /// another row with the same FK pair already exists with a server_id.
  Future<bool> _isDuplicatePivotRow(
      Database db, String table, Map<String, dynamic> row) async {
    final localId = row['local_id'] as int;
    switch (table) {
      case 'juego_propietario':
        final j = row['juego_local_id'] as int?;
        final p = row['propietario_local_id'] as int?;
        if (j == null || p == null) return false;
        final dup = await db.query('juego_propietario',
            where: 'juego_local_id = ? AND propietario_local_id = ? '
                'AND local_id != ? AND server_id IS NOT NULL',
            whereArgs: [j, p, localId],
            limit: 1);
        return dup.isNotEmpty;
      case 'juego_categoria':
        final j = row['juego_local_id'] as int?;
        final c = row['categoria_local_id'] as int?;
        if (j == null || c == null) return false;
        final dup = await db.query('juego_categoria',
            where: 'juego_local_id = ? AND categoria_local_id = ? '
                'AND local_id != ? AND server_id IS NOT NULL',
            whereArgs: [j, c, localId],
            limit: 1);
        return dup.isNotEmpty;
      case 'juego_fundas':
        final j = row['juego_local_id'] as int?;
        final t = row['tipo_funda_local_id'] as int?;
        if (j == null || t == null) return false;
        final dup = await db.query('juego_fundas',
            where: 'juego_local_id = ? AND tipo_funda_local_id = ? '
                'AND local_id != ? AND server_id IS NOT NULL',
            whereArgs: [j, t, localId],
            limit: 1);
        return dup.isNotEmpty;
      default:
        return false;
    }
  }

  Future<void> _backfillForeignKeyServerIds({
    required String table,
    required int localId,
    required int serverId,
  }) async {
    final db = await _dbService.database;
    final fkMappings = <String, List<String>>{
      'juegos': ['juego_fundas.juego', 'juego_propietario.juego', 'juego_categoria.juego', 'juegos.juego_base'],
      'tipos_funda': ['juego_fundas.tipo_funda'],
      'propietarios': ['juego_propietario.propietario'],
      'categorias': ['juegos.categoria', 'juego_categoria.categoria'],
      'ubicaciones': ['juegos.ubicacion', 'juego_propietario.ubicacion'],
      'habitaciones': ['muebles.habitacion'],
      'muebles': ['ubicaciones.mueble'],
    };
    final mappings = fkMappings[table] ?? const [];
    for (final mapping in mappings) {
      final parts = mapping.split('.');
      final targetTable = parts[0];
      final fkPrefix = parts[1];
      await db.update(
        targetTable,
        {'${fkPrefix}_server_id': serverId},
        where:
            '${fkPrefix}_local_id = ? AND ${fkPrefix}_server_id IS NULL',
        whereArgs: [localId],
      );
    }
  }

  Future<void> _pull({bool fullPull = false}) async {
    final since =
        fullPull ? null : await _dbService.getSyncState('last_pull_at');
    final response = await _api
        .get('/sync/snapshot', params: since != null ? {'since': since} : null);
    final data = response.data is Map<String, dynamic>
        ? response.data as Map<String, dynamic>
        : <String, dynamic>{};
    final tablesRaw = data['tables'];
    final tables = tablesRaw is Map<String, dynamic>
        ? tablesRaw
        : <String, dynamic>{};
    final deletedRaw = data['deleted'];
    final deleted = deletedRaw is Map<String, dynamic>
        ? deletedRaw
        : <String, dynamic>{};
    final serverNow = data['server_now'] as String?;

    // ORDEN: padres antes que hijos para que las FK resuelvan.
    final categorias =
        (tables['categorias'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final c in categorias) {
      await _categorias.upsertFromServer(c);
    }
    final props =
        (tables['propietarios'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final p in props) {
      await _propietarios.upsertFromServer(p);
    }
    final habs =
        (tables['habitaciones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final h in habs) {
      await _ubicaciones.upsertHabitacionFromServer(h);
    }
    final muebles =
        (tables['muebles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final m in muebles) {
      await _ubicaciones.upsertMuebleFromServer(m);
    }
    final ubics =
        (tables['ubicaciones'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final u in ubics) {
      await _ubicaciones.upsertUbicacionFromServer(u);
    }
    final tipos =
        (tables['tipos_funda'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final t in tipos) {
      await _tiposFunda.upsertFromServer(t);
    }
    final juegos =
        (tables['juegos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // Dos pasadas: primero juegos base, luego expansiones (para resolver juego_base_local_id).
    for (final j in juegos.where((j) => j['juego_base_id'] == null)) {
      await _juegos.upsertJuegoFromServer(j);
    }
    for (final j in juegos.where((j) => j['juego_base_id'] != null)) {
      await _juegos.upsertJuegoFromServer(j);
    }
    final fundas =
        (tables['juego_fundas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final f in fundas) {
      await _juegos.upsertJuegoFundaFromServer(f);
    }
    final jp =
        (tables['juego_propietario'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final r in jp) {
      await _juegos.upsertJuegoPropietarioFromServer(r);
    }
    final jc =
        (tables['juego_categoria'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final r in jc) {
      await _juegos.upsertJuegoCategoriaFromServer(r);
    }

    // tombstones (borrados): aplicar después del upsert.
    for (final entry in deleted.entries) {
      final table = entry.key;
      final ids = (entry.value as List?)?.cast<int>() ?? [];
      if (ids.isEmpty) continue;
      switch (table) {
        case 'categorias':
          await _categorias.deleteByServerIds(ids);
          break;
        case 'propietarios':
          await _propietarios.deleteByServerIds(ids);
          break;
        case 'habitaciones':
        case 'muebles':
        case 'ubicaciones':
          await _ubicaciones.deleteByServerIds(table, ids);
          break;
        case 'tipos_funda':
          await _tiposFunda.deleteByServerIds(ids);
          break;
        case 'juegos':
        case 'juego_fundas':
        case 'juego_propietario':
        case 'juego_categoria':
          await _juegos.deleteByServerIds(table, ids);
          break;
      }
    }

    if (serverNow != null) {
      await _dbService.setSyncState('last_pull_at', serverNow);
    }
  }

  void _emit(SyncSnapshot s) {
    _current = s;
    _controller.add(s);
  }

  /// Itera por los juegos que tienen imagen pero no pHash y los calcula en
  /// segundo plano (download + hash + persist). No bloquea la sincronizaci\u00f3n.
  Future<void> _indexPendingPhashes() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      "SELECT local_id, imagen FROM juegos "
      "WHERE imagen IS NOT NULL AND imagen != '' AND phash IS NULL "
      "LIMIT 25",
    );
    if (rows.isEmpty) return;
    final cacheDir = await _phashCacheDir();
    for (final row in rows) {
      final localId = row['local_id'] as int;
      final imagen = row['imagen'] as String;
      try {
        final url = _resolveImageUrl(imagen);
        if (url == null) continue;
        final file = File(p.join(cacheDir.path, 'juego_$localId.bin'));
        if (!await file.exists()) {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) continue;
          await file.writeAsBytes(response.bodyBytes);
        }
        final hash = await PhashService.hashFile(file);
        if (hash != null) {
          await _juegos.setPhash(
            localId: localId,
            phash: hash,
            imageLocalPath: file.path,
          );
        }
      } catch (e) {
        debugPrint('phash error juego=$localId: $e');
      }
    }
  }

  Future<Directory> _phashCacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'ludoteca_phash'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String? _resolveImageUrl(String imagen) {
    if (imagen.startsWith('http://') || imagen.startsWith('https://')) {
      return imagen;
    }
    final path = imagen.startsWith('/') ? imagen : '/$imagen';
    return '${ApiConfig.storageUrl}$path';
  }
}
