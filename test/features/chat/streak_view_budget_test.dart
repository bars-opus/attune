import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('spending a view decrements the local budget', () async {
    // The RPC decrements server-side and RETURNS what remains, but the
    // viewer discarded that value and nothing refreshed the list — so the
    // bubble kept the count it was built with and could be reopened
    // indefinitely.
    final repo = FakeChatRepository(currentUserId: 'me');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    repo.seedIncoming(
      id: 'streak-1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime.now(),
      mediaType: 'streak',
      streakViewsRemaining: 3,
    );

    final container = buildChatContainer(repository: repo, userId: 'me');
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    Message streak() => container
        .read(chatControllerProvider(convo))
        .messages
        .firstWhere((m) => m.id == 'streak-1');

    expect(streak().streakViewsRemaining, 3);

    controller.applyStreakViewSpent('streak-1', 2);
    expect(streak().streakViewsRemaining, 2);

    controller.applyStreakViewSpent('streak-1', 0);
    expect(
      streak().streakViewsRemaining,
      0,
      reason: 'a spent streak must reach zero so the bubble stops opening it',
    );
  });

  test('spending a view also stamps viewedAt locally', () async {
    // viewed_at is what locks the SENDER out ("Opened") and what the
    // server checks to refuse their reopen. The RPC sets it on the
    // recipient's first view, but the local row kept viewedAt null, so
    // the sender's bubble never reached its Opened state in-session.
    final repo = FakeChatRepository(currentUserId: 'me');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    repo.seedIncoming(
      id: 'streak-1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime.now(),
      mediaType: 'streak',
      streakViewsRemaining: 3,
    );

    final container = buildChatContainer(repository: repo, userId: 'me');
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    Message streak() => container
        .read(chatControllerProvider(convo))
        .messages
        .firstWhere((m) => m.id == 'streak-1');

    expect(streak().viewedAt, isNull);

    controller.applyStreakViewSpent('streak-1', 2);

    expect(
      streak().viewedAt,
      isNotNull,
      reason: 'the first view opens the window and locks the sender out',
    );
  });

  test('an unknown message id changes nothing', () async {
    final repo = FakeChatRepository(currentUserId: 'me');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    repo.seedIncoming(
      id: 'streak-1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: DateTime.now(),
      mediaType: 'streak',
      streakViewsRemaining: 3,
    );

    final container = buildChatContainer(repository: repo, userId: 'me');
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    controller.applyStreakViewSpent('does-not-exist', 0);

    expect(
      container
          .read(chatControllerProvider(convo))
          .messages
          .firstWhere((m) => m.id == 'streak-1')
          .streakViewsRemaining,
      3,
    );
  });

  test('the viewer\'s returned count is wired through to the controller', () {
    // The three pieces have to meet: the viewer must RETURN the count, the
    // bubble must forward it, and the screen must apply it. Each is fine
    // in isolation and the budget still never moves if one is missing.
    final viewer =
        File(
          'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
        ).readAsStringSync();
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();
    final screen =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();

    expect(
      viewer,
      contains('pop(_remaining)'),
      reason: 'the viewer must return what the RPC reported, not discard it',
    );
    expect(
      bubble,
      contains('onStreakViewSpent?.call'),
      reason: 'the bubble must forward the returned count',
    );
    expect(
      screen,
      contains('.applyStreakViewSpent('),
      reason: 'the screen must apply it to the message list',
    );
  });
}
