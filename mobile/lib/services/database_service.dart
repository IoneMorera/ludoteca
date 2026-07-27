import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../models/partida.dart';
import '../utils/text_normalize.dart';

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
  static const int _schemaVersion = 11;

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
        await _createSchemaV4(db);
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
        if (oldVersion < 4) {
          await _migrateToV4(db);
        }
        if (oldVersion < 5) {
          await _migrateToV5(db);
        }
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
        if (oldVersion < 7) {
          await _migrateToV7(db);
        }
        if (oldVersion < 8) {
          await _migrateToV8(db);
        }
        if (oldVersion < 9) {
          await _migrateToV9(db);
        }
        if (oldVersion < 10) {
          await _migrateToV10(db);
        }
        if (oldVersion < 11) {
          await _migrateToV11(db);
        }
      },
    );
  }

  Future<void> _createSchemaV4(Database db) async {
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
        nombre_norm TEXT,
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
        es_expansion INTEGER NOT NULL DEFAULT 0,
        autojugable INTEGER NOT NULL DEFAULT 0,
        idiomas TEXT,
        idioma_otro TEXT,
        independiente_idioma INTEGER NOT NULL DEFAULT 0,
        tradumaquetado INTEGER NOT NULL DEFAULT 0,
        tradumaquetado_parcial INTEGER NOT NULL DEFAULT 0,
        tradumaquetado_parcial_notas TEXT,
        varias_copias INTEGER NOT NULL DEFAULT 0,
        precio REAL,
        en_caja_base INTEGER NOT NULL DEFAULT 0,
        sin_abrir INTEGER NOT NULL DEFAULT 0,
        print_and_play INTEGER NOT NULL DEFAULT 0,
        phash TEXT,
        image_local_path TEXT,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_juegos_nombre ON juegos(nombre)');
    await db.execute('CREATE INDEX idx_juegos_nombre_norm ON juegos(nombre_norm)');
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
        ubicacion_server_id INTEGER,
        ubicacion_local_id INTEGER,
        es_principal INTEGER NOT NULL DEFAULT 0,
        estado TEXT,
        fecha_compra TEXT,
        no_enfundar INTEGER NOT NULL DEFAULT 0,
        idiomas TEXT,
        idioma_otro TEXT,
        independiente_idioma INTEGER NOT NULL DEFAULT 0,
        tradumaquetado INTEGER NOT NULL DEFAULT 0,
        tradumaquetado_parcial INTEGER NOT NULL DEFAULT 0,
        tradumaquetado_parcial_notas TEXT,
        sin_abrir INTEGER NOT NULL DEFAULT 0,
        print_and_play INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_jp_juego ON juego_propietario(juego_local_id)');

    await db.execute('''
      CREATE TABLE juego_propietario_fundas (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_propietario_server_id INTEGER,
        juego_propietario_local_id INTEGER,
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
        'CREATE INDEX idx_jpf_jp ON juego_propietario_fundas(juego_propietario_local_id)');

    await db.execute('''
      CREATE TABLE juego_categoria (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_server_id INTEGER,
        juego_local_id INTEGER,
        categoria_server_id INTEGER,
        categoria_local_id INTEGER,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_jc_juego ON juego_categoria(juego_local_id)');

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
    await db.execute('DROP TABLE IF EXISTS juegos_cache');
    await _createSchemaV4(db);
  }

  Future<void> _migrateToV4(Database db) async {
    // New fields on juegos
    await db.execute('ALTER TABLE juegos ADD COLUMN es_expansion INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juegos ADD COLUMN idiomas TEXT');
    await db.execute('ALTER TABLE juegos ADD COLUMN idioma_otro TEXT');
    await db.execute('ALTER TABLE juegos ADD COLUMN independiente_idioma INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juegos ADD COLUMN tradumaquetado INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juegos ADD COLUMN tradumaquetado_parcial INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juegos ADD COLUMN tradumaquetado_parcial_notas TEXT');
    await db.execute('ALTER TABLE juegos ADD COLUMN varias_copias INTEGER NOT NULL DEFAULT 0');

    // Backfill es_expansion
    await db.execute("UPDATE juegos SET es_expansion = 1 WHERE juego_base_server_id IS NOT NULL OR juego_base_local_id IS NOT NULL");

    // Migrate old estado values
    await db.execute("UPDATE juegos SET estado = 'disponible' WHERE estado NOT IN ('disponible', 'en_venta', 'vendido')");

    // ubicacion on juego_propietario
    await db.execute('ALTER TABLE juego_propietario ADD COLUMN ubicacion_server_id INTEGER');
    await db.execute('ALTER TABLE juego_propietario ADD COLUMN ubicacion_local_id INTEGER');

    // juego_categoria pivot table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS juego_categoria (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_server_id INTEGER,
        juego_local_id INTEGER,
        categoria_server_id INTEGER,
        categoria_local_id INTEGER,
        updated_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        pending_action TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_jc_juego ON juego_categoria(juego_local_id)');

    // Migrate existing categoria_id to juego_categoria
    await db.execute('''
      INSERT INTO juego_categoria (juego_local_id, juego_server_id, categoria_local_id, categoria_server_id, dirty)
      SELECT local_id, server_id, categoria_local_id, categoria_server_id, 0
      FROM juegos
      WHERE categoria_local_id IS NOT NULL OR categoria_server_id IS NOT NULL
    ''');

    // Force full re-pull to get new fields from server
    await db.delete('sync_state', where: "key = 'last_pull_at'");
  }

  Future<void> _migrateToV5(Database db) async {
    await db.execute('ALTER TABLE juegos ADD COLUMN precio REAL');
    await db.execute('ALTER TABLE juegos ADD COLUMN en_caja_base INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _migrateToV6(Database db) async {
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN es_principal INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juego_propietario ADD COLUMN estado TEXT');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN no_enfundar INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE juego_propietario ADD COLUMN idiomas TEXT');
    await db.execute('ALTER TABLE juego_propietario ADD COLUMN idioma_otro TEXT');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN independiente_idioma INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN tradumaquetado INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN tradumaquetado_parcial INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN tradumaquetado_parcial_notas TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS juego_propietario_fundas (
        local_id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id INTEGER UNIQUE,
        juego_propietario_server_id INTEGER,
        juego_propietario_local_id INTEGER,
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
        'CREATE INDEX IF NOT EXISTS idx_jpf_jp ON juego_propietario_fundas(juego_propietario_local_id)');

    // Backfill es_principal where owner location matches game location.
    await db.execute('''
      UPDATE juego_propietario
      SET es_principal = 1
      WHERE juego_local_id IN (
        SELECT local_id FROM juegos WHERE varias_copias = 1 AND ubicacion_local_id IS NOT NULL
      )
      AND ubicacion_local_id = (
        SELECT ubicacion_local_id FROM juegos j
        WHERE j.local_id = juego_propietario.juego_local_id
      )
    ''');
  }

  Future<void> _migrateToV7(Database db) async {
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN fecha_compra TEXT');

    // Backfill principal copy from game-level purchase date.
    await db.execute('''
      UPDATE juego_propietario
      SET fecha_compra = (
        SELECT fecha_compra FROM juegos j
        WHERE j.local_id = juego_propietario.juego_local_id
      )
      WHERE es_principal = 1
        AND fecha_compra IS NULL
        AND juego_local_id IN (
          SELECT local_id FROM juegos WHERE varias_copias = 1 AND fecha_compra IS NOT NULL
        )
    ''');
  }

  Future<void> _migrateToV8(Database db) async {
    await db.execute(
        'ALTER TABLE juegos ADD COLUMN sin_abrir INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE juegos ADD COLUMN print_and_play INTEGER NOT NULL DEFAULT 0');

    // Fuerza un re-pull completo para traer los nuevos campos del servidor.
    await db.delete('sync_state', where: "key = 'last_pull_at'");
  }

  Future<void> _migrateToV9(Database db) async {
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN sin_abrir INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE juego_propietario ADD COLUMN print_and_play INTEGER NOT NULL DEFAULT 0');

    // Backfill: la copia principal hereda los indicadores del juego.
    await db.execute('''
      UPDATE juego_propietario
      SET sin_abrir = (
            SELECT sin_abrir FROM juegos j
            WHERE j.local_id = juego_propietario.juego_local_id
          ),
          print_and_play = (
            SELECT print_and_play FROM juegos j
            WHERE j.local_id = juego_propietario.juego_local_id
          )
      WHERE es_principal = 1
        AND juego_local_id IN (
          SELECT local_id FROM juegos WHERE varias_copias = 1
        )
    ''');

    // Fuerza un re-pull completo para traer los nuevos campos del servidor.
    await db.delete('sync_state', where: "key = 'last_pull_at'");
  }

  Future<void> _migrateToV10(Database db) async {
    await db.execute(
        'ALTER TABLE juegos ADD COLUMN autojugable INTEGER NOT NULL DEFAULT 0');

    // Fuerza un re-pull completo para traer el nuevo campo del servidor.
    await db.delete('sync_state', where: "key = 'last_pull_at'");
  }

  /// Columna persistente `nombre_norm` (minúsculas + sin acentos) para poder
  /// ordenar y buscar de forma insensible a tildes sin usar expresiones SQL
  /// frágiles (REPLACE anidados) que fallan en el SQLite de algunos dispositivos.
  Future<void> _migrateToV11(Database db) async {
    await db.execute('ALTER TABLE juegos ADD COLUMN nombre_norm TEXT');

    // Backfill de las filas existentes normalizando en Dart.
    final rows = await db.query('juegos', columns: ['local_id', 'nombre']);
    final batch = db.batch();
    for (final r in rows) {
      final nombre = (r['nombre'] as String?) ?? '';
      batch.update(
        'juegos',
        {'nombre_norm': normalizeText(nombre)},
        where: 'local_id = ?',
        whereArgs: [r['local_id']],
      );
    }
    await batch.commit(noResult: true);

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_juegos_nombre_norm ON juegos(nombre_norm)');
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
