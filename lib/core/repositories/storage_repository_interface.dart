// lib/domain/repositories/storage_repository_interface.dart

import 'dart:io';

abstract class StorageRepository {
  /// Upload a file to a bucket and return the public URL
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
    bool upsert,
    bool bustCache,
  });

  /// Delete a file from storage
  Future<void> deleteFile({required String bucket, required String path});

  /// Get public URL for a file
  String getPublicUrl(String bucket, String path);
}
