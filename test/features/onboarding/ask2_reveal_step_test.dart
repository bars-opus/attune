// Spec 5 (research 06 §3 F9 (1)): the Ask-2 reward is the person's own two
// anchors reflected back plus "something for tonight" -- never a pairing.
import 'package:attune/features/onboarding/presentation/widgets/ask2_reveal_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<String>> _pump(WidgetTester t, List<String> anchors) async {
  final taps = <String>[];
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: OnboardingDeckScope(
            cardKey: 3,
            accent: OnboardingDeckAccent.couples,
            enableDeck: false,
            child: Ask2RevealStep(
              anchors: anchors,
              onDone: () => taps.add('done'),
              onLoveMap: () => taps.add('love_map'),
              onThisOrThat: () => taps.add('this_or_that'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('reflects the first two anchors back, never the third', (t) async {
    await _pump(t, ['Their patience', 'More laughter', 'I used to go quiet']);
    expect(find.text("You're both in"), findsOneWidget);
    expect(find.textContaining('Their patience'), findsOneWidget);
    expect(find.textContaining('More laughter'), findsOneWidget);
    expect(find.textContaining('I used to go quiet'), findsNothing);
    expect(find.textContaining('compatibility'), findsNothing);
    expect(find.textContaining('pairing'), findsNothing);
  });

  testWidgets('blank anchors are not shown as empty lines', (t) async {
    await _pump(t, ['', '  ', 'x']);
    expect(find.text('You admire'), findsNothing);
    expect(find.text('You hope for more of'), findsNothing);
  });

  testWidgets('something for tonight: a Love map round or This or That', (t) async {
    final taps = await _pump(t, ['a', 'b', 'c']);
    expect(find.text('Something for tonight'), findsOneWidget);
    await t.tap(find.text('A Love map round'));
    await t.tap(find.text('This or That'));
    await t.ensureVisible(find.text('Done'));
    await t.tap(find.text('Done'));
    expect(taps, ['love_map', 'this_or_that', 'done']);
  });
}
