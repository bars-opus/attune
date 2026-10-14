import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The journal's private photos, behind one seam so tests fake them.
abstract class JournalMediaGateway {
  /// Uploads a prepared JPEG. Storage policies admit only the owner's own
  /// `{user}/{entry}/` folder.
  Future<void> uploadJpeg(String path, Uint8List bytes);

  /// A short-lived URL for showing a stored photo.
  Future<String> signedUrl(String path);
}

class SupabaseJournalMediaGateway implements JournalMediaGateway {
  const SupabaseJournalMediaGateway(this._supabase);
  final SupabaseClient _supabase;
  static const bucket = 'journal-media';
  static const signedUrlTtl = Duration(minutes: 10);

  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) => _supabase.storage
      .from(bucket)
      .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false))
      .timeout(const Duration(seconds: 60));

  @override
  Future<String> signedUrl(String path) =>
      _supabase.storage.from(bucket).createSignedUrl(path, signedUrlTtl.inSeconds).timeout(const Duration(seconds: 10));
}
