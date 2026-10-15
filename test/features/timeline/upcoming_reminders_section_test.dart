import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

ReminderModel _reminder({
  required String id,
  required String title,
  required DateTime remindAt,
  String recurrence = 'none',
  String? linkedTimelineEventId,
  String type = 'anniversary',
}) {
  return ReminderModel(
    id: id,
    relationshipId: 'rel-1',
    createdBy: 'user-1',
    reminderType: type,
    title: title,
    remindAt: remindAt,
    recurrence: recurrence,
    sent: false,
    linkedTimelineEventId: linkedTimelineEventId,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('nextOccurrence', () {
    test('one-off reminder returns remindAt unchanged', () {
      final reminder = _reminder(
        id: 'r1',
        title: 'Trip',
        remindAt: DateTime(2026, 9, 15),
      );
      final result = nextOccurrence(reminder, now: DateTime(2026, 8, 28));
      expect(result, DateTime(2026, 9, 15));
    });

    test(
      'yearly reminder not yet passed this year returns this year\'s date',
      () {
        final reminder = _reminder(
          id: 'r2',
          title: 'Anniversary',
          remindAt: DateTime(2020, 12, 25),
          recurrence: 'yearly',
        );
        final result = nextOccurrence(reminder, now: DateTime(2026, 8, 28));
        expect(result, DateTime(2026, 12, 25));
      },
    );

    test('yearly reminder already passed this year rolls to next year', () {
      final reminder = _reminder(
        id: 'r3',
        title: 'Birthday',
        remindAt: DateTime(2020, 3, 1),
        recurrence: 'yearly',
      );
      final result = nextOccurrence(reminder, now: DateTime(2026, 8, 28));
      expect(result, DateTime(2027, 3, 1));
    });

    test(
      'a Feb 29 yearly reminder clamps to Feb 28 in a non-leap year, not March 1',
      () {
        // Algorithm Quality Review Checklist v3.1, item 6.1 (boundary
        // values): DateTime(2026, 2, 29) silently rolls to March 1st since
        // 2026 isn't a leap year — this reminder must fire on Feb 28, not
        // skip to March, matching REMINDERS.md's server-side generator
        // behavior for the same edge case.
        final reminder = _reminder(
          id: 'r4',
          title: 'Leap day anniversary',
          remindAt: DateTime(2024, 2, 29), // 2024 is a leap year
          recurrence: 'yearly',
        );
        final result = nextOccurrence(reminder, now: DateTime(2026, 1, 1));
        expect(result, DateTime(2026, 2, 28));
      },
    );

    test('a Feb 29 yearly reminder fires on Feb 29 in a leap year', () {
      final reminder = _reminder(
        id: 'r5',
        title: 'Leap day anniversary',
        remindAt: DateTime(2024, 2, 29),
        recurrence: 'yearly',
      );
      final result = nextOccurrence(reminder, now: DateTime(2028, 1, 1));
      expect(result, DateTime(2028, 2, 29)); // 2028 is a leap year
    });
  });

  group('upcomingReminders', () {
    test('excludes a one-off reminder whose date has already passed', () {
      final reminders = [
        _reminder(id: 'r1', title: 'Past trip', remindAt: DateTime(2026, 7, 1)),
        _reminder(
          id: 'r2',
          title: 'Future trip',
          remindAt: DateTime(2026, 9, 15),
        ),
      ];
      final result = upcomingReminders(reminders, now: DateTime(2026, 8, 28));
      expect(result.map((r) => r.id), ['r2']);
    });

    test('includes a reminder occurring today', () {
      final reminders = [
        _reminder(id: 'r1', title: 'Today', remindAt: DateTime(2026, 8, 28)),
      ];
      final result = upcomingReminders(reminders, now: DateTime(2026, 8, 28));
      expect(result.map((r) => r.id), ['r1']);
    });

    test(
      'keeps a yearly reminder whose remindAt year is in the past, using rolled-forward date',
      () {
        final reminders = [
          _reminder(
            id: 'r1',
            title: 'Anniversary',
            remindAt: DateTime(2020, 10, 25),
            recurrence: 'yearly',
          ),
        ];
        final result = upcomingReminders(reminders, now: DateTime(2026, 8, 28));
        expect(result.map((r) => r.id), ['r1']);
      },
    );

    test('empty input yields empty output', () {
      expect(upcomingReminders(const [], now: DateTime(2026, 8, 28)), isEmpty);
    });

    test('excludes a reminder more than 3 months out', () {
      final reminders = [
        _reminder(
          id: 'r1',
          title: 'Within window',
          remindAt: DateTime(2026, 11, 20),
        ),
        _reminder(
          id: 'r2',
          title: 'Beyond window',
          remindAt: DateTime(2026, 12, 1),
        ),
      ];
      final result = upcomingReminders(reminders, now: DateTime(2026, 8, 28));
      expect(result.map((r) => r.id), ['r1']);
    });
  });

  group('linkedTimelineEventIds', () {
    test('collects ids from reminders that have a linked timeline event', () {
      final reminders = [
        _reminder(
          id: 'r1',
          title: 'A',
          remindAt: DateTime(2026, 9, 1),
          linkedTimelineEventId: 'evt-1',
        ),
        _reminder(id: 'r2', title: 'B', remindAt: DateTime(2026, 9, 2)),
        _reminder(
          id: 'r3',
          title: 'C',
          remindAt: DateTime(2026, 9, 3),
          linkedTimelineEventId: 'evt-2',
        ),
      ];
      final result = linkedTimelineEventIds(reminders);
      expect(result, {'evt-1', 'evt-2'});
    });

    test('empty when no reminders have a linked timeline event', () {
      final reminders = [
        _reminder(id: 'r1', title: 'A', remindAt: DateTime(2026, 9, 1)),
      ];
      expect(linkedTimelineEventIds(reminders), isEmpty);
    });
  });

  group('UpcomingRemindersSection', () {
    Future<void> pump(WidgetTester tester, Widget child) {
      return tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
        ),
      );
    }

    testWidgets('renders one row per reminder with title and countdown', (
      tester,
    ) async {
      final reminders = [
        _reminder(id: 'r1', title: "Emma's birthday", remindAt: DateTime.now()),
      ];
      await pump(
        tester,
        UpcomingRemindersSection(reminders: reminders, onReminderTap: null),
      );

      expect(find.text("Emma's birthday"), findsOneWidget);
      expect(find.text('Today - Reminder'), findsOneWidget);
    });

    testWidgets('in dark mode the occasion icons take Planning\'s dark category colours', (tester) async {
      final today = DateTime.now();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Scaffold(
              body: UpcomingRemindersSection(
                reminders: [
                  _reminder(id: 'r1', title: "Ama's birthday", type: 'birthday',
                      remindAt: DateTime(today.year, today.month, today.day + 2)),
                ],
                onReminderTap: null,
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.text("Ama's birthday"));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(
        tester.widget<Icon>(find.byIcon(FontAwesomeIcons.birthdayCake)).color,
        planningCategoryFill(context, 'pink'),
      );
    });

    testWidgets('rows read like the Agenda\'s, every icon fitting the occasion', (tester) async {
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final reminders = [
        _reminder(id: 'r1', title: "Ama's birthday", type: 'birthday', recurrence: 'yearly',
            remindAt: day.add(const Duration(days: 5))),
        _reminder(id: 'r2', title: 'Dentist', type: 'custom', remindAt: day.add(const Duration(days: 1))),
        _reminder(id: 'r3', title: 'Our anniversary', type: 'anniversary', recurrence: 'yearly',
            remindAt: day.add(const Duration(days: 9))),
      ];
      await pump(tester, UpcomingRemindersSection(reminders: reminders, onReminderTap: null));
      Finder inRow(String title, Finder f) =>
          find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(InfoRowWidget)), matching: f);
      // Every icon in a row fits its occasion: the circle and the end.
      expect(inRow("Ama's birthday", find.byIcon(Icons.cake_outlined)), findsOneWidget);
      expect(inRow("Ama's birthday", find.byIcon(FontAwesomeIcons.birthdayCake)), findsOneWidget);
      expect(inRow('Our anniversary', find.byIcon(Icons.celebration_outlined)), findsOneWidget);
      expect(inRow('Our anniversary', find.byIcon(FontAwesomeIcons.champagneGlasses)), findsOneWidget);
      expect(inRow('Dentist', find.byIcon(Icons.notifications_none_rounded)), findsOneWidget);
      expect(inRow('Dentist', find.byIcon(FontAwesomeIcons.bell)), findsOneWidget);
      // No repeat / one-off icons any more.
      expect(find.byIcon(Icons.event_repeat_rounded), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      // Each occasion has its own colour, as bright as Planning's category
      // icons (birthday pink, anniversary gold).
      final context = tester.element(find.text('Dentist'));
      Color? colourOf(IconData icon) => tester.widget<Icon>(find.byIcon(icon)).color;
      expect(colourOf(FontAwesomeIcons.birthdayCake), planningCategoryFill(context, 'pink'));
      expect(colourOf(FontAwesomeIcons.champagneGlasses), planningCategoryFill(context, 'amber'));
      expect(colourOf(FontAwesomeIcons.birthdayCake), isNot(colourOf(FontAwesomeIcons.champagneGlasses)));
      // Countdown, then what it is — as in the Agenda.
      expect(find.text('In 5 days - Reminder'), findsOneWidget);
      expect(find.text('Tomorrow - Reminder'), findsOneWidget);
    });

    testWidgets(
      'lays out like Planning: an Upcoming title over one card holding the rows',
      (tester) async {
        final now = DateTime.now();
        await pump(
          tester,
          UpcomingRemindersSection(
            reminders: [
              _reminder(id: 'r1', title: 'First', remindAt: now),
              _reminder(
                id: 'r2',
                title: 'Second',
                remindAt: now.add(const Duration(days: 3)),
              ),
            ],
            onReminderTap: null,
          ),
        );

        expect(find.text('Upcoming'), findsOneWidget);
        final card = find.byType(CardInkWell);
        expect(card, findsOneWidget, reason: 'one card for the whole list');
        expect(
          tester.getTopLeft(find.text('Upcoming')).dy,
          lessThan(tester.getTopLeft(card).dy),
        );
        final rows =
            tester
                .widgetList<InfoRowWidget>(
                  find.descendant(
                    of: card,
                    matching: find.byType(InfoRowWidget),
                  ),
                )
                .toList();
        expect(rows.map((r) => r.title), ['First', 'Second']);
        expect(
          rows.map((r) => r.showDivider),
          [true, false],
          reason: 'a divider between rows, none under the last',
        );
      },
    );

    testWidgets('renders nothing when reminders list is empty', (tester) async {
      await pump(
        tester,
        const UpcomingRemindersSection(reminders: [], onReminderTap: null),
      );

      expect(find.byType(UpcomingRemindersSection), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('tapping a row calls onReminderTap with that reminder', (
      tester,
    ) async {
      ReminderModel? tapped;
      final reminder = _reminder(
        id: 'r1',
        title: 'Anniversary',
        remindAt: DateTime.now(),
      );
      await pump(
        tester,
        UpcomingRemindersSection(
          reminders: [reminder],
          onReminderTap: (r) => tapped = r,
        ),
      );

      await tester.tap(find.text('Anniversary'));
      expect(tapped?.id, 'r1');
    });

    testWidgets('sorts reminders by next occurrence, soonest first', (
      tester,
    ) async {
      final now = DateTime.now();
      final later = _reminder(
        id: 'r1',
        title: 'Later event',
        remindAt: now.add(const Duration(days: 10)),
      );
      final sooner = _reminder(
        id: 'r2',
        title: 'Sooner event',
        remindAt: now.add(const Duration(days: 2)),
      );
      await pump(
        tester,
        UpcomingRemindersSection(
          reminders: [later, sooner],
          onReminderTap: null,
        ),
      );

      final soonerCenter = tester.getCenter(find.text('Sooner event'));
      final laterCenter = tester.getCenter(find.text('Later event'));
      expect(soonerCenter.dy, lessThan(laterCenter.dy));
    });

    testWidgets('renders nothing when the only reminder is a past one-off', (
      tester,
    ) async {
      final pastReminder = _reminder(
        id: 'r1',
        title: 'Past one-off',
        remindAt: DateTime.now().subtract(const Duration(days: 42)),
      );
      await pump(
        tester,
        UpcomingRemindersSection(
          reminders: [pastReminder],
          onReminderTap: null,
        ),
      );

      expect(find.text('Past one-off'), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets(
      'excludes a past one-off reminder while still showing a future one',
      (tester) async {
        final now = DateTime.now();
        final pastReminder = _reminder(
          id: 'r1',
          title: 'Past one-off',
          remindAt: now.subtract(const Duration(days: 42)),
        );
        final futureReminder = _reminder(
          id: 'r2',
          title: 'Future event',
          remindAt: now.add(const Duration(days: 5)),
        );
        await pump(
          tester,
          UpcomingRemindersSection(
            reminders: [pastReminder, futureReminder],
            onReminderTap: null,
          ),
        );

        expect(find.text('Past one-off'), findsNothing);
        expect(find.text('Future event'), findsOneWidget);
      },
    );
  });
}
