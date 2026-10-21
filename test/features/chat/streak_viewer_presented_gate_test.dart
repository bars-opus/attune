// test/features/chat/streak_viewer_presented_gate_test.dart
//
// A view-once item is consumed when the media is actually shown — never by a
// tap or a back gesture on the loading screen (H-1 / issue #41).
import 'dart:async';
import 'dart:convert';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart'
    show kStoryImageHoldDuration;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _GatedStreakRepository implements StreakRepository {
  _GatedStreakRepository({
    this.clips = const [],
    this.gate,
    this.error,
    this.failSpends = 0,
    this.remaining = 0,
    this.hang,
  });

  final List<StreakClip> clips;
  final Completer<void>? gate; // fetchClips waits on this when set
  final Object? error; // fetchClips throws this when set
  int failSpends; // the first N spends throw (lost response, offline)
  final Completer<void>? hang; // the FIRST spend waits on this, then throws
  final int remaining; // what a successful spend reports
  int markViewedCalls = 0;
  final List<String> openIds = [];

  @override
  Future<int> markViewed(String messageId, {required String openId}) async {
    markViewedCalls++;
    openIds.add(openId);
    if (markViewedCalls == 1 && hang != null) {
      await hang!.future;
      throw Exception('spend timed out on a dead link');
    }
    if (failSpends > 0) {
      failSpends--;
      throw Exception('spend lost');
    }
    return remaining;
  }

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async {
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return clips;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signing can be held open so the viewer sits on its spinner with clips
/// already fetched.
class _GatedSigningRepository extends FakeChatRepository {
  _GatedSigningRepository({required super.currentUserId, this.signingGate});
  final Completer<void>? signingGate;

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    if (signingGate != null) await signingGate!.future;
    return 'https://signed.test/$mediaKey?token=abc';
  }
}

/// Same shape as streak_viewer_photo_test's fake: every video is
/// "initialized" as soon as its event stream is listened to.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  _FakeVideoPlayerPlatform({
    this.initialize = true,
    this.failCreate = false,
    this.failPlay = false,
    this.advances = true,
    this.stalled = const {},
    this.disposeGate,
  });
  final Completer<void>? disposeGate; // platform dispose waits on this
  final bool initialize;
  final bool failCreate; // the decoder refuses the clip outright
  final bool failPlay; // play() throws
  final bool advances; // false: "playing" but stuck at 0 (stalled stream)
  final Set<int> stalled; // these player ids never get past 0:00
  final Set<int> _playing = {};

  /// Player ids released through [dispose] — a native player never
  /// released keeps playing (and sounding) after the viewer has closed.
  final List<int> disposed = [];
  int _next = 0;
  final Map<int, StreamController<VideoEvent>> _controllers = {};

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    _playing.remove(playerId);
    if (disposeGate != null) await disposeGate!.future;
    await _controllers.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failCreate) throw Exception('decoder refused the clip');
    final id = _next++;
    final controller = StreamController<VideoEvent>.broadcast(
      onListen: () {
        if (!initialize) return; // never reaches its first frame
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
  Future<void> play(int playerId) async {
    if (failPlay) throw Exception('playback refused');
    _playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async => _playing.remove(playerId);
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      _playing.contains(playerId) && advances && !stalled.contains(playerId)
          ? const Duration(milliseconds: 500)
          : Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused');
}

/// Signs every clip except the [failing] keys, as if the connection
/// dropped between segments.
class _FailingSigningRepository extends FakeChatRepository {
  _FailingSigningRepository({
    required super.currentUserId,
    required this.failing,
  });
  final Set<String> failing;
  final List<String> requested = [];

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    requested.add(mediaKey);
    if (failing.contains(mediaKey)) return null;
    return 'https://signed.test/$mediaKey?token=abc';
  }
}

/// A photo whose bytes arrive exactly when the test says so.
class _ControlledImage extends ImageProvider<_ControlledImage> {
  final Completer<ImageInfo> bytes = Completer<ImageInfo>();

  @override
  Future<_ControlledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_ControlledImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _ControlledImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(bytes.future);
}

StreakClip _video(int index) => StreakClip(
  index: index,
  mediaUrl: 'chat/clip-$index',
  durationMs: 4000,
  mediaKind: StreakClipKind.video,
);

const _videoClip = StreakClip(
  index: 0,
  mediaUrl: 'chat/clip-0',
  durationMs: 4000,
  mediaKind: StreakClipKind.video,
);
const _photoClip = StreakClip(
  index: 0,
  mediaUrl: 'chat/photo-0',
  durationMs: 0,
  mediaKind: StreakClipKind.photo,
);

/// 1x1 transparent PNG — decodable by the test engine.
final Uint8List _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);

void main() {
  late VideoPlayerPlatform original;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  /// Pushes the viewer as a real route and captures its pop result.
  Future<ValueNotifier<int?>> open(
    WidgetTester tester, {
    required FakeChatRepository chatRepo,
    required StreakRepository streakRepo,
    ImageProvider Function(String url)? imageProviderBuilder,
    bool reduceMotion = false,
  }) async {
    final result = ValueNotifier<int?>(-1);
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(chatRepo),
        streakRepositoryProvider.overrideWithValue(streakRepo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduceMotion),
                child: child!,
              ),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () async {
                      result.value = await Navigator.of(context).push<int>(
                        MaterialPageRoute<int>(
                          builder:
                              (_) => StreakViewerScreen(
                                messageId: 'm1',
                                imageProviderBuilder: imageProviderBuilder,
                              ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return result;
  }

  testWidgets('tapping while the clips are still loading spends nothing', (
    tester,
  ) async {
    // 2-3 s of black screen + spinner reads as "nothing happened", so people
    // tap it. That tap used to call _finish -> markViewed -> clips deleted:
    // the only view burnt, "Opened" on both phones, nobody saw it.
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();

    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(result.value, isNull, reason: 'null keeps the bubble\'s count');
    gate.complete();
  });

  testWidgets('the back gesture while loading spends nothing either', (
    tester,
  ) async {
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );

    // System back: PopScope(canPop:false) routes it through _finish.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
    gate.complete();
  });

  testWidgets('clips fetched but still signing: still nothing is spent', (
    tester,
  ) async {
    final signing = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: _GatedSigningRepository(
        currentUserId: 'me',
        signingGate: signing,
      ),
      streakRepo: streakRepo,
    );
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    signing.complete();
  });

  testWidgets('a video that never reaches its first frame spends nothing', (
    tester,
  ) async {
    // Review Focus 3.
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(initialize: false);
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('once the video is on screen, closing spends exactly one view', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);
    // Presented once playback reports progress (position polled ~100 ms).
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a photo counts as presented once its first frame decodes', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    final provider = MemoryImage(_onePixelPng);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
      imageProviderBuilder: (_) => provider,
    );
    // Let the engine decode the PNG off the fake clock, then paint it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('streak-photo-view')));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a photo whose bytes never arrive is not spent', (tester) async {
    // The default NetworkImage gets HTTP 400 from the test host: errorBuilder
    // path. Nothing painted, nothing spent, and the person is told.
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text("Couldn't load this streak. Try again in a moment."),
      findsOneWidget,
    );
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('a fetch failure never spends', (tester) async {
    final streakRepo = _GatedStreakRepository(error: Exception('offline'));
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(find.text('This streak is no longer available.'), findsOneWidget);
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    expect(result.value, isNull);
  });

  testWidgets('clips the server says are gone still sync the budget', (
    tester,
  ) async {
    // Review Focus 4: an empty fetch is the server saying "spent/expired".
    // Spending here returns 0 and flips both bubbles to Opened; it must
    // survive the presented gate.
    final streakRepo = _GatedStreakRepository(clips: const []);
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(result.value, 0);
  });

  testWidgets('there is an explicit Close control while loading', (
    tester,
  ) async {
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_videoClip], gate: gate);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(streakRepo.markViewedCalls, 0);
    gate.complete();
  });
  testWidgets('a signing failure says so honestly and spends nothing', (
    tester,
  ) async {
    // Signing can fail for transient reasons (offline, token refresh). The
    // old code called _finish here, which spent the view on a clip nobody
    // saw. Now the person is told, and leaving is free.
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    final result = await open(
      tester,
      // signMediaUrls defaults to false: every sign returns null.
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(
      find.text("Couldn't load this streak. Try again in a moment."),
      findsOneWidget,
    );
    expect(
      find.byType(StreakViewerScreen),
      findsOneWidget,
      reason: 'the viewer must not close itself on a sign failure',
    );
    expect(streakRepo.markViewedCalls, 0);

    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(result.value, isNull);
  });

  testWidgets('a video the decoder refuses is not spent', (tester) async {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(failCreate: true);
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(
      find.text("Couldn't load this streak. Try again in a moment."),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });

  testWidgets('a later clip failing after one was shown still spends once', (
    tester,
  ) async {
    // The first clip WAS seen, so the view is genuinely used; a failure on
    // clip two must not make the open free.
    final chatRepo = _FailingSigningRepository(
      currentUserId: 'me',
      failing: {'chat/clip-1'},
    );
    final streakRepo = _GatedStreakRepository(clips: [_video(0), _video(1)]);
    await open(tester, chatRepo: chatRepo, streakRepo: streakRepo);
    await tester.pump();
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250)); // presented
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isTrue);

    // Advance to clip two, whose signing fails.
    // ignore: avoid_dynamic_calls
    unawaited((state as dynamic).playAtForTest(1) as Future<void>);
    // Disposing clip one's controller completes off the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(
      find.text("Couldn't load this streak. Try again in a moment."),
      findsOneWidget,
    );
    // Task 5b: the view is spent when clip one was PRESENTED, not at exit.
    expect(streakRepo.markViewedCalls, 1, reason: 'spent at presentation');

    // It was the last clip: after the brief error the streak ends, and
    // closing does not spend again.
    await tester.pump(kStreakClipFailureHold);
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });

  testWidgets('every exit racing after presentation spends exactly once', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isTrue);
    // ignore: avoid_dynamic_calls
    unawaited((state as dynamic).finishForTest() as Future<void>);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });
  // ── Fix round 1 ──────────────────────────────────────────────────────

  const failedCopy = "Couldn't load this streak. Try again in a moment.";

  testWidgets('a photo that decodes at 4.8 s still gets its full hold', (
    tester,
  ) async {
    // I1: the hold used to start when the URL was signed, so a slow photo
    // was seen for ~0.2 s and still spent the view.
    final image = _ControlledImage();
    final decoded = await tester.runAsync(
      () => createTestImage(width: 1, height: 1),
    );
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
      imageProviderBuilder: (_) => image,
    );
    await tester.pump(const Duration(milliseconds: 4500)); // ~4.8 s in
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'a photo still downloading shows it is loading',
    );
    expect(find.byType(StreakViewerScreen), findsOneWidget);

    image.bytes.complete(ImageInfo(image: decoded!));
    await tester.pump(); // first frame
    await tester.pump(); // post-frame: the hold starts here
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Task 5b: the first painted frame IS the view: spent now, once.
    expect(streakRepo.markViewedCalls, 1, reason: 'spent at first frame');

    await tester.pump(kStoryImageHoldDuration - const Duration(seconds: 1));
    expect(
      find.byType(StreakViewerScreen),
      findsOneWidget,
      reason: 'the hold runs from the first frame, not from the URL',
    );
    expect(streakRepo.markViewedCalls, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });

  testWidgets('a photo that never decodes times out honestly, unspent', (
    tester,
  ) async {
    final image = _ControlledImage(); // never completes
    final streakRepo = _GatedStreakRepository(clips: [_photoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
      imageProviderBuilder: (_) => image,
    );
    await tester.pump(kStoryImageHoldDuration + const Duration(seconds: 1));
    expect(
      find.byType(StreakViewerScreen),
      findsOneWidget,
      reason: 'no silent close after the hold length',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(failedCopy), findsNothing);

    await tester.pump(kStreakClipLoadTimeout);
    expect(find.text(failedCopy), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byType(StreakViewerScreen),
      findsOneWidget,
      reason: 'the only clip failed: wait for the person to leave',
    );

    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });

  testWidgets('a video that never starts also times out', (tester) async {
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(initialize: false);
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump(kStreakClipLoadTimeout);
    expect(find.text(failedCopy), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('reduce motion shows a still loading mark, not a spinner', (
    tester,
  ) async {
    final gate = Completer<void>();
    final streakRepo = _GatedStreakRepository(clips: [_photoClip], gate: gate);
    final image = _ControlledImage();
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
      imageProviderBuilder: (_) => image,
      reduceMotion: true,
    );
    // Fetching the clips.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('streak-loading-static')), findsOneWidget);

    // Photo signed, bytes still on the way.
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('streak-photo-view')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('streak-loading-static')), findsOneWidget);
  });

  testWidgets('a video "playing" but stuck at 0:00 is not presented', (
    tester,
  ) async {
    // Minor 3: play() resolving is not the same as frames moving — a
    // stalled stream sits on a black texture.
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform(advances: false);
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(VideoPlayer), findsOneWidget);
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('play() failing says so and spends nothing', (tester) async {
    final platform = _FakeVideoPlayerPlatform(failPlay: true);
    VideoPlayerPlatform.instance = platform;
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(failedCopy), findsOneWidget);
    expect(
      find.byType(VideoPlayer),
      findsNothing,
      reason: 'no frozen first frame passing for a playing clip',
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(platform.disposed, [0], reason: 'the refused player is released');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('a failure on a middle clip moves on to the next one', (
    tester,
  ) async {
    // Minor 4: clip two failing used to strand the person on the error,
    // with clip three never tried.
    final chatRepo = _FailingSigningRepository(
      currentUserId: 'me',
      failing: {'chat/clip-1'},
    );
    final streakRepo = _GatedStreakRepository(
      clips: [_video(0), _video(1), _video(2)],
    );
    await open(tester, chatRepo: chatRepo, streakRepo: streakRepo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isTrue);

    // ignore: avoid_dynamic_calls
    unawaited((state as dynamic).playAtForTest(1) as Future<void>);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text(failedCopy), findsOneWidget);

    await tester.pump(kStreakClipFailureHold);
    await tester.pump();
    await tester.pump();
    expect(chatRepo.requested, contains('chat/clip-2'));
    expect(find.text(failedCopy), findsNothing);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    // Task 5b: spent when clip one was presented; clip three adds nothing.
    expect(streakRepo.markViewedCalls, 1, reason: 'spent at presentation');

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a failure on the first clip waits for the person', (
    tester,
  ) async {
    // Nothing has been seen yet: moving on would spend the view on clip
    // two while the person never saw clip one. Stay, say so, leave free.
    final chatRepo = _FailingSigningRepository(
      currentUserId: 'me',
      failing: {'chat/clip-0'},
    );
    final streakRepo = _GatedStreakRepository(clips: [_video(0), _video(1)]);
    await open(tester, chatRepo: chatRepo, streakRepo: streakRepo);
    await tester.pump();
    await tester.pump(kStreakClipFailureHold * 3);
    expect(find.text(failedCopy), findsOneWidget);
    // Task 5b: every clip is signed up front, but clip two is never played.
    expect(chatRepo.requested, ['chat/clip-0', 'chat/clip-1']);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('the Close control sits on a dark scrim', (tester) async {
    // Minor 5: a bare white X vanishes over a bright frame.
    final gate = Completer<void>();
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: _GatedStreakRepository(clips: [_videoClip], gate: gate),
    );
    final button = tester.widget<IconButton>(find.byType(IconButton));
    final background = button.style?.backgroundColor?.resolve({});
    expect(background, isNotNull);
    expect(background!.a, greaterThan(0.2));
    expect(background.computeLuminance(), lessThan(0.1));
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    gate.complete();
  });
  // ── Fix round 2 ──────────────────────────────────────────────────────

  testWidgets('a stalled video that times out releases its player', (
    tester,
  ) async {
    // N1: the timeout nulled _controller without disposing it, so the
    // native player lived on — and if the stream recovered, the clip's
    // audio played over the chat with no view spent.
    final platform = _FakeVideoPlayerPlatform(advances: false);
    VideoPlayerPlatform.instance = platform;
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);

    await tester.pump(kStreakClipLoadTimeout);
    // Controller teardown completes off the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text(failedCopy), findsOneWidget);
    expect(platform.disposed, [0], reason: 'the stalled player is released');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 0);
  });

  testWidgets('a stalled later clip is released before moving on', (
    tester,
  ) async {
    final platform = _FakeVideoPlayerPlatform(stalled: {1});
    VideoPlayerPlatform.instance = platform;
    final chatRepo = FakeChatRepository(currentUserId: 'me')
      ..signMediaUrls = true;
    final streakRepo = _GatedStreakRepository(
      clips: [_video(0), _video(1), _video(2)],
    );
    await open(tester, chatRepo: chatRepo, streakRepo: streakRepo);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isTrue);

    // ignore: avoid_dynamic_calls
    unawaited((state as dynamic).playAtForTest(1) as Future<void>);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(platform.disposed, [0], reason: 'clip one released on advance');

    await tester.pump(kStreakClipLoadTimeout); // clip two stalls out
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text(failedCopy), findsOneWidget);
    expect(platform.disposed, [0, 1], reason: 'clip two released on failure');

    await tester.pump(kStreakClipFailureHold);
    await tester.pump();
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(platform.disposed, [0, 1], reason: 'clip three is the live one');

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
  });

  // ── Task 5b: the view is spent at presentation, idempotently ─────────

  /// Opens a one-video streak and lets clip one reach presentation.
  Future<ValueNotifier<int?>> openAndPresent(
    WidgetTester tester,
    _GatedStreakRepository streakRepo,
  ) async {
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // presented
    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    expect((state as dynamic).hasPresentedForTest, isTrue);
    return result;
  }

  testWidgets('the view is spent the moment clip one is presented, once', (
    tester,
  ) async {
    // Task-4 review Issue 2: spending on EXIT meant a force-quit, quick exit
    // or PIN lock mid-watch never spent the view, and the streak stayed on
    // "Play" with its window never started.
    final streakRepo = _GatedStreakRepository(
      clips: [_videoClip],
      remaining: 2,
    );
    final result = await openAndPresent(tester, streakRepo);
    expect(streakRepo.markViewedCalls, 1, reason: 'spent before any exit');

    await tester.pump(const Duration(seconds: 1));
    expect(streakRepo.markViewedCalls, 1, reason: 'once per open');

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(streakRepo.openIds.toSet(), hasLength(1));
    expect(result.value, 2, reason: 'the stored count reaches the bubble');
  });

  testWidgets('a route torn down after presentation has already spent', (
    tester,
  ) async {
    // Quick exit / PIN lock / logout remove the route without _finish.
    final streakRepo = _GatedStreakRepository(clips: [_videoClip]);
    await openAndPresent(tester, streakRepo);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(streakRepo.markViewedCalls, 1);
  });

  testWidgets('a failed spend is retried once on exit, same open id', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(
      clips: [_videoClip],
      failSpends: 1,
      remaining: 1,
    );
    final result = await openAndPresent(tester, streakRepo);
    expect(streakRepo.markViewedCalls, 1);

    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 2, reason: 'retried exactly once');
    expect(
      streakRepo.openIds.toSet(),
      hasLength(1),
      reason: 'the retry is idempotent server-side only with the same id',
    );
    expect(result.value, 1);
    expect(find.byType(StreakViewerScreen), findsNothing);
  });

  testWidgets('a failed spend owed at teardown is retried, same open id', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(
      clips: [_videoClip],
      failSpends: 1,
    );
    await openAndPresent(tester, streakRepo);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(streakRepo.markViewedCalls, 2);
    expect(streakRepo.openIds.toSet(), hasLength(1));
  });

  testWidgets('a spend that keeps failing still lets the person leave', (
    tester,
  ) async {
    final streakRepo = _GatedStreakRepository(
      clips: [_videoClip],
      failSpends: 99,
    );
    final result = await openAndPresent(tester, streakRepo);
    await tester.tap(find.byType(VideoPlayer));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 2, reason: 'one retry, not a loop');
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(result.value, isNull, reason: 'null keeps the bubble\'s count');
  });

  testWidgets('every clip is signed before clip one plays', (tester) async {
    // The last view destroys the clips server-side the moment it is spent
    // (now at presentation), and storage then refuses to sign them.
    final chatRepo = _FailingSigningRepository(
      currentUserId: 'me',
      failing: const {},
    );
    final streakRepo = _GatedStreakRepository(
      clips: [_video(0), _video(1), _video(2)],
    );
    await open(tester, chatRepo: chatRepo, streakRepo: streakRepo);
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(chatRepo.requested, ['chat/clip-0', 'chat/clip-1', 'chat/clip-2']);
  });

  testWidgets('advancing cancels the outgoing clip before releasing it', (
    tester,
  ) async {
    // Task-4 re-review N1 note: _playAt awaited the old controller's
    // dispose BEFORE cancelling its load timeout, so a slow release let
    // that timeout fire for a clip already left behind.
    final release = Completer<void>();
    final platform = _FakeVideoPlayerPlatform(
      stalled: {0},
      disposeGate: release,
    );
    VideoPlayerPlatform.instance = platform;
    final streakRepo = _GatedStreakRepository(clips: [_video(0), _video(1)]);
    await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
      streakRepo: streakRepo,
    );
    await tester.pump();
    expect(find.byType(VideoPlayer), findsOneWidget);

    final state = tester.state(find.byType(StreakViewerScreen));
    // ignore: avoid_dynamic_calls
    unawaited((state as dynamic).playAtForTest(1) as Future<void>);
    await tester.pump(kStreakClipLoadTimeout);
    expect(
      find.text(failedCopy),
      findsNothing,
      reason: 'clip one\'s timeout fired after the viewer had moved on',
    );

    release.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(platform.disposed, [0], reason: 'released exactly once');
  });

  testWidgets('closing does not wait on a hung spend', (tester) async {
    // Fix round 1 (review M-2): on a dead link the last frame sat there
    // until the 20 s network bound. The count only matters to the bubble
    // (realtime delivers it anyway): leave after a short wait and let the
    // retry settle in the background with the same open id.
    final hang = Completer<void>();
    final streakRepo = _GatedStreakRepository(
      clips: [_videoClip],
      hang: hang,
      remaining: 0,
    );
    final result = await openAndPresent(tester, streakRepo);
    expect(streakRepo.markViewedCalls, 1);

    await tester.tap(find.byType(VideoPlayer));
    await tester.pump(kStreakSpendCloseWait);
    await tester.pumpAndSettle();
    expect(
      find.byType(StreakViewerScreen),
      findsNothing,
      reason: 'the close must not wait out the network bound',
    );
    expect(result.value, isNull, reason: 'no count yet: the bubble keeps its own');

    // The hung attempt finally fails: the retry runs in the background.
    hang.complete();
    await tester.pump();
    await tester.pump();
    expect(streakRepo.markViewedCalls, 2);
    expect(streakRepo.openIds.toSet(), hasLength(1));
  });

  testWidgets('an empty fetch before the attach hands back the intact budget', (
    tester,
  ) async {
    // Fix round 1 (review M-1): the empty-fetch budget sync used to burn a
    // streak whose clip row had not landed yet. The server now answers the
    // untouched budget; the viewer must pass it through, not assume 0.
    final streakRepo = _GatedStreakRepository(clips: const [], remaining: 1);
    final result = await open(
      tester,
      chatRepo: FakeChatRepository(currentUserId: 'me'),
      streakRepo: streakRepo,
    );
    await tester.pump();
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(streakRepo.markViewedCalls, 1);
    expect(result.value, 1, reason: 'the bubble keeps Play');
  });
}
