import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the quiz step with a given answer list and reports whether Next is
/// tappable and whether the taps landed.
Future<({bool nextEnabled, List<int> changes})> _pumpStep(
  WidgetTester tester, {
  required List<int?> answers,
  int questionIndex = 0,
}) async {
  final changes = <int>[];
  var advanced = false;

  await tester.pumpWidget(
    MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => AttachmentQuizStep(
              questionIndex: questionIndex,
              answers: answers,
              onChanged: changes.add,
              onBack: null,
              onNext: () => advanced = true,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Tap the forward button and see whether it did anything.
  await tester.tap(find.text('Next'), warnIfMissed: false);
  await tester.pumpAndSettle();

  return (nextEnabled: advanced, changes: changes);
}

void main() {
  testWidgets('an unanswered question cannot be advanced past', (tester) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);

    final result = await _pumpStep(tester, answers: answers);

    // The whole point: tapping Next on a question you never answered does
    // nothing, so we can never store a fabricated midpoint for it.
    expect(result.nextEnabled, isFalse);
  });

  testWidgets('an answered question can be advanced past', (tester) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);
    answers[0] = 4;

    final result = await _pumpStep(tester, answers: answers);

    expect(result.nextEnabled, isTrue);
  });

  testWidgets('no Likert value is pre-selected on an untouched question', (
    tester,
  ) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);

    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => AttachmentQuizStep(
                questionIndex: 0,
                answers: answers,
                onChanged: (_) {},
                onBack: null,
                onNext: () {},
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final segmented = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    // Nothing selected — an untouched question must not look answered.
    expect(segmented.selected, isEmpty);
    expect(segmented.emptySelectionAllowed, isTrue);
  });
}
