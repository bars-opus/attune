// Final review M-3: the streak viewer had no lifecycle observer. On Android
// video_player does not pause on backgrounding, so a clip backgrounded
// mid-play kept its sound going over the home screen until it ended, and
// then _finish popped the viewer behind the user's back. A photo's hold
// ran out the same way. The viewer now holds still while the app is away
// and carries on where it stopped when the app comes back — the view was
// already spent at presentation, so closing would burn the recipient's
// (often only) view on a phone call or a pulled-down notification shade.
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _StreakRepo implements StreakRepository {
  _StreakRepo(this.clips);
  final List<StreakClip> clips;
  int spends = 0;

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async => clips;

  @override
  Future<int> markViewed(String messageId, {required String openId}) async {
    spends++;
    return 0;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records play/pause. A playing clip reports 0.5 s of progress, so it
/// counts as presented; [initGate] holds the first frame back.
class _RecordingVideoPlatform extends VideoPlayerPlatform {
  _RecordingVideoPlatform({this.initGate});
  final Completer<void>? initGate;
  final List<String> calls = [];
  final Set<int> _playing = {};
  final Map<int, StreamController<VideoEvent>> _streams = {};
  int _next = 0;

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {
    _playing.remove(playerId);
    await _streams.remove(playerId)?.close();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    _streams[id] = StreamController<VideoEvent>.broadcast(
      onListen: () async {
        if (initGate != null) await initGate!.future;
        _streams[id]?.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            duration: const Duration(seconds: 4),
            size: const Size(720, 1280),
          ),
        );
      },
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _streams[playerId]!.stream;
  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    _playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {
    calls.add('pause');
    _playing.remove(playerId);
  }

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
      _playing.contains(playerId)
          ? const Duration(milliseconds: 500)
          : Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox.shrink();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} unused');
}

/// A photo whose bytes arrive when the test says so.
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

void main() {
  late VideoPlayerPlatform original;
  late _RecordingVideoPlatform platform;
  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = _RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  Future<void> background(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester,
    _StreakRepo streaks, {
    ImageProvider Function(String url)? imageProviderBuilder,
  }) async {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(
          FakeChatRepository(currentUserId: 'me')..signMediaUrls = true,
        ),
        streakRepositoryProvider.overrideWithValue(streaks),
      ],
    );
    addTearDown(container.dispose);
    // A failing expect must not leave the app "paused" for the next test.
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed:
                        () => Navigator.of(context).push<int>(
                          MaterialPageRoute<int>(
                            builder:
                                (_) => StreakViewerScreen(
                                  messageId: 'm1',
                                  imageProviderBuilder: imageProviderBuilder,
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
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  VideoPlayerController controllerOf(WidgetTester tester) =>
      tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller;

  testWidgets('backgrounding pauses a playing clip; coming back resumes it', (
    tester,
  ) async {
    // video_player 2.10's own observer already pauses an initialized,
    // playing controller on `paused`; this pins that the viewer's hold
    // composes with it (one pause, one resume, still on screen).
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(controllerOf(tester).value.isPlaying, isTrue);
    expect(streaks.spends, 1, reason: 'presented, so spent');

    platform.calls.clear();
    await background(tester);
    expect(platform.calls, contains('pause'));
    expect(
      controllerOf(tester).value.isPlaying,
      isFalse,
      reason: 'no sound over the home screen',
    );

    // Away for a long time: still there, still paused, nothing re-spent.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byType(StreakViewerScreen), findsOneWidget);
    expect(platform.calls, isNot(contains('play')));

    await foreground(tester);
    expect(platform.calls, contains('play'));
    expect(controllerOf(tester).value.isPlaying, isTrue);
    expect(find.byType(StreakViewerScreen), findsOneWidget);
    expect(streaks.spends, 1);
  });

  testWidgets('a clip that finishes loading while away waits to start', (
    tester,
  ) async {
    final init = Completer<void>();
    platform = _RecordingVideoPlatform(initGate: init);
    VideoPlayerPlatform.instance = platform;
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);

    await background(tester);
    init.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.calls, isNot(contains('play')));
    expect(streaks.spends, 0, reason: 'nothing was shown while away');

    // Away past the load timeout: being away is not a failed load.
    await tester.pump(kStreakClipLoadTimeout + const Duration(seconds: 1));
    expect(
      find.text("Couldn't load this streak. Try again in a moment."),
      findsNothing,
    );

    await foreground(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(platform.calls, contains('play'));
    expect(controllerOf(tester).value.isPlaying, isTrue);
    expect(streaks.spends, 1);
  });

  testWidgets('a photo hold stops while away and keeps its time left', (
    tester,
  ) async {
    final image = _ControlledImage();
    final decoded = await tester.runAsync(
      () => createTestImage(width: 1, height: 1),
    );
    final streaks = _StreakRepo([_photoClip]);
    await open(tester, streaks, imageProviderBuilder: (_) => image);
    image.bytes.complete(ImageInfo(image: decoded!));
    await tester.pump(); // first frame
    await tester.pump(); // post-frame: the hold starts
    expect(streaks.spends, 1);

    const hold = Duration(seconds: 5); // kStoryImageHoldDuration
    await tester.pump(const Duration(seconds: 2));
    await background(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.byType(StreakViewerScreen),
      findsOneWidget,
      reason: 'the hold does not run out behind the lock screen',
    );

    await foreground(tester);
    await tester.pump(hold - const Duration(seconds: 2, milliseconds: 100));
    expect(find.byType(StreakViewerScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(streaks.spends, 1);
  });

  testWidgets('an inactive blip alone pauses too: the privacy cover is up '
      '(stories Wave 3)', (tester) async {
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(controllerOf(tester).value.isPlaying, isTrue);
    platform.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.calls, contains('pause'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, contains('play'));
    expect(streaks.spends, 1);
  });

  testWidgets('a return that stops at the Safety lock check stays paused '
      'until the lock opens (stories Wave 3)', (tester) async {
    final streaks = _StreakRepo([_videoClip]);
    await open(tester, streaks);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StreakViewerScreen)),
    );
    platform.calls.clear();
    await background(tester);
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    await foreground(tester);
    expect(platform.calls, isNot(contains('play')));
    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump();
    expect(platform.calls, contains('play'));
    expect(find.byType(StreakViewerScreen), findsOneWidget);
    expect(streaks.spends, 1);
  });

  testWidgets('a photo that arrives behind the Safety lock check is not '
      'spent, and its hold does not start, until the lock opens '
      '(stories Wave 3)', (tester) async {
    final image = _ControlledImage();
    final decoded = await tester.runAsync(
      () => createTestImage(width: 1, height: 1),
    );
    final streaks = _StreakRepo([_photoClip]);
    await open(tester, streaks, imageProviderBuilder: (_) => image);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StreakViewerScreen)),
    );
    await background(tester);
    container.read(appContentVisibleProvider.notifier).setLockOpen(false);
    await foreground(tester);

    image.bytes.complete(ImageInfo(image: decoded!));
    await tester.pump(); // first frame, behind the PIN check
    await tester.pump(); // post-frame
    await tester.pump(const Duration(seconds: 30));
    expect(streaks.spends, 0, reason: 'nobody has seen it');
    expect(find.byType(StreakViewerScreen), findsOneWidget);

    container.read(appContentVisibleProvider.notifier).setLockOpen(true);
    await tester.pump(); // rebuilt: the frame is shown
    await tester.pump(); // post-frame: spent, the hold starts
    expect(streaks.spends, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(StreakViewerScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(StreakViewerScreen), findsNothing);
    expect(streaks.spends, 1);
  });
}
