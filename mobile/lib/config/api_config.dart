import 'package:shared_preferences/shared_preferences.dart';

import 'app_environment.dart';

class ApiConfig {
  static const String _devServerUrl = 'http://10.0.2.2:8000';
  static const String _prodServerUrl = 'https://ludoteca.up.railway.app';
  static const String _prefsKey = 'server_url';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static String _serverUrl = _devServerUrl;

  static String get defaultServerUrl =>
      AppEnvironment.isDev ? _devServerUrl : _prodServerUrl;

  static String get baseUrl => '$_serverUrl/api';
  static String get storageUrl => _serverUrl;
  static String get serverUrl => _serverUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance(); // ya cacheado por warmUp
    var saved = prefs.getString(_prefsKey);

    // En prod, corrige URLs de emulador guardadas por error en builds anteriores.
    if (!AppEnvironment.isDev &&
        (saved == null || saved.contains('10.0.2.2'))) {
      saved = defaultServerUrl;
      await prefs.setString(_prefsKey, saved);
    }

    _serverUrl = saved ?? defaultServerUrl;
  }

  static Future<void> setServerUrl(String url) async {
    String cleaned = url.trim();
    if (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    _serverUrl = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, cleaned);
  }
}
