import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/checklist_block_view.dart';
import 'package:attune/features/planning/presentation/widgets/table_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gateway(Map<String, dynamic> block) => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [block]),
    });

void main() {
  testWidgets('the table menu sits in its heading row, so the grid gets the full width', (tester) async {
    await tester.pumpWidget(planningTestApp(
        _gateway(fakeBlockJson(id: 't', type: 'table', payload: {
          'title': 'Itinerary',
          'columns': [
            {'key': 'c0', 'label': 'Day', 'type': 'text'},
          ],
        })),
        _screen));
    await tester.pumpAndSettle();
    final menu = find.byTooltip('Options for Itinerary');
    expect(find.descendant(of: find.byType(TableBlockView), matching: menu), findsOneWidget);
    final grid = find.byKey(const ValueKey('planning-table-grid'));
    expect(tester.getTopLeft(grid).dy, greaterThanOrEqualTo(tester.getBottomLeft(menu).dy), reason: 'menu above the grid');
    expect(tester.getTopRight(grid).dx, greaterThan(tester.getTopLeft(menu).dx), reason: 'grid runs under the menu');
  });

  testWidgets('the checklist menu sits in its heading row, so the items get the full width', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(fakeBlockJson(id: 'c', payload: {'title': 'Packing'})), _screen));
    await tester.pumpAndSettle();
    final menu = find.byTooltip('Options for Packing');
    expect(find.descendant(of: find.byType(ChecklistBlockView), matching: menu), findsOneWidget);
    final add = find.widgetWithText(TextField, 'Add item');
    expect(tester.getTopRight(add).dx, greaterThan(tester.getTopLeft(menu).dx), reason: 'items run under the menu');
  });
}
