import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/table_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway() => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 't', type: 'table', payload: {
              'title': 'Itinerary',
              'columns': [
                {'key': 'c0', 'label': 'Day', 'type': 'text'},
                {'key': 'c1', 'label': 'Plan', 'type': 'text'},
              ],
            }, items: [
              {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'Mon', 'c1': 'Beach'}},
              {...fakeItemJson(id: 'r2', sortKey: 'W'), 'cells': {'c0': 'Tue', 'c1': 'Hike'}},
            ]),
          ]),
    });

BoxDecoration? _decoration(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  return switch (w) {
    Container(decoration: final BoxDecoration d) => d,
    DecoratedBox(decoration: final BoxDecoration d) => d,
    _ => null,
  };
}

final _cellKey = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('planning-table-cell-'));

void main() {
  testWidgets('the table has gridlines: an outer border, lines between columns and rows, a shaded header', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    final scheme = Theme.of(tester.element(find.byType(TableBlockView))).colorScheme;

    final gridBox = tester.widget<Container>(find.byKey(const ValueKey('planning-table-grid')));
    // The outline is painted over the cells, so the shaded header can't cover
    // the inside of its rounded corners; the clip rounds the cells to match.
    final outline = gridBox.foregroundDecoration! as BoxDecoration;
    expect(outline.border, Border.all(color: scheme.outlineVariant));
    expect(outline.borderRadius, isNotNull, reason: 'rounded, like the cards');
    expect(gridBox.clipBehavior, isNot(Clip.none));
    expect((gridBox.decoration! as BoxDecoration).borderRadius, outline.borderRadius);

    BoxDecoration? cellOf(String text) =>
        _decoration(tester, find.ancestor(of: find.text(text), matching: _cellKey));
    // A column line on the right of every cell but the last column's.
    expect((cellOf('Mon')!.border as Border).right.color, scheme.outlineVariant);
    expect((cellOf('Day')!.border as Border).right.color, scheme.outlineVariant);
    expect(cellOf('Beach')?.border, anyOf(isNull, isA<Border>().having((b) => b.right, 'right', BorderSide.none)));

    // A row line above every data row; the header is shaded.
    BoxDecoration rowOf(String text) =>
        _decoration(tester, find.ancestor(of: find.text(text), matching: find.byKey(const ValueKey('planning-table-row'))))!;
    expect((rowOf('Mon').border as Border).top.color, scheme.outlineVariant);
    expect((rowOf('Tue').border as Border).top.color, scheme.outlineVariant);
    expect(_decoration(tester, find.byKey(const ValueKey('planning-table-header')))!.color,
        scheme.surfaceContainerHighest);

    // Column lines run the full height of a row.
    expect(tester.getSize(find.ancestor(of: find.text('Mon'), matching: _cellKey)).height,
        tester.getSize(find.ancestor(of: find.text('Mon'), matching: find.byKey(const ValueKey('planning-table-row')))).height - 1);
  });

  testWidgets('the table sits in the note, not in a card; its menu stays at the right', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    expect(find.ancestor(of: find.byType(TableBlockView), matching: find.byType(CardInkWell)), findsNothing);
    expect(find.byTooltip('Options for Itinerary'), findsOneWidget);
  });

  FakePlanningGateway wide() => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 't', type: 'table', payload: {
                'title': 'Itinerary',
                'columns': [
                  for (var i = 0; i < 8; i++) {'key': 'c$i', 'label': 'Col $i', 'type': 'text'},
                ],
              }),
            ]),
      });

  testWidgets('the row editor stacks its fields without dead space between them', (tester) async {
    await tester.pumpWidget(planningTestApp(wide(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    final first = find.widgetWithText(AppTextFormField, 'Col 0');
    final second = find.widgetWithText(AppTextFormField, 'Col 1');
    expect(tester.getSize(first).height, lessThan(80), reason: 'compact: no room held for a counter it never shows');
    expect(tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy, Spacing.sm, reason: 'Spacing.sm between fields');
  });

  testWidgets('the row editor sheet stops short of the top of the screen, even with the keyboard up', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 72); // status bar, physical px (3x)
    addTearDown(tester.view.reset);
    await tester.pumpWidget(planningTestApp(wide(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // a field is focused: keyboard up
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(Scaffold).first).height;
    final top = tester.getTopLeft(find.byType(BottomSheet)).dy;
    expect(top, greaterThanOrEqualTo(screen * 0.15 - 0.5), reason: 'capped below the top of the screen');
  });

  testWidgets('the columns sheet is capped the same way', (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(planningTestApp(wide(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(Scaffold).first).height;
    expect(tester.getTopLeft(find.byType(BottomSheet)).dy, greaterThanOrEqualTo(screen * 0.15 - 0.5));
  });

  testWidgets('the row editor is headed with the row number, on the neutral sheet colour', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tue'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(BottomSheetHeader, 'Row 2'), findsOneWidget);
    final scheme = Theme.of(tester.element(find.byType(BottomSheet))).colorScheme;
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor, scheme.neutral);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(BottomSheetHeader, 'Row 3'), findsOneWidget, reason: 'a new row is the next number');
  });

  FakePlanningGateway priced() => FakePlanningGateway({
        'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
              fakeBlockJson(id: 't', type: 'table', payload: {
                'title': 'Itinerary',
                'columns': [
                  {'key': 'c0', 'label': 'Day', 'type': 'text'},
                  {'key': 'c1', 'label': 'Cost', 'type': 'money'},
                ],
              }, items: [
                {...fakeItemJson(id: 'r1'), 'cells': {'c0': 'Mon'}},
              ]),
            ]),
      });

  testWidgets('row editor: Done in the header saves the row; there is no Save button', (tester) async {
    final g = priced();
    g.handlers['save_planning_rich_item'] = (p) => {...fakeItemJson(id: 'r1'), 'cells': (p['p_fields'] as Map)['cells']};
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')), findsNothing);
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Day'), 'Wed');
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Cost'), '12.50');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final cells = (g.callsTo('save_planning_rich_item').single['p_fields'] as Map)['cells'] as Map;
    expect(cells['c0'], 'Wed');
  });

  testWidgets('row editor: Done with an amount it cannot read keeps the sheet and says why', (tester) async {
    final g = priced();
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Cost'), '1.2.3');
    await tester.pump();
    expect(find.text('Enter an amount like 500'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'nothing lost');
    expect(g.callsTo('save_planning_rich_item'), isEmpty);
  });

  testWidgets('columns sheet: an untitled header whose Done saves; no Save button', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (p) => fakeBlockJson(id: 't', type: 'table', payload: p['p_payload'] as Map<String, dynamic>, version: 2);
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    expect(tester.widget<BottomSheetHeader>(find.byType(BottomSheetHeader)).title, isEmpty,
        reason: 'the fields are already labelled Column 1, Column 2…');
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')), findsNothing);
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Column 1'), 'Weekday');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final cols = (g.callsTo('update_planning_block').single['p_payload'] as Map)['columns'] as List;
    expect((cols.first as Map)['label'], 'Weekday');
  });

  testWidgets('columns sheet: Done with an unnamed column keeps the sheet and says why', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Column 1'), '  ');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Name this column'), findsOneWidget);
    expect(g.callsTo('update_planning_block'), isEmpty);
  });

  testWidgets('columns sheet: the type picker and remove button line up with the field, no underline', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(AppTextFormField, 'Column 1');
    final box = tester.getRect(find.descendant(of: field, matching: find.byType(InputDecorator)));
    final type = find.byType(DropdownButton<PlanningColumnType>).first;
    final remove = find.byTooltip('Remove column').first;
    expect(tester.getCenter(type).dy, moreOrLessEquals(box.center.dy, epsilon: 1));
    expect(tester.getCenter(remove).dy, moreOrLessEquals(box.center.dy, epsilon: 1));
    final underline = find.descendant(
        of: type,
        matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null));
    expect(underline, findsNothing, reason: 'a picker, not a text field');
  });

  testWidgets('field labels in both table sheets sit Spacing.lg in from the field edge', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    double indent(String label) {
      final field = find.widgetWithText(AppTextFormField, label);
      return tester.getTopLeft(find.descendant(of: field, matching: find.text(label))).dx -
          tester.getTopLeft(find.descendant(of: field, matching: find.byType(InputDecorator))).dx;
    }

    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    expect(indent('Day'), Spacing.lg);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    expect(indent('Column 1'), Spacing.lg);
  });

  testWidgets('field labels in both table sheets are softened to 60% of the text colour', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), _screen));
    await tester.pumpAndSettle();
    final soft = Theme.of(tester.element(find.byType(TableBlockView))).colorScheme.onSurface.withValues(alpha: 0.6);
    Color? colour(String label) => tester
        .widget<Text>(find.descendant(of: find.widgetWithText(AppTextFormField, label), matching: find.text(label)))
        .style
        ?.color;

    await tester.tap(find.text('Mon'));
    await tester.pumpAndSettle();
    expect(colour('Day'), soft);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit columns'));
    await tester.pumpAndSettle();
    expect(colour('Column 1'), soft);
  });
}
