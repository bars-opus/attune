# Together Phase 8a: Home-Screen Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in, discreet "Next" home-screen widget on iOS and Android. It shows the next one or two plans you're in (title and time), or a free window. It's off by default, never names the partner, uses no app wording, and is wiped the moment quick exit runs or you sign out.

**Architecture:**
- **App side:** the Flutter app computes a small payload whenever Together's agenda loads, while the widget is on for this phone. The payload holds up to three lines, each with a title, a pre-formatted local label, and start/end epoch milliseconds.
- **Storage:** the payload goes into widget storage through `home_widget` (an iOS App Group `UserDefaults`, or Android `SharedPreferences`), followed by a refresh request.
- **Widgets:** the native widgets only read that JSON and hide lines whose end has passed. iOS schedules a timeline entry at each end; Android re-filters on its 30-minute update.
- **Opt-in:** a per-phone setting, kept locally because it's about this device. Turning it off, quick exit and sign-out all clear the payload.
- **Prerequisite:** the pre-existing Android build failure is fixed first, by swapping the unmaintained `flutter_native_timezone` for its maintained fork `flutter_timezone`, so the Android widget can be build-verified.

**Tech Stack:** Flutter 3.29, Riverpod 2, `home_widget ^0.9.2`, `flutter_timezone ^5.1.1`, `shared_preferences` (existing), SwiftUI + WidgetKit (iOS 14+ extension), Kotlin `AppWidgetProvider` (RemoteViews), the Ruby `xcodeproj` gem (bundled with CocoaPods) to add the iOS target.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (D13, §8 Phase 8 row, §3.9 quick-exit and privacy-cover safety). Owner decisions (2026-10-14):
- **The widget comes first among the Phase 8 pieces.**
- **"Off by default, discreet":**
  - opt-in per person;
  - neutral text such as "Next: Dinner · Sat 7pm";
  - no partner name;
  - no app-revealing wording;
  - turns itself off with the discreet exit (quick exit).

## Global Constraints

- Off by default, per person (per phone).
- Discreet:
  - no partner name;
  - no "Attune" or "Together" wording inside the widget (the OS gallery shows the app name, which can't be avoided);
  - only titles and times of plans the user is in.
- Quick exit (permanent constraint 7: triple tap to the decoy) clears the widget. This must not delay or reveal activation, so it's fire-and-forget after the neutral cover is shown. Sign-out clears it too.
- Nothing about the partner's own plans: only items I'm a participant in. Moments never appear; neither do proposals (the read already excludes them) or Planning to-dos.
- Owner rules:
  - work on `main`;
  - write each test first and watch it fail;
  - commit nothing unless asked;
  - re-read a file before editing it;
  - make surgical changes;
  - flag regression risk in shared files (`quick_exit_service.dart`, `logout_action.dart`, `timezone_utils.dart`, `AndroidManifest.xml`, the Xcode project).

### Rulings (record them in spec §8.11 in Task 7)

- **R1: The widget is a "Next" card.** It shows up to two current lines: plans I'm in (events, ritual weeks, reminders and birthdays) and today's free windows, labelled "Free".
  - Titles appear as the user wrote them; the widget adds no names of its own.
  - Tapping it opens the app, under the usual privacy cover and safety unlock; there's no deep link.
- **R2: The setting lives on this phone** (`shared_preferences`, key `together_widget_enabled`), not on the server. It's about this device's home screen.
- **R3: The app formats labels** ("7:00 PM", "Tomorrow 7:00 PM", "Sat 7:00 PM"; all-day "Today", "Tomorrow", "Sat") in the user's locale. The native widgets only compare epoch times, so there are no date-formatting differences between platforms.
- **R4: Data refreshes whenever Together's agenda loads.** There's no background fetch, so a stale widget simply runs out of lines and shows "Nothing to show". iOS rolls over at each line's end; Android rolls over every 30 minutes.
- **R5: `flutter_native_timezone` is replaced by `flutter_timezone`** (one call site), which unblocks Android builds. Cost if wrong: a one-line revert.
- **R6: The iOS extension target is added by a script** (the `xcodeproj` gem), with an App Group `group.com.barsopus.attune` on Runner and the extension.
  - The owner must enable that App Group for both bundle IDs in the Apple Developer portal before a device build.
  - Simulator builds don't need it.

## Review Focus

1. **Quick exit must clear the widget without delaying activation.** The neutral cover shows first, and the clear is unawaited. Pinned in the Task 3 test.
2. **Turning the widget off, or signing out, leaves nothing readable in widget storage.** Pinned in the Task 3 tests.
3. **The partner's own plans, masked busy blocks, private events I'm not in, and moments never reach the widget.** Pinned in the Task 2 builder tests.
4. **Lines already over don't show.** All-day items last until the end of their last day. Pinned in the Task 2 tests (the payload carries the end) and in the native filter.
5. **A user who never turns it on.** Nothing is written, and an added widget shows "Nothing to show". Pinned in the Task 3 test.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `pubspec.yaml` | Modify | `-flutter_native_timezone`, `+flutter_timezone`, `+home_widget` |
| `lib/core/utils/timezone_utils.dart` | Modify | Use `flutter_timezone` |
| `test/core/utils/timezone_utils_test.dart` | Create | Channel-mocked test |
| `lib/features/together/domain/together_widget.dart` | Create | `WidgetLine`, `togetherWidgetLines`, `encodeWidgetPayload` (pure) |
| `lib/features/together/data/together_widget_sync.dart` | Create | `WidgetStore`, `HomeWidgetStore`, `TogetherWidgetSync` |
| `lib/features/together/presentation/together_providers.dart` | Modify | `togetherWidgetEnabledProvider` |
| `lib/features/together/presentation/widgets/together_settings_sheet.dart` | Modify | "Home screen" toggle |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | Publish when the agenda changes |
| `lib/features/safety/domain/services/quick_exit_service.dart` | Modify | Fire-and-forget clear |
| `lib/features/auth/presentation/widgets/logout_action.dart` | Modify | Clear on sign-out |
| `ios/TogetherWidget/{TogetherWidget.swift, Info.plist, TogetherWidget.entitlements}` | Create | The iOS widget |
| `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj` | Modify | App Group; the extension target (script) |
| `android/app/src/main/kotlin/com/barsopus/attune/TogetherWidgetProvider.kt` | Create | The Android widget |
| `android/app/src/main/res/layout/together_widget.xml`, `res/xml/together_widget_info.xml`, `res/values/together_widget_strings.xml` | Create | Layout and metadata |
| `android/app/src/main/AndroidManifest.xml` | Modify | Widget receiver |
| `docs/superpowers/specs/2026-10-14-together-hub-design.md` | Modify | §8.11 |

---

### Task 1: Unblock Android builds (timezone package)

**Files:**
- Modify: `pubspec.yaml`, `lib/core/utils/timezone_utils.dart`
- Test: `test/core/utils/timezone_utils_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/core/utils/timezone_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the device zone comes from the maintained timezone plugin', () async {
    TimezoneUtils.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_timezone'), (
          call,
        ) async {
          if (call.method == 'getLocalTimezone') return 'Europe/London';
          return null;
        });
    expect(await TimezoneUtils.getDeviceTimezone(), 'Europe/London');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/core/utils/timezone_utils_test.dart`
Expected: FAIL. The old plugin's channel isn't mocked, so it falls back to `'UTC'`.

- [ ] **Step 3: Swap the package**
  - Run `flutter pub remove flutter_native_timezone && flutter pub add flutter_timezone:^5.1.1`.
  - In `timezone_utils.dart`, change the import to `package:flutter_timezone/flutter_timezone.dart`, and the call to `_cachedTimezone = (await FlutterTimezone.getLocalTimezone()).identifier;`.
  - Run `grep -rn flutter_native_timezone lib test ios android` and expect nothing.

- [ ] **Step 4: Verify the test and the Android build**

Run: `flutter test test/core/utils/timezone_utils_test.dart && flutter build apk --debug --target-platform android-arm64`
Expected: the test passes, and the build reports `Built build/app/outputs/flutter-apk/app-debug.apk`. If the build fails for another, unrelated reason, record it in the ledger and continue. The widget's Android code is then verified by `flutter analyze` plus Kotlin syntax only, and the gap is flagged to the owner.

---

### Task 2: The widget's lines (pure Dart)

**Files:**
- Create: `lib/features/together/domain/together_widget.dart`
- Test: `test/features/together/together_widget_test.dart`

**Interfaces:**
- Produces:
  - `class WidgetLine { String title; String label; int startMs; int endMs; }`
  - `List<WidgetLine> togetherWidgetLines({required List<TogetherItem> items, required List<FreeWindow> windows, required String? me, required DateTime now, String locale = 'en'})`, returning at most 3 lines, sorted by start, all still current at `now`.
  - `String encodeWidgetPayload(List<WidgetLine> lines)`, producing `{"v":1,"lines":[{"title","label","start","end"}]}`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:convert';

import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _event(
  String id,
  DateTime start, {
  List<String> who = const ['ama', 'kofi'],
  String visibility = 'shared',
  String createdBy = 'ama',
  String title = 'Dinner',
  bool allDay = false,
  String kind = 'event',
}) => TogetherItem.fromRow({
  'item_kind': kind,
  'item_id': id,
  'item_date':
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
  'starts_at': allDay ? null : start.toUtc().toIso8601String(),
  'ends_at':
      allDay ? null : start.add(const Duration(hours: 2)).toUtc().toIso8601String(),
  'all_day': allDay,
  'tz': allDay ? null : 'UTC',
  'title': title,
  'participant_ids': who,
  'owner_id': null,
  'created_by': createdBy,
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {'kind': 'event'},
});

void main() {
  final now = DateTime(2026, 11, 2, 9); // Monday 09:00

  test('my plans, soonest first, labelled for a glance', () {
    final lines = togetherWidgetLines(
      items: [
        _event('a', DateTime(2026, 11, 7, 19), title: 'Dinner'),
        _event('b', DateTime(2026, 11, 2, 18), title: 'Gym', who: ['ama']),
        _event('c', DateTime(2026, 11, 3, 8), title: 'Flight'),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.map((l) => (l.title, l.label)), [
      ('Gym', '6:00 PM'),
      ('Flight', 'Tomorrow 8:00 AM'),
      ('Dinner', 'Sat 7:00 PM'),
    ]);
  });

  test("my partner's own plans, busy blocks and moments never appear", () {
    final lines = togetherWidgetLines(
      items: [
        _event('p', DateTime(2026, 11, 2, 12), who: ['kofi'], createdBy: 'kofi', title: 'Kofi lunch'),
        _event('b', DateTime(2026, 11, 2, 13), who: ['kofi'], createdBy: 'kofi', visibility: 'busy_only', title: 'Busy'),
        _event('m', DateTime(2026, 11, 2, 0), kind: 'moment', title: 'A memory'),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines, isEmpty);
  });

  test('a past plan is gone; an all-day plan lasts its whole day', () {
    final lines = togetherWidgetLines(
      items: [
        _event('old', DateTime(2026, 11, 2, 6), title: 'Run'), // ended 08:00
        _event('day', DateTime(2026, 11, 2), title: 'Rent', allDay: true),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.single.title, 'Rent');
    expect(lines.single.label, 'Today');
    expect(lines.single.endMs, DateTime(2026, 11, 3).millisecondsSinceEpoch);
  });

  test("today's free window shows as Free, with no names", () {
    final lines = togetherWidgetLines(
      items: const [],
      windows: [
        FreeWindow(
          start: DateTime(2026, 11, 2, 19),
          end: DateTime(2026, 11, 2, 22),
          partnerFrom: '14:00',
          partnerTo: '17:00',
          partnerDiffers: true,
        ),
      ],
      me: 'ama',
      now: now,
    );
    expect((lines.single.title, lines.single.label), (
      'Free',
      '7:00 PM–10:00 PM',
    ));
  });

  test('the payload is small JSON with epoch times', () {
    final json =
        jsonDecode(
              encodeWidgetPayload([
                const WidgetLine(title: 'Dinner', label: 'Sat 7:00 PM', startMs: 1, endMs: 2),
              ]),
            )
            as Map;
    expect(json, {
      'v': 1,
      'lines': [
        {'title': 'Dinner', 'label': 'Sat 7:00 PM', 'start': 1, 'end': 2},
      ],
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_widget_test.dart`
Expected: a compile failure because `together_widget.dart` doesn't exist.

- [ ] **Step 3: Write `together_widget.dart`**

```dart
/// The home-screen "Next" card (Together Phase 8a): plans I'm in and
/// today's free time, as a glance. No names added, no app wording (R1, R3).
library;

import 'dart:convert';

import 'package:intl/intl.dart';

import 'together_item.dart';
import 'together_overlay.dart';

class WidgetLine {
  const WidgetLine({
    required this.title,
    required this.label,
    required this.startMs,
    required this.endMs,
  });

  final String title;
  final String label;
  final int startMs;
  final int endMs;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _when(DateTime start, DateTime today, String locale, {bool timed = true}) {
  final diff = _day(start).difference(today).inDays;
  final time = DateFormat.jm(locale).format(start);
  final day = switch (diff) {
    0 => timed ? null : 'Today',
    1 => 'Tomorrow',
    _ => DateFormat.E(locale).format(start),
  };
  if (!timed) return day!;
  return day == null ? time : '$day $time';
}

List<WidgetLine> togetherWidgetLines({
  required List<TogetherItem> items,
  required List<FreeWindow> windows,
  required String? me,
  required DateTime now,
  String locale = 'en',
}) {
  final today = _day(now);
  final out = <WidgetLine>[];
  for (final i in items) {
    // Plans I'm in: events I take part in, and our shared reminders.
    final mine = switch (i.kind) {
      TogetherItemKind.event => me != null && i.participantIds.contains(me),
      TogetherItemKind.reminder => true,
      _ => false,
    };
    if (!mine) continue;
    final DateTime start;
    final DateTime end;
    if (i.allDay || i.startsAt == null) {
      start = _day(i.day);
      end = start.add(const Duration(days: 1));
    } else {
      start = i.startsAt!;
      end = i.endsAt ?? start.add(const Duration(hours: 1));
    }
    if (!end.isAfter(now)) continue;
    out.add(
      WidgetLine(
        title: i.title,
        label: _when(start, today, locale, timed: !(i.allDay || i.startsAt == null)),
        startMs: start.millisecondsSinceEpoch,
        endMs: end.millisecondsSinceEpoch,
      ),
    );
  }
  for (final w in windows) {
    if (_day(w.start) != today || !w.end.isAfter(now)) continue;
    out.add(
      WidgetLine(
        title: 'Free',
        label:
            '${DateFormat.jm(locale).format(w.start)}–${DateFormat.jm(locale).format(w.end)}',
        startMs: w.start.millisecondsSinceEpoch,
        endMs: w.end.millisecondsSinceEpoch,
      ),
    );
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out.take(3).toList();
}

String encodeWidgetPayload(List<WidgetLine> lines) => jsonEncode({
  'v': 1,
  'lines': [
    for (final l in lines)
      {'title': l.title, 'label': l.label, 'start': l.startMs, 'end': l.endMs},
  ],
});
```

The test for the reminder kind relies on `TogetherItemKind.reminder` and the row parsing. If `TogetherItem.fromRow` maps `item_kind: 'moment'` to `TogetherItemKind.moment`, the moment is excluded by the `_ => false` branch.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/together_widget_test.dart`
Expected: 5 pass. "6:00 PM" assumes the `en` locale; the test passes the default.

---

### Task 3: Storage, the setting, quick exit and sign-out

**Files:**
- Create: `lib/features/together/data/together_widget_sync.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Modify: `lib/features/safety/domain/services/quick_exit_service.dart` (shared safety code: one unawaited line, after the cover)
- Modify: `lib/features/auth/presentation/widgets/logout_action.dart` (shared: one awaited, error-swallowing line)
- Test: `test/features/together/together_widget_sync_test.dart`

**Interfaces:**
- Produces:
  - `abstract class WidgetStore { Future<void> save(String? payload); }`
  - `class HomeWidgetStore implements WidgetStore`. It sets the App Group and saves the key `together_widget_v1`, then calls `updateWidget(iOSName: 'TogetherWidget', qualifiedAndroidName: 'com.barsopus.attune.TogetherWidgetProvider')`.
  - `class TogetherWidgetSync { static WidgetStore store; static Future<void> publish(List<WidgetLine>); static Future<void> clear(); }`. Both are error-swallowing; `clear` saves `null`.
  - `togetherWidgetEnabledProvider`: an `AsyncNotifierProvider<TogetherWidgetEnabled, bool>`, backed by `SharedPreferences` key `together_widget_enabled` (default `false`). `set(bool)` persists, and turning it off clears.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWidgetStore implements WidgetStore {
  final saved = <String?>[];
  @override
  Future<void> save(String? payload) async => saved.add(payload);
}

void main() {
  late FakeWidgetStore store;
  setUp(() {
    store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    SharedPreferences.setMockInitialValues({});
  });

  test('off by default; turning it off clears what the widget shows', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherWidgetEnabledProvider.future), isFalse);
    await c.read(togetherWidgetEnabledProvider.notifier).set(true);
    expect(await c.read(togetherWidgetEnabledProvider.future), isTrue);
    await c.read(togetherWidgetEnabledProvider.notifier).set(false);
    expect(store.saved.last, isNull);
    expect(
      (await SharedPreferences.getInstance()).getBool('together_widget_enabled'),
      isFalse,
    );
  });

  test('publish writes the payload; a broken store never throws', () async {
    await TogetherWidgetSync.publish([
      const WidgetLine(title: 'Dinner', label: 'Sat 7:00 PM', startMs: 1, endMs: 2),
    ]);
    expect(store.saved.single, contains('"Dinner"'));
    TogetherWidgetSync.store = _ThrowingStore();
    await TogetherWidgetSync.publish(const []);
    await TogetherWidgetSync.clear();
  });

  testWidgets('quick exit shows the neutral screen first, then clears the widget', (
    t,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (c, _) => Scaffold(
                body: TextButton(
                  onPressed: () => QuickExitService.execute(c),
                  child: const Text('exit'),
                ),
              ),
        ),
        GoRoute(
          path: '/neutral',
          name: 'neutralScreen',
          builder: (_, __) => const Text('neutral'),
        ),
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.tap(find.text('exit'));
    await t.pump();
    expect(find.text('neutral'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 400));
    expect(store.saved, [null]);
  });
}

class _ThrowingStore implements WidgetStore {
  @override
  Future<void> save(String? payload) async => throw Exception('no widget');
}
```

The quick-exit test needs `flutter_secure_storage`'s channel. If its write throws in tests (no mock), it's already unawaited and non-fatal in `execute`. If an uncaught async error fails the test, mock the `plugins.it_nomads.com/flutter_secure_storage` channel to return `null`, and record that in the ledger.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_widget_sync_test.dart`
Expected: a compile failure because `together_widget_sync.dart` doesn't exist.

- [ ] **Step 3: Add `home_widget` and write the sync**
  - Run `flutter pub add home_widget:^0.9.2`.
  - `together_widget_sync.dart`:

```dart
import 'package:home_widget/home_widget.dart';

import '../domain/together_widget.dart';

const togetherWidgetAppGroup = 'group.com.barsopus.attune';
const _payloadKey = 'together_widget_v1';

/// Where the widget reads from (a seam so tests and quick exit stay simple).
abstract class WidgetStore {
  Future<void> save(String? payload);
}

class HomeWidgetStore implements WidgetStore {
  const HomeWidgetStore();

  @override
  Future<void> save(String? payload) async {
    await HomeWidget.setAppGroupId(togetherWidgetAppGroup);
    await HomeWidget.saveWidgetData<String>(_payloadKey, payload);
    await HomeWidget.updateWidget(
      iOSName: 'TogetherWidget',
      qualifiedAndroidName: 'com.barsopus.attune.TogetherWidgetProvider',
    );
  }
}

/// Fills or empties the home-screen card. Never throws: a phone without
/// the widget (or a test without the plugin) must not break the caller.
class TogetherWidgetSync {
  static WidgetStore store = const HomeWidgetStore();

  static Future<void> publish(List<WidgetLine> lines) async {
    try {
      await store.save(encodeWidgetPayload(lines));
    } catch (_) {}
  }

  /// Quick exit, sign-out and "off": nothing readable is left behind.
  static Future<void> clear() async {
    try {
      await store.save(null);
    } catch (_) {}
  }
}
```

  - The provider, in `together_providers.dart` (import `package:shared_preferences/shared_preferences.dart` and `../data/together_widget_sync.dart`):

```dart
/// The home-screen card, opted into on this phone (Phase 8a R2). Off by default.
class TogetherWidgetEnabled extends AsyncNotifier<bool> {
  static const key = 'together_widget_enabled';

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> set(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherWidgetSync.clear();
    state = AsyncData(on);
  }
}

final togetherWidgetEnabledProvider =
    AsyncNotifierProvider<TogetherWidgetEnabled, bool>(TogetherWidgetEnabled.new);
```

  - In `quick_exit_service.dart`'s `execute`, directly after `_showNeutralCover(context);`, add:

```dart
    // The home-screen card shows plans: empty it too. Fire-and-forget,
    // after the cover is up, so nothing delays or reveals activation.
    unawaited(TogetherWidgetSync.clear());
```

    Import `package:attune/features/together/data/together_widget_sync.dart`.
  - In `logout_action.dart`, after `clearUserData()`, add `await TogetherWidgetSync.clear();` with the import. It already swallows errors.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/together_widget_sync_test.dart && flutter analyze lib/features/together lib/features/safety lib/features/auth`
Expected: 3 pass; no issues. Then run `flutter test test/features/safety test/features/auth` and expect them green, since those are shared files.

---

### Task 4: The setting, and publishing from the hub

**Files:**
- Modify: `lib/features/together/presentation/widgets/together_settings_sheet.dart`
- Modify: `lib/features/together/presentation/screens/together_screen.dart`
- Test: `test/features/together/together_widget_settings_test.dart` (new) and `test/features/together/together_screen_test.dart` (extended)

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;
import 'together_widget_sync_test.dart' show FakeWidgetStore;

void main() {
  testWidgets('the home-screen card is off until I turn it on, and says what it shows', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = FakeWidgetStore();
    TogetherWidgetSync.store = store;
    t.view.physicalSize = const Size(1170, 4400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(
            TogetherRepository(
              FakeTogetherGateway({
                'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
              }),
            ),
          ),
          quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
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
    expect(find.text('Next plans on my home screen'), findsOneWidget);
    expect(find.textContaining('no names'), findsOneWidget);
    final toggle = find.descendant(
      of: find.ancestor(
        of: find.text('Next plans on my home screen'),
        matching: find.byType(InfoRowWidget),
      ),
      matching: find.byType(AppToggleSwitch),
    );
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool('together_widget_enabled'),
      isTrue,
    );
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(store.saved.last, isNull);
  });
}
```

  In `together_screen_test.dart`, add a test. `_pump` gets an `upcoming` row for an event I'm in. Set `SharedPreferences.setMockInitialValues({'together_widget_enabled': true})` and a `FakeWidgetStore`, pump, and expect `store.saved.last` to contain that event's title. A second test sets the preference to `false`, or leaves it unset, and expects `store.saved` to be empty.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/together/together_widget_settings_test.dart test/features/together/together_screen_test.dart`
Expected: failures, because the setting row and the publishing don't exist yet.

- [ ] **Step 3: The settings row.** In the settings sheet, read `final widgetOn = ref.watch(togetherWidgetEnabledProvider).valueOrNull ?? false;`. Add a section after "Free time together" and before "Your calendar app":

```dart
          AppDivider(),
          InfoRowWidget(
            title: 'Next plans on my home screen',
            subtitle:
                'Off unless you turn it on. Shows your next plans’ titles and '
                'times — no names. Anyone who sees your phone can see it; quick '
                'exit clears it.',
            icon: Icons.widgets_outlined,
            showAvatar: false,
            showDivider: false,
            isToggleItem: true,
            toggleValue: widgetOn,
            onToggleChanged:
                (v) => ref.read(togetherWidgetEnabledProvider.notifier).set(v),
          ),
```

- [ ] **Step 4: Publish from the hub.** In `together_screen.dart`'s `_agenda`, after `windows` is read, listen once per build:

```dart
    // The home-screen card (Phase 8a): refreshed from what the hub just
    // loaded, only when it's on for this phone.
    ref.listen<AsyncValue<TogetherAgenda>>(
      togetherAgendaProvider(relationshipId),
      (_, next) => _publishWidget(next.valueOrNull, windows, me, now),
    );
```

  Add the method:

```dart
  Future<void> _publishWidget(
    TogetherAgenda? agenda,
    List<FreeWindow> windows,
    String? me,
    DateTime now,
  ) async {
    if (agenda == null) return;
    final on = await ref.read(togetherWidgetEnabledProvider.future);
    if (!on || !mounted) return;
    await TogetherWidgetSync.publish(
      togetherWidgetLines(
        items: [
          ...agenda.today,
          for (final d in agenda.week) ...d.items,
          ...agenda.comingUp,
        ],
        windows: windows,
        me: me,
        now: now,
      ),
    );
  }
```

  Check the agenda field names in `together_agenda.dart` (`today`, `week`, `comingUp`); they're used above as defined there. The imports are `../../data/together_widget_sync.dart` and `../../domain/together_widget.dart`. If `ref.listen` doesn't fire for the first value in the screen test, also publish once in the same microtask that reports the zone, from `ref.read(togetherAgendaProvider(relationshipId).future)`, and record that in the ledger.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues. Other harnesses that pump the hub default to the widget being off (an empty `SharedPreferences` mock, or none), so they must not publish. If a harness lacks a `SharedPreferences` mock and errors, add `SharedPreferences.setMockInitialValues({})` to it and record that in the ledger.

---

### Task 5: The iOS widget

**Files:**
- Create: `ios/TogetherWidget/TogetherWidget.swift`, `ios/TogetherWidget/Info.plist`, `ios/TogetherWidget/TogetherWidget.entitlements`
- Modify: `ios/Runner/Runner.entitlements`, `ios/Runner.xcodeproj/project.pbxproj` (via the script)
- Scratch: `<scratchpad>/add_together_widget.rb`

- [ ] **Step 1: Write the widget**

`ios/TogetherWidget/TogetherWidget.swift`:

```swift
// Together "Next" card (Phase 8a). Reads only what the app wrote to the
// App Group; shows nothing that has already ended; adds no names or app words.
import SwiftUI
import WidgetKit

private let appGroup = "group.com.barsopus.attune"
private let payloadKey = "together_widget_v1"

struct Line: Decodable {
  let title: String
  let label: String
  let start: Double
  let end: Double
}

private struct Payload: Decodable {
  let v: Int
  let lines: [Line]
}

struct NextEntry: TimelineEntry {
  let date: Date
  let lines: [Line]
}

private func loadLines() -> [Line] {
  guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: payloadKey),
        let data = raw.data(using: .utf8),
        let payload = try? JSONDecoder().decode(Payload.self, from: data)
  else { return [] }
  return payload.lines
}

private func current(_ lines: [Line], at date: Date) -> [Line] {
  let ms = date.timeIntervalSince1970 * 1000
  return Array(lines.filter { $0.end > ms }.prefix(2))
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> NextEntry {
    NextEntry(date: Date(), lines: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
    let now = Date()
    completion(NextEntry(date: now, lines: current(loadLines(), at: now)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
    let now = Date()
    let all = loadLines()
    // A new entry whenever a line ends, so a passed plan drops off by itself.
    let ends = all.map { Date(timeIntervalSince1970: $0.end / 1000) }.filter { $0 > now }.sorted()
    let entries = ([now] + ends.prefix(5)).map { NextEntry(date: $0, lines: current(all, at: $0)) }
    let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now
    completion(Timeline(entries: entries, policy: .after(refresh)))
  }
}

struct TogetherWidgetView: View {
  var entry: NextEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Next").font(.caption).foregroundColor(.secondary)
      if entry.lines.isEmpty {
        Text("Nothing to show").font(.subheadline).foregroundColor(.secondary)
      } else {
        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
          VStack(alignment: .leading, spacing: 1) {
            Text(line.title).font(.subheadline).bold().lineLimit(1)
            Text(line.label).font(.caption).foregroundColor(.secondary).lineLimit(1)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .modifier(WidgetBackground())
  }
}

private struct WidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(.fill.tertiary, for: .widget)
    } else {
      content.padding()
    }
  }
}

@main
struct TogetherWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "TogetherWidget", provider: Provider()) { entry in
      TogetherWidgetView(entry: entry)
    }
    .configurationDisplayName("Next")
    .description("Your next plans. Turn it on in the app first.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
```

`ios/TogetherWidget/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>$(DEVELOPMENT_LANGUAGE)</string>
	<key>CFBundleDisplayName</key>
	<string>Next</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$(PRODUCT_NAME)</string>
	<key>CFBundlePackageType</key>
	<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.widgetkit-extension</string>
	</dict>
</dict>
</plist>
```

`ios/TogetherWidget/TogetherWidget.entitlements`, plus the same `com.apple.security.application-groups` entry added to `ios/Runner/Runner.entitlements`, keeping its existing associated-domains key:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.barsopus.attune</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Add the target with a script** (`<scratchpad>/add_together_widget.rb`, run with `GEM_HOME=/opt/homebrew/lib/ruby/gems/3.4.0 ruby <script>` from the repo root)

```ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
abort('TogetherWidget already exists') if project.targets.any? { |t| t.name == 'TogetherWidget' }
runner = project.targets.find { |t| t.name == 'Runner' }

widget = project.new_target(:app_extension, 'TogetherWidget', :ios, '14.0')
group = project.main_group.new_group('TogetherWidget', 'TogetherWidget')
widget.add_file_references([group.new_reference('TogetherWidget.swift')])
group.new_reference('Info.plist')
group.new_reference('TogetherWidget.entitlements')
widget.add_system_framework(%w[WidgetKit SwiftUI])

widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.barsopus.attune.TogetherWidget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'TogetherWidget/Info.plist'
  s['CODE_SIGN_ENTITLEMENTS'] = 'TogetherWidget/TogetherWidget.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = 'A8RJ357U9Y'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  s['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  s['SKIP_INSTALL'] = 'YES'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

runner.add_dependency(widget)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
build_file = embed.add_file_reference(widget.product_reference, true)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Flutter's "Thin Binary" phase must run after embedding, or Xcode reports a cycle.
thin = runner.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(runner.build_phases.index(thin), embed)
end

runner.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] ||= 'Runner/Runner.entitlements'
end

project.save
puts 'TogetherWidget target added'
```

  Before running it, check that Runner's configs already set `CODE_SIGN_ENTITLEMENTS` (`grep -n CODE_SIGN_ENTITLEMENTS ios/Runner.xcodeproj/project.pbxproj`). The `||=` keeps any existing value.

- [ ] **Step 3: Build for the simulator**

Run: `flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`, and `build/ios/iphonesimulator/Runner.app/PlugIns/TogetherWidget.appex` exists. If the build reports a dependency cycle, move the embed phase above "Thin Binary" as the script intends, and record that in the ledger. If it fails for signing on the extension, add `CODE_SIGNING_ALLOWED=NO` through `flutter build ios --simulator --debug --no-codesign`, and record that.

---

### Task 6: The Android widget

**Files:**
- Create: `android/app/src/main/kotlin/com/barsopus/attune/TogetherWidgetProvider.kt`
- Create: `android/app/src/main/res/layout/together_widget.xml`, `android/app/src/main/res/xml/together_widget_info.xml`, `android/app/src/main/res/values/together_widget_strings.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Write the provider**

```kotlin
package com.barsopus.attune

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/** Together "Next" card (Phase 8a): reads what the app wrote; hides what has ended. */
class TogetherWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    val lines = currentLines(widgetData.getString("together_widget_v1", null), System.currentTimeMillis())
    appWidgetIds.forEach { id ->
      val views = RemoteViews(context.packageName, R.layout.together_widget).apply {
        setOnClickPendingIntent(
          R.id.together_widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        bind(this, R.id.line1_title, R.id.line1_label, lines.getOrNull(0))
        bind(this, R.id.line2_title, R.id.line2_label, lines.getOrNull(1))
        setViewVisibility(R.id.together_widget_empty, if (lines.isEmpty()) View.VISIBLE else View.GONE)
      }
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun bind(views: RemoteViews, titleId: Int, labelId: Int, line: Line?) {
    val visibility = if (line == null) View.GONE else View.VISIBLE
    views.setViewVisibility(titleId, visibility)
    views.setViewVisibility(labelId, visibility)
    if (line != null) {
      views.setTextViewText(titleId, line.title)
      views.setTextViewText(labelId, line.label)
    }
  }

  data class Line(val title: String, val label: String, val end: Double)

  companion object {
    fun currentLines(raw: String?, now: Long): List<Line> = try {
      val array = JSONObject(raw ?: return emptyList()).getJSONArray("lines")
      (0 until array.length())
        .map { array.getJSONObject(it) }
        .map { Line(it.getString("title"), it.getString("label"), it.getDouble("end")) }
        .filter { it.end > now }
        .take(2)
    } catch (_: Exception) {
      emptyList()
    }
  }
}
```

- [ ] **Step 2: Layout, metadata and strings**

`res/layout/together_widget.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/together_widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="12dp"
    android:background="@android:drawable/screen_background_light">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="@string/together_widget_heading"
        android:textSize="12sp"
        android:textColor="#757575" />

    <TextView
        android:id="@+id/together_widget_empty"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="4dp"
        android:text="@string/together_widget_empty"
        android:textSize="14sp"
        android:textColor="#757575" />

    <TextView android:id="@+id/line1_title" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="4dp" android:maxLines="1" android:ellipsize="end"
        android:textSize="14sp" android:textStyle="bold" android:textColor="#212121" android:visibility="gone" />
    <TextView android:id="@+id/line1_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:maxLines="1" android:ellipsize="end" android:textSize="12sp" android:textColor="#757575" android:visibility="gone" />
    <TextView android:id="@+id/line2_title" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:layout_marginTop="6dp" android:maxLines="1" android:ellipsize="end"
        android:textSize="14sp" android:textStyle="bold" android:textColor="#212121" android:visibility="gone" />
    <TextView android:id="@+id/line2_label" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:maxLines="1" android:ellipsize="end" android:textSize="12sp" android:textColor="#757575" android:visibility="gone" />
</LinearLayout>
```

`res/xml/together_widget_info.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="140dp"
    android:minHeight="110dp"
    android:targetCellWidth="2"
    android:targetCellHeight="2"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/together_widget"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/together_widget_description" />
```

`res/values/together_widget_strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="together_widget_heading">Next</string>
    <string name="together_widget_empty">Nothing to show</string>
    <string name="together_widget_description">Your next plans. Turn it on in the app first.</string>
</resources>
```

- [ ] **Step 3: Register the receiver** in `AndroidManifest.xml`, inside `<application>`:

```xml
        <!-- Together "Next" card (Phase 8a). -->
        <receiver android:name=".TogetherWidgetProvider" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/together_widget_info" />
        </receiver>
```

- [ ] **Step 4: Verify**

Run: `xmllint --noout android/app/src/main/AndroidManifest.xml android/app/src/main/res/layout/together_widget.xml android/app/src/main/res/xml/together_widget_info.xml android/app/src/main/res/values/together_widget_strings.xml && flutter build apk --debug --target-platform android-arm64`
Expected: XML valid, and `Built …/app-debug.apk`. If Task 1's build was still blocked by something unrelated, record that and rely on `xmllint` plus the owner's device check.

---

### Task 7: Spec rulings, full verification, device checklist

- [ ] **Step 1: Add §8.11** after §8.10 in the spec:

```markdown
### 8.11 Phase 8a rulings — home-screen widget (plan `2026-10-14-together-phase8a-widget.md`)
- Owner decisions: the widget comes first among the native pieces; it is off by default and discreet.
- R1: A "Next" card: up to two current lines — plans I'm in and today's free windows ("Free") — titles as written, no names added, no app wording; tapping opens the app under its usual cover.
- R2: The on/off setting lives on the phone (it's about that home screen).
- R3: The app formats the labels; the widgets only compare times.
- R4: It refreshes when Together loads; lines drop off when they end. Quick exit, sign-out and "off" empty it at once.
- R5: `flutter_native_timezone` replaced by `flutter_timezone` (unblocks Android builds).
- R6: iOS App Group `group.com.barsopus.attune` for the app and the widget.
```

- [ ] **Step 2: Full verification**

Run:
- `flutter test`
- `flutter analyze lib/features/together lib/features/safety lib/features/auth lib/core/utils`
- `flutter build ios --simulator --debug`
- `flutter build apk --debug --target-platform android-arm64`

Expected: everything passes and both builds complete.

- [ ] **Step 3: The owner's device checklist** (put it in the final report):
  1. In the Apple Developer portal, enable the App Group `group.com.barsopus.attune` for `com.barsopus.attune` and `com.barsopus.attune.TogetherWidget`, then build to a device.
  2. Add the "Next" widget before turning it on. It should say "Nothing to show".
  3. Turn on "Next plans on my home screen", open Together, and check that the widget shows your next plan.
  4. Triple-tap quick exit, then go back to the home screen. The widget should say "Nothing to show".
  5. On Android, do the same with the widget picker.
