import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Pumps ChatScreen and returns the container so the caller can dispose
/// it after unmounting.
///
/// GlowPulse breathes a fixed number of cycles and then stops scheduling
/// frames, so these tests pump a bounded duration rather than settling —
/// and unmount before disposing, so no animation outlives the container.
Future<ProviderContainer> _pumpChat(
  WidgetTester tester, {
  required bool isOnline,
}) async {
  final repo = FakeChatRepository(currentUserId: 'user-a');
  final convo = activeConversation('rel-1');
  repo.conversationOverride = convo;
  final container = buildChatContainer(
    repository: repo,
    userId: 'user-a',
    // The header's glow tracks connectivity, so drive it at the source
    // rather than reaching into the widget.
    extraOverrides: [
      chatConnectivityProvider.overrideWith((ref) => Stream.value(isOnline)),
    ],
  );

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: withScreenUtil(MaterialApp(home: ChatScreen(conversation: convo))),
  ));
  await tester.pump(const Duration(milliseconds: 40));
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
  c.dispose();
}

void main() {
  testWidgets('header avatar glows while the partner is here', (tester) async {
    final container = await _pumpChat(tester, isOnline: true);

    final glow = tester.widget<GlowPulse>(find.byType(GlowPulse));
    expect(
      glow.active,
      isTrue,
      reason: 'an active conversation with the partner online must glow',
    );

    await _teardown(tester, container);
  });

  testWidgets('header avatar does not glow while the partner is away',
      (tester) async {
    // The widget is still mounted when offline — only `active` flips —
    // so asserting on presence alone would pass either way. This pins
    // the flag itself, which is what actually shows the glow.
    final container = await _pumpChat(tester, isOnline: false);

    final glow = tester.widget<GlowPulse>(find.byType(GlowPulse));
    expect(
      glow.active,
      isFalse,
      reason: 'an offline partner must not read as here',
    );

    await _teardown(tester, container);
  });
}
