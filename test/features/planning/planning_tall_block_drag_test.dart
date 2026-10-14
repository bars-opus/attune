import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('long-pressing in a block taller than the screen does not start a drag that breaks', (tester) async {
    await tester.pumpWidget(planningTestApp(
        FakePlanningGateway({
          'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
                fakeBlockJson(id: 'x', type: 'expenses', payload: {'title': 'Costs'}, items: [
                  for (var i = 0; i < 9; i++)
                    {...fakeItemJson(id: 'e$i', text: 'Line $i', sortKey: 'k$i'), 'amount_minor': 1000 * (i + 1), 'currency': 'GHS', 'paid_by': 'u-a'},
                ]),
              ]),
        }),
        _screen));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Line 0'));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(find.text('Line 0')));
    await tester.pump(const Duration(milliseconds: 800)); // past the long-press delay
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 60)); // toward the bottom edge, where auto-scroll kicks in
      await tester.pump(const Duration(milliseconds: 50));
    }
    final error = tester.takeException();
    await gesture.up();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(error, isNull, reason: 'no drag-target-too-big assertion');
    expect(tester.takeException(), isNull);
  });
}
