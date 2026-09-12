// Streak photos (spec §6.3 step 3): the streak camera adapter now passes
// CaptureKinds.photoAndVideo, so a short tap takes a photo instead of
// always recording video. This suite proves the PHOTO half of that split
// reaches sendStreakMessage with the right shape — the video half is
// already covered end-to-end by streak_camera_contract_test.dart, and
// that suite's own 5 tests must stay green and unweakened (see this
// task's own report for the timing fix that required — the 300ms hold
// threshold now subtracts from recorded duration, which is a real
// consequence of switching CaptureKinds, not a loosened assertion).
//
// Mirrors streak_camera_contract_test.dart's harness shape closely
// (same _FakeCameraPlatform base, same bootContainer/buildHarness/
// pumpToReady pattern) and story_camera_test.dart's photo-specific pieces
// (tapShutter's short press, a REAL decodable JPEG fixture so
// CaptureImagePreparer's decode step does not reject it, and the
// _FakeCaptureImagePreparer seam for flutter_image_compress, which has no
// platform channel on a test host).

import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_camera_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

/// Fake CameraPlatform covering both takePicture() (the photo half) and
/// stopVideoRecording() (the video half, unused by these tests but kept
/// so a stray videoOnly-shaped path in shared code does not throw).
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform({required this.photoPath});

  final String photoPath;
  int _nextCameraId = 0;
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
        '${invocation.memberName} is not used by this photo-path suite',
      );
}

class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _nextPlayerId++;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => const Stream.empty();

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this photo-path suite',
      );
}

class _FakeStreakRepository implements StreakRepository {
  final List<
    ({
      String messageId,
      String mediaUrl,
      int durationMs,
      StreakClipKind mediaKind,
    })
  >
  attachClipCalls = [];

  @override
  Future<void> attachClip({
    required String messageId,
    required String mediaUrl,
    required int durationMs,
    StreakClipKind mediaKind = StreakClipKind.video,
  }) async {
    attachClipCalls.add((
      messageId: messageId,
      mediaUrl: mediaUrl,
      durationMs: durationMs,
      mediaKind: mediaKind,
    ));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for CaptureImagePreparer, mirroring story_camera_test.dart's
/// own fake: copies the source byte-for-byte rather than actually
/// compressing (flutter_image_compress has no platform channel on a test
/// host), asserting the output CONTRACT rather than real compression.
class _FakeCaptureImagePreparer extends CaptureImagePreparer {
  _FakeCaptureImagePreparer({this.rejection});

  /// When set, prepare() throws this instead of succeeding — mirrors
  /// streak_camera_contract_test.dart's _FakeChatVideoPreparer.rejection,
  /// the same seam used there to exercise the video-rejection path
  /// without depending on real dart:io timing inside FakeAsync.
  final CaptureImageRejected? rejection;

  final List<String> preparedPaths = [];

  @override
  Future<PreparedCaptureImage> prepare(String localPath) async {
    preparedPaths.add(localPath);
    final rejected = rejection;
    if (rejected != null) throw rejected;
    final bytes = File(localPath).readAsBytesSync();
    final outPath = '$localPath.prepared.jpg';
    File(outPath).writeAsBytesSync(bytes);
    return PreparedCaptureImage(
      file: File(outPath),
      mimeType: 'image/jpeg',
      byteSize: bytes.length,
      width: 32,
      height: 32,
    );
  }
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  late Directory tempDir;
  late CameraPlatform originalCameraPlatform;
  late VideoPlayerPlatform originalVideoPlayerPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('streak_photo_test');
    originalCameraPlatform = CameraPlatform.instance;
    originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    CameraPlatform.instance = originalCameraPlatform;
    VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// A REAL, decodable JPEG. CaptureImagePreparer's confirmSend() path
  /// (through the streak review sheet's Send tap) decodes the file it is
  /// given — junk bytes reject with CaptureImageRejected before ever
  /// reaching the outbox, exactly as story_camera_test.dart's own comment
  /// on this same fixture documents.
  Future<String> writeJpegFile(WidgetTester tester, String name) async {
    final path = '${tempDir.path}/$name';
    await tester.runAsync(() async {
      final image = img.Image(width: 32, height: 32);
      img.fill(image, color: img.ColorRgb8(200, 100, 50));
      final bytes = img.encodeJpg(image, quality: 90);
      await File(path).writeAsBytes(bytes);
    });
    return path;
  }

  Future<ProviderContainer> bootContainer({
    required FakeChatRepository repository,
    required String userId,
    required _FakeStreakRepository streakRepository,
    List<Override> extraOverrides = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return buildChatContainer(
      repository: repository,
      userId: userId,
      extraOverrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        streakRepositoryProvider.overrideWithValue(streakRepository),
        soundServiceProvider.overrideWithValue(FakeSoundService()),
        ...extraOverrides,
      ],
    );
  }

  Widget buildHarness(ProviderContainer container, Widget screen) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => context.push('/streak-camera'),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
        GoRoute(path: '/streak-camera', builder: (context, state) => screen),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpToReady(
    WidgetTester tester,
    ProviderContainer container,
    Widget screen,
  ) async {
    await tester.pumpWidget(buildHarness(container, screen));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// A short tap — well under the 300ms hold threshold (spec §6.2) — so
  /// release fires _takePicture rather than starting a recording.
  Future<void> tapShutter(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Lets _onCaptured -> _openReviewGuarded's async chain (which shows
    // the review sheet as a static image, no video decoder involved)
    // settle before the test looks for the Send button.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpAfterSend(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets(
    'a short tap takes a photo and reaches sendStreakMessage as image/jpeg '
    'with duration 0',
    (tester) async {
      final photoPath = await writeJpegFile(tester, 'photo.jpg');
      final cameraPlatform = _FakeCameraPlatform(photoPath: photoPath);
      CameraPlatform.instance = cameraPlatform;
      final imagePreparer = _FakeCaptureImagePreparer();
      final streakRepo = _FakeStreakRepository();

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(
        repository: repo,
        userId: userId,
        streakRepository: streakRepo,
      );
      addTearDown(container.dispose);
      container.read(chatControllerProvider(convo).notifier);

      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          imagePreparerFactory: () => imagePreparer,
        ),
      );

      await tapShutter(tester);

      expect(
        cameraPlatform.takePictureCalls,
        1,
        reason: 'a short tap must take a photo, not start a recording',
      );
      expect(find.text('Send'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      expect(imagePreparer.preparedPaths.single, photoPath);

      expect(repo.sendCallCount, 1);
      final sent = repo.serverMessages.values.single;
      expect(sent.mediaType, 'streak');
      expect(
        sent.mediaDurationMs,
        0,
        reason:
            'a photo streak stores duration_ms = 0 honestly rather than '
            'a fabricated or null length',
      );

      // The clip attaches with media_kind = photo — the explicit
      // discriminator this task added, proven at the actual boundary
      // (attachClip) rather than inferred from duration_ms alone.
      expect(streakRepo.attachClipCalls.single.mediaKind, StreakClipKind.photo);
      expect(streakRepo.attachClipCalls.single.durationMs, 0);

      expect(find.byType(StreakCameraScreen), findsNothing);
    },
  );

  testWidgets(
    'a photo streak gets the same view budget as a video streak for the '
    'same replay preference',
    (tester) async {
      final photoPath = await writeJpegFile(tester, 'photo.jpg');
      CameraPlatform.instance = _FakeCameraPlatform(photoPath: photoPath);
      final imagePreparer = _FakeCaptureImagePreparer();
      final streakRepo = _FakeStreakRepository();

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(
        repository: repo,
        userId: userId,
        streakRepository: streakRepo,
        extraOverrides: [
          streakReplayPreferenceProvider.overrideWith(
            (ref) => StreakReplayPreferenceNotifier.forTesting(true),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(chatControllerProvider(convo).notifier);

      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          imagePreparerFactory: () => imagePreparer,
        ),
      );

      await tapShutter(tester);
      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      final sent = repo.serverMessages.values.single;
      expect(
        sent.streakViewsRemaining,
        streakViewBudget(allowReplays: true),
        reason:
            'the view budget is a user preference (streakViewBudget), not '
            'a per-media-type constant — a photo streak must inherit it '
            'unchanged, exactly like a video streak does',
      );
    },
  );

  testWidgets(
    'a rejected photo prepare shows the streak message and stays, never '
    'reaching the chat controller',
    (tester) async {
      final photoPath = await writeJpegFile(tester, 'photo.jpg');
      CameraPlatform.instance = _FakeCameraPlatform(photoPath: photoPath);
      // Scripted rejection rather than a real corrupt file: CaptureImagePreparer
      // does genuine dart:io I/O with no seam to run it through runAsync from
      // inside the widget's own gesture callback (streak_camera_contract_test.dart's
      // _FakeChatVideoPreparer.rejection is the established house pattern for
      // exercising a prepare-rejection path deterministically under FakeAsync).
      final imagePreparer = _FakeCaptureImagePreparer(
        rejection: const CaptureImageRejected('media_decode_failed'),
      );

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(
        repository: repo,
        userId: userId,
        streakRepository: _FakeStreakRepository(),
      );
      addTearDown(container.dispose);
      container.read(chatControllerProvider(convo).notifier);

      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          imagePreparerFactory: () => imagePreparer,
        ),
      );

      await tapShutter(tester);
      expect(find.text('Send'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      expect(find.text('That streak could not be sent.'), findsOneWidget);
      expect(
        find.byType(StreakCameraScreen),
        findsOneWidget,
        reason: 'a rejected photo prepare must not pop the camera',
      );
      expect(
        repo.sendCallCount,
        0,
        reason:
            'a rejected photo prepare must never reach the chat controller',
      );
    },
  );
}
