// Plan 1a (chat W1a: delivery, sync & cache) — the final whole-plan
// review's fixes: C1, I1 and M1–M7. M8 (the io cache on a background
// isolate) is covered in chat_cache_backend_io_test.dart.
import 'dart:async';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/data/repositories/supabase_chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/chat_test_harness.dart';

const _userId = 'user-a';
const _relId = 'rel-1';

class _Booted {
  _Booted(this.controller, this.container, this.conversation, this.cache);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  final ChatCacheService cache;
  ChatState get state => container.read(chatControllerProvider(conversation));
}

Future<_Booted> _boot(
  FakeChatRepository repo, {
  ChatCacheService? cache,
  Conversation? conversation,
  Duration? networkTimeout,
  int? pageSize,
  StateProvider<User?>? userSwitch,
}) async {
  final effectiveCache =
      cache ?? ChatCacheService.forTesting(backend: memBackend());
  final container = buildChatContainer(
    repository: repo,
    userId: _userId,
    cache: effectiveCache,
    userSwitch: userSwitch,
    extraOverrides: [
      chatConfigProvider.overrideWithValue(
        ChatConfig(
          networkTimeout: networkTimeout ?? const ChatConfig().networkTimeout,
          messagePageSize: pageSize ?? const ChatConfig().messagePageSize,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final convo = conversation ?? activeConversation(_relId);
  repo.conversationOverride ??= convo;
  final controller = container.read(chatControllerProvider(convo).notifier);
  await Future<void>.delayed(const Duration(milliseconds: 30));
  return _Booted(controller, container, convo, effectiveCache);
}

Message _partnerSends(
  FakeChatRepository repo,
  String id, {
  DateTime? at,
  String content = 'hello',
}) => repo.seedIncoming(
  id: id,
  relationshipId: _relId,
  senderId: 'partner',
  content: content,
  createdAt: at ?? DateTime.now(),
);

ChatRealtimeEvent _insert(String id) =>
    ChatRealtimeEvent(ChatRealtimeKind.messageInsert, messageId: id);

/// Waits out the realtime debounce (250 ms) and the batch behind it.
Future<void> _settle([int ms = 350]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Collects debugPrint output (ChatLog) for the rest of the test.
List<String> _captureLogs() {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  addTearDown(() => debugPrint = previous);
  return lines;
}

void main() {
  group('C1: an insert committed behind the forward cursor', () {
    test('a partner row whose sort_at is older than the newest held row still '
        'renders from its frame', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final now = DateTime.now();
      // My message: its transaction started 5 ms after the partner's but
      // took the counter lock first and committed first.
      repo.seedIncoming(
        id: 'mine-1',
        relationshipId: _relId,
        senderId: _userId,
        content: 'mine',
        createdAt: now,
      );
      final b = await _boot(repo);
      expect(b.state.messages.first.id, 'mine-1');

      _partnerSends(
        repo,
        'inc-late',
        at: now.subtract(const Duration(milliseconds: 5)),
      );
      repo.emitRealtime(_insert('inc-late'));
      await _settle();

      expect(b.state.messages.map((m) => m.id), contains('inc-late'));
      expect(
        repo.getMessagesByIdsCalls,
        1,
        reason: 'the row the catch-up missed is read by id, once',
      );
    });

    test('an insert the catch-up returns costs no by-id read', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      _partnerSends(repo, 'inc-0', content: 'earlier');
      final b = await _boot(repo);
      final forward = repo.getMessagesAfterCalls;

      _partnerSends(repo, 'inc-1', content: 'new');
      repo.emitRealtime(_insert('inc-1'));
      await _settle();

      expect(b.state.messages.first.id, 'inc-1');
      expect(repo.getMessagesAfterCalls, forward + 1);
      expect(repo.getMessagesByIdsCalls, 0);
    });
  });

  group('I1: a frame beats a failing insert response', () {
    test('the delivered row stays sent with no banner, and the retry '
        'reconciles onto one row', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      repo.enforceUniqueClientId = true;
      final b = await _boot(
        repo,
        networkTimeout: const Duration(milliseconds: 600),
      );
      // The insert commits; its answer is lost on the way back.
      repo.sendResponseGates.add(Completer<void>());

      final send = b.controller.sendMessage('hello');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final cid = repo.lastSendArgs!.clientMessageId;
      repo.emitRealtime(_insert('srv-$cid'));
      await _settle();
      expect(
        b.state.messages.where((m) => m.clientMessageId == cid).single.id,
        'srv-$cid',
        reason: 'the catch-up merged the canonical row before the timeout',
      );

      await send; // the bounded insert times out
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final row = b.state.messages.where((m) => m.clientMessageId == cid);
      expect(row.single.status, MessageStatus.sent);
      expect(b.state.error, isNull, reason: 'no offline banner: it arrived');

      await b.controller.flushOutbox(force: true); // 23505 -> reconcile
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final after = b.state.messages.where((m) => m.clientMessageId == cid);
      expect(after.single.status, MessageStatus.sent);
      expect(after.single.id, 'srv-$cid');
      expect(
        await b.cache.readOutbox(_userId, relationshipId: _relId),
        isEmpty,
      );
    });

    test('a chat going read-only never turns a delivered row failed', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      // The server has the message; its outbox row is still waiting (the
      // answer was lost) and reconciles on the next attempt.
      repo.seedIncoming(
        id: 'mine-1',
        relationshipId: _relId,
        senderId: _userId,
        content: 'mine',
        createdAt: DateTime.now(),
      );
      await cache.putOutbox(
        _userId,
        PendingSend(
          clientMessageId: 'seed-mine-1',
          relationshipId: _relId,
          senderId: _userId,
          text: 'mine',
          createdAt: DateTime.now(),
          attempts: 1,
          nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
          state: PendingSendState.queued,
        ),
      );
      repo.conversationOverride = readOnlyConversation(_relId);
      final header = Completer<void>();
      repo.getConversationGate = header; // the page lands first
      final b = await _boot(repo, cache: cache);
      expect(b.state.messages.single.id, 'mine-1');

      repo.getConversationGate = null;
      header.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final row = b.state.messages.single;
      expect(row.id, 'mine-1');
      expect(row.status, MessageStatus.sent);
      expect(b.state.error, isNull, reason: 'nothing of theirs is unsent');
    });
  });

  group('M1: a history write failing at runtime', () {
    test('is logged, never an uncaught async error, on every unawaited '
        'path', () async {
      final logs = _captureLogs();
      final repo = FakeChatRepository(currentUserId: _userId);
      for (var i = 1; i <= 8; i++) {
        _partnerSends(
          repo,
          'm-$i',
          at: DateTime.now().subtract(Duration(minutes: 10 - i)),
          content: 'private words $i',
        );
      }
      final backend = ScriptedCacheBackend()..failWriteMessages = true;
      final cache = ChatCacheService.forTesting(backend: backend);
      // First page.
      final b = await _boot(repo, cache: cache, pageSize: 5);
      // Catch-up.
      _partnerSends(repo, 'm-9', content: 'private words 9');
      repo.emitRealtime(_insert('m-9'));
      await _settle();
      // By-id refresh.
      await b.controller.refreshMessagesByIds({'m-8'});
      // An older page.
      await b.controller.loadMoreMessages();
      // Removing a failed send.
      repo.nextSendError = const _UnknownServerError();
      await b.controller.sendMessage('private words 10');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final local = b.state.messages.firstWhere(
        (m) => m.id.startsWith('_local_'),
      );
      await b.controller.removeFailedMessage(local);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final failures = logs.where(
        (l) => l.contains('history cache write failed'),
      );
      expect(failures.length, greaterThanOrEqualTo(5));
      expect(
        logs.where((l) => l.contains('private words')),
        isEmpty,
        reason: 'ids and shapes only, never content',
      );
    });
  });

  group('M2: one reader on open', () {
    test(
      'the channel joining right after the open reads nothing again',
      () async {
        final repo = FakeChatRepository(currentUserId: _userId);
        _partnerSends(repo, 'inc-1', content: 'undelivered');
        final b = await _boot(repo);
        expect(b.state.messages, hasLength(1));
        final pages = repo.getMessagesCalls;
        final headers = repo.getConversationCalls;
        final pins = repo.getPinnedCalls;
        final delivered = repo.markDeliveredCalls.length;

        repo.emitRealtime(const ChatRealtimeEvent.resync(initial: true));
        await _settle(400);

        expect(repo.getMessagesCalls, pages, reason: 'no second first page');
        expect(repo.getConversationCalls, headers, reason: 'no second header');
        expect(repo.getPinnedCalls, pins, reason: 'no second pins read');
        expect(repo.markDeliveredCalls.length, delivered);

        // A real reconnect after that is a full resync.
        repo.emitRealtime();
        await _settle(400);
        expect(repo.getMessagesCalls, pages + 1);
        expect(repo.getConversationCalls, headers + 1);
        expect(repo.getPinnedCalls, pins + 1);
      },
    );

    test('an empty chat: a message landing between the open and the join is '
        'visible after the join, with no further frame', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final b = await _boot(repo); // the open's first page is empty
      expect(b.state.messages, isEmpty);

      _partnerSends(repo, 'inc-1', content: 'first ever');
      repo.emitRealtime(const ChatRealtimeEvent.resync(initial: true));
      await _settle(400);

      expect(b.state.messages.map((m) => m.id), ['inc-1']);
    });

    test('a join landing while the cold open is still reading waits for it: '
        'one first page', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      _partnerSends(repo, 'inc-1');
      final gate = Completer<void>();
      repo.getMessagesGate = gate;
      final b = await _boot(repo);
      repo.emitRealtime(const ChatRealtimeEvent.resync(initial: true));
      await _settle(300);

      repo.getMessagesGate = null;
      gate.complete();
      await _settle(400);

      expect(b.state.messages.map((m) => m.id), ['inc-1']);
      expect(repo.getMessagesCalls, 1);
    });

    test('a join long after the open (more than a network timeout) is a '
        'full resync', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      _partnerSends(repo, 'inc-1');
      final b = await _boot(
        repo,
        networkTimeout: const Duration(milliseconds: 200),
      );
      expect(b.state.messages, hasLength(1));
      final pages = repo.getMessagesCalls;
      final headers = repo.getConversationCalls;
      final pins = repo.getPinnedCalls;
      await Future<void>.delayed(const Duration(milliseconds: 300));

      repo.emitRealtime(const ChatRealtimeEvent.resync(initial: true));
      await _settle(400);

      expect(repo.getMessagesCalls, pages + 1);
      expect(repo.getConversationCalls, headers + 1);
      expect(repo.getPinnedCalls, pins + 1);
    });

    test('an open whose first page failed is repaired by the join', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      _partnerSends(repo, 'inc-1');
      repo.getMessagesError = Exception('flaky');
      final b = await _boot(repo);
      expect(b.state.messages, isEmpty);
      final pages = repo.getMessagesCalls;

      repo.getMessagesError = null;
      repo.emitRealtime(const ChatRealtimeEvent.resync(initial: true));
      await _settle(400);

      expect(repo.getMessagesCalls, pages + 1);
      expect(b.state.messages.map((m) => m.id), ['inc-1']);
    });
  });

  group('M3: an unreadable outbox', () {
    testWidgets('is retried on a doubling backoff up to 64 s, not every 5 s', (
      tester,
    ) async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final backend =
          ScriptedCacheBackend()..armReadOutboxFailures((_) => true);
      final cache = ChatCacheService.forTesting(backend: backend);
      final container = buildChatContainer(
        repository: repo,
        userId: _userId,
        cache: cache,
      );
      final convo = activeConversation(_relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await tester.pump(const Duration(milliseconds: 100));
      final atOpen = backend.readOutboxCalls;

      // 150 s of a dead cache. Every 5 s would be ~30 passes; 5, 10, 20,
      // 40, 64 s is five.
      for (var s = 0; s < 150; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final passes = (backend.readOutboxCalls - atOpen) ~/ 2;
      expect(passes, inInclusiveRange(4, 6));

      // The cache recovers: the next pass reads it, and a later failure
      // starts the backoff from the bottom again.
      backend.failReadOutbox = null;
      for (var s = 0; s < 70; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      backend.armReadOutboxFailures((_) => true);
      await controller.flushOutbox();
      await tester.pump(const Duration(milliseconds: 10));
      final wait = controller.debugRetryDeadline!.difference(DateTime.now());
      expect(wait, lessThanOrEqualTo(const Duration(seconds: 5)));

      container.dispose();
      await tester.pump();
    });
  });

  group('M4: an older-page read', () {
    test('that never answers cannot leave isLoadingMore stuck', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final base = DateTime.now().subtract(const Duration(hours: 1));
      for (var i = 1; i <= 10; i++) {
        _partnerSends(repo, 'm-$i', at: base.add(Duration(minutes: i)));
      }
      final b = await _boot(
        repo,
        pageSize: 5,
        networkTimeout: const Duration(milliseconds: 200),
      );
      expect(b.state.hasMore, isTrue);

      repo.getMessagesGate = Completer<void>(); // black-holed
      unawaited(b.controller.loadMoreMessages());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(b.state.isLoadingMore, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(b.state.isLoadingMore, isFalse);
    });
  });

  group('M5: bounds scale with the requests underneath', () {
    test(
      'a by-id refresh over two id chunks on a slow link completes',
      () async {
        final repo = FakeChatRepository(currentUserId: _userId);
        final base = DateTime.now().subtract(const Duration(hours: 3));
        for (var i = 1; i <= 150; i++) {
          _partnerSends(repo, 'm-$i', at: base.add(Duration(minutes: i)));
        }
        final b = await _boot(
          repo,
          pageSize: 200,
          networkTimeout: const Duration(milliseconds: 200),
        );
        expect(b.state.messages, hasLength(150));
        await repo.editMessage(messageId: 'm-1', newContent: 'edited');
        // Each request is quick (150 ms < 200 ms); two chunks plus the
        // reactions read are not (450 ms).
        repo.byIdsRequestDelay = const Duration(milliseconds: 150);

        await b.controller.refreshMessagesByIds({
          for (var i = 1; i <= 150; i++) 'm-$i',
        });

        expect(
          b.state.messages.firstWhere((m) => m.id == 'm-1').content,
          'edited',
        );
      },
    );

    test('a catch-up over a big gap on a slow link restores every row, in '
        'separately bounded page reads', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      final base = DateTime.now().subtract(const Duration(hours: 1));
      _partnerSends(repo, 'm-0', at: base);
      final b = await _boot(
        repo,
        pageSize: 5,
        networkTimeout: const Duration(milliseconds: 200),
      );
      for (var i = 1; i <= 30; i++) {
        _partnerSends(repo, 'm-$i', at: base.add(Duration(seconds: i)));
      }
      // Each page is quick (60 ms); the whole gap is seven pages (420 ms),
      // past one 200 ms bound.
      repo.afterPageDelay = const Duration(milliseconds: 60);
      repo.emitRealtime(_insert('m-30'));
      await _settle(1200);

      expect(b.state.messages, hasLength(31));
      expect(
        repo.lastAfterMaxPagesArg,
        1,
        reason: 'one page per bounded request',
      );
    });
  });

  group('M6: a same-device account switch inside the keep-alive', () {
    Future<void> expectLiveFor(
      FakeChatRepository repo,
      ProviderContainer container,
      Conversation convo,
    ) async {
      final state = container.read(chatControllerProvider(convo));
      expect(
        state.conversation.availability,
        isNot(ConversationAvailability.archived),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final opened = container.read(chatControllerProvider(convo));
      expect(opened.error, isNull);
      expect(opened.messages.map((m) => m.id), contains('inc-1'));

      // Subscribed: a frame reaches the new controller.
      _partnerSends(repo, 'inc-2', content: 'for whoever is here now');
      repo.emitRealtime(_insert('inc-2'));
      await _settle();
      expect(
        container.read(chatControllerProvider(convo)).messages.map((m) => m.id),
        contains('inc-2'),
      );
    }

    test('sign out, then the other member signs in and opens the shared '
        'chat: live, subscribed, their messages', () async {
      final repo = FakeChatRepository(currentUserId: _userId);
      _partnerSends(repo, 'inc-1');
      final userSwitch = StateProvider<User?>((ref) => testUser(_userId));
      final b = await _boot(repo, userSwitch: userSwitch);
      expect(b.state.messages, isNotEmpty);

      b.container.read(userSwitch.notifier).state = null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      b.container.read(userSwitch.notifier).state = testUser('user-b');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await expectLiveFor(repo, b.container, b.conversation);
    });

    test(
      'a direct switch to the other member gives them a live chat',
      () async {
        final repo = FakeChatRepository(currentUserId: _userId);
        _partnerSends(repo, 'inc-1');
        final userSwitch = StateProvider<User?>((ref) => testUser(_userId));
        final b = await _boot(repo, userSwitch: userSwitch);

        b.container.read(userSwitch.notifier).state = testUser('user-b');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        await expectLiveFor(repo, b.container, b.conversation);
      },
    );
  });

  group('M7: the first-page seed of the sync cursor', () {
    test('message reads select updated_at', () {
      expect(
        SupabaseChatRepository.debugMessageColumns.split(','),
        contains('updated_at'),
      );
    });

    test(
      'is the page\'s newest updated_at, not its newest created_at',
      () async {
        final repo = FakeChatRepository(currentUserId: _userId);
        final t0 = DateTime.utc(2026, 9, 1, 12);
        for (var i = 1; i <= 4; i++) {
          _partnerSends(repo, 'm-$i', at: t0.add(Duration(minutes: i)));
        }
        // A reaction yesterday on an old message.
        final reacted = t0.add(const Duration(days: 20));
        repo.touch('m-2', reacted);
        final b = await _boot(repo);

        await b.controller.syncChangesSinceCursor();

        expect(
          repo.lastChangedSinceArg,
          reacted.subtract(ChatController.changesSinceOverlap),
        );
      },
    );
  });
}

/// A send failure of unknown shape: the bubble stays local (queued), which
/// is what Remove acts on.
class _UnknownServerError implements Exception {
  const _UnknownServerError();
}
