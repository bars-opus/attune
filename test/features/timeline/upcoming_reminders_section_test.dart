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
}) {
  return ReminderModel(
    id: id,
    relationshipId: 'rel-1',
    createdBy: 'user-1',
    reminderType: 'anniversary',
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

    test('yearly reminder not yet passed this year returns this year\'s date', () {
      final reminder = _reminder(
        id: 'r2',
        title: 'Anniversary',
        remindAt: DateTime(2020, 12, 25),
        recurrence: 'yearly',
      );
      final result = nextOccurrence(reminder, now: DateTime(2026, 8, 28));
      expect(result, DateTime(2026, 12, 25));
    });

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

    test('keeps a yearly reminder whose remindAt year is in the past, using rolled-forward date', () {
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
    });

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
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('renders nothing when reminders list is empty', (
      tester,
    ) async {
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

    testWidgets(
      'renders nothing when the only reminder is a past one-off',
      (tester) async {
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
      },
    );

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
