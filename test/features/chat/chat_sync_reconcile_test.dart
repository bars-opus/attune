import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  ChatState get state => container.read(chatControllerProvider(conversation));
  ChatCacheService get cache => container.read(chatCacheServiceProvider);
}

/// Delegates to the in-memory backend; counts message writes and can fail
/// them, to observe how often a sync persists history and what it does when
/// that write fails.
class _ProbeBackend implements ChatCacheBackend {
  _ProbeBackend(this._inner);
  final ChatCacheBackend _inner;
  int messageWrites = 0;
  bool failMessageWrites = false;

  @override
  Future<void> init() => _inner.init();
  @override
  Future<void> reset() => _inner.reset();
  @override
  Future<void> requestWipeOnNextOpen() => _inner.requestWipeOnNextOpen();
  @override
  Future<String?> readMessages(String u, String r) => _inner.readMessages(u, r);
  @override
  Future<void> writeMessages(String u, String r, String payload) async {
    messageWrites++;
    if (failMessageWrites) throw StateError('disk full');
    await _inner.writeMessages(u, r, payload);
  }

  @override
  Future<void> deleteMessages(String u, String r) =>
      _inner.deleteMessages(u, r);
  @override
  Future<String?> readConversations(String u) => _inner.readConversations(u);
  @override
  Future<void> writeConversations(String u, String p) =>
      _inner.writeConversations(u, p);
  @override
  Future<List<String>> readOutbox(String u, {String? relationshipId}) =>
      _inner.readOutbox(u, relationshipId: relationshipId);
  @override
  Future<void> putOutbox(String u, String r, String c, String p, int t) =>
      _inner.putOutbox(u, r, c, p, t);
  @override
  Future<void> removeOutbox(String u, String r, String c) =>
      _inner.removeOutbox(u, r, c);
  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String u,
    int limit,
  ) => _inner.oldestOutbox(u, limit);
  @override
  Future<void> purgeOutboxForRelationship(String u, String r) =>
      _inner.purgeOutboxForRelationship(u, r);
  @override
  Future<String?> readDraft(String u, String r) => _inner.readDraft(u, r);
  @override
  Future<void> writeDraft(String u, String r, String d) =>
      _inner.writeDraft(u, r, d);
  @override
  Future<void> clearDraft(String u, String r) => _inner.clearDraft(u, r);
  @override
  Future<({int micros, String? id})?> readSyncCursor(String u, String r) =>
      _inner.readSyncCursor(u, r);
  @override
  Future<void> writeSyncCursor(String u, String r, int micros, String? id) =>
      _inner.writeSyncCursor(u, r, micros, id);
  @override
  Future<void> clearSyncCursor(String u, String r) =>
      _inner.clearSyncCursor(u, r);
  @override
  Future<void> clearAll() => _inner.clearAll();
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  final t0 = DateTime(2026, 10, 18, 9);

  Message row(String id, int minutes, {String content = ''}) =>
      Message.fromRow({
        'id': id,
        'relationship_id': relId,
        'sender_id': 'partner',
        'client_message_id': 'c-$id',
        'content': content.isEmpty ? id : content,
        'created_at':
            t0.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
        'source': 'native',
      }, currentUserId: userId);

  Future<_Booted> boot(
    FakeChatRepository repo, {
    int pageSize = 50,
    ChatCacheService? cache,
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: cache,
      extraOverrides: [
        chatConfigProvider.overrideWithValue(
          ChatConfig(messagePageSize: pageSize),
        ),
      ],
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo);
  }

  void seed(FakeChatRepository repo, int count) {
    for (var i = 1; i <= count; i++) {
      repo.seedIncoming(
        id: 'm-$i',
        relationshipId: relId,
        senderId: 'partner',
        content: 'message $i',
        createdAt: t0.add(Duration(minutes: i)),
      );
    }
  }

  group('reconcileWindow (pure)', () {
    test('drops a canonical row inside the fetched span that the page lacks, '
        'keeps rows below the span and every _local_ row', () {
      final a = row('a', 10), b = row('b', 9), c = row('c', 8), d = row('d', 7);
      final local = Message.optimistic(
        id: '_local_x',
        clientMessageId: 'x',
        relationshipId: relId,
        senderId: userId,
        content: 'mine',
        createdAt: t0.add(const Duration(minutes: 11)),
      );
      final result = ChatController.reconcileWindow(
        [local, a, b, c, d],
        [a, c],
        exhaustive: false,
      );
      expect(result.map((m) => m.id), ['_local_x', 'a', 'c', 'd']);
    });

    test(
      'an exhaustive page (shorter than the limit) owns everything below it too',
      () {
        final a = row('a', 10), c = row('c', 8), d = row('d', 7);
        final result = ChatController.reconcileWindow(
          [a, c, d],
          [a, c],
          exhaustive: true,
        );
        expect(result.map((m) => m.id), ['a', 'c']);
      },
    );

    test('an empty exhaustive first page clears every canonical row', () {
      final a = row('a', 10), b = row('b', 9);
      final result = ChatController.reconcileWindow(
        [a, b],
        const [],
        exhaustive: true,
      );
      expect(result, isEmpty);
    });

    test(
      'with a paging cursor only the span below the cursor is reconciled',
      () {
        final a = row('a', 10),
            b = row('b', 9),
            c = row('c', 8),
            d = row('d', 7),
            e = row('e', 6);
        final result = ChatController.reconcileWindow(
          [a, b, c, d, e],
          [c, e],
          before: ChatMessageCursor(sortAt: b.sortAt, id: b.id),
          exhaustive: false,
        );
        // d sat between c and e and the server did not return it; a and b are
        // above the cursor and none of this page's business.
        expect(result.map((m) => m.id), ['a', 'b', 'c', 'e']);
      },
    );

    test(
      'a row sharing the oldest fetched sortAt but with a lower id is below the span',
      () {
        final a = row('a', 10);
        final c2 = row('c2', 8);
        final c1 = row(
          'c1',
          8,
        ); // same minute, lower id: it is on the NEXT page
        final result = ChatController.reconcileWindow(
          [a, c2, c1],
          [a, c2],
          exhaustive: false,
        );
        expect(result.map((m) => m.id), ['a', 'c2', 'c1']);
      },
    );
  });

  group('first page reconcile (#6)', () {
    test(
      'a message deleted on the server disappears from state and cache on the next load',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 3);
        final b = await boot(repo);
        expect(
          b.state.messages.map((m) => m.id),
          containsAll(['m-1', 'm-2', 'm-3']),
        );

        repo.serverMessages.remove('m-2');
        await b.controller.loadMessages(silent: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(b.state.messages.map((m) => m.id), ['m-3', 'm-1']);
        final cached = await b.cache.readMessages(userId, relId);
        expect(cached.map((m) => m.id), ['m-3', 'm-1']);
      },
    );

    test(
      'a wiped table clears the history but keeps a queued local message',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 2);
        final b = await boot(repo);
        repo.sendErrorQueue.add(Exception('network down'));
        await b.controller.sendMessage('still mine');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          b.state.messages.firstWhere((m) => m.content == 'still mine').status,
          MessageStatus.queued,
        );

        repo.serverMessages.clear();
        await b.controller.loadMessages(silent: true);

        expect(b.state.messages.map((m) => m.content), ['still mine']);
      },
    );

    test(
      'a row acknowledged while the first page was in flight is not dropped by that page',
      () async {
        // The page request left before the send was acknowledged, so the
        // response cannot contain the new row. Reconcile may only drop rows the
        // client held BEFORE the request left, never one that arrived while it
        // ran — otherwise a just-sent bubble vanishes until the next catch-up.
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 2);
        final b = await boot(repo);
        final gate = Completer<void>();
        repo.getMessagesResponseGate = gate;
        final page = b.controller.loadMessages(silent: true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await b.controller.sendMessage('while the page was in flight');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(b.state.messages.first.status, MessageStatus.sent);

        repo.getMessagesResponseGate = null;
        gate.complete();
        await page;

        expect(
          b.state.messages.map((m) => m.content),
          contains('while the page was in flight'),
        );
        expect(b.state.messages.first.id.startsWith('_local_'), isFalse);
      },
    );
  });

  group('older pages (#7a)', () {
    test(
      'loadMoreMessages refreshes rows it already holds from the cache',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 8);
        // A cache from a previous session with a stale copy of an old row.
        final cache = ChatCacheService.forTesting(backend: memBackend());
        final stale = [
          for (var i = 8; i >= 1; i--)
            repo.serverMessages['m-$i']!.copyWith(
              content: i == 2 ? 'stale copy' : 'message $i',
            ),
        ];
        await cache.writeMessages(userId, relId, stale);
        final b = await boot(repo, pageSize: 5, cache: cache);
        expect(
          b.state.messages.firstWhere((m) => m.id == 'm-2').content,
          'stale copy',
          reason:
              'row 2 is outside the first page, so it still shows the cache',
        );

        await b.controller.loadMoreMessages();

        expect(
          b.state.messages.firstWhere((m) => m.id == 'm-2').content,
          'message 2',
        );
        expect(b.state.hasMore, isFalse);
      },
    );

    test(
      'loadMoreMessages drops a row in its span that the server no longer has',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 8);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.writeMessages(userId, relId, [
          for (var i = 8; i >= 1; i--) repo.serverMessages['m-$i']!,
        ]);
        repo.serverMessages.remove('m-2');
        final b = await boot(repo, pageSize: 5, cache: cache);
        expect(b.state.messages.any((m) => m.id == 'm-2'), isTrue);

        await b.controller.loadMoreMessages();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(b.state.messages.any((m) => m.id == 'm-2'), isFalse);
        final cached = await b.cache.readMessages(userId, relId);
        expect(
          cached.any((m) => m.id == 'm-2'),
          isFalse,
          reason: 'an older-page drop must survive a restart',
        );
      },
    );
  });

  group('refreshMessagesByIds (#7b)', () {
    test(
      'a reaction on a row outside the newest page is applied in place',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 8);
        final b = await boot(repo, pageSize: 5);
        await b.controller.loadMoreMessages();
        expect(b.state.messages, hasLength(8));

        await repo.addReaction(
          relationshipId: relId,
          messageId: 'm-2',
          emoji: '❤️',
        );
        await b.controller.refreshMessagesByIds({'m-2'});

        final updated = b.state.messages.firstWhere((m) => m.id == 'm-2');
        expect(updated.reactions['❤️'], contains(userId));
        expect(repo.getMessagesByIdsCalls, 1);
      },
    );

    test('an id the server no longer returns is removed locally', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 3);
      final b = await boot(repo);

      repo.serverMessages.remove('m-3');
      await b.controller.refreshMessagesByIds({'m-3'});

      expect(b.state.messages.any((m) => m.id == 'm-3'), isFalse);
      final cached = await b.cache.readMessages(userId, relId);
      expect(cached.any((m) => m.id == 'm-3'), isFalse);
    });
  });

  group('syncChangesSinceCursor (#7c)', () {
    test('edits and deletions made while away land on loaded rows', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final b = await boot(repo);

      await repo.editMessage(messageId: 'm-2', newContent: 'edited away');
      await repo.deleteMessage('m-3');
      await b.controller.syncChangesSinceCursor();

      expect(
        b.state.messages.firstWhere((m) => m.id == 'm-2').content,
        'edited away',
      );
      expect(
        b.state.messages.firstWhere((m) => m.id == 'm-3').isDeleted,
        isTrue,
      );
    });

    test('the sync cursor is the newest server timestamp minus the overlap, '
        'not the device clock', () async {
      // A phone an hour ahead must not ask for "changes since an hour from
      // now" and miss everything: the cursor comes from the rows it holds.
      // The fixed overlap re-reads late-committing transactions (now() is
      // transaction start time) instead of skipping them.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4); // newest row is t0 + 4 min, long before DateTime.now()
      final b = await boot(repo);

      await b.controller.syncChangesSinceCursor();

      expect(
        repo.lastChangedSinceArg,
        t0
            .add(const Duration(minutes: 4))
            .subtract(ChatController.changesSinceOverlap),
      );
      expect(ChatController.changesSinceOverlap, const Duration(seconds: 30));
    });

    test(
      'a changed row older than everything loaded is not glued onto the list',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 12);
        final b = await boot(repo, pageSize: 5);
        expect(b.state.messages, hasLength(5));
        expect(b.state.hasMore, isTrue);

        repo.touch('m-1'); // reacted to, far below the loaded window
        await b.controller.syncChangesSinceCursor();

        expect(
          b.state.messages.any((m) => m.id == 'm-1'),
          isFalse,
          reason:
              'it would render with a hole above it; paging back fetches it in order',
        );
      },
    );

    test('with nothing loaded the cursor sync is a no-op', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      await b.controller.syncChangesSinceCursor();
      expect(repo.lastChangedSinceArg, isNull);
    });
  });

  test(
    '_catchUpFromCursor with no canonical row loads the first page instead of '
    'paging the whole history forward',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 3);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      repo.getMessagesGate = Completer<void>();
      // Reading the notifier boots the controller (its _init runs).
      container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // State is still empty (first page gated). A realtime frame arrives.
      final before = repo.getMessagesAfterCalls;
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageInsert,
          messageId: 'm-3',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(
        repo.getMessagesAfterCalls,
        before,
        reason: 'an open-ended forward page would walk the entire history',
      );
      repo.getMessagesGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(chatControllerProvider(convo)).messages,
        hasLength(3),
      );
      expect(
        repo.getMessagesAfterCalls,
        before,
        reason: 'still no forward page',
      );
    },
  );

  group('fix round 1', () {
    test('isOlderThanCursor: an exact (sortAt, id) match is not older', () {
      final c = row('c', 8);
      final cursor = ChatMessageCursor(sortAt: c.sortAt, id: c.id);
      expect(ChatController.isOlderThanCursor(c, cursor), isFalse);
      expect(ChatController.isOlderThanCursor(row('b', 8), cursor), isTrue);
      expect(ChatController.isOlderThanCursor(row('d', 8), cursor), isFalse);
    });

    test('Message.fromRow carries the server updated_at; toJson does not', () {
      final m = Message.fromRow({
        'id': 'x',
        'relationship_id': relId,
        'sender_id': 'partner',
        'client_message_id': 'c-x',
        'content': 'x',
        'created_at': t0.toUtc().toIso8601String(),
        'updated_at':
            t0.add(const Duration(hours: 2)).toUtc().toIso8601String(),
        'source': 'native',
      }, currentUserId: userId);
      expect(m.serverUpdatedAt, t0.add(const Duration(hours: 2)));
      expect(m.toJson().containsKey('serverUpdatedAt'), isFalse);
    });

    test('I1(a): a locally stamped edit does not push the cursor into the '
        'future', () async {
      // editMessage stamps editedAt with the DEVICE clock (here a day after
      // every server timestamp). The cursor must still come from the server.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final b = await boot(repo);
      final target = b.state.messages.firstWhere((m) => m.id == 'm-2');
      await b.controller.editMessage(target, 'edited on this phone');
      expect(
        b.state.messages
            .firstWhere((m) => m.id == 'm-2')
            .editedAt!
            .isAfter(t0.add(const Duration(hours: 1))),
        isTrue,
      );

      await b.controller.syncChangesSinceCursor();

      expect(
        repo.lastChangedSinceArg,
        t0
            .add(const Duration(minutes: 4))
            .subtract(ChatController.changesSinceOverlap),
      );
    });

    test('I1(b): the server cursor survives a controller restart via the '
        'cache', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final first = await boot(repo, cache: cache);
      final serverChange = t0.add(const Duration(hours: 1));
      repo.touch('m-2', serverChange);
      await first.controller.syncChangesSinceCursor();
      expect(
        repo.lastChangedSinceArg,
        t0
            .add(const Duration(minutes: 4))
            .subtract(ChatController.changesSinceOverlap),
      );

      // A new controller over the same cache (a cold start).
      final second = await boot(repo, cache: cache);
      await second.controller.syncChangesSinceCursor();

      expect(
        repo.lastChangedSinceArg,
        serverChange.subtract(ChatController.changesSinceOverlap),
        reason: 'resumes from the persisted server cursor, not a re-seed',
      );
    });

    test('I1: a first page never advances an existing cursor', () async {
      // A first page shows the newest rows' current state; it says nothing
      // about changes to older cached rows made while away.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final first = await boot(repo, cache: cache);
      final applied = t0.add(const Duration(hours: 1));
      repo.touch('m-2', applied);
      await first.controller.syncChangesSinceCursor();

      // While away: a new message far newer than the persisted cursor.
      repo.seedIncoming(
        id: 'm-5',
        relationshipId: relId,
        senderId: 'partner',
        content: 'sent while away',
        createdAt: t0.add(const Duration(hours: 3)),
      );
      final second = await boot(repo, cache: cache);
      expect(second.state.messages.first.id, 'm-5');
      await second.controller.syncChangesSinceCursor();

      expect(
        repo.lastChangedSinceArg,
        applied.subtract(ChatController.changesSinceOverlap),
      );
    });

    test('I1: with no server page yet the cursor sync is a no-op even with a '
        'warm cache', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 4; i >= 1; i--) repo.serverMessages['m-$i']!,
      ]);
      repo.getMessagesGate = Completer<void>();
      final b = await boot(repo, cache: cache);
      expect(b.state.messages, hasLength(4));

      await b.controller.syncChangesSinceCursor();

      expect(repo.lastChangedSinceArg, isNull);
      repo.getMessagesGate!.complete();
    });

    test('I1(c): more than 200 changed rows are all applied', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 250);
      final b = await boot(repo, pageSize: 50);
      while (b.state.hasMore) {
        await b.controller.loadMoreMessages();
      }
      expect(b.state.messages, hasLength(250));

      for (var i = 1; i <= 250; i++) {
        repo.serverMessages['m-$i'] = repo.serverMessages['m-$i']!.copyWith(
          content: 'changed $i',
        );
        repo.touch('m-$i', t0.add(Duration(days: 1, seconds: i)));
      }
      await b.controller.syncChangesSinceCursor();

      expect(
        b.state.messages.where((m) => m.content.startsWith('changed ')),
        hasLength(250),
      );
      expect(repo.changedSinceCalls, greaterThan(1));
    });

    test('I1(d): 300 rows changed in ONE transaction (one updated_at) are '
        'all applied by one sync', () async {
      // A partner reading 300 unread messages stamps them all with the same
      // transaction-time updated_at. A timestamp-only continuation re-reads
      // the same capped page forever; the (updated_at, id) keyset moves on.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 300);
      final b = await boot(repo, pageSize: 50);
      while (b.state.hasMore) {
        await b.controller.loadMoreMessages();
      }
      expect(b.state.messages, hasLength(300));

      final oneTransaction = t0.add(const Duration(days: 1));
      for (var i = 1; i <= 300; i++) {
        repo.serverMessages['m-$i'] = repo.serverMessages['m-$i']!.copyWith(
          content: 'read $i',
        );
        repo.touch('m-$i', oneTransaction);
      }
      await b.controller.syncChangesSinceCursor();

      expect(
        b.state.messages.where((m) => m.content.startsWith('read ')),
        hasLength(300),
      );
    });

    test('the Supabase changes-since read starts on the keyset branch when '
        'given an afterId', () {
      // Source-level (the real repository needs a server): a caller's
      // (since, afterId) continuation must enter the strictly-after keyset
      // query, not the `updated_at >= since` first-page query.
      final source =
          File(
            'lib/features/chat/data/repositories/supabase_chat_repository.dart',
          ).readAsStringSync();
      final start = source.indexOf(
        'Future<List<Message>> getMessagesChangedSince(',
      );
      final end = source.indexOf('@override', start + 1);
      final body = source.substring(start, end);
      expect(body, contains('String? afterId,'));
      // The paging loop is collectChangedSincePages (behaviour-tested in
      // changed_since_pages_test.dart); its first page gets these.
      expect(
        body,
        contains('startUpdatedAt: afterId == null ? null : sinceIso,'),
      );
      expect(body, contains('startId: afterId,'));
      expect(body, contains('lastUpdatedAt == null'));
      expect(
        body,
        contains("'and(updated_at.eq.\$lastUpdatedAt,id.gt.\$lastId)'"),
      );
    });

    test('M1: before any server page lands, a by-id row older than the warm '
        'cache is not glued on', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 10);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 10; i >= 6; i--) repo.serverMessages['m-$i']!,
      ]);
      repo.getMessagesGate = Completer<void>();
      final b = await boot(repo, cache: cache);
      expect(b.state.messages, hasLength(5));
      expect(b.state.hasMore, isFalse, reason: 'ChatState.initial default');

      await b.controller.refreshMessagesByIds({'m-1'});

      expect(b.state.messages.any((m) => m.id == 'm-1'), isFalse);
      repo.getMessagesGate!.complete();
    });

    test('M3: a pull whose page is all rows already on screen chains to '
        'the next page', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 15);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 15; i >= 6; i--) repo.serverMessages['m-$i']!,
      ]);
      final b = await boot(repo, pageSize: 5, cache: cache);
      expect(b.state.messages, hasLength(10));
      final callsBefore = repo.getMessagesCalls;

      await b.controller.loadMoreMessages();

      expect(b.state.messages.any((m) => m.id == 'm-1'), isTrue);
      expect(repo.getMessagesCalls - callsBefore, 2);
      expect(b.state.isLoadingMore, isFalse);
    });

    test('M3: chaining is bounded per pull', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 40);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 40; i >= 2; i--) repo.serverMessages['m-$i']!,
      ]);
      final b = await boot(repo, pageSize: 5, cache: cache);
      final callsBefore = repo.getMessagesCalls;

      await b.controller.loadMoreMessages();

      expect(repo.getMessagesCalls - callsBefore, 5);
      expect(b.state.hasMore, isTrue);
      expect(b.state.isLoadingMore, isFalse);
    });

    test('M6: a catch-up that falls back to the first page does not load it '
        'twice', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 3);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      repo.getMessagesGate = Completer<void>();
      container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final callsBefore = repo.getMessagesCalls;

      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageInsert,
          messageId: 'm-3',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      repo.getMessagesGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.getMessagesCalls - callsBefore, 1);
      expect(
        container.read(chatControllerProvider(convo)).messages,
        hasLength(3),
      );
    });

    test('M7: a row merged while an older page was in flight is not dropped '
        'by that page', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 10);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.writeMessages(userId, relId, [
        for (var i = 10; i >= 1; i--) repo.serverMessages['m-$i']!,
      ]);
      final b = await boot(repo, pageSize: 5, cache: cache);
      expect(b.state.messages, hasLength(10));

      final gate = Completer<void>();
      repo.getMessagesResponseGate = gate;
      final page = b.controller.loadMoreMessages();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Lands on the server after the page snapshot, inside the page's span,
      // and reaches this phone by id while the page is still in flight.
      repo.seedIncoming(
        id: 'm-3b',
        relationshipId: relId,
        senderId: 'partner',
        content: 'late arrival',
        createdAt: t0.add(const Duration(minutes: 3, seconds: 30)),
      );
      await b.controller.refreshMessagesByIds({'m-3b'});
      expect(b.state.messages.any((m) => m.id == 'm-3b'), isTrue);

      repo.getMessagesResponseGate = null;
      gate.complete();
      await page;

      expect(b.state.messages.any((m) => m.id == 'm-3b'), isTrue);
    });
  });

  group('fix round 2', () {
    test('R2-1: a backlog of >1000 rows on one updated_at does not stall the '
        'cursor: each call gets past the persisted cursor', () async {
      // Every call restarts 30 s behind the cursor. Without jumping to the
      // call-start cursor once the overlap is re-read, the per-call budget
      // is spent re-reading the same 1000 rows forever.
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 1100);
      final b = await boot(repo, pageSize: 50);
      final oneTransaction = t0.add(const Duration(days: 1));
      for (var i = 1; i <= 1100; i++) {
        repo.touch('m-$i', oneTransaction);
      }
      await b.controller.syncChangesSinceCursor();
      await b.controller.syncChangesSinceCursor();

      repo.serverMessages['m-1100'] = repo.serverMessages['m-1100']!.copyWith(
        content: 'changed later',
      );
      repo.touch('m-1100', oneTransaction.add(const Duration(seconds: 1)));
      await b.controller.syncChangesSinceCursor();

      expect(
        b.state.messages.firstWhere((m) => m.id == 'm-1100').content,
        'changed later',
      );
    });

    test('R2-2: a read the repository did not cap ends the sync without an '
        'extra round trip', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 120);
      final b = await boot(repo, pageSize: 50);
      for (var i = 1; i <= 120; i++) {
        repo.touch('m-$i', t0.add(Duration(days: 1, seconds: i)));
      }
      final before = repo.changedSinceCalls;
      await b.controller.syncChangesSinceCursor();
      expect(
        repo.changedSinceCalls - before,
        1,
        reason: '120 rows is under the repository cap: the set is exhausted',
      );
    });

    test('R2-3: a purge that lands while a sync is in flight is not undone '
        'by that sync', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final b = await boot(repo, cache: cache);
      expect(await b.cache.readSyncCursor(userId, relId), isNotNull);
      repo.touch('m-2', t0.add(const Duration(hours: 1)));

      final gate = Completer<void>();
      repo.getMessagesChangedSinceGate = gate;
      final sync = b.controller.syncChangesSinceCursor();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The relationship is archived meanwhile: local state is purged.
      repo.conversationOverride = activeConversation(
        relId,
      ).copyWith(availability: ConversationAvailability.archived);
      b.container.read(conversationsRefreshProvider.notifier).state++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await b.cache.readSyncCursor(userId, relId), isNull);

      repo.getMessagesChangedSinceGate = null;
      gate.complete();
      await sync;

      expect(await b.cache.readSyncCursor(userId, relId), isNull);
      expect(await b.cache.readMessages(userId, relId), isEmpty);
    });

    test('R2-4: one sync of several reads writes the history once', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 250);
      final backend = _ProbeBackend(memBackend());
      final cache = ChatCacheService.forTesting(backend: backend);
      final b = await boot(repo, pageSize: 50, cache: cache);
      while (b.state.hasMore) {
        await b.controller.loadMoreMessages();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      for (var i = 1; i <= 250; i++) {
        repo.serverMessages['m-$i'] = repo.serverMessages['m-$i']!.copyWith(
          content: 'changed $i',
        );
        repo.touch('m-$i', t0.add(Duration(days: 1, seconds: i)));
      }
      final writesBefore = backend.messageWrites;
      final readsBefore = repo.changedSinceCalls;

      await b.controller.syncChangesSinceCursor();

      expect(repo.changedSinceCalls - readsBefore, greaterThan(1));
      expect(backend.messageWrites - writesBefore, 1);
      expect(
        b.state.messages.where((m) => m.content.startsWith('changed ')),
        hasLength(250),
      );
    });

    test(
      'R2-4: the cursor is not persisted when the history write fails',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 4);
        final backend = _ProbeBackend(memBackend());
        final cache = ChatCacheService.forTesting(backend: backend);
        final b = await boot(repo, cache: cache);
        final seeded = await b.cache.readSyncCursor(userId, relId);
        expect(seeded, isNotNull);

        await repo.editMessage(messageId: 'm-2', newContent: 'edited away');
        backend.failMessageWrites = true;
        await expectLater(
          b.controller.syncChangesSinceCursor(),
          throwsA(isA<StateError>()),
        );

        final after = await b.cache.readSyncCursor(userId, relId);
        expect(after!.at, seeded!.at);
        expect(after.id, seeded.id);
      },
    );
  });

  group('fix round 3: nothing is written back after a purge', () {
    Conversation archived() => activeConversation(
      relId,
    ).copyWith(availability: ConversationAvailability.archived);

    Future<void> archiveNow(_Booted b, FakeChatRepository repo) async {
      repo.conversationOverride = archived();
      b.container.read(conversationsRefreshProvider.notifier).state++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        b.state.conversation.availability,
        ConversationAvailability.archived,
      );
    }

    Future<void> expectNothingPersisted(
      ChatCacheService cache,
      ChatState state,
    ) async {
      expect(await cache.readSyncCursor(userId, relId), isNull);
      expect(await cache.readMessages(userId, relId), isEmpty);
      expect(state.messages, isEmpty);
    }

    test('R3(a): a first page in flight across an archive purge writes '
        'nothing and seeds no cursor', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      // _init's concurrent header refresh finds the relationship archived
      // while the first page is still in flight.
      repo.conversationOverride = archived();
      final gate = Completer<void>();
      repo.getMessagesGate = gate;
      container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        container.read(chatControllerProvider(convo)).conversation.availability,
        ConversationAvailability.archived,
      );

      repo.getMessagesGate = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await expectNothingPersisted(
        cache,
        container.read(chatControllerProvider(convo)),
      );
    });

    test('R3(b): a first page in flight across an account change writes '
        'nothing under the previous account', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final gate = Completer<void>();
      repo.getMessagesGate = gate;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await controller.debugHandleAccountChange(userId);
      repo.getMessagesGate = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await expectNothingPersisted(
        cache,
        container.read(chatControllerProvider(convo)),
      );
    });

    test(
      'R3(c): loadMoreMessages in flight across a purge writes nothing',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 10);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        final b = await boot(repo, pageSize: 5, cache: cache);
        final gate = Completer<void>();
        repo.getMessagesResponseGate = gate;
        final more = b.controller.loadMoreMessages();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await archiveNow(b, repo);
        repo.getMessagesResponseGate = null;
        gate.complete();
        await more;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await expectNothingPersisted(cache, b.state);
        expect(b.state.isLoadingMore, isFalse);
      },
    );

    test('R3: a forward catch-up in flight across an account change writes '
        'nothing under the previous account', () async {
      // (An archive purge here would be masked: the realtime handler's
      // tail refreshes the conversation, which purges a second time.)
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 4);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final b = await boot(repo, cache: cache);
      repo.seedIncoming(
        id: 'm-5',
        relationshipId: relId,
        senderId: 'partner',
        content: 'new',
        createdAt: t0.add(const Duration(minutes: 5)),
      );
      final gate = Completer<void>();
      repo.getMessagesAfterGate = gate;
      final afterCallsBefore = repo.getMessagesAfterCalls;
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(
        repo.getMessagesAfterCalls - afterCallsBefore,
        1,
        reason: 'the catch-up read is in flight',
      );

      await b.controller.debugHandleAccountChange(userId);
      repo.getMessagesAfterGate = null;
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectNothingPersisted(cache, b.state);
    });

    test(
      'R3: refreshMessagesByIds in flight across a purge writes nothing',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        seed(repo, 4);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        final b = await boot(repo, cache: cache);
        final gate = Completer<void>();
        repo.getMessagesByIdsGate = gate;
        final refresh = b.controller.refreshMessagesByIds({'m-2'});
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await archiveNow(b, repo);
        repo.getMessagesByIdsGate = null;
        gate.complete();
        await refresh;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await expectNothingPersisted(cache, b.state);
      },
    );

    test('R3-3: a later read failing keeps the progress of the reads before '
        'it, then rethrows', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      seed(repo, 250);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final b = await boot(repo, pageSize: 50, cache: cache);
      while (b.state.hasMore) {
        await b.controller.loadMoreMessages();
      }
      for (var i = 1; i <= 250; i++) {
        repo.serverMessages['m-$i'] = repo.serverMessages['m-$i']!.copyWith(
          content: 'changed $i',
        );
        repo.touch('m-$i', t0.add(Duration(days: 1, seconds: i)));
      }
      // The first read (200 rows) succeeds; the continuation fails.
      repo.changedSinceErrorsByCall[repo.changedSinceCalls + 2] = StateError(
        'offline',
      );

      await expectLater(
        b.controller.syncChangesSinceCursor(),
        throwsA(isA<StateError>()),
      );

      final cursor = await b.cache.readSyncCursor(userId, relId);
      expect(cursor!.at, t0.add(const Duration(days: 1, seconds: 200)));
      expect(cursor.id, 'm-200');
      final cached = await b.cache.readMessages(userId, relId);
      expect(
        cached.firstWhere((m) => m.id == 'm-200').content,
        'changed 200',
        reason: 'what was applied before the failure is persisted',
      );

      await b.controller.syncChangesSinceCursor();
      expect(
        b.state.messages.where((m) => m.content.startsWith('changed ')),
        hasLength(250),
      );
    });
  });
}
