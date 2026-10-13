import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

final _now = DateTime.now();
String _ago(int days) => _now.subtract(Duration(days: days)).toUtc().toIso8601String();

Map<String, dynamic> _summary(String id, String title, String at, {bool pinned = false}) => {
      'id': id, 'title': title, 'status': 'active', 'last_activity_at': at, 'pinned': pinned,
      'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0,
    };

PlanningEntrySummary _e(String title, DateTime at) =>
    PlanningEntrySummary.fromJson(_summary(title, title, at.toUtc().toIso8601String()));

PlanningCategory _notes() => PlanningCategory.fromJson(
    fakeCategoryJson(id: 'c1', seedKey: 'notes', name: 'Notes', icon: 'note', color: 'indigo', entryCount: 4));

void main() {
  test('plans group by last activity like Apple Notes, newest group first', () {
    final now = DateTime(2026, 10, 12, 12);
    final sections = planningDateSections([
      _e('a', DateTime(2026, 10, 12, 8)),
      _e('b', DateTime(2026, 10, 11, 20)),
      _e('c', DateTime(2026, 10, 8)),
      _e('d', DateTime(2026, 9, 25)),
      _e('e', DateTime(2026, 3, 3)),
      _e('f', DateTime(2025, 6, 1)),
      _e('g', DateTime(2026, 10, 12, 1)),
    ], now);
    expect([for (final s in sections) s.title],
        ['Today', 'Yesterday', 'Previous 7 Days', 'Previous 30 Days', 'March', '2025']);
    expect([for (final x in sections.first.entries) x.title], ['a', 'g']);
  });

  testWidgets('Notes: Pinned, then date sections, each a titled card of InfoRowWidget rows', (tester) async {
    final g = FakePlanningGateway({
      'mark_planning_category_seen': (_) => {'seen_at': _ago(0)},
      'list_planning_entries': (p) => p['p_group'] == 'open'
          ? {
              'pinned': [_summary('p', 'Pass words', _ago(40), pinned: true)],
              'entries': [_summary('t', 'Shopping', _ago(0)), _summary('y', 'Surveys', _ago(1))],
              'next_cursor': null,
            }
          : {'entries': [_summary('z', 'Old trip', _ago(3))], 'next_cursor': null},
    });
    await tester.pumpWidget(planningTestApp(g, PlanningCategoryScreen(relationshipId: 'r1', category: _notes())));
    await tester.pumpAndSettle();

    final headers = ['Pinned', 'Today', 'Yesterday'];
    final ys = [for (final h in headers) tester.getTopLeft(find.text(h).first).dy]; // headers come before row dates
    expect(ys, orderedEquals([...ys]..sort()), reason: 'Pinned first, then by date');
    for (final title in ['Pass words', 'Shopping', 'Surveys']) {
      final row = find.ancestor(of: find.text(title), matching: find.byType(InfoRowWidget));
      expect(row, findsOneWidget, reason: title);
      expect(find.ancestor(of: row, matching: find.byType(CardInkWell)), findsOneWidget, reason: '$title sits in its section card');
    }
    expect(find.text('Done & archived'), findsNothing, reason: 'moved to the app bar menu');

    // The add button is icon-only, labelled for screen readers.
    expect(find.byTooltip('New note'), findsOneWidget);
    expect(find.descendant(of: find.byType(FloatingActionButton), matching: find.byType(Text)), findsNothing);

    await tester.tap(find.byTooltip('Category options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done & archived'));
    await tester.pumpAndSettle();
    expect(find.text('Old trip'), findsOneWidget);
    expect(find.text('Previous 7 Days'), findsOneWidget);
  });
}
