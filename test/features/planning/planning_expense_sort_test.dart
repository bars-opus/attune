import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/expense_view.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';
import '../../helpers/info_row_value.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(String id, String text, int? minor, String paidBy, {String currency = 'GHS', String sort = 'a'}) =>
    {...fakeItemJson(id: id, text: text, sortKey: sort), 'amount_minor': minor, 'currency': currency, 'paid_by': paidBy};

void main() {
  final items = [
    for (final j in [
      _expense('1', 'Hotel', 20000, 'u-a', sort: 'a'),
      _expense('2', 'Taxi', 1500, 'u-b', sort: 'b'),
      _expense('3', 'Dinner', 8000, 'u-a', sort: 'c'),
      _expense('4', 'Tip', null, 'u-b', sort: 'd'),
      _expense('5', 'Ferry', 9000, 'u-b', sort: 'e'),
    ])
      PlanningItem.fromJson(j),
  ];
  List<String> names(PlanningExpenseView v) => [for (final i in planningExpenseRows(items, v)) i.text];

  test('order added is the order they were added', () {
    expect(names(const PlanningExpenseView()), ['Hotel', 'Taxi', 'Dinner', 'Tip', 'Ferry']);
  });

  test('lowest to highest and highest to lowest; a line with no amount goes last either way', () {
    expect(names(const PlanningExpenseView(sort: PlanningExpenseSort.lowest)), ['Taxi', 'Dinner', 'Ferry', 'Hotel', 'Tip']);
    expect(names(const PlanningExpenseView(sort: PlanningExpenseSort.highest)), ['Hotel', 'Ferry', 'Dinner', 'Taxi', 'Tip']);
  });

  test('showing one partner keeps only what they paid, in the chosen order', () {
    expect(names(const PlanningExpenseView(paidBy: 'u-b')), ['Taxi', 'Tip', 'Ferry']);
    expect(names(const PlanningExpenseView(paidBy: 'u-b', sort: PlanningExpenseSort.highest)), ['Ferry', 'Taxi', 'Tip']);
  });

  test('amounts compare in whole units, so a currency without cents sorts fairly', () {
    final mixed = [
      PlanningItem.fromJson(_expense('a', 'Yen', 1000, 'u-a', currency: 'JPY')), // ¥1,000
      PlanningItem.fromJson(_expense('b', 'Cedis', 5000, 'u-a')), // GH₵50.00
    ];
    expect([for (final i in planningExpenseRows(mixed, const PlanningExpenseView(sort: PlanningExpenseSort.lowest))) i.text],
        ['Cedis', 'Yen']);
  });

  FakePlanningGateway gateway() => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 'x', type: 'expenses', payload: {'title': 'Costs'}, items: [
                _expense('1', 'Hotel', 20000, 'u-a', sort: 'a'),
                _expense('2', 'Taxi', 1500, 'u-b', sort: 'b'),
                _expense('3', 'Dinner', 8000, 'u-a', sort: 'c'),
              ]),
            ]),
      });

  List<String> shown(WidgetTester tester) {
    final ys = {for (final t in ['Hotel', 'Taxi', 'Dinner']) if (find.text(t).evaluate().isNotEmpty) t: tester.getTopLeft(find.text(t)).dy};
    return (ys.keys.toList()..sort((a, b) => ys[a]!.compareTo(ys[b]!)));
  }

  Future<void> choose(WidgetTester tester, String option) async {
    await tester.tap(find.byTooltip('Options for Costs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
  }

  testWidgets('the ⋮ menu sorts the expenses and shows one partner at a time, with a ✓ on the current choice',
      (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(), _screen));
    await tester.pumpAndSettle();
    expect(shown(tester), ['Hotel', 'Taxi', 'Dinner']);

    await tester.tap(find.byTooltip('Options for Costs'));
    await tester.pumpAndSettle();
    for (final o in ['Order added', 'Lowest to highest', 'Highest to lowest', 'Paid by anyone', 'Paid by Ama', 'Paid by Kofi']) {
      expect(find.text(o), findsOneWidget, reason: o);
    }
    expect(tester.widget<CheckedPopupMenuItem<Object>>(find.ancestor(of: find.text('Order added'), matching: find.byType(CheckedPopupMenuItem<Object>))).checked,
        isTrue);
    await tester.tapAt(const Offset(5, 5)); // close the menu
    await tester.pumpAndSettle();

    await choose(tester, 'Lowest to highest');
    expect(shown(tester), ['Taxi', 'Dinner', 'Hotel']);
    await choose(tester, 'Highest to lowest');
    expect(shown(tester), ['Hotel', 'Dinner', 'Taxi']);

    await choose(tester, 'Paid by Ama');
    expect(shown(tester), ['Hotel', 'Dinner']);
    expect(find.text('Paid by Ama'), findsWidgets, reason: 'the totals say whose they are');
    expect(infoRowValue(tester, 'Total'), formatPlanningMoney(28000, 'GHS'), reason: "the total is just Ama's");
    await choose(tester, 'Paid by anyone');
    expect(shown(tester), ['Hotel', 'Dinner', 'Taxi']);
    expect(infoRowValue(tester, 'Total'), isNotNull);
  });

  testWidgets('sorting glides the lines to their new places rather than jumping', (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(), _screen));
    await tester.pumpAndSettle();
    final hotelStart = tester.getTopLeft(find.text('Hotel')).dy;
    final dinnerStart = tester.getTopLeft(find.text('Dinner')).dy;
    await tester.tap(find.byTooltip('Options for Costs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lowest to highest')); // Taxi, Dinner, Hotel: Hotel goes to the bottom
    await tester.pump(); // the menu closes and the move starts
    await tester.pump(const Duration(milliseconds: 60));
    final hotelMid = tester.getTopLeft(find.text('Hotel')).dy;
    expect(hotelMid, greaterThan(hotelStart), reason: 'on its way down');
    expect(hotelMid, lessThan(dinnerStart), reason: 'not there yet');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Hotel')).dy, moreOrLessEquals(dinnerStart));
  });
}
