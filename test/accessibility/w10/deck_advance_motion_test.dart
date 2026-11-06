// Spec 1 §2.2, W10b: the quiz deck advances in kMakeRoomDuration (320 ms),
// not 900 ms, and not at all under reduce motion.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _flying = ValueKey<String>('deck-flying-card');

Widget _deck(int step, {bool reduceMotion = false}) => ScreenUtilConfig.builder(
  builder:
      (_) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: SizedBox(
              height: 700,
              child: OnboardingDeckCard(
                title: 'How you connect',
                subtitle: 'Question ${step + 1} of 10',
                stepIndex: step,
                enableDeck: true,
                totalSegments: 10,
                progressValue: (step + 1) / 10,
                child: Text('Question ${step + 1}'),
              ),
            ),
          ),
        ),
      ),
);

void main() {
  testWidgets('the deck advance takes kMakeRoomDuration (320 ms)', (t) async {
    expect(kMakeRoomDuration, const Duration(milliseconds: 320));
    await t.pumpWidget(_deck(0));
    await t.pumpAndSettle();
    await t.pumpWidget(_deck(1));
    await t.pump();
    expect(find.byKey(_flying), findsOneWidget);
    await t.pump(kMakeRoomDuration - const Duration(milliseconds: 20));
    expect(find.byKey(_flying), findsOneWidget, reason: 'still moving');
    await t.pump(const Duration(milliseconds: 40));
    expect(find.byKey(_flying), findsNothing, reason: 'settled by 320 ms');
    expect(find.text('Question 2'), findsOneWidget);
  });

  testWidgets('under reduce motion the next card is simply there', (t) async {
    await t.pumpWidget(_deck(0, reduceMotion: true));
    await t.pumpAndSettle();
    await t.pumpWidget(_deck(1, reduceMotion: true));
    await t.pump();
    expect(find.byKey(_flying), findsNothing);
    expect(find.text('Question 2'), findsOneWidget);
  });
}
