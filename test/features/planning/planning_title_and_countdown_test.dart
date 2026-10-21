// A category's screen names it with its icon; a countdown reads like the
// couple's days-together count: a big number, "days" over "to go".
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/core/widgets/app_days_count.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/countdown_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

String _ymd(DateTime d) => planningYmd(d);

Map<String, dynamic> _countdownIn(int days) {
  final today = DateUtils.dateOnly(DateTime.now());
  return {
    ...fakeBlockJson(id: 'cd', type: 'countdown', payload: {'title': 'Trip'}),
    'computed': {
      'target_date': _ymd(today.add(Duration(days: days))),
      'date_block_id': null,
    },
  };
}

Future<void> _openCountdown(WidgetTester t, int days) async {
  await t.pumpWidget(
    planningTestApp(
      FakePlanningGateway({
        'get_planning_entry':
            (_) => fakeEntryDetailJson(blocks: [_countdownIn(days)]),
      }),
      const PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1'),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'the category screen\'s title is its icon, in its colour, then its name',
    (t) async {
      final cat = PlanningCategory.fromJson(
        fakeCategoryJson(
          id: 'c1',
          seedKey: 'trips',
          name: 'Trips',
          icon: 'plane',
          color: 'teal',
        ),
      );
      await t.pumpWidget(
        planningTestApp(
          FakePlanningGateway({
            'list_planning_entries':
                (_) => {'entries': [], 'next_cursor': null},
          }),
          PlanningCategoryScreen(relationshipId: 'r1', category: cat),
        ),
      );
      await t.pumpAndSettle();
      final bar = find.byType(AppBar);
      final icon = find.descendant(
        of: bar,
        matching: find.byIcon(planningIcon('plane')),
      );
      final name = find.descendant(of: bar, matching: find.text('Trips'));
      expect(icon, findsOneWidget);
      expect(name, findsOneWidget);
      expect(
        t.getCenter(icon).dx,
        lessThan(t.getCenter(name).dx),
        reason: 'icon first',
      );
      final circle = t.widget<CircleAvatar>(
        find.ancestor(of: icon, matching: find.byType(CircleAvatar)),
      );
      expect(
        circle.backgroundColor,
        planningCategoryFill(t.element(icon), 'teal'),
      );
    },
  );

  testWidgets('a plan\'s app bar is transparent, like its category\'s', (t) async {
    await _openCountdown(t, 5);
    expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, Colors.transparent);
  });

  testWidgets('a countdown: the number big, "days" over "to go", rolling in', (
    t,
  ) async {
    await _openCountdown(t, 232);
    expect(find.byType(AppDaysCount), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppDaysCount),
        matching: find.byType(AnimatedRollingCounter),
      ),
      findsOneWidget,
    );
    expect(find.text('232'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.text('to go'), findsOneWidget);
  });

  testWidgets('one day: "day", not "days"', (t) async {
    await _openCountdown(t, 1);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('day'), findsOneWidget);
    expect(find.text('to go'), findsOneWidget);
  });

  testWidgets('on the day: Today', (t) async {
    await _openCountdown(t, 0);
    // The plan's header chip says Today too; this is the block's.
    expect(
      find.descendant(
        of: find.byType(CountdownBlockView),
        matching: find.text('Today'),
      ),
      findsOneWidget,
    );
    expect(find.text('to go'), findsNothing);
  });

  testWidgets('after the day: days ago', (t) async {
    await _openCountdown(t, -3);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('ago'), findsOneWidget);
  });
}
