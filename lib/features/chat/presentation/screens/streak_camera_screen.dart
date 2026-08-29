import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/chat/presentation/widgets/streak_review_sheet.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:video_player/video_player.dart';
import 'package:attune/features/chat/presentation/widgets/streak_lock_hint.dart';

/// Press-and-hold streak capture, auto-splitting into 60-second segments.
///
/// Deliberately separate from [EphemeralCameraScreen] rather than a mode
/// on it: that screen sends one clip immediately on release with no review
/// step, and folding two send contracts into one widget is how the release
/// path becomes ambiguous.
class StreakCameraScreen extends ConsumerStatefulWidget {
  const StreakCameraScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<StreakCameraScreen> createState() => _StreakCameraScreenState();
}

class _StreakCameraScreenState extends ConsumerState<StreakCameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _permissionError;

  final List<StreakSegment> _segments = [];
  bool _isRecording = false;
  Duration _segmentElapsed = Duration.zero;
  Timer? _ticker;
  DateTime? _segmentStartedAt;

  /// True between the press and startVideoRecording() completing. The
  /// gesture can end inside that window, and dropping it would leave the
  /// camera recording with no UI attached (the bug fixed in 511f4665).
  bool _isSending = false;

  /// Plays back what was just captured while the send sheet is open.
  /// Reviewing over a LIVE viewfinder would show the user the room they
  /// are standing in rather than the take they are deciding on.
  VideoPlayerController? _previewController;

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
    if (controller == null || _isRecording || _startInFlight || _isSending) {
      return;
    }

    _startInFlight = true;
    _releasedDuringStart = false;

    try {
      await controller.startVideoRecording();
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
      _segmentStartedAt = DateTime.now();
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

      final elapsed = DateTime.now().difference(started);
      setState(() => _segmentElapsed = elapsed);

      if (StreakRecordingSession.shouldSplitAt(elapsed)) {
        unawaited(_splitSegment());
      }
    });
  }

  /// Closes the current segment and immediately opens the next, unless the
  /// cap has been reached — in which case recording stops and review opens
  /// with everything captured.
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
      unawaited(HapticFeedback.heavyImpact());
      unawaited(_openReviewGuarded());
      return;
    }

    await controller.startVideoRecording();
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = DateTime.now();
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
      if (mounted) context.pop();
      return;
    }

    // A partial final segment is kept: it is what the user recorded, and
    // dropping it would make the last thing they said disappear.
    _segments.add(StreakSegment(path: file.path, duration: held));
    unawaited(_openReviewGuarded());
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

  /// Offers send or cancel. A streak must not fly away the instant a
  /// finger lifts — a mis-hold would otherwise be unrecallable.
  /// Wraps the review flow so nothing is lost.
  ///
  /// This runs under unawaited() from the gesture handlers, so any
  /// exception escaping it disappears with no console output whatsoever —
  /// which is exactly what made a failing send look like silence.
  Future<void> _openReviewGuarded() async {
    try {
      await _openReview();
    } catch (error, stack) {
      ChatLog.diagnostic('streak review failed', '$error\n$stack');
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
    }
  }

  Future<void> _openReview() async {
    ChatLog.diagnostic('streak review', 'segments=${_segments.length}');
    if (!mounted || _segments.isEmpty) return;

    await _startPreview_(_segments.first.path);
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
            segments: _segments,
            onSend: () => Navigator.of(sheetContext).pop(true),
            onDiscard: () => Navigator.of(sheetContext).pop(false),
          ),
    );

    if (!mounted) return;

    if (send != true) {
      // Cancel means "not that take", not "leave the camera". Reset to a
      // live viewfinder ready to record again -- popping here would make
      // a rejected take cost the user their whole session.
      await _resetCapture();
      return;
    }

    // Whether replays are allowed is a persistent chat setting, read at
    // send time rather than chosen here.
    final allowReplays = ref.read(streakReplayPreferenceProvider);
    ChatLog.diagnostic('streak send start', 'replays=$allowReplays');
    await _send(allowReplays: allowReplays);
  }

  Future<void> _send({required bool allowReplays}) async {
    final segment = _segments.isEmpty ? null : _segments.first;
    if (segment == null) return;

    // Hand the clip to the outbox and leave. The upload, its retries and
    // its failure handling all belong to _attemptSend, and the optimistic
    // bubble is where the user watches it — holding them on the camera
    // through a 25MB upload bought nothing.
    // Transcode BEFORE queueing. _attemptSend uploads whatever path it is
    // given verbatim, so handing it raw camera output would push a file
    // several times larger than the ceiling allows.
    setState(() => _isSending = true);
    final PreparedChatVideo prepared;
    try {
      prepared = await const ChatVideoPreparer().prepare(
        localPath: segment.path,
        maxDuration: kStreakSegmentDuration,
        maxBytes: 25 * 1024 * 1024,
      );
    } on ChatVideoRejected catch (rejected) {
      ChatLog.diagnostic('streak prepare rejected', rejected);
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That streak could not be sent.')),
      );
      return;
    }
    if (!mounted) return;

    ChatLog.diagnostic('streak queued', '${prepared.byteSize}B');
    unawaited(
      ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .sendStreakMessage(
            localPath: prepared.file.path,
            durationMs: prepared.durationMs,
            viewsRemaining: streakViewBudget(allowReplays: allowReplays),
          ),
    );

    // The staged file now belongs to the outbox, so clear the local
    // reference WITHOUT deleting it — _attemptSend still needs to read it.
    await _disposePreview();
    _segments.clear();
    if (mounted) context.pop();
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
    await _resetCapture();
    if (!mounted) return;
    context.pop();
  }

  /// Opens the captured clip for review.
  Future<void> _startPreview_(String path) async {
    await _disposePreview();
    final controller = VideoPlayerController.file(File(path));
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
    await controller?.dispose();
  }

  /// Back to a live camera with nothing staged.
  Future<void> _resetCapture() async {
    await _disposePreview();
    await _discardAll();
    if (!mounted) return;
    setState(() {
      // _isSending is set before the transcode and cleared only on the
      // error paths -- the success path pops the screen, so it never
      // needed clearing there. Cancelling instead KEEPS the screen, and
      // a stuck flag then made the button permanently busy: no haptic,
      // no recording, on every take after the first.
      _isSending = false;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = null;
    });
  }

  /// Deletes every staged file. A recorded-but-unsent streak must leave
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
    _previewController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(body: Center(child: Text(_permissionError!)));
    }
    final controller = _controller;
    final preview = _previewController;
    final progress =
        _segmentElapsed.inMilliseconds / kStreakSegmentDuration.inMilliseconds;

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
          // Both hidden while a take is under review: the send sheet owns
          // that moment, and closing or flipping mid-decision would either
          // discard the take silently or spin up a camera nobody is
          // looking at.
          if (preview == null) ...[
            // Below the status bar and notch rather than tight against the
            // top edge, and a larger target: these are the only two controls
            // on a full-bleed viewfinder.
            Positioned(
              top: Spacing.xxl,
              left: Spacing.md,
              child: IconButton(
                iconSize: 32,
                // A LOCKED take must stay abandonable: nothing is holding
              // it, so disabling this left no way out but waiting a
              // minute. Only a finger-held take blocks closing.
              onPressed: (_isRecording && !_isLocked) || _isSending
                  ? null
                  : _closeCamera,
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
                onPressed: _isSending ? null : _flipCamera,
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
                  // Hidden while a take is under REVIEW -- the sheet owns
                  // that moment -- but shown again during the send, where
                  // the ring is the only progress the user gets. Keying on
                  // the preview alone hid it for the whole upload.
                  preview != null && !_isSending
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
                            unawaited(HapticFeedback.mediumImpact());
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
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
