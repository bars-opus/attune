import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

Map<String, dynamic> _summary(String id) => {
      'id': id, 'title': 'Groceries', 'status': 'active', 'last_activity_at': DateTime.now().toUtc().toIso8601String(),
      'pinned': false, 'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0,
    };

FakePlanningGateway _gateway() => FakePlanningGateway({
      'mark_planning_category_seen': (_) => {'seen_at': '2026-10-12T09:00:00Z'},
      'list_planning_entries': (p) => {'entries': [_summary('e1')], 'next_cursor': null},
      'get_planning_entry': (_) => fakeEntryDetailJson(seedKey: 'notes', categoryName: 'Notes', blocks: [
            fakeBlockJson(id: 'b1', type: 'text', plainText: 'Hello', payload: {
              'delta': [{'insert': 'Hello\n'}]
            }),
          ]),
    });

PlanningCategory _notes() => PlanningCategory.fromJson(
    fakeCategoryJson(id: 'c1', seedKey: 'notes', name: 'Notes', icon: 'note', color: 'indigo'));

void main() {
  testWidgets('the Notes title flies from the list to the note, left-aligned in the same style', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), PlanningCategoryScreen(relationshipId: 'r1', category: _notes())));
    await tester.pumpAndSettle();
    final listTitle = find.byWidgetPredicate((w) => w is Hero && w.tag == planningCategoryHeroTag('c1'));
    expect(listTitle, findsOneWidget);
    final listStyle = tester.widget<Text>(find.descendant(of: listTitle, matching: find.text('Notes'))).style;

    await tester.tap(find.text('Groceries'));
    await tester.pump(); // the push
    await tester.pump(const Duration(milliseconds: 50)); // mid-transition, before the plan has loaded
    expect(
      find.descendant(
        of: find.byType(PlanningEntryScreen, skipOffstage: false),
        matching: find.byWidgetPredicate((w) => w is Hero && w.tag == planningCategoryHeroTag('c1')),
        skipOffstage: false,
      ),
      findsOneWidget,
      reason: 'the note has its title from the first frame, so it can fly',
    );
    await tester.pumpAndSettle();

    final noteBar = tester.widget<AppBar>(find.descendant(of: find.byType(PlanningEntryScreen), matching: find.byType(AppBar)));
    expect(noteBar.centerTitle, isFalse);
    final noteTitle = find.descendant(of: find.byType(PlanningEntryScreen), matching: find.text('Notes'));
    expect(tester.widget<Text>(noteTitle).style, listStyle);
  });

  testWidgets('app-bar menus are vertical (more_vert) on both screens', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), PlanningCategoryScreen(relationshipId: 'r1', category: _notes())));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.byIcon(Icons.more_vert)), findsOneWidget);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    final noteBar = find.descendant(of: find.byType(PlanningEntryScreen), matching: find.byType(AppBar));
    expect(find.descendant(of: noteBar, matching: find.byIcon(Icons.more_vert)), findsOneWidget);
  });

  testWidgets('tapping the page away from text hides the keyboard (and saves)', (tester) async {
    final g = _gateway();
    g.handlers['update_planning_block'] = (_) => fakeBlockJson(id: 'b1', type: 'text', version: 2, payload: {
          'delta': [{'insert': 'xHello\n'}]
        });
    await tester.pumpWidget(planningTestApp(g, const PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();
    final focus = tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode;
    expect(focus.hasFocus, isTrue);
    await tester.tapAt(const Offset(400, 380)); // empty page below the text
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
  });
}
