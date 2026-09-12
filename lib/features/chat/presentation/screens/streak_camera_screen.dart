import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/screens/capture_camera_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/streak_review_sheet.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart'
    show CaptureImagePreparer, CaptureImageRejected;
import 'package:video_player/video_player.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/settings/data/sound_preference.dart';

/// Press-and-hold streak capture, auto-splitting into 60-second segments.
///
/// Deliberately separate from [EphemeralCameraScreen] rather than a mode
/// on it: that screen sends one clip immediately on release with no review
/// step, and folding two send contracts into one widget is how the release
/// path becomes ambiguous.
///
/// This screen is the streak ADAPTER (spec §6): capture itself —
/// permissions, camera switching, segment recording, the ticker,
/// transcode, the 25MB ceiling — lives in [CaptureCameraScreen], embedded
/// here rather than pushed as a separate route so this screen's own
/// widget tree (and the tests pinning it) stays exactly as it was before
/// the extraction. What stays here is everything streak-specific: the
/// `Conversation`, the review sheet, the sounds, the replay-preference
/// read, the view budget and the send through `chatControllerProvider`.
class StreakCameraScreen extends ConsumerStatefulWidget {
  const StreakCameraScreen({
    super.key,
    required this.conversation,
    this.videoPreparerFactory,
    this.imagePreparerFactory,
  });

  final Conversation conversation;

  /// Test seam, mirroring ChatTextField's `recorderFactory`: defaults to
  /// the real [ChatVideoPreparer] constructor. video_compress has no
  /// platform channel on a test host, so `prepare()` always rejects there
  /// — this lets a characterization test observe the success path too.
  /// Passed straight through to the embedded [CaptureCameraScreen], which
  /// is the half that actually calls it.
  final ChatVideoPreparer Function()? videoPreparerFactory;

  /// Test seam for the photo half (spec §6.3 step 3), mirroring
  /// [videoPreparerFactory] exactly: defaults to the real
  /// [CaptureImagePreparer] constructor. flutter_image_compress has no
  /// platform channel on a test host either, so a photo streak's own
  /// success path needs the same kind of seam the video path already had
  /// — see [StoryCameraScreen]'s identical parameter.
  final CaptureImagePreparer Function()? imagePreparerFactory;

  @override
  ConsumerState<StreakCameraScreen> createState() => _StreakCameraScreenState();
}

class _StreakCameraScreenState extends ConsumerState<StreakCameraScreen> {
  final GlobalKey<CaptureCameraScreenState> _captureKey =
      GlobalKey<CaptureCameraScreenState>();

  /// Plays back what was just captured while the send sheet is open.
  /// Reviewing over a LIVE viewfinder would show the user the room they
  /// are standing in rather than the take they are deciding on. Null for
  /// a photo take — see [_previewImagePath] instead.
  VideoPlayerController? _previewController;

  /// The captured photo's path, shown as a static image behind the review
  /// sheet exactly where [_previewController] shows a looping video for a
  /// video take. Mutually exclusive with [_previewController] — a take is
  /// always exactly one media kind.
  String? _previewImagePath;

  /// Mirrors the pre-extraction screen's `preview != null` gate on the
  /// embedded [CaptureCameraScreen]'s own close/flip/record controls.
  /// Set true as soon as a take is captured (before the preview player
  /// itself has necessarily initialized) and cleared whenever review
  /// ends, whether by cancel or by send.
  bool _isReviewing = false;

  void _playSound(AppSound sound) {
    if (!ref.read(messageSoundsEnabledProvider)) return;
    ref.read(soundServiceProvider).play(sound);
  }

  /// Called by the embedded [CaptureCameraScreen] once a take is
  /// captured (RAW, not yet transcoded — transcode happens only if Send
  /// is tapped, in [_send]). Opens the review sheet; the camera has
  /// already stopped, so this cue cannot leak into the clip under
  /// review.
  void _onCaptured(CapturedMedia media) {
    setState(() => _isReviewing = true);
    _playSound(AppSound.streakCaptureReady);
    unawaited(_openReviewGuarded(media));
  }

  /// Called by the embedded [CaptureCameraScreen] when a take is
  /// discarded outright (a stray tap too short to count) rather than
  /// reviewed — mirrors the pre-extraction `context.pop()` on that path.
  void _onCaptureCancelled() {
    if (mounted) context.pop();
  }

  /// This runs under unawaited() from [_onCaptured], so any exception
  /// escaping it disappears with no console output whatsoever — which is
  /// exactly what made a failing send look like silence.
  Future<void> _openReviewGuarded(CapturedMedia media) async {
    try {
      await _openReview(media);
    } catch (error, stack) {
      ChatLog.diagnostic('streak review failed', '$error\n$stack');
      if (!mounted) return;
      // Mirrors the pre-extraction catch here, which cleared only the
      // busy flag (then living on this screen) and left the preview/
      // review state alone -- an unexpected error in _openReview itself
      // (e.g. showModalBottomSheet throwing) should just surface the
      // message. Nothing needs unfreezing here: this can only be
      // reached before _send/confirmSend ever runs (confirmSend's own
      // `finally` clears the busy flag on every path once it starts),
      // and _isReviewing (this screen's mirror of the old
      // `preview != null` gate) is left untouched for the same reason
      // the pre-extraction catch left `preview` exactly as it was.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
    }
  }

  Future<void> _openReview(CapturedMedia media) async {
    ChatLog.diagnostic('streak review', 'path=${media.path}');
    if (!mounted) return;

    await _startPreview(media);
    if (!mounted) return;

    final send = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      // Transparent so the captured clip stays visible behind the sheet:
      // the whole point of the review is seeing what you are sending.
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => StreakReviewSheet(
            // A photo has no duration to show: Duration.zero renders as
            // "0s" in the sheet's own label, which is the correct answer
            // for "how long is this" — there is no length — rather than a
            // faked one.
            segments: [
              StreakSegment(
                path: media.path,
                duration: Duration(milliseconds: media.durationMs ?? 0),
              ),
            ],
            onSend: () => Navigator.of(sheetContext).pop(true),
            onDiscard: () => Navigator.of(sheetContext).pop(false),
          ),
    );

    if (!mounted) return;

    if (send != true) {
      // Cancel means "not that take", not "leave the camera". Reset to a
      // live viewfinder ready to record again -- popping here would make
      // a rejected take cost the user their whole session.
      await _disposePreview();
      if (mounted) setState(() => _isReviewing = false);
      await _captureKey.currentState?.reset();
      return;
    }

    // Whether replays are allowed is a persistent chat setting, read at
    // send time rather than chosen here.
    final allowReplays = ref.read(streakReplayPreferenceProvider);
    ChatLog.diagnostic('streak send start', 'replays=$allowReplays');
    await _send(media, allowReplays: allowReplays);
  }

  Future<void> _send(CapturedMedia raw, {required bool allowReplays}) async {
    // Transcode BEFORE queueing, and only now -- not at capture time.
    // _attemptSend uploads whatever path it is given verbatim, so
    // handing it raw camera output would push a file several times
    // larger than the ceiling allows. Delegated to the embedded
    // CaptureCameraScreen, which owns ChatVideoPreparer/CaptureImagePreparer
    // (confirmSend itself branches on raw.type) and also drives the record
    // button's busy state while this runs.
    final CapturedMedia prepared;
    try {
      prepared = await _captureKey.currentState!.confirmSend(raw);
    } on ChatVideoRejected catch (rejected) {
      ChatLog.diagnostic('streak prepare rejected', rejected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
      return;
    } on CaptureImageRejected catch (rejected) {
      ChatLog.diagnostic('streak photo prepare rejected', rejected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
      return;
    }
    if (!mounted) return;

    final isPhoto = prepared.type == CapturedMediaType.image;

    // Hand the clip to the outbox and leave. The upload, its retries and
    // its failure handling all belong to _attemptSend, and the optimistic
    // bubble is where the user watches it — holding them on the camera
    // through a 25MB upload bought nothing.
    ChatLog.diagnostic('streak queued', prepared.path);
    unawaited(
      ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .sendStreakMessage(
            localPath: prepared.path,
            // A photo carries no duration (spec §6.2/§4.2's own CHECK
            // constraint on messages already refuses one); stored as 0
            // rather than null so downstream int-typed reads (the
            // optimistic bubble, the outbox cache) need no new nullable
            // branch of their own for a case that already means
            // "no length" everywhere else in this pipeline.
            durationMs: isPhoto ? 0 : (prepared.durationMs ?? 0),
            viewsRemaining: streakViewBudget(allowReplays: allowReplays),
            mimeType: isPhoto ? 'image/jpeg' : 'video/mp4',
          ),
    );
    _playSound(AppSound.streakSend);

    // The staged file now belongs to the outbox, so clear the local
    // reference WITHOUT deleting it — _attemptSend still needs to read it.
    await _disposePreview();
    if (mounted) context.pop();
  }

  /// Opens the captured take for review: a looping video player for a
  /// video take, a static image for a photo take (mutually exclusive —
  /// see [_previewImagePath]'s doc comment).
  Future<void> _startPreview(CapturedMedia media) async {
    await _disposePreview();

    if (media.type == CapturedMediaType.image) {
      if (!mounted) return;
      setState(() => _previewImagePath = media.path);
      return;
    }

    final controller = VideoPlayerController.file(File(media.path));
    try {
      await controller.initialize();
    } catch (error) {
      // A preview that will not open must not block the send: the clip
      // itself is already on disk and valid.
      ChatLog.diagnostic('streak preview failed', error);
      await controller.dispose();
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    // Looping, because a clip that plays once and freezes on a black last
    // frame reads as a crash mid-review.
    await controller.setLooping(true);
    await controller.play();
    setState(() => _previewController = controller);
  }

  Future<void> _disposePreview() async {
    final controller = _previewController;
    _previewController = null;
    _previewImagePath = null;
    await controller?.dispose();
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewController;
    final imagePreview = _previewImagePath;

    return Stack(
      fit: StackFit.expand,
      children: [
        CaptureCameraScreen(
          key: _captureKey,
          // photoAndVideo (spec §6.3 step 3): a release before the hold
          // threshold now takes a photo, exactly as the story adapter's
          // camera already does — the tap/hold split itself lives in
          // CaptureCameraScreen and needed no change here.
          allow: CaptureKinds.photoAndVideo,
          videoPreparerFactory: widget.videoPreparerFactory,
          imagePreparerFactory: widget.imagePreparerFactory,
          onCaptured: _onCaptured,
          onCancelled: _onCaptureCancelled,
          isReviewing: _isReviewing,
        ),

        // The captured take, over the live camera. Same cover-crop as the
        // viewfinder so the framing the user reviews is the framing they
        // recorded.
        if (preview != null && preview.value.isInitialized)
          Positioned.fill(
            key: const ValueKey('streak-capture-preview'),
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: preview.value.size.width,
                    height: preview.value.size.height,
                    child: VideoPlayer(preview),
                  ),
                ),
              ),
            ),
          )
        else if (imagePreview != null)
          Positioned.fill(
            key: const ValueKey('streak-capture-image-preview'),
            child: ClipRect(
              child: Image.file(File(imagePreview), fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }
}
