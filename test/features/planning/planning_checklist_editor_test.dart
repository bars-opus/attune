import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway() => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'c', payload: {'title': 'Packing'}, items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]),
          ]),
    });

Future<void> _open(WidgetTester tester, FakePlanningGateway g) async {
  await tester.pumpWidget(planningTestApp(g, _screen));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tomatoes'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the item sheet: untitled header, neutral background, Done saves, no Save button', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block_item'] =
        (p) => fakeItemJson(id: 'i1', text: p['p_text'] as String, version: 2);
    await _open(tester, g);
    expect(tester.widget<BottomSheetHeader>(find.byType(BottomSheetHeader)).title, isEmpty);
    final scheme = Theme.of(tester.element(find.byType(BottomSheet))).colorScheme;
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor, scheme.neutral);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Save')), findsNothing);
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Item'), 'Cherry tomatoes');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(g.callsTo('update_planning_block_item').single['p_text'], 'Cherry tomatoes');
  });

  testWidgets('Done with the item emptied keeps the sheet and says why', (tester) async {
    final g = _gateway();
    await _open(tester, g);
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Item'), '   ');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Type the item'), findsOneWidget);
    expect(g.callsTo('update_planning_block_item'), isEmpty);
  });

  testWidgets('the field labels are softened to 60% of the text colour', (tester) async {
    await _open(tester, _gateway());
    final soft = Theme.of(tester.element(find.byType(BottomSheet))).colorScheme.onSurface.withValues(alpha: 0.6);
    for (final label in ['Item', 'Section (optional)']) {
      final text = find.descendant(of: find.widgetWithText(AppTextFormField, label), matching: find.text(label));
      expect(tester.widget<Text>(text).style?.color, soft, reason: label);
    }
  });

  testWidgets('tapping a blank part of the sheet puts the keyboard away', (tester) async {
    await _open(tester, _gateway());
    await tester.tap(find.widgetWithText(AppTextFormField, 'Item'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text("Who's on it"));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('the due date is picked from an InfoRowWidget row, like the Date block', (tester) async {
    await _open(tester, _gateway());
    final row = find.widgetWithText(InfoRowWidget, 'No due date');
    expect(row, findsOneWidget);
    final info = tester.widget<InfoRowWidget>(row);
    expect(info.icon, Icons.event_rounded);
    expect(info.iconColor, Theme.of(tester.element(row)).colorScheme.primary);
    expect(info.showTrailingArrow, isTrue);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(ListTile)), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // close the wheel: today
    await tester.pumpAndSettle();
    final set = find.ancestor(of: find.textContaining('Due '), matching: find.byType(InfoRowWidget));
    expect(set, findsOneWidget);
    expect(find.descendant(of: set, matching: find.byTooltip('Clear due date')), findsOneWidget);
    await tester.tap(find.byTooltip('Clear due date'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InfoRowWidget, 'No due date'), findsOneWidget);
  });
}
