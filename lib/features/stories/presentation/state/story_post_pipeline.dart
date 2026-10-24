import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart'
    show kStreakSegmentDuration;
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart' show VideoQuality;
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

/// One take the person tapped Share on, and the seams to prepare it.
@immutable
class StoryPostRequest {
  const StoryPostRequest({
    required this.raw,
    required this.relationshipId,
    required this.utcOffsetMinutes,
    this.place,
    this.videoPreparer,
    this.imagePreparer,
    this.thumbnailPreparer,
    this.thumbnailGrabber,
  });

  /// The camera's raw capture (tmp/). Deleted once queued or rejected;
  /// kept only when the keystore refused, so Share can be tried again.
  final CapturedMedia raw;
  final String relationshipId;

  /// Read by the caller at Share time (the device offset then).
  final int utcOffsetMinutes;

  /// The "Pin to our map" read, bounded by [StoryPostPipeline.placeBound].
  final Future<StoryPlaceDraft?> Function()? place;

  /// Test seams. Null uses the story policies below.
  final ChatVideoPreparer Function()? videoPreparer;
  final CaptureImagePreparer Function()? imagePreparer;
  final CaptureImagePreparer Function()? thumbnailPreparer;
  final Future<Uint8List?> Function(String videoPath)? thumbnailGrabber;
}

/// What became of a [StoryPostRequest].
sealed class StoryPostOutcome {
  const StoryPostOutcome();
}

/// In the outbox; the upload is the outbox controller's job from here.
final class StoryPostQueued extends StoryPostOutcome {
  const StoryPostQueued({
    required this.clientStoryId,
    required this.placeDropped,
  });
  final String clientStoryId;

  /// The pin was on but the place lookup ran past the bound, so the story
  /// was queued without one. The caller says so.
  final bool placeDropped;
}

/// The keystore refused (fail closed): nothing queued. The raw take is
/// kept while the camera shows it; otherwise it is deleted and a
/// `not_saved` notice raised.
final class StoryPostNotSaved extends StoryPostOutcome {
  const StoryPostNotSaved();
}

/// The take could not be prepared (or the person signed out meanwhile).
/// [code] maps to copy through `storyPrepareFailureMessage`; a [retryable]
/// one through `storyPrepareRetryMessage`.
final class StoryPostRejected extends StoryPostOutcome {
  const StoryPostRejected(this.code, {this.retryable = false});
  final String code;

  /// The failure was not about the take, and the camera is still showing
  /// it: the raw take was kept, so Share can be tried again.
  final bool retryable;
}

/// A rejection nobody was on screen to see (the camera had gone), for the
/// rings row to show.
@immutable
class StoryPostNotice {
  const StoryPostNotice({
    required this.code,
    required this.mediaType,
    required this.userId,
  });
  final String code;

  /// The account it was raised for; the rings row shows it only to them.
  final String userId;
  final CapturedMediaType mediaType;
}

/// The story thumbnail policy (spec §4.3): 400px long edge, JPEG q75, at
/// most 800KB (the server's thumbnail ceiling). Moved from
/// story_camera_screen.dart unchanged.
const int _thumbnailMaxDimension = 400;
const int _thumbnailQuality = 75;
const int _thumbnailMaxBytes = 800 * 1024;

/// Raised when a thumbnail cannot be produced at all (a corrupt capture,
/// or the video frame grab failing). A coarse, content-free code, like
/// [CaptureImageRejected].
class StoryThumbnailFailed implements Exception {
  const StoryThumbnailFailed(this.code);
  final String code;

  @override
  String toString() => 'StoryThumbnailFailed($code)';
}

/// Everything between Share and the outbox: prepare to the main-media
/// policy, build the required thumbnail, read the pin (bounded), move both
/// files into the vault, enqueue. Runs on a provider Ref, not a widget's, so
/// a camera that unmounts mid-prepare (back, the privacy cover, a route
/// change) never drops the take (01 #14, 07b G7). [post]'s
/// `callerListening` says whether the camera is still there to show a
/// failure; if not, the failure goes to [storyPostNoticeProvider] for the
/// rings row.
class StoryPostPipeline {
  StoryPostPipeline(this._ref, {this.placeBound = const Duration(seconds: 3)});

  final Ref _ref;

  /// How long Share waits for the pin's place before posting without one.
  final Duration placeBound;

  /// A camera take overshoots the minute by its stop latency (01 #4).
  static const Duration videoBoundaryTolerance = Duration(seconds: 2);
  static const int _maxVideoBytes = 25 * 1024 * 1024;

  /// The story video preparer: the 60 s edge tolerance (Task 15), and a
  /// `veryHigh` (1080p) take that encodes past the 25 MB ceiling (the
  /// server's too) at 720p is encoded once more at 960×540 before it is
  /// refused (batch-5 review #2). Chat and streaks keep the default.
  static ChatVideoPreparer storyVideoPreparer() => const ChatVideoPreparer(
    boundaryTolerance: videoBoundaryTolerance,
    oversizeRetryQuality: VideoQuality.Res960x540Quality,
  );

  /// Rejections about the take itself: Share would fail the same way
  /// again, so the take is deleted. Every other code (an interrupted or
  /// failed export, a thumbnail that could not be made, anything
  /// unexpected) is transient: while the camera is showing, the take is
  /// kept on the review for another Share (batch-7 review I3).
  static const Set<String> permanentRejections = {
    'media_too_long',
    'media_too_short',
    'media_too_large',
    'media_dimensions_excessive',
    'media_decode_failed',
    'media_type_unsupported',
    'media_missing',
    'media_empty',
  };

  Future<StoryPostOutcome> post(
    StoryPostRequest request, {
    bool Function()? callerListening,
  }) async {
    // Read up front: nothing below may depend on the caller still existing.
    final userId = _ref.read(currentUserProvider)?.id;
    final vault = _ref.read(storyMediaVaultProvider);
    final store = _ref.read(storyOutboxStoreProvider);
    final raw = request.raw;
    bool gone() => callerListening != null && !callerListening();
    if (userId == null || userId.isEmpty) {
      return _rejected('signed_out', raw, gone: gone(), userId: userId);
    }
    // Sign-out and quick exit wipe the outbox and the vault BEFORE the
    // session ends, while this user is still current; the wipe bumps the
    // store's epoch. Either change means: queue nothing for this account
    // (batch-7 review I1, Review Focus 2).
    final epoch = store.epoch;
    bool stale() =>
        store.epoch != epoch || _ref.read(currentUserProvider)?.id != userId;
    // Intermediate files in tmp/, removed on any failure before the vault
    // takes them (01 #19).
    final scratch = <String>[];
    StoryOutboxRecord? adopted;
    String? adopting;
    try {
      final prepared = await _prepare(request);
      if (prepared.path != raw.path) scratch.add(prepared.path);
      final thumbnailPath = await _thumbnail(request, prepared);
      scratch.add(thumbnailPath);
      final (place, placeDropped) = await _place(request);
      if (stale()) throw const _SignedOutMeanwhile();
      final outbox = _ref.read(storyOutboxProvider.notifier);
      final clientStoryId = newClientStoryId();
      adopting = clientStoryId;
      final stored = await vault.adopt(
        userId: userId,
        clientStoryId: clientStoryId,
        mediaPath: prepared.path,
        thumbnailPath: thumbnailPath,
      );
      final record = StoryOutboxRecord(
        clientStoryId: clientStoryId,
        relationshipId: request.relationshipId,
        localMediaPath: stored.media,
        localThumbnailPath: stored.thumbnail,
        mediaType: prepared.type,
        mimeType:
            prepared.type == CapturedMediaType.image
                ? 'image/jpeg'
                : 'video/mp4',
        width: prepared.width,
        height: prepared.height,
        durationMs: prepared.durationMs,
        utcOffsetMinutes: request.utcOffsetMinutes,
        createdAt: DateTime.now(),
        place: place,
      );
      adopted = record;
      // The store refuses the write if a wipe ran since [epoch].
      final queued = await outbox.enqueueLocally(record, expectEpoch: epoch);
      if (stale()) {
        // A wipe that landed after the write: take the row back out (the
        // catch below removes the files).
        if (queued) await store.remove(userId, clientStoryId);
        throw const _SignedOutMeanwhile();
      }
      if (!queued) {
        // Keystore refused (fail closed): nothing queued; drop the
        // prepared copies.
        await vault.deleteFor(record);
        if (gone()) {
          // Nobody is left to offer Share again: delete the take and say
          // so (batch-7 review I2).
          unawaited(_deleteQuietly(raw.path));
          _notice('not_saved', raw.type, userId);
        }
        // Otherwise the raw take is kept so the review can offer Share
        // again.
        return const StoryPostNotSaved();
      }
      // Not awaited: the outcome (and the camera's pop) does not wait on
      // file I/O, and no I/O runs synchronously on the UI isolate.
      unawaited(_deleteQuietly(raw.path));
      if (placeDropped && gone()) _notice('place_dropped', raw.type, userId);
      return StoryPostQueued(
        clientStoryId: clientStoryId,
        placeDropped: placeDropped,
      );
    } catch (error, stack) {
      ChatLog.diagnostic('story post prepare failed', '$error\n$stack');
      for (final path in scratch) {
        await _deleteQuietly(path);
      }
      if (adopted != null) await vault.deleteFor(adopted);
      final code = switch (error) {
        ChatVideoRejected(:final code) => code,
        CaptureImageRejected(:final code) => code,
        StoryThumbnailFailed(:final code) => code,
        _SignedOutMeanwhile() => 'signed_out',
        _ => 'capture_failed',
      };
      final retryable =
          code != 'signed_out' && !permanentRejections.contains(code);
      final callerGone = gone();
      if (retryable && !callerGone) {
        // The camera is still showing the take: keep it for another Share.
        return StoryPostRejected(code, retryable: true);
      }
      return _rejected(code, raw, gone: callerGone, userId: userId);
    } finally {
      // The row is written or the folder deleted: the orphan sweep may
      // judge this folder now (final review #3c).
      if (adopting != null) vault.release(adopting);
    }
  }

  Future<StoryPostOutcome> _rejected(
    String code,
    CapturedMedia raw, {
    required bool gone,
    required String? userId,
  }) async {
    await _deleteQuietly(raw.path);
    // signed_out is never told: the next person on this phone would see it
    // (batch-7 review M3).
    if (gone && code != 'signed_out' && userId != null) {
      _notice(code, raw.type, userId);
    }
    return StoryPostRejected(code);
  }

  void _notice(String code, CapturedMediaType type, String userId) {
    _ref.read(storyPostNoticeProvider.notifier).state = StoryPostNotice(
      code: code,
      mediaType: type,
      userId: userId,
    );
  }

  Future<CapturedMedia> _prepare(StoryPostRequest r) async {
    final raw = r.raw;
    if (raw.type == CapturedMediaType.image) {
      final image = await (r.imagePreparer ?? CaptureImagePreparer.new)()
          .prepare(raw.path);
      return CapturedMedia(
        path: image.file.path,
        type: CapturedMediaType.image,
        width: image.width,
        height: image.height,
      );
    }
    // The preparer's first-frame poster (a full-quality JPEG in tmp/) is
    // chat's bubble poster; a story builds its own thumbnail, so the poster
    // is deleted on every path, never left as plaintext (final review #3b).
    final posters = <String>{};
    final PreparedChatVideo video;
    try {
      video = await (r.videoPreparer ?? storyVideoPreparer)().prepare(
        localPath: raw.path,
        maxDuration: kStreakSegmentDuration,
        maxBytes: _maxVideoBytes,
        onPosterReady: posters.add,
      );
      posters.add(video.thumbnailFile.path);
      posters.remove(video.file.path); // never the media itself
    } finally {
      for (final poster in posters) {
        unawaited(_deleteQuietly(poster));
      }
    }
    return CapturedMedia(
      path: video.file.path,
      type: CapturedMediaType.video,
      width: video.width,
      height: video.height,
      durationMs: video.durationMs,
    );
  }

  /// Spec §4.3: a frame grab for a video, a downscaled rendition for an
  /// image, both through the same 400px/q75 preparer. Moved from
  /// story_camera_screen.dart `_buildThumbnail`.
  Future<String> _thumbnail(StoryPostRequest r, CapturedMedia prepared) async {
    final preparer =
        (r.thumbnailPreparer ??
            () => const CaptureImagePreparer(
              maxDimension: _thumbnailMaxDimension,
              maxBytes: _thumbnailMaxBytes,
              // One fixed quality, not the main-image ladder: at 400px a
              // JPEG is far under 800KB at q75.
              qualityLadder: [_thumbnailQuality],
              fallbackQuality: _thumbnailQuality,
            ))();
    if (prepared.type == CapturedMediaType.image) {
      return (await preparer.prepare(prepared.path)).file.path;
    }
    final grab =
        r.thumbnailGrabber ??
        (path) => video_thumb.VideoThumbnail.thumbnailData(
          video: path,
          timeMs: 0,
          quality: 90,
        );
    final bytes = await grab(prepared.path);
    if (bytes == null) {
      throw const StoryThumbnailFailed('thumbnail_frame_failed');
    }
    final frame = await _tempPath('story_thumb_frame', 'jpg');
    await File(frame).writeAsBytes(bytes, flush: true);
    try {
      return (await preparer.prepare(frame)).file.path;
    } finally {
      await _deleteQuietly(frame);
    }
  }

  /// The pin, bounded (01 #14: a slow fix used to hold the shutter up to
  /// 20 s + 10 s). Past the bound the story posts without a place.
  Future<(StoryPlaceDraft?, bool)> _place(StoryPostRequest r) async {
    final lookup = r.place;
    if (lookup == null) return (null, false);
    try {
      return (await lookup().timeout(placeBound), false);
    } on TimeoutException {
      return (null, true);
    } catch (_) {
      return (null, false);
    }
  }

  static Future<String> _tempPath(String prefix, String ext) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    return p.join(
      dir.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _SignedOutMeanwhile implements Exception {
  const _SignedOutMeanwhile();
}

final storyPostPipelineProvider = Provider<StoryPostPipeline>(
  (ref) => StoryPostPipeline(ref),
);

/// The latest outcome the camera was no longer there to show. Rebuilt
/// (cleared) on any account change, so a notice never reaches the next
/// person on a shared phone (batch-7 review M3).
final storyPostNoticeProvider = StateProvider<StoryPostNotice?>((ref) {
  ref.watch(currentUserProvider.select((user) => user?.id));
  return null;
});
