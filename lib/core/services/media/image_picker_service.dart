// lib/core/services/image_picker_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from gallery or camera.
  /// [crop] — show the crop UI after picking.
  /// [lockAspectRatio] — when true the crop tool locks to [cropRatio] (default
  ///   1:1 square). Pass false for freeform crop (e.g. chat images).
  Future<File?> pickImage({
    required bool fromCamera,
    bool crop = false,
    CropAspectRatio? cropRatio,
    bool lockAspectRatio = true,
  }) async {
    try {
      // On web, we can't crop or compress the same way
      if (kIsWeb) {
        final XFile? pickedFile = await _picker.pickImage(
          source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        );

        if (pickedFile == null) return null;

        // For web, just return the file without cropping/compressing
        // Note: On web, File is not a real file path, but it works for upload
        return File(pickedFile.path);
      }

      // Mobile: full experience
      final XFile? pickedFile = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return null;

      // Copy to permanent directory
      final permanentFile = await _copyToPermanentDirectory(
        File(pickedFile.path),
      );

      // Crop if requested.
      //
      // A null result here means the user CANCELLED the cropper, which is
      // a cancellation of the whole pick — not "keep the original". Every
      // caller treats a non-null return as "the user confirmed a photo"
      // and uploads it immediately, so falling through to return the
      // uncropped original silently saved a photo the user had just
      // backed out of. (_cropImage returns the original, not null, when
      // the cropper itself ERRORS — that stays a usable fallback.)
      if (crop) {
        final cropped = await _cropImage(
          permanentFile,
          cropRatio: cropRatio,
          lockAspectRatio: lockAspectRatio,
        );
        if (cropped == null) return null;
        return await _compressImage(cropped);
      }

      // Always compress
      return await _compressImage(permanentFile);
    } catch (e) {
      debugPrint('Failed to pick image: $e');
      return null;
    }
  }

  /// Copy file to permanent app documents directory (Mobile only)
  Future<File> _copyToPermanentDirectory(File sourceFile) async {
    try {
      if (kIsWeb) return sourceFile;

      final directory = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${directory.path}/shop_images');
      if (!await imageDir.exists()) {
        await imageDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = path.join(imageDir.path, fileName);

      return await sourceFile.copy(newPath);
    } catch (e) {
      return sourceFile;
    }
  }

  /// Pick a video from gallery or camera
  Future<File?> pickVideo({required bool fromCamera}) async {
    try {
      // Videos not supported on web in same way
      if (kIsWeb) {
        debugPrint('Video picking not fully supported on web');
        return null;
      }

      final XFile? pickedFile = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (pickedFile == null) return null;
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('Failed to pick video: $e');
      return null;
    }
  }

  /// Crop image (Mobile only).
  /// [lockAspectRatio] false → freeform; true → locked to [cropRatio] (default 1:1).
  Future<File?> _cropImage(
    File imageFile, {
    CropAspectRatio? cropRatio,
    bool lockAspectRatio = true,
  }) async {
    // Don't crop on web
    if (kIsWeb) return imageFile;

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        aspectRatio:
            lockAspectRatio
                ? (cropRatio ?? const CropAspectRatio(ratioX: 1, ratioY: 1))
                : null,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: Colors.deepOrange,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: lockAspectRatio,
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioLockEnabled: lockAspectRatio,
          ),
        ],
      );

      if (croppedFile == null) return null;
      return File(croppedFile.path);
    } catch (e) {
      debugPrint('Failed to crop image: $e');
      return imageFile;
    }
  }

  /// Compress image (Mobile only)
  Future<File> _compressImage(File file) async {
    // Don't compress on web
    if (kIsWeb) return file;

    try {
      final dir = await getTemporaryDirectory();
      final targetPath = path.join(
        dir.path,
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 80,
        minWidth: 500,
        minHeight: 500,
      );

      if (result == null) return file;
      return File(result.path);
    } catch (e) {
      debugPrint('Failed to compress image: $e');
      return file;
    }
  }

  /// Delete file
  Future<void> deleteFile(File file) async {
    if (kIsWeb) return;

    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // ignore cleanup errors
    }
  }
}
