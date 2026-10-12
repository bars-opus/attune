import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_category_screen.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

Map<String, dynamic> _summary(String id, {String? date, int done = 0, int total = 0}) => {
      'id': id, 'title': 'Trip $id', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
      'date_start': date, 'date_end': null, 'checklist_done': done, 'checklist_total': total,
    };

FakePlanningGateway _gateway({List<Map<String, dynamic>>? open}) => FakePlanningGateway({
      'mark_planning_category_seen': (_) => {'seen_at': '2026-10-12T09:00:00Z'},
      'list_planning_entries': (p) => p['p_group'] == 'open'
          ? {'entries': open ?? [_summary('1', date: '2026-03-03', done: 2, total: 5)], 'next_cursor': null}
          : {'entries': [_summary('9')], 'next_cursor': null},
      'get_planning_entry': (p) => fakeEntryDetailJson(id: p['p_id'] as String),
    });

PlanningCategory _cat({String? seedKey = 'trips'}) => PlanningCategory.fromJson(
    fakeCategoryJson(id: 'c1', seedKey: seedKey, name: seedKey == null ? 'Wedding' : 'Trips', entryCount: 3));

void main() {
  testWidgets('lists open entries with date and checklist progress; marks the category seen', (tester) async {
    final g = _gateway();
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    expect(find.text('Trip 1'), findsOneWidget);
    expect(find.text('Mar 3, 2026 · 2 of 5 done'), findsOneWidget);
    expect(g.callsTo('mark_planning_category_seen'), hasLength(1));
    expect(find.text('Trip 9'), findsNothing, reason: 'closed entries load only when expanded');
    await tester.tap(find.text('Done & archived'));
    await tester.pumpAndSettle();
    expect(find.text('Trip 9'), findsOneWidget);
  });

  testWidgets('empty state offers to start a plan', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(open: []),
        PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    expect(find.text('No plans here yet'), findsOneWidget);
  });

  testWidgets('new plan from the template creates it and opens it', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String, title: 'Bali');
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bali');
    await tester.pump(); // enterText does not pump; Create enables on rebuild
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final call = g.callsTo('create_planning_entry').single;
    expect(call['p_title'], 'Bali');
    expect(call['p_use_template'], isTrue);
    expect(call['p_currency'], matches(RegExp(r'^[A-Z]{3}$')));
    expect(find.byType(PlanningV2EntryScreen), findsOneWidget);
  });

  testWidgets('Start blank sends use_template false', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String);
    await tester.pumpWidget(planningV2TestApp(g, PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Weekend');
    await tester.pump();
    await tester.tap(find.text('Start blank'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(g.callsTo('create_planning_entry').single['p_use_template'], isFalse);
  });

  testWidgets('starters cannot be deleted, only reset', (tester) async {
    await tester.pumpWidget(planningV2TestApp(_gateway(), PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete category'), findsNothing);
    expect(find.text('Reset template'), findsOneWidget);
  });

  testWidgets('custom categories confirm deletion with the entry count', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_category'] = (_) => {'deleted_entries': 3};
    await tester.pumpWidget(planningV2TestApp(g,
        PlanningV2CategoryScreen(relationshipId: 'r1', category: _cat(seedKey: null))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete category'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Wedding and its 3 plans?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(g.callsTo('delete_planning_category'), hasLength(1));
  });
}
