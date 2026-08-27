import 'package:attune/features/games/mirror/presentation/screens/mirror_question_screen.dart';
import 'package:attune/features/games/scenario/presentation/screens/scenario_question_screen.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SlidingScaleQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q1',
      gameType: 'sliding_scale',
      questionText: 'How much of our money should be shared?',
      valueDomain: 'money',
      scaleLow: 'Kept separate',
      scaleHigh: 'Fully shared',
    );

    testWidgets('shows both anchor labels', (tester) async {
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('Kept separate'), findsOneWidget);
      expect(find.text('Fully shared'), findsOneWidget);
    });

    testWidgets('submits a value inside 1-10', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(
          question: question,
          onSubmit: (v) => submitted = v,
        )),
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();

      final value = int.parse(submitted!);
      // The server rejects anything outside 1-10; the UI must never be
      // able to produce such a value in the first place.
      expect(value, greaterThanOrEqualTo(1));
      expect(value, lessThanOrEqualTo(10));
    });

    testWidgets('slider is configured to exactly 1-10 in 9 divisions',
        (tester) async {
      // Pins the actual widget configuration, not just an emitted value,
      // so this fails if someone widens the range (e.g. min: 0, max: 100)
      // even before anyone drags it.
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(question: question, onSubmit: (_) {})),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.min, 1);
      expect(slider.max, 10);
      expect(slider.divisions, 9);
    });

    testWidgets('dragging to each extreme submits 1 and 10', (tester) async {
      // Exercises real boundaries rather than only the untouched default,
      // so a widened range would surface as a wrong emitted value too.
      String? submitted;
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(
          question: question,
          onSubmit: (v) => submitted = v,
        )),
      );

      await tester.drag(find.byType(Slider), const Offset(-500, 0));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(submitted, '1');

      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(submitted, '10');
    });
  });

  group('ScenarioQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q2',
      gameType: 'scenario',
      questionText: 'You are both tired and a disagreement starts.',
      options: [
        SessionGameOption(key: 'a', text: 'Push through'),
        SessionGameOption(key: 'b', text: 'Pause'),
        SessionGameOption(key: 'c', text: 'Step away'),
      ],
    );

    testWidgets('renders every option', (tester) async {
      await tester.pumpWidget(
        wrap(ScenarioQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('Push through'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Step away'), findsOneWidget);
    });

    testWidgets('submits the option KEY, not its text', (tester) async {
      // The server validates the answer against the question's option
      // keys, so submitting display text would be rejected.
      String? submitted;
      await tester.pumpWidget(
        wrap(ScenarioQuestionScreen(
          question: question,
          onSubmit: (v) => submitted = v,
        )),
      );
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(submitted, 'b');
    });

    testWidgets('empty options renders no buttons and never submits',
        (tester) async {
      // SessionGameQuestion.options defaults to const [], so an
      // options-free scenario question can reach this screen without a
      // malformed server response being impossible. The screen must show
      // a plain unavailable message instead of stranding the user.
      const emptyQuestion = SessionGameQuestion(
        id: 'q2-empty',
        gameType: 'scenario',
        questionText: 'You are both tired and a disagreement starts.',
      );
      var submitCount = 0;
      await tester.pumpWidget(
        wrap(ScenarioQuestionScreen(
          question: emptyQuestion,
          onSubmit: (_) => submitCount++,
        )),
      );
      expect(find.byType(OutlinedButton), findsNothing);
      expect(submitCount, 0);
    });
  });

  group('MirrorQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q3',
      gameType: 'mirror',
      questionText: 'What is weighing on them most this week?',
    );

    testWidgets('shows the prompt and a text field', (tester) async {
      await tester.pumpWidget(
        wrap(MirrorQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('What is weighing on them most this week?'),
          findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('will not submit an empty answer', (tester) async {
      // The server rejects empty answers; the UI should not let the user
      // reach that error.
      var submitCount = 0;
      await tester.pumpWidget(
        wrap(MirrorQuestionScreen(
          question: question,
          onSubmit: (_) => submitCount++,
        )),
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(submitCount, 0);
    });

    testWidgets('will not submit a whitespace-only answer', (tester) async {
      // Whitespace-only is one of the three conditions the server RAISES
      // on; _controller.text.trim().isEmpty must catch it before onSubmit
      // is ever called.
      var submitCount = 0;
      await tester.pumpWidget(
        wrap(MirrorQuestionScreen(
          question: question,
          onSubmit: (_) => submitCount++,
        )),
      );
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(submitCount, 0);
    });
  });
}
