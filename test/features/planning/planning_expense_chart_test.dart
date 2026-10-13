import 'package:attune/core/widgets/charts/rose_chart.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/expense_view.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(String id, String text, int minor, {String currency = 'GHS', String paidBy = 'u-a'}) =>
    {...fakeItemJson(id: id, text: text, sortKey: id), 'amount_minor': minor, 'currency': currency, 'paid_by': paidBy};

PlanningItem _item(String id, String text, int minor, {String currency = 'GHS', bool paid = false}) =>
    PlanningItem.fromJson({..._expense(id, text, minor, currency: currency), if (paid) 'checked_at': '2026-10-13T10:00:00Z'});

void main() {
  group('planningExpenseChart', () {
    test('one slice per line in whole units, biggest first, each paid or not', () {
      final c = planningExpenseChart([
        _item('1', 'Hotel', 20000),
        _item('2', 'Taxi', 1500, paid: true),
        _item('3', 'Taxi', 500),
      ])!;
      expect(c.currency, 'GHS');
      expect([for (final s in c.slices) (s.label, s.value, s.kind)], [
        ('Hotel', 200.0, PlanningChartSlice.unpaid),
        ('Taxi', 15.0, PlanningChartSlice.paid),
        ('Taxi', 5.0, PlanningChartSlice.unpaid),
      ]);
    });

    test('past eight lines the smallest share one Other slice, paid only if all of them are', () {
      final c = planningExpenseChart([for (var i = 1; i <= 10; i++) _item('$i', 'x$i', i * 100, paid: i <= 2)])!;
      expect(c.slices, hasLength(8));
      expect(c.slices.last.label, 'Other');
      expect(c.slices.last.value, 1.0 + 2.0 + 3.0);
      expect(c.slices.last.kind, PlanningChartSlice.unpaid);
    });

    test("with a budget left in the same currency, a last slice shows what's left", () {
      final c = planningExpenseChart(
        [for (var i = 1; i <= 10; i++) _item('$i', 'x$i', i * 100)],
        budgetLeft: (minor: 50000, currency: 'GHS'),
      )!;
      expect(c.slices, hasLength(8));
      expect(c.slices[6].label, 'Other');
      expect((c.slices.last.label, c.slices.last.value, c.slices.last.kind), ('Left in budget', 500.0, PlanningChartSlice.left));
    });

    test('no budget slice when the budget is used up or in another currency', () {
      final items = [_item('1', 'Hotel', 20000), _item('2', 'Taxi', 1500)];
      expect(planningExpenseChart(items, budgetLeft: (minor: 0, currency: 'GHS'))!.slices, hasLength(2));
      expect(planningExpenseChart(items, budgetLeft: (minor: 5000, currency: 'USD'))!.slices, hasLength(2));
    });

    test('fewer than two amounts is not worth a chart', () {
      expect(planningExpenseChart([_item('1', 'Hotel', 20000)]), isNull);
      expect(planningExpenseChart([]), isNull);
    });

    test('with several currencies it charts the one with most spent, and says others are left out', () {
      final c = planningExpenseChart([
        _item('1', 'Hotel', 20000),
        _item('2', 'Taxi', 1500),
        _item('3', 'Visa', 5000, currency: 'USD'),
      ])!;
      expect(c.currency, 'GHS');
      expect(c.otherCurrencies, isTrue);
      expect(c.slices, hasLength(2));
    });
  });

  testWidgets('one solid colour per wedge: primary paid, light primary not yet paid, grey for what is left', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                {
                  ...fakeBlockJson(id: 'bud', type: 'budget', sortKey: 'a', payload: {'title': 'Budget'}),
                  'target_minor': 30000,
                  'target_currency': 'GHS',
                  'computed': {'spent_minor': 21500, 'other_currencies': []},
                },
                fakeBlockJson(id: 'x', type: 'expenses', sortKey: 'b', payload: {'title': 'Costs'}, items: [
                  _expense('1', 'Hotel', 20000),
                  {..._expense('2', 'Taxi', 1500, paidBy: 'u-b'), 'checked_at': '2026-10-13T10:00:00Z'},
                ]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(RoseChart), 100,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
    final scheme = Theme.of(tester.element(find.byType(RoseChart))).colorScheme;
    final chart = tester.widget<RoseChart>(find.byType(RoseChart));
    expect([for (final s in chart.slices) s.label], ['Hotel', 'Taxi', 'Left in budget']);
    expect(chart.slices[0].color, scheme.primary.withValues(alpha: 0.18), reason: 'not yet paid');
    expect(chart.slices[1].color, scheme.primary, reason: 'paid');
    expect(chart.slices[2].color, scheme.outlineVariant, reason: "what's left of the budget");
    expect(chart.slices[2].valueLabel, formatPlanningMoneyCompact(8500, 'GHS'));
    for (final l in ['Paid', 'Not yet paid', 'Left in budget']) {
      expect(find.text(l), findsOneWidget, reason: 'legend: $l');
    }
  });

  testWidgets('without a budget, the legend has just paid and not yet paid', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 'x', type: 'expenses', items: [_expense('1', 'Hotel', 20000), _expense('2', 'Taxi', 1500)]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    expect(find.text('Left in budget'), findsNothing);
    expect(find.text('Not yet paid'), findsOneWidget);
  });

  testWidgets('one expense: no chart', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 'x', type: 'expenses', items: [_expense('1', 'Hotel', 20000)]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    expect(find.byType(RoseChart), findsNothing);
  });

  test('compact amounts for the wedges', () {
    expect(formatPlanningMoneyCompact(20000, 'GHS'), contains('200'));
    expect(formatPlanningMoneyCompact(250000, 'GHS'), contains('2.5K'));
  });
}
