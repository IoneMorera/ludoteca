import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _user;
  bool _loading = false;
  String? _error;

  Map<String, dynamic>? get user => _user;
  bool get loading => _loading;
  bool get isAuthenticated => _user != null;
  String? get error => _error;
  String get userName => _user?['name'] ?? '';
  String get userEmail => _user?['email'] ?? '';
  String? get bggUsername => _user?['bgg_username'];
  bool get bggConnected => _user?['bgg_connected'] == true;
  bool get noEnfundo => _user?['no_enfundo'] == true;
  bool get ocultarPorEstrenar => _user?['ocultar_por_estrenar'] == true;
  bool get ocultarFaltanTraduccion =>
      _user?['ocultar_faltan_traduccion'] == true;
  bool get ocultarExpansionOtroIdioma =>
      _user?['ocultar_expansion_otro_idioma'] == true;
  bool get ocultarPorColocar => _user?['ocultar_por_colocar'] == true;
  bool get ocultarNuevasExpansiones =>
      _user?['ocultar_nuevas_expansiones'] == true;

  Future<bool> checkAuth() async {
    if (!await _authService.isLoggedIn()) return false;
    try {
      _user = await _authService.getUser();
      notifyListeners();
      return _user != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.login(email, password);
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _loading = false;
      _error = _parseLoginError(e);
      notifyListeners();
      return false;
    }
  }

  String _parseLoginError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.response == null) {
        return 'No se pudo conectar con el servidor. Comprueba tu conexión.';
      }
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return 'Credenciales incorrectas';
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? bggUsername,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.register(
        name: name,
        email: email,
        password: password,
        passwordConfirmation: passwordConfirmation,
        bggUsername: bggUsername,
      );
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _loading = false;
      _error = _parseRegisterError(e);
      notifyListeners();
      return false;
    }
  }

  String _parseRegisterError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['errors'] is Map) {
        final errors = Map<String, dynamic>.from(data['errors'] as Map);
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty) {
            return value.first.toString();
          }
        }
      }
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return 'No se pudo crear la cuenta. Revisa los datos e inténtalo de nuevo.';
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    notifyListeners();
  }

  Future<bool> updateProfile({
    String? name,
    String? bggUsername,
    bool? noEnfundo,
    bool? ocultarPorEstrenar,
    bool? ocultarFaltanTraduccion,
    bool? ocultarExpansionOtroIdioma,
    bool? ocultarPorColocar,
    bool? ocultarNuevasExpansiones,
  }) async {
    try {
      final updated = await _authService.updateUser(
        name: name,
        bggUsername: bggUsername,
        noEnfundo: noEnfundo,
        ocultarPorEstrenar: ocultarPorEstrenar,
        ocultarFaltanTraduccion: ocultarFaltanTraduccion,
        ocultarExpansionOtroIdioma: ocultarExpansionOtroIdioma,
        ocultarPorColocar: ocultarPorColocar,
        ocultarNuevasExpansiones: ocultarNuevasExpansiones,
      );
      if (updated != null) {
        _user = updated;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<String?> connectBgg({
    required String username,
    required String password,
  }) async {
    try {
      _user = await _authService.connectBgg(
        username: username,
        password: password,
      );
      notifyListeners();
      return null;
    } catch (e) {
      return _parseApiError(e, 'No se pudo conectar con BoardGameGeek.');
    }
  }

  Future<String?> disconnectBgg() async {
    try {
      _user = await _authService.disconnectBgg();
      notifyListeners();
      return null;
    } catch (e) {
      return _parseApiError(e, 'No se pudo desconectar de BoardGameGeek.');
    }
  }

  String _parseApiError(Object e, String fallback) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
    }
    return fallback;
  }
}
