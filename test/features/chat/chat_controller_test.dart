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

  group('message actions', () {
    test('deleteMessage removes the message content from state optimistically',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('to be deleted');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sent = b.state.messages.single;

      await b.controller.deleteMessage(sent);

      final updated = b.state.messages.firstWhere((m) => m.id == sent.id);
      expect(updated.isDeleted, isTrue);
      expect(repo.deleteMessageCalls, contains(sent.id));
    });

    test('editMessage updates content and sets editedAt', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('original');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sent = b.state.messages.single;

      await b.controller.editMessage(sent, 'edited content');

      final updated = b.state.messages.firstWhere((m) => m.id == sent.id);
      expect(updated.content, 'edited content');
      expect(updated.editedAt, isNotNull);
    });

    test('starMessage and unstarMessage toggle starredMessageIds', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('star me');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sent = b.state.messages.single;

      await b.controller.starMessage(sent.id);
      expect(b.state.starredMessageIds, contains(sent.id));

      await b.controller.unstarMessage(sent.id);
      expect(b.state.starredMessageIds, isNot(contains(sent.id)));
    });

    test(
        'a message starred in a prior session is seeded as starred on chat open',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final priorStar = repo.seedIncoming(
        id: 'msg-prior-star',
        relationshipId: relId,
        senderId: userId,
        content: 'starred last session',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      // Simulate a star recorded in a previous session, before this
      // controller (and its in-memory starredMessageIds) ever existed.
      repo.starredMessageIds.add(priorStar.id);

      final b = await boot(repo);

      expect(b.state.starredMessageIds, contains(priorStar.id));
    });

    test('pinMessage and unpinMessage update pinnedMessages from the server',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendMessage('pin me');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sent = b.state.messages.single;

      await b.controller.pinMessage(sent);
      expect(b.state.pinnedMessages.map((m) => m.id), contains(sent.id));

      await b.controller.unpinMessage(sent);
      expect(b.state.pinnedMessages.map((m) => m.id), isNot(contains(sent.id)));
    });
  });

  group('reactions', () {
    test('reactToMessage patches the message in state with the new reaction', () async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final conversation = activeConversation('rel-1');
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final notifier = container.read(chatControllerProvider(conversation).notifier);
      // Let _init() (cache read, refresh, load, subscribe) settle before the
      // test's own loadMessages() call, same as boot() above.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.loadMessages();

      final message = container.read(chatControllerProvider(conversation)).messages.first;
      await notifier.reactToMessage(message, '❤️');

      final updated = container.read(chatControllerProvider(conversation)).messages.first;
      expect(updated.reactions['❤️'], contains('user-a'));
    });

    test('removeReactionFrom clears the caller\'s reaction from state', () async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final conversation = activeConversation('rel-1');
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final notifier = container.read(chatControllerProvider(conversation).notifier);
      // Let _init() (cache read, refresh, load, subscribe) settle before the
      // test's own loadMessages() call, same as boot() above.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.loadMessages();

      final message = container.read(chatControllerProvider(conversation)).messages.first;
      await notifier.reactToMessage(message, '👍');
      final reacted = container.read(chatControllerProvider(conversation)).messages.first;
      await notifier.removeReactionFrom(reacted);

      final cleared = container.read(chatControllerProvider(conversation)).messages.first;
      expect(cleared.reactions['👍'] ?? {}, isNot(contains('user-a')));
    });

    test('switching to a different emoji removes the caller from the old bucket, not just adds to the new one', () async {
      // Regression guard: the one-reaction-per-person invariant (enforced
      // server-side by message_reactions' PRIMARY KEY (message_id, user_id))
      // requires _withReaction to clear every OTHER bucket for this user
      // before adding to the new one. A regression that only added to the
      // new bucket (skipping the _withoutReaction step) would leave the
      // caller as a phantom reactor under BOTH emoji simultaneously — this
      // test fails red against that exact shape.
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final conversation = activeConversation('rel-1');
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final notifier = container.read(chatControllerProvider(conversation).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.loadMessages();

      final message = container.read(chatControllerProvider(conversation)).messages.first;
      await notifier.reactToMessage(message, '❤️');
      final firstReaction = container.read(chatControllerProvider(conversation)).messages.first;
      await notifier.reactToMessage(firstReaction, '👍');

      final switched = container.read(chatControllerProvider(conversation)).messages.first;
      expect(switched.reactions['❤️'] ?? {}, isNot(contains('user-a')));
      expect(switched.reactions['👍'], contains('user-a'));
    });

    test('a reload re-applies server reactions over a stale reaction-less copy already in state', () async {
      // Regression guard for the "reactions vanish after an app restart" bug.
      // On cold start _init() seeds state from the on-disk cache (written
      // before the reaction existed, so reactions is empty) and THEN calls
      // loadMessages(), whose server rows do carry the reaction. If
      // _mergeMessages lets the pre-existing state entry win the id collision,
      // the freshly-hydrated reaction is discarded — and the stripped result
      // is written straight back to the cache, so the loss re-persists on
      // every subsequent launch.
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final conversation = activeConversation('rel-1');
      repo.conversationOverride = conversation;
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final notifier = container.read(chatControllerProvider(conversation).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.loadMessages();

      // The reaction exists server-side (as it would after a previous session
      // wrote it), but the copy sitting in state has no reactions on it —
      // exactly the shape a restore-from-cache produces.
      await repo.addReaction(
        relationshipId: 'rel-1',
        messageId: 'm1',
        emoji: '❤️',
      );

      await notifier.loadMessages();

      final reloaded = container.read(chatControllerProvider(conversation)).messages
          .firstWhere((m) => m.id == 'm1');
      expect(reloaded.reactions['❤️'], contains('user-a'));
    });
  });
}
