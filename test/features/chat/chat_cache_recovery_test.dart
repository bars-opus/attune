import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_backend_base.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// A backend that fails to open a scripted number of times, can be reset,
/// and can be told to throw on reads — the three ways SQLite fails in the
/// field (corrupt file, locked WAL, disk I/O).
class _FlakyBackend implements ChatCacheBackend {
  _FlakyBackend({
    this.initFailuresLeft = 0,
    this.initFailureKind = ChatCacheFailureKind.corrupt,
    this.initFailureKinds,
  });

  final ChatCacheBackend inner = memBackend();
  int initFailuresLeft;

  /// How each scripted open failure is classified; null throws a plain
  /// (unclassified) error, as a non-SQLite failure would.
  ChatCacheFailureKind? initFailureKind;

  /// Per-attempt kinds, consumed in order before [initFailureKind] applies.
  List<ChatCacheFailureKind>? initFailureKinds;
  int initCalls = 0;
  int resetCalls = 0;
  bool throwOnReads = false;
  bool throwOnWrites = false;

  /// Fails only the named backend calls (e.g. 'oldestOutbox'), regardless of
  /// [throwOnReads]/[throwOnWrites].
  final Set<String> failOnly = <String>{};

  @override
  Future<void> init() async {
    initCalls++;
    final gate = initGate;
    if (gate != null) await gate.future;
    if (initFailuresLeft > 0) {
      initFailuresLeft--;
      final scripted = initFailureKinds;
      final kind =
          scripted != null && scripted.isNotEmpty
              ? scripted.removeAt(0)
              : initFailureKind;
      final cause = StateError('scripted open failure');
      if (kind == null) throw cause;
      throw ChatCacheOpenException(kind, cause);
    }
    await inner.init();
    _opened = true;
  }

  /// Holds [init] open (a hung keystore or file open).
  Completer<void>? initGate;

  /// Like the io backend: every call before a successful [init] throws.
  bool requireInit = false;
  bool _opened = false;

  /// Holds [deleteMessages] (the first step of a purge).
  Completer<void>? deleteMessagesGate;

  void _checkOpen() {
    if (requireInit && !_opened) {
      throw StateError('Chat cache backend not initialized.');
    }
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    if (failReset) throw StateError('scripted: store could not be deleted');
    await inner.clearAll();
  }

  /// Makes [reset] fail, as a store that cannot be deleted right now.
  bool failReset = false;
  int wipeRequests = 0;

  @override
  Future<void> requestWipeOnNextOpen() async {
    wipeRequests++;
  }

  Future<T> _read<T>(String name, Future<T> Function() run) {
    _checkOpen();
    if (throwOnReads || failOnly.contains(name)) {
      throw StateError('SQLITE_IOERR: disk I/O error');
    }
    return run();
  }

  Future<void> _write(String name, Future<void> Function() run) {
    _checkOpen();
    if (throwOnWrites || failOnly.contains(name)) {
      throw StateError('SQLITE_FULL: database or disk is full');
    }
    return run();
  }

  @override
  Future<String?> readMessages(String userId, String relationshipId) =>
      _read('readMessages', () => inner.readMessages(userId, relationshipId));
  @override
  Future<void> writeMessages(
    String userId,
    String relationshipId,
    String payload,
  ) => _write(
    'writeMessages',
    () => inner.writeMessages(userId, relationshipId, payload),
  );
  @override
  Future<void> deleteMessages(String userId, String relationshipId) =>
      _write('deleteMessages', () async {
        final gate = deleteMessagesGate;
        if (gate != null) await gate.future;
        await inner.deleteMessages(userId, relationshipId);
      });
  @override
  Future<String?> readConversations(String userId) =>
      _read('readConversations', () => inner.readConversations(userId));
  @override
  Future<void> writeConversations(String userId, String payload) => _write(
    'writeConversations',
    () => inner.writeConversations(userId, payload),
  );
  @override
  Future<List<String>> readOutbox(String userId, {String? relationshipId}) =>
      _read(
        'readOutbox',
        () => inner.readOutbox(userId, relationshipId: relationshipId),
      );
  @override
  Future<void> putOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
    String payload,
    int createdAtMillis,
  ) => _write(
    'putOutbox',
    () => inner.putOutbox(
      userId,
      relationshipId,
      clientMessageId,
      payload,
      createdAtMillis,
    ),
  );
  @override
  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) => _write(
    'removeOutbox',
    () => inner.removeOutbox(userId, relationshipId, clientMessageId),
  );
  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String userId,
    int limit,
  ) => _read('oldestOutbox', () => inner.oldestOutbox(userId, limit));
  @override
  Future<void> purgeOutboxForRelationship(
    String userId,
    String relationshipId,
  ) => _write(
    'purgeOutboxForRelationship',
    () => inner.purgeOutboxForRelationship(userId, relationshipId),
  );
  @override
  Future<String?> readDraft(String userId, String relationshipId) =>
      _read('readDraft', () => inner.readDraft(userId, relationshipId));
  @override
  Future<void> writeDraft(String userId, String relationshipId, String draft) =>
      _write(
        'writeDraft',
        () => inner.writeDraft(userId, relationshipId, draft),
      );
  @override
  Future<void> clearDraft(String userId, String relationshipId) =>
      _write('clearDraft', () => inner.clearDraft(userId, relationshipId));
  @override
  Future<({int micros, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  ) => _read(
    'readSyncCursor',
    () => inner.readSyncCursor(userId, relationshipId),
  );
  @override
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    int micros,
    String? id,
  ) => _write(
    'writeSyncCursor',
    () => inner.writeSyncCursor(userId, relationshipId, micros, id),
  );
  @override
  Future<void> clearSyncCursor(String userId, String relationshipId) => _write(
    'clearSyncCursor',
    () => inner.clearSyncCursor(userId, relationshipId),
  );
  @override
  Future<void> clearAll() => _write('clearAll', inner.clearAll);
}

void main() {
  // Every failure path logs by design; keep the test output to results.
  setUp(() {
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = previous);
  });

  PendingSend pending(String id, {DateTime? createdAt}) => PendingSend(
    clientMessageId: id,
    relationshipId: 'rel-1',
    senderId: 'user-a',
    text: 'queued',
    createdAt: createdAt ?? DateTime.now(),
  );

  /// A raw row in the backend under the service, to check what survives.
  Future<void> seedRawOutbox(_FlakyBackend backend) =>
      backend.inner.putOutbox('user-a', 'rel-1', 'kept', 'raw-row', 1);

  test('a corrupt database is rebuilt once and the cache then works', () async {
    final backend = _FlakyBackend(initFailuresLeft: 1);
    final cache = ChatCacheService.forTesting(backend: backend);

    await cache.init(); // must not throw

    expect(backend.resetCalls, 1);
    expect(cache.isDegraded, isFalse);
    await cache.putOutbox('user-a', pending('q1'));
    expect((await cache.readOutbox('user-a')).single.clientMessageId, 'q1');
  });

  test(
    'a database that cannot be rebuilt falls back to memory for the session',
    () async {
      final backend = _FlakyBackend(initFailuresLeft: 5);
      final cache = ChatCacheService.forTesting(backend: backend);

      await cache.init(); // must not throw

      expect(backend.resetCalls, 1);
      expect(cache.isDegraded, isTrue);
      await cache.putOutbox('user-a', pending('q1'));
      expect(
        (await cache.readOutbox('user-a')).single.clientMessageId,
        'q1',
        reason: 'the queue still works within the session',
      );
    },
  );

  test(
    'a busy/locked store is retried, not deleted: the queue survives',
    () async {
      final backend = _FlakyBackend(
        initFailuresLeft: 2,
        initFailureKind: ChatCacheFailureKind.busy,
      );
      await seedRawOutbox(backend);
      final cache = ChatCacheService.forTesting(backend: backend);

      final watch = Stopwatch()..start();
      await cache.init();

      expect(backend.initCalls, 3);
      expect(backend.resetCalls, 0);
      expect(cache.isDegraded, isFalse);
      expect(await backend.inner.readOutbox('user-a'), ['raw-row']);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
    },
  );

  test(
    'a store that stays busy runs the session on memory and keeps its file',
    () async {
      final backend = _FlakyBackend(
        initFailuresLeft: 99,
        initFailureKind: ChatCacheFailureKind.busy,
      );
      await seedRawOutbox(backend);
      final cache = ChatCacheService.forTesting(backend: backend);

      await cache.init();

      expect(backend.initCalls, 3, reason: 'bounded: three tries');
      expect(backend.resetCalls, 0);
      expect(cache.isDegraded, isTrue);
      expect(await backend.inner.readOutbox('user-a'), ['raw-row']);
    },
  );

  test(
    'a non-corruption open or upgrade failure falls back to memory without deleting',
    () async {
      for (final kind in <ChatCacheFailureKind?>[
        ChatCacheFailureKind.other,
        null, // an unclassified error (e.g. the platform directory call)
      ]) {
        final backend = _FlakyBackend(
          initFailuresLeft: 1,
          initFailureKind: kind,
        );
        await seedRawOutbox(backend);
        final cache = ChatCacheService.forTesting(backend: backend);

        await cache.init();

        expect(backend.initCalls, 1, reason: '$kind: no retry');
        expect(backend.resetCalls, 0, reason: '$kind: never deleted');
        expect(cache.isDegraded, isTrue);
        expect(await backend.inner.readOutbox('user-a'), ['raw-row']);
        await cache.putOutbox('user-a', pending('q1'));
        expect(
          (await cache.readOutbox('user-a')).single.clientMessageId,
          'q1',
          reason: 'the session queue runs on memory',
        );
      }
    },
  );

  test('busy that turns out to be corruption is rebuilt', () async {
    final backend = _FlakyBackend(
      initFailuresLeft: 2,
      initFailureKinds: [
        ChatCacheFailureKind.busy,
        ChatCacheFailureKind.corrupt,
      ],
    );
    final cache = ChatCacheService.forTesting(backend: backend);

    await cache.init();

    expect(backend.resetCalls, 1);
    expect(cache.isDegraded, isFalse);
  });

  group('no key (keystore unreadable or slower than 3 s)', () {
    test('putOutbox throws instead of pretending the row was queued', () async {
      final backend = memBackend();
      final cache = ChatCacheService.forTesting(
        backend: backend,
        withoutCipher: true,
      );

      await expectLater(
        cache.putOutbox('user-a', pending('q1')),
        throwsStateError,
      );
      expect(await backend.readOutbox('user-a'), isEmpty);
    });

    test('no sync cursor is persisted without the rows it covers', () async {
      final backend = memBackend();
      final cache = ChatCacheService.forTesting(
        backend: backend,
        withoutCipher: true,
      );

      await cache.writeSyncCursor('user-a', 'rel-1', DateTime.now(), id: 'm');

      expect(await backend.readSyncCursor('user-a', 'rel-1'), isNull);
    });

    test(
      'a send ends failed and retryable, never queued with no row',
      () async {
        final backend = memBackend();
        final cache = ChatCacheService.forTesting(
          backend: backend,
          withoutCipher: true,
        );
        final repo = FakeChatRepository(currentUserId: 'user-a');
        repo.sendErrorQueue.add(const SocketException('offline'));
        final container = buildChatContainer(
          repository: repo,
          userId: 'user-a',
          cache: cache,
        );
        addTearDown(container.dispose);
        final convo = activeConversation('rel-1');
        repo.conversationOverride = convo;
        final controller = container.read(
          chatControllerProvider(convo).notifier,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        await controller.sendMessage('no key');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final bubble =
            container.read(chatControllerProvider(convo)).messages.single;
        expect(bubble.status, MessageStatus.failed);
        expect(await backend.readOutbox('user-a'), isEmpty);

        await controller.retryMessage(bubble);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['no key']);
        expect(
          container.read(chatControllerProvider(convo)).messages.single.status,
          MessageStatus.sent,
        );
      },
    );
  });

  test(
    'a runtime read or write failure in the read cache is a cache miss, not an exception',
    () async {
      final backend = _FlakyBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();

      backend.throwOnReads = true;
      expect(await cache.readMessages('user-a', 'rel-1'), isEmpty);
      expect(await cache.readConversations('user-a'), isEmpty);
      expect(await cache.readDraft('user-a', 'rel-1'), '');
      expect(await cache.readSyncCursor('user-a', 'rel-1'), isNull);

      backend.throwOnReads = false;
      backend.throwOnWrites = true;
      // None of these may throw.
      await cache.writeDraft('user-a', 'rel-1', 'x');
      await cache.writeDraft('user-a', 'rel-1', '');
      await cache.clearDraft('user-a', 'rel-1');
      await cache.writeConversations('user-a', const []);
      await cache.writeSyncCursor('user-a', 'rel-1', DateTime.now(), id: 'm');
      await cache.purgeRelationship('user-a', 'rel-1');
      await cache.clearAll();
    },
  );

  test('the outbox and the history write keep their failure signal: the engine '
      'and the cursor rule are built on it', () async {
    // putOutbox throwing is how a send learns no queue row backs it (M1:
    // send once directly, else turn failed). readOutbox throwing is how a
    // flush arms its retry (M2). removeOutbox throwing keeps a dismissed
    // bubble from silently staying queued. writeMessages throwing keeps
    // the sync cursor from being persisted ahead of its rows (R2-4).
    final backend = _FlakyBackend();
    final cache = ChatCacheService.forTesting(backend: backend);
    await cache.init();
    await cache.putOutbox('user-a', pending('q1'));

    backend.throwOnReads = true;
    await expectLater(cache.readOutbox('user-a'), throwsStateError);

    backend.throwOnReads = false;
    backend.throwOnWrites = true;
    await expectLater(
      cache.putOutbox('user-a', pending('q2')),
      throwsStateError,
    );
    await expectLater(
      cache.removeOutbox('user-a', 'rel-1', 'q1'),
      throwsStateError,
    );
    await expectLater(
      cache.writeMessages('user-a', 'rel-1', const []),
      throwsStateError,
    );
  });

  test(
    'a failed overflow trim does not report the landed put as failed',
    () async {
      final backend = _FlakyBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();
      final base = DateTime(2026, 10, 19);
      for (var i = 0; i < 100; i++) {
        await cache.putOutbox(
          'user-a',
          pending('q$i', createdAt: base.add(Duration(seconds: i))),
        );
      }

      backend.failOnly.add('oldestOutbox');
      // Row 101 lands; only the trim behind it fails. Reporting that as a
      // failed put would make the controller send it directly as well.
      await cache.putOutbox(
        'user-a',
        pending('q100', createdAt: base.add(const Duration(seconds: 100))),
      );

      final queue = await cache.readOutbox('user-a');
      expect(queue, hasLength(101));
      expect(queue.last.clientMessageId, 'q100');
    },
  );

  test('a purge runs every step even when one of them fails', () async {
    final backend = _FlakyBackend();
    final cache = ChatCacheService.forTesting(backend: backend);
    await cache.init();
    await cache.putOutbox('user-a', pending('q1'));
    await cache.writeDraft('user-a', 'rel-1', 'draft');
    await cache.writeSyncCursor('user-a', 'rel-1', DateTime.now(), id: 'm');

    backend.failOnly.add('deleteMessages');
    await cache.purgeRelationship('user-a', 'rel-1'); // must not throw

    expect(await cache.readOutbox('user-a'), isEmpty);
    expect(await cache.readDraft('user-a', 'rel-1'), '');
    expect(await cache.readSyncCursor('user-a', 'rel-1'), isNull);
  });

  test(
    'a chat opened over a broken cache still loads from the server',
    () async {
      final backend = _FlakyBackend()..throwOnReads = true;
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'from the server',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        cache: cache,
      );
      addTearDown(container.dispose);
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;

      container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(chatControllerProvider(convo));
      expect(state.isLoading, isFalse);
      expect(state.messages.map((m) => m.id), ['inc-1']);
    },
  );

  group('a degraded session still reaches the disk store it left behind', () {
    Future<(_FlakyBackend, ChatCacheService)> degraded({
      int initFailures = 1,
    }) async {
      final backend = _FlakyBackend(
        initFailuresLeft: initFailures,
        initFailureKind: ChatCacheFailureKind.other,
      );
      await seedRawOutbox(backend);
      await backend.inner.writeMessages('user-a', 'rel-1', 'disk-history');
      await backend.inner.writeMessages('user-a', 'rel-2', 'other-history');
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();
      expect(cache.isDegraded, isTrue);
      return (backend, cache);
    }

    test('sign-out (clearAll) wipes the disk store too', () async {
      final (backend, cache) = await degraded();

      await cache.clearAll();

      expect(backend.resetCalls, 1);
      expect(backend.wipeRequests, 0);
      expect(await backend.inner.readOutbox('user-a'), isEmpty);
      expect(await backend.inner.readMessages('user-a', 'rel-1'), isNull);
    });

    test(
      'a disk store that cannot be deleted now is marked for wipe on next open',
      () async {
        final (backend, cache) = await degraded();
        backend.failReset = true;

        await cache.clearAll(); // must not throw

        expect(backend.resetCalls, 1);
        expect(backend.wipeRequests, 1);
      },
    );

    test('a purge reaches the disk store when it opens now', () async {
      final (backend, cache) = await degraded(); // second open succeeds

      await cache.purgeRelationship('user-a', 'rel-1');

      expect(await backend.inner.readOutbox('user-a'), isEmpty);
      expect(await backend.inner.readMessages('user-a', 'rel-1'), isNull);
      expect(
        await backend.inner.readMessages('user-a', 'rel-2'),
        'other-history',
        reason: 'only the purged relationship',
      );
    });

    test(
      'a purge while the disk store still will not open never throws',
      () async {
        final (backend, cache) = await degraded(initFailures: 99);

        await cache.purgeRelationship('user-a', 'rel-1'); // must not throw

        expect(await backend.inner.readOutbox('user-a'), ['raw-row']);
      },
    );
  });

  test(
    'a healthy store whose rows cannot be deleted at sign-out is deleted and reopened',
    () async {
      final backend = _FlakyBackend();
      await seedRawOutbox(backend);
      final cache = ChatCacheService.forTesting(backend: backend);
      await cache.init();
      backend.failOnly.add('clearAll');

      await cache.clearAll(); // must not throw

      expect(backend.resetCalls, 1);
      expect(backend.initCalls, 2, reason: 'a fresh store for the session');
      expect(cache.isDegraded, isFalse);
      expect(await backend.inner.readOutbox('user-a'), isEmpty);
    },
  );

  group('a purge always runs, even when the queue cannot be read (I2)', () {
    Future<
      ({
        ScriptedCacheBackend backend,
        ChatCacheService cache,
        ChatController controller,
        ChatState Function() state,
        FakeChatRepository repo,
        ProviderContainer container,
      })
    >
    bootOpen() async {
      final backend = ScriptedCacheBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'inc-1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'from the server',
        createdAt: DateTime.now(),
      );
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        cache: cache,
      );
      addTearDown(container.dispose);
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cache.writeDraft('user-a', 'rel-1', 'unsent words');
      expect(
        await cache.readMessages('user-a', 'rel-1'),
        isNotEmpty,
        reason: 'the open persisted history',
      );
      return (
        backend: backend,
        cache: cache,
        controller: controller,
        state: () => container.read(chatControllerProvider(convo)),
        repo: repo,
        container: container,
      );
    }

    test('account change: purge runs and the screen is cleared', () async {
      final b = await bootOpen();
      expect(b.state().messages, isNotEmpty);
      b.backend.armReadOutboxFailures((_) => true);

      // Completes normally: no error escapes the (unawaited in production)
      // account-change handler.
      await b.controller.debugHandleAccountChange('user-a');

      expect(b.state().messages, isEmpty);
      expect(await b.cache.readMessages('user-a', 'rel-1'), isEmpty);
      expect(await b.cache.readDraft('user-a', 'rel-1'), '');
    });

    test('archive: purge runs and the screen is cleared', () async {
      final b = await bootOpen();
      b.backend.armReadOutboxFailures((_) => true);

      b.repo.conversationOverride = activeConversation(
        'rel-1',
      ).copyWith(availability: ConversationAvailability.archived);
      b.container.read(conversationsRefreshProvider.notifier).state++;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        b.state().conversation.availability,
        ConversationAvailability.archived,
      );
      expect(b.state().messages, isEmpty);
      expect(await b.cache.readMessages('user-a', 'rel-1'), isEmpty);
      expect(await b.cache.readDraft('user-a', 'rel-1'), '');
    });
  });

  test(
    'sign-out never hangs on an init still running, and starts no second recovery',
    () async {
      final backend =
          _FlakyBackend()
            ..requireInit = true
            ..initGate = Completer<void>();
      await seedRawOutbox(backend);
      final cache = ChatCacheService.forTesting(
        backend: backend,
        clearAllBound: const Duration(milliseconds: 200),
      );
      // main()'s 8 s bound fired: init is still running in the background.
      unawaited(cache.init());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final watch = Stopwatch()..start();
      await cache.clearAll().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('sign-out hung on the cache'),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(
        backend.wipeRequests,
        greaterThanOrEqualTo(1),
        reason: 'the unfinished wipe is owed to the next open',
      );

      // Single flight: neither a second init nor a second sign-out starts
      // another open or recovery.
      unawaited(cache.init());
      await cache.clearAll().timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('second sign-out hung'),
      );
      expect(backend.initCalls, 1);
      expect(backend.resetCalls, 0);

      // The open finishes: the one pending clear runs on the opened store.
      backend.initGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.initCalls, 1);
      expect(backend.resetCalls, 0);
      expect(cache.isDegraded, isFalse);
      expect(await backend.inner.readOutbox('user-a'), isEmpty);
    },
  );

  group('a controller disposed while a refresh purges sets no state', () {
    Future<void> run(
      FakeChatRepository Function(FakeChatRepository) arrange,
    ) async {
      final backend = _FlakyBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        cache: cache,
      );
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      arrange(repo);
      backend.deleteMessagesGate = Completer<void>();
      final refresh = controller.debugRefreshConversation();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      container.dispose(); // the screen closes mid-purge
      backend.deleteMessagesGate!.complete();

      await expectLater(refresh, completes);
    }

    test('archived branch', () async {
      await run(
        (repo) =>
            repo
              ..conversationOverride = activeConversation(
                'rel-1',
              ).copyWith(availability: ConversationAvailability.archived),
      );
    });

    test('conversation gone (null) branch', () async {
      await run((repo) => repo..returnNullConversation = true);
    });
  });

  test('main() cannot be held by cache init', () {
    // Source-level: main is not unit-testable. The init call must be
    // bounded and guarded so a hung keystore or a locked file never holds
    // the splash (Spec 16).
    final source = File('lib/main.dart').readAsStringSync();
    final at = source.indexOf('chatCache.init()');
    expect(at, greaterThan(0));
    final around = source.substring(at - 80, at + 160);
    expect(around, contains('.timeout('));
    expect(around, contains('catch'));
  });
}
