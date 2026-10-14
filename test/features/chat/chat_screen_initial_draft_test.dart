import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Covers ChatScreen.initialDraft — arriving from Together's care card
/// ("How did it go?") with a message ready to send or edit.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    String? initialDraft,
    String? savedDraft,
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
    if (savedDraft != null) {
      await container
          .read(chatCacheServiceProvider)
          .writeDraft('user-a', 'rel-1', savedDraft);
    }
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            home: ChatScreen(conversation: convo, initialDraft: initialDraft),
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

  testWidgets('a draft passed in fills the composer', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = await pumpChat(
      tester,
      repo,
      initialDraft: 'How did the interview go?',
    );
    expect(find.text('How did the interview go?'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('no draft leaves the composer alone', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = await pumpChat(tester, repo);
    expect(find.text('How did the interview go?'), findsNothing);
    await tearDownChat(tester, container);
  });

  test('the chat route passes ?draft= through', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    final at = src.indexOf("name: 'chatScreen'");
    expect(
      src.substring(at, src.indexOf('GoRoute(', at)),
      contains("queryParameters['draft']"),
    );
  });

  testWidgets(
    'a saved draft is kept: the care line is added below it, and nothing is saved until I type',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final container = await pumpChat(
        tester,
        repo,
        savedDraft: 'About tonight',
        initialDraft: 'How did it go?',
      );
      expect(find.text('About tonight\nHow did it go?'), findsOneWidget);
      expect(
        await container
            .read(chatCacheServiceProvider)
            .readDraft('user-a', 'rel-1'),
        'About tonight',
      );
      await tearDownChat(tester, container);
    },
  );
}
