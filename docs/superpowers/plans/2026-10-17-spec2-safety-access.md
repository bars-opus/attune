# Spec 2 (trimmed) — Quick Exit Everywhere, Safety PIN, Where You're Signed In — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three safety floors for a couples app whose likeliest adversary is the partner:
1. **F3 — quick exit from every signed-in screen.** It includes Android task removal and an iOS cover in the app switcher.
2. **F2 — the Safety PIN.** Today it is promised but never built.
3. **F7 — "Where you're signed in" and "Sign out all other devices",** with an in-app notice when a new device signs in.

**Owner scope (2026-10-17):** "Spec 2 trimmed" means F2, F3 and F7. F8's neutral icon, launcher alias and sender-name audit wait until before the Ghana launch. No feature flags in this spec: these are safety floors, and a failed flag read must never switch one off (plan ruling R2-1).

**Architecture:**
- **One root shell.** `MaterialApp.router`'s `builder` already wraps every route. A new `appShell(...)` function holds the whole wrapper. From outside in:
  - `ShareIntakeListener`;
  - `SafetyLockGate`, which replaces everything while locked and is fed by a Riverpod controller;
  - `AppPrivacyCover`;
  - a `Stack` of the routed child, the `NewDeviceNotice` banner and the `QuickExitZone`.

  Because it sits above the Navigator, it covers every route, dialog and sheet, deep link, notification tap and widget launch.
- **PIN in the OS keystore.** PBKDF2-HMAC-SHA256 with a 16-byte salt and 100,000 iterations, computed off the UI isolate. Stored in `flutter_secure_storage` with `first_unlock_this_device` (iOS) and encrypted prefs (Android), so it is never synced. Failure counters live beside it. There is no wipe.
- **The lock decision lives in a controller,** not widget state, because `AppPrivacyCover` unmounts its subtree on every inactive event. It decides at cold start and at every return from background.
- **Sessions are read from `auth.sessions`** by a SECURITY DEFINER RPC. A small `public.session_devices` table holds the label each device reports. Signing out other devices uses the auth client's own `signOut(scope: SignOutScope.others)`, so migrations never write to Supabase's auth schema.

**Tech Stack:** Flutter 3.29 / Riverpod 2, `go_router` 10, `flutter_secure_storage` 9.2.4, `pointycastle` 3.9.1, `supabase_flutter` 2.14.1 (gotrue 2.21.0: `SignOutScope.others`), Postgres 17 harness, Kotlin `MainActivity`, Swift `AppDelegate`.

**Spec:** `docs/superpowers/research/2026-10-16-couples-research/06-synthesis-roadmap.md` §3 rows F2, F3, F7 (verbatim below), and §11 Spec 2. Code map (read alongside this plan): `.superpowers/sdd/spec2-map.md`.

> **F2 Safety PIN gate enforced.**
> (1) Cold start and resume: if `safety_requires_unlock` is set, the PIN screen is the first frame; no deep link, widget or notification bypasses it.
> (2) Biometrics alone do not clear it.
> (3) Salted KDF hash in the OS keystore, never synced.
> (4) Five failures → escalating local delay, no wipe.
> (5) Recovery = sign out to a generic state until DV review approves another path.
> (6) Setup offered on first visit to Support resources and in Settings; quick exit works with no PIN (return = signed-out).
> (7) Real-device tests both platforms, including app kill during decoy.
>
> **F3 Quick exit from every authenticated screen; Android task removal.**
> (1) Triple-tap target mounted once in the root shell above GoRouter; widget test asserts coverage of every named route (Settings, resources, Planning entry, journal, Healing, full-screen map, games).
> (2) Android `finishAndRemoveTask()` via audited channel, verified on three OEMs.
> (3) iOS cover within 200 ms plus switcher image.
> (4) Activation sends no network, analytics or log.
> (5) Together/map device data and widget opt-in clear.
>
> **F7 Account security for the IPV threat model.**
> (1) Settings → "Where you're signed in": sessions/devices, last active (owner-only), "Sign out all other devices" revokes refresh tokens server-side.
> (2) New-device sign-in → in-app notice to the owner only; never SMS/email.
> (3) No recovery path through a partner's phone or email.
> (4) Phone change needs current session + OTP to the new number + in-app notice.

## Rulings in this plan (confirm at review)
- **R2-1 No flags.** Quick exit, the PIN gate and the device list are safety floors, so none is behind `feature_flags`. The owner's "flag everything on" is met trivially: there is nothing to switch.
- **R2-2 When the PIN is asked for.**
  - Always after a quick exit (F2 (1)).
  - Optionally every time Attune opens or returns from the background: the switch "Ask for my PIN every time Attune opens", default off.
  - Only while someone is signed in. A signed-out app shows only the login screen.
- **R2-3 Quick exit with no PIN set.** The next open signs the person out to the login screen (F2 (6) "return = signed-out").
- **R2-4 Recovery.** "Forgot PIN?" signs out to the login screen and removes the PIN, the quick-exit flag and the "every open" choice. Signing back in needs the phone number and its SMS code. There is no partner-assisted path (F2 (5), F7 (3)).
- **R2-5 Delay schedule.**
  - Failures 1–4: no delay.
  - Then 30 s at 5, 1 min at 6, 5 min at 7, 15 min at 8, and 1 h at 9 or more.
  - Persisted, so killing the app does not reset it.
  - Nothing is ever wiped (F2 (4)).
- **R2-6 PIN format.** 4 to 8 digits, entered on an in-app keypad. There is no system keyboard and no text field, so it works above the Navigator, where no Overlay exists.
- **R2-7 The lock screen is neutral.**
  - It shows "Enter PIN", the keypad and "Forgot PIN?". There is no app name, logo or partner name.
  - The quick-exit decoy (`NeutralScreen`) is unchanged.
- **R2-8 F7 (4) phone change.** Attune has no phone-change flow (`spec2-map.md` §C: phone OTP sign-in only), so nothing is built. The ledger records "N/A — no flow exists". A future phone-change flow must meet F7 (4).
- **R2-9 Device labels without a new package.** Labels are "iPhone or iPad · iOS 17.2", "Android phone" or "Web". There is no `device_info_plus`. The list's job is "is that me?", which signed-in and last-active dates answer.
- **R2-10 Sign out others.** The auth client revokes the other sessions' refresh tokens server-side (`signOut(scope: others)`). The copy says other devices can take up to an hour to notice, because their access token stays valid until it expires.
- **R2-11 The new-device notice** is shown on an older device the next time that device opens or resumes Attune. It is a bottom banner, "Review" or "Dismiss", in the app only (F7 (2)). The first run on a device records the existing sessions without showing a notice.

## Plan review amendments (Fable, 2026-10-17) — BINDING, they override the task text below
Report: `.superpowers/sdd/2026-10-17-spec2-plan-review.md`.

**Critical**
- **C1.** While locked, the Navigator is intentionally NOT mounted. Tests must not assume `navigatorKey.currentState`. Replace the Task 3 test "a route pushed while locked stays hidden" with a `MaterialApp.router` + GoRouter version:
  - assert `navKey.currentState` is null while locked;
  - `router.go('/deep')` while locked;
  - assert "DEEP LINKED" is absent and "Enter PIN" present;
  - unlock;
  - assert "DEEP LINKED" now shows (it landed behind the lock).
- **C2.** Failures fail closed.
  - `evaluate`, `unlock` and `forgot` are wrapped in try/catch. `_failClosed()` signs out if signed in, then sets `open`. The state never stays `checking`.
  - Both secure storages use `AndroidOptions(encryptedSharedPreferences: true, resetOnError: true)`.
  - `backup_rules.xml` and `data_extraction_rules.xml` exclude `sharedpref` `FlutterSecureStorage.xml` and `FlutterSecureKeyStorage.xml`.
  - Controller test: storage `read` throws → `open` and `signOuts == 1`.
- **C3.** `_run` awaits `_markSafetyUnlockRequired()` (errors caught) after the cover is shown and the device data is cleared. Only then does it wait at least 300 ms and remove the task. Unit test: a slow write (500 ms) still completes before `_exitApp`.

**Important**
- **I1.** Sign-out is verified.
  - `safetySignOut` rechecks `currentUserProvider` after the attempt; if a user is still signed in, it calls `Supabase.instance.client.auth.signOut()`.
  - The controller sets `open` only if `!signedIn()`. Otherwise it stays `locked` with "Couldn't sign out. Try again."
  - Gate test: `signOut` throws → stays locked, and "SECRET CONTENT" never shows.
- **I2.** Unlocking leaves the decoy.
  - New dep `SafetyLockDeps.leaveDecoy`: if the router path is `/neutralScreen`, go home.
  - It is called on unlock `ok` and when `evaluate` opens a signed-in session.
  - Test with a `leaveDecoy` counter.
- **I3.** `SafetyPinStore` gets an injectable `verifier`, by default `compute(_verifyInIsolate, (pin, encoded))`. Tests inject a synchronous one. Production iterations are 20,000; the format version carries the count.
- **I4.** The delay schedule keeps escalating:
  - 9 failures → 1 h, 10 → 2 h, 11 → 4 h, 12 → 8 h, 13 or more → 24 h.
  - `safety_pin_last_failure_at` is persisted. If `now < lastFailureAt` (the clock moved back), the full delay applies from that moment.
  - `PinLockScreen.initState` reads `retryAt()` and starts the countdown at once.
  - Ledger note: a forward clock jump cannot be detected offline.
  - Test: the clock moves back → still waiting.
- **I5.** Seed the lock decision before `runApp`.
  - `main()` reads the flag, `hasPin` and `everyOpen`, plus whether a session exists (`Supabase.instance.client.auth.currentUser`).
  - It overrides `safetyLockSeedProvider` with the initial `SafetyLockState`; `build()` uses the seed when present. The common, unlocked path then mounts the Router on frame 1.
  - Notification taps that arrive while locked are deferred, not dropped. `OneSignalService` stashes the last click in `pendingNotificationTapProvider` when locked or when no navigator is ready; the gate replays it on open.
  - Test: a pure `PendingTap` replay.
- **I6.** New-device checks are scheduled by a provider (`newDeviceWatcherProvider`, which owns its `AppLifecycleListener` and a 5-minute throttle), not by widget lifecycle. No check runs and no banner renders while the route is `/neutralScreen` or the state is `locked`.
- **I7.** Hand-off checks, run on staging before shipping:
  - `select has_table_privilege('postgres','auth.sessions','select')` returns `t`;
  - `rpc('list_my_sessions')` through PostgREST with a real JWT marks `is_current`;
  - the project's access-token expiry is read and recorded. If it isn't 3600 s, change the "up to an hour" copy.
- **I8.** The zone is limited to the toolbar band (`top: topInset`, `height: kToolbarHeight`, 72 wide) and counts only touch pointer-downs. Test: triple-tapping the middle tab of `AppBar(bottom: TabBar)` does not exit.
- **I9.** Ruling R2-12: the PIN protects against someone who can open the phone but can't read its SMS. Recovery via the same phone is an accepted limit pending DV review. The manual copy at `safety_docs.dart:158` and `:225` says what the PIN actually does, with no "cannot be bypassed".
- **I10.** `OneSignalService` adds `addForegroundWillDisplayListener`, which calls `preventDefault()` when the pure predicate `shouldSuppressForegroundPush(lockState, path)` is true (locked, or on `/neutralScreen`). Unit test the predicate.
- **I11.** Zone tests find the target by `Key('quick_exit_zone')`, not by semantics label.
- **I12.** Turning "every open" off requires the current PIN; turning it on does not. The test is updated to match.

**Minor**
- **M1.** Kotlin sends `result.success(null)` before `finishAndRemoveTask()`.
- **M2.** `QuickExitZone` always mounts the detector, with `TripleTapDetector(enabled: signedIn)`.
- **M3.** The lock screen is wrapped in the text-scale clamp.
- **M4.** A test-file comment: drive the delay UI with `pump(Duration)`.
- **M5.** The iOS cover uses `window?.backgroundColor ?? .systemBackground`.
- **M6.** Unique settings orders (recorded in the ledger).
- **M7.** One `Random.secure()` instance.
- **M8.** Devices screen intro: "Phones you no longer use stay here until you sign them out."
- **M9.** The first run after the update shows a one-time "Review where you're signed in" notice.
- **M10.** Not applied (key rewrite risk).
- **M11.** `FLAG_SECURE` recorded as an F8 candidate.
- **M12.** The ledger notes that an intruder's "sign out others" signs the owner out and clears their PIN.

## Global Constraints
- Work on `main`. **No commits.** Never `dart format` a pre-existing file. Snapshot-diff every shared file into `$WS/snapshots/`. Analyzer gate: `flutter analyze <files> 2>&1 | grep -E "^\s*(error|warning) "` prints nothing.
- **Do not touch** `lib/features/planning/**`, `test/features/planning/**`, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md` or `chat_feature_flags.dart`.
- `lib/home/home_screen.dart` keeps exactly three `_reportTimezone();` calls (its wiring test counts them).
- SQL:
  - Scratch DB `attune_spec2`; never use `attune_test`, `attune_spec1a` or `attune_spec1b`.
  - Contracts assert specific errors.
  - Table REVOKEs go in a `*_grants.sql` replayed by `scripts/local_pg_grants.sql`.
  - Migrations start at `20261017200000`.
- Fixtures use uuid prefix `9a` and phones `+233597…`. Confirm both are unused at Task 0.
- Never log a PIN, a hash or a session id.

**Copy (verbatim)**
- Lock screen:
  - Title "Enter PIN" and keypad with digits 0–9, "Delete" and "Unlock".
  - Wrong PIN: "That PIN didn't match."
  - Delay: "Try again in {n} seconds." / "Try again in {n} minutes." / "Try again in about an hour."
  - Recovery link: "Forgot PIN?"
  - Recovery confirm: "Sign out of Attune? You'll need your phone number to sign back in. Your PIN will be removed." with buttons "Sign out" and "Cancel".
- Settings row: title "Safety PIN", subtitle "Asked for after you use quick exit".
- PIN screen:
  - Title "Safety PIN".
  - Intro: "After you use quick exit, Attune asks for this PIN before it opens again. If you forget it, you can sign out and sign back in with your phone number."
  - Buttons "Set a PIN", "Change PIN", "Remove PIN".
  - Toggle "Ask for my PIN every time Attune opens".
  - Prompts: "Choose a 4–8 digit PIN", "Enter it again", "Enter your current PIN".
  - Confirmation errors: "Those PINs didn't match." and "Use 4 to 8 digits."
- Support resources card: title "Set a Safety PIN", body "So no one can open Attune after you leave it in a hurry.", buttons "Set PIN" and "Not now".
- Devices:
  - Settings row title "Where you're signed in", subtitle "See the phones on your account".
  - Screen title "Where you're signed in"; current-device suffix " · This phone".
  - Row subtitle: `MyDateFormat.join(['Signed in ' + toDate(signedIn), 'Last active ' + toDate(lastActive)])`.
  - Button "Sign out all other devices".
  - Confirm title "Sign out all other devices?", message "Every other phone signed in to your account will be signed out. It can take up to an hour for another phone to notice.", button "Sign out others".
  - Success "Other devices are signed out."
  - Empty state "Only this phone is signed in."
- New-device notice: "A new device signed in to your account: {label}, {date}. Not you? Review your devices." with buttons "Review" and "Dismiss".

## Review Focus
1. **A deep link or a notification tap while the PIN is required.** It must land behind the lock, never above it. Pinned in Task 3 (`safety_lock_gate_test.dart` "a route pushed while locked stays hidden").
2. **The app killed during the decoy.** The next cold start must show the lock, or sign out, before any app frame. Pinned in Task 3 ("cold start with the quick-exit flag and a PIN shows only the lock").
3. **Five wrong PINs, then an app kill.** The delay survives the kill. Pinned in Task 2 (`safety_pin_store_test.dart` "the delay survives a restart").
4. **Two people on one phone.** Signing out must not leave the previous person's PIN behind for the next person. Pinned in Task 3 ("signing out removes the PIN data").
5. **Quick exit from a dialog, sheet or pushed `MaterialPageRoute`** (the full-screen map). Pinned in Task 4 (`quick_exit_zone_test.dart` coverage list).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/local_pg_bootstrap.sql` (shared) | Stub `auth.sessions` and `auth.jwt()` (harness only) |
| `supabase/migrations/20261017200000_account_sessions.sql` (new) | `session_devices`, `register_my_device`, `list_my_sessions` |
| `supabase/migrations/20261017200100_session_devices_grants.sql` (new, replayed) | No client access to `session_devices` |
| `supabase/tests/account_sessions_contracts.sql` (new) | F7 server contracts |
| `lib/features/safety/domain/safety_pin.dart` (new) | Pure: PIN validation, PBKDF2 hash/verify, delay schedule |
| `lib/features/safety/data/safety_pin_store.dart` (new) | Keystore storage, failure counter, every-open choice |
| `lib/features/safety/data/safety_sign_out.dart` (new) | Context-free sign-out to the login screen |
| `lib/features/safety/presentation/safety_lock_controller.dart` (new) | Lock state machine |
| `lib/features/safety/presentation/widgets/safety_lock_gate.dart` (new) | Root gate and lifecycle hook |
| `lib/features/safety/presentation/widgets/pin_keypad.dart` (new) | Keypad and dots |
| `lib/features/safety/presentation/widgets/pin_lock_screen.dart` (new) | Neutral lock screen |
| `lib/features/safety/presentation/widgets/quick_exit_zone.dart` (new) | Root triple-tap zone (uses the router) |
| `lib/features/safety/domain/services/quick_exit_service.dart` (shared) | Router variant; Android task removal |
| `lib/features/safety/presentation/widgets/triple_tap_detector.dart` (shared) | Optional `onTripleTap` |
| `lib/features/safety/presentation/screens/safety_pin_screen.dart` (new) | Set/change/remove, and the every-open toggle |
| `lib/features/safety/presentation/screens/safety_resources_screen.dart` (shared) | "Set a Safety PIN" card |
| `lib/features/account/data/account_sessions.dart` (new) | `SignedInDevice`, repository, providers, `newSessionIds` |
| `lib/features/account/presentation/signed_in_devices_screen.dart` (new) | The list and sign out others |
| `lib/features/account/presentation/new_device_notice.dart` (new) | Watcher and banner |
| `lib/app/app_shell.dart` (new) | The root wrapper used by `App` and by tests |
| `lib/app/app.dart` (shared) | Builder calls `appShell` |
| `lib/app/routing/app_router.dart` (shared) | Two routes: `safetyPin`, `signedInDevices` |
| `lib/features/settings/data/settings_data.dart` (shared) | Two rows |
| `lib/home/home_screen.dart` (shared) | Drop the local `TripleTapDetector` (the root zone replaces it) |
| `android/.../MainActivity.kt` (shared) | `attune/safety` channel: `finishAndRemoveTask` |
| `ios/Runner/AppDelegate.swift` (shared) | Native app-switcher cover |
| `lib/app/documentations/user_manual/data/safety_docs.dart` (shared) | Manual matches what was built |

---

### Task 0: Workspace and baseline

- [ ] **Step 1:** Create the ledger.
  - Run `export WS=/Users/user/attune/.superpowers/sdd/2026-10-17-spec2-safety-access; mkdir -p $WS/snapshots`.
  - Write `$WS/progress.md` with first line `# SDD ledger — plan: docs/superpowers/plans/2026-10-17-spec2-safety-access.md`, plus a Baseline header.
  - Copy `.superpowers/sdd/2026-10-17-spec1b-quiet-surfaces/mutant.sh` to `$WS/mutant.sh`, replacing `attune_spec1b` with `attune_spec2`.
- [ ] **Step 2:** Baselines.
  - Run `grep -rl -- "+233597\|9a100000-" supabase/tests` and expect nothing.
  - Run `flutter test` (full) and record the count.
  - Run `ATTUNE_TEST_DB=attune_spec2 scripts/local_pg_setup.sh` and record PASS and FAIL. Expect 91 PASS and the 8 known FAIL.
  - Append `Task 0: complete (…)`.

---

### Task 1: Sessions on the server (F7 (1))

**Files:** `scripts/local_pg_bootstrap.sql` (append), migrations `20261017200000_account_sessions.sql` and `20261017200100_session_devices_grants.sql`, `scripts/local_pg_grants.sql` (append), `supabase/tests/account_sessions_contracts.sql`.

**Interfaces — Produces:**
- `public.register_my_device(p_label text, p_platform text) RETURNS void`. SECURITY DEFINER, for `authenticated`.
  - Keyed by `auth.jwt()->>'session_id'`.
  - Errors: `session:unknown` with no session claim; `session:invalid_input` when the label is longer than 60 characters, or the platform is not one of ios, android, web, other.
- `public.list_my_sessions() RETURNS TABLE (session_id uuid, device_label text, platform text, signed_in_at timestamptz, last_active_at timestamptz, is_current boolean)`.
  - SECURITY DEFINER, for `authenticated`.
  - Returns the caller's sessions only, unexpired (`not_after` null or in the future), newest activity first.

- [ ] **Step 1: Harness stubs.** Snapshot `scripts/local_pg_bootstrap.sql`, then append:
```sql
-- Spec 2: the slice of Supabase's auth.sessions that list_my_sessions reads,
-- and auth.jwt(), which Supabase defines over the same GUC as auth.uid().
CREATE TABLE IF NOT EXISTS auth.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  not_after timestamptz,
  refreshed_at timestamp without time zone,
  user_agent text,
  ip inet
);
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$$;
```

- [ ] **Step 2: The failing contract.**
```sql
-- supabase/tests/account_sessions_contracts.sql
-- "Where you're signed in" (Spec 2 Task 1; research 06 §3 F7 (1)): a member
-- lists only their own live sessions, the current one marked; a device names
-- only its own session; nobody reads session_devices directly. Every check
-- RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('9a100000-0000-0000-0000-0000000000a1'),
  ('9a100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9a100000-0000-0000-0000-0000000000a1', '+233597100001', 'Device A'),
  ('9a100000-0000-0000-0000-0000000000b2', '+233597100002', 'Device B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO auth.sessions (id, user_id, created_at, updated_at, refreshed_at, not_after) VALUES
  ('9a300000-0000-0000-0000-000000000001', '9a100000-0000-0000-0000-0000000000a1', now() - interval '30 days', now() - interval '2 days', (now() - interval '1 hour') AT TIME ZONE 'UTC', NULL),
  ('9a300000-0000-0000-0000-000000000002', '9a100000-0000-0000-0000-0000000000a1', now() - interval '1 day', now() - interval '1 day', NULL, NULL),
  ('9a300000-0000-0000-0000-000000000003', '9a100000-0000-0000-0000-0000000000a1', now() - interval '90 days', now() - interval '80 days', NULL, now() - interval '1 day'),
  ('9a300000-0000-0000-0000-000000000004', '9a100000-0000-0000-0000-0000000000b2', now(), now(), NULL, NULL);

CREATE FUNCTION pg_temp.as_session(p_user uuid, p_session uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'session_id', p_session)::text, true);
END $$;

-- 1. Grants: the two RPCs for the app; session_devices for nobody.
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.list_my_sessions()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.register_my_device(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app cannot reach its sessions';
  END IF;
  IF has_function_privilege('anon', 'public.list_my_sessions()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.register_my_device(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can reach sessions';
  END IF;
  IF has_table_privilege('authenticated', 'public.session_devices', 'SELECT')
     OR has_table_privilege('authenticated', 'public.session_devices', 'INSERT')
     OR has_table_privilege('anon', 'public.session_devices', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: session_devices is client-reachable';
  END IF;
END $$;

-- 2. A device names its own session; the list shows A's two live sessions,
--    the current one marked, the expired one gone, newest activity first.
DO $$
DECLARE v_n int; v_current uuid; v_label text; v_first uuid;
BEGIN
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000a1', '9a300000-0000-0000-0000-000000000002');
  PERFORM public.register_my_device('iPhone or iPad · iOS 17.2', 'ios');
  SELECT count(*) INTO v_n FROM public.list_my_sessions();
  SELECT session_id INTO v_current FROM public.list_my_sessions() WHERE is_current;
  SELECT device_label INTO v_label FROM public.list_my_sessions() WHERE session_id = '9a300000-0000-0000-0000-000000000002';
  SELECT session_id INTO v_first FROM public.list_my_sessions() LIMIT 1;
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % sessions (want 2 live)', v_n; END IF;
  IF v_current IS DISTINCT FROM '9a300000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the current session is not marked (%)', v_current;
  END IF;
  IF v_label IS DISTINCT FROM 'iPhone or iPad · iOS 17.2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device label was not stored (%)', v_label;
  END IF;
  -- Session 1 refreshed an hour ago: the most recently active.
  IF v_first IS DISTINCT FROM '9a300000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not ordered by last activity (%)', v_first;
  END IF;
END $$;

-- 3. Owner-only: B sees only B; B cannot name A's session.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000b2', '9a300000-0000-0000-0000-000000000004');
  SELECT count(*) INTO v_n FROM public.list_my_sessions()
   WHERE session_id IN ('9a300000-0000-0000-0000-000000000001', '9a300000-0000-0000-0000-000000000002');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B sees A''s sessions'; END IF;
  -- A claim naming A's session under B's sub is ignored: register keys by sub too.
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000b2', '9a300000-0000-0000-0000-000000000001');
  BEGIN
    PERFORM public.register_my_device('Spoof', 'android');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device named another account''s session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'session:unknown' THEN RAISE; END IF;
  END;
  RESET ROLE;
END $$;

-- 4. Input: no session claim, an over-long label, an unknown platform.
DO $$
DECLARE v_msg text;
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '9a100000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.register_my_device('Phone', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: registered without a session';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:unknown' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000a1', '9a300000-0000-0000-0000-000000000002');
  BEGIN
    PERFORM public.register_my_device(repeat('x', 61), 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 61-character label was stored';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:invalid_input' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.register_my_device('Phone', 'toaster');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown platform was stored';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:invalid_input' THEN RAISE; END IF;
  END;
  RESET ROLE;
END $$;

DO $$ BEGIN RAISE NOTICE 'account_sessions_contracts: all held'; END $$;
ROLLBACK;
```
Run it after `ATTUNE_TEST_DB=attune_spec2 scripts/local_pg_setup.sh --no-tests`. Expected: `ERROR: function public.list_my_sessions() does not exist` (red: the RPC is missing).

- [ ] **Step 3: Migrations.**
```sql
-- supabase/migrations/20261017200000_account_sessions.sql
--
-- "Where you're signed in" (Spec 2; research 06 §3 F7 (1)). A partner who
-- knows the phone number, or shares the phone, can sign in elsewhere; the
-- owner must be able to see every signed-in phone and sign the others out.
--
-- Sessions are read from Supabase's auth.sessions (never written here:
-- signing out others uses the auth API's own scope=others logout).
-- session_devices holds only the label each device reports for itself,
-- keyed by the session id in its JWT; no client reads or writes it directly.
CREATE TABLE IF NOT EXISTS public.session_devices (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
  platform text NOT NULL CHECK (platform IN ('ios', 'android', 'web', 'other')),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.session_devices ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS session_devices_user_idx ON public.session_devices (user_id);

CREATE OR REPLACE FUNCTION public.register_my_device(p_label text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_session uuid;
BEGIN
  BEGIN
    v_session := nullif(auth.jwt()->>'session_id', '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_session := NULL;
  END;
  IF auth.uid() IS NULL OR v_session IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.sessions s WHERE s.id = v_session AND s.user_id = auth.uid()) THEN
    RAISE EXCEPTION 'session:unknown';
  END IF;
  IF p_label IS NULL OR char_length(btrim(p_label)) NOT BETWEEN 1 AND 60
     OR p_platform IS NULL OR p_platform NOT IN ('ios', 'android', 'web', 'other') THEN
    RAISE EXCEPTION 'session:invalid_input';
  END IF;
  INSERT INTO public.session_devices (session_id, user_id, label, platform, updated_at)
  VALUES (v_session, auth.uid(), btrim(p_label), p_platform, now())
  ON CONFLICT (session_id) DO UPDATE
    SET label = EXCLUDED.label, platform = EXCLUDED.platform, updated_at = now()
    WHERE session_devices.user_id = auth.uid();
END $$;
REVOKE ALL ON FUNCTION public.register_my_device(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_my_device(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.list_my_sessions()
RETURNS TABLE (session_id uuid, device_label text, platform text,
               signed_in_at timestamptz, last_active_at timestamptz, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, d.label, d.platform, s.created_at,
         greatest(s.created_at, s.updated_at, s.refreshed_at AT TIME ZONE 'UTC'),
         s.id::text = coalesce(auth.jwt()->>'session_id', '')
  FROM auth.sessions s
  LEFT JOIN public.session_devices d ON d.session_id = s.id AND d.user_id = s.user_id
  WHERE auth.uid() IS NOT NULL AND s.user_id = auth.uid()
    AND (s.not_after IS NULL OR s.not_after > now())
  ORDER BY 5 DESC, s.id
$$;
REVOKE ALL ON FUNCTION public.list_my_sessions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_sessions() TO authenticated;
```
```sql
-- supabase/migrations/20261017200100_session_devices_grants.sql
-- Replayed by scripts/local_pg_grants.sql after its blanket grant.
REVOKE ALL ON public.session_devices FROM PUBLIC, anon, authenticated;
```
Append to `scripts/local_pg_grants.sql`:
```
-- Spec 2 (Task 1): session_devices is RPC-only.
\i supabase/migrations/20261017200100_session_devices_grants.sql
```

- [ ] **Step 4:** Rebuild and run the contract; expect `NOTICE: account_sessions_contracts: all held`. Then run the mutants:
  - `"$WS/mutant.sh" "CREATE OR REPLACE FUNCTION public.list_my_sessions() RETURNS TABLE (session_id uuid, device_label text, platform text, signed_in_at timestamptz, last_active_at timestamptz, is_current boolean) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS \$\$ SELECT s.id, NULL::text, NULL::text, s.created_at, s.updated_at, false FROM auth.sessions s \$\$;" supabase/tests/account_sessions_contracts.sql`. Expected: `CONTRACT VIOLATED: A sees …` and `MUTANT KILLED`.
  - `"$WS/mutant.sh" "GRANT SELECT ON public.session_devices TO authenticated;" supabase/tests/account_sessions_contracts.sql`. Expected: `session_devices is client-reachable` and `MUTANT KILLED`.
- [ ] **Step 5:** Ledger: `Task 1: complete (account_sessions_contracts RED→GREEN; 2 mutants KILLED; bootstrap +stubs)`.

---

### Task 2: The PIN core (F2 (3), (4))

**Files:** `lib/features/safety/domain/safety_pin.dart`, `lib/features/safety/data/safety_pin_store.dart`, `test/features/safety/safety_pin_test.dart`, `test/features/safety/safety_pin_store_test.dart`.

**Interfaces — Produces:**
- `bool isValidPin(String pin)`: 4–8 ASCII digits.
- `String hashPin(String pin, {List<int>? salt, int iterations = 100000})` returns `v1$<iterations>$<b64 salt>$<b64 hash>`.
- `bool verifyPinHash(String pin, String encoded)`: constant-time comparison.
- `Duration safetyPinDelayAfter(int failures)`.
- `enum PinCheck { ok, wrong, waiting }`.
- `class SafetyPinStore`:
  - constructor `SafetyPinStore({FlutterSecureStorage? storage, DateTime Function()? clock, Future<String> Function(String pin)? hasher})`;
  - `Future<bool> hasPin()`; `Future<void> setPin(String pin)` (throws `ArgumentError` if invalid);
  - `Future<({PinCheck result, DateTime? retryAt})> check(String pin)`;
  - `Future<DateTime?> retryAt()`;
  - `Future<bool> everyOpen()`; `Future<void> setEveryOpen(bool on)`;
  - `Future<void> clearAll()`;
  - `static final instance = SafetyPinStore()`.

- [ ] **Step 1: Failing tests.**
```dart
// test/features/safety/safety_pin_test.dart
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a PIN is 4 to 8 digits', () {
    for (final ok in ['1234', '00000000', '9876543']) {
      expect(isValidPin(ok), isTrue, reason: ok);
    }
    for (final bad in ['123', '123456789', '12a4', ' 1234', '', '１２３４']) {
      expect(isValidPin(bad), isFalse, reason: bad);
    }
  });

  test('the hash is salted, versioned and verifies only its own PIN', () {
    final a = hashPin('2468', iterations: 1000);
    final b = hashPin('2468', iterations: 1000);
    expect(a, startsWith(r'v1$1000$'));
    expect(a, isNot(b), reason: 'a fresh salt each time');
    expect(verifyPinHash('2468', a), isTrue);
    expect(verifyPinHash('2469', a), isFalse);
    expect(verifyPinHash('2468', 'garbage'), isFalse);
    expect(a.contains('2468'), isFalse);
  });

  test('five failures start an escalating delay, never a wipe', () {
    expect(safetyPinDelayAfter(4), Duration.zero);
    expect(safetyPinDelayAfter(5), const Duration(seconds: 30));
    expect(safetyPinDelayAfter(6), const Duration(minutes: 1));
    expect(safetyPinDelayAfter(7), const Duration(minutes: 5));
    expect(safetyPinDelayAfter(8), const Duration(minutes: 15));
    expect(safetyPinDelayAfter(9), const Duration(hours: 1));
    expect(safetyPinDelayAfter(40), const Duration(hours: 1));
  });
}
```
```dart
// test/features/safety/safety_pin_store_test.dart
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  SafetyPinStore store() => SafetyPinStore(
    clock: () => now,
    hasher: (pin) async => hashPin(pin, iterations: 1000),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 10, 12);
  });

  test('set, check, remove', () async {
    final s = store();
    expect(await s.hasPin(), isFalse);
    await s.setPin('2468');
    expect(await s.hasPin(), isTrue);
    expect((await s.check('2468')).result, PinCheck.ok);
    expect((await s.check('1111')).result, PinCheck.wrong);
    await s.clearAll();
    expect(await s.hasPin(), isFalse);
  });

  test('an invalid PIN is refused', () async {
    expect(() => store().setPin('12'), throwsArgumentError);
  });

  test('the fifth miss starts a wait; a right PIN during it still waits', () async {
    final s = store();
    await s.setPin('2468');
    for (var i = 0; i < 4; i++) {
      expect((await s.check('0000')).result, PinCheck.wrong);
    }
    final fifth = await s.check('0000');
    expect(fifth.result, PinCheck.wrong);
    expect(fifth.retryAt, now.add(const Duration(seconds: 30)));
    expect((await s.check('2468')).result, PinCheck.waiting);
    now = now.add(const Duration(seconds: 31));
    expect((await s.check('2468')).result, PinCheck.ok);
    // A success resets the count.
    expect((await s.check('0000')).retryAt, isNull);
  });

  test('the delay survives a restart (a new store over the same keystore)', () async {
    await store().setPin('2468');
    for (var i = 0; i < 5; i++) {
      await store().check('0000');
    }
    expect(await store().retryAt(), now.add(const Duration(seconds: 30)));
    expect((await store().check('2468')).result, PinCheck.waiting);
  });

  test('every-open is off by default and cleared with the PIN', () async {
    final s = store();
    expect(await s.everyOpen(), isFalse);
    await s.setPin('2468');
    await s.setEveryOpen(true);
    expect(await s.everyOpen(), isTrue);
    await s.clearAll();
    expect(await s.everyOpen(), isFalse);
  });
}
```
Run `flutter test test/features/safety/safety_pin_test.dart test/features/safety/safety_pin_store_test.dart`. Expected: they fail to compile (files missing).

- [ ] **Step 2: Implementation.**
```dart
// lib/features/safety/domain/safety_pin.dart
/// The Safety PIN (Spec 2; research 06 §3 F2): a salted PBKDF2-HMAC-SHA256
/// hash, a 4–8 digit PIN, and an escalating delay after five misses. No wipe.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

final _digits = RegExp(r'^[0-9]{4,8}$');

bool isValidPin(String pin) => _digits.hasMatch(pin);

Uint8List _derive(String pin, List<int> salt, int iterations) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(pin)));
}

String hashPin(String pin, {List<int>? salt, int iterations = 100000}) {
  final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
  final h = _derive(pin, s, iterations);
  return 'v1\$$iterations\$${base64Encode(s)}\$${base64Encode(h)}';
}

bool verifyPinHash(String pin, String encoded) {
  final parts = encoded.split(r'$');
  if (parts.length != 4 || parts[0] != 'v1') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final List<int> salt;
  final List<int> want;
  try {
    salt = base64Decode(parts[2]);
    want = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  final got = _derive(pin, salt, iterations);
  if (got.length != want.length) return false;
  var diff = 0;
  for (var i = 0; i < got.length; i++) {
    diff |= got[i] ^ want[i];
  }
  return diff == 0;
}

Duration safetyPinDelayAfter(int failures) {
  if (failures < 5) return Duration.zero;
  return switch (failures) {
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 1),
    7 => const Duration(minutes: 5),
    8 => const Duration(minutes: 15),
    _ => const Duration(hours: 1),
  };
}

enum PinCheck { ok, wrong, waiting }
```
```dart
// lib/features/safety/data/safety_pin_store.dart
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _hashInIsolate(String pin) => hashPin(pin);

/// The PIN, its failure count and the "every open" choice, in the OS keystore
/// on this device only (never synced, never backed up to another phone).
class SafetyPinStore {
  SafetyPinStore({
    FlutterSecureStorage? storage,
    DateTime Function()? clock,
    Future<String> Function(String pin)? hasher,
  }) : _storage = storage ?? _defaultStorage,
       _clock = clock ?? DateTime.now,
       _hasher = hasher ?? ((pin) => compute(_hashInIsolate, pin));

  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static final instance = SafetyPinStore();

  static const _hashKey = 'safety_pin_hash';
  static const _failuresKey = 'safety_pin_failures';
  static const _retryAtKey = 'safety_pin_retry_at';
  static const _everyOpenKey = 'safety_pin_every_open';

  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  final Future<String> Function(String pin) _hasher;

  Future<bool> hasPin() async => (await _storage.read(key: _hashKey)) != null;

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('pin');
    await _storage.write(key: _hashKey, value: await _hasher(pin));
    await _storage.delete(key: _failuresKey);
    await _storage.delete(key: _retryAtKey);
  }

  Future<DateTime?> retryAt() async {
    final raw = await _storage.read(key: _retryAtKey);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<({PinCheck result, DateTime? retryAt})> check(String pin) async {
    final wait = await retryAt();
    if (wait != null && _clock().isBefore(wait)) {
      return (result: PinCheck.waiting, retryAt: wait);
    }
    final hash = await _storage.read(key: _hashKey);
    if (hash != null && verifyPinHash(pin, hash)) {
      await _storage.delete(key: _failuresKey);
      await _storage.delete(key: _retryAtKey);
      return (result: PinCheck.ok, retryAt: null);
    }
    final failures =
        (int.tryParse(await _storage.read(key: _failuresKey) ?? '') ?? 0) + 1;
    await _storage.write(key: _failuresKey, value: '$failures');
    final delay = safetyPinDelayAfter(failures);
    if (delay == Duration.zero) return (result: PinCheck.wrong, retryAt: null);
    final at = _clock().toUtc().add(delay);
    await _storage.write(key: _retryAtKey, value: '${at.millisecondsSinceEpoch}');
    return (result: PinCheck.wrong, retryAt: at);
  }

  Future<bool> everyOpen() async =>
      (await _storage.read(key: _everyOpenKey)) == 'true';

  Future<void> setEveryOpen(bool on) =>
      _storage.write(key: _everyOpenKey, value: on ? 'true' : 'false');

  Future<void> clearAll() async {
    for (final k in [_hashKey, _failuresKey, _retryAtKey, _everyOpenKey]) {
      await _storage.delete(key: k);
    }
  }
}
```
Note: in the store test, `now` is UTC and `retryAt` is built from a UTC clock, so the `expect(... now.add(...))` equalities hold.

- [ ] **Step 3:** Run the tests (green), `dart format` the four new files, and run the analyzer. Ledger.

---

### Task 3: The lock gate (F2 (1), (2), (5), (6))

**Files:**
- New: `lib/features/safety/data/safety_sign_out.dart`, `lib/features/safety/presentation/safety_lock_controller.dart`, `lib/features/safety/presentation/widgets/pin_keypad.dart`, `lib/features/safety/presentation/widgets/pin_lock_screen.dart`, `lib/features/safety/presentation/widgets/safety_lock_gate.dart`, `lib/app/app_shell.dart`.
- Modify: `lib/app/app.dart` (builder → `appShell`).
- Test: `test/features/safety/safety_lock_gate_test.dart`.

**Interfaces — Produces:**
- `enum SafetyLockState { checking, open, locked }`.
- `class SafetyLockDeps { Future<bool> Function() quickExitFlag; Future<void> Function() clearQuickExitFlag; SafetyPinStore pins; Future<void> Function() signOut; bool Function() signedIn; }`
- `final safetyLockDepsProvider = Provider<SafetyLockDeps>(...)`: production wiring.
- `class SafetyLockController extends Notifier<SafetyLockState>`:
  - `Future<void> evaluate({required bool coldStart})`;
  - `Future<({PinCheck result, DateTime? retryAt})> unlock(String pin)`;
  - `Future<void> forgot()`;
  - `Future<void> onSignedOut()`.
- `final safetyLockProvider = NotifierProvider<SafetyLockController, SafetyLockState>(SafetyLockController.new)`.
- `class SafetyLockGate extends ConsumerStatefulWidget { child }`.
- `Widget appShell({required GoRouter router, required Widget child})` in `lib/app/app_shell.dart`.

- [ ] **Step 1: Failing tests.**
```dart
// test/features/safety/safety_lock_gate_test.dart
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _World {
  bool flag = false;
  bool signedIn = true;
  int signOuts = 0;
  final pins = SafetyPinStore(hasher: (p) async => hashPin(p, iterations: 1000));
  SafetyLockDeps get deps => SafetyLockDeps(
    quickExitFlag: () async => flag,
    clearQuickExitFlag: () async => flag = false,
    pins: pins,
    signOut: () async {
      signOuts++;
      signedIn = false;
    },
    signedIn: () => signedIn,
  );
}

Future<void> _pump(WidgetTester t, _World w) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
      child: const MaterialApp(
        home: SafetyLockGate(child: Text('SECRET CONTENT')),
      ),
    ),
  );
}

Future<void> _type(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.widgetWithText(InkResponse, d).first);
    await t.pump();
  }
  await t.tap(find.text('Unlock'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('no PIN, no flag: the app opens', (t) async {
    final w = _World();
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
  });

  testWidgets('cold start with the quick-exit flag and a PIN shows only the '
      'lock, and never a frame of the app', (t) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    await _pump(t, w);
    expect(find.text('SECRET CONTENT'), findsNothing, reason: 'first frame');
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(find.text("That PIN didn't match."), findsOneWidget);
    expect(find.text('SECRET CONTENT'), findsNothing);
    await _type(t, '2468');
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    expect(w.flag, isFalse, reason: 'the flag clears on unlock');
  });

  testWidgets('quick exit with no PIN: the next open signs out', (t) async {
    final w = _World()..flag = true;
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
    expect(w.flag, isFalse);
  });

  testWidgets('every-open: locks at cold start and after the background, '
      'not before', (t) async {
    final w = _World();
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    // A notification shade (inactive only) does not lock.
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    // The background does.
    for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden,
        AppLifecycleState.paused, AppLifecycleState.hidden,
        AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      t.binding.handleAppLifecycleStateChanged(s);
    }
    await t.pumpAndSettle();
    expect(find.text('Enter PIN'), findsOneWidget);
  });

  testWidgets('forgot PIN signs out and removes the PIN', (t) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    await _pump(t, w);
    await t.pumpAndSettle();
    await t.tap(find.text('Forgot PIN?'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(w.signOuts, 1);
    expect(await w.pins.hasPin(), isFalse);
  });

  testWidgets('signed out: never locks, and signing out removes the PIN data',
      (t) async {
    final w = _World()..signedIn = false;
    await w.pins.setPin('2468');
    await w.pins.setEveryOpen(true);
    await _pump(t, w);
    await t.pumpAndSettle();
    expect(find.text('SECRET CONTENT'), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(SafetyLockGate)));
    await c.read(safetyLockProvider.notifier).onSignedOut();
    expect(await w.pins.hasPin(), isFalse);
  });

  testWidgets('a route pushed while locked stays hidden', (t) async {
    final w = _World()..flag = true;
    await w.pins.setPin('2468');
    final navKey = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      ProviderScope(
        overrides: [safetyLockDepsProvider.overrideWithValue(w.deps)],
        child: MaterialApp(
          navigatorKey: navKey,
          builder: (context, child) => SafetyLockGate(child: child!),
          home: const Text('SECRET CONTENT'),
        ),
      ),
    );
    await t.pumpAndSettle();
    // A notification tap pushes through the navigator key.
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('DEEP LINKED')),
    );
    await t.pumpAndSettle();
    expect(find.text('DEEP LINKED'), findsNothing);
    expect(find.text('Enter PIN'), findsOneWidget);
  });
}
```
Run: expect compile failure (files missing).

- [ ] **Step 2: Implementation.**
```dart
// lib/features/safety/data/safety_sign_out.dart
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/together/data/together_device_surfaces.dart';
import 'package:attune/features/together/presentation/together_providers.dart'
    show
        togetherWidgetEnabledProvider,
        togetherLiveEnabledProvider,
        togetherMirrorEnabledProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign out to the login screen with no BuildContext (Spec 2: the lock gate
/// sits above the Navigator). The same sequence as LogoutAction, without its
/// confirmation sheet.
Future<void> safetySignOut(Ref ref) async {
  try {
    await ref.read(authOperationsProvider).signOut();
  } catch (_) {}
  await clearTogetherDeviceSurfaces();
  await ref.read(preferencesServiceProvider).clearUserData();
  ref.invalidate(togetherWidgetEnabledProvider);
  ref.invalidate(togetherLiveEnabledProvider);
  ref.invalidate(togetherMirrorEnabledProvider);
  ref.read(routingNotifierProvider).clearUser();
  ref.read(appRouterProvider).go(RouteNames.intro);
}
```
```dart
// lib/features/safety/presentation/safety_lock_controller.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/data/safety_sign_out.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SafetyLockState { checking, open, locked }

class SafetyLockDeps {
  const SafetyLockDeps({
    required this.quickExitFlag,
    required this.clearQuickExitFlag,
    required this.pins,
    required this.signOut,
    required this.signedIn,
  });

  final Future<bool> Function() quickExitFlag;
  final Future<void> Function() clearQuickExitFlag;
  final SafetyPinStore pins;
  final Future<void> Function() signOut;
  final bool Function() signedIn;
}

final safetyLockDepsProvider = Provider<SafetyLockDeps>((ref) {
  return SafetyLockDeps(
    quickExitFlag: QuickExitService.requiresSafetyUnlock,
    clearQuickExitFlag: QuickExitService.clearSafetyUnlockRequired,
    pins: SafetyPinStore.instance,
    signOut: () => safetySignOut(ref),
    signedIn: () => ref.read(currentUserProvider) != null,
  );
});

/// Whether Attune may show itself (Spec 2; research 06 §3 F2). Decided at
/// cold start and on every return from the background, in a provider:
/// AppPrivacyCover unmounts the app's subtree whenever it goes inactive.
class SafetyLockController extends Notifier<SafetyLockState> {
  SafetyLockDeps get _deps => ref.read(safetyLockDepsProvider);

  @override
  SafetyLockState build() {
    Future.microtask(() => evaluate(coldStart: true));
    return SafetyLockState.checking;
  }

  Future<void> evaluate({required bool coldStart}) async {
    final d = _deps;
    final flag = await d.quickExitFlag();
    if (!d.signedIn()) {
      // Nothing to protect behind a login screen.
      if (flag) await d.clearQuickExitFlag();
      state = SafetyLockState.open;
      return;
    }
    final hasPin = await d.pins.hasPin();
    if (flag) {
      if (hasPin) {
        state = SafetyLockState.locked;
      } else {
        // Quick exit with no PIN: the way back is signed out (F2 (6)).
        await d.clearQuickExitFlag();
        await d.signOut();
        state = SafetyLockState.open;
      }
      return;
    }
    if (hasPin && await d.pins.everyOpen()) {
      state = SafetyLockState.locked;
      return;
    }
    if (state == SafetyLockState.checking) state = SafetyLockState.open;
  }

  Future<({PinCheck result, DateTime? retryAt})> unlock(String pin) async {
    final r = await _deps.pins.check(pin);
    if (r.result == PinCheck.ok) {
      await _deps.clearQuickExitFlag();
      state = SafetyLockState.open;
    }
    return r;
  }

  /// "Forgot PIN?": sign out to the login screen; the PIN goes (F2 (5)).
  Future<void> forgot() async {
    await _deps.pins.clearAll();
    await _deps.clearQuickExitFlag();
    await _deps.signOut();
    state = SafetyLockState.open;
  }

  /// The next person on this phone must not inherit this person's PIN.
  Future<void> onSignedOut() async {
    await _deps.pins.clearAll();
    await _deps.clearQuickExitFlag();
    state = SafetyLockState.open;
  }
}

final safetyLockProvider =
    NotifierProvider<SafetyLockController, SafetyLockState>(
      SafetyLockController.new,
    );
```
```dart
// lib/features/safety/presentation/widgets/pin_keypad.dart
import 'package:flutter/material.dart';

/// A 0–9 keypad with dots: no system keyboard and no text field, so it works
/// above the Navigator where there is no Overlay (Spec 2 ruling R2-6).
class PinKeypad extends StatelessWidget {
  const PinKeypad({
    super.key,
    required this.length,
    required this.onDigit,
    required this.onDelete,
    this.enabled = true,
  });

  final int length;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, VoidCallback onTap, {String? semantics}) => SizedBox(
      width: 72,
      height: 64,
      child: Semantics(
        button: true,
        label: semantics ?? label,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 32,
          child: Center(
            child: Text(label, style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '$length digits entered',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 8; i++)
                if (i < length || i < 4)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      i < length ? Icons.circle : Icons.circle_outlined,
                      size: 14,
                      color: scheme.onSurface,
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final d in row) key(d, () => onDigit(d))],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 72, height: 64),
            key('0', () => onDigit('0')),
            key('⌫', onDelete, semantics: 'Delete'),
          ],
        ),
      ],
    );
  }
}
```
```dart
// lib/features/safety/presentation/widgets/pin_lock_screen.dart
import 'dart:async';

import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/pin_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String retryCopy(Duration left) {
  if (left.inSeconds < 60) return 'Try again in ${left.inSeconds.clamp(1, 59)} seconds.';
  if (left.inMinutes < 50) return 'Try again in ${(left.inSeconds / 60).ceil()} minutes.';
  return 'Try again in about an hour.';
}

/// Neutral on purpose (Spec 2 ruling R2-7): no app name, no logo, no name.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  String? _message;
  DateTime? _retryAt;
  bool _confirmForgot = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _waiting => _retryAt != null && DateTime.now().toUtc().isBefore(_retryAt!);

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (!_waiting) {
          _retryAt = null;
          _message = null;
          _tick?.cancel();
        } else {
          _message = retryCopy(_retryAt!.difference(DateTime.now().toUtc()));
        }
      });
    });
  }

  Future<void> _unlock() async {
    if (_busy || _pin.isEmpty || _waiting) return;
    setState(() => _busy = true);
    final r = await ref.read(safetyLockProvider.notifier).unlock(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      switch (r.result) {
        case PinCheck.ok:
          _message = null;
        case PinCheck.wrong:
          _retryAt = r.retryAt;
          _message = r.retryAt == null
              ? "That PIN didn't match."
              : retryCopy(r.retryAt!.difference(DateTime.now().toUtc()));
        case PinCheck.waiting:
          _retryAt = r.retryAt;
          _message = retryCopy(r.retryAt!.difference(DateTime.now().toUtc()));
      }
    });
    if (_retryAt != null) _startTick();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: _confirmForgot
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Sign out of Attune? You'll need your phone number to sign back in. Your PIN will be removed.",
                        textAlign: TextAlign.center,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => ref.read(safetyLockProvider.notifier).forgot(),
                        child: const Text('Sign out'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _confirmForgot = false),
                        child: const Text('Cancel'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Enter PIN', style: text.headlineSmall),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 24,
                        child: _message == null
                            ? null
                            : Text(
                                _message!,
                                style: text.bodyMedium?.copyWith(color: scheme.error),
                              ),
                      ),
                      const SizedBox(height: 16),
                      PinKeypad(
                        length: _pin.length,
                        enabled: !_busy && !_waiting,
                        onDigit: (d) => setState(() {
                          if (_pin.length < 8) _pin += d;
                          if (_message != null && !_waiting) _message = null;
                        }),
                        onDelete: () => setState(() {
                          if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                        }),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _pin.length >= 4 && !_busy && !_waiting ? _unlock : null,
                        child: const Text('Unlock'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _confirmForgot = true),
                        child: const Text('Forgot PIN?'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
```
```dart
// lib/features/safety/presentation/widgets/safety_lock_gate.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/presentation/widgets/pin_lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root gate above the Navigator (Spec 2; research 06 §3 F2): while the
/// PIN is required the app's subtree is not in the tree at all, so no deep
/// link, notification tap or widget launch can show it.
class SafetyLockGate extends ConsumerStatefulWidget {
  const SafetyLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SafetyLockGate> createState() => _SafetyLockGateState();
}

class _SafetyLockGateState extends ConsumerState<SafetyLockGate> {
  late final AppLifecycleListener _lifecycle;
  bool _wentBackground = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _wentBackground = true,
      onResume: () {
        if (!_wentBackground) return;
        _wentBackground = false;
        ref.read(safetyLockProvider.notifier).evaluate(coldStart: false);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The next person on this phone must not inherit this person's PIN.
    ref.listen(currentUserProvider, (prev, next) {
      if (prev != null && next == null) {
        ref.read(safetyLockProvider.notifier).onSignedOut();
      }
    });
    switch (ref.watch(safetyLockProvider)) {
      case SafetyLockState.checking:
        return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
      case SafetyLockState.locked:
        return const PinLockScreen();
      case SafetyLockState.open:
        return widget.child;
    }
  }
}
```
In the tests, `currentUserProvider` resolves through `authStateProvider`. If it throws without Supabase in the test harness, override it: add `currentUserProvider.overrideWithValue(null)` to each test's overrides. The gate only uses it for the transition listener; `signedIn` comes from the deps. Record a ruling if this was needed.

```dart
// lib/app/app_shell.dart
import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/account/presentation/new_device_notice.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:attune/features/together/presentation/widgets/share_intake_listener.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Everything MaterialApp.router's builder wraps around every route (Spec 2).
/// Above the Navigator, so it covers every route, dialog and sheet.
///   ShareIntakeListener  -- outside: a share can arrive while covered.
///   SafetyLockGate       -- replaces everything while the PIN is required.
///   AppPrivacyCover      -- neutral cover while inactive.
///   QuickExitZone        -- the triple-tap target, on top of everything.
///   NewDeviceNotice      -- the "a new device signed in" banner.
Widget appShell({required GoRouter router, required Widget child}) {
  return ShareIntakeListener(
    onShare: () => showTogetherForShare(router),
    child: SafetyLockGate(
      child: AppPrivacyCover(
        child: QuickExitZone(
          router: router,
          child: NewDeviceNotice(
            router: router,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.0,
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
```
`app.dart`:
- Replace the builder body with `builder: (context, child) => appShell(router: router, child: child ?? const SizedBox.shrink()),`.
- Add the import `package:attune/app/app_shell.dart`.
- Remove the now-unused imports (`app_privacy_cover.dart`, `share_intake_listener.dart`) only if the analyzer flags them.

Snapshot `app.dart` first. Tasks 4 and 6 create `quick_exit_zone.dart` and `new_device_notice.dart`. Until then, create both as pass-through widgets (`QuickExitZone({router, child})` and `NewDeviceNotice({router, child})` returning `child`), so Task 3 compiles. Tasks 4 and 6 replace them.

- [ ] **Step 3:** Run the gate tests and the full `test/core/services/app_privacy_cover_test.dart`; both green. Format the new files, analyze, and ledger.

---

### Task 4: Quick exit from everywhere (F3)

**Files:** `quick_exit_service.dart` (shared), `triple_tap_detector.dart` (shared), `quick_exit_zone.dart` (replaces the Task 3 stub), `home_screen.dart` (shared), `MainActivity.kt` (shared), `AppDelegate.swift` (shared), `test/features/safety/quick_exit_zone_test.dart`, `test/features/safety/quick_exit_wiring_test.dart`.

**Interfaces — Produces:**
- `QuickExitService.executeWithRouter(GoRouter router)`.
- `TripleTapDetector({required child, VoidCallback? onTripleTap})`.
- `QuickExitZone({required GoRouter router, required Widget child})`: shown only while signed in.
- The Android channel `attune/safety` method `finishAndRemoveTask`.

- [ ] **Step 1: Failing tests.**
```dart
// test/features/safety/quick_exit_zone_test.dart
// Spec 2 (research 06 §3 F3 (1)): one triple-tap target in the root shell
// covers every route -- pushed pages, a pageless MaterialPageRoute (the
// full-screen map), dialogs and bottom sheets.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

final _user = User(
  id: 'u1', appMetadata: const {}, userMetadata: const {}, aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    for (final p in [
      RouteNames.settings,
      RouteNames.safetyResources,
      '/planning/entry',
      '/journal',
      '/healing',
      '/games',
    ])
      GoRoute(path: p, builder: (_, __) => Scaffold(appBar: AppBar(title: Text(p)), body: Text('AT $p'))),
    GoRoute(
      path: RouteNames.neutralScreen,
      name: 'neutralScreen',
      builder: (_, __) => const Scaffold(body: Text('DECOY')),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester t, {bool signedIn = true}) async {
  final router = _router();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(signedIn ? _user : null),
        safetyLockDepsProvider.overrideWithValue(SafetyLockDeps(
          quickExitFlag: () async => false,
          clearQuickExitFlag: () async {},
          pins: SafetyPinStore(),
          signOut: () async {},
          signedIn: () => signedIn,
        )),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => QuickExitZone(router: router, child: child!),
      ),
    ),
  );
  await t.pumpAndSettle();
  return router;
}

Future<void> _tripleTap(WidgetTester t) async {
  final zone = find.bySemanticsLabel('Quick exit gesture area');
  for (var i = 0; i < 3; i++) {
    await t.tap(zone, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final p in [
    RouteNames.settings,
    RouteNames.safetyResources,
    '/planning/entry',
    '/journal',
    '/healing',
    '/games',
  ]) {
    testWidgets('quick exit works on $p', (t) async {
      final router = await _pump(t);
      router.push(p);
      await t.pumpAndSettle();
      expect(find.text('AT $p'), findsOneWidget);
      await _tripleTap(t);
      expect(find.text('DECOY'), findsOneWidget);
    });
  }

  testWidgets('quick exit works over a pageless route (the full-screen map), '
      'a dialog and a bottom sheet', (t) async {
    final router = await _pump(t);
    final nav = router.routerDelegate.navigatorKey.currentState!;
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('MAP'))));
    await t.pumpAndSettle();
    showDialog<void>(context: nav.context, builder: (_) => const AlertDialog(content: Text('DIALOG')));
    await t.pumpAndSettle();
    await _tripleTap(t);
    expect(find.text('DECOY'), findsOneWidget);
    expect(find.text('DIALOG'), findsNothing);
  });

  testWidgets('signed out: there is no quick-exit target', (t) async {
    await _pump(t, signedIn: false);
    expect(find.bySemanticsLabel('Quick exit gesture area'), findsNothing);
  });
}
```
```dart
// test/features/safety/quick_exit_wiring_test.dart
// Spec 2: the quick-exit target is mounted once, in the root shell; no
// screen mounts its own any more; Android leaves through finishAndRemoveTask.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the root shell mounts the zone; HomeScreen no longer does', () {
    final shell = File('lib/app/app_shell.dart').readAsStringSync();
    expect(shell, contains('QuickExitZone('));
    expect(File('lib/app/app.dart').readAsStringSync(), contains('appShell('));
    expect(File('lib/home/home_screen.dart').readAsStringSync(), isNot(contains('TripleTapDetector(')));
  });

  test('Android removes the task through the audited channel', () {
    final kt = File('android/app/src/main/kotlin/com/barsopus/attune/MainActivity.kt').readAsStringSync();
    expect(kt, contains('"attune/safety"'));
    expect(kt, contains('finishAndRemoveTask()'));
    final svc = File('lib/features/safety/domain/services/quick_exit_service.dart').readAsStringSync();
    expect(svc, contains("MethodChannel('attune/safety')"));
    expect(svc, contains("'finishAndRemoveTask'"));
  });

  test('iOS covers the app switcher natively', () {
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift, contains('willResignActiveNotification'));
    expect(swift, contains('didBecomeActiveNotification'));
  });

  test('activation sends nothing: no network or analytics in the service', () {
    final svc = File('lib/features/safety/domain/services/quick_exit_service.dart').readAsStringSync();
    for (final banned in ['http', 'Supabase', 'analytics', 'debugPrint', 'log(']) {
      expect(svc.contains(banned), isFalse, reason: banned);
    }
  });
}
```
Run both: expect failures. The zone stub renders no target, and the wiring scans fail.

- [ ] **Step 2: Implementation.**
- `quick_exit_service.dart` (snapshot first):
  - Replace `execute` with:
```dart
  /// Execute quick exit from a screen's context.
  static Future<void> execute(BuildContext context) =>
      _run(() => context.goNamed('neutralScreen'));

  /// Execute quick exit from the root shell, above the Router (Spec 2).
  static Future<void> executeWithRouter(GoRouter router) =>
      _run(() => router.goNamed('neutralScreen'));

  static Future<void> _run(void Function() showCover) async {
    unawaited(_markSafetyUnlockRequired());
    showCover();
    // The home-screen card and the lock-screen plan show plans: empty them
    // too. Fire-and-forget, after the cover is up, so nothing delays or
    // reveals activation.
    unawaited(clearTogetherDeviceSurfaces());
    // The map's tile cache holds the partner's area; pins hold faces.
    unawaited(clearCoupleMapDeviceData());

    Future.delayed(const Duration(milliseconds: 300), () {
      _exitApp();
    });
  }
```
  - Delete `_showNeutralCover`, but keep its comment above the `execute` line.
  - Replace `_exitApp` with:
```dart
  static const _channel = MethodChannel('attune/safety');

  static Future<void> _exitApp() async {
    if (!Platform.isAndroid) return;
    // Removes the task, so Attune is not left in Recents (F3 (2)).
    try {
      await _channel.invokeMethod<void>('finishAndRemoveTask');
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
```
- `triple_tap_detector.dart`:
  - Add `final VoidCallback? onTripleTap;` and `this.onTripleTap,` to the constructor.
  - In `_handleTap` replace `QuickExitService.execute(context);` with `(widget.onTripleTap ?? () => QuickExitService.execute(context))();`.
- `quick_exit_zone.dart` (replacing the stub):
```dart
// lib/features/safety/presentation/widgets/quick_exit_zone.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/triple_tap_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The one quick-exit target (Spec 2; research 06 §3 F3 (1)), in the root
/// shell above the Navigator, so it covers every route, dialog and sheet.
/// Signed-in only. The builder's context is above the Router, so it drives
/// the router directly.
class QuickExitZone extends ConsumerWidget {
  const QuickExitZone({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(currentUserProvider) == null) return child;
    return TripleTapDetector(
      onTripleTap: () => QuickExitService.executeWithRouter(router),
      child: child,
    );
  }
}
```
  The `TripleTapDetector` Stack needs `Directionality`. The builder child sits inside `MaterialApp`, which provides it.
- `home_screen.dart` (snapshot):
  - Replace `TripleTapDetector(child: home)` (around `:402`) with `home`.
  - Delete the `triple_tap_detector.dart` import.
  - Keep exactly three `_reportTimezone();`.
- `MainActivity.kt` (snapshot). In `configureFlutterEngine`, after the screenshot channel handler, add:
```kotlin
        // Quick exit (Spec 2; research 06 §3 F3 (2)): leave AND drop the
        // task, so Attune is not left in Recents. The only method on this
        // channel; nothing is logged or sent.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "attune/safety")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishAndRemoveTask" -> {
                        finishAndRemoveTask()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
```
- `AppDelegate.swift` (snapshot):
  - Add the property `private var switcherCover: UIView?`.
  - In `didFinishLaunching`, before `return super.application(...)` (at both return points; put it right after `GeneratedPluginRegistrant.register(with: self)`), add:
```swift
    // Quick exit / privacy (Spec 2; research 06 §3 F3 (3)): a native cover the
    // moment Attune leaves the foreground, so the app-switcher snapshot never
    // shows content (Flutter's own cover can miss the snapshot frame).
    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.showSwitcherCover() }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.hideSwitcherCover() }
```
  - Add these methods to the class:
```swift
  private func showSwitcherCover() {
    guard switcherCover == nil, let window = window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(red: 0xF5 / 255, green: 0xF1 / 255, blue: 0xE8 / 255, alpha: 1)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    switcherCover = cover
  }

  private func hideSwitcherCover() {
    switcherCover?.removeFromSuperview()
    switcherCover = nil
  }
```

- [ ] **Step 3:** Run the zone and wiring tests, `test/home`, `test/features/together/together_widget_sync_test.dart` and `together_live_activity_test.dart` (they use `execute(context)`). All green.
  - Build check: `flutter build apk --debug` and `flutter build ios --debug --no-codesign`; expect both to build. If a build cannot run (tooling), record it as an owner device check.
  - Format the new files, analyze, and diff the snapshots.
  - Ledger.

---

### Task 5: Setting the PIN (F2 (6))

**Files:** `lib/features/safety/presentation/screens/safety_pin_screen.dart`, `app_router.dart` (route `safetyPin` at `/settings/safety-pin`), `settings_data.dart` (row), `safety_resources_screen.dart` (card), `test/features/safety/safety_pin_screen_test.dart`.

**Interfaces — Produces:**
- `RouteNames.safetyPin = '/settings/safety-pin'` with route name `'safetyPin'`.
- `SafetyPinScreen({SafetyPinStore? store})`.
- `SafetyPinPromptCard` on Support resources. It is shown when there is no PIN and the prefs key `safety_pin_prompt_dismissed` is not set.

- [ ] **Step 1: Failing tests.**
```dart
// test/features/safety/safety_pin_screen_test.dart
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

SafetyPinStore _store() => SafetyPinStore(hasher: (p) async => hashPin(p, iterations: 1000));

Future<void> _type(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.widgetWithText(InkResponse, d).first);
    await t.pump();
  }
  await t.tap(find.text('Next'));
  await t.pumpAndSettle();
}

Future<void> _pump(WidgetTester t, SafetyPinStore s) async {
  await t.pumpWidget(ProviderScope(child: MaterialApp(home: SafetyPinScreen(store: s))));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('set a PIN: choose, confirm, done', (t) async {
    final s = _store();
    await _pump(t, s);
    expect(find.text('Set a PIN'), findsOneWidget);
    await t.tap(find.text('Set a PIN'));
    await t.pumpAndSettle();
    expect(find.text('Choose a 4–8 digit PIN'), findsOneWidget);
    await _type(t, '2468');
    expect(find.text('Enter it again'), findsOneWidget);
    await _type(t, '2468');
    expect(await s.hasPin(), isTrue);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Remove PIN'), findsOneWidget);
  });

  testWidgets('a mismatched confirmation is refused', (t) async {
    final s = _store();
    await _pump(t, s);
    await t.tap(find.text('Set a PIN'));
    await t.pumpAndSettle();
    await _type(t, '2468');
    await _type(t, '1357');
    expect(find.text("Those PINs didn't match."), findsOneWidget);
    expect(await s.hasPin(), isFalse);
  });

  testWidgets('remove needs the current PIN; every-open toggles', (t) async {
    final s = _store();
    await s.setPin('2468');
    await _pump(t, s);
    final toggle = find.byType(Switch);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(await s.everyOpen(), isTrue);
    await t.tap(find.text('Remove PIN'));
    await t.pumpAndSettle();
    expect(find.text('Enter your current PIN'), findsOneWidget);
    await _type(t, '1111');
    expect(await s.hasPin(), isTrue);
    await _type(t, '2468');
    expect(await s.hasPin(), isFalse);
    expect(find.text('Set a PIN'), findsOneWidget);
  });
}
```
- [ ] **Step 2: Implementation.** Write `SafetyPinScreen` as a `ConsumerStatefulWidget`.
  - Steps enum: `overview`, `choose`, `confirm`, `current` (with the purpose change or remove).
  - It uses `PinKeypad` and a "Next" `FilledButton`, which is enabled when the PIN is 4 or more digits.
  - Overview with no PIN: the intro copy, then "Set a PIN".
  - Overview with a PIN: the intro copy, then an `InfoRowWidget` toggle "Ask for my PIN every time Attune opens" (`isToggleItem: true`, wired to `store.setEveryOpen`), then "Change PIN" and "Remove PIN".
  - The `Switch` above is the `InfoRowWidget` toggle; confirm that `find.byType(Switch)` finds it. If the widget uses `CupertinoSwitch`, change the test finder to that type and record a ruling.
  - Current-PIN check uses `store.check`.
  - Messages use the verbatim copy. Every step has an AppBar back arrow that returns to overview. The title is "Safety PIN".
  - Route in `app_router.dart` (snapshot):
    - Add `static const String safetyPin = '/settings/safety-pin';` to `RouteNames`.
    - Add `GoRoute(path: RouteNames.safetyPin, name: 'safetyPin', builder: (context, state) => const SafetyPinScreen())` next to the `safetyResources` route.
  - Settings row (`settings_data.dart`, snapshot): directly after the `safety_resources` `SettingsConfig`, add
```dart
          SettingsConfig(
            id: 'safety_pin',
            title: 'Safety PIN',
            subtitle: 'Asked for after you use quick exit',
            icon: Icons.pin_outlined,
            type: SettingsItemType.navigation,
            routeName: '/settings/safety-pin',
            iconColor: Colors.redAccent,
            order: 2,
          ),
```
  - Support resources card (`safety_resources_screen.dart`, snapshot): first child of the body `Column`, add `const SafetyPinPromptCard(),`. It is defined in the PIN screen file as a `ConsumerStatefulWidget`.
    - On init it reads `SafetyPinStore.instance.hasPin()` and the prefs key.
    - If there is no PIN and the card isn't dismissed, it shows a `CardInkWell` with the title, body and two buttons. "Set PIN" calls `context.pushNamed('safetyPin')`; "Not now" sets the prefs key and hides the card.
    - Otherwise it renders `SizedBox.shrink()`.
    - Add a test in the same test file: "Support resources offers the PIN once". Pump `SafetyResourcesScreen` in a GoRouter, expect "Set a Safety PIN", tap "Not now", rebuild, and expect it gone.
- [ ] **Step 3:** Run the tests and `test/features/settings`; all green. Format the new files, analyze, diff, and ledger.

---

### Task 6: Where you're signed in (F7 (1), (2))

**Files:** `lib/features/account/data/account_sessions.dart`, `lib/features/account/presentation/signed_in_devices_screen.dart`, `lib/features/account/presentation/new_device_notice.dart` (replaces the Task 3 stub), `app_router.dart` (route), `settings_data.dart` (row), and tests `test/features/account/account_sessions_test.dart`, `signed_in_devices_screen_test.dart`, `new_device_notice_test.dart`.

**Interfaces — Produces:**
- `class SignedInDevice { sessionId, label?, platform?, signedInAt, lastActiveAt, isCurrent; factory fromRow(Map) }`.
- `typedef SessionsRpc = Future<dynamic> Function(String fn, [Map<String, dynamic>? params])`.
- `class AccountSessionsRepository`:
  - constructor `AccountSessionsRepository(SessionsRpc rpc, Future<void> Function() signOutOthers)`;
  - `Future<List<SignedInDevice>> list()`;
  - `Future<void> registerThisDevice()`;
  - `Future<void> signOutOtherDevices()`.
- `String thisDeviceLabel()` and `String thisDevicePlatform()`, both pure over `Platform`.
- `Set<String> newSessionIds({required Set<String>? known, required List<SignedInDevice> now})`. It returns the ids of non-current sessions that are not in `known`; when `known` is null (first run) it returns empty.
- `accountSessionsRepositoryProvider`, `signedInDevicesProvider` (`FutureProvider.autoDispose`), `newDeviceNoticeProvider` (`StateProvider<SignedInDevice?>`).
- `RouteNames.signedInDevices = '/settings/signed-in-devices'`, with route name `'signedInDevices'`.

- [ ] **Step 1: Failing tests (excerpts — write them in full in the files).**
  - `account_sessions_test.dart`:
    - `fromRow` parses all six fields.
    - `list()` calls `list_my_sessions`.
    - `registerThisDevice()` calls `register_my_device` with `{'p_label', 'p_platform'}`.
    - `signOutOtherDevices()` calls the injected function.
    - `newSessionIds`:
      - first run (`known` null) gives an empty set;
      - known {a}, now [a, b (not current)] gives {b};
      - now [c (current)] gives empty;
      - known {a}, now [] gives empty.
  - `signed_in_devices_screen_test.dart`: override `signedInDevicesProvider` with two devices (one current) and the repository with a fake.
    - It shows "iPhone or iPad · iOS 17.2 · This phone" and "Android phone".
    - Each subtitle contains "Last active".
    - Tapping "Sign out all other devices" opens the confirm. Tapping "Sign out others" calls the fake exactly once, shows "Other devices are signed out." and invalidates the list.
    - With one device, it shows "Only this phone is signed in." and no button.
  - `new_device_notice_test.dart`: pump `NewDeviceNotice(router: testRouter, child: Text('APP'))` with `newDeviceNoticeProvider` set to a device.
    - It shows the notice copy with the label and `MyDateFormat.toDate`.
    - "Dismiss" clears it.
    - "Review" navigates to the `signedInDevices` route (a stub route in the test router).
    - Add the pure watcher test: `NewDeviceWatcher.check(...)` with a fake repository and mock prefs records the known ids on first run (no notice), then reports a new one.
- [ ] **Step 2: Implementation (key pieces).**
```dart
// lib/features/account/data/account_sessions.dart  (excerpt; write the file in full)
String thisDevicePlatform() {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'other';
}

String thisDeviceLabel() {
  if (kIsWeb) return 'Web';
  if (Platform.isIOS) {
    final m = RegExp(r'Version ([0-9.]+)').firstMatch(Platform.operatingSystemVersion);
    return m == null ? 'iPhone or iPad' : 'iPhone or iPad · iOS ${m.group(1)}';
  }
  if (Platform.isAndroid) return 'Android phone';
  return 'This device';
}

Set<String> newSessionIds({required Set<String>? known, required List<SignedInDevice> now}) {
  if (known == null) return const {};
  return {for (final d in now) if (!d.isCurrent && !known.contains(d.sessionId)) d.sessionId};
}

final accountSessionsRepositoryProvider = Provider<AccountSessionsRepository>((ref) {
  final client = Supabase.instance.client;
  return AccountSessionsRepository(
    (fn, [params]) => client.rpc(fn, params: params),
    () => client.auth.signOut(scope: SignOutScope.others),
  );
});
```
  - `NewDeviceWatcher` (in `new_device_notice.dart`):
    - `static Future<SignedInDevice?> check(AccountSessionsRepository repo, String userId)`.
      - Calls `registerThisDevice()` (errors swallowed), then `list()`.
      - Reads `account_known_sessions:<userId>` (a JSON list) from `SharedPreferences`.
      - Computes `newSessionIds`, writes back the full set of current session ids, and returns the newest new device, or null.
      - Every error is swallowed and returns null.
    - The `NewDeviceNotice` widget is a `ConsumerStatefulWidget`.
      - It runs `check` on init and on resume (an `AppLifecycleListener`, throttled to 5 minutes), plus on a `currentUserProvider` change to non-null.
      - It sets `newDeviceNoticeProvider`.
      - It renders `Stack(children: [child, if (device != null) Positioned(left: 16, right: 16, bottom: viewPadding.bottom + 72, child: Material(elevation: 3, borderRadius: 16, child: … copy … Row[TextButton('Dismiss'), FilledButton('Review')]))])`.
      - "Review" calls `router.pushNamed('signedInDevices')` and clears the provider.
  - `SignedInDevicesScreen`:
    - A `Scaffold` with the AppBar title "Where you're signed in".
    - A body list of `InfoRowWidget` rows. Title is `label ?? 'Unnamed device'` plus `' · This phone'` when current. Subtitle per the copy. Icon `Icons.phone_iphone` / `Icons.phone_android` / `Icons.devices`. `showAvatar: false`, `showTrailingArrow: false`.
    - With more than one device, an `AppButton(label: 'Sign out all other devices')` at the bottom opens the `ConfirmationDialog` via `BottomSheetUtils.showDocumentationBottomSheet` (the pattern in `logout_action.dart`). On confirm it calls `signOutOtherDevices()`, then `ref.invalidate(signedInDevicesProvider)` and `context.showSuccessSnackbar('Other devices are signed out.')`.
    - Loading shows a `CircularProgressIndicator`. Error shows `EmptyStateWidget(icon: Icons.devices, title: "Couldn't load your devices", subtitle: 'Try again in a moment.')`.
  - Route: add `RouteNames.signedInDevices` and its `GoRoute` (as for the PIN route).
  - Settings row in the `account` section, after `blocked`/`muted`:
```dart
            SettingsConfig(
              id: 'signed_in_devices',
              title: "Where you're signed in",
              subtitle: 'See the phones on your account',
              icon: Icons.devices_outlined,
              type: SettingsItemType.navigation,
              routeName: '/settings/signed-in-devices',
              iconColor: theme.colorScheme.primary,
              order: 7,
            ),
```
  Before choosing `order`, check the account section's existing values. Pick the slot after `muted`, and record the value used.
- [ ] **Step 3:** Run the tests and `test/features/settings`; all green. Format the new files, analyze, and ledger. Record `F7 (3)` (no partner recovery path exists: phone OTP only) and `F7 (4)` (N/A, ruling R2-8).

---

### Task 7: Manual, full runs, review

- [ ] **Step 1:** In `safety_docs.dart` (snapshot), read the PIN text at `:158` and `:225`. Rewrite only those strings so they describe what was built:
  - set the PIN in Settings → Safety PIN or from Support resources;
  - it is asked for after quick exit, and optionally every open;
  - forgetting it means signing out and back in with the phone number;
  - there is no wipe.

  Add an FAQ in the same file, `faq_safety_signed_in`: "Can I see where my account is signed in?" — "Yes. Settings → Where you're signed in lists every phone signed in to your account. You can sign out all the others at once; it can take up to an hour for another phone to notice."
- [ ] **Step 2:** Full runs. Run `flutter test` (full), with only the known time-of-day test allowed to fail (and only between 00:00 and 05:00). Run the full SQL suite: PASS 92 = 91 + 1 new, with failures identical to baseline. Then:
  - Run `flutter analyze` on every touched or new file.
  - Run the privacy greps: no `debugPrint`/`print(`/`log(` in `lib/features/safety/**` or `lib/features/account/**`, and no `pin` value or session id in any log.
- [ ] **Step 3:** Owner hand-off (into the ledger):
  1. `supabase db push` (2 migrations).
  2. Ship the app build (Android and iOS).
  3. Device matrix (F2 (7), F3 (2), (3)):
     - triple-tap on Settings, the full-screen map, a game, the journal and a dialog;
     - Android, three OEMs: Attune gone from Recents;
     - iOS: the switcher shows the neutral cover;
     - set a PIN, quick exit, kill the app while the decoy is showing, reopen: the PIN screen comes first;
     - five wrong PINs: the delay shows and survives a kill;
     - "Forgot PIN?" leads to the login screen;
     - a second phone signs in: the first phone shows the notice;
     - "Sign out all other devices": the second phone is signed out within an hour.
- [ ] **Step 4:** Final review. Build a review package of snapshot diffs plus the new files. Dispatch Fable with this plan, the F2/F3/F7 rows, the Review Focus and the ledger rulings. Make one fix pass, every fix test-first. Ledger.
