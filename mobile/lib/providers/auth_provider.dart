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
      _error = 'Credenciales incorrectas';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    notifyListeners();
  }
}
