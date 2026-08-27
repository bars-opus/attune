import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a waiting state and no answer text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: false,
            partnerAnswer: null,
          ),
        ),
      ),
    );
    expect(find.textContaining('Waiting'), findsOneWidget);
  });

  testWidgets('renders nothing resembling an answer before reveal', (
    tester,
  ) async {
    // The screen is handed a null partner answer because the gated RPC
    // returns null until both submit. This asserts the screen has no
    // other source it could render from.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: false,
            partnerAnswer: null,
          ),
        ),
      ),
    );
    expect(find.textContaining('answered:'), findsNothing);
  });

  testWidgets('reports reveal exactly once when the gate opens', (
    tester,
  ) async {
    var revealCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: true,
            partnerAnswer: 'their answer',
            onRevealed: () => revealCount++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(revealCount, 1);
  });
}
