// Headline amounts roll up from 0 when their block first shows (and from
// the old figure when they change), then settle as plain text: the budget's
// gauge and "spent", the Expenses totals, a table's totals and a progress
// figure. Line items never roll.
import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(String id, String text, int minor) => {
  ...fakeItemJson(id: id, text: text, sortKey: id),
  'amount_minor': minor,
  'currency': 'GHS',
  'paid_by': 'u-a',
};

Future<void> _open(WidgetTester t, List<Map<String, dynamic>> blocks) =>
    t.pumpWidget(
      planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
        }),
        _screen,
      ),
    );

Finder _counterIn(Finder of) =>
    find.descendant(of: of, matching: find.byType(AnimatedRollingCounter));
Finder _rollingIn(Finder of) => find.descendant(
  of: _counterIn(of),
  matching: find.byKey(const ValueKey('animated-rolling-counter-rolling')),
);

void main() {
  testWidgets(
    'the budget: its gauge headline and "spent" roll up, then read as before',
    (t) async {
      await _open(t, [
        {
          ...fakeBlockJson(
            id: 'bud',
            type: 'budget',
            payload: {'title': 'Budget'},
          ),
          'target_minor': 30000,
          'target_currency': 'GHS',
          'computed': {'spent_minor': 23000, 'other_currencies': []},
        },
      ]);
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      expect(
        _rollingIn(find.byType(ArcGauge)),
        findsWidgets,
        reason: 'the headline is rolling',
      );
      await t.pumpAndSettle();
      expect(
        find.text('${formatPlanningMoney(7000, 'GHS')} left'),
        findsOneWidget,
      );
      expect(
        find.text('${formatPlanningMoney(23000, 'GHS')} spent'),
        findsOneWidget,
      );
      expect(_counterIn(find.byType(ArcGauge)), findsOneWidget);
    },
  );

  testWidgets('Expenses: the totals roll; the expense lines do not', (t) async {
    await _open(t, [
      fakeBlockJson(
        id: 'x',
        type: 'expenses',
        items: [_expense('1', 'Hotel', 20000), _expense('2', 'Taxi', 1500)],
      ),
    ]);
    await t.pumpAndSettle();
    final lines = find.byWidgetPredicate(
      (w) => '${w.key}'.contains('expense-line-'),
    );
    expect(lines, findsWidgets);
    expect(_counterIn(lines), findsNothing, reason: 'line items stay still');
    expect(find.text(formatPlanningMoney(21500, 'GHS')), findsWidgets);
    expect(
      find.byType(AnimatedRollingCounter),
      findsWidgets,
      reason: 'the totals roll',
    );
  });

  testWidgets('a table: its Total row and Total of all roll', (t) async {
    await _open(t, [
      fakeBlockJson(
        id: 't',
        type: 'table',
        payload: {
          'title': 'Costs',
          'columns': [
            {'key': 'c0', 'label': 'Day', 'type': 'text'},
            {'key': 'c1', 'label': 'Flights', 'type': 'money'},
            {'key': 'c2', 'label': 'Hotel', 'type': 'money'},
          ],
        },
        items: [
          {
            ...fakeItemJson(id: 'r1'),
            'cells': {'c0': 'Mon', 'c1': 200000, 'c2': 80000},
          },
        ],
      ),
    ]);
    await t.pumpAndSettle();
    expect(
      _counterIn(find.byKey(const ValueKey('planning-table-total'))),
      findsNWidgets(2),
    );
    expect(
      _counterIn(find.byKey(const ValueKey('planning-table-grand-total'))),
      findsOneWidget,
    );
    final currency = 'GHS';
    expect(
      find.text('Total of all: ${formatPlanningMoney(280000, currency)}'),
      findsOneWidget,
    );
  });

  testWidgets('a progress figure rolls', (t) async {
    await _open(t, [
      {
        ...fakeBlockJson(
          id: 'p',
          type: 'progress',
          payload: {'mode': 'numeric', 'unit': 'money'},
        ),
        'target_minor': 100000,
        'target_currency': 'GHS',
        'computed': {'mode': 'numeric', 'current': 40000},
      },
    ]);
    await t.pumpAndSettle();
    expect(find.byType(AnimatedRollingCounter), findsOneWidget);
    expect(
      find.text(
        '${formatPlanningMoney(40000, 'GHS')} of ${formatPlanningMoney(100000, 'GHS')}',
      ),
      findsOneWidget,
    );
  });
}
