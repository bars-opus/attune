// Stories Wave 3: the chat and its viewers stay mounted behind the privacy
// cover and the lock check, so a video must stop itself while Attune is
// not on screen.
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../helpers/recording_video_platform.dart';
import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late VideoPlayerPlatform original;
  late RecordingVideoPlatform platform;

  setUp(() {
    original = VideoPlayerPlatform.instance;
    platform = RecordingVideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = original);

  void life(WidgetTester t, AppLifecycleState s) =>
      t.binding.handleAppLifecycleStateChanged(s);

  Future<({ProviderContainer container, FakeChatRepository repo})> openViewer(
    WidgetTester tester,
  ) async {
    addTearDown(() => life(tester, AppLifecycleState.resumed));
    final repo = FakeChatRepository(currentUserId: userId);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(chatControllerProvider(conversation).notifier);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => context.push('/viewer'),
                  child: const Text('open'),
                ),
              ),
        ),
        GoRoute(
          path: '/viewer',
          builder:
              (_, __) => EphemeralVideoViewerScreen(
                messageId: 'm1',
                videoUrl: '/tmp/local/clip.mp4',
                conversation: conversation,
              ),
        ),
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
    await tester.pump();
    return (container: container, repo: repo);
  }

  group('ephemeral video viewer', () {
    testWidgets('pauses while Attune is off screen and carries on after; '
        'nothing is marked viewed meanwhile', (tester) async {
      final v = await openViewer(tester);
      expect(platform.calls, contains('play'));
      platform.calls.clear();
      life(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(platform.calls, contains('pause'), reason: 'no sound behind it');
      await tester.pump(const Duration(seconds: 10));
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, contains('play'));
      expect(v.repo.markVideoViewedCalls, isEmpty);
    });

    testWidgets('a clip that opens while Attune is off screen waits to start', (
      tester,
    ) async {
      final init = Completer<void>();
      platform = RecordingVideoPlatform(initGate: init);
      VideoPlayerPlatform.instance = platform;
      await openViewer(tester);
      life(tester, AppLifecycleState.inactive);
      init.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.calls, isNot(contains('play')));
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, contains('play'));
    });

    testWidgets('a return that stops at the lock check waits for the lock '
        '(Review Focus 1)', (tester) async {
      final v = await openViewer(tester);
      platform.calls.clear();
      life(tester, AppLifecycleState.inactive);
      v.container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      life(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(platform.calls, isNot(contains('play')));
      v.container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump();
      expect(platform.calls, contains('play'));
    });
  });

  testWidgets('an inline chat video stops when Attune leaves the screen and '
      'stays stopped on return (a tap plays it again)', (tester) async {
    addTearDown(() => life(tester, AppLifecycleState.resumed));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              messageId: 'm1',
              videoUrl: '/tmp/local/inline.mp4',
              thumbnailUrl: null,
              durationMs: 4000,
              width: 720,
              height: 1280,
              autoPlay: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.calls, contains('play'));
    platform.calls.clear();
    life(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(platform.calls, contains('pause'));
    life(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.calls, isNot(contains('play')));
    expect(
      tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller
          .value
          .isPlaying,
      isFalse,
    );
  });

  testWidgets('a tapped inline video whose loading finishes after Attune '
      'leaves the screen stays paused and waits for a tap (fix round 0)', (
    tester,
  ) async {
    addTearDown(() => life(tester, AppLifecycleState.resumed));
    final init = Completer<void>();
    platform = RecordingVideoPlatform(initGate: init);
    VideoPlayerPlatform.instance = platform;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              messageId: 'm1',
              videoUrl: '/tmp/local/inline.mp4',
              thumbnailUrl: null,
              durationMs: 4000,
              width: 720,
              height: 1280,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(VideoMessagePlayer));
    await tester.pump();
    life(tester, AppLifecycleState.inactive);
    init.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.calls, isNot(contains('play')), reason: 'off screen');
    life(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.calls, isNot(contains('play')), reason: 'waits for a tap');
    expect(
      container.read(currentlyPlayingVideoMessageIdProvider),
      isNull,
      reason: 'the cross-media lock is not held by a clip that never played',
    );

    await tester.tap(find.byType(VideoMessagePlayer));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(platform.calls, contains('play'));
  });
}
