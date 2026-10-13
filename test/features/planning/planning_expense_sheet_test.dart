import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway() => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'x', type: 'expenses')]),
      'save_planning_rich_item': (p) =>
          {...fakeItemJson(id: p['p_id'] as String, text: 'Taxi'), 'amount_minor': 1250, 'currency': 'GHS'},
    });

Future<void> _open(WidgetTester tester, FakePlanningGateway g) async {
  await tester.pumpWidget(planningTestApp(g, _screen));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add expense'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("the expense sheet is the app's sheet: header, neutral colour, Done saves, no Save button", (tester) async {
    final g = _gateway();
    await _open(tester, g);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget, reason: 'BottomSheetUtils');
    expect(find.byType(BottomSheetHeader), findsOneWidget);
    final sheet = tester.widget<CircularDocumentationContainer>(find.byType(CircularDocumentationContainer));
    expect(sheet.color, Theme.of(tester.element(find.byType(BottomSheetHeader))).colorScheme.neutral);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);

    await tester.enterText(find.widgetWithText(AppTextFormField, 'What for'), 'Taxi');
    await tester.enterText(find.widgetWithText(AppTextFormField, 'Amount'), '12.50');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetHeader), findsNothing, reason: 'closed once saved');
    expect(g.callsTo('save_planning_rich_item').single['p_fields']['amount_minor'], 1250);
  });

  testWidgets('Done with something missing keeps the sheet and says what', (tester) async {
    final g = _gateway();
    await _open(tester, g);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheetHeader), findsOneWidget, reason: 'still open');
    expect(find.text('Say what it was for'), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(g.callsTo('save_planning_rich_item'), isEmpty);
  });

  testWidgets('the fields sit close together, and the currency lines up inside the amount field', (tester) async {
    await _open(tester, _gateway());
    final what = find.widgetWithText(AppTextFormField, 'What for');
    final amount = find.widgetWithText(AppTextFormField, 'Amount');
    expect(tester.getTopLeft(amount).dy - tester.getBottomLeft(what).dy, lessThanOrEqualTo(8.0 + 0.5),
        reason: 'Spacing.sm between fields');
    expect(tester.getSize(what).height, lessThan(80), reason: 'compact: no room held for a counter it never shows');
    final box = tester.getRect(find.descendant(of: amount, matching: find.byType(InputDecorator)));
    final currency = find.descendant(of: amount, matching: find.byType(DropdownButton<String>));
    expect(currency, findsOneWidget, reason: 'inside the amount field');
    expect(tester.getCenter(currency).dy, moreOrLessEquals(box.center.dy, epsilon: 1));
  });

  testWidgets('the labels are softened to 60% of the text colour', (tester) async {
    await _open(tester, _gateway());
    final soft = Theme.of(tester.element(find.byType(BottomSheetHeader))).colorScheme.onSurface.withValues(alpha: 0.6);
    for (final label in ['What for', 'Amount']) {
      final text = find.descendant(of: find.widgetWithText(AppTextFormField, label), matching: find.text(label));
      expect(tester.widget<Text>(text).style?.color, soft, reason: label);
    }
  });
}
