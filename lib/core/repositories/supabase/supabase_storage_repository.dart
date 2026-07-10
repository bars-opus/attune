// lib/data/repositories/supabase/supabase_storage_repository.dart

import 'dart:io';
import 'package:attune/core/repositories/storage_repository_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mime/mime.dart';

class SupabaseStorageRepository implements StorageRepository {
  final SupabaseClient _client;

  SupabaseStorageRepository(this._client);

  @override
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required File file,
    String? contentType,
    bool upsert = true,
    bool bustCache = true,
  }) async {
    try {
      final mimeType = contentType ?? lookupMimeType(file.path) ?? 'image/jpeg';

      final response = await _client.storage
          .from(bucket)
          .upload(
            path,
            file,
            fileOptions: FileOptions(contentType: mimeType, upsert: upsert),
          );

      // response is the path string on success
      return getPublicUrl(bucket, path);
    } on StorageException catch (e) {
      // Map specific error codes to user-friendly messages
      if (e.message.contains('Duplicate')) {
        throw Exception('A file with this name already exists');
      } else if (e.message.contains('permission')) {
        throw Exception('You don\'t have permission to upload files');
      } else {
        throw Exception('Upload failed: ${e.message}');
      }
    }
  }

  @override
  Future<void> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } on StorageException catch (e) {
      throw Exception('Delete failed: ${e.message}');
    } catch (e) {
      throw Exception('Delete failed: $e');
    }
  }

  @override
  String getPublicUrl(String bucket, String path, {bool bustCache = true}) {
    final baseUrl = _client.storage.from(bucket).getPublicUrl(path);
    if (bustCache) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return '$baseUrl?t=$timestamp';
    }
    return baseUrl;
  }
}
