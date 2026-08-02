import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of preparing an image for the private dating-photo upload pipeline.
class PreparedDatingImage {
  const PreparedDatingImage({
    required this.file,
    required this.mimeType,
    required this.byteSize,
  });

  final File file;
  final String mimeType;
  final int byteSize;
}

/// Raised when an image cannot be made to meet the dating-photo upload
/// contract. The [code] is a coarse, content-free reason.
class DatingImageRejected implements Exception {
  const DatingImageRejected(this.code);
  final String code;

  @override
  String toString() => 'DatingImageRejected($code)';
}

/// Enforces the private-image upload contract on the client, before any
/// upload intent is requested — mirrors ChatImagePreparer
/// (lib/features/chat/domain/services/chat_image_preparer.dart) with a
/// higher output size ceiling appropriate for a profile photo rather than a
/// chat thumbnail. Kept as a separate class (not shared with chat) so the
/// two features' size/quality policies can diverge independently.
class DatingImagePreparer {
  const DatingImagePreparer();

  static const int maxBytes = 1536 * 1024; // 1.5 MB
  static const int maxSourceBytes = 25 * 1024 * 1024;
  static const int maxDimension = 2000;
  static const int maxDecodePixels = 60 * 1000 * 1000;

  static const _approvedInputMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  Future<PreparedDatingImage> prepare(String localPath) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const DatingImageRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const DatingImageRejected('media_empty');
    if (sourceLength > maxSourceBytes) {
      throw const DatingImageRejected('media_too_large');
    }

    final bytes = await source.readAsBytes();
    final sniffedMime = _sniffMime(bytes);
    if (sniffedMime == null || !_approvedInputMimes.contains(sniffedMime)) {
      throw const DatingImageRejected('media_type_unsupported');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const DatingImageRejected('media_decode_failed');
    if (decoded.width * decoded.height > maxDecodePixels) {
      throw const DatingImageRejected('media_dimensions_excessive');
    }

    final targetPath = await _tempTargetPath();

    try {
      for (final quality in const [85, 75, 65, 50, 35]) {
        final out = await FlutterImageCompress.compressAndGetFile(
          localPath,
          targetPath,
          quality: quality,
          minWidth: 1,
          minHeight: 1,
          keepExif: false,
          format: CompressFormat.jpeg,
        );
        if (out == null) continue;
        final outFile = File(out.path);
        final outSize = await outFile.length();
        if (outSize > 0 && outSize <= maxBytes) {
          return PreparedDatingImage(
            file: outFile,
            mimeType: 'image/jpeg',
            byteSize: outSize,
          );
        }
      }
    } catch (_) {
      // Fall through to the Dart-only path.
    }

    final resized = _resizeLongestEdge(decoded, maxDimension);
    final jpeg = img.encodeJpg(resized, quality: 65);
    if (jpeg.lengthInBytes <= maxBytes) {
      final outFile = File(targetPath);
      await outFile.writeAsBytes(jpeg, flush: true);
      return PreparedDatingImage(
        file: outFile,
        mimeType: 'image/jpeg',
        byteSize: jpeg.lengthInBytes,
      );
    }

    throw const DatingImageRejected('media_compress_failed');
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
      dir = Directory.systemTemp;
    }
    final name = 'dating_photo_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }

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
