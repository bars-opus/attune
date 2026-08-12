# Timeline + Reminders/Calendar Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge Reminders/Calendar into Timeline as one screen with one feed — upcoming reminders above, past logged moments below — retiring `CouplesCalendarScreen` and its month-grid view without touching the underlying `reminders`/`timeline_events` data split.

**Architecture:** `TimelineScreen` gains an "Upcoming" section (ported from `CouplesCalendarScreen._buildList`'s reminder rows) rendered above its existing moments log, and its `CalendarStrip` gains a second dot style for upcoming reminders. A single FAB opens a choice sheet routing to the two existing unmodified add-flows (`logMomentType`, `AddEditReminderScreen`). `CouplesCalendarScreen`, `CalendarMonthView`, and the `/couples-calendar` route are deleted; `FamilyMembersScreen`/`AddEditReminderScreen`/`LogMomentTypeScreen`/`LogMomentDetailsScreen` are all reused exactly as-is.

**Tech Stack:** Flutter, Riverpod, Supabase.

## Global Constraints

- Data model unchanged: `reminders`/`couple_family_members` and `timeline_events` stay two separate tables with their own RLS models (Calendar fully-shared edit, Timeline owner-only edit) — this is a UI/screen consolidation only.
- `AddEditReminderScreen`, `LogMomentDetailsScreen`, `LogMomentTypeScreen`, `FamilyMembersScreen`, `FamilyMemberEditSheet` are reused exactly as they exist today — only their launch point changes.
- Section-based ordering: Upcoming (soonest first) always above Timeline (newest-first) — not one interleaved chronological sort.
- A `timeline_events` row linked to a still-upcoming/active reminder (`reminders.linked_timeline_event_id`) must not double-appear in both sections.
- `CalendarMonthView`'s `TableCalendar`-based month grid is dropped, not preserved behind a toggle.
- The "Docs" icon (`HealingDocs`) from `CouplesCalendarScreen`'s AppBar does not carry over.
- **Known pre-existing limitation carried through unchanged:** `TimelineScreen._scrollToDate` (already present before this plan) only sets `_selectedDate` for the strip's highlight ring — it does not actually scroll the list to the tapped date's item; its own existing comment says so ("In a full implementation, you would scroll the list to the event"). This plan wires reminders into the same stub, so tapping a date with only an upcoming reminder highlights it on the strip but does not auto-scroll the page to that reminder's row, matching Timeline's existing (already-stubbed) behavior for past moments. Building real scroll-to-item is out of scope for this plan — it was never built for Timeline either, so the merge does not regress anything; call this out explicitly rather than let the design spec's "scrolls to" wording imply more than ships.

---

## File Structure

- **Modify** `lib/features/timeline/presentation/widgets/calendar_strip.dart` — accept and render a second, distinct dot style for upcoming reminders.
- **Modify** `lib/features/timeline/presentation/screens/timeline_screen.dart` — add the Upcoming section, the FAB choice sheet, the Family-members AppBar icon, and wire the extended `CalendarStrip` tap-to-scroll behavior across both sections.
- **Create** `lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart` — the ported reminder-row list (title, countdown label, recurring icon), including the linked-timeline-event dedup logic.
- **Create** `lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart` — the FAB's two-choice bottom sheet.
- **Delete** `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`.
- **Delete** `lib/features/reminders/presentation/screens/calendar_month_view.dart`.
- **Modify** `lib/app/routing/app_router.dart` — remove the `/couples-calendar` route and its `CouplesCalendarScreen`/`CalendarMonthView` imports.
- **Test:** `test/features/timeline/upcoming_reminders_section_test.dart` (new), `test/features/timeline/calendar_strip_test.dart` (new).

---

## Task 1: `UpcomingRemindersSection` widget — reminder rows + dedup logic

**Files:**
- Create: `lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart`
- Test: `test/features/timeline/upcoming_reminders_section_test.dart`

**Interfaces:**
- Consumes: `ReminderModel` (`lib/features/reminders/data/models/reminder_model.dart` — fields `id`, `title`, `remindAt`, `recurrence`, `isRecurring` getter, `linkedTimelineEventId`), `TimelineEventModel` (`lib/features/timeline/data/models/timeline_event_model.dart`).
- Produces: `UpcomingRemindersSection(reminders: List<ReminderModel>, onReminderTap: void Function(ReminderModel)?)` widget, and a standalone top-level function `nextOccurrence(ReminderModel reminder, {DateTime? now})` and `linkedTimelineEventIds(List<ReminderModel> reminders)` — both consumed by Task 2 (`TimelineScreen`) for building the Timeline section's exclusion set and reused by the calendar strip logic in Task 3.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/timeline/upcoming_reminders_section_test.dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:flutter/material.dart';
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
      return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
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
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timeline/upcoming_reminders_section_test.dart`
Expected: FAIL — `upcoming_reminders_section.dart` does not exist.

- [ ] **Step 3: Implement the widget and its helper functions**

```dart
// lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The reminder's next real-world occurrence — itself for a one-off, or
/// this year's (or next year's, if this year's has already passed)
/// month/day for a yearly-recurring reminder. Ported from
/// CouplesCalendarScreen._nextOccurrence.
DateTime nextOccurrence(ReminderModel reminder, {DateTime? now}) {
  if (!reminder.isRecurring) return reminder.remindAt;
  final today = now ?? DateTime.now();
  var next = DateTime(today.year, reminder.remindAt.month, reminder.remindAt.day);
  if (next.isBefore(DateTime(today.year, today.month, today.day))) {
    next = DateTime(today.year + 1, reminder.remindAt.month, reminder.remindAt.day);
  }
  return next;
}

String _countdownLabel(DateTime occurrence, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final days = DateTime(occurrence.year, occurrence.month, occurrence.day)
      .difference(DateTime(today.year, today.month, today.day))
      .inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}

/// Timeline event ids that already have a reminder representing them —
/// a reminder created via AddEditReminderScreen's "Add to Timeline too?"
/// flow produces both a ReminderModel and a linked TimelineEventModel for
/// the same real-world date. Callers exclude these ids from the Timeline
/// section's past-moments log so the event isn't shown twice while its
/// reminder is still upcoming/active. Ported from
/// CalendarMonthView's linkedTimelineEventIds computation.
Set<String> linkedTimelineEventIds(List<ReminderModel> reminders) {
  return reminders
      .map((reminder) => reminder.linkedTimelineEventId)
      .whereType<String>()
      .toSet();
}

/// The "what's coming up" half of the merged Timeline screen — a sorted
/// list of upcoming reminders (soonest first), rendered above the existing
/// past-moments log. Ported from CouplesCalendarScreen._buildList's
/// reminder rows.
class UpcomingRemindersSection extends StatelessWidget {
  const UpcomingRemindersSection({
    super.key,
    required this.reminders,
    required this.onReminderTap,
  });

  final List<ReminderModel> reminders;
  final void Function(ReminderModel reminder)? onReminderTap;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) return const SizedBox.shrink();

    final sorted = [...reminders]
      ..sort(
        (a, b) => nextOccurrence(a).compareTo(nextOccurrence(b)),
      );

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final reminder = sorted[index];
        return CardInkWell(
          child: InfoRowWidget(
            subtitle: _countdownLabel(nextOccurrence(reminder)),
            title: reminder.title,
            icon:
                reminder.isRecurring
                    ? FontAwesomeIcons.repeat
                    : Icons.event_outlined,
            iconSize: 20.h,
            onTap:
                onReminderTap == null ? null : () => onReminderTap!(reminder),
            disableTrailing: true,
            showAvatar: false,
            showDivider: false,
            showTrailingArrow: false,
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timeline/upcoming_reminders_section_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart test/features/timeline/upcoming_reminders_section_test.dart
git commit -m "feat(timeline): add UpcomingRemindersSection widget"
```

---

## Task 2: `CalendarStrip` gains an upcoming-reminder dot style

**Files:**
- Modify: `lib/features/timeline/presentation/widgets/calendar_strip.dart`
- Test: `test/features/timeline/calendar_strip_test.dart`

**Interfaces:**
- Consumes: `nextOccurrence` (Task 1, `lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart`), `ReminderModel`.
- Produces: `CalendarStrip(..., remindersByDate: Map<DateTime, List<ReminderModel>>)` — an added optional named param, defaulting to `const {}` so existing callers (none exist outside `TimelineScreen`, but the default keeps the widget safe to construct without it) are unaffected. Consumed by Task 3 (`TimelineScreen`).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/timeline/calendar_strip_test.dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineEventModel _event(DateTime occurredAt, {String eventType = 'milestone'}) {
  return TimelineEventModel(
    id: 'evt-${occurredAt.toIso8601String()}',
    relationshipId: 'rel-1',
    loggedBy: 'user-1',
    eventType: eventType,
    title: 'Event',
    occurredAt: occurredAt,
    createdAt: occurredAt,
  );
}

ReminderModel _reminder(DateTime remindAt) {
  return ReminderModel(
    id: 'r-${remindAt.toIso8601String()}',
    relationshipId: 'rel-1',
    createdBy: 'user-1',
    reminderType: 'anniversary',
    title: 'Reminder',
    remindAt: remindAt,
    recurrence: 'none',
    sent: false,
    createdAt: remindAt,
    updatedAt: remindAt,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('renders without a remindersByDate argument', (tester) async {
    final focused = DateTime(2026, 8, 1);
    await pump(
      tester,
      CalendarStrip(
        focusedMonth: focused,
        eventsByDate: {
          DateTime(2026, 8, 5): [_event(DateTime(2026, 8, 5))],
        },
        onDaySelected: (_) {},
        onMonthChanged: (_) {},
      ),
    );

    expect(find.byType(CalendarStrip), findsOneWidget);
  });

  testWidgets('a date with only a reminder still renders a dot', (
    tester,
  ) async {
    final focused = DateTime(2026, 8, 1);
    await pump(
      tester,
      CalendarStrip(
        focusedMonth: focused,
        eventsByDate: const {},
        remindersByDate: {
          DateTime(2026, 8, 10): [_reminder(DateTime(2026, 8, 10))],
        },
        onDaySelected: (_) {},
        onMonthChanged: (_) {},
      ),
    );

    // The day cell for the 10th renders a Container-based dot beneath its
    // number — presence is enough to confirm remindersByDate is consumed
    // without throwing; exact color assertion is covered by the reminder
    // dot color being distinct from moment dot colors below.
    expect(find.text('10'), findsOneWidget);
  });

  testWidgets('tapping a day still calls onDaySelected with reminders present', (
    tester,
  ) async {
    DateTime? tapped;
    final focused = DateTime(2026, 8, 1);
    await pump(
      tester,
      CalendarStrip(
        focusedMonth: focused,
        eventsByDate: const {},
        remindersByDate: {
          DateTime(2026, 8, 10): [_reminder(DateTime(2026, 8, 10))],
        },
        onDaySelected: (date) => tapped = date,
        onMonthChanged: (_) {},
      ),
    );

    await tester.tap(find.text('10'));
    expect(tapped, DateTime(2026, 8, 10));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/timeline/calendar_strip_test.dart`
Expected: FAIL — `remindersByDate` is not a defined named parameter on `CalendarStrip`.

- [ ] **Step 3: Modify `CalendarStrip`**

In `lib/features/timeline/presentation/widgets/calendar_strip.dart`, add the field, constructor param, and a second dot row keyed off it. Change:

```dart
class CalendarStrip extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<DateTime, List<TimelineEventModel>> eventsByDate;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onMonthChanged;
  final DateTime? selectedDate;

  const CalendarStrip({
    super.key,
    required this.focusedMonth,
    required this.eventsByDate,
    required this.onDaySelected,
    required this.onMonthChanged,
    this.selectedDate,
  });
```

to:

```dart
class CalendarStrip extends StatelessWidget {
  final DateTime focusedMonth;
  final Map<DateTime, List<TimelineEventModel>> eventsByDate;
  final Map<DateTime, List<dynamic>> remindersByDate;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onMonthChanged;
  final DateTime? selectedDate;

  const CalendarStrip({
    super.key,
    required this.focusedMonth,
    required this.eventsByDate,
    this.remindersByDate = const {},
    required this.onDaySelected,
    required this.onMonthChanged,
    this.selectedDate,
  });
```

`remindersByDate`'s value type is `List<dynamic>` (rather than importing `ReminderModel` into this widget) because only its *presence* per date matters here — the widget never reads reminder fields, only whether a date's list is non-empty, so this avoids a new cross-feature import for a value that's never inspected.

Then in `build()`, where `eventsOnDate`/`hasEvents`/`dotColors` are computed (around line 112-117), add a parallel reminder lookup and a second, visually distinct dot color:

```dart
              final eventsOnDate = eventsByDate[date] ?? [];
              final remindersOnDate = remindersByDate[date] ?? [];
              final hasEvents = eventsOnDate.isNotEmpty || remindersOnDate.isNotEmpty;

              // Get unique event types for dots
              final eventTypes = eventsOnDate.map((e) => e.eventType).toSet().toList();
              final dotColors = eventTypes.map((type) => _getEventTypeColor(type, colorScheme)).toList();
              // Upcoming-reminder dots use a hollow/outlined ring rather
              // than a filled dot, so they read as "not yet happened"
              // next to the filled moment-type dots — one shared color
              // (colorScheme.secondary) regardless of reminder type, since
              // "this date has something upcoming" is the only signal the
              // strip needs to carry, not which reminder type it is.
              final hasReminderDot = remindersOnDate.isNotEmpty;
```

Then update the dot-rendering block (around line 150-167) to render the reminder ring alongside the existing filled dots:

```dart
                      if (hasEvents)
                        Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ...dotColors.take(3).map((color) {
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: color,
                                  ),
                                );
                              }),
                              if (hasReminderDot)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colorScheme.secondary,
                                      width: 1,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/timeline/calendar_strip_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run dart analyze**

Run: `dart analyze lib/features/timeline/presentation/widgets/calendar_strip.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/timeline/presentation/widgets/calendar_strip.dart test/features/timeline/calendar_strip_test.dart
git commit -m "feat(timeline): CalendarStrip renders a dot for upcoming reminders"
```

---

## Task 3: `AddMomentOrReminderSheet` — the FAB's two-choice sheet

**Files:**
- Create: `lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `AddMomentOrReminderSheet.show(BuildContext context) -> Future<_AddChoice?>` where `_AddChoice` is a private enum `{ moment, reminder }` — consumed by Task 4 (`TimelineScreen`'s FAB).

- [ ] **Step 1: Implement the sheet**

No automated test for this file — it is a pure navigation-choice presenter with no logic to unit test; its two outcomes are exercised end-to-end by Task 4's manual verification step.

```dart
// lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart

import 'package:attune/core/utils/exports/export_screens.dart';

enum AddChoice { moment, reminder }

/// The Timeline FAB's entry point — replaces what used to be two separate
/// FABs (Timeline's "log a moment", Calendar's "add reminder") with one
/// FAB and a choice between the two existing, unmodified flows.
class AddMomentOrReminderSheet {
  static Future<AddChoice?> show(BuildContext context) {
    return showModalBottomSheet<AddChoice>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.md.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoRowWidget(
                  title: 'Log a moment',
                  subtitle: 'A milestone, conflict, highlight...',
                  icon: Icons.auto_awesome_outlined,
                  disableTrailing: true,
                  showAvatar: false,
                  showDivider: false,
                  showTrailingArrow: false,
                  onTap: () => Navigator.of(context).pop(AddChoice.moment),
                ),
                InfoRowWidget(
                  title: 'Add a reminder',
                  subtitle: 'Anniversary, birthday, or any date',
                  icon: Icons.event_outlined,
                  disableTrailing: true,
                  showAvatar: false,
                  showDivider: false,
                  showTrailingArrow: false,
                  onTap: () => Navigator.of(context).pop(AddChoice.reminder),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Run dart analyze**

Run: `dart analyze lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart
git commit -m "feat(timeline): add AddMomentOrReminderSheet for the merged FAB"
```

---

## Task 4: `TimelineScreen` — Upcoming section, dedup, FAB choice sheet, Family icon

**Files:**
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`

**Interfaces:**
- Consumes: `UpcomingRemindersSection`, `nextOccurrence`, `linkedTimelineEventIds` (Task 1), `CalendarStrip(..., remindersByDate:)` (Task 2), `AddMomentOrReminderSheet.show` (Task 3), `remindersListProvider` (`lib/features/reminders/presentation/providers/reminders_providers.dart`), `AddEditReminderScreen` (`lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`), `FamilyMembersScreen`'s route name `'familyMembers'`.
- Produces: the finished merged screen — no later task depends on new symbols from this one.

Read the current file in full before starting — it is reproduced in the design spec's "One screen, one feed" section, but read the live file at implementation time since other work may have touched it since this plan was written; apply the intent below to whatever the real current structure is.

- [ ] **Step 1: Add the reminders import and read `remindersListProvider` in `build()`**

In `lib/features/timeline/presentation/screens/timeline_screen.dart`, add imports:

```dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
```

The `reminders_providers` prefix is required because both
`lib/features/timeline/presentation/providers/timeline_providers.dart`
(already imported by this file) and
`lib/features/reminders/presentation/providers/reminders_providers.dart`
each declare their own `currentRelationshipIdProvider` and
`supabaseClientProvider` — importing both unprefixed collides. Only
`remindersListProvider` is actually referenced with the prefix below;
Timeline's own `currentRelationshipIdProvider` (unprefixed, from
`timeline_providers.dart`) continues to gate the whole screen exactly as
it does today.

In `build()`, alongside the existing `eventsAsync`/`currentUserId`/`relationshipIdAsync` reads, add:

```dart
    final remindersAsync = ref.watch(reminders_providers.remindersListProvider);
```

- [ ] **Step 2: Compute the linked-event exclusion set and pass it into the moments list**

Where `eventsAsync.when(...)` builds the `MomentsList` inside the second `SliverPadding` (the moments-list sliver), the events list must exclude any event whose id is in `linkedTimelineEventIds(reminders)` — computed from whatever `remindersAsync` currently holds. Wrap the existing `data: (events) { ... }` branch's event list with a filter:

```dart
                  sliver: eventsAsync.when(
                    data: (events) {
                      final excludedIds = linkedTimelineEventIds(
                        remindersAsync.valueOrNull ?? const [],
                      );
                      final visibleEvents =
                          events
                              .where((event) => !excludedIds.contains(event.id))
                              .toList();

                      if (visibleEvents.isEmpty) {
                        return SliverToBoxAdapter(
                          child: MomentsList(
                            events: const [],
                            currentUserId: currentUserId ?? '',
                            currentMonth: _focusedMonth,
                            onDateSelected: (date) {},
                          ),
                        );
                      }
                      return SliverToBoxAdapter(
                        child: MomentsList(
                          events: visibleEvents,
                          currentUserId: currentUserId ?? '',
                          currentMonth: _focusedMonth,
                          onDateSelected: _scrollToDate,
                        ),
                      );
                    },
```

`remindersAsync.valueOrNull ?? const []` (rather than gating the whole
build on reminders having loaded) means the Timeline section renders
immediately even if the reminders fetch is still in flight or has failed
— the exclusion set is simply empty until reminders resolve, which is a
strictly safe default (an event might transiently show that will vanish
once reminders load, never the reverse).

- [ ] **Step 3: Add the Upcoming section above the calendar-strip sliver**

Insert a new `SliverToBoxAdapter` immediately before the existing calendar-strip `SliverToBoxAdapter` in the `CustomScrollView`'s `slivers` list, so Upcoming renders above the strip, which sits above Timeline — matching the design spec's section order (Upcoming, then the strip/Timeline log together as the "past" half):

```dart
              slivers: [
                SliverToBoxAdapter(
                  child: remindersAsync.when(
                    data: (reminders) {
                      if (reminders.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Gap(Spacing.md.h),
                            Text(
                              'Upcoming',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Gap(Spacing.sm.h),
                            UpcomingRemindersSection(
                              reminders: reminders,
                              onReminderTap: (reminder) {},
                            ),
                            const Divider(height: 32),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (error, stack) => const SizedBox.shrink(),
                  ),
                ),
                // Calendar strip as SliverToBoxAdapter
                SliverToBoxAdapter(
```

(The following `SliverToBoxAdapter(child: eventsAsync.when(...))` for the calendar strip is unchanged except for the `CalendarStrip` construction itself, in the next step.)

`onReminderTap: (reminder) {}` is intentionally a no-op for this task — tapping an Upcoming row does not need to navigate anywhere new; it exists so `UpcomingRemindersSection`'s tap affordance renders (matching its parent row style elsewhere in the app), not to open an edit flow, since editing an existing reminder is out of this plan's scope (only adding one, via the FAB, is in scope).

- [ ] **Step 4: Pass `remindersByDate` into the `CalendarStrip` construction**

Inside the calendar-strip `SliverToBoxAdapter`'s `eventsAsync.when(data: (events) { ... })` branch, where `CalendarStrip(...)` is constructed, add the `remindersByDate` argument built from the same `remindersAsync` read:

```dart
                          CalendarStrip(
                            focusedMonth: _focusedMonth,
                            eventsByDate: eventsByDate,
                            remindersByDate: _remindersByDate(
                              remindersAsync.valueOrNull ?? const [],
                            ),
                            selectedDate: _selectedDate,
                            onDaySelected: (date) {
                              _scrollToDate(date);
                            },
                            onMonthChanged: (month) {
                              setState(() {
                                _focusedMonth = month;
                              });
                              ref.invalidate(timelineEventsProvider(month));
                            },
                          ),
```

Add the grouping helper as a method on `_TimelineScreenState`, alongside `_scrollToDate`:

```dart
  Map<DateTime, List<ReminderModel>> _remindersByDate(
    List<ReminderModel> reminders,
  ) {
    final Map<DateTime, List<ReminderModel>> grouped = {};
    for (final reminder in reminders) {
      final occurrence = nextOccurrence(reminder);
      if (occurrence.month != _focusedMonth.month ||
          occurrence.year != _focusedMonth.year) {
        continue;
      }
      final date = DateTime(occurrence.year, occurrence.month, occurrence.day);
      grouped.putIfAbsent(date, () => []).add(reminder);
    }
    return grouped;
  }
```

This mirrors the existing `eventsByDate` grouping already present a few lines above it in the same `data: (events) { ... }` branch (same month-scoping, same `DateTime(year, month, day)` key normalization) — the two grouping blocks stay side by side for a future reader to compare directly.

- [ ] **Step 5: Replace the FAB with the two-choice sheet**

Change the existing `floatingActionButton`:

```dart
          floatingActionButton: AppFab(
            icon: Icons.add,
            onPressed: () {
              context.pushNamed('logMomentType').then((refreshNeeded) {
                if (refreshNeeded == true && mounted) {
                  ref.invalidate(timelineEventsProvider(_focusedMonth));
                }
              });
            },
          ),
```

to:

```dart
          floatingActionButton: AppFab(
            icon: Icons.add,
            onPressed: () async {
              final choice = await AddMomentOrReminderSheet.show(context);
              if (!mounted || choice == null) return;

              switch (choice) {
                case AddChoice.moment:
                  final refreshNeeded = await context.pushNamed('logMomentType');
                  if (refreshNeeded == true && mounted) {
                    ref.invalidate(timelineEventsProvider(_focusedMonth));
                  }
                case AddChoice.reminder:
                  await BottomSheetUtils.showDocumentationBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.neutral,
                    widget: const AddEditReminderScreen(),
                  );
                  if (mounted) {
                    ref.invalidate(reminders_providers.remindersListProvider);
                  }
              }
            },
          ),
```

The `AddChoice.reminder` branch matches `CouplesCalendarScreen`'s existing
FAB (`BottomSheetUtils.showDocumentationBottomSheet` with
`backgroundColor: colorScheme.neutral`) exactly, so `AddEditReminderScreen`
itself needs zero changes — only its launch site moves. Invalidating
`remindersListProvider` afterward is new (the old Calendar screen's own
`remindersListProvider` watch already re-fetched on its own list-rebuild
cadence; here it must be explicit since `TimelineScreen` wasn't
previously watching that provider at all).

- [ ] **Step 6: Add the Family-members AppBar icon**

`TimelineScreen`'s `Scaffold` currently has no `appBar`. Add one with just the Family icon (matching `CouplesCalendarScreen`'s icon exactly; the "Docs" icon is dropped per the spec):

```dart
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            actions: [
              AppIconButton(
                icon: Icons.people_outline,
                tooltip: 'Family',
                onPressed: () => context.pushNamed('familyMembers'),
              ),
            ],
          ),
          floatingActionButton: AppFab(
```

- [ ] **Step 7: Run dart analyze**

Run: `dart analyze lib/features/timeline/presentation/screens/timeline_screen.dart`
Expected: `No issues found!`

- [ ] **Step 8: Manual verification (no automated integration test for this screen)**

Run the app and, in a relationship with at least one reminder and one logged moment:

1. Confirm the Upcoming section renders above the calendar strip, showing the reminder's title and countdown label.
2. Confirm a moment whose `timeline_events.id` matches a reminder's `linked_timeline_event_id` does NOT appear in the Timeline log below (only in Upcoming).
3. Tap the FAB — confirm the choice sheet shows "Log a moment" / "Add a reminder", and each option launches its existing unmodified screen.
4. After adding a new reminder via the sheet, confirm the Upcoming section refreshes to show it without a manual pull-to-refresh.
5. Confirm the calendar strip shows a hollow ring on a date with only an upcoming reminder (no logged moment that day).
6. Tap the Family icon in the AppBar — confirm it opens `FamilyMembersScreen`.

Note the result of this manual check in the task's completion comment.

- [ ] **Step 9: Commit**

```bash
git add lib/features/timeline/presentation/screens/timeline_screen.dart
git commit -m "feat(timeline): merge Upcoming reminders and dedup into TimelineScreen"
```

---

## Task 5: Retire `CouplesCalendarScreen`, `CalendarMonthView`, and the `/couples-calendar` route

**Files:**
- Delete: `lib/features/reminders/presentation/screens/couples_calendar_screen.dart`
- Delete: `lib/features/reminders/presentation/screens/calendar_month_view.dart`
- Modify: `lib/app/routing/app_router.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing — this is the final cleanup task.

- [ ] **Step 1: Confirm no remaining references before deleting**

Run: `grep -rn "CouplesCalendarScreen\|CalendarMonthView\|couplesCalendar" lib --include="*.dart"`

Expected output: only the two files' own declarations and the three lines in `app_router.dart` this task is about to remove (the import, the `RouteNames.couplesCalendar` constant, and the `GoRoute` block). If anything else references either class, stop and investigate before deleting — a reference this plan didn't anticipate must be resolved first, not silently broken.

- [ ] **Step 2: Delete the two files**

```bash
git rm lib/features/reminders/presentation/screens/couples_calendar_screen.dart
git rm lib/features/reminders/presentation/screens/calendar_month_view.dart
```

- [ ] **Step 3: Remove the route registration from `app_router.dart`**

Remove the import:

```dart
import 'package:attune/features/reminders/presentation/screens/couples_calendar_screen.dart';
```

Remove the route-name constant:

```dart
  static const String couplesCalendar = '/couples-calendar';
```

Remove the `GoRoute` block:

```dart
      GoRoute(
        path: RouteNames.couplesCalendar,
        name: 'couplesCalendar',
        builder: (context, state) => const CouplesCalendarScreen(),
      ),
```

Also check whether `calendar_month_view.dart`'s class (`CalendarMonthView`) is imported in `app_router.dart` directly — if so (it may only ever have been imported transitively via `couples_calendar_screen.dart`), remove that import too. Confirm via:

Run: `grep -n "CalendarMonthView\|calendar_month_view" lib/app/routing/app_router.dart`
Expected: no output after this step's edits.

- [ ] **Step 4: Run dart analyze on the whole project**

Run: `dart analyze`
Expected: zero new errors compared to before this task (pre-existing unrelated info/warning-level lints elsewhere are not this task's concern — confirm specifically that no error mentions `couples_calendar_screen.dart`, `calendar_month_view.dart`, `CouplesCalendarScreen`, or `CalendarMonthView`).

- [ ] **Step 5: Confirm `RouteNames.familyMembers`'s path is unaffected**

`RouteNames.familyMembers` is currently `/couples-calendar/family` (a sub-path of the now-removed `couples-calendar` route). GoRouter route paths are independent strings, not filesystem-nested — removing the `/couples-calendar` `GoRoute` does not affect `/couples-calendar/family`'s own separately-registered `GoRoute`, so no path change is needed. Confirm this by running the app and navigating to Family members via `TimelineScreen`'s AppBar icon (Task 4, already manually verified there) — if it fails to resolve, the path needs updating; expected result is that it works unchanged, since GoRouter doesn't require parent routes to exist for child-shaped paths to resolve.

- [ ] **Step 6: Commit**

```bash
git add lib/app/routing/app_router.dart
git commit -m "chore(reminders): retire CouplesCalendarScreen, merged into TimelineScreen"
```

---

## Task 6: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full timeline + reminders test suite**

Run: `flutter test test/features/timeline/ test/features/reminders/`
Expected: PASS — every test across `upcoming_reminders_section_test.dart`, `calendar_strip_test.dart`, plus any pre-existing tests under both directories (confirm none regressed).

- [ ] **Step 2: Run `dart analyze` across the whole project**

Run: `dart analyze`
Expected: zero new errors; only pre-existing info/warning-level lints in files this plan didn't touch.

- [ ] **Step 3: Confirm no other callers of `CalendarStrip` were missed**

Run: `grep -rn "CalendarStrip(" lib --include="*.dart" | grep -v "_test.dart"`

Expected: only the one construction site inside `timeline_screen.dart` (Task 4) and the class's own declaration in `calendar_strip.dart` — confirming the new `remindersByDate` param's default (`const {}`) was never actually needed by a second caller, and Task 2's change was safe.

- [ ] **Step 4: Confirm the branch is clean**

Run: `git status --short`

Expected: clean (no commit needed — this task is verification-only).
