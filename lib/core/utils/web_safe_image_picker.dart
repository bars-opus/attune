import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';

class WebSafeImagePicker {
  /// Pick an image (works on both web and mobile)
  static Future<File?> pickImage({
    bool fromCamera = false,
    bool shouldCrop = false,
    CropAspectRatio? cropRatio, // Added this parameter
  }) async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );

    if (pickedFile == null) return null;

    // On web, return as is (can't crop)
    if (kIsWeb) {
      return File(pickedFile.path);
    }

    // On mobile, crop if requested
    if (shouldCrop) {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatio:
            cropRatio ??
            const CropAspectRatio(ratioX: 1, ratioY: 1), // Added aspectRatio
      );

      if (croppedFile != null) {
        return File(croppedFile.path);
      }
    }

    return File(pickedFile.path);
  }
}
