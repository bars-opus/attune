# Relationship Lifecycle Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two confirmed gaps in the couples-invite/relationship lifecycle: the inviter never learns their invite was accepted, and there is no way to end a relationship at all — both fixed by a single client-side reconciliation mechanism plus two push notifications.

**Architecture:** A new `OnboardingStore.syncModeFromServer()` write method plus a `HomeScreen._syncRelationshipMode()` reconciliation call (wired to `WidgetsBindingObserver`'s app-resume hook and cold start) pulls `relationships.status` from the server and corrects the local-only `OnboardingMode` cache in both directions. `accept-invite` gains a best-effort push to the inviter. A new `end_relationship` RPC plus `end-relationship` edge function lets either partner end a relationship, archiving chat via the already-existing `chat_archived_reason = 'manual_end'` schema value, with a best-effort push to the other partner. A new Settings entry triggers it via the existing `ConfirmationDialog`/`SettingsConfig` pattern.

**Tech Stack:** Flutter (`WidgetsBindingObserver`, `SharedPreferences` via `OnboardingStore`), Supabase (Postgres RPC, RLS, Deno edge functions), OneSignal push via the existing `_shared/onesignal_push.ts` helper.

## Global Constraints

- `syncMode`'s status→mode mapping is exactly: `'active'` → `OnboardingMode.couples`; `'pending'` → `OnboardingMode.couplesPending`; anything else (`'ended'`, `'paused'`, or no row) → `OnboardingMode.personal`. No other mapping is valid (design spec §1).
- Every push notification added by this plan (`accept-invite`, `end-relationship`) is **best-effort**: a push failure must never cause the RPC's already-committed database effect to appear as a failure to the calling user. The resume-resync is the correctness guarantee; the push is only a latency improvement (design spec §2, §3).
- `end_relationship`'s RPC sets exactly four columns in one `UPDATE`: `status = 'ended'`, `ended_at = now()`, `ended_by = auth.uid()`, `chat_archived_at = now()`, `chat_archived_reason = 'manual_end'` — `'manual_end'` is an already-valid CHECK constraint value with no prior writer; do not add a new CHECK value (design spec §3).
- `end_relationship` only operates on a relationship where the caller is `user_a` or `user_b` and `status = 'active'` — reject (via `RAISE EXCEPTION`) anything else, including a caller's own already-`pending` or already-`ended` relationship (design spec §3).
- No push-tap deep-linking is built in this plan. `data.screen` is included in both new push payloads for forward-compatibility only (design spec §4) — do not wire up any click listener.
- `HomeScreen`'s existing `initState`/`dispose`/`_authSubscription` logic must remain unmodified in behavior — the new `WidgetsBindingObserver` wiring is additive only (design spec §1, confirmed exact current file content in Task 1's brief).

---

## File Structure

- **Modify:** `lib/features/onboarding/data/onboarding_store.dart` — add `syncModeFromServer`.
- **Create:** `lib/features/onboarding/domain/relationship_mode_sync.dart` — pure function mapping a `relationships.status` string to `OnboardingMode`, extracted so it's unit-testable without a live Supabase client (mirrors this codebase's `decideModerationOutcome` pattern).
- **Modify:** `lib/home/home_screen.dart` — add `WidgetsBindingObserver`, `_syncRelationshipMode()`.
- **Modify:** `supabase/functions/accept-invite/index.ts` — add the inviter push.
- **Create:** `supabase/migrations/20260815120000_end_relationship.sql` — `end_relationship` RPC.
- **Create:** `supabase/functions/end-relationship/index.ts` — thin edge function wrapping the RPC + other-partner push.
- **Create:** `lib/features/relationships/data/relationship_lifecycle_service.dart` — client-side caller for `end-relationship`, mirroring `RelationshipInviteService`'s shape; also hosts `activeRelationshipIdProvider`, a feature-local Riverpod provider (matching this codebase's established per-feature convention) used to resolve the relationship id at Settings-tap time.
- **Create:** `lib/features/relationships/presentation/widgets/end_relationship_action.dart` — `EndRelationshipAction.confirmAndEnd(context)`, mirroring `LogoutAction`.
- **Modify:** `lib/features/settings/data/settings_data.dart` — add the Settings entry.
- **Test:** `test/features/onboarding/relationship_mode_sync_test.dart`, `test/home/home_screen_sync_test.dart`.

---

### Task 1: Pure sync-mapping function + `OnboardingStore.syncModeFromServer`

**Files:**
- Create: `lib/features/onboarding/domain/relationship_mode_sync.dart`
- Test: `test/features/onboarding/relationship_mode_sync_test.dart`
- Modify: `lib/features/onboarding/data/onboarding_store.dart`

**Interfaces:**
- Consumes: `OnboardingMode` enum (`lib/features/onboarding/domain/onboarding_models.dart:1` — exactly `enum OnboardingMode { personal, couplesPending, couples }`, already exists, unmodified).
- Produces: `OnboardingMode resolveModeFromRelationshipStatus(String? status)` (pure function); `OnboardingStore.syncModeFromServer(OnboardingMode mode) → Future<void>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/onboarding/relationship_mode_sync_test.dart
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active status resolves to couples', () {
    expect(resolveModeFromRelationshipStatus('active'), OnboardingMode.couples);
  });

  test('pending status resolves to couplesPending', () {
    expect(resolveModeFromRelationshipStatus('pending'), OnboardingMode.couplesPending);
  });

  test('ended status resolves to personal', () {
    expect(resolveModeFromRelationshipStatus('ended'), OnboardingMode.personal);
  });

  test('paused status resolves to personal', () {
    expect(resolveModeFromRelationshipStatus('paused'), OnboardingMode.personal);
  });

  test('null status (no relationship row) resolves to personal', () {
    expect(resolveModeFromRelationshipStatus(null), OnboardingMode.personal);
  });

  test('unrecognized status resolves to personal, not a crash', () {
    expect(resolveModeFromRelationshipStatus('some_future_status'), OnboardingMode.personal);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/onboarding/relationship_mode_sync_test.dart`
Expected: FAIL — `relationship_mode_sync.dart` does not exist.

- [ ] **Step 3: Write the pure function**

```dart
// lib/features/onboarding/domain/relationship_mode_sync.dart
import 'package:attune/features/onboarding/domain/onboarding_models.dart';

/// Maps a relationships.status value (server source of truth) to the
/// OnboardingMode the client should locally cache. Pure and side-effect
/// free so it's testable without a live Supabase client — the actual
/// server round-trip lives in HomeScreen._syncRelationshipMode.
///
/// 'paused' intentionally resolves to personal, not a distinct mode: no UI
/// in this codebase distinguishes a paused relationship from an ended one
/// on the couples/chat surface (see design spec
/// docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
/// §1). An unrecognized/future status also resolves to personal rather
/// than throwing, so a server-side enum addition never crashes the client.
OnboardingMode resolveModeFromRelationshipStatus(String? status) {
  switch (status) {
    case 'active':
      return OnboardingMode.couples;
    case 'pending':
      return OnboardingMode.couplesPending;
    default:
      return OnboardingMode.personal;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/onboarding/relationship_mode_sync_test.dart`
Expected: PASS, 6/6 tests.

- [ ] **Step 5: Add `syncModeFromServer` to `OnboardingStore`**

Add this method to the `OnboardingStore` class in `lib/features/onboarding/data/onboarding_store.dart`, placed directly after the existing `startCouplesInvite()` method (do not modify `startCouplesInvite()` itself):

```dart
  /// Overwrites the locally-cached mode with a value derived from the
  /// server's relationships.status — the one place mode is written from a
  /// source other than the user's own device. Called by
  /// HomeScreen._syncRelationshipMode after resolving the server state via
  /// resolveModeFromRelationshipStatus. completed/displayName are
  /// untouched, matching startCouplesInvite's own scope.
  Future<void> syncModeFromServer(OnboardingMode mode) async {
    await _prefs.setString(_key(_modeKey), mode.name);
  }
```

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/features/onboarding test/features/onboarding`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/onboarding/domain/relationship_mode_sync.dart
git add test/features/onboarding/relationship_mode_sync_test.dart
git add lib/features/onboarding/data/onboarding_store.dart
git commit -m "feat(onboarding): add relationship-status-to-mode sync mapping"
```

---

### Task 2: `HomeScreen` resume/cold-start reconciliation

**Files:**
- Modify: `lib/home/home_screen.dart`

**Interfaces:**
- Consumes: `resolveModeFromRelationshipStatus`, `OnboardingStore.syncModeFromServer` (Task 1).
- Produces: `_HomeScreenState._syncRelationshipMode()` — no external callers, wired only to lifecycle hooks within this file.

`_HomeScreenState`'s exact current content (confirmed by reading the file directly before this plan was written) is:

```dart
class _HomeScreenState extends State<HomeScreen> {
  // ... existing fields: _authService, _syncService, _authSubscription,
  //     late Future<OnboardingStore> _storeFuture, String? _scopeUserId ...

  @override
  void initState() {
    super.initState();
    _scopeUserId = _authService.currentUser?.id;
    _storeFuture = _loadStore();
    _authSubscription = _authService.authStateChanges.listen((_) {
      if (!mounted) return;
      final userId = _authService.currentUser?.id;
      if (userId == _scopeUserId) return;
      setState(() {
        _scopeUserId = userId;
        _storeFuture = _loadStore();
      });
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<OnboardingStore> _loadStore() async {
    // ... existing body, unmodified ...
  }
}
```

- [ ] **Step 1: Add the `WidgetsBindingObserver` mixin and lifecycle wiring**

Change the class declaration from:
```dart
class _HomeScreenState extends State<HomeScreen> {
```
to:
```dart
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
```

Add `WidgetsBinding.instance.addObserver(this);` as the first line inside `initState`, immediately after `super.initState();`, and add a call to schedule the first sync at the end of `initState` (after the existing `_authSubscription` assignment, still inside the method body):

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scopeUserId = _authService.currentUser?.id;
    _storeFuture = _loadStore();
    _authSubscription = _authService.authStateChanges.listen((_) {
      if (!mounted) return;
      final userId = _authService.currentUser?.id;
      if (userId == _scopeUserId) return;
      setState(() {
        _scopeUserId = userId;
        _storeFuture = _loadStore();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRelationshipMode());
  }
```

Add `WidgetsBinding.instance.removeObserver(this);` as the first line inside `dispose`:

```dart
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    super.dispose();
  }
```

- [ ] **Step 2: Add the lifecycle hook and the reconciliation method**

Add both as new methods on `_HomeScreenState`, placed after `dispose()`:

```dart
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncRelationshipMode();
  }

  /// Reconciles the locally-cached OnboardingMode against the server's
  /// relationships.status, in both directions: a partner accepting an
  /// invite (pending -> active) and either partner ending a relationship
  /// (active -> ended). This is the self-healing half of the fix — it
  /// runs independent of whether a push notification was delivered,
  /// tapped, or missed entirely, so the worst case is "found out when you
  /// next open the app" rather than "never found out." See design spec
  /// docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md
  /// §1.
  Future<void> _syncRelationshipMode() async {
    final store = await _storeFuture;
    if (store.mode == OnboardingMode.personal) return;

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final row = await supabase
        .from('relationships')
        .select('status')
        .or('user_a.eq.$userId,user_b.eq.$userId')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final resolved = resolveModeFromRelationshipStatus(row?['status'] as String?);
    if (resolved != store.mode) {
      await store.syncModeFromServer(resolved);
      if (mounted) setState(() => _storeFuture = _loadStore());
    }
  }
```

- [ ] **Step 3: Add the required imports**

Add to the top of `lib/home/home_screen.dart`, alongside its existing imports:

```dart
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```

(If any of these are already imported via this file's existing imports — check before adding, since `export_screens.dart` or another existing barrel import may already bring in `OnboardingMode` or `Supabase` — do not create a duplicate import.)

- [ ] **Step 4: Write the widget test**

```dart
// test/home/home_screen_sync_test.dart
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/domain/relationship_mode_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Full HomeScreen widget testing requires a live/mocked Supabase client
  // and OnboardingStore, which this codebase has no existing test harness
  // for (see design spec's Testing Evidence section). This test instead
  // covers the one piece of _syncRelationshipMode's logic that's a pure
  // decision independent of any live client: that the resolved mode is
  // only considered "changed" (triggering a write + rebuild) when it
  // actually differs from the current cached mode.
  test('resolved mode differs from cached mode when relationship became active', () {
    const cachedMode = OnboardingMode.couplesPending;
    final resolvedMode = resolveModeFromRelationshipStatus('active');
    expect(resolvedMode == cachedMode, isFalse);
    expect(resolvedMode, OnboardingMode.couples);
  });

  test('resolved mode matches cached mode when nothing changed (no-op case)', () {
    const cachedMode = OnboardingMode.couplesPending;
    final resolvedMode = resolveModeFromRelationshipStatus('pending');
    expect(resolvedMode == cachedMode, isTrue);
  });
}
```

- [ ] **Step 5: Run the test**

Run: `flutter test test/home/home_screen_sync_test.dart`
Expected: PASS, 2/2 tests.

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/home test/home`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/home/home_screen.dart
git add test/home/home_screen_sync_test.dart
git commit -m "feat(home): reconcile OnboardingMode from server on resume/cold start"
```

---

### Task 3: `accept-invite` push notification

**Files:**
- Modify: `supabase/functions/accept-invite/index.ts`

**Interfaces:**
- Consumes: `sendOneSignalPush` from `_shared/onesignal_push.ts` (already exists, signature: `sendOneSignalPush(input: { userId: string; title: string; body: string; data?: Record<string, unknown>; idempotencyKey?: string })`).
- Produces: nothing new consumed by later tasks — this is a terminal addition to an existing function.

- [ ] **Step 1: Add the import**

In `supabase/functions/accept-invite/index.ts`, add to the existing import block at the top of the file:

```typescript
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";
```

- [ ] **Step 2: Add the push call after the relationship update succeeds**

The current function body has this sequence (already existing, do not modify): the `relationships` UPDATE (`user_b`, `status: "active"`, `invite_code: null`, `invite_accepted_at`), then the `relationship_invite_acceptances` INSERT, then the success `jsonResponse`. Insert the push call after the `relationship_invite_acceptances` INSERT succeeds and before the final `return jsonResponse(...)`:

```typescript
    // Best-effort: a failed push must never make this endpoint appear to
    // fail to the accepting user — the relationship update already
    // committed, and HomeScreen._syncRelationshipMode's resume-resync is
    // the correctness guarantee, not this push. See design spec
    // docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §2.
    try {
      await sendOneSignalPush({
        userId: relationship.user_a,
        title: "Your partner joined Attune",
        body: "You can start chatting now.",
        data: { type: "invite_accepted", screen: "chat" },
      });
    } catch (pushError) {
      console.error(
        "accept-invite: push notification failed (non-fatal):",
        pushError instanceof Error ? pushError.message : "unknown",
      );
    }

    return jsonResponse({
      relationship_id: updated.id,
      status: updated.status,
      idempotent: false,
    });
```

Note: `relationship.user_a` (from the earlier `SELECT` in this same function, variable name confirmed by reading the current file) is the inviter's user id — the accepting user is `user.id`, never the push target.

- [ ] **Step 3: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/accept-invite && deno check index.ts`
Expected: no type errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/accept-invite/index.ts
git commit -m "feat(relationships): notify inviter when their invite is accepted"
```

Note: no automated test for this task. No precedent exists in this codebase for testing an edge function that wraps a Postgres RPC/table write and sends a push (confirmed: no `.test.ts` exists for `accept-invite`, `create-relationship-invite`, or `send-notification`; existing Deno tests are confined to pure-logic `_shared` modules). `deno check` type-checking plus the plan's final manual-verification checklist is the verification for this task, consistent with this codebase's established practice for side-effecting edge functions.

---

### Task 4: `end_relationship` database migration

**Files:**
- Create: `supabase/migrations/20260815120000_end_relationship.sql`

**Interfaces:**
- Consumes: existing `relationships` table (`id, user_a, user_b, status, chat_archived_at, chat_archived_reason, ended_at, ended_by` columns, all already exist per `20260606120000_attune_core_schema.sql` and `20260705120000_chat_system_v1_2.sql`).
- Produces: RPC `public.end_relationship(p_relationship_id uuid) RETURNS void`.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260815120000_end_relationship.sql
--
-- First writer of chat_archived_reason = 'manual_end' — that CHECK value
-- has existed since 20260705120000_chat_system_v1_2.sql but no code path
-- has ever written it until now. See design spec
-- docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §3.

CREATE OR REPLACE FUNCTION public.end_relationship(p_relationship_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not found or not active';
  END IF;

  UPDATE public.relationships
  SET status = 'ended',
      ended_at = now(),
      ended_by = v_user_id,
      chat_archived_at = now(),
      chat_archived_reason = 'manual_end'
  WHERE id = p_relationship_id;
END;
$$;

REVOKE ALL ON FUNCTION public.end_relationship(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.end_relationship(uuid) TO authenticated;
```

- [ ] **Step 2: Verify the target columns already exist**

Run: `grep -n "ended_at\|ended_by\|chat_archived_at\|chat_archived_reason" supabase/migrations/20260606120000_attune_core_schema.sql supabase/migrations/20260705120000_chat_system_v1_2.sql`
Expected: all four columns found in one of those two files — this migration only writes to pre-existing columns, it does not `ALTER TABLE`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260815120000_end_relationship.sql
git commit -m "feat(relationships): add end_relationship RPC"
```

Note: no automated test — pure DDL/RPC SQL, no live Supabase project in this sandboxed environment. `supabase db push` and live RPC verification are deferred to a human before this branch merges/deploys, consistent with every other migration task in this codebase's recent history.

---

### Task 5: `end-relationship` edge function

**Files:**
- Create: `supabase/functions/end-relationship/index.ts`

**Interfaces:**
- Consumes: `end_relationship` RPC (Task 4); `requireUser`, `HttpError`, `jsonResponse`, `serviceRoleClient` from `_shared/attune_auth.ts` (already exist, used throughout this codebase's edge functions); `sendOneSignalPush` from `_shared/onesignal_push.ts`.
- Produces: an HTTP endpoint accepting `POST { relationship_id: string }` → `{ success: true }`.

- [ ] **Step 1: Write the implementation**

```typescript
// supabase/functions/end-relationship/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { sendOneSignalPush } from "../_shared/onesignal_push.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const relationshipId = typeof body.relationship_id === "string"
      ? body.relationship_id
      : null;
    if (!relationshipId) {
      throw new HttpError("relationship_id is required", 400);
    }

    const supabase = serviceRoleClient();

    // Fetch the other partner's id BEFORE ending it, since end_relationship
    // doesn't return the row and RLS still applies to a plain SELECT here
    // (service role bypasses RLS, but we still scope the WHERE clause to
    // the caller's own relationship rather than trusting relationship_id
    // blindly, matching this codebase's existing service-role caution).
    const { data: relationship, error: fetchError } = await supabase
      .from("relationships")
      .select("user_a, user_b")
      .eq("id", relationshipId)
      .eq("status", "active")
      .or(`user_a.eq.${user.id},user_b.eq.${user.id}`)
      .maybeSingle();
    if (fetchError) throw fetchError;
    if (!relationship) {
      throw new HttpError("Relationship not found or not active", 404);
    }

    const { error: rpcError } = await supabase.rpc("end_relationship", {
      p_relationship_id: relationshipId,
    });
    if (rpcError) throw rpcError;

    // Best-effort, same framing as accept-invite's push (Task 3) — a
    // failed push must never make this endpoint appear to fail, since the
    // RPC's effect already committed. See design spec
    // docs/superpowers/specs/2026-08-02-relationship-lifecycle-sync-design.md §3.
    const otherPartnerId = relationship.user_a === user.id
      ? relationship.user_b
      : relationship.user_a;
    if (otherPartnerId) {
      try {
        await sendOneSignalPush({
          userId: otherPartnerId,
          title: "Your relationship has ended",
          body: "Reach out if you have questions, or take some time — we're here when you're ready.",
          data: { type: "relationship_ended", screen: "home" },
        });
      } catch (pushError) {
        console.error(
          "end-relationship: push notification failed (non-fatal):",
          pushError instanceof Error ? pushError.message : "unknown",
        );
      }
    }

    return jsonResponse({ success: true });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error(
      "end-relationship failed:",
      error instanceof Error ? error.name : typeof error,
    );
    return jsonResponse({ error: "Could not end relationship" }, 500);
  }
});
```

- [ ] **Step 2: Type-check with Deno**

Run: `cd /Users/user/attune/supabase/functions/end-relationship && deno check index.ts`
Expected: no type errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/end-relationship/index.ts
git commit -m "feat(relationships): add end-relationship edge function"
```

Note: no automated test, same reasoning as Task 3 — no precedent in this codebase for testing a side-effecting edge function directly. `deno check` plus the final manual-verification checklist is the verification for this task.

---

### Task 6: Client service + Settings entry point

**Files:**
- Create: `lib/features/relationships/data/relationship_lifecycle_service.dart`
- Create: `lib/features/relationships/presentation/widgets/end_relationship_action.dart`
- Modify: `lib/features/settings/data/settings_data.dart`

**Interfaces:**
- Consumes: `end-relationship` edge function (Task 5). `HomeScreen._syncRelationshipMode` is NOT directly callable from outside `home_screen.dart` (it's a private method) — this task does not attempt to trigger it directly; instead it navigates to Healing Mode's entry route (`RouteNames.healingJourney`) after success, and relies on `HomeScreen`'s own next resume to reconcile mode via the shared mechanism (Task 2), exactly as it already does for the invite-acceptance direction.
- Produces: `RelationshipLifecycleService.endRelationship({required String relationshipId}) → Future<void>`; `activeRelationshipIdProvider` (`FutureProvider<String?>`, defined in the same file as the service); `EndRelationshipAction.confirmAndEnd(BuildContext context, {required String relationshipId})`.

- [ ] **Step 1: Write the client service**

```dart
// lib/features/relationships/data/relationship_lifecycle_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when ending a relationship fails, mirroring
/// RelationshipInviteException's shape (relationship_invite_service.dart)
/// so error handling stays consistent across this feature area.
class RelationshipLifecycleException implements Exception {
  const RelationshipLifecycleException(this.message);
  final String message;

  @override
  String toString() => 'RelationshipLifecycleException: $message';
}

class RelationshipLifecycleService {
  RelationshipLifecycleService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  static const _timeout = Duration(seconds: 30);

  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  Future<void> endRelationship({required String relationshipId}) async {
    try {
      final response = await _safeClient.functions
          .invoke(
            'end-relationship',
            body: {'relationship_id': relationshipId},
          )
          .timeout(_timeout);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw RelationshipLifecycleException(data['error'].toString());
      }
    } catch (error) {
      debugPrint('[relationship-lifecycle] end failed: ${error.runtimeType}');
      if (error is RelationshipLifecycleException) rethrow;
      throw const RelationshipLifecycleException(
        'Could not end this relationship. Please try again.',
      );
    }
  }
}
```

Add the required `debugPrint` import at the top of the file:

```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 2: Write the confirm-and-end action**

```dart
// lib/features/relationships/presentation/widgets/end_relationship_action.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared end-relationship confirmation + action flow, mirroring
/// LogoutAction (lib/features/auth/presentation/widgets/logout_action.dart)
/// so this destructive action goes through the same confirmation-dialog
/// pattern as the rest of this codebase's irreversible actions.
class EndRelationshipAction {
  static void confirmAndEnd(
    BuildContext context, {
    required String relationshipId,
  }) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 340.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        title: 'End this relationship?',
        confirmText: 'End relationship',
        message:
            'This can\'t be undone. Your chat history will be archived and '
            'no longer accessible from either side.',
        onConfirm: () async {
          try {
            await RelationshipLifecycleService().endRelationship(
              relationshipId: relationshipId,
            );
            if (!context.mounted) return;
            context.showSuccessSnackbar('Relationship ended.');
            // No public API exists on HomeScreen to force its private
            // _syncRelationshipMode to run immediately (it's a private
            // method, and this action is triggered from Settings, a
            // separate route pushed on top of HomeScreen) — pushing to
            // Healing Mode's real entry route (RouteNames.healingJourney,
            // confirmed at app_router.dart:196/441, HealingJourneyScreen
            // takes no constructor args) offers the next step immediately;
            // HomeScreen's own next resume (when the user eventually
            // navigates back to it) picks up the mode change via the
            // shared reconciliation mechanism (design spec §1) — no
            // separate signal needs to be sent to HomeScreen from here.
            context.push(RouteNames.healingJourney);
          } catch (error) {
            if (!context.mounted) return;
            final message = error is RelationshipLifecycleException
                ? error.message
                : 'Could not end this relationship. Please try again.';
            context.showErrorSnackbar(message);
          }
        },
      ),
    );
  }
}
```

**IMPORTANT — resolve this before writing the code above:** `RouteNames.healingJourneyOffer` is a placeholder name for "wherever Healing Mode's entry route actually is" — the design spec (§3) calls for a "Would you like to start your healing journey?" prompt after ending succeeds, but this plan was written without confirming the actual healing-mode entry route name. Before implementing this step: run `grep -n "static const String healing" lib/app/routing/app_router.dart` to find the real route constant name, and substitute it for `RouteNames.healingJourneyOffer` above. If no single "offer" route exists (only a full healing-journey-screen route), use `context.push(RouteNames.<actual healing entry route>)` instead of `context.go`, and adjust the comment accordingly. Do not leave `RouteNames.healingJourneyOffer` as literal code — it does not exist and will not compile.

- [ ] **Step 3: Add a feature-local `activeRelationshipIdProvider` to read at tap-time**

`getSettingsSections(BuildContext context, String currentUserId)` builds `SettingsConfig` objects (including their `onTap` closures) once, synchronously, with no `async`/Riverpod access at build time — but `onTap` itself is a closure that fires later, when `context` is still valid and can read a provider on demand. This avoids changing `getSettingsSections`'s signature or any of its existing callers.

Add this provider to `lib/features/relationships/data/relationship_lifecycle_service.dart` (same file as the service, since it's relationship-lifecycle-scoped, following this codebase's established convention of feature-local Riverpod providers seen in `timeline_providers.dart`/`pulse_providers.dart`/etc.):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The caller's current active (status = 'active') relationship id, or
/// null if none. Read on-demand inside EndRelationshipAction's onTap
/// closure (not at SettingsConfig build time) so the Settings entry can
/// gate itself without threading a new parameter through
/// getSettingsSections's existing signature/call sites.
final activeRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final row = await supabase
      .from('relationships')
      .select('id')
      .eq('status', 'active')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .maybeSingle();
  return row?['id'] as String?;
});
```

Add the required import at the top of `relationship_lifecycle_service.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
```

(This import is likely already present from Step 1 — do not duplicate it if so.)

- [ ] **Step 4: Add the Settings entry**

In `lib/features/settings/data/settings_data.dart`, add a new `SettingsConfig` inside the existing `danger`/destructive section (the same section containing the `logout` item, confirmed at lines 268-278 of the current file, itself gated by `if (currentUserId.isNotEmpty)` at line 243), placed before the `logout` entry so logout remains the last, most-final action in the list:

```dart
SettingsConfig(
  id: 'endRelationship',
  title: 'End relationship',
  subtitle: 'Permanently end your relationship on Attune',
  icon: Icons.heart_broken_outlined,
  type: SettingsItemType.destructive,
  onTap: () async {
    final container = ProviderScope.containerOf(context, listen: false);
    final relationshipId = await container.read(
      activeRelationshipIdProvider.future,
    );
    if (relationshipId == null) {
      if (context.mounted) {
        context.showErrorSnackbar('No active relationship to end.');
      }
      return;
    }
    if (context.mounted) {
      EndRelationshipAction.confirmAndEnd(
        context,
        relationshipId: relationshipId,
      );
    }
  },
  iconColor: theme.colorScheme.error,
  order: 0,
),
```

Add the required imports to `settings_data.dart` if not already present:

```dart
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Note: this entry always renders inside the existing `if (currentUserId.isNotEmpty)` section (it does not need its own separate visibility gate) — a user with no active relationship simply sees the "No active relationship to end" error on tap rather than the button being hidden outright, since `getSettingsSections` builds synchronously and can't await the relationship check before deciding whether to include the item. This matches the tap-time-gating approach the async `activeRelationshipIdProvider` read already requires.

- [ ] **Step 5: Run `flutter analyze`**

Run: `flutter analyze lib/features/relationships lib/features/settings`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/features/relationships/data/relationship_lifecycle_service.dart
git add lib/features/relationships/presentation/widgets/end_relationship_action.dart
git add lib/features/settings/data/settings_data.dart
git commit -m "feat(relationships): add end-relationship Settings entry point"
```

---

## Post-implementation manual verification (not a task — a checklist for the final reviewer)

- [ ] Send an invite from User A, accept it from User B; confirm User A receives a push titled "Your partner joined Attune" (requires a linked Supabase project and real device/OneSignal setup — not available in this sandboxed environment).
- [ ] With User A's app already open (foregrounded) when User B accepts, background and re-foreground User A's app; confirm the Chat tab now shows real chat (`ConversationsScreen`), not `ChatCouplesLockedScreen`, without needing to tap the push.
- [ ] Cold-start User A's app after User B has already accepted (push missed/denied); confirm the app resolves to real chat on launch, not the locked screen.
- [ ] From Settings, trigger "End relationship" as User A; confirm the confirmation dialog appears with the exact copy in Task 6 Step 2, and canceling leaves the relationship untouched.
- [ ] Confirm ending; verify `relationships.status = 'ended'`, `chat_archived_at` set, `chat_archived_reason = 'manual_end'` in the database.
- [ ] Confirm User B receives a push titled "Your relationship has ended", and User B's app (foreground resume or cold start) resolves back to `ChatCouplesLockedScreen` (non-pending variant) rather than staying on stale chat.
- [ ] Confirm `HealingRepository.getStartableRelationship()` immediately returns the newly-ended relationship for User A (no changes needed there per design spec §3 — this step only verifies the existing query picks up the new row).
- [ ] Attempt to call `end_relationship` RPC directly (e.g. via SQL) for a relationship the caller is not a participant of; confirm it raises the "not found or not active" exception, not a silent no-op.
- [ ] Attempt to call `end_relationship` twice in a row on the same relationship; confirm the second call raises the same exception (already `ended`, not `active`), rather than double-processing.
