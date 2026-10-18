// test/features/pulse/your_week_card_test.dart
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/presentation/widgets/your_week_card.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show yourWeekProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, YourWeek week) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [yourWeekProvider.overrideWith((ref) async => week)],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: YourWeekCard()),
              ),
            ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

const _answers = WeeklyCheckinAnswers(
  communication: 8,
  connection: 7,
  conflictHealth: null,
  conflictHealthNA: true,
  alignment: 9,
  safety: 6,
);

void main() {
  testWidgets('no check-in yet: the card says so and shows no number', (
    t,
  ) async {
    await _pump(t, const YourWeek());
    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('Only you can see this.'), findsOneWidget);
    expect(find.text('No check-in this week yet.'), findsOneWidget);
    expect(find.text('Emotional safety'), findsNothing);
  });

  testWidgets('with a check-in: my private score and my answers', (t) async {
    await _pump(
      t,
      YourWeek(
        checkin: _answers,
        emotionalSafety: 71,
        weekEnding: DateTime.utc(2026, 10, 18),
      ),
    );
    expect(find.text('Emotional safety'), findsOneWidget);
    expect(find.text('71'), findsOneWidget);
    expect(find.text('8/10'), findsOneWidget);
    expect(find.text('Not this week'), findsOneWidget);
    expect(find.text('6/10'), findsOneWidget);
  });

  testWidgets('a check-in whose score is not computed yet shows a dash', (
    t,
  ) async {
    await _pump(t, const YourWeek(checkin: _answers));
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('fromJson reads the check-in row', (t) async {
    final a = WeeklyCheckinAnswers.fromJson({
      'communication_rating': 8,
      'connection_rating': 7,
      'conflict_health_rating': null,
      'conflict_health_na': true,
      'alignment_rating': 9,
      'safety_rating': 6,
    });
    expect(a, _answers);
  });
}
