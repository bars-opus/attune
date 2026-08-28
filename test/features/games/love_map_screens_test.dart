import 'package:attune/features/games/love_map/domain/love_map_selection.dart';
import 'package:attune/features/games/love_map/presentation/screens/love_map_question_screen.dart';
import 'package:attune/features/games/love_map/presentation/screens/love_map_reveal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _q = LoveMapQuestion(
  id: 'q1',
  valueDomain: 'fears',
  text: 'What are they most afraid of losing right now?',
);

const _subjectBanner =
    'Answer honestly about yourself — your partner is trying to read you.';

void main() {
  testWidgets('the subject is told to answer about themselves', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoveMapQuestionScreen(
          question: _q, isSubject: true, onSubmit: (_) {}),
    ));
    expect(find.text(_subjectBanner), findsOneWidget);
  });

  testWidgets('the guesser is not told to answer about themselves',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoveMapQuestionScreen(
          question: _q, isSubject: false, onSubmit: (_) {}),
    ));
    expect(find.text(_subjectBanner), findsNothing);
    expect(find.text(_q.text), findsOneWidget);
  });

  testWidgets('will not submit an empty answer', (tester) async {
    var submitted = false;
    await tester.pumpWidget(MaterialApp(
      home: LoveMapQuestionScreen(
          question: _q, isSubject: false, onSubmit: (_) => submitted = true),
    ));
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(submitted, isFalse);
  });

  testWidgets('a repeat never shows the guesser the previous answer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LoveMapRevealScreen(
        yourAnswer: 'my guess',
        theirAnswer: 'their truth',
        isSubject: false,
        previousAnswer: 'what they said six months ago',
      ),
    ));
    expect(find.text('what they said six months ago'), findsNothing);
  });

  testWidgets('a repeat shows the subject their own previous answer',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LoveMapRevealScreen(
        yourAnswer: 'my truth',
        theirAnswer: 'their guess',
        isSubject: true,
        previousAnswer: 'what I said six months ago',
      ),
    ));
    expect(find.text('what I said six months ago'), findsOneWidget);
    expect(find.text('Six months ago you said'), findsOneWidget);
  });

  testWidgets('the reveal shows no score, tally or percentage',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LoveMapRevealScreen(
        yourAnswer: 'a', theirAnswer: 'b', isSubject: true),
    ));
    // §11.1: Love Map accumulates, it does not grade.
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('correct'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+ of \d+')), findsNothing);
  });
}
