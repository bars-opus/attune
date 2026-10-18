import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

FakePlanningGateway _gateway() => FakePlanningGateway({
  'get_planning_home':
      (_) => {
        'categories': [
          fakeCategoryJson(
            id: 'c1',
            seedKey: 'goals',
            name: 'Goals',
            icon: 'flag',
            color: 'rose',
            entryCount: 2,
          ),
        ],
      },
  'mark_planning_category_seen': (_) => {'seen_at': '2026-10-12T09:00:00Z'},
  'list_planning_entries': (_) => {'entries': [], 'next_cursor': null},
});

Finder _hero(String id) => find.byWidgetPredicate(
  (w) => w is Hero && w.tag == planningCategoryHeroTag(id),
);

void main() {
  // Owner, 2026-10-16: with Recent at the top of Planning, the name flying
  // from its row into the category screen looked wrong; the row has no Hero.
  // (The category screen to plan flight stays: planning_appbar_test.)
  testWidgets('a category row opens its screen without a flying title', (
    tester,
  ) async {
    await tester.pumpWidget(
      planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')),
    );
    await tester.pumpAndSettle();
    expect(_hero('c1'), findsNothing, reason: 'no Hero on the Planning row');
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Goals')),
      findsOneWidget,
      reason: 'the category screen still opens with its name',
    );
  });
}
