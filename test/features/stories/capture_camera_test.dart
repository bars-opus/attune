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

import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/capture_camera_screen.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  ) async => _nextCameraId++;

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
}
