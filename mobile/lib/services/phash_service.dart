import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Servicio para calcular y comparar perceptual hashes (pHash) de portadas.
///
/// Estrategia simple "average hash" (aHash) sobre 8x8 (64 bits). M\u00e1s estable
/// que dHash en portadas, suficientemente discriminativo para conjuntos
/// peque\u00f1os (los juegos de la ludoteca local).
class PhashService {
  /// Computa el aHash 64-bit de la imagen indicada. Devuelve una cadena hex
  /// (16 chars). Devuelve null si la imagen no se puede decodificar.
  static Future<String?> hashFile(File file) async {
    final bytes = await file.readAsBytes();
    return compute(_hashBytes, bytes);
  }

  static Future<String?> hashBytes(Uint8List bytes) async {
    return compute(_hashBytes, bytes);
  }

  static int hammingDistanceHex(String a, String b) {
    if (a.length != b.length) return 64;
    var dist = 0;
    for (var i = 0; i < a.length; i++) {
      final ax = int.parse(a[i], radix: 16);
      final bx = int.parse(b[i], radix: 16);
      dist += _bitCount(ax ^ bx);
    }
    return dist;
  }

  static int _bitCount(int v) {
    var n = v;
    var count = 0;
    while (n > 0) {
      count += n & 1;
      n >>= 1;
    }
    return count;
  }
}

String? _hashBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // gris + redimensionar a 8x8
  final small = img.copyResize(decoded, width: 8, height: 8);
  final gray = img.grayscale(small);
  var sum = 0;
  final values = List<int>.generate(64, (i) {
    final pixel = gray.getPixel(i % 8, i ~/ 8);
    final lum = pixel.r.toInt();
    sum += lum;
    return lum;
  });
  final avg = sum ~/ 64;
  var bits = 0;
  for (var i = 0; i < 64; i++) {
    if (values[i] >= avg) bits |= 1 << i;
  }
  // a hex 16 chars
  final buf = StringBuffer();
  for (var i = 0; i < 16; i++) {
    final nibble = (bits >> (i * 4)) & 0xF;
    buf.write(nibble.toRadixString(16));
  }
  return buf.toString();
}
