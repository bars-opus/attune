# Push Notification Wiring — Design

**Goal:** Fix two compounding gaps found while tracing the post-invite-acceptance flow: `OneSignalService.initialize()` is never called anywhere in the app (the SDK never starts, so no push notification can ever reach a device), and even if it were called, the app's fully-built `onNotificationTap` deep-link router (`notification_config.dart`) has nothing wired to invoke it from a real OS-level notification tap.

## 1. Scope

In scope:
- Call `OneSignalService.initialize()` at app startup.
- Register `OneSignal.Notifications.addClickListener(...)` inside that initialization, routing every tap through the existing `onNotificationTap` config.
- A `GlobalKey<NavigatorState>` on the app's `GoRouter`, since a notification tap has no guaranteed `BuildContext`.

Out of scope (explicitly deferred):
- Any change to the notification *content* pipeline (`sendOneSignalPush`, `process-scheduled-notifications`, per-feature push payloads) — all already correct, per this session's earlier audits of `accept-invite` and `evaluate-ask2-eligibility`.
- The `notification_inbox_screen.dart` in-app list and its own tap handling — already correct, DB-backed, independent of the OneSignal client SDK, unaffected by this fix.
- Native platform setup (APNs certificate, FCM config, `Info.plist`/`AndroidManifest.xml` entries) — assumed already done as part of the existing `onesignal_flutter` integration; this spec only fixes the Dart-side wiring gap. If push still doesn't arrive after this fix ships, native config is the next thing to check, not something this spec covers.
- The two smaller gaps from the same audit (chat empty-state copy, the missing Day 7 pivot screen) — separate, unrelated fixes.

## 2. Why the SDK's own buffering solves cold start

`onesignal_flutter` 5.5.8 (the version resolved in `pubspec.lock`) already buffers notification clicks that arrive before any listener is registered — confirmed by reading the package source directly (`onesignal_flutter-5.5.8/lib/src/notifications.dart:19-27`, `195-225`). Up to 50 pre-registration clicks are held, then flushed via a `scheduleMicrotask` the moment the first `addClickListener` call registers, fanning out to every registered listener. This means a cold-start tap (app fully killed, the tap itself launches the app) is **not** a special case this spec needs to solve manually — it only requires `addClickListener` to be called during normal app startup, before the user could plausibly interact with anything else. No custom event queue, no `SharedPreferences`-based "pending tap" flag, no drain-on-first-frame logic.

## 3. Initialization

`lib/app/app.dart`'s `_AppState.initState()` already initializes two other services this same way — `localeNotifierProvider` and `soundServiceProvider`, both via `Future.microtask(() { if (!mounted) return; ref.read(...).initialize(); })`. `OneSignalService.initialize()` gets the identical treatment, added as a third call in the same method. No new startup pattern is introduced.

`OneSignalService.initialize()` itself (`lib/core/notifications/services/onesignal_service.dart`) already does everything needed except register the click listener — `OneSignal.initialize(appId)`, iOS permission request, and the auth-state → `OneSignal.login`/`logout` wiring are all correct and unchanged. The click listener registration is added as one more step inside this same method, after `OneSignal.initialize(appId)` and before the function returns.

## 4. The click listener and navigation

```dart
OneSignal.Notifications.addClickListener((event) {
  final data = event.notification.additionalData;
  if (data == null) return;
  final navigatorContext = appNavigatorKey.currentContext;
  if (navigatorContext == null) return;
  final config = _ref.read(notificationConfigProvider);
  config.onNotificationTap?.call(
    AppNotification.fromPushData(data), // exact construction TBD at implementation time — see open question below
    navigatorContext,
  );
});
```

`_ref` is `OneSignalService`'s existing constructor field (`OneSignalService(this._ref)`, already present) — `notificationConfigProvider` is a plain `Provider<NotificationConfig>` (`feature/notification_config.dart:98`), readable synchronously with no new provider wiring needed.

`event.notification.additionalData` (confirmed field name in the resolved package version, `notification.dart:40,247-248`) is the `Map<String, dynamic>` matching exactly what `sendOneSignalPush`'s `data` parameter sent server-side — the same shape `privacySafeData()` already filters for every push in this codebase (`type`, `relationship_id`, and the other allowlisted keys).

The two early `return`s in the listener (`data == null`, `navigatorContext == null`) are deliberately silent drops, not a fallback to `RouteNames.home` — distinct from `onNotificationTap`'s own `default:` case, which handles a *recognized-but-unmapped* `type` by choosing home. Here, `data == null` means the push carried no routable payload at all (nothing to look up a type from), and `navigatorContext == null` means the app hasn't rendered a frame yet (a state `onNotificationTap`'s router can't meaningfully act in either). Both are listener-level "can't call the router at all" conditions, not router-level "don't know where to go" — silently doing nothing is correct; falling back to home would imply the tap was handled when it wasn't.

A new top-level `GlobalKey<NavigatorState> appNavigatorKey` is defined once (natural home: alongside `createAppRouter` in `lib/app/routing/app_router.dart`, since it's routing infrastructure) and passed to `GoRouter(navigatorKey: appNavigatorKey, ...)` at `app_router.dart:268`. `appNavigatorKey.currentContext` gives a valid `BuildContext` any time the app has rendered at least one frame — which, per §2, is guaranteed by the time a buffered or live click event actually reaches this listener, since the buffer flush is a microtask scheduled after `initState`'s synchronous body (including this registration) completes, and `runApp` has already built the widget tree before `_AppState.initState` runs at all.

**`onNotificationTap`'s existing signature is unchanged**: `void Function(AppNotification, BuildContext)`. The in-app inbox's call site (`notification_inbox_screen.dart:158`, `config.onNotificationTap?.call(notification, context)`) keeps passing its own widget `context`, untouched. The new OS-tap call site passes `appNavigatorKey.currentContext!` instead — both are ordinary `BuildContext` values from the router's perspective; `onNotificationTap`'s internals (the `switch` on `notification.data?['type']`, every `GoRouter.of(context).push/go` call) need zero changes.

## 5. Open question — resolved at implementation time

`onNotificationTap`'s first parameter is typed `AppNotification` (`notification_config.dart:70`), a domain entity presumably populated from a DB row when called from the in-app inbox. The OS click listener only has a raw `additionalData` map, not a full `AppNotification` — whichever fields `onNotificationTap`'s body actually reads (confirmed: only `.data?['type']` and `.data?['shop_id']`/`.data?['relationship_id']`, all sourced from `notification.data`) need to be populated on a minimal/synthetic `AppNotification` built from `additionalData` directly. The exact construction (a new named constructor `AppNotification.fromPushData(map)`, or reusing an existing factory) is a plan-level detail, not a design-level one — resolved by reading `AppNotification`'s actual class definition during implementation, not guessed here.

## 6. Testing evidence expected at implementation time

- No live-device test is possible in this sandboxed environment (push delivery requires real APNs/FCM credentials and a physical or simulator device with the app installed) — this is a hard, pre-existing constraint on this whole notification system, not new to this fix.
- A pure-function unit test for whatever `additionalData` → `AppNotification`-equivalent construction is chosen (§5), covering: a `type` key present, a `type` key absent (should not crash `onNotificationTap`'s switch, which already has a `default:` case), and a `relationship_id` key present for the `ask2_invite`/`new_message` cases specifically, since those are the two types this session's own audit exercised.
- Manual verification checklist (device/build required, cannot run in this sandbox): send a test push via OneSignal's dashboard or `send-notification` with the app fully backgrounded, confirm tapping the OS notification banner opens the app directly to the correct screen; repeat with the app fully killed (cold start) to confirm the SDK's own buffering (§2) delivers the click after startup completes, not silently dropped.
