# Push Notification Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make push notifications actually reach devices and route on tap — `OneSignalService.initialize()` is currently never called anywhere, and the existing `onNotificationTap` deep-link router has nothing wired to invoke it from a real OS-level notification tap.

**Architecture:** Add a `GlobalKey<NavigatorState>` to the app's `GoRouter` so navigation is possible without a widget's own `BuildContext`. Register `OneSignal.Notifications.addClickListener(...)` inside `OneSignalService.initialize()`, converting each click's `additionalData` payload into an `AppNotification` and routing it through the existing, unchanged `onNotificationTap` config. Call `OneSignalService.initialize()` from app startup, mirroring the exact pattern already used there for two other services.

**Tech Stack:** Flutter, Riverpod, `onesignal_flutter` 5.5.8 (the exact resolved version, confirmed via `pubspec.lock` — all API references below are checked directly against this version's source in `~/.pub-cache/hosted/pub.dev/onesignal_flutter-5.5.8/lib/`), GoRouter.

## Global Constraints

- `onesignal_flutter` 5.5.8's `OneSignalNotifications.addClickListener` already buffers clicks that arrive before any listener is registered (up to 50, oldest dropped past that) and flushes them via a `scheduleMicrotask` the moment the first listener registers (confirmed by reading `onesignal_flutter-5.5.8/lib/src/notifications.dart:19-27,195-225` directly). This means cold-start taps require NO custom queue/drain logic on the app side — only calling `addClickListener` during normal startup is required. Do not add any custom pending-tap storage, `SharedPreferences` flag, or manual buffer.
- `onNotificationTap`'s existing signature — `void Function(AppNotification notification, BuildContext context)?` (`lib/core/notifications/config/feature/notification_config.dart:46-47`) — must NOT change. The in-app inbox's existing call site (`notification_inbox_screen.dart:158`) must keep working unmodified.
- The click listener's two "can't route" cases (`additionalData == null`, no navigator context yet) are silent no-ops, NOT a fallback to `RouteNames.home` — that fallback belongs only inside `onNotificationTap`'s own `switch` for a recognized-but-unmapped `type`, a different failure mode (design spec §4).
- No native platform config (APNs certs, `Info.plist`, `AndroidManifest.xml`) is in scope — this plan is Dart-side wiring only.

---

## File Structure

- **Modify:** `lib/app/routing/app_router.dart` — add `appNavigatorKey`, pass it to `GoRouter(...)`.
- **Modify:** `lib/core/notifications/services/onesignal_service.dart` — register the click listener inside `initialize()`.
- **Modify:** `lib/app/app.dart` — call `OneSignalService.initialize()` from `_AppState.initState()`.
- **Test:** `test/core/notifications/onesignal_click_routing_test.dart` — pure-function test for the `additionalData` → `AppNotification` conversion.

---

### Task 1: Navigator key for context-free navigation

**Files:**
- Modify: `lib/app/routing/app_router.dart:267-268`

**Interfaces:**
- Produces: `final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();` (top-level, in this file) — consumed by Task 2's click listener via `appNavigatorKey.currentContext`.

- [ ] **Step 1: Add the navigator key and pass it to `GoRouter`**

In `lib/app/routing/app_router.dart`, the current function is:

```dart
GoRouter createAppRouter(RoutingNotifier routingNotifier) {
  return GoRouter(
    debugLogDiagnostics: kDebugMode,
    initialLocation: '/_invisible',
    refreshListenable: routingNotifier,
    redirect: (context, state) {
```

Add the key as a top-level declaration immediately above this function, and pass it into the `GoRouter(...)` constructor call:

```dart
/// Lets code with no widget BuildContext of its own (e.g. a push
/// notification tap arriving from the OS, which has no guaranteed
/// context) still navigate. Read via appNavigatorKey.currentContext,
/// which is non-null any time the app has rendered at least one frame.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

GoRouter createAppRouter(RoutingNotifier routingNotifier) {
  return GoRouter(
    navigatorKey: appNavigatorKey,
    debugLogDiagnostics: kDebugMode,
    initialLocation: '/_invisible',
    refreshListenable: routingNotifier,
    redirect: (context, state) {
```

- [ ] **Step 2: Run `flutter analyze`**

Run: `flutter analyze lib/app/routing/app_router.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/app/routing/app_router.dart
git commit -m "feat(notifications): add a navigator key for context-free navigation"
```

Note: no automated test for this task — a single field addition and one constructor argument, with no independently testable behavior of its own (its correctness is exercised by Task 2's test).

---

### Task 2: Click listener registration and routing

**Files:**
- Modify: `lib/core/notifications/services/onesignal_service.dart`
- Test: `test/core/notifications/onesignal_click_routing_test.dart`

**Interfaces:**
- Consumes: `appNavigatorKey` (Task 1, `lib/app/routing/app_router.dart`); `notificationConfigProvider` (existing, `lib/core/notifications/config/feature/notification_config.dart:98`); `AppNotification` (existing, `lib/core/notifications/domain/entities/app_notification.dart` — fields: `id` (`String`, required), `title` (`String`, required), `body` (`String`, required), `data` (`Map<String, dynamic>?`), `isRead` (`bool`, default `false`), `readAt` (`DateTime?`), `createdAt` (`DateTime`, required)).
- Produces: `AppNotification appNotificationFromPushData({required String notificationId, String? title, String? body, Map<String, dynamic>? additionalData})` (a new top-level pure function in `onesignal_service.dart`, extracted so it's unit-testable without the OneSignal SDK) — consumed only within this task's own click listener, not by any later task.

- [ ] **Step 1: Write the failing test for the pure conversion function**

```dart
// test/core/notifications/onesignal_click_routing_test.dart
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts a click event with title, body, and data into an AppNotification', () {
    final notification = appNotificationFromPushData(
      notificationId: 'abc-123',
      title: 'Your partner joined Attune',
      body: 'You can start chatting now.',
      additionalData: {'type': 'invite_accepted', 'screen': 'chat'},
    );

    expect(notification.id, 'abc-123');
    expect(notification.title, 'Your partner joined Attune');
    expect(notification.body, 'You can start chatting now.');
    expect(notification.data, {'type': 'invite_accepted', 'screen': 'chat'});
  });

  test('falls back to empty strings when title/body are null', () {
    final notification = appNotificationFromPushData(
      notificationId: 'xyz-789',
      title: null,
      body: null,
      additionalData: {'type': 'ask2_invite', 'relationship_id': 'rel-1'},
    );

    expect(notification.title, '');
    expect(notification.body, '');
    expect(notification.data?['relationship_id'], 'rel-1');
  });

  test('data is null when additionalData is null', () {
    final notification = appNotificationFromPushData(
      notificationId: 'no-data',
      title: 'Title only',
      body: 'Body only',
      additionalData: null,
    );

    expect(notification.data, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/notifications/onesignal_click_routing_test.dart`
Expected: FAIL — `appNotificationFromPushData` does not exist.

- [ ] **Step 3: Write the pure conversion function and the click listener**

This is the full new content of `lib/core/notifications/services/onesignal_service.dart`, replacing the existing file entirely (the diff is additive — every line of the original `initialize`/`_setupUserListener` body is preserved unchanged; only the click listener registration and the new top-level function are added):

```dart
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OneSignalService {
  final Ref _ref;
  bool _isInitialized = false;

  OneSignalService(this._ref);

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = Environment.oneSignalAppId;
    if (appId == null || appId.isEmpty) {
      return;
    }

    OneSignal.initialize(appId);

    if (Platform.isIOS) {
      await OneSignal.Notifications.requestPermission(true);
    }

    // Wire auth state changes → OneSignal login/logout.
    _setupUserListener();

    // Route a real OS-level notification tap through the same
    // onNotificationTap config the in-app inbox already uses. The SDK
    // buffers any click that arrives before this listener is registered
    // (including a cold-start tap that launches the app) and flushes it
    // once registration completes — no custom queue needed here.
    OneSignal.Notifications.addClickListener((event) {
      final additionalData = event.notification.additionalData;
      if (additionalData == null) return;

      final navigatorContext = appNavigatorKey.currentContext;
      if (navigatorContext == null) return;

      final notification = appNotificationFromPushData(
        notificationId: event.notification.notificationId,
        title: event.notification.title,
        body: event.notification.body,
        additionalData: additionalData,
      );

      final config = _ref.read(notificationConfigProvider);
      config.onNotificationTap?.call(notification, navigatorContext);
    });

    // If the user is already authenticated when the service starts,
    // log in immediately and await completion before marking initialized.
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await OneSignal.login(user.id);
    }

    _isInitialized = true;
  }

  void _setupUserListener() {
    _ref.listen(currentUserProvider, (previous, next) async {
      if (next != null) {
        await OneSignal.login(next.id);
      } else if (previous != null) {
        await OneSignal.logout();
      }
    });
  }
}

/// Converts a OneSignal click event's raw fields into the AppNotification
/// shape onNotificationTap already expects — pure, no OneSignal SDK types
/// in the signature, so it's testable without mocking the plugin. title/
/// body default to '' (matching AppNotification's non-nullable fields)
/// since onNotificationTap's own body only ever reads `.data`, never
/// `.title`/`.body` (confirmed: every existing case in notification_config.dart's
/// switch reads only notification.data), so an empty string here is inert,
/// not a silent data-loss bug.
AppNotification appNotificationFromPushData({
  required String notificationId,
  String? title,
  String? body,
  Map<String, dynamic>? additionalData,
}) {
  return AppNotification(
    id: notificationId,
    title: title ?? '',
    body: body ?? '',
    data: additionalData,
    createdAt: DateTime.now(),
  );
}

final oneSignalServiceProvider = Provider<OneSignalService>((ref) {
  return OneSignalService(ref);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/notifications/onesignal_click_routing_test.dart`
Expected: PASS, 3/3 tests.

- [ ] **Step 5: Run `flutter analyze`**

Run: `flutter analyze lib/core/notifications/services/onesignal_service.dart test/core/notifications/onesignal_click_routing_test.dart`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/core/notifications/services/onesignal_service.dart
git add test/core/notifications/onesignal_click_routing_test.dart
git commit -m "feat(notifications): register OneSignal click listener, route through onNotificationTap"
```

---

### Task 3: Call `OneSignalService.initialize()` at app startup

**Files:**
- Modify: `lib/app/app.dart`

**Interfaces:**
- Consumes: `oneSignalServiceProvider` (Task 2, `lib/core/notifications/services/onesignal_service.dart`).
- Produces: nothing consumed by a later task — this is the final wiring step.

The current `_AppState.initState()` (confirmed by reading the live file before this plan was written) is:

```dart
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(localeNotifierProvider.notifier).initialize();
    });
    // Fire-and-forget preload so first send/receive has no cold-start latency.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(soundServiceProvider).preload();
    });
  }
```

- [ ] **Step 1: Add the OneSignal initialization call**

Add a third `Future.microtask` block, matching the exact style of the existing `localeNotifierProvider` call:

```dart
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(localeNotifierProvider.notifier).initialize();
    });
    Future.microtask(() {
      if (!mounted) return;
      ref.read(oneSignalServiceProvider).initialize();
    });
    // Fire-and-forget preload so first send/receive has no cold-start latency.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(soundServiceProvider).preload();
    });
  }
```

- [ ] **Step 2: Add the import**

Add to `lib/app/app.dart`'s existing import block:

```dart
import 'package:attune/core/notifications/services/onesignal_service.dart';
```

- [ ] **Step 3: Run `flutter analyze`**

Run: `flutter analyze lib/app/app.dart`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/app/app.dart
git commit -m "feat(notifications): initialize OneSignal at app startup"
```

Note: no automated test for this task — a single call added to an existing, already-working `initState` pattern (`localeNotifierProvider`/`soundServiceProvider`), with no new independently-testable logic of its own. Manual verification (requires a real device/build, cannot run in this sandbox) is listed below.

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Build and run the app on a real device or simulator with a valid `ONESIGNAL_APP_ID` configured (`--dart-define=ONESIGNAL_APP_ID=...`); confirm `OneSignal.initialize` is actually reached (no early return from a missing App ID) and the OneSignal dashboard shows the device as subscribed.
- [ ] Send a test push via OneSignal's dashboard (or trigger `accept-invite`/`evaluate-ask2-eligibility` for real) with the app backgrounded (not killed); tap the OS notification banner; confirm the app opens directly to the correct screen per `onNotificationTap`'s switch (e.g. `ask2_invite` → `/ask2/:relationshipId`), not the app's default launch route.
- [ ] Repeat with the app fully force-killed (not just backgrounded) before the tap — this exercises the SDK's pre-registration click buffer (Global Constraints, item 1); confirm the tap still routes correctly once the app finishes launching, not silently dropped.
- [ ] Confirm the in-app notification inbox (`NotificationInboxScreen`) still opens and its own tap-to-navigate behavior is unaffected — this path never touches the new click listener and should be identical to before this plan.
- [ ] Confirm a push notification with no `data` payload at all (or a `type` not present in `onNotificationTap`'s switch) doesn't crash on tap — should silently no-op (no navigator context/data case) or land on `RouteNames.home` (unrecognized-type case), never throw.
