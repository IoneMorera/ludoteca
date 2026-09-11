import 'dart:async';

import 'package:flutter/material.dart';

import '../data/evento_repository.dart';
import '../data/outbox_dao.dart';
import '../data/sync_service.dart';
import '../models/evento.dart';
import '../services/database_service.dart';

class EventosProvider extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  late final OutboxDao _outbox = OutboxDao(_dbService);
  late final EventoRepository _eventos = EventoRepository(_dbService, _outbox);

  List<Evento> _eventosFuturos = [];
  List<Evento> _eventosPasados = [];
  Evento? _eventoDetalle;
  Evento? _proximoEvento;
  int _eventosPendientesCount = 0;
  int _totalEventosResumen = 0;
  bool _loading = false;

  List<Evento> get eventosFuturos => _eventosFuturos;
  List<Evento> get eventosPasados => _eventosPasados;
  Evento? get eventoDetalle => _eventoDetalle;
  Evento? get proximoEvento => _proximoEvento;
  int get eventosPendientesCount => _eventosPendientesCount;
  int get totalEventosResumen => _totalEventosResumen;
  bool get loading => _loading;

  EventoRepository get eventoRepository => _eventos;

  Future<void> fetchEventos() async {
    _loading = true;
    notifyListeners();
    try {
      _eventosFuturos = await _eventos.getFuturos();
      _eventosPasados = await _eventos.getPasados();
    } catch (e) {
      debugPrint('fetchEventos error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> fetchEventosResumen() async {
    try {
      _eventosPendientesCount = await _eventos.countPendientesColocar();
      _totalEventosResumen = await _eventos.countFuturosYCerrados();
      _proximoEvento = await _eventos.getProximoEvento();
    } catch (e) {
      debugPrint('fetchEventosResumen error: $e');
    }
    notifyListeners();
  }

  Future<void> fetchEvento(int localId) async {
    _loading = true;
    _eventoDetalle = null;
    notifyListeners();
    try {
      _eventoDetalle = await _eventos.getByLocalId(localId);
    } catch (e) {
      debugPrint('fetchEvento error: $e');
    }
    _loading = false;
    notifyListeners();
  }

  Future<int> saveEvento(Evento evento) async {
    final localId = await _eventos.save(evento);
    unawaited(SyncService().syncAll());
    await fetchEventos();
    await fetchEventosResumen();
    return localId;
  }

  Future<void> addJuego(int eventoLocalId, int juegoLocalId) async {
    await _eventos.addJuego(eventoLocalId, juegoLocalId);
    unawaited(SyncService().syncAll());
    await fetchEvento(eventoLocalId);
    await fetchEventosResumen();
  }

  Future<void> removeJuego(int eventoLocalId, int juegoLocalId) async {
    await _eventos.removeJuego(eventoLocalId, juegoLocalId);
    unawaited(SyncService().syncAll());
    await fetchEvento(eventoLocalId);
  }

  Future<void> cerrarEvento(int localId) async {
    await _eventos.cerrarEvento(localId);
    unawaited(SyncService().syncAll());
    await fetchEventos();
    await fetchEventosResumen();
  }

  Future<void> deleteEvento(int localId) async {
    await _eventos.delete(localId);
    unawaited(SyncService().syncAll());
    await fetchEventos();
    await fetchEventosResumen();
  }
}
