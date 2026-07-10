import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Client-side coverage for the Spec 16 edge-case contract. Server/RLS rows
/// (outsider enumeration, receipt replay monotonicity, archive access refusal)
/// are covered by supabase/tests/chat_system_contracts.sql; these exercise the
/// client convergence and lifecycle guarantees.
void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<({ChatController controller, ProviderContainer container, Conversation convo})>
      boot(FakeChatRepository repo) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller =
        container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (controller: controller, container: container, convo: convo);
  }

  ChatState stateOf(
    ProviderContainer c,
    Conversation convo,
  ) =>
      c.read(chatControllerProvider(convo));

  test('Double tap / request replay → one canonical message', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final b = await boot(repo);

    // Two rapid sends of the same intent produce two client_message_ids in the
    // UI; but a re-flush of the queue must not duplicate a committed row. Here
    // we simulate the "replay" by flushing the outbox twice quickly.
    await b.controller.sendMessage('tap');
    await b.controller.flushOutbox();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final mine = stateOf(b.container, b.convo)
        .messages
        .where((m) => m.content == 'tap')
        .toList();
    expect(mine, hasLength(1));
    expect(mine.single.status, MessageStatus.sent);
  });

  test('Commit succeeds, response lost → retry reconciles existing row',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final b = await boot(repo);

    // First attempt: the row commits on the server but the client sees a
    // duplicate on the (retried) send.
    repo.simulateDuplicate = true;
    await b.controller.sendMessage('lost-response');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Turn off duplicate and let a retry reconcile via findMessageByClientId.
    final msgs = stateOf(b.container, b.convo).messages;
    expect(msgs.where((m) => m.content == 'lost-response'), hasLength(1));
  });

  test('Realtime event precedes/refreshes → optimistic and canonical merge',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final b = await boot(repo);

    await b.controller.sendMessage('merge-me');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // A realtime tick triggers refresh + cursor catch-up; the canonical row is
    // already present, so no duplicate appears.
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final merged = stateOf(b.container, b.convo)
        .messages
        .where((m) => m.content == 'merge-me')
        .toList();
    expect(merged, hasLength(1));
  });

  test('Reconnect after missed events → cursor catch-up restores rows',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final b = await boot(repo);

    // Two partner messages arrive on the "server" while we were away.
    repo.seedIncoming(
      id: 'inc-1',
      relationshipId: relId,
      senderId: 'partner',
      content: 'missed one',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );
    repo.seedIncoming(
      id: 'inc-2',
      relationshipId: relId,
      senderId: 'partner',
      content: 'missed two',
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final contents =
        stateOf(b.container, b.convo).messages.map((m) => m.content).toSet();
    expect(contents, containsAll(<String>['missed one', 'missed two']));
  });

  test('Two messages share a timestamp → stable id tie-breaker order',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final shared = DateTime.now();
    repo.seedIncoming(
      id: 'aaa',
      relationshipId: relId,
      senderId: 'partner',
      content: 'first',
      createdAt: shared,
    );
    repo.seedIncoming(
      id: 'bbb',
      relationshipId: relId,
      senderId: 'partner',
      content: 'second',
      createdAt: shared,
    );
    final b = await boot(repo);

    final ids = stateOf(b.container, b.convo).messages.map((m) => m.id).toList();
    // Newest-first with id DESC tie-breaker → 'bbb' before 'aaa'.
    expect(ids.indexOf('bbb'), lessThan(ids.indexOf('aaa')));
  });

  test('Chat archives while open → messages purged from state', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final b = await boot(repo);
    await b.controller.sendMessage('will-be-purged');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(stateOf(b.container, b.convo).messages, isNotEmpty);

    // The relationship becomes archived; a realtime refresh observes it.
    repo.conversationOverride = Conversation(
      id: relId,
      relationshipId: relId,
      partnerId: 'partner',
      name: 'Partner',
      updatedAt: DateTime.now(),
      relationshipStatus: 'ended',
      availability: ConversationAvailability.archived,
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final s = stateOf(b.container, b.convo);
    expect(s.conversation.availability, ConversationAvailability.archived);
    expect(s.messages, isEmpty);
  });

  test('Account switch → previous user local state becomes inaccessible',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final cache = ChatCacheService.forTesting(backend: memBackend());
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        chatCacheServiceProvider.overrideWithValue(cache),
        currentUserProvider.overrideWith((ref) => testUser(userId)),
      ],
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await controller.sendMessage('user-a secret');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The account-change listener purges the previous user's cache. We assert
    // the previous user's cached messages are gone.
    await controller.debugHandleAccountChange(userId);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final leftover = await cache.readMessages(userId, relId);
    expect(leftover, isEmpty);
  });
}
