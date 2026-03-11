import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';

class ImageCacheManager {
  static final instance = CacheManager(
    Config(
      'ludotecaImageCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1000,
      fileService: HttpFileService(
        httpClient: IOClient(
          HttpClient()..maxConnectionsPerHost = 2,
        ),
      ),
    ),
  );
}
