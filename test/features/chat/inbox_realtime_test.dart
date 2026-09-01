import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

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
  test('the conversation list subscribes to its relationships', () async {
    // The list was fetched once at build and never again: a message
    // arriving while the user sat on the conversations screen updated
    // neither the preview nor the unread badge until they pulled to
    // refresh or restarted the app. The chat screen had a subscription;
    // the list had none.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1'), _convo('rel-2')];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);

    expect(
      repo.inboxSubscriptions, isNotEmpty,
      reason: 'the list never subscribed, so nothing can refresh it',
    );
    expect(
      repo.inboxSubscriptions.last..sort(),
      containsAll(<String>['rel-1', 'rel-2']),
      reason: 'every relationship in the list must be watched',
    );
  });

  test('an inbox event refreshes the unread count in place', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1')];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    final initial = await container.read(conversationsProvider.future);
    expect(initial.single.unreadCount, 0);

    // The partner sends a message: the server row now reads 1 unread.
    repo.conversations = [_convo('rel-1', unread: 1)];
    repo.inboxEvents.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final refreshed = container.read(conversationsProvider).value;
    expect(
      refreshed?.single.unreadCount, 1,
      reason: 'the badge must update without a restart or pull-to-refresh',
    );
  });

  test('a refresh does not flash the list away', () async {
    // invalidate() would rebuild through AsyncLoading, blanking the list
    // under the user for something as ordinary as a message arriving.
    // The refresh must land as data, never as loading.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1')];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);

    final states = <bool>[];
    container.listen(conversationsProvider, (_, next) {
      states.add(next.isLoading);
    });

    repo.conversations = [_convo('rel-1', unread: 3)];
    repo.inboxEvents.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      states.contains(true), isFalse,
      reason: 'a realtime refresh must not surface a loading state',
    );
    expect(container.read(conversationsProvider).value?.single.unreadCount, 3);
  });

  test('the subscription is not rebuilt on every event', () async {
    // Each refresh re-enters the subscribe path. Without a guard on the
    // id set, the channel would tear down and rebuild for every message
    // that arrived -- churning a websocket per delivered event.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1')];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);
    final afterBuild = repo.inboxSubscriptions.length;

    for (var i = 0; i < 3; i++) {
      repo.inboxEvents.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      repo.inboxSubscriptions.length, afterBuild,
      reason: 'the same relationships must not resubscribe on each event',
    );
  });

  test('the list reports delivery for messages the device now holds', () async {
    // The notification worker used to stamp delivered_at when it QUEUED a
    // push -- which happens whether the recipient's phone is reachable or
    // switched off, so a message sent to someone with no data showed the
    // sender two checks while it sat in a queue nobody had received.
    //
    // Delivery is now claimed only where it is observed. The conversation
    // list holding an unread partner message IS that observation, and it
    // must not wait for the chat to be opened -- that is when READ is
    // recorded, and the two would collapse into one state.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1', unread: 2)];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(
      repo.relationshipDeliveredCalls, contains('rel-1'),
      reason: 'a held-but-unread message is delivered, and must say so',
    );
  });

  test('a read conversation is not re-reported as delivered', () async {
    // Nothing to deliver means no call: otherwise every list refresh would
    // fire an RPC per conversation forever.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.conversations = [_convo('rel-1')];

    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repo.relationshipDeliveredCalls, isEmpty);
  });
}
