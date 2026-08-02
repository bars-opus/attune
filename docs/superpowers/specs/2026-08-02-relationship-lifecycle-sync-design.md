# Relationship Lifecycle Sync — Design

**Goal:** Close two confirmed gaps found while auditing `ChatCouplesLockedScreen`: (1) a user who sends a couples invite has no way to learn their partner accepted it, short of the sender re-sending; (2) there is no way to end a relationship anywhere in the app, and even if there were, local `OnboardingMode` would never reflect it.

## 1. Root cause and shared fix

`OnboardingMode` (`personal | couplesPending | couples`) lives entirely in `SharedPreferences` via `OnboardingStore` (`lib/features/onboarding/data/onboarding_store.dart`). It is written only by explicit local actions (`complete()`, `startCouplesInvite()`) and never read back from the server. Meanwhile `relationships.status` (`pending | active | paused | ended`) is the real source of truth and can change from a source the local device doesn't control — the *other* partner accepting an invite, or either partner ending the relationship. Nothing reconciles the two. Both gaps are the same root cause in two directions (pending→active, active→ended), so both are fixed by one mechanism.

### `OnboardingStore.syncModeFromServer(OnboardingMode mode)`

A new write method, same shape as the existing `startCouplesInvite()`:

```dart
/// Overwrites the locally-cached mode with a value derived from the
/// server's relationships.status — the one place mode is written from a
/// source other than the user's own device (see syncRelationshipMode in
/// HomeScreen). completed/displayName are untouched.
Future<void> syncModeFromServer(OnboardingMode mode) async {
  await _prefs.setString(_key(_modeKey), mode.name);
}
```

### The reconciliation call: `HomeScreen._syncRelationshipMode()`

A new private method on `_HomeScreenState`, added to the existing `WidgetsBinding`/`initState` machinery already in that file:

```dart
Future<void> _syncRelationshipMode() async {
  final store = await _storeFuture;
  if (store.mode == OnboardingMode.personal) return; // nothing to reconcile
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  // ORDER BY + LIMIT 1 rather than a bare .maybeSingle(): the master spec's
  // idx_one_active_relationship_pair constraint guarantees at most one
  // active/pending relationship per user at a time, but a user can
  // accumulate multiple *ended* rows over their history — this always
  // resolves to the most recent one.
  final row = await supabase
      .from('relationships')
      .select('status, user_a, user_b')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

  final resolved = switch (row?['status'] as String?) {
    'active' => OnboardingMode.couples,
    'pending' => OnboardingMode.couplesPending,
    _ => OnboardingMode.personal, // no row, 'ended', or 'paused'
  };

  if (resolved != store.mode) {
    await store.syncModeFromServer(resolved);
    if (mounted) setState(() => _storeFuture = _loadStore());
  }
}
```

The `store.mode == personal` early return matters: a user who has never sent or received an invite has no `relationships` row at all, so every resume would otherwise run a pointless query. Once `mode` is `couplesPending` or `couples`, the check runs on every resume/cold start until it resolves back to `personal`.

`'paused'` intentionally resolves to `personal` here, not a new mode — no UI in this codebase currently distinguishes a paused relationship from an ended one for the couples/chat surface, and inventing that distinction is out of scope for this fix (paused is used elsewhere, e.g. Dating Mode eligibility, but not by `ChatCouplesLockedScreen`/`AuthenticatedChatWorkspace`, which only ever branches on `couples` vs. not).

### Wiring: app resume + cold start

`HomeScreen` (`lib/home/home_screen.dart`) gains `WidgetsBindingObserver`, mirroring the existing pattern in `chat_screen.dart`:

```dart
class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ... existing initState body (unchanged) ...
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRelationshipMode());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncRelationshipMode();
  }
}
```

Cold start is covered by the `addPostFrameCallback` in `initState`; every subsequent foreground is covered by `didChangeAppLifecycleState`. This is deliberately push-independent: it self-heals even if OneSignal permission was denied, the notification was dismissed unread, or delivery simply failed — the worst case is "found out when you next open the app" rather than "never found out."

## 2. Gap 1 — invite acceptance notification

`accept-invite/index.ts` currently updates `relationships` and returns, with no notification of any kind to `relationship.user_a` (confirmed by reading the function directly — no import of the OneSignal helper exists). Add one call after the update succeeds, using the exact helper and payload shape `send-notification/index.ts` already establishes:

```ts
await sendOneSignalPush({
  userId: relationship.user_a,
  title: 'Your partner joined Attune',
  body: 'You can start chatting now.',
  data: { type: 'invite_accepted', screen: 'chat' },
});
```

This call is best-effort: if it throws, the function still returns success for the accept itself (the relationship update already committed) — a failed push must never make `accept-invite` appear to fail to the accepting user, since the resume-resync (§1) is the real safety net, not the push.

## 3. Gap 2 — ending a relationship

### RPC: `end_relationship(p_relationship_id uuid)`

New `SECURITY DEFINER` RPC, callable by either participant of an `active` relationship:

```sql
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

`chat_archived_reason = 'manual_end'` already exists as a valid CHECK value (`20260705120000_chat_system_v1_2.sql`, alongside `'partner_new_relationship'`) — it was defined for exactly this scenario but no code path has ever written it until now, confirmed by grepping every migration and edge function for `'manual_end'`. No schema changes needed; this RPC is the first writer.

The RPC is called from a new edge function, `end-relationship` (user-JWT, thin wrapper matching the `accept-invite`/`create-relationship-invite` pattern: `requireUser`, call the RPC, then send the other-partner push, then return). The push:

```ts
const otherPartnerId = relationship.user_a === user.id ? relationship.user_b : relationship.user_a;
if (otherPartnerId) {
  await sendOneSignalPush({
    userId: otherPartnerId,
    title: 'Your relationship has ended',
    body: 'Reach out if you have questions, or take some time — we\'re here when you\'re ready.',
    data: { type: 'relationship_ended', screen: 'home' },
  });
}
```

Same best-effort framing as §2 — a failed push never blocks the RPC's already-committed effect, and the resume-resync catches it regardless.

### Client: Settings entry point

Settings is data-driven (`lib/features/settings/screens/settings_screen.dart` renders sections from `SettingsDataSource.getSettingsSections`, `lib/features/settings/data/settings_data.dart`) — no existing irreversible-action section exists to extend (confirmed: no "delete account" or similar action exists anywhere in this codebase yet), so this adds a new section entry there, gated behind a confirmation dialog:

> "End this relationship? This can't be undone. Your chat history will be archived and no longer accessible from either side."

On confirm: call the new `end-relationship` edge function via a thin repository method (mirroring `RelationshipInviteService`'s shape). On success: call `HomeScreen`'s `_syncRelationshipMode()` immediately (don't wait for the next resume — the ending user already knows), then show a one-time prompt: "Would you like to start your healing journey?" with a button pushing to Healing Mode's entry route, and a "Not now" dismissal. No changes needed to `HealingRepository.getStartableRelationship()` — it already queries `status = 'ended'` (`lib/features/healing/data/repositories/healing_repository.dart:47`), so the newly-ended relationship is immediately eligible with zero healing-side changes.

## 4. What this does NOT change

- `ChatCouplesLockedScreen` itself is unmodified — it already renders correctly once `isPendingCouples`/`isCouples` reflect reality; the fix is entirely upstream of it (`HomeScreen` + `OnboardingStore` + two edge functions).
- No push-tap deep-linking is built. The `data.screen` field is included in both payloads for forward compatibility (matching `send-notification`'s existing convention of always including `type`/`screen`) but nothing reads it yet — the resume-resync makes tap-handling unnecessary for correctness, only useful for snappier feel, and that's an explicit non-goal here.
- `'paused'` relationships are not given a distinct local mode (see §1).
- No changes to Ask 2 eligibility, Dating Mode eligibility, or any other consumer of `relationships.status` — this fix only touches the client-local `OnboardingMode` cache and the two write paths (`accept-invite`, new `end-relationship`) that needed a notification.

## 5. Testing evidence expected at implementation time

- Unit test for `syncMode`'s status→mode mapping (`active`→`couples`, `pending`→`couplesPending`, `ended`/`paused`/no-row→`personal`) as a pure function, extracted so it's testable without a live Supabase client.
- A test proving `_syncRelationshipMode`'s early return when `store.mode == personal` (no query fired).
- Manual verification checklist (no live Supabase project in this sandboxed environment, consistent with prior work in this session): invite acceptance triggers a push to the inviter and the inviter's app self-heals to `couples` mode on next resume even without tapping the push; `end_relationship` correctly rejects a non-participant and a non-active relationship; ending a relationship archives chat (`chat_archived_at` set, `ConversationsScreen`'s existing archived-chat handling — unmodified by this spec — takes over); the other partner receives a push and self-heals to `personal` mode on next resume; a newly-ended relationship is immediately visible to `HealingRepository.getStartableRelationship()`.
