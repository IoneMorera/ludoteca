import 'package:flutter/material.dart';
import '../models/juego.dart';
import '../services/api_service.dart';

class JuegosProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Juego> _juegos = [];
  Juego? _juegoDetalle;
  bool _loading = false;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  String _busqueda = '';
  Map<String, dynamic> _stats = {};

  List<Juego> get juegos => _juegos;
  Juego? get juegoDetalle => _juegoDetalle;
  bool get loading => _loading;
  int get currentPage => _currentPage;
  int get lastPage => _lastPage;
  int get total => _total;
  Map<String, dynamic> get stats => _stats;

  Future<void> fetchJuegos({int page = 1, String? buscar}) async {
    _loading = true;
    notifyListeners();

    if (buscar != null) _busqueda = buscar;

    try {
      final params = <String, dynamic>{'page': page};
      if (_busqueda.isNotEmpty) params['buscar'] = _busqueda;

      final response = await _api.get('/juegos', params: params);
      final data = response.data;

      _juegos = (data['data'] as List).map((j) => Juego.fromJson(j)).toList();
      _currentPage = data['current_page'] ?? 1;
      _lastPage = data['last_page'] ?? 1;
      _total = data['total'] ?? 0;
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> fetchJuego(int id) async {
    _loading = true;
    _juegoDetalle = null;
    notifyListeners();

    try {
      final response = await _api.get('/juegos/$id');
      _juegoDetalle = Juego.fromJson(response.data);
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> fetchStats() async {
    try {
      final response = await _api.get('/stats');
      _stats = response.data;
    } catch (_) {}
    notifyListeners();
  }

  Future<List<Categoria>> fetchCategorias() async {
    try {
      final response = await _api.get('/categorias');
      return (response.data as List)
          .map((c) => Categoria.fromJson(c))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Propietario>> fetchPropietarios() async {
    try {
      final response = await _api.get('/propietarios');
      return (response.data as List)
          .map((p) => Propietario.fromJson(p))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void clearBusqueda() {
    _busqueda = '';
  }
}
