import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/juego.dart';
import '../services/cover_store.dart';
import '../services/image_cache_manager.dart';

class GameImage extends StatelessWidget {
  final Juego juego;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const GameImage({
    super.key,
    required this.juego,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final local = CoverStore.existingSyncForJuego(juego);
    if (local != null) {
      return _clipped(
        Image.file(
          local,
          width: width,
          height: height,
          fit: BoxFit.cover,
          cacheWidth: (width * 2).toInt(),
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      );
    }

    final url = juego.imagenUrl;
    if (url == null) return _placeholder();

    return _clipped(
      CachedNetworkImage(
        cacheManager: ImageCacheManager.instance,
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: (width * 2).toInt(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, url) => _loader(),
        errorWidget: (context, url, error) {
          debugPrint('IMG_ERR: ${juego.nombre} | $url | $error');
          final fallback = CoverStore.existingSyncForJuego(juego);
          if (fallback != null) {
            return Image.file(
              fallback,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(),
            );
          }
          return _placeholder();
        },
      ),
    );
  }

  Widget _clipped(Widget child) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(6),
      child: child,
    );
  }

  Widget _loader() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: borderRadius ?? BorderRadius.circular(6),
      ),
      child: const Icon(Icons.casino, size: 20, color: Colors.grey),
    );
  }
}
