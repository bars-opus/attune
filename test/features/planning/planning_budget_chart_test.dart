// The spending breakdown lives on the Budget, not on Expenses: a Budget tab
// (gauge, Counts, Set budget) and a Breakdown tab (the pie chart and its key
// only), built from whatever the budget counts.
import 'package:attune/core/widgets/charts/app_pie_chart.dart';
import 'package:attune/core/widgets/charts/arc_gauge.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/expense_view.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(
  String id,
  String text,
  int minor, {
  bool paid = false,
}) => {
  ...fakeItemJson(id: id, text: text, sortKey: id),
  'amount_minor': minor,
  'currency': 'GHS',
  'paid_by': 'u-a',
  if (paid) 'checked_at': '2026-10-13T10:00:00Z',
};

Map<String, dynamic> _budget({
  String source = 'all',
  String? sourceId,
  int? target = 30000,
  int spent = 21500,
}) => {
  ...fakeBlockJson(
    id: 'bud',
    type: 'budget',
    sortKey: 'a',
    payload: {'title': 'Budget'},
  ),
  'target_minor': target,
  'target_currency': 'GHS',
  'computed': {
    'spent_minor': spent,
    'other_currencies': [],
    'source': source,
    'source_block_id': sourceId,
  },
};

final _costs = fakeBlockJson(
  id: 'x',
  type: 'expenses',
  sortKey: 'b',
  payload: {'title': 'Costs'},
  items: [
    _expense('1', 'Hotel', 20000),
    _expense('2', 'Taxi', 1500, paid: true),
  ],
);
final _food = fakeBlockJson(
  id: 'y',
  type: 'expenses',
  sortKey: 'c',
  payload: {'title': 'Food'},
  items: [_expense('3', 'Dinner', 3000)],
);
Map<String, dynamic> _table({bool withPaid = true}) => fakeBlockJson(
  id: 't',
  type: 'table',
  sortKey: 'd',
  payload: {
    'title': 'Bills',
    'columns': [
      {'key': 'c0', 'label': 'Bill', 'type': 'text'},
      {'key': 'c1', 'label': 'Amount', 'type': 'money'},
      {'key': 'c2', 'label': 'Extra', 'type': 'money'},
      if (withPaid) {'key': 'c3', 'label': 'Paid', 'type': 'check'},
    ],
  },
  items: [
    {
      ...fakeItemJson(id: 'r1', sortKey: 'a'),
      'cells': {
        'c0': 'Rent',
        'c1': 150000,
        'c2': 5000,
        if (withPaid) 'c3': true,
      },
    },
    {
      ...fakeItemJson(id: 'r2', sortKey: 'b'),
      'cells': {'c0': 'Water', 'c1': 4000},
    },
  ],
);

List<PlanningBlock> _blocks(List<Map<String, dynamic>> j) => [
  for (final b in j) PlanningBlock.fromJson(b),
];

Future<void> _open(WidgetTester t, List<Map<String, dynamic>> blocks) async {
  await t.pumpWidget(
    planningTestApp(
      FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks),
      }),
      _screen,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _breakdown(WidgetTester t) async {
  await t.tap(find.text('Breakdown'));
  await t.pumpAndSettle();
}

void main() {
  group('planningBudgetChart', () {
    test(
      'all expenses: a slice per line across every Expenses block, then what is left',
      () {
        final blocks = _blocks([_budget(), _costs, _food]);
        final c =
            planningBudgetChart(blocks.first, blocks, planCurrency: 'GHS')!;
        expect(
          [for (final s in c.slices) s.label],
          ['Hotel', 'Dinner', 'Taxi', 'Left in budget'],
        );
        expect(c.slices.last.value, (30000 - 21500) / 100);
      },
    );

    test('one Expenses block: only its lines', () {
      final blocks = _blocks([
        _budget(source: 'expenses', sourceId: 'y', spent: 3000),
        _costs,
        _food,
        fakeBlockJson(
          id: 'z',
          type: 'expenses',
          items: [_expense('4', 'Snacks', 500)],
        ),
      ]);
      final c = planningBudgetChart(blocks.first, blocks, planCurrency: 'GHS');
      expect(c, isNull, reason: 'one line is not worth a chart');
      final two = _blocks([
        _budget(source: 'expenses', sourceId: 'x'),
        _costs,
        _food,
      ]);
      expect(
        [
          for (final s
              in planningBudgetChart(
                two.first,
                two,
                planCurrency: 'GHS',
              )!.slices)
            s.label,
        ],
        ['Hotel', 'Taxi', 'Left in budget'],
      );
    });

    test(
      'a table: a slice per row, named by its first text cell, its money cells added up; paid from its Paid column',
      () {
        final blocks = _blocks([
          _budget(source: 'table', sourceId: 't', target: null),
          _table(),
        ]);
        final c =
            planningBudgetChart(blocks.first, blocks, planCurrency: 'GHS')!;
        expect(
          [for (final s in c.slices) (s.label, s.value, s.kind)],
          [
            ('Rent', 1550.0, PlanningChartSlice.paid),
            ('Water', 40.0, PlanningChartSlice.unpaid),
          ],
        );
      },
    );

    test('a table with no yes/no column: every row is just counted', () {
      final blocks = _blocks([
        _budget(source: 'table', sourceId: 't', target: null),
        _table(withPaid: false),
      ]);
      expect(
        {
          for (final s
              in planningBudgetChart(
                blocks.first,
                blocks,
                planCurrency: 'GHS',
              )!.slices)
            s.kind,
        },
        {PlanningChartSlice.counted},
      );
    });
  });

  testWidgets('the Budget tab: gauge, Counts and Set budget; no chart', (
    t,
  ) async {
    await _open(t, [_budget(), _costs]);
    expect(find.text('Budget'), findsWidgets);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.byType(ArcGauge), findsOneWidget);
    expect(
      find.widgetWithText(InfoRowWidget, 'Counts: All expenses'),
      findsOneWidget,
    );
    expect(find.text('Set budget'), findsOneWidget);
    expect(find.byType(AppPieChart), findsNothing);
  });

  testWidgets('the Breakdown tab: only the chart and its key', (t) async {
    await _open(t, [_budget(), _costs]);
    await _breakdown(t);
    expect(find.byType(AppPieChart), findsOneWidget);
    expect(find.byType(ArcGauge), findsNothing);
    expect(find.textContaining('Counts:'), findsNothing);
    expect(find.text('Set budget'), findsNothing);
    final scheme = Theme.of(t.element(find.byType(AppPieChart))).colorScheme;
    final chart = t.widget<AppPieChart>(find.byType(AppPieChart));
    expect(
      [for (final s in chart.slices) s.label],
      ['Hotel', 'Taxi', 'Left in budget'],
    );
    expect(
      chart.slices[0].color,
      scheme.primary.withValues(alpha: 0.18),
      reason: 'not yet paid',
    );
    expect(chart.slices[1].color, scheme.primary, reason: 'paid');
    expect(
      chart.slices[2].color,
      scheme.outlineVariant,
      reason: "what's left of the budget",
    );
    expect(chart.slices[2].valueLabel, formatPlanningMoneyCompact(8500, 'GHS'));
    final sections = t.widget<PieChart>(find.byType(PieChart)).data.sections;
    final whole = sections.fold<double>(0, (sum, s) => sum + s.value);
    expect(
      sections[0].value / whole,
      moreOrLessEquals(20000 / 30000),
      reason: 'Hotel is two-thirds of the budget',
    );
    for (final l in ['Paid', 'Not yet paid', 'Left in budget']) {
      expect(
        find.descendant(of: find.byType(Wrap), matching: find.text(l)),
        findsOneWidget,
        reason: 'key: $l',
      );
    }
  });

  testWidgets('the key is centred under the chart', (t) async {
    await _open(t, [_budget(), _costs]);
    await _breakdown(t);
    final legend =
        find
            .ancestor(
              of: find.text('Not yet paid'),
              matching: find.byType(Wrap),
            )
            .first;
    expect(
      t.getCenter(legend).dx,
      moreOrLessEquals(t.getCenter(find.byType(AppPieChart)).dx, epsilon: 2),
    );
  });

  testWidgets('a table with no Paid column: the key just says Counted', (
    t,
  ) async {
    await _open(t, [
      _budget(source: 'table', sourceId: 't', target: null),
      _table(withPaid: false),
    ]);
    await _breakdown(t);
    expect(
      find.descendant(of: find.byType(Wrap), matching: find.text('Counted')),
      findsOneWidget,
    );
    expect(find.text('Not yet paid'), findsNothing);
    expect(
      find.text('Left in budget'),
      findsNothing,
      reason: 'no target, nothing left to show',
    );
  });

  testWidgets('too little to chart: Breakdown says so', (t) async {
    await _open(t, [
      _budget(),
      fakeBlockJson(
        id: 'x',
        type: 'expenses',
        items: [_expense('1', 'Hotel', 20000)],
      ),
    ]);
    await _breakdown(t);
    expect(find.byType(AppPieChart), findsNothing);
    expect(
      find.text('Add at least two amounts to see a breakdown.'),
      findsOneWidget,
    );
  });

  testWidgets('Expenses no longer carries a chart', (t) async {
    await _open(t, [_costs]);
    expect(find.byType(AppPieChart), findsNothing);
    expect(find.text('Not yet paid'), findsNothing);
  });
}
