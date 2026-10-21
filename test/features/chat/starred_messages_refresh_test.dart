import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// RC-12: starredMessagesProvider was a plain FutureProvider nobody ever
/// invalidated, so Starred showed its first fetch for the whole session.
void main() {
  test('starring and unstarring refresh the Starred list', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm2',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'keep this',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A live listener, as the Starred screen's ref.watch would be.
    final sub = container.listen(starredMessagesProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await container.read(starredMessagesProvider.future), isEmpty);

    await controller.starMessage('m2');
    expect(
      (await container.read(starredMessagesProvider.future)).map((m) => m.id),
      ['m2'],
    );

    await controller.unstarMessage('m2');
    expect(await container.read(starredMessagesProvider.future), isEmpty);
  });

  group('an open Starred list follows changes to a starred row (M-12)', () {
    Future<
      ({
        ProviderContainer container,
        ChatController controller,
        FakeChatRepository repo,
      })
    >
    open() async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final now = DateTime.now();
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'user-a',
        content: 'home at 9',
        createdAt: now.subtract(const Duration(minutes: 2)),
      );
      repo.seedIncoming(
        id: 'm2',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'bring the keys',
        createdAt: now.subtract(const Duration(minutes: 1)),
      );
      repo.starredMessageIds.addAll(['m1', 'm2']);
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await controller.whenOpened;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sub = container.listen(starredMessagesProvider, (_, __) {});
      addTearDown(sub.close);
      expect(
        (await container.read(starredMessagesProvider.future)).map(
          (m) => m.content,
        ),
        containsAll(['home at 9', 'bring the keys']),
      );
      return (container: container, controller: controller, repo: repo);
    }

    Future<Map<String, String>> starred(ProviderContainer container) async => {
      for (final m in await container.read(starredMessagesProvider.future))
        m.id: m.isDeleted ? '<deleted>' : m.content,
    };

    test('my edit', () async {
      final (:container, :controller, :repo) = await open();
      final message = controller.state.messages.firstWhere((m) => m.id == 'm1');
      await controller.editMessage(message, 'home at 10');
      expect((await starred(container))['m1'], 'home at 10');
    });

    test('my delete', () async {
      final (:container, :controller, :repo) = await open();
      final message = controller.state.messages.firstWhere((m) => m.id == 'm1');
      await controller.deleteMessage(message);
      expect((await starred(container))['m1'], '<deleted>');
    });

    test('a partner edit applied by id (realtime)', () async {
      final (:container, :controller, :repo) = await open();
      repo.serverMessages['m2'] = repo.serverMessages['m2']!.copyWith(
        content: 'bring the spare keys',
        editedAt: DateTime.now(),
      );
      repo.touch('m2');
      await controller.refreshMessagesByIds({'m2'});
      expect((await starred(container))['m2'], 'bring the spare keys');
    });

    test('a partner edit applied by changes-since', () async {
      final (:container, :controller, :repo) = await open();
      repo.serverMessages['m2'] = repo.serverMessages['m2']!.copyWith(
        content: 'bring the spare keys',
        editedAt: DateTime.now(),
      );
      repo.touch('m2', DateTime.now().add(const Duration(seconds: 1)));
      await controller.syncChangesSinceCursor();
      expect(
        controller.state.messages.firstWhere((m) => m.id == 'm2').content,
        'bring the spare keys',
        reason: 'the sync applied it',
      );
      expect((await starred(container))['m2'], 'bring the spare keys');
    });
  });

  test('the provider is released when nothing watches it', () {
    expect(starredMessagesProvider, isA<AutoDisposeFutureProvider<Object?>>());
  });
}
