import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a batch of messages arriving after reconnect each animate in',
      (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(repository: repo, userId: 'user-a');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 40));

    // Three partner messages arrive together, then a realtime tick.
    final base = DateTime.now();
    for (var i = 0; i < 3; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'msg $i',
        createdAt: base.add(Duration(seconds: i)),
      );
    }
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));

    // Each newly-arrived bubble is wrapped in a SettleIn (the cascade vehicle).
    expect(find.byType(SettleIn), findsWidgets);

    // The list is newest-first (reverse: true), so the topmost SettleIn
    // widgets correspond to the most-recently-arrived messages. With the
    // per-index stagger, the newest bubble (index 0) should settle no slower
    // than bubbles further down the newest-run, and at least one later
    // bubble in the batch should have a strictly longer duration than the
    // topmost one, proving the cascade offset is applied.
    final settleIns = tester
        .widgetList<SettleIn>(find.byType(SettleIn))
        .where((w) => w.animate)
        .toList();
    expect(settleIns.length, greaterThanOrEqualTo(3));
    final durations = settleIns.map((w) => w.duration).toList();
    expect(durations.last, greaterThan(durations.first));

    // Let the view-active mark-as-read debounce (500ms) fire, then unmount
    // the widget tree before the container disposes so the controller's
    // keep-alive eviction Timer is cancelled via onCancel/onDispose instead
    // of racing the test binding's pending-timer check.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });
}
