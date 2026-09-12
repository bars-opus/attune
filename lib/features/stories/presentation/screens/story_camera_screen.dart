/// The story adapter over the shared capture module (Plan B, Task 7, spec
/// §6/§6.1/§4.3) — the LAST piece tying capture to the posting outbox.
///
/// [CaptureCameraScreen] (`lib/features/chat/presentation/screens/
/// capture_camera_screen.dart`) owns everything destination-neutral:
/// permissions, camera switching, the tap/hold gesture split, transcode
/// and the main-media size ceilings.
///
/// **Embedded, not pushed — mirrors [StreakCameraScreen] exactly.**
/// [CaptureCameraScreen] supports two shapes (see its own doc comment):
/// pushed standalone, where it transcodes and pops itself with the
/// result; or embedded via a [GlobalKey] with [onCaptured]/[onCancelled]
/// callbacks, where the embedder decides when to call [confirmSend]
/// itself. This screen uses the SECOND shape, the one
/// `StreakCameraScreen` already ships with — [CaptureCameraScreen] owns
/// its `context.pop(prepared)` on the standalone path, which only
/// resolves for whatever pushed it; embedding sidesteps that seam
/// entirely; there is no nested route whose pop needs to line up with
/// anything, and no risk of a go_router `context.pop()` call failing to
/// resolve a plain `Navigator.push`ed route (a mismatch this task hit
/// and fixed by switching shapes, not by swapping which `pop` API is
/// called elsewhere).
///
/// This screen's own job, mirroring what [StreakCameraScreen] does for
/// streaks (spec §6: "two thin adapters consume it"):
///  1. Generate the REQUIRED thumbnail (spec §4.3): 400px long edge, JPEG,
///     quality 75. `thumbnail_key` is `NOT NULL` server-side, so a story
///     without one can never be finalized — this runs before enqueue, not
///     after, so a queued record is never missing one.
///  2. Build a [StoryOutboxRecord], minting its [newClientStoryId] exactly
///     once (never regenerated — that is what makes a retry after a lost
///     finalize response safe, per `StoryOutboxController`'s own doc
///     comment).
///  3. Enqueue through [storyOutboxProvider] and leave. The upload and its
///     retries belong to the outbox controller (Task 6) — spec §6.1: "a
///     capture must not hold the user on a progress screen through a
///     25MB upload." This screen never calls [StoryGateway] directly.
///  4. Pop back to wherever the story camera was opened from.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/capture_camera_screen.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

/// The story thumbnail policy (spec §4.3): 400px long edge, JPEG, quality
/// 75 — distinct from [CaptureImagePreparer]'s default MAIN image policy
/// (2560px/5MB, spec §4.2), which Task 3's tests pin and which this
/// screen must not disturb. 800KB is the server's own ceiling for a
/// thumbnail object (spec §4.2's table); nothing at 400px/q75 JPEG comes
/// remotely close to it in practice, but the preparer still enforces a
/// real ceiling rather than trusting the quality setting alone.
const int _thumbnailMaxDimension = 400;
const int _thumbnailQuality = 75;
const int _thumbnailMaxBytes = 800 * 1024;

/// Raised when a thumbnail cannot be produced at all (e.g. a corrupt
/// capture, or the video frame-grab failing). Mirrors
/// [CaptureImageRejected]'s shape: a coarse, content-free code.
class StoryThumbnailFailed implements Exception {
  const StoryThumbnailFailed(this.code);
  final String code;

  @override
  String toString() => 'StoryThumbnailFailed($code)';
}

class StoryCameraScreen extends ConsumerStatefulWidget {
  const StoryCameraScreen({
    super.key,
    required this.relationshipId,
    this.videoPreparerFactory,
    this.imagePreparerFactory,
    this.thumbnailPreparerFactory,
    this.thumbnailGrabber,
  });

  /// Which relationship this capture posts to. Stories have no
  /// destination-picker (spec §2: "audience is the partner, always"), so
  /// this is the only routing information the adapter needs.
  final String relationshipId;

  /// Test seam, forwarded verbatim to the embedded [CaptureCameraScreen].
  final ChatVideoPreparer Function()? videoPreparerFactory;

  /// Test seam, forwarded verbatim to the embedded [CaptureCameraScreen]
  /// for the MAIN image prepare step (2560px/5MB, spec §4.2). The
  /// thumbnail step below always builds its own dedicated
  /// [CaptureImagePreparer] instance at the 400px/q75 policy — this
  /// factory is never reused for it, so overriding one never silently
  /// changes the other's numbers.
  final CaptureImagePreparer Function()? imagePreparerFactory;

  /// Test seam for the thumbnail-policy [CaptureImagePreparer] itself
  /// (400px/q75, spec §4.3), separate from [imagePreparerFactory] above
  /// for the reason stated there. Defaults to a real instance constructed
  /// with the thumbnail policy.
  final CaptureImagePreparer Function()? thumbnailPreparerFactory;

  /// Test seam for the video frame-grab this screen uses to build a
  /// video's thumbnail source frame. `video_thumbnail`'s platform channel
  /// has no implementation on a test host (the same gap
  /// [ChatVideoPreparer]'s own `VideoThumbnail.thumbnailData` call hits),
  /// so a widget test cannot exercise the real grab — this seam lets one
  /// substitute a fake JPEG frame instead. Defaults to the real
  /// `video_thumbnail` call. Documented here rather than restructuring
  /// shipped code: this is new code in this task, so the seam belongs on
  /// it directly.
  final Future<Uint8List?> Function(String videoPath)? thumbnailGrabber;

  @override
  ConsumerState<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends ConsumerState<StoryCameraScreen> {
  final GlobalKey<CaptureCameraScreenState> _captureKey =
      GlobalKey<CaptureCameraScreenState>();

  /// Guards against a double-enqueue: [CaptureCameraScreen] reports a
  /// capture exactly once per take, but a story that posts twice from one
  /// capture is exactly the failure mode the outbox's idempotency key
  /// exists to prevent, so this is worth being certain about too.
  bool _handled = false;

  /// Called by the embedded [CaptureCameraScreen] once a take is
  /// captured. Unlike the streak adapter, there is no review sheet here
  /// (spec §6.1: the outbox queue itself, with its visible Retry/Discard,
  /// is the review) — [CaptureCameraScreen] has already prepared the
  /// media by the time this fires: a video through [ChatVideoPreparer]
  /// (25MB ceiling) if it came from a hold, straight off [takePicture] if
  /// a tap, and either way `raw` here is what
  /// [CaptureCameraScreenState.confirmSend] would themselves resize for
  /// an image, so this calls it explicitly to reach that same prepared
  /// state before building the outbox record.
  void _onCaptured(CapturedMedia raw) {
    unawaited(_prepareAndEnqueue(raw));
  }

  /// Called by the embedded [CaptureCameraScreen] when a take is
  /// discarded outright, or the user closes the camera without capturing
  /// anything.
  void _onCaptureCancelled() {
    if (mounted) context.pop();
  }

  Future<void> _prepareAndEnqueue(CapturedMedia raw) async {
    if (_handled) return;
    _handled = true;

    try {
      // confirmSend transcodes/prepares to the MAIN media policy — video
      // through ChatVideoPreparer's 25MB ceiling, image through
      // CaptureImagePreparer's 2560px/5MB ceiling (spec §4.2). This is
      // the exact call StreakCameraScreen._send makes at send-tap time
      // (not capture-completion time, deliberately — see
      // CaptureCameraScreen.confirmSend's own doc comment); the story
      // adapter has no separate "send tap" of its own, so this runs
      // immediately once the take is captured.
      final prepared = await _captureKey.currentState!.confirmSend(raw);
      if (!mounted) return;

      final utcOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      final thumbnailPath = await _buildThumbnail(prepared);

      final record = StoryOutboxRecord(
        clientStoryId: newClientStoryId(),
        relationshipId: widget.relationshipId,
        localMediaPath: prepared.path,
        localThumbnailPath: thumbnailPath,
        mediaType: prepared.type,
        mimeType: _mimeTypeFor(prepared.type),
        width: prepared.width,
        height: prepared.height,
        durationMs: prepared.durationMs,
        utcOffsetMinutes: utcOffsetMinutes,
        createdAt: DateTime.now(),
      );

      // Enqueue and leave: the upload (and its retries) belong entirely
      // to the outbox controller from here (spec §6.1). `enqueue` returns
      // the underlying flush's future, but this screen deliberately does
      // NOT await it — awaiting would hold the user on this screen for
      // exactly the upload the spec says never to block on.
      unawaited(ref.read(storyOutboxProvider.notifier).enqueue(record));
    } on ChatVideoRejected catch (rejected) {
      ChatLog.diagnostic('story video prepare rejected', rejected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That could not be posted.')),
        );
      }
    } on CaptureImageRejected catch (rejected) {
      ChatLog.diagnostic('story image prepare rejected', rejected);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That could not be posted.')),
        );
      }
    } catch (error, stack) {
      ChatLog.diagnostic('story capture failed', '$error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That could not be posted.')),
        );
      }
    } finally {
      if (mounted) context.pop();
    }
  }

  /// Spec §4.3: "for a video this is a frame grab; for an image a
  /// downscaled rendition." Both target 400px long edge, JPEG, quality 75
  /// — the same numbers `process-chat-media` already uses for chat
  /// thumbnails.
  Future<String> _buildThumbnail(CapturedMedia prepared) async {
    if (prepared.type == CapturedMediaType.image) {
      final thumb = await _thumbnailPreparer().prepare(prepared.path);
      return thumb.file.path;
    }

    // Video: grab a frame, then run it through the SAME 400px/q75 image
    // preparer used for the photo case, so both media types produce a
    // thumbnail meeting the identical contract.
    final grabber = widget.thumbnailGrabber ?? _defaultThumbnailGrabber;
    final frameBytes = await grabber(prepared.path);
    if (frameBytes == null) {
      throw const StoryThumbnailFailed('thumbnail_frame_failed');
    }
    final rawFramePath = await _tempTargetPath('story_thumb_frame', 'jpg');
    await File(rawFramePath).writeAsBytes(frameBytes, flush: true);

    try {
      final thumb = await _thumbnailPreparer().prepare(rawFramePath);
      return thumb.file.path;
    } finally {
      await _deleteQuietly(rawFramePath);
    }
  }

  /// The 400px/q75 thumbnail policy (spec §4.3), always its own
  /// [CaptureImagePreparer] instance — never [widget.imagePreparerFactory],
  /// which is the MAIN image policy forwarded to [CaptureCameraScreen].
  CaptureImagePreparer _thumbnailPreparer() =>
      (widget.thumbnailPreparerFactory ??
          () => const CaptureImagePreparer(
            maxDimension: _thumbnailMaxDimension,
            maxBytes: _thumbnailMaxBytes,
            // A single fixed quality, not the main-image ladder: the
            // spec's thumbnail policy is one number (q75), and at 400px a
            // JPEG comes in far under 800KB at that quality regardless,
            // so there is no need to hunt down the ladder.
            qualityLadder: [_thumbnailQuality],
            fallbackQuality: _thumbnailQuality,
          ))();

  Future<Uint8List?> _defaultThumbnailGrabber(String videoPath) {
    return video_thumb.VideoThumbnail.thumbnailData(
      video: videoPath,
      timeMs: 0,
      quality: 90,
    );
  }

  String _mimeTypeFor(CapturedMediaType type) => switch (type) {
    CapturedMediaType.image => 'image/jpeg',
    CapturedMediaType.video => 'video/mp4',
  };

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

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup of the raw frame-grab; not worth failing the
      // post over.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Embedded exactly like StreakCameraScreen: CaptureCameraScreen owns
    // the whole viewfinder, permissions, gestures and its own busy state
    // while confirmSend runs (isSending, driven from inside that screen).
    // There is no preview/review layer to stack on top of it here — the
    // outbox queue is the review (spec §6.1).
    return CaptureCameraScreen(
      key: _captureKey,
      allow: CaptureKinds.photoAndVideo,
      videoPreparerFactory: widget.videoPreparerFactory,
      imagePreparerFactory: widget.imagePreparerFactory,
      onCaptured: _onCaptured,
      onCancelled: _onCaptureCancelled,
    );
  }
}
