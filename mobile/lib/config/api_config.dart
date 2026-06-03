import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String _defaultServerUrl = 'http://10.0.2.2:8000';
  static const String _prefsKey = 'server_url';

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 60);

  static String _serverUrl = _defaultServerUrl;

  static String get baseUrl => '$_serverUrl/api';
  static String get storageUrl => _serverUrl;
  static String get serverUrl => _serverUrl;
  static String get defaultServerUrl => _defaultServerUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_prefsKey) ?? _defaultServerUrl;
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
