import 'dart:async';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
// fake_async ships with flutter_test (same pattern as
// signed_media_url_retry_test.dart).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
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

  ChatState get state => container.read(chatControllerProvider(conversation));
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  test('initial state stays loading until the first history load resolves', () {
    final state = ChatState.initial(activeConversation(relId));

    expect(state.messages, isEmpty);
    expect(state.isLoading, isTrue);
  });

  Future<_Booted> boot(
    FakeChatRepository repo, {
    Conversation? conversation,
    ChatConfig? config,
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      extraOverrides: [
        if (config != null) chatConfigProvider.overrideWithValue(config),
      ],
    );
    addTearDown(container.dispose);
    final convo = conversation ?? activeConversation(relId);
    // Keep refresh consistent with the conversation under test.
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    // Let _init() (cache read, refresh, load, subscribe) settle.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _Booted(controller, container, convo);
  }

  group('chat identity refresh', () {
    test(
      'bumping conversationsRefreshProvider re-reads the conversation, so a '
      'name/photo edit made elsewhere shows without leaving the screen',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final b = await boot(repo);

        expect(b.state.conversation.name, 'Partner');
        expect(b.state.conversation.avatarUrl, isNull);

        // Simulates the identity sheet on PulseTab writing a new name/photo
        // and signalling it the only way it can — this counter. Without the
        // controller listening, state.conversation (what the chat header
        // renders) would keep the value captured at _init until the screen
        // was left and re-entered.
        repo.conversationOverride = b.conversation.copyWith(
          name: 'Japerl34',
          avatarUrl: 'relationship-avatars/rel-1/new.jpg',
        );
        b.container.read(conversationsRefreshProvider.notifier).state++;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(b.state.conversation.name, 'Japerl34');
        expect(
          b.state.conversation.avatarUrl,
          'relationship-avatars/rel-1/new.jpg',
        );
      },
    );
  });

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
      final b = await boot(repo, conversation: readOnlyConversation(relId));

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

    test(
      'retry after a transient failure sends exactly one canonical row',
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
      },
    );

    test('permanent failure (unauthorized) marks message failed', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..nextSendError = const PostgrestException(
          message: 'permission denied',
          code: '42501',
        );
      final b = await boot(repo);

      await b.controller.sendMessage('denied');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(b.state.messages.single.status, MessageStatus.failed);
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

    test('receipts off: a message already marked is not re-marked on the '
        'next sync (Spec 1a)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'hi from partner',
        createdAt: DateTime.now(),
      );
      final b = await boot(repo);

      b.controller.setViewActive(true);
      await Future<void>.delayed(const Duration(milliseconds: 550));
      expect(repo.markReadCalls, hasLength(1));

      // The fake, like the server while receipts are off, leaves readAt null
      // on the partner's message. Another visible sync must not call again.
      await b.controller.markAsRead();
      await b.controller.markAsRead();
      expect(repo.markReadCalls, hasLength(1));
    });

    test('a read refreshes the conversations list, so the unread badge clears '
        'even when receipts are off and no messages event fires (Spec 1a)',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: relId,
        senderId: 'partner',
        content: 'hi from partner',
        createdAt: DateTime.now(),
      );
      final b = await boot(repo);
      await b.container.read(conversationsProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final before = repo.getConversationsCalls;

      b.controller.setViewActive(true);
      // The read lands at 500 ms; its list refresh is coalesced over 300 ms.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(repo.markReadCalls, hasLength(1));
      expect(repo.getConversationsCalls, greaterThan(before));

      // Nothing new to mark: no call, no extra list refresh.
      final after = repo.getConversationsCalls;
      await b.controller.markAsRead();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(repo.getConversationsCalls, after);
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
    test(
      'deleteMessage removes the message content from state optimistically',
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
      },
    );

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
      },
    );

    test(
      'pinMessage and unpinMessage update pinnedMessages from the server',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final b = await boot(repo);

        await b.controller.sendMessage('pin me');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final sent = b.state.messages.single;

        await b.controller.pinMessage(sent);
        expect(b.state.pinnedMessages.map((m) => m.id), contains(sent.id));

        await b.controller.unpinMessage(sent);
        expect(
          b.state.pinnedMessages.map((m) => m.id),
          isNot(contains(sent.id)),
        );
      },
    );
  });

  group('reactions', () {
    test(
      'reactToMessage patches the message in state with the new reaction',
      () async {
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
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          chatControllerProvider(conversation).notifier,
        );
        // Let _init() (cache read, refresh, load, subscribe) settle before the
        // test's own loadMessages() call, same as boot() above.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.loadMessages();

        final message =
            container.read(chatControllerProvider(conversation)).messages.first;
        await notifier.reactToMessage(message, '❤️');

        final updated =
            container.read(chatControllerProvider(conversation)).messages.first;
        expect(updated.reactions['❤️'], contains('user-a'));
      },
    );

    test(
      'removeReactionFrom clears the caller\'s reaction from state',
      () async {
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
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          chatControllerProvider(conversation).notifier,
        );
        // Let _init() (cache read, refresh, load, subscribe) settle before the
        // test's own loadMessages() call, same as boot() above.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.loadMessages();

        final message =
            container.read(chatControllerProvider(conversation)).messages.first;
        await notifier.reactToMessage(message, '👍');
        final reacted =
            container.read(chatControllerProvider(conversation)).messages.first;
        await notifier.removeReactionFrom(reacted);

        final cleared =
            container.read(chatControllerProvider(conversation)).messages.first;
        expect(cleared.reactions['👍'] ?? {}, isNot(contains('user-a')));
      },
    );

    test(
      'switching to a different emoji removes the caller from the old bucket, not just adds to the new one',
      () async {
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
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          chatControllerProvider(conversation).notifier,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.loadMessages();

        final message =
            container.read(chatControllerProvider(conversation)).messages.first;
        await notifier.reactToMessage(message, '❤️');
        final firstReaction =
            container.read(chatControllerProvider(conversation)).messages.first;
        await notifier.reactToMessage(firstReaction, '👍');

        final switched =
            container.read(chatControllerProvider(conversation)).messages.first;
        expect(switched.reactions['❤️'] ?? {}, isNot(contains('user-a')));
        expect(switched.reactions['👍'], contains('user-a'));
      },
    );

    test(
      'a reload re-applies server reactions over a stale reaction-less copy already in state',
      () async {
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
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
        );
        addTearDown(container.dispose);
        final notifier = container.read(
          chatControllerProvider(conversation).notifier,
        );
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

        final reloaded = container
            .read(chatControllerProvider(conversation))
            .messages
            .firstWhere((m) => m.id == 'm1');
        expect(reloaded.reactions['❤️'], contains('user-a'));
      },
    );
  });

  group('ensureMessageLoaded (jump-to-message)', () {
    void seed(FakeChatRepository repo, int n) {
      final base = DateTime(2026, 7, 1);
      for (var i = 0; i < n; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: relId,
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
    }

    test('pages contiguously until the target is in state.messages', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      expect(b.state.messages.length, 5);
      final callsBefore = repo.getMessagesCalls;

      final result = await b.controller.ensureMessageLoaded('m3');

      expect(result, JumpTargetResult.loaded);
      expect(b.state.messages.any((m) => m.id == 'm3'), isTrue);
      // 35 older rows in pages of 10 → 4 pages, never one per 5.
      expect(repo.getMessagesCalls - callsBefore, 4);
      // Still contiguous: every id between the newest and the target.
      final ids = b.state.messages.map((m) => m.id).toList();
      expect(ids.first, 'm39');
      expect(ids.contains('m3'), isTrue);
      expect(ids.length, 40);
    });

    test(
      'a missing target is reported without paging the whole history',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 40);
        final b = await boot(
          repo,
          config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
        );
        final callsBefore = repo.getMessagesCalls;
        expect(
          await b.controller.ensureMessageLoaded('ghost'),
          JumpTargetResult.notFound,
        );
        expect(repo.getMessagesCalls - callsBefore, 0);
      },
    );

    test(
      'a target hidden from the pages stops once paged past its sort_at',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 40);
        // Visible by id but absent from list pages (e.g. a row the list
        // query filters). Simulate: getMessagesByIds knows it, getMessages
        // never returns it.
        repo.hiddenFromPages.add('m20');
        final b = await boot(
          repo,
          config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
        );
        final callsBefore = repo.getMessagesCalls;
        expect(
          await b.controller.ensureMessageLoaded('m20'),
          JumpTargetResult.notFound,
        );
        // Stopped as soon as the fetched span reached past m20 (page 1:
        // m34..m25; page 2: m24..m14 with m20 missing), not after paging
        // the whole history.
        expect(repo.getMessagesCalls - callsBefore, 2);
        expect(
          b.state.messages.last.sortAt.isBefore(
            repo.serverMessages['m20']!.sortAt,
          ),
          isTrue,
        );
      },
    );

    test('a page fetch that fails ends the jump instead of spinning', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      repo.getMessagesError = Exception('offline');
      final callsBefore = repo.getMessagesCalls;
      expect(
        await b.controller.ensureMessageLoaded('m3'),
        JumpTargetResult.exhausted,
      );
      expect(repo.getMessagesCalls - callsBefore, 1, reason: 'no retry storm');
    });

    test('a target lookup that never answers is bounded', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(
          messagePageSize: 5,
          jumpPageSize: 10,
          networkTimeout: Duration(milliseconds: 50),
        ),
      );
      // A black-holed by-id read: it never completes.
      final gate = repo.getMessagesByIdsGate = Completer<void>();
      addTearDown(gate.complete);
      final callsBefore = repo.getMessagesCalls;
      final result = await b.controller
          .ensureMessageLoaded('m3')
          .timeout(const Duration(seconds: 2));
      expect(result, JumpTargetResult.exhausted);
      // No blind paging without the target's position (a slow link is the
      // worst place to fetch history with no bound).
      expect(repo.getMessagesCalls - callsBefore, 0);
    });

    test('a target beyond the page cap is reported as too far back', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      final callsBefore = repo.getMessagesCalls;
      expect(
        await b.controller.ensureMessageLoaded('m3', maxPages: 2),
        JumpTargetResult.tooFarBack,
      );
      expect(repo.getMessagesCalls - callsBefore, 2);
    });

    // Both run in fake time: "A's page is in flight" is a counted fact
    // (microtasks flushed until getMessages was called), not a real sleep
    // that a loaded machine can outrun.
    _Booted bootFake(FakeAsync async, FakeChatRepository repo) {
      _Booted? booted;
      boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      ).then((b) => booted = b);
      async.elapse(const Duration(milliseconds: 50));
      expect(booted, isNotNull, reason: 'boot settles in fake time');
      expect(booted!.state.messages.length, 5);
      return booted!;
    }

    /// Flushes microtasks until [repo] has served [n] more page reads than
    /// [before]; fails instead of guessing if that never happens.
    void untilPageCalls(
      FakeAsync async,
      FakeChatRepository repo,
      int before,
      int n,
    ) {
      for (var i = 0; i < 100 && repo.getMessagesCalls - before < n; i++) {
        async.flushMicrotasks();
      }
      expect(repo.getMessagesCalls - before, n);
    }

    test('cancelJump stops the paging loop between pages', () {
      fakeAsync((async) {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 40);
        final b = bootFake(async, repo);
        final gate = repo.getMessagesResponseGate = Completer<void>();
        final callsBefore = repo.getMessagesCalls;
        JumpTargetResult? result;
        b.controller.ensureMessageLoaded('m3').then((r) => result = r);
        untilPageCalls(async, repo, callsBefore, 1); // one page in flight
        b.controller.cancelJump();
        gate.complete();
        async.elapse(const Duration(milliseconds: 50));

        expect(result, JumpTargetResult.cancelled);
        expect(repo.getMessagesCalls - callsBefore, 1, reason: 'no more pages');
        expect(b.state.messages.any((m) => m.id == 'm3'), isFalse);
        expect(b.state.isLoadingMore, isFalse);
      });
    });

    test(
      'overlapping jumps: the newer one waits out a slow in-flight page and '
      'succeeds, the older one stops paging',
      () {
        fakeAsync((async) {
          final repo = FakeChatRepository(currentUserId: userId);
          seed(repo, 40);
          final b = bootFake(async, repo);
          final gate = repo.getMessagesResponseGate = Completer<void>();
          final callsBefore = repo.getMessagesCalls;
          JumpTargetResult? resultA;
          JumpTargetResult? resultB;
          b.controller.ensureMessageLoaded('m3').then((r) => resultA = r);
          untilPageCalls(async, repo, callsBefore, 1); // A's page in flight
          b.controller.ensureMessageLoaded('m20').then((r) => resultB = r);
          async.flushMicrotasks();

          // A slow link: A's page takes longer than any fixed wait budget
          // (the old poll gave up after 5 s and reported "not found").
          async.elapse(const Duration(seconds: 8));
          expect(resultB, isNull, reason: "B waits on A's page, no budget");
          expect(repo.getMessagesCalls - callsBefore, 1);
          gate.complete();
          async.elapse(const Duration(milliseconds: 50));

          expect(resultB, JumpTargetResult.loaded);
          expect(resultA, JumpTargetResult.cancelled);
          expect(b.state.messages.any((m) => m.id == 'm20'), isTrue);
          // A's in-flight page (m34..m25) + B's one page (m24..m15): A paged
          // no further toward m3.
          expect(repo.getMessagesCalls - callsBefore, 2);
          expect(b.state.messages.any((m) => m.id == 'm3'), isFalse);
        });
      },
    );

    test('a deleted (tombstoned) target older than the page still loads', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      repo.serverMessages['m2'] = repo.serverMessages['m2']!.copyWith(
        deletedAt: DateTime(2026, 7, 2),
        content: '',
      );
      final b = await boot(
        repo,
        config: const ChatConfig(messagePageSize: 5, jumpPageSize: 10),
      );
      expect(
        await b.controller.ensureMessageLoaded('m2'),
        JumpTargetResult.loaded,
      );
      final row = b.state.messages.firstWhere((m) => m.id == 'm2');
      expect(row.isDeleted, isTrue);
    });
  });
}
