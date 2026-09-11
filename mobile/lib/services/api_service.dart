import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio dio;

  /// Instancia cacheada de SharedPreferences para evitar llamar
  /// getInstance() en cada request HTTP.
  static SharedPreferences? _prefs;

  /// Precarga SharedPreferences para que el interceptor sea síncrono.
  /// Llamar una vez en main() antes de cualquier petición HTTP.
  static Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  ApiService._internal() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        _prefs = prefs;
        final token = prefs.getString('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (_shouldRetry(error)) {
          _retryRequest(error, handler);
        } else {
          handler.next(error);
        }
      },
    ));
  }

  /// Determina si un error es transitorio y merece reintento.
  static bool _shouldRetry(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    final statusCode = error.response?.statusCode;
    return statusCode != null && (statusCode >= 500 || statusCode == 429);
  }

  /// Reintenta la petición una vez tras un breve delay.
  Future<void> _retryRequest(
      DioException error, ErrorInterceptorHandler handler) async {
    try {
      await Future.delayed(const Duration(milliseconds: 800));
      final opts = error.requestOptions;
      final response = await dio.fetch(opts);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  void updateBaseUrl(String serverUrl) {
    dio.options.baseUrl = '$serverUrl/api';
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) {
    return dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data, Options? options}) {
    return dio.post(path, data: data, options: options);
  }

  Future<Response> put(String path, {dynamic data}) {
    return dio.put(path, data: data);
  }

  Future<Response> delete(String path) {
    return dio.delete(path);
  }

  Future<Response> upload(String path, FormData data) {
    return dio.post(path, data: data);
  }
}
