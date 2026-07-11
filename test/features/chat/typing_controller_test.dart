import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  test('partner typing:true sets partnerTyping, auto-expires after 5s',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    // Reading the provider constructs the controller and starts its
    // watchTyping subscription.
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping('partner', true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(typingControllerProvider(relId)).partnerTyping, isTrue);

    // after ~5s with no further events, it clears
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('own typing echo is ignored', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping(userId, true); // our own id
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('partner typing:false clears immediately', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    container.read(typingControllerProvider(relId));

    repo.emitPartnerTyping('partner', true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.emitPartnerTyping('partner', false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        container.read(typingControllerProvider(relId)).partnerTyping, isFalse);
  });

  test('composing throttles typing:true to at most one per 2s window',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    controller.onComposingChanged(true);
    controller.onComposingChanged(true);
    // Only one typing:true should have been sent in the immediate window.
    final trues = repo.sentTyping.where((e) => e.typing).length;
    expect(trues, 1);
  });

  test('onSent broadcasts typing:false', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    controller.onSent();
    expect(repo.sentTyping.last.typing, isFalse);
  });
}
