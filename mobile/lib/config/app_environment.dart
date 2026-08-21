import 'package:package_info_plus/package_info_plus.dart';

/// Detecta el flavor de la app (prod vs dev) a partir del applicationId.
///
/// - Dev: `com.ludoteca.ludoteca_mobile.dev` (suffix `.dev` en Gradle)
/// - Prod: `com.ludoteca.ludoteca_mobile`
class AppEnvironment {
  static bool isDev = false;

  static Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    isDev = info.packageName.endsWith('.dev');
  }
}
