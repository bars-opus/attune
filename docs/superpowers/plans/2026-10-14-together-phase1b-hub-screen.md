# Together Phase 1b — The Together screen: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Together hub that couples actually open:
- an Agenda: Today, This week, Coming up, Our story;
- a Month view, which is the existing calendar, now showing Together events;
- an event editor: create, edit, delete, leave;
- entry points: `/together`, with `/timeline` as an alias, Planning's Calendar tab, the Conversations card, and notification taps.

**Architecture:** One new screen in `lib/features/together/presentation/`. It reads two ranges through Phase 1a's `togetherRangeProvider`: the next 91 days for plans and the last 93 days for recent moments. A pure `togetherAgenda()` function groups them into sections.
- The Month view reuses `TimelineScreen` rather than rebuilding the calendar. Its calendar dots and day sheet gain Together events.
- The editor writes through Phase 1a's `TogetherRepository`.
- All UI follows the Planning patterns the owner has shaped: titled section cards, `InfoRowWidget` rows, the app sheet with a Save header, the skeletons and the empty state.

**Tech Stack:** Flutter 3.29, Riverpod 2, GoRouter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` §4 (screen), §6.1, §8 Phase 1. The base is Phase 0 and 1a, both uncommitted on main.

## Global Constraints

- Work directly on `main`. Do not commit unless asked. Re-read every file before editing it; the owner edits by hand.
- `dart format` only the files you touch, one path at a time.
- **UI:**
  - Material 3 tokens: `Spacing.*`, `colorScheme`.
  - Sentence case, plain words.
  - Every state is handled: loading uses a skeleton, errors use the app's `ErrorStateWidget`, and there is an empty state.
  - Section cards match Planning: a title at `fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0)`, `titleSmall` w600 at `onSurface` 0.8 alpha, then `Padding(Spacing.allMd)` around a `CardInkWell(margin: EdgeInsets.zero)`.
- **Hard rules (spec §3):**
  - Partner-affecting actions are proposals (Phase 2), so 1b never sets the partner as owner.
  - Busy and private events are only ever editable by their creator, and the server already enforces that.
  - No counters or tallies anywhere in the UI.
- The full suite has one known pre-existing failure: `planning_home_screen_test.dart: shows visible categories…`.

## Rulings (deviations from the spec, decided while planning)

- **R1:** Planning's Calendar tab embeds the Together screen instead of the spec's single "Open Together" row, and the duplicate Map tab is removed. A tab holding one link row is poor UX, and this keeps the owner's two-tab Planning home. Cost if wrong: a one-line content swap.
- **R2:** On the Conversations card, the Calendar row becomes a Together row, but the Planning row stays. The spec replaced both, which would remove Planning's only entry from home. Cost if wrong: deleting one row.
- **R3:** The Month view is the existing `TimelineScreen`, taught to show Together events, rather than a rebuilt calendar. This keeps the Family button, stories, the day sheet and the moments archive working unchanged. Cost if wrong: a later rebuild.
- **R4:** "Coming up" is a section of rows with "In N days" text, not horizontal countdown cards, matching the card-and-row language used everywhere else. Cost if wrong: a styling change.
- **R5:** "Needs you", "Rituals" and "On this day" are left out. They belong to Phases 2–4 and have no data yet, and empty sections would be noise. Cost if wrong: none.
- **R6:** PostHog (spec D14) moves to its own small plan. It needs the owner's PostHog project key and host, plus native manifest and Info.plist setup. Cost if wrong: metrics start later.
- **R7:** `/timeline` becomes an alias that builds the Together screen; `/together` is the canonical route. Notification taps for `moment_logged` and `reminder_upcoming` keep `RouteNames.timeline`, which now opens Together, and `together_event` uses `RouteNames.together`. Cost if wrong: none.

## Review Focus

1. **An event at 23:30 tonight seen by a partner in a zone 6 hours ahead** belongs to their tomorrow. Grouping uses `TogetherItem.day`, which is local. Pinned in Task 1's test.
2. **A 5-day trip** shows on each of its days in Today and This week, but only once in Coming up. Pinned in Task 1's test.
3. **The partner's view of a busy-only event** shows "Busy", can't be opened for editing, and offers no delete. Pinned in Task 3 and Task 4 tests.
4. **Saving an event with an empty title or an end before its start** keeps the sheet open with a plain message and sends nothing. Pinned in Task 4's test.
5. **A brand-new couple with nothing at all** sees the empty state with three actions, not blank sections. Pinned in Task 5's test.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/features/together/domain/together_agenda.dart` | `TogetherAgenda`, `togetherAgenda()`, ranges |
| `lib/features/together/domain/couple_event_draft.dart` (modify) | `CoupleEventDraft.fromItem` |
| `lib/features/together/presentation/together_providers.dart` (modify) | Me, partner id, device zone, clock providers |
| `lib/features/together/presentation/widgets/together_section.dart` | Planning-style titled section card |
| `lib/features/together/presentation/widgets/together_item_row.dart` | One agenda row |
| `lib/features/together/presentation/widgets/couple_event_sheet.dart` | `showCoupleEventSheet` editor |
| `lib/features/together/presentation/screens/together_screen.dart` | The hub |
| `lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart` (modify) | Adds an "event" choice |
| `lib/features/timeline/presentation/screens/timeline_screen.dart` (modify) | Shows Together events in the month; FAB event choice |
| `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` (modify) | Together event rows |
| `lib/app/routing/app_router.dart` (modify) | `RouteNames.together`, `/timeline` alias |
| `lib/core/notifications/config/notification_config.dart` (modify) | `together_event` → `/together` |
| `lib/features/planning/presentation/screens/planning_home_screen.dart` (modify) | Calendar tab embeds Together; Map tab removed |
| `lib/features/chat/presentation/screens/conversations_screen.dart` (modify) | Together row |
| `test/features/together/*`, `test/features/planning/support/planning_test_app.dart` (modify) | Tests and overrides |

---

### Task 1: Agenda grouping and draft-from-item (pure Dart)

**Files:**
- Create: `lib/features/together/domain/together_agenda.dart`
- Modify: `lib/features/together/domain/couple_event_draft.dart`
- Test: `test/features/together/together_agenda_test.dart`, `test/features/together/couple_event_draft_from_item_test.dart`

**Interfaces:**
- Produces:
  - `class TogetherAgenda`, with:
    - `today: List<TogetherItem>`;
    - `week: List<({DateTime day, List<TogetherItem> items})>`;
    - `comingUp: List<TogetherItem>`;
    - `recentMoments: List<TogetherItem>`;
    - `bool get isEmpty`.
  - `TogetherAgenda togetherAgenda({required List<TogetherItem> upcoming, required List<TogetherItem> past, required DateTime now})`;
  - `({DateTime start, DateTime end}) togetherUpcomingRange(DateTime now)`, covering today to today + 90;
  - `({DateTime start, DateTime end}) togetherPastRange(DateTime now)`, covering today − 93 to today − 1 (a span of 92 days);
  - `factory CoupleEventDraft.fromItem(TogetherItem item)`.

- [ ] **Step 1: Write the failing tests**

`test/features/together/together_agenda_test.dart`:

```dart
import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _i(
  String id,
  DateTime day, {
  TogetherItemKind kind = TogetherItemKind.event,
  DateTime? startsAt,
  String title = 'x',
}) => TogetherItem(
  kind: kind,
  id: id,
  date: DateTime(day.year, day.month, day.day),
  startsAt: startsAt,
  allDay: startsAt == null,
  title: title,
  participantIds: const ['ama', 'kofi'],
);

void main() {
  final now = DateTime(2026, 11, 2, 9);

  test('today: all-day first, then by time, then title; moments excluded', () {
    final a = togetherAgenda(
      upcoming: [
        _i('late', now, startsAt: DateTime(2026, 11, 2, 19), title: 'Dinner'),
        _i('early', now, startsAt: DateTime(2026, 11, 2, 8), title: 'Gym'),
        _i('allday', now, title: 'Rent'),
        _i('m', now, kind: TogetherItemKind.moment),
      ],
      past: const [],
      now: now,
    );
    expect(a.today.map((i) => i.id), ['allday', 'early', 'late']);
  });

  test('this week groups the next six days that have something', () {
    final a = togetherAgenda(
      upcoming: [
        _i('tue', DateTime(2026, 11, 3)),
        _i('sun', DateTime(2026, 11, 8)),
        _i('next-mon', DateTime(2026, 11, 9)),
      ],
      past: const [],
      now: now,
    );
    expect(a.week.map((w) => w.day), [DateTime(2026, 11, 3), DateTime(2026, 11, 8)]);
    expect(a.comingUp.map((i) => i.id), ['next-mon']);
  });

  test('a multi-day trip shows every day this week but once in coming up', () {
    final trip = [
      for (var d = 7; d <= 11; d++) _i('trip', DateTime(2026, 11, d), title: 'Lisbon'),
    ];
    final a = togetherAgenda(upcoming: trip, past: const [], now: now);
    expect(a.week.map((w) => w.day), [DateTime(2026, 11, 7), DateTime(2026, 11, 8)]);
    expect(a.comingUp.where((i) => i.id == 'trip'), hasLength(1));
  });

  test('a timed item is grouped by the viewer\'s local day', () {
    // 23:30 tonight in a zone 6 hours behind is tomorrow morning here.
    final starts = DateTime(2026, 11, 3, 5, 30);
    final a = togetherAgenda(
      upcoming: [_i('call', DateTime(2026, 11, 2), startsAt: starts)],
      past: const [],
      now: now,
    );
    expect(a.today, isEmpty);
    expect(a.week.single.day, DateTime(2026, 11, 3));
  });

  test('recent moments: newest three from the past', () {
    final a = togetherAgenda(
      upcoming: const [],
      past: [
        for (var d = 1; d <= 5; d++)
          _i('m$d', DateTime(2026, 10, d), kind: TogetherItemKind.moment),
      ],
      now: now,
    );
    expect(a.recentMoments.map((i) => i.id), ['m5', 'm4', 'm3']);
    expect(a.isEmpty, isFalse);
  });

  test('ranges stay inside the 93-day server cap', () {
    final up = togetherUpcomingRange(now);
    final past = togetherPastRange(now);
    expect(up.start, DateTime(2026, 11, 2));
    expect(up.end.difference(up.start).inDays, lessThanOrEqualTo(93));
    expect(past.end, DateTime(2026, 11, 1));
    expect(past.end.difference(past.start).inDays, lessThanOrEqualTo(93));
  });
}
```

`test/features/together/couple_event_draft_from_item_test.dart`:

```dart
import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a weekly timed event round-trips into an editable draft', () {
    final item = TogetherItem.fromRow({
      'item_kind': 'event', 'item_id': 'e1', 'item_date': '2026-10-23',
      'starts_at': '2026-10-23T18:00:00+00:00', 'ends_at': '2026-10-23T20:00:00+00:00',
      'all_day': false, 'tz': 'Europe/London', 'title': 'Date night',
      'participant_ids': ['ama', 'kofi'], 'owner_id': 'ama', 'created_by': 'ama',
      'visibility': 'shared', 'status': 'confirmed',
      'source_ref': {
        'kind': 'event', 'note': 'Somewhere new', 'location_name': 'Osu',
        'event_starts_at': '2026-10-16T18:00:00+00:00',
        'event_ends_at': '2026-10-16T20:00:00+00:00',
        'rrule': 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR',
        'recurrence_until': '2026-12-31', 'remind_offsets_min': [60],
      },
    });
    final d = CoupleEventDraft.fromItem(item);
    expect(d.start, DateTime.utc(2026, 10, 16, 18).toLocal(), reason: 'the series start, not this occurrence');
    expect(d.end, DateTime.utc(2026, 10, 16, 20).toLocal());
    expect(d.timezone, 'Europe/London');
    expect(d.repeat, TogetherRepeat.weekly);
    expect(d.interval, 2);
    expect(d.weekdays, {DateTime.monday, DateTime.friday});
    expect(d.repeatUntil, DateTime(2026, 12, 31));
    expect(d.remindOffsetsMin, [60]);
    expect(d.ownerId, 'ama');
    expect(d.rrule, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
  });

  test('an all-day trip keeps its dates', () {
    final item = TogetherItem.fromRow({
      'item_kind': 'event', 'item_id': 'e2', 'item_date': '2026-11-08',
      'starts_at': null, 'ends_at': null, 'all_day': true, 'tz': null, 'title': 'Lisbon',
      'participant_ids': ['ama'], 'owner_id': null, 'created_by': 'ama',
      'visibility': 'private', 'status': 'confirmed',
      'source_ref': {'kind': 'trip', 'start_date': '2026-11-07', 'end_date': '2026-11-11', 'continuation': true},
    });
    final d = CoupleEventDraft.fromItem(item);
    expect(d.allDay, isTrue);
    expect(d.start, DateTime(2026, 11, 7));
    expect(d.end, DateTime(2026, 11, 11));
    expect(d.kind, 'trip');
    expect(d.visibility, TogetherVisibility.private);
    expect(d.repeat, TogetherRepeat.none);
  });
}
```

- [ ] **Step 2: Run them to verify they fail:** `flutter test test/features/together/together_agenda_test.dart test/features/together/couple_event_draft_from_item_test.dart` → undefined names.

- [ ] **Step 3: Implement**

`lib/features/together/domain/together_agenda.dart`:

```dart
import 'together_item.dart';

/// The Agenda's sections, built from what `list_together_items` returned.
class TogetherAgenda {
  const TogetherAgenda({
    required this.today,
    required this.week,
    required this.comingUp,
    required this.recentMoments,
  });

  final List<TogetherItem> today;

  /// The next six days that have something, in order.
  final List<({DateTime day, List<TogetherItem> items})> week;

  /// Further ahead, each item once (a trip appears on its first day only).
  final List<TogetherItem> comingUp;

  /// The newest three moments, newest first.
  final List<TogetherItem> recentMoments;

  bool get isEmpty =>
      today.isEmpty && week.isEmpty && comingUp.isEmpty && recentMoments.isEmpty;
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Today through 90 days ahead (inside the server's 93-day cap).
({DateTime start, DateTime end}) togetherUpcomingRange(DateTime now) {
  final today = _dayOf(now);
  return (start: today, end: DateTime(today.year, today.month, today.day + 90));
}

/// The 93 days before today, for recent moments.
({DateTime start, DateTime end}) togetherPastRange(DateTime now) {
  final today = _dayOf(now);
  return (
    start: DateTime(today.year, today.month, today.day - 93),
    end: DateTime(today.year, today.month, today.day - 1),
  );
}

/// All-day first, then by start time, then title.
int compareTogetherItems(TogetherItem a, TogetherItem b) {
  final day = a.day.compareTo(b.day);
  if (day != 0) return day;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final sa = a.startsAt, sb = b.startsAt;
  if (sa != null && sb != null) {
    final t = sa.compareTo(sb);
    if (t != 0) return t;
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

TogetherAgenda togetherAgenda({
  required List<TogetherItem> upcoming,
  required List<TogetherItem> past,
  required DateTime now,
}) {
  final today = _dayOf(now);
  final weekEnd = DateTime(today.year, today.month, today.day + 6);
  final plans =
      upcoming.where((i) => i.kind != TogetherItemKind.moment).toList()
        ..sort(compareTogetherItems);

  final week = <({DateTime day, List<TogetherItem> items})>[];
  for (var d = 1; d <= 6; d++) {
    final day = DateTime(today.year, today.month, today.day + d);
    final items = plans.where((i) => i.day == day).toList();
    if (items.isNotEmpty) week.add((day: day, items: items));
  }

  final seen = <String>{};
  final comingUp = [
    for (final i in plans)
      if (i.day.isAfter(weekEnd) && seen.add('${i.kind.name}:${i.id}')) i,
  ];

  final moments =
      [...past, ...upcoming]
          .where((i) => i.kind == TogetherItemKind.moment && !i.day.isAfter(today))
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));

  return TogetherAgenda(
    today: plans.where((i) => i.day == today).toList(),
    week: week,
    comingUp: comingUp,
    recentMoments: moments.take(3).toList(),
  );
}
```

In `couple_event_draft.dart`, add inside `CoupleEventDraft`, after the constructor:

```dart
  /// The editable definition behind a listed event (any occurrence of it):
  /// the series start, repeat rule and reminders from its source_ref.
  factory CoupleEventDraft.fromItem(TogetherItem item) {
    final ref = item.sourceRef;
    DateTime? day(Object? v) {
      if (v == null) return null;
      final p = DateTime.parse(v as String);
      return DateTime(p.year, p.month, p.day);
    }

    DateTime? instant(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();

    final rule = ref['rrule'] as String?;
    String? part(String key) =>
        rule == null ? null : RegExp('$key=([A-Z0-9,]+)').firstMatch(rule)?.group(1);
    final freq = part('FREQ');
    final byDay = part('BYDAY');

    return CoupleEventDraft(
      title: item.title,
      allDay: item.allDay,
      start:
          item.allDay
              ? (day(ref['start_date']) ?? item.date)
              : (instant(ref['event_starts_at']) ?? item.startsAt ?? item.date),
      end: item.allDay ? day(ref['end_date']) : instant(ref['event_ends_at']),
      timezone: item.tz,
      note: ref['note'] as String?,
      locationName: ref['location_name'] as String?,
      kind: ref['kind'] as String? ?? 'event',
      repeat: switch (freq) {
        'DAILY' => TogetherRepeat.daily,
        'WEEKLY' => TogetherRepeat.weekly,
        'MONTHLY' => TogetherRepeat.monthly,
        'YEARLY' => TogetherRepeat.yearly,
        _ => TogetherRepeat.none,
      },
      interval: int.tryParse(part('INTERVAL') ?? '') ?? 1,
      weekdays:
          byDay == null
              ? const {}
              : {for (final c in byDay.split(',')) _weekdayCodes.indexOf(c) + 1},
      repeatUntil: day(ref['recurrence_until']),
      participantIds: item.participantIds,
      ownerId: item.ownerId,
      visibility: item.visibility,
      remindOffsetsMin: [
        for (final o in (ref['remind_offsets_min'] as List? ?? const [])) (o as num).toInt(),
      ],
    );
  }
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 2: Providers for the screen

**Files:**
- Modify: `lib/features/together/presentation/together_providers.dart`
- Test: `test/features/together/together_providers_test.dart`

**Interfaces:**
- Produces:
  - `togetherMeProvider`: `Provider<String?>`, the signed-in user id;
  - `togetherPartnerIdProvider`: `FutureProvider<String?>`, the other member of the active relationship;
  - `togetherDeviceTimezoneProvider`: `FutureProvider<String>`, the IANA zone, falling back to `'UTC'`;
  - `togetherClockProvider`: `Provider<DateTime Function()>`, defaulting to `DateTime.now`;
  - `togetherAgendaProvider`: `FutureProvider.autoDispose.family<TogetherAgenda, String>`, keyed by relationship id.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _row(String id, String date, String kind) => {
  'item_kind': kind, 'item_id': id, 'item_date': date, 'starts_at': null, 'ends_at': null,
  'all_day': true, 'tz': null, 'title': id, 'participant_ids': ['ama'], 'owner_id': null,
  'created_by': 'ama', 'visibility': 'shared', 'status': 'confirmed', 'source_ref': {},
};

void main() {
  test('the agenda reads both ranges and groups them', () async {
    final g = FakeTogetherGateway({
      'list_together_items': (p) => p['p_start'] == '2026-11-02'
          ? [_row('rent', '2026-11-02', 'event')]
          : [_row('beach', '2026-10-20', 'moment')],
    });
    final c = ProviderContainer(overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      togetherClockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9)),
      togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
      planningChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
    ]);
    addTearDown(c.dispose);
    final agenda = await c.read(togetherAgendaProvider('r1').future);
    expect(agenda.today.single.id, 'rent');
    expect(agenda.recentMoments.single.id, 'beach');
    expect(g.calls.map((c) => c.$2['p_start']).toSet(), {'2026-11-02', '2026-08-01'});
  });
}
```

- [ ] **Step 2: Run it to verify it fails** (undefined names).

- [ ] **Step 3: Implement.** Append to `together_providers.dart` (add imports `package:attune/core/utils/timezone_utils.dart` and `../domain/together_agenda.dart`):

```dart
/// The signed-in user.
final togetherMeProvider = Provider<String?>(
  (ref) => Supabase.instance.client.auth.currentUser?.id,
);

/// The other member of the active relationship.
final togetherPartnerIdProvider = FutureProvider<String?>((ref) async {
  final me = ref.watch(togetherMeProvider);
  if (me == null) return null;
  final row =
      await Supabase.instance.client
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$me,user_b.eq.$me')
          .eq('status', 'active')
          .maybeSingle();
  if (row == null) return null;
  return (row['user_a'] == me ? row['user_b'] : row['user_a']) as String?;
});

/// The device's IANA zone, so a weekly 19:00 stays 19:00 across DST.
final togetherDeviceTimezoneProvider = FutureProvider<String>((ref) async {
  try {
    return await TimezoneUtils.getDeviceTimezone();
  } catch (_) {
    return 'UTC';
  }
});

/// "Now", overridable in tests.
final togetherClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The Agenda: the next 91 days of plans plus the last 93 days of moments.
final togetherAgendaProvider = FutureProvider.autoDispose
    .family<TogetherAgenda, String>((ref, relationshipId) async {
      final now = ref.watch(togetherClockProvider)();
      final up = togetherUpcomingRange(now);
      final past = togetherPastRange(now);
      final results = await Future.wait([
        ref.watch(togetherRangeProvider((
          relationshipId: relationshipId, start: up.start, end: up.end,
        )).future),
        ref.watch(togetherRangeProvider((
          relationshipId: relationshipId, start: past.start, end: past.end,
        )).future),
      ]);
      return togetherAgenda(upcoming: results[0], past: results[1], now: now);
    });
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass.

---

### Task 3: Section card and agenda row

**Files:**
- Create: `lib/features/together/presentation/widgets/together_section.dart`
- Create: `lib/features/together/presentation/widgets/together_item_row.dart`
- Test: `test/features/together/together_item_row_test.dart`

**Interfaces:**
- Produces:
  - `TogetherSection({required String title, required List<Widget> children})`;
  - `TogetherItemRow({required TogetherItem item, required String? me, required String partnerName, bool last = false, String? lead, VoidCallback? onTap})`. `lead` is an optional prefix such as "In 12 days".
  - `String togetherWhoLabel(TogetherWho who, String partnerName)`, returning `'You' | partnerName | 'Both of you'`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/widgets/together_item_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _event({
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String createdBy = 'ama',
  String title = 'Dinner',
  DateTime? startsAt,
}) => TogetherItem(
  kind: TogetherItemKind.event, id: 'e1', date: DateTime(2026, 11, 2),
  startsAt: startsAt ?? DateTime(2026, 11, 2, 19), endsAt: DateTime(2026, 11, 2, 21),
  allDay: false, title: title, participantIds: who, createdBy: createdBy, visibility: visibility,
);

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(ScreenUtilInit(
  designSize: const Size(375, 812),
  builder: (_, __) => MaterialApp(home: Scaffold(body: w)),
));

void main() {
  testWidgets('shows time and who, from my side', (t) async {
    var tapped = false;
    await _pump(t, TogetherItemRow(item: _event(), me: 'ama', partnerName: 'Kofi', onTap: () => tapped = true));
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.textContaining('Both of you'), findsOneWidget);
    expect(find.textContaining('7:00'), findsOneWidget);
    await t.tap(find.text('Dinner'));
    expect(tapped, isTrue);
  });

  testWidgets("the partner's own event names them", (t) async {
    await _pump(t, TogetherItemRow(item: _event(who: ['kofi'], createdBy: 'kofi'), me: 'ama', partnerName: 'Kofi'));
    expect(find.textContaining('Kofi'), findsOneWidget);
  });

  testWidgets('a lead line comes first', (t) async {
    await _pump(t, TogetherItemRow(item: _event(), me: 'ama', partnerName: 'Kofi', lead: 'In 12 days'));
    expect(find.textContaining('In 12 days'), findsOneWidget);
  });

  test('who labels', () {
    expect(togetherWhoLabel(TogetherWho.me, 'Kofi'), 'You');
    expect(togetherWhoLabel(TogetherWho.partner, 'Kofi'), 'Kofi');
    expect(togetherWhoLabel(TogetherWho.us, 'Kofi'), 'Both of you');
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement**

`together_section.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/card_inkwell.dart';
import 'package:flutter/material.dart';

/// A section title over one card of rows, as Planning's lists are laid out.
class TogetherSection extends StatelessWidget {
  const TogetherSection({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        Padding(
          padding: Spacing.allMd,
          child: CardInkWell(margin: EdgeInsets.zero, child: Column(children: children)),
        ),
      ],
    );
  }
}
```

`together_item_row.dart`:

```dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';

String togetherWhoLabel(TogetherWho who, String partnerName) => switch (who) {
  TogetherWho.me => 'You',
  TogetherWho.partner => partnerName,
  TogetherWho.us => 'Both of you',
};

/// One thing on the Agenda: what, when and whose, in the app's row style.
class TogetherItemRow extends StatelessWidget {
  const TogetherItemRow({
    super.key,
    required this.item,
    required this.me,
    required this.partnerName,
    this.last = false,
    this.lead,
    this.onTap,
  });

  final TogetherItem item;
  final String? me;
  final String partnerName;

  /// The last row in its card: no divider under it.
  final bool last;

  /// A leading phrase for the subtitle, e.g. "In 12 days".
  final String? lead;
  final VoidCallback? onTap;

  bool get _masked =>
      item.visibility == TogetherVisibility.busyOnly && item.createdBy != me;

  IconData get _icon {
    if (_masked) return Icons.do_not_disturb_on_outlined;
    switch (item.kind) {
      case TogetherItemKind.event:
        return switch (item.sourceRef['kind']) {
          'trip' => Icons.flight_takeoff_rounded,
          'big_day' => Icons.star_outline_rounded,
          _ => Icons.event_rounded,
        };
      case TogetherItemKind.reminder:
        return switch (item.sourceRef['reminder_type']) {
          'birthday' => Icons.cake_outlined,
          'anniversary' => Icons.favorite_border_rounded,
          _ => Icons.notifications_none_rounded,
        };
      case TogetherItemKind.planningDate:
        return Icons.checklist_rounded;
      case TogetherItemKind.planningItem:
        return item.sourceRef['is_complete'] == true
            ? Icons.check_box_outlined
            : Icons.check_box_outline_blank_rounded;
      case TogetherItemKind.moment:
        return Icons.auto_awesome_outlined;
    }
  }

  String get _when {
    final s = item.startsAt;
    if (item.allDay || s == null) {
      return switch (item.kind) {
        TogetherItemKind.reminder => 'Reminder',
        TogetherItemKind.planningDate => 'Plan',
        TogetherItemKind.planningItem => 'To-do',
        TogetherItemKind.moment => 'Moment',
        TogetherItemKind.event => 'All day',
      };
    }
    final e = item.endsAt;
    final t = DateFormat.jm();
    return e == null ? t.format(s) : '${t.format(s)} – ${t.format(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final who = me == null ? null : item.whoFor(me!);
    final whoColor = switch (who) {
      TogetherWho.me => colorScheme.tertiary,
      TogetherWho.partner => colorScheme.secondary,
      _ => colorScheme.primary,
    };
    final parts = [
      if (lead != null) lead!,
      _when,
      if (item.kind == TogetherItemKind.event && who != null && !_masked)
        togetherWhoLabel(who, partnerName),
    ];
    final done = item.kind == TogetherItemKind.planningItem && item.sourceRef['is_complete'] == true;
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
      icon: _icon,
      iconColor: whoColor,
      backgroundColor: whoColor.withValues(alpha: 0.12),
      title: item.title.isEmpty ? 'Untitled' : item.title,
      titleStyle: done
          ? Theme.of(context).textTheme.titleSmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            )
          : null,
      subtitle: parts.join(' · '),
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: !last,
      disableTrailing: true,
      onTap: _masked ? null : onTap,
    );
  }
}
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/together_item_row_test.dart` → pass.

---

### Task 4: The event editor sheet

**Files:**
- Create: `lib/features/together/presentation/widgets/couple_event_sheet.dart`
- Test: `test/features/together/couple_event_sheet_test.dart`

**Interfaces:**
- Consumes:
  - `CoupleEventDraft` (Task 1, Phase 1a);
  - `togetherRepositoryProvider`, `togetherMeProvider`, `togetherPartnerIdProvider`, `togetherDeviceTimezoneProvider` (Task 2);
  - `partnerNameProvider` (quiz providers, used by Phase 0).
- Produces: `Future<void> showCoupleEventSheet(BuildContext context, {required String relationshipId, TogetherItem? item})`. With no item it creates an event; with one it edits that event. It shows "Saved." or "Added." on the host screen when the sheet closes.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/couple_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Future<FakeTogetherGateway> _open(WidgetTester t, {TogetherItem? item}) async {
  final g = FakeTogetherGateway({
    'create_couple_event': (_) => 'ev-1',
    'update_couple_event': (_) => null,
    'delete_couple_event': (_) => null,
    'leave_couple_event': (_) => null,
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      togetherMeProvider.overrideWithValue('ama'),
      togetherPartnerIdProvider.overrideWith((ref) async => 'kofi'),
      togetherDeviceTimezoneProvider.overrideWith((ref) async => 'Africa/Accra'),
      quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
    ],
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCoupleEventSheet(context, relationshipId: 'r1', item: item),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return g;
}

TogetherItem _item({List<String> who = const ['ama', 'kofi'], String createdBy = 'ama',
    TogetherVisibility visibility = TogetherVisibility.shared}) =>
  TogetherItem.fromRow({
    'item_kind': 'event', 'item_id': 'e1', 'item_date': '2026-11-06',
    'starts_at': '2026-11-06T19:00:00+00:00', 'ends_at': null, 'all_day': false,
    'tz': 'Africa/Accra', 'title': 'Dinner', 'participant_ids': who, 'owner_id': null,
    'created_by': createdBy, 'visibility': visibility.wire, 'status': 'confirmed',
    'source_ref': {'kind': 'event', 'event_starts_at': '2026-11-06T19:00:00+00:00'},
  });

void main() {
  testWidgets('a new event for both of us is created and confirmed behind the sheet', (t) async {
    final g = await _open(t);
    expect(find.text('New event'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Dinner at Buka');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final payload = g.calls.single.$2['p_event'] as Map<String, dynamic>;
    expect(payload['title'], 'Dinner at Buka');
    expect(payload['participant_ids'], ['ama', 'kofi']);
    expect(payload['tz'], 'Africa/Accra');
    expect(find.text('New event'), findsNothing);
    expect(find.text('Added.'), findsOneWidget);
  });

  testWidgets('an empty title stays open with a plain message and sends nothing', (t) async {
    final g = await _open(t);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty);
    expect(find.text('Give it a title'), findsOneWidget);
    expect(find.text('New event'), findsOneWidget);
  });

  testWidgets('editing my event saves an update; delete asks first', (t) async {
    final g = await _open(t, item: _item());
    expect(find.text('Edit event'), findsOneWidget);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.single.$1, 'update_couple_event');
    expect(g.calls.single.$2['p_event_id'], 'e1');

    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Delete event'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Delete event'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Delete'));
    await t.pumpAndSettle();
    expect(g.calls.last.$1, 'delete_couple_event');
  });

  testWidgets("my partner's event that includes me can be left", (t) async {
    final g = await _open(t, item: _item(createdBy: 'kofi'));
    await t.scrollUntilVisible(find.text('Leave event'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Leave event'));
    await t.pumpAndSettle();
    expect(g.calls.single.$1, 'leave_couple_event');
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement** `couple_event_sheet.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/together_repository.dart';
import '../../domain/couple_event_draft.dart';
import '../../domain/together_item.dart';
import '../together_providers.dart';

/// Opens the event editor: empty to plan something, or with [item] to edit
/// it. The sheet closes with its confirmation, shown on the screen behind.
Future<void> showCoupleEventSheet(
  BuildContext context, {
  required String relationshipId,
  TogetherItem? item,
}) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: _CoupleEventSheet(relationshipId: relationshipId, item: item),
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

enum _Who { both, me, partner }

const _remindChoices = <int?, String>{
  null: 'No reminder',
  0: 'At the time',
  60: '1 hour before',
  1440: '1 day before',
};

const _repeatLabels = {
  TogetherRepeat.none: 'Does not repeat',
  TogetherRepeat.daily: 'Every day',
  TogetherRepeat.weekly: 'Every week',
  TogetherRepeat.monthly: 'Every month',
  TogetherRepeat.yearly: 'Every year',
};

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _errorCopy(String code) => switch (code) {
  'not_found' => 'This event is no longer here.',
  'owner_handoff' => 'Ask your partner to take it on instead.',
  'forbidden' => 'Only the person who made it can change who sees it.',
  _ => 'Could not save that. Please try again.',
};

class _CoupleEventSheet extends ConsumerStatefulWidget {
  const _CoupleEventSheet({required this.relationshipId, this.item});
  final String relationshipId;
  final TogetherItem? item;

  @override
  ConsumerState<_CoupleEventSheet> createState() => _CoupleEventSheetState();
}

class _CoupleEventSheetState extends ConsumerState<_CoupleEventSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _location = TextEditingController();
  late bool _allDay;
  late DateTime _start;
  DateTime? _end;
  TogetherRepeat _repeat = TogetherRepeat.none;
  Set<int> _weekdays = {};
  _Who _who = _Who.both;
  TogetherVisibility _visibility = TogetherVisibility.shared;
  int? _remind;
  String? _ownerId;
  String _kind = 'event';
  int _interval = 1;
  DateTime? _repeatUntil;
  bool _busy = false;

  bool get _editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item == null) {
      final now = DateTime.now();
      _allDay = false;
      _start = DateTime(now.year, now.month, now.day, now.hour + 1);
      _end = _start.add(const Duration(hours: 1));
      return;
    }
    final d = CoupleEventDraft.fromItem(item);
    _title.text = d.title;
    _note.text = d.note ?? '';
    _location.text = d.locationName ?? '';
    _allDay = d.allDay;
    _start = d.start;
    _end = d.end;
    _repeat = d.repeat;
    _weekdays = {...d.weekdays};
    _interval = d.interval;
    _repeatUntil = d.repeatUntil;
    _visibility = d.visibility;
    _remind = d.remindOffsetsMin.isEmpty ? null : d.remindOffsetsMin.first;
    _ownerId = d.ownerId;
    _kind = d.kind;
    final me = ref.read(togetherMeProvider);
    _who = d.participantIds.length > 1
        ? _Who.both
        : (d.participantIds.contains(me) ? _Who.me : _Who.partner);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _location.dispose();
    super.dispose();
  }

  List<String> _participants(String? me, String? partner) {
    if (_visibility != TogetherVisibility.shared) return [if (me != null) me];
    return switch (_who) {
      _Who.both => [if (me != null) me, if (partner != null) partner],
      _Who.me => [if (me != null) me],
      _Who.partner => [if (partner != null) partner],
    };
  }

  Future<void> _pick({required bool end}) {
    final initial = end ? (_end ?? _start.add(const Duration(hours: 1))) : _start;
    return showCupertinoDateTimeSheet(
      context: context,
      mode: _allDay ? CupertinoDatePickerMode.date : CupertinoDatePickerMode.dateAndTime,
      initialDateTime: initial,
      sheetHeight: 350.h,
      onChanged: (v) => setState(() {
        if (end) {
          _end = v;
        } else {
          final length = _end?.difference(_start);
          _start = v;
          if (length != null) _end = v.add(length);
        }
      }),
    );
  }

  Future<T?> _choose<T>(String title, Map<T, String> options) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries)
              ListTile(title: Text(e.value), onTap: () => Navigator.of(c).pop(e.key)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final me = ref.read(togetherMeProvider);
    final partner = await ref.read(togetherPartnerIdProvider.future);
    final tz = await ref.read(togetherDeviceTimezoneProvider.future);
    final draft = CoupleEventDraft(
      title: _title.text,
      allDay: _allDay,
      start: _allDay ? DateTime(_start.year, _start.month, _start.day) : _start,
      end: _end == null
          ? null
          : (_allDay ? DateTime(_end!.year, _end!.month, _end!.day) : _end),
      timezone: widget.item?.tz ?? tz,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      locationName: _location.text.trim().isEmpty ? null : _location.text.trim(),
      kind: _kind,
      repeat: _repeat,
      interval: _interval,
      weekdays: _repeat == TogetherRepeat.weekly ? _weekdays : const {},
      repeatUntil: _repeat == TogetherRepeat.none ? null : _repeatUntil,
      participantIds: _participants(me, partner),
      ownerId: _ownerId,
      visibility: _visibility,
      remindOffsetsMin: [if (_remind != null) _remind!],
    );
    final problem = draft.validate();
    if (problem != null) {
      context.showErrorSnackbar(problem);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(togetherRepositoryProvider);
    try {
      if (_editing) {
        await repo.updateEvent(widget.item!.id, draft);
      } else {
        await repo.createEvent(widget.relationshipId, draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(_editing ? 'Saved.' : 'Added.');
    } on TogetherException catch (e) {
      if (!mounted) return;
      context.showErrorSnackbar(_errorCopy(e.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not save that. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this event?'),
        content: const Text('It will be removed for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => ref.read(togetherRepositoryProvider).deleteEvent(widget.item!.id), 'Deleted.');
  }

  Future<void> _leave() => _run(
    () => ref.read(togetherRepositoryProvider).leaveEvent(widget.item!.id),
    'You left it.',
  );

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(done);
    } on TogetherException catch (e) {
      if (!mounted) return;
      context.showErrorSnackbar(_errorCopy(e.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not do that. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _format(DateTime d) =>
      _allDay ? DateFormat.yMMMEd().format(d) : DateFormat.yMMMEd().add_jm().format(d);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final me = ref.watch(togetherMeProvider);
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final item = widget.item;
    final mine = item == null || item.createdBy == me;
    final canDelete = item != null && (mine || item.visibility == TogetherVisibility.shared);
    final canLeave = item != null && !mine && item.participantIds.contains(me) &&
        item.participantIds.length > 1;
    final shared = _visibility == TogetherVisibility.shared;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          children: [
            BottomSheetHeader(
              title: _editing ? 'Edit event' : 'New event',
              actionLabel: 'Save',
              onPressed: _busy ? null : _save,
            ),
            AppTextFormField(
              controller: _title,
              label: 'Title',
              hintText: 'Dinner, a trip, the dentist…',
              autofocus: !_editing,
              textCapitalization: TextCapitalization.sentences,
            ),
            Gap(Spacing.sm),
            AppDivider(),
            InfoRowWidget(
              title: 'All day',
              subtitle: '',
              icon: Icons.wb_sunny_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: _allDay,
              onToggleChanged: (v) => setState(() => _allDay = v),
            ),
            AppDivider(),
            InfoRowWidget(
              title: _format(_start),
              subtitle: 'Starts',
              icon: Icons.schedule_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () => _pick(end: false),
            ),
            AppDivider(),
            InfoRowWidget(
              title: _end == null ? 'Add an end' : _format(_end!),
              subtitle: 'Ends',
              icon: Icons.schedule_outlined,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () => _pick(end: true),
            ),
            AppDivider(),
            InfoRowWidget(
              title: _repeatLabels[_repeat]!,
              subtitle: 'Repeats',
              icon: Icons.repeat_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () async {
                final r = await _choose('Repeats', _repeatLabels);
                if (r != null) {
                  setState(() {
                    _repeat = r;
                    if (r == TogetherRepeat.weekly && _weekdays.isEmpty) {
                      _weekdays = {_start.weekday};
                    }
                  });
                }
              },
            ),
            if (_repeat == TogetherRepeat.weekly)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                child: Wrap(
                  spacing: Spacing.xs,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(_weekdayShort[d - 1]),
                        selected: _weekdays.contains(d),
                        onSelected: (on) => setState(() {
                          on ? _weekdays.add(d) : _weekdays.remove(d);
                        }),
                      ),
                  ],
                ),
              ),
            AppDivider(),
            Padding(
              padding: EdgeInsets.fromLTRB(Spacing.md.w, Spacing.md, Spacing.md.w, 0),
              child: Text('Who it’s for', style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<_Who>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: _Who.both, label: Text('Both of us')),
                  const ButtonSegment(value: _Who.me, label: Text('Me')),
                  ButtonSegment(value: _Who.partner, label: Text(partnerName)),
                ],
                selected: {shared ? _who : _Who.me},
                onSelectionChanged: shared ? (s) => setState(() => _who = s.first) : null,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text('Who can see it', style: Theme.of(context).textTheme.labelLarge),
            ),
            Padding(
              padding: Spacing.allMd,
              child: SegmentedButton<TogetherVisibility>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TogetherVisibility.shared, label: Text('Both')),
                  ButtonSegment(value: TogetherVisibility.busyOnly, label: Text('Busy only')),
                  ButtonSegment(value: TogetherVisibility.private, label: Text('Just me')),
                ],
                selected: {_visibility},
                onSelectionChanged: mine ? (s) => setState(() => _visibility = s.first) : null,
              ),
            ),
            AppDivider(),
            InfoRowWidget(
              title: _remindChoices[_remind] ?? 'No reminder',
              subtitle: 'Remind',
              icon: Icons.notifications_none_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () async {
                final picked = await _choose('Remind', {
                  for (final e in _remindChoices.entries) (e.key ?? -1): e.value,
                });
                if (picked != null) setState(() => _remind = picked == -1 ? null : picked);
              },
            ),
            AppDivider(),
            AppTextFormField(controller: _location, label: 'Where (optional)', maxLength: 120),
            AppTextFormField(controller: _note, label: 'Note (optional)', maxLines: 3, maxLength: 500),
            if (canLeave) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Leave event',
                subtitle: '',
                icon: Icons.logout_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _busy ? null : _leave,
              ),
            ],
            if (canDelete) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Delete event',
                subtitle: '',
                icon: Icons.delete_outline_rounded,
                iconColor: colorScheme.error,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _busy ? null : _delete,
              ),
            ],
            Gap(Spacing.xl),
          ],
        ),
      ),
    );
  }
}
```

If `AppDivider`, `Gap`, `InfoRowWidget`, `AppTextFormField`, `showCupertinoDateTimeSheet`, `BottomSheetUtils` or `.neutral` are not re-exported by `export_screens.dart`, import them directly; the reminder sheet's imports show which paths work. `_title`'s first `TextField` is the title field, which the test's `find.byType(TextField).first` relies on.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/couple_event_sheet_test.dart` → pass. If the snackbar copy test is flaky, check that "Added." uses `showSuccessSnackbar` on the host context, as the reminder sheet does.

---

### Task 5: The Together screen

**Files:**
- Create: `lib/features/together/presentation/screens/together_screen.dart`
- Modify: `lib/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart` (add `AddChoice.event`)
- Test: `test/features/together/together_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4; `timeline_providers.currentRelationshipIdProvider`; `TimelineScreen`; `showReminderSheet`; `remindersListProvider`; `planningRoute`, `PlanningEntryScreen`; `PlanningEntriesSkeleton`.
- Produces:
  - `TogetherScreen({super.key, this.embedded = false})`. When `embedded` is true it renders no AppBar, for use inside Planning's tab.
  - `enum AddChoice { event, moment, reminder }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart' as timeline;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/screens/together_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _row(String id, String date, {String kind = 'event', String? startsAt, String title = ''}) => {
  'item_kind': kind, 'item_id': id, 'item_date': date, 'starts_at': startsAt, 'ends_at': null,
  'all_day': startsAt == null, 'tz': startsAt == null ? null : 'UTC',
  'title': title.isEmpty ? id : title, 'participant_ids': ['ama', 'kofi'], 'owner_id': null,
  'created_by': 'ama', 'visibility': 'shared', 'status': 'confirmed', 'source_ref': {'kind': 'event'},
};

Future<void> _pump(WidgetTester t, {List<Map<String, dynamic>> upcoming = const [], List<Map<String, dynamic>> past = const []}) async {
  final g = FakeTogetherGateway({
    'list_together_items': (p) => p['p_start'] == '2026-11-02' ? upcoming : past,
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
      togetherClockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9)),
      togetherMeProvider.overrideWithValue('ama'),
      togetherPartnerIdProvider.overrideWith((ref) async => 'kofi'),
      togetherDeviceTimezoneProvider.overrideWith((ref) async => 'UTC'),
      quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      timeline.currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
      timeline.togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
      planningChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => const MaterialApp(home: TogetherScreen()),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sections: today, this week, coming up, our story', (t) async {
    await _pump(t, upcoming: [
      _row('rent', '2026-11-02', title: 'Rent'),
      _row('gym', '2026-11-04', title: 'Gym'),
      _row('lisbon', '2026-11-20', title: 'Lisbon'),
    ], past: [
      _row('beach', '2026-10-20', kind: 'moment', title: 'Beach day'),
    ]);
    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Beach day'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.textContaining('In 18 days'), findsOneWidget);
    expect(find.text('Our story'), findsOneWidget);
  });

  testWidgets('an empty today says so, quietly', (t) async {
    await _pump(t, upcoming: [_row('gym', '2026-11-04', title: 'Gym')]);
    expect(find.text('Nothing planned today.'), findsOneWidget);
  });

  testWidgets('a new couple sees three ways to start', (t) async {
    await _pump(t);
    expect(find.text('Your life together starts here'), findsOneWidget);
    expect(find.text('Add your anniversary'), findsOneWidget);
    expect(find.text('Add a birthday'), findsOneWidget);
    expect(find.text('Plan something together'), findsOneWidget);
  });

  testWidgets('tapping an event opens its editor', (t) async {
    await _pump(t, upcoming: [_row('rent', '2026-11-02', title: 'Rent')]);
    await t.tap(find.text('Rent'));
    await t.pumpAndSettle();
    expect(find.text('Edit event'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement**

In `add_moment_or_reminder_sheet.dart`:
- change the enum to `enum AddChoice { event, moment, reminder }`;
- add a first row before "Log a moment", using the existing rows' style:

```dart
                InfoRowWidget(
                  title: 'Plan something together',
                  subtitle: 'A date, a trip, anything with a time',
                  icon: Icons.event_rounded,
                  showAvatar: false,
                  showDivider: false,
                  showTrailingArrow: false,
                  trailing: Icon(
                    Icons.add,
                    size: 25.h,
                    color: colorScheme.onBackground.withOpacity(.5),
                  ),
                  onTap: () => Navigator.of(context).pop(AddChoice.event),
                ),
                AppDivider(),
```

Update the class doc to "one FAB, three flows". `TimelineScreen`'s switch must handle `AddChoice.event`; Task 7 does it. Until then, add a minimal case so the code compiles:

```dart
                case AddChoice.event:
                  if (!context.mounted) return;
                  await showCoupleEventSheet(context, relationshipId: relationshipId);
```

That requires `relationshipId` in scope; it is, inside `relationshipIdAsync.when(data: (relationshipId) {…})`. Also add the import `package:attune/features/together/presentation/widgets/couple_event_sheet.dart`.

`together_screen.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart' show planningRoute;
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/planning_skeletons.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:attune/features/timeline/presentation/screens/timeline_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/add_moment_or_reminder_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_agenda.dart';
import '../../domain/together_item.dart';
import '../together_providers.dart';
import '../widgets/couple_event_sheet.dart';
import '../widgets/together_item_row.dart';
import '../widgets/together_section.dart';

enum _View { agenda, month }

/// The couple's life hub: what's on today and this week, what's coming,
/// and the story so far. The Month view is the calendar (TimelineScreen).
class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key, this.embedded = false});

  /// Inside another screen's tab: no app bar of its own.
  final bool embedded;

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  _View _view = _View.agenda;

  Future<void> _add(String relationshipId) async {
    final choice = await AddMomentOrReminderSheet.show(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case AddChoice.event:
        await showCoupleEventSheet(context, relationshipId: relationshipId);
      case AddChoice.moment:
        await context.pushNamed('logMomentType');
      case AddChoice.reminder:
        await showReminderSheet(context);
    }
  }

  void _open(TogetherItem item, String relationshipId) {
    switch (item.kind) {
      case TogetherItemKind.event:
        showCoupleEventSheet(context, relationshipId: relationshipId, item: item);
      case TogetherItemKind.planningDate:
      case TogetherItemKind.planningItem:
        final entryId = item.sourceRef['entry_id'] as String?;
        if (entryId == null) return;
        Navigator.of(context).push(planningRoute(
          PlanningEntryScreen(relationshipId: relationshipId, entryId: entryId),
        ));
      case TogetherItemKind.reminder:
        final reminders =
            ref.read(reminders_providers.remindersListProvider).valueOrNull ?? const [];
        for (final r in reminders) {
          if (r.id == item.id) {
            showReminderSheet(context, reminder: r);
            return;
          }
        }
      case TogetherItemKind.moment:
        setState(() => _view = _View.month);
    }
  }

  String _dayLabel(DateTime day, DateTime today) {
    final diff = day.difference(today).inDays;
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEEE d MMM').format(day);
  }

  List<Widget> _rows(List<TogetherItem> items, String relationshipId, String? me,
      String partnerName, {String? Function(TogetherItem)? lead}) => [
    for (var i = 0; i < items.length; i++)
      TogetherItemRow(
        item: items[i],
        me: me,
        partnerName: partnerName,
        last: i == items.length - 1,
        lead: lead?.call(items[i]),
        onTap: () => _open(items[i], relationshipId),
      ),
  ];

  Widget _agenda(String relationshipId) {
    final me = ref.watch(togetherMeProvider);
    final partnerName =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final now = ref.watch(togetherClockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    return ref.watch(togetherAgendaProvider(relationshipId)).when(
      skipLoadingOnReload: true,
      loading: () => const PlanningEntriesSkeleton(label: 'Loading your plans'),
      error: (e, _) => Center(
        child: ErrorStateWidget(
          title: 'Could not load your plans',
          subtitle: 'Pull down to try again.',
        ),
      ),
      data: (agenda) => RefreshIndicator(
        onRefresh: () => ref.refresh(togetherAgendaProvider(relationshipId).future),
        child: ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl * 2),
          children: agenda.isEmpty
              ? [_EmptyTogether(onPlan: () => showCoupleEventSheet(context, relationshipId: relationshipId))]
              : [
                  TogetherSection(
                    title: 'Today',
                    children: agenda.today.isEmpty
                        ? [
                            Padding(
                              padding: const EdgeInsets.all(Spacing.md),
                              child: Text(
                                'Nothing planned today.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ]
                        : _rows(agenda.today, relationshipId, me, partnerName),
                  ),
                  if (agenda.week.isNotEmpty)
                    TogetherSection(
                      title: 'This week',
                      children: [
                        for (final w in agenda.week)
                          ..._rows(w.items, relationshipId, me, partnerName,
                              lead: (_) => _dayLabel(w.day, today)),
                      ],
                    ),
                  if (agenda.comingUp.isNotEmpty)
                    TogetherSection(
                      title: 'Coming up',
                      children: _rows(agenda.comingUp, relationshipId, me, partnerName,
                          lead: (i) => 'In ${i.day.difference(today).inDays} days'),
                    ),
                  if (agenda.recentMoments.isNotEmpty)
                    TogetherSection(
                      title: 'Our story',
                      children: [
                        ..._rows(agenda.recentMoments, relationshipId, me, partnerName,
                            lead: (i) => DateFormat.MMMd().format(i.day)),
                        InfoRowWidget(
                          title: 'All memories',
                          subtitle: '',
                          icon: Icons.photo_album_outlined,
                          showAvatar: false,
                          showDivider: false,
                          showTrailingArrow: true,
                          onTap: () => setState(() => _view = _View.month),
                        ),
                      ],
                    ),
                ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relationshipId =
        ref.watch(timeline_providers.currentRelationshipIdProvider).valueOrNull;
    final toggle = Padding(
      padding: EdgeInsets.fromLTRB(Spacing.md.w, Spacing.sm, Spacing.md.w, 0),
      child: SegmentedButton<_View>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: _View.agenda, label: Text('Agenda'), icon: Icon(Icons.view_agenda_outlined)),
          ButtonSegment(value: _View.month, label: Text('Month'), icon: Icon(Icons.calendar_month_outlined)),
        ],
        selected: {_view},
        onSelectionChanged: (s) => setState(() => _view = s.first),
      ),
    );
    final body = relationshipId == null
        ? const PlanningEntriesSkeleton(label: 'Loading your plans')
        : Column(
            children: [
              toggle,
              Expanded(
                child: _view == _View.agenda
                    ? _agenda(relationshipId)
                    : const TimelineScreen(showAppBar: true, showOwnAppBar: false),
              ),
            ],
          );
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Together'),
              actions: [
                AppIconButton(
                  icon: Icons.people_outline,
                  tooltip: 'Family',
                  onPressed: () => context.pushNamed('familyMembers'),
                ),
              ],
            ),
      floatingActionButton: relationshipId == null || _view == _View.month
          ? null
          : AppFab(
              heroTag: 'together-add',
              icon: Icons.add_rounded,
              onPressed: () => _add(relationshipId),
            ),
      body: body,
    );
  }
}

/// A brand-new couple: three easy ways in.
class _EmptyTogether extends StatelessWidget {
  const _EmptyTogether({required this.onPlan});
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Gap(Spacing.xl),
        const EmptyStateWidget(
          type: EmptyStateType.custom,
          icon: Icons.favorite_outline_rounded,
          title: 'Your life together starts here',
          subtitle: 'Add the dates that matter, then plan something.',
          compact: false,
        ),
        TogetherSection(
          title: 'Start with',
          children: [
            InfoRowWidget(
              title: 'Add your anniversary',
              subtitle: '',
              icon: Icons.favorite_border_rounded,
              showAvatar: false,
              showTrailingArrow: true,
              onTap: () => showReminderSheet(context),
            ),
            InfoRowWidget(
              title: 'Add a birthday',
              subtitle: '',
              icon: Icons.cake_outlined,
              showAvatar: false,
              showTrailingArrow: true,
              onTap: () => showReminderSheet(context),
            ),
            InfoRowWidget(
              title: 'Plan something together',
              subtitle: '',
              icon: Icons.event_rounded,
              showAvatar: false,
              showDivider: false,
              showTrailingArrow: true,
              onTap: onPlan,
            ),
          ],
        ),
      ],
    );
  }
}
```

Check `ErrorStateWidget`'s required params in `export_screens` (TimelineScreen uses `ErrorStateWidget(title: '', subtitle: '…')`) and `AppIconButton` (TimelineScreen uses it with `icon`, `tooltip`, `onPressed`). The "Together" text appears in the AppBar title; in the test, the Month segment label is "Month" and doesn't clash.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/` → pass. Then run `flutter test test/features/timeline/` → pass, which confirms the `AddChoice.event` case compiles.

---

### Task 6: Routes and notification taps

**Files:**
- Modify: `lib/app/routing/app_router.dart` (`RouteNames` and the `/timeline` route)
- Modify: `lib/core/notifications/config/notification_config.dart` (the `together_event` case)
- Modify: `test/core/notifications/together_event_route_test.dart`
- Create: `test/features/together/together_routes_test.dart`

- [ ] **Step 1: Write the failing tests.**

Change the expectation in `together_event_route_test.dart` from `RouteNames.timeline` to `RouteNames.together`.

`together_routes_test.dart`:

```dart
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// /together is the hub's home; /timeline stays as an alias for old links
/// and notifications, building the same screen (plan ruling R7).
void main() {
  test('route names', () {
    expect(RouteNames.together, '/together');
    expect(RouteNames.timeline, '/timeline');
  });

  test('both paths build the Together screen', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    for (final name in ["name: 'together'", "name: 'timeline'"]) {
      final at = src.indexOf(name);
      expect(at, isNot(-1), reason: name);
      expect(src.substring(at, src.indexOf('),', at)), contains('TogetherScreen()'), reason: name);
    }
  });
}
```

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Implement.**
  - In `RouteNames`, next to `timeline`, add `static const String together = '/together';`.
  - Replace the `/timeline` GoRoute builder with `const TogetherScreen()`.
  - Add a sibling route:

```dart
      GoRoute(
        path: RouteNames.together,
        name: 'together',
        builder: (context, state) => const TogetherScreen(),
      ),
```

  - Import `together_screen.dart`. Remove the `TimelineScreen` import only if nothing else in the router uses it.
  - In `notification_config.dart`, change the `together_event` case to `GoRouter.of(context).go(RouteNames.together);`.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/together_routes_test.dart test/core/notifications/` → pass.

---

### Task 7: Month view shows Together events; Planning's Calendar tab embeds Together

**Files:**
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart`
- Modify: `lib/features/planning/presentation/screens/planning_home_screen.dart`
- Modify: `test/features/planning/support/planning_test_app.dart`
- Test: `test/features/together/timeline_together_events_test.dart`

**Interfaces:**
- Consumes: `togetherRangeProvider`, `showCoupleEventSheet`, `TogetherItem`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the day sheet lists a Together event by its title', (t) async {
    final item = TogetherItem(
      kind: TogetherItemKind.event, id: 'e1', date: DateTime(2026, 11, 6),
      allDay: true, title: 'Dinner at Buka', participantIds: const ['ama', 'kofi'],
    );
    await t.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: CalendarDaySheet(
              relationshipId: null,
              date: DateTime(2026, 11, 6),
              events: const [],
              reminders: const [],
              planningEntries: [item],
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Dinner at Buka'), findsOneWidget);
  });

  test('Planning\'s Calendar tab is the Together screen and the Map placeholder is gone', () {
    final src = File('lib/features/planning/presentation/screens/planning_home_screen.dart').readAsStringSync();
    expect(src, contains('TogetherScreen(embedded: true)'));
    expect(src, isNot(contains("label: 'Map'")));
  });
}
```

Add `import 'dart:io';` at the top.

- [ ] **Step 2: Run it to verify it fails.** The day sheet renders "Scheduled item"; the source test fails.

- [ ] **Step 3: Implement.**

`calendar_day_sheet.dart` `_ScheduledTile`:
- add `TogetherItem(:final title) => title,` to `_title`;
- add this case to `_onTap`, before `_ => null` (import `together_item.dart` and `couple_event_sheet.dart`):

```dart
    TogetherItem item when relationshipId != null && item.kind == TogetherItemKind.event => () {
      final navigator = Navigator.of(context);
      final host = navigator.context;
      navigator.pop();
      showCoupleEventSheet(host, relationshipId: relationshipId!, item: item);
    },
```

`timeline_screen.dart`:
- Inside `build`, after `planningEntriesAsync`, watch this month's Together events:

```dart
    final togetherEventsAsync =
        relationshipIdAsync.valueOrNull == null
            ? const AsyncValue<List<TogetherItem>>.data([])
            : ref.watch(
              togetherRangeProvider((
                relationshipId: relationshipIdAsync.valueOrNull!,
                start: DateTime(_focusedMonth.year, _focusedMonth.month, 1),
                end: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0),
              )),
            );
```

- Replace `_planningEntriesByDate` with a `_scheduledByDate(List<PlanningCalendarEntry> entries, List<TogetherItem> together)` that returns `Map<DateTime, List<Object>>`. It groups the Planning entries as before, then adds every `together` item with `kind == TogetherItemKind.event`, keyed by `item.day`.
- Update the three call sites to pass `togetherEventsAsync.valueOrNull ?? const []`. These are the two `planningEntriesByDate:` arguments and the day sheet's `planningEntries:`.
- **Leave `PlanningDaySection` alone.** It filters `PlanningCalendarEntry` from `planningEntriesAsync` directly.
- **Imports:** `together_item.dart` and `together_providers.dart`.

`planning_home_screen.dart`:
- In the `TabsWithContent` `tabs`, replace the Calendar item's `content:` with `TogetherScreen(embedded: true)`. The tab keeps the `const AppTabItem(label: 'Calendar', icon: Icons.calendar_month_rounded, …)` label and icon.
- Delete the Map `AppTabItem`.
- Import `together_screen.dart`, and remove the `timeline_screen.dart` import if it is now unused.

`planning_test_app.dart`: add these overrides to `planningOverrides`, with imports for the together providers and repository:

```dart
      // The Calendar tab is now the Together screen (Phase 1b R1).
      togetherRepositoryProvider.overrideWithValue(
        TogetherRepository(_EmptyTogetherGateway()),
      ),
      timeline_providers.togetherChangeSignalProvider.overrideWith(
        (ref, relationshipId) => const Stream<void>.empty(),
      ),
      togetherMeProvider.overrideWithValue(userId),
      togetherPartnerIdProvider.overrideWith((ref) async => null),
```

and at the bottom of the file:

```dart
class _EmptyTogetherGateway implements TogetherRpcGateway {
  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async => const [];
}
```

- [ ] **Step 4: Run tests**: `flutter test test/features/together/ test/features/timeline/ test/features/planning/` → all pass except the known `planning_home_screen_test` tab-height failure. If that test's expected tab count changes ("Tab 2 of 3" becomes "of 2"), confirm it still fails only on the pre-existing 41.4-tall tab target, then ledger it.

---

### Task 8: Conversations card — the Together row

**Files:**
- Modify: `lib/features/chat/presentation/screens/conversations_screen.dart` (`_NextCalendarEventRow`, lines ~457–526)
- Test: `test/features/together/together_conversations_row_test.dart`

- [ ] **Step 1: Write the failing test** as a source guard plus pure logic:

```dart
import 'dart:io';

import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Conversations card opens Together, not the old timeline', () {
    final src = File('lib/features/chat/presentation/screens/conversations_screen.dart').readAsStringSync();
    expect(src, contains("pushNamed('together')"));
    expect(src, isNot(contains('class _NextCalendarEventRow')));
  });

  test('nextTogetherItem picks the soonest upcoming plan, skipping past times and moments', () {
    final now = DateTime(2026, 11, 2, 12);
    TogetherItem i(String id, DateTime day, {DateTime? at, TogetherItemKind kind = TogetherItemKind.event}) =>
        TogetherItem(kind: kind, id: id, date: day, startsAt: at, allDay: at == null, title: id, participantIds: const ['a']);
    final next = nextTogetherItem([
      i('earlier', DateTime(2026, 11, 2), at: DateTime(2026, 11, 2, 9)),
      i('moment', DateTime(2026, 11, 2), kind: TogetherItemKind.moment),
      i('tonight', DateTime(2026, 11, 2), at: DateTime(2026, 11, 2, 19)),
      i('friday', DateTime(2026, 11, 6)),
    ], now);
    expect(next?.id, 'tonight');
  });
}
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: Implement.**

In `together_agenda.dart`, add:

```dart
/// The soonest plan that hasn't started yet (all-day items count for their
/// whole day). Moments are memories, not plans.
TogetherItem? nextTogetherItem(List<TogetherItem> items, DateTime now) {
  final today = _dayOf(now);
  final upcoming = items.where((i) {
    if (i.kind == TogetherItemKind.moment) return false;
    if (i.day.isBefore(today)) return false;
    final s = i.startsAt;
    return i.allDay || s == null || !s.isBefore(now);
  }).toList()
    ..sort(compareTogetherItems);
  return upcoming.isEmpty ? null : upcoming.first;
}
```

In `conversations_screen.dart`, replace the whole `_NextCalendarEventRow` class with `_TogetherRow`, and change the usage at line ~184 from `const _NextCalendarEventRow()` to `const _TogetherRow()`:

```dart
/// The next thing on Together, with a way in.
class _TogetherRow extends ConsumerWidget {
  const _TogetherRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final relationshipId =
        ref.watch(timeline_providers.currentRelationshipIdProvider).valueOrNull;
    final now = DateTime.now();
    final range = togetherUpcomingRange(now);
    final items = relationshipId == null
        ? const <TogetherItem>[]
        : ref.watch(togetherRangeProvider((
              relationshipId: relationshipId, start: range.start, end: range.end,
            ))).valueOrNull ?? const <TogetherItem>[];
    final next = nextTogetherItem(items, now);
    String title = 'Nothing planned yet';
    if (next != null) {
      final days = next.day.difference(DateTime(now.year, now.month, now.day)).inDays;
      final when = days == 0 ? 'today' : days == 1 ? 'tomorrow' : 'in $days days';
      final s = next.startsAt;
      title = s == null || next.allDay
          ? '${next.title} $when'
          : '${next.title} $when, ${DateFormat.jm().format(s)}';
    }
    return InfoRowWidget(
      title: title,
      subtitle: 'Together',
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      icon: Icons.calendar_month,
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: () => context.pushNamed('together'),
    );
  }
}
```

Imports:
- `together_agenda.dart`, `together_item.dart` and `together_providers.dart` (for `togetherRangeProvider`);
- `timeline_providers.dart as timeline_providers`, if not already imported under another alias;
- `intl` if missing.

Remove `ReminderModel` and `remindersListProvider` imports only if no other code in the file uses them. Then run `grep -rln "ConversationsScreen(" test` and add to each test that pumps it the same four overrides Task 7 added to `planningOverrides`: the empty together gateway, the together signal, me and partner. Also add `planningChangeSignalProvider` empty if that test doesn't already have it.

- [ ] **Step 4: Run tests**: `flutter test test/features/together/ test/features/chat/ test/features/stories/` → pass.

---

### Task 9: Close out

- [ ] **Step 1:** In spec §8, add "Phase 1b rulings" with R1–R7 one line each.
- [ ] **Step 2:** Run the full suite with `flutter test`. Expected: only the known planning failure.
- [ ] **Step 3:** Run `flutter analyze lib/features/together lib/features/timeline lib/features/planning/presentation/screens/planning_home_screen.dart lib/features/chat/presentation/screens/conversations_screen.dart lib/app/routing/app_router.dart` → no new errors or warnings.
- [ ] **Step 4:** Render golden previews of the Agenda (populated and empty) and the editor sheet in a throwaway test, look at them, then delete the test file. This is the owner's design bar; check spacing against Planning's category screen.
- [ ] **Step 5:** Report:
  - Manual checks on two devices:
    - create a shared event on phone A; it appears on B live;
    - a busy-only event shows "Busy" on B;
    - leave an event on B;
    - the alarm arrives.
  - The PostHog follow-up plan (R6) needs the owner's project key and host.
