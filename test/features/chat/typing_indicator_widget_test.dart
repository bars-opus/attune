import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('shows BreathingDots when the partner is typing', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: withScreenUtil(MaterialApp(home: ChatScreen(conversation: convo))),
    ));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byType(BreathingDots), findsNothing);

    repo.emitPartnerTyping('partner', true);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(BreathingDots), findsOneWidget);

    // Let the view-active mark-as-read debounce (500ms) and the typing
    // controller's own timers settle, then unmount the widget tree before
    // the container disposes so pending Timers are cancelled via
    // onCancel/onDispose instead of racing the test binding's
    // pending-timer check.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });
}
