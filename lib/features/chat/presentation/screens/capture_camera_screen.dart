import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/features/chat/presentation/widgets/streak_lock_hint.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:camera/camera.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionActions, PermissionStatus, openAppSettings;

/// Which kinds of media a [CaptureCameraScreen] instance may capture.
///
/// Only [videoOnly] exists today. Task 3 (spec §6.2/§6.3) adds
/// [photoAndVideo] alongside `takePicture()` and a tap/hold gesture split;
/// this screen must not grow that behaviour before then, so every capture
/// path below assumes video.
enum CaptureKinds { videoOnly, photoAndVideo }

/// The copy a [CaptureCameraScreen] shows (spec §6: each adapter owns its
/// copy). The defaults are the streak camera's shipped strings, so a caller
/// that passes nothing is byte-identical to the shipped streak screen.
@immutable
class CaptureCameraCopy {
  const CaptureCameraCopy({
    this.cameraDenied = 'Attune needs camera access to record a streak.',
    this.noCamera = 'No camera available.',
    this.videoNeedsMicrophone = 'Video needs microphone access.',
    this.shutterLabel,
  });

  /// The story camera's copy: never says "streak".
  static const story = CaptureCameraCopy(
    cameraDenied: 'Attune needs camera access to share a story.',
    videoNeedsMicrophone:
        'Video needs microphone access. Tap for a photo, or allow the microphone in Settings.',
  );

  final String cameraDenied;
  final String noCamera;
  final String videoNeedsMicrophone;

  /// The shutter's screen-reader label; null picks one from the allowed
  /// capture kinds.
  final String? shutterLabel;
}

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
    this.imagePreparerFactory,
    this.onCaptured,
    this.onCancelled,
    this.isReviewing = false,
    this.resolutionPreset = ResolutionPreset.medium,
    this.microphoneOptional = false,
    this.copy = const CaptureCameraCopy(),
    this.openSettings,
    this.permissionGranted,
  });

  /// [CaptureKinds.videoOnly] (the streak adapter's value, spec §6.2.1) is
  /// byte-for-byte the pre-Task-3 gesture: press starts recording
  /// immediately, release stops it. [CaptureKinds.photoAndVideo] adds the
  /// tap/hold split (spec §6.2): release before a 300ms hold threshold
  /// takes a photo via [takePicture]; crossing the threshold starts video
  /// exactly as [videoOnly] always has.
  final CaptureKinds allow;

  /// Test seam, mirroring ChatTextField's `recorderFactory`: defaults to
  /// the real [ChatVideoPreparer] constructor. video_compress has no
  /// platform channel on a test host, so `prepare()` always rejects there
  /// — this lets a characterization test observe the success path too.
  final ChatVideoPreparer Function()? videoPreparerFactory;

  /// Test seam for the photo path, same shape as [videoPreparerFactory]:
  /// defaults to the real [CaptureImagePreparer] constructor.
  final CaptureImagePreparer Function()? imagePreparerFactory;

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

  /// The sensor preset. Defaults to the streak camera's shipped `medium`
  /// (§6.4: streaks byte-identical); stories pass `veryHigh` (1080p video,
  /// 1920-px photos) because a 640×480 frame is visibly soft full screen.
  final ResolutionPreset resolutionPreset;

  /// When the microphone is refused, re-initialise without audio so photos
  /// still work (01 #6); a hold then explains that video needs the mic.
  /// Off by default: the streak camera's shipped behaviour is unchanged.
  final bool microphoneOptional;

  /// Destination copy (spec §6: each adapter owns its copy). The defaults
  /// are the streak camera's shipped strings.
  final CaptureCameraCopy copy;

  /// Test seam for the error screen's Open Settings; defaults to
  /// permission_handler's openAppSettings.
  final Future<void> Function()? openSettings;

  /// Test seam: whether [Permission] is granted now. Defaults to
  /// permission_handler's status check (false if it cannot be read). Read
  /// on return to the app, so a refusal changed in Settings is picked up
  /// without asking the person again.
  final Future<bool> Function(Permission permission)? permissionGranted;

  @override
  ConsumerState<CaptureCameraScreen> createState() =>
      CaptureCameraScreenState();
}

class CaptureCameraScreenState extends ConsumerState<CaptureCameraScreen>
    with WidgetsBindingObserver {
  late final RecordingHaptics _recordingHaptics;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  String? _permissionError;

  /// The microphone was refused and [CaptureCameraScreen.microphoneOptional]
  /// is set: the controller runs without audio, so photos only.
  bool _audioUnavailable = false;

  /// The error screen's Open Settings is offered only when a permission
  /// change could fix it (not for a phone with no camera).
  bool _settingsHelps = false;

  /// The CameraException code behind [_permissionError] (null for no
  /// camera). On return to the app a refusal is retried only once its
  /// permission is granted; anything else (a camera still held by a call)
  /// is simply retried (batch-6 review #5).
  String? _errorCode;

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

  /// True while a photo is being captured/prepared. Same role as
  /// [_isSending] but kept separate so the record button's busy state
  /// during a photo take cannot be confused with a video transcode.
  bool _isCapturingPhoto = false;

  /// Armed on press-down when [CaptureKinds.photoAndVideo]: fires
  /// [_beginRecording] after the 300ms hold threshold (spec §6.2). A
  /// release before it fires cancels it and takes a photo instead; a
  /// release after it fires (i.e. [_isRecording] is already true) stops
  /// the recording as normal. The two outcomes are mutually exclusive by
  /// construction — the timer is the single source of truth for which
  /// gesture this press turned into, so a tap can never also start a
  /// recording and a hold can never also fire the shutter.
  Timer? _holdThresholdTimer;

  static const Duration _tick = Duration(milliseconds: 100);

  /// Spec §6.2: "release before a 300ms hold threshold takes a photo;
  /// crossing the threshold starts video".
  static const Duration _holdThreshold = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Stories Wave 3: the shell keeps this screen mounted through the
    // Safety lock's return check, so the camera re-opens when Attune is on
    // screen again, not merely resumed. Release stays on the lifecycle.
    ref.listenManual<bool>(appContentVisibleProvider, (_, visible) {
      if (visible) unawaited(_resume());
    });
    WidgetsBinding.instance.addObserver(this);
    _recordingHaptics = ref.read(recordingHapticsProvider);
    // iOS suppresses haptics by default while audio input is active. Enable
    // before the camera owns the audio session so lock, stop and a quick
    // second take all remain tactile on a physical device.
    unawaited(_recordingHaptics.enable());
    unawaited(_initCamera());
  }

  static const _audioDeniedCodes = {
    'AudioAccessDenied',
    'AudioAccessDeniedWithoutPrompt',
    'AudioAccessRestricted',
  };

  /// Refusals that the system Settings app can undo: only these offer Open
  /// Settings (a busy or broken camera would send the person somewhere that
  /// cannot help).
  static const _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    ..._audioDeniedCodes,
  };

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _permissionError = widget.copy.noCamera;
            _errorCode = null;
            _settingsHelps = false;
          });
        }
        return;
      }
      await _startPreview();
    } on CameraException catch (error) {
      var failure = error;
      if (widget.microphoneOptional && _audioDeniedCodes.contains(error.code)) {
        try {
          _audioUnavailable = true;
          await _startPreview();
          return;
        } on CameraException catch (retryError) {
          // Fall through: the camera itself is refused too.
          failure = retryError;
        }
      }
      _showCameraError(failure);
    } catch (error) {
      // Anything else (a plugin StateError, a PlatformException the plugin
      // did not wrap) lands on the error screen with Close, never a blank
      // screen: _retryAfterError has already cleared the last error.
      ChatLog.diagnostic('capture init failed', error);
      _showCameraError(error);
    }
  }

  void _showCameraError(Object error) {
    if (!mounted) return;
    setState(() {
      _permissionError = widget.copy.cameraDenied;
      _errorCode = error is CameraException ? error.code : null;
      _settingsHelps = _permissionCodes.contains(_errorCode);
    });
  }

  Future<bool> _granted(Permission permission) async {
    try {
      final check =
          widget.permissionGranted ??
          (p) async => await p.status == PermissionStatus.granted;
      return await check(permission);
    } catch (_) {
      return false;
    }
  }

  Future<void> _startPreview() async {
    if (_cameras.isEmpty) return;
    final controller =
        _audioUnavailable
            ? CameraController(
              _cameras[_cameraIndex],
              widget.resolutionPreset,
              // Microphone refused (microphoneOptional): photos only.
              enableAudio: false,
            )
            : CameraController(
              _cameras[_cameraIndex],
              widget.resolutionPreset,
              // A streak is someone talking to their partner: a muted format
              // removes most of what makes it worth sending.
              enableAudio: true,
            );
    _initInFlight = true;
    try {
      await controller.initialize();
    } catch (_) {
      // Never leak a half-initialised controller (a failed init used to).
      try {
        await controller.dispose();
      } catch (_) {}
      rethrow;
    } finally {
      _initInFlight = false;
    }
    // Finished while the app was away: release it, and _resume builds a
    // fresh one.
    if (!mounted || _suspended) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// The camera is released while the app is not in front (the camera
  /// plugin's documented lifecycle handling), and comes back on resume.
  /// Applies to every embedder: without it an interrupted session leaves a
  /// black or frozen preview, and Wave 3 keeps this screen mounted behind
  /// the privacy cover, where that would show (07b G7, risk 1).
  bool _suspended = false;
  bool _initInFlight = false;

  /// The release in progress, so a quick return waits for it instead of
  /// opening a second session over one still closing.
  Future<void>? _releasing;

  /// The stop in progress. One at a time: the touch cancel and the
  /// lifecycle pause of one interruption both end the take, and a second
  /// stop reaching the plugin is refused on iOS ("Video is not recording!"),
  /// which lost the take (batch-6 review #1).
  Future<void>? _stopping;

  /// A recording start and a photo in progress: a release waits for them
  /// too, so the controller is never disposed under the plugin (review #3,
  /// #4).
  Future<void>? _starting;
  Future<void>? _capturing;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_suspend());
      case AppLifecycleState.resumed:
        // Behind the lock check: the listener above re-opens it.
        if (ref.read(appContentVisibleProvider)) unawaited(_resume());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _suspend() async {
    if (_suspended) return;
    _suspended = true;
    _holdThresholdTimer?.cancel();
    _holdThresholdTimer = null;
    await _settleCameraWork();
    // Back already while the take was being saved: keep the camera.
    if (!_suspended) return;
    final controller = _controller;
    if (controller == null) return; // still initialising: see _startPreview
    if (mounted) setState(() => _controller = null);
    final release = () async {
      try {
        await controller.dispose();
      } catch (_) {}
    }();
    _releasing = release;
    await release;
    if (identical(_releasing, release)) _releasing = null;
  }

  /// Lets camera work already under way finish before a release, so the
  /// controller is never disposed under it. A call or Control Centre
  /// mid-hold keeps what was recorded; a locked take ends the same way, and
  /// Close and review follow on return. Bounded: each pass either finishes
  /// something or stops.
  Future<void> _settleCameraWork() async {
    for (var pass = 0; pass < 4; pass++) {
      final starting = _starting;
      if (starting != null) {
        // The take that is starting ends as soon as it has started.
        if (_startInFlight) _releasedDuringStart = true;
        await starting;
        continue;
      }
      final capturing = _capturing;
      if (capturing != null) {
        await capturing;
        continue;
      }
      final stopping = _stopping;
      if (stopping != null) {
        await stopping;
        continue;
      }
      if (_isRecording) {
        _isLocked = false;
        await _endRecording();
        continue;
      }
      return;
    }
  }

  Future<void> _resume() async {
    if (!_suspended) return;
    _suspended = false;
    final releasing = _releasing;
    if (releasing != null) await releasing;
    if (_suspended || !mounted) return; // away again before it closed
    if (_permissionError != null) {
      await _retryAfterError();
      return;
    }
    if (_cameras.isEmpty || _controller != null || _initInFlight) return;
    // Audio is tried again only when the microphone is now allowed (the
    // snackbar's Settings, batch-5 review #3). Trying without that check
    // showed Android's microphone dialog on every return (batch-6 #2).
    final retryAudio =
        widget.microphoneOptional &&
        _audioUnavailable &&
        await _granted(Permission.microphone);
    if (_suspended || !mounted || _controller != null || _initInFlight) return;
    try {
      if (retryAudio) {
        _audioUnavailable = false;
        try {
          await _startPreview();
          return;
        } on CameraException catch (error) {
          _audioUnavailable = true;
          if (!_audioDeniedCodes.contains(error.code)) rethrow;
        }
      }
      await _startPreview();
    } catch (error) {
      ChatLog.diagnostic('capture resume failed', error);
      _showCameraError(error);
    }
  }

  /// Back on the error screen: a refusal is retried once its permission is
  /// granted (changed in Settings); a camera that was busy or failed is
  /// simply tried again, so a transient failure does not stick.
  Future<void> _retryAfterError() async {
    final code = _errorCode;
    if (code != null && _permissionCodes.contains(code)) {
      final permission =
          _audioDeniedCodes.contains(code)
              ? Permission.microphone
              : Permission.camera;
      if (!await _granted(permission)) return;
    }
    if (_suspended || !mounted || _permissionError == null) return;
    setState(() {
      _permissionError = null;
      _errorCode = null;
      _settingsHelps = false;
    });
    await _initCamera();
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

  /// Press-down. [CaptureKinds.videoOnly] starts recording immediately —
  /// exactly today's behaviour, untouched. [CaptureKinds.photoAndVideo]
  /// instead arms [_holdThresholdTimer]; nothing is called on the camera
  /// yet, so a tap that never crosses the threshold never talks to the
  /// camera at all until it decides to take a photo.
  Future<void> _onPressStart() async {
    if (widget.allow == CaptureKinds.videoOnly) {
      await _beginRecording();
      return;
    }

    if (_isRecording || _isCapturingPhoto || _holdThresholdTimer != null) {
      return;
    }
    _holdThresholdTimer = Timer(_holdThreshold, () {
      _holdThresholdTimer = null;
      unawaited(_beginRecording());
    });
  }

  /// Release. [CaptureKinds.videoOnly] stops recording immediately —
  /// exactly today's behaviour, untouched. [CaptureKinds.photoAndVideo]
  /// checks whether [_holdThresholdTimer] already fired: if it did not,
  /// this was a tap, so the timer is cancelled (guaranteeing it can never
  /// fire afterwards and start a recording the user already released)
  /// and a photo is taken instead; if it did, recording is already under
  /// way and this release stops it exactly as [_endRecording] always has.
  Future<void> _onPressEnd() async {
    if (widget.allow == CaptureKinds.videoOnly) {
      await _endRecording();
      return;
    }

    final threshold = _holdThresholdTimer;
    if (threshold != null) {
      threshold.cancel();
      _holdThresholdTimer = null;
      await _takePicture();
      return;
    }

    await _endRecording();
  }

  Future<void> _beginRecording() async {
    final start = _beginRecordingNow();
    _starting = start;
    try {
      await start;
    } finally {
      if (identical(_starting, start)) _starting = null;
    }
  }

  Future<void> _beginRecordingNow() async {
    final controller = _controller;
    if (controller == null || _isRecording || _startInFlight) return;

    if (_audioUnavailable) {
      if (!mounted) return;
      // Replace, never queue: each hold would otherwise add another 4 s of
      // the same notice.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(widget.copy.videoNeedsMicrophone),
            action: SnackBarAction(label: 'Settings', onPressed: _openSettings),
          ),
        );
      return;
    }

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
    // Calls _endRecording directly (not the _onPressEnd dispatcher):
    // recording has genuinely started by this point regardless of which
    // gesture path led here, so this is unconditionally a stop.
    if (_releasedDuringStart) {
      _releasedDuringStart = false;
      await _endRecording();
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
    if (_stopping != null) return; // a stop is already ending this take
    final split = _splitSegmentNow();
    _stopping = split;
    try {
      await split;
    } finally {
      if (identical(_stopping, split)) _stopping = null;
    }
  }

  Future<void> _splitSegmentNow() async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;

    // Suspend the ticker's split check while this runs, or a slow stop
    // lets a second split fire against a controller already stopping.
    _segmentStartedAt = null;

    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } on CameraException catch (error) {
      await _recoverFromFailedStop(error);
      return;
    }
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

    try {
      await controller.startVideoRecording();
    } on CameraException catch (error) {
      // Unreachable while kStreakMaxSegments is 1 (the cap returns
      // above). The segment just closed is a whole take: report it rather
      // than losing it, then put the viewfinder back.
      final saved = _segments.isNotEmpty;
      _ticker?.cancel();
      if (mounted) setState(() => _isRecording = false);
      if (saved) _reportCaptured();
      await _recoverFromFailedStop(error, announce: !saved);
      return;
    }
    if (!mounted) return;
    ref.read(hapticsProvider).selection();
    setState(() {
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = clock.now();
    });
  }

  Future<void> _endRecording() async {
    // Released before startVideoRecording() finished: remember it, and
    // _beginRecording finishes as soon as there is a recording to finish.
    if (_startInFlight) {
      _releasedDuringStart = true;
      return;
    }
    // A stop already under way ends this take: wait for it instead of
    // sending a second one.
    while (_stopping != null) {
      await _stopping;
    }
    if (!_isRecording) return;

    // Locking is precisely the promise that lifting a finger does not end
    // the take. The stop button owns that from here.
    if (_isLocked) return;

    final controller = _controller;
    if (controller == null) return;

    final stop = _stopAndKeep(controller);
    _stopping = stop;
    try {
      await stop;
    } finally {
      if (identical(_stopping, stop)) _stopping = null;
    }
  }

  Future<void> _stopAndKeep(CameraController controller) async {
    _ticker?.cancel();
    final held = _segmentElapsed;
    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } on CameraException catch (error) {
      await _recoverFromFailedStop(error);
      return;
    }
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
      // Too short to keep. A release closes the camera as before; an
      // interruption (call, Control Centre) leaves it open for the return.
      if (!_suspended) _reportCancelled();
      return;
    }

    // A partial final segment is kept: it is what the user recorded, and
    // dropping it would make the last thing they said disappear.
    _segments.add(StreakSegment(path: file.path, duration: held));
    _reportCaptured();
  }

  /// stopVideoRecording threw (low storage, an interrupted writer): put the
  /// screen back to a live viewfinder instead of leaving it "recording"
  /// with Close hidden (01 #15).
  ///
  /// [announce] is false when the take was still handed on (a failed
  /// restart after a whole segment): nothing was lost, so nothing is said.
  Future<void> _recoverFromFailedStop(
    Object error, {
    bool announce = true,
  }) async {
    ChatLog.diagnostic('capture stop failed', error);
    _ticker?.cancel();
    await _discardAll();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = null;
    });
    if (announce) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save that recording.')),
      );
    }
    // The plugin only clears isRecordingVideo when the native stop
    // succeeds, so a controller whose stop threw refuses every later start
    // ("already started"). Rebuild it so the next hold records again.
    final stale = _controller;
    if (stale == null || !stale.value.isRecordingVideo) return;
    setState(() => _controller = null);
    try {
      await stale.dispose();
    } catch (_) {}
    if (!mounted) return;
    try {
      await _startPreview();
    } catch (restartError) {
      // No controller would leave a shutter spinning forever: hand over to
      // the error screen, whose Close is the way out. (The failed take has
      // no path to delete: the plugin returns none when its stop throws.)
      ChatLog.diagnostic('capture restart after failed stop', restartError);
      _showCameraError(restartError);
    }
  }

  /// Ends a locked take.
  ///
  /// Separate from _endRecording, which returns early while locked -- that
  /// guard is what lets the finger lift, and routing the stop button
  /// through it made stopping impossible until the 60s cap fired.
  Future<void> _stopLockedRecording() async {
    if (!_isRecording || !_isLocked) return;
    setState(() => _isLocked = false);
    await _endRecording();
  }

  /// Takes a photo via [CameraController.takePicture] and reports it as a
  /// RAW (not yet resized/compressed) [CapturedMedia] — via
  /// [CaptureCameraScreen.onCaptured] if an embedder is watching,
  /// otherwise by preparing it immediately and popping this route with
  /// the result. Mirrors [_reportCaptured]'s video contract exactly, so a
  /// future story adapter's review step behaves identically for either
  /// media type.
  ///
  /// Only reachable when [widget.allow] is [CaptureKinds.photoAndVideo]
  /// (see [_onPressEnd]) — the streak adapter passes [CaptureKinds
  /// .videoOnly] and never calls this.
  Future<void> _takePicture() async {
    final shot = _takePictureNow();
    _capturing = shot;
    try {
      await shot;
    } finally {
      if (identical(_capturing, shot)) _capturing = null;
    }
  }

  Future<void> _takePictureNow() async {
    final controller = _controller;
    if (controller == null || _isCapturingPhoto || _isRecording) return;

    if (_isSending) {
      ChatLog.diagnostic('capture tap while sending', 'clearing stale flag');
      setState(() => _isSending = false);
    }

    setState(() => _isCapturingPhoto = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;

      final size = controller.value.previewSize;
      final media = CapturedMedia(
        path: file.path,
        type: CapturedMediaType.image,
        width: size?.width.round() ?? 0,
        height: size?.height.round() ?? 0,
        // Never set for an image: the server CHECK constraint refuses an
        // image row that carries a duration (spec §6.2/§4.2).
        durationMs: null,
      );

      final onCaptured = widget.onCaptured;
      if (onCaptured != null) {
        onCaptured(media);
        return;
      }
      unawaited(_transcodeAndPopGuarded(media));
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not take that photo.')),
      );
    } finally {
      if (mounted) setState(() => _isCapturingPhoto = false);
    }
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

  /// The standalone-push contract: transcode/prepare right away (there is
  /// no embedder to defer that decision to) and pop with the result.
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
    } on CaptureImageRejected catch (rejected) {
      ChatLog.diagnostic('capture image rejected', rejected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That photo could not be sent.')),
      );
    } catch (error, stack) {
      ChatLog.diagnostic('capture failed', '$error\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That could not be captured.')),
      );
    }
  }

  /// Prepares [raw] for sending and returns the prepared [CapturedMedia]:
  /// a video transcodes through [ChatVideoPreparer] (25MB ceiling); a
  /// photo resizes/compresses through [CaptureImagePreparer] (2560px /
  /// 5MB, spec §4.2) and always comes back with `durationMs: null` — the
  /// server CHECK constraint refuses an image row that has one.
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
  /// Throws [ChatVideoRejected] or [CaptureImageRejected] on a rejected
  /// prepare; the caller decides what to show for that (this screen shows
  /// its own message only on the standalone-push path, via
  /// [_transcodeAndPopGuarded]).
  Future<CapturedMedia> confirmSend(CapturedMedia raw) async {
    if (raw.type == CapturedMediaType.image) {
      return _prepareImage(raw);
    }
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

  /// The image half of [confirmSend]. A photo carries no duration
  /// (spec §6.2/§4.2): the source [CapturedMedia] from [_takePicture]
  /// already has `durationMs: null`, and nothing here introduces one.
  Future<CapturedMedia> _prepareImage(CapturedMedia raw) async {
    if (mounted) setState(() => _isSending = true);
    try {
      final prepared = await (widget.imagePreparerFactory ??
              CaptureImagePreparer.new)()
          .prepare(raw.path);
      ChatLog.diagnostic('capture image prepared', '${prepared.byteSize}B');
      return CapturedMedia(
        path: prepared.file.path,
        type: CapturedMediaType.image,
        width: prepared.width,
        height: prepared.height,
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _openSettings() => unawaited(
    (widget.openSettings ??
        () async {
          await openAppSettings();
        })(),
  );

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
      _isCapturingPhoto = false;
      _isLocked = false;
      _lockDrag = 0;
      _segmentElapsed = Duration.zero;
      _segmentStartedAt = null;
    });
  }

  /// Discards anything staged and leaves the camera.
  Future<void> _closeCamera() async {
    // A stop already under way finishes first (never two at once).
    while (_stopping != null) {
      await _stopping;
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _holdThresholdTimer?.cancel();
    _controller?.dispose();
    unawaited(_recordingHaptics.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      // A fixed black surface like the viewfinder, with a way out: the
      // plain text screen this replaced was a dead end (06 #13).
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: Spacing.md,
                left: Spacing.md,
                child: IconButton(
                  iconSize: IconSizes.lg,
                  tooltip: 'Close camera',
                  onPressed: _reportCancelled,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              Center(
                child: Padding(
                  padding: Spacing.allLg,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        size: IconSizes.xl,
                        color: Colors.white70,
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        _permissionError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.white),
                      ),
                      if (_settingsHelps) ...[
                        const SizedBox(height: Spacing.lg),
                        FilledButton(
                          onPressed: _openSettings,
                          child: const Text('Open Settings'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
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
                tooltip: 'Switch camera',
                icon: const Icon(
                  Icons.flip_camera_ios_outlined,
                  color: Colors.white,
                ),
              ),
            ),
          ],

          // Tap-for-photo / hold-for-video hint. Only when the seam is
          // actually open — the streak adapter passes CaptureKinds
          // .videoOnly, and this affordance must be entirely absent
          // there (§6.2.1): a photo option offered on a screen that
          // cannot send a photo would be a control that lies. Hidden
          // the moment a gesture is in progress or a take is staged, for
          // the same "no dead control on screen" reasoning as the
          // close/flip buttons above.
          if (widget.allow == CaptureKinds.photoAndVideo &&
              !reviewing &&
              !_isSending &&
              !_isCapturingPhoto &&
              !_isRecording &&
              _holdThresholdTimer == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: Spacing.xxl * 2 + 96,
              child: Center(
                child: Text(
                  key: const ValueKey('capture-shutter-hint'),
                  'Tap for photo · Hold for video',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ),
            ),

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
                      : Semantics(
                        button: true,
                        label:
                            widget.copy.shutterLabel ??
                            (widget.allow == CaptureKinds.photoAndVideo
                                ? 'Take photo, hold for video'
                                : 'Hold to record'),
                        // The button is a raw Listener, which a screen
                        // reader's double-tap never reaches: give it a tap.
                        // Only when the button itself would take one: never
                        // while busy (a send, a photo, a take) or not ready,
                        // or a double-tap mid-send captures a second time.
                        onTap:
                            widget.allow == CaptureKinds.photoAndVideo &&
                                    !_isSending &&
                                    !_isCapturingPhoto &&
                                    !_isRecording &&
                                    controller != null &&
                                    controller.value.isInitialized
                                ? () => unawaited(_takePicture())
                                : null,
                        child: Listener(
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
                            isSending: _isSending || _isCapturingPhoto,
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
          ),
        ],
      ),
    );
  }
}
