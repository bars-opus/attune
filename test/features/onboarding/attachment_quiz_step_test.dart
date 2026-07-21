import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    ProviderScope(
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => Scaffold(
                body: OnboardingDeckScope(
                cardKey: questionIndex,
                accent: OnboardingDeckAccent.neutral,
                enableDeck: true,
                  child: AttachmentQuizStep(
                    questionIndex: questionIndex,
                    answers: answers,
                    onChanged: changes.add,
                    onBack: null,
                    onNext: () => advanced = true,
                  ),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The card content scrolls on short screens, so bring the button into view
  // before tapping — otherwise the tap silently misses and the test reads as
  // "did not advance" regardless of whether the button was actually enabled.
  final nextFinder = find.text('Next');
  await tester.ensureVisible(nextFinder);
  await tester.pumpAndSettle();
  await tester.tap(nextFinder, warnIfMissed: false);
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
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => Scaffold(
                  body: OnboardingDeckScope(
                  cardKey: 0,
                  accent: OnboardingDeckAccent.neutral,
                enableDeck: true,
                    child: AttachmentQuizStep(
                      questionIndex: 0,
                      answers: answers,
                      onChanged: (_) {},
                      onBack: null,
                      onNext: () {},
                    ),
                  ),
                ),
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

  testWidgets('tapping the description expands to the full detail view', (
    tester,
  ) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => Scaffold(
                  body: OnboardingDeckScope(
                    cardKey: 0,
                    accent: OnboardingDeckAccent.neutral,
                    enableDeck: true,
                    child: AttachmentQuizStep(
                      questionIndex: 0,
                      answers: answers,
                      onChanged: (_) {},
                      onBack: null,
                      onNext: () {},
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Collapsed: the description is truncated, so the affordance must be
    // present — otherwise the extra explanation is unreachable.
    final readMore = find.text('Read more');
    expect(readMore, findsOneWidget);

    await tester.ensureVisible(readMore);
    await tester.pumpAndSettle();
    await tester.tap(readMore);
    await tester.pumpAndSettle();

    // Expanded: full description reachable, and the scale came with it so the
    // user can answer while reading.
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsWidgets);
  });

  testWidgets('answering inside the detail view reports to the parent', (
    tester,
  ) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);
    final changes = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => Scaffold(
                  body: OnboardingDeckScope(
                    cardKey: 0,
                    accent: OnboardingDeckAccent.neutral,
                    enableDeck: true,
                    child: AttachmentQuizStep(
                      questionIndex: 0,
                      answers: answers,
                      onChanged: changes.add,
                      onBack: null,
                      onNext: () {},
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final readMore = find.text('Read more');
    await tester.ensureVisible(readMore);
    await tester.pumpAndSettle();
    await tester.tap(readMore);
    await tester.pumpAndSettle();

    // Answer from the expanded view. It must reach the parent immediately —
    // dismissing the sheet has no commit step, so a dropped value here would
    // silently lose the user's answer.
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();

    expect(changes, contains(4));
  });

  testWidgets(
    'Next is inert while the detail view\'s close flight is still in progress',
    (tester) async {
      final answers = List<int?>.filled(attachmentQuestions.length, null);
      answers[0] = 3;
      var advanced = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder:
                  (_, __) => Scaffold(
                    body: OnboardingDeckScope(
                      cardKey: 0,
                      accent: OnboardingDeckAccent.neutral,
                      enableDeck: true,
                      child: AttachmentQuizStep(
                        questionIndex: 0,
                        answers: answers,
                        onChanged: (_) {},
                        onBack: null,
                        onNext: () => advanced = true,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final readMore = find.text('Read more');
      await tester.ensureVisible(readMore);
      await tester.pumpAndSettle();
      await tester.tap(readMore);
      await tester.pumpAndSettle();

      // Start closing the detail view, but do NOT settle — this is the exact
      // window where the Hero return flight is still reparented into the
      // Overlay. Tapping Next here previously raced the deck's own
      // transition against that flight and crashed layout.
      await tester.tap(find.text('Done'));
      await tester.pump();

      final nextFinder = find.text('Next');
      if (tester.any(nextFinder)) {
        await tester.tap(nextFinder, warnIfMissed: false);
      }
      await tester.pump();

      // Next must not have fired while the flight was still resolving.
      expect(advanced, isFalse);

      // Let the flight finish; only now should Next be capable of firing.
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(advanced, isTrue);
    },
  );

  testWidgets(
    'advancing right after closing the detail view drives the deck crossfade '
    'without a layout error',
    (tester) async {
      // Guards the deck advance path that the "RenderBox was not laid out"
      // crash lived on: open a question's detail sheet, close it, then advance
      // to the next question so OnboardingDeckCard plays its crossfade between
      // the outgoing card (with its SingleChildScrollView) and the incoming
      // one. Pumped frame-by-frame (not settled) so every transition frame —
      // including the one where _outgoing is nulled and its scroll subtree is
      // disposed — is asserted exception-free. The fix pins each card ROLE to a
      // stable Key so the outgoing scroll subtree can never be reconciled into
      // the incoming card's element mid-frame.
      await tester.pumpWidget(const _AdvancingDeckHarness());
      await tester.pumpAndSettle();

      // Open the detail view.
      final readMore = find.text('Read more');
      await tester.ensureVisible(readMore);
      await tester.pumpAndSettle();
      await tester.tap(readMore);
      await tester.pumpAndSettle();

      // Begin closing it, then advance while the deck transition is live —
      // pumping frame-by-frame through the whole crossfade so the frame where
      // _outgoing is nulled (and its scroll view disposed) is exercised.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final next = find.text('Next');
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next, warnIfMissed: false);

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.takeException(),
          isNull,
          reason: 'deck transition frame $i threw',
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The advance actually landed on the next question.
      expect(find.text('Question 2 of ${attachmentQuestions.length}'),
          findsOneWidget);
    },
  );
}

/// Drives a real AttachmentQuizStep whose Next advances the question index,
/// keeping the deck enabled so OnboardingDeckCard plays its crossfade — the
/// exact transition that rebuilds/disposes the outgoing card's scroll view.
class _AdvancingDeckHarness extends StatefulWidget {
  const _AdvancingDeckHarness();

  @override
  State<_AdvancingDeckHarness> createState() => _AdvancingDeckHarnessState();
}

class _AdvancingDeckHarnessState extends State<_AdvancingDeckHarness> {
  int _index = 0;
  late final List<int?> _answers =
      List<int?>.filled(attachmentQuestions.length, null)
        ..[0] = 4
        ..[1] = 4;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => Scaffold(
                body: OnboardingDeckScope(
                  // Fold the question index into the card identity exactly as
                  // OnboardingFlow does, so advancing changes stepIndex and the
                  // deck runs its transition.
                  cardKey: _index,
                  accent: OnboardingDeckAccent.neutral,
                  enableDeck: true,
                  child: AttachmentQuizStep(
                    questionIndex: _index,
                    answers: _answers,
                    onChanged: (v) => setState(() => _answers[_index] = v),
                    onBack: null,
                    onNext: () => setState(() => _index++),
                  ),
                ),
              ),
        ),
      ),
    );
  }
}
