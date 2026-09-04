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
    final user = data['user'] as Map<String, dynamic>;
    await _cacheUser(prefs, user);
    return user;
  }

  /// Guarda los datos completos del usuario en SharedPreferences para
  /// poder restaurar la sesión sin llamada de red al arrancar.
  Future<void> _cacheUser(SharedPreferences prefs, Map<String, dynamic> user) async {
    await prefs.setString('user_name', user['name'] ?? '');
    await prefs.setString('user_email', user['email'] ?? '');
    if (user['bgg_username'] != null) {
      await prefs.setString('bgg_username', user['bgg_username']);
    } else {
      await prefs.remove('bgg_username');
    }
    await prefs.setBool('bgg_connected', user['bgg_connected'] == true);
    await prefs.setBool('no_enfundo', user['no_enfundo'] == true);
    await prefs.setBool('ocultar_por_estrenar', user['ocultar_por_estrenar'] == true);
    await prefs.setBool('ocultar_faltan_traduccion', user['ocultar_faltan_traduccion'] == true);
    await prefs.setBool('ocultar_expansion_otro_idioma', user['ocultar_expansion_otro_idioma'] == true);
    await prefs.setBool('ocultar_por_colocar', user['ocultar_por_colocar'] == true);
    await prefs.setBool('ocultar_nuevas_expansiones', user['ocultar_nuevas_expansiones'] == true);
  }

  /// Reconstruye un mapa de usuario a partir de SharedPreferences
  /// para poder arrancar sin esperar al servidor.
  Future<Map<String, dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return null;
    final name = prefs.getString('user_name');
    if (name == null) return null;
    return {
      'name': name,
      'email': prefs.getString('user_email') ?? '',
      'bgg_username': prefs.getString('bgg_username'),
      'bgg_connected': prefs.getBool('bgg_connected') ?? false,
      'no_enfundo': prefs.getBool('no_enfundo') ?? false,
      'ocultar_por_estrenar': prefs.getBool('ocultar_por_estrenar') ?? false,
      'ocultar_faltan_traduccion': prefs.getBool('ocultar_faltan_traduccion') ?? false,
      'ocultar_expansion_otro_idioma': prefs.getBool('ocultar_expansion_otro_idioma') ?? false,
      'ocultar_por_colocar': prefs.getBool('ocultar_por_colocar') ?? false,
      'ocultar_nuevas_expansiones': prefs.getBool('ocultar_nuevas_expansiones') ?? false,
    };
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
    await prefs.remove('bgg_connected');
    await prefs.remove('no_enfundo');
    await prefs.remove('ocultar_por_estrenar');
    await prefs.remove('ocultar_faltan_traduccion');
    await prefs.remove('ocultar_expansion_otro_idioma');
    await prefs.remove('ocultar_por_colocar');
    await prefs.remove('ocultar_nuevas_expansiones');
  }

  Future<Map<String, dynamic>?> getUser() async {
    try {
      final response = await _api.get('/user');
      final user = response.data['user'] as Map<String, dynamic>?;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await _cacheUser(prefs, user);
      }
      return user;
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
