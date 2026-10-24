import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/domain/services/mp4_location_stripper.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
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
  const ChatVideoPreparer({this.boundaryTolerance, this.oversizeRetryQuality});

  /// Opt-in (stories only; chat and streaks pass nothing and are
  /// byte-identical). A camera take that overshoots [maxDuration] by up to
  /// this much (stop latency) is clamped to exactly the max, an untrimmed
  /// source is exported whole instead of through a whole-second window,
  /// and `durationMs` is the exported length capped at the max (01 #4, #16).
  final Duration? boundaryTolerance;

  /// Opt-in (stories only; null keeps chat and streaks byte-identical: one
  /// 720p encode, refused when over the byte ceiling). A 1080p story take
  /// can encode past 25 MB at 720p, the server's ceiling too, so when the
  /// first output is over the limit it is deleted and the source encoded
  /// once more at this quality; only then is the take refused.
  final VideoQuality? oversizeRetryQuality;

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
    if (brand == 'qt  ') return 'video/quicktime';
    // Any other ISO base media file format brand (isom, iso2..iso6, mp41,
    // mp42, avc1, hev1, M4V, 3gp*, dash, f4v, ...) is a container the
    // transcode step normalises to mp4 anyway; refusing uncommon brands only
    // rejected valid clips from ffmpeg/HEVC exports (chat review #29). The
    // brand must still be four printable ASCII characters, so random bytes
    // that happen to spell 'ftyp' at offset 4 are not treated as video.
    final printable = brand.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    return printable ? 'video/mp4' : null;
  }

  /// Corrects raw encoded frame dimensions for rotation metadata, so the
  /// persisted media_width/media_height describe how the video actually
  /// DISPLAYS rather than how its frames happen to be stored.
  ///
  /// video_compress's MediaInfo reports width/height straight off the
  /// encoded stream and exposes `orientation` as a SEPARATE field: a
  /// portrait phone clip is commonly stored as a 1280x720 landscape frame
  /// plus a 90-degree rotation flag. Persisting those raw numbers made
  /// every portrait video render with a landscape aspect ratio — too tall
  /// in the bubble, letterboxed against the wrong edge fullscreen.
  ///
  /// A quarter turn (90 or 270) swaps the axes; 0/180 leave them alone. A
  /// null/unknown orientation is treated as no rotation, which is the same
  /// assumption the old code made unconditionally.
  @visibleForTesting
  static ({int width, int height}) debugOrientedSize({
    required int width,
    required int height,
    required int? orientation,
  }) {
    final normalized = ((orientation ?? 0) % 360 + 360) % 360;
    final quarterTurned = normalized == 90 || normalized == 270;
    return quarterTurned
        ? (width: height, height: width)
        : (width: width, height: height);
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

  /// The part of the source to export. [whole] is true when that is the
  /// entire source: untrimmed (or trimmed to its full length), and, with
  /// [boundaryTolerance], a take up to that much over [maxDuration] (stop
  /// latency), whose window is clamped to exactly the max for the duration
  /// checks and reporting while the file itself is exported whole.
  @visibleForTesting
  static ({Duration start, Duration end, bool whole}) debugExportWindow({
    required Duration source,
    Duration? trimStart,
    Duration? trimEnd,
    required Duration maxDuration,
    Duration? boundaryTolerance,
  }) {
    final start = trimStart ?? Duration.zero;
    final end = trimEnd ?? source;
    final untrimmed = trimStart == null && trimEnd == null;
    if (boundaryTolerance != null &&
        untrimmed &&
        source > maxDuration &&
        source <= maxDuration + boundaryTolerance) {
      return (start: Duration.zero, end: maxDuration, whole: true);
    }
    return (start: start, end: end, whole: start <= Duration.zero && end >= source);
  }

  /// video_compress 3.1.4's `startTime` / `duration` (whole seconds) for an
  /// export window. A whole source passes neither: on Android the plugin
  /// hands `duration` to Transcoder's TrimDataSource as the time cut from
  /// the END (VideoCompressPlugin.kt:145), so the old always-passed full
  /// length cut almost everything; on iOS a zero duration is an empty range
  /// (01 #16). A real trim starts on the whole second at or before the
  /// window and is rounded so the export always covers the window: iOS
  /// takes the length (rounded up), Android the seconds to cut from the end
  /// (rounded down, so start + cut stays under the source and
  /// TrimDataSource does not throw). The Android export can therefore run
  /// up to about a second longer at each end than the window; prepare()
  /// reports the exported length there.
  @visibleForTesting
  static ({int? startTime, int? duration}) debugCompressArgs({
    required Duration source,
    required Duration start,
    required Duration end,
    required bool whole,
    required bool android,
  }) {
    if (whole) return (startTime: null, duration: null);
    final startTime = start.inSeconds;
    if (android) {
      final cut = end >= source ? Duration.zero : source - end;
      return (startTime: startTime, duration: cut.inSeconds);
    }
    final fromStart = end - Duration(seconds: startTime);
    return (startTime: startTime, duration: (fromStart.inMilliseconds / 1000).ceil());
  }

  @visibleForTesting
  static int debugReportedDurationMs({
    required Duration window,
    double? exportedMs,
    required Duration maxDuration,
    required bool precise,
  }) {
    if (!precise) return window.inMilliseconds;
    final actual = exportedMs?.round() ?? window.inMilliseconds;
    return actual < maxDuration.inMilliseconds ? actual : maxDuration.inMilliseconds;
  }

  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    void Function(String posterPath)? onPosterReady,
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

    final window = debugExportWindow(
      source: sourceDuration,
      trimStart: trimStart,
      trimEnd: trimEnd,
      maxDuration: effectiveMaxDuration,
      boundaryTolerance: boundaryTolerance,
    );
    final effectiveStart = window.start;
    final effectiveDuration = window.end - window.start;
    final args = debugCompressArgs(
      source: sourceDuration,
      start: window.start,
      end: window.end,
      whole: window.whole,
      android: defaultTargetPlatform == TargetPlatform.android,
    );

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

    // Thumbnail FIRST, before the expensive transcode. It reads from
    // `localPath` (the original source), never from the compressed output,
    // so it has no real dependency on compression having run — it only used
    // to sit after it. Extracting it up front lets the caller paint a real
    // poster in the bubble while compression is still running (WhatsApp's
    // behavior: the frame appears the instant you hit send, with progress
    // drawn on top) instead of showing a blank placeholder for the entire
    // transcode.
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
      try {
        preparedThumbnail = await const ChatImagePreparer().prepare(
          rawThumbPath,
        );
      } finally {
        // The raw frame is only the preparer's input (it always writes a new
        // file): never leave a full-quality plaintext frame in tmp/.
        try {
          await File(rawThumbPath).delete();
        } catch (_) {}
      }
    } on ChatImageRejected {
      throw const ChatVideoRejected('thumbnail_failed');
    }
    onPosterReady?.call(preparedThumbnail.file.path);

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
    // video_compress reports progress (0-100) on a broadcast-style
    // ObservableBuilder<double> (VideoCompress.compressProgress$), separate
    // from the compressVideo() future itself — subscribe around the call and
    // forward each value through onProgress, unsubscribing in `finally` so
    // the subscription can't outlive this call or fire after prepare()
    // returns/throws (compressProgress$ is a singleton on the plugin
    // instance, shared across calls).
    Future<({MediaInfo info, File file, int size})> encode(
      VideoQuality quality,
    ) async {
      final MediaInfo? compressed;
      final progressSubscription =
          onProgress == null
              ? null
              : VideoCompress.compressProgress$.subscribe((value) {
                onProgress(value);
              });
      try {
        compressed = await VideoCompress.compressVideo(
          localPath,
          quality: quality,
          startTime: args.startTime,
          duration: args.duration,
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
      // Where it was recorded stays on the phone (couple map spec §7): the
      // transcode keeps the source's location atoms; neutralise them in
      // place.
      await Mp4LocationStripper.strip(outFile);
      return (info: compressed, file: outFile, size: await outFile.length());
    }

    var encoded = await encode(VideoQuality.Res1280x720Quality);
    // Opted in (stories): one more encode, one quality step down, before an
    // oversize take is refused. The oversize output is deleted first (the
    // Android plugin names outputs by the second, so a quick second encode
    // could reuse the path).
    final retryQuality = oversizeRetryQuality;
    if (encoded.size > effectiveMaxBytes && retryQuality != null) {
      ChatLog.diagnostic('video over limit, re-encoding', '${encoded.size}B');
      try {
        await encoded.file.delete();
      } catch (_) {}
      encoded = await encode(retryQuality);
    }
    final compressed = encoded.info;
    final outFile = encoded.file;
    final outSize = encoded.size;
    if (outSize <= 0 || outSize > effectiveMaxBytes) {
      // Opted in: the refused encode is not left in the plugin's folder
      // (never cleared on Android; batch-6 review #6). Chat is unchanged.
      if (retryQuality != null) {
        try {
          await outFile.delete();
        } catch (_) {}
      }
      throw const ChatVideoRejected('media_compress_failed');
    }

    // Rotation-correct the dimensions before they're persisted — see
    // debugOrientedSize. Falls back to the SOURCE probe's dimensions when
    // the compressed MediaInfo omits them (observed on some Android
    // encoders, where compressVideo returns a valid file with null
    // width/height); a wrong-but-present source ratio still beats the 16/9
    // default the UI would otherwise land on.
    final rawWidth = compressed.width ?? info.width ?? 0;
    final rawHeight = compressed.height ?? info.height ?? 0;
    final oriented = debugOrientedSize(
      width: rawWidth,
      height: rawHeight,
      // Prefer the OUTPUT's orientation: the transcode may have baked the
      // rotation into the frames (leaving orientation 0), in which case
      // applying the source's rotation would double-correct and re-break
      // the ratio. Only fall back to the source when the output is silent.
      orientation: compressed.orientation ?? info.orientation,
    );

    return PreparedChatVideo(
      file: outFile,
      mimeType: 'video/mp4',
      byteSize: outSize,
      durationMs: debugReportedDurationMs(
        window: effectiveDuration,
        exportedMs: compressed.duration,
        maxDuration: effectiveMaxDuration,
        // A real trim on Android is rounded outward (debugCompressArgs), so
        // the exported length is reported, not the window (review #7). iOS
        // keeps the window: its plugin ignores the range with audio (C1,
        // owner decision).
        precise:
            boundaryTolerance != null ||
            (!window.whole && defaultTargetPlatform == TargetPlatform.android),
      ),
      thumbnailFile: preparedThumbnail.file,
      thumbnailMimeType: preparedThumbnail.mimeType,
      thumbnailByteSize: preparedThumbnail.byteSize,
      width: oriented.width,
      height: oriented.height,
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
