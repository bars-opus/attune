// lib/core/services/media_upload_service.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:attune/core/repositories/models/media_upload.dart';
import 'package:attune/core/repositories/storage_repository_interface.dart';
import 'package:attune/core/services/media/image_picker_service.dart';

class MediaUploadService {
  final StorageRepository _storageRepo;
  final ImagePickerService _imagePickerService;

  MediaUploadService({
    required StorageRepository storageRepo,
    required ImagePickerService imagePickerService,
  }) : _storageRepo = storageRepo,
       _imagePickerService = imagePickerService;

  Future<UploadResult?> pickAndUpload({
    required MediaUploadRequest request,
    required bool fromCamera,
    required String userId,
    bool shouldCrop = false,
    CropAspectRatio? cropRatio,
  }) async {
    try {
      // 1. Pick file if not provided
      File? file = request.file;

      if (file == null) {
        if (request.mediaType == MediaType.image) {
          file = await _imagePickerService.pickImage(
            fromCamera: fromCamera,
            crop: shouldCrop && !kIsWeb, // No crop on web
            cropRatio: cropRatio,
          );
        } else if (request.mediaType == MediaType.video) {
          file = await _imagePickerService.pickVideo(fromCamera: fromCamera);
        }
      }

      if (file == null) return null;

      // 2. Generate storage path with userId
      final path = request.customPath ?? _generatePath(request, userId);

      // 3. Upload to storage
      final publicUrl = await _storageRepo.uploadFile(
        bucket: request.bucket,
        path: path,
        file: file,
        upsert: request.upsert,
      );

      // 4. Add cache buster for images (skip on web to avoid double ?)
      final finalUrl =
          (request.mediaType == MediaType.image && !kIsWeb)
              ? '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}'
              : publicUrl;

      // 5. Return result (handle file size safely on web)
      int fileSize = 0;
      if (!kIsWeb) {
        try {
          fileSize = await file.length();
        } catch (_) {}
      }

      return UploadResult(
        publicUrl: finalUrl,
        storagePath: path,
        mediaType: request.mediaType,
        fileSize: fileSize,
        metadata: request.metadata,
      );
    } catch (e) {
      debugPrint('MediaUploadService.pickAndUpload error: $e');
      return null;
    }
  }

  Future<UploadResult?> uploadFile({
    required MediaUploadRequest request,
    required String userId,
  }) async {
    try {
      if (request.file == null) throw Exception('File is required');

      final path = request.customPath ?? _generatePath(request, userId);

      final publicUrl = await _storageRepo.uploadFile(
        bucket: request.bucket,
        path: path,
        file: request.file!,
        upsert: request.upsert,
      );

      // Skip cache buster on web
      final finalUrl =
          (request.mediaType == MediaType.image && !kIsWeb)
              ? '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}'
              : publicUrl;

      int fileSize = 0;
      if (!kIsWeb) {
        try {
          fileSize = await request.file!.length();
        } catch (_) {}
      }

      return UploadResult(
        publicUrl: finalUrl,
        storagePath: path,
        mediaType: request.mediaType,
        fileSize: fileSize,
        metadata: request.metadata,
      );
    } catch (e) {
      debugPrint('MediaUploadService.uploadFile error: $e');
      return null;
    }
  }

  String _generatePath(MediaUploadRequest request, String userId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    switch (request.mediaType) {
      case MediaType.image:
        return '$userId/images/${request.metadata?['name'] ?? 'image_$timestamp.jpg'}';
      case MediaType.video:
        return '$userId/videos/video_$timestamp.mp4';
      case MediaType.document:
        return '$userId/documents/doc_$timestamp.pdf';
      case MediaType.audio:
        return '$userId/audio/audio_$timestamp.m4a';
    }
  }
}
