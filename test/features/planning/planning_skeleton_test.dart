import 'dart:async';

import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

PlanningCategory _cat(String seedKey, String name) => PlanningCategory.fromJson(
  fakeCategoryJson(id: 'c1', seedKey: seedKey, name: name, entryCount: 3),
);

void main() {
  testWidgets(
    'Planning home shows skeleton category rows while it loads, then the categories',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final home = Completer<Map<String, dynamic>>();
      final g = FakePlanningGateway({'get_planning_home': (_) => home.future});
      await tester.pumpWidget(
        planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SchimmerSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('Loading categories'), findsOneWidget);

      home.complete({
        'categories': [
          fakeCategoryJson(
            id: 'c1',
            seedKey: 'goals',
            name: 'Goals',
            icon: 'flag',
            color: 'rose',
          ),
        ],
      });
      await tester.pumpAndSettle();
      expect(find.byType(SchimmerSkeleton), findsNothing);
      expect(find.text('Goals'), findsOneWidget);
      semantics.dispose();
    },
  );

  for (final (seed, name) in [('notes', 'Notes'), ('trips', 'Trips')]) {
    testWidgets(
      '$name shows skeleton rows while its list loads, then the list',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final open = Completer<Map<String, dynamic>>();
        final g = FakePlanningGateway({
          'mark_planning_category_seen':
              (_) => {'seen_at': '2026-10-12T09:00:00Z'},
          'list_planning_entries': (_) => open.future,
        });
        await tester.pumpWidget(
          planningTestApp(
            g,
            PlanningCategoryScreen(
              relationshipId: 'r1',
              category: _cat(seed, name),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SchimmerSkeleton), findsWidgets);
        expect(
          find.bySemanticsLabel(
            seed == 'notes' ? 'Loading notes' : 'Loading plans',
          ),
          findsOneWidget,
        );

        open.complete({
          'entries': [
            {
              'id': 'e1',
              'title': 'First',
              'status': 'active',
              'last_activity_at': '2026-10-12T09:00:00Z',
              'pinned': false,
              'date_start': null,
              'date_end': null,
              'checklist_done': 0,
              'checklist_total': 0,
            },
          ],
          'next_cursor': null,
        });
        await tester.pumpAndSettle();
        expect(find.byType(SchimmerSkeleton), findsNothing);
        expect(find.text('First'), findsOneWidget);
        semantics.dispose();
      },
    );
  }
}
