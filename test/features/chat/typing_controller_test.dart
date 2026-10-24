import 'package:attune/features/chat/presentation/state/typing_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  test(
    'partner typing:true sets partnerTyping, auto-expires after 5s',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      // Registering a listener constructs the controller, starts its
      // watchTyping subscription, and keeps it alive for the test body —
      // mirroring how the real composer widget watches this provider.
      final sub = container.listen(typingControllerProvider(relId), (_, __) {});
      addTearDown(sub.close);

      repo.emitPartnerTyping('partner', true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(typingControllerProvider(relId)).partnerTyping,
        isTrue,
      );

      // after ~5s with no further events, it clears
      await Future<void>.delayed(const Duration(seconds: 6));
      expect(
        container.read(typingControllerProvider(relId)).partnerTyping,
        isFalse,
      );
    },
  );

  test('own typing echo is ignored', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final sub = container.listen(typingControllerProvider(relId), (_, __) {});
    addTearDown(sub.close);

    repo.emitPartnerTyping(userId, true); // our own id
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(typingControllerProvider(relId)).partnerTyping,
      isFalse,
    );
  });

  test('partner typing:false clears immediately', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final sub = container.listen(typingControllerProvider(relId), (_, __) {});
    addTearDown(sub.close);

    repo.emitPartnerTyping('partner', true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    repo.emitPartnerTyping('partner', false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(typingControllerProvider(relId)).partnerTyping,
      isFalse,
    );
  });

  test(
    'composing throttles typing:true to at most one per 2s window',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final sub = container.listen(typingControllerProvider(relId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(
        typingControllerProvider(relId).notifier,
      );

      controller.onComposingChanged(true);
      controller.onComposingChanged(true);
      controller.onComposingChanged(true);
      // Only one typing:true should have been sent in the immediate window.
      final trues = repo.sentTyping.where((e) => e.typing).length;
      expect(trues, 1);
    },
  );

  test('onSent broadcasts typing:false', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final sub = container.listen(typingControllerProvider(relId), (_, __) {});
    addTearDown(sub.close);
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    controller.onSent();
    expect(repo.sentTyping.last.typing, isFalse);
  });

  test(
    'throttle stops and emits typing:false after keystroke inactivity',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final sub = container.listen(typingControllerProvider(relId), (_, __) {});
      addTearDown(sub.close);
      final controller = container.read(
        typingControllerProvider(relId).notifier,
      );

      // Single keystroke, then leave text in the composer with no further
      // activity — simulates the partner walking away mid-message. The 2s
      // throttle keeps re-sending typing:true until the 5s inactivity window
      // elapses (leading-edge true at t=0, re-sends at t=2s/t=4s, decay
      // detected and typing:false sent at the t=6s tick).
      controller.onComposingChanged(true);

      // Wait past the inactivity window (5s) plus another throttle tick (2s)
      // so the periodic timer has a chance to observe the decay and fire.
      await Future<void>.delayed(const Duration(seconds: 8));

      expect(repo.sentTyping.last.typing, isFalse);
      // No typing:true should have been sent after the decay-triggered false.
      final falseIndex = repo.sentTyping.lastIndexWhere((e) => !e.typing);
      final afterDecay = repo.sentTyping.skip(falseIndex + 1);
      expect(afterDecay, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // Stories Wave 3: the chat stays mounted behind the privacy cover, with
  // the composer still focused, so the throttle no longer dies with it.
  testWidgets('never sends typing while Attune is covered: leaving stops it; '
      'typing again on return starts it', (t) async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    final sub = container.listen(typingControllerProvider(relId), (_, __) {});
    final controller = container.read(typingControllerProvider(relId).notifier);

    controller.onComposingChanged(true);
    expect(repo.sentTyping.map((e) => e.typing), [true]);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    expect(repo.sentTyping.last.typing, isFalse, reason: 'cleared on leave');
    final atLeave = repo.sentTyping.length;
    controller.onComposingChanged(true); // a draft restored while covered
    await t.pump(const Duration(seconds: 7));
    expect(repo.sentTyping.length, atLeave, reason: 'nothing while covered');

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    controller.onComposingChanged(true);
    expect(repo.sentTyping.last.typing, isTrue);

    controller.onSent();
    sub.close();
    container.dispose();
    // Riverpod schedules the auto-dispose on a zero-length timer.
    await t.pump(const Duration(milliseconds: 1));
  });
}
