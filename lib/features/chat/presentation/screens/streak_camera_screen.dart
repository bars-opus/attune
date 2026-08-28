import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/chat/presentation/widgets/streak_review_sheet.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        setState(() => _permissionError =
            'Attune needs camera access to record a streak.');
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
    if (_isRecording || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    _controller = null;
    await _startPreview();
  }

  Future<void> _onPressStart() async {
    final controller = _controller;
    if (controller == null || _isRecording || _startInFlight) return;

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
    _segments.add(StreakSegment(
      path: file.path,
      duration: kStreakSegmentDuration,
    ));

    if (StreakRecordingSession.shouldStopAt(_segments.length)) {
      _ticker?.cancel();
      if (mounted) setState(() => _isRecording = false);
      unawaited(HapticFeedback.heavyImpact());
      unawaited(_openReview());
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

    final controller = _controller;
    if (controller == null) return;

    _ticker?.cancel();
    final held = _segmentElapsed;
    final file = await controller.stopVideoRecording();
    if (!mounted) return;

    setState(() => _isRecording = false);

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
    unawaited(_openReview());
  }

  /// Offers send or cancel. A streak must not fly away the instant a
  /// finger lifts — a mis-hold would otherwise be unrecallable.
  Future<void> _openReview() async {
    if (!mounted || _segments.isEmpty) return;

    final send = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => StreakReviewSheet(
        segments: _segments,
        onSend: () => Navigator.of(sheetContext).pop(true),
        onDiscard: () => Navigator.of(sheetContext).pop(false),
      ),
    );

    if (!mounted) return;

    if (send != true) {
      await _discardAll();
      if (mounted) context.pop();
      return;
    }

    // Whether replays are allowed is a persistent chat setting, read at
    // send time rather than chosen here.
    final allowReplays = ref.read(streakReplayPreferenceProvider);
    await _send(allowReplays: allowReplays);
  }

  Future<void> _send({required bool allowReplays}) async {
    // The upload path is wired in the send-integration task; the clips and
    // the budget are what it needs, and both are settled here.
    if (!mounted) return;
    context.pop();
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(body: Center(child: Text(_permissionError!)));
    }
    final controller = _controller;
    final progress = _segmentElapsed.inMilliseconds /
        kStreakSegmentDuration.inMilliseconds;

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
            )
          else
            const Center(child: CircularProgressIndicator()),

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

          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: _isRecording ? null : _flipCamera,
              icon: const Icon(
                Icons.flip_camera_ios_outlined,
                color: Colors.white,
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: StreakRecordButton(
                progress: progress.clamp(0.0, 1.0),
                isRecording: _isRecording,
                onPressStart: () => unawaited(_onPressStart()),
                onPressEnd: () => unawaited(_onPressEnd()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
