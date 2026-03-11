import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
// juego.dart not directly imported; raw maps used for cache
import '../models/partida.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'ludoteca.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE juegos_cache (
            id INTEGER PRIMARY KEY,
            nombre TEXT NOT NULL,
            descripcion TEXT,
            imagen TEXT,
            edad_minima INTEGER,
            num_jugadores_min INTEGER,
            num_jugadores_max INTEGER,
            categoria_nombre TEXT,
            estado TEXT,
            fecha_compra TEXT,
            juego_base_id INTEGER,
            ubicacion_texto TEXT,
            propietarios_texto TEXT,
            data_json TEXT
          )
        ''');
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
      },
    );
  }

  Future<void> cacheJuegos(List<Map<String, dynamic>> juegos) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('juegos_cache');
    for (final j in juegos) {
      batch.insert('juegos_cache', {
        'id': j['id'],
        'nombre': j['nombre'],
        'descripcion': j['descripcion'],
        'imagen': j['imagen'],
        'edad_minima': j['edad_minima'],
        'num_jugadores_min': j['num_jugadores_min'],
        'num_jugadores_max': j['num_jugadores_max'],
        'categoria_nombre': j['categoria']?['nombre'],
        'estado': j['estado'],
        'fecha_compra': j['fecha_compra'],
        'juego_base_id': j['juego_base_id'],
        'ubicacion_texto': _buildUbicacionTexto(j['ubicacion']),
        'propietarios_texto': (j['propietarios'] as List?)
            ?.map((p) => p['nombre'])
            .join(', '),
      });
    }
    await batch.commit(noResult: true);
  }

  String? _buildUbicacionTexto(Map<String, dynamic>? ubicacion) {
    if (ubicacion == null) return null;
    final mueble = ubicacion['mueble'];
    if (mueble == null) return ubicacion['nombre'];
    final hab = mueble['habitacion'];
    return '${hab?['nombre'] ?? ''} › ${mueble['nombre']} › ${ubicacion['nombre']}';
  }

  Future<List<Map<String, dynamic>>> getCachedJuegos({String? buscar}) async {
    final db = await database;
    if (buscar != null && buscar.isNotEmpty) {
      return db.query('juegos_cache',
          where: 'nombre LIKE ?', whereArgs: ['%$buscar%']);
    }
    return db.query('juegos_cache');
  }

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
