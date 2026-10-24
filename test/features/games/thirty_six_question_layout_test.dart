// Stories Wave 3 final review I4 + M1: the 36 Questions answer screen is
// answered with the keyboard up, so Skip and Submit must stay on screen above
// it, with nothing overflowing, on a standard and an SE-class iPhone.
import 'package:attune/features/games/thirty_six_questions/presentation/providers/thirty_six_question_providers.dart';
import 'package:attune/features/games/thirty_six_questions/presentation/screens/thirty_six_question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

// Three lines at 390 pt in the test font (its glyphs are square).
const _question = 'aaaa aaaa aaaa aaaa aaaa aaaa aaaa';

Future<void> _pump(
  WidgetTester t, {
  required Size size,
  required double keyboard,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [partnerNameProvider.overrideWith((ref) async => 'Sam')],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              home: ThirtySixQuestionScreen(
                sessionId: 's1',
                chapter: 1,
                loadOpenRound:
                    () async => (id: 'r1', number: 1, text: _question),
                readPartnerAnswered: (_) async => false,
                watchRound: (_, _) => () {},
              ),
            ),
      ),
    ),
  );
  await t.pump();
  // The buttons scale in (AppButton's entrance animation).
  await t.pump(const Duration(seconds: 1));
}

void main() {
  for (final c in [
    (name: 'iPhone 14/15 (390x844)', size: const Size(390, 844), kb: 336.0),
    (name: 'iPhone SE (375x667)', size: const Size(375, 667), kb: 260.0),
  ]) {
    testWidgets('${c.name} with the keyboard up: no overflow, and Skip and '
        'Submit stay above the keyboard', (t) async {
      await _pump(t, size: c.size, keyboard: c.kb);
      expect(t.takeException(), isNull, reason: 'no RenderFlex overflow');
      expect(find.text(_question), findsOneWidget);
      final keyboardTop = c.size.height - c.kb;
      for (final label in ['Skip question', 'Submit answer']) {
        final button = find.text(label);
        expect(button.hitTestable(), findsOneWidget, reason: label);
        expect(
          t.getRect(button).bottom,
          lessThanOrEqualTo(keyboardTop),
          reason: '$label is not under the keyboard',
        );
      }
    });
  }

  testWidgets('the answer shows one character counter, the field\'s own '
      '(final review M1)', (t) async {
    await _pump(t, size: const Size(390, 844), keyboard: 0);
    expect(find.text('0/400'), findsOneWidget);
    await t.enterText(find.byType(TextFormField), 'Yes');
    await t.pump();
    expect(find.text('3/400'), findsOneWidget);
  });
}
