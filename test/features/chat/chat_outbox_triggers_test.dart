import 'dart:async';
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_outbox_drainer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation, this.cache);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  final ChatCacheService cache;
  ChatState get state => container.read(chatControllerProvider(conversation));
  Future<List<PendingSend>> outbox() =>
      cache.readOutbox('user-a', relationshipId: 'rel-1');
}

void main() {
  // The drainer listens to app lifecycle, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-a';
  const relId = 'rel-1';

  // The list's one cold-start cache paint is process-wide; go to the fake
  // repository every time so test order does not matter.
  setUp(() => ConversationsNotifier.debugServedCache = true);

  PendingSend queuedText(
    String id,
    String text, {
    String relationshipId = relId,
  }) => PendingSend(
    clientMessageId: id,
    relationshipId: relationshipId,
    senderId: userId,
    text: text,
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
  );

  Future<_Booted> boot(
    FakeChatRepository repo, {
    ChatCacheService? cache,
    Stream<bool>? connectivity,
    List<Override> extraOverrides = const [],
  }) async {
    final effectiveCache =
        cache ?? ChatCacheService.forTesting(backend: memBackend());
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: effectiveCache,
      connectivity: connectivity,
      extraOverrides: extraOverrides,
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo, effectiveCache);
  }

  test('opening a chat offline still restores and attempts the previous '
      'session\'s queue, and the first resubscribe sends it (#1)', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final cache = ChatCacheService.forTesting(backend: memBackend());
    await cache.putOutbox(userId, queuedText('q1', 'typed in the tunnel'));
    repo.getConversationError = const SocketException('offline');
    repo.sendErrorQueue.add(const SocketException('offline'));

    final b = await boot(repo, cache: cache);

    expect(b.state.messages.single.status, MessageStatus.queued);
    expect(
      repo.sendCallCount,
      1,
      reason: 'the open-time flush must run although the header refresh threw',
    );
    expect(b.state.isLoading, isFalse);

    repo.getConversationError = null;
    repo.emitRealtime(); // the channel (re)subscribed: the network is back
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(b.state.messages.single.status, MessageStatus.sent);
    expect(await b.outbox(), isEmpty);
  });

  test('a delivered-mark that throws at open cannot skip the open-time '
      'flush, and nothing escapes the open uncaught (#1)', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final cache = ChatCacheService.forTesting(backend: memBackend());
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'not yet marked delivered',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );
    repo.markDeliveredError = const SocketException('dropped');
    await cache.putOutbox(userId, queuedText('q1', 'typed in the tunnel'));

    final b = await boot(repo, cache: cache);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(repo.markDeliveredCalls, isNotEmpty);
    expect(repo.sentContents, ['typed in the tunnel']);
    expect(await b.outbox(), isEmpty);
  });

  test('a failed cold first load stays visible through later state writes, '
      'and a successful retry clears it', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    repo.getMessagesError = const SocketException('offline');
    final b = await boot(repo);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final copy =
        ChatError.from(const SocketException('offline')).toLoadMessage();
    // The header, pins and stars all wrote state after the failed load;
    // each write clears `error` by design. The failure must outlive them.
    expect(b.state.isLoading, isFalse);
    expect(b.state.messages, isEmpty);
    expect(b.state.loadFailure, copy);
    expect(b.state.bannerErrorFor(isOnline: true), copy);

    // An unrelated later write (a header refresh) still keeps it.
    b.container.read(conversationsRefreshProvider.notifier).state++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(b.state.bannerErrorFor(isOnline: true), copy);

    repo.getMessagesError = null;
    await b.controller.loadMessages();
    expect(b.state.loadFailure, isNull);
    expect(b.state.bannerErrorFor(isOnline: true), isNull);
  });

  test('connectivity coming back nudges the socket, resyncs and flushes '
      'at once', () async {
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final repo = FakeChatRepository(currentUserId: userId);
    repo.sendErrorQueue.add(const SocketException('offline'));
    final b = await boot(repo, connectivity: connectivity.stream);

    await b.controller.sendMessage('waiting');
    expect(b.state.messages.single.status, MessageStatus.queued);
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'sent while you were out of range',
      createdAt: DateTime.now(),
    );

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(repo.ensureRealtimeConnectedCalls, 1);
    expect(b.state.messages.map((m) => m.id), contains('inc-1'));
    expect(
      b.state.messages.firstWhere((m) => m.content == 'waiting').status,
      MessageStatus.sent,
    );
  });

  test('coming back to the foreground flushes and resyncs', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    repo.sendErrorQueue.add(const SocketException('offline'));
    final b = await boot(repo);
    await b.controller.sendMessage('waiting');
    expect(b.state.messages.single.status, MessageStatus.queued);

    b.controller.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(b.state.messages.single.status, MessageStatus.sent);
  });

  test('an insert the network black-holes is bounded: the row goes back to '
      'the queue, the next trigger sends it, and the late commit reconciles '
      'to one message (fix I1)', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    repo.enforceUniqueClientId = true;
    // The server takes the first insert; its answer never arrives.
    final lost = Completer<void>();
    addTearDown(() {
      if (!lost.isCompleted) lost.complete();
    });
    repo.sendResponseGates.add(lost);
    final b = await boot(
      repo,
      extraOverrides: [
        chatConfigProvider.overrideWithValue(
          const ChatConfig(networkTimeout: Duration(milliseconds: 100)),
        ),
      ],
    );

    unawaited(b.controller.sendMessage('into the void'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(b.state.messages.single.status, MessageStatus.queued);
    expect(await b.outbox(), hasLength(1));

    // Any later trigger now reaches the queue (it used to find the flush
    // still busy and only leave a note for a pass that never came).
    b.controller.onAppResumed();
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(repo.sendCallCount, 2);
    expect(repo.sentContents, ['into the void']);
    final mine = b.state.messages.where((m) => m.content == 'into the void');
    expect(mine, hasLength(1));
    expect(mine.single.status, MessageStatus.sent);
    expect(mine.single.id, startsWith('srv-'));
    expect(await b.outbox(), isEmpty);
  });

  group('drainer (chat not open)', () {
    test(
      'drains on its own at startup when someone is signed in (fix I2)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [activeConversation(relId)];
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.putOutbox(userId, queuedText('q1', 'from last night'));
        final container = buildChatContainer(
          repository: repo,
          userId: userId,
          cache: cache,
        );
        addTearDown(container.dispose);

        // No resume, no connectivity transition: just the app starting.
        container.read(chatOutboxDrainerProvider);
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(repo.sentContents, ['from last night']);
        expect(await cache.readOutbox(userId), isEmpty);
      },
    );

    test('drains when someone signs in (fix I2)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [activeConversation(relId)];
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, queuedText('q1', 'before sign-out'));
      final signedIn = StateProvider<User?>((ref) => null);
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        userSwitch: signedIn,
      );
      addTearDown(container.dispose);

      container.read(chatOutboxDrainerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.sendCallCount, 0);

      container.read(signedIn.notifier).state = testUser(userId);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(repo.sentContents, ['before sign-out']);
    });

    test(
      'skips an archived relationship without waking its chat (fix M2)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final archived = activeConversation(
          relId,
        ).copyWith(availability: ConversationAvailability.archived);
        repo.conversations = [archived];
        repo.conversationOverride = archived;
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.putOutbox(userId, queuedText('q1', 'too late'));
        final container = buildChatContainer(
          repository: repo,
          userId: userId,
          cache: cache,
        );
        addTearDown(container.dispose);

        await container.read(chatOutboxDrainerProvider).drain();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(repo.sendCallCount, 0);
        expect(
          repo.getConversationCalls,
          0,
          reason: 'a woken controller refreshes its header on open',
        );
      },
    );

    test('waits for the woken chat to finish opening before it flushes '
        '(fix M4)', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [activeConversation(relId)];
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, queuedText('q1', 'from the car'));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);
      final open = Completer<void>();
      repo.getMessagesGate = open;

      final drain = container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        repo.sendCallCount,
        0,
        reason: 'the open (outbox restore, first page) has not finished',
      );

      open.complete();
      await drain;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.sentContents, ['from the car']);
      final state = container.read(
        chatControllerProvider(activeConversation(relId)),
      );
      final mine = state.messages.where((m) => m.content == 'from the car');
      expect(mine, hasLength(1));
      expect(mine.single.id, startsWith('srv-'));
    });

    test(
      'sends queued messages for a relationship whose chat is closed',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.conversations = [activeConversation(relId)];
        repo.conversationOverride = activeConversation(relId);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.putOutbox(userId, queuedText('q1', 'from the car'));
        await cache.putOutbox(userId, queuedText('q2', 'and this one'));
        final container = buildChatContainer(
          repository: repo,
          userId: userId,
          cache: cache,
        );
        addTearDown(container.dispose);

        await container.read(chatOutboxDrainerProvider).drain();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(repo.sentContents, ['from the car', 'and this one']);
        expect(await cache.readOutbox(userId), isEmpty);
      },
    );

    test(
      'is a no-op when signed out or when the relationship is gone',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.putOutbox(
          userId,
          queuedText('q1', 'orphaned', relationshipId: 'rel-gone'),
        );

        // Signed out.
        final signedOut = ProviderContainer(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            chatCacheServiceProvider.overrideWithValue(cache),
            currentUserProvider.overrideWithValue(null),
            chatConnectivityProvider.overrideWith(
              (ref) => Stream<bool>.value(true),
            ),
          ],
        );
        addTearDown(signedOut.dispose);
        await signedOut.read(chatOutboxDrainerProvider).drain();
        expect(repo.sendCallCount, 0);

        // Signed in, but the queued relationship is not in the list.
        repo.conversations = [activeConversation(relId)];
        final container = buildChatContainer(
          repository: repo,
          userId: userId,
          cache: cache,
        );
        addTearDown(container.dispose);
        await container.read(chatOutboxDrainerProvider).drain();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(repo.sendCallCount, 0);
      },
    );

    test('flushes through the open chat\'s own controller instead of waking '
        'a second one', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      // The list hands back a different instance than the one the screen
      // opened with; the family keys on the relationship (Conversation ==),
      // so the drainer must land on the controller already running.
      repo.conversations = [activeConversation(relId)];
      repo.sendErrorQueue.add(const SocketException('offline'));
      final b = await boot(repo);
      final keepOpen = b.container.listen(
        chatControllerProvider(b.conversation),
        (_, __) {},
      );
      addTearDown(keepOpen.close);
      await b.controller.sendMessage('waiting');
      expect(b.state.messages.single.status, MessageStatus.queued);
      final loadsBefore = repo.getMessagesCalls;

      await b.container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(b.state.messages.single.status, MessageStatus.sent);
      expect(
        repo.getMessagesCalls,
        loadsBefore,
        reason: 'a second controller would have run its own open-time load',
      );
    });

    test('never drains a queue across an account change', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.conversations = [activeConversation(relId)];
      final gate = Completer<void>();
      repo.getConversationsGates.add(gate);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(userId, queuedText('q1', 'user a only'));
      final signedIn = StateProvider<User?>((ref) => testUser(userId));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        userSwitch: signedIn,
      );
      addTearDown(container.dispose);

      final drain = container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(signedIn.notifier).state = testUser('user-b');
      gate.complete();
      await drain;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repo.sendCallCount, 0);
      expect(await cache.readOutbox(userId), hasLength(1));
    });
  });
}
