import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BggIgnoredGame {
  const BggIgnoredGame({
    required this.id,
    required this.nombre,
    this.bggId,
  });

  final int id;
  final String nombre;
  final int? bggId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'bgg_id': bggId,
      };

  factory BggIgnoredGame.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : (rawId as num).toInt();
    final rawBgg = json['bgg_id'];
    int? bggId;
    if (rawBgg is int) {
      bggId = rawBgg;
    } else if (rawBgg is num) {
      bggId = rawBgg.toInt();
    }
    return BggIgnoredGame(
      id: id,
      nombre: json['nombre']?.toString() ?? 'Juego',
      bggId: bggId,
    );
  }

  factory BggIgnoredGame.fromPreview(Map<String, dynamic> item) {
    final rawId = item['id'];
    final id = rawId is int ? rawId : (rawId as num).toInt();
    final rawBgg = item['bgg_id'];
    int? bggId;
    if (rawBgg is int) {
      bggId = rawBgg;
    } else if (rawBgg is num) {
      bggId = rawBgg.toInt();
    }
    return BggIgnoredGame(
      id: id,
      nombre: item['nombre']?.toString() ?? 'Juego',
      bggId: bggId,
    );
  }
}

/// Lista persistente de juegos que no deben volver a proponerse al exportar a BGG.
class BggExportIgnoreStore {
  static const _key = 'bgg_export_ignored';

  static final BggExportIgnoreStore _instance = BggExportIgnoreStore._();
  factory BggExportIgnoreStore() => _instance;
  BggExportIgnoreStore._();

  List<BggIgnoredGame> _items = [];
  bool _loaded = false;

  List<BggIgnoredGame> get items {
    final copy = [..._items];
    copy.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );
    return copy;
  }

  Set<int> get ids => _items.map((e) => e.id).toSet();

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _items = [];
      _loaded = true;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _items = decoded
            .whereType<Map>()
            .map((e) => BggIgnoredGame.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {
      _items = [];
    }
    _loaded = true;
  }

  Future<void> ignore(BggIgnoredGame game) async {
    await load();
    _items.removeWhere((e) => e.id == game.id);
    _items.add(game);
    await _persist();
  }

  Future<void> restore(int id) async {
    await load();
    _items.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
  }
}
