import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Covers ChatScreen.initialJumpToMessageId — arriving from Starred
/// messages (or any future entry point) with a specific message to scroll
/// to and flash, including the case where that message is older than the
/// first loaded page and must be paged in via loadMoreMessages first.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    String? initialJumpToMessageId,
    int messagePageSize = 50,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [
        chatConfigProvider.overrideWithValue(
          ChatConfig(messagePageSize: messagePageSize),
        ),
      ],
    );
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ChatScreen(
            conversation: convo,
            initialJumpToMessageId: initialJumpToMessageId,
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

  testWidgets(
      'scrolls to and highlights the target message when it is already in the loaded page',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now();
    for (var i = 0; i < 10; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'message $i',
        createdAt: base.subtract(Duration(minutes: 10 - i)),
      );
    }
    final container = await pumpChat(
      tester,
      repo,
      initialJumpToMessageId: 'm3',
    );
    await tester.pumpAndSettle();

    expect(find.text('message 3'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets(
      'pages backward to find and scroll to a target message older than the first page',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now();
    // 12 messages with a page size of 5: the target (oldest, m0) is on the
    // third page, so this only passes if loadMoreMessages is actually
    // called repeatedly rather than just searching the first page.
    for (var i = 0; i < 12; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'message $i',
        createdAt: base.subtract(Duration(minutes: 12 - i)),
      );
    }
    final container = await pumpChat(
      tester,
      repo,
      initialJumpToMessageId: 'm0',
      messagePageSize: 5,
    );
    // Allow the paging loop's async loadMoreMessages calls to complete —
    // each is a real (fake-repo) round trip plus a settle.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(find.text('message 0'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets(
      'does nothing when initialJumpToMessageId is null (normal open)',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('hello there'), findsOneWidget);
    await tearDownChat(tester, container);
  });
}
