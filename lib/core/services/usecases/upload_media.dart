// lib/domain/usecases/upload_media.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:attune/core/repositories/models/media_upload.dart';
import 'package:attune/core/services/media/media_upload_service.dart';
import 'package:attune/core/utils/web_safe_image_picker.dart';

class UploadMedia {
  final MediaUploadService _mediaUploadService;

  UploadMedia({required MediaUploadService mediaUploadService})
    : _mediaUploadService = mediaUploadService;

  /// Generic method to upload any media with full control.
  /// Pass [existingFile] to skip picking (e.g. file already picked elsewhere).
  Future<UploadResult?> execute({
    required String bucket,
    required String userId,
    MediaType mediaType = MediaType.image,
    String? customPath,
    bool upsert = false,
    Map<String, String>? metadata,
    bool shouldPick = true,
    File? existingFile,
    bool fromCamera = false,
    bool shouldCrop = false,
    VoidCallback? onProgress,
    CropAspectRatio? cropRatio,
  }) async {
    File? fileToUpload = existingFile;

    if (shouldPick && fileToUpload == null) {
      fileToUpload = await WebSafeImagePicker.pickImage(
        fromCamera: fromCamera,
        shouldCrop: !kIsWeb && shouldCrop,
        cropRatio: cropRatio,
      );
    }

    if (fileToUpload == null) return null;

    final request = MediaUploadRequest(
      file: fileToUpload,
      mediaType: mediaType,
      bucket: bucket,
      customPath: customPath,
      upsert: upsert,
      metadata: metadata,
      onProgress: onProgress,
    );

    return await _mediaUploadService.uploadFile(
      request: request,
      userId: userId,
    );
  }
}
