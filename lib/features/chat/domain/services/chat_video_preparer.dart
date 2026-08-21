import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Result of preparing a video for the private chat media pipeline.
class PreparedChatVideo {
  const PreparedChatVideo({
    required this.file,
    required this.mimeType,
    required this.byteSize,
    required this.durationMs,
    required this.thumbnailFile,
    required this.thumbnailMimeType,
    required this.thumbnailByteSize,
    required this.width,
    required this.height,
  });

  final File file;
  final String mimeType;
  final int byteSize;
  final int durationMs;
  final File thumbnailFile;
  final String thumbnailMimeType;
  final int thumbnailByteSize;
  final int width;
  final int height;
}

/// Raised when a video cannot be made to meet the chat upload contract. The
/// [code] is a coarse, content-free reason (mirrors ChatImageRejected in
/// chat_image_preparer.dart) — safe to log, never a raw path or exception.
class ChatVideoRejected implements Exception {
  const ChatVideoRejected(this.code);
  final String code;

  @override
  String toString() => 'ChatVideoRejected($code)';
}

/// Enforces the private-video upload contract on the client, before any
/// upload intent is requested. See design spec's "Client Architecture" and
/// "Error Handling" sections for the full guard-order rationale.
///
/// Deliberately client-side only, mirroring ChatImagePreparer/
/// VoiceRecorderService — there is no server-side transcoding step (see the
/// design spec's "Why video compression is client-side only" section: no
/// viable Flutter-compatible server-side transcoding option exists for
/// Supabase Edge Functions).
class ChatVideoPreparer {
  const ChatVideoPreparer();

  static const int maxBytes = 25 * 1024 * 1024; // post-transcode output ceiling
  static const int maxSourceBytes =
      500 * 1024 * 1024; // trim-window estimate guard
  static const Duration maxDuration = Duration(minutes: 3);
  static const Duration minDuration = Duration(milliseconds: 500);

  /// Longest-edge target for the transcoded output. Not passed as a
  /// standalone parameter — video_compress has no explicit
  /// width/height/bitrate control surface, only the [VideoQuality] enum
  /// (see the `compressVideo` call in [prepare] below). This constant is
  /// honored by choosing [VideoQuality.Res1280x720Quality], which the
  /// plugin's native Android implementation maps to `atMost(720, 1280)`
  /// (`DefaultVideoStrategy` in video_compress's Kotlin source). It's kept
  /// as a named constant — rather than inlined — because Task 6 (trim
  /// screen) and other call sites reason about "what resolution will this
  /// produce" against this name.
  static const int targetHeight = 720;

  /// Test seam: the same trim-window-byte-estimate formula prepare() uses
  /// internally (sourceBytes * windowDuration/sourceDuration), exposed so
  /// its RELATIVE correctness (a longer window estimates more bytes than a
  /// shorter one) can be asserted directly — this is the numeric-transform
  /// class of logic that needs a relative-correctness test, not just a
  /// shape/range test, per this plan's Global Constraints.
  @visibleForTesting
  static int debugEstimateWindowBytes({
    required int sourceBytes,
    required Duration sourceDuration,
    required Duration windowDuration,
  }) {
    if (sourceDuration.inMicroseconds <= 0) return 0;
    final fraction =
        windowDuration.inMicroseconds / sourceDuration.inMicroseconds;
    return (sourceBytes * fraction).round();
  }

  /// Test seam: sniffs the MIME from the leading ISO-BMFF `ftyp` box magic
  /// bytes, without needing a full file. Never trusts the filename
  /// extension — the video analogue of ChatImagePreparer's byte-sniffing.
  @visibleForTesting
  static String? debugSniffMime(List<int> bytes) {
    if (bytes.length < 12) return null;
    // ISO base media file format: [4-byte box size][4-byte type 'ftyp'][4-byte major brand]...
    final isFtyp =
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    if (!isFtyp) return null;

    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    switch (brand) {
      case 'isom':
      case 'mp42':
      case 'avc1':
      case 'M4V ':
        return 'video/mp4';
      case 'qt  ':
        return 'video/quicktime';
      default:
        return null;
    }
  }

  /// Test seam: the same maxDuration-defaulting prepare() does internally
  /// (fall back to the class constant when the caller omits an override),
  /// exposed so the defaulting behavior itself can be asserted without a
  /// full native-backed prepare() call.
  @visibleForTesting
  static Duration debugResolveMaxDuration(Duration? override) =>
      override ?? maxDuration;

  /// Test seam: mirrors debugResolveMaxDuration for the byte ceiling.
  @visibleForTesting
  static int debugResolveMaxBytes(int? override) => override ?? maxBytes;

  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    Duration? maxDuration,
    int? maxBytes,
  }) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const ChatVideoRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const ChatVideoRejected('media_empty');

    // Early, cheap absolute-size guard: reject a source file that's already
    // bigger than the pre-transcode ceiling outright, before paying for a
    // MIME sniff, getMediaInfo probe, or (further down) any decode work.
    // This is deliberately independent of the trim window — VideoTrimScreen
    // clamps the *selected* window to <=3 minutes before prepare() ever
    // runs, which means the window-estimate guard below (windowEstimate >
    // maxSourceBytes) can in practice only trip within a narrow high-bitrate
    // band once the window is bounded. An absurdly large full source (e.g. a
    // multi-GB 4K/60 file the user only trims a few seconds from) deserves
    // to be rejected before any expensive probing, independent of what
    // window they eventually pick.
    if (sourceLength > maxSourceBytes) {
      throw const ChatVideoRejected('media_too_large');
    }

    final headerBytes = await source.openRead(0, 128).first;
    final sniffedMime = debugSniffMime(headerBytes);
    if (sniffedMime == null) {
      throw const ChatVideoRejected('media_type_unsupported');
    }

    final effectiveMaxDuration = debugResolveMaxDuration(maxDuration);
    final effectiveMaxBytes = debugResolveMaxBytes(maxBytes);

    final MediaInfo info;
    try {
      info = await VideoCompress.getMediaInfo(localPath);
    } catch (_) {
      throw const ChatVideoRejected('media_decode_failed');
    }
    final sourceDurationMs = info.duration?.round();
    if (sourceDurationMs == null) {
      throw const ChatVideoRejected('media_decode_failed');
    }
    final sourceDuration = Duration(milliseconds: sourceDurationMs);

    final effectiveStart = trimStart ?? Duration.zero;
    final effectiveEnd = trimEnd ?? sourceDuration;
    final effectiveDuration = effectiveEnd - effectiveStart;

    // Window-estimate size guard runs BEFORE the duration-bounds check
    // (rather than after, as a naive top-to-bottom reading of the flow might
    // suggest) so it can fire independently of the UI's <=3-minute trim
    // clamp. If it ran after the duration check, it would only ever be
    // reachable within an already-<=3-minute window — collapsing its
    // practical range to a narrow ~13Mbit/s+-sustained-bitrate band instead
    // of providing broad protection against oversized/high-bitrate sources.
    final windowEstimate = debugEstimateWindowBytes(
      sourceBytes: sourceLength,
      sourceDuration: sourceDuration,
      windowDuration: effectiveDuration,
    );
    if (windowEstimate > maxSourceBytes) {
      throw const ChatVideoRejected('media_too_large');
    }

    if (effectiveDuration < minDuration) {
      throw const ChatVideoRejected('media_too_short');
    }
    if (effectiveDuration > effectiveMaxDuration) {
      throw const ChatVideoRejected('media_too_long');
    }

    // NOTE on quality targets: video_compress's method channel only accepts
    // path/quality/deleteOrigin/startTime/duration/includeAudio/frameRate
    // (see the plugin's own `compressVideo` implementation) — there is no
    // bitrate or audio-channel-count parameter anywhere in its API surface.
    // The design spec's 800kbps video / 64kbps-mono-AAC audio targets are
    // therefore NOT directly enforceable with this plugin: on Android,
    // VideoQuality.Res1280x720Quality resolves to an `atMost(720, 1280)`
    // resolution cap with the encoder's own default bitrate for that
    // resolution (not a fixed 800kbps), and audio is passed through via
    // DefaultAudioStrategy using the source's own channel count/sample rate
    // (not downmixed to mono or capped at 64kbps); on iOS it maps to the
    // opaque AVAssetExportPresetMediumHighQuality-class preset for 720p.
    // [maxBytes] (25MB, enforced below) is the real, authoritative backstop
    // against oversized output — resolution/quality-enum choice is a
    // best-effort input to staying under that ceiling, not a guarantee.
    final MediaInfo? compressed;
    // video_compress reports progress (0-100) on a broadcast-style
    // ObservableBuilder<double> (VideoCompress.compressProgress$), separate
    // from the compressVideo() future itself — subscribe around the call and
    // forward each value through onProgress, unsubscribing in `finally` so
    // the subscription can't outlive this call or fire after prepare()
    // returns/throws (compressProgress$ is a singleton on the plugin
    // instance, shared across calls).
    final progressSubscription =
        onProgress == null
            ? null
            : VideoCompress.compressProgress$.subscribe((value) {
              onProgress(value);
            });
    try {
      compressed = await VideoCompress.compressVideo(
        localPath,
        quality: VideoQuality.Res1280x720Quality,
        startTime: effectiveStart.inSeconds,
        duration: effectiveDuration.inSeconds,
        includeAudio: true,
        deleteOrigin: false,
      );
    } catch (_) {
      throw const ChatVideoRejected('media_compress_failed');
    } finally {
      progressSubscription?.unsubscribe();
    }
    if (compressed?.file == null) {
      throw const ChatVideoRejected('media_compress_failed');
    }

    final outFile = compressed!.file!;
    final outSize = await outFile.length();
    if (outSize <= 0 || outSize > effectiveMaxBytes) {
      throw const ChatVideoRejected('media_compress_failed');
    }

    final PreparedChatImage preparedThumbnail;
    try {
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: localPath,
        timeMs: effectiveStart.inMilliseconds,
        quality: 90,
      );
      if (thumbnailBytes == null) {
        throw const ChatVideoRejected('thumbnail_failed');
      }
      final rawThumbPath = await _tempTargetPath('raw_thumb', 'jpg');
      await File(rawThumbPath).writeAsBytes(thumbnailBytes, flush: true);
      preparedThumbnail = await const ChatImagePreparer().prepare(rawThumbPath);
    } on ChatImageRejected {
      throw const ChatVideoRejected('thumbnail_failed');
    }

    return PreparedChatVideo(
      file: outFile,
      mimeType: 'video/mp4',
      byteSize: outSize,
      durationMs: effectiveDuration.inMilliseconds,
      thumbnailFile: preparedThumbnail.file,
      thumbnailMimeType: preparedThumbnail.mimeType,
      thumbnailByteSize: preparedThumbnail.byteSize,
      width: compressed.width ?? 0,
      height: compressed.height ?? 0,
    );
  }

  Future<String> _tempTargetPath(String prefix, String extension) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final name =
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    return p.join(dir.path, name);
  }
}
