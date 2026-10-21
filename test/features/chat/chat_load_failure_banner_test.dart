import 'dart:io';

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// The conversation banner after a cold open whose first page failed
/// (W1a Task 7 (b), fix M1).
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    required bool online,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      connectivity: Stream<bool>.value(online),
    );
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
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

  testWidgets('a failed cold open keeps saying so after the writes that '
      'follow it', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.getMessagesError = const SocketException('offline');
    final container = await pumpChat(tester, repo, online: true);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Could not sync'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('offline with messages waiting, the queued count wins over '
      'the old load failure', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.getMessagesError = const SocketException('offline');
    repo.sendErrorQueue.add(const SocketException('offline'));
    final container = await pumpChat(tester, repo, online: false);

    await container
        .read(chatControllerProvider(activeConversation('rel-1')).notifier)
        .sendMessage('waiting');
    // The send's own offline notice is a fresh error and lasts until the
    // next state write (a header refresh here); the load failure outlives
    // it, and that is what must not cover the queued count.
    container.read(conversationsRefreshProvider.notifier).state++;
    await tester.pump(const Duration(milliseconds: 400));
    // Let the banner's switch animation retire the outgoing card.
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('1 message queued. They will send when you reconnect.'),
      findsOneWidget,
    );
    expect(find.text('Could not sync'), findsNothing);
    await tearDownChat(tester, container);
  });
}
