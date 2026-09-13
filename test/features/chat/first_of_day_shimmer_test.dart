import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a message that starts a new day is wrapped in a Shimmer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    // Establish an empty initial snapshot, then deliver two realtime rows.
    // Both timestamps are deliberately behind the device clock: arrival
    // animation is keyed by stable identity, never by createdAt.
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'today',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'today msg',
      createdAt: now.subtract(const Duration(minutes: 5)),
    );
    repo.seedIncoming(
      id: 'yesterday',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'yesterday msg',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 400));

    // At least one Shimmer present (the first-of-day bubble).
    expect(find.byType(Shimmer), findsWidgets);

    // Shimmer loops (AnimationController.repeat()) while shown, and the view
    // starts a mark-as-read debounce timer, so — as in
    // message_list_animation_test.dart — unmount the widget tree (which stops
    // the ticker and cancels pending timers) before disposing the container,
    // rather than disposing underneath a still-mounted, still-animating tree.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });
}
