import 'dart:async';

import 'package:flutter/material.dart';

import '../data/bgg_expansion_repository.dart';
import '../data/categoria_repository.dart';
import '../data/juego_repository.dart';
import '../data/outbox_dao.dart';
import '../data/propietario_repository.dart';
import '../data/sync_service.dart';
import '../data/tipo_funda_repository.dart';
import '../data/ubicacion_repository.dart';
import '../models/juego.dart';
import '../services/database_service.dart';

/// Provider que centraliza el acceso a los juegos para la UI.
///
/// Todas las lecturas/escrituras se hacen contra la BBDD local (offline-first).
/// El push al servidor lo realiza `SyncService` desde el outbox.
class JuegosProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  late final OutboxDao _outbox = OutboxDao(_dbService);
  late final JuegoRepository _juegos = JuegoRepository(_dbService, _outbox);
  late final CategoriaRepository _categorias =
      CategoriaRepository(_dbService, _outbox);
  late final PropietarioRepository _propietarios =
      PropietarioRepository(_dbService, _outbox);
  late final UbicacionRepository _ubicaciones =
      UbicacionRepository(_dbService, _outbox);
  late final TipoFundaRepository _tiposFunda =
      TipoFundaRepository(_dbService, _outbox);
  late final BggExpansionRepository _bggExpansiones =
      BggExpansionRepository(_dbService, _outbox);

  List<Juego> _items = [];
  Juego? _juegoDetalle;
  bool _loading = false;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  String _busqueda = '';
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _fundasFaltantes = [];

  List<Juego> get juegos => _items;
  Juego? get juegoDetalle => _juegoDetalle;
  bool get loading => _loading;
  int get currentPage => _currentPage;
  int get lastPage => _lastPage;
  int get total => _total;
  Map<String, dynamic> get stats => _stats;
  List<Map<String, dynamic>> get fundasFaltantes => _fundasFaltantes;

  static const int _perPage = 30;

  JuegoRepository get juegoRepository => _juegos;
  BggExpansionRepository get bggExpansionRepository => _bggExpansiones;
  CategoriaRepository get categoriaRepository => _categorias;
  PropietarioRepository get propietarioRepository => _propietarios;
  UbicacionRepository get ubicacionRepository => _ubicaciones;
  TipoFundaRepository get tipoFundaRepository => _tiposFunda;

  String? _estadoFilter;
  bool? _esExpansionFilter;
  int? _categoriaLocalId;
  int? _tipoFundaLocalId;
  int? _ubicacionLocalId;

  String? get estadoFilter => _estadoFilter;
  bool? get esExpansionFilter => _esExpansionFilter;

  void setFilters({
    String? estado,
    bool? esExpansion,
    int? categoriaLocalId,
    int? tipoFundaLocalId,
    int? ubicacionLocalId,
  }) {
    _estadoFilter = estado;
    _esExpansionFilter = esExpansion;
    _categoriaLocalId = categoriaLocalId;
    _tipoFundaLocalId = tipoFundaLocalId;
    _ubicacionLocalId = ubicacionLocalId;
  }

  void resetFilters() {
    _estadoFilter = null;
    _esExpansionFilter = null;
    _categoriaLocalId = null;
    _tipoFundaLocalId = null;
    _ubicacionLocalId = null;
    _busqueda = '';
  }

  Future<void> fetchJuegos({
    int page = 1,
    String? buscar,
    String? estado,
    bool? esExpansion,
    int? categoriaLocalId,
    int? tipoFundaLocalId,
    int? ubicacionLocalId,
  }) async {
    _loading = true;
    notifyListeners();
    if (buscar != null) _busqueda = buscar;
    if (estado != null) _estadoFilter = estado;
    if (esExpansion != null) _esExpansionFilter = esExpansion;
    if (categoriaLocalId != null) _categoriaLocalId = categoriaLocalId;
    if (tipoFundaLocalId != null) _tipoFundaLocalId = tipoFundaLocalId;
    if (ubicacionLocalId != null) _ubicacionLocalId = ubicacionLocalId;
    try {
      _items = await _juegos.search(
        buscar: _busqueda.isEmpty ? null : _busqueda,
        page: page,
        perPage: _perPage,
        estado: _estadoFilter,
        esExpansion: _esExpansionFilter,
        categoriaLocalId: _categoriaLocalId,
        tipoFundaLocalId: _tipoFundaLocalId,
        ubicacionLocalId: _ubicacionLocalId,
      );
      _total = await _juegos.count(
        buscar: _busqueda.isEmpty ? null : _busqueda,
        estado: _estadoFilter,
        esExpansion: _esExpansionFilter,
        categoriaLocalId: _categoriaLocalId,
        tipoFundaLocalId: _tipoFundaLocalId,
        ubicacionLocalId: _ubicacionLocalId,
      );
      _currentPage = page;
      _lastPage = ((_total / _perPage).ceil()).clamp(1, 9999);
    } catch (e) {
      debugPrint('fetchJuegos local error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchJuego(int localOrServerId, {bool isServerId = false}) async {
    // No resetear _juegoDetalle a null: la lectura SQLite es casi instantánea
    // y poner null causa un flash blanco innecesario en la pantalla.
    _loading = _juegoDetalle == null;
    if (_loading) notifyListeners();
    try {
      if (isServerId) {
        _juegoDetalle = await _juegos.getByServerId(localOrServerId);
      } else {
        _juegoDetalle = await _juegos.getByLocalId(localOrServerId);
        _juegoDetalle ??= await _juegos.getByServerId(localOrServerId);
      }
    } catch (e) {
      debugPrint('fetchJuego local error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshDetail() async {
    if (_juegoDetalle == null) return;
    final localId = _juegoDetalle!.localId;
    if (localId != null) {
      _juegoDetalle = await _juegos.getByLocalId(localId);
    } else if (_juegoDetalle!.serverId != null) {
      _juegoDetalle = await _juegos.getByServerId(_juegoDetalle!.serverId!);
    }
    notifyListeners();
  }

  Future<void> fetchStats() async {
    try {
      _stats = await _juegos.stats();
      _stats['expansionesNuevas'] =
          await _bggExpansiones.countNuevasDelAnio();
      _fundasFaltantes = await _juegos.fundasFaltantesAgrupadas();
      _stats['fundasFaltantes'] = _fundasFaltantes;
    } catch (e) {
      debugPrint('fetchStats local error: $e');
    }
    notifyListeners();
  }

  Future<List<BggExpansionRow>> faltantesExpansiones(int baseBggId) =>
      _bggExpansiones.faltantesDe(baseBggId);

  Future<int> saveJuego(
    Juego juego, {
    required List<int> propietarioLocalIds,
    required List<JuegoFundaDraft> fundas,
    List<int> categoriaLocalIds = const [],
    Map<int, int?> propietarioUbicaciones = const {},
    Map<int, CopiaPropietarioDraft>? copiasData,
  }) async {
    final localId = await _juegos.save(
      juego,
      propietarioLocalIds: propietarioLocalIds,
      fundas: fundas,
      categoriaLocalIds: categoriaLocalIds,
      propietarioUbicaciones: propietarioUbicaciones,
      copiasData: copiasData,
    );
    unawaited(SyncService().syncAll());
    await fetchJuegos(page: _currentPage);
    return localId;
  }

  Future<void> deleteJuego(int localId) async {
    await _juegos.delete(localId);
    unawaited(SyncService().syncAll());
    await fetchJuegos(page: _currentPage);
  }

  void clearBusqueda() {
    _busqueda = '';
  }
}
