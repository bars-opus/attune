/// The story adapter over the shared capture module (Plan B, Task 7, spec
/// §6/§6.1/§4.3) — the LAST piece tying capture to the posting outbox.
///
/// [CaptureCameraScreen] (`lib/features/chat/presentation/screens/
/// capture_camera_screen.dart`) owns everything destination-neutral:
/// permissions, camera switching, the tap/hold gesture split and the
/// lifecycle. Preparing a take to the main-media ceilings is
/// [StoryPostPipeline]'s job, on Share.
///
/// **Embedded, not pushed — mirrors [StreakCameraScreen] exactly.**
/// [CaptureCameraScreen] supports two shapes (see its own doc comment):
/// pushed standalone, where it transcodes and pops itself with the
/// result; or embedded via a [GlobalKey] with [onCaptured]/[onCancelled]
/// callbacks, where the embedder receives the RAW take and decides what
/// to do with it. This screen uses the SECOND shape, the one
/// `StreakCameraScreen` already ships with — [CaptureCameraScreen] owns
/// its `context.pop(prepared)` on the standalone path, which only
/// resolves for whatever pushed it; embedding sidesteps that seam
/// entirely; there is no nested route whose pop needs to line up with
/// anything, and no risk of a go_router `context.pop()` call failing to
/// resolve a plain `Navigator.push`ed route (a mismatch this task hit
/// and fixed by switching shapes, not by swapping which `pop` API is
/// called elsewhere).
///
/// This screen's own job (owner ruling 1, overriding spec §6.1's "the
/// outbox is the review"):
///  1. Shutter → review. The embedded camera reports the RAW take through
///     [CaptureCameraScreen.onCaptured]; this screen shows it full bleed
///     ([StoryReviewLayer]) with Retake and Share, and sets
///     [CaptureCameraScreen.isReviewing] so the camera hides its own
///     controls. Nothing is prepared or queued yet.
///  2. Retake deletes the take and returns to a live viewfinder. Close (or
///     back) asks before discarding it.
///  3. Share hands the take to [StoryPostPipeline] (a provider, so it
///     survives this screen unmounting mid-prepare, 01 #14): prepare to
///     the main-media policy, build the required thumbnail (spec §4.3),
///     read the pin (bounded at 3 s), move both files into the vault and
///     enqueue. The upload and its retries belong to the outbox. While
///     sharing, Close is hidden and back is blocked.
///  4. Queued → pop. A take rejected for itself (too long, unreadable)
///     says why and returns to the live camera; a transient failure (an
///     interrupted export) or a keystore refusal stays on the review so
///     Share can be tried again.
library;

export 'package:attune/features/stories/presentation/state/story_post_pipeline.dart'
    show StoryThumbnailFailed;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/services/media/visible_only_playback.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/capture_camera_screen.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_toggle.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:attune/features/stories/presentation/widgets/story_review_layer.dart';
import 'package:camera/camera.dart' show ResolutionPreset;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

class StoryCameraScreen extends ConsumerStatefulWidget {
  const StoryCameraScreen({
    super.key,
    required this.relationshipId,
    this.videoPreparerFactory,
    this.imagePreparerFactory,
    this.thumbnailPreparerFactory,
    this.thumbnailGrabber,
    this.utcOffsetMinutesReader,
  });

  /// Which relationship this capture posts to. Stories have no
  /// destination-picker (spec §2: "audience is the partner, always"), so
  /// this is the only routing information the adapter needs.
  final String relationshipId;

  /// Test seam for the video prepare step, passed to [StoryPostPipeline]
  /// (and forwarded to the embedded [CaptureCameraScreen], which does not
  /// prepare in the embedded shape). Null uses
  /// [StoryPostPipeline.storyVideoPreparer].
  final ChatVideoPreparer Function()? videoPreparerFactory;

  /// Test seam for the MAIN image prepare step (2560px/5MB, spec §4.2),
  /// passed to [StoryPostPipeline]. The thumbnail step always builds its
  /// own [CaptureImagePreparer] at the 400px/q75 policy — this factory is
  /// never reused for it, so overriding one never silently changes the
  /// other's numbers.
  final CaptureImagePreparer Function()? imagePreparerFactory;

  /// Test seam for the thumbnail-policy [CaptureImagePreparer] itself
  /// (400px/q75, spec §4.3), separate from [imagePreparerFactory] above
  /// for the reason stated there. Defaults to a real instance constructed
  /// with the thumbnail policy.
  final CaptureImagePreparer Function()? thumbnailPreparerFactory;

  /// Test seam for the video frame grab [StoryPostPipeline] uses to build
  /// a video's thumbnail source frame. `video_thumbnail`'s platform channel
  /// has no implementation on a test host (the same gap
  /// [ChatVideoPreparer]'s own `VideoThumbnail.thumbnailData` call hits),
  /// so a widget test cannot exercise the real grab — this seam lets one
  /// substitute a fake JPEG frame instead. Defaults to the real
  /// `video_thumbnail` call. Documented here rather than restructuring
  /// shipped code: this is new code in this task, so the seam belongs on
  /// it directly.
  final Future<Uint8List?> Function(String videoPath)? thumbnailGrabber;

  /// Test seam for "utcOffsetMinutes comes from the device at capture
  /// time" (the brief, verbatim). Defaults to the real
  /// `DateTime.now().timeZoneOffset.inMinutes` read. Without this seam a
  /// test asserting the record's offset can only recompute the same
  /// device call production makes — which degenerates to `expect(0, 0)`
  /// on any UTC host (this one and most CI included) and proves nothing.
  /// Injecting a fixed value here lets a test assert the record actually
  /// carries WHATEVER this reader returns, independent of the host's
  /// real timezone in either direction.
  final int Function()? utcOffsetMinutesReader;

  @override
  ConsumerState<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends ConsumerState<StoryCameraScreen> {
  final GlobalKey<CaptureCameraScreenState> _captureKey =
      GlobalKey<CaptureCameraScreenState>();

  /// The couple map's "Pin to our map" switch, when the map is enabled.
  StoryPinController? _pin;

  /// The raw take on review (not yet prepared or queued), if any.
  CapturedMedia? _review;

  /// A looping preview of a video take; null for a photo or until it opens.
  VideoPlayerController? _preview;

  /// The preview loops only while Attune is on screen (stories Wave 3).
  late final VisibleOnlyPlayback _previewPlayback = VisibleOnlyPlayback(
    isVisible: () => ref.read(appContentVisibleProvider),
  );

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _previewPlayback.onVisibility(visible),
    );
  }

  /// Share was tapped and the pipeline is running: Close hidden, back
  /// blocked, a second Share ignored (Review Focus 5).
  bool _posting = false;

  /// Called by the embedded [CaptureCameraScreen] with the RAW take.
  void _onCaptured(CapturedMedia raw) {
    // One take at a time (Review Focus 5): a second report while a review
    // is up is dropped and its file deleted, never leaked.
    if (_review != null || _posting || !mounted) {
      unawaited(_deleteQuietly(raw.path));
      return;
    }
    setState(() => _review = raw);
    unawaited(_startPreview(raw));
  }

  /// Called by the embedded [CaptureCameraScreen] when the user closes the
  /// camera without a take.
  void _onCaptureCancelled() {
    if (mounted) context.pop();
  }

  Future<void> _startPreview(CapturedMedia raw) async {
    if (raw.type != CapturedMediaType.video) return;
    final controller = VideoPlayerController.file(File(raw.path));
    try {
      await controller.initialize();
      await controller.setLooping(true);
    } catch (error) {
      // The review still offers Share with a placeholder.
      ChatLog.diagnostic('story review preview failed', error);
      await controller.dispose();
      return;
    }
    if (!mounted || !identical(_review, raw)) {
      await controller.dispose();
      return;
    }
    setState(() => _preview = controller);
    _previewPlayback.start(controller);
  }

  Future<void> _disposePreview() async {
    _previewPlayback.clear();
    final controller = _preview;
    _preview = null;
    await controller?.dispose();
  }

  Future<void> _retake() async {
    final raw = _review;
    if (raw == null || _posting) return;
    await _disposePreview();
    await _deleteQuietly(raw.path);
    if (!mounted) return;
    setState(() => _review = null);
    await _captureKey.currentState?.reset();
  }

  /// Close or back during review: the take has not been shared, so ask.
  Future<void> _closeFromReview() async {
    final raw = _review;
    if (raw == null || _posting) return;
    final noun = raw.type == CapturedMediaType.image ? 'photo' : 'video';
    final discard = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Discard this $noun?'),
            content: const Text("It hasn't been shared."),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
    );
    // A Share that started while the dialog was up wins.
    if (discard != true || !mounted || _posting || !identical(_review, raw)) {
      return;
    }
    await _disposePreview();
    await _deleteQuietly(raw.path);
    if (!mounted) return;
    setState(() => _review = null);
    context.pop();
  }

  Future<void> _share() async {
    final raw = _review;
    if (raw == null || _posting) return; // Review Focus 5
    // Captured before the first await: the camera may unmount below.
    final pipeline = ref.read(storyPostPipelineProvider);
    final messenger = ScaffoldMessenger.of(context);
    final pin = _pin;
    setState(() => _posting = true);
    StoryPostOutcome outcome;
    try {
      outcome = await pipeline.post(
        StoryPostRequest(
          raw: raw,
          relationshipId: widget.relationshipId,
          utcOffsetMinutes:
              (widget.utcOffsetMinutesReader ??
                  _defaultUtcOffsetMinutesReader)(),
          place: pin?.placeForPost,
          videoPreparer: widget.videoPreparerFactory,
          imagePreparer: widget.imagePreparerFactory,
          thumbnailPreparer: widget.thumbnailPreparerFactory,
          thumbnailGrabber: widget.thumbnailGrabber,
        ),
        callerListening: () => mounted,
      );
    } catch (error, stack) {
      // The pipeline reports its own failures; this only keeps the screen
      // from being stuck with back blocked if something unexpected escapes.
      ChatLog.diagnostic('story share failed', '$error\n$stack');
      outcome = const StoryPostRejected('capture_failed');
    }
    if (!mounted) {
      // The pipeline already queued it or raised a notice. A take it kept
      // for another Share (NotSaved, a retryable rejection: the camera was
      // still listening when it decided) has nobody to show it now: delete
      // it, never leave raw plaintext in tmp/ (final review #1).
      unawaited(_deleteQuietly(raw.path));
      return;
    }
    switch (outcome) {
      case StoryPostQueued(:final placeDropped):
        await _disposePreview();
        if (!mounted) return;
        setState(() {
          _review = null;
          _posting = false;
        });
        context.pop();
        if (placeDropped) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                "Shared without a place. We couldn't find where you are in time.",
              ),
            ),
          );
        }
      case StoryPostNotSaved():
        setState(() => _posting = false);
        messenger.showSnackBar(
          const SnackBar(content: Text('That could not be saved. Try again.')),
        );
      case StoryPostRejected(retryable: true):
        // Not about the take (an interrupted export, say): it was kept, so
        // the review stays up with Share ready (batch-7 review I3).
        setState(() => _posting = false);
        messenger.showSnackBar(
          SnackBar(content: Text(storyPrepareRetryMessage(raw.type))),
        );
      case StoryPostRejected(:final code):
        messenger.showSnackBar(
          SnackBar(content: Text(storyPrepareFailureMessage(code, raw.type))),
        );
        await _disposePreview();
        if (!mounted) return;
        setState(() {
          _review = null;
          _posting = false;
        });
        await _captureKey.currentState?.reset();
    }
  }

  /// utcOffsetMinutes comes from the device at capture time (the brief,
  /// verbatim). This is the real production read; [widget.utcOffsetMinutesReader]
  /// overrides it for tests.
  int _defaultUtcOffsetMinutesReader() =>
      DateTime.now().timeZoneOffset.inMinutes;

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup of a discarded take.
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    // Torn down without Close or Share (quick exit, a sign-out redirect, a
    // route replaced): the take on the review is raw plaintext in tmp/, so
    // it goes with the screen (final review #1). While posting, the
    // pipeline owns the file (its callerListening check deletes it once
    // this screen is gone), and _share's unmounted branch covers a take it
    // kept.
    final raw = _review;
    if (raw != null && !_posting) unawaited(_deleteQuietly(raw.path));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return PopScope(
      canPop: review == null && !_posting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _posting) return;
        unawaited(_closeFromReview());
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: CaptureCameraScreen(
              key: _captureKey,
              allow: CaptureKinds.photoAndVideo,
              // Stories show full screen: 640×480 (`medium`) is visibly soft.
              resolutionPreset: ResolutionPreset.veryHigh,
              // A refused microphone still leaves photos (01 #6).
              microphoneOptional: true,
              copy: CaptureCameraCopy.story,
              // The shared camera hides its controls under the review.
              isReviewing: review != null,
              videoPreparerFactory: widget.videoPreparerFactory,
              imagePreparerFactory: widget.imagePreparerFactory,
              onCaptured: _onCaptured,
              onCancelled: _onCaptureCancelled,
            ),
          ),
          if (review != null)
            Positioned.fill(
              child: StoryReviewLayer(
                media: review,
                videoController: _preview,
                posting: _posting,
                onShare: () => unawaited(_share()),
                onRetake: () => unawaited(_retake()),
                onClose: () => unawaited(_closeFromReview()),
              ),
            ),
          // "Pin to our map" (couple map): on the live camera and on the
          // review, read when Share is tapped. Renders nothing with the map
          // off. Kept mounted while sharing (hidden and inert), so a failed
          // share brings back the same switch with no second lookup or
          // prompt. Keyed: the review slot above appears and goes, and an
          // unkeyed pill would be rebuilt fresh (a second lookup, its state
          // lost) every time it shifts position in this Stack.
          Positioned(
            key: const ValueKey('story-pin-slot'),
            top: Spacing.xxl,
            left: 64,
            right: 64,
            child: Offstage(
              offstage: _posting,
              child: IgnorePointer(
                ignoring: _posting,
                child: Center(
                  child: StoryPinToggle(
                    relationshipId: widget.relationshipId,
                    onController: (c) => _pin = c,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
