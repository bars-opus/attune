import 'package:attune/core/widgets/feedback/error_state.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

FakePlanningGateway _gateway() => FakePlanningGateway({
      'get_planning_home': (_) => {
            'categories': [
              fakeCategoryJson(id: 'c1', seedKey: 'goals', name: 'Goals', icon: 'flag', color: 'rose', entryCount: 2, hasNew: true),
              fakeCategoryJson(id: 'c2', seedKey: 'trips', name: 'Trips', icon: 'plane', color: 'teal'),
              fakeCategoryJson(id: 'c3', name: 'Wedding', icon: 'ring', color: 'violet', hidden: true),
            ]
          },
    });

void main() {
  testWidgets('shows visible categories in order with counts and a labelled new dot', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('2 plans'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Wedding'), findsNothing, reason: 'hidden until expanded');
    expect(find.bySemanticsLabel('New from your partner'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('hidden categories appear under the Hidden row', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hidden (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Wedding'), findsOneWidget);
  });

  testWidgets('creating a category sends trimmed name and chosen icon and colour', (tester) async {
    final semantics = tester.ensureSemantics();
    final g = _gateway();
    g.handlers['create_planning_category'] = (p) => fakeCategoryJson(id: p['p_id'] as String, name: 'Moving');
    await tester.pumpWidget(planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Moving  ');
    await tester.pump(); // enterText does not pump; Save enables on rebuild
    await tester.tap(find.bySemanticsLabel('Icon box'));
    await tester.tap(find.bySemanticsLabel('Colour orange'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final call = g.callsTo('create_planning_category').single;
    expect(call['p_name'], 'Moving');
    expect(call['p_icon'], 'box');
    expect(call['p_color'], 'orange');
    expect(call['p_relationship_id'], 'r1');
    expect(g.callsTo('get_planning_home'), hasLength(2), reason: 'refetched after create');
    semantics.dispose(); // must be disposed inside the test body
  });

  testWidgets('a load error shows an actionable message and Retry', (tester) async {
    var fail = true;
    final g = _gateway();
    final ok = g.handlers['get_planning_home']!;
    g.handlers['get_planning_home'] = (p) {
      if (fail) throw Exception('offline');
      return ok(p);
    };
    await tester.pumpWidget(planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach Attune. Check your connection and try again.'), findsOneWidget);
    expect(find.byType(ErrorStateWidget), findsOneWidget, reason: 'the app\'s shared error state, not a Planning one-off');
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
  });

  testWidgets('an ended relationship shows the closed message, not Retry', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_home': (_) => throw const PostgrestException(message: 'planning:inactive', code: 'P0001'),
    });
    await tester.pumpWidget(planningTestApp(g, const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Planning is closed for this relationship.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('renders in dark mode without errors', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1'),
        themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('category name counts code points like the server: 21 flags stop at 20 (final review I3)', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '🇬🇭' * 21);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '🇬🇭' * 20);
    expect(find.text('40/40'), findsOneWidget);
  });

  testWidgets('Planning keeps its Calendar tab, which shows the shared calendar', (tester) async {
    await tester.pumpWidget(planningTestApp(_gateway(), const PlanningHomeScreen(relationshipId: 'r1')));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget, reason: 'the Planning tab shows the categories first');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(TimelineScreen), findsOneWidget);
  });
}

