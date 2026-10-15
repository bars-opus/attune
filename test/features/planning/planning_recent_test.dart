import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:attune/features/planning/presentation/screens/planning_recent_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_recent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

/// A plan as Recent lists it: the entry summary plus its category.
Map<String, dynamic> _recent(
  String id,
  String title,
  DateTime at, {
  String category = 'Trips',
}) => {
  'id': id,
  'title': title,
  'status': 'active',
  'last_activity_at': at.toUtc().toIso8601String(),
  'pinned': false,
  'date_start': null,
  'date_end': null,
  'checklist_done': 0,
  'checklist_total': 0,
  'category': {
    'id': 'cat-$category',
    'name': category,
    'icon': 'plane',
    'color': 'teal',
  },
};

FakePlanningGateway _gateway(List<Map<String, dynamic>> recent, {bool more = false}) =>
    FakePlanningGateway({
      'get_planning_home': (_) => {
        'categories': [
          fakeCategoryJson(id: 'c1', seedKey: 'trips', name: 'Trips', icon: 'plane', color: 'teal'),
        ],
      },
      'list_planning_recent': (p) {
        final limit = p['p_limit'] as int;
        final page = recent.take(limit).toList();
        return {
          'entries': page,
          'next_cursor':
              recent.length > limit || more
                  ? {'at': page.last['last_activity_at'], 'id': page.last['id']}
                  : null,
        };
      },
    });

void main() {
  final now = DateTime.now();
  List<Map<String, dynamic>> plans(int n) => [
    for (var i = 0; i < n; i++)
      _recent('e$i', 'Plan $i', now.subtract(Duration(hours: i)), category: i.isEven ? 'Trips' : 'Home'),
  ];

  test('the repository reads Recent with its paging and maps each category', () async {
    final g = _gateway(plans(3));
    final page = await PlanningRepository(g).listRecent('r1', limit: 6);
    expect(g.callsTo('list_planning_recent').single, {
      'p_relationship_id': 'r1',
      'p_cursor_at': null,
      'p_cursor_id': null,
      'p_limit': 6,
    });
    expect(page.entries.map((e) => e.entry.title), ['Plan 0', 'Plan 1', 'Plan 2']);
    expect(page.entries[1].categoryName, 'Home');
    expect(page.entries[1].categoryColor, 'teal');
    expect(page.hasMore, isFalse);
  });

  testWidgets('Recent sits above the categories: five plans in one card, See all for more', (t) async {
    await t.pumpWidget(planningTestApp(_gateway(plans(8)), const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      expect(find.text('Plan $i'), findsOneWidget);
    }
    expect(find.text('Plan 5'), findsNothing);
    // One card holds the five, and it comes before the categories.
    final card = find.ancestor(of: find.text('Plan 0'), matching: find.byType(CardInkWell));
    expect(find.descendant(of: card.first, matching: find.text('Plan 4')), findsOneWidget);
    expect(t.getTopLeft(find.text('Plan 4')).dy, lessThan(t.getTopLeft(find.text('Trips').last).dy));
    // The category and the time, joined the app's way.
    expect(find.text(MyDateFormat.join(['Home', planningRowDate(now.subtract(const Duration(hours: 1)), DateTime.now())])), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('five or fewer: no See all', (t) async {
    await t.pumpWidget(planningTestApp(_gateway(plans(5)), const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
  });

  testWidgets('nothing yet: no Recent at all, just the categories', (t) async {
    await t.pumpWidget(planningTestApp(_gateway(const []), const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.text('Recent'), findsNothing);
    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('if Recent can\'t load, the categories still show', (t) async {
    final g = _gateway(const [])..handlers.remove('list_planning_recent');
    await t.pumpWidget(planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    expect(find.text('Recent'), findsNothing);
    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('a recent plan opens', (t) async {
    final g = _gateway(plans(2));
    g.handlers['get_planning_entry'] = (_) => fakeEntryDetailJson(id: 'e0');
    await t.pumpWidget(planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Plan 0'));
    await t.pumpAndSettle();
    expect(find.byType(PlanningEntryScreen), findsOneWidget);
  });

  testWidgets('See all lists every recent plan, grouped by when, with its category', (t) async {
    final list = [
      _recent('a', 'Today plan', now),
      _recent('b', 'Older plan', now.subtract(const Duration(days: 40)), category: 'Home'),
      ...plans(6).skip(1),
    ];
    await t.pumpWidget(planningTestApp(_gateway(list), const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    await t.tap(find.text('See all'));
    await t.pumpAndSettle();
    expect(find.byType(PlanningRecentScreen), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Older plan'),
      200,
      scrollable: find.descendant(of: find.byType(PlanningRecentScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Older plan'), findsOneWidget);
  });

  testWidgets('See all loads the next page as it scrolls', (t) async {
    final list = [for (var i = 0; i < 45; i++) _recent('p$i', 'Item $i', now.subtract(Duration(minutes: i)))];
    final g = _gateway(list);
    g.handlers['list_planning_recent'] = (p) {
      final limit = p['p_limit'] as int;
      final afterId = p['p_cursor_id'] as String?;
      final start = afterId == null ? 0 : list.indexWhere((e) => e['id'] == afterId) + 1;
      final page = list.skip(start).take(limit).toList();
      final more = start + limit < list.length;
      return {
        'entries': page,
        'next_cursor': more ? {'at': page.last['last_activity_at'], 'id': page.last['id']} : null,
      };
    };
    await t.pumpWidget(planningTestApp(g, const PlanningRecentScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('Item 44'),
      400,
      scrollable: find.descendant(of: find.byType(PlanningRecentScreen), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('Item 44'), findsOneWidget);
    expect(g.callsTo('list_planning_recent').length, greaterThan(1));
  });

  testWidgets('recent rows have no leading icon, like a category\'s plans', (t) async {
    await t.pumpWidget(planningTestApp(_gateway(plans(3)), const PlanningHomeScreen(relationshipId: 'r1')));
    await t.pumpAndSettle();
    final row = find.ancestor(of: find.text('Plan 0'), matching: find.byType(PlanningRecentRow));
    expect(find.descendant(of: row, matching: find.byIcon(planningIcon('plane'))), findsNothing);
    expect(find.descendant(of: row, matching: find.byType(Icon)), findsNothing);
  });
}
