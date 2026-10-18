// A checklist's sections (Produce, Dairy…) are set apart: a divider and
// room above each one after the first.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('a divider and room between sections, none above the first', (
    t,
  ) async {
    final g = FakePlanningGateway({
      'get_planning_entry':
          (_) => fakeEntryDetailJson(
            blocks: [
              fakeBlockJson(
                id: 'b1',
                payload: {'title': 'Shopping list'},
                items: [
                  fakeItemJson(
                    id: 'i1',
                    text: 'Tomatoes',
                    section: 'Produce',
                    sortKey: 'a',
                  ),
                  fakeItemJson(
                    id: 'i2',
                    text: 'Onions',
                    section: 'Produce',
                    sortKey: 'b',
                  ),
                  fakeItemJson(
                    id: 'i3',
                    text: 'Milk',
                    section: 'Dairy',
                    sortKey: 'c',
                  ),
                  fakeItemJson(
                    id: 'i4',
                    text: 'Soap',
                    section: 'Household',
                    sortKey: 'd',
                  ),
                ],
              ),
            ],
          ),
    });
    await t.pumpWidget(planningTestApp(g, _screen));
    await t.pumpAndSettle();
    final dividers = find.byType(AppDivider);
    expect(
      dividers,
      findsNWidgets(2),
      reason: 'above Dairy and above Household, not above Produce',
    );
    double top(String s) => t.getTopLeft(find.text(s)).dy;
    double bottom(String s) => t.getBottomLeft(find.text(s)).dy;
    final first = t.getCenter(dividers.at(0)).dy;
    expect(first, inExclusiveRange(bottom('Onions'), top('Dairy')));
    expect(
      t.getCenter(dividers.at(1)).dy,
      inExclusiveRange(bottom('Milk'), top('Household')),
    );
    expect(
      top('Dairy') - first,
      greaterThanOrEqualTo(Spacing.sm),
      reason: 'the heading sits clear of its divider',
    );
  });
}
