import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('header avatar is wrapped in a GlowPulse', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ChatScreen(conversation: convo)),
    ));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(GlowPulse), findsWidgets);

    // Stop timers: unmount before disposing the container so the
    // controller's keep-alive eviction Timer and GlowPulse's repeating
    // animation are cancelled instead of racing the pending-timer check.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });
}
