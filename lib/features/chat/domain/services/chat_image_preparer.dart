import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of preparing an image for the private chat media pipeline.
class PreparedChatImage {
  const PreparedChatImage({
    required this.file,
    required this.mimeType,
    required this.byteSize,
  });

  final File file;

  /// Canonical MIME sniffed from the bytes, never the filename extension.
  final String mimeType;
  final int byteSize;
}

/// Raised when an image cannot be made to meet the chat upload contract. The
/// [code] is a coarse, content-free reason suitable for the error taxonomy
/// (Spec 12.3); the message is safe to log (no path, no content).
class ChatImageRejected implements Exception {
  const ChatImageRejected(this.code);
  final String code;

  @override
  String toString() => 'ChatImageRejected($code)';
}

/// Enforces the private-image upload contract (Spec 8.1) on the client, before
/// any upload intent is requested:
///
/// - accept approved MIME types only, sniffed from bytes (not the extension);
/// - decode with resource limits and reject anything undecodable / hostile;
/// - strip EXIF and location metadata;
/// - correct orientation, resize the longest useful dimension, and compress to
///   at most [maxBytes] (default 800 KB);
/// - reject files that cannot be brought under the size limit.
///
/// This is deliberately a chat-only service so it does not alter the shared
/// image picker used elsewhere in the app.
class ChatImagePreparer {
  const ChatImagePreparer();

  static const int maxBytes = 800 * 1024;
  static const int maxSourceBytes = 25 * 1024 * 1024; // pre-decode guard
  static const int maxDimension = 1600; // longest edge after resize
  static const int maxDecodePixels = 60 * 1000 * 1000; // decompression-bomb cap

  /// Approved output types. WebP is normalized to JPEG on re-encode.
  static const _approvedInputMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  Future<PreparedChatImage> prepare(String localPath) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const ChatImageRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const ChatImageRejected('media_empty');
    if (sourceLength > maxSourceBytes) {
      throw const ChatImageRejected('media_too_large');
    }

    final bytes = await source.readAsBytes();
    final sniffedMime = _sniffMime(bytes);
    if (sniffedMime == null || !_approvedInputMimes.contains(sniffedMime)) {
      throw const ChatImageRejected('media_type_unsupported');
    }

    // Decode fully to validate the file really is a decodable image and to
    // guard against decompression bombs before we ever hand it to the encoder.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const ChatImageRejected('media_decode_failed');
    if (decoded.width * decoded.height > maxDecodePixels) {
      throw const ChatImageRejected('media_dimensions_excessive');
    }

    final targetPath = await _tempTargetPath();

    // flutter_image_compress bakes in orientation, strips EXIF (keepExif:false),
    // resizes the longest edge, and re-encodes as JPEG. We step quality down
    // until the output meets the size ceiling. If the native plugin is
    // unavailable (e.g. pure Dart test host), fall through to the Dart encoder
    // below.
    try {
      for (final quality in const [82, 70, 58, 45, 32]) {
        final out = await FlutterImageCompress.compressAndGetFile(
          localPath,
          targetPath,
          quality: quality,
          minWidth: 1, // let the longest-edge cap below drive sizing
          minHeight: 1,
          keepExif: false,
          format: CompressFormat.jpeg,
        );
        if (out == null) continue;
        final outFile = File(out.path);
        final outSize = await outFile.length();
        if (outSize > 0 && outSize <= maxBytes) {
          return PreparedChatImage(
            file: outFile,
            mimeType: 'image/jpeg',
            byteSize: outSize,
          );
        }
      }
    } catch (_) {
      // Fall through to the Dart-only path.
    }

    // Last resort: hard-resize with the pure-Dart encoder, then re-check.
    final resized = _resizeLongestEdge(decoded, maxDimension);
    final jpeg = img.encodeJpg(resized, quality: 60);
    if (jpeg.lengthInBytes <= maxBytes) {
      final outFile = File(targetPath);
      await outFile.writeAsBytes(jpeg, flush: true);
      return PreparedChatImage(
        file: outFile,
        mimeType: 'image/jpeg',
        byteSize: jpeg.lengthInBytes,
      );
    }

    throw const ChatImageRejected('media_compress_failed');
  }

  img.Image _resizeLongestEdge(img.Image src, int longest) {
    final longestSide = src.width >= src.height ? src.width : src.height;
    if (longestSide <= longest) return src;
    if (src.width >= src.height) {
      return img.copyResize(src, width: longest);
    }
    return img.copyResize(src, height: longest);
  }

  Future<String> _tempTargetPath() async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      // path_provider is unavailable (e.g. a pure Dart test host); use the OS
      // temp dir. Production always has the plugin.
      dir = Directory.systemTemp;
    }
    final name = 'chat_media_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }

  /// Sniffs the MIME from the leading magic bytes. Filename extensions are not
  /// trusted (Spec 8.1: "do not trust filename extensions").
  String? _sniffMime(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
