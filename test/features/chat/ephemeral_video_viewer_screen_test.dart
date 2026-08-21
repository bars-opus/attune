import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  // ScreenshotDetectionService listens on this exact MethodChannel name
  // (lib/core/services/media/screenshot_detection_service.dart) and treats
  // an incoming 'onScreenshot' call as a detected screenshot event. There
  // is no test seam to inject a fake service into
  // EphemeralVideoViewerScreen (it constructs its own instance internally,
  // matching the class's own "best-effort instrumentation" design), so
  // tests that need to simulate a screenshot drive the platform channel
  // directly the same way the real native side would.
  const screenshotChannel = MethodChannel('attune/screenshot_detection');

  Future<void> simulateScreenshot(WidgetTester tester) async {
    final call = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onScreenshot'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      screenshotChannel.name,
      call,
      (_) {},
    );
  }

  // Reached via GoRouter's 'ephemeralVideoViewer' named route in production
  // (see app_router.dart) — EphemeralVideoViewerScreen's own dismiss/pop
  // path now calls context.pop(), which requires a real GoRouter ancestor,
  // not just a Navigator. A minimal two-route GoRouter (open button pushes
  // 'viewer') mirrors production's route-based navigation instead of a
  // bare MaterialApp + Navigator.push, so an initialize()-failure pop (real
  // on this test host, since there is no platform video decoder, matching
  // VideoMessagePlayer's documented rejection behavior) has an actual
  // route to return to.
  Widget buildHarness(ProviderContainer container, Widget viewer) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => context.push('/viewer'),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
        GoRoute(path: '/viewer', builder: (context, state) => viewer),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets(
    'calls markVideoViewed via the repository when playback completes or is dismissed',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      // Keep chatControllerProvider (an .autoDispose family) alive for the
      // whole test by holding a subscription to its notifier, mirroring
      // chat_state_send_ephemeral_video_message_test.dart's _Booted pattern —
      // without this a bare container.read() later in the test can observe
      // stale/uninitialized state.
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // Two pumps are required to complete the push: the first registers the
      // tap and starts MaterialPageRoute's transition; the new route isn't
      // hit-testable as the topmost route until a second pump advances past
      // its ~300ms transition animation. (Now that initState's catchError is
      // a deliberate no-op — see EphemeralVideoViewerScreen's own comment —
      // there is no rejection-driven state change left to race against
      // here.)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap anywhere to dismiss — exercises the explicit-dismissal path since
      // a real playback-completion event needs a platform video decoder
      // unavailable in this test host.
      await tester.tap(find.byType(EphemeralVideoViewerScreen));
      await tester.pump();

      expect(repo.markVideoViewedCalls, ['m1']);
    },
  );

  testWidgets(
    'self-closes with an "already viewed" indicator if the message becomes expired while open',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      final seeded = repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      // seedIncoming has no isViewOnce param (a pre-existing, shared harness
      // method with no prior ephemeral-video callers) — set it directly so
      // this message is a genuinely view-once row; otherwise
      // isEphemeralVideoExpired (isViewOnce && viewedAt != null) is always
      // false regardless of viewedAt, and ephemeralVideoExpiredProvider would
      // never actually go true.
      repo.serverMessages['m1'] = seeded.copyWith(isViewOnce: true);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      // See the first test's comment: keep the .autoDispose family alive by
      // holding the notifier for the whole test.
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      // Simulate a second device/viewer revoking the video via
      // mark_video_viewed BEFORE this screen is ever pushed: the fake server
      // row's viewed_at flips, and a realtime "something changed" signal
      // drives ChatController's real refresh path
      // (_refreshConversation/loadMessages -> _mergeMessages), exactly as
      // production does when a revocation lands over realtime.
      //
      // tester.pump(duration) (NOT a bare `await Future.delayed(...)`) is
      // required to let ChatController's real dart:async Timer-based
      // realtime-refresh debounce actually fire: testWidgets bodies run
      // inside a package:fake_async FakeAsync zone (see
      // AutomatedTestWidgetsFlutterBinding), where pending Timers are
      // advanced by pump(duration)'s elapse() call, not by real wall-clock
      // waiting — a bare Future.delayed there just stalls forever waiting on
      // a Timer nothing ever advances.
      final serverMessage = repo.serverMessages['m1']!;
      repo.serverMessages['m1'] = serverMessage.copyWith(
        viewedAt: DateTime.now(),
      );
      repo.emitRealtime();
      await tester.pump(
        container.read(chatConfigProvider).realtimeRefreshDebounce +
            const Duration(milliseconds: 150),
      );

      // Deliberately done with no video-playback widget mounted yet, so the
      // revocation-processing pumps above never interleave with
      // EphemeralVideoViewerScreen's own VideoPlayerController lifecycle —
      // the two are independent concerns and this keeps the test focused on
      // ephemeralVideoExpiredProvider's wiring, not video playback.
      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // Two pumps to complete the push — see the first test's identical
      // comment on why a single pump() (or a single pump(duration)) is
      // insufficient here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The message was already expired by the time this screen's first
      // build ran, so ephemeralVideoExpiredProvider's watched (not merely
      // listened) value catches it immediately — see the "isExpiredNow"
      // guard in EphemeralVideoViewerScreen.build.
      expect(find.text('Already viewed'), findsOneWidget);
    },
  );

  testWidgets(
    'shows a visible error state (not an indefinite spinner) when the video '
    "can't be initialized, and dismissing it calls markVideoViewed once",
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // Two pumps to complete the push (see the first test's comment), plus
      // this test host's VideoPlayerController.initialize() rejecting (no
      // platform video decoder, matching VideoMessagePlayer's documented
      // behavior) during that same window — that rejection is exactly what
      // this test means to exercise.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text("Couldn't play this video"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(EphemeralVideoViewerScreen));
      await tester.pump();

      expect(repo.markVideoViewedCalls, ['m1']);
    },
  );

  testWidgets('still closes the screen when markVideoViewed fails on both the '
      'initial call and its retry (Important finding I1)', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    repo.seedIncoming(
      id: 'm1',
      relationshipId: relId,
      senderId: 'partner',
      content: '',
      createdAt: DateTime.now(),
    );
    // Both the initial attempt and the one retry fail, exercising the
    // worst case: the user must still be able to leave the screen even
    // though the server call never landed.
    repo.markVideoViewedFailures.addAll([
      Exception('network down'),
      Exception('still down'),
    ]);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(chatControllerProvider(conversation).notifier);

    await tester.pumpWidget(
      buildHarness(
        container,
        EphemeralVideoViewerScreen(
          messageId: 'm1',
          videoUrl: '/tmp/local/clip.mp4',
          conversation: conversation,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Tap to dismiss: triggers _markViewedAndClose, which should try once,
    // fail, wait ~500ms, retry, fail again, and STILL pop the route rather
    // than leaving the user stuck.
    await tester.tap(find.byType(EphemeralVideoViewerScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // Let the pop's route-removal transition (~300ms) finish, same as the
    // push transition this file's other tests already account for.
    await tester.pump(const Duration(milliseconds: 350));

    expect(repo.markVideoViewedCalls, ['m1', 'm1']);
    // The viewer route is gone; back on the harness's "open" screen.
    expect(find.byType(EphemeralVideoViewerScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
    'closes normally after one failed attempt followed by a successful '
    'retry (Important finding I1)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      repo.markVideoViewedFailures.add(Exception('transient network blip'));
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(find.byType(EphemeralVideoViewerScreen));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 350));

      expect(repo.markVideoViewedCalls, ['m1', 'm1']);
      expect(find.byType(EphemeralVideoViewerScreen), findsNothing);
    },
  );

  testWidgets(
    'sends at most one screenshot notice per screen instance even when '
    'the platform channel fires the event twice (Important finding I4)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final sendsBefore = repo.sendCallCount;

      // Simulate the platform firing the screenshot event twice in quick
      // succession — e.g. across the Android native ContentObserver's
      // debounce window, or on iOS which has no native debounce at all.
      await simulateScreenshot(tester);
      await simulateScreenshot(tester);
      await tester.pump();

      expect(
        repo.sendCallCount - sendsBefore,
        1,
        reason:
            'only the first screenshot event should produce a system-notice send',
      );
      expect(
        repo.serverMessages.values.where((m) => m.isSystemNotice).length,
        1,
      );
    },
  );

  testWidgets(
    'a failed screenshot-notice send does not crash the screen or block '
    'playback/dismissal (Important finding I4)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final conversation = activeConversation(relId);
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now(),
      );
      repo.nextSendError = Exception('screenshot notice send failed');
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      container.read(chatControllerProvider(conversation).notifier);

      await tester.pumpWidget(
        buildHarness(
          container,
          EphemeralVideoViewerScreen(
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            conversation: conversation,
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await simulateScreenshot(tester);
      await tester.pump();

      // The screen must still be usable — no uncaught exception should have
      // propagated out of the stream listener. Dismissing normally still
      // works and still calls markVideoViewed.
      await tester.tap(find.byType(EphemeralVideoViewerScreen));
      await tester.pump();

      expect(repo.markVideoViewedCalls, ['m1']);
      expect(tester.takeException(), isNull);
    },
  );
}
