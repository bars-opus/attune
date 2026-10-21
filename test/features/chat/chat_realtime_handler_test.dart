import 'dart:async';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  ChatState get state => container.read(chatControllerProvider(conversation));
}

Conversation _convo(String id, {int unread = 0}) => Conversation(
  id: id,
  relationshipId: id,
  partnerId: 'partner',
  name: 'Partner',
  updatedAt: DateTime.now(),
  relationshipStatus: 'active',
  availability: ConversationAvailability.active,
  unreadCount: unread,
);

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<_Booted> boot(FakeChatRepository repo) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo);
  }

  void partnerSends(FakeChatRepository repo, String id, String content) {
    repo.seedIncoming(
      id: id,
      relationshipId: relId,
      senderId: 'partner',
      content: content,
      createdAt: DateTime.now(),
    );
  }

  group('per-chat handler', () {
    test('a new message renders even when the header refresh throws', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      repo.getConversationError = Exception('metadata unreachable');

      partnerSends(repo, 'inc-1', 'are you there?');
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageInsert,
          messageId: 'inc-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.map((m) => m.id), contains('inc-1'));
    });

    test(
      'an insert frame costs one forward fetch and no header or list work',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-0', 'earlier');
        final b = await boot(repo);
        final conversationCalls = repo.getConversationCalls;
        final pageCalls = repo.getMessagesCalls;
        final forwardCalls = repo.getMessagesAfterCalls;
        final bumps = b.container.read(conversationsRefreshProvider);

        partnerSends(repo, 'inc-1', 'new');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageInsert,
            messageId: 'inc-1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(b.state.messages.first.id, 'inc-1');
        expect(repo.getMessagesAfterCalls, forwardCalls + 1);
        expect(
          repo.getMessagesCalls,
          pageCalls,
          reason: 'no first-page refetch for an insert',
        );
        expect(
          repo.getConversationCalls,
          conversationCalls,
          reason: 'no header refetch for an insert',
        );
        expect(
          b.container.read(conversationsRefreshProvider),
          bumps,
          reason: 'the handler must not rebuild the conversations list',
        );
      },
    );

    test(
      'frames inside one debounce window are processed as one batch',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-0', 'earlier');
        final b = await boot(repo);
        final forwardCalls = repo.getMessagesAfterCalls;

        for (var i = 1; i <= 5; i++) {
          partnerSends(repo, 'inc-$i', 'burst $i');
          repo.emitRealtime(
            ChatRealtimeEvent(
              ChatRealtimeKind.messageInsert,
              messageId: 'inc-$i',
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(
          b.state.messages.where((m) => m.content.startsWith('burst')),
          hasLength(5),
        );
        expect(repo.getMessagesAfterCalls, forwardCalls + 1);
      },
    );

    test(
      'an update frame refreshes exactly the named row, wherever it is',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'original');
        final b = await boot(repo);

        await repo.editMessage(messageId: 'inc-1', newContent: 'edited');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageUpdate,
            messageId: 'inc-1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(b.state.messages.single.content, 'edited');
        expect(repo.getMessagesByIdsCalls, 1);
      },
    );

    test(
      'a reaction frame (add or remove) refreshes the message it names (#8)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'react to me');
        final b = await boot(repo);

        await repo.addReaction(
          relationshipId: relId,
          messageId: 'inc-1',
          emoji: '❤️',
        );
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.reaction,
            messageId: 'inc-1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(b.state.messages.single.reactions['❤️'], contains(userId));

        await repo.removeReaction('inc-1');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.reaction,
            messageId: 'inc-1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(b.state.messages.single.reactions, isEmpty);
      },
    );

    test(
      'a pin frame refreshes the pinned banner (#8 unpin arrives live)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'pin me');
        final b = await boot(repo);
        repo.pinnedMessageIds.add('inc-1');
        repo.emitRealtime(
          const ChatRealtimeEvent(ChatRealtimeKind.pin, messageId: 'inc-1'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(b.state.pinnedMessages.map((m) => m.id), ['inc-1']);

        repo.pinnedMessageIds.remove('inc-1');
        repo.emitRealtime(
          const ChatRealtimeEvent(ChatRealtimeKind.pin, messageId: 'inc-1'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(b.state.pinnedMessages, isEmpty);
      },
    );

    test(
      'a resync frame refreshes page, header and pins, and flushes the outbox (#1)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-0', 'earlier');
        final b = await boot(repo);
        repo.sendErrorQueue.add(Exception('network down'));
        await b.controller.sendMessage('typed offline');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          b.state.messages
              .firstWhere((m) => m.content == 'typed offline')
              .status
              .name,
          'queued',
        );
        final conversationCalls = repo.getConversationCalls;
        final pageCalls = repo.getMessagesCalls;
        final pinCalls = repo.getPinnedCalls;

        repo.emitRealtime();
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(repo.getConversationCalls, conversationCalls + 1);
        expect(repo.getMessagesCalls, pageCalls + 1);
        expect(repo.getPinnedCalls, pinCalls + 1);
        expect(
          b.state.messages
              .firstWhere((m) => m.content == 'typed offline')
              .status
              .name,
          'sent',
          reason: 'a (re)subscribe is the moment the network is back',
        );
      },
    );

    test('one failing step does not skip the others', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      repo.getPinnedError = Exception('pins down');
      partnerSends(repo, 'inc-1', 'undelivered');
      final deliveredBefore = repo.markDeliveredCalls.length;

      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(b.state.messages.map((m) => m.id), contains('inc-1'));
      expect(repo.markDeliveredCalls.length, greaterThan(deliveredBefore));
    });

    test(
      'frames that arrive mid-batch are processed by exactly one follow-up batch',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-0', 'earlier');
        final b = await boot(repo);
        final forwardCalls = repo.getMessagesAfterCalls;

        // Hold the resync batch at its first-page step so frames can land
        // while it is genuinely running.
        final gate = Completer<void>();
        repo.getMessagesGate = gate;
        repo.emitRealtime();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          repo.getMessagesAfterCalls,
          forwardCalls + 1,
          reason: 'the batch is running',
        );

        for (var i = 1; i <= 3; i++) {
          partnerSends(repo, 'inc-$i', 'late $i');
          repo.emitRealtime(
            ChatRealtimeEvent(
              ChatRealtimeKind.messageInsert,
              messageId: 'inc-$i',
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          repo.getMessagesAfterCalls,
          forwardCalls + 1,
          reason: 'nothing may run concurrently with the open batch',
        );

        repo.getMessagesGate = null;
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          b.state.messages.where((m) => m.content.startsWith('late')),
          hasLength(3),
        );
        expect(
          repo.getMessagesAfterCalls,
          forwardCalls + 2,
          reason: 'one follow-up batch for the three frames, not three',
        );
      },
    );
  });

  group('conversations list', () {
    test(
      'bumping conversationsRefreshProvider rebuilds the list without resubscribing the inbox',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [_convo('rel-1')];
        final container = buildChatContainer(repository: repo, userId: userId);
        addTearDown(container.dispose);
        await container.read(conversationsProvider.future);
        final subscriptions = repo.inboxSubscriptions.length;

        for (var i = 0; i < 3; i++) {
          container.read(conversationsRefreshProvider.notifier).state++;
          await container.read(conversationsProvider.future);
        }

        expect(
          repo.inboxSubscriptions.length,
          subscriptions,
          reason: 'each rebuild used to tear down and rejoin the inbox channel',
        );
      },
    );

    test('a burst of inbox events is one refetch', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [_convo('rel-1')];
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      await container.read(conversationsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final calls = repo.getConversationsCalls;

      repo.conversations = [_convo('rel-1', unread: 5)];
      for (var i = 0; i < 5; i++) {
        repo.inboxEvents.add(null);
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(repo.getConversationsCalls, calls + 1);
      expect(
        container.read(conversationsProvider).value?.single.unreadCount,
        5,
      );
    });

    test('refreshQuietly refetches in place without a loading state', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [_convo('rel-1', unread: 2)];
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      await container.read(conversationsProvider.future);
      final states = <bool>[];
      container.listen(
        conversationsProvider,
        (_, next) => states.add(next.isLoading),
      );

      repo.conversations = [_convo('rel-1', unread: 0)];
      await container.read(conversationsProvider.notifier).refreshQuietly();

      expect(states.contains(true), isFalse);
      expect(
        container.read(conversationsProvider).value?.single.unreadCount,
        0,
      );
    });
  });

  group('purge guards (account change mid-batch)', () {
    /// Boots over a cache whose purge a test can hold: the account change
    /// bumps the purge epoch, then its first step (reading the queue) waits,
    /// so the old controller is still MOUNTED, with the new account signed
    /// in, when a late answer lands. Only the epoch guard can stop it then
    /// (since final-review M6 the controller is replaced once the purge
    /// ends, and a disposed one is stopped by `mounted` alone).
    Future<
      ({
        _Booted b,
        StateProvider<User?> userSwitch,
        ScriptedCacheBackend backend,
        ChatCacheService cache,
      })
    >
    bootHeldPurge(FakeChatRepository repo) async {
      final backend = ScriptedCacheBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      final userSwitch = StateProvider<User?>((ref) => testUser(userId));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        userSwitch: userSwitch,
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return (
        b: _Booted(controller, container, convo),
        userSwitch: userSwitch,
        backend: backend,
        cache: cache,
      );
    }

    PendingSend queuedFor(String sender) => PendingSend(
      clientMessageId: 'cid-$sender',
      relationshipId: relId,
      senderId: sender,
      text: 'queued',
      createdAt: DateTime.now(),
      nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
      state: PendingSendState.queued,
    );

    test(
      'a header refresh in flight across an account change writes nothing back',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootHeldPurge(repo);
        // The new account has a message waiting in this relationship.
        await s.cache.putOutbox('user-b', queuedFor('user-b'));
        final gate = Completer<void>();
        repo.getConversationGate = gate;
        // The late response says read-only: applying it would un-archive the
        // conversation the account change just closed and run the queue-close
        // path for the NEW account.
        repo.conversationOverride = readOnlyConversation(relId);
        repo.emitRealtime(
          const ChatRealtimeEvent(ChatRealtimeKind.relationship),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        final purge = Completer<void>();
        s.backend.readOutboxGate = purge;
        final writes = <ChatState>[];
        s.b.controller.addListener(writes.add, fireImmediately: false);
        s.b.container.read(s.userSwitch.notifier).state = testUser('user-b');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(s.b.controller.mounted, isTrue, reason: 'purge held');

        repo.getConversationGate = null;
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(writes, isEmpty, reason: 'the late answer wrote nothing back');
        expect(
          (await s.cache.readOutbox('user-b', relationshipId: relId))
              .single
              .state,
          PendingSendState.queued,
          reason: 'the queue-close path never ran for the new account',
        );

        purge.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          writes.last.error,
          'This conversation is no longer available for this account.',
        );
      },
    );

    test(
      'a pins refresh in flight across an account change writes nothing back',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'pin me');
        final s = await bootHeldPurge(repo);
        final gate = Completer<void>();
        repo.getPinnedGate = gate;
        repo.pinnedMessageIds.add('inc-1');
        repo.emitRealtime(
          const ChatRealtimeEvent(ChatRealtimeKind.pin, messageId: 'inc-1'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        final purge = Completer<void>();
        s.backend.readOutboxGate = purge;
        final writes = <ChatState>[];
        s.b.controller.addListener(writes.add, fireImmediately: false);
        s.b.container.read(s.userSwitch.notifier).state = testUser('user-b');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(s.b.controller.mounted, isTrue, reason: 'purge held');

        repo.getPinnedGate = null;
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(writes, isEmpty, reason: 'the late pins wrote nothing back');
        expect(s.b.controller.state.pinnedMessages, isEmpty);

        purge.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
    );
  });

  group('first-page loads', () {
    test('an older first-page response landing late cannot restore a row a '
        'newer one dropped', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'kept');
      partnerSends(repo, 'inc-2', 'deleted on the server');
      final b = await boot(repo);
      expect(
        b.state.messages.map((m) => m.id),
        containsAll(['inc-1', 'inc-2']),
      );

      // Load A: the server builds its page (both rows), then the response is
      // slow to arrive.
      final slow = Completer<void>();
      repo.getMessagesResponseGate = slow;
      final a = b.controller.loadMessages(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The row is deleted; load B (e.g. a resume refresh) sees it gone.
      repo.getMessagesResponseGate = null;
      repo.serverMessages.remove('inc-2');
      final newer = b.controller.loadMessages(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      slow.complete();
      await a;
      await newer;

      expect(b.state.messages.map((m) => m.id), ['inc-1']);
    });
  });

  group('fix round 1', () {
    /// Boots a controller. [waiting] is put in the outbox BEFORE boot with
    /// a deadline an hour out, so only a forced flush can send it — the
    /// retry timer cannot, inside a test's lifetime.
    Future<({_Booted b, StateProvider<User?> userSwitch})> bootFull(
      FakeChatRepository repo, {
      Duration? networkTimeout,
      int? pageSize,
      String? waiting,
    }) async {
      final userSwitch = StateProvider<User?>((ref) => testUser(userId));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        userSwitch: userSwitch,
        extraOverrides: [
          if (networkTimeout != null || pageSize != null)
            chatConfigProvider.overrideWithValue(
              ChatConfig(
                networkTimeout:
                    networkTimeout ?? const ChatConfig().networkTimeout,
                messagePageSize: pageSize ?? const ChatConfig().messagePageSize,
              ),
            ),
        ],
      );
      addTearDown(container.dispose);
      if (waiting != null) {
        await container
            .read(chatCacheServiceProvider)
            .putOutbox(
              userId,
              PendingSend(
                clientMessageId: 'cid-waiting',
                relationshipId: relId,
                senderId: userId,
                text: waiting,
                createdAt: DateTime.now(),
                attempts: 3,
                nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
                state: PendingSendState.queued,
              ),
            );
      }
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return (b: _Booted(controller, container, convo), userSwitch: userSwitch);
    }

    String statusOf(_Booted b, String content) =>
        b.state.messages.firstWhere((m) => m.content == content).status.name;

    test('I1: a request that never answers cannot stall realtime — the next '
        'batch runs and a waiting message sends', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-0', 'earlier');
      final s = await bootFull(
        repo,
        networkTimeout: const Duration(milliseconds: 200),
        waiting: 'waited',
      );
      expect(statusOf(s.b, 'waited'), 'queued');
      expect(repo.sendCallCount, 0);

      // The forward read is black-holed: it never answers.
      repo.getMessagesAfterGate = Completer<void>();
      partnerSends(repo, 'inc-1', 'stuck behind a hung read');
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageInsert,
          messageId: 'inc-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      repo.getMessagesAfterGate = null;
      final conversationCalls = repo.getConversationCalls;
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(repo.getConversationCalls, conversationCalls + 1);
      expect(s.b.state.messages.map((m) => m.id), contains('inc-1'));
      expect(statusOf(s.b, 'waited'), 'sent');
    });

    test('I1: a hung first-page load cannot block the next one', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'earlier');
      final s = await bootFull(
        repo,
        networkTimeout: const Duration(milliseconds: 200),
      );

      repo.getMessagesGate = Completer<void>(); // never answers
      final hung = s.b.controller.loadMessages(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      repo.getMessagesGate = null;
      partnerSends(repo, 'inc-2', 'arrived meanwhile');

      // e.g. the person taps Retry.
      await s.b.controller
          .loadMessages(silent: true)
          .timeout(const Duration(seconds: 2));
      await hung;

      expect(s.b.state.messages.map((m) => m.id), contains('inc-2'));
    });

    test('I2a: a header step that throws does not skip pins, delivered or '
        'the resync flush', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'undelivered');
      final s = await bootFull(repo, waiting: 'waited');
      repo.getConversationError = Exception('metadata unreachable');
      final pins = repo.getPinnedCalls;
      final delivered = repo.markDeliveredCalls.length;

      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(repo.getPinnedCalls, pins + 1);
      expect(repo.markDeliveredCalls.length, greaterThan(delivered));
      expect(statusOf(s.b, 'waited'), 'sent');
    });

    test('I2b: a by-id refresh that throws does not skip delivered', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'undelivered');
      final s = await bootFull(repo);
      repo.getMessagesByIdsError = Exception('by-id read failed');
      final delivered = repo.markDeliveredCalls.length;

      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageUpdate,
          messageId: 'inc-1',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(repo.getMessagesByIdsCalls, 1);
      expect(repo.markDeliveredCalls.length, greaterThan(delivered));
      expect(s.b.state.messages.map((m) => m.id), contains('inc-1'));
    });

    test('M4: delivered marking and the flush are skipped once a purge lands '
        'mid-batch', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      partnerSends(repo, 'inc-1', 'undelivered');
      final s = await bootFull(repo, waiting: 'waited');
      final gate = Completer<void>();
      repo.getConversationGate = gate;
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));

      s.b.container.read(s.userSwitch.notifier).state = testUser('user-b');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final delivered = repo.markDeliveredCalls.length;
      final sends = repo.sendCallCount;
      repo.getConversationGate = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repo.markDeliveredCalls.length, delivered);
      expect(repo.sendCallCount, sends);
    });

    test(
      'C1: a delete frame removes the row the server no longer returns',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'kept');
        partnerSends(repo, 'inc-2', 'deleted');
        final s = await bootFull(repo);
        expect(
          s.b.state.messages.map((m) => m.id),
          containsAll(['inc-1', 'inc-2']),
        );

        repo.serverMessages.remove('inc-2');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageDelete,
            messageId: 'inc-2',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(s.b.state.messages.map((m) => m.id), ['inc-1']);
        expect(repo.getMessagesByIdsCalls, 1);
      },
    );

    group('fix round 2', () {
      test('R2-1: a changed-since read of several slow pages, each within the '
          'bound, still lands', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final t0 = DateTime.now().subtract(const Duration(hours: 1));
        String id(int i) => 'm-${i.toString().padLeft(2, '0')}';
        for (var i = 1; i <= 20; i++) {
          repo.seedIncoming(
            id: id(i),
            relationshipId: relId,
            senderId: 'partner',
            content: 'row $i',
            createdAt: t0.add(Duration(minutes: i)),
          );
        }
        final s = await bootFull(
          repo,
          networkTimeout: const Duration(milliseconds: 200),
          pageSize: 5,
        );
        final now = DateTime.now();
        for (var i = 1; i <= 20; i++) {
          await repo.editMessage(messageId: id(i), newContent: 'edited $i');
          repo.touch(id(i), now.add(Duration(milliseconds: i)));
        }
        // 20 changes = four full pages of five, 80 ms each: 320 ms for the
        // one call, every page well inside the 200 ms bound.
        repo.changedSincePageDelay = const Duration(milliseconds: 80);

        await s.b.controller.syncChangesSinceCursor();

        expect(
          s.b.state.messages.firstWhere((m) => m.id == id(20)).content,
          'edited 20',
        );
      });

      test('R2-2: ids whose by-id refresh failed are retried', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'original');
        final s = await bootFull(repo);
        repo.getMessagesByIdsError = Exception('by-id read failed');

        await repo.editMessage(messageId: 'inc-1', newContent: 'edited');
        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageUpdate,
            messageId: 'inc-1',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(s.b.state.messages.single.content, 'original');

        repo.getMessagesByIdsError = null;
        await Future<void>.delayed(const Duration(milliseconds: 1300));
        expect(s.b.state.messages.single.content, 'edited');
      });

      testWidgets('R2-2: the retry is bounded', (tester) async {
        final repo = FakeChatRepository(currentUserId: userId);
        partnerSends(repo, 'inc-1', 'original');
        final container = buildChatContainer(repository: repo, userId: userId);
        final convo = activeConversation(relId);
        repo.conversationOverride = convo;
        container.read(chatControllerProvider(convo).notifier);
        await tester.pump(const Duration(milliseconds: 30));
        repo.getMessagesByIdsError = Exception('by-id read failed');

        repo.emitRealtime(
          const ChatRealtimeEvent(
            ChatRealtimeKind.messageUpdate,
            messageId: 'inc-1',
          ),
        );
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        final calls = repo.getMessagesByIdsCalls;
        expect(calls, greaterThan(1), reason: 'it retried');
        expect(calls, lessThanOrEqualTo(6), reason: 'one try + five retries');
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(repo.getMessagesByIdsCalls, calls, reason: 'then it stops');
        container.dispose();
      });

      testWidgets('R2-3: a steady stream of inbox frames cannot postpone the '
          'list refresh past the max wait', (tester) async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [_convo('rel-1')];
        final container = buildChatContainer(repository: repo, userId: userId);
        await container.read(conversationsProvider.future);
        await tester.pump(const Duration(milliseconds: 20));
        final before = repo.getConversationsCalls;

        // A frame every 200 ms, always inside the 300 ms window.
        for (var i = 0; i < 6; i++) {
          repo.inboxEvents.add(null);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(
          repo.getConversationsCalls,
          before + 1,
          reason: 'refreshed by the max wait, mid-stream',
        );

        await tester.pump(const Duration(milliseconds: 400));
        container.dispose();
      });
    });

    group('conversations list', () {
      test('M1: a refresh requested for the new account after a switch is not '
          'dropped as the old account\'s', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [_convo('rel-1')];
        final userSwitch = StateProvider<User?>((ref) => testUser(userId));
        final container = buildChatContainer(
          repository: repo,
          userId: userId,
          userSwitch: userSwitch,
        );
        addTearDown(container.dispose);
        await container.read(conversationsProvider.future);
        final notifier = container.read(conversationsProvider.notifier);

        final g1 = Completer<void>();
        final g2 = Completer<void>();
        repo.getConversationsGates.addAll([g1, g2]);
        final forA = notifier.refreshQuietly(); // A's fetch, in flight
        await Future<void>.delayed(const Duration(milliseconds: 10));

        container.read(userSwitch.notifier).state = testUser('user-b');
        final builtForB = container.read(conversationsProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final forB = notifier.refreshQuietly(); // coalesced behind A's
        g2.complete();
        await builtForB;

        repo.conversations = [_convo('rel-1', unread: 4)];
        g1.complete();
        await forA;
        await forB;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(conversationsProvider).value?.single.unreadCount,
          4,
        );
      });

      test('M2: an awaited refreshQuietly waits for data fetched after it was '
          'asked', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [_convo('rel-1', unread: 2)];
        final container = buildChatContainer(repository: repo, userId: userId);
        addTearDown(container.dispose);
        await container.read(conversationsProvider.future);
        final notifier = container.read(conversationsProvider.notifier);

        final gate = Completer<void>();
        repo.getConversationsGates.add(gate);
        final first = notifier.refreshQuietly();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        repo.conversations = [_convo('rel-1', unread: 7)];
        final calls = repo.getConversationsCalls;

        var secondDone = false;
        final second = notifier.refreshQuietly().then((_) => secondDone = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(secondDone, isFalse, reason: 'must wait for fresh data');

        gate.complete();
        await first;
        await second;
        expect(repo.getConversationsCalls, calls + 1, reason: 'one re-run');
        expect(
          container.read(conversationsProvider).value?.single.unreadCount,
          7,
        );
      });

      test(
        'M3: a read and the receipt UPDATE it causes are one list fetch',
        () async {
          final repo = FakeChatRepository(currentUserId: userId);
          repo.conversations = [_convo(relId, unread: 1)];
          partnerSends(repo, 'inc-1', 'hi');
          final s = await bootFull(repo);
          await s.b.container.read(conversationsProvider.future);
          await Future<void>.delayed(const Duration(milliseconds: 20));
          final before = repo.getConversationsCalls;

          s.b.controller.setViewActive(true);
          await s.b.controller.markAsRead();
          // Receipts on: the read stamps the rows, and that UPDATE streams to
          // the inbox channel.
          repo.inboxEvents.add(null);
          await Future<void>.delayed(const Duration(milliseconds: 450));

          expect(repo.markReadCalls, hasLength(1));
          expect(repo.getConversationsCalls, before + 1);
        },
      );

      test('M5: a fetch failure that falls back to the cache still subscribes '
          'the inbox', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final container = buildChatContainer(repository: repo, userId: userId);
        addTearDown(container.dispose);
        await container.read(chatCacheServiceProvider).writeConversations(
          userId,
          [_convo('rel-1', unread: 1)],
        );
        ConversationsNotifier.debugServedCache = true; // force the fetch path
        repo.getConversationsError = Exception('offline');

        final list = await container.read(conversationsProvider.future);

        expect(list.single.relationshipId, 'rel-1');
        expect(repo.inboxSubscriptions, [
          ['rel-1'],
        ]);
      });

      test('M5: an inbox frame between a dispose callback and the rebuild does '
          'not drop the subscription', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [_convo('rel-1')];
        final container = buildChatContainer(repository: repo, userId: userId);
        addTearDown(container.dispose);
        await container.read(conversationsProvider.future);
        final subscriptions = repo.inboxSubscriptions.length;

        // Nobody listens, so the bump only marks the list dirty; the frame
        // lands before anything rebuilds it.
        container.read(conversationsRefreshProvider.notifier).state++;
        repo.inboxEvents.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await container.read(conversationsProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(repo.inboxSubscriptions.length, subscriptions);
      });
    });
  });
}
