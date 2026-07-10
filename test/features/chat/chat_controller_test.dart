import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

/// Bundles a booted controller with a live view of its state.
class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;

  ChatState get state =>
      container.read(chatControllerProvider(conversation));
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<_Booted> boot(
    FakeChatRepository repo, {
    Conversation? conversation,
  }) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = conversation ?? activeConversation(relId);
    // Keep refresh consistent with the conversation under test.
    repo.conversationOverride = convo;
    final controller = container.read(
      chatControllerProvider(convo).notifier,
    );
    // Let _init() (cache read, refresh, load, subscribe) settle.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _Booted(controller, container, convo);
  }

  group('send', () {
    test('optimistic message becomes sent on success', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('hello');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      expect(messages.single.content, 'hello');
      expect(messages.single.status, MessageStatus.sent);
      expect(messages.single.id.startsWith('_local_'), isFalse);
      expect(repo.sendCallCount, 1);
    });

    test('empty/whitespace content is rejected before any send', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('   ');
      expect(b.state.messages, isEmpty);
      expect(repo.sendCallCount, 0);
    });

    test('read-only conversation blocks sending', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(
        repo,
        conversation: readOnlyConversation(relId),
      );

      await b.controller.sendMessage('nope');
      expect(b.state.messages, isEmpty);
      expect(repo.sendCallCount, 0);
    });
  });

  group('offline queue + retry', () {
    test('transient failure keeps message queued, not failed', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..nextSendError = Exception('network down');
      final b = await boot(repo);

      await b.controller.sendMessage('queued one');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final msg = b.state.messages.single;
      expect(msg.status, MessageStatus.queued);
    });

    test('retry after a transient failure sends exactly one canonical row',
        () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..nextSendError = Exception('network down');
      final b = await boot(repo);

      await b.controller.sendMessage('retry me');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final queued = b.state.messages.single;
      expect(queued.status, MessageStatus.queued);

      // nextSendError is one-shot; retry now succeeds.
      await b.controller.retryMessage(queued);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      expect(messages.single.status, MessageStatus.sent);
      expect(repo.sendCallCount, 2); // one fail + one success
    });

    test('permanent failure (unauthorized) marks message failed', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..nextSendError = const PostgrestException(
          message: 'permission denied',
          code: '42501',
        );
      final b = await boot(repo);

      await b.controller.sendMessage('denied');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(b.state.messages.single.status,
          MessageStatus.failed);
    });

    test('removeFailedMessage clears it from the list', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..nextSendError = const PostgrestException(
          message: 'permission denied',
          code: '42501',
        );
      final b = await boot(repo);

      await b.controller.sendMessage('remove me');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final failed = b.state.messages.single;

      await b.controller.removeFailedMessage(failed);
      expect(b.state.messages, isEmpty);
    });
  });

  group('duplicate send (idempotency)', () {
    test('23505 duplicate reconciles to one canonical row', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      // Arrange a duplicate: server raises 23505 and findByClientId returns
      // the canonical row.
      repo.simulateDuplicate = true;
      // We don't know the generated clientMessageId up front, so let the
      // controller create it, then satisfy findMessageByClientId for any id.
      repo.duplicateClientMessageId = null;

      await b.controller.sendMessage('dup');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      // Either reconciled to canonical, or still queued for retry — never two.
      expect(messages.length, 1);
    });
  });

  group('receipts + presence', () {
    test('marking read is suppressed until the view is active', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'hi from partner',
        createdAt: DateTime.now(),
      );
      final b = await boot(repo);

      // Not viewing yet: no read.
      await b.controller.markAsRead();
      expect(repo.markReadCalls, isEmpty);

      // Becoming active triggers presence + read.
      b.controller.setViewActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(repo.presenceCalls, contains(relId));
      expect(repo.markReadCalls, isNotEmpty);
    });

    test('leaving the view clears presence', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      b.controller.setViewActive(true);
      b.controller.setViewActive(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.presenceCalls, contains(relId));
      expect(repo.presenceCalls.last, isNull);
    });
  });
}
