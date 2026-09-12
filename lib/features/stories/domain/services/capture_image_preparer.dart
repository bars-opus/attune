import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of preparing a photo captured by [CaptureCameraScreen].
class PreparedCaptureImage {
  const PreparedCaptureImage({
    required this.file,
    required this.mimeType,
    required this.byteSize,
    required this.width,
    required this.height,
  });

  final File file;

  /// Canonical MIME sniffed from the bytes, never the filename extension.
  final String mimeType;
  final int byteSize;
  final int width;
  final int height;
}

/// Raised when a captured photo cannot be made to meet the capture
/// contract. The [code] is a coarse, content-free reason, mirroring
/// [ChatImageRejected]/[DatingImageRejected].
class CaptureImageRejected implements Exception {
  const CaptureImageRejected(this.code);
  final String code;

  @override
  String toString() => 'CaptureImageRejected($code)';
}

/// Enforces the capture-photo contract (spec §4.2/§6.2) on the client,
/// before any upload intent is requested: by default at most 2560px on
/// the long edge, JPEG, at most 5MB. Orientation is baked in and
/// EXIF/location metadata is stripped, matching [ChatImagePreparer] and
/// [DatingImagePreparer] — kept as its own class (not shared with either)
/// so the camera's own size/quality policy can diverge from chat's and
/// dating's independently, the same reasoning that keeps those two apart.
///
/// **Parameterised, not forked, for the thumbnail policy (spec §4.3).**
/// A story thumbnail needs different numbers — 400px long edge, JPEG,
/// quality 75 — but otherwise wants the exact same MIME-sniffing,
/// decompression-bomb guard, orientation handling and quality-ladder
/// fallback this class already has. Forking that into a second ~150-line
/// class would drift from this one the moment either changed. Instead the
/// size/quality knobs are constructor parameters defaulting to the
/// existing MAIN image policy (2560px / 5MB) — [maxBytes] and
/// [maxDimension] stay as static constants too, unchanged, so Task 3's
/// tests (which construct this via the bare `CaptureImagePreparer.new`
/// factory the capture screen's `imagePreparerFactory` seam expects) see
/// byte-for-byte the same behaviour. `StoryCameraScreen` constructs a
/// second instance with `CaptureImagePreparer(maxDimension: 400,
/// maxBytes: ..., qualityLadder: [75])` for its thumbnail.
class CaptureImagePreparer {
  const CaptureImagePreparer({
    int? maxDimension,
    int? maxBytes,
    List<int>? qualityLadder,
    int? fallbackQuality,
  }) : _maxDimension = maxDimension ?? defaultMaxDimension,
       _maxBytes = maxBytes ?? defaultMaxBytes,
       _qualityLadder = qualityLadder ?? const [85, 75, 65, 50, 35],
       _fallbackQuality = fallbackQuality ?? 70;

  /// MAIN image policy (spec §4.2). Left as the class's static defaults —
  /// and named `defaultMaxBytes`/`defaultMaxDimension` rather than
  /// `maxBytes`/`maxDimension` — so nothing constructing this with no
  /// arguments (Task 3's `CaptureImagePreparer.new` factory reference)
  /// changes behaviour.
  static const int defaultMaxBytes = 5 * 1024 * 1024; // 5 MB, spec §4.2
  static const int defaultMaxDimension = 2560; // longest edge, §4.2

  static const int maxSourceBytes = 25 * 1024 * 1024; // pre-decode guard
  static const int maxDecodePixels = 60 * 1000 * 1000; // decompression-bomb cap

  final int _maxDimension;
  final int _maxBytes;
  final List<int> _qualityLadder;
  final int _fallbackQuality;

  static const _approvedInputMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  Future<PreparedCaptureImage> prepare(String localPath) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const CaptureImageRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const CaptureImageRejected('media_empty');
    if (sourceLength > maxSourceBytes) {
      throw const CaptureImageRejected('media_too_large');
    }

    final bytes = await source.readAsBytes();
    final sniffedMime = _sniffMime(bytes);
    if (sniffedMime == null || !_approvedInputMimes.contains(sniffedMime)) {
      throw const CaptureImageRejected('media_type_unsupported');
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const CaptureImageRejected('media_decode_failed');
    }
    if (decoded.width * decoded.height > maxDecodePixels) {
      throw const CaptureImageRejected('media_dimensions_excessive');
    }

    final targetPath = await _tempTargetPath();

    // See ChatImagePreparer's own comment: minWidth/minHeight are a
    // TARGET the plugin scales toward, not a floor, so the real
    // longest-edge target is derived from the decoded source first.
    final targetDimensions = _longestEdgeTarget(
      decoded.width,
      decoded.height,
      _maxDimension,
    );

    try {
      for (final quality in _qualityLadder) {
        final out = await FlutterImageCompress.compressAndGetFile(
          localPath,
          targetPath,
          quality: quality,
          minWidth: targetDimensions.width,
          minHeight: targetDimensions.height,
          keepExif: false,
          format: CompressFormat.jpeg,
        );
        if (out == null) continue;
        final outFile = File(out.path);
        final outSize = await outFile.length();
        if (outSize > 0 && outSize <= _maxBytes) {
          final outDecoded = img.decodeImage(await outFile.readAsBytes());
          return PreparedCaptureImage(
            file: outFile,
            mimeType: 'image/jpeg',
            byteSize: outSize,
            width: outDecoded?.width ?? targetDimensions.width,
            height: outDecoded?.height ?? targetDimensions.height,
          );
        }
      }
    } catch (_) {
      // Fall through to the Dart-only path (e.g. no platform channel on
      // a test host).
    }

    // Last resort: hard-resize with the pure-Dart encoder, then re-check.
    final resized = _resizeLongestEdge(decoded, _maxDimension);
    final jpeg = img.encodeJpg(resized, quality: _fallbackQuality);
    if (jpeg.lengthInBytes <= _maxBytes) {
      final outFile = File(targetPath);
      await outFile.writeAsBytes(jpeg, flush: true);
      return PreparedCaptureImage(
        file: outFile,
        mimeType: 'image/jpeg',
        byteSize: jpeg.lengthInBytes,
        width: resized.width,
        height: resized.height,
      );
    }

    throw const CaptureImageRejected('media_compress_failed');
  }

  ({int width, int height}) _longestEdgeTarget(
    int sourceWidth,
    int sourceHeight,
    int longest,
  ) {
    final longestSide = sourceWidth >= sourceHeight ? sourceWidth : sourceHeight;
    if (longestSide <= longest) {
      return (width: sourceWidth, height: sourceHeight);
    }
    final scale = longest / longestSide;
    return (
      width: (sourceWidth * scale).round(),
      height: (sourceHeight * scale).round(),
    );
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
    final name = 'capture_image_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }

  /// Sniffs the MIME from the leading magic bytes. Filename extensions are
  /// not trusted.
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
