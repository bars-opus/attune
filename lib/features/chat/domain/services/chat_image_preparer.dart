import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
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

/// What the worker-isolate probe learns from the container, without decoding
/// a pixel: stored (unrotated) dimensions and the EXIF orientation (1–8).
typedef ChatImageProbe = ({int width, int height, int orientation});

/// Header probe. Runs in a worker isolate (Isolate.run): the SOF/IHDR/VP8
/// read and the structural walk below scan the whole file in Dart, which is
/// tens of milliseconds for a 12 MP original — too long for the UI isolate.
/// Null when the file is not a complete, readable image (Spec 8.1: reject
/// anything undecodable — a truncated JPEG with a valid header included).
ChatImageProbe? _probeSource(Uint8List bytes, String mime) {
  try {
    if (!chatImageStructurallyComplete(bytes, mime)) return null;
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) return null;
    final orientation =
        mime == 'image/jpeg'
            ? img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1
            : 1;
    return (
      width: info.width,
      height: info.height,
      orientation: orientation >= 1 && orientation <= 8 ? orientation : 1,
    );
  } catch (_) {
    return null;
  }
}

/// Whether [bytes] are a complete file of [mime]: a JPEG reaches its EOI
/// marker through well-formed segments and scans, a PNG chains its chunks to
/// IEND, a WebP holds the bytes its RIFF header promises. A pick cut short
/// (an interrupted copy, a half-synced cloud photo) still has a readable
/// header; decoders fill the missing rows with grey instead of failing.
@visibleForTesting
bool chatImageStructurallyComplete(Uint8List b, String mime) {
  final n = b.length;
  switch (mime) {
    case 'image/jpeg':
      var i = 2; // after SOI
      while (i + 1 < n) {
        if (b[i] != 0xFF) {
          // Extraneous bytes before a marker: libjpeg warns and skips to
          // the next 0xFF, so do the same (EOI is still required below).
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker == 0xFF) {
          i++; // fill byte
          continue;
        }
        if (marker == 0xD9) return true; // EOI
        if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
          i += 2; // standalone marker
          continue;
        }
        if (i + 3 >= n) return false;
        final length = (b[i + 2] << 8) | b[i + 3];
        if (length < 2) return false;
        i += 2 + length;
        if (i > n) return false;
        if (marker == 0xDA) {
          // Entropy-coded scan: runs until the next real marker. 0xFF00 is a
          // stuffed byte and 0xFFD0–D7 are restarts; anything else ends it.
          while (i + 1 < n) {
            if (b[i] == 0xFF) {
              final next = b[i + 1];
              if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
                i += 2;
                continue;
              }
              break;
            }
            i++;
          }
        }
      }
      return false;
    case 'image/png':
      var i = 8; // after the signature
      while (i + 8 <= n) {
        final length =
            (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
        final isEnd =
            b[i + 4] == 0x49 && // I
            b[i + 5] == 0x45 && // E
            b[i + 6] == 0x4E && // N
            b[i + 7] == 0x44; // D
        if (length < 0 || i + 12 + length > n) return false;
        if (isEnd) return true;
        i += 12 + length;
      }
      return false;
    case 'image/webp':
      if (n < 12) return false;
      final riffSize = b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24);
      return riffSize >= 4 && riffSize + 8 <= n;
    default:
      return false;
  }
}

/// The minWidth/minHeight to hand flutter_image_compress so the output's
/// long edge is at most [longest] whatever the EXIF orientation.
///
/// Both plugins size against the DISPLAY orientation: iOS through UIImage's
/// oriented size, Android by swapping minWidth/minHeight when the EXIF
/// rotation is 90/270 (orientations 5–8) before scaling the stored bitmap.
/// A target computed from the stored dimensions therefore came out with
/// its SHORT edge at [longest] for a sideways photo (4000x3000 rotated →
/// 1600x2133). The short edge is floored so the long-edge ratio is always
/// the binding one in both plugins' min/max scale choice.
@visibleForTesting
({int width, int height}) chatCompressTarget({
  required int storedWidth,
  required int storedHeight,
  required int orientation,
  int longest = ChatImagePreparer.maxDimension,
}) {
  final swapped = orientation >= 5 && orientation <= 8;
  return ChatImagePreparer._longestEdgeTarget(
    swapped ? storedHeight : storedWidth,
    swapped ? storedWidth : storedHeight,
    longest,
  );
}

/// Android BitmapFactory `inSampleSize` for that target: the largest power
/// of two whose sampled decode still covers the target in the stored
/// orientation, so each quality step decodes a quarter (or less) of a
/// 12 MP original's pixels instead of all of them. iOS ignores it.
@visibleForTesting
int chatCompressSampleSize({
  required int storedWidth,
  required int storedHeight,
  required int orientation,
  int longest = ChatImagePreparer.maxDimension,
}) {
  final target = chatCompressTarget(
    storedWidth: storedWidth,
    storedHeight: storedHeight,
    orientation: orientation,
    longest: longest,
  );
  final swapped = orientation >= 5 && orientation <= 8;
  final targetW = swapped ? target.height : target.width;
  final targetH = swapped ? target.width : target.height;
  var sample = 1;
  while (storedWidth ~/ (sample * 2) >= targetW &&
      storedHeight ~/ (sample * 2) >= targetH) {
    sample *= 2;
  }
  return sample;
}

/// Pure-Dart fallback encoder. Runs in a worker isolate (Isolate.run): no
/// platform channels, no `this`. Null when the bytes do not decode.
Uint8List? _dartFallbackJpeg(Uint8List bytes, int longest) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null; // package:image throws (RangeError) on a damaged scan
  }
  if (decoded == null) return null;
  final resized = const ChatImagePreparer()._resizeLongestEdge(
    img.bakeOrientation(decoded),
    longest,
  );
  resized.exif = img.ExifData();
  return img.encodeJpg(resized, quality: 60);
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

  /// Whether [header] (a file's leading bytes; 12 are enough) is a type
  /// [prepare] accepts. ChatImagePicker converts anything else (an Android
  /// HEIF original) to JPEG before it gets here.
  static bool acceptsHeader(Uint8List header) =>
      _approvedInputMimes.contains(_sniffMime(header));

  /// [outputDirectory] is where the upload file is written (created if
  /// missing). Chat passes a durable Application Support folder so a photo
  /// queued offline survives an OS temp purge; other callers that upload
  /// at once keep the default, the OS temp dir.
  Future<PreparedChatImage> prepare(
    String localPath, {
    Future<Directory> Function()? outputDirectory,
  }) async {
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

    // Header-only probe (no pixel decode), in a worker isolate: full-
    // resolution originals reach this code now (chat review #20), and
    // package:image decoding a 12 MP JPEG on the UI isolate froze the app
    // for seconds per photo. SOF/IHDR/VP8 headers give the dimensions for
    // the bomb guard and the resize target, EXIF the orientation; a
    // structural walk rejects a file cut short. The native plugin decodes
    // natively (sampled) below and the pure-Dart fallback decodes in a
    // worker isolate.
    final info = await Isolate.run(() => _probeSource(bytes, sniffedMime));
    if (info == null) throw const ChatImageRejected('media_decode_failed');
    if (info.width * info.height > maxDecodePixels) {
      throw const ChatImageRejected('media_dimensions_excessive');
    }

    final targetPath = await _targetPath(outputDirectory);

    // flutter_image_compress's minWidth/minHeight are a TARGET size the
    // plugin scales toward (not a floor) — it resizes the image as close to
    // these dimensions as it can while preserving aspect ratio. Passing 1x1
    // here previously made every image collapse to a near-1x1 output. Derive
    // the real longest-edge-maxDimension target from the header-probed
    // source, in display orientation (see chatCompressTarget), so the
    // plugin resizes correctly, mirroring _resizeLongestEdge's logic used by
    // the Dart fallback path below.
    final targetDimensions = chatCompressTarget(
      storedWidth: info.width,
      storedHeight: info.height,
      orientation: info.orientation,
    );
    // One sampled decode size for every quality step (Android): see
    // chatCompressSampleSize. The ladder rarely passes its first step — a
    // 1600 px JPEG at q82 is typically 250–600 KB — so this, not a reused
    // intermediate (a lossy re-encode of a re-encode), is the saving.
    final sampleSize = chatCompressSampleSize(
      storedWidth: info.width,
      storedHeight: info.height,
      orientation: info.orientation,
    );

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
          minWidth: targetDimensions.width,
          minHeight: targetDimensions.height,
          inSampleSize: sampleSize,
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

    // Last resort: the pure-Dart path, in a worker isolate so the UI keeps
    // drawing. It bakes the EXIF orientation first (an untouched Android
    // original carries it there; the native path does the same), resizes,
    // and clears EXIF — the encoder would otherwise copy it, GPS included.
    // Every way out from here but success removes the target: the native
    // ladder may have left an oversize file there, and in chat's durable
    // folder nothing else would ever delete it.
    try {
      final jpeg = await Isolate.run(
        () => _dartFallbackJpeg(bytes, maxDimension),
      );
      if (jpeg == null) throw const ChatImageRejected('media_decode_failed');
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
    } catch (_) {
      try {
        final target = File(targetPath);
        if (await target.exists()) await target.delete();
      } catch (_) {
        // Best effort; chat's stale sweep covers its own folder.
      }
      rethrow;
    }
  }

  /// Computes the (width, height) that keep the longer source edge at most
  /// [longest] pixels, preserving aspect ratio. Returns the source
  /// dimensions unchanged if already within the cap — flutter_image_compress
  /// treats minWidth/minHeight as a target it scales toward, so passing the
  /// untouched source size here is a correct no-op resize, not a floor.
  static ({int width, int height}) _longestEdgeTarget(
    int sourceWidth,
    int sourceHeight,
    int longest,
  ) {
    final longestSide = sourceWidth >= sourceHeight ? sourceWidth : sourceHeight;
    if (longestSide <= longest) {
      return (width: sourceWidth, height: sourceHeight);
    }
    // The long edge lands exactly on [longest]; the short edge is floored
    // (never 0) so neither plugin's scale choice can push the long edge
    // past it by a rounding pixel.
    if (sourceWidth >= sourceHeight) {
      return (
        width: longest,
        height: (sourceHeight * longest ~/ sourceWidth).clamp(1, longest),
      );
    }
    return (
      width: (sourceWidth * longest ~/ sourceHeight).clamp(1, longest),
      height: longest,
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

  Future<String> _targetPath(
    Future<Directory> Function()? outputDirectory,
  ) async {
    Directory dir;
    try {
      if (outputDirectory == null) throw StateError('no output directory');
      dir = await outputDirectory();
      await dir.create(recursive: true);
    } catch (_) {
      try {
        dir = await getTemporaryDirectory();
      } catch (_) {
        // path_provider is unavailable (e.g. a pure Dart test host); use the
        // OS temp dir. Production always has the plugin.
        dir = Directory.systemTemp;
      }
    }
    final name = 'chat_media_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(dir.path, name);
  }

  /// Sniffs the MIME from the leading magic bytes. Filename extensions are not
  /// trusted (Spec 8.1: "do not trust filename extensions").
  static String? _sniffMime(Uint8List b) {
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
