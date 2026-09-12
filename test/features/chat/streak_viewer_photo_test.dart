// Streak photos (spec §6.3 step 3): the streak viewer now branches on
// StreakClip.mediaKind rather than being unconditionally a video player.
// Proves, through the real screen (never a fake standing in for the whole
// widget — see this task's own lesson about fixtures that hide branching
// bugs): a PHOTO clip renders an image and never a VideoPlayer; a VIDEO
// clip is completely unaffected and still renders a VideoPlayer; the
// photo hold is driven by fake time only (tester.pump, no real-clock
// wait) and, once it elapses, spends the view and closes exactly like a
// finished video does; and the view budget/close contract (PopScope,
// _close, the single markViewed charge) is identical for both kinds —
// this suite deliberately varies media kind across every test rather
// than fixing it, since a fixture uniform in the dimension being branched
// on is exactly what hid four other bugs on this branch (see report).

import 'dart:async';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

/// Scripts fetchClips/markViewed without touching Supabase.
class _FakeStreakRepository implements StreakRepository {
  _FakeStreakRepository({required this.clips});

  final List<StreakClip> clips;
  int markViewedCalls = 0;
  int viewsRemainingToReturn = 0;

  @override
  Future<int> markViewed(String messageId) async {
    markViewedCalls++;
    return viewsRemainingToReturn;
  }

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async => clips;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No platform video decoder exists on a test host
/// (ephemeral_video_viewer_screen_test.dart documents this); this fake
/// reports every video as instantly "initialized" with a fixed duration,
/// so the VIDEO branch's own end-of-clip listener can be driven without a
/// real decoder — a plain reject-on-initialize stub (as the streak CAMERA
/// suite uses for its preview-only concern) would make the video path
/// here untestable as anything but the error branch.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  final Map<int, StreamController<VideoEvent>> _controllers = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    await _controllers.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextPlayerId++;
    // VideoPlayerController.initialize() only calls videoEventsFor(id)
    // AFTER createWithOptions resolves, so the 'initialized' event must
    // be emitted on listen — emitting it eagerly here (e.g. via
    // scheduleMicrotask against a broadcast controller with no listener
    // yet) drops the event entirely, and initialize() then hangs forever
    // waiting on a completer nothing ever completes.
    final controller = StreamController<VideoEvent>.broadcast(
      onListen: () {
        Future.microtask(() {
          _controllers[id]?.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 4),
              size: const Size(720, 1280),
            ),
          );
        });
      },
    );
    _controllers[id] = controller;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _controllers[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        '${invocation.memberName} is not used by this photo-viewer suite',
      );
}

void main() {
  const userId = 'user-a';
  late VideoPlayerPlatform originalVideoPlayerPlatform;

  setUp(() {
    originalVideoPlayerPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });

  tearDown(() {
    VideoPlayerPlatform.instance = originalVideoPlayerPlatform;
  });

  /// A real pushed route, mirroring streak_viewer_pop_test.dart's own
  /// harness: StreakViewerScreen's PopScope/_close call Navigator.pop,
  /// which needs an actual route stack under it, not a bare `home:`.
  Widget harness({
    required ProviderContainer container,
    required String messageId,
    Duration imageHoldDuration = const Duration(seconds: 5),
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<int>(
                            builder:
                                (_) => StreakViewerScreen(
                                  messageId: messageId,
                                  imageHoldDuration: imageHoldDuration,
                                ),
                          ),
                        ),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  /// Pumps the harness, taps "open" to push the real route, and settles
  /// the MaterialPageRoute transition.
  Future<void> openViewer(
    WidgetTester tester, {
    required ProviderContainer container,
    required String messageId,
    Duration imageHoldDuration = const Duration(seconds: 5),
  }) async {
    await tester.pumpWidget(
      harness(
        container: container,
        messageId: messageId,
        imageHoldDuration: imageHoldDuration,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  ProviderContainer buildContainer({
    required FakeChatRepository chatRepo,
    required _FakeStreakRepository streakRepo,
  }) {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chatRepo),
        streakRepositoryProvider.overrideWithValue(streakRepo),
      ],
    );
    return container;
  }

  testWidgets(
    'a photo clip renders an image and never mounts a VideoPlayer',
    (tester) async {
      final chatRepo = FakeChatRepository(currentUserId: userId)
        ..signMediaUrls = true;
      final streakRepo = _FakeStreakRepository(
        clips: const [
          StreakClip(
            index: 0,
            mediaUrl: 'chat/photo-0',
            durationMs: 0,
            mediaKind: StreakClipKind.photo,
          ),
        ],
      );
      final container = buildContainer(
        chatRepo: chatRepo,
        streakRepo: streakRepo,
      );
      addTearDown(container.dispose);

      await openViewer(tester, container: container, messageId: 'm-photo');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('streak-photo-view')),
        findsOneWidget,
        reason: 'a photo clip must render the image branch',
      );
      expect(
        find.byType(VideoPlayer),
        findsNothing,
        reason: 'a photo clip must never mount a VideoPlayer',
      );
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'once the photo has resolved, the spinner must be gone',
      );
    },
  );

  testWidgets(
    'a video clip still renders a VideoPlayer and is unaffected by the '
    'photo branch',
    (tester) async {
      final chatRepo = FakeChatRepository(currentUserId: userId)
        ..signMediaUrls = true;
      final streakRepo = _FakeStreakRepository(
        clips: const [
          StreakClip(
            index: 0,
            mediaUrl: 'chat/video-0',
            durationMs: 4000,
            mediaKind: StreakClipKind.video,
          ),
        ],
      );
      final container = buildContainer(
        chatRepo: chatRepo,
        streakRepo: streakRepo,
      );
      addTearDown(container.dispose);

      await openViewer(tester, container: container, messageId: 'm-video');
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      expect(
        find.byType(VideoPlayer),
        findsOneWidget,
        reason: 'a video clip must still render through VideoPlayer',
      );
      expect(
        find.byKey(const ValueKey('streak-photo-view')),
        findsNothing,
        reason: 'a video clip must never render the image branch',
      );
    },
  );

  testWidgets(
    'a photo clip holds for imageHoldDuration (fake time only) then '
    'spends the view and closes',
    (tester) async {
      final chatRepo = FakeChatRepository(currentUserId: userId)
        ..signMediaUrls = true;
      final streakRepo = _FakeStreakRepository(
        clips: const [
          StreakClip(
            index: 0,
            mediaUrl: 'chat/photo-0',
            durationMs: 0,
            mediaKind: StreakClipKind.photo,
          ),
        ],
      )..viewsRemainingToReturn = 2;
      final container = buildContainer(
        chatRepo: chatRepo,
        streakRepo: streakRepo,
      );
      addTearDown(container.dispose);

      // A generous hold, well clear of openViewer's own ~300ms route
      // transition (the timer starts inside _playAt, which runs DURING
      // that transition's pumps — a hold too close to 300ms would let it
      // elapse before this test ever checks the "not yet spent" state).
      // Still short enough to keep the suite fast, and independent of
      // kStoryImageHoldDuration itself, which a separate test pins
      // directly (mirrors story_reel_test.dart's own imageHoldDuration
      // seam pattern).
      const hold = Duration(seconds: 5);
      await openViewer(
        tester,
        container: container,
        messageId: 'm-photo-hold',
        imageHoldDuration: hold,
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);
      expect(
        streakRepo.markViewedCalls,
        0,
        reason: 'the view must not spend before the hold elapses',
      );

      // Just under the hold, measured from NOW (the photo is already
      // showing and its timer already running) rather than from widget
      // construction: 4 of the remaining ~4.7s.
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);
      expect(streakRepo.markViewedCalls, 0);

      // Crossing the hold advances past the only clip, which finishes:
      // spends the view and pops.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(streakRepo.markViewedCalls, 1);
      expect(
        find.byType(StreakViewerScreen),
        findsNothing,
        reason: 'the hold elapsing must close the viewer exactly like a '
            'finished video does',
      );
    },
  );

  /// Shared body for the view-budget-parity check below, run once per
  /// media kind as separate testWidgets cases (rather than one test
  /// looping both kinds through a single tester) so a leftover widget
  /// from one iteration's pop settling can never bleed into the next.
  Future<void> expectBudgetAppliesFor(
    WidgetTester tester,
    StreakClipKind kind,
  ) async {
    final chatRepo = FakeChatRepository(currentUserId: userId)
      ..signMediaUrls = true;
    final streakRepo = _FakeStreakRepository(
      clips: [
        StreakClip(
          index: 0,
          mediaUrl: 'chat/clip-0',
          durationMs: kind == StreakClipKind.photo ? 0 : 4000,
          mediaKind: kind,
        ),
      ],
    )..viewsRemainingToReturn = 1;
    final container = buildContainer(chatRepo: chatRepo, streakRepo: streakRepo);
    addTearDown(container.dispose);

    // A long hold: this test calls finishForTest() directly rather than
    // waiting for the timer, so the hold only needs to outlast
    // openViewer's own route-transition pump (300ms) — otherwise the
    // photo's own timer could fire and close the screen before the test
    // ever reaches finishForTest.
    await openViewer(
      tester,
      container: container,
      messageId: 'm-budget-$kind',
      imageHoldDuration: const Duration(seconds: 30),
    );
    await tester.pump();
    await tester.pump();

    // finishForTest drives the same completion path a real end-of-clip
    // does for either kind, without depending on the photo timer or a
    // real video decoder's own end-of-clip signal.
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    await (state as dynamic).finishForTest();
    await tester.pumpAndSettle();

    expect(
      streakRepo.markViewedCalls,
      1,
      reason:
          'markViewed must be called exactly once for a $kind clip — the '
          'budget RPC itself carries no media-type parameter, so the '
          'client-side call shape must not vary by kind either',
    );
  }

  testWidgets(
    'the view budget applies to a photo clip exactly like a video clip: photo',
    (tester) => expectBudgetAppliesFor(tester, StreakClipKind.photo),
  );

  testWidgets(
    'the view budget applies to a photo clip exactly like a video clip: video',
    (tester) => expectBudgetAppliesFor(tester, StreakClipKind.video),
  );

  testWidgets(
    'dismissing a photo streak while its hold timer is still pending does '
    'not crash or double-spend',
    (tester) async {
      // Regression coverage for dismissing a photo streak while its hold
      // Timer is still pending: proves no crash and no double-spend when
      // the callback eventually fires after dispose. NOTE (mutation-test
      // finding, see report): removing this callback's own
      // mounted/generation guard does NOT independently fail this test —
      // _close()'s own pre-existing `if (!mounted) return` absorbs the
      // unmounted case downstream, since the only path from here is
      // _playAt(index + 1) -> _finish() -> _close(). The guard is kept as
      // correct, cheap defense-in-depth (this task's own "guard every
      // post-await state write" requirement) and this test still proves
      // the OUTCOME (no crash, no double charge) even though it cannot
      // isolate this one guard from the one behind it.
      final chatRepo = FakeChatRepository(currentUserId: userId)
        ..signMediaUrls = true;
      final streakRepo = _FakeStreakRepository(
        clips: const [
          StreakClip(
            index: 0,
            mediaUrl: 'chat/photo-0',
            durationMs: 0,
            mediaKind: StreakClipKind.photo,
          ),
        ],
      )..viewsRemainingToReturn = 0;
      final container = buildContainer(
        chatRepo: chatRepo,
        streakRepo: streakRepo,
      );
      addTearDown(container.dispose);

      await openViewer(
        tester,
        container: container,
        messageId: 'm-photo-dismiss',
        imageHoldDuration: const Duration(seconds: 10),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);

      // Dismiss well before the 10s hold elapses — the timer is still
      // pending underneath when the screen closes. finishForTest drives
      // exactly the same _finish() a tap-to-dismiss does (see this
      // screen's own doc comment on the seam); a raw tap risks hitting
      // an unrelated GestureDetector still in the tree behind the pushed
      // route, which is a test-harness concern this task's actual target
      // (the timer's mounted/generation guard) has nothing to do with.
      final state = tester.state(find.byType(StreakViewerScreen));
      // ignore: avoid_dynamic_calls
      await (state as dynamic).finishForTest();
      await tester.pumpAndSettle();

      expect(streakRepo.markViewedCalls, 1);
      expect(find.byType(StreakViewerScreen), findsNothing);

      // Advance PAST where the (now-cancelled) timer would have fired.
      // If the timer were still live and its callback lacked the
      // mounted/generation guard, this would throw (setState/Navigator
      // on a disposed screen) or double-spend the view.
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();

      expect(
        streakRepo.markViewedCalls,
        1,
        reason:
            'a stale timer firing after dismissal must not spend the view '
            'a second time',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
