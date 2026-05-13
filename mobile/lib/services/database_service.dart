import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/partida.dart';

/// Servicio singleton para acceder a la BBDD SQLite local.
///
/// Tablas espejo del backend con metadata de sincronizaci\u00f3n:
/// - `server_id`: id del servidor (null hasta sincronizar).
/// - `dirty`: 1 si tiene cambios pendientes de subir.
/// - `pending_action`: null|'create'|'update'|'delete'.
/// - `updated_at`: timestamp del servidor (ISO).
///
/// Adem\u00e1s `sync_outbox` y `sync_state` para coordinar la sincronizaci\u00f3n.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;
  static const int _schemaVersion = 3;

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ludoteca.db');

    return openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchemaV3(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS partidas (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              juego_id INTEGER NOT NULL,
              juego_nombre TEXT NOT NULL,
              juego_imagen TEXT,
              fecha TEXT NOT NULL,
              num_jugadores INTEGER,
              ganador TEXT,
              notas TEXT,
              jugadores TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await _migrateToV3(db);
        }
      },
    );
  }

  Future<void> _createSchemaV3(Database db) async {
    // tablas de sincronizaci\u00f3n
    await db.execute('''
      CREATE TABLE sync_state (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_op_id TEXT NOT NULL UNIQUE,
        table_name TEXT NOT NULL,
        action TEXT NOT NULL,
        local_id INTEGER,
        server_id INTEGER,
        payload_json TEXT,
        base_updated_at TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_outbox_status ON sync_outbox(attempts, created_at)');

    // tablas espejo
    await db.execute('''
      CREATE TABLE categorias (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE propietarios (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        nombre TEXT NOT NULL,
        bgg_username TEXT,
        es_principal INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE habitaciones (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        nombre TEXT NOT NULL,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE muebles (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        habitacion_server_id INTEGER,
        habitacion_local_id INTEGER,
        nombre TEXT NOT NULL,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE ubicaciones (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        mueble_server_id INTEGER,
        mueble_local_id INTEGER,
        nombre TEXT NOT NULL,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tipos_funda (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        nombre TEXT NOT NULL,
        ancho_mm INTEGER NOT NULL DEFAULT 0,
        alto_mm INTEGER NOT NULL DEFAULT 0,
        descripcion TEXT,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE juegos (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        nombre TEXT NOT NULL,
        descripcion TEXT,
        edad_minima INTEGER,
        edad_maxima INTEGER,
        num_jugadores_min INTEGER,
        num_jugadores_max INTEGER,
        categoria_server_id INTEGER,
        categoria_local_id INTEGER,
        ubicacion_server_id INTEGER,
        ubicacion_local_id INTEGER,
        estado TEXT,
        fecha_compra TEXT,
        imagen TEXT,
        bgg_id INTEGER,
        juego_base_server_id INTEGER,
        juego_base_local_id INTEGER,
        no_enfundar INTEGER NOT NULL DEFAULT 0,
        phash TEXT,
        image_local_path TEXT,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_juegos_nombre ON juegos(nombre)');
    await db.execute('CREATE INDEX idx_juegos_base ON juegos(juego_base_server_id)');

    await db.execute('''
      CREATE TABLE juego_fundas (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_server_id INTEGER,
        juego_local_id INTEGER,
        tipo_funda_server_id INTEGER,
        tipo_funda_local_id INTEGER,
        cantidad_cartas INTEGER NOT NULL DEFAULT 0,
        enfundadas INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_juego_fundas_juego ON juego_fundas(juego_local_id)');

    await db.execute('''
      CREATE TABLE juego_propietario (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_server_id INTEGER,
        juego_local_id INTEGER,
        propietario_server_id INTEGER,
        propietario_local_id INTEGER,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_jp_juego ON juego_propietario(juego_local_id)');

    // tabla partidas (heredada de v2)
    await db.execute('''
      CREATE TABLE partidas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        juego_id INTEGER NOT NULL,
        juego_nombre TEXT NOT NULL,
        juego_imagen TEXT,
        fecha TEXT NOT NULL,
        num_jugadores INTEGER,
        ganador TEXT,
        notas TEXT,
        jugadores TEXT
      )
    ''');
  }

  Future<void> _migrateToV3(Database db) async {
    // El cache antiguo `juegos_cache` no contiene la informaci\u00f3n suficiente
    // para sincronizar; se descarta y se fuerza un pull completo en el primer
    // arranque tras la actualizaci\u00f3n.
    await db.execute('DROP TABLE IF EXISTS juegos_cache');
    await _createSchemaV3(db);
  }

  // ---------- sync_state helpers ----------

  Future<String?> getSyncState(String key) async {
    final db = await database;
    final rows = await db.query('sync_state',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSyncState(String key, String? value) async {
    final db = await database;
    await db.insert(
      'sync_state',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- legacy: partidas (no se sincronizan a\u00fan) ----------

  Future<void> insertPartida(Partida partida) async {
    final db = await database;
    await db.insert('partidas', partida.toMap());
  }

  Future<List<Partida>> getPartidas() async {
    final db = await database;
    final maps = await db.query('partidas', orderBy: 'fecha DESC');
    return maps.map((m) => Partida.fromMap(m)).toList();
  }
}
