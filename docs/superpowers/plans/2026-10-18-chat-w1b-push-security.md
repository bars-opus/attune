# Chat Wave 1b — Push Notifications & Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every partner message reaches the other phone as a push within ~2 s on iOS and Android, exactly once, only on devices the recipient signed in on, and no client can forge an Attune system notice (review issues #13–#19).

**Architecture:** Three layers change. (1) Device: iOS gains the `aps-environment` entitlement and background remote notifications; the OneSignal wrapper moves behind a small `PushSdk` interface so the permission prompt (both platforms, after sign-in, lock open) and the device's push-subscription registration are unit-tested; sign-out unregisters the device and opts it out. (2) Server push pipeline: the chat outbox worker queues its push through `enqueuePush` with the outbox id as a metadata dedupe key (a unique index, not `source_key`, so the Spec 1b overnight collapse is untouched), gates on `push_enabled` only, and wakes `process-scheduled-notifications` as soon as a row is queued (the minute cron stays as the sweeper); the sender addresses `include_subscription_ids` read from `push_tokens` instead of the `external_id` alias. (3) Database: `push_tokens` is written only through two `SECURITY DEFINER` RPCs keyed on `auth.uid()`; a BEFORE trigger refuses `is_system_notice = true` from the `authenticated`/`anon` roles, and the screenshot notice moves to `send_screenshot_notice`.

**Tech Stack:** Flutter 3.29 / Riverpod 2.6 / onesignal_flutter 5.5.1; Supabase PG17 (pg_net, pg_cron) + Deno 2.8 edge functions (std@0.224 asserts in tests); psql against the scratch DB `attune_spec3a`.

**Spec:** `docs/reviews/2026-10-18-chat-robustness-review.md` (#13–#19), evidence in `docs/reviews/2026-10-18-chat-review/07_server_security_push.md` (H-1, H-2, H-3, M-3, M-5, M-6, M-8) and `V2_media_motion_server_verify.md` (07 section); `lib/architecture/CHAT_SYSTEM_SPEC.md` §9 (push authority, idempotency per `(recipient_id, message_id, type)`, privacy, do-not-send rules); Spec 1b quiet hours in `supabase/migrations/20261017170000_quiet_hours.sql`.

## Global Constraints

- Work on main in the existing working tree (the owner has other uncommitted work; never revert or reformat it). NO COMMITS: replace every "Commit" step with "Checkpoint: run this task's tests and `flutter analyze <touched files>` filtered with `grep -E '^\s*(error|warning) '`; no commit (the owner commits)".
- Never run `dart format` on pre-existing files (repo uses an older formatter; reflowing is a regression). Only new files may be formatted.
- Test-first: every fix starts with a failing test that reproduces the verified failure scenario; watch it fail for the right reason, then fix.
- Flutter tests: `flutter test <path>`; reuse existing harnesses (test/features/chat/support/chat_test_harness.dart, FakeChatRepository, fake cache backends, FakeHaptics). Update old tests only where they encode the wrong behaviour, and say so.
- SQL: new migrations only (never edit an existing migration). Use ONLY your assigned timestamp range (20261019110000–20261019119999). Apply locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`; contract tests in supabase/tests/<name>_contracts.sql in the existing style (BEGIN … RAISE EXCEPTION 'CONTRACT VIOLATED: …' … ROLLBACK; see supabase/tests/home_card_order_contracts.sql and chat_system_contracts.sql), run with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Include a mutation check for each key rule (temporarily break the rule in a transaction and show the contract fails). NEVER use the attune_test database. Never touch the live project; deploying migrations/functions is an owner step — list them at the end under "Owner deploy steps".
- Edge functions (Deno/TS): follow existing patterns in supabase/functions; if the function has Deno tests, add tests; otherwise extract pure logic into a testable module with a Deno test (`deno test` if available — check `which deno`; if not available, say so and make the logic testable via SQL or Dart instead). Here: `deno` 2.8.1 is at `/opt/homebrew/bin/deno`. Run Deno tests **by file**, from `supabase/functions`, as `deno test --allow-read --allow-env --allow-net <file>` (several `index.ts` files call `serve()` at import and print "Listening on http://localhost:8000/" — that is expected pre-test output).
- Owner-only steps (Xcode capabilities, OneSignal dashboard settings, App Store / Apple developer portal) are listed explicitly as "Owner step" with exact instructions; the plan still makes every file change that can be made in the repo (e.g. entitlements/Info.plist edits).
- Display dates via MyDateFormat; user-facing copy plain and warm; respect reduceMotionOf for animations; haptics via hapticsProvider.
- Don't touch ATTUNE_SOUL.md / ATTUNE_THESIS.md. Don't read .env/credentials/keychain.
- Execution order across plans: 1a → 1b → 2 → 3 → 4, sequential on the same tree. Later plans must not assume line numbers from before earlier plans ran; say which files you share with other plans in a "Shared files" note.
- Grants live in a separate `*_grants.sql` migration that `scripts/local_pg_grants.sql` replays after its blanket grant (see its tail); every grants file this plan adds gets an `\i` line appended there.
- Spec 1b must hold throughout: overnight chat pushes (22:00–08:00 recipient local) still collapse into one neutral push at 08:00; the only OneSignal caller stays `process-scheduled-notifications` (`_shared/push_transport.test.ts`).

## Rulings (issues that cannot be fixed as the review proposed)

- **#18 — OneSignal Identity Verification cannot be implemented from this app today.** Evidence: `~/.pub-cache/hosted/pub.dev/onesignal_flutter-5.5.1/lib/onesignal_flutter.dart:64` `login(String externalId)` takes no token; `:72-80` `loginWithJWT` is `@Deprecated('Do not use, this method is not implemented. See https://documentation.onesignal.com/docs/identity-verification for updates.')` (Android-only channel call, iOS no-op); the same is true at the package's `main` branch and in the newest release 5.7.1 (2026-10-16), and OneSignal's Identity Verification page states Flutter/React Native/Unity/Cordova "do not expose `login(externalId, token)` yet" (native Android ≥ 5.9.0 / iOS ≥ 5.8.0 only). Minting a JWT server-side would therefore have no client that can present it, and turning IV on in the dashboard would break the SDK's own user/subscription calls. **Fix adopted instead (Tasks 6–8):** the server stops trusting the `external_id` alias and pushes only to `include_subscription_ids` that the recipient's own authenticated session registered through `register_push_subscription`. That closes H-3 completely without OneSignal's help: the attacker can `login(<victim id>)` all they like, no push is ever addressed to that alias. `OneSignal.login(userId)` is kept (user model / analytics; harmless). **Owner step:** keep Identity Verification OFF; revisit when onesignal_flutter ships `login(externalId, token)` + `addUserJwtInvalidatedListener`.
- **#13 — no Notification Service Extension target in this wave.** Pushes register and display without one; the NSE adds confirmed-delivery analytics, badge increments and rich media, none of which #13–#19 need, and adding an Xcode target by hand-editing `project.pbxproj` is the single most regression-prone change in the iOS project. Badge/grouping (review M-4) is not in this wave. Listed under Owner deploy steps as an optional follow-up done in Xcode.
- **#17 — the dedupe key is in `metadata`, not `source_key`.** `scheduled_notifications_quiet_guard` keeps an inserter's own `source_key` on a chat push and then does **not** collapse it into the 08:00 overnight push (`quiet_hours_contracts.sql` check 10, owner decision D2). A unique index on `metadata->>'outbox_id'` dedupes retries in daytime while the night path (collapse into the existing row, `RETURN NULL`) never reaches the index. Proved in Task 4.

## Review Focus

1. Permission prompt while the Safety PIN screen is up — a person must never see the OS dialog over the lock; it waits for the lock to open (pinned in Task 2's service test "waits for the lock").
2. Same phone, two accounts — after A signs out and B signs in, A's pushes must not reach the phone and B's must (Task 6 contract "re-registration moves the device", Task 8 test "sign-out unregisters and opts out").
3. Worker retry after the push was already sent — exactly one banner (Task 4 contract 1, "after the first was sent, too").
4. Overnight messages after this change — still one neutral push at 08:00, and a retried job at night joins it instead of raising (Task 4 contract 3).
5. A recipient with no registered device (old app build, signed out everywhere) — the row is skipped once, not retried five times a minute (Task 7 `deliver.test.ts` "no device → skipped").

## File Structure

- Create `test/core/ios_push_capability_test.dart` — guard: entitlements/Info.plist/manifest/pbxproj carry the push keys.
- Modify `ios/Runner/Runner.entitlements`, `ios/Runner/Info.plist` — aps-environment, UIBackgroundModes.
- Modify `android/app/src/main/AndroidManifest.xml`, `ios/Podfile` — comments only (the prompt is no longer "on startup").
- Create `lib/core/notifications/services/push_sdk.dart` — `PushSdk` interface + `OneSignalPushSdk`.
- Create `lib/core/notifications/services/push_permission_policy.dart` — pure `shouldAskForPushPermission`.
- Create `lib/core/notifications/data/push_subscription_registry.dart` — RPC client for register/unregister.
- Modify `lib/core/notifications/services/onesignal_service.dart` — uses `PushSdk`; prompt after sign-in; subscription sync; `beforeSignOut()`.
- Modify `lib/features/auth/providers/auth_provider.dart` (`AuthOperations.signOut`) and `lib/features/safety/data/safety_sign_out.dart` — call `beforeSignOut()` while the session is valid.
- Create `test/core/notifications/push_permission_policy_test.dart`, `test/core/notifications/onesignal_service_test.dart`.
- Modify `supabase/functions/process-chat-notification-outbox/index.ts` (+ `index.test.ts`) — `chatPushAllowed`, `enqueuePush` with `dedupedByData`, in-app 23505 tolerance, wake the sender.
- Create `supabase/functions/process-chat-notification-outbox/dispatch.ts` (+ `dispatch.test.ts`) — `wakeScheduledSender`.
- Modify `supabase/functions/_shared/push_queue.ts` (+ `push_queue.test.ts`) — `dedupedByData`.
- Modify `supabase/functions/_shared/onesignal_push.ts` — `include_subscription_ids`, invalid-id parsing, injectable fetch/env. Create `supabase/functions/_shared/onesignal_push.test.ts`.
- Create `supabase/functions/_shared/push_targets.ts` (+ `.test.ts`) — load/deactivate subscription ids.
- Create `supabase/functions/process-scheduled-notifications/deliver.ts` (+ `deliver.test.ts`); modify `process-scheduled-notifications/index.ts` to use it.
- Create migrations `20261019110000_chat_push_dedupe.sql`, `20261019110200_push_subscriptions.sql`, `20261019110210_push_subscriptions_grants.sql`, `20261019110300_system_notice_server_only.sql`, `20261019110310_system_notice_server_only_grants.sql`.
- Create contract tests `supabase/tests/chat_push_dedupe_contracts.sql`, `push_subscriptions_contracts.sql`, `system_notice_contracts.sql`.
- Modify `scripts/local_pg_grants.sql` — two `\i` lines.
- Modify `lib/features/chat/data/repositories/chat_repository.dart`, `supabase_chat_repository.dart`, `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart`, `test/features/chat/support/chat_test_harness.dart`, `test/features/chat/ephemeral_video_viewer_screen_test.dart` — screenshot notice via RPC; client never sends `is_system_notice`. Create `test/features/chat/send_payload_guard_test.dart`.

**Shared files (other plans in this wave touch them too — re-read before editing, design against names not lines):** `lib/features/chat/data/repositories/supabase_chat_repository.dart` and `chat_repository.dart` (Plan 1a: send/outbox; Plan 2: media), `test/features/chat/support/chat_test_harness.dart` (all plans), `lib/features/auth/providers/auth_provider.dart` (Plan 1a may touch sign-out cache clearing), `supabase/functions/process-chat-notification-outbox/index.ts` (Plan 1a does not; Plan 2 does not). This plan owns `onesignal_service.dart`, `onesignal_push.ts`, `process-scheduled-notifications/*` and all migrations in its range.

---

### Task 1: iOS push capability files (#13)

**Files:**
- Create: `test/core/ios_push_capability_test.dart`
- Modify: `ios/Runner/Runner.entitlements`, `ios/Runner/Info.plist`
- Modify (comments): `android/app/src/main/AndroidManifest.xml` (the `POST_NOTIFICATIONS` comment), `ios/Podfile` (the `PERMISSION_NOTIFICATIONS=1` comment)

**Interfaces:**
- Consumes: nothing.
- Produces: the entitlement/plist keys OneSignal iOS needs to call `registerForRemoteNotifications`; a guard test the owner's Xcode step cannot silently undo.

- [ ] **Step 1: Write the failing guard test**

```dart
// test/core/ios_push_capability_test.dart
//
// Chat review #13 (07 H-1): the iOS app was built without the
// aps-environment entitlement, so iOS refused registerForRemoteNotifications
// ("no valid 'aps-environment' entitlement string found") and no iPhone
// could ever receive a push. Same shape as android_manifest_test.dart:
// fakes cannot see these files, so pin them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS can register with APNs: aps-environment entitlement', () {
    final entitlements =
        File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, contains('<key>aps-environment</key>'));
    // development in the repo; Xcode rewrites it to production when
    // exporting with a distribution profile.
    expect(
      entitlements,
      anyOf(
        contains('<string>development</string>'),
        contains('<string>production</string>'),
      ),
    );
  });

  test('iOS declares background remote notifications', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>UIBackgroundModes</key>'));
    expect(plist, contains('<string>remote-notification</string>'));
  });

  test('the Runner target signs with the entitlements file that carries it', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
  });

  test('Android 13+ can be asked for notifications (#15)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
  });
}
```

- [ ] **Step 2: Run it and watch the first two fail**

Run: `flutter test test/core/ios_push_capability_test.dart`
Expected: 2 failing ("iOS can register with APNs" — `aps-environment` not found; "iOS declares background remote notifications" — `UIBackgroundModes` not found), 2 passing.

- [ ] **Step 3: Add the entitlement**

Edit `ios/Runner/Runner.entitlements`: inside `<dict>`, after the `com.apple.developer.associated-domains` array, add:

```xml
	<key>aps-environment</key>
	<string>development</string>
```

(Exactly this key; Xcode's "Push Notifications" capability writes the same two lines. Do not touch `ios/TogetherWidget/TogetherWidget.entitlements` or `ios/Share Extension/Share Extension.entitlements` — extensions do not receive pushes.)

- [ ] **Step 4: Add background remote notifications**

Edit `ios/Runner/Info.plist`: after the `<key>NSSupportsLiveActivities</key><true/>` pair, add:

```xml
		<key>UIBackgroundModes</key>
		<array>
			<string>remote-notification</string>
		</array>
```

- [ ] **Step 5: Correct the two stale comments (no behaviour change)**

In `android/app/src/main/AndroidManifest.xml` replace the `POST_NOTIFICATIONS` comment block text with:

```xml
    <!-- onesignal_flutter: OneSignalService asks for notification permission
         after sign-in, with the app open (OneSignal.Notifications
         .requestPermission). Required from Android 13 (API 33) onward;
         without it the dialog never appears and the OS treats the app as
         notifications-off. -->
```

In `ios/Podfile` change the line `# onesignal_flutter requests notification permission on startup.` to `# onesignal_flutter asks for notification permission after sign-in (OneSignalService).`

- [ ] **Step 6: Run the guard test**

Run: `flutter test test/core/ios_push_capability_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 7: Checkpoint**

Run this task's tests. There are no Dart source changes to analyze. No commit (the owner commits).

**Owner step (Xcode, before the first iOS device test):** open `ios/Runner.xcworkspace` → Runner target → Signing & Capabilities → `+ Capability` → **Push Notifications** (Xcode shows it already satisfied by the entitlement and registers the Push service on the App ID `com.barsopus.attune` under automatic signing) → `+ Capability` → **Background Modes** → tick **Remote notifications** (already in Info.plist; ticking only adds the `SystemCapabilities` bookkeeping to `project.pbxproj`). Then in the Apple Developer portal create an **APNs Auth Key (.p8)** (Keys → + → Apple Push Notifications service) and in OneSignal → Settings → Platforms → **Apple iOS (APNs)** upload the .p8 with Key ID + Team ID + bundle id. Confirm **Google Android (FCM)** has the Firebase service-account JSON. Commit the two iOS files plus whatever Xcode changed in `project.pbxproj`.

---

### Task 2: Ask for notification permission at the right moment, both platforms (#15)

**Files:**
- Create: `lib/core/notifications/services/push_sdk.dart`
- Create: `lib/core/notifications/services/push_permission_policy.dart`
- Modify: `lib/core/notifications/services/onesignal_service.dart`
- Create: `test/core/notifications/push_permission_policy_test.dart`
- Create: `test/core/notifications/onesignal_service_test.dart`

**Interfaces:**
- Consumes: `currentUserProvider` (`lib/features/auth/providers/auth_provider.dart`), `safetyLockProvider` / `safetyLockSeedProvider` / `SafetyLockState` (`lib/features/safety/presentation/safety_lock_controller.dart`).
- Produces:
  - `abstract class PushSdk { void initialize(String appId); Future<void> login(String externalId); Future<void> logout(); bool get permissionGranted; Future<bool> canRequestPermission(); Future<bool> requestPermission(); String? get subscriptionId; bool get optedIn; Future<void> optIn(); Future<void> optOut(); void onSubscriptionChanged(void Function(String? id, bool optedIn) listener); }` and `class OneSignalPushSdk implements PushSdk`.
  - `bool shouldAskForPushPermission({required bool signedIn, required SafetyLockState lock, required bool alreadyGranted, required bool osCanPrompt, required bool askedThisRun})`.
  - `OneSignalService(Ref ref, {PushSdk? sdk, String? platform})` with `@visibleForTesting Future<void> attach()`; Task 8 adds `beforeSignOut()` and the subscription sync to the same class.

- [ ] **Step 1: Write the failing policy test**

```dart
// test/core/notifications/push_permission_policy_test.dart
//
// Chat review #15 (07 M-5): the OS prompt was requested only on iOS, at app
// start. Android 13+ shows no dialog unless asked, so Android phones never
// received a push. The prompt now goes to a signed-in person with the app
// open, once per run, on both platforms.
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool ask({
    bool signedIn = true,
    SafetyLockState lock = SafetyLockState.open,
    bool alreadyGranted = false,
    bool osCanPrompt = true,
    bool askedThisRun = false,
  }) => shouldAskForPushPermission(
    signedIn: signedIn,
    lock: lock,
    alreadyGranted: alreadyGranted,
    osCanPrompt: osCanPrompt,
    askedThisRun: askedThisRun,
  );

  test('a signed-in person with the app open is asked once', () {
    expect(ask(), isTrue);
    expect(ask(askedThisRun: true), isFalse);
  });

  test('never before sign-in', () {
    expect(ask(signedIn: false), isFalse);
  });

  test('never over the Safety lock or while it is still deciding', () {
    expect(ask(lock: SafetyLockState.locked), isFalse);
    expect(ask(lock: SafetyLockState.checking), isFalse);
  });

  test('not when already granted, nor once the OS stopped offering the prompt', () {
    expect(ask(alreadyGranted: true), isFalse);
    expect(ask(osCanPrompt: false), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/core/notifications/push_permission_policy_test.dart`
Expected: compile error — `push_permission_policy.dart` not found.

- [ ] **Step 3: Write the policy**

```dart
// lib/core/notifications/services/push_permission_policy.dart
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';

/// When to show the OS notification prompt, on both platforms (Android 13+
/// shows nothing until asked; chat review #15). Once per app run, to a
/// signed-in person with the app open: never before sign-in, never over
/// the Safety lock (Spec 2), and not once the OS has stopped offering the
/// dialog (a person who said no is not nagged; Settings is theirs).
bool shouldAskForPushPermission({
  required bool signedIn,
  required SafetyLockState lock,
  required bool alreadyGranted,
  required bool osCanPrompt,
  required bool askedThisRun,
}) =>
    signedIn &&
    lock == SafetyLockState.open &&
    !alreadyGranted &&
    osCanPrompt &&
    !askedThisRun;
```

- [ ] **Step 4: Run the policy test**

Run: `flutter test test/core/notifications/push_permission_policy_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 5: Write the PushSdk interface and the OneSignal implementation**

```dart
// lib/core/notifications/services/push_sdk.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// The slice of the OneSignal SDK Attune uses, behind an interface so
/// OneSignalService can be tested without the plugin's static channels.
abstract class PushSdk {
  void initialize(String appId);
  Future<void> login(String externalId);
  Future<void> logout();

  /// OS-level permission as the SDK last saw it.
  bool get permissionGranted;

  /// False once the OS will not show the dialog again (iOS: answered once).
  Future<bool> canRequestPermission();

  /// Shows the OS dialog; never falls back to opening Settings.
  Future<bool> requestPermission();

  /// This device's OneSignal push subscription id; null until the SDK has
  /// registered with APNs/FCM.
  String? get subscriptionId;
  bool get optedIn;
  Future<void> optIn();
  Future<void> optOut();

  /// Fires whenever the subscription changes (first registration, a
  /// reinstall, a token refresh, opt in/out).
  void onSubscriptionChanged(void Function(String? id, bool optedIn) listener);
}

class OneSignalPushSdk implements PushSdk {
  @override
  void initialize(String appId) => OneSignal.initialize(appId);

  @override
  Future<void> login(String externalId) => OneSignal.login(externalId);

  @override
  Future<void> logout() => OneSignal.logout();

  @override
  bool get permissionGranted => OneSignal.Notifications.permission;

  @override
  Future<bool> canRequestPermission() => OneSignal.Notifications.canRequest();

  @override
  Future<bool> requestPermission() =>
      OneSignal.Notifications.requestPermission(false);

  @override
  String? get subscriptionId => OneSignal.User.pushSubscription.id;

  @override
  bool get optedIn => OneSignal.User.pushSubscription.optedIn ?? false;

  @override
  Future<void> optIn() => OneSignal.User.pushSubscription.optIn();

  @override
  Future<void> optOut() => OneSignal.User.pushSubscription.optOut();

  @override
  void onSubscriptionChanged(
    void Function(String? id, bool optedIn) listener,
  ) {
    OneSignal.User.pushSubscription.addObserver((state) {
      listener(state.current.id, state.current.optedIn);
    });
  }
}
```

- [ ] **Step 6: Write the failing service test (prompt timing)**

```dart
// test/core/notifications/onesignal_service_test.dart
//
// Chat review #15/#18: the prompt goes to a signed-in person with the lock
// open, once; the device's push subscription is registered with the server
// and released on sign-out. Drives OneSignalService.attach() with a fake
// PushSdk -- no plugin channels.
import 'package:attune/core/notifications/data/push_subscription_registry.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

class FakePushSdk implements PushSdk {
  final logins = <String>[];
  int logouts = 0;
  int prompts = 0;
  bool granted = false;
  bool canPrompt = true;
  String? subscription;
  bool opted = true;
  int optIns = 0;
  int optOuts = 0;
  void Function(String? id, bool optedIn)? listener;

  @override
  void initialize(String appId) {}
  @override
  Future<void> login(String externalId) async => logins.add(externalId);
  @override
  Future<void> logout() async => logouts++;
  @override
  bool get permissionGranted => granted;
  @override
  Future<bool> canRequestPermission() async => canPrompt;
  @override
  Future<bool> requestPermission() async {
    prompts++;
    granted = true;
    return true;
  }
  @override
  String? get subscriptionId => subscription;
  @override
  bool get optedIn => opted;
  @override
  Future<void> optIn() async {
    optIns++;
    opted = true;
  }
  @override
  Future<void> optOut() async {
    optOuts++;
    opted = false;
  }
  @override
  void onSubscriptionChanged(void Function(String? id, bool optedIn) l) =>
      listener = l;
}

class FakeRegistry implements PushSubscriptionRegistry {
  final registered = <(String, String)>[];
  final unregistered = <String>[];
  Object? failWith;
  @override
  Future<void> register({
    required String subscriptionId,
    required String platform,
  }) async {
    if (failWith != null) throw failWith!;
    registered.add((subscriptionId, platform));
  }
  @override
  Future<void> unregister(String subscriptionId) async {
    if (failWith != null) throw failWith!;
    unregistered.add(subscriptionId);
  }
}

/// A lock whose state the test flips.
class _Lock extends SafetyLockController {
  _Lock(this._initial);
  final SafetyLockState _initial;
  @override
  SafetyLockState build() => _initial;
  void set(SafetyLockState s) => state = s;
}

final _userState = StateProvider<User?>((_) => null);

({ProviderContainer container, OneSignalService service, FakePushSdk sdk, FakeRegistry registry})
    _build({User? user, SafetyLockState lock = SafetyLockState.open}) {
  final sdk = FakePushSdk();
  final registry = FakeRegistry();
  final container = ProviderContainer(
    overrides: [
      _userState.overrideWith((_) => user),
      currentUserProvider.overrideWith((ref) => ref.watch(_userState)),
      safetyLockProvider.overrideWith(() => _Lock(lock)),
      pushSubscriptionRegistryProvider.overrideWithValue(registry),
      oneSignalServiceProvider.overrideWith(
        (ref) => OneSignalService(ref, sdk: sdk, platform: 'ios'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    service: container.read(oneSignalServiceProvider),
    sdk: sdk,
    registry: registry,
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('signed in, lock open: logs in and asks once', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    await t.service.attach();
    expect(t.sdk.logins, ['u1']);
    expect(t.sdk.prompts, 1);
  });

  test('signed out: no prompt; asks after sign-in', () async {
    final t = _build();
    await t.service.attach();
    expect(t.sdk.prompts, 0);
    t.container.read(_userState.notifier).state = _user('u2');
    await _settle();
    expect(t.sdk.logins, ['u2']);
    expect(t.sdk.prompts, 1);
  });

  test('waits for the lock: no prompt while locked, asks when it opens', () async {
    final t = _build(user: _user('u1'), lock: SafetyLockState.locked);
    await t.service.attach();
    expect(t.sdk.prompts, 0);
    (t.container.read(safetyLockProvider.notifier) as _Lock)
        .set(SafetyLockState.open);
    await _settle();
    expect(t.sdk.prompts, 1);
  });

  test('already granted, or the OS will not prompt again: silent', () async {
    final granted = _build(user: _user('u1'));
    granted.sdk.granted = true;
    await granted.service.attach();
    expect(granted.sdk.prompts, 0);

    final refused = _build(user: _user('u1'));
    refused.sdk.canPrompt = false;
    await refused.service.attach();
    expect(refused.sdk.prompts, 0);
  });

  test('sign-out logs the SDK out', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.sdk.logouts, 1);
  });
}
```

(The `PushSubscriptionRegistry` import/override is created in Task 8; until then, this file will not compile. To keep this task independently runnable, in **this** task write the file WITHOUT the `FakeRegistry` class, the two `push_subscription_registry` lines and the `registry` record field; Task 8 adds them back verbatim.)

- [ ] **Step 7: Run it to verify it fails**

Run: `flutter test test/core/notifications/onesignal_service_test.dart`
Expected: compile errors — `OneSignalService` has no named parameter `sdk`, no `attach`.

- [ ] **Step 8: Rewrite OneSignalService around PushSdk**

Replace the top of `lib/core/notifications/services/onesignal_service.dart` (the class up to and including `_setupUserListener`; keep `appNotificationFromPushData` and `oneSignalServiceProvider` as they are) with:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/config/env.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/core/notifications/services/push_sdk.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OneSignalService {
  OneSignalService(this._ref, {PushSdk? sdk, String? platform})
    : _sdk = sdk ?? OneSignalPushSdk(),
      _platform = platform ?? (Platform.isIOS ? 'ios' : 'android');

  final Ref _ref;
  final PushSdk _sdk;
  // Used by Task 8's subscription registration (the ignore goes then).
  // ignore: unused_field
  final String _platform;
  bool _isInitialized = false;
  bool _askedThisRun = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    final appId = Environment.oneSignalAppId;
    if (appId == null || appId.isEmpty) {
      return;
    }

    _sdk.initialize(appId);

    // Route a real OS-level notification tap through the same
    // onNotificationTap config the in-app inbox already uses. The SDK
    // buffers any click that arrives before this listener is registered
    // (including a cold-start tap that launches the app) and flushes it
    // once registration completes — no custom queue needed here.
    OneSignal.Notifications.addClickListener((event) {
      final additionalData = event.notification.additionalData;
      if (additionalData == null) return;

      final notification = appNotificationFromPushData(
        notificationId: event.notification.notificationId,
        title: event.notification.title,
        body: event.notification.body,
        additionalData: additionalData,
      );

      // Spec 2: while the Safety PIN is required (or before the Router has
      // mounted) the tap waits and is replayed on unlock -- never dropped,
      // never shown above the lock (review I5).
      // On iOS the decoy stays in the foreground after a quick exit, so a
      // tap on an earlier notification must wait there too (review I-2).
      final navigatorContext = appNavigatorKey.currentContext;
      if (navigatorContext == null ||
          shouldDeferNotificationTap(
            state: _ref.read(safetyLockProvider),
            path: _currentPath(),
            navigatorReady: true,
          )) {
        _pendingTap = notification;
        return;
      }
      final config = _ref.read(notificationConfigProvider);
      config.onNotificationTap?.call(notification, navigatorContext);
    });

    // Spec 2: no banner over the lock screen or the quick-exit decoy
    // (review I10).
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      if (shouldSuppressForegroundPush(
        _ref.read(safetyLockProvider),
        _currentPath(),
      )) {
        event.preventDefault();
      }
    });

    await attach();
    _isInitialized = true;
  }

  /// Everything that follows the SDK's existence: auth → login/logout, the
  /// permission prompt (chat review #15: after sign-in, lock open, both
  /// platforms — Android 13+ never asked before) and, from Task 8, the
  /// device's push subscription. Separate from initialize() so tests drive
  /// it with a fake PushSdk.
  @visibleForTesting
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _setupUserListener();
    _ref.listen<SafetyLockState>(safetyLockProvider, (_, __) {
      unawaited(_maybeAskForPermission());
    });

    // If the user is already authenticated when the service starts,
    // log in immediately and await completion before marking initialized.
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await _sdk.login(user.id);
      await _maybeAskForPermission();
    }
  }

  bool _attached = false;

  Future<void> _maybeAskForPermission() async {
    final osCanPrompt = await _sdk.canRequestPermission();
    if (!shouldAskForPushPermission(
      signedIn: _ref.read(currentUserProvider) != null,
      lock: _ref.read(safetyLockProvider),
      alreadyGranted: _sdk.permissionGranted,
      osCanPrompt: osCanPrompt,
      askedThisRun: _askedThisRun,
    )) {
      return;
    }
    _askedThisRun = true;
    try {
      await _sdk.requestPermission();
    } catch (_) {
      // A refused or failed prompt is not an error; the OS remembers.
    }
  }

  AppNotification? _pendingTap;

  String _currentPath() {
    try {
      return _ref
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;
    } catch (_) {
      return '';
    }
  }

  /// Delivers a tap that arrived while Attune was locked (Spec 2), and only
  /// into a signed-in, open app (review I-5).
  void replayPendingTap() {
    final notification = _pendingTap;
    final navigatorContext = appNavigatorKey.currentContext;
    if (notification == null || navigatorContext == null) return;
    if (!canReplayNotificationTap(
      signedIn: _ref.read(currentUserProvider) != null,
      state: _ref.read(safetyLockProvider),
      path: _currentPath(),
      navigatorReady: true,
    )) {
      return;
    }
    _pendingTap = null;
    final config = _ref.read(notificationConfigProvider);
    config.onNotificationTap?.call(notification, navigatorContext);
  }

  void _setupUserListener() {
    _ref.listen(currentUserProvider, (previous, next) async {
      if (next != null) {
        await _sdk.login(next.id);
        await _maybeAskForPermission();
      } else if (previous != null) {
        // A tap held for the person who just signed out is theirs, not the
        // next screen's (review I-5).
        _pendingTap = null;
        await _sdk.logout();
      }
    });
  }
}
```

Note the `attach()` guard `_attached`: the test calls `attach()` twice to prove "once per run"; production calls it once from `initialize()`.

- [ ] **Step 9: Run the service test and the existing click-routing test**

Run: `flutter test test/core/notifications/onesignal_service_test.dart test/core/notifications/onesignal_click_routing_test.dart`
Expected: `All tests passed!` (5 + 3 tests)

- [ ] **Step 10: Checkpoint**

Run: `flutter test test/core/notifications/ && flutter analyze lib/core/notifications/services/onesignal_service.dart lib/core/notifications/services/push_sdk.dart lib/core/notifications/services/push_permission_policy.dart test/core/notifications/onesignal_service_test.dart test/core/notifications/push_permission_policy_test.dart | grep -E '^\s*(error|warning) '`
Expected: all tests pass; the grep prints nothing. No commit (the owner commits). (`dart format` is fine on the three NEW files only.)

---

### Task 3: "Relationship Updates" must not gate chat pushes (#16)

**Files:**
- Modify: `supabase/functions/process-chat-notification-outbox/index.ts`
- Test: `supabase/functions/process-chat-notification-outbox/index.test.ts`

**Interfaces:**
- Produces: `export function chatPushAllowed(settings: { push_enabled?: boolean | null } | null | undefined): boolean` in `index.ts`.

- [ ] **Step 1: Add the failing tests**

Append to `supabase/functions/process-chat-notification-outbox/index.test.ts` (and add `chatPushAllowed` to the existing import from `./index.ts`):

```ts
// Chat review #16 (07 M-8): the settings toggle labelled "Relationship
// Updates" (shared-activity pings) also switched off message pushes. Only
// the master push switch gates a chat push.
Deno.test("only the master push switch gates a chat push", () => {
  assertEquals(chatPushAllowed(null), true);
  assertEquals(chatPushAllowed(undefined), true);
  assertEquals(chatPushAllowed({ push_enabled: true }), true);
  assertEquals(chatPushAllowed({ push_enabled: null }), true);
  assertEquals(chatPushAllowed({ push_enabled: false }), false);
});

Deno.test("the worker never reads the Relationship Updates column", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes("booking_reminders"), false);
  assertEquals(src.includes("chatPushAllowed(settings)"), true);
});
```

- [ ] **Step 2: Run to verify failure**

Run (from `supabase/functions`): `deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/index.test.ts`
Expected: FAIL — `chatPushAllowed` is not exported (TS2305) / the source still contains `booking_reminders`.

- [ ] **Step 3: Implement**

In `index.ts`, change the settings select and gate:

```ts
    const { data: settings, error: settingsError } = await supabase
      .from("notification_settings")
      .select("push_enabled, chat_message_preview_enabled")
      .eq("user_id", recipientId)
      .maybeSingle();

    if (settingsError) throw settingsError;

    if (!chatPushAllowed(settings)) {
```

(the body of that `if` — finalize `suppressed_notifications_disabled` and return — stays as is). Add next to `messagePushable`:

```ts
/// Chat review #16: a chat push is gated by the master switch only. The
/// "Relationship Updates" toggle is about shared-activity pings (moments,
/// plans), not messages from a partner; a person who turned it off kept
/// losing message pushes and could not see why.
export function chatPushAllowed(
  settings: { push_enabled?: boolean | null } | null | undefined,
): boolean {
  return settings?.push_enabled !== false;
}
```

- [ ] **Step 4: Run the tests**

Run: `deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/index.test.ts`
Expected: `ok | 4 passed | 0 failed`

- [ ] **Step 5: Checkpoint**

Run: `deno check process-chat-notification-outbox/index.ts` (from `supabase/functions`) — Expected: no errors. No commit (the owner commits).

---

### Task 4: One push per chat outbox job — the database rule (#17)

**Files:**
- Create: `supabase/migrations/20261019110000_chat_push_dedupe.sql`
- Create: `supabase/tests/chat_push_dedupe_contracts.sql`

**Interfaces:**
- Produces: unique indexes `scheduled_notifications_chat_outbox_idx ON scheduled_notifications ((metadata->>'outbox_id')) WHERE metadata ? 'outbox_id'` and `in_app_notifications_chat_outbox_idx ON in_app_notifications (user_id, (data->>'outbox_id')) WHERE data ? 'outbox_id'`. Task 5's worker relies on `23505` from these meaning "already queued".

- [ ] **Step 1: Write the failing contract test**

```sql
-- supabase/tests/chat_push_dedupe_contracts.sql
-- Chat review #17 (07 M-3): a chat outbox job queues at most one push and
-- one in-app notification however often the worker retries, and the
-- overnight collapse (Spec 1b D2) is untouched. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES ('8d170000-0000-0000-0000-0000000000a1')
ON CONFLICT (id) DO NOTHING;
-- Zone unknown first: daytime behaviour (no deferral) until check 3.
INSERT INTO public.users (id, phone, display_name, timezone)
VALUES ('8d170000-0000-0000-0000-0000000000a1', '+233598170001', 'Dedupe A', NULL)
ON CONFLICT (id) DO UPDATE SET timezone = NULL;

-- Queue a chat push exactly as process-chat-notification-outbox does
-- (enqueuePush: metadata carries type/title/body/relationship_id/outbox_id,
-- no source_key). NULL when the quiet guard collapsed it.
CREATE FUNCTION pg_temp.chat_push(p_outbox text, p_at timestamptz DEFAULT now())
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'immediate', p_at, 'pending',
          jsonb_build_object('type', 'new_message', 'title', 'New message in Attune',
                             'body', 'Open Attune to read it.',
                             'relationship_id', '8d170000-0000-0000-0000-000000000011',
                             'outbox_id', p_outbox))
  RETURNING id $$;

-- 1. The same job twice is one push -- before and after the first was sent.
DO $$
DECLARE v1 uuid; v2 uuid;
BEGIN
  v1 := pg_temp.chat_push('job-1');
  IF v1 IS NULL THEN RAISE EXCEPTION 'fixture broken: the first push did not queue'; END IF;
  BEGIN
    v2 := pg_temp.chat_push('job-1');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried chat outbox job queued a second push';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v1;
  BEGIN
    v2 := pg_temp.chat_push('job-1');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry after the push was sent queued it again';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

-- 2. Different jobs are different pushes.
DO $$
BEGIN
  PERFORM pg_temp.chat_push('job-2');
  PERFORM pg_temp.chat_push('job-3');
  IF (SELECT count(*) FROM public.scheduled_notifications
      WHERE metadata->>'outbox_id' IN ('job-2', 'job-3')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two different jobs did not both queue';
  END IF;
END $$;

-- 3. Overnight (Spec 1b D2) still collapses: two jobs at 23:00 Accra make one
--    row at 08:00, and the first job retried at night joins it (no raise).
UPDATE public.users SET timezone = 'Africa/Accra' WHERE id = '8d170000-0000-0000-0000-0000000000a1';
DO $$
DECLARE v_first uuid; v_second uuid; v_retry uuid; v_n int;
BEGIN
  v_first  := pg_temp.chat_push('night-1', '2026-11-10 23:00+00');
  v_second := pg_temp.chat_push('night-2', '2026-11-10 23:05+00');
  v_retry  := pg_temp.chat_push('night-1', '2026-11-10 23:06+00');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE source_key LIKE 'quiet_chat:8d170000-0000-0000-0000-0000000000a1:%';
  IF v_first IS NULL OR v_second IS NOT NULL OR v_retry IS NOT NULL OR v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the overnight collapse changed (first=% second=% retry=% rows=%)',
      v_first, v_second, v_retry, v_n;
  END IF;
  IF (SELECT scheduled_for FROM public.scheduled_notifications WHERE id = v_first) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the collapsed push is not at 08:00 local';
  END IF;
  IF (SELECT metadata->>'quiet_count' FROM public.scheduled_notifications WHERE id = v_first) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the later jobs did not join the 08:00 push';
  END IF;
END $$;

-- 4. In-app: one row per (person, job).
DO $$
BEGIN
  INSERT INTO public.in_app_notifications (user_id, title, body, data)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"new_message","outbox_id":"job-1"}');
  BEGIN
    INSERT INTO public.in_app_notifications (user_id, title, body, data)
    VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"new_message","outbox_id":"job-1"}');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried job wrote a second in-app notification';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  -- Rows without a job key (every other notification type) are not constrained.
  INSERT INTO public.in_app_notifications (user_id, title, body, data)
  VALUES ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"invite_accepted"}'),
         ('8d170000-0000-0000-0000-0000000000a1', 'T', 'B', '{"type":"invite_accepted"}');
END $$;

-- 5. Mutation check: without the index, check 1 would be violated.
SAVEPOINT mutate;
DROP INDEX public.scheduled_notifications_chat_outbox_idx;
DO $$
DECLARE v_dup uuid;
BEGIN
  v_dup := pg_temp.chat_push('job-2');
  IF v_dup IS NULL THEN RAISE EXCEPTION 'mutation check broken: the duplicate was not inserted'; END IF;
  RAISE NOTICE 'mutation check: without scheduled_notifications_chat_outbox_idx a retry queued a second push (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate;

DO $$ BEGIN RAISE NOTICE 'chat_push_dedupe_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_push_dedupe_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: a retried chat outbox job queued a second push` (check 1).

- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261019110000_chat_push_dedupe.sql
--
-- Chat review #17 (07 M-3): one push per chat outbox job, whatever the
-- worker's retries do. process-chat-notification-outbox queued its push,
-- then marked the job done; a failure between the two put the job back to
-- pending and the retry queued a second push with a new id (the OneSignal
-- Idempotency-Key is per queued row, so it did not help). The outbox id
-- already travels in metadata; it is now unique there, and the worker
-- treats a duplicate as "already queued". Same for the in-app copy.
--
-- Why not source_key: scheduled_notifications_quiet_guard keeps an
-- inserter's own source_key and then does NOT collapse that push into the
-- one 08:00 overnight push (quiet_hours_contracts.sql check 10; Spec 1b
-- owner decision D2). A metadata key leaves the collapse untouched: the
-- collapsed row keeps the first job's outbox_id, later jobs return NULL
-- from the guard (no row, no conflict), and a retried first job at night
-- joins the existing row before the index is consulted.
--
-- History first: any double pushes already queued would block the index.
-- The oldest row per job is kept (that is the one that was sent).
DELETE FROM public.scheduled_notifications s
USING public.scheduled_notifications k
WHERE s.metadata ? 'outbox_id' AND k.metadata ? 'outbox_id'
  AND s.metadata->>'outbox_id' = k.metadata->>'outbox_id'
  AND s.id <> k.id
  AND (s.created_at, s.id) > (k.created_at, k.id);

DELETE FROM public.in_app_notifications s
USING public.in_app_notifications k
WHERE s.data ? 'outbox_id' AND k.data ? 'outbox_id'
  AND s.user_id = k.user_id
  AND s.data->>'outbox_id' = k.data->>'outbox_id'
  AND s.id <> k.id
  AND (s.created_at, s.id) > (k.created_at, k.id);

CREATE UNIQUE INDEX IF NOT EXISTS scheduled_notifications_chat_outbox_idx
  ON public.scheduled_notifications ((metadata->>'outbox_id'))
  WHERE metadata ? 'outbox_id';

CREATE UNIQUE INDEX IF NOT EXISTS in_app_notifications_chat_outbox_idx
  ON public.in_app_notifications (user_id, (data->>'outbox_id'))
  WHERE data ? 'outbox_id';
```

- [ ] **Step 4: Apply and run the contract**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019110000_chat_push_dedupe.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_push_dedupe_contracts.sql`
Expected: two `NOTICE` lines ending with `chat_push_dedupe_contracts: all held`, then `ROLLBACK`.

- [ ] **Step 5: Prove Spec 1b is untouched**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/quiet_hours_contracts.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/push_copy_contracts.sql`
Expected: both end in `all held` / `ROLLBACK` with no `CONTRACT VIOLATED`.

- [ ] **Step 6: Checkpoint**

No Dart/TS changes. No commit (the owner commits).

---

### Task 5: Outbox worker — dedupe on retry and wake the sender immediately (#17, #14)

**Files:**
- Modify: `supabase/functions/_shared/push_queue.ts`, `supabase/functions/_shared/push_queue.test.ts`
- Create: `supabase/functions/process-chat-notification-outbox/dispatch.ts`, `dispatch.test.ts`
- Modify: `supabase/functions/process-chat-notification-outbox/index.ts`, `index.test.ts`

**Interfaces:**
- Consumes: `enqueuePush(supabase, push)` (`_shared/push_queue.ts`), `requireEnv(name)` (`_shared/attune_auth.ts`), Task 4's indexes.
- Produces: `QueuedPush.dedupedByData?: boolean`; `wakeScheduledSender({supabaseUrl, serviceRoleKey, fetchImpl?, timeoutMs?}): Promise<"woken" | "failed">` and `senderUrl(supabaseUrl): string` in `dispatch.ts`; `processJob` results carry `queued: true` when a push row was queued.

- [ ] **Step 1: Failing test — enqueuePush tolerates a data-keyed duplicate**

Append to `supabase/functions/_shared/push_queue.test.ts`:

```ts
// Chat review #17: the chat outbox dedupes on metadata.outbox_id (a unique
// index; see 20261019110000), not source_key, so the overnight collapse
// still applies. A duplicate there means "already queued".
Deno.test("a duplicate of a data-keyed push means already queued: no throw", async () => {
  const c = fakeClient({ code: "23505" });
  await enqueuePush(c, { ...push, data: { outbox_id: "o1" }, dedupedByData: true });
  assertEquals(c.rows[0].source_key, null);
});

Deno.test("dedupedByData never sets source_key", async () => {
  const c = fakeClient();
  await enqueuePush(c, { ...push, data: { outbox_id: "o1" }, dedupedByData: true });
  assertEquals(c.rows[0].source_key, null);
  assertEquals((c.rows[0].metadata as Record<string, unknown>).outbox_id, "o1");
});
```

- [ ] **Step 2: Run to verify failure**

Run (from `supabase/functions`): `deno test --allow-read --allow-env --allow-net _shared/push_queue.test.ts`
Expected: FAIL — TS2353 `'dedupedByData' does not exist in type 'QueuedPush'`.

- [ ] **Step 3: Implement in push_queue.ts**

Add to `QueuedPush` after `sourceKey`:

```ts
  /**
   * The caller's `data` carries its own unique key (a unique index on the
   * metadata, e.g. outbox_id -- 20261019110000): a duplicate means the
   * push is already queued and is not an error. Unlike sourceKey this does
   * not opt the push out of the overnight collapse (quiet guard).
   */
  dedupedByData?: boolean;
```

and change the duplicate line to:

```ts
  if ((push.sourceKey || push.dedupedByData) && error.code === "23505") return;
```

Run: `deno test --allow-read --allow-env --allow-net _shared/push_queue.test.ts` — Expected: `ok | 6 passed | 0 failed`.

- [ ] **Step 4: Failing test — the wake**

```ts
// supabase/functions/process-chat-notification-outbox/dispatch.test.ts
// Chat review #14 (07 H-2): after queuing, the worker wakes the sender; a
// failed wake is not an error (the cron sweeps).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { senderUrl, wakeScheduledSender } from "./dispatch.ts";

Deno.test("the sender's URL is under the project's functions host", () => {
  assertEquals(
    senderUrl("https://abc.supabase.co/"),
    "https://abc.supabase.co/functions/v1/process-scheduled-notifications",
  );
});

Deno.test("a wake posts with the service role and reports woken", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const out = await wakeScheduledSender({
    supabaseUrl: "https://abc.supabase.co",
    serviceRoleKey: "srk",
    fetchImpl: (url, init) => {
      seen = { url, init };
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assertEquals(out, "woken");
  assertEquals(seen!.url, "https://abc.supabase.co/functions/v1/process-scheduled-notifications");
  assertEquals(seen!.init.method, "POST");
  const headers = seen!.init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], "Bearer srk");
  assertEquals(headers["apikey"], "srk");
});

Deno.test("a refused, failed or slow wake is reported, never thrown", async () => {
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: () => Promise.resolve(new Response("no", { status: 500 })),
    }),
    "failed",
  );
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: () => Promise.reject(new TypeError("network")),
    }),
    "failed",
  );
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k", timeoutMs: 10,
      fetchImpl: (_url, init) =>
        new Promise((_, reject) =>
          init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")))
        ),
    }),
    "failed",
  );
});
```

Run: `deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/dispatch.test.ts` — Expected: FAIL, module `./dispatch.ts` not found.

- [ ] **Step 5: Write dispatch.ts**

```ts
// supabase/functions/process-chat-notification-outbox/dispatch.ts
//
// Chat review #14 (07 H-2): a chat push used to wait for the once-a-minute
// cron (0-60 s after the message). After queuing, the worker wakes
// process-scheduled-notifications once per run. The sender claims rows
// atomically (status pending -> processing), so a wake racing the cron or
// another wake is safe; a failed wake is not an error -- the cron remains
// the sweeper. Nothing here talks to OneSignal (push_transport.test.ts):
// Spec 1b's quiet-hours and copy guards still see every push.
//
// Awaited (with a timeout) rather than fire-and-forget: the edge runtime
// may end a pending fetch once the response is written, and this worker's
// own callers (pg_net, cron) never wait on it anyway.

export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

export function senderUrl(supabaseUrl: string): string {
  return `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/process-scheduled-notifications`;
}

export async function wakeScheduledSender(opts: {
  supabaseUrl: string;
  serviceRoleKey: string;
  fetchImpl?: Fetch;
  timeoutMs?: number;
}): Promise<"woken" | "failed"> {
  const fetchImpl = opts.fetchImpl ?? ((u, i) => fetch(u, i));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 8000);
  try {
    const res = await fetchImpl(senderUrl(opts.supabaseUrl), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${opts.serviceRoleKey}`,
        "apikey": opts.serviceRoleKey,
      },
      body: JSON.stringify({ reason: "chat_outbox" }),
      signal: controller.signal,
    });
    return res.ok ? "woken" : "failed";
  } catch (_) {
    return "failed";
  } finally {
    clearTimeout(timer);
  }
}
```

Run the dispatch test — Expected: `ok | 3 passed | 0 failed`.

- [ ] **Step 6: Failing source-shape tests for the worker**

Append to `process-chat-notification-outbox/index.test.ts`:

```ts
// Chat review #17/#14: the queued push carries the outbox id as its dedupe
// key (through enqueuePush, never a raw insert), the in-app copy tolerates
// its own duplicate, and the sender is woken after the loop.
Deno.test("the push is queued through enqueuePush, keyed by outbox_id", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes('.from("scheduled_notifications")'), false);
  const call = src.slice(src.indexOf("await enqueuePush(supabase, {"));
  const body = call.slice(0, call.indexOf("});"));
  assertEquals(body.includes("outbox_id: outboxId"), true);
  assertEquals(body.includes("dedupedByData: true"), true);
  assertEquals(body.includes("sourceKey"), false);
});

Deno.test("a duplicate in-app notification is not an error", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes('inAppResult.error.code !== "23505"'), true);
});

Deno.test("the sender is woken once after the loop when a push was queued", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const loopEnd = src.indexOf("return jsonResponse({\n      success: true,");
  const wake = src.indexOf("await wakeScheduledSender(");
  if (wake < 0 || wake > loopEnd) throw new Error("wakeScheduledSender is not awaited before the response");
  assertEquals(src.includes("if (queuedAny)"), true);
});
```

Run: `deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/index.test.ts` — Expected: 3 new FAILs.

- [ ] **Step 7: Change the worker**

In `index.ts`:

Imports:

```ts
import { HttpError, jsonResponse, requireEnv, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { enqueuePush } from "../_shared/push_queue.ts";
import { wakeScheduledSender } from "./dispatch.ts";
```

In `serve`, replace the results loop and response with:

```ts
    const results = [];
    let queuedAny = false;
    for (const job of jobs) {
      const claimed = await claimJob(supabase, String(job.id));
      if (!claimed) continue;
      const result = await processJob(supabase, claimed);
      results.push(result);
      if (result.queued === true) queuedAny = true;
    }

    // Chat review #14: do not leave the push to the minute cron.
    let wake: "woken" | "failed" | "not_needed" = "not_needed";
    if (queuedAny) {
      wake = await wakeScheduledSender({
        supabaseUrl: requireEnv("SUPABASE_URL"),
        serviceRoleKey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
      });
    }

    return jsonResponse({
      success: true,
      processed: results.length,
      wake,
      results,
    });
```

In `processJob`, the in-app insert:

```ts
    const inAppResult = await supabase
      .from("in_app_notifications")
      .insert({
        user_id: recipientId,
        title,
        body,
        data: {
          type: isReaction ? "message_reaction" : "new_message",
          relationship_id: relationship.id,
          outbox_id: outboxId,
        },
      });
    // Chat review #17: a retry after this insert succeeded finds its own row
    // (in_app_notifications_chat_outbox_idx) -- that is not an error.
    if (inAppResult.error && inAppResult.error.code !== "23505") throw inAppResult.error;
```

Replace the whole `const scheduledResult = await supabase.from("scheduled_notifications").insert({...}); if (scheduledResult.error) throw scheduledResult.error;` block with:

```ts
    // Chat review #17: keyed by the outbox id (scheduled_notifications_chat_
    // outbox_idx); a retry after this insert finds its own row and moves on.
    // Through enqueuePush so Spec 1b's guards and conventions apply; no
    // sourceKey, which would opt the push out of the overnight collapse.
    await enqueuePush(supabase, {
      userId: recipientId,
      type: isReaction ? "message_reaction" : "new_message",
      title,
      body,
      data: { relationship_id: relationship.id, outbox_id: outboxId },
      dedupedByData: true,
    });
```

and change that branch's final return to `return { outbox_id: outboxId, status: "completed", queued: true };`. The `const now = new Date().toISOString();` line is no longer used — delete it (keep `title`/`body`). Every other `return {...}` in `processJob` stays as is (no `queued`).

- [ ] **Step 8: Run all three test files and type-check**

Run (from `supabase/functions`):
```bash
deno check process-chat-notification-outbox/index.ts
deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/index.test.ts
deno test --allow-read --allow-env --allow-net process-chat-notification-outbox/dispatch.test.ts
deno test --allow-read --allow-env --allow-net _shared/push_queue.test.ts
deno test --allow-read --allow-env --allow-net _shared/push_transport.test.ts
```
Expected: check clean; `7 passed`, `3 passed`, `6 passed`, `1 passed`; 0 failed each.

- [ ] **Step 9: Checkpoint**

No Dart changes. No commit (the owner commits).

---

### Task 6: Push subscriptions belong to the signed-in session — database (#18)

**Files:**
- Create: `supabase/migrations/20261019110200_push_subscriptions.sql`
- Create: `supabase/migrations/20261019110210_push_subscriptions_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append one `\i`)
- Create: `supabase/tests/push_subscriptions_contracts.sql`

**Interfaces:**
- Produces: `public.register_push_subscription(p_subscription_id text, p_platform text) RETURNS void` and `public.unregister_push_subscription(p_subscription_id text) RETURNS void`, both `SECURITY DEFINER`, `authenticated` may execute; `push_tokens` has no client grants or policies; `push_tokens.token` = OneSignal push subscription id, `platform IN ('ios','android')`, `is_active`. Task 7 reads `push_tokens` with the service role; Task 8 calls the RPCs.

- [ ] **Step 1: Write the failing contract test**

```sql
-- supabase/tests/push_subscriptions_contracts.sql
-- Chat review #18 (07 H-3): a push reaches only devices the recipient's own
-- signed-in session registered. push_tokens is written through two RPCs as
-- auth.uid(); a client cannot write or read it directly; a device moves to
-- whoever signs in on it; sign-out releases it. Every check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d180000-0000-0000-0000-0000000000a1'), ('8d180000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.owner_of(p_sub text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT user_id FROM public.push_tokens WHERE token = p_sub AND is_active $$;

-- 1. A signs in on a phone: its subscription is hers.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios');
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios'); -- idempotent
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') <> '8d180000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: registering did not attach the device to the caller';
  END IF;
END $$;

-- 2. Nobody writes or reads the table directly, and bad input is refused.
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.push_tokens (user_id, token, platform)
    VALUES ('8d180000-0000-0000-0000-0000000000a1', '99999999-2222-4333-8444-555555555555', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote push_tokens directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM count(*) FROM public.push_tokens;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client read push_tokens directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.register_push_subscription('not-a-subscription-id', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-UUID subscription id was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'web');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown platform was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
END $$;

-- 3. The same phone, a new account: the device moves to B; A's unregister
--    of a device that is no longer hers is a no-op.
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.unregister_push_subscription('11111111-2222-4333-8444-555555555555');
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000b2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registration did not move the device to the new account (or A released B''s device)';
  END IF;
END $$;

-- 4. Sign-out: B releases the device; nothing targets it any more.
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
SELECT public.unregister_push_subscription('11111111-2222-4333-8444-555555555555');
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sign-out did not release the device';
  END IF;
END $$;

-- 5. Only the newest ten devices per person stay active.
DO $$
DECLARE i int;
BEGIN
  FOR i IN 1..12 LOOP
    PERFORM public.register_push_subscription(
      format('%s-aaaa-4bbb-8ccc-dddddddddddd', lpad(i::text, 8, '0')), 'android');
  END LOOP;
END $$;
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.push_tokens WHERE user_id = '8d180000-0000-0000-0000-0000000000b2' AND is_active) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: active devices per person are not capped at ten';
  END IF;
  -- All twelve share one updated_at inside this transaction: the device
  -- that just registered must still be the one that survives the cap.
  IF NOT EXISTS (SELECT 1 FROM public.push_tokens
                 WHERE token = '00000012-aaaa-4bbb-8ccc-dddddddddddd' AND is_active) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device that just registered was capped out';
  END IF;
  IF has_function_privilege('anon', 'public.register_push_subscription(text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.unregister_push_subscription(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can touch push subscriptions';
  END IF;
  IF has_table_privilege('anon', 'public.push_tokens', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can read push_tokens';
  END IF;
END $$;

-- 6. Mutation check: with the old open policy and grant back, check 2 is violated.
SAVEPOINT mutate;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO authenticated;
CREATE POLICY users_own_tokens ON public.push_tokens FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
INSERT INTO public.push_tokens (user_id, token, platform)
VALUES ('8d180000-0000-0000-0000-0000000000b2', '88888888-2222-4333-8444-555555555555', 'ios');
DO $$ BEGIN RAISE NOTICE 'mutation check: with the old policy a client wrote push_tokens directly (as expected)'; END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

DO $$ BEGIN RAISE NOTICE 'push_subscriptions_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/push_subscriptions_contracts.sql`
Expected: `ERROR:  function public.register_push_subscription(unknown, unknown) does not exist`.

- [ ] **Step 3: Write the schema migration**

```sql
-- supabase/migrations/20261019110200_push_subscriptions.sql
--
-- Chat review #18 (07 H-3): a push reaches only devices the recipient's own
-- signed-in session registered. The sender targeted the OneSignal alias
-- external_id = user id; anyone with the OneSignal app id (it ships in the
-- binary) and the partner's user id (readable by design) could call
-- OneSignal.login(<that id>) on their own phone and receive every push --
-- an ex, or a controlling partner. OneSignal's remedy, Identity
-- Verification, is not exposed by the Flutter SDK (5.5.1 … 5.7.1:
-- login(externalId) only; loginWithJWT is @Deprecated "not implemented"),
-- so the server stops trusting the alias: push_tokens.token holds the
-- device's OneSignal push subscription id, written only through these RPCs
-- as auth.uid(), and process-scheduled-notifications targets
-- include_subscription_ids from this table.
--
-- A subscription id is a OneSignal-minted UUID known only to the device
-- that owns it. Re-registering it moves it to the caller (the same phone, a
-- new account): the previous account stops receiving on that phone, which
-- is what sign-out must achieve anyway.

COMMENT ON COLUMN public.push_tokens.token IS
  'OneSignal push subscription id of one device (not an APNs/FCM token). Written only by register_push_subscription / unregister_push_subscription (chat review #18).';

-- Whatever is in the table today was written by the old direct-insert path
-- (savePushToken: raw APNs/FCM tokens), never by these RPCs, so none of it
-- is a OneSignal subscription id. Left active it would be handed to
-- OneSignal as include_subscription_ids and fail every push for that
-- person until the invalid-id pruning caught up. Devices re-register on
-- the next app open (OneSignalService._syncSubscription).
UPDATE public.push_tokens SET is_active = false, updated_at = now() WHERE is_active;

CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  IF p_subscription_id IS NULL
     OR p_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
     OR p_platform IS NULL OR p_platform NOT IN ('ios', 'android') THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at, updated_at)
  VALUES (v_uid, lower(p_subscription_id), p_platform, true, now(), now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        is_active = true, updated_at = now();
  -- A phone keeps one live subscription; reinstalls mint new ids. The
  -- newest ten per person stay active so the table cannot grow unbounded.
  -- The device registering right now is never the one capped out (ties on
  -- updated_at are possible inside one transaction, e.g. the contract test).
  UPDATE public.push_tokens t SET is_active = false, updated_at = now()
  WHERE t.user_id = v_uid AND t.is_active
    AND t.token <> lower(p_subscription_id)
    AND t.id NOT IN (SELECT k.id FROM public.push_tokens k
                     WHERE k.user_id = v_uid AND k.is_active
                     ORDER BY k.updated_at DESC, k.id LIMIT 10);
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = lower(p_subscription_id) AND user_id = auth.uid() AND is_active;
$$;
```

- [ ] **Step 4: Write the grants migration and register it locally**

```sql
-- supabase/migrations/20261019110210_push_subscriptions_grants.sql
-- Chat review #18: push_tokens is written only through the RPCs. The old
-- direct policy (users_own_tokens, FOR ALL) let a client write any row
-- shape; nothing in the app used it (savePushToken has no caller).
REVOKE ALL ON public.push_tokens FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS users_own_tokens ON public.push_tokens;
REVOKE ALL ON FUNCTION public.register_push_subscription(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_subscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_subscription(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_subscription(text) TO authenticated;
```

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Chat review #18: push subscriptions are written through RPCs only.
\i supabase/migrations/20261019110210_push_subscriptions_grants.sql
```

- [ ] **Step 5: Apply and run**

Run:
```bash
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019110200_push_subscriptions.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019110210_push_subscriptions_grants.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/push_subscriptions_contracts.sql
```
Expected: the contract ends with `NOTICE:  push_subscriptions_contracts: all held` then `ROLLBACK`, with the mutation NOTICE before it.

- [ ] **Step 6: Nothing else lost its grant**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/service_role_grants_test.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_system_contracts.sql`
Expected: both pass (service_role keeps its explicit grant on `push_tokens` from 20260931140000; `REVOKE … FROM PUBLIC, anon, authenticated` does not touch it).

- [ ] **Step 7: Checkpoint**

No Dart/TS changes. No commit (the owner commits).

---

### Task 7: The sender addresses registered devices, not the alias (#18)

**Files:**
- Modify: `supabase/functions/_shared/onesignal_push.ts`
- Create: `supabase/functions/_shared/onesignal_push.test.ts`
- Create: `supabase/functions/_shared/push_targets.ts`, `push_targets.test.ts`
- Create: `supabase/functions/process-scheduled-notifications/deliver.ts`, `deliver.test.ts`
- Modify: `supabase/functions/process-scheduled-notifications/index.ts`

**Interfaces:**
- Consumes: `push_tokens(user_id, token, is_active)` from Task 6.
- Produces:
  - `sendOneSignalPush({subscriptionIds: string[]; title; body; data?; idempotencyKey?; fetchImpl?; env?}): Promise<{ id: string | null; invalidSubscriptionIds: string[] }>` and `export function invalidIds(result: unknown, targeted: string[]): string[]`.
  - `loadPushSubscriptions(supabase, userId): Promise<string[]>`, `deactivatePushSubscriptions(supabase, tokens): Promise<void>`.
  - `deliverPush(job: {id: string; user_id: string}, copy: {title; body; data}, deps: DeliverDeps): Promise<{status: "sent" | "skipped"; lastError: string | null}>` with `DeliverDeps = { loadSubscriptions; send; deactivate }`.

- [ ] **Step 1: Failing transport test**

```ts
// supabase/functions/_shared/onesignal_push.test.ts
// Chat review #18 (07 H-3): the push is addressed to the recipient's
// registered devices, never to the external_id alias a stranger can claim.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { invalidIds, sendOneSignalPush } from "./onesignal_push.ts";

const env = (n: string) => ({ ONESIGNAL_APP_ID: "app", ONESIGNAL_API_KEY: "key" })[n];

function capture(status = 200, body: unknown = { id: "n1" }) {
  const seen: { url?: string; init?: RequestInit } = {};
  const fetchImpl = (url: string, init: RequestInit) => {
    seen.url = url;
    seen.init = init;
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  return { seen, fetchImpl };
}

Deno.test("targets include_subscription_ids and nothing else", async () => {
  const { seen, fetchImpl } = capture();
  const out = await sendOneSignalPush({
    subscriptionIds: ["s1", "s2"], title: "T", body: "B", data: { type: "new_message" },
    idempotencyKey: "job-1", fetchImpl, env,
  });
  assertEquals(out, { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(seen.url, "https://api.onesignal.com/notifications");
  const sent = JSON.parse(seen.init!.body as string);
  assertEquals(sent.include_subscription_ids, ["s1", "s2"]);
  assertEquals("include_aliases" in sent, false);
  assertEquals("include_external_user_ids" in sent, false);
  assertEquals(sent.target_channel, "push");
  assertEquals((seen.init!.headers as Record<string, string>)["Idempotency-Key"], "job-1");
});

Deno.test("no device: refuses to send rather than widening the target", async () => {
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: [], title: "T", body: "B", fetchImpl: capture().fetchImpl, env }),
    Error, "onesignal_no_subscription",
  );
});

Deno.test("devices OneSignal no longer knows come back for pruning", async () => {
  const gone = capture(200, { id: "n2", errors: { invalid_player_ids: ["s2"] } });
  const out = await sendOneSignalPush({ subscriptionIds: ["s1", "s2"], title: "T", body: "B", fetchImpl: gone.fetchImpl, env });
  assertEquals(out, { id: "n2", invalidSubscriptionIds: ["s2"] });

  const none = capture(200, { id: "", errors: ["All included players are not subscribed"] });
  const out2 = await sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: none.fetchImpl, env });
  assertEquals(out2, { id: null, invalidSubscriptionIds: ["s1"] });
});

Deno.test("invalidIds reads both shapes OneSignal uses", () => {
  assertEquals(invalidIds({ errors: { invalid_subscription_ids: ["a"] } }, ["a", "b"]), ["a"]);
  assertEquals(invalidIds({ errors: { invalid_player_ids: ["b"] } }, ["a", "b"]), ["b"]);
  assertEquals(invalidIds({ errors: ["All included players are not subscribed"] }, ["a", "b"]), ["a", "b"]);
  assertEquals(invalidIds({ errors: ["something else"] }, ["a"]), []);
  assertEquals(invalidIds({}, ["a"]), []);
  assertEquals(invalidIds(null, ["a"]), []);
});

Deno.test("an HTTP failure still throws with the status", async () => {
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: capture(503, {}).fetchImpl, env }),
    Error, "onesignal_503",
  );
  // A 400 that names nothing to prune is a real failure (bad app id, bad
  // payload) and must retry/dead-letter like any other.
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: capture(400, { errors: ["app_id not found"] }).fetchImpl, env }),
    Error, "onesignal_400",
  );
});

Deno.test("a 400 that only names dead subscriptions is a prune, not a failure", async () => {
  // OneSignal has answered both 200 and 400 for "every target is gone"
  // depending on API vintage; either way the row must be skipped once and
  // the devices pruned, never retried five times a minute.
  const gone = capture(400, { errors: { invalid_player_ids: ["s1"] } });
  assertEquals(
    await sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: gone.fetchImpl, env }),
    { id: null, invalidSubscriptionIds: ["s1"] },
  );
  const none = capture(400, { errors: ["All included players are not subscribed"] });
  assertEquals(
    await sendOneSignalPush({ subscriptionIds: ["s1", "s2"], title: "T", body: "B", fetchImpl: none.fetchImpl, env }),
    { id: null, invalidSubscriptionIds: ["s1", "s2"] },
  );
});

Deno.test("the transport source never mentions the alias", async () => {
  const src = await Deno.readTextFile(new URL("./onesignal_push.ts", import.meta.url));
  assertEquals(src.includes("include_aliases"), false);
  assertEquals(src.includes("external_id"), false);
});
```

Run (from `supabase/functions`): `deno test --allow-read --allow-env --allow-net _shared/onesignal_push.test.ts` — Expected: FAIL (TS: `subscriptionIds`/`fetchImpl`/`env` unknown; `invalidIds` not exported).

- [ ] **Step 2: Rewrite onesignal_push.ts**

```ts
// supabase/functions/_shared/onesignal_push.ts
//
// The only OneSignal caller (push_transport.test.ts). Chat review #18: a
// push is addressed to the recipient's registered devices
// (include_subscription_ids, from push_tokens via push_targets.ts), never
// to an alias a stranger can attach to their own phone -- see
// 20261019110200_push_subscriptions.sql.
export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

export type OneSignalSendResult = {
  /** OneSignal's notification id; null when no targeted device was subscribed. */
  id: string | null;
  /** Subscription ids OneSignal no longer knows or that are unsubscribed. */
  invalidSubscriptionIds: string[];
};

export async function sendOneSignalPush(input: {
  subscriptionIds: string[];
  title: string;
  body: string;
  data?: Record<string, unknown>;
  idempotencyKey?: string;
  fetchImpl?: Fetch;
  env?: (name: string) => string | undefined;
}): Promise<OneSignalSendResult> {
  if (input.subscriptionIds.length === 0) throw new Error("onesignal_no_subscription");
  const env = input.env ?? ((name: string) => Deno.env.get(name));
  const appId = requiredEnv(env, "ONESIGNAL_APP_ID");
  const apiKey = requiredEnv(env, "ONESIGNAL_API_KEY");
  const fetchImpl = input.fetchImpl ?? ((u, i) => fetch(u, i));
  const response = await fetchImpl("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Authorization": `Key ${apiKey}`,
      "Content-Type": "application/json",
      ...(input.idempotencyKey
        ? { "Idempotency-Key": input.idempotencyKey }
        : {}),
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: input.subscriptionIds,
      target_channel: "push",
      headings: { en: input.title },
      contents: { en: input.body },
      data: input.data ?? {},
    }),
  });

  const result = await response.json().catch(() => ({}));
  const invalid = invalidIds(result, input.subscriptionIds);
  if (!response.ok) {
    // A 400 whose only complaint is dead targets is a prune (the caller
    // deactivates them and skips the row); anything else is a failure.
    if (response.status === 400 && invalid.length > 0) {
      return { id: null, invalidSubscriptionIds: invalid };
    }
    throw new Error(`onesignal_${response.status}`);
  }
  const id = typeof result.id === "string" && result.id.length > 0 ? result.id : null;
  return { id, invalidSubscriptionIds: invalid };
}

/// OneSignal answers 200 and names unknown targets under
/// errors.invalid_player_ids (legacy name) or errors.invalid_subscription_ids;
/// when none of the targets is subscribed it answers 200 with id "" and
/// errors: ["All included players are not subscribed"]. Either way those
/// devices are gone and must not be targeted again.
export function invalidIds(result: unknown, targeted: string[]): string[] {
  const errors = (result as { errors?: unknown } | null)?.errors;
  if (!errors) return [];
  if (Array.isArray(errors)) {
    return errors.some((e) => typeof e === "string" && /not subscribed/i.test(e)) ? [...targeted] : [];
  }
  if (typeof errors !== "object") return [];
  const e = errors as Record<string, unknown>;
  return [e.invalid_player_ids, e.invalid_subscription_ids]
    .flatMap((v) => (Array.isArray(v) ? v : []))
    .filter((v): v is string => typeof v === "string");
}

function requiredEnv(env: (name: string) => string | undefined, name: string) {
  const value = env(name);
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}
```

Run the transport test — Expected: `ok | 7 passed | 0 failed`. Also run `deno test --allow-read --allow-env --allow-net _shared/push_transport.test.ts` — Expected: still `1 passed` (test files are excluded from its scan).

- [ ] **Step 3: Failing push_targets test**

```ts
// supabase/functions/_shared/push_targets.test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deactivatePushSubscriptions, loadPushSubscriptions } from "./push_targets.ts";

function fakeClient(rows: Record<string, unknown>[] | null, error: { code?: string } | null = null) {
  const calls: Record<string, unknown>[] = [];
  const builder = {
    select(cols: string) { calls.push({ select: cols }); return builder; },
    eq(col: string, v: unknown) { calls.push({ eq: [col, v] }); return builder; },
    update(patch: Record<string, unknown>) { calls.push({ update: patch }); return builder; },
    in(col: string, v: unknown) { calls.push({ in: [col, v] }); return Promise.resolve({ error }); },
    then(resolve: (v: unknown) => void) { resolve({ data: rows, error }); },
  };
  return { calls, from(table: string) { calls.push({ from: table }); return builder; } };
}

const s1 = "11111111-2222-4333-8444-555555555551";
const s2 = "11111111-2222-4333-8444-555555555552";

Deno.test("loads the person's active device subscriptions only", async () => {
  // A OneSignal subscription id is a UUID. Anything else in the column is a
  // leftover raw APNs/FCM token from the retired savePushToken path (the
  // migration deactivates those, this is the belt to its braces): never
  // handed to OneSignal, where it would 400 the whole send.
  const c = fakeClient([{ token: s1 }, { token: s2 }, { token: "" }, { token: "fcm:legacy-token-abc" }]);
  assertEquals(await loadPushSubscriptions(c, "u1"), [s1, s2]);
  assertEquals(c.calls[0], { from: "push_tokens" });
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ eq: ["user_id", "u1"] })), true);
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ eq: ["is_active", true] })), true);
});

Deno.test("a read error is an error (the push is retried, not silently skipped)", async () => {
  await assertRejects(() => loadPushSubscriptions(fakeClient(null, { code: "42501" }), "u1"), Error, "push_targets_failed:42501");
});

Deno.test("pruning marks the named devices inactive and never throws", async () => {
  const c = fakeClient(null);
  await deactivatePushSubscriptions(c, [s2]);
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ in: ["token", [s2]] })), true);
  await deactivatePushSubscriptions(fakeClient(null, { code: "x" }), [s2]);
  const untouched = fakeClient(null);
  await deactivatePushSubscriptions(untouched, []);
  assertEquals(untouched.calls, []);
});
```

Run: `deno test --allow-read --allow-env --allow-net _shared/push_targets.test.ts` — Expected: FAIL, `./push_targets.ts` not found.

- [ ] **Step 4: Write push_targets.ts**

```ts
// supabase/functions/_shared/push_targets.ts
//
// Chat review #18: which devices a push may go to -- the recipient's own
// registered OneSignal subscriptions (push_tokens, written only by
// register_push_subscription as auth.uid()).

// deno-lint-ignore no-explicit-any
type Client = { from: (table: string) => any };

/** OneSignal subscription ids are UUIDs; register_push_subscription enforces it. */
const SUBSCRIPTION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function loadPushSubscriptions(supabase: Client, userId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("push_tokens")
    .select("token")
    .eq("user_id", userId)
    .eq("is_active", true);
  if (error) throw new Error(`push_targets_failed:${error.code ?? "unknown"}`);
  return ((data ?? []) as { token?: unknown }[])
    .map((r) => r.token)
    .filter((t): t is string => typeof t === "string" && SUBSCRIPTION_ID.test(t));
}

/** A device OneSignal no longer knows is not targeted again. Never throws. */
export async function deactivatePushSubscriptions(supabase: Client, tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  const { error } = await supabase
    .from("push_tokens")
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .in("token", tokens);
  if (error) console.error("deactivate push subscriptions failed", error.code ?? "unknown");
}
```

Run the push_targets test — Expected: `ok | 3 passed | 0 failed`.

- [ ] **Step 5: Failing deliver test**

```ts
// supabase/functions/process-scheduled-notifications/deliver.test.ts
// Chat review #18: a push goes to registered devices; a person with none is
// skipped once (never retried five times a minute); gone devices are pruned.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deliverPush } from "./deliver.ts";

const job = { id: "j1", user_id: "u1" };
const copy = { title: "T", body: "B", data: { type: "new_message" } };

function deps(subs: string[], result: { id: string | null; invalidSubscriptionIds: string[] } | Error) {
  const sent: unknown[] = [];
  const pruned: string[][] = [];
  return {
    sent,
    pruned,
    deps: {
      loadSubscriptions: (_u: string) => Promise.resolve(subs),
      send: (input: unknown) => {
        sent.push(input);
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      },
      deactivate: (ids: string[]) => {
        pruned.push(ids);
        return Promise.resolve();
      },
    },
  };
}

Deno.test("sends to every registered device with the row id as idempotency key", async () => {
  const d = deps(["s1", "s2"], { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(await deliverPush(job, copy, d.deps), { status: "sent", lastError: null });
  assertEquals(d.sent, [{ subscriptionIds: ["s1", "s2"], title: "T", body: "B", data: { type: "new_message" }, idempotencyKey: "j1" }]);
  assertEquals(d.pruned, []);
});

Deno.test("no device → skipped, nothing sent", async () => {
  const d = deps([], { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(await deliverPush(job, copy, d.deps), { status: "skipped", lastError: "no_push_subscription" });
  assertEquals(d.sent, []);
});

Deno.test("gone devices are pruned; none left subscribed → skipped", async () => {
  const some = deps(["s1", "s2"], { id: "n1", invalidSubscriptionIds: ["s2"] });
  assertEquals(await deliverPush(job, copy, some.deps), { status: "sent", lastError: null });
  assertEquals(some.pruned, [["s2"]]);

  const none = deps(["s1"], { id: null, invalidSubscriptionIds: ["s1"] });
  assertEquals(await deliverPush(job, copy, none.deps), { status: "skipped", lastError: "no_subscribed_device" });
  assertEquals(none.pruned, [["s1"]]);
});

Deno.test("a transport failure propagates (the worker's retry path)", async () => {
  const d = deps(["s1"], new Error("onesignal_503"));
  await assertRejects(() => deliverPush(job, copy, d.deps), Error, "onesignal_503");
});
```

Run: `deno test --allow-read --allow-env --allow-net process-scheduled-notifications/deliver.test.ts` — Expected: FAIL, `./deliver.ts` not found.

- [ ] **Step 6: Write deliver.ts**

```ts
// supabase/functions/process-scheduled-notifications/deliver.ts
//
// Chat review #18: one queued row → the recipient's registered devices.
// Pure orchestration over injected pieces so it is testable without
// OneSignal or Postgres; index.ts supplies the real ones.

export type DeliverDeps = {
  loadSubscriptions: (userId: string) => Promise<string[]>;
  send: (input: {
    subscriptionIds: string[];
    title: string;
    body: string;
    data: Record<string, unknown>;
    idempotencyKey: string;
  }) => Promise<{ id: string | null; invalidSubscriptionIds: string[] }>;
  deactivate: (ids: string[]) => Promise<void>;
};

export type DeliverOutcome = { status: "sent" | "skipped"; lastError: string | null };

export async function deliverPush(
  job: { id: string; user_id: string },
  copy: { title: string; body: string; data: Record<string, unknown> },
  deps: DeliverDeps,
): Promise<DeliverOutcome> {
  const subscriptionIds = await deps.loadSubscriptions(job.user_id);
  // Nobody registered (signed out everywhere, or an app build before #18):
  // skipped once, not retried -- a retry would find the same nothing.
  if (subscriptionIds.length === 0) return { status: "skipped", lastError: "no_push_subscription" };
  const result = await deps.send({ subscriptionIds, ...copy, idempotencyKey: job.id });
  if (result.invalidSubscriptionIds.length > 0) await deps.deactivate(result.invalidSubscriptionIds);
  if (result.id === null) return { status: "skipped", lastError: "no_subscribed_device" };
  return { status: "sent", lastError: null };
}
```

Run the deliver test — Expected: `ok | 4 passed | 0 failed`.

- [ ] **Step 7: Wire the sender**

In `process-scheduled-notifications/index.ts`:

Imports:

```ts
import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";
import { deactivatePushSubscriptions, loadPushSubscriptions } from "../_shared/push_targets.ts";
import { deliverPush } from "./deliver.ts";
```

Replace the block from `await sendOneSignalPush({` through `processed++;` with:

```ts
        // Chat review #18: to the person's registered devices only.
        const outcome = await deliverPush(
          { id: String(job.id), user_id: String(job.user_id) },
          { title, body, data },
          {
            loadSubscriptions: (userId) => loadPushSubscriptions(supabase, userId),
            send: (input) => sendOneSignalPush(input),
            deactivate: (ids) => deactivatePushSubscriptions(supabase, ids),
          },
        );
        await finish(supabase, job.id, outcome.status, job.retry_count, outcome.lastError);
        if (outcome.status === "sent") processed++;
```

Everything else in the file (claim, bounced-claim skip, `finish`, `privacySafeData`, the catch/retry path) stays unchanged.

- [ ] **Step 8: Run every sender/transport test and type-check**

Run (from `supabase/functions`):
```bash
deno check process-scheduled-notifications/index.ts
for f in process-scheduled-notifications/deliver.test.ts process-scheduled-notifications/claim_recheck.test.ts process-scheduled-notifications/together_event_data.test.ts _shared/onesignal_push.test.ts _shared/push_targets.test.ts _shared/push_transport.test.ts; do deno test --allow-read --allow-env --allow-net $f 2>&1 | grep -E "passed|failed" | tail -1; done
```
Expected: check clean; six lines each `… passed | 0 failed`.

- [ ] **Step 9: Checkpoint**

No Dart changes. No commit (the owner commits).

---

### Task 8: The app registers its device after sign-in and releases it on sign-out (#18)

**Files:**
- Create: `lib/core/notifications/data/push_subscription_registry.dart`
- Modify: `lib/core/notifications/services/onesignal_service.dart`
- Modify: `lib/features/auth/providers/auth_provider.dart` (`AuthOperations.signOut`)
- Modify: `lib/features/safety/data/safety_sign_out.dart`
- Modify: `test/core/notifications/onesignal_service_test.dart`

**Interfaces:**
- Consumes: Task 2's `PushSdk`/`OneSignalService`, Task 6's RPCs, `supabaseClientProvider` (`lib/features/auth/providers/auth_provider.dart`).
- Produces: `abstract class PushSubscriptionRegistry { Future<void> register({required String subscriptionId, required String platform}); Future<void> unregister(String subscriptionId); }`, `pushSubscriptionRegistryProvider`, `OneSignalService.beforeSignOut()`.

- [ ] **Step 1: Add the failing tests**

In `test/core/notifications/onesignal_service_test.dart` add back the pieces Task 2 left out (the `push_subscription_registry.dart` import, the `FakeRegistry` class, the `registry` record field and the `pushSubscriptionRegistryProvider.overrideWithValue(registry)` override — exactly as printed in Task 2 Step 6), then append inside `main()`:

```dart
  test('a signed-in device is registered with the server', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await t.service.attach();
    expect(t.registry.registered, [('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'ios')]);
  });

  test('a subscription that appears later (after the OS prompt) is registered too', () async {
    final t = _build(user: _user('u1'));
    await t.service.attach();
    expect(t.registry.registered, isEmpty);
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    t.sdk.listener!('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', true);
    await _settle();
    expect(t.registry.registered.length, 1);
    // The same id again is not re-sent.
    t.sdk.listener!('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', true);
    await _settle();
    expect(t.registry.registered.length, 1);
  });

  test('sign-out unregisters and opts the device out, then logs out', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await t.service.attach();
    await t.service.beforeSignOut();
    expect(t.registry.unregistered, ['aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee']);
    expect(t.sdk.optOuts, 1);
    t.container.read(_userState.notifier).state = null;
    await _settle();
    expect(t.sdk.logouts, 1);
  });

  test('the device still opts out when the server call fails (offline sign-out)', () async {
    final t = _build(user: _user('u1'));
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    await t.service.attach();
    t.registry.failWith = StateError('offline');
    await t.service.beforeSignOut();
    expect(t.sdk.optOuts, 1);
  });

  test('the next account on the same phone opts back in and registers', () async {
    final t = _build();
    t.sdk.subscription = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    t.sdk.opted = false;
    t.sdk.granted = true;
    await t.service.attach();
    t.container.read(_userState.notifier).state = _user('u2');
    await _settle();
    expect(t.sdk.optIns, 1);
    expect(t.registry.registered, [('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'ios')]);
    expect(t.sdk.prompts, 0, reason: 'permission already granted: no dialog');
  });
```

Run: `flutter test test/core/notifications/onesignal_service_test.dart` — Expected: compile errors (`push_subscription_registry.dart` missing, no `beforeSignOut`).

- [ ] **Step 2: Write the registry**

```dart
// lib/core/notifications/data/push_subscription_registry.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which OneSignal device subscription belongs to the
/// signed-in person (chat review #18): the server pushes only to these,
/// never to the external_id alias. Both calls run as auth.uid() server-side
/// (register_push_subscription / unregister_push_subscription).
abstract class PushSubscriptionRegistry {
  Future<void> register({
    required String subscriptionId,
    required String platform,
  });
  Future<void> unregister(String subscriptionId);
}

class SupabasePushSubscriptionRegistry implements PushSubscriptionRegistry {
  SupabasePushSubscriptionRegistry(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register({
    required String subscriptionId,
    required String platform,
  }) => _client.rpc(
    'register_push_subscription',
    params: {'p_subscription_id': subscriptionId, 'p_platform': platform},
  );

  @override
  Future<void> unregister(String subscriptionId) => _client.rpc(
    'unregister_push_subscription',
    params: {'p_subscription_id': subscriptionId},
  );
}

final pushSubscriptionRegistryProvider = Provider<PushSubscriptionRegistry>(
  (ref) => SupabasePushSubscriptionRegistry(ref.watch(supabaseClientProvider)),
);
```

- [ ] **Step 3: Extend OneSignalService**

In `onesignal_service.dart` add the import `import 'package:attune/core/notifications/data/push_subscription_registry.dart';`, remove the `// ignore: unused_field` comment above `_platform`, and:

In `attach()`, after `_setupUserListener();` add:

```dart
    _sdk.onSubscriptionChanged((id, optedIn) {
      if (optedIn && id != null && id.isNotEmpty) unawaited(_syncSubscription());
    });
```

and change the signed-in branch at the end of `attach()` to:

```dart
    final user = _ref.read(currentUserProvider);
    if (user != null) {
      await _onSignedIn(user.id);
    }
```

In `_setupUserListener`, replace `await _sdk.login(next.id); await _maybeAskForPermission();` with `await _onSignedIn(next.id);`.

Add these members:

```dart
  /// The subscription id the server holds for this run (null = not sent).
  String? _registeredSubscription;

  Future<void> _onSignedIn(String userId) async {
    _registeredSubscription = null;
    await _sdk.login(userId);
    await _maybeAskForPermission();
    // A previous sign-out on this phone opted the device out; a granted
    // permission means optIn() shows no dialog.
    if (!_sdk.optedIn && _sdk.permissionGranted) {
      try {
        await _sdk.optIn();
      } catch (_) {}
    }
    await _syncSubscription();
  }

  /// Chat review #18: the server pushes only to devices registered by the
  /// signed-in session. Sent once per (run, subscription id).
  Future<void> _syncSubscription() async {
    final user = _ref.read(currentUserProvider);
    final id = _sdk.subscriptionId;
    if (user == null || id == null || id.isEmpty) return;
    if (_registeredSubscription == id) return;
    try {
      await _ref
          .read(pushSubscriptionRegistryProvider)
          .register(subscriptionId: id, platform: _platform);
      _registeredSubscription = id;
    } catch (e) {
      // Retried on the next subscription change or sign-in; until then this
      // phone simply gets no push (never someone else's).
      debugPrint('push subscription register failed: ${e.runtimeType}');
    }
  }

  /// Called while the session is still valid, before auth sign-out: the
  /// server forgets this device, and the device stops receiving even if
  /// that call failed (offline sign-out). The SDK logout follows from the
  /// auth listener.
  Future<void> beforeSignOut() async {
    final id = _sdk.subscriptionId;
    if (id != null && id.isNotEmpty) {
      try {
        // Bounded: an offline sign-out must not hang on this RPC. The
        // opt-out below still stops the device receiving.
        await _ref
            .read(pushSubscriptionRegistryProvider)
            .unregister(id)
            .timeout(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('push subscription unregister failed: ${e.runtimeType}');
      }
    }
    _registeredSubscription = null;
    try {
      await _sdk.optOut();
    } catch (_) {}
  }
```

- [ ] **Step 4: Call it from both sign-out paths**

`lib/features/auth/providers/auth_provider.dart` — add `import 'package:attune/core/notifications/services/onesignal_service.dart';` and in `AuthOperations.signOut()`, immediately before `final authService = ref.read(authServiceProvider);`:

```dart
      // Chat review #18: release this device's push subscription while the
      // session can still prove whose it is. Best-effort; sign-out proceeds.
      try {
        await ref.read(oneSignalServiceProvider).beforeSignOut();
      } catch (e) {
        debugPrint('⚠️ [AUTH] push unregister failed on sign-out: ${e.runtimeType}');
      }
```

`lib/features/safety/data/safety_sign_out.dart` — add `import 'package:attune/core/notifications/services/onesignal_service.dart';` and, inside the `if (ref.read(currentUserProvider) != null) {` fallback block, before `await Supabase.instance.client.auth.signOut();`:

```dart
    try {
      await ref.read(oneSignalServiceProvider).beforeSignOut();
    } catch (_) {}
```

(What is NOT changed: the order of cache clearing, recovery-flag reset and `authService.signOut()`; the `_exclusive` lock; the decoy/leave logic. Regression risk: `auth_provider.dart` is shared — the only addition is one try/catch'd await.)

- [ ] **Step 5: Run the service tests**

Run: `flutter test test/core/notifications/`
Expected: `All tests passed!` (service: 10 tests; policy 4; the three routing files unchanged).

- [ ] **Step 6: Checkpoint**

Run: `flutter analyze lib/core/notifications/services/onesignal_service.dart lib/core/notifications/data/push_subscription_registry.dart lib/features/auth/providers/auth_provider.dart lib/features/safety/data/safety_sign_out.dart test/core/notifications/onesignal_service_test.dart | grep -E '^\s*(error|warning) '`
Expected: nothing. Also `flutter test test/features/safety/` (lock gate + sign-out tests still pass). No commit (the owner commits).

---

### Task 9: System notices are server-only — database (#19)

**Files:**
- Create: `supabase/migrations/20261019110300_system_notice_server_only.sql`
- Create: `supabase/migrations/20261019110310_system_notice_server_only_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (append one `\i`)
- Create: `supabase/tests/system_notice_contracts.sql`

**Interfaces:**
- Produces: trigger `messages_system_notice_guard` (BEFORE INSERT OR UPDATE OF is_system_notice) raising `system_notice:server_only` when `current_user IN ('authenticated','anon')`; `public.send_screenshot_notice(p_relationship_id uuid, p_client_message_id uuid) RETURNS uuid` (`SECURITY DEFINER`, `authenticated` may execute). Existing server writers (`planning_v2_maybe_celebrate`, `share_ai_assist_draft`, `send_appreciation`, `send_pause`, `send_pause_reply` — all `SECURITY DEFINER`, verified via `pg_proc.prosecdef`) are untouched and keep working.

- [ ] **Step 1: Write the failing contract test**

```sql
-- supabase/tests/system_notice_contracts.sql
-- Chat review #19 (07 M-6): a partner could INSERT is_system_notice = true
-- and forge a centred, official-looking Attune line. Only the server writes
-- notices; the app's own screenshot notice goes through
-- send_screenshot_notice with server-authored text. Every check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d190000-0000-0000-0000-0000000000a1'),
  ('8d190000-0000-0000-0000-0000000000b2'),
  ('8d190000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8d190000-0000-0000-0000-0000000000a1', '+233598190001', 'Notice A'),
  ('8d190000-0000-0000-0000-0000000000b2', '+233598190002', 'Notice B'),
  ('8d190000-0000-0000-0000-0000000000c3', '+233598190003', 'Notice C')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('8d190000-0000-0000-0000-000000000011',
        '8d190000-0000-0000-0000-0000000000a1', '8d190000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now())
ON CONFLICT (id) DO UPDATE SET status = 'active', chat_archived_at = NULL;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 0. Every function that writes a notice runs as its owner, not the caller.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['planning_v2_maybe_celebrate', 'share_ai_assist_draft',
                              'send_appreciation', 'send_pause', 'send_pause_reply',
                              'send_screenshot_notice'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = v_fn AND p.prosecdef) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not SECURITY DEFINER (it would be refused by the notice guard)', v_fn;
    END IF;
  END LOOP;
END $$;

-- 1. A client cannot author a notice; ordinary sends (with or without the
--    column, as old and new app builds send them) still work.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
    VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
            gen_random_uuid(), 'Attune: your partner reported this chat', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client inserted a system notice';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'system_notice:server_only' THEN RAISE; END IF;
  END;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'hello (old build)', false);
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
  VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'hello (new build)');
END $$;

-- 2. The screenshot notice: server-authored text, idempotent per client id,
--    members only.
DO $$
DECLARE v1 uuid; v2 uuid; v_notice boolean; v_sender uuid; v_content text;
BEGIN
  v1 := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f1');
  v2 := public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000f1');
  -- Named columns only: the client SELECT grant is a column allowlist
  -- (20261017130100), so SELECT * would fail as authenticated.
  SELECT m.is_system_notice, m.sender_id, m.content INTO v_notice, v_sender, v_content
    FROM public.messages m WHERE m.id = v1;
  IF v1 IS NULL OR v2 <> v1 OR NOT coalesce(v_notice, false)
     OR v_sender <> '8d190000-0000-0000-0000-0000000000a1'
     OR v_content <> 'Notice A took a screenshot' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: send_screenshot_notice wrote % / % / %', v1, v2, v_content;
  END IF;
  IF (SELECT count(*) FROM public.messages WHERE client_message_id = '8d190000-0000-0000-0000-0000000000f1') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the screenshot notice was written twice';
  END IF;
END $$;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  BEGIN
    PERFORM public.send_screenshot_notice('8d190000-0000-0000-0000-000000000011', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider wrote a screenshot notice into someone else''s chat';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'screenshot_notice:not_allowed' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;

-- 3. The server (a worker with the service role, a SECURITY DEFINER RPC)
--    still writes notices.
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
        gen_random_uuid(), '🎉 Goal reached', true);
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.send_screenshot_notice(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can call send_screenshot_notice';
  END IF;
END $$;

-- 4. Mutation check: with the guard off, check 1 is violated.
SAVEPOINT mutate;
ALTER TABLE public.messages DISABLE TRIGGER messages_system_notice_guard;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d190000-0000-0000-0000-0000000000a1');
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, is_system_notice)
VALUES ('8d190000-0000-0000-0000-000000000011', '8d190000-0000-0000-0000-0000000000a1',
        gen_random_uuid(), 'forged', true);
DO $$ BEGIN RAISE NOTICE 'mutation check: with the guard disabled a client authored a notice (as expected)'; END $$;
RESET ROLE;
ROLLBACK TO SAVEPOINT mutate;

DO $$ BEGIN RAISE NOTICE 'system_notice_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/system_notice_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: send_screenshot_notice is not SECURITY DEFINER …` (check 0: the function does not exist yet).

- [ ] **Step 3: Write the schema migration**

```sql
-- supabase/migrations/20261019110300_system_notice_server_only.sql
--
-- Chat review #19 (07 M-6): a system notice is written by the server only.
-- The client's INSERT grant included is_system_notice, so a partner (REST,
-- their own token) could write a centred, official-looking line -- never
-- pushed, never unread, no bubble -- and make it look like Attune said it.
--
-- The guard is by role: a direct client INSERT runs as `authenticated`;
-- every legitimate notice is written inside a SECURITY DEFINER function
-- (planning_v2_maybe_celebrate, share_ai_assist_draft, send_appreciation,
-- send_pause, send_pause_reply, send_screenshot_notice below) or by a
-- service-role worker, where current_user is the owner / service_role.
-- Those paths need no change. The INSERT column grant is deliberately kept
-- so app builds that still send is_system_notice = false keep sending (a
-- forged `true` is what is refused); the new client omits the column.
--
-- Deliberately NOT SECURITY DEFINER (unlike the other guards in this
-- repo): the whole check is "who is current_user", which a definer
-- function would rewrite to its owner.
CREATE OR REPLACE FUNCTION public.messages_system_notice_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.is_system_notice
     AND (TG_OP = 'INSERT' OR OLD.is_system_notice IS DISTINCT FROM NEW.is_system_notice)
     AND current_user IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'system_notice:server_only';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_system_notice_guard ON public.messages;
CREATE TRIGGER messages_system_notice_guard
  BEFORE INSERT OR UPDATE OF is_system_notice ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_system_notice_guard();

-- The one notice the app itself raises: "<name> took a screenshot" while
-- viewing a view-once video (ephemeral video design §7.5). Server-authored
-- text; the caller only names the conversation. Idempotent per
-- client_message_id (messages_sender_client_id_unique).
CREATE OR REPLACE FUNCTION public.send_screenshot_notice(p_relationship_id uuid, p_client_message_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_name text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR p_client_message_id IS NULL
     OR NOT public.relationship_active_for_me(p_relationship_id)
     OR EXISTS (SELECT 1 FROM public.relationships r
                WHERE r.id = p_relationship_id AND r.chat_archived_at IS NOT NULL) THEN
    RAISE EXCEPTION 'screenshot_notice:not_allowed';
  END IF;
  SELECT nullif(btrim(u.display_name), '') INTO v_name FROM public.users u WHERE u.id = v_uid;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, source,
                               is_system_notice, message_analysis_skipped)
  VALUES (p_relationship_id, v_uid, p_client_message_id,
          coalesce(v_name, 'Someone') || ' took a screenshot', 'native', true, true)
  ON CONFLICT (sender_id, client_message_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT m.id INTO v_id FROM public.messages m
    WHERE m.sender_id = v_uid AND m.client_message_id = p_client_message_id;
  END IF;
  RETURN v_id;
END;
$$;
```

- [ ] **Step 4: Grants + local replay**

```sql
-- supabase/migrations/20261019110310_system_notice_server_only_grants.sql
-- Chat review #19: grants for 20261019110300.
REVOKE ALL ON FUNCTION public.messages_system_notice_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.send_screenshot_notice(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_screenshot_notice(uuid, uuid) TO authenticated;
```

Append to `scripts/local_pg_grants.sql`:

```sql

-- Chat review #19: system notices are server-only; the screenshot notice RPC.
\i supabase/migrations/20261019110310_system_notice_server_only_grants.sql
```

- [ ] **Step 5: Apply and run**

Run:
```bash
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019110300_system_notice_server_only.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019110310_system_notice_server_only_grants.sql
psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/system_notice_contracts.sql
```
Expected: ends with `NOTICE:  system_notice_contracts: all held`, `ROLLBACK`.

- [ ] **Step 6: The existing notice writers still pass their own contracts**

Run:
```bash
for f in pause_messages_contracts appreciation_contracts planning_goals_contracts ai_assist_draft_share_contracts chat_system_contracts quiet_effects_contracts; do echo "== $f"; psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql 2>&1 | grep -E "CONTRACT VIOLATED|all held|ERROR|ROLLBACK" | tail -2; done
```
Expected: no `CONTRACT VIOLATED`/`ERROR` line for any file.

- [ ] **Step 7: Checkpoint**

No Dart/TS changes. No commit (the owner commits).

---

### Task 10: The client never sends `is_system_notice`; the screenshot notice uses the RPC (#19)

**Files:**
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`
- Modify: `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart`
- Modify: `test/features/chat/support/chat_test_harness.dart`
- Modify: `test/features/chat/ephemeral_video_viewer_screen_test.dart`
- Create: `test/features/chat/send_payload_guard_test.dart`

**Interfaces:**
- Consumes: Task 9's `send_screenshot_notice`.
- Produces: `ChatRepository.sendTextMessage` loses the `isSystemNotice` parameter; new `Future<void> sendScreenshotNotice({required String relationshipId, required String clientMessageId})` on `ChatRepository`, `SupabaseChatRepository` and `FakeChatRepository` (which also gains `int screenshotNoticeCalls`).

- [ ] **Step 1: Make the ephemeral viewer test encode the new path (it encoded the old one)**

In `test/features/chat/ephemeral_video_viewer_screen_test.dart`, in the test around the comment "Simulate the platform firing the screenshot event twice", replace the two expectations after `await tester.pump();` with:

```dart
      // Chat review #19: the notice is server-authored (send_screenshot_notice);
      // the client never inserts is_system_notice itself.
      expect(repo.sendCallCount - sendsBefore, 0,
          reason: 'a screenshot notice is not a client-side message insert');
      expect(repo.screenshotNoticeCalls, 1,
          reason: 'only the first screenshot event should raise the notice');
      expect(
        repo.serverMessages.values.where((m) => m.isSystemNotice).length,
        1,
      );
```

In the next test, `'a failed screenshot-notice send does not crash the screen …'`, replace `repo.nextSendError = Exception('screenshot notice send failed');` with `repo.nextScreenshotNoticeError = Exception('screenshot notice send failed');` — it encoded the old insert path (`nextSendError` only trips `sendTextMessage`, which the notice no longer uses, so without this change the test would pass without exercising the failure branch).

Add the source guard test:

```dart
// test/features/chat/send_payload_guard_test.dart
//
// Chat review #19: is_system_notice is server-only (messages_system_notice_
// guard). The client's insert must not carry the column at all -- an old
// client sending `false` still works, but the new one has no business
// naming it, and the fake repository must mirror that.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the chat insert payload never names is_system_notice', () {
    final src = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();
    final insert = src.substring(src.indexOf("Future<Message> sendTextMessage("));
    final body = insert.substring(0, insert.indexOf('return _hydrateMessage'));
    expect(body.contains("'is_system_notice'"), isFalse);
    expect(body.contains('isSystemNotice'), isFalse);
  });

  test('the screenshot notice is an RPC, not an insert', () {
    final src = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();
    expect(src, contains(".rpc('send_screenshot_notice'"));
  });
}
```

- [ ] **Step 2: Run both to verify failure**

Run: `flutter test test/features/chat/send_payload_guard_test.dart test/features/chat/ephemeral_video_viewer_screen_test.dart`
Expected: guard test — 2 failures (payload contains `'is_system_notice'`; no `.rpc('send_screenshot_notice'`); viewer test — compile error, `screenshotNoticeCalls` undefined.

- [ ] **Step 3: Interface**

`lib/features/chat/data/repositories/chat_repository.dart`: in `sendTextMessage` delete the line `bool isSystemNotice = false,`. After the `findMessageByClientId` declaration add:

```dart
  /// "<name> took a screenshot" while a view-once video was open (design
  /// §7.5). Server-authored: the server names the caller and marks the row
  /// a system notice (chat review #19 — clients cannot write notices).
  /// Idempotent per [clientMessageId].
  Future<void> sendScreenshotNotice({
    required String relationshipId,
    required String clientMessageId,
  });
```

- [ ] **Step 4: Supabase implementation**

`supabase_chat_repository.dart`: in `sendTextMessage` delete `bool isSystemNotice = false,` from the signature and the line `'is_system_notice': isSystemNotice,` from the insert map. After `sendTextMessage` add:

```dart
  @override
  Future<void> sendScreenshotNotice({
    required String relationshipId,
    required String clientMessageId,
  }) async {
    await _supabase.rpc(
      'send_screenshot_notice',
      params: {
        'p_relationship_id': relationshipId,
        'p_client_message_id': clientMessageId,
      },
    );
  }
```

- [ ] **Step 5: Fake repository**

`test/features/chat/support/chat_test_harness.dart`, in `FakeChatRepository`: delete `bool isSystemNotice = false,` from `sendTextMessage` and change the row line to `'is_system_notice': false,`. Add a counter next to `sendCallCount` (`int screenshotNoticeCalls = 0;`), a one-shot failure seam next to `nextSendError` (`/// Thrown once by the next [sendScreenshotNotice] call.` `Object? nextScreenshotNoticeError;`) and the method:

```dart
  @override
  Future<void> sendScreenshotNotice({
    required String relationshipId,
    required String clientMessageId,
  }) async {
    screenshotNoticeCalls++;
    final failure = nextScreenshotNoticeError;
    if (failure != null) {
      nextScreenshotNoticeError = null;
      throw failure;
    }
    final id = 'srv-$clientMessageId';
    if (serverMessages.containsKey(id)) return; // idempotent, like the RPC
    serverMessages[id] = Message.fromRow({
      'id': id,
      'relationship_id': relationshipId,
      'sender_id': currentUserId,
      'client_message_id': clientMessageId,
      'content': 'Someone took a screenshot',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'native',
      'is_system_notice': true,
    }, currentUserId: currentUserId);
  }
```

- [ ] **Step 6: The viewer**

`ephemeral_video_viewer_screen.dart`, replace the body of `_notifyScreenshot` from `final user = ref.read(currentUserProvider);` through the end of the `try` block with:

```dart
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      // Chat review #19: the server names the viewer and writes the notice;
      // the client cannot author a system notice.
      await ref
          .read(chatRepositoryProvider)
          .sendScreenshotNotice(
            relationshipId: widget.conversation.relationshipId,
            clientMessageId: const Uuid().v4(),
          );
    } catch (error) {
```

(keep the existing `catch` body). Update the doc comment above it: replace the sentence about "riding the ordinary sender_id/insert path unchanged" with "sent through send_screenshot_notice (20261019110300), which names the caller server-side". Remove the now-unused import `package:attune/core/providers/profile_providers/profile_provider.dart` if `currentUserProfileProvider` has no other use in the file (it does not).

- [ ] **Step 7: Run the chat tests that touch sends**

Run: `flutter test test/features/chat/send_payload_guard_test.dart test/features/chat/ephemeral_video_viewer_screen_test.dart test/features/chat/message_model_test.dart && flutter test test/features/chat/ 2>&1 | tail -3`
Expected: the three pass; the whole chat suite reports `All tests passed!` (Plan 1a's suite included — if Plan 1a is mid-flight, run only the three).

- [ ] **Step 8: Checkpoint**

Run: `flutter analyze lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart test/features/chat/support/chat_test_harness.dart test/features/chat/ephemeral_video_viewer_screen_test.dart test/features/chat/send_payload_guard_test.dart | grep -E '^\s*(error|warning) '`
Expected: nothing (also confirms no other `sendTextMessage` caller passed `isSystemNotice:` — `quiet_states_screen.dart`, `story_reel_screen.dart` and `chat_state.dart` do not). No commit (the owner commits).

---

### Task 11: Whole-plan verification and owner hand-off

**Files:** none new.

- [ ] **Step 1: Flutter**

Run: `flutter test test/core/ test/features/chat/ test/features/safety/ 2>&1 | tail -3`
Expected: `All tests passed!`

- [ ] **Step 2: Deno (by file)**

Run (from `supabase/functions`):
```bash
for f in process-chat-notification-outbox/index.test.ts process-chat-notification-outbox/dispatch.test.ts process-scheduled-notifications/deliver.test.ts process-scheduled-notifications/claim_recheck.test.ts process-scheduled-notifications/together_event_data.test.ts _shared/push_queue.test.ts _shared/push_transport.test.ts _shared/onesignal_push.test.ts _shared/push_targets.test.ts; do printf "%s: " $f; deno test --allow-read --allow-env --allow-net $f 2>&1 | grep -E "passed|failed" | tail -1; done
deno check process-chat-notification-outbox/index.ts process-scheduled-notifications/index.ts
```
Expected: every line `… passed | 0 failed`; check clean.

- [ ] **Step 3: SQL**

Run:
```bash
for f in chat_push_dedupe push_subscriptions system_notice quiet_hours push_copy chat_system service_role_grants pause_messages appreciation; do printf "%s: " $f; psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/${f}_contracts.sql 2>&1 | grep -cE "CONTRACT VIOLATED|^psql:.*ERROR"; done
```
Expected: every line ends in `0` (note `service_role_grants` is `service_role_grants_test.sql`, not `_contracts` — run it by its real name: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/service_role_grants_test.sql`).

- [ ] **Step 4: Analyzer over everything this plan touched**

Run: `flutter analyze lib/core/notifications lib/features/auth/providers/auth_provider.dart lib/features/safety/data/safety_sign_out.dart lib/features/chat/data/repositories lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart test/core test/features/chat/support test/features/chat/ephemeral_video_viewer_screen_test.dart test/features/chat/send_payload_guard_test.dart | grep -E '^\s*(error|warning) '`
Expected: nothing.

- [ ] **Step 5: Hand-off**

No commit (the owner commits). Report the Owner deploy steps below verbatim.

## Owner deploy steps (in this order)

1. **Xcode / Apple (Task 1 owner step):** Push Notifications + Background Modes → Remote notifications on the Runner target; APNs .p8 key uploaded to OneSignal (Apple iOS platform); confirm FCM credentials for Android. Commit `project.pbxproj` changes with the two iOS files.
2. **OneSignal dashboard:** leave **Identity Verification OFF** (see Rulings — the Flutter SDK cannot present a token; enabling it would break subscription registration). No other dashboard change.
3. **Build and install the new app on both test phones first.** The sender will only address devices registered through `register_push_subscription`; a phone on an older build receives no pushes once step 5 is live (rows are `skipped` with `no_push_subscription`).
4. **Migrations** (`supabase db push`, or apply in order): `20261019110000_chat_push_dedupe.sql`, `20261019110200_push_subscriptions.sql`, `20261019110210_push_subscriptions_grants.sql`, `20261019110300_system_notice_server_only.sql`, `20261019110310_system_notice_server_only_grants.sql`. The dedupe migration deletes duplicate historical queue rows (keeps the oldest per `outbox_id`). The subscriptions migration deactivates every existing `push_tokens` row (legacy raw tokens, none registered through the RPC) — from that moment until a phone opens the new build, that phone receives no push. Deploy step 5 in the same sitting, after step 3's installs.
5. **Edge functions:** `supabase functions deploy process-chat-notification-outbox process-scheduled-notifications`. No new secrets: the outbox worker uses the runtime's `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` to wake the sender; `ONESIGNAL_APP_ID`/`ONESIGNAL_API_KEY` are unchanged.
6. **Prod sanity (SQL editor):** `select public.app_setting('supabase_url') is not null and public.app_setting('service_role_key') is not null;` must be `true` — the immediate path from message INSERT to the outbox worker (`messages_enqueue_downstream_work` → `net.http_post(…/process-chat-notification-outbox)`) depends on these Vault secrets (review 07 "Not verified"); if false, the kick falls back to the minute cron and #14 is not met. After step 5, `select count(*) filter (where is_active) from public.push_tokens;` should climb as phones open the new build; `select status, last_error, count(*) from public.scheduled_notifications where created_at > now() - interval '1 hour' group by 1, 2;` shows `skipped / no_push_subscription` only for people who have not yet opened it. Also `select jobname, schedule from cron.job where jobname in ('process-scheduled-notifications','process-chat-notification-outbox');` — both must still be scheduled (the sweepers).
7. **Device checks:** (a) iPhone: first sign-in shows the notification prompt (after PIN unlock if set); Settings → Attune → Notifications exists; (b) Android 14: same prompt on first sign-in; (c) A sends while B's app is closed → B's lock screen within ~2 s (check the outbox worker's response `wake: "woken"` in function logs); (d) B signs out → A sends → nothing arrives on B's phone; B signs back in → pushes resume; (e) second account on B's phone → gets its own pushes, none of B's; (f) 22:30 local message → nothing until 08:00, then one "New messages in Attune".
8. **Optional follow-up (not this wave):** OneSignal Notification Service Extension target in Xcode (badges, confirmed delivery), and revisit Identity Verification when `onesignal_flutter` ships `login(externalId, token)`.
