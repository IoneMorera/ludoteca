import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Datos del dispositivo que acompañan cada error enviado al backend.
class DeviceContext {
  static String? _model;
  static String? _osVersion;
  static bool _warmedUp = false;

  /// Precarga modelo y versión de SO (no cambian durante la sesión).
  static Future<void> warmUp() async {
    if (_warmedUp) return;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final brand = info.brand.trim();
        final model = info.model.trim();
        final brandLower = brand.toLowerCase();
        final modelLower = model.toLowerCase();
        if (brand.isNotEmpty && !modelLower.startsWith(brandLower)) {
          _model = '$brand $model';
        } else {
          _model = model.isNotEmpty ? model : brand;
        }
        _osVersion =
            'Android ${info.version.release} (SDK ${info.version.sdkInt})';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _model = info.utsname.machine;
        _osVersion = 'iOS ${info.systemVersion}';
      } else {
        _model = Platform.operatingSystem;
        _osVersion = Platform.operatingSystemVersion;
      }
      _warmedUp = true;
    } catch (e) {
      debugPrint('DeviceContext.warmUp failed: $e');
    }
  }

  /// Captura el estado actual: modelo, SO, conexión y memoria libre.
  static Future<Map<String, dynamic>> capture() async {
    if (!_warmedUp) await warmUp();

    return {
      'device_model': _model,
      'os_version': _osVersion,
      'connection_type': await _connectionType(),
      'free_memory': await _freeMemory(),
    };
  }

  static Future<String> _connectionType() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none) && results.length == 1) {
        return 'sin conexión';
      }
      if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'datos móviles';
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.vpn)) return 'VPN';
      if (results.contains(ConnectivityResult.other)) return 'otra';
    } catch (_) {}
    return 'desconocida';
  }

  static Future<String?> _freeMemory() async {
    try {
      final plugin = DeviceInfoPlugin();
      int? mb;
      if (Platform.isAndroid) {
        mb = (await plugin.androidInfo).availableRamSize;
      } else if (Platform.isIOS) {
        mb = (await plugin.iosInfo).availableRamSize;
      }
      if (mb == null || mb <= 0) return null;
      if (mb >= 1024) {
        return '${(mb / 1024).toStringAsFixed(1)} GB';
      }
      return '$mb MB';
    } catch (_) {
      return null;
    }
  }
}
