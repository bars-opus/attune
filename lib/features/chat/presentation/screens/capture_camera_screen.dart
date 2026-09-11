import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/features/chat/presentation/widgets/streak_lock_hint.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Which kinds of media a [CaptureCameraScreen] instance may capture.
///
/// Only [videoOnly] exists today. Task 3 (spec §6.2/§6.3) adds
/// [photoAndVideo] alongside `takePicture()` and a tap/hold gesture split;
/// this screen must not grow that behaviour before then, so every capture
/// path below assumes video.
enum CaptureKinds { videoOnly, photoAndVideo }

/// Destination-neutral capture: permissions, camera switching, segment
/// recording, the ticker, transcode through [ChatVideoPreparer] and the
/// 25MB ceiling.
///
/// Extracted from `StreakCameraScreen` (spec §6: "extract, do not
/// branch") — this screen knows nothing about a [Conversation], a chat
/// outbox, or streak sounds/copy. Whatever review UI and send flow a
/// destination wants is entirely up to the caller; this screen only ever
/// hands back a [CapturedMedia] (or reports a cancellation) and, when a
/// caller wants to send it, transcodes on demand.
///
/// Two ways to use it:
///  - Pushed on its own (`Navigator.push<CapturedMedia>`): a completed
///    capture is transcoded immediately and pops with the result;
///    `null` means cancelled. No review step of its own.
///  - Embedded in a parent's own build, holding this state via a
///    [GlobalKey] (e.g. `StreakCameraScreen`, which wants its own review
///    sheet BEFORE anything is transcoded — matching the shipped
///    streak flow, where a rejected transcode must leave the review
///    already-closed camera on screen rather than never opening it).
///    Pass [onCaptured] / [onCancelled]; capture reports the RAW file
///    there, and the embedder calls [CaptureCameraScreenState.confirmSend]
///    only once its own review step accepts the take.
class CaptureCameraScreen extends ConsumerStatefulWidget {
  const CaptureCameraScreen({
    super.key,
    this.allow = CaptureKinds.videoOnly,
    this.videoPreparerFactory,
    this.onCaptured,
    this.onCancelled,
    this.isReviewing = false,
  });

  /// Task 3 seam (spec §6.3): video-only today, deliberately. Nothing in
  /// this screen branches on it yet.
  final CaptureKinds allow;

  /// Test seam, mirroring ChatTextField's `recorderFactory`: defaults to
  /// the real [ChatVideoPreparer] constructor. video_compress has no
  /// platform channel on a test host, so `prepare()` always rejects there
  /// — this lets a characterization test observe the success path too.
  final ChatVideoPreparer Function()? videoPreparerFactory;

  /// When set, a completed capture is reported here (as the RAW file,
  /// not yet transcoded) instead of this screen transcoding and popping
  /// the Navigator itself — an embedding adapter owns what happens next.
  final ValueChanged<CapturedMedia>? onCaptured;

  /// When set, a cancelled/discarded capture is reported here instead of
  /// popping the Navigator.
  final VoidCallback? onCancelled;

  /// True while an embedding adapter is showing its own review UI over
  /// this screen (e.g. a preview player and a send/cancel sheet).
  /// Mirrors the pre-extraction screen's `preview != null` gate: hides
  /// the close/flip controls and the record button, since a review step
  /// owns the screen at that point. Ignored when this screen manages its
  /// own Navigator pop (no [onCaptured] set) — there is no review step
  /// to hide behind.
  final bool isReviewing;

  @override
  ConsumerState<CaptureCameraScreen> createState() =>
      CaptureCameraScreenState();
}

class CaptureCameraScreenState extends ConsumerState<CaptureCameraScreen> {
  late final RecordingHaptics _recordingHaptics;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _permissionError;

  final List<StreakSegment> _segments = [];
  bool _isRecording = false;
  Duration _segmentElapsed = Duration.zero;
  Timer? _ticker;

  /// When the current segment started, read from `package:clock`'s
  /// `clock.now()` rather than `DateTime.now()` directly. In production
  /// (no active `withClock` zone) the two are identical; a widget test
  /// running inside `FakeAsync` (as `testWidgets` bodies do) installs its
  /// own `Clock`, so `clock.now()` tracks the FAKE clock `tester.pump
  /// (duration)` advances instead of real wall-clock time. That is what
  /// lets streak_camera_contract_test.dart drive a full press-hold-
  /// release-review-send take without `tester.runAsync()` for the
  /// elapsed-time computation: a real-clock wait here needed the real
  /// event loop to actually run, which starves under a full parallel
  /// `flutter test` run and intermittently exceeds the framework's
  /// per-test timeout — the regression a full-suite run caught that no
  /// single-file run could reproduce.
  DateTime? _segmentStartedAt;

  /// True while a captured take is being transcoded/sent. The gesture
  /// can end inside the press-start window too (see _onPressStart), and
  /// dropping that flag would leave the camera recording with no UI
  /// attached (the bug fixed in 511f4665) -- so it also briefly covers
  /// that window.
  bool _isSending = false;

  /// Locked recordings continue after the finger lifts, and are stopped
  /// by tapping the stop button instead.
  bool _isLocked = false;

  /// 0..1 of the way to the lock threshold, driving the hint's animation.
  double _lockDrag = 0;

  bool _startInFlight = false;
  bool _releasedDuringStart = false;

  static const Duration _tick = Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _recordingHaptics = ref.read(recordingHapticsProvider);
    // iOS suppresses haptics by default while audio input is active. Enable
    // before the camera owns the audio session so lock, stop and a quick
    // second take all remain tactile on a physical device.
    unawaited(_recordingHaptics.enable());
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _permissionError = 'No camera available.');
        return;
      }
      await _startPreview();
    } on CameraException {
      if (mounted) {
        setState(
          () =>
              _permissionError =
                  'Attune needs camera access to record a streak.',
        );
      }
    }
  }

  Future<void> _startPreview() async {
    if (_cameras.isEmpty) return;
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      // A streak is someone talking to their partner: a muted format
      // removes most of what makes it worth sending.
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _flipCamera() async {
    final controller = _controller;
    if (controller == null || _cameras.length < 2) return;

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    // While recording, swap the lens in place. Disposing and recreating
    // the controller would end the take -- setDescription routes to
    // setDescriptionWhileRecording, which both camera_avfoundation and
    // camera_android_camerax implement.
    if (_isRecording) {
      try {
        await controller.setDescription(_cameras[_cameraIndex]);
      } on CameraException catch (error) {
        // Not fatal: the take continues on the lens it was already using.
        ChatLog.diagnostic('streak flip while recording failed', error);
      }
      if (mounted) setState(() {});
      return;
    }

    await controller.dispose();
    _controller = null;
    await _startPreview();
  }

  Future<void> _onPressStart() async {
    final controller = _controller;
    if (controller == null || _isRecording || _startInFlight) return;

    // _isSending gates a real upload, but it is set before the transcode
    // and cleared on several paths -- if any of them is missed the camera
    // becomes permanently unable to record, with no error and no way back
    // except leaving the screen. Recover rather than refuse: nothing is
    // staged at this point, so there is no in-flight send to protect.
    if (_isSending) {
      ChatLog.diagnostic('streak press while sending', 'clearing stale flag');
      setState(() => _isSending = false);
    }

    _startInFlight = true;
    _releasedDuringStart = false;

    try {
      // Camera plugins may reconfigure AVAudioSession between takes. Refresh
      // the permission immediately before each recording rather than relying
      // only on the screen-entry call.
      await _recordingHaptics.enable();
      await controller.startVideoRecording();
      // startVideoRecording may itself reconfigure AVAudioSession. Reassert
      // after that transition so haptics are permitted by the session that
      // is actually consuming microphone input.
      await _recordingHaptics.enable();
    } on CameraException {
      _startInFlight = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start recording.')),
      );
      return;
    }

    if (!mounted) {
      _startInFlight = false;
      return;
    }

    setState(() {
      _isRecording = true;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = clock.now();
    });
    _startTicker();
    _startInFlight = false;

    // The finger came up while startVideoRecording() was still awaiting.
    // Without this the release handler already returned (it saw
    // _isRecording == false) and nothing would ever stop the camera.
    if (_releasedDuringStart) {
      _releasedDuringStart = false;
      await _onPressEnd();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (_) {
      if (!mounted || !_isRecording) return;
      final started = _segmentStartedAt;
      if (started == null) return;

      final elapsed = clock.now().difference(started);
      setState(() => _segmentElapsed = elapsed);

      if (StreakRecordingSession.shouldSplitAt(elapsed)) {
        unawaited(_splitSegment());
      }
    });
  }

  /// Closes the current segment and immediately opens the next, unless the
  /// cap has been reached — in which case recording stops and the capture
  /// is reported.
  Future<void> _splitSegment() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;

    // Suspend the ticker's split check while this runs, or a slow stop
    // lets a second split fire against a controller already stopping.
    _segmentStartedAt = null;

    final file = await controller.stopVideoRecording();
    _segments.add(
      StreakSegment(path: file.path, duration: kStreakSegmentDuration),
    );

    if (StreakRecordingSession.shouldStopAt(_segments.length)) {
      _ticker?.cancel();
      if (mounted) setState(() => _isRecording = false);
      ref.read(hapticsProvider).medium();
      // The camera has stopped before the capture is reported, so
      // nothing recorded after this point can leak into the take a
      // caller is about to review.
      _reportCaptured();
      return;
    }

    await controller.startVideoRecording();
    if (!mounted) return;
    ref.read(hapticsProvider).selection();
    setState(() {
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = clock.now();
    });
  }

  Future<void> _onPressEnd() async {
    // Released before startVideoRecording() finished: remember it, and
    // _onPressStart finishes as soon as there is a recording to finish.
    if (_startInFlight) {
      _releasedDuringStart = true;
      return;
    }
    if (!_isRecording) return;

    // Locking is precisely the promise that lifting a finger does not end
    // the take. The stop button owns that from here.
    if (_isLocked) return;

    final controller = _controller;
    if (controller == null) return;

    _ticker?.cancel();
    final held = _segmentElapsed;
    final file = await controller.stopVideoRecording();
    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isLocked = false;
      _lockDrag = 0;
    });

    if (StreakRecordingSession.shouldDiscard(
      completedSegments: _segments.length,
      held: held,
    )) {
      await _discardAll(extra: file.path);
      _reportCancelled();
      return;
    }

    // A partial final segment is kept: it is what the user recorded, and
    // dropping it would make the last thing they said disappear.
    _segments.add(StreakSegment(path: file.path, duration: held));
    _reportCaptured();
  }

  /// Ends a locked take.
  ///
  /// Separate from _onPressEnd, which returns early while locked -- that
  /// guard is what lets the finger lift, and routing the stop button
  /// through it made stopping impossible until the 60s cap fired.
  Future<void> _stopLockedRecording() async {
    if (!_isRecording || !_isLocked) return;
    setState(() => _isLocked = false);
    await _onPressEnd();
  }

  /// Reports the just-recorded (RAW, not yet transcoded) segment as a
  /// [CapturedMedia] — via [CaptureCameraScreen.onCaptured] if an
  /// embedder is watching, otherwise by transcoding it immediately and
  /// popping this route with the result (the standalone-push contract).
  void _reportCaptured() {
    if (_segments.isEmpty) return;
    final segment = _segments.first;
    final size = _controller?.value.previewSize;
    final media = CapturedMedia(
      path: segment.path,
      type: CapturedMediaType.video,
      width: size?.width.round() ?? 0,
      height: size?.height.round() ?? 0,
      durationMs: segment.duration.inMilliseconds,
    );
    _segments.clear();

    final onCaptured = widget.onCaptured;
    if (onCaptured != null) {
      onCaptured(media);
      return;
    }
    unawaited(_transcodeAndPopGuarded(media));
  }

  /// The standalone-push contract: transcode right away (there is no
  /// embedder to defer that decision to) and pop with the result.
  Future<void> _transcodeAndPopGuarded(CapturedMedia raw) async {
    try {
      final prepared = await confirmSend(raw);
      if (mounted) context.pop(prepared);
    } on ChatVideoRejected catch (rejected) {
      ChatLog.diagnostic('capture prepare rejected', rejected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
    } catch (error, stack) {
      ChatLog.diagnostic('capture failed', '$error\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That could not be captured.')),
      );
    }
  }

  /// Transcodes [raw] through [ChatVideoPreparer], enforcing the 25MB
  /// ceiling, and returns the prepared [CapturedMedia].
  ///
  /// Public so an embedding adapter calls this itself, at the moment ITS
  /// OWN review step accepts the take — not at capture completion. This
  /// is deliberate: the shipped streak flow opens its review sheet on
  /// the RAW clip and only transcodes once Send is tapped, so a rejected
  /// transcode is discovered with the sheet already closed and the
  /// camera on screen, never before the sheet had a chance to open.
  /// Manages [_isSending] itself, so the record button (owned by this
  /// screen) still becomes the busy indicator during the embedder's
  /// send, exactly as it did pre-extraction.
  ///
  /// Throws [ChatVideoRejected] on a rejected transcode; the caller
  /// decides what to show for that (this screen shows its own message
  /// only on the standalone-push path, via [_transcodeAndPopGuarded]).
  Future<CapturedMedia> confirmSend(CapturedMedia raw) async {
    if (mounted) setState(() => _isSending = true);
    try {
      final prepared = await (widget.videoPreparerFactory ??
              ChatVideoPreparer.new)()
          .prepare(
            localPath: raw.path,
            maxDuration: kStreakSegmentDuration,
            maxBytes: 25 * 1024 * 1024,
          );
      ChatLog.diagnostic('capture prepared', '${prepared.byteSize}B');
      return CapturedMedia(
        path: prepared.file.path,
        type: CapturedMediaType.video,
        width: prepared.width,
        height: prepared.height,
        durationMs: prepared.durationMs,
      );
    } finally {
      // Cleared on every path -- success reports out through the
      // caller's own send flow, but the button must not stay busy
      // forever if that caller decides to stay on this screen (e.g. a
      // rejected transcode, or an embedder returning to a live
      // viewfinder after its own review is cancelled).
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _reportCancelled() {
    final onCancelled = widget.onCancelled;
    if (onCancelled != null) {
      onCancelled();
      return;
    }
    if (mounted) context.pop();
  }

  /// Back to a live camera with nothing staged.
  ///
  /// Public so an embedding adapter (holding this state via a
  /// [GlobalKey]) can return to a fresh viewfinder after its own review
  /// step is cancelled — mirrors what popping-and-reopening this screen
  /// would produce for a standalone push.
  Future<void> reset() async {
    await _discardAll();
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = null;
    });
  }

  /// Discards anything staged and leaves the camera.
  Future<void> _closeCamera() async {
    // Stop the camera first: popping with a recording still running
    // leaves the controller writing to a file nobody will ever read.
    if (_isRecording) {
      _ticker?.cancel();
      _isLocked = false;
      try {
        await _controller?.stopVideoRecording();
      } on CameraException {
        // Already stopped, or the controller is gone. Either way the
        // screen is closing.
      }
      if (mounted) setState(() => _isRecording = false);
    }
    await _discardAll();
    _reportCancelled();
  }

  /// Deletes every staged file. A recorded-but-unsent capture must leave
  /// nothing behind.
  Future<void> _discardAll({String? extra}) async {
    for (final segment in _segments) {
      await _deleteQuietly(segment.path);
    }
    if (extra != null) await _deleteQuietly(extra);
    _segments.clear();
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A staged file we cannot delete is not worth failing the flow for;
      // the OS clears the temp directory.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    unawaited(_recordingHaptics.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(body: Center(child: Text(_permissionError!)));
    }
    final controller = _controller;
    final progress =
        _segmentElapsed.inMilliseconds / kStreakSegmentDuration.inMilliseconds;
    final reviewing = widget.onCaptured != null && widget.isReviewing;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            // Cover-crop rather than stretch: a bare CameraPreview in a
            // StackFit.expand Stack scales the sensor image to the
            // screen's shape and elongates everything.
            LayoutBuilder(
              builder: (context, constraints) {
                final previewRatio = 1 / controller.value.aspectRatio;
                return ClipRect(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxWidth / previewRatio,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                );
              },
            ),

          // The lock affordance, above the button. Gone once locked: it
          // has served its purpose and the stop button says the rest.
          if (_isRecording && !_isLocked)
            Positioned(
              left: 0,
              right: 0,
              bottom: Spacing.xxl * 2 + 168,
              child: Center(child: StreakLockHint(dragProgress: _lockDrag)),
            ),

          // Elapsed seconds, centred. A streak is capped at a minute, so
          // the number itself is the whole story — no bar, no ring, just
          // how long you have been talking. Rolls rather than jumps so a
          // glance registers the change without re-reading the digits.
          if (_isRecording)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedRollingCounter(
                    key: const ValueKey('streak-elapsed'),
                    count: _segmentElapsed.inSeconds,
                    suffix: 's',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        // The viewfinder behind this is arbitrary, so
                        // the digits need their own contrast.
                        Shadow(blurRadius: 12, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Segment previews, only once a SECOND segment exists — a lone
          // thumbnail for a lone clip is noise.
          if (StreakRecordingSession.showPreviews(_segments.length))
            Positioned(
              top: 56,
              right: 16,
              child: Column(
                children: [
                  for (var i = 0; i < _segments.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      width: 44,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white70),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Leaving the camera is now explicit: cancel returns to a live
          // viewfinder rather than exiting, so without this there would be
          // no way out once a take is staged.
          // Both hidden while an embedder's review step owns the screen,
          // or while a take is being sent: closing or flipping mid-decision
          // would either discard the take silently or spin up a camera
          // nobody is looking at.
          // Hidden entirely rather than shown disabled: a control the
          // user can see and press to no effect invites the tap and then
          // ignores it, which reads as the app being broken.
          //
          // Close survives a LOCKED take -- nothing is holding it, so it
          // must stay abandonable -- but goes while a finger is down,
          // where the gesture owns the screen. Both go during review and
          // during the send.
          if (!reviewing && !_isSending) ...[
            if (!_isRecording || _isLocked)
              // Below the status bar and notch rather than tight against the
              // top edge, and a larger target: these are the only two controls
              // on a full-bleed viewfinder.
              Positioned(
                top: Spacing.xxl,
                left: Spacing.md,
                child: IconButton(
                  iconSize: 32,
                  onPressed: _closeCamera,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Close camera',
                ),
              ),

            Positioned(
              top: Spacing.xxl,
              right: Spacing.md,
              child: IconButton(
                iconSize: 32,
                // Enabled DURING recording too: the camera plugin supports
                // switching lenses mid-take on both platforms, and turning
                // the camera round without stopping is most of the point of
                // a hands-free streak.
                onPressed: _flipCamera,
                icon: const Icon(
                  Icons.flip_camera_ios_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ],

          // No blocking overlay: the record button itself becomes the
          // loading indicator while sending, and refuses presses, so a
          // second spinner would only compete with it.
          Positioned(
            left: 0,
            right: 0,
            // Clear of the home indicator and the very bottom edge, where
            // the ring sat awkwardly close to the screen's edge.
            bottom: Spacing.xxl * 2,
            child: Center(
              child:
                  // Hidden while an embedder's review step owns the
                  // screen -- but shown again during the send, where the
                  // ring is the only progress the user gets. Keying on
                  // `reviewing` alone would hide it for the whole upload.
                  reviewing && !_isSending
                      ? const SizedBox.shrink()
                      : Listener(
                        // Tracked here rather than on the button so the
                        // finger can travel well past it and still be
                        // followed -- the lock target sits above the
                        // button, outside its own hit box.
                        onPointerMove: (event) {
                          if (!_isRecording || _isLocked) return;
                          final next = (_lockDrag -
                                  event.delta.dy / kStreakLockDragDistance)
                              .clamp(0.0, 1.0);
                          if (next >= 1.0) {
                            ref.read(hapticsProvider).medium();
                            setState(() {
                              _isLocked = true;
                              _lockDrag = 1;
                            });
                            return;
                          }
                          setState(() => _lockDrag = next);
                        },
                        child: StreakRecordButton(
                          progress: progress.clamp(0.0, 1.0),
                          isRecording: _isRecording,
                          isSending: _isSending,
                          // Nothing else marks the wait: the screen is deliberately
                          // just the (black) preview until the camera is ready.
                          isPreparing:
                              controller == null ||
                              !controller.value.isInitialized,
                          onPressStart: () => unawaited(_onPressStart()),
                          onPressEnd: () => unawaited(_onPressEnd()),
                          isLocked: _isLocked,
                          onStop: () => unawaited(_stopLockedRecording()),
                          haptics: ref.read(hapticsProvider),
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
