import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

    final operations = pending.map((op) {
      final action = syncActionToString(op.action);
      return {
        'client_op_id': op.clientOpId,
        'table': op.table,
        'action': action,
        if (op.serverId != null) 'server_id': op.serverId,
        if (op.baseUpdatedAt != null) 'base_updated_at': op.baseUpdatedAt,
        if (op.payload.isNotEmpty) 'data': op.payload,
      };
    }).toList();

    final response =
        await _api.post('/sync/push', data: {'operations': operations});
    final results =
        (response.data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final byOpId = {for (final op in pending) op.clientOpId: op};

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

  Future<void> _backfillForeignKeyServerIds({
    required String table,
    required int localId,
    required int serverId,
  }) async {
    final db = await _dbService.database;
    final fkMappings = <String, List<String>>{
      'juegos': ['juego_fundas.juego', 'juego_propietario.juego', 'juegos.juego_base'],
      'tipos_funda': ['juego_fundas.tipo_funda'],
      'propietarios': ['juego_propietario.propietario'],
      'categorias': ['juegos.categoria'],
      'ubicaciones': ['juegos.ubicacion'],
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
    final data = response.data as Map<String, dynamic>;
    final tables = data['tables'] as Map<String, dynamic>? ?? {};
    final deleted = data['deleted'] as Map<String, dynamic>? ?? {};
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

    // tombstones (borrados): aplicar despu\u00e9s del upsert.
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
