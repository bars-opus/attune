// Camera and preparer doubles for the Wave 2 story-camera suites. The older
// capture_camera_test.dart / story_camera_test.dart keep their own.
import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import 'outbox_fakes.dart';

class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform({required this.videoPath, required this.photoPath});

  final String videoPath;
  final String photoPath;
  int _nextCameraId = 0;
  int createCalls = 0;
  int disposeCalls = 0;
  int takePictureCalls = 0;
  int startVideoCalls = 0;
  int stopVideoCalls = 0;
  final settings = <MediaSettings>[];

  /// Thrown from create when the settings ask for audio (mic denied).
  CameraException? audioDenied;

  /// Thrown from create always (camera denied).
  CameraException? cameraDenied;

  /// Thrown from stopVideoRecording.
  CameraException? stopError;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
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
    createCalls++;
    settings.add(mediaSettings);
    if (cameraDenied != null) throw cameraDenied!;
    if (mediaSettings.enableAudio && audioDenied != null) throw audioDenied!;
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
    startVideoCalls++;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopVideoCalls++;
    if (stopError != null) throw stopError!;
    return XFile(videoPath);
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    takePictureCalls++;
    return XFile(photoPath);
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

/// Sync file I/O on purpose: testWidgets' FakeAsync zone never completes an
/// async dart:io future without runAsync (story_camera_test.dart header).
class FakeImagePreparer extends CaptureImagePreparer {
  FakeImagePreparer({this.suffix = 'prepared', this.gate, this.rejectWith});
  final String suffix;
  final Completer<void>? gate;
  final String? rejectWith;
  int calls = 0;

  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    calls++;
    await gate?.future;
    if (rejectWith != null) throw CaptureImageRejected(rejectWith!);
    final bytes = File(localPath).readAsBytesSync();
    final out = File('$localPath.$suffix.jpg')..writeAsBytesSync(bytes);
    return PreparedCaptureImage(
      file: out,
      mimeType: 'image/jpeg',
      byteSize: bytes.length,
      width: 32,
      height: 32,
    );
  }
}

class FakeVideoPreparer extends ChatVideoPreparer {
  FakeVideoPreparer({this.rejectWith});
  final String? rejectWith;

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
    if (rejectWith != null) throw ChatVideoRejected(rejectWith!);
    final out = File('$localPath.out.mp4')
      ..writeAsBytesSync(File(localPath).readAsBytesSync());
    return PreparedChatVideo(
      file: out,
      mimeType: 'video/mp4',
      byteSize: 1024,
      durationMs: 4000,
      thumbnailFile: out,
      thumbnailMimeType: 'image/jpeg',
      thumbnailByteSize: 1,
      width: 720,
      height: 1280,
    );
  }
}

Future<String> writeJpeg(
  WidgetTester tester,
  Directory dir,
  String name,
) async {
  final path = '${dir.path}/$name';
  await tester.runAsync(() async {
    final image = img.Image(width: 32, height: 32);
    img.fill(image, color: img.ColorRgb8(200, 100, 50));
    await File(path).writeAsBytes(img.encodeJpg(image, quality: 90));
  });
  return path;
}

typedef StoryCameraHarness =
    ({
      ProviderContainer container,
      StoryOutboxStore store,
      ScriptedStoryGateway gateway,
      Directory support,
    });

/// A signed-in container whose uploads are held open (so queued rows stay
/// put), with the vault rooted under [root]/support and the couple map off.
StoryCameraHarness storyCameraContainer(
  Directory root, {
  bool cipherUnavailable = false,
  List<Override> extra = const [],
}) {
  final support = Directory('${root.path}/support')
    ..createSync(recursive: true);
  final store = StoryOutboxStore.forTesting(
    stub.createStoryOutboxBackend(),
    cipherUnavailable: cipherUnavailable,
  );
  final gateway = ScriptedStoryGateway()..uploadGate = Completer<void>();
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(outboxUser()),
      storyOutboxStoreProvider.overrideWithValue(store),
      storyGatewayProvider.overrideWithValue(gateway),
      storyMediaVaultProvider.overrideWithValue(
        StoryMediaVault(supportDirectory: () async => support),
      ),
      coupleMapEnabledProvider.overrideWith((ref) async => false),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    store: store,
    gateway: gateway,
    support: support,
  );
}

/// Opens [screen] through go_router, the way the app does, and settles the
/// camera's async init with bounded pumps (an indeterminate spinner would
/// hang pumpAndSettle).
Future<void> pumpStoryCamera(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/camera'),
                  child: const Text('open'),
                ),
              ),
            ),
      ),
      GoRoute(path: '/camera', builder: (context, state) => screen),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> tapShutterOnly(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(StreakRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Lets the real file I/O a Share does (vault create/rename, raw delete)
/// complete. Inside testWidgets' FakeAsync zone each sequential dart:io
/// await needs a real-time wait (the callback arrives) AND a pump (the fake
/// zone's microtasks run), so this alternates the two. If a test still
/// stalls at the vault move, raise [cycles]; do not make the vault sync.
Future<void> settleIo(WidgetTester tester, [int cycles = 10]) async {
  for (var i = 0; i < cycles; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}
