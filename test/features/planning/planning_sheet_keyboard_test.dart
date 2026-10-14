import 'dart:io';

import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  test('every sheet in Planning, and the app sheets, with a text field can hide the keyboard on a tap', () {
    // A sheet built with showModalBottomSheet whose content has a field must
    // wrap that content in DismissKeyboardOnTap (BottomSheetUtils does it for
    // its own sheets). The checklist item sheet does it inline.
    final files = [
      'lib/features/planning/presentation/widgets/table_block_view.dart',
      'lib/features/planning/presentation/widgets/place_block_view.dart',
      'lib/features/planning/presentation/widgets/category_editor_sheet.dart',
      'lib/features/planning/presentation/screens/planning_category_screen.dart',
      'lib/features/location/presentation/widgets/share_place_sheet.dart',
      'lib/core/utils/bottom_sheet_utils.dart',
    ];
    for (final f in files) {
      final source = File(f).readAsStringSync();
      expect(
        source.contains('DismissKeyboardOnTap(') || source.contains('BottomSheetUtils.showDocumentationBottomSheet'),
        isTrue,
        reason: f,
      );
    }
  });

  testWidgets('the table row editor hides the keyboard on a tap outside its fields', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 't', type: 'table', payload: {
                  'title': 'Trip',
                  'columns': [
                    {'key': 'c0', 'label': 'Day', 'type': 'text'},
                    {'key': 'c1', 'label': 'Plan', 'type': 'text'},
                  ],
                }),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add row'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppTextFormField, 'Day'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('Row 1')); // the header's title: empty space as far as fields go
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
