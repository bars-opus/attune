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

  Future<void> show(WidgetTester tester, WordHuntSession s) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WordHuntReveal(
              session: s,
              partnerName: 'Ama',
              onPlayAgain: () {},
              onBackToChat: () {},
            ),
          ),
        ),
      );

  testWidgets('never ranks the two players, however politely', (tester) async {
    // THE BANNED LIST GREW AFTER A REVIEW. The first version of this test
    // banned "won", "lost" and "beat" while a sibling test REQUIRED the
    // headline "You were quicker" -- which is the same claim in a politer
    // register, and the review said so. A comparative is a ranking
    // whatever verb carries it.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 12000,
        theirs: WordHuntStatus.found,
        theirMs: 40000,
      ),
    );
    for (final banned in [
      'won',
      'Won',
      'lost',
      'Lost',
      'beat',
      'Beat',
      'winner',
      'Winner',
      'loser',
      'Loser',
      'quicker',
      'Quicker',
      'faster',
      'Faster',
      'slower',
      'Slower',
      'first',
      'First',
    ]) {
      expect(
        find.textContaining(banned, findRichText: true),
        findsNothing,
        reason: 'the reveal must not rank the players ("$banned")',
      );
    }
  });

  testWidgets('the same holds when the times are reversed', (tester) async {
    // The asymmetric case: a ranking that only appears when the partner
    // is faster would be the easiest version of this to reintroduce.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 40000,
        theirs: WordHuntStatus.found,
        theirMs: 12000,
      ),
    );
    for (final banned in ['quicker', 'faster', 'slower', 'beat', 'won']) {
      expect(find.textContaining(banned), findsNothing);
    }
    expect(find.text('You both found it'), findsOneWidget);
  });

  testWidgets('both finding it says exactly that, at any gap', (tester) async {
    // 12s against 40s is a wide gap and still not a contest: the two
    // attempts happened at different times, possibly days apart.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 12000,
        theirs: WordHuntStatus.found,
        theirMs: 40000,
      ),
    );
    expect(find.text('You both found it'), findsOneWidget);
  });

  testWidgets('times within a second are called out as level', (tester) async {
    // The measurement includes Start-response latency, render time and
    // Submit latency. Presenting two numbers this close as ordered would
    // report network jitter as skill -- so the screen says so plainly
    // rather than leaving the reader to compare 20.0 and 21.0.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 20000,
        theirs: WordHuntStatus.found,
        theirMs: 20999,
      ),
    );
    expect(find.text('Within a second of each other.'), findsOneWidget);
  });

  testWidgets('a wider gap gets no such line, and still no ranking', (
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
    expect(find.text('Within a second of each other.'), findsNothing);
    expect(find.text('You both found it'), findsOneWidget);
  });

  testWidgets('both times are still shown, so the reader can compare', (
    tester,
  ) async {
    // Not ranking them is not the same as hiding them. The numbers are
    // the point of the game; the app just does not editorialise.
    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 12000,
        theirs: WordHuntStatus.found,
        theirMs: 40000,
      ),
    );
    expect(find.text('12.0s'), findsOneWidget);
    expect(find.text('40.0s'), findsOneWidget);
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
      session(
        mine: WordHuntStatus.found,
        myMs: 9000,
        theirs: WordHuntStatus.gaveUp,
      ),
    );
    expect(find.text("Didn't find it"), findsOneWidget);
    expect(find.textContaining('gave up'), findsNothing);
    expect(find.textContaining('quit'), findsNothing);
    expect(find.textContaining('surrender'), findsNothing);

    await show(
      tester,
      session(
        mine: WordHuntStatus.found,
        myMs: 9000,
        theirs: WordHuntStatus.timedOut,
      ),
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
      session(mine: WordHuntStatus.timedOut, theirs: WordHuntStatus.gaveUp),
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
