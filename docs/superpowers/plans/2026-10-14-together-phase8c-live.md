# Together Phase 8c: lock-screen plan (Live Activity) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a shared plan tonight is close, an opted-in iPhone shows its title, its time and a countdown on the lock screen and in the Dynamic Island, and removes it when the plan ends, on quick exit, on sign-out or when it is turned off.

**Architecture:**
- A pure Dart picker chooses at most one plan.
- A small `MethodChannel` (`attune/together_live`) asks iOS ActivityKit to start, update or end one Live Activity. No package is added.
- The widget extension from Phase 8a draws the activity. It shares one `ActivityAttributes` struct with the app.
- The hub publishes the plan when Together loads, in the same way 8a publishes the widget.
- One new function, `clearTogetherDeviceSurfaces()`, clears every Together surface on the phone. Quick exit and sign-out both call it.

**Tech Stack:** Flutter 3.29 / Riverpod 2, SharedPreferences, Swift (ActivityKit and WidgetKit, iOS 16.2+ at runtime, app still iOS 14+), the Ruby xcodeproj gem.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md`. Phase 8 row in §8 (`live_activities`, "date tonight"); §3 hard rules; §8.11 (8a) and §8.12 (8b) rulings.

## Global Constraints

- The owner's Phase 8 rule: **off by default, opt-in per phone; discreet.** No partner name and no app-revealing wording on OS surfaces. Quick exit, sign-out and "off" clear it at once.
- Spec §3: private or surprise events are visible only to their creator, everywhere. Never show a `private` or `busy_only` item on the lock screen.
- Spec §3 "quiet by default": no new pushes. This phase adds no notification and no server code.
- The app's deployment target stays **iOS 14.0**. ActivityKit is weak-linked, and every ActivityKit use is behind `#available(iOS 16.2, *)`.
- Android: nothing in this phase (ruling R1). The setting is hidden on Android.
- Owner rules: work on main, write each test first and watch it fail, make no commits. Re-read a file before editing it, because the owner edits by hand.

### Rulings (record them in spec §8.13 in Task 5)

- **R1: iOS only.** Live Activities exist only on iOS. Android gets no ongoing notification, because quiet by default wins. *Cost if wrong:* a later Android ongoing-notification task.
- **R2: what is shown.** One plan: a confirmed, timed, `shared` event that includes both of us. It appears from 4 hours before it starts until it ends. If two qualify, the earliest start wins, so a plan already under way beats a later one.
  - Before the start: the title as written, the times, and a countdown.
  - After the start: the title and the times.
  - Never shown: names, the app's name, notes or places.
  - *Cost if wrong:* widening the filter later.
- **R3: who drives it.** The app starts, updates and ends it whenever Together loads. iOS does not let an app start one in the background without a push server, which is out of scope. The 4-hour lead keeps it inside iOS's 8-hour limit. If the person doesn't reopen the app, iOS ends it within 8 hours of starting. *Cost if wrong:* a push-to-start phase.
- **R4: the setting.** Opt-in per phone, stored under the SharedPreferences key `together_live_enabled` and off by default. It is shown only where supported: iOS 16.2+ with Live Activities allowed in iOS Settings.
- **R5: clearing.** Quick exit, sign-out and "off" end it with immediate dismissal. One function, `clearTogetherDeviceSurfaces()`, clears the widget and the Live Activity (8d adds the calendar copy).
- **R6: no package.** We use our own channel instead. Weak-linked ActivityKit keeps iOS 14 devices working, and the `live_activities` package's fixed attribute type is avoided.

## Review Focus

1. **A plan cancelled, moved or renamed while it's on the lock screen.** The next time Together loads, the activity updates or ends. Pinned by the Task 3 test "with no plan close, the hub ends the lock-screen plan".
2. **Two plans tonight.** The one under way wins over a later one, and an ended one never shows. Pinned in the Task 1 tests.
3. **A private surprise plan, or the partner's busy-only block.** It never reaches the lock screen. Pinned in the Task 1 tests.
4. **Live Activities turned off in iOS Settings, iOS older than 16.2, or Android.** The setting is hidden and nothing throws. Pinned in the Task 2 test (a broken channel gives `false`) and the Task 3 settings test.
5. **Quick exit while the activity is up.** It ends together with the widget. Pinned in the Task 2 quick-exit test.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `lib/features/together/domain/together_live.dart` | Create | `LivePlan`, `liveLead`, `livePlanFor` (pure) |
| `lib/features/together/data/together_live_activity.dart` | Create | `LiveActivityStore` seam, `ChannelLiveActivityStore`, `TogetherLiveActivity` (never throws), `liveEnabledKey` |
| `lib/features/together/data/together_device_surfaces.dart` | Create | `clearTogetherDeviceSurfaces()` |
| `lib/features/together/presentation/together_providers.dart` | Modify | `TogetherLiveEnabled` and its provider, `togetherLiveSupportedProvider` |
| `lib/features/together/presentation/widgets/together_settings_sheet.dart` | Modify | "Tonight's plan on my lock screen" toggle |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | `_publishLive` from the agenda and the opt-in listeners |
| `lib/features/safety/domain/services/quick_exit_service.dart` | Modify (shared) | Call `clearTogetherDeviceSurfaces()` |
| `lib/features/auth/presentation/widgets/logout_action.dart` | Modify (shared) | Same, plus invalidate `togetherLiveEnabledProvider` |
| `ios/TogetherWidget/TogetherActivityAttributes.swift` | Create | Shared `ActivityAttributes` (app + widget targets) |
| `ios/TogetherWidget/TogetherLiveActivity.swift` | Create | Lock-screen and Dynamic Island views |
| `ios/TogetherWidget/TogetherWidget.swift` | Modify | `@main` moves to a `WidgetBundle` |
| `ios/Runner/TogetherLiveActivityChannel.swift` | Create | The channel: supported, show, end |
| `ios/Runner/AppDelegate.swift` | Modify (shared) | One registration line |
| `ios/Runner/Info.plist` | Modify | `NSSupportsLiveActivities` |
| `ios/Runner.xcodeproj/project.pbxproj` | Modify (script) | Add files to targets; weak-link ActivityKit |
| Tests | Create/modify | `together_live_test.dart`, `together_live_activity_test.dart`, `together_screen_test.dart`, `together_live_settings_test.dart` |

**Regression risk to flag:**
- Quick exit, logout and AppDelegate are shared. The change in each is one line, swapping in the combined clear or adding a registration.
- `TogetherWidget.swift` loses its `@main`. The widget's `kind` stays `"TogetherWidget"`, so installed widgets survive.

---

### Task 1: Which plan goes on the lock screen (pure Dart)

**Files:**
- Create: `lib/features/together/domain/together_live.dart`
- Test: `test/features/together/together_live_test.dart`

**Interfaces:**
- Consumes: `TogetherItem`, `TogetherItemKind`, `TogetherVisibility`, `TogetherWho` (`lib/features/together/domain/together_item.dart`).
- Produces: `class LivePlan { String title; DateTime start; DateTime end; }` with value equality; `const Duration liveLead`; `LivePlan? livePlanFor({required List<TogetherItem> items, required String? me, required DateTime now})`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 2, 16);

TogetherItem _e(
  String id, {
  required DateTime start,
  DateTime? end,
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String status = 'confirmed',
  TogetherItemKind kind = TogetherItemKind.event,
  bool allDay = false,
}) => TogetherItem(
  kind: kind,
  id: id,
  date: DateTime(start.year, start.month, start.day),
  startsAt: allDay ? null : start,
  endsAt: allDay ? null : end,
  allDay: allDay,
  title: id,
  participantIds: who,
  createdBy: 'ama',
  visibility: visibility,
  status: status,
);

LivePlan? _pick(List<TogetherItem> items) =>
    livePlanFor(items: items, me: 'ama', now: _now);

void main() {
  test('a shared plan tonight shows from 4 hours before it starts', () {
    final dinner = _e(
      'Dinner',
      start: DateTime(2026, 11, 2, 21),
      end: DateTime(2026, 11, 2, 23),
    );
    expect(_pick([dinner]), isNull); // 5 hours away at 16:00
    expect(
      livePlanFor(items: [dinner], me: 'ama', now: DateTime(2026, 11, 2, 17)),
      LivePlan(
        title: 'Dinner',
        start: DateTime(2026, 11, 2, 21),
        end: DateTime(2026, 11, 2, 23),
      ),
    );
    // No end time: an hour.
    final walk = _e('Walk', start: DateTime(2026, 11, 2, 20));
    expect(
      _pick([walk]),
      LivePlan(
        title: 'Walk',
        start: DateTime(2026, 11, 2, 20),
        end: DateTime(2026, 11, 2, 21),
      ),
    );
  });

  test('the plan under way beats a later one; an ended one never shows', () {
    final under = _e('Lunch', start: DateTime(2026, 11, 2, 15), end: DateTime(2026, 11, 2, 17));
    final later = _e('Film', start: DateTime(2026, 11, 2, 18), end: DateTime(2026, 11, 2, 20));
    final ended = _e('Gym', start: DateTime(2026, 11, 2, 14), end: DateTime(2026, 11, 2, 16));
    expect(_pick([later, ended, under])?.title, 'Lunch');
  });

  test('never private, busy-only, just mine, suggested, all-day or a reminder', () {
    final at = DateTime(2026, 11, 2, 18);
    expect(
      _pick([
        _e('Surprise', start: at, visibility: TogetherVisibility.private),
        _e('Busy', start: at, visibility: TogetherVisibility.busyOnly),
        _e('Mine', start: at, who: const ['ama']),
        _e('Theirs', start: at, who: const ['kofi']),
        _e('Maybe', start: at, status: 'proposed'),
        _e('Trip', start: at, allDay: true),
        _e('Call mum', start: at, kind: TogetherItemKind.reminder),
      ]),
      isNull,
    );
    expect(livePlanFor(items: [_e('Dinner', start: at)], me: null, now: _now), isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_live_test.dart`
Expected: FAIL, because `together_live.dart` doesn't exist.

- [ ] **Step 3: Implement**

```dart
/// The lock-screen plan (Together Phase 8c): one shared plan close at hand,
/// as a countdown. Titles as written; no names, no app wording (R2).
library;

import 'together_item.dart';

class LivePlan {
  const LivePlan({required this.title, required this.start, required this.end});

  final String title;
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is LivePlan &&
      other.title == title &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(title, start, end);
}

/// How long before a plan starts it appears. iOS keeps a Live Activity up
/// for at most 8 hours, so the lead leaves room for the plan itself (R3).
const liveLead = Duration(hours: 4);

LivePlan? livePlanFor({
  required List<TogetherItem> items,
  required String? me,
  required DateTime now,
}) {
  if (me == null) return null;
  LivePlan? best;
  for (final i in items) {
    final start = i.startsAt;
    if (i.kind != TogetherItemKind.event || i.allDay || start == null) continue;
    if (i.status != 'confirmed') continue;
    // A surprise or a busy block never reaches the lock screen (spec §3).
    if (i.visibility != TogetherVisibility.shared) continue;
    if (i.whoFor(me) != TogetherWho.us) continue;
    final end = i.endsAt ?? start.add(const Duration(hours: 1));
    if (!end.isAfter(now) || start.difference(now) > liveLead) continue;
    if (best == null || start.isBefore(best.start)) {
      best = LivePlan(title: i.title, start: start, end: end);
    }
  }
  return best;
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `flutter test test/features/together/together_live_test.dart`
Expected: PASS (3 tests).

---

### Task 2: The channel, the setting, and clearing it everywhere

**Files:**
- Create: `lib/features/together/data/together_live_activity.dart`
- Create: `lib/features/together/data/together_device_surfaces.dart`
- Modify: `lib/features/together/presentation/together_providers.dart` (after `togetherWidgetEnabledProvider`)
- Modify: `lib/features/safety/domain/services/quick_exit_service.dart:24`
- Modify: `lib/features/auth/presentation/widgets/logout_action.dart:38-41`
- Test: `test/features/together/together_live_activity_test.dart`

**Interfaces:**
- Consumes: `LivePlan` (Task 1); `TogetherWidgetSync.clear()` (8a/8b).
- Produces:
  - `const liveEnabledKey = 'together_live_enabled'`;
  - `abstract class LiveActivityStore { Future<bool> isSupported(); Future<void> show(LivePlan plan); Future<void> end(); }`;
  - `class TogetherLiveActivity { static LiveActivityStore store; static Future<bool> isSupported(); static Future<void> end(); static Future<void> showIfEnabled(LivePlan? plan); }`;
  - `Future<void> clearTogetherDeviceSurfaces()`;
  - `togetherLiveEnabledProvider` (`AsyncNotifierProvider<TogetherLiveEnabled, bool>`, with `set(bool)`);
  - `togetherLiveSupportedProvider` (`FutureProvider<bool>`);
  - test export `FakeLiveStore`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_widget_sync.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_widget_sync_test.dart' show FakeWidgetStore;

class FakeLiveStore implements LiveActivityStore {
  FakeLiveStore({this.supported = true});
  final bool supported;
  final shown = <LivePlan>[];
  int ends = 0;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<void> show(LivePlan plan) async => shown.add(plan);
  @override
  Future<void> end() async => ends++;
}

class _BrokenStore implements LiveActivityStore {
  @override
  Future<bool> isSupported() async => throw Exception('no channel');
  @override
  Future<void> show(LivePlan plan) async => throw Exception('no channel');
  @override
  Future<void> end() async => throw Exception('no channel');
}

final _plan = LivePlan(
  title: 'Dinner',
  start: DateTime(2026, 11, 2, 19),
  end: DateTime(2026, 11, 2, 21),
);

void main() {
  late FakeLiveStore store;
  setUp(() {
    store = FakeLiveStore();
    TogetherLiveActivity.store = store;
    TogetherWidgetSync.store = FakeWidgetStore();
    SharedPreferences.setMockInitialValues({});
  });

  test('off by default; turning it off ends what is showing', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(togetherLiveEnabledProvider.future), isFalse);
    await c.read(togetherLiveEnabledProvider.notifier).set(true);
    expect(await c.read(togetherLiveEnabledProvider.future), isTrue);
    await c.read(togetherLiveEnabledProvider.notifier).set(false);
    expect(store.ends, 1);
    expect(
      (await SharedPreferences.getInstance()).getBool('together_live_enabled'),
      isFalse,
    );
  });

  test('shows or ends only when this phone opted in (read from storage)', () async {
    await TogetherLiveActivity.showIfEnabled(_plan);
    expect(store.shown, isEmpty);
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    await TogetherLiveActivity.showIfEnabled(_plan);
    expect(store.shown, [_plan]);
    await TogetherLiveActivity.showIfEnabled(null);
    expect(store.ends, 1);
  });

  test('a phone without Live Activities: unsupported, and nothing throws', () async {
    TogetherLiveActivity.store = _BrokenStore();
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    expect(await TogetherLiveActivity.isSupported(), isFalse);
    await TogetherLiveActivity.showIfEnabled(_plan);
    await TogetherLiveActivity.end();
  });

  testWidgets('quick exit ends the lock-screen plan and empties the card', (t) async {
    final widgetStore = FakeWidgetStore();
    TogetherWidgetSync.store = widgetStore;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, _) => Scaffold(
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
    await t.pumpAndSettle();
    expect(find.text('neutral'), findsOneWidget);
    expect(store.ends, 1);
    expect(widgetStore.saved, [null]);
  });
}
```

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/features/together/together_live_activity_test.dart`
Expected: FAIL, because `together_live_activity.dart` is missing.

- [ ] **Step 3: Implement the channel wrapper**

`lib/features/together/data/together_live_activity.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/together_live.dart';

/// This phone's opt-in (Phase 8c R4); off unless set.
const liveEnabledKey = 'together_live_enabled';

/// Where the lock-screen plan goes (a seam so tests never touch iOS).
abstract class LiveActivityStore {
  Future<bool> isSupported();
  Future<void> show(LivePlan plan);
  Future<void> end();
}

/// iOS ActivityKit via ios/Runner/TogetherLiveActivityChannel.swift. On
/// Android the channel isn't registered, so every call throws and is caught.
class ChannelLiveActivityStore implements LiveActivityStore {
  const ChannelLiveActivityStore();

  static const _channel = MethodChannel('attune/together_live');

  @override
  Future<bool> isSupported() async =>
      await _channel.invokeMethod<bool>('supported') ?? false;

  @override
  Future<void> show(LivePlan plan) => _channel.invokeMethod('show', {
    'title': plan.title,
    'start': plan.start.millisecondsSinceEpoch,
    'end': plan.end.millisecondsSinceEpoch,
  });

  @override
  Future<void> end() => _channel.invokeMethod('end');
}

/// Starts, updates or ends the lock-screen plan. Never throws: a phone
/// without Live Activities (or a test without the channel) must not break
/// the caller.
class TogetherLiveActivity {
  static LiveActivityStore store = const ChannelLiveActivityStore();

  /// False off iOS, below iOS 16.2, or with Live Activities off in Settings.
  static Future<bool> isSupported() async {
    try {
      return await store.isSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<void> end() async {
    try {
      await store.end();
    } catch (_) {}
  }

  /// Shows [plan], or ends what's showing when there's none, only if this
  /// phone opted in, read from storage itself so a stale in-memory "on"
  /// (say, after sign-out) never shows anything.
  static Future<void> showIfEnabled(LivePlan? plan) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(liveEnabledKey) ?? false)) return;
      if (plan == null) {
        await store.end();
      } else {
        await store.show(plan);
      }
    } catch (_) {}
  }
}
```

- [ ] **Step 4: Implement the combined clear**

`lib/features/together/data/together_device_surfaces.dart`:

```dart
import 'together_live_activity.dart';
import 'together_widget_sync.dart';

/// Everything Together puts on this phone outside the app (Phase 8): the
/// home-screen card and the lock-screen plan. Quick exit and sign-out empty
/// them all (owner rule: discreet). Never throws.
Future<void> clearTogetherDeviceSurfaces() async {
  await TogetherWidgetSync.clear();
  await TogetherLiveActivity.end();
}
```

- [ ] **Step 5: Implement the providers**

In `together_providers.dart`, add `import '../data/together_live_activity.dart';` next to the other `../data/` imports. Then add this after `togetherWidgetEnabledProvider`:

```dart
/// The lock-screen plan, opted into on this phone (Phase 8c R4). Off by
/// default.
class TogetherLiveEnabled extends AsyncNotifier<bool> {
  static const key = liveEnabledKey;

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> set(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherLiveActivity.end();
    state = AsyncData(on);
  }
}

final togetherLiveEnabledProvider =
    AsyncNotifierProvider<TogetherLiveEnabled, bool>(TogetherLiveEnabled.new);

/// Whether this phone can show it at all (iOS 16.2+, allowed in Settings).
final togetherLiveSupportedProvider = FutureProvider<bool>(
  (ref) => TogetherLiveActivity.isSupported(),
);
```

- [ ] **Step 6: Wire quick exit and sign-out (shared files; re-read them first)**

`quick_exit_service.dart`:
- Replace the import `package:attune/features/together/data/together_widget_sync.dart` with `package:attune/features/together/data/together_device_surfaces.dart`.
- Replace the call and its comment:

```dart
    // The home-screen card and the lock-screen plan show plans: empty them
    // too. Fire-and-forget, after the cover is up, so nothing delays or
    // reveals activation.
    unawaited(clearTogetherDeviceSurfaces());
```

`logout_action.dart`:
- Replace the `together_widget_sync.dart` import with `together_device_surfaces.dart`.
- Change the `show` list to `show togetherWidgetEnabledProvider, togetherLiveEnabledProvider`.
- Replace the clear block with:

```dart
            // The home-screen card and lock-screen plan must not keep
            // showing this person's plans.
            await clearTogetherDeviceSurfaces();
            // …and forget this session's opt-ins (the next person opts in afresh).
            ref.invalidate(togetherWidgetEnabledProvider);
            ref.invalidate(togetherLiveEnabledProvider);
```

- [ ] **Step 7: Run the tests and watch them pass, including 8a's**

Run: `flutter test test/features/together/together_live_activity_test.dart test/features/together/together_widget_sync_test.dart`
Expected: PASS (4 new tests). 8a's quick-exit test still passes, because the widget is still cleared.

---

### Task 3: The setting, and publishing from the hub

**Files:**
- Modify: `lib/features/together/presentation/widgets/together_settings_sheet.dart` (after the "Next plans on my home screen" block)
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (next to `_publishWidget` and its two `ref.listen`s)
- Test: `test/features/together/together_live_settings_test.dart` (new), `test/features/together/together_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 (`livePlanFor`), Task 2 (`TogetherLiveActivity.showIfEnabled`, `togetherLiveEnabledProvider`, `togetherLiveSupportedProvider`, `FakeLiveStore`).
- Produces: none.

- [ ] **Step 1: Write the failing settings test**

`test/features/together/together_live_settings_test.dart`:

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_live_activity.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'together_live_activity_test.dart' show FakeLiveStore;
import 'together_repository_test.dart' show FakeTogetherGateway;

Future<void> _open(WidgetTester t, {required bool supported}) async {
  t.view.physicalSize = const Size(1170, 5200);
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
            }),
          ),
        ),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        togetherLiveSupportedProvider.overrideWith((ref) async => supported),
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TogetherLiveActivity.store = FakeLiveStore();
  });

  testWidgets('the lock-screen plan is off until I turn it on, and says what it shows', (
    t,
  ) async {
    await _open(t, supported: true);
    expect(find.text("Tonight's plan on my lock screen"), findsOneWidget);
    expect(find.textContaining('no names'), findsWidgets);
    final toggle = find.descendant(
      of: find.ancestor(
        of: find.text("Tonight's plan on my lock screen"),
        matching: find.byType(InfoRowWidget),
      ),
      matching: find.byType(Switch),
    );
    expect(t.widget<Switch>(toggle).value, isFalse);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getBool('together_live_enabled'),
      isTrue,
    );
  });

  testWidgets('where Live Activities aren’t available, there is no setting', (t) async {
    await _open(t, supported: false);
    expect(find.text("Tonight's plan on my lock screen"), findsNothing);
  });
}
```

If `InfoRowWidget` doesn't render a `Switch` for `isToggleItem`, match how `together_widget_settings_test.dart` finds and taps the 8a toggle, and use that same finder here.

- [ ] **Step 2: Write the failing hub tests**

In `together_screen_test.dart`:
- add the imports `package:attune/features/together/data/together_live_activity.dart` and `'together_live_activity_test.dart' show FakeLiveStore;`;
- in `_pump`, add a default store so that no test touches the real channel: `TogetherLiveActivity.store = FakeLiveStore();` as the first line of `_pump` (tests that need to read it set their own store after `_pump` is defined. See below);
- add the tests below, next to the 8a widget tests:

```dart
  testWidgets('with the lock-screen plan on, the hub shows tonight’s shared plan', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    final live = FakeLiveStore();
    await _pump(
      t,
      live: live,
      upcoming: [
        _row(
          'd',
          '2026-11-02',
          // 12:00 local; the clock says 09:00, so it's within 4 hours.
          startsAt: DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
          title: 'Lunch',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(live.shown.last.title, 'Lunch');
  });

  testWidgets('with no plan close, the hub ends the lock-screen plan', (t) async {
    SharedPreferences.setMockInitialValues({'together_live_enabled': true});
    final live = FakeLiveStore();
    await _pump(
      t,
      live: live,
      upcoming: [
        _row(
          'd',
          '2026-11-03',
          startsAt: '2026-11-03T19:00:00Z',
          title: 'Dinner',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(live.shown, isEmpty);
    expect(live.ends, greaterThan(0));
  });

  testWidgets('turning the lock-screen plan on shows it straight away', (t) async {
    SharedPreferences.setMockInitialValues({});
    final live = FakeLiveStore();
    await _pump(
      t,
      live: live,
      upcoming: [
        _row(
          'd',
          '2026-11-02',
          startsAt: DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
          title: 'Lunch',
        ),
      ],
    );
    await t.pumpAndSettle();
    expect(live.shown, isEmpty);
    final c = ProviderScope.containerOf(t.element(find.byType(TogetherScreen)));
    await c.read(togetherLiveEnabledProvider.notifier).set(true);
    await t.pumpAndSettle();
    expect(live.shown.last.title, 'Lunch');
  });
```

Give `_pump` the matching parameter `FakeLiveStore? live`, and replace the first-line default with `TogetherLiveActivity.store = live ?? FakeLiveStore();`.

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/features/together/together_live_settings_test.dart test/features/together/together_screen_test.dart`
Expected: FAIL. The setting title is not found, and `live.shown` is empty.

- [ ] **Step 4: Implement the setting**

In `together_settings_sheet.dart`, next to `final widgetOn = …`, add:

```dart
    // Only on phones that can show it, and only once its value is known.
    final liveSupported =
        ref.watch(togetherLiveSupportedProvider).valueOrNull ?? false;
    final liveOn = ref.watch(togetherLiveEnabledProvider).valueOrNull;
```

Then add this directly after the `if (widgetOn != null) ...[ … ],` block:

```dart
          if (liveSupported && liveOn != null) ...[
            AppDivider(),
            InfoRowWidget(
              title: "Tonight's plan on my lock screen",
              subtitle:
                  'Off unless you turn it on. A plan you’re both in shows its '
                  'title, time and a countdown from 4 hours before — no names. '
                  'Anyone who sees your phone can see it; quick exit clears it.',
              icon: Icons.lock_clock_outlined,
              showAvatar: false,
              showDivider: false,
              isToggleItem: true,
              toggleValue: liveOn,
              onToggleChanged:
                  (v) => ref.read(togetherLiveEnabledProvider.notifier).set(v),
            ),
          ],
```

- [ ] **Step 5: Implement publishing from the hub**

In `together_screen.dart`, add the imports `../../data/together_live_activity.dart` and `../../domain/together_live.dart`, matching the file's existing relative-import style. Then add this after `_publishWidget`:

```dart
  Future<void> _publishLive(
    TogetherAgenda? agenda,
    String? me,
    DateTime now,
  ) async {
    if (agenda == null || !mounted) return;
    await TogetherLiveActivity.showIfEnabled(
      livePlanFor(
        items: [
          ...agenda.today,
          for (final d in agenda.week) ...d.items,
          ...agenda.comingUp,
        ],
        me: me,
        now: now,
      ),
    );
  }
```

In `_agenda`, change the agenda listener and add one more listener:

```dart
    // The home-screen card (Phase 8a) and the lock-screen plan (8c):
    // refreshed from what the hub just loaded, only where they're on.
    ref.listen<AsyncValue<TogetherAgenda>>(
      togetherAgendaProvider(relationshipId),
      (_, next) {
        _publishWidget(next.valueOrNull, windows, me, now);
        _publishLive(next.valueOrNull, me, now);
      },
    );
```

```dart
    // Turning the lock-screen plan on shows it now, from what the hub has.
    ref.listen<AsyncValue<bool>>(togetherLiveEnabledProvider, (prev, next) {
      if (next.valueOrNull == true && prev?.valueOrNull != true) {
        _publishLive(
          ref.read(togetherAgendaProvider(relationshipId)).valueOrNull,
          me,
          now,
        );
      }
    });
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `flutter test test/features/together/`
Expected: PASS for everything in the folder, including 8a's widget and settings tests.

---

### Task 4: The iOS Live Activity

**Files:**
- Create: `ios/TogetherWidget/TogetherActivityAttributes.swift`, `ios/TogetherWidget/TogetherLiveActivity.swift`, `ios/Runner/TogetherLiveActivityChannel.swift`
- Modify: `ios/TogetherWidget/TogetherWidget.swift` (the `@main` lines near 106–115), `ios/Runner/AppDelegate.swift` (shared: one line), `ios/Runner/Info.plist`
- Script: `<scratchpad>/add_live_activity.rb` (not committed)

**Interfaces:**
- Consumes: the channel contract from Task 2:
  - `supported` returns a Bool;
  - `show` takes `{title: String, start: ms, end: ms}`;
  - `end`.
- Produces: none.

- [ ] **Step 1: The shared attributes** (compiled into both the Runner and TogetherWidget targets)

```swift
// Shared by the app (which starts it) and the widget extension (which draws
// it). Together Phase 8c: one plan, its title and times; no names.
import ActivityKit
import Foundation

@available(iOS 16.2, *)
struct TogetherActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
  }
}
```

- [ ] **Step 2: The views** (`ios/TogetherWidget/TogetherLiveActivity.swift`)

```swift
// Together lock-screen plan (Phase 8c R2): the title as written, the times,
// a countdown until it starts. No names, no app wording.
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
private struct Countdown: View {
  let state: TogetherActivityAttributes.ContentState

  var body: some View {
    // Counts down to the start and stops at zero; the activity goes stale at
    // the start (the app sets staleDate), when the times take over.
    Text(timerInterval: state.start.addingTimeInterval(-4 * 3600)...state.start, countsDown: true)
      .monospacedDigit()
  }
}

@available(iOS 16.2, *)
private struct LockScreenView: View {
  let state: TogetherActivityAttributes.ContentState
  let started: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(state.title).font(.headline).lineLimit(1)
        Text(state.start...state.end).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      if !started {
        Countdown(state: state)
          .font(.title3)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 96)
      }
    }
    .padding(16)
    .privacySensitive()
  }
}

@available(iOS 16.2, *)
struct TogetherLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TogetherActivityAttributes.self) { context in
      LockScreenView(state: context.state, started: context.isStale)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.title).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.start, style: .time)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if context.isStale {
            Text(context.state.start...context.state.end).foregroundStyle(.secondary)
          } else {
            Countdown(state: context.state)
          }
        }
      } compactLeading: {
        Image(systemName: "calendar")
      } compactTrailing: {
        if context.isStale {
          Text(context.state.start, style: .time).frame(maxWidth: 56)
        } else {
          Countdown(state: context.state).frame(maxWidth: 56)
        }
      } minimal: {
        Image(systemName: "calendar")
      }
    }
  }
}
```

- [ ] **Step 3: The bundle** (`TogetherWidget.swift`; re-read it first)

Remove `@main` from `struct TogetherWidget: Widget`, and change nothing else in that struct (its `kind` stays `"TogetherWidget"`). Then add this at the end of the file:

```swift
@main
struct TogetherWidgets: WidgetBundle {
  var body: some Widget {
    TogetherWidget()
    if #available(iOS 16.2, *) {
      TogetherLiveActivity()
    }
  }
}
```

- [ ] **Step 4: The channel** (`ios/Runner/TogetherLiveActivityChannel.swift`)

```swift
// Together Phase 8c: starts, updates and ends the lock-screen plan. Only the
// app writes it, while it's open; iOS ends it within 8 hours regardless (R3).
import ActivityKit
import Flutter
import Foundation

enum TogetherLiveActivityChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "attune/together_live", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(call.method == "supported" ? false : nil)
        return
      }
      switch call.method {
      case "supported":
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      case "show":
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let start = args["start"] as? NSNumber,
              let end = args["end"] as? NSNumber
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "show expects title, start, end", details: nil))
          return
        }
        let state = TogetherActivityAttributes.ContentState(
          title: title,
          start: Date(timeIntervalSince1970: start.doubleValue / 1000),
          end: Date(timeIntervalSince1970: end.doubleValue / 1000)
        )
        Task { @MainActor in
          await show(state)
          result(nil)
        }
      case "end":
        Task { @MainActor in
          await endAll()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// One activity at most: update the running one, or start one.
  @available(iOS 16.2, *)
  private static func show(_ state: TogetherActivityAttributes.ContentState) async {
    // Stale from the start: the countdown gives way to the plan's times.
    let content = ActivityContent(state: state, staleDate: state.start)
    let all = Activity<TogetherActivityAttributes>.activities
    let running = all.filter { $0.activityState == .active || $0.activityState == .stale }
    if let current = running.first {
      await current.update(content)
      for extra in all where extra.id != current.id {
        await extra.end(nil, dismissalPolicy: .immediate)
      }
    } else {
      _ = try? Activity.request(attributes: TogetherActivityAttributes(), content: content, pushType: nil)
    }
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<TogetherActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
```

- [ ] **Step 5: Register it** (`AppDelegate.swift`; a shared file, so re-read it first and add exactly one line)

Directly before the final `return super.application(application, didFinishLaunchingWithOptions: launchOptions)` in `application(_:didFinishLaunchingWithOptions:)`, add:

```swift
    TogetherLiveActivityChannel.register(with: controller.binaryMessenger)
```

- [ ] **Step 6: Info.plist** (`ios/Runner/Info.plist`; add these inside the top-level `<dict>`)

```xml
	<key>NSSupportsLiveActivities</key>
	<true/>
```

- [ ] **Step 7: Add the files to their targets and weak-link ActivityKit**

Write `<scratchpad>/add_live_activity.rb`:

```ruby
require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |t| t.name == 'Runner' }
widget = project.targets.find { |t| t.name == 'TogetherWidget' }
wgroup = project.main_group['TogetherWidget']
abort('already added') if wgroup.files.any? { |f| f.path == 'TogetherActivityAttributes.swift' }
attrs = wgroup.new_reference('TogetherActivityAttributes.swift')
views = wgroup.new_reference('TogetherLiveActivity.swift')
widget.add_file_references([attrs, views])
runner.add_file_references([attrs])
channel = project.main_group['Runner'].new_reference('TogetherLiveActivityChannel.swift')
runner.add_file_references([channel])
[runner, widget].each do |t|
  t.add_system_framework('ActivityKit')
  bf = t.frameworks_build_phase.files.find { |f| f.display_name == 'ActivityKit.framework' }
  bf.settings = { 'ATTRIBUTES' => ['Weak'] }
end
project.save
puts 'live activity files added; ActivityKit weak-linked'
```

Run: `GEM_HOME=/opt/homebrew/lib/ruby/gems/3.4.0 ruby <scratchpad>/add_live_activity.rb`
Expected: `live activity files added; ActivityKit weak-linked`

- [ ] **Step 8: Build and check the linking**

Run: `flutter build ios --simulator --debug`
Expected: `✓ Built build/ios/iphonesimulator/Runner.app`

Run: `for f in build/ios/iphonesimulator/Runner.app/Runner build/ios/iphonesimulator/Runner.app/Runner.debug.dylib build/ios/iphonesimulator/Runner.app/PlugIns/TogetherWidget.appex/TogetherWidget; do [ -f "$f" ] && echo "$f" && otool -l "$f" | grep -A2 LC_LOAD_WEAK_DYLIB | grep ActivityKit; done`
Expected: an `ActivityKit` line under the Runner binary (or `Runner.debug.dylib`) and under the widget. That shows the weak link, so the app still launches on iOS 14–16.1.

Run: `bash <scratchpad>/check_appex_version.sh`
Expected: `PASS`. Both appex match the app.

---

### Task 5: Spec rulings, full verification, device checklist

- [ ] **Step 1: Add §8.13 after §8.12** in the spec

```markdown
### 8.13 Phase 8c rulings — lock-screen plan (plan `2026-10-14-together-phase8c-live.md`)
- R1: iOS only (Live Activities); Android gets no ongoing notification (quiet by default).
- R2: One confirmed, timed, shared plan we're both in, from 4 hours before it starts until it ends; the earliest wins (one under way beats a later one). The title as written, the times and a countdown; no names, app name, notes or places. Never private or busy-only.
- R3: The app starts, updates and ends it when Together loads (no background start without a push server); iOS ends it within 8 hours regardless.
- R4: Opt-in on this phone, off by default; shown only where the phone supports it and Live Activities are allowed.
- R5: Quick exit, sign-out and "off" end it at once; one function clears every Together surface on the phone.
- R6: Our own channel instead of a package; ActivityKit is weak-linked, so the app stays iOS 14+.
```

- [ ] **Step 2: Full verification**

Run each of the following:
- `flutter test`
- `flutter analyze lib`
- `flutter build apk --debug --target-platform android-arm64`
- `flutter build ios --simulator --debug`
- `bash <scratchpad>/check_appex_version.sh`

Expected: all green. The analyzer shows no new issues in the touched files.

- [ ] **Step 3: Owner device checklist (for the final report)**

1. Use an iPhone on iOS 16.2+, and turn on "Tonight's plan on my lock screen".
   - Make a shared plan starting in 2 hours and open Together.
   - Lock the phone. The title, the times and a countdown should show, with no names.
   - On a phone with a Dynamic Island, check the compact and expanded views.
2. Rename the plan and reopen Together: the activity updates. Cancel it and reopen: it disappears.
3. Use quick exit: it is gone at once. Sign out: it is gone.
4. Turn off Live Activities for Attune in iOS Settings: the setting disappears.
5. Use an iOS 15 device or simulator, if available: the app launches and the setting is hidden.
