// A table's Person column (Me or the partner, chosen like Expenses' "Paid
// by") and its date cells (the app's Cupertino date row, with a clear).
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gap/gap.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _bills(Map<String, dynamic> cells) => FakePlanningGateway({
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
                {'key': 'c2', 'label': 'Due date', 'type': 'date'},
                {'key': 'c3', 'label': 'Paid', 'type': 'check'},
                {'key': 'c4', 'label': 'Paid by', 'type': 'person'},
              ],
            },
            items: [
              {
                ...fakeItemJson(id: 'r1'),
                'cells': {'c0': 'Rent', ...cells},
              },
            ],
          ),
        ],
      ),
  'save_planning_rich_item':
      (p) => {
        ...fakeItemJson(id: p['p_id'] as String),
        'cells': {'c0': 'Rent', ...(p['p_fields']['cells'] as Map)},
      },
});

Future<void> _openRow(WidgetTester t, FakePlanningGateway g) async {
  await t.pumpWidget(planningTestApp(g, _screen));
  await t.pumpAndSettle();
  await t.tap(find.text('Rent'));
  await t.pumpAndSettle();
}

Map _saved(FakePlanningGateway g) =>
    g.callsTo('save_planning_rich_item').single['p_fields']['cells'] as Map;

void main() {
  test('person is a column type', () {
    expect(
      PlanningTableColumn.fromJson({
        'key': 'c4',
        'label': 'Paid by',
        'type': 'person',
      }).type,
      PlanningColumnType.person,
    );
  });

  testWidgets('the grid shows the person by name', (t) async {
    await t.pumpWidget(planningTestApp(_bills({'c4': 'u-b'}), _screen));
    await t.pumpAndSettle();
    expect(find.text('Kofi'), findsOneWidget);
  });

  testWidgets('Paid by is the rounded Me / partner choice, not a text field', (
    t,
  ) async {
    final g = _bills({});
    await _openRow(t, g);
    final choice = find.byType(SegmentedButton<String>);
    expect(choice, findsOneWidget);
    expect(
      find.descendant(of: choice, matching: find.text('Me')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: choice, matching: find.text('Kofi')),
      findsOneWidget,
    );
    await t.tap(find.descendant(of: choice, matching: find.text('Kofi')));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(_saved(g)['c4'], 'u-b');
  });

  testWidgets('tapping the chosen person again clears it', (t) async {
    final g = _bills({'c4': 'u-a'});
    await _openRow(t, g);
    await t.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('Me'),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(_saved(g).containsKey('c4'), isTrue);
    expect(_saved(g)['c4'], isNull);
  });

  testWidgets('a date cell is the Cupertino date row: pick, show, clear', (
    t,
  ) async {
    final g = _bills({});
    await _openRow(t, g);
    final row = find.widgetWithText(InfoRowWidget, 'Due date');
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('No date')),
      findsOneWidget,
    );
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    await t.tapAt(const Offset(20, 20)); // close the wheel unturned: today
    await t.pumpAndSettle();
    final today = DateTime.now();
    expect(
      find.text(formatPlanningRange(DateUtils.dateOnly(today), null)),
      findsOneWidget,
    );
    await t.tap(find.byTooltip('Clear Due date'));
    await t.pumpAndSettle();
    expect(find.text('No date'), findsOneWidget);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(_saved(g)['c2'], isNull);
  });

  testWidgets('a chosen date reads in the primary colour', (t) async {
    await _openRow(t, _bills({'c2': '2026-11-01'}));
    final date = t.widget<Text>(find.text(formatPlanningRange(DateTime(2026, 11, 1), null)));
    final primary = Theme.of(t.element(find.byType(BottomSheetHeader))).colorScheme.primary;
    expect(date.style?.color, primary);
    // "No date" stays quiet.
    await t.tap(find.byTooltip('Clear Due date'));
    await t.pumpAndSettle();
    expect(t.widget<Text>(find.text('No date')).style?.color, isNot(primary));
  });

  testWidgets('dividers between the date, Paid and Paid by; Paid by\'s choice spans the width', (t) async {
    await _openRow(t, _bills({}));
    final dividers = find.byType(AppDivider);
    expect(dividers, findsNWidgets(2));
    double y(Finder f) => t.getCenter(f).dy;
    final date = find.widgetWithText(InfoRowWidget, 'Due date');
    final paid = find.widgetWithText(SwitchListTile, 'Paid');
    final paidBy = find.byType(SegmentedButton<String>);
    expect(y(dividers.at(0)), inExclusiveRange(y(date), y(paid)));
    expect(y(dividers.at(1)), inExclusiveRange(y(paid), y(paidBy)));
    // Full width, like Expenses' "Paid by".
    expect(t.getSize(paidBy).width, moreOrLessEquals(t.getSize(date).width, epsilon: 1));
  });

  testWidgets('Paid by ends with a medium gap under its choice', (t) async {
    await _openRow(t, _bills({}));
    final field = t.widget<Column>(
      find.ancestor(of: find.byType(SegmentedButton<String>), matching: find.byType(Column)).first,
    );
    expect(field.children.last, isA<Gap>().having((g) => g.mainAxisExtent, 'size', Spacing.md));
  });

  testWidgets('a picked date saves as a day', (t) async {
    final g = _bills({});
    await _openRow(t, g);
    await t.tap(find.widgetWithText(InfoRowWidget, 'Due date'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(20, 20));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(_saved(g)['c2'], planningYmd(DateTime.now()));
  });

  testWidgets('Person is a column type in the columns sheet', (t) async {
    await t.pumpWidget(planningTestApp(_bills({}), _screen));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Edit columns'));
    await t.pumpAndSettle();
    // Paid by's type, shown as its picker's value.
    expect(
      find.descendant(
        of: find.byType(DropdownButton<PlanningColumnType>),
        matching: find.text('Person'),
      ),
      findsOneWidget,
    );
  });
}
