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

double _size(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style!.fontSize!;

void main() {
  testWidgets(
    'the category name flies from its row into the category app bar, growing as it goes',
    (tester) async {
      await tester.pumpWidget(
        planningTestApp(
          _gateway(),
          const PlanningHomeScreen(relationshipId: 'r1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _hero('c1'),
        findsOneWidget,
        reason: 'the row title is the same Hero as the app bar title',
      );
      final rowSize = _size(
        tester,
        find.descendant(of: _hero('c1'), matching: find.text('Goals')),
      );

      await tester.tap(find.text('Goals'));
      await tester.pump(); // the push
      await tester.pump(const Duration(milliseconds: 150)); // mid-flight
      final midFlight =
          find
              .text('Goals', skipOffstage: false)
              .evaluate()
              .map((e) => (e.widget as Text).style?.fontSize)
              .whereType<double>()
              .toList();

      await tester.pumpAndSettle();
      final barTitle = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Goals'),
      );
      expect(
        find.descendant(of: _hero('c1'), matching: barTitle),
        findsOneWidget,
      );
      final barSize = _size(tester, barTitle);
      expect(barSize, greaterThan(rowSize));
      expect(
        midFlight.where((s) => s > rowSize && s < barSize),
        isNotEmpty,
        reason:
            'the flying name is between the row and app-bar sizes, not jumping',
      );

      // And back: the name flies home again without errors.
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_hero('c1'), findsOneWidget);
    },
  );
}
