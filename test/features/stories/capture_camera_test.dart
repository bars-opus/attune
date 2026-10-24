// Tests for the photo half of CaptureCameraScreen (Plan B, Task 3).
//
// The camera module is destination-neutral (spec §6): capture, review,
// permissions, switching and media preparation, returning a CapturedMedia.
// Task 2 added the CaptureKinds seam (videoOnly / photoAndVideo) without
// wiring it up. This suite proves the tap/hold gesture split and
// takePicture() actually work, and that videoOnly leaves the photo
// affordance entirely absent — the streak adapter passes videoOnly, so a
// photo affordance there would offer a capture streaks cannot send (§6.2.1).
//
// _FakeCameraPlatform mirrors streak_camera_contract_test.dart's own fake
// (same CameraPlatform.instance seam, no change to shipped code) with
// takePicture() added, since the streak suite never needed it.

import 'dart:async';
import 'dart:io';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/capture_camera_screen.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart' show Permission;

import 'support/capture_fakes.dart' as fakes;

/// Minimal fake CameraPlatform so CameraController.initialize(),
/// startVideoRecording(), stopVideoRecording() and takePicture() can run
/// without a device. Anything else throws loudly via noSuchMethod,
/// mirroring streak_camera_contract_test.dart's _FakeCameraPlatform.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({required this.videoPath, required this.photoPath});

  final String videoPath;
  final String photoPath;

  int _nextCameraId = 0;
  int startVideoRecordingCalls = 0;
  int stopVideoRecordingCalls = 0;
  int takePictureCalls = 0;
  final settings = <MediaSettings>[];

  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'fake-back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    settings.add(mediaSettings);
    return _nextCameraId++;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          720,
          1280,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    startVideoRecordingCalls++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopVideoRecordingCalls++;
    return XFile(videoPath);
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    return XFile(photoPath);
  }

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this suite',
      );
}

/// Stands in for ChatVideoPreparer so a "hold" take's transcode succeeds
/// without video_compress's platform channel (unavailable on a test host).
class _FakeChatVideoPreparer extends ChatVideoPreparer {
  final List<String> preparedPaths = [];

  @override
  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    void Function(String posterPath)? onPosterReady,
    Duration? maxDuration,
    int? maxBytes,
  }) async {
    preparedPaths.add(localPath);
    return PreparedChatVideo(
      file: File(localPath),
      mimeType: 'video/mp4',
      byteSize: 1024,
      durationMs: 4000,
      thumbnailFile: File(localPath),
      thumbnailMimeType: 'image/jpeg',
      thumbnailByteSize: 128,
      width: 720,
      height: 1280,
    );
  }
}

/// Batch-6 review #1: a stop that is held open, where a second stop while
/// one is in flight is refused the way camera_avfoundation refuses it.
class _GatedCameraPlatform extends fakes.FakeCameraPlatform {
  _GatedCameraPlatform({required super.videoPath, required super.photoPath});

  Completer<void>? stopGate;
  Completer<void>? startGate;
  Completer<void>? photoGate;
  bool _stopping = false;

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    if (_stopping) {
      stopVideoCalls++;
      throw CameraException('Error', 'Video is not recording!');
    }
    _stopping = true;
    try {
      await stopGate?.future;
      return await super.stopVideoRecording(cameraId);
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    await startGate?.future;
    await super.startVideoCapturing(options);
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    await photoGate?.future;
    return super.takePicture(cameraId);
  }
}

void main() {
  late Directory tempDir;
  late CameraPlatform originalCameraPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('capture_camera_test');
    originalCameraPlatform = CameraPlatform.instance;
  });

  tearDown(() async {
    CameraPlatform.instance = originalCameraPlatform;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeFile(
    WidgetTester tester,
    String name, {
    int bytes = 128,
  }) async {
    final path = '${tempDir.path}/$name';
    await tester.runAsync(() => File(path).writeAsBytes(List.filled(bytes, 1)));
    return path;
  }

  Widget buildHarness(Widget screen) {
    return ProviderScope(
      child: MaterialApp(home: screen),
    );
  }

  /// Boots the screen and settles the camera's async init so the record
  /// button is ready. Bounded pump()s only (see streak_camera_contract_
  /// test.dart's own pumpToReady doc comment) — the record button shows an
  /// indeterminate spinner while preparing, which would hang pumpAndSettle.
  Future<void> pumpToReady(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(buildHarness(screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a tap takes a photo, a hold records video', (tester) async {
    final videoPath = await writeFile(tester, 'clip.mp4');
    final photoPath = await writeFile(tester, 'photo.jpg');
    final cameraPlatform = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );
    CameraPlatform.instance = cameraPlatform;

    CapturedMedia? captured;

    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        videoPreparerFactory: () => _FakeChatVideoPreparer(),
        onCaptured: (media) => captured = media,
      ),
    );

    // TAP: press and release well BEFORE the hold threshold. Must take a
    // photo and must NOT ever have started a recording.
    final tapGesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tapGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      cameraPlatform.takePictureCalls,
      1,
      reason: 'a short tap must fire the shutter',
    );
    expect(
      cameraPlatform.startVideoRecordingCalls,
      0,
      reason: 'a tap must NOT start a recording',
    );
    expect(captured?.type, CapturedMediaType.image);

    captured = null;

    // HOLD: press and hold past the threshold, then release. Must record
    // video and must NOT also fire the shutter.
    final holdGesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    // Cross the 300ms hold threshold first, and pump separately right
    // after so _beginRecording's own awaits (haptics enable, then
    // startVideoRecording) fully resolve and _isRecording flips true
    // before the finger lifts -- a single large pump() advances the fake
    // clock far enough to fire the Timer but does not guarantee every
    // microtask chained off it has actually settled by the time this
    // helper moves on to .up().
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    // Now past the 500ms minimum first-segment length too
    // (StreakRecordingSession.shouldDiscard). Ticked in 100ms steps
    // (rather than one large pump) so the ticker's own Timer.periodic
    // actually advances _segmentElapsed via several ticks, exactly as a
    // real hold would -- matching kStreakMinFirstSegment's own 100ms
    // ticker cadence.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await holdGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      cameraPlatform.startVideoRecordingCalls,
      1,
      reason: 'a hold past the threshold must start a recording',
    );
    expect(
      cameraPlatform.takePictureCalls,
      1,
      reason: 'a hold must NOT also fire the shutter (still just the '
          'one call from the earlier tap)',
    );
    expect(captured?.type, CapturedMediaType.video);
  });

  testWidgets('videoOnly hides the shutter entirely', (tester) async {
    final videoPath = await writeFile(tester, 'clip.mp4');
    final photoPath = await writeFile(tester, 'photo.jpg');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );

    await pumpToReady(
      tester,
      const CaptureCameraScreen(allow: CaptureKinds.videoOnly),
    );

    // No photo-specific affordance anywhere in the tree — the streak
    // adapter passes videoOnly, and a photo affordance there would offer
    // a capture streaks cannot send.
    expect(find.byIcon(Icons.camera_alt), findsNothing);
    expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(find.byKey(const ValueKey('capture-shutter-hint')), findsNothing);
  });

  testWidgets('a photo carries no duration', (tester) async {
    final videoPath = await writeFile(tester, 'clip.mp4');
    final photoPath = await writeFile(tester, 'photo.jpg');
    CameraPlatform.instance = _FakeCameraPlatform(
      videoPath: videoPath,
      photoPath: photoPath,
    );

    CapturedMedia? captured;

    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        onCaptured: (media) => captured = media,
      ),
    );

    final tapGesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tapGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(captured, isNotNull);
    expect(captured!.type, CapturedMediaType.image);
    expect(
      captured!.durationMs,
      isNull,
      reason:
          'the server CHECK constraint refuses an image row that has a '
          'duration',
    );
  });

  testWidgets('the sensor preset is the embedder\'s; the default is streak\'s medium',
      (tester) async {
    final platform = _FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;

    await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.medium);
    expect(platform.settings.last.enableAudio, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpToReady(
      tester,
      const CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        resolutionPreset: ResolutionPreset.veryHigh,
      ),
    );
    expect(platform.settings.last.resolutionPreset, ResolutionPreset.veryHigh);
  });

  group('permissions (01 #6, 06 #13)', () {
    testWidgets('microphone denied + microphoneOptional: photos still work, a hold '
        'says video needs the mic', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      CapturedMedia? captured;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          microphoneOptional: true,
          copy: const CaptureCameraCopy(videoNeedsMicrophone: 'MIC NEEDED'),
          onCaptured: (m) => captured = m,
        ),
      );
      expect(platform.settings.map((s) => s.enableAudio), [true, false]);
      expect(find.byType(StreakRecordButton), findsOneWidget);

      // Tap: a photo.
      final tap = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 100));
      await tap.up();
      await tester.pump();
      expect(captured?.type, CapturedMediaType.image);

      // Hold: no recording, and the reason.
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await hold.up();
      await tester.pump();
      expect(platform.startVideoCalls, 0);
      expect(find.text('MIC NEEDED'), findsOneWidget);
    });

    testWidgets('microphone denied without opting in: today\'s streak behaviour',
        (tester) async {
      CameraPlatform.instance = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
      expect(find.text('Attune needs camera access to record a streak.'), findsOneWidget);
    });

    testWidgets('the error screen offers Close and Open Settings', (tester) async {
      CameraPlatform.instance = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..cameraDenied = CameraException('CameraAccessDenied', 'denied');
      var settingsOpened = 0;
      var cancelled = 0;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          copy: CaptureCameraCopy.story,
          openSettings: () async => settingsOpened++,
          onCaptured: (_) {},
          onCancelled: () => cancelled++,
        ),
      );
      expect(find.text('Attune needs camera access to share a story.'), findsOneWidget);
      expect(find.textContaining('streak'), findsNothing);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(settingsOpened, 1);
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pump();
      expect(cancelled, 1);
    });
  });

  testWidgets('the shutter and flip are labelled, and a screen-reader tap takes '
      'a photo (06 #12)', (tester) async {
    final handle = tester.ensureSemantics();
    final platform = _FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;
    CapturedMedia? captured;
    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        onCaptured: (m) => captured = m,
      ),
    );
    expect(find.byTooltip('Switch camera'), findsOneWidget);
    final shutter = find.bySemanticsLabel('Take photo, hold for video');
    expect(shutter, findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('Take photo, hold for video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.takePictureCalls, 1);
    expect(captured?.type, CapturedMediaType.image);
    handle.dispose();
  });

  testWidgets('a failed stop resets the camera instead of freezing it (01 #15)',
      (tester) async {
    final platform = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    )..stopError = CameraException('IOError', 'AVAssetWriter could not finish writing');
    CameraPlatform.instance = platform;
    var captured = 0;
    await pumpToReady(
      tester,
      CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (_) => captured++),
    );
    final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(captured, 0);
    expect(find.text('Could not save that recording.'), findsOneWidget);
    expect(find.byTooltip('Close camera'), findsOneWidget,
        reason: 'Close must come back, the only way out before this fix was the edge swipe');
    expect(find.byKey(const ValueKey('streak-elapsed')), findsNothing,
        reason: 'the counter must not stay frozen on screen');
  });

  testWidgets('after a failed stop the next hold records again (01 #15)',
      (tester) async {
    // The plugin leaves its controller marked "recording" when the native
    // stop throws, so every later start would fail with "Could not start
    // recording." unless the controller is rebuilt.
    final platform = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    )..stopError = CameraException('IOError', 'writer failed');
    CameraPlatform.instance = platform;
    var captured = 0;
    await pumpToReady(
      tester,
      CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (_) => captured++),
    );
    Future<void> holdFor(int ticks) async {
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump();
      for (var i = 0; i < ticks; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await hold.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await holdFor(8);
    expect(captured, 0);
    platform.stopError = null;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await holdFor(8);
    expect(platform.startVideoCalls, 2);
    expect(find.text('Could not start recording.'), findsNothing);
    expect(captured, 1);
  });

  testWidgets('a busy shutter ignores a screen-reader tap (review #1)',
      (tester) async {
    final handle = tester.ensureSemantics();
    final platform = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    );
    CameraPlatform.instance = platform;
    final gate = Completer<void>();
    final key = GlobalKey<CaptureCameraScreenState>();
    var captures = 0;
    await pumpToReady(
      tester,
      CaptureCameraScreen(
        key: key,
        allow: CaptureKinds.photoAndVideo,
        imagePreparerFactory: () => fakes.FakeImagePreparer(gate: gate),
        onCaptured: (m) {
          captures++;
          unawaited(key.currentState!.confirmSend(m).catchError((_) => m));
        },
      ),
    );

    // A screen reader's double-tap, sent whether or not the node offers it.
    Future<void> srTap() async {
      tester.semantics.performAction(
        find.semantics.byLabel('Take photo, hold for video'),
        SemanticsAction.tap,
        checkForAction: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    await srTap();
    expect(platform.takePictureCalls, 1);
    expect(captures, 1);
    // The send is in flight (the preparer is gated): the shutter is busy.
    await srTap();
    expect(platform.takePictureCalls, 1,
        reason: 'a busy shutter must ignore a semantic tap');
    expect(captures, 1);
    gate.complete();
    await tester.pump();
    handle.dispose();
  });

  testWidgets('Open Settings is offered only for a permission refusal (review #5)',
      (tester) async {
    Future<void> boot(String code) async {
      CameraPlatform.instance = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..cameraDenied = CameraException(code, 'failed');
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          openSettings: () async {},
          onCaptured: (_) {},
          onCancelled: () {},
        ),
      );
    }

    await boot('CameraPermissionsRequestOngoing');
    expect(find.byTooltip('Close camera'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing,
        reason: 'Settings cannot fix a camera that is busy or broken');

    await boot('CameraAccessDeniedWithoutPrompt');
    expect(find.text('Open Settings'), findsOneWidget);

    await boot('AudioAccessDenied');
    expect(find.text('Open Settings'), findsOneWidget,
        reason: 'a refused microphone is fixed in Settings too');
  });

  testWidgets('repeated holds with the mic denied show one notice, not a queue '
      '(review #4)', (tester) async {
    CameraPlatform.instance = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    )..audioDenied = CameraException('AudioAccessDenied', 'denied');
    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.photoAndVideo,
        microphoneOptional: true,
        copy: const CaptureCameraCopy(videoNeedsMicrophone: 'MIC NEEDED'),
        onCaptured: (_) {},
      ),
    );
    for (var i = 0; i < 3; i++) {
      final hold = await tester.startGesture(
        tester.getCenter(find.byType(StreakRecordButton)),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await hold.up();
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('MIC NEEDED'), findsOneWidget);

    // One snackbar's lifetime (4 s plus its animations), not three.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('MIC NEEDED'), findsNothing);
  });

  testWidgets('a camera that cannot restart after a failed stop shows the error '
      'screen, not a forever-busy shutter (review #6)', (tester) async {
    final platform = fakes.FakeCameraPlatform(
      videoPath: await writeFile(tester, 'clip.mp4'),
      photoPath: await writeFile(tester, 'photo.jpg'),
    )..stopError = CameraException('IOError', 'writer failed');
    CameraPlatform.instance = platform;
    var cancelled = 0;
    await pumpToReady(
      tester,
      CaptureCameraScreen(
        allow: CaptureKinds.videoOnly,
        onCaptured: (_) {},
        onCancelled: () => cancelled++,
      ),
    );
    // The rebuild's create fails: the camera went away mid-take.
    platform.cameraDenied = CameraException('CameraUnavailable', 'gone');
    final hold = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await hold.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(platform.createCalls, 2, reason: 'the rebuild was attempted');
    expect(find.byType(StreakRecordButton), findsNothing);
    expect(find.text('Attune needs camera access to record a streak.'), findsOneWidget);
    expect(find.text('Open Settings'), findsNothing);
    await tester.tap(find.byTooltip('Close camera'));
    await tester.pump();
    expect(cancelled, 1);
  });

  group('lifecycle (01 #15, Review Focus 4)', () {
    void background(WidgetTester tester) =>
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    void foreground(WidgetTester tester) =>
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    testWidgets('inactive releases the camera; resumed brings it back', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(tester, const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo));
      expect(platform.createCalls, 1);

      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 1);

      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 2);
      expect(find.byType(StreakRecordButton), findsOneWidget);
    });

    testWidgets('a return that stops at the Safety lock check re-opens the '
        'camera only once the lock opens (stories Wave 3)', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(
        tester,
        const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CaptureCameraScreen)),
      );
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 1);

      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 1, reason: 'no camera behind the PIN check');

      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, 2);
      expect(find.byType(StreakRecordButton), findsOneWidget);
    });

    testWidgets('a call mid-hold keeps the take recorded so far', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      CapturedMedia? captured;
      await pumpToReady(
        tester,
        CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (m) => captured = m),
      );
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      background(tester); // the phone rings
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Kept by the inactive itself, before the finger lifts (the gesture
      // cancel below stops a take on its own, so it cannot prove this).
      expect(platform.stopVideoCalls, 1, reason: 'stopped on inactive');
      expect(captured?.type, CapturedMediaType.video);
      await hold.cancel();

      expect(platform.stopVideoCalls, 1);
      expect(captured?.type, CapturedMediaType.video);
      expect(captured!.durationMs, greaterThanOrEqualTo(500));
    });

    testWidgets('an inactive during the first permission prompt does not start '
        'two cameras', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: const CaptureCameraScreen(allow: CaptureKinds.photoAndVideo)),
      ));
      background(tester); // iOS shows the camera prompt: willResignActive
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls - platform.disposeCalls, 1,
          reason: 'exactly one live controller');
    });

    // Batch-5 review #3: the snackbar's Settings leads somewhere that must
    // fix itself on return, without reopening the camera.
    testWidgets('a microphone allowed in Settings is picked up on return: '
        'video works without reopening', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      CapturedMedia? captured;
      var micGranted = false;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          microphoneOptional: true,
          copy: const CaptureCameraCopy(videoNeedsMicrophone: 'MIC NEEDED'),
          onCaptured: (m) => captured = m,
          permissionGranted: (p) async => p == Permission.microphone && micGranted,
        ),
      );
      expect(platform.settings.map((s) => s.enableAudio), [true, false]);

      background(tester); // off to Settings
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      platform.audioDenied = null; // the microphone is allowed there
      micGranted = true;
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(platform.settings.last.enableAudio, isTrue,
          reason: 'the camera came back with audio');
      expect(platform.createCalls - platform.disposeCalls, 1);
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 350));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await hold.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.startVideoCalls, 1);
      expect(find.text('MIC NEEDED'), findsNothing);
      expect(captured?.type, CapturedMediaType.video);
    });

    testWidgets('a microphone still refused on return falls back to photos '
        'again, not the error screen', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          microphoneOptional: true,
          onCaptured: (_) {},
          permissionGranted: (_) async => false,
        ),
      );
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Review #2 (fix round 2): audio is not tried again unless the
      // permission changed. On Android each try shows the system dialog.
      expect(platform.settings.map((s) => s.enableAudio), [true, false, false],
          reason: 'one no-audio session, no audio retry');
      expect(find.byType(StreakRecordButton), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    for (final cancelFirst in [false, true]) {
      testWidgets('the touch cancel and the inactive of one interruption stop '
          'the take once and keep it (review #1, '
          '${cancelFirst ? 'cancel first' : 'inactive first'})', (tester) async {
        final platform = _GatedCameraPlatform(
          videoPath: await writeFile(tester, 'clip.mp4'),
          photoPath: await writeFile(tester, 'photo.jpg'),
        )..stopGate = Completer<void>();
        CameraPlatform.instance = platform;
        addTearDown(() => foreground(tester));
        CapturedMedia? captured;
        await pumpToReady(
          tester,
          CaptureCameraScreen(allow: CaptureKinds.videoOnly, onCaptured: (m) => captured = m),
        );
        final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
        await tester.pump();
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Control Centre / a call: the OS cancels the touch as the app goes
        // inactive, with no frame in between.
        if (cancelFirst) {
          await hold.cancel();
          background(tester);
        } else {
          background(tester);
          await hold.cancel();
        }
        await tester.pump();
        platform.stopGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(platform.stopVideoCalls, 1);
        expect(captured?.type, CapturedMediaType.video);
        expect(captured!.durationMs, greaterThanOrEqualTo(500));
        expect(find.text('Could not save that recording.'), findsNothing);
      });
    }

    testWidgets('an inactive while a recording is starting waits for the start, '
        'then ends it without closing the camera (review #3)', (tester) async {
      final platform = _GatedCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..startGate = Completer<void>();
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      var cancelled = 0;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.videoOnly,
          onCaptured: (_) {},
          onCancelled: () => cancelled++,
        ),
      );
      final hold = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump();
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 0, reason: 'never released under the start');

      platform.startGate!.complete();
      // The too-short take is deleted with real file I/O: let it finish.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 50));
      await hold.cancel();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(platform.stopVideoCalls, 1, reason: 'the started take was ended');
      expect(platform.disposeCalls, 1);
      expect(cancelled, 0, reason: 'an interruption does not close the camera');

      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final again = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(platform.startVideoCalls, 2, reason: 'the camera records again');
      await again.up();
      await tester.pump();
    });

    testWidgets('an inactive while a photo is being taken keeps the photo '
        '(review #4)', (tester) async {
      final platform = _GatedCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..photoGate = Completer<void>();
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      CapturedMedia? captured;
      await pumpToReady(
        tester,
        CaptureCameraScreen(allow: CaptureKinds.photoAndVideo, onCaptured: (m) => captured = m),
      );
      final tap = await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
      await tester.pump(const Duration(milliseconds: 100));
      await tap.up();
      await tester.pump();
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.disposeCalls, 0, reason: 'never released under the shutter');

      platform.photoGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(captured?.type, CapturedMediaType.image);
      expect(find.text('Could not take that photo.'), findsNothing);
      expect(platform.disposeCalls, 1);
    });

    testWidgets('a camera busy on return (a call still holding it) is retried '
        'on the next return, not left on the error screen (review #5)', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          onCaptured: (_) {},
          permissionGranted: (_) async => true,
        ),
      );
      Future<void> cycle() async {
        background(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        foreground(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      platform.cameraDenied = CameraException('CameraUnavailable', 'in use');
      await cycle();
      expect(find.byType(StreakRecordButton), findsNothing);
      expect(find.byTooltip('Close camera'), findsOneWidget);

      platform.cameraDenied = null; // the call ended
      await cycle();
      expect(find.byType(StreakRecordButton), findsOneWidget);
      expect(platform.createCalls - platform.disposeCalls, 1);
    });

    testWidgets('a retry on return that fails with something other than a '
        'CameraException lands on the error screen, never a blank one '
        '(batch-6 re-review)', (tester) async {
      final platform = _OtherFailurePlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      );
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      var cancelled = 0;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          onCaptured: (_) {},
          onCancelled: () => cancelled++,
          permissionGranted: (_) async => true,
        ),
      );
      Future<void> cycle() async {
        background(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        foreground(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      platform.cameraDenied = CameraException('CameraUnavailable', 'in use');
      await cycle();
      expect(find.byTooltip('Close camera'), findsOneWidget);

      platform
        ..cameraDenied = null
        ..other = StateError('plugin went away');
      await cycle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StreakRecordButton), findsNothing);
      expect(find.byTooltip('Close camera'), findsOneWidget);
      await tester.tap(find.byTooltip('Close camera'));
      await tester.pump();
      expect(cancelled, 1);
    });

    testWidgets('a first open that fails with something other than a '
        'CameraException shows the error screen too', (tester) async {
      final platform = _OtherFailurePlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..other = StateError('plugin went away');
      CameraPlatform.instance = platform;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          onCaptured: (_) {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Close camera'), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('a camera allowed in Settings comes back on return; while it '
        'is still refused nothing is retried (review #5)', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..cameraDenied = CameraException('CameraAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      var cameraGranted = false;
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.photoAndVideo,
          onCaptured: (_) {},
          permissionGranted: (p) async => p == Permission.camera && cameraGranted,
        ),
      );
      expect(find.text('Open Settings'), findsOneWidget);
      final creates = platform.createCalls;
      Future<void> cycle() async {
        background(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        foreground(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }

      await cycle(); // back from Settings without allowing it
      expect(platform.createCalls, creates, reason: 'no new attempt while refused');
      expect(find.text('Open Settings'), findsOneWidget);

      platform.cameraDenied = null;
      cameraGranted = true;
      await cycle();
      expect(find.byType(StreakRecordButton), findsOneWidget);
      expect(find.text('Open Settings'), findsNothing);
    });

    testWidgets('a streak camera refused the microphone does not ask again on '
        'every return (review #2)', (tester) async {
      final platform = fakes.FakeCameraPlatform(
        videoPath: await writeFile(tester, 'clip.mp4'),
        photoPath: await writeFile(tester, 'photo.jpg'),
      )..audioDenied = CameraException('AudioAccessDenied', 'denied');
      CameraPlatform.instance = platform;
      addTearDown(() => foreground(tester));
      await pumpToReady(
        tester,
        CaptureCameraScreen(
          allow: CaptureKinds.videoOnly,
          onCaptured: (_) {},
          permissionGranted: (_) async => false,
        ),
      );
      final creates = platform.createCalls;
      background(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      foreground(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(platform.createCalls, creates);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });
}

/// Throws [other] (not a CameraException) from create when set.
class _OtherFailurePlatform extends fakes.FakeCameraPlatform {
  _OtherFailurePlatform({required super.videoPath, required super.photoPath});

  Object? other;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) {
    final failure = other;
    if (failure != null) throw failure;
    return super.createCameraWithSettings(description, mediaSettings);
  }
}
