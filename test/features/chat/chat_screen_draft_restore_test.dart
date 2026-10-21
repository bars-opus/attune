import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    required String savedDraft,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    await container
        .read(chatCacheServiceProvider)
        .writeDraft('user-a', 'rel-1', savedDraft);
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

  testWidgets(
    'restoring a saved draft fills the composer without telling the partner '
    'I am typing',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final container = await pumpChat(
        tester,
        repo,
        savedDraft: 'hey, about tonight',
      );

      expect(find.text('hey, about tonight'), findsOneWidget);
      expect(
        repo.sentTyping,
        isEmpty,
        reason: 'a restore is not typing; the partner must not see "typing…"',
      );

      // Actually typing still does.
      await tester.enterText(
        find.byType(TextField).first,
        'hey, about tonight!',
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(repo.sentTyping.where((t) => t.typing), isNotEmpty);

      await tearDownChat(tester, container);
    },
  );
}
