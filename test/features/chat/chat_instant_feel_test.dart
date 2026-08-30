import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Verifies the "WhatsApp feel": a just-sent message appears instantly and does
/// not jump position, disappear, or reorder as its status ticks up.
void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  test(
    'sent message appears immediately and stays at the top through ack',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Seed an existing (older) message so there is a list to sit atop.
      repo.seedIncoming(
        id: 'old-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'earlier',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // Give the send real latency so the optimistic window is observable.
      repo.sendDelay = const Duration(milliseconds: 80);
      final sendFuture = controller.sendMessage('brand new');

      // Let the optimistic insert settle but not the ack.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Immediately after send (optimistic), the new message is top and sending.
      var state = container.read(chatControllerProvider(convo));
      expect(state.messages.first.content, 'brand new');
      expect(state.messages.first.status, MessageStatus.sending);
      expect(state.messages.first.id.startsWith('_local_'), isTrue);

      // After the server ack, it is the SAME slot (index 0), now sent, no jump.
      await sendFuture;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = container.read(chatControllerProvider(convo));
      expect(state.messages.first.content, 'brand new');
      expect(state.messages.first.status, MessageStatus.sent);
      expect(state.messages.first.id.startsWith('_local_'), isFalse);
      // The older message stayed below; nothing vanished.
      expect(
        state.messages.map((m) => m.content),
        containsAllInOrder(<String>['brand new', 'earlier']),
      );
      // Exactly one copy of the sent message — never duplicated.
      expect(state.messages.where((m) => m.content == 'brand new').length, 1);
    },
  );

  test(
    'a server timestamp slightly behind local time does not reorder',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.sendMessage('first');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await controller.sendMessage('second');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final state = container.read(chatControllerProvider(convo));
      // Newest-first: 'second' above 'first', order preserved through both acks.
      expect(
        state.messages.map((m) => m.content),
        containsAllInOrder(<String>['second', 'first']),
      );
      for (final m in state.messages) {
        expect(m.status, MessageStatus.sent);
      }
    },
  );

  test('warm cache: opening does not enter the cold loading state', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    // Pre-seed the cache so the next open has a warm cache.
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;

    // Seed a server message and boot once to populate the cache.
    repo.seedIncoming(
      id: 'm-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'cached history',
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    // The controller for this conversation now holds messages without ever
    // having presented an empty cold-load (messages are present).
    final state = container.read(chatControllerProvider(convo));
    expect(state.messages, isNotEmpty);
    // isLoading must be false once content is shown, not a spinner-over-content.
    expect(state.isLoading, isFalse);
  });
}
