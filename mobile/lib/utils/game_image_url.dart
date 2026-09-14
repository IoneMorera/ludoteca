import '../config/api_config.dart';

/// Resuelve portadas de la colección hacia almacenamiento propio
/// (`/storage/juegos/bgg_{id}.ext`) y evita pedir el CDN de BGG
/// (`cf.geekdo-images.com`), bloqueado en España durante partidos de LaLiga.
class GameImageUrl {
  static final _bggCdn = RegExp(
    r'(?:^https?:)?//(?:[^/]*\.)?(?:geekdo-images\.com|geekdo\.com)/',
    caseSensitive: false,
  );

  static const _allowedExt = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

  static bool isBggCdn(String? url) {
    if (url == null || url.isEmpty) return false;
    return _bggCdn.hasMatch(url);
  }

  static String storagePath({required int bggId, String? sourceUrl}) {
    return '/storage/juegos/bgg_$bggId.${extensionOf(sourceUrl)}';
  }

  static String extensionOf(String? sourceUrl) {
    if (sourceUrl == null || sourceUrl.isEmpty) return 'jpg';
    final uri = Uri.tryParse(sourceUrl);
    final path = uri?.path ?? sourceUrl;
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < slash) return 'jpg';
    var ext = path.substring(dot + 1).toLowerCase();
    final query = ext.indexOf('?');
    if (query >= 0) ext = ext.substring(0, query);
    if (!_allowedExt.contains(ext)) return 'jpg';
    return ext == 'jpeg' ? 'jpg' : ext;
  }

  /// Valor a persistir en `juegos.imagen`. Las URLs de BGG se sustituyen
  /// por la ruta local; si no hay `bggId` se descartan.
  static String? canonicalize(String? imagen, int? bggId) {
    if (imagen == null || imagen.isEmpty) return imagen;
    if (!isBggCdn(imagen)) return imagen;
    if (bggId == null) return null;
    return storagePath(bggId: bggId, sourceUrl: imagen);
  }

  /// URL absoluta para widgets. Nunca devuelve el CDN de BGG.
  static String? resolve(String? imagen, int? bggId) {
    final value = canonicalize(imagen, bggId);
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      if (isBggCdn(value)) return null;
      return value;
    }
    final path = value.startsWith('/') ? value : '/$value';
    return '${ApiConfig.storageUrl}$path';
  }
}
