import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/image_cache_manager.dart';
import '../models/juego.dart';

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
    final url = juego.imagenUrl;
    if (url == null) return _placeholder();

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(6),
      child: CachedNetworkImage(
        cacheManager: ImageCacheManager.instance,
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
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
        ),
        errorWidget: (context, url, error) {
          debugPrint('IMG_ERR: ${juego.nombre} | $url | $error');
          return _placeholder();
        },
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
