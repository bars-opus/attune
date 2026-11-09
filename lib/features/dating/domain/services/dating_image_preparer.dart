import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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

/// Spec 2 W3c (R-23): one deterministic path: upright, at most 1600 px on
/// the long side, EXIF (GPS included) cleared, JPEG at quality 80, stepping
/// down only to fit maxBytes. Runs in a worker isolate (Isolate.run; fix
/// round 1, I-3): no platform channels, no `this`. The header is read first,
/// so an excessive image is refused before its pixels are decoded. Answers
/// the JPEG, or the rejection code.
({Uint8List? jpeg, String? error}) _encodeDatingJpeg(Uint8List bytes) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info != null &&
        info.width * info.height > DatingImagePreparer.maxDecodePixels) {
      return (jpeg: null, error: 'media_dimensions_excessive');
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return (jpeg: null, error: 'media_decode_failed');
    if (decoded.width * decoded.height > DatingImagePreparer.maxDecodePixels) {
      return (jpeg: null, error: 'media_dimensions_excessive');
    }
    final upright = img.bakeOrientation(decoded);
    final resized = const DatingImagePreparer()._resizeLongestEdge(
      upright,
      DatingImagePreparer.maxDimension,
    );
    resized.exif = img.ExifData();
    for (final q in const [DatingImagePreparer.quality, 70, 60, 50]) {
      final jpeg = img.encodeJpg(resized, quality: q);
      if (jpeg.lengthInBytes <= DatingImagePreparer.maxBytes) {
        return (jpeg: jpeg, error: null);
      }
    }
    return (jpeg: null, error: 'media_compress_failed');
  } catch (_) {
    // package:image throws (RangeError) on a damaged file.
    return (jpeg: null, error: 'media_decode_failed');
  }
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
  static const int maxDimension = 1600;
  static const int quality = 80;
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

    // Spec 2 W3c Task 9 fix round 1 (I-3): the decode, resize and encode
    // run in a worker isolate (Isolate.run), as ChatImagePreparer's; the
    // temp name and the file write stay here.
    final encoded = await Isolate.run(() => _encodeDatingJpeg(bytes));
    final jpeg = encoded.jpeg;
    if (jpeg == null) throw DatingImageRejected(encoded.error!);

    final targetPath = await _tempTargetPath();
    final outFile = File(targetPath);
    await outFile.writeAsBytes(jpeg, flush: true);
    return PreparedDatingImage(
      file: outFile,
      mimeType: 'image/jpeg',
      byteSize: jpeg.lengthInBytes,
    );
  }

  /// Spec 2 W3 final fix (M-13): a crash between the write and the
  /// delete can leave a prepared photo (`p_<micros>.jpg`, a neutral name)
  /// in the temp folder until the OS clears it. D9 sweeps them when it
  /// opens: only that name, and only from before [before] (now), so a
  /// photo being prepared right now is never touched. Never throws; a
  /// folder that can't be read sweeps nothing.
  Future<int> sweepLeftovers({Directory? dir, DateTime? before}) async {
    final cutoff = (before ?? DateTime.now()).microsecondsSinceEpoch;
    var swept = 0;
    try {
      final folder = dir ?? await getTemporaryDirectory();
      await for (final entry in folder.list(followLinks: false)) {
        final m = _leftoverName.firstMatch(p.basename(entry.path));
        if (entry is! File || m == null) continue;
        if ((int.tryParse(m.group(1)!) ?? cutoff) >= cutoff) continue;
        try {
          await entry.delete();
          swept++;
        } catch (_) {
          // Gone already, or not ours to delete: nothing to sweep.
        }
      }
    } catch (_) {
      // No temp folder here (or unreadable): nothing to sweep.
    }
    return swept;
  }

  static final _leftoverName = RegExp(r'^p_(\d+)\.jpg$');

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
    final name = 'p_${DateTime.now().microsecondsSinceEpoch}.jpg';
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
