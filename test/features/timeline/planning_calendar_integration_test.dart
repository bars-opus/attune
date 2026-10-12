import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/presentation/screens/planning_v2_entry_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/planning_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planning/v2/support/fake_planning_gateway.dart';
import '../planning/v2/support/planning_v2_test_app.dart';

PlanningCalendarEntry _item({bool complete = false}) => PlanningCalendarEntry(
      kind: PlanningCalendarKind.item, entryId: 'e1', itemId: 'i1',
      date: DateTime(2026, 6, 15), title: 'Water the plants', isComplete: complete);

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
        child: child,
      ));

  // The small circular indicator CalendarStrip draws under a day number
  // (see the original test for why "small and circular" rather than a size).
  bool dayCellHasDot(WidgetTester tester, String dayNumber) {
    final textFinder = find.text(dayNumber);
    if (textFinder.evaluate().isEmpty) return false;
    final cellColumn = find.ancestor(of: textFinder, matching: find.byType(Column)).evaluate().first;
    return find
        .descendant(
          of: find.byWidget(cellColumn.widget),
          matching: find.byWidgetPredicate((w) {
            if (w is! Container) return false;
            final d = w.decoration;
            final width = w.constraints?.maxWidth;
            return d is BoxDecoration && d.shape == BoxShape.circle && width != null && width > 0 && width <= 20;
          }),
        )
        .evaluate()
        .isNotEmpty;
  }

  testWidgets('CalendarStrip shows a dot for a day with only a Planning entry, none for an empty day', (tester) async {
    final day = DateTime(2026, 6, 15);
    await pump(
      tester,
      CalendarStrip(
        focusedMonth: DateTime(2026, 6, 1),
        eventsByDate: const {},
        planningEntriesByDate: {day: [_item()]},
        onDaySelected: (_) {},
        onMonthChanged: (_) {},
      ),
    );
    expect(dayCellHasDot(tester, '15'), isTrue);
    expect(dayCellHasDot(tester, '16'), isFalse);
  });

  testWidgets('a ticked to-do is struck through; an open one is not', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlanningDaySection(relationshipId: 'r1', entries: [_item(complete: true)])),
    ));
    expect(tester.widget<Text>(find.text('Water the plants')).style?.decoration, TextDecoration.lineThrough);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PlanningDaySection(relationshipId: 'r1', entries: [_item()])),
    ));
    expect(tester.widget<Text>(find.text('Water the plants')).style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('a date shows with the event icon', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningDaySection(relationshipId: 'r1', entries: [
          PlanningCalendarEntry(kind: PlanningCalendarKind.date, entryId: 'e9', itemId: null,
              date: DateTime(2026, 6, 15), title: 'Bali', isComplete: false),
        ]),
      ),
    ));
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
  });

  testWidgets('tapping a calendar row opens its plan', (tester) async {
    final g = FakePlanningGateway({'get_planning_entry': (p) => fakeEntryDetailJson(id: p['p_id'] as String)});
    await tester.pumpWidget(planningV2TestApp(
        g, Scaffold(body: PlanningDaySection(relationshipId: 'r1', entries: [_item()]))));
    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanningV2EntryScreen), findsOneWidget);
    expect(g.callsTo('get_planning_entry').single, {'p_id': 'e1'});
  });

  testWidgets('renders nothing for an empty day', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlanningDaySection(relationshipId: 'r1', entries: [])),
    ));
    expect(find.byType(ListTile), findsNothing);
  });
}
