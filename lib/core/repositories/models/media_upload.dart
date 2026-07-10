// lib/data/models/media_upload.dart

import 'dart:io';
import 'dart:ui';

enum MediaType { image, video, document, audio }

class MediaUploadRequest {
  final File? file;
  final MediaType mediaType;
  final String bucket;
  final String? customPath;
  final bool upsert;
  final Map<String, String>? metadata;
  final VoidCallback? onProgress;

  MediaUploadRequest({
    required this.file,
    required this.mediaType,
    required this.bucket,
    this.customPath,
    this.upsert = false,
    this.metadata,
    this.onProgress,
  });
}

class UploadResult {
  final String publicUrl;
  final String storagePath;
  final MediaType mediaType;
  final int fileSize;
  final Map<String, String>? metadata;

  UploadResult({
    required this.publicUrl,
    required this.storagePath,
    required this.mediaType,
    required this.fileSize,
    this.metadata,
  });
}
