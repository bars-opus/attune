// Spec 8 (research 06 F14; plan review I1, M1): the private safety check.
// Four items (clinician sign-off pending: [DRAFT]), each yes / no / prefer
// not to say; the answers go to the server and are never shown again; the
// card shown at the end comes from the server.
import 'package:attune/features/safety/self_check/safety_self_check_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake extends SafetySelfCheckService {
  _Fake(this.card);
  final String card;
  Map<String, String>? sent;

  @override
  Future<String> submit(
    String relationshipId,
    Map<String, String> answers,
  ) async {
    sent = answers;
    if (card == 'throw') throw Exception('offline');
    return card;
  }
}

Future<_Fake> _pump(WidgetTester t, String card) async {
  t.view.physicalSize = const Size(1170, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  final fake = _Fake(card);
  await t.pumpWidget(
    ProviderScope(
      overrides: [safetySelfCheckServiceProvider.overrideWithValue(fake)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => const MaterialApp(
              home: SafetySelfCheckScreen(relationshipId: 'r1'),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return fake;
}

Future<void> _answer(WidgetTester t, int item, String label) async {
  final chip = find.byKey(ValueKey('safety-q$item-$label'));
  await t.ensureVisible(chip);
  await t.tap(chip);
  await t.pump();
}

void main() {
  testWidgets(
    'four items, each answerable; Submit only when all are answered',
    (t) async {
      final fake = await _pump(t, 'none');
      expect(find.textContaining('[DRAFT]'), findsNWidgets(4));
      expect(find.textContaining('never stored'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
            .onPressed,
        isNull,
      );
      await _answer(t, 1, 'no');
      await _answer(t, 2, 'prefer_not');
      await _answer(t, 3, 'no');
      await _answer(t, 4, 'yes');
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      expect(fake.sent, {
        'q1': 'no',
        'q2': 'prefer_not',
        'q3': 'no',
        'q4': 'yes',
      });
    },
  );

  testWidgets('the server decides the card: resources once', (t) async {
    await _pump(t, 'resources');
    for (var i = 1; i <= 4; i++) {
      await _answer(t, i, 'no');
    }
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text("You don't have to face this alone."), findsOneWidget);
    expect(find.text('See support options'), findsOneWidget);
    // The answers are not shown back.
    expect(find.textContaining('[DRAFT]'), findsNothing);
  });

  testWidgets('all prefer-not: the plain link; no answers repeated', (t) async {
    await _pump(t, 'plain');
    for (var i = 1; i <= 4; i++) {
      await _answer(t, i, 'prefer_not');
    }
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Support is here whenever you want it.'), findsOneWidget);
    expect(find.text("You don't have to face this alone."), findsNothing);
  });

  // Final review m-5: nothing is stored, so the screen never says "save".
  testWidgets('a failed send says so, without promising storage', (t) async {
    await _pump(t, 'throw');
    for (var i = 1; i <= 4; i++) {
      await _answer(t, i, 'no');
    }
    await t.tap(find.text('Done'));
    await t.pump();
    expect(find.text("Couldn't send it. Try again."), findsOneWidget);
    expect(find.textContaining('save'), findsNothing);
  });

  test('the entry row reads the same whatever was answered (I1)', () {
    expect(
      safetySelfCheckRowTitle,
      'A private check-in about how safe you feel',
    );
    expect(safetySelfCheckDue(null, DateTime(2026, 10, 18)), isTrue);
    expect(
      safetySelfCheckDue(DateTime(2026, 7, 1), DateTime(2026, 10, 18)),
      isTrue,
    );
    expect(
      safetySelfCheckDue(DateTime(2026, 9, 1), DateTime(2026, 10, 18)),
      isFalse,
    );
  });
}
