import 'package:attune/core/ui/motion/make_room.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('a live-arriving row opens its own slot', (tester) async {
    // The list is reverse: true, so a new bubble at the bottom displaces
    // everything older upward. Previously the row took its full height on
    // its first frame -- older messages jumped to their new positions and
    // the bubble then faded in on top of the settled layout.
    //
    // Asserted on MakeRoom's own measured height rather than by driving a
    // whole ChatScreen: the screen's provider holds a 5-minute keep-alive
    // eviction timer that outlives the widget tree, so a screen-level
    // version of this test fails teardown for reasons unrelated to the
    // animation. The wiring itself is covered by the SettleIn/MakeRoom
    // structure test below.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('earlier message'),
              MakeRoom(child: SizedBox(height: 80, width: 100)),
            ],
          ),
        ),
      ),
    );

    final before = tester.getTopLeft(find.text('earlier message')).dy;
    await tester.pump(const Duration(milliseconds: 16));
    final earlyShift =
        (before - tester.getTopLeft(find.text('earlier message')).dy).abs();

    await tester.pumpAndSettle();
    final finalShift =
        (before - tester.getTopLeft(find.text('earlier message')).dy).abs();

    expect(
      finalShift,
      greaterThan(8.0),
      reason: 'the older message must end up displaced',
    );
    expect(
      earlyShift,
      lessThan(finalShift * 0.6),
      reason:
          'it jumped $earlyShift of $finalShift on the first frame — the '
          'slot is not growing',
    );
  });

  testWidgets('each message bubble is wrapped in a SettleIn', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello',
      createdAt: DateTime.now(),
    );
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

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

    expect(find.byType(SettleIn), findsWidgets);
    // And in a MakeRoom that opens the row's slot as it arrives. Without
    // this the widget could be correct and simply never wired in.
    expect(find.byType(MakeRoom), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(MakeRoom),
        matching: find.byType(SettleIn),
      ),
      findsWidgets,
      reason:
          'MakeRoom must wrap SettleIn — the slot grows while the bubble '
          'settles into it, not the other way round',
    );

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
