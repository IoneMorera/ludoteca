import 'dart:io';

import 'package:flutter/services.dart';

/// Mantiene vivo el escaneo BGG en Android con un servicio en primer plano.
///
/// Sin esto, al salir de la app o apagar la pantalla el sistema corta la red
/// y el escaneo falla. iOS no permite un trabajo tan largo en segundo plano.
class ForegroundScanKeeper {
  static const _channel =
      MethodChannel('com.ludoteca.ludoteca_mobile/foreground');

  static bool get isSupported => Platform.isAndroid;

  static Future<void> start({
    String title = 'Comprobando expansiones',
    String text = 'El escaneo continúa en segundo plano',
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('start', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  static Future<void> update(String text) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('update', {'text': text});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
