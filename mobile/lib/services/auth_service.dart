import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _api.post('/mobile/login', data: {
      'email': email,
      'password': password,
    });

    final data = response.data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token']);
    await prefs.setString('user_name', data['user']['name']);
    await prefs.setString('user_email', data['user']['email']);
    if (data['user']['bgg_username'] != null) {
      await prefs.setString('bgg_username', data['user']['bgg_username']);
    }

    return data['user'];
  }

  Future<void> logout() async {
    try {
      await _api.post('/mobile/logout');
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('bgg_username');
  }

  Future<Map<String, dynamic>?> getUser() async {
    try {
      final response = await _api.get('/user');
      return response.data['user'];
    } catch (_) {
      return null;
    }
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') != null;
  }

  Future<String?> getSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }
}
