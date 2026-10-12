import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Storage and edge-function calls Planning makes besides its RPCs, behind
/// one seam so tests fake them.
abstract class PlanningMediaGateway {
  /// Uploads a prepared JPEG to the private planning-media bucket. Storage
  /// policies admit only the couple's own `{relationship}/{entry}/` folder.
  Future<void> uploadJpeg(String path, Uint8List bytes);

  /// A short-lived URL for showing a stored photo.
  Future<String> signedUrl(String path);

  /// Asks the server to fetch a Link block's preview. Best effort: the
  /// block is already saved and shows a plain card until a preview lands.
  Future<void> requestLinkPreview(String blockId);
}

class SupabasePlanningMediaGateway implements PlanningMediaGateway {
  const SupabasePlanningMediaGateway(this._supabase);

  final SupabaseClient _supabase;
  static const bucket = 'planning-media';
  static const signedUrlTtl = Duration(hours: 1);

  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) => _supabase.storage
      .from(bucket)
      .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false))
      .timeout(const Duration(seconds: 60));

  @override
  Future<String> signedUrl(String path) => _supabase.storage
      .from(bucket)
      .createSignedUrl(path, signedUrlTtl.inSeconds)
      .timeout(const Duration(seconds: 10));

  @override
  Future<void> requestLinkPreview(String blockId) => _supabase.functions
      .invoke('planning-link-preview', body: {'block_id': blockId})
      .timeout(const Duration(seconds: 10));
}
