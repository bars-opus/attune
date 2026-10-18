import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/charts/app_pie_chart.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/expense_view.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/info_row_value.dart';

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

  testWidgets('one expense: no chart', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 'x', type: 'expenses', items: [_expense('1', 'Hotel', 20000)]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    expect(find.byType(AppPieChart), findsNothing);
  });

  test('compact amounts for the wedges', () {
    expect(formatPlanningMoneyCompact(20000, 'GHS'), contains('200'));
    expect(formatPlanningMoneyCompact(250000, 'GHS'), contains('2.5K'));
  });

  testWidgets('dividers separate the header from the expenses, and the totals from Add expense', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 'x', type: 'expenses', items: [_expense('1', 'Hotel', 20000), _expense('2', 'Taxi', 1500)]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    double y(Finder f) => tester.getTopLeft(f).dy;
    // The block's own dividers, not the ones between expense lines, by
    // their rendered positions (both are the same const widget).
    final ys = [
      for (final e in find.byType(AppDivider).evaluate())
        if (find
            .ancestor(
                of: find.byElementPredicate((x) => x == e),
                matching: find.byWidgetPredicate((w) => '${w.key}'.contains('expense-line-')))
            .evaluate()
            .isEmpty)
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
    ]..sort();
    // No chart here any more (it is the Budget's Breakdown): under the
    // Items/Prices header, above the totals, above the Total row, and
    // between the totals and Add expense.
    expect(ys, hasLength(4));
    expect(ys[0], greaterThan(y(find.text('Items'))), reason: 'under the header');
    expect(ys[0], lessThan(y(find.text('Hotel').last)), reason: 'above the expenses');
    expect(ys[1], lessThan(y(find.text('Total'))), reason: 'above the totals');
    expect(ys[2], lessThan(y(find.text('Total'))), reason: 'above the Total row');
    expect(ys[3], greaterThan(y(find.text('Total'))), reason: 'below the total');
    expect(ys[3], lessThan(y(find.text('Add expense'))), reason: 'above Add expense');
  });

  testWidgets('with nothing spent, no stray dividers', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'x', type: 'expenses')]),
        }),
        _screen));
    await tester.pumpAndSettle();
    expect(find.byType(AppDivider), findsNothing);
  });

  FakePlanningGateway three() => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 'x', type: 'expenses', items: [
                _expense('1', 'Hotel', 20000),
                _expense('2', 'Taxi', 1500),
                _expense('3', 'Food', 8000),
              ]),
            ]),
      });

  testWidgets("each expense is the app's InfoRowWidget without its own divider; an AppDivider sits between them",
      (tester) async {
    await tester.pumpWidget(planningTestApp(three(), _screen));
    await tester.pumpAndSettle();
    // The expense lines' rows (the totals below are InfoRowWidgets too).
    final rows = tester
        .widgetList<InfoRowWidget>(find.descendant(
            of: find.byWidgetPredicate((w) => '${w.key}'.contains('expense-line-')), matching: find.byType(InfoRowWidget)))
        .toList();
    expect([for (final r in rows) r.title], ['Hotel', 'Taxi', 'Food']);
    expect([for (final r in rows) r.showDivider], [false, false, false]);
    expect(rows.first.trailing, isA<Text>(), reason: 'the amount sits at the end of the row');
    double y(String t) => tester.getTopLeft(find.text(t).last).dy;
    final between = [
      for (final e in find.byType(AppDivider).evaluate())
        (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
    ].where((d) => d > y('Hotel') && d < y('Food')).toList();
    expect(between, hasLength(2), reason: 'one under Hotel, one under Taxi, none after Food');
    expect(between.first, lessThan(y('Taxi')));
  });

  testWidgets('a header names the columns: Items over the names, Prices over the amounts', (tester) async {
    await tester.pumpWidget(planningTestApp(three(), _screen));
    await tester.pumpAndSettle();
    final item = tester.getRect(find.text('Items'));
    final price = tester.getRect(find.text('Prices'));
    expect(item.bottom, lessThanOrEqualTo(tester.getTopLeft(find.text('Hotel').last).dy), reason: 'above the rows');
    expect(item.left, moreOrLessEquals(tester.getTopLeft(find.text('Hotel').last).dx, epsilon: 1), reason: 'over the names');
    expect(price.right,
        moreOrLessEquals(tester.getTopRight(find.text(formatPlanningMoney(20000, 'GHS'))).dx, epsilon: 1),
        reason: 'over the amounts');
  });

  testWidgets('no header while nothing is spent', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'x', type: 'expenses')])}),
        _screen));
    await tester.pumpAndSettle();
    expect(find.text('Items'), findsNothing);
    expect(find.text('Prices'), findsNothing);
  });

  testWidgets('expense names are normal weight; the total amount is bold', (tester) async {
    await tester.pumpWidget(planningTestApp(three(), _screen));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).toList();
    final hotel = rows.firstWhere((r) => r.title == 'Hotel');
    expect(hotel.titleStyle?.fontWeight, FontWeight.normal);
    expect(infoRowTrailingText(tester, 'Total')?.style?.fontWeight, FontWeight.bold);
  });
}
