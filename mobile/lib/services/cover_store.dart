import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/juego.dart';

/// Portadas en disco de la app (no temporales) para mostrarlas sin red.
class CoverStore {
  CoverStore._();

  static const dirName = 'covers';
  static const maxEdge = 400;
  static const jpegQuality = 80;
  static const timeout = Duration(seconds: 8);

  static String? _dirPath;

  static Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dirPath = dir.path;
  }

  static Future<File> fileFor(int localId) async {
    final dir = _dirPath ?? (await _ensureDir()).path;
    return File(p.join(dir, 'juego_$localId.jpg'));
  }

  static Future<Directory> _ensureDir() async {
    await init();
    return Directory(_dirPath!);
  }

  static File? existingSync({int? localId, String? storedPath}) {
    if (storedPath != null && storedPath.isNotEmpty) {
      final stored = File(storedPath);
      if (stored.existsSync()) return stored;
    }
    if (localId != null && _dirPath != null) {
      final canonical = File(p.join(_dirPath!, 'juego_$localId.jpg'));
      if (canonical.existsSync()) return canonical;
    }
    return null;
  }

  static File? existingSyncForJuego(Juego juego) => existingSync(
        localId: juego.localId,
        storedPath: juego.imageLocalPath,
      );

  static Future<File?> existingFile({int? localId, String? storedPath}) async {
    return existingSync(localId: localId, storedPath: storedPath);
  }

  static Future<File> saveBytes(int localId, Uint8List bytes) async {
    final resized = await compute(_resizeJpeg, bytes);
    final file = await fileFor(localId);
    await file.writeAsBytes(resized, flush: true);
    return file;
  }

  static Future<File> saveFile(int localId, File source) async {
    return saveBytes(localId, await source.readAsBytes());
  }

  static Future<File?> download(int localId, String url) async {
    final already = await fileFor(localId);
    if (await already.exists()) return already;

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout
      ..maxConnectionsPerHost = 4;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(response)
          .timeout(timeout);
      if (bytes.isEmpty) return null;
      return await saveBytes(localId, bytes);
    } finally {
      client.close(force: true);
    }
  }

  static bool isCanonicalPath(String path) {
    return path.contains('${Platform.pathSeparator}$dirName${Platform.pathSeparator}') ||
        path.contains('/$dirName/');
  }
}

Uint8List _resizeJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  img.Image out = decoded;
  if (decoded.width >= decoded.height) {
    if (decoded.width > CoverStore.maxEdge) {
      out = img.copyResize(decoded, width: CoverStore.maxEdge);
    }
  } else if (decoded.height > CoverStore.maxEdge) {
    out = img.copyResize(decoded, height: CoverStore.maxEdge);
  }

  return Uint8List.fromList(img.encodeJpg(out, quality: CoverStore.jpegQuality));
}
