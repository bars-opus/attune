// Bills: an expense line's optional due date (set and cleared in its sheet,
// shown on the line) and a total under each money column of a table.
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/planning_money.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

Map<String, dynamic> _bill(
  String id,
  String text, {
  String? due,
  int amount = 150000,
}) => {
  ...fakeItemJson(id: id, text: text),
  'amount_minor': amount,
  'currency': 'GHS',
  'due_date': due,
};

FakePlanningGateway _expenses(List<Map<String, dynamic>> lines) =>
    FakePlanningGateway({
      'get_planning_entry':
          (_) => fakeEntryDetailJson(
            blocks: [fakeBlockJson(id: 'x', type: 'expenses', items: lines)],
          ),
      'save_planning_rich_item':
          (p) => {
            ..._bill(p['p_id'] as String, p['p_fields']['label'] as String),
            'due_date': p['p_fields']['due_date'],
          },
    });

void main() {
  group('a bill\'s due date', () {
    testWidgets('chosen in the sheet, sent as a day', (t) async {
      final g = _expenses([]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      await t.tap(find.text('Add expense'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(AppTextFormField, 'What for'),
        'Rent',
      );
      await t.enterText(
        find.widgetWithText(AppTextFormField, 'Amount'),
        '1500',
      );
      await t.tap(find.text('No due date'));
      await t.pumpAndSettle();
      await t.tapAt(const Offset(20, 20)); // close the wheel unturned: today
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        g.callsTo('save_planning_rich_item').single['p_fields']['due_date'],
        planningYmd(DateTime.now()),
      );
    });

    testWidgets('shown on the line, and cleared from its sheet', (t) async {
      final g = _expenses([_bill('b1', 'Rent', due: '2026-11-01')]);
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      final due = 'Due ${formatPlanningRange(DateTime(2026, 11, 1), null)}';
      expect(
        find.descendant(
          of: find.widgetWithText(InfoRowWidget, 'Rent'),
          matching: find.text(due),
        ),
        findsOneWidget,
      );

      await t.tap(find.text('Rent'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Clear due date'));
      await t.pumpAndSettle();
      expect(find.text('No due date'), findsOneWidget);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final fields =
          g.callsTo('save_planning_rich_item').single['p_fields'] as Map;
      expect(fields.containsKey('due_date'), isTrue);
      expect(fields['due_date'], isNull);
    });

    testWidgets('a line without one says nothing about it', (t) async {
      await t.pumpWidget(
        planningTestApp(_expenses([_bill('b1', 'Rent')]), _screen),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Due '), findsNothing);
    });
  });

  group('a table\'s money total', () {
    FakePlanningGateway table(
      List<Map<String, dynamic>> rows, {
      bool money = true,
    }) => FakePlanningGateway({
      'get_planning_entry':
          (_) => fakeEntryDetailJson(
            blocks: [
              fakeBlockJson(
                id: 't',
                type: 'table',
                payload: {
                  'title': 'Bills',
                  'columns': [
                    {'key': 'c0', 'label': 'Bill', 'type': 'text'},
                    {
                      'key': 'c1',
                      'label': 'Amount',
                      'type': money ? 'money' : 'number',
                    },
                  ],
                },
                items: rows,
              ),
            ],
          ),
    });
    Map<String, dynamic> row(
      String id,
      String bill,
      Object? amount,
      String sort,
    ) => {
      ...fakeItemJson(id: id, sortKey: sort),
      'cells': {'c0': bill, 'c1': amount},
    };

    testWidgets(
      'a Total row adds up each money column; empty cells count as nothing',
      (t) async {
        await t.pumpWidget(
          planningTestApp(
            table([
              row('r1', 'Rent', 150000, 'V'),
              row('r2', 'Water', 4550, 'W'),
              row('r3', 'TV', null, 'X'),
            ]),
            _screen,
          ),
        );
        await t.pumpAndSettle();
        final total = find.byKey(const ValueKey('planning-table-total'));
        expect(total, findsOneWidget);
        expect(
          find.descendant(of: total, matching: find.text('Total')),
          findsOneWidget,
        );
        // The test plan's currency (fakeEntryDetailJson).
        final currency =
            PlanningEntryDetail.fromJson(fakeEntryDetailJson()).entry.currency;
        expect(
          find.descendant(
            of: total,
            matching: find.text(formatPlanningMoney(154550, currency)),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('two or more money columns: one total of all of them under the table', (t) async {
      final g = FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 't', type: 'table', payload: {
                'title': 'Trip costs',
                'columns': [
                  {'key': 'c0', 'label': 'Day', 'type': 'text'},
                  {'key': 'c1', 'label': 'Flights', 'type': 'money'},
                  {'key': 'c2', 'label': 'Hotel', 'type': 'money'},
                ],
              }, items: [
                {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'Mon', 'c1': 200000, 'c2': 80000}},
                {...fakeItemJson(id: 'r2', sortKey: 'W'), 'cells': {'c0': 'Tue', 'c2': 80000}},
              ]),
            ]),
      });
      await t.pumpWidget(planningTestApp(g, _screen));
      await t.pumpAndSettle();
      final currency = PlanningEntryDetail.fromJson(fakeEntryDetailJson()).entry.currency;
      expect(find.byKey(const ValueKey('planning-table-grand-total')), findsOneWidget);
      expect(find.text('Total of all: ${formatPlanningMoney(360000, currency)}'), findsOneWidget);
    });

    testWidgets('one money column: its Total row says it all, no second total', (t) async {
      await t.pumpWidget(planningTestApp(table([row('r1', 'Rent', 150000, 'V')]), _screen));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('planning-table-total')), findsOneWidget);
      expect(find.byKey(const ValueKey('planning-table-grand-total')), findsNothing);
    });

    testWidgets('no money column, or no rows: no Total row', (t) async {
      await t.pumpWidget(
        planningTestApp(
          table([row('r1', 'Rent', 3, 'V')], money: false),
          _screen,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('planning-table-total')), findsNothing);
      await t.pumpWidget(planningTestApp(table([]), _screen));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('planning-table-total')), findsNothing);
    });
  });
}
