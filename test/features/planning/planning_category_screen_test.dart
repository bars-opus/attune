import 'dart:async';

import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_text_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

Map<String, dynamic> _summary(String id, {String? date, int done = 0, int total = 0, bool pinned = false}) => {
      'id': id, 'title': 'Trip $id', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
      'pinned': pinned, 'date_start': date, 'date_end': null, 'checklist_done': done, 'checklist_total': total,
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
    await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
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
    await tester.pumpWidget(planningTestApp(_gateway(open: []),
        PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    expect(find.text('No plans here yet'), findsOneWidget);
  });

  testWidgets('new plan from the template creates it and opens it', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String, title: 'Bali');
    await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
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
    expect(find.byType(PlanningEntryScreen), findsOneWidget);
  });

  testWidgets('Start blank sends use_template false', (tester) async {
    final g = _gateway();
    g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(id: p['p_id'] as String);
    await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
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
    await tester.pumpWidget(planningTestApp(_gateway(), PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete category'), findsNothing);
    expect(find.text('Reset template'), findsOneWidget);
  });

  testWidgets('custom categories confirm deletion with the entry count', (tester) async {
    final g = _gateway();
    g.handlers['delete_planning_category'] = (_) => {'deleted_entries': 3};
    await tester.pumpWidget(planningTestApp(g,
        PlanningCategoryScreen(relationshipId: 'r1', category: _cat(seedKey: null))));
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

  group('swipe actions on plans', () {
    FakePlanningGateway swipeGateway() {
      var pinned = false;
      var deleted = false;
      final g = _gateway();
      g.handlers['list_planning_entries'] = (p) => p['p_group'] == 'open'
          ? {
              'entries': [if (!pinned && !deleted) _summary('1'), _summary('2')],
              'pinned': [if (pinned && !deleted) _summary('1', pinned: true)],
              'next_cursor': null,
            }
          : {'entries': [], 'pinned': [], 'next_cursor': null};
      g.handlers['pin_planning_entry'] = (p) {
        pinned = p['p_pinned'] as bool;
        return {'entry': {...fakeEntryDetailJson(id: '1')['entry'] as Map, 'pinned_at': pinned ? '2026-10-12T09:00:00Z' : null}};
      };
      g.handlers['delete_planning_entry'] = (_) {
        deleted = true;
        return {'deleted': true};
      };
      g.handlers['restore_planning_entry'] = (_) {
        deleted = false;
        return {'entry': fakeEntryDetailJson(id: '1')['entry']};
      };
      return g;
    }

    testWidgets('swipe RIGHT deletes the plan, with Undo', (tester) async {
      final g = swipeGateway();
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('entry-1')), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(g.callsTo('delete_planning_entry').single, {'p_id': '1'});
      expect(find.text('Trip 1'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(g.callsTo('restore_planning_entry'), hasLength(1));
      expect(find.text('Trip 1'), findsOneWidget);
    });

    testWidgets('swipe LEFT pins the plan into the Pinned group, and again unpins it', (tester) async {
      final g = swipeGateway();
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('entry-1')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(g.callsTo('pin_planning_entry').single, {'p_id': '1', 'p_pinned': true});
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Trip 1'), findsOneWidget, reason: 'pinning keeps the plan on screen');
      expect(g.callsTo('delete_planning_entry'), isEmpty);
      await tester.drag(find.byKey(const ValueKey('entry-1')), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(g.callsTo('pin_planning_entry').last, {'p_id': '1', 'p_pinned': false});
      expect(find.text('Pinned'), findsNothing);
    });

    testWidgets('long-press offers Pin and Delete without swiping (accessibility)', (tester) async {
      final g = swipeGateway();
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _cat())));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Trip 1'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();
      expect(g.callsTo('pin_planning_entry').single['p_pinned'], isTrue);
    });
  });

  group('Notes', () {
    PlanningCategory notes() => PlanningCategory.fromJson(
        fakeCategoryJson(id: 'c1', seedKey: 'notes', name: 'Notes', icon: 'note', color: 'indigo'));

    testWidgets('+ creates a note and opens the editor directly — no template choice', (tester) async {
      final g = _gateway();
      g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(
          id: p['p_id'] as String, title: 'New note', seedKey: 'notes', categoryName: 'Notes', blocks: [
            fakeBlockJson(id: 'b1', type: 'text', plainText: '', payload: {
              'delta': [{'insert': '\n'}]
            }),
          ]);
      g.handlers['get_planning_entry'] = (p) => g.handlers['create_planning_entry']!(p);
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: notes())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      expect(find.text('Use template'), findsNothing);
      final call = g.callsTo('create_planning_entry').single;
      expect(call['p_title'], 'New note');
      expect(call['p_use_template'], isTrue, reason: 'the Notes template is the blank sheet');
      expect(find.byType(PlanningTextEditorScreen), findsOneWidget);
    });

    FakePlanningGateway noteGateway() {
      final g = _gateway();
      g.handlers['create_planning_entry'] = (p) => fakeEntryDetailJson(
          id: p['p_id'] as String, title: 'New note', seedKey: 'notes', categoryName: 'Notes', blocks: [
            fakeBlockJson(id: 'b1', type: 'text', plainText: '', payload: {
              'delta': [{'insert': '\n'}]
            }),
          ]);
      g.handlers['get_planning_entry'] = (p) => g.handlers['create_planning_entry']!(p);
      g.handlers['delete_planning_entry'] = (_) => {'deleted': true};
      return g;
    }

    testWidgets('backing out of a new note without writing leaves no empty note behind (review m1)', (tester) async {
      final g = noteGateway();
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: notes())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New note'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanningTextEditorScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final created = g.callsTo('create_planning_entry').single['p_id'];
      expect(g.callsTo('delete_planning_entry').single, {'p_id': created});
      expect(find.byType(PlanningEntryScreen), findsNothing, reason: 'straight back to the Notes list');
    });

    testWidgets('double-tapping New note creates one note (review m1)', (tester) async {
      final g = noteGateway();
      final slow = Completer<void>();
      final create = g.handlers['create_planning_entry']!;
      g.handlers['create_planning_entry'] = (p) async {
        await slow.future; // the first create is still in flight when the second tap lands
        return create(p);
      };
      await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: notes())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New note'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('New note'));
      await tester.pump(const Duration(milliseconds: 100));
      slow.complete();
      await tester.pumpAndSettle();
      expect(g.callsTo('create_planning_entry'), hasLength(1));
    });

    testWidgets('Notes has no template menu items', (tester) async {
      await tester.pumpWidget(planningTestApp(_gateway(), PlanningCategoryScreen(relationshipId: 'r1', category: notes())));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Category options'));
      await tester.pumpAndSettle();
      expect(find.text('Edit template'), findsNothing);
      expect(find.text('Reset template'), findsNothing);
    });
  });
}
