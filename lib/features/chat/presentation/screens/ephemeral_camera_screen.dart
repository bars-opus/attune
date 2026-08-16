import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/video_prepare_progress_dialog.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen live camera preview for press-and-hold ephemeral video
/// capture. Pushed via Navigator.push from chat_screen.dart's composer, not
/// a GoRouter route — mirrors VideoTrimScreen's established
/// "full-screen route for video-specific UI" pattern from Part 1.
///
/// Release-to-send has NO confirm step — this is a deliberate, confirmed
/// design choice (true Snapchat parity), not an oversight. A minimum hold
/// duration silently discards accidental taps, mirroring
/// VoiceRecorderService.minDuration's identical pattern.
///
/// Takes the same [Conversation] object chat_screen.dart itself holds
/// (rather than a bare relationshipId string) so
/// `chatControllerProvider(conversation)` resolves to the SAME controller
/// instance the chat screen is using — chatControllerProvider is a family
/// provider keyed on the whole Conversation object (see chat_screen.dart's
/// own `chatControllerProvider(widget.conversation)` call sites), not on an
/// id string, so a relationshipId-only constructor could not reach it.
class EphemeralCameraScreen extends ConsumerStatefulWidget {
  const EphemeralCameraScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<EphemeralCameraScreen> createState() =>
      EphemeralCameraScreenState();
}

class EphemeralCameraScreenState
    extends ConsumerState<EphemeralCameraScreen> {
  static const Duration _maxRecordingDuration = Duration(seconds: 10);
  static const Duration _minHoldDuration = Duration(milliseconds: 500);

  /// Test seam: the minimum-hold-duration discard check prepare() itself
  /// doesn't own — this screen decides BEFORE ever handing a file to
  /// ChatVideoPreparer whether a hold was long enough to be an intentional
  /// recording versus an accidental tap.
  @visibleForTesting
  static bool debugShouldDiscardHold(Duration held) =>
      held < _minHoldDuration;

  /// Test seam: the 10-second auto-stop clamp, exposed so its correctness
  /// (never exceeds the cap, never clamps a shorter recording down) can be
  /// asserted directly without a real camera/timer.
  @visibleForTesting
  static Duration debugClampRecordingDuration(Duration elapsed) =>
      elapsed > _maxRecordingDuration ? _maxRecordingDuration : elapsed;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  DateTime? _recordingStartedAt;
  Timer? _autoStopTimer;
  bool _isRecording = false;
  bool _isPreparing = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      // Front camera default, per the approved design — find the first
      // front-facing camera, falling back to index 0 if none is reported
      // (some emulators/devices only expose one lens).
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startPreview();
    } catch (_) {
      // camera throws CameraException for both permission-denial and
      // hardware-unavailable cases; either way there is no usable preview,
      // so both collapse to the same "can't record" messaging here.
      if (mounted) {
        setState(
          () => _permissionError = 'Camera access is needed to record.',
        );
      }
    }
  }

  Future<void> _startPreview() async {
    if (_cameras.isEmpty) return;
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
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

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || _isRecording) return;
    try {
      await controller.startVideoRecording();
    } catch (_) {
      return;
    }
    _recordingStartedAt = DateTime.now();
    setState(() => _isRecording = true);
    _autoStopTimer = Timer(_maxRecordingDuration, () {
      unawaited(_stopAndSend());
    });
  }

  Future<void> _stopAndSend() async {
    _autoStopTimer?.cancel();
    final controller = _controller;
    final startedAt = _recordingStartedAt;
    if (controller == null || !_isRecording || startedAt == null) return;

    setState(() => _isRecording = false);
    final held = debugClampRecordingDuration(
      DateTime.now().difference(startedAt),
    );

    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } catch (_) {
      return;
    }

    if (debugShouldDiscardHold(held)) {
      // Silent discard — matches VoiceRecorderService's identical
      // accidental-tap handling. Delete the short clip so it doesn't
      // linger in temp storage.
      try {
        await File(file.path).delete();
      } catch (_) {
        // Best-effort cleanup only — a failed delete doesn't block the
        // discard itself.
      }
      return;
    }

    await _prepareAndSend(file.path, held);
  }

  Future<void> _prepareAndSend(String localPath, Duration held) async {
    setState(() => _isPreparing = true);
    try {
      final prepared = await VideoPrepareProgressDialog.show(
        context,
        localPath: localPath,
        trimStart: Duration.zero,
        trimEnd: held,
      );
      if (!mounted) return;
      await ref
          .read(chatControllerProvider(widget.conversation).notifier)
          .sendEphemeralVideoMessage(
            localPath: prepared.file.path,
            durationMs: prepared.durationMs,
            thumbnailLocalPath: prepared.thumbnailFile.path,
            width: prepared.width,
            height: prepared.height,
          );
      if (mounted) Navigator.of(context).pop();
    } on ChatVideoRejected catch (rejected) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _permissionError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rejectionMessage(rejected.code))),
      );
      // Deliberately does NOT pop back to the chat screen on failure — the
      // user is still on the camera screen and can try recording again,
      // unlike a picker-cancel elsewhere in the app which just returns.
    }
  }

  String _rejectionMessage(String code) {
    switch (code) {
      case 'media_too_long':
        return 'That recording is too long.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'Could not prepare that video. Try again.';
      case 'media_too_short':
        return 'That clip is too short.';
      default:
        return 'That video is no longer available.';
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(body: Center(child: Text(_permissionError!)));
    }
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            CameraPreview(controller)
          else
            const Center(child: CircularProgressIndicator()),
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
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onLongPressStart: (_) => unawaited(_startRecording()),
                onLongPressEnd: (_) => unawaited(_stopAndSend()),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (_isPreparing)
            const ColoredBox(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
