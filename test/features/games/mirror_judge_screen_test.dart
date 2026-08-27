import 'package:attune/features/games/mirror/presentation/screens/mirror_judge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows your own answer beside their guess', (tester) async {
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'Work has been overwhelming',
          theirGuess: 'She is stressed about work',
          onJudge: (_) {},
        ),
      ),
    );
    expect(find.text('Work has been overwhelming'), findsOneWidget);
    expect(find.text('She is stressed about work'), findsOneWidget);
  });

  testWidgets('both verdicts report their value', (tester) async {
    final judgements = <bool>[];
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'truth',
          theirGuess: 'guess',
          onJudge: judgements.add,
        ),
      ),
    );

    await tester.tap(find.text('Yes'));
    await tester.pump();
    expect(judgements, [true]);

    await tester.tap(find.text('Not quite'));
    await tester.pump();
    expect(judgements, [true, false]);
  });

  testWidgets('Yes and Not quite use the same button type', (tester) async {
    // I2: a FilledButton on "Yes" visually nudges toward the affirmative
    // in the exact measurement the §8.4 attentiveness flag reads. Both
    // must render as the same widget type so neither is visually
    // preferred.
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'truth',
          theirGuess: 'guess',
          onJudge: (_) {},
        ),
      ),
    );

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNWidgets(2));
  });

  testWidgets('renders no tally, counter or progress indicator', (
    tester,
  ) async {
    // §11.1 rule 1. The subject produces every mark that composes their
    // partner's score, so showing them a running total would hand them
    // the partner's score outright — the exact thing §11.1 forbids. A
    // later contributor would add a progress bar as an obvious
    // improvement; this test is what stops that.
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'truth',
          theirGuess: 'guess',
          onJudge: (_) {},
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('of 4'), findsNothing);
    expect(find.textContaining('of 8'), findsNothing);
    expect(find.textContaining('correct'), findsNothing);
    expect(find.textContaining('score'), findsNothing);
  });
}
