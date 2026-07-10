import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  test('a new partner message while viewing fires one receive haptic',
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
  });
}
