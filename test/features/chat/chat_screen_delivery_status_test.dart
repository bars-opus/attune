import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
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

  testWidgets('ticks show on the newest own message and each own group end', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(minutes: 10));
    // own, own (group end), partner, own (newest own)
    repo.seedIncoming(
      id: 'o1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'one',
      createdAt: base,
      deliveredAt: base,
    );
    repo.seedIncoming(
      id: 'o2',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'two',
      createdAt: base.add(const Duration(minutes: 1)),
      deliveredAt: base,
    );
    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'reply',
      createdAt: base.add(const Duration(minutes: 2)),
    );
    repo.seedIncoming(
      id: 'o3',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'three',
      createdAt: base.add(const Duration(minutes: 3)),
    );
    repo.seedIncoming(
      id: 'p2',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'last',
      createdAt: base.add(const Duration(minutes: 4)),
    );
    final semantics = tester.ensureSemantics();
    final container = await pumpChat(tester, repo);

    bool hasTick(String text) =>
        find
            .descendant(
              of: find.ancestor(
                of: find.text(text),
                matching: find.byType(MessageBubble),
              ),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    (w.properties.label ?? '').startsWith('Message status:'),
              ),
            )
            .evaluate()
            .isNotEmpty;

    expect(hasTick('three'), isTrue, reason: 'newest own');
    expect(hasTick('two'), isTrue, reason: 'end of the first own group');
    expect(hasTick('one'), isFalse, reason: 'settled mid-group row');
    expect(hasTick('reply'), isFalse);
    await tearDownChat(tester, container);
    semantics.dispose();
  });

  testWidgets('a failed own row in the middle of a run shows its tick and '
      'Retry', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(minutes: 10));
    repo.seedIncoming(
      id: 'o1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'first',
      createdAt: base,
      deliveredAt: base,
    );
    final semantics = tester.ensureSemantics();
    final container = await pumpChat(tester, repo);
    final controller = container.read(
      chatControllerProvider(activeConversation('rel-1')).notifier,
    );

    // A permanent refusal fails the send; the next one goes through, so
    // the failed row sits between two own rows (not a group end).
    repo.nextSendError = const PostgrestException(
      message: 'permission denied',
      code: '42501',
    );
    await tester.runAsync(() => controller.sendMessage('refused'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => controller.sendMessage('after'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    Finder inBubble(String text, Finder matching) => find.descendant(
      of: find.ancestor(
        of: find.text(text),
        matching: find.byType(MessageBubble),
      ),
      matching: matching,
    );
    final failedTick = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Message status: Failed',
    );
    expect(
      container
          .read(chatControllerProvider(activeConversation('rel-1')))
          .messages
          .map((m) => (m.content, m.status))
          .take(2),
      [('after', MessageStatus.sent), ('refused', MessageStatus.failed)],
    );
    expect(inBubble('refused', failedTick), findsOneWidget);
    expect(inBubble('refused', find.text('Retry')), findsOneWidget);
    await tearDownChat(tester, container);
    semantics.dispose();
  });

  testWidgets('a swipe exposes one "Message status" node, not two', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: Message(
                id: 'm1',
                clientMessageId: 'c1',
                relationshipId: 'r1',
                senderId: 'me',
                content: 'hello',
                createdAt: DateTime(2026, 7, 1, 15, 4),
                status: MessageStatus.delivered,
                isMine: true,
              ),
              // A group end mid-swipe: the footer chip and the revealed
              // column's chip are both on screen.
              timestampRevealOffset: 80,
            ),
          ),
        ),
      ),
    );

    // The footer's chip is merged into the bubble's node ("hello | Message
    // status: …"); the revealed column must not add a second one.
    expect(find.bySemanticsLabel(RegExp('Message status: ')), findsOneWidget);
    semantics.dispose();
  });
}

