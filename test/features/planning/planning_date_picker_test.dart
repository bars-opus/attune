import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway(List<Map<String, dynamic>> blocks) =>
    FakePlanningGateway({'get_planning_entry': (_) => fakeEntryDetailJson(blocks: blocks)});

/// Turns the wheel, then closes the sheet the way a person would: a tap above it.
Future<void> _pick(WidgetTester tester, DateTime d) async {
  expect(find.byType(DatePickerDialog), findsNothing, reason: 'the Cupertino wheel, not the calendar');
  tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker)).onDateTimeChanged(d);
  await tester.pump();
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Date block: A single date is picked on the Cupertino wheel and saved when the sheet closes', (tester) async {
    final g = _gateway([fakeBlockJson(id: 'd1', type: 'date', payload: {'title': 'When'})]);
    g.handlers['update_planning_block'] = (p) => fakeBlockJson(
        id: 'd1', type: 'date', payload: {'title': 'When'}, dateStart: p['p_date_start'] as String?, version: 2);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A single date'));
    await tester.pumpAndSettle();
    await _pick(tester, DateTime(2026, 11, 20));
    final call = g.callsTo('update_planning_block').single;
    expect((call['p_date_start'], call['p_date_end']), ('2026-11-20', null));
  });

  testWidgets('checklist: the due date uses the wheel and the row updates as it turns', (tester) async {
    await tester.pumpWidget(planningTestApp(
        _gateway([
          fakeBlockJson(id: 'c', payload: {'title': 'Packing'}, items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]),
        ]),
        _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomatoes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InfoRowWidget, 'No due date'));
    await tester.pumpAndSettle();
    await _pick(tester, DateTime(2026, 11, 20));
    expect(find.text('Due Nov 20, 2026'), findsOneWidget);
  });

  testWidgets('table: a date column uses the wheel', (tester) async {
    await tester.pumpWidget(planningTestApp(
        _gateway([
          fakeBlockJson(id: 't', type: 'table', payload: {
            'title': 'Trip',
            'columns': [
              {'key': 'c0', 'label': 'When', 'type': 'date'},
            ],
          }),
        ]),
        _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No date'));
    await tester.pumpAndSettle();
    await _pick(tester, DateTime(2026, 11, 20));
    expect(find.text('Nov 20, 2026'), findsOneWidget);
  });

  testWidgets("a checklist item's due date shows in the primary colour", (tester) async {
    await tester.pumpWidget(planningTestApp(
        _gateway([
          fakeBlockJson(id: 'c', payload: {'title': 'Packing'}, items: [
            {...fakeItemJson(id: 'i1', text: 'Tomatoes'), 'due_date': '2026-11-20'},
          ]),
        ]),
        _screen));
    await tester.pumpAndSettle();
    final due = find.text('Due Nov 20, 2026');
    expect(tester.widget<Text>(due).style?.color, Theme.of(tester.element(due)).colorScheme.primary);
  });
}
