// Characterization suite for StreakCameraScreen (Plan B, Task 1).
//
// Pins today's behaviour at the six verified coupling points BEFORE later
// tasks extract the capture half into a shared module:
//   line 31  (widget ctor)  — requires a Conversation
//   line 250 / 303          — AppSound.streakCaptureReady
//   line 372                — reads streakReplayPreferenceProvider
//   line 410                — sends through chatControllerProvider
//   line 414                — streakViewBudget(allowReplays:)
//   line 417                — AppSound.streakSend
//
// These tests MUST pass against unchanged screen behaviour. A failure here
// means the test is wrong, not the code — do not "fix" the screen to make
// a test pass.
//
// Two fakes stand in for hardware that widget tests cannot use:
//
//  - _FakeCameraPlatform replaces CameraPlatform.instance (the camera
//    plugin's own platform-interface seam — no change to shipped code,
//    same pattern as this suite's PathProviderPlatform.instance swap and
//    the existing _FakePathProviderPlatform in
//    chat_state_send_video_message_test.dart) so _initCamera/_startPreview
//    can complete without a device.
//
//  - _FakeChatVideoPreparer stands in for ChatVideoPreparer. This DID
//    require a small seam on the shipped screen: StreakCameraScreen now
//    takes an optional `videoPreparerFactory` constructor parameter,
//    defaulting to the real ChatVideoPreparer.new — the same shape as
//    ChatTextField's existing `recorderFactory` seam. Without it, _send()
//    always fails: video_compress has no platform channel on a test host,
//    so VideoCompress.getMediaInfo throws and ChatVideoPreparer.prepare
//    unconditionally rejects with 'media_decode_failed' — the success path
//    (capture -> prepare -> sendStreakMessage) would be permanently
//    unreachable from a widget test otherwise.

import 'dart:io';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/streak_camera_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:attune/features/settings/data/streak_replay_preference.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

/// A minimal fake CameraPlatform so CameraController.initialize(),
/// startVideoRecording() and stopVideoRecording() can run without a
/// device. Implements exactly the surface StreakCameraScreen's flow
/// touches (availableCameras -> createCameraWithSettings ->
/// onCameraInitialized/initializeCamera -> startVideoCapturing ->
/// stopVideoRecording -> dispose); anything else throws loudly via
/// noSuchMethod, mirroring the _BlockingPosterCacheManager pattern in
/// chat_state_send_video_message_test.dart.
class _FakeCameraPlatform extends CameraPlatform {
  _FakeCameraPlatform(this.recordedFilePath);

  /// Path handed back from every stopVideoRecording() call. The screen
  /// treats it as the segment it just captured.
  final String recordedFilePath;

  int _nextCameraId = 0;
  final Set<int> recordingCameraIds = {};
  int stopVideoRecordingCalls = 0;

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
    recordingCameraIds.add(options.cameraId);
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    stopVideoRecordingCalls++;
    recordingCameraIds.remove(cameraId);
    return XFile(recordedFilePath);
  }

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Widget buildPreview(int cameraId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this characterization '
        'suite',
      );
}

/// Fakes VideoPlayerPlatform for the streak review's preview.
///
/// The default VideoPlayerPlatform.instance (_PlaceholderImplementation)
/// throws UnimplementedError from createWithOptions() before
/// VideoPlayerController's own _creatingCompleter is ever completed —
/// which the screen's _startPreview_ catches around initialize(), BUT
/// VideoPlayerController.dispose() (called in that same catch block)
/// unconditionally awaits that same _creatingCompleter first. A
/// never-completed completer means dispose() hangs forever, silently,
/// inside the screen's unawaited() review flow — no test seam or pump
/// count fixes that; a stand-in platform is the only way createWithOptions
/// can succeed so _creatingCompleter completes, letting initialize() fail
/// (and dispose() return) the way it does when video_player's own iOS/
/// Android backend is actually present.
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
  Stream<VideoEvent> videoEventsFor(int playerId) {
    // Mirrors a real decode failure: VideoPlayerController's own
    // errorListener expects exactly a PlatformException here and turns it
    // into initialize()'s rejection — the same path a corrupt/unsupported
    // file takes on a real device.
    return Stream.error(
      PlatformException(
        code: 'video_error',
        message: 'characterization stub: no real decoder',
      ),
    );
  }

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this characterization '
        'suite',
      );
}

/// Stands in for StreakRepository, whose real attachClip() hits
/// Supabase.instance.client — never initialized in a widget test.
/// ChatController._attemptSend calls attachClip() right after a streak
/// message's canonical insert (see chat_state.dart around
/// streakRepositoryProvider), so without this override every send in this
/// suite fails inside that call and never reaches sendCallCount.
class _FakeStreakRepository implements StreakRepository {
  final List<({String messageId, String mediaUrl, int durationMs})>
  attachClipCalls = [];

  @override
  Future<void> attachClip({
    required String messageId,
    required String mediaUrl,
    required int durationMs,
  }) async {
    attachClipCalls.add((
      messageId: messageId,
      mediaUrl: mediaUrl,
      durationMs: durationMs,
    ));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the real ChatVideoPreparer (see file header). Scripts a
/// success or a ChatVideoRejected, and records exactly what localPath it
/// was called with.
class _FakeChatVideoPreparer extends ChatVideoPreparer {
  _FakeChatVideoPreparer({this.rejection});

  /// When set, prepare() throws this instead of succeeding.
  final ChatVideoRejected? rejection;

  final List<String> preparedPaths = [];
  int calls = 0;

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
    calls++;
    preparedPaths.add(localPath);
    final rejected = rejection;
    if (rejected != null) throw rejected;
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
  const userId = 'user-a';
  const relId = 'rel-1';

  late Directory tempDir;
  late CameraPlatform originalCameraPlatform;
  late VideoPlayerPlatform originalVideoPlayerPlatform;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('streak_camera_test');
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

  /// Writes a small fake clip file for the fake camera/preparer to point
  /// at. Runs via tester.runAsync: testWidgets bodies execute inside a
  /// package:fake_async FakeAsync zone (AutomatedTestWidgetsFlutterBinding),
  /// and real dart:io File I/O started directly inside that zone never
  /// completes — its completion arrives through the real event loop, which
  /// the fake zone does not pump. runAsync briefly runs its callback in the
  /// real zone so the write actually finishes. (setUp/tearDown are NOT
  /// affected: those callbacks run outside the per-test FakeAsync zone,
  /// which is why the tempDir.createTemp() above needs no such wrapping.)
  Future<String> writeFile(
    WidgetTester tester,
    String name, {
    int bytes = 128,
  }) async {
    final path = '${tempDir.path}/$name';
    await tester.runAsync(() => File(path).writeAsBytes(List.filled(bytes, 1)));
    return path;
  }

  /// buildChatContainer plus a real sharedPreferencesProvider override.
  ///
  /// The screen's _playSound reads messageSoundsEnabledProvider, which
  /// watches sharedPreferencesProvider — left un-overridden, every
  /// _onPressEnd throws "sharedPreferencesProvider not initialized"
  /// inside its own unawaited() call, which swallows the exception with
  /// no console output whatsoever (the screen's own documented risk,
  /// see _openReviewGuarded's doc comment) and quietly stops the take
  /// from ever reaching the review sheet.
  ///
  /// Also defaults soundServiceProvider to a FakeSoundService: the real
  /// one's preload() hits a real audioplayers platform channel that
  /// throws MissingPluginException asynchronously on this test host, and
  /// Flutter's test framework fails the test over that alone even when
  /// every assertion in it passed. Tests that care about which sounds
  /// play override it again via extraOverrides (spread last, so it wins).
  Future<ProviderContainer> bootContainer({
    required FakeChatRepository repository,
    required String userId,
    List<Override> extraOverrides = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return buildChatContainer(
      repository: repository,
      userId: userId,
      extraOverrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        streakRepositoryProvider.overrideWithValue(_FakeStreakRepository()),
        soundServiceProvider.overrideWithValue(FakeSoundService()),
        ...extraOverrides,
      ],
    );
  }

  /// Wraps the screen the way the real app router does: a route it can
  /// context.pop() back out of. Mirrors
  /// ephemeral_video_viewer_screen_test.dart's buildHarness.
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

  /// Boots the screen inside its harness, opens the streak camera route,
  /// and settles the camera's async init so the record button is ready.
  ///
  /// Deliberately bounded pump()s rather than pumpAndSettle(): the record
  /// button shows an INDETERMINATE CircularProgressIndicator while
  /// isPreparing/isSending, which schedules a frame forever and hangs
  /// pumpAndSettle() outright, regardless of how quickly the fake camera
  /// finishes initializing underneath it.
  Future<void> pumpToReady(
    WidgetTester tester,
    ProviderContainer container,
    Widget screen,
  ) async {
    await tester.pumpWidget(buildHarness(container, screen));
    await tester.tap(find.text('open'));
    // Completes the GoRouter push's ~300ms MaterialPageRoute transition
    // (ephemeral_video_viewer_screen_test.dart's own pattern) then lets
    // _initCamera -> availableCameras -> _startPreview -> initialize()
    // resolve against the fake CameraPlatform.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Drives one full press-record-release-send take through the real
  /// gesture handlers, ending on the review sheet's Send button.
  Future<void> recordAndReachReviewSheet(WidgetTester tester) async {
    // A raw Listener drives the record button (see StreakRecordButton's
    // own doc comment on why: pan gestures don't report an end for a
    // press with no movement). Drive the same Listener via a low-level
    // gesture so both onPressStart and onPressEnd fire, exactly as a
    // real press-and-release does.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(StreakRecordButton)),
    );
    await tester.pump();

    // CaptureCameraScreen's ticker reads clock.now() (package:clock)
    // rather than DateTime.now() directly (Plan B, Task 2 fix round 1),
    // so inside this FakeAsync zone it tracks the FAKE clock — a single
    // pump(duration) both advances "held time" past
    // kStreakMinFirstSegment (500ms) AND fires the pending Timer.periodic
    // that reads it, with no real wall-clock wait needed. The previous
    // version of this helper used tester.runAsync() to let 600ms of REAL
    // time pass for exactly this computation; that real-clock wait is
    // what intermittently exceeded the test framework's per-test timeout
    // under a full, contended `flutter test` run (many isolates
    // competing for the real event loop) despite finishing in
    // milliseconds every time this file ran alone — the regression a
    // full-suite run caught that no single-file run could reproduce.
    await tester.pump(const Duration(milliseconds: 600));

    await gesture.up();
    // _onPressEnd stops the recording (cancelling the 100ms ticker),
    // plays the ready sound, and opens the review sheet asynchronously
    // (_openReviewGuarded -> _startPreview_ -> showModalBottomSheet).
    // _startPreview_'s VideoPlayerController.initialize() rejects (no
    // decoder on this test host, by design), and its own dispose() call
    // in that catch block — like the file-write and haptics gaps above —
    // only resolves via real wall-clock progression, not tester.pump()'s
    // fake clock. Another runAsync wait lets that (and the rest of the
    // unawaited _openReviewGuarded chain) actually finish before this
    // helper checks for the sheet.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    // Bounded pumps only: showModalBottomSheet's entrance animation is
    // finite, but an indeterminate spinner could reappear if a later
    // step regresses _isSending — pumpAndSettle would hang on either.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Bounded pumps for after tapping the review sheet's Send button:
  /// _send() flips _isSending (the indeterminate spinner again, so still
  /// no pumpAndSettle), awaits the fake ChatVideoPreparer, and — on
  /// success — pops the sheet and the screen. The unawaited
  /// sendStreakMessage() -> _attemptSend() chain that follows contains its
  /// own real-clock async gaps (createMediaUploadIntent/uploadChatMedia
  /// against the fake repository), so a runAsync wait is needed here for
  /// the same reason as recordAndReachReviewSheet's — tester.pump(duration)
  /// alone leaves those Futures never actually progressing.
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

  group('a completed recording sends through the chat controller', () {
    testWidgets('capture -> ChatVideoPreparer -> sendStreakMessage with the '
        'replay-derived view budget', (tester) async {
      final clipPath = await writeFile(tester, 'clip.mp4');
      final cameraPlatform = _FakeCameraPlatform(clipPath);
      CameraPlatform.instance = cameraPlatform;
      final preparer = _FakeChatVideoPreparer();

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      // Keep the .autoDispose chatControllerProvider family alive for
      // the duration of the test (chat_test_harness's own pattern).
      // Its async _init() settles during pumpToReady's own pumps below
      // — a bare Future.delayed here would stall forever: testWidgets
      // bodies run inside a FakeAsync zone where only tester.pump(...)
      // advances pending Timers (see
      // ephemeral_video_viewer_screen_test.dart's own comment on this).
      container.read(chatControllerProvider(convo).notifier);

      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          videoPreparerFactory: () => preparer,
        ),
      );

      await recordAndReachReviewSheet(tester);

      // The review sheet is open with the captured take. Tap Send.
      expect(find.text('Send'), findsOneWidget);
      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      // capture -> ChatVideoPreparer: prepare() was called with the
      // path the fake camera "recorded".
      expect(preparer.calls, 1);
      expect(preparer.preparedPaths.single, clipPath);

      // ChatVideoPreparer -> sendStreakMessage, through the real
      // chatControllerProvider/repository, with the DEFAULT replay
      // preference (allowReplays: false) turned into its view budget.
      expect(repo.sendCallCount, 1);
      final sent = repo.serverMessages.values.single;
      expect(sent.mediaType, 'streak');
      expect(
        sent.streakViewsRemaining,
        streakViewBudget(allowReplays: false),
        reason:
            'default replay preference is false; the budget reaching '
            'sendStreakMessage must be streakViewBudget(allowReplays: '
            'false)',
      );

      // The screen pops on a successful send.
      expect(find.byType(StreakCameraScreen), findsNothing);
    });
  });

  group('the replay preference decides the view budget', () {
    Future<void> sendOnceWith({
      required WidgetTester tester,
      required bool allowReplays,
      required FakeChatRepository repo,
      required int expectedBudget,
    }) async {
      final clipPath = await writeFile(tester, 'clip_$allowReplays.mp4');
      CameraPlatform.instance = _FakeCameraPlatform(clipPath);
      final preparer = _FakeChatVideoPreparer();

      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [
          streakReplayPreferenceProvider.overrideWith(
            (ref) => StreakReplayPreferenceNotifier.forTesting(allowReplays),
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
          videoPreparerFactory: () => preparer,
        ),
      );
      await recordAndReachReviewSheet(tester);
      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      final sent = repo.serverMessages.values.single;
      expect(sent.streakViewsRemaining, expectedBudget);
    }

    testWidgets('allowReplays: true reaches sendStreakMessage unchanged', (
      tester,
    ) async {
      await sendOnceWith(
        tester: tester,
        allowReplays: true,
        repo: FakeChatRepository(currentUserId: userId),
        expectedBudget: streakViewBudget(allowReplays: true),
      );
    });

    testWidgets('allowReplays: false reaches sendStreakMessage unchanged', (
      tester,
    ) async {
      await sendOnceWith(
        tester: tester,
        allowReplays: false,
        repo: FakeChatRepository(currentUserId: userId),
        expectedBudget: streakViewBudget(allowReplays: false),
      );
    });
  });

  group('capture-ready and send play the streak sounds', () {
    testWidgets('AppSound.streakCaptureReady on a completed take, '
        'AppSound.streakSend on send', (tester) async {
      final clipPath = await writeFile(tester, 'clip.mp4');
      CameraPlatform.instance = _FakeCameraPlatform(clipPath);
      final preparer = _FakeChatVideoPreparer();
      final fakeSound = FakeSoundService();

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [soundServiceProvider.overrideWithValue(fakeSound)],
      );
      addTearDown(container.dispose);
      container.read(chatControllerProvider(convo).notifier);

      // messageSoundsEnabledProvider defaults to true (SoundPreferenceNotifier),
      // so _playSound's gate is open without any extra override.
      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          videoPreparerFactory: () => preparer,
        ),
      );

      await recordAndReachReviewSheet(tester);

      expect(
        fakeSound.played,
        [AppSound.streakCaptureReady],
        reason: 'a completed take must play the ready cue exactly once',
      );

      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      expect(
        fakeSound.played,
        [AppSound.streakCaptureReady, AppSound.streakSend],
        reason:
            'send must play the send cue, after (not instead of) '
            'the ready cue',
      );
    });
  });

  group('a rejected transcode shows the streak message and stays', () {
    testWidgets('ChatVideoRejected shows "That streak could not be sent." and '
        'the camera does NOT pop', (tester) async {
      final clipPath = await writeFile(tester, 'clip.mp4');
      CameraPlatform.instance = _FakeCameraPlatform(clipPath);
      final preparer = _FakeChatVideoPreparer(
        rejection: const ChatVideoRejected('media_decode_failed'),
      );

      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final container = await bootContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      container.read(chatControllerProvider(convo).notifier);

      await pumpToReady(
        tester,
        container,
        StreakCameraScreen(
          conversation: convo,
          videoPreparerFactory: () => preparer,
        ),
      );

      await recordAndReachReviewSheet(tester);

      await tester.tap(find.text('Send'));
      await pumpAfterSend(tester);

      expect(find.text('That streak could not be sent.'), findsOneWidget);
      expect(
        find.byType(StreakCameraScreen),
        findsOneWidget,
        reason: 'a rejected transcode must not pop the camera',
      );
      expect(
        repo.sendCallCount,
        0,
        reason:
            'a rejected transcode must never reach the chat '
            'controller',
      );
    });
  });
}
