import 'package:dio/dio.dart';

class BggWriteException implements Exception {
  BggWriteException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get rateLimited => statusCode == 403 || statusCode == 429;

  @override
  String toString() => message;
}

/// Escrituras a BGG desde el dispositivo (IP residencial/móvil).
/// El backend en cloud dispara Cloudflare Bot Management en geekcollection.php.
class BggWriteService {
  BggWriteService({
    required this.cookie,
    required this.username,
    required this.userAgent,
    required this.referer,
  });

  final String cookie;
  final String username;
  final String userAgent;
  final String referer;

  static const _origin = 'https://boardgamegeek.com';

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _origin,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  Map<String, String> get _headers => {
        'User-Agent': userAgent,
        'Cookie': cookie,
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Accept-Language': 'en-US,en;q=0.9,es;q=0.8',
        'Origin': _origin,
        'Referer': referer,
      };

  Future<void> addOwned(int bggId) async {
    final body = await _addItem(bggId);
    final collId = _extractCollId(body);
    if (collId != null) {
      await _saveStatus(bggId: bggId, collId: collId, own: true, prevOwned: false);
    }
  }

  Future<void> markPrevOwned(int bggId) async {
    final body = await _addItem(bggId);
    final collId = _extractCollId(body);
    if (collId == null) {
      throw BggWriteException(
        502,
        'No se pudo obtener el collid de BGG tras añadir el juego.',
      );
    }
    await _saveStatus(bggId: bggId, collId: collId, own: false, prevOwned: true);
  }

  Future<String> _addItem(int bggId) async {
    final query = {
      'action': 'additem',
      'objecttype': 'thing',
      'objectid': '$bggId',
      'ajax': '1',
      'instanceid': '0',
    };

    var response = await _dio.get<dynamic>(
      '/geekcollection.php',
      queryParameters: query,
      options: Options(headers: _headers),
    );

    var body = _bodyString(response.data);
    if (response.statusCode == 200 && !_looksBlocked(body)) {
      return body;
    }

    response = await _dio.post<dynamic>(
      '/geekcollection.php',
      data: query,
      options: Options(
        headers: {
          ..._headers,
          'X-Requested-With': 'XMLHttpRequest',
        },
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    body = _bodyString(response.data);

    final status = response.statusCode ?? 0;
    if (status == 403 || status == 429 || _looksBlocked(body)) {
      throw BggWriteException(
        status == 0 ? 403 : status,
        'BGG bloqueó temporalmente la escritura (HTTP ${status == 0 ? 403 : status}).',
      );
    }
    if (status != 200) {
      throw BggWriteException(status, 'BGG rechazó la alta del juego (HTTP $status).');
    }

    return body;
  }

  Future<void> _saveStatus({
    required int bggId,
    required int collId,
    required bool own,
    required bool prevOwned,
  }) async {
    final response = await _dio.post<dynamic>(
      '/geekcollection.php',
      data: {
        'action': 'savedata',
        'ajax': '1',
        'collid': '$collId',
        'fieldname': 'status',
        'own': own ? '1' : '0',
        'prevowned': prevOwned ? '1' : '0',
        'objecttype': 'thing',
        'objectid': '$bggId',
      },
      options: Options(
        headers: {
          ..._headers,
          'X-Requested-With': 'XMLHttpRequest',
        },
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final status = response.statusCode ?? 0;
    final body = _bodyString(response.data);
    if (status == 403 || status == 429 || _looksBlocked(body)) {
      throw BggWriteException(
        status == 0 ? 403 : status,
        'BGG bloqueó temporalmente la escritura (HTTP ${status == 0 ? 403 : status}).',
      );
    }
  }

  String _bodyString(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    return data.toString();
  }

  bool _looksBlocked(String body) {
    final lower = body.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('cf-browser-verification') ||
        lower.contains('attention required') ||
        lower.contains('challenge-platform') ||
        lower.contains('must be logged in') ||
        lower.contains('not logged');
  }

  int? _extractCollId(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      final id = int.tryParse(trimmed);
      return (id != null && id > 0) ? id : null;
    }

    final patterns = [
      RegExp(r'\bcollid["\s:=]+(\d+)', caseSensitive: false),
      RegExp(r'\bcollectionid["\s:=]+(\d+)', caseSensitive: false),
      RegExp(r'editownership_(\d+)'),
      RegExp(r'data-collid=["\x27]?(\d+)', caseSensitive: false),
      RegExp(r'/collection/item/(\d+)', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }
}
