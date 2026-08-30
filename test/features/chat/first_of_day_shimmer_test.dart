import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a message that starts a new day is wrapped in a Shimmer', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    final now = DateTime.now();
    // A message "today" and one from "yesterday" → today's is first-of-day.
    // The "today" message is stamped ahead of `now` so it is unambiguously
    // after ChatScreen's firstBuildCutoff (captured moments later, when the
    // widget is constructed during pumpWidget below) and therefore counts
    // as new — same calendar day, so the first-of-day comparison is
    // unaffected.
    //
    // The margin is minutes, not seconds: under a loaded parallel suite run
    // more than a couple of seconds of WALL CLOCK can pass between seeding
    // here and the widget being built, letting the cutoff overtake the
    // timestamp. The message then reads as history, no Shimmer renders, and
    // the test fails for load rather than for behaviour.
    repo.seedIncoming(
      id: 'today',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'today msg',
      createdAt: now.add(const Duration(minutes: 5)),
    );
    repo.seedIncoming(
      id: 'yesterday',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'yesterday msg',
      createdAt: now.subtract(const Duration(days: 1)),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
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
