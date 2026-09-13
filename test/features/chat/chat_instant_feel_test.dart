import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
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

  test('send exposes the optimistic bubble before the server reply', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..sendDelay = const Duration(milliseconds: 80);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    final controller = container.read(
      chatControllerProvider(conversation).notifier,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    Message? optimistic;
    final send = controller.sendMessage(
      'in flight',
      onOptimisticMessage: (message) => optimistic = message,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(optimistic, isNotNull);
    expect(optimistic!.id, startsWith('_local_'));
    expect(optimistic!.status, MessageStatus.sending);
    expect(repo.sendCallCount, 1);

    await send;
  });

  test('text is published before sendMessage yields to persistence', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..sendDelay = const Duration(milliseconds: 80);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    final controller = container.read(
      chatControllerProvider(conversation).notifier,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    Message? published;
    final send = controller.sendMessage(
      'same frame',
      onOptimisticMessage: (message) => published = message,
    );

    expect(published?.content, 'same frame');
    expect(
      container
          .read(chatControllerProvider(conversation))
          .messages
          .first
          .content,
      'same frame',
    );

    await send;
  });

  test('image preparation failure keeps a durable retryable bubble', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final conversation = activeConversation(relId);
    repo.conversationOverride = conversation;
    final controller = container.read(
      chatControllerProvider(conversation).notifier,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final raw = File(
      '${Directory.systemTemp.path}/chat_invalid_${DateTime.now().microsecondsSinceEpoch}.bin',
    );
    await raw.writeAsBytes(const [1, 2, 3, 4]);
    addTearDown(() async {
      if (await raw.exists()) await raw.delete();
    });

    Message? optimistic;
    final send = controller.sendImageMessage(
      localPath: raw.path,
      onOptimisticMessage: (message) => optimistic = message,
    );

    expect(optimistic?.status, MessageStatus.sending);
    expect(
      container.read(chatControllerProvider(conversation)).messages.single.id,
      startsWith('_local_'),
    );

    await send;
    final failed =
        container.read(chatControllerProvider(conversation)).messages.single;
    expect(failed.status, MessageStatus.failed);
    expect(failed.localMediaPath, raw.path);
    expect(repo.sendCallCount, 0);

    final outbox = await container
        .read(chatCacheServiceProvider)
        .readOutbox(userId, relationshipId: relId);
    expect(outbox, hasLength(1));
    expect(outbox.single.requiresPreparation, isTrue);
    expect(outbox.single.state, PendingSendState.failedPermanent);

    await controller.removeFailedMessage(failed);
    expect(await raw.exists(), isTrue);
  });

  test('equal relationship ids reuse the same chat controller', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final first = activeConversation(relId);
    final refreshed = first.copyWith(name: 'Refreshed metadata');
    repo.conversationOverride = refreshed;

    final firstController = container.read(
      chatControllerProvider(first).notifier,
    );
    final refreshedController = container.read(
      chatControllerProvider(refreshed).notifier,
    );

    expect(identical(firstController, refreshedController), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

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

  test(
    'realtime reconciliation does not move an acknowledged local bubble',
    () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..sendCreatedAtOffset = const Duration(minutes: -10);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      repo.seedIncoming(
        id: 'partner-recent',
        relationshipId: relId,
        senderId: 'partner',
        content: 'partner row',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await controller.sendMessage('my row');
      expect(
        container.read(chatControllerProvider(convo)).messages.first.content,
        'my row',
      );

      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(
        container.read(chatControllerProvider(convo)).messages.first.content,
        'my row',
      );
    },
  );

  test(
    'warm cache survives controller recreation and paints before network',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;

      // First controller fetches once and commits a real encrypted cache row.
      repo.seedIncoming(
        id: 'm-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'cached history',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final first = buildChatContainer(repository: repo, userId: userId);
      final sharedCache = first.read(chatCacheServiceProvider);
      first.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(first.read(chatControllerProvider(convo)).messages, isNotEmpty);
      first.dispose();

      // A genuinely new provider container must restore that cache while its
      // live fetch is still blocked. Reusing the first controller would not
      // exercise disk/cache hydration at all.
      repo.getMessagesGate = Completer<void>();
      final reopened = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: sharedCache,
      );
      addTearDown(reopened.dispose);
      addTearDown(() {
        final gate = repo.getMessagesGate;
        if (gate != null && !gate.isCompleted) gate.complete();
      });
      reopened.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = reopened.read(chatControllerProvider(convo));
      expect(state.messages.single.content, 'cached history');
      expect(state.isLoading, isFalse);
      expect(repo.getMessagesGate!.isCompleted, isFalse);
    },
  );
}
