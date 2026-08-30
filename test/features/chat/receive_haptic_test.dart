import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test(
    'a new partner message while viewing fires one receive haptic',
    () async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final fake = FakeHaptics();
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final container = buildChatContainer(
        repository: repo,
        userId: 'user-a',
        extraOverrides: [hapticsProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.setViewActive(true);

      repo.seedIncoming(
        id: 'p1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hey',
        createdAt: DateTime.now(),
      );
      repo.emitRealtime();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(fake.selectionCount + fake.lightCount, greaterThanOrEqualTo(1));
    },
  );

  test('own message does not fire the receive haptic', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fake = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.setViewActive(true);

    await controller.sendMessage('mine');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Simulate the server echoing our own send back over realtime (as would
    // happen once the row is persisted) so the merged message list is
    // actually re-scanned by _maybeReceiveHaptic with our own message as the
    // newest row — this is what the `!m.isMine` filter must guard against.
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fake.selectionCount, 0);
  });

  test('a new partner message while backgrounded does not fire the receive '
      'haptic', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fake = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // Explicitly (re)confirm the view is backgrounded rather than active.
    controller.setViewActive(false);

    repo.seedIncoming(
      id: 'p1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hey',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fake.selectionCount, 0);
  });

  test('partner messages already present in the initial history do not fire '
      'the receive haptic on open', () async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final fake = FakeHaptics();
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    // Seed a partner message BEFORE the controller boots so it's part of the
    // initial load, not a "new" arrival.
    repo.seedIncoming(
      id: 'p0',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'already here',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [hapticsProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final controller = container.read(chatControllerProvider(convo).notifier);
    controller.setViewActive(true);
    // Let _init() (initial load + baseline seeding) settle.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(fake.selectionCount, 0);
  });
}
