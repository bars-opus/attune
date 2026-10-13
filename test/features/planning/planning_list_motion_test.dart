import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

double _opacity(WidgetTester tester, String text) =>
    tester.widget<FadeTransition>(find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first).opacity.value;

void main() {
  FakePlanningGateway checklist() => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 'c', payload: {'title': 'Packing'}, items: [
                fakeItemJson(id: 'i1', text: 'Sunscreen', sortKey: 'a'),
                fakeItemJson(id: 'i2', text: 'Passport', sortKey: 'b'),
                fakeItemJson(id: 'i3', text: 'Towel', sortKey: 'c', checkedAt: '2026-10-13T09:00:00Z'),
              ]),
            ]),
        'set_planning_block_item_checked': (p) => fakeItemJson(
            id: p['p_id'] as String, text: 'Sunscreen', sortKey: 'a', checkedAt: '2026-10-13T10:00:00Z', version: 2),
      });

  testWidgets('a ticked checklist item folds out of the list instead of vanishing', (tester) async {
    await tester.pumpWidget(planningTestApp(checklist(), _screen));
    await tester.pumpAndSettle();
    final passportStart = tester.getTopLeft(find.text('Passport')).dy;
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Sunscreen'), findsOneWidget, reason: 'still folding away');
    expect(_opacity(tester, 'Sunscreen'), inExclusiveRange(0, 1));
    expect(tester.getTopLeft(find.text('Passport')).dy, lessThan(passportStart), reason: 'the next item is moving up');
    await tester.pumpAndSettle();
    expect(find.text('Sunscreen'), findsNothing, reason: 'in the done list, which is collapsed');
  });

  testWidgets('opening the done list lets its items grow in', (tester) async {
    await tester.pumpWidget(planningTestApp(checklist(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, 'Towel'), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(_opacity(tester, 'Towel'), 1);
  });

  testWidgets('a deleted table row folds out of the grid', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 't', type: 'table', payload: {
              'title': 'Itinerary',
              'columns': [
                {'key': 'c0', 'label': 'Day', 'type': 'text'},
              ],
            }, items: [
              {...fakeItemJson(id: 'r1', sortKey: 'a'), 'cells': {'c0': 'Mon'}},
              {...fakeItemJson(id: 'r2', sortKey: 'b'), 'cells': {'c0': 'Tue'}},
            ]),
          ]),
      'delete_planning_block_item': (_) => {'deleted': true},
    });
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    final tueStart = tester.getTopLeft(find.text('Tue')).dy;
    await tester.drag(find.text('Mon'), const Offset(500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // the swipe settles back
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Mon'), findsOneWidget, reason: 'still folding away');
    expect(tester.getTopLeft(find.text('Tue')).dy, lessThan(tueStart));
    await tester.pumpAndSettle();
    expect(find.text('Mon'), findsNothing);
  });
}
