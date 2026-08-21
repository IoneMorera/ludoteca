import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _api.post('/mobile/login', data: {
      'email': email,
      'password': password,
    });

    return _persistSession(response.data);
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    String? bggUsername,
  }) async {
    final response = await _api.post('/register', data: {
      'name': name,
      'email': email,
      'password': password,
      'password_confirmation': passwordConfirmation,
      if (bggUsername != null && bggUsername.isNotEmpty)
        'bgg_username': bggUsername,
    });

    return _persistSession(response.data);
  }

  Future<Map<String, dynamic>> _persistSession(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token']);
    await prefs.setString('user_name', data['user']['name']);
    await prefs.setString('user_email', data['user']['email']);
    if (data['user']['bgg_username'] != null) {
      await prefs.setString('bgg_username', data['user']['bgg_username']);
    }

    return data['user'] as Map<String, dynamic>;
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

  Future<Map<String, dynamic>?> updateUser({
    String? name,
    String? bggUsername,
    bool? noEnfundo,
    bool? ocultarPorEstrenar,
    bool? ocultarFaltanTraduccion,
    bool? ocultarExpansionOtroIdioma,
    bool? ocultarPorColocar,
    bool? ocultarNuevasExpansiones,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (bggUsername != null) body['bgg_username'] = bggUsername;
    if (noEnfundo != null) body['no_enfundo'] = noEnfundo;
    if (ocultarPorEstrenar != null) {
      body['ocultar_por_estrenar'] = ocultarPorEstrenar;
    }
    if (ocultarFaltanTraduccion != null) {
      body['ocultar_faltan_traduccion'] = ocultarFaltanTraduccion;
    }
    if (ocultarExpansionOtroIdioma != null) {
      body['ocultar_expansion_otro_idioma'] = ocultarExpansionOtroIdioma;
    }
    if (ocultarPorColocar != null) {
      body['ocultar_por_colocar'] = ocultarPorColocar;
    }
    if (ocultarNuevasExpansiones != null) {
      body['ocultar_nuevas_expansiones'] = ocultarNuevasExpansiones;
    }
    if (body.isEmpty) return null;
    final response = await _api.put('/user', data: body);
    final user = response.data['user'] as Map<String, dynamic>?;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      if (user['name'] != null) {
        await prefs.setString('user_name', user['name']);
      }
      if (user['bgg_username'] != null) {
        await prefs.setString('bgg_username', user['bgg_username']);
      } else {
        await prefs.remove('bgg_username');
      }
      if (user['no_enfundo'] != null) {
        await prefs.setBool('no_enfundo', user['no_enfundo'] == true);
      }
    }
    return user;
  }

  Future<Map<String, dynamic>> connectBgg({
    required String username,
    required String password,
  }) async {
    final response = await _api.post('/bgg/connect', data: {
      'username': username,
      'password': password,
    });
    final user = response.data['user'] as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    if (user['bgg_username'] != null) {
      await prefs.setString('bgg_username', user['bgg_username']);
    }
    return user;
  }

  Future<Map<String, dynamic>> disconnectBgg() async {
    final response = await _api.post('/bgg/disconnect');
    return response.data['user'] as Map<String, dynamic>;
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
