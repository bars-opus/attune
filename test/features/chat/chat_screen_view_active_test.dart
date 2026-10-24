import 'dart:async';

import 'package:attune/app/routing/app_route_observer.dart';
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  // The observer is app-wide: what one test pushed must not leak into the
  // next one's PopupRoute checks.
  setUp(() => appRouteObserver.lastPushedRoute = null);

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: userId);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            navigatorObservers: [appRouteObserver],
            home: ChatScreen(conversation: convo),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  /// Drives the lifecycle the way the engine does (the public channel), so
  /// WidgetsBindingObserver.didChangeAppLifecycleState fires on the screen.
  Future<void> setLifecycle(WidgetTester tester, String state) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state),
      (_) {},
    );
  }

  testWidgets(
    'a route pushed over the chat ends presence and stops read receipts '
    'until it pops',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = await pumpChat(tester, repo);
      expect(repo.presenceCalls.last, relId, reason: 'the chat is on screen');

      final navigator = Navigator.of(tester.element(find.byType(ChatScreen)));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder:
                (_) => const Scaffold(body: Center(child: Text('Love Map'))),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.presenceCalls.last, isNull, reason: 'a game covers the chat');

      // The partner writes while the game is open.
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'are you there?',
        createdAt: DateTime.now(),
      );
      repo.emitRealtime();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        repo.markReadCalls,
        isEmpty,
        reason: 'nobody saw it: it must not be marked read',
      );

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.presenceCalls.last, relId, reason: 'back on the chat');
      await tester.pump(const Duration(milliseconds: 700));
      expect(repo.markReadCalls, isNotEmpty, reason: 'now it has been seen');

      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'leaving the foreground (inactive, as on screen lock) ends presence; '
    'resuming restores it',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = await pumpChat(tester, repo);
      expect(repo.presenceCalls.last, relId);

      await setLifecycle(tester, 'AppLifecycleState.inactive');
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.presenceCalls.last, isNull);

      await setLifecycle(tester, 'AppLifecycleState.paused');
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.presenceCalls.last, isNull);

      await setLifecycle(tester, 'AppLifecycleState.resumed');
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.presenceCalls.last, relId);

      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'a sheet or dialog over the chat keeps presence and read receipts: '
    'the person is still in the chat',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = await pumpChat(tester, repo);
      expect(repo.presenceCalls.last, relId);
      final presenceCallsBefore = repo.presenceCalls.length;

      final chatContext = tester.element(find.byType(ChatScreen));
      unawaited(
        showModalBottomSheet<void>(
          context: chatContext,
          builder:
              (_) =>
                  const SizedBox(height: 200, child: Text('Message actions')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        repo.presenceCalls.length,
        presenceCallsBefore,
        reason: 'a popup route must not clear presence',
      );

      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'still here?',
        createdAt: DateTime.now(),
      );
      repo.emitRealtime();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        repo.markReadCalls,
        isNotEmpty,
        reason: 'the chat is still what the person is looking at',
      );

      Navigator.of(chatContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.presenceCalls.last, relId);

      await tearDownChat(tester, container);
    },
  );

  testWidgets('a cover taken off the stack without a pop (removeRoute) still '
      'gives the chat back its presence', (tester) async {
    // RouteObserver reports didPop but not didRemove, so didPopNext never
    // fires for this; the chat must not stay stuck inactive.
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    final navigator = Navigator.of(tester.element(find.byType(ChatScreen)));
    final page = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Center(child: Text('Love Map'))),
    );
    unawaited(navigator.push(page));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, isNull, reason: 'a game covers the chat');

    navigator.removeRoute(page);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId, reason: 'back on the chat');
    await tearDownChat(tester, container);
  });
  testWidgets('coming back to the foreground while a game still covers the '
      'chat does not mark anything read', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    final navigator = Navigator.of(tester.element(find.byType(ChatScreen)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Love Map'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await setLifecycle(tester, 'AppLifecycleState.paused');
    await tester.pump(const Duration(milliseconds: 50));
    await setLifecycle(tester, 'AppLifecycleState.resumed');
    await tester.pump(const Duration(milliseconds: 50));

    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'are you there?',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      repo.markReadCalls,
      isEmpty,
      reason: 'the game is still what the person is looking at',
    );
    expect(repo.presenceCalls.last, isNull);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('coming back to the foreground with a sheet open over the chat '
      'restores presence: the sheet does not cover it', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    final chatContext = tester.element(find.byType(ChatScreen));
    unawaited(
      showModalBottomSheet<void>(
        context: chatContext,
        builder:
            (_) => const SizedBox(height: 200, child: Text('Message actions')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await setLifecycle(tester, 'AppLifecycleState.inactive');
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.presenceCalls.last, isNull);
    await setLifecycle(tester, 'AppLifecycleState.resumed');
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      repo.presenceCalls.last,
      relId,
      reason: 'the chat is not current only because a sheet is open',
    );

    Navigator.of(chatContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('a sheet that replaces itself with a page (pushReplacement) '
      'covers the chat', (tester) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = await pumpChat(tester, repo);
    final chatContext = tester.element(find.byType(ChatScreen));
    unawaited(
      showModalBottomSheet<void>(
        context: chatContext,
        builder:
            (sheetContext) => SizedBox(
              height: 200,
              child: TextButton(
                onPressed:
                    () => Navigator.of(sheetContext).pushReplacement(
                      MaterialPageRoute<void>(
                        builder:
                            (_) => const Scaffold(
                              body: Center(child: Text('Love Map')),
                            ),
                      ),
                    ),
                child: const Text('Play'),
              ),
            ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId);

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Love Map'), findsOneWidget);
    expect(
      repo.presenceCalls.last,
      isNull,
      reason: 'the replacing page covers the chat',
    );

    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'are you there?',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    expect(repo.markReadCalls, isEmpty);

    Navigator.of(chatContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId, reason: 'back on the chat');
    await tearDownChat(tester, container);
  });

  test('createAppRouter installs appRouteObserver on its navigator', () {
    final notifier = RoutingNotifier();
    final router = createAppRouter(notifier);
    addTearDown(() {
      router.dispose();
      notifier.dispose();
    });
    expect(router.routerDelegate.builder.observers, contains(appRouteObserver));
  });

  testWidgets('through GoRouter (observers: [appRouteObserver], as '
      'createAppRouter does), pushNamed over the chat ends presence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final router = GoRouter(
      initialLocation: '/',
      observers: [appRouteObserver],
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, state) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => context.push('/chat'),
                    child: const Text('conversation list'),
                  ),
                ),
              ),
        ),
        GoRoute(
          path: '/chat',
          builder: (context, state) => ChatScreen(conversation: convo),
        ),
        GoRoute(
          path: '/loveMap',
          name: 'loveMap',
          builder:
              (context, state) =>
                  const Scaffold(body: Center(child: Text('Love Map'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(MaterialApp.router(routerConfig: router)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('conversation list'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId);

    unawaited(
      tester.element(find.byType(ChatScreen)).pushNamed<void>('loveMap'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, isNull, reason: 'a game covers the chat');

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.presenceCalls.last, relId, reason: 'back on the chat');

    await tearDownChat(tester, container);
  });

  testWidgets(
    'a return that stops at the Safety lock check keeps presence and read '
    'receipts off until the lock opens (stories Wave 3)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = await pumpChat(tester, repo);
      expect(repo.presenceCalls.last, relId);

      await setLifecycle(tester, 'AppLifecycleState.paused');
      await tester.pump(const Duration(milliseconds: 50));
      // What SafetyLockGate does on a return: the lock is being checked.
      container.read(appContentVisibleProvider.notifier).setLockOpen(false);
      await setLifecycle(tester, 'AppLifecycleState.resumed');
      await tester.pump(const Duration(milliseconds: 50));

      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'are you there?',
        createdAt: DateTime.now(),
      );
      repo.emitRealtime();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        repo.presenceCalls.last,
        isNull,
        reason: 'the PIN check is on screen, not the chat',
      );
      expect(repo.markReadCalls, isEmpty, reason: 'nobody has seen it');

      container.read(appContentVisibleProvider.notifier).setLockOpen(true);
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.presenceCalls.last, relId);
      await tester.pump(const Duration(milliseconds: 700));
      expect(repo.markReadCalls, isNotEmpty);

      await tearDownChat(tester, container);
    },
  );
}
