import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The copy IS the design on this screen.
///
/// Two people who did not play at the same time being told one "beat" the
/// other is a small lie: nobody was present for the other attempt, and a
/// modified client could solve the grid without looking. These tests pin
/// the words, because a later edit that reads better and claims more
/// would be a regression no other test would catch.
void main() {
  WordHuntSession session({
    required WordHuntStatus mine,
    int? myMs,
    WordHuntStatus? theirs,
    int? theirMs,
  }) => WordHuntSession(
    sessionId: 's',
    relationshipId: 'r',
    initiatorId: 'a',
    status: 'completed',
    userA: 'a',
    userB: 'b',
    partnerId: 'b',
    wordLength: 4,
    serverObservedAt: DateTime.utc(2026, 9, 8),
    bothTerminal: true,
    myStatus: mine,
    myElapsedMs: myMs,
    partnerStatus: theirs,
    partnerElapsedMs: theirMs,
  );

  Future<void> show(WidgetTester tester, WordHuntSession s) => tester
      .pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordHuntReveal(
              session: s,
              onPlayAgain: () {},
              onBackToChat: () {},
            ),
          ),
        ),
      );

  testWidgets('never says won, lost, beat or a rank', (tester) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 12000,
        theirs: WordHuntStatus.found,
        theirMs: 40000,
      ),
    );
    for (final banned in ['won', 'Won', 'lost', 'Lost', 'beat', 'Beat',
                          'winner', 'Winner', 'loser', 'Loser']) {
      expect(
        find.textContaining(banned, findRichText: true),
        findsNothing,
        reason: 'the reveal must not frame this as a contest ("$banned")',
      );
    }
  });

  testWidgets('a sub-second difference is a tie, not a ranking', (
    tester,
  ) async {
    // The measurement includes Start-response latency, render time and
    // Submit latency. Ranking two numbers this close reports network
    // jitter as skill.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 20000,
        theirs: WordHuntStatus.found,
        theirMs: 20999,
      ),
    );
    expect(find.text('Dead even'), findsOneWidget);
  });

  testWidgets('a difference over the threshold is reported plainly', (
    tester,
  ) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 20000,
        theirs: WordHuntStatus.found,
        theirMs: 21001,
      ),
    );
    expect(find.text('You were quicker'), findsOneWidget);
  });

  testWidgets('the threshold is symmetric', (tester) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 21001,
        theirs: WordHuntStatus.found,
        theirMs: 20000,
      ),
    );
    expect(find.text('They were quicker'), findsOneWidget);
  });

  testWidgets('no speed comparison unless both found it', (tester) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 9000,
        theirs: WordHuntStatus.gaveUp,
      ),
    );
    expect(find.text('You found it'), findsOneWidget);
    expect(find.textContaining('quicker'), findsNothing);
  });

  testWidgets('a surrender and a timeout read identically', (tester) async {
    // The database distinguishes them. The screen must not: reporting a
    // quit as a quit turns a kindness into something to be embarrassed
    // about.
    await show(
      tester,
      session(mine: WordHuntStatus.found, myMs: 9000,
              theirs: WordHuntStatus.gaveUp),
    );
    expect(find.text("Didn't find it"), findsOneWidget);
    expect(find.textContaining('gave up'), findsNothing);
    expect(find.textContaining('quit'), findsNothing);
    expect(find.textContaining('surrender'), findsNothing);

    await show(
      tester,
      session(mine: WordHuntStatus.found, myMs: 9000,
              theirs: WordHuntStatus.timedOut),
    );
    expect(find.text("Didn't find it"), findsOneWidget);
    expect(find.textContaining('ran out'), findsNothing);
  });

  testWidgets('an absent partner is "did not play", not "did not find it"', (
    tester,
  ) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 9000,
        theirs: WordHuntStatus.didNotPlay,
      ),
    );
    expect(find.text("Didn't play"), findsOneWidget);
    expect(find.text("Didn't find it"), findsNothing);
  });

  testWidgets('neither finding it says so without blaming either', (
    tester,
  ) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.timedOut,
        theirs: WordHuntStatus.gaveUp,
      ),
    );
    expect(find.text('Neither of you found it'), findsOneWidget);
  });

  testWidgets('Play again is present, and is the prominent action', (
    tester,
  ) async {
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 9000,
        theirs: WordHuntStatus.found,
        theirMs: 11000,
      ),
    );
    // Filled, not a text button: this screen exists to get back to
    // playing rather than to dwell on two numbers.
    expect(find.widgetWithText(FilledButton, 'Play again'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Back to chat'), findsOneWidget);
  });
}
