# Together Phase 8d: copy our plans into my phone's calendar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opted-in phone keeps a calendar of its own, called "Plans". It holds the shared plans this person is in for the next 60 days, with titles, times and places. It is refreshed whenever Together opens, and deleted on "off", on quick exit and on sign-out.

**Architecture:**
- Pure Dart decides what belongs in the copy (`mirrorEventsFor`) and what to change (`mirrorChanges`). Events are matched by a fingerprint, so no per-event bookkeeping is stored.
- A `MirrorCalendar` seam wraps `device_calendar_plus` (already in the app since Phase 6). Its write permissions are already declared.
- `TogetherMirror` syncs and clears; it never throws. The only thing stored is the calendar's id, in SharedPreferences.
- The busy overlay (Phase 6) skips this calendar when reading busy times, so plans are never uploaded back as busy blocks.
- `clearTogetherDeviceSurfaces()` (from 8c) gains the calendar delete.

**Tech Stack:** Flutter 3.29 / Riverpod 2, `device_calendar_plus` 0.8.1, SharedPreferences. No native code.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md`. Phase 8 row in §8 ("optional mirror into an on-device calendar"); §3 hard rules; §6.4 External calendars; §8.9 (Phase 6 overlay) and §8.11–§8.13 rulings.

**Prerequisite:** Phase 8c is implemented. This plan extends its `lib/features/together/data/together_device_surfaces.dart`.

## Global Constraints

- The owner's Phase 8 rule: **off by default, opt-in per phone; discreet.**
  - No partner name and no app-revealing wording on OS surfaces: the calendar is called "Plans".
  - Quick exit, sign-out and "off" clear it at once, which here means deleting the whole calendar.
- Spec §3: private or surprise events are visible only to their creator, and `busy_only` blocks are masked. Only `shared` events are copied (ruling R2).
- Spec §6.4: Supabase stays the single source of truth. The copy is one-way; edits made in the phone calendar are overwritten on the next sync.
- Spec §8.9 R4: the overlay uploads busy times from the phone's calendars. It must not upload this copy.
- Permissions are already declared: Android `READ_CALENDAR` and `WRITE_CALENDAR` (Phase 6), and iOS `NSCalendarsFullAccessUsageDescription`. That iOS purpose string must now mention the copy (App Review).
- Owner rules: work on main, write each test first and watch it fail, make no commits. Re-read a file before editing it, because the owner edits by hand.

### Rulings (record them in spec §8.14 in Task 5)

- **R1: one-way copy into a calendar of its own,** named "Plans", with no app name and no partner name. It is created on this phone's own ("local") account where one exists, which is always the case on Android and on iPhones without iCloud calendars. Otherwise iOS's default is used, and the setting says it may appear on the person's other devices. *Cost if wrong:* refuse instead of falling back.
- **R2: what is copied.**
  - Included: confirmed `shared` events I'm in, for the next 60 days, each repeat as its own entry. Title, times, all-day dates and place.
  - Never copied: notes, names, private or busy-only items, suggestions (`proposed`), reminders, moments or Planning items.
  - *Cost if wrong:* widening the filter later.
- **R3: matching.** Entries are matched by a fingerprint of title, times (for all-day events, the first and last day) and place. A changed plan is removed and re-added. Entries before today are left alone as history, and everything goes when the copy is turned off. *Cost if wrong:* a churned entry on phones that report all-day ends unusually. That is covered by the device check.
- **R4: when it refreshes.** Once each time Together opens, and straight away when it is turned on. *Cost if wrong:* a sync after each save.
- **R5: clearing.** "Off", quick exit and sign-out delete the whole calendar. Sign-out does so before stored settings are wiped, because the calendar id is one of them. *Cost if wrong:* an orphan "Plans" calendar the person deletes by hand.
- **R6: the overlay never reads the copy.** The busy overlay skips this calendar, because Together already counts its own plans as busy (§8.9 R3).

## Review Focus

1. **Opening Together twice with nothing changed** leaves the calendar untouched: no duplicates and no delete-and-re-add. Pinned by the Task 2 test "a second sync with nothing changed changes nothing".
2. **The person deletes the "Plans" calendar in their calendar app.** The next sync makes a new one, and nothing throws. Pinned by the Task 2 test "a deleted calendar is made again".
3. **Calendar access denied or revoked.** The switch stays off and the person is told how to allow access; a revoked sync does nothing. Pinned by the Task 2 notifier test and the Task 4 settings test.
4. **A trip's last day moves, or a plan is renamed.** The old entry goes and the new one comes. Pinned by the Task 1 tests (fingerprint and changes) and the Task 2 rename test.
5. **Quick exit or sign-out with the copy on.** The calendar is deleted, together with the widget and the lock-screen plan. Pinned by the Task 2 test of `clearTogetherDeviceSurfaces`. The ordering in logout is reviewed by reading the code: no test is practical there.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `lib/features/together/domain/together_mirror.dart` | Create | `MirrorEvent`, `DeviceMirrorEvent`, `mirrorFingerprint`, `allDayLastDay`, `mirrorEventsFor`, `mirrorChanges`, `mirrorDays` |
| `lib/features/together/data/together_calendar_mirror.dart` | Create | `MirrorCalendar` seam, `DeviceCalendarPlusMirror`, `TogetherMirror` (sync, clear, calendarId, ensureAccess), keys |
| `lib/features/together/data/together_device_surfaces.dart` | Modify | Also `TogetherMirror.clear()` |
| `lib/features/together/domain/together_overlay.dart` | Modify | `DeviceBusy.calendarId` (optional) |
| `lib/features/together/data/device_busy_source.dart` | Modify | Pass `calendarId` through |
| `lib/features/together/presentation/together_providers.dart` | Modify | `syncBusyTimes` skips the copy; `TogetherMirrorEnabled` and its provider |
| `lib/features/together/presentation/widgets/together_settings_sheet.dart` | Modify | "Copy our plans to my phone's calendar" toggle |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | Once-per-visit sync, and sync on turning it on |
| `lib/features/auth/presentation/widgets/logout_action.dart` | Modify (shared) | Clear the surfaces before `clearUserData()`; invalidate the mirror opt-in |
| `ios/Runner/Info.plist` | Modify | Calendar purpose strings mention the copy |
| Tests | Create/modify | `together_mirror_test.dart`, `together_calendar_mirror_test.dart`, `busy_sync_test.dart`, `together_mirror_settings_test.dart`, `together_screen_test.dart` |

**Regression risk to flag:**
- `logout_action.dart` (shared): the device clear moves from after `clearUserData()` to before it. It never throws, so sign-out can't fail because of it.
- The busy overlay: `DeviceBusy` gains an optional field, and the filter is a no-op unless the copy exists.

---

### Task 1: What belongs in the copy, and what to change (pure Dart)

**Files:**
- Create: `lib/features/together/domain/together_mirror.dart`
- Test: `test/features/together/together_mirror_test.dart`

**Interfaces:**
- Consumes: `TogetherItem`, `TogetherItemKind`, `TogetherVisibility`.
- Produces:
  - `const mirrorDays = 60`;
  - `String mirrorFingerprint({required String title, required DateTime start, required DateTime end, required bool allDay, String? location})`;
  - `DateTime allDayLastDay(DateTime start, DateTime end)`;
  - `class MirrorEvent { title, start, end, allDay, location; String get fingerprint; }`;
  - `class DeviceMirrorEvent { String id; DateTime start; String fingerprint; }`;
  - `List<MirrorEvent> mirrorEventsFor({required List<TogetherItem> items, required String? me})`;
  - `({List<MirrorEvent> create, List<String> delete}) mirrorChanges(List<MirrorEvent> desired, List<DeviceMirrorEvent> existing)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _e(
  String title, {
  DateTime? start,
  DateTime? end,
  DateTime? day,
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String status = 'confirmed',
  TogetherItemKind kind = TogetherItemKind.event,
  Map<String, dynamic> ref = const {},
}) => TogetherItem(
  kind: kind,
  id: title,
  date: day ?? DateTime(start!.year, start.month, start.day),
  startsAt: start,
  endsAt: end,
  allDay: start == null,
  title: title,
  participantIds: who,
  createdBy: 'ama',
  visibility: visibility,
  status: status,
  sourceRef: ref,
);

void main() {
  test('copies shared, confirmed plans I am in: titles, times and places', () {
    final out = mirrorEventsFor(
      me: 'ama',
      items: [
        _e(
          'Dinner',
          start: DateTime(2026, 11, 3, 19),
          ref: const {'location_name': 'Kozo', 'note': 'bring wine'},
        ),
        _e('Gym', start: DateTime(2026, 11, 4, 7), who: const ['ama']),
        _e('Surprise', start: DateTime(2026, 11, 5, 19), visibility: TogetherVisibility.private),
        _e('Busy', start: DateTime(2026, 11, 5, 9), visibility: TogetherVisibility.busyOnly),
        _e('Theirs', start: DateTime(2026, 11, 5, 12), who: const ['kofi']),
        _e('Maybe', start: DateTime(2026, 11, 6, 19), status: 'proposed'),
        _e('Call mum', start: DateTime(2026, 11, 6, 9), kind: TogetherItemKind.reminder),
        _e('  ', start: DateTime(2026, 11, 7, 9)),
      ],
    );
    expect(out.map((e) => e.title), ['Dinner', 'Gym']);
    expect(out.first.location, 'Kozo');
    expect(out.first.end, DateTime(2026, 11, 3, 20)); // no end: an hour
    expect(mirrorEventsFor(me: null, items: [_e('Dinner', start: DateTime(2026, 11, 3, 19))]), isEmpty);
  });

  test('a three-day trip is one all-day entry; its later days are skipped', () {
    final ref = {'start_date': '2026-11-06', 'end_date': '2026-11-08'};
    final out = mirrorEventsFor(
      me: 'ama',
      items: [
        _e('Lisbon', day: DateTime(2026, 11, 6), ref: ref),
        _e('Lisbon', day: DateTime(2026, 11, 7), ref: {...ref, 'continuation': true}),
        _e('Lisbon', day: DateTime(2026, 11, 8), ref: {...ref, 'continuation': true}),
      ],
    );
    expect(out, hasLength(1));
    expect(out.single.allDay, isTrue);
    expect(out.single.start, DateTime(2026, 11, 6));
    expect(out.single.end, DateTime(2026, 11, 8));
  });

  test('phones report an all-day end as the last day or the midnight after it', () {
    final start = DateTime(2026, 11, 6);
    expect(allDayLastDay(start, DateTime(2026, 11, 8, 23, 59, 59)), DateTime(2026, 11, 8));
    expect(allDayLastDay(start, DateTime(2026, 11, 9)), DateTime(2026, 11, 8));
    expect(allDayLastDay(start, DateTime(2026, 11, 6)), DateTime(2026, 11, 6));
  });

  test('unchanged entries stay, new ones are added, gone or edited ones go', () {
    MirrorEvent m(String t, int h) => MirrorEvent(
      title: t,
      start: DateTime(2026, 11, 3, h),
      end: DateTime(2026, 11, 3, h + 1),
      allDay: false,
    );
    DeviceMirrorEvent d(String id, MirrorEvent e) =>
        DeviceMirrorEvent(id: id, start: e.start, fingerprint: e.fingerprint);
    final keep = m('Dinner', 19);
    final renamed = m('Brunch', 11);
    final changes = mirrorChanges(
      [keep, renamed, m('Film', 21)],
      [d('a', keep), d('b', m('Breakfast', 11)), d('c', m('Gone', 8)), d('dup', keep)],
    );
    expect(changes.create.map((e) => e.title), ['Brunch', 'Film']);
    expect(changes.delete.toSet(), {'b', 'c', 'dup'});
  });

  test('a moved last day, a new place or a new time is a different entry', () {
    final base = mirrorFingerprint(
      title: 'Lisbon',
      start: DateTime(2026, 11, 6),
      end: DateTime(2026, 11, 8),
      allDay: true,
    );
    expect(
      mirrorFingerprint(title: 'Lisbon', start: DateTime(2026, 11, 6), end: DateTime(2026, 11, 9), allDay: true),
      isNot(base),
    );
    expect(
      mirrorFingerprint(title: 'Lisbon', start: DateTime(2026, 11, 6), end: DateTime(2026, 11, 8), allDay: true, location: 'Porto'),
      isNot(base),
    );
    // All-day: the time of day the phone stores doesn't matter.
    expect(
      mirrorFingerprint(title: 'Lisbon', start: DateTime(2026, 11, 6, 0, 0, 1), end: DateTime(2026, 11, 8, 23, 59), allDay: true),
      base,
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_mirror_test.dart`
Expected: FAIL, because `together_mirror.dart` doesn't exist.

- [ ] **Step 3: Implement**

```dart
/// The phone-calendar copy (Together Phase 8d): plans I'm in for the next
/// 60 days, in a calendar of their own. Titles, times and places only; no
/// names or notes (R2). One-way: Together is the source (spec §6.4).
library;

import 'together_item.dart';

const mirrorDays = 60;

String _ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Matches a copied entry to its plan without storing anything per entry
/// (R3). All-day entries compare by day: phones store their times variously.
String mirrorFingerprint({
  required String title,
  required DateTime start,
  required DateTime end,
  required bool allDay,
  String? location,
}) {
  final when =
      allDay
          ? '${_ymd(start)}..${_ymd(end)}'
          : '${start.millisecondsSinceEpoch}..${end.millisecondsSinceEpoch}';
  return '$title|$when|$allDay|${location ?? ''}';
}

/// Phones report an all-day event's end either as its last day or as the
/// midnight after it; both mean the same last day.
DateTime allDayLastDay(DateTime start, DateTime end) {
  final first = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  final midnight =
      end.hour == 0 && end.minute == 0 && end.second == 0 && end.millisecond == 0;
  return midnight && last.isAfter(first)
      ? DateTime(last.year, last.month, last.day - 1)
      : last;
}

class MirrorEvent {
  const MirrorEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
  });

  final String title;

  /// Local times; for all-day entries the first and last day (midnight).
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  String get fingerprint => mirrorFingerprint(
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    location: location,
  );
}

/// An entry already in the phone's copy.
class DeviceMirrorEvent {
  const DeviceMirrorEvent({
    required this.id,
    required this.start,
    required this.fingerprint,
  });

  final String id;
  final DateTime start;
  final String fingerprint;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

List<MirrorEvent> mirrorEventsFor({
  required List<TogetherItem> items,
  required String? me,
}) {
  if (me == null) return const [];
  final out = <MirrorEvent>[];
  final seen = <String>{};
  for (final i in items) {
    if (i.kind != TogetherItemKind.event || i.status != 'confirmed') continue;
    // Surprises and busy blocks stay in Together (spec §3).
    if (i.visibility != TogetherVisibility.shared) continue;
    if (!i.participantIds.contains(me)) continue;
    // A multi-day plan arrives once per day: copy it once, from its first.
    if (i.sourceRef['continuation'] == true) continue;
    final title = i.title.trim();
    if (title.isEmpty) continue;
    final s = i.startsAt;
    final allDay = i.allDay || s == null;
    final DateTime start;
    final DateTime end;
    if (allDay) {
      // A repeating all-day plan is one day each time.
      final repeats = i.sourceRef['rrule'] != null;
      start = repeats ? i.date : (_date(i.sourceRef['start_date']) ?? i.date);
      end = repeats ? start : (_date(i.sourceRef['end_date']) ?? start);
    } else {
      start = s;
      end = i.endsAt ?? s.add(const Duration(hours: 1));
    }
    final e = MirrorEvent(
      title: title,
      start: start,
      end: end,
      allDay: allDay,
      location: i.sourceRef['location_name'] as String?,
    );
    if (seen.add(e.fingerprint)) out.add(e);
  }
  return out;
}

/// What to add and what to remove so the copy matches [desired]. Duplicates
/// on the phone beyond what's wanted are removed.
({List<MirrorEvent> create, List<String> delete}) mirrorChanges(
  List<MirrorEvent> desired,
  List<DeviceMirrorEvent> existing,
) {
  final pool = <String, List<String>>{};
  for (final e in existing) {
    (pool[e.fingerprint] ??= []).add(e.id);
  }
  final create = <MirrorEvent>[];
  for (final d in desired) {
    final ids = pool[d.fingerprint];
    if (ids != null && ids.isNotEmpty) {
      ids.removeAt(0);
    } else {
      create.add(d);
    }
  }
  return (create: create, delete: [for (final ids in pool.values) ...ids]);
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `flutter test test/features/together/together_mirror_test.dart`
Expected: PASS (5 tests).

---

### Task 2: The calendar, the sync, the setting and the clearing

**Files:**
- Create: `lib/features/together/data/together_calendar_mirror.dart`
- Modify: `lib/features/together/data/together_device_surfaces.dart` (from 8c)
- Modify: `lib/features/together/presentation/together_providers.dart` (after `togetherLiveSupportedProvider`)
- Modify: `lib/features/auth/presentation/widgets/logout_action.dart` (shared; re-read it first)
- Test: `test/features/together/together_calendar_mirror_test.dart`

**Interfaces:**
- Consumes: Task 1, plus `clearTogetherDeviceSurfaces` (8c).
- Produces:
  - `const mirrorEnabledKey = 'together_mirror_enabled'`, `const mirrorCalendarKey = 'together_mirror_calendar_id'`, `const mirrorCalendarName = 'Plans'`;
  - `abstract class MirrorCalendar { hasAccess(); requestAccess(); exists(id); create(name); list(id, from, to); add(id, MirrorEvent); remove(eventId); deleteCalendar(id); }`;
  - `class TogetherMirror` with the static members `calendar`, `ensureAccess()`, `calendarId()`, `syncIfEnabled(load, me, now)` and `clear()`;
  - `togetherMirrorEnabledProvider`, whose `set(bool)` returns `Future<bool>` and is false when access is refused;
  - test export `FakeMirrorCalendar`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

class FakeMirrorCalendar implements MirrorCalendar {
  FakeMirrorCalendar({this.access = true});
  bool access;
  final names = <String, String>{};
  final events = <String, List<(String, MirrorEvent)>>{};
  int adds = 0;
  int removes = 0;
  var _n = 0;

  List<MirrorEvent> entries(String name) => [
    for (final id in names.keys.where((k) => names[k] == name))
      for (final (_, e) in events[id] ?? const <(String, MirrorEvent)>[]) e,
  ];

  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<bool> requestAccess() async => access;
  @override
  Future<bool> exists(String calendarId) async => events.containsKey(calendarId);
  @override
  Future<String> create(String name) async {
    final id = 'cal-${++_n}';
    names[id] = name;
    events[id] = [];
    return id;
  }

  @override
  Future<List<DeviceMirrorEvent>> list(String calendarId, DateTime from, DateTime to) async => [
    for (final (id, e) in events[calendarId] ?? const <(String, MirrorEvent)>[])
      if (!e.start.isBefore(from) && e.start.isBefore(to))
        DeviceMirrorEvent(id: id, start: e.start, fingerprint: e.fingerprint),
  ];
  @override
  Future<void> add(String calendarId, MirrorEvent e) async {
    adds++;
    events[calendarId]!.add(('ev-${++_n}', e));
  }

  @override
  Future<void> remove(String eventId) async {
    removes++;
    for (final l in events.values) {
      l.removeWhere((x) => x.$1 == eventId);
    }
  }

  @override
  Future<void> deleteCalendar(String calendarId) async {
    events.remove(calendarId);
    names.remove(calendarId);
  }
}

final _now = DateTime(2026, 11, 2, 9);

TogetherItem _plan(String title, DateTime start) => TogetherItem(
  kind: TogetherItemKind.event,
  id: title,
  date: DateTime(start.year, start.month, start.day),
  startsAt: start,
  allDay: false,
  title: title,
  participantIds: const ['ama', 'kofi'],
  createdBy: 'ama',
);

void main() {
  late FakeMirrorCalendar cal;
  setUp(() {
    cal = FakeMirrorCalendar();
    TogetherMirror.calendar = cal;
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
  });

  Future<bool> sync(List<TogetherItem> items) => TogetherMirror.syncIfEnabled(
    (from, to) async => items,
    'ama',
    _now,
  );

  test('copies my plans into a calendar called Plans, and remembers it', () async {
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isTrue);
    expect(cal.names.values, ['Plans']);
    expect(cal.entries('Plans').map((e) => e.title), ['Dinner']);
    expect(await TogetherMirror.calendarId(), cal.names.keys.single);
  });

  test('a second sync with nothing changed changes nothing', () async {
    final items = [_plan('Dinner', DateTime(2026, 11, 3, 19))];
    await sync(items);
    final (adds, removes) = (cal.adds, cal.removes);
    await sync(items);
    expect((cal.adds, cal.removes), (adds, removes));
    expect(cal.names, hasLength(1));
  });

  test('a renamed plan replaces its entry', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    await sync([_plan('Dinner at Kozo', DateTime(2026, 11, 3, 19))]);
    expect(cal.entries('Plans').map((e) => e.title), ['Dinner at Kozo']);
  });

  test('a deleted calendar is made again', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    await cal.deleteCalendar(cal.names.keys.single);
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isTrue);
    expect(cal.entries('Plans').map((e) => e.title), ['Dinner']);
  });

  test('off, or no calendar access: nothing is made or read', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isFalse);
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    cal.access = false;
    expect(await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]), isFalse);
    expect(cal.names, isEmpty);
  });

  test('turning it on asks for access; refused, it stays off', () async {
    SharedPreferences.setMockInitialValues({});
    cal.access = false;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherMirrorEnabledProvider.future), isFalse);
    expect(await c.read(togetherMirrorEnabledProvider.notifier).set(true), isFalse);
    expect(await c.read(togetherMirrorEnabledProvider.future), isFalse);
    cal.access = true;
    expect(await c.read(togetherMirrorEnabledProvider.notifier).set(true), isTrue);
    expect(await c.read(togetherMirrorEnabledProvider.future), isTrue);
  });

  test('off deletes the whole calendar and forgets it', () async {
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(togetherMirrorEnabledProvider.notifier).set(false);
    expect(cal.names, isEmpty);
    expect(await TogetherMirror.calendarId(), isNull);
  });

  test('quick exit and sign-out clear every surface: card, lock screen, calendar', () async {
    final widget = FakeWidgetStore();
    final live = FakeLiveStore();
    TogetherWidgetSync.store = widget;
    TogetherLiveActivity.store = live;
    await sync([_plan('Dinner', DateTime(2026, 11, 3, 19))]);
    await clearTogetherDeviceSurfaces();
    expect(widget.saved, [null]);
    expect(live.ends, 1);
    expect(cal.names, isEmpty);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/together/together_calendar_mirror_test.dart`
Expected: FAIL, because `together_calendar_mirror.dart` is missing.

- [ ] **Step 3: Implement the calendar and the sync**

`lib/features/together/data/together_calendar_mirror.dart`:

```dart
import 'dart:io' show Platform;

import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/together_item.dart';
import '../domain/together_mirror.dart';

/// This phone's opt-in (Phase 8d); off unless set.
const mirrorEnabledKey = 'together_mirror_enabled';

/// The copy's calendar on this phone (the only thing stored, R3).
const mirrorCalendarKey = 'together_mirror_calendar_id';

/// No app name, no partner name (owner rule: discreet).
const mirrorCalendarName = 'Plans';

/// The phone's calendar store (a seam so tests never touch the platform).
abstract class MirrorCalendar {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<bool> exists(String calendarId);
  Future<String> create(String name);
  Future<List<DeviceMirrorEvent>> list(
    String calendarId,
    DateTime from,
    DateTime to,
  );
  Future<void> add(String calendarId, MirrorEvent e);
  Future<void> remove(String eventId);
  Future<void> deleteCalendar(String calendarId);
}

class DeviceCalendarPlusMirror implements MirrorCalendar {
  const DeviceCalendarPlusMirror();

  dc.DeviceCalendar get _cal => dc.DeviceCalendar.instance;

  @override
  Future<bool> hasAccess() async =>
      await _cal.hasPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> requestAccess() async =>
      await _cal.requestPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> exists(String calendarId) async =>
      (await _cal.listCalendars()).any((c) => c.id == calendarId);

  @override
  Future<String> create(String name) async {
    // Kept on this phone where it can be (R1): Android's default already is;
    // on iOS "On My iPhone" exists only without iCloud calendars.
    dc.CreateCalendarPlatformOptions? options;
    if (Platform.isIOS) {
      final local =
          (await _cal.listSources())
              .where(
                (s) =>
                    s.type == dc.CalendarSourceType.local &&
                    s.supportsCalendarCreation,
              )
              .firstOrNull;
      if (local != null) options = dc.CreateCalendarOptionsIos(sourceId: local.id);
    }
    return _cal.createCalendar(
      name: name,
      colorHex: '#8E8E93',
      platformOptions: options,
    );
  }

  @override
  Future<List<DeviceMirrorEvent>> list(
    String calendarId,
    DateTime from,
    DateTime to,
  ) async => [
    for (final e in await _cal.listEvents(from, to, calendarIds: [calendarId]))
      DeviceMirrorEvent(
        id: e.eventId,
        start: e.startDate,
        fingerprint: mirrorFingerprint(
          title: e.title,
          start: e.startDate,
          end: e.isAllDay ? allDayLastDay(e.startDate, e.endDate) : e.endDate,
          allDay: e.isAllDay,
          location: (e.location?.isEmpty ?? true) ? null : e.location,
        ),
      ),
  ];

  @override
  Future<void> add(String calendarId, MirrorEvent e) => _cal.createEvent(
    calendarId: calendarId,
    title: e.title,
    startDate: e.start,
    endDate: e.end,
    isAllDay: e.allDay,
    location: e.location,
  );

  @override
  Future<void> remove(String eventId) => _cal.deleteEvent(eventId: eventId);

  @override
  Future<void> deleteCalendar(String calendarId) =>
      _cal.deleteCalendar(calendarId);
}

/// Keeps the copy in step with Together, and removes it. Never throws.
class TogetherMirror {
  static MirrorCalendar calendar = const DeviceCalendarPlusMirror();

  static Future<String?> calendarId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(
        mirrorCalendarKey,
      );
    } catch (_) {
      return null;
    }
  }

  /// Already allowed, or asks now. False when refused.
  static Future<bool> ensureAccess() async {
    try {
      return await calendar.hasAccess() || await calendar.requestAccess();
    } catch (_) {
      return false;
    }
  }

  /// Copies the plans I'm in for the next [mirrorDays] days, if this phone
  /// opted in (read from storage itself) and calendar access is allowed.
  /// [load] fetches Together items for a date range. Returns whether it ran.
  static Future<bool> syncIfEnabled(
    Future<List<TogetherItem>> Function(DateTime from, DateTime to) load,
    String? me,
    DateTime now,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(mirrorEnabledKey) ?? false) || me == null) {
        return false;
      }
      if (!await calendar.hasAccess()) return false;
      var id = prefs.getString(mirrorCalendarKey);
      if (id == null || !await calendar.exists(id)) {
        id = await calendar.create(mirrorCalendarName);
        await prefs.setString(mirrorCalendarKey, id);
      }
      final from = DateTime(now.year, now.month, now.day);
      final to = DateTime(from.year, from.month, from.day + mirrorDays);
      final desired = [
        for (final e in mirrorEventsFor(items: await load(from, to), me: me))
          if (!e.start.isBefore(from)) e,
      ];
      // Entries from before today stay as history (R3).
      final existing = [
        for (final e in await calendar.list(id, from, to))
          if (!e.start.isBefore(from)) e,
      ];
      final changes = mirrorChanges(desired, existing);
      for (final eventId in changes.delete) {
        await calendar.remove(eventId);
      }
      for (final e in changes.create) {
        await calendar.add(id, e);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// "Off", quick exit and sign-out: the whole calendar goes (R5).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(mirrorCalendarKey);
      if (id == null) return;
      await calendar.deleteCalendar(id);
      await prefs.remove(mirrorCalendarKey);
    } catch (_) {}
  }
}
```

If `firstOrNull` isn't available (it comes from `package:collection` / Dart 3 iterable extensions), use `.cast<dc.CalendarSource?>().firstWhere(…, orElse: () => null)`. Check `dc.CreateCalendarOptionsIos` the same way: it is exported through `device_calendar_plus.dart`, which re-exports `device_calendar_plus_ios`.

- [ ] **Step 4: Add the calendar to the combined clear**

Replace the body of `together_device_surfaces.dart`, and add `import 'together_calendar_mirror.dart';`:

```dart
/// Everything Together puts on this phone outside the app (Phase 8): the
/// home-screen card, the lock-screen plan and the calendar copy. Quick exit
/// and sign-out empty them all (owner rule: discreet). Never throws.
Future<void> clearTogetherDeviceSurfaces() async {
  await TogetherWidgetSync.clear();
  await TogetherLiveActivity.end();
  await TogetherMirror.clear();
}
```

- [ ] **Step 5: Add the opt-in**

In `together_providers.dart`, add `import '../data/together_calendar_mirror.dart';`, then:

```dart
/// The calendar copy, opted into on this phone (Phase 8d). Off by default.
class TogetherMirrorEnabled extends AsyncNotifier<bool> {
  static const key = mirrorEnabledKey;

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  /// Turning it on needs calendar access first; refused, it stays off and
  /// this returns false so the caller can say how to allow it.
  Future<bool> set(bool on) async {
    if (on && !await TogetherMirror.ensureAccess()) {
      state = const AsyncData(false);
      return false;
    }
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherMirror.clear();
    state = AsyncData(on);
    return true;
  }
}

final togetherMirrorEnabledProvider =
    AsyncNotifierProvider<TogetherMirrorEnabled, bool>(
      TogetherMirrorEnabled.new,
    );
```

- [ ] **Step 6: Sign-out clears before stored settings are wiped** (`logout_action.dart`, shared; re-read it first)

Move the line `await clearTogetherDeviceSurfaces();` and its comment from after `clearUserData()` to directly before it. The calendar id lives in SharedPreferences, which `clearUserData()` wipes. Add `togetherMirrorEnabledProvider` to the `show` list and invalidate it next to the other two:

```dart
            // The card, lock-screen plan and calendar copy must not keep
            // showing this person's plans. Before clearUserData(): the
            // copy's calendar id is one of the settings it wipes.
            await clearTogetherDeviceSurfaces();

            // Clear user-specific SharedPrefs (keeps theme/language).
            await ref.read(preferencesServiceProvider).clearUserData();

            // …and forget this session's opt-ins (the next person opts in afresh).
            ref.invalidate(togetherWidgetEnabledProvider);
            ref.invalidate(togetherLiveEnabledProvider);
            ref.invalidate(togetherMirrorEnabledProvider);
```

- [ ] **Step 7: Run the tests and watch them pass**

Run: `flutter test test/features/together/together_calendar_mirror_test.dart test/features/together/together_live_activity_test.dart test/features/together/together_widget_sync_test.dart`
Expected: PASS (8 new tests). The 8a and 8c quick-exit tests still pass.

---

### Task 3: The busy overlay never reads the copy

**Files:**
- Modify: `lib/features/together/domain/together_overlay.dart:65-79` (`DeviceBusy`)
- Modify: `lib/features/together/data/device_busy_source.dart` (`read`)
- Modify: `lib/features/together/presentation/together_providers.dart` (`syncBusyTimes`)
- Test: `test/features/together/busy_sync_test.dart`

**Interfaces:**
- Consumes: `TogetherMirror.calendarId()` (Task 2).
- Produces: `DeviceBusy({…, String? calendarId})`.

- [ ] **Step 1: Write the failing test** (add it to `busy_sync_test.dart`, together with the import `package:shared_preferences/shared_preferences.dart`)

```dart
  test('the calendar copy of our plans is never uploaded as busy', () async {
    SharedPreferences.setMockInitialValues({
      'together_mirror_calendar_id': 'cal-copy',
    });
    final g = FakeTogetherGateway({
      'get_together_overlay': (_) => {'level': 'free_windows'},
      'replace_my_busy_blocks': (_) => 1,
    });
    await syncBusyTimes(
      TogetherRepository(g),
      FakeBusySource(
        events: [
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 9),
            end: DateTime.utc(2026, 11, 10, 10),
            calendarId: 'work',
          ),
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 19),
            end: DateTime.utc(2026, 11, 10, 21),
            calendarId: 'cal-copy',
          ),
        ],
      ),
      'r1',
      now,
    );
    expect(g.calls.last.$2['p_blocks'], [
      {
        'starts_at': '2026-11-10T09:00:00.000Z',
        'ends_at': '2026-11-10T10:00:00.000Z',
      },
    ]);
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/busy_sync_test.dart`
Expected: FAIL, with a compile error because `calendarId` is not a `DeviceBusy` parameter.

- [ ] **Step 3: Implement**

`DeviceBusy`: add `this.calendarId,` to the constructor, and add this field:

```dart
  /// Which phone calendar it came from (lets the calendar copy be skipped).
  final String? calendarId;
```

`DeviceCalendarPlusSource.read`: add `calendarId: e.calendarId,` to the `DeviceBusy(…)`.

`syncBusyTimes`: replace the `read` line with the following, and add `import '../data/together_calendar_mirror.dart';` if Task 2 hasn't already:

```dart
    // Our own plans, copied into the phone (Phase 8d), are already busy on
    // the server (§8.9 R3): never upload them again.
    final copy = await TogetherMirror.calendarId();
    final events = [
      for (final e in await source.read(now, now.add(const Duration(days: 14))))
        if (copy == null || e.calendarId != copy) e,
    ];
```

- [ ] **Step 4: Run it and watch it pass**

Run: `flutter test test/features/together/busy_sync_test.dart`
Expected: PASS. All the existing busy-sync tests still pass, because with no copy stored nothing is filtered.

---

### Task 4: The setting, the hub sync, and the iOS purpose strings

**Files:**
- Modify: `lib/features/together/presentation/widgets/together_settings_sheet.dart` (after the 8c lock-screen block)
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (next to `_busySynced`)
- Modify: `ios/Runner/Info.plist` (`NSCalendarsUsageDescription`, `NSCalendarsFullAccessUsageDescription`)
- Test: `test/features/together/together_mirror_settings_test.dart` (new), `test/features/together/together_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 (`togetherMirrorEnabledProvider`, `TogetherMirror.syncIfEnabled`, `FakeMirrorCalendar`).
- Produces: none.

- [ ] **Step 1: Write the failing settings test**

`test/features/together/together_mirror_settings_test.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_calendar_mirror.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_calendar_mirror_test.dart' show FakeMirrorCalendar;
import 'together_repository_test.dart' show FakeTogetherGateway;

const _title = "Copy our plans to my phone's calendar";

Future<void> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(1170, 5600);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(
          TogetherRepository(
            FakeTogetherGateway({
              'get_together_prefs':
                  (_) => {'daily_summary': true, 'care_nudges': true},
              'get_together_overlay': (_) => {'level': 'off'},
            }),
          ),
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        deviceBusySourceProvider.overrideWithValue(FakeBusySource()),
        togetherLiveSupportedProvider.overrideWith((ref) async => false),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed: () => showTogetherSettingsSheet(c, 'r1'),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

Finder _toggle() => find.descendant(
  of: find.ancestor(of: find.text(_title), matching: find.byType(InfoRowWidget)),
  matching: find.byType(Switch),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the calendar copy is off until I turn it on, and says what it adds', (
    t,
  ) async {
    TogetherMirror.calendar = FakeMirrorCalendar();
    await _open(t);
    expect(find.text(_title), findsOneWidget);
    expect(find.textContaining('“Plans”'), findsOneWidget);
    expect(t.widget<Switch>(_toggle()).value, isFalse);
    await t.tap(_toggle());
    await t.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool('together_mirror_enabled'),
      isTrue,
    );
  });

  testWidgets('without calendar access it stays off and says how to allow it', (
    t,
  ) async {
    TogetherMirror.calendar = FakeMirrorCalendar(access: false);
    await _open(t);
    await t.tap(_toggle());
    await t.pumpAndSettle();
    expect(t.widget<Switch>(_toggle()).value, isFalse);
    expect(find.text('Calendar access is off. You can allow it in Settings.'), findsOneWidget);
  });
}
```

If `InfoRowWidget` exposes its toggle differently, use the finder from `together_widget_settings_test.dart`.

- [ ] **Step 2: Write the failing hub tests**

In `together_screen_test.dart`:
- add the imports `package:attune/features/together/data/together_calendar_mirror.dart` and `'together_calendar_mirror_test.dart' show FakeMirrorCalendar;`;
- give `_pump` a `FakeMirrorCalendar? mirror` parameter, and set `TogetherMirror.calendar = mirror ?? FakeMirrorCalendar();` next to the 8c live default;
- add these tests:

```dart
  testWidgets('with the calendar copy on, opening Together copies our plans', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_mirror_enabled': true});
    final mirror = FakeMirrorCalendar();
    await _pump(
      t,
      mirror: mirror,
      upcoming: [
        _row('d', '2026-11-03', startsAt: '2026-11-03T19:00:00Z', title: 'Dinner'),
      ],
    );
    await t.pumpAndSettle();
    expect(mirror.entries('Plans').map((e) => e.title), ['Dinner']);
  });

  testWidgets('turning the calendar copy on copies straight away', (t) async {
    SharedPreferences.setMockInitialValues({});
    final mirror = FakeMirrorCalendar();
    await _pump(
      t,
      mirror: mirror,
      upcoming: [
        _row('d', '2026-11-03', startsAt: '2026-11-03T19:00:00Z', title: 'Dinner'),
      ],
    );
    await t.pumpAndSettle();
    expect(mirror.names, isEmpty);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    await c.read(togetherMirrorEnabledProvider.notifier).set(true);
    await t.pumpAndSettle();
    expect(mirror.entries('Plans').map((e) => e.title), ['Dinner']);
  });
```

The fake gateway answers `list_together_items` with `upcoming` when `p_start` is `2026-11-02`. The sync loads from the hub clock's day (`togetherClockProvider`, 2026-11-02), so it receives `upcoming`.

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/features/together/together_mirror_settings_test.dart test/features/together/together_screen_test.dart`
Expected: FAIL. The setting title is not found, and `mirror.entries('Plans')` is empty.

- [ ] **Step 4: Implement the setting**

In `together_settings_sheet.dart`:
- add `final mirrorOn = ref.watch(togetherMirrorEnabledProvider).valueOrNull;` next to `liveOn`;
- add this method next to `_setOverlay`:

```dart
  Future<void> _setMirror(bool on) async {
    final ok = await ref.read(togetherMirrorEnabledProvider.notifier).set(on);
    if (!ok && mounted) {
      // iOS never shows the prompt twice: offer the way back.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Calendar access is off. You can allow it in Settings.',
          ),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: () => ref.read(deviceBusySourceProvider).openSettings(),
          ),
        ),
      );
    }
  }
```

Add this after the 8c lock-screen block:

```dart
          if (mirrorOn != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: "Copy our plans to my phone's calendar",
              subtitle:
                  'Off unless you turn it on. Adds a calendar called “Plans” '
                  'with the next 60 days of plans you’re in — titles, times and '
                  'places; no names or notes. If your phone keeps calendars in '
                  'iCloud it may show on your other devices. Turning it off or '
                  'quick exit deletes it.',
              icon: Icons.event_available_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: mirrorOn,
              onToggleChanged: _setMirror,
            ),
          ],
```

If `onToggleChanged`'s type is `void Function(bool)`, wrap the method as `(v) => _setMirror(v)`.

- [ ] **Step 5: Implement the hub sync**

In `together_screen.dart`:
- add the import `../../data/together_calendar_mirror.dart`, matching the file's relative-import style;
- add the field `bool _mirrorSynced = false;` with the comment `/// The calendar copy is refreshed once per visit (Phase 8d R4).`, next to `_busySynced`;
- add this method:

```dart
  Future<void> _syncMirror(String relationshipId) async {
    final repo = ref.read(togetherRepositoryProvider);
    await TogetherMirror.syncIfEnabled(
      (from, to) => repo.listItems(relationshipId, start: from, end: to),
      ref.read(togetherMeProvider),
      ref.read(togetherClockProvider)(),
    );
  }
```

In `build`, directly after the `_busySynced` block, add:

```dart
    if (relationshipId != null && !_mirrorSynced) {
      _mirrorSynced = true;
      Future.microtask(() => _syncMirror(relationshipId));
    }
    // Turning the calendar copy on fills it now.
    ref.listen<AsyncValue<bool>>(togetherMirrorEnabledProvider, (prev, next) {
      if (relationshipId != null &&
          next.valueOrNull == true &&
          prev?.valueOrNull != true) {
        _syncMirror(relationshipId);
      }
    });
```

- [ ] **Step 6: The iOS purpose strings** (`ios/Runner/Info.plist`; App Review checks that these match what the app does)

`NSCalendarsFullAccessUsageDescription`:

```xml
		<string>With Free time together on, Attune reads only when you're busy in your calendar (never titles, places or people) to show when you're both free. With Copy our plans on, it keeps a calendar called Plans with the plans you're in.</string>
```

`NSCalendarsUsageDescription` (older iOS):

```xml
		<string>Attune adds a Together event to your calendar when you ask; with Free time together on, reads only when you're busy (never titles) to find time you're both free; and with Copy our plans on, keeps a calendar called Plans with the plans you're in.</string>
```

- [ ] **Step 7: Run the tests and watch them pass**

Run: `flutter test test/features/together/`
Expected: PASS for everything in the folder.

---

### Task 5: Spec rulings, full verification, device checklist

- [ ] **Step 1: Add §8.14 after §8.13** in the spec

```markdown
### 8.14 Phase 8d rulings — calendar copy (plan `2026-10-14-together-phase8d-mirror.md`)
- R1: A one-way copy into a calendar of its own called "Plans" (no app or partner name), on the phone's own account where one exists; otherwise iOS's default, and the setting says it may show on the person's other devices.
- R2: Confirmed shared plans I'm in, the next 60 days, each repeat its own entry: title, times or days, place. Never notes, names, private or busy-only items, suggestions, reminders, moments or Planning items.
- R3: Entries are matched by title, times (all-day: first and last day) and place; a changed plan is replaced; entries before today stay until it's turned off. Edits made in the phone calendar are overwritten.
- R4: Refreshed each time Together opens and straight away when turned on.
- R5: "Off", quick exit and sign-out delete the whole calendar (sign-out before stored settings are wiped).
- R6: The busy overlay never reads the copy.
```

- [ ] **Step 2: Full verification**

Run each of the following:
- `flutter test`
- `flutter analyze lib`
- `flutter build apk --debug --target-platform android-arm64`
- `flutter build ios --simulator --debug`
- `plutil -lint ios/Runner/Info.plist`

Expected: all green. The analyzer shows no new issues in the touched files.

- [ ] **Step 3: Owner device checklist (for the final report)**

1. On Android and iPhone, turn on "Copy our plans to my phone's calendar" and allow access.
   - A calendar called "Plans" appears, holding our shared plans: titles, times and places; no notes.
   - On an iPhone with iCloud calendars, note whether it landed in iCloud.
2. Open Together twice without changes. The phone calendar doesn't flicker or duplicate entries. All-day trips stay single entries on both platforms.
3. Rename a plan in Together and reopen Together: the entry updates.
4. Turn on Free time together. Busy times don't include the copied plans; check the partner's strips.
5. Test the three ways it is removed:
   - Quick exit deletes "Plans".
   - Turning it back on and then off deletes it.
   - Sign-out deletes it.
6. Deny calendar access, then try to turn it on. The switch stays off, and "Open Settings" goes to the app's settings page.
