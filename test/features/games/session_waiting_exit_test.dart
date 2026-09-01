import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('the wait offers an immediate way back to the chat', (
    tester,
  ) async {
    // Session games are asynchronous: a partner may answer in an hour or
    // tomorrow. Holding a player on a blocking spinner until then made a
    // working game feel broken -- and leaving lost their place, because
    // nothing carried the state.
    var left = false;

    await tester.pumpWidget(
      wrap(
        SessionGameWaitingScreen.forTesting(
          bothAnswered: false,
          partnerAnswer: null,
          onLeaveToChat: () => left = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Back to chat'), findsOneWidget);

    await tester.tap(find.text('Back to chat'));
    await tester.pump();

    expect(
      left, isTrue,
      reason: 'a player who knows their partner is asleep must be able to '
          'leave without waiting out a timer',
    );
  });

  testWidgets('the wait says the answer is already saved', (tester) async {
    // Without this the screen reads as "your answer is in flight", and
    // leaving feels like abandoning it.
    await tester.pumpWidget(
      wrap(
        SessionGameWaitingScreen.forTesting(
          bothAnswered: false,
          partnerAnswer: null,
          onLeaveToChat: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Your answer is saved'), findsOneWidget);
  });

  testWidgets('a reveal wins the race against the exit', (tester) async {
    // The same-room case: the partner answers while the screen is up, and
    // showing the result must beat bouncing to the chat.
    //
    // Tapping the button AFTER a reveal is what makes this real: the
    // forTesting constructor skips the grace timer, so asserting only
    // that a revealed round did not also exit passes even with the guard
    // removed -- it never had the chance to fire.
    var revealed = false;
    var left = false;

    await tester.pumpWidget(
      wrap(
        SessionGameWaitingScreen.forTesting(
          bothAnswered: true,
          partnerAnswer: null,
          onRevealed: () => revealed = true,
          onLeaveToChat: () => left = true,
        ),
      ),
    );
    await tester.pump();

    expect(revealed, isTrue);

    // The reveal replaces this screen in the real flow, but a tap that
    // was already queued must not still drag the player to the chat out
    // from under the result. Tapping through the real button is what
    // exercises the guard -- asserting only that a revealed round did not
    // ALSO exit passes even with the guard removed, since nothing ever
    // called the exit.
    if (find.text('Back to chat').evaluate().isNotEmpty) {
      await tester.tap(find.text('Back to chat'));
      await tester.pump();
    }

    expect(
      left, isFalse,
      reason: 'once revealed, nothing may navigate away from the result',
    );
  });
}
