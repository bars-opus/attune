import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Task 8 wiring: ChatScreen must pass real message-action handlers down to
/// MessageBubble and render the pinned-messages banner from ChatState.
void main() {
  /// Boots ChatScreen against [repo] and settles the initial load.
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    Conversation? conversation,
  }) async {
    // The actions sheet lists up to six tiles; the default 800x600 surface
    // pushes Edit/Delete below the fold and off the hit-test area.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = conversation ?? activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: ChatScreen(conversation: convo)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// Unmounts before disposing so the controller's keep-alive eviction timer
  /// is cancelled instead of racing the binding's pending-timer check —
  /// mirrors message_list_animation_test.dart's teardown.
  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('long-pressing a bubble opens the actions sheet', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();

    // currentUserId is wired through, so the sheet actually opens.
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tearDownChat(tester, container);
  });

  testWidgets('Star from the sheet reaches the repository', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();

    expect(repo.starredMessageIds, contains('m1'));
    await tearDownChat(tester, container);
  });

  testWidgets('Pin from the sheet renders the pinned banner', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'pin me please',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    expect(find.byIcon(Icons.push_pin), findsNothing);

    await tester.longPress(find.text('pin me please'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(repo.pinnedMessageIds, contains('m1'));
    // The banner's pin icon plus the bubble text now duplicated in the strip.
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('pin me please'), findsNWidgets(2));

    await tearDownChat(tester, container);
  });

  testWidgets('already-pinned messages load into the banner on open', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'pinned earlier',
      createdAt: DateTime.now(),
    );
    repo.pinnedMessageIds.add('m1');

    final container = await pumpChat(tester, repo);

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('Delete confirms before calling the repository', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      // Own message inside the edit/delete window so the sheet offers them.
      senderId: 'user-a',
      content: 'oops',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('oops'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete message?'), findsOneWidget);
    // Cancelling must not delete.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.deleteMessageCalls, isEmpty);

    await tester.longPress(find.text('oops'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deleteMessageCalls, contains('m1'));
    expect(find.text('This message was deleted'), findsOneWidget);

    await tearDownChat(tester, container);
  });

  testWidgets('Edit saves the new content through the controller', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'teh typo',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('teh typo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit message'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'the typo');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.editMessageCalls.single.messageId, 'm1');
    expect(repo.editMessageCalls.single.newContent, 'the typo');
    // The "edited" affordance is wired to the edit-history sheet.
    expect(find.text('edited'), findsOneWidget);
    await tester.tap(find.text('edited'));
    await tester.pumpAndSettle();
    expect(find.text('Edit history'), findsOneWidget);
    // The current content always closes out the history list.
    expect(find.text('Current'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tearDownChat(tester, container);
  });

  // Fix round 1: an ended relationship opened through "Previous relationships"
  // reuses this same ChatScreen. The whole action surface is gated on
  // canSend, so long-press must not offer mutating actions the RPCs now
  // correctly reject server-side.
  testWidgets('read-only conversation offers no actions on long-press', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'just sent this',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(
      tester,
      repo,
      conversation: readOnlyConversation('rel-1'),
    );

    await tester.longPress(find.text('just sent this'));
    await tester.pumpAndSettle();

    // No sheet at all — not merely Edit/Delete withheld.
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Star'), findsNothing);
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await tearDownChat(tester, container);
  });
}
