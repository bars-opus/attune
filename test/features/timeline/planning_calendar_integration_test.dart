import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/planning_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) {
          return MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: child),
            ),
          );
        },
        child: child,
      ),
    );
  }

  // Locates the small circular dot Container rendered beneath a given
  // day number, if one is present — the same dot/hollow-ring Container
  // CalendarStrip already draws for reminders. The day cell is
  // `Column(children: [Text(dayNumber), if (hasEvents) Row(dots...)])`,
  // so the dot lives as a DESCENDANT of the cell's own Column, a
  // sibling of the day-number Text — not an ancestor of the Text (the
  // Text's own ancestor Container chain only reaches the cell's outer
  // background/today-ring Container, which is always present
  // regardless of dots). Walk up from the Text to its enclosing Column,
  // then look for a small circular decorated Container within that
  // Column, distinguishing "this day has a dot" from "this day merely
  // renders its number" — the strengthening Step 5 itself calls for.
  bool dayCellHasDot(WidgetTester tester, String dayNumber) {
    final textFinder = find.text(dayNumber);
    if (textFinder.evaluate().isEmpty) return false;
    final cellColumn = find
        .ancestor(of: textFinder, matching: find.byType(Column))
        .evaluate()
        .first;
    final dotContainers = find.descendant(
      of: find.byWidget(cellColumn.widget),
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        // Distinguish the small indicator circle from the cell's own
        // larger circular background/today-ring Container, which is
        // always present regardless of indicators and also has
        // shape: BoxShape.circle. Matched by "small and circular"
        // rather than one exact pixel width: the indicators are now
        // sized from kCalendarEventAvatarDiameter (and the upcoming
        // ring from a fraction of it), so pinning an exact value here
        // re-breaks this test on every visual tweak without telling us
        // anything about the property under test.
        final width = widget.constraints?.maxWidth;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            width != null &&
            width > 0 &&
            width <= 20;
      }),
    );
    return dotContainers.evaluate().isNotEmpty;
  }

  testWidgets(
    'CalendarStrip shows a dot for a date with ONLY a planning entry '
    '(no timeline event, no reminder), and no dot for an empty date',
    (tester) async {
      final month = DateTime(2026, 6, 1);
      final planningDate = DateTime(2026, 6, 15);
      await pump(
        tester,
        CalendarStrip(
          focusedMonth: month,
          eventsByDate: const {},
          planningEntriesByDate: {
            planningDate: [
              PlanningCalendarEntryModel(
                kind: PlanningCalendarEntryKind.task,
                id: 't1',
                date: planningDate,
                title: 'Water the plants',
                isComplete: false,
              ),
            ],
          },
          onDaySelected: (_) {},
          onMonthChanged: (_) {},
        ),
      );

      expect(find.text('15'), findsOneWidget);
      expect(
        dayCellHasDot(tester, '15'),
        isTrue,
        reason:
            'a planning-only date must still show the hollow-ring dot, '
            'or it silently disappears from the strip',
      );
      // An entirely empty date (the 16th) must NOT show a dot — proves
      // the dot is data-driven, not always-on.
      expect(find.text('16'), findsOneWidget);
      expect(dayCellHasDot(tester, '16'), isFalse);
    },
  );

  testWidgets('PlanningDaySection renders a completed task with strikethrough styling', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningDaySection(entries: [
          PlanningCalendarEntryModel(
            kind: PlanningCalendarEntryKind.task,
            id: 't1',
            date: DateTime(2026, 6, 15),
            title: 'Water the plants',
            isComplete: true,
          ),
        ]),
      ),
    ));
    final text = tester.widget<Text>(find.text('Water the plants'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets(
    'PlanningDaySection renders an incomplete task WITHOUT strikethrough styling',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PlanningDaySection(entries: [
            PlanningCalendarEntryModel(
              kind: PlanningCalendarEntryKind.task,
              id: 't1',
              date: DateTime(2026, 6, 15),
              title: 'Water the plants',
              isComplete: false,
            ),
          ]),
        ),
      ));
      final text = tester.widget<Text>(find.text('Water the plants'));
      expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
    },
  );

  testWidgets('PlanningDaySection renders nothing for an empty entry list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlanningDaySection(entries: [])),
    ));
    expect(find.byType(ListTile), findsNothing);
  });
}
