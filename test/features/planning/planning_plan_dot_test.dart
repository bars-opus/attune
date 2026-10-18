// The per-plan "new from your partner" dot: on a plan's row in Recent and
// in its category, cleared by opening that plan.
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_category_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

/// A plan summary as the server sends it; new until [opened] holds its id.
Map<String, dynamic> _plan(
  String id,
  String title, {
  required bool partner,
  required Set<String> opened,
}) => {
  'id': id,
  'title': title,
  'status': 'active',
  'last_activity_at': DateTime.now().toUtc().toIso8601String(),
  'pinned': false,
  'date_start': null,
  'date_end': null,
  'checklist_done': 0,
  'checklist_total': 0,
  'has_new': partner && !opened.contains(id),
};

FakePlanningGateway _gateway(Set<String> opened) => FakePlanningGateway({
  'get_planning_home':
      (_) => {
        'categories': [
          fakeCategoryJson(
            id: 'c1',
            seedKey: 'trips',
            name: 'Trips',
            icon: 'plane',
            color: 'teal',
            entryCount: 2,
            hasNew: !opened.contains('e1'),
          ),
        ],
      },
  'list_planning_recent':
      (_) => {
        'entries': [
          for (final p in [
            _plan('e1', 'Lisbon', partner: true, opened: opened),
            _plan('e2', 'Accra', partner: false, opened: opened),
          ])
            {
              ...p,
              'category': {
                'id': 'c1',
                'name': 'Trips',
                'icon': 'plane',
                'color': 'teal',
              },
            },
        ],
        'next_cursor': null,
      },
  'list_planning_entries':
      (p) =>
          p['p_group'] == 'open'
              ? {
                'entries': [
                  _plan('e1', 'Lisbon', partner: true, opened: opened),
                  _plan('e2', 'Accra', partner: false, opened: opened),
                ],
                'pinned': [],
                'next_cursor': null,
              }
              : {'entries': [], 'pinned': [], 'next_cursor': null},
  'mark_planning_category_seen': (_) => {'seen_at': '2026-10-18T09:00:00Z'},
  // Opening a plan marks it seen on the server.
  'get_planning_entry': (p) {
    opened.add(p['p_id'] as String);
    return fakeEntryDetailJson(id: p['p_id'] as String);
  },
});

Finder _dotIn(String title) => find.descendant(
  of: find.widgetWithText(InfoRowWidget, title),
  matching: find.byType(PlanningNewDot),
);

void main() {
  test('has_new is read from the summary, and missing means not new', () {
    final j = _plan('e1', 'Lisbon', partner: true, opened: {});
    expect(PlanningEntrySummary.fromJson(j).hasNew, isTrue);
    expect(
      PlanningEntrySummary.fromJson({...j}..remove('has_new')).hasNew,
      isFalse,
    );
  });

  testWidgets(
    'Recent: the partner\'s plan carries the dot, until it is opened',
    (t) async {
      final g = _gateway({});
      await t.pumpWidget(
        planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')),
      );
      await t.pumpAndSettle();
      expect(_dotIn('Lisbon'), findsOneWidget);
      expect(_dotIn('Accra'), findsNothing);

      await t.tap(find.text('Lisbon'));
      await t.pumpAndSettle();
      expect(g.callsTo('get_planning_entry'), hasLength(1));
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        _dotIn('Lisbon'),
        findsNothing,
        reason: 'opened, so no longer new',
      );
      expect(
        find.bySemanticsLabel('New from your partner'),
        findsNothing,
        reason: 'the category dot went with it',
      );
    },
  );

  testWidgets(
    'a category\'s list: the dot is on the plan, and goes once it is opened',
    (t) async {
      final g = _gateway({});
      final cat = PlanningCategory.fromJson(
        fakeCategoryJson(
          id: 'c1',
          seedKey: 'trips',
          name: 'Trips',
          entryCount: 2,
          hasNew: true,
        ),
      );
      await t.pumpWidget(
        planningTestApp(
          g,
          PlanningCategoryScreen(relationshipId: 'r1', category: cat),
        ),
      );
      await t.pumpAndSettle();
      expect(_dotIn('Lisbon'), findsOneWidget);
      expect(_dotIn('Accra'), findsNothing);

      await t.tap(find.text('Lisbon'));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(_dotIn('Lisbon'), findsNothing);
    },
  );
}
