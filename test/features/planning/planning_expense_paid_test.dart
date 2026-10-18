import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/expense_view.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';
import '../../helpers/info_row_value.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _expense(String id, String text, int minor, String paidBy,
        {String sort = 'a', bool paid = false, String currency = 'GHS'}) =>
    {
      ...fakeItemJson(id: id, text: text, sortKey: sort, checkedAt: paid ? '2026-10-13T10:00:00Z' : null),
      'amount_minor': minor,
      'currency': currency,
      'paid_by': paidBy,
    };

String _m(int minor) => formatPlanningMoney(minor, 'GHS');

void main() {
  test('totals per currency: everything, and what is already paid', () {
    final t = planningExpenseTotals([
      PlanningItem.fromJson(_expense('1', 'Hotel', 20000, 'u-a', paid: true)),
      PlanningItem.fromJson(_expense('2', 'Taxi', 1500, 'u-b')),
      PlanningItem.fromJson(_expense('3', 'Fuel', 4000, 'u-b', currency: 'USD', paid: true)),
    ]);
    expect(t['GHS'], (total: 21500, paid: 20000));
    expect(t['USD'], (total: 4000, paid: 4000));
  });

  final calls = <Map<String, dynamic>>[];
  FakePlanningGateway gateway({bool hotelPaid = false}) {
    calls.clear();
    return FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'x', type: 'expenses', payload: {'title': 'Costs'}, items: [
              _expense('1', 'Hotel', 20000, 'u-a', sort: 'a', paid: hotelPaid),
              _expense('2', 'Taxi', 1500, 'u-b', sort: 'b'),
            ]),
          ]),
      'set_planning_block_item_checked': (p) {
        calls.add(p);
        final checked = p['p_checked'] as bool;
        return p['p_id'] == '1'
            ? _expense('1', 'Hotel', 20000, 'u-a', sort: 'a', paid: checked)
            : _expense('2', 'Taxi', 1500, 'u-b', sort: 'b', paid: checked);
      },
    });
  }

  Text amount(WidgetTester tester, int minor) => tester.widget<Text>(find.text(_m(minor)).first);

  testWidgets('swipe left marks an expense paid: grey initial, struck-through amount, and it leaves the total to pay',
      (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(), _screen));
    await tester.pumpAndSettle();
    expect(infoRowValue(tester, 'Total'), _m(21500));
    expect(amount(tester, 20000).style?.decoration, isNot(TextDecoration.lineThrough));

    await tester.ensureVisible(find.text('Hotel'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Hotel'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(calls.single['p_id'], '1');
    expect(calls.single['p_checked'], isTrue);

    expect(amount(tester, 20000).style?.decoration, TextDecoration.lineThrough);
    final scheme = Theme.of(tester.element(find.text('Hotel'))).colorScheme;
    final avatar = tester.widget<CircleAvatar>(
        find.descendant(of: find.ancestor(of: find.text('Hotel'), matching: find.byType(Row)).first, matching: find.byType(CircleAvatar)));
    expect(avatar.backgroundColor, scheme.primary, reason: 'primary once paid');
    expect(infoRowValue(tester, 'Left to pay'), _m(1500));
    expect(infoRowValue(tester, 'Paid'), _m(20000));
    expect(infoRowValue(tester, 'Total'), _m(21500));
    expect(find.text('Hotel'), findsOneWidget, reason: 'stays in the list; swipe left does not delete');
  });

  testWidgets('an unpaid expense has its initial on light primary', (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(), _screen));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.text('Taxi'))).colorScheme;
    final avatar = tester.widget<CircleAvatar>(
        find.descendant(of: find.ancestor(of: find.text('Taxi'), matching: find.byType(Row)).first, matching: find.byType(CircleAvatar)));
    expect(avatar.backgroundColor, scheme.primary.withValues(alpha: 0.18), reason: 'light primary until paid');
  });

  testWidgets('swiping a paid expense left again marks it unpaid', (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(hotelPaid: true), _screen));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Hotel'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Hotel'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(calls.single['p_checked'], isFalse);
    expect(infoRowValue(tester, 'Total'), _m(21500));
  });

  testWidgets('with everything paid the total says so', (tester) async {
    final g = gateway(hotelPaid: true);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Taxi'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Taxi'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(infoRowValue(tester, 'Total'), _m(21500));
    expect(infoRowSubtitle(tester, 'Total'), 'All paid');
  });

  testWidgets('screen readers get the swipe actions too: Mark as paid and Delete', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningTestApp(gateway(), _screen));
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.text('Taxi'));
    final labels = [
      for (final id in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        CustomSemanticsAction.getAction(id)?.label,
    ];
    expect(labels, containsAll(['Mark as paid', 'Delete']));
    semantics.dispose();
  });

  testWidgets('in the totals, only the amounts are coloured: paid primary, left to pay red, total as it was',
      (tester) async {
    await tester.pumpWidget(planningTestApp(gateway(hotelPaid: true), _screen));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.text('Hotel').first)).colorScheme;
    InfoRowWidget row(String title) =>
        tester.widgetList<InfoRowWidget>(find.byType(InfoRowWidget)).where((r) => r.title == title).single;
    Color? amount(String title) => infoRowTrailingText(tester, title)?.style?.color;
    expect(amount('Paid'), scheme.primary);
    expect(amount('Left to pay'), scheme.error);
    expect(amount('Total'), Theme.of(tester.element(find.text('Hotel').first)).textTheme.bodyLarge?.color,
        reason: 'the usual text colour, as before');
    for (final t in ['Paid', 'Left to pay', 'Total']) {
      expect(row(t).titleFontColor, isNull, reason: '$t: the title keeps its colour');
      expect(row(t).iconColor, isNull, reason: '$t: the icon keeps its colour');
    }
  });
}
