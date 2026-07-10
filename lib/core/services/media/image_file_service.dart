// lib/core/services/media/image_file_service.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageFileService {
  /// Get permanent directory for shop images
  static Future<Directory> getShopImagesDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${directory.path}/shop_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    return imageDir;
  }

  /// Save a file to permanent storage
  static Future<File> saveFileToPermanent(File sourceFile) async {
    final imageDir = await getShopImagesDirectory();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final newPath = path.join(imageDir.path, fileName);
    return await sourceFile.copy(newPath);
  }

  /// Check if a file exists and is accessible
  static Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get all shop images (for cleanup)
  static Future<List<File>> getAllShopImages() async {
    final imageDir = await getShopImagesDirectory();
    final List<File> images = [];

    if (await imageDir.exists()) {
      await for (var entity in imageDir.list()) {
        if (entity is File &&
            (entity.path.endsWith('.jpg') || entity.path.endsWith('.png'))) {
          images.add(entity);
        }
      }
    }
    return images;
  }

  /// Delete old images (cleanup)
  static Future<void> deleteOldImages({int olderThanDays = 7}) async {
    final images = await getAllShopImages();
    final now = DateTime.now();

    for (var image in images) {
      final stat = await image.stat();
      final modified = stat.modified;
      final daysOld = now.difference(modified).inDays;

      if (daysOld > olderThanDays) {
        await image.delete();
      }
    }
  }
}
