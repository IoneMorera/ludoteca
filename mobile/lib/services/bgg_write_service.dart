import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class BggWriteException implements Exception {
  BggWriteException(
    this.statusCode,
    this.message, {
    this.capture,
    this.attempt = 1,
  });

  final int statusCode;
  final String message;
  final BggHttpCapture? capture;
  final int attempt;

  bool get rateLimited => statusCode == 403 || statusCode == 429;

  String get diagnosticDump =>
      capture?.dump(attempt: attempt, firstOfSession: attempt == 1) ?? message;

  @override
  String toString() => message;
}

class BggHttpCapture {
  const BggHttpCapture({
    required this.status,
    this.url = '',
    this.redirected = false,
    this.type = '',
    this.headers = const {},
    this.body = '',
    this.via = 'fetch',
  });

  final int status;
  final String url;
  final bool redirected;
  final String type;
  final Map<String, String> headers;
  final String body;
  final String via;

  String header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return '';
  }

  String classify() {
    final bodyL = body.toLowerCase();
    final mitigated = header('cf-mitigated').toLowerCase();
    final server = header('server').toLowerCase();
    final cfRay = header('cf-ray');
    final cloudflare = mitigated == 'challenge' ||
        bodyL.contains('just a moment') ||
        bodyL.contains('attention required') ||
        bodyL.contains('cf-error') ||
        bodyL.contains('cf-browser-verification') ||
        bodyL.contains('challenge-platform') ||
        bodyL.contains('ray id') ||
        (status == 403 &&
            (cfRay.isNotEmpty ||
                server.contains('cloudflare') ||
                bodyL.contains('cloudflare')));
    final bggApp = bodyL.contains('temporarily blocked') ||
        bodyL.contains('blocked from editing') ||
        bodyL.contains('blocked from updating') ||
        bodyL.contains('you have been blocked') ||
        bodyL.contains('too many collection');

    if (status == 0) {
      return 'C) Sin respuesta HTTP (fetch falló, CORS o timeout)';
    }
    if (cloudflare) {
      return 'A) Challenge de Cloudflare (corta antes de BGG)';
    }
    if (isInvalidAction) {
      return 'E) BGG respondió Invalid action (llegó a la app; el método/formato no vale)';
    }
    if (bggApp) {
      return 'B) Bloqueo de la aplicación BGG (antiabuso cuenta/IP)';
    }
    if (status == 403 || status == 429) {
      return 'D) HTTP $status sin firma clara A/B — hace falta el body';
    }
    return 'HTTP $status (no parece bloqueo)';
  }

  bool get isInvalidAction => body.toLowerCase().contains('invalid action');

  bool get looksBlocked {
    final kind = classify();
    return kind.startsWith('A)') ||
        kind.startsWith('B)') ||
        kind.startsWith('C)') ||
        kind.startsWith('D)');
  }

  bool get isSuccessfulWrite {
    if (status != 200 && status != 201) return false;
    if (looksBlocked || isInvalidAction) return false;
    final bodyL = body.toLowerCase();
    if (bodyL.contains('must be logged') || bodyL.contains('not logged')) {
      return false;
    }
    if (bodyL.contains('messagebox error')) return false;
    return true;
  }

  String dump({required int attempt, required bool firstOfSession}) {
    const interesting = [
      'server',
      'cf-ray',
      'cf-mitigated',
      'content-type',
      'cf-cache-status',
      'refresh',
      'location',
    ];
    final buf = StringBuffer();
    buf.writeln('vía: $via');
    buf.writeln('intento de escritura en esta sesión: $attempt');
    buf.writeln('¿primera alta de la sesión?: ${firstOfSession ? 'sí' : 'no'}');
    buf.writeln('clasificación: ${classify()}');
    buf.writeln('HTTP $status');
    buf.writeln('url final: ${url.isEmpty ? '(desconocida)' : url}');
    buf.writeln('redirected: $redirected');
    buf.writeln('type: ${type.isEmpty ? '(desconocido)' : type}');
    buf.writeln('--- cabeceras clave ---');
    for (final name in interesting) {
      final value = header(name);
      buf.writeln(
        '$name: ${value.isEmpty ? '(ausente o no visible en JS)' : value}',
      );
    }
    buf.writeln('--- todas las cabeceras visibles en JS ---');
    if (headers.isEmpty) {
      buf.writeln('(ninguna)');
    } else {
      headers.forEach((key, value) => buf.writeln('$key: $value'));
    }
    buf.writeln('--- body (${body.length} chars) ---');
    buf.writeln(body.isEmpty ? '(vacío)' : body);
    return buf.toString().trim();
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'url': url,
        'redirected': redirected,
        'type': type,
        'headers': headers,
        'body': body,
        'via': via,
        'diagnosis': classify(),
      };
}

/// Puente para escribir en BGG desde un WebView real (ejecuta JS de Cloudflare).
class BggWebViewBridge {
  _BggWebViewHostState? _state;
  final Completer<void> ready = Completer<void>();

  Future<BggHttpCapture> probeWriteEndpoint() {
    return _requireState().probeWriteEndpoint();
  }

  Future<void> addOwned(int bggId) {
    return _requireState().addOwned(bggId);
  }

  Future<void> markPrevOwned(int bggId) {
    return _requireState().markPrevOwned(bggId);
  }

  _BggWebViewHostState _requireState() {
    final state = _state;
    if (state == null) {
      throw BggWriteException(500, 'WebView de BGG no está listo.');
    }
    return state;
  }
}

class BggWebViewHost extends StatefulWidget {
  const BggWebViewHost({
    super.key,
    required this.bridge,
    required this.cookie,
    required this.username,
    required this.userAgent,
    required this.referer,
  });

  final BggWebViewBridge bridge;
  final String cookie;
  final String username;
  final String userAgent;
  final String referer;

  @override
  State<BggWebViewHost> createState() => _BggWebViewHostState();
}

class _BggWebViewHostState extends State<BggWebViewHost> {
  late final WebViewController _controller;
  Completer<String>? _jsResult;
  int _writeAttempt = 0;

  @override
  void initState() {
    super.initState();
    widget.bridge._state = this;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.userAgent)
      ..addJavaScriptChannel(
        'LudotecaBgg',
        onMessageReceived: (message) {
          final pending = _jsResult;
          if (pending != null && !pending.isCompleted) {
            pending.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _maybeMarkReady();
          },
        ),
      );
    _start();
  }

  Future<void> _configureAndroidCookies() async {
    try {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        final cookiePlatform = WebViewCookieManager().platform;
        if (cookiePlatform is AndroidWebViewCookieManager) {
          await cookiePlatform.setAcceptThirdPartyCookies(platform, true);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.bridge._state == this) {
      widget.bridge._state = null;
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _configureAndroidCookies();
      await _injectCookies();
      await _controller.loadRequest(Uri.parse(widget.referer));
      await _waitUntilBggReady();
      final href = _jsString(
        await _controller.runJavaScriptReturningResult('window.location.href'),
      );
      if (href.contains('/login') && widget.username.isNotEmpty) {
        throw BggWriteException(
          401,
          'BGG no reconoció la sesión de ${widget.username}. Vuelve a conectar la cuenta en el perfil.',
        );
      }
      if (!widget.bridge.ready.isCompleted) {
        widget.bridge.ready.complete();
      }
    } catch (e) {
      if (!widget.bridge.ready.isCompleted) {
        widget.bridge.ready.completeError(e);
      }
    }
  }

  Future<void> _injectCookies() async {
    final manager = WebViewCookieManager();
    for (final part in widget.cookie.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) continue;
      final idx = trimmed.indexOf('=');
      final name = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + 1).trim();
      if (name.isEmpty || value.isEmpty || value.toLowerCase() == 'deleted') {
        continue;
      }
      await manager.setCookie(
        WebViewCookie(
          name: name,
          value: value,
          domain: '.boardgamegeek.com',
          path: '/',
        ),
      );
    }
  }

  Future<void> _maybeMarkReady() async {
    // El challenge de CF termina en onPageFinished sucesivos.
  }

  Future<void> _waitUntilBggReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final raw = await _controller.runJavaScriptReturningResult('''
          (function() {
            var href = String(location.href || '');
            if (href.indexOf('about:blank') !== -1 || href.indexOf('boardgamegeek.com') === -1) {
              return 'loading';
            }
            var t = (document.title || '') + ' ' + (document.body ? document.body.innerText : '');
            t = t.toLowerCase();
            if (t.indexOf('just a moment') !== -1 || t.indexOf('attention required') !== -1) {
              return 'challenge';
            }
            if (document.readyState === 'complete') return 'ok';
            return 'loading';
          })();
        ''');
        final status = _jsString(raw);
        if (status == 'ok') return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    throw BggWriteException(
      403,
      'BGG no superó la verificación de Cloudflare. Complétala en el recuadro si aparece.',
    );
  }

  Future<BggHttpCapture> probeWriteEndpoint() async {
    await _ensureOnBgg();
    final href = _jsString(
      await _controller.runJavaScriptReturningResult('window.location.href'),
    );
    final cookieNames = _jsString(
      await _controller.runJavaScriptReturningResult('''
        (document.cookie || '').split(';').map(function(c) {
          return c.split('=')[0].trim();
        }).filter(Boolean).join(', ')
      '''),
    );
    return BggHttpCapture(
      status: href.contains('boardgamegeek.com') ? 200 : 0,
      url: href,
      body: 'cookies visibles en el WebView: $cookieNames',
      via: 'sonda de sesión (ubicación actual, sin geekcollection)',
    );
  }

  Future<void> addOwned(int bggId) async {
    await _ensureOnBgg();
    final added = await _addItemWithFallbacks(bggId);
    final collId = _extractCollId(added['body'] ?? '');
    if (collId != null) {
      try {
        await _fetchSaveStatus(
          bggId: bggId,
          collId: collId,
          own: true,
          prevOwned: false,
        );
      } on BggWriteException {
        // additem ya deja el juego como Owned por defecto.
      }
    }
  }

  Future<void> markPrevOwned(int bggId) async {
    await _ensureOnBgg();
    final added = await _addItemWithFallbacks(bggId);
    final collId = _extractCollId(added['body'] ?? '');
    if (collId != null) {
      await _fetchSaveStatus(
        bggId: bggId,
        collId: collId,
        own: false,
        prevOwned: true,
      );
      return;
    }
    await _setPrevOwnedOnGamePage(bggId);
  }

  Future<Map<String, String>> _addItemWithFallbacks(int bggId) async {
    _writeAttempt++;
    final dumps = <String>[];
    BggHttpCapture? last;

    Future<Map<String, String>?> tryCapture(BggHttpCapture capture) async {
      last = capture;
      dumps.add(
        capture.dump(
          attempt: _writeAttempt,
          firstOfSession: _writeAttempt == 1,
        ),
      );
      if (capture.isSuccessfulWrite) {
        return {'status': '${capture.status}', 'body': capture.body};
      }
      return null;
    }

    final form = await tryCapture(await _postAddItemForm(bggId));
    if (form != null) return form;

    final jsonFlat =
        await tryCapture(await _postCollectionItemsJson(bggId, wrapped: false));
    if (jsonFlat != null) return jsonFlat;

    final jsonWrapped =
        await tryCapture(await _postCollectionItemsJson(bggId, wrapped: true));
    if (jsonWrapped != null) return jsonWrapped;

    try {
      await _clickAddOnGamePage(bggId);
      return {'status': '200', 'body': 'clicked'};
    } catch (e) {
      dumps.add('clic en ficha: $e');
    }

    throw BggWriteException(
      last?.status == 0 ? 502 : (last?.status ?? 502),
      last?.classify() ?? 'No se pudo añadir el juego a BGG',
      capture: BggHttpCapture(
        status: last?.status ?? 502,
        url: last?.url ?? '',
        redirected: last?.redirected ?? false,
        type: last?.type ?? '',
        headers: last?.headers ?? const {},
        body: dumps.join('\n\n-----\n\n'),
        via: 'fallbacks de alta',
      ),
      attempt: _writeAttempt,
    );
  }

  Future<void> _ensureOnBgg() async {
    final href = _jsString(
      await _controller.runJavaScriptReturningResult('window.location.href'),
    );
    if (!href.contains('boardgamegeek.com') || href.contains('about:blank')) {
      await _controller.loadRequest(Uri.parse(widget.referer));
      await _waitUntilBggReady();
    }
  }

  Future<BggHttpCapture> _postAddItemForm(int bggId) {
    return _runFetchCapture(
      '''
      fetch('https://boardgamegeek.com/geekcollection.php', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01'
        },
        body: 'action=additem&ajax=1&objecttype=thing&objectid=$bggId'
      })
      ''',
      via: 'POST form geekcollection.php action=additem',
    );
  }

  Future<BggHttpCapture> _postCollectionItemsJson(
    int bggId, {
    required bool wrapped,
  }) {
    final payload = wrapped
        ? '{item:{collid:0,objecttype:"thing",objectid:$bggId,status:{own:true,prevowned:false}}}'
        : '{objecttype:"thing",objectid:$bggId,status:{own:true,prevowned:false}}';
    return _runFetchCapture(
      '''
      fetch('https://boardgamegeek.com/api/collectionitems', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify($payload)
      })
      ''',
      via: wrapped
          ? 'POST JSON /api/collectionitems (item wrapper)'
          : 'POST JSON /api/collectionitems',
    );
  }

  Future<void> _clickAddOnGamePage(int bggId) async {
    await _controller.loadRequest(
      Uri.parse('https://boardgamegeek.com/boardgame/$bggId'),
    );
    await _waitUntilBggReady();
    await Future<void>.delayed(const Duration(seconds: 2));
    final status = _jsString(
      await _controller.runJavaScriptReturningResult('''
        (function() {
          function visible(el) {
            if (!el) return false;
            var r = el.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
          }
          var nodes = Array.from(document.querySelectorAll('button, a, span, div[role="button"]'));
          var already = nodes.find(function(el) {
            return /in collection|edit collection|en la colección/i.test(el.textContent || '');
          });
          if (already) return 'already';
          var add = nodes.find(function(el) {
            return /add to collection|añadir a la colección/i.test(el.textContent || '');
          });
          if (add) { add.click(); return 'clicked'; }
          return 'notfound';
        })();
      '''),
    );
    if (status == 'notfound') {
      throw BggWriteException(
        502,
        'No se encontró el botón Add to Collection (no es un 403 HTTP).',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    await _controller.loadRequest(Uri.parse(widget.referer));
    await _waitUntilBggReady();
  }

  Future<void> _setPrevOwnedOnGamePage(int bggId) async {
    await _controller.loadRequest(
      Uri.parse('https://boardgamegeek.com/boardgame/$bggId'),
    );
    await _waitUntilBggReady();
    await Future<void>.delayed(const Duration(seconds: 2));
    final status = _jsString(
      await _controller.runJavaScriptReturningResult('''
        (function() {
          function visible(el) {
            if (!el) return false;
            var r = el.getBoundingClientRect();
            return r.width > 0 && r.height > 0;
          }
          var nodes = Array.from(document.querySelectorAll('button, a, span, div[role="button"], label, input'));
          var edit = nodes.find(function(el) {
            return visible(el) && /edit collection|in collection|editar colección/i.test(el.textContent || '');
          });
          if (edit) edit.click();
          var prev = Array.from(document.querySelectorAll('input[type="checkbox"], label')).find(function(el) {
            var t = (el.textContent || el.getAttribute('name') || el.id || '').toLowerCase();
            return t.indexOf('prevowned') !== -1 || t.indexOf('previously owned') !== -1;
          });
          if (prev) {
            prev.click();
            return 'clicked';
          }
          return 'notfound';
        })();
      '''),
    );
    if (status == 'notfound') {
      throw BggWriteException(
        502,
        'No se pudo marcar Previously Owned en BGG.',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await _controller.loadRequest(Uri.parse(widget.referer));
    await _waitUntilBggReady();
  }

  Future<void> _fetchSaveStatus({
    required int bggId,
    required int collId,
    required bool own,
    required bool prevOwned,
  }) async {
    final capture = await _runFetchCapture(
      '''
      fetch('https://boardgamegeek.com/geekcollection.php', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'X-Requested-With': 'XMLHttpRequest'
        },
        body: 'action=savedata&ajax=1&collid=$collId&fieldname=status&own=${own ? 1 : 0}&prevowned=${prevOwned ? 1 : 0}&objecttype=thing&objectid=$bggId'
      })
      ''',
      via: 'fetch POST savedata',
    );
    if (capture.looksBlocked || capture.status == 403 || capture.status == 429) {
      throw BggWriteException(
        capture.status == 0 ? 403 : capture.status,
        capture.classify(),
        capture: capture,
        attempt: _writeAttempt,
      );
    }
  }

  Future<BggHttpCapture> _runFetchCapture(
    String fetchExpr, {
    required String via,
  }) async {
    _jsResult = Completer<String>();
    await _controller.runJavaScript('''
      (async function() {
        try {
          const r = await $fetchExpr;
          const headers = {};
          try { r.headers.forEach(function(v, k) { headers[k] = v; }); } catch (e) {}
          const t = await r.text();
          LudotecaBgg.postMessage(JSON.stringify({
            status: r.status,
            url: r.url,
            redirected: r.redirected,
            type: r.type,
            headers: headers,
            body: t.slice(0, 8000)
          }));
        } catch (e) {
          LudotecaBgg.postMessage(JSON.stringify({
            status: 0,
            url: '',
            redirected: false,
            type: 'error',
            headers: {},
            body: String(e)
          }));
        }
      })();
    ''');
    final raw = await _jsResult!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          '{"status":0,"url":"","redirected":false,"type":"timeout","headers":{},"body":"timeout"}',
    );
    _jsResult = null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final headerMap = <String, String>{};
        final rawHeaders = decoded['headers'];
        if (rawHeaders is Map) {
          rawHeaders.forEach((key, value) {
            headerMap['$key'] = '$value';
          });
        }
        return BggHttpCapture(
          status: int.tryParse('${decoded['status'] ?? 0}') ?? 0,
          url: '${decoded['url'] ?? ''}',
          redirected: decoded['redirected'] == true,
          type: '${decoded['type'] ?? ''}',
          headers: headerMap,
          body: '${decoded['body'] ?? ''}',
          via: via,
        );
      }
    } catch (_) {}
    return BggHttpCapture(status: 0, body: raw, via: via);
  }

  String _jsString(dynamic raw) {
    var text = raw?.toString() ?? '';
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        text = jsonDecode(text) as String;
      } catch (_) {
        text = text.substring(1, text.length - 1);
      }
    }
    return text;
  }

  bool _looksBlocked(String body) {
    final lower = body.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('cf-browser-verification') ||
        lower.contains('attention required') ||
        lower.contains('challenge-platform');
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

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
