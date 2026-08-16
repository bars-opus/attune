# Ephemeral Video Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user press-and-hold an in-app camera to capture a ≤10-second clip that sends immediately (no confirm step), which the receiver can view exactly once — the video is genuinely deleted server-side the moment either party finishes viewing it, and a "Video expired" tombstone remains in its place.

**Architecture:** Extends Part 1's video-sharing media pipeline (same bucket, same upload-intent RPC, same `ChatVideoPreparer`) rather than building a parallel one — ephemeral video reuses `media_type = 'video'` with a new `is_view_once` flag, not a new media type. The one genuinely new piece of server infrastructure is `mark_video_viewed`, a single atomic RPC that performs the view-guard, the Storage deletion, and the tombstone write together. Revocation propagates to the sender through the chat's existing Postgres-changes subscription — no new realtime channel.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase (Postgres + Storage + RPC), `camera` (new dependency — first live in-app camera preview in this app), `video_player`/`video_compress`/`video_thumbnail` (already dependencies from Part 1, reused as-is).

**Design spec:** `docs/superpowers/specs/2026-08-16-ephemeral-video-capture-design.md` — read it first; this plan implements it exactly. Do not re-derive decisions already made there.

**A note on process for whoever executes this plan:** every file this plan touches was read in full, at its current live state on `main` (post-Part-1-merge, commit history confirmed to have zero chat-related changes since Part 1 landed), before this plan was written. Two load-bearing findings came out of that verification that are not obvious from the spec's prose alone:

1. **`chat_ephemeral_video` needs the SAME paired-flag treatment `chat_video_sharing` already required** (Task 8's flag-gating comment in `chat_screen.dart:625-636` explains why: `create_chat_media_upload_intent` branches purely on `p_media_type`, with no way to distinguish an ephemeral video intent from a gallery video intent — both request `media_type = 'video'`. This means the server-side RPC change in Part 1's migration already, silently, applies to ephemeral video too. The client must additionally gate on `chat_ephemeral_video` being enabled — layered on TOP of the existing `chat_video_sharing AND chat_image_sharing` gate, not instead of it. Getting this wrong reproduces exactly the bug Part 1's final review caught and fixed.
2. **There is no existing "system message" convention anywhere in this codebase** (confirmed by grep across `lib/features/chat/` and `supabase/migrations/` — zero hits for `message_kind`, `is_system`, `SystemMessage`, or similar). The screenshot-notice message (spec Section 7.5) needs a new, minimal convention invented from scratch in this plan (Task 9), not a reuse of something that turned out not to exist.

Trust this plan's file:line references over the spec's prose wherever they'd otherwise conflict.

## Global Constraints

- Max capture duration: **10 seconds** (`Duration(seconds: 10)`), auto-stop while still held, matching Snapchat parity per the approved spec.
- Post-compress byte ceiling for ephemeral clips: **2MB** (`2 * 1024 * 1024`), proportional to Part 1's 800kbps target scaled to 10s.
- **No confirm-before-send step** — releasing the record button sends immediately. A minimum hold duration (mirroring `VoiceRecorderService.minDuration`, 500ms) silently discards accidental taps.
- Audio is captured along with video.
- Front camera default; a flip button switches camera **before** recording starts only, not mid-recording.
- **Real deletion on view, not soft-hide**: `mark_video_viewed` deletes the actual Storage objects and nulls `media_url`/`media_thumbnail_url` on the row. The row itself is never deleted — it survives as a tombstone.
- **`mark_video_viewed` is atomic and idempotent-safe by construction**: `UPDATE ... WHERE viewed_at IS NULL` — first caller (from any device, sender or receiver) does the real work; every subsequent call is a safe no-op. This is the single most safety-critical piece of logic in this feature and must have a direct concurrency/idempotency test, not just a happy-path test (per Algorithm Quality Review Checklist items 1.1/2.18, `[MUTATION]` scope — both cited verbatim in Task 2).
- **Full symmetry confirmed, not a bug**: the sender's own complete view of their sent clip counts as "viewed" and revokes it for the receiver too. No `sender_id` exclusion anywhere in `mark_video_viewed`.
- No new realtime channel — revocation and screenshot-notice delivery both ride the chat's existing Postgres-changes subscription on `messages` (`supabase_chat_repository.dart:481-491`).
- Screenshot detection is best-effort on both platforms: real/reliable on iOS (`UIApplication.userDidTakeScreenshotNotification`), unreliable-but-shipped on Android (`ContentObserver`) — this asymmetry is accepted per the approved spec, not a defect to fix.
- `dart analyze` must stay clean (no new errors/warnings) on every file touched in every task.
- Confirmed current test baseline on `main` (verified by running the suite immediately before writing this plan): `flutter test test/features/chat/` → **192 passed, 2 known pre-existing failures** in `chat_couples_locked_screen_healing_entry_test.dart` ("shows healing entry card when there is no invite" and "tapping the card with an existing solo journey navigates directly, no sheet"). Any other failure in any task's test run is a real regression — root-cause it before marking the task done, never dismiss it.
- **Lesson carried forward from Part 1's final whole-branch review**, which found (after every individual task already passed its own review): a client/server flag-gating mismatch, dead progress-reporting code, and a size guard that was practically unreachable given how the UI constrained its inputs. This plan's tasks are written to close the analogous risks proactively rather than rely on a final review to catch them cold:
  - The flag-gating task (Task 8) explicitly requires the double-AND pairing described above, with a test asserting all flag-state combinations.
  - `ChatVideoPreparer`'s new optional parameters (Task 1) are tested for both "omitted preserves Part 1's exact behavior" AND "passed overrides correctly" — not just the new-value case.
  - `mark_video_viewed`'s atomicity (Task 2) is tested for concurrency from the start, not discovered as a gap during final review.
- When `showCaptureVideo`/`onCaptureVideo` are absent (the default), every existing screen using `ChatTextField` must behave identically to today — `showAttachImage`/`onAttachImage`/`showAttachVideo`/`onAttachVideo`/`showVoiceMessage`/`onVoiceMessageRecorded` are left completely unchanged.
- Checklist scope: **`[MOBILE][MUTATION]`** — same as Part 1. `mark_video_viewed` is the one piece of logic this plan explicitly holds to the `[MUTATION]`-scoped checklist items (1.1, 2.18: "Idempotency keys implemented for all mutations" / "Idempotency implemented for all mutations (same input + retry = same outcome)").

---

### Task 1: `ChatVideoPreparer` gains optional `maxDuration`/`maxBytes` overrides

**Files:**
- Modify: `lib/features/chat/domain/services/chat_video_preparer.dart`
- Test: `test/features/chat/chat_video_preparer_test.dart` (already exists from Part 1 — add to it)

**Interfaces:**
- Produces: `ChatVideoPreparer.prepare()` gains two new optional named parameters, `Duration? maxDuration` and `int? maxBytes`, both defaulting internally to the existing static constants (`ChatVideoPreparer.maxDuration` = 3 minutes, `ChatVideoPreparer.maxBytes` = 25MB) when omitted. Every later task that calls `prepare()` for ephemeral capture (Task 6) passes `maxDuration: Duration(seconds: 10), maxBytes: 2 * 1024 * 1024`.

Current file state (confirmed by reading the file in full immediately before writing this task — 284 lines, includes both of Part 1's final-review fixes: the absolute-source-size guard at line ~131-144, and the `compressProgress$` subscription at lines ~198-232): `prepare()`'s current signature is:

```dart
Future<PreparedChatVideo> prepare({
  required String localPath,
  Duration? trimStart,
  Duration? trimEnd,
  void Function(double)? onProgress,
}) async {
```

The static `maxDuration`/`maxBytes` constants (lines 58-59) are referenced directly inside `prepare()`'s body at three points: the absolute source-size guard (`if (sourceLength > maxSourceBytes)` — **note this uses `maxSourceBytes`, a DIFFERENT constant for the pre-transcode guard, not `maxBytes`** — do not confuse the two), the window-estimate guard (`if (windowEstimate > maxSourceBytes)` — same `maxSourceBytes` constant), the duration-bounds check (`if (effectiveDuration > maxDuration)`), and the post-compress size check (`if (outSize <= 0 || outSize > maxBytes)`). Only the duration-bounds check and the post-compress size check should read the new parameters — `maxSourceBytes` (the pre-transcode guard) is deliberately NOT parameterized by this task, since the spec does not ask for a different pre-transcode source guard for ephemeral capture (a 10-second capture is inherently bounded by the recording UI itself, so the existing 300MB `maxSourceBytes` constant remains a sane, unreachable-in-practice backstop for ephemeral capture too — there's no reason to make it configurable).

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/features/chat/chat_video_preparer_test.dart

  group('optional maxDuration/maxBytes overrides', () {
    test('omitting maxDuration/maxBytes preserves the existing 3-minute/25MB constants', () {
      // This test asserts on the PARAMETER DEFAULTING behavior itself,
      // not a full prepare() run (which needs native calls unavailable in
      // this test host) — it confirms the guard conditions prepare()
      // evaluates internally would be computed against
      // ChatVideoPreparer.maxDuration/maxBytes when the new parameters are
      // null, by checking the effective values a small extracted helper
      // would resolve to. Since prepare() doesn't expose this resolution
      // as a separate testable unit today, this task also adds a
      // @visibleForTesting seam (Step 3) specifically so this can be
      // asserted without a full native-backed prepare() call.
      expect(
        ChatVideoPreparer.debugResolveMaxDuration(null),
        ChatVideoPreparer.maxDuration,
      );
      expect(
        ChatVideoPreparer.debugResolveMaxBytes(null),
        ChatVideoPreparer.maxBytes,
      );
    });

    test('passing maxDuration/maxBytes overrides the defaults', () {
      const overrideDuration = Duration(seconds: 10);
      const overrideBytes = 2 * 1024 * 1024;
      expect(
        ChatVideoPreparer.debugResolveMaxDuration(overrideDuration),
        overrideDuration,
      );
      expect(
        ChatVideoPreparer.debugResolveMaxBytes(overrideBytes),
        overrideBytes,
      );
    });

    test('an ephemeral-scale duration bound (10s) correctly rejects an 11-second window', () async {
      // Uses ChatVideoPreparer's own debugEstimateWindowBytes/duration-bounds
      // reasoning indirectly: since prepare() itself needs native calls this
      // test host can't provide, this asserts the resolved bound value
      // itself is what a caller would compare effectiveDuration against —
      // i.e. that passing maxDuration: Duration(seconds: 10) genuinely
      // produces a 10-second (not 3-minute) ceiling for any downstream
      // duration comparison.
      final resolved = ChatVideoPreparer.debugResolveMaxDuration(
        const Duration(seconds: 10),
      );
      expect(const Duration(seconds: 11) > resolved, isTrue);
      expect(const Duration(seconds: 9) > resolved, isFalse);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart`
Expected: FAIL — `debugResolveMaxDuration`/`debugResolveMaxBytes` don't exist yet.

- [ ] **Step 3: Implement the parameters and the test seams**

In `lib/features/chat/domain/services/chat_video_preparer.dart`:

1. Add two small `@visibleForTesting` static resolver methods, next to the existing `debugEstimateWindowBytes`/`debugSniffMime` seams (after line ~110, before `prepare()`'s own declaration):

```dart
  /// Test seam: the same maxDuration-defaulting prepare() does internally
  /// (fall back to the class constant when the caller omits an override),
  /// exposed so the defaulting behavior itself can be asserted without a
  /// full native-backed prepare() call.
  @visibleForTesting
  static Duration debugResolveMaxDuration(Duration? override) =>
      override ?? maxDuration;

  /// Test seam: mirrors debugResolveMaxDuration for the byte ceiling.
  @visibleForTesting
  static int debugResolveMaxBytes(int? override) => override ?? maxBytes;
```

2. Widen `prepare()`'s signature to add the two new optional parameters:

```dart
  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
    Duration? maxDuration,
    int? maxBytes,
  }) async {
```

3. Inside `prepare()`'s body, resolve the effective bounds once near the top (immediately after the `sniffedMime` check, before the `getMediaInfo` probe, since neither resolution needs the probe result):

```dart
    final effectiveMaxDuration = debugResolveMaxDuration(maxDuration);
    final effectiveMaxBytes = debugResolveMaxBytes(maxBytes);
```

4. Replace the duration-bounds check's reference to the class constant:

```dart
    if (effectiveDuration > effectiveMaxDuration) {
      throw const ChatVideoRejected('media_too_long');
    }
```

(The `effectiveDuration < minDuration` check above it is UNCHANGED — `minDuration` is not parameterized by this task; the spec's minimum-hold-duration behavior for ephemeral capture is a UI-layer concern in `EphemeralCameraScreen`, Task 6, not a `ChatVideoPreparer` parameter, since `ChatVideoPreparer.minDuration` at 500ms is already the correct floor for both flows.)

5. Replace the post-compress size check's reference to the class constant:

```dart
    if (outSize <= 0 || outSize > effectiveMaxBytes) {
      throw const ChatVideoRejected('media_compress_failed');
    }
```

6. Leave every other reference to `maxSourceBytes` (the pre-transcode absolute-size guard and the window-estimate guard) completely untouched — those are not parameterized by this task, per the reasoning in this task's introduction above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart`
Expected: PASS, all tests including the 3 new ones.

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/features/chat/domain/services/chat_video_preparer.dart test/features/chat/chat_video_preparer_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the full chat test suite to confirm no regression**

Run: `flutter test test/features/chat/`
Expected: 192 passed + 3 new = 195 passed, only the 2 known baseline failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/domain/services/chat_video_preparer.dart test/features/chat/chat_video_preparer_test.dart
git commit -m "feat(chat): add optional maxDuration/maxBytes overrides to ChatVideoPreparer.prepare()"
```

---

### Task 2: `mark_video_viewed` RPC — migration, schema, atomicity test

**Files:**
- Create: `supabase/migrations/20260816130000_chat_ephemeral_video.sql`
- Test: manual verification via `supabase db reset` if a live Postgres is available in the execution environment; static re-read fallback otherwise (same standing gap Part 1's own migrations hit — no `docker`/`psql` were available when Part 1 was built; confirm current availability before assuming either way)

**Interfaces:**
- Produces: `messages.is_view_once boolean NOT NULL DEFAULT false`, `messages.viewed_at timestamptz`; `mark_video_viewed(p_message_id uuid) RETURNS void`, `SECURITY DEFINER`, callable by `authenticated`. Task 5 (`sendEphemeralVideoMessage`) writes `is_view_once`; Task 7 (`EphemeralVideoViewerScreen`) calls `mark_video_viewed`.
- Consumes: `public.messages`, `public.relationships`, `storage.objects` — all pre-existing, unmodified by this task except for the two new columns on `messages`.

This is the single most safety-critical piece of server logic in this feature. The atomicity/idempotency test in Step 4 below is not optional polish — it is the direct analog of Part 1's demand for a relative-correctness test on the byte-estimate formula, and this plan's Global Constraints explicitly call out building this test in from the start rather than discovering the gap during final review.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/20260816130000_chat_ephemeral_video.sql
--
-- Adds ephemeral (view-once) video capture on top of Part 1's video-sharing
-- pipeline (20260815130000_chat_video_messages.sql). Reuses media_type =
-- 'video' as-is — NO new media_type value, NO changes to
-- create_chat_media_upload_intent or validate_message_media_before_insert.
-- Every existing constraint/RPC/trigger check for media_type = 'video'
-- already applies unchanged to an ephemeral capture, since the only thing
-- that distinguishes one from a gallery-pick video is the new is_view_once
-- flag on the messages row — set only AFTER the upload-intent flow (which
-- this migration does not touch) has already completed successfully.
--
-- Confirmed directly against the live create_chat_media_upload_intent RPC
-- before writing this migration: it branches purely on p_media_type, with
-- no way to distinguish an ephemeral video intent from a gallery video
-- intent — both request media_type = 'video'. This means the CLIENT is
-- solely responsible for an additional chat_ephemeral_video flag gate
-- before even offering the capture UI (see chat_screen.dart wiring, a
-- later task in this feature's plan) — there is no corresponding
-- server-side flag branch to add here, because the RPC has no way to know
-- a given video intent request is "for an ephemeral capture" versus "for
-- a gallery pick." Both share the exact same chat_video_sharing AND
-- chat_image_sharing server-side gate Part 1 already established.

-- 1. Two new nullable/defaulted columns on messages. Both are safe no-ops
--    for every existing row (is_view_once defaults false, viewed_at stays
--    NULL) — no data migration needed.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_view_once boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS viewed_at timestamptz;

-- 2. Feature flag row, same convention as chat_video_sharing/
--    chat_voice_messages/chat_image_sharing — defaults off. This flag is
--    checked CLIENT-SIDE only (see comment above) — there is no
--    server-side branch for it, since the upload-intent RPC cannot
--    distinguish ephemeral from non-ephemeral video requests.
INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_ephemeral_video', false)
ON CONFLICT (key) DO NOTHING;

-- 3. mark_video_viewed: the one new piece of server logic this feature
--    needs. Atomic view-guard + Storage deletion + tombstone write, all in
--    one SECURITY DEFINER function so a client never needs direct DELETE
--    access to storage.objects or direct UPDATE access to media_url/
--    media_thumbnail_url on messages (both remain server-controlled).
--
--    Idempotency/atomicity (Algorithm Quality Review Checklist 1.1, 2.18,
--    [MUTATION] scope): the UPDATE ... WHERE viewed_at IS NULL guard below
--    is the entire safety mechanism. Two concurrent calls for the same
--    p_message_id — whether from the same device retrying after a network
--    failure, two devices open simultaneously, or sender-then-receiver
--    racing — can only ever have ONE of them find viewed_at still NULL and
--    proceed past the RETURNING clause; every other call's RETURNING
--    yields no row, v_message.id stays NULL, and the function returns
--    early with no side effects. This makes retries always safe: a client
--    that doesn't know whether its previous call actually landed
--    server-side can simply call again.
--
--    Deliberately does NOT distinguish sender from receiver — full
--    symmetry is the confirmed, intended design (see design spec Section
--    7.2's explicit confirmation): the sender's own complete view of their
--    sent clip counts as "viewed" and revokes it for the receiver too.
CREATE OR REPLACE FUNCTION public.mark_video_viewed(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.messages
  SET viewed_at = now()
  WHERE id = p_message_id
    AND is_view_once = true
    AND viewed_at IS NULL
    AND media_url IS NOT NULL
    AND relationship_id IN (
      SELECT id FROM public.relationships
      WHERE status = 'active' AND (user_a = v_user_id OR user_b = v_user_id)
    )
  RETURNING * INTO v_message;

  IF v_message.id IS NULL THEN
    -- Already viewed by an earlier call (the common, expected retry/race
    -- case), or the message doesn't exist / isn't view-once / the caller
    -- isn't a relationship member. No way to distinguish these without
    -- leaking existence to a non-member, and the caller doesn't need to —
    -- "not viewable anymore" is the only actionable outcome either way.
    RETURN;
  END IF;

  DELETE FROM storage.objects
  WHERE bucket_id = 'message-media'
    AND name IN (v_message.media_url, v_message.media_thumbnail_url);

  UPDATE public.messages
  SET media_url = NULL, media_thumbnail_url = NULL
  WHERE id = p_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_video_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_video_viewed(uuid) TO authenticated;
```

- [ ] **Step 2: Apply the migration locally, if a live Postgres is available**

Run: `supabase db reset` (or this repo's established local-migration-apply command)
Expected: migration applies with no errors. If no local Postgres/Docker/`supabase` CLI is available (check for `docker`, `psql` on `PATH` first), state that plainly in the task's completion notes and proceed to Step 3's static verification as the fallback.

- [ ] **Step 3: Static verification (if no live Postgres) or live verification (if available)**

If live Postgres is available, run and record actual output:

```sql
-- (a) Columns exist with correct defaults
SELECT column_name, data_type, column_default FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'messages'
  AND column_name IN ('is_view_once', 'viewed_at');
-- Expected: is_view_once | boolean | false ; viewed_at | timestamp with time zone | (null)

-- (b) Flag row exists, defaults off
SELECT key, enabled FROM public.feature_flags WHERE key = 'chat_ephemeral_video';
-- Expected: chat_ephemeral_video | false

-- (c) A fresh call on a real view-once message with viewed_at IS NULL performs
--     the real work (requires a real row with is_view_once=true, media_url
--     set to a real uploaded object, and the caller being a relationship
--     member — set this up via the ordinary send flow first, or seed
--     directly for this test)
SELECT public.mark_video_viewed('<a real is_view_once message id>'::uuid);
SELECT viewed_at, media_url, media_thumbnail_url FROM public.messages WHERE id = '<same id>';
-- Expected: viewed_at is now set, media_url and media_thumbnail_url are NULL

-- (d) A SECOND call on the SAME message is a safe no-op
SELECT public.mark_video_viewed('<same id>');
-- Expected: no error, no change (viewed_at was already set by (c))

-- (e) The underlying Storage objects are genuinely gone
SELECT * FROM storage.objects WHERE bucket_id = 'message-media' AND name = '<the pre-view media_url value>';
-- Expected: zero rows
```

If no live Postgres is available, re-read the finished migration file line by line and confirm: (1) the `WHERE` clause on the guarding `UPDATE` includes `viewed_at IS NULL` (the entire atomicity mechanism); (2) the `RETURNING * INTO v_message` combined with the `IF v_message.id IS NULL THEN RETURN; END IF;` guard correctly makes every losing caller's function body a no-op before it ever reaches the `DELETE FROM storage.objects` or second `UPDATE`; (3) there is no code path between the winning `UPDATE`'s success and the `DELETE`/second `UPDATE` that could itself fail and leave `viewed_at` set but the Storage objects NOT deleted (note: this is a real, accepted risk in the current design — if the `DELETE FROM storage.objects` or the second `UPDATE` fails after `viewed_at` is already committed, the row is left in a state where a retry will no-op instead of retrying the deletion, since `viewed_at IS NULL` will now be false. Flag this explicitly in the task's completion notes as a known limitation, not a defect to fix in this task — a `BEGIN...EXCEPTION` block wrapping the deletion with a rollback of `viewed_at` on failure would close this gap but adds meaningful complexity for a failure mode Postgres's own transaction semantics already make rare, since the whole function body runs as one implicit transaction and a `DELETE`/`UPDATE` failing here would almost always mean something is badly wrong with the Storage schema itself, not a transient issue). State clearly whether this was static or live verification.

- [ ] **Step 4: Write and run the atomicity/idempotency test**

This is the test the plan's Global Constraints and the checklist scope require — it must actually exercise concurrent/sequential calls, not just assert on the SQL text.

If a live Postgres is available for Step 2/3, extend Step 3's manual verification with an explicit concurrency check:

```sql
-- Simulate two near-simultaneous callers (same session is fine for this
-- purpose — the WHERE viewed_at IS NULL guard's correctness doesn't
-- depend on true parallelism, it depends on the UPDATE's row-level
-- atomicity, which Postgres guarantees regardless of caller timing):
BEGIN;
SELECT public.mark_video_viewed('<a fresh is_view_once message id, not yet viewed>'::uuid);
-- record: did this call's effects (viewed_at set, storage objects deleted) happen? (yes, expected)
SELECT public.mark_video_viewed('<same id>');
-- record: did this second call do anything? (expected: no — no error, no additional deletion attempt since media_url is now NULL and the WHERE clause's viewed_at IS NULL condition is now false)
COMMIT;
-- Verify only ONE deletion happened by confirming storage.objects has no
-- lingering row for the original media_url (from the first call) and no
-- error was raised by the second call attempting to re-delete an
-- already-gone object.
```

If no live Postgres is available, write this as a documented, explicit gap in the task's completion notes — state plainly that the atomicity guarantee was verified STATICALLY (by the guard-clause trace in Step 3) but NOT empirically exercised against a real concurrent/sequential call pair, and that this should be the first thing verified once a live Postgres environment becomes available (matching how Part 1's migration tasks handled the identical environment gap — never claim live verification that didn't happen).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260816130000_chat_ephemeral_video.sql
git commit -m "feat(chat): add mark_video_viewed RPC — atomic view-once deletion for ephemeral video"
```

---

### Task 3: `Message` gains `isViewOnce`/`viewedAt` and the two new getters

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Test: `test/features/chat/message_model_test.dart` (already exists from Part 1 — add to it)

**Interfaces:**
- Produces: `Message.isViewOnce` (`bool`, default `false`), `Message.viewedAt` (`DateTime?`), `Message.isEphemeralVideoAvailable` (`bool` getter), `Message.isEphemeralVideoExpired` (`bool` getter) — Task 4 (`MessageBubble`) and Task 5 (`sendEphemeralVideoMessage`) both consume these exact names.

Current file state (confirmed by reading the file in full immediately before writing this task — 319 lines total): the class currently has 10 media-related fields (lines 11-20, ending with `mediaHeight`), a constructor with matching named params (lines 41-50), `fromRow` (lines 61-100), `optimistic` (lines 102-140), `copyWith` (lines 142-198), `toJson`/`fromJson` (lines 200-262), and the three `has*` getters (lines 264-272, ending with `hasVideo`).

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/features/chat/message_model_test.dart
  group('ephemeral video fields', () {
    test('isViewOnce defaults to false and viewedAt defaults to null', () {
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
      );
      expect(message.isViewOnce, isFalse);
      expect(message.viewedAt, isNull);
    });

    test('isEphemeralVideoAvailable is true only when view-once, unviewed, and media is present', () {
      final available = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        localMediaPath: '/tmp/clip.mp4',
      );
      expect(available.isEphemeralVideoAvailable, isTrue);
      expect(available.isEphemeralVideoExpired, isFalse);

      final notViewOnce = available.copyWith(isViewOnce: false);
      expect(notViewOnce.isEphemeralVideoAvailable, isFalse);

      final noMediaYet = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
      );
      expect(noMediaYet.isEphemeralVideoAvailable, isFalse);
      expect(noMediaYet.isEphemeralVideoExpired, isFalse);
    });

    test('isEphemeralVideoExpired is true once viewedAt is set, regardless of media presence', () {
      final expired = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        viewedAt: DateTime(2026, 8, 16, 12),
      );
      expect(expired.isEphemeralVideoExpired, isTrue);
      expect(expired.isEphemeralVideoAvailable, isFalse);
    });

    test('a non-view-once video message is never ephemeral-available or -expired', () {
      final ordinary = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        signedMediaUrl: 'https://example.com/clip.mp4',
      );
      expect(ordinary.isEphemeralVideoAvailable, isFalse);
      expect(ordinary.isEphemeralVideoExpired, isFalse);
      expect(ordinary.hasVideo, isTrue); // unaffected — this is Part 1's gallery-video path
    });

    test('isViewOnce and viewedAt persist through toJson/fromJson', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16, 9),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        viewedAt: DateTime(2026, 8, 16, 10),
      );
      final restored = Message.fromJson(original.toJson());
      expect(restored.isViewOnce, isTrue);
      expect(restored.viewedAt, DateTime(2026, 8, 16, 10));
    });

    test('copyWith preserves isViewOnce/viewedAt when not overridden', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
      );
      final copied = original.copyWith(status: MessageStatus.sent);
      expect(copied.isViewOnce, isTrue);
      expect(copied.viewedAt, isNull);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/message_model_test.dart`
Expected: FAIL — `isViewOnce`, `viewedAt`, `isEphemeralVideoAvailable`, `isEphemeralVideoExpired` are undefined.

- [ ] **Step 3: Implement the fields and getters**

In `lib/features/chat/domain/entities/message.dart`:

1. Add two fields after `mediaHeight` (line 20):
```dart
  final bool isViewOnce;
  final DateTime? viewedAt;
```

2. Add as constructor params after `this.mediaHeight,` (line 50):
```dart
    this.isViewOnce = false,
    this.viewedAt,
```

3. In `fromRow` (after `mediaHeight` at line 84), add:
```dart
      isViewOnce: (row['is_view_once'] as bool?) ?? false,
      viewedAt: _parseDateTime(row['viewed_at']),
```

4. In `optimistic` (add as new optional named params after `mediaHeight` at line 116, and thread through the constructor call after `mediaHeight: mediaHeight,` at line 133):
```dart
    // param list addition:
    bool isViewOnce = false,
    // constructor-call addition:
    isViewOnce: isViewOnce,
```
(`viewedAt` is deliberately NOT added to `optimistic` — an optimistic, not-yet-sent message can never already be viewed; it always starts `null`, which is the field's own default.)

5. In `copyWith` (add params after `mediaHeight` at line 158, add to the constructor call after `mediaHeight: mediaHeight ?? this.mediaHeight,` at line 186):
```dart
    // param list addition:
    bool? isViewOnce,
    DateTime? viewedAt,
    // constructor-call addition:
    isViewOnce: isViewOnce ?? this.isViewOnce,
    viewedAt: viewedAt ?? this.viewedAt,
```

6. In `toJson` (add after `'mediaHeight': mediaHeight,` at line 214):
```dart
      'isViewOnce': isViewOnce,
      'viewedAt': viewedAt?.toIso8601String(),
```

7. In `fromJson` (add after `mediaHeight: (json['mediaHeight'] as num?)?.toInt(),` at line 244):
```dart
      isViewOnce: (json['isViewOnce'] as bool?) ?? false,
      viewedAt: _parseDateTime(json['viewedAt']),
```

8. Add the two new getters after `hasVideo` (after line 272):
```dart
  bool get isEphemeralVideoAvailable =>
      isViewOnce &&
      viewedAt == null &&
      (localMediaPath != null || signedMediaUrl != null);
  bool get isEphemeralVideoExpired => isViewOnce && viewedAt != null;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/message_model_test.dart`
Expected: PASS, all tests including the 6 new ones.

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/features/chat/domain/entities/message.dart test/features/chat/message_model_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the full chat test suite to confirm no regression**

Run: `flutter test test/features/chat/`
Expected: 195 (from Task 1) + 6 new = 201 passed, only the 2 known baseline failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart test/features/chat/message_model_test.dart
git commit -m "feat(chat): add isViewOnce/viewedAt fields and ephemeral-video getters to Message"
```

---

### Task 4: `_messageColumns`, `_hydrateMessages`, `sendTextMessage` — thread `isViewOnce`/`viewedAt` server-side

**Files:**
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart`
- Test: no new test file — this task's behavior is exercised end-to-end by Task 5's `sendEphemeralVideoMessage` tests; this task's own verification is `dart analyze` plus confirming Task 5's later tests pass against these changes.

**Interfaces:**
- Consumes: `Message.isViewOnce`/`viewedAt` (Task 3).
- Produces: `ChatRepository.sendTextMessage`'s abstract signature gains one new parameter, `bool isViewOnce = false`; the concrete implementation writes `is_view_once` on insert; `_messageColumns` selects `is_view_once,viewed_at`; `Message.fromRow` (already updated in Task 3) picks them up automatically once selected.

Current file state (confirmed by reading both files in full immediately before writing this task): `ChatRepository.sendTextMessage`'s abstract signature (`chat_repository.dart:24-37`) currently ends `String? replyToMessageId, String? quotedText,`. The concrete implementation (`supabase_chat_repository.dart:251-295`) mirrors that signature exactly and builds an `.insert({...})` map (lines 276-289) with one key per parameter. `_messageColumns` (lines 34-38) is a single string constant currently listing 15 columns, ending `...,deleted_at,edited_at`. `_hydrateMessages` (lines 729-766) gates on `base.mediaKey == null || mediaType not in {image,audio,video}` — **already correctly handles an ephemeral video whose `media_url` has been nulled by `mark_video_viewed`**, since `base.mediaKey` (populated from `row['media_url']`) will be `null` for a viewed/expired ephemeral message, triggering the early `return base;` with no signed-URL resolution attempted. **No changes needed to `_hydrateMessages` itself** — confirmed by tracing this logic directly against the current implementation, not assumed.

- [ ] **Step 1: Widen `ChatRepository.sendTextMessage`'s abstract signature**

In `lib/features/chat/data/repositories/chat_repository.dart`, add one parameter at the end of the existing list (after `String? quotedText,`):

```dart
    bool isViewOnce = false,
```

- [ ] **Step 2: Widen `_messageColumns` and the concrete `sendTextMessage`**

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`:

1. Widen `_messageColumns` (lines 34-38) to add the two new columns — append `,is_view_once,viewed_at` to the final line:
```dart
  static const _messageColumns =
      'id,relationship_id,sender_id,client_message_id,content,created_at,'
      'delivered_at,read_at,media_url,media_thumbnail_url,media_type,'
      'media_duration_ms,media_waveform,media_width,media_height,source,'
      'reply_to_message_id,quoted_text,deleted_at,edited_at,'
      'is_view_once,viewed_at';
```

2. Widen the concrete `sendTextMessage`'s signature (lines 251-265) to match Step 1's addition:
```dart
    bool isViewOnce = false,
  }) async {
```

3. Add `'is_view_once': isViewOnce,` to the `.insert({...})` map (after `'quoted_text': quotedText,` at line 289):
```dart
              'is_view_once': isViewOnce,
```

(`viewed_at` is NOT part of the insert map — it is never client-set; it is only ever written server-side by `mark_video_viewed`, Task 2. The column is selected by `_messageColumns` so it flows back on read, but a client never writes it directly, matching the design spec's server-authoritative model for view state.)

- [ ] **Step 3: Run `dart analyze`**

Run: `dart analyze lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full chat test suite to confirm no regression**

Run: `flutter test test/features/chat/`
Expected: 201 passed (unchanged from Task 3 — this task adds no new tests of its own), only the 2 known baseline failures. If any test fails here, it means an existing mock/fake `ChatRepository` implementation (e.g. in a test harness) needs its `sendTextMessage` override widened to match the new parameter — check `test/features/chat/support/chat_test_harness.dart`'s `FakeChatRepository` first, since Part 1's own final-review fix wave already widened it once for `mediaThumbnailKey`/`mediaWidth`/`mediaHeight` and it likely needs the same one-line addition here (`bool isViewOnce = false,` added to its own override signature, and threading it into whatever row-map it constructs internally, mirroring Part 1's pattern exactly).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/features/chat/support/chat_test_harness.dart
git commit -m "feat(chat): thread isViewOnce through sendTextMessage and _messageColumns"
```

(Note: `chat_test_harness.dart` is included in the `git add` above defensively — only actually modified if Step 4 revealed it needed updating. If it needed no changes, drop it from the commit.)

---

### Task 5: `PendingSend` gains `isViewOnce`; `ChatController.sendEphemeralVideoMessage`

**Files:**
- Modify: `lib/features/chat/data/cache/pending_send.dart`
- Modify: `lib/features/chat/presentation/state/chat_state.dart`
- Test: `test/features/chat/pending_send_video_test.dart` (already exists from Part 1 — add to it)
- Test: `test/features/chat/chat_state_send_ephemeral_video_message_test.dart` (new file, mirrors Part 1's `chat_state_send_video_message_test.dart` structure exactly)

**Interfaces:**
- Consumes: `PreparedChatVideo` (Task 1, unchanged shape — `{file, mimeType, byteSize, durationMs, thumbnailFile, thumbnailMimeType, thumbnailByteSize, width, height}`), `Message.isViewOnce` (Task 3), `ChatRepository.sendTextMessage`'s widened `isViewOnce` parameter (Task 4).
- Produces: `ChatController.sendEphemeralVideoMessage({required String localPath, required int durationMs, required String thumbnailLocalPath, required int width, required int height})` — Task 6 (`EphemeralCameraScreen`) calls this exact signature.

Current file state (confirmed by reading both files in full immediately before writing this task): `PendingSend` (112 lines) has the same `copyWith` quirk Part 1 documented — its parameter list (lines 48-53) exposes only `attempts`/`nextAttemptAt`/`lastErrorCategory`/`state`; every other field is threaded through the constructor call inside `copyWith`'s body (lines 54-76) by reading the instance field directly. `sendVideoMessage` (`chat_state.dart:647-727`) is the exact structural template this task mirrors. `_attemptSend` (`chat_state.dart:1008-1142`) already branches on `pending.mediaType == 'video'` for its two-intent upload logic (lines 1028-1071) and needs **no changes** for ephemeral video, since an ephemeral capture's `PendingSend.mediaType` is also `'video'` — it goes through the identical two-intent path (video intent, then non-fatal thumbnail intent) with zero new branching. The only change `_attemptSend` needs is threading `pending.isViewOnce` into the `sendTextMessage` call (line 1072-1086).

- [ ] **Step 1: Write the failing `PendingSend` round-trip test**

```dart
// Add to test/features/chat/pending_send_video_test.dart
  test('PendingSend toJson/fromJson round-trips isViewOnce', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/clip.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: 8000,
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 720,
      mediaHeight: 1280,
      isViewOnce: true,
      createdAt: DateTime(2026, 8, 16, 9),
    );
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.isViewOnce, isTrue);
  });

  test('PendingSend.copyWith preserves isViewOnce', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      isViewOnce: true,
      createdAt: DateTime(2026, 8, 16, 9),
    );
    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.isViewOnce, isTrue);
  });

  test('isViewOnce defaults to false for a non-ephemeral PendingSend', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      createdAt: DateTime(2026, 8, 16, 9),
    );
    expect(original.isViewOnce, isFalse);
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.isViewOnce, isFalse);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/pending_send_video_test.dart`
Expected: FAIL — `isViewOnce` is not a defined parameter on `PendingSend`.

- [ ] **Step 3: Add `isViewOnce` to `PendingSend`**

In `lib/features/chat/data/cache/pending_send.dart`:

1. Add the field after `mediaHeight` (line 16):
```dart
  final bool isViewOnce;
```

2. Add as a constructor param after `this.mediaHeight,` (line 38):
```dart
    this.isViewOnce = false,
```

3. Add to `copyWith`'s constructor-call body (the unconditional pass-through — NOT the parameter list, per the established quirk) after `mediaHeight: mediaHeight,` (line 67):
```dart
      isViewOnce: isViewOnce,
```

4. Add to `toJson` after `'mediaHeight': mediaHeight,` (line 92):
```dart
      'isViewOnce': isViewOnce,
```

5. Add to `fromJson` after `mediaHeight: (json['mediaHeight'] as num?)?.toInt(),` (line 119):
```dart
      isViewOnce: (json['isViewOnce'] as bool?) ?? false,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/pending_send_video_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `ChatController.sendEphemeralVideoMessage`**

In `lib/features/chat/presentation/state/chat_state.dart`, add a new method immediately after `sendVideoMessage` (after line 727, before `retryMessage`):

```dart
  /// Sends an ephemeral (view-once) video message, mirroring
  /// sendVideoMessage's exact shape with one addition: the constructed
  /// PendingSend/Message carries isViewOnce: true. Deliberately a separate
  /// method rather than a parameter on sendVideoMessage — the two have
  /// different validation (10s cap here vs. ChatVideoPreparer.maxDuration's
  /// 3-minute default there) and conflating them risks exactly the kind of
  /// accidental cross-contamination Part 1 was careful to avoid with
  /// _attemptSend's branching. _attemptSend itself needs NO new branching:
  /// an ephemeral capture's PendingSend.mediaType is 'video' just like a
  /// gallery pick, so it flows through the identical two-intent upload path
  /// already there — only the final sendTextMessage call (below, and in
  /// _attemptSend) needs isViewOnce threaded through.
  Future<void> sendEphemeralVideoMessage({
    required String localPath,
    required int durationMs,
    required String thumbnailLocalPath,
    required int width,
    required int height,
  }) async {
    if (!state.conversation.canSend) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }
    final thumbnailFile = File(thumbnailLocalPath);
    if (!await thumbnailFile.exists()) {
      if (mounted) {
        state = state.copyWith(error: 'That video is no longer available.');
      }
      return;
    }

    // Belt-and-suspenders duration check against the 10-second ephemeral
    // cap — mirrors sendVideoMessage's identical check against
    // ChatVideoPreparer.maxDuration, but against the ephemeral-specific
    // bound, since a stale/modified local file or a future caller
    // bypassing EphemeralCameraScreen's own recording cap should not be
    // able to queue an oversized ephemeral send.
    const ephemeralMaxDuration = Duration(seconds: 10);
    if (durationMs > ephemeralMaxDuration.inMilliseconds) {
      if (mounted) {
        state = state.copyWith(error: 'That video is too long to send.');
      }
      return;
    }
    if (durationMs < ChatVideoPreparer.minDuration.inMilliseconds) {
      return;
    }

    final clientMessageId = const Uuid().v4();
    final optimisticId = '_local_$clientMessageId';
    final now = DateTime.now();
    final pending = PendingSend(
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      text: '',
      localMediaPath: localPath,
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: durationMs,
      localThumbnailPath: thumbnailLocalPath,
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: width,
      mediaHeight: height,
      isViewOnce: true,
      createdAt: now,
    );
    await ref.read(chatCacheServiceProvider).putOutbox(user.id, pending);

    final optimistic = Message.optimistic(
      id: optimisticId,
      clientMessageId: clientMessageId,
      relationshipId: relationshipId,
      senderId: user.id,
      content: '',
      createdAt: now,
      mediaType: 'video',
      localMediaPath: localPath,
      mediaDurationMs: durationMs,
      mediaWidth: width,
      mediaHeight: height,
      isViewOnce: true,
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );

    await _attemptSend(pending);
  }
```

- [ ] **Step 6: Thread `isViewOnce` through `_attemptSend`'s `sendTextMessage` call**

In `lib/features/chat/presentation/state/chat_state.dart`, `_attemptSend` (lines 1008-1142), widen the `sendTextMessage` call (lines 1072-1086) by adding one line:

```dart
      final canonical = await repository.sendTextMessage(
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        clientMessageId: pending.clientMessageId,
        content: pending.text,
        mediaKey: mediaKey,
        mediaType: pending.mediaType,
        mediaDurationMs: pending.mediaDurationMs,
        waveform: pending.waveform,
        mediaThumbnailKey: mediaThumbnailKey,
        mediaWidth: pending.mediaWidth,
        mediaHeight: pending.mediaHeight,
        isViewOnce: pending.isViewOnce,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );
```

No other change to `_attemptSend` is needed — the two-intent upload branch above this call already handles `pending.mediaType == 'video'` generically, and an ephemeral capture's `PendingSend` is indistinguishable from a gallery-pick video's at that point in the function (both have `mediaType: 'video'`, both have a `localThumbnailPath`). This is a deliberate, verified-correct consequence of Part 1's own `_attemptSend` already being media-type-generic rather than something this task needs to work around.

- [ ] **Step 7: Write `ChatController.sendEphemeralVideoMessage` behavioral tests**

Check `test/features/chat/chat_state_send_video_message_test.dart` (Part 1's equivalent) for the exact harness usage pattern (`FakeChatRepository`/`buildChatContainer` from `test/features/chat/support/chat_test_harness.dart`) before writing this new file — mirror its structure exactly.

```dart
// test/features/chat/chat_state_send_ephemeral_video_message_test.dart
//
// Follow test/features/chat/chat_state_send_video_message_test.dart's exact
// harness usage pattern. Write real behavioral tests covering:
//
// - sendEphemeralVideoMessage with a missing local video file sets
//   state.error and does not queue a PendingSend.
// - sendEphemeralVideoMessage with a missing thumbnail file sets
//   state.error and does not queue.
// - sendEphemeralVideoMessage with durationMs over 10000 (10 seconds) sets
//   state.error and does not queue — THIS IS THE KEY DIFFERENCE FROM
//   sendVideoMessage's test suite: assert specifically against the 10s
//   ephemeral cap, not Part 1's 3-minute cap, to prove the two methods
//   enforce genuinely different bounds rather than accidentally sharing
//   ChatVideoPreparer.maxDuration's 3-minute constant.
// - sendEphemeralVideoMessage with durationMs under
//   ChatVideoPreparer.minDuration.inMilliseconds (500ms) returns silently,
//   no error, no queued message.
// - A valid send produces exactly one optimistic message in state.messages
//   with mediaType == 'video', isViewOnce == true,
//   isEphemeralVideoAvailable == true, status == sending.
// - The queued PendingSend (verify via the fake outbox / cache service)
//   has isViewOnce == true.
```

- [ ] **Step 8: Run all new/modified tests**

Run: `flutter test test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_ephemeral_video_message_test.dart`
Expected: all PASS.

- [ ] **Step 9: Run `dart analyze` on every file this task touched**

Run: `dart analyze lib/features/chat/data/cache/pending_send.dart lib/features/chat/presentation/state/chat_state.dart test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_ephemeral_video_message_test.dart`
Expected: `No issues found!`

- [ ] **Step 10: Run the full chat test suite for regressions**

Run: `flutter test test/features/chat/`
Expected: only the 2 known baseline failures — specifically confirm Part 1's EXISTING `sendVideoMessage` tests still pass unmodified, since this task's `_attemptSend` change is a widening of code that path also runs through.

- [ ] **Step 11: Commit**

```bash
git add lib/features/chat/data/cache/pending_send.dart lib/features/chat/presentation/state/chat_state.dart test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_ephemeral_video_message_test.dart
git commit -m "feat(chat): add ChatController.sendEphemeralVideoMessage, thread isViewOnce through PendingSend/_attemptSend"
```

---

### Task 6: `EphemeralCameraScreen` — press-and-hold in-app capture

**Files:**
- Create: `lib/features/chat/presentation/screens/ephemeral_camera_screen.dart`
- Modify: `pubspec.yaml` (add `camera`)
- Test: `test/features/chat/ephemeral_camera_screen_test.dart`

**Interfaces:**
- Consumes: `ChatVideoPreparer.prepare()` with `maxDuration`/`maxBytes` overrides (Task 1), `VideoPrepareProgressDialog` (Part 1, unchanged — reused as-is, since it already accepts any `prepare()`-shaped call).
- Produces: a route pushed via `Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const EphemeralCameraScreen()))` — this screen does not return a value; on successful capture+prepare+send it pops itself back to the chat screen directly (mirroring how a completed send anywhere else in this app doesn't require the caller to do anything further). `EphemeralCameraScreen` widget: no required constructor params (it reads `relationshipId`/`ChatController` via the ambient `ChatController` provider scope, same as `chat_screen.dart` itself does — confirm the exact provider-scoping mechanism by reading `chat_screen.dart`'s own `ChatController` access pattern before implementing, since this screen is pushed FROM `chat_screen.dart` and needs to reach the same controller instance, not a fresh one).

**Package note**: the `camera` package is a genuinely new dependency — first live in-app camera preview anywhere in this app. Unlike `video_compress`/`video_thumbnail` (Part 1's native calls, already established to degrade to `MissingPluginException` in a pure-Dart `flutter test` host), `camera`'s test-host degradation needs the same treatment: add `camera_platform_interface` as a direct dev_dependency if this task's tests need to fake native camera responses, following the exact precedent already established in `pubspec.yaml`'s `dev_dependencies` block (`permission_handler_platform_interface`, `record_platform_interface`, `path_provider_platform_interface`, each with an explanatory comment about satisfying `depend_on_referenced_packages` for test-time native-call faking).

- [ ] **Step 1: Add the `camera` dependency**

In `pubspec.yaml`, add to the `dependencies:` block (after `video_compress: ^3.1.2` — the last of Part 1's video-related additions):
```yaml
  camera: ^0.11.0
```

Run: `flutter pub get`
Expected: resolves cleanly. If a version conflict arises, check the error for the specific conflicting package and pick the highest compatible version — do not downgrade any other existing dependency to force this one in.

- [ ] **Step 2: Write the failing tests focused on the testable, non-native logic**

This screen's live camera preview cannot be meaningfully exercised in a `flutter test` VM host (no real camera hardware). Per this plan's Global Constraints and the established pattern from `VoiceRecorderService.debugTriggerMaxDurationAutoStop()`, this task's tests focus on the state-machine logic (minimum-hold-duration discard, 10-second auto-stop, camera-flip-before-recording-only) via a `@visibleForTesting` seam, not the actual `CameraController` construction.

```dart
// test/features/chat/ephemeral_camera_screen_test.dart
import 'package:attune/features/chat/presentation/screens/ephemeral_camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('minimum hold duration', () {
    test('a hold shorter than 500ms is discarded, not sent', () {
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(milliseconds: 200),
        ),
        isTrue,
      );
    });

    test('a hold of exactly 500ms or longer is not discarded', () {
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(milliseconds: 500),
        ),
        isFalse,
      );
      expect(
        EphemeralCameraScreenState.debugShouldDiscardHold(
          const Duration(seconds: 3),
        ),
        isFalse,
      );
    });
  });

  group('10-second auto-stop cap', () {
    test('recording duration is clamped to at most 10 seconds', () {
      expect(
        EphemeralCameraScreenState.debugClampRecordingDuration(
          const Duration(seconds: 15),
        ),
        const Duration(seconds: 10),
      );
      expect(
        EphemeralCameraScreenState.debugClampRecordingDuration(
          const Duration(seconds: 7),
        ),
        const Duration(seconds: 7),
      );
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/ephemeral_camera_screen_test.dart`
Expected: FAIL — `ephemeral_camera_screen.dart` doesn't exist yet.

- [ ] **Step 4: Implement `EphemeralCameraScreen`**

```dart
// lib/features/chat/presentation/screens/ephemeral_camera_screen.dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/video_prepare_progress_dialog.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Full-screen live camera preview for press-and-hold ephemeral video
/// capture. Pushed via Navigator.push from chat_screen.dart's composer, not
/// a GoRouter route — mirrors VideoTrimScreen's established
/// "full-screen route for video-specific UI" pattern from Part 1.
///
/// Release-to-send has NO confirm step — this is a deliberate, confirmed
/// design choice (true Snapchat parity), not an oversight. A minimum hold
/// duration silently discards accidental taps, mirroring
/// VoiceRecorderService.minDuration's identical pattern.
class EphemeralCameraScreen extends ConsumerStatefulWidget {
  const EphemeralCameraScreen({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<EphemeralCameraScreen> createState() =>
      EphemeralCameraScreenState();
}

class EphemeralCameraScreenState
    extends ConsumerState<EphemeralCameraScreen> {
  static const Duration _maxRecordingDuration = Duration(seconds: 10);
  static const Duration _minHoldDuration = Duration(milliseconds: 500);

  /// Test seam: the minimum-hold-duration discard check prepare() itself
  /// doesn't own — this screen decides BEFORE ever handing a file to
  /// ChatVideoPreparer whether a hold was long enough to be an intentional
  /// recording versus an accidental tap.
  @visibleForTesting
  static bool debugShouldDiscardHold(Duration held) =>
      held < _minHoldDuration;

  /// Test seam: the 10-second auto-stop clamp, exposed so its correctness
  /// (never exceeds the cap, never clamps a shorter recording down) can be
  /// asserted directly without a real camera/timer.
  @visibleForTesting
  static Duration debugClampRecordingDuration(Duration elapsed) =>
      elapsed > _maxRecordingDuration ? _maxRecordingDuration : elapsed;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  DateTime? _recordingStartedAt;
  Timer? _autoStopTimer;
  bool _isRecording = false;
  bool _isPreparing = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      // Front camera default, per the approved design — find the first
      // front-facing camera, falling back to index 0 if none is reported
      // (some emulators/devices only expose one lens).
      _cameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _startPreview();
    } catch (_) {
      // Mirrors VoiceRecorderService's permission-handling precedent —
      // check that service's requestPermission()/denial-UI pattern before
      // finalizing this catch block's exact error classification; camera
      // package throws CameraException for both permission-denial and
      // hardware-unavailable cases, which this screen should distinguish
      // in its error UI where the underlying exception allows.
      if (mounted) {
        setState(() => _permissionError = 'Camera access is needed to record.');
      }
    }
  }

  Future<void> _startPreview() async {
    if (_cameras.isEmpty) return;
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _flipCamera() async {
    if (_isRecording || _cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    _controller = null;
    await _startPreview();
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || _isRecording) return;
    try {
      await controller.startVideoRecording();
    } catch (_) {
      return;
    }
    _recordingStartedAt = DateTime.now();
    setState(() => _isRecording = true);
    _autoStopTimer = Timer(_maxRecordingDuration, () {
      unawaited(_stopAndSend());
    });
  }

  Future<void> _stopAndSend() async {
    _autoStopTimer?.cancel();
    final controller = _controller;
    final startedAt = _recordingStartedAt;
    if (controller == null || !_isRecording || startedAt == null) return;

    setState(() => _isRecording = false);
    final held = DateTime.now().difference(startedAt);

    final XFile file;
    try {
      file = await controller.stopVideoRecording();
    } catch (_) {
      return;
    }

    if (debugShouldDiscardHold(held)) {
      // Silent discard — matches VoiceRecorderService's identical
      // accidental-tap handling. Delete the short clip so it doesn't
      // linger in temp storage.
      await File(file.path).delete().catchError((_) => File(file.path));
      return;
    }

    await _prepareAndSend(file.path);
  }

  Future<void> _prepareAndSend(String localPath) async {
    setState(() => _isPreparing = true);
    try {
      final prepared = await VideoPrepareProgressDialog.show(
        context,
        localPath: localPath,
        maxDuration: const Duration(seconds: 10),
        maxBytes: 2 * 1024 * 1024,
      );
      if (!mounted) return;
      await ref
          .read(chatControllerProvider(/* conversation param — see note below */).notifier)
          .sendEphemeralVideoMessage(
            localPath: prepared.file.path,
            durationMs: prepared.durationMs,
            thumbnailLocalPath: prepared.thumbnailFile.path,
            width: prepared.width,
            height: prepared.height,
          );
      if (mounted) Navigator.of(context).pop();
    } on ChatVideoRejected catch (rejected) {
      if (!mounted) return;
      setState(() {
        _isPreparing = false;
        _permissionError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_rejectionMessage(rejected.code))),
      );
      // Deliberately does NOT pop back to the chat screen on failure — the
      // user is still on the camera screen and can try recording again,
      // unlike a picker-cancel elsewhere in the app which just returns.
    }
  }

  String _rejectionMessage(String code) {
    switch (code) {
      case 'media_too_long':
        return 'That recording is too long.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'Could not prepare that video. Try again.';
      case 'media_too_short':
        return 'That clip is too short.';
      default:
        return 'That video is no longer available.';
    }
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionError != null) {
      return Scaffold(
        body: Center(child: Text(_permissionError!)),
      );
    }
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            CameraPreview(controller)
          else
            const Center(child: CircularProgressIndicator()),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: _isRecording ? null : _flipCamera,
              icon: const Icon(Icons.flip_camera_ios_outlined, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onLongPressStart: (_) => unawaited(_startRecording()),
                onLongPressEnd: (_) => unawaited(_stopAndSend()),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (_isPreparing)
            const ColoredBox(
              color: Colors.black54,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
```

**Implementer note**: the `ref.read(chatControllerProvider(...))` call site above has a placeholder comment (`/* conversation param — see note below */`) — this is NOT an acceptable placeholder to ship. Before finalizing this task, read `chat_screen.dart`'s own exact `chatControllerProvider(widget.conversation)` access pattern (confirmed present at multiple call sites in that file, e.g. line 618) and thread the actual `conversation` object (or equivalent identifying param) into `EphemeralCameraScreen`'s constructor exactly as needed to reach the SAME controller instance the chat screen itself is using — mirror `VideoTrimScreen`'s constructor-param pattern if it needed something analogous, or `chat_screen.dart`'s own prop-drilling if not. Resolve this before Step 5; do not leave a placeholder comment in committed code.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/chat/ephemeral_camera_screen_test.dart`
Expected: PASS, both tests.

- [ ] **Step 6: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/screens/ephemeral_camera_screen.dart test/features/chat/ephemeral_camera_screen_test.dart pubspec.yaml`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/chat/presentation/screens/ephemeral_camera_screen.dart test/features/chat/ephemeral_camera_screen_test.dart
git commit -m "feat(chat): add EphemeralCameraScreen with press-and-hold capture, 10s auto-stop, min-hold discard"
```

---

### Task 7: `EphemeralVideoViewerScreen` — full-screen one-shot playback, `mark_video_viewed` call

**Files:**
- Create: `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart`
- Modify: `lib/features/chat/data/repositories/chat_repository.dart` (add `markVideoViewed`)
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart` (implement it)
- Test: `test/features/chat/ephemeral_video_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `mark_video_viewed` RPC (Task 2), `Message.isEphemeralVideoAvailable`/`isEphemeralVideoExpired`/`viewedAt` (Task 3).
- Produces: `ChatRepository.markVideoViewed({required String messageId})` — Task 8 (`MessageBubble`'s sealed-tile tap handler) consumes this via `EphemeralVideoViewerScreen`'s push. `EphemeralVideoViewerScreen` widget: `{required String messageId, required String videoUrl}` (no thumbnail needed — this screen never shows a poster, per the design spec's sealed-tile treatment, it goes straight to playback), pushed via `Navigator.push<void>`.

- [ ] **Step 1: Add `markVideoViewed` to `ChatRepository`**

In `lib/features/chat/data/repositories/chat_repository.dart`, add a new abstract method (near `createMediaUploadIntent`/`uploadChatMedia`):

```dart
  Future<void> markVideoViewed({required String messageId});
```

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`, implement it (near `createMediaUploadIntent`'s implementation):

```dart
  @override
  Future<void> markVideoViewed({required String messageId}) async {
    await _supabase.rpc(
      'mark_video_viewed',
      params: {'p_message_id': messageId},
    );
  }
```

Also widen `test/features/chat/support/chat_test_harness.dart`'s `FakeChatRepository` with a matching override — a simple in-memory implementation that records the call (for test assertions) and, if the harness's test doubles track message state, marks the corresponding fake message as viewed. Check the harness's existing shape before deciding the exact fake implementation; keep it minimal.

- [ ] **Step 2: Write the failing tests**

```dart
// test/features/chat/ephemeral_video_viewer_screen_test.dart
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calls markVideoViewed via the repository when playback completes or is dismissed',
      (tester) async {
    // Follow test/features/chat/support/chat_test_harness.dart's
    // FakeChatRepository pattern (widened in Step 1) — construct a
    // ProviderScope overriding chatRepositoryProvider with a fake that
    // records markVideoViewed calls, pump EphemeralVideoViewerScreen, tap
    // the close/back button (since exercising an actual video-completion
    // event needs a real platform video decoder unavailable in this test
    // host — the explicit-dismissal path is what's testable here), and
    // assert the fake recorded exactly one markVideoViewed('m1') call.
  });

  testWidgets('self-closes with an "already viewed" indicator if the message becomes expired while open',
      (tester) async {
    // Construct the screen with a Message provider/stream (whatever the
    // real cross-media ref.listen mechanism turns out to consume — mirror
    // VideoMessagePlayer/VoiceMessagePlayer's existing
    // ref.listen(currentlyPlayingXMessageIdProvider) pattern, but scoped to
    // THIS message's viewedAt field) already reflecting isEphemeralVideoExpired
    // == true at pump time (simulating a revocation that arrived via the
    // realtime subscription while this screen was already open), and
    // assert the screen shows an "already viewed" state rather than
    // attempting playback of stale/gone content.
  });
}
```

**Implementer note**: the exact mechanism by which `EphemeralVideoViewerScreen` learns "this message's `viewedAt` just changed while I'm open" needs to be resolved against how messages actually flow into this screen — the design spec (Section 7.4) says to mirror `VideoMessagePlayer`/`VoiceMessagePlayer`'s `ref.listen` cross-media-coordination pattern, but those watch a dedicated `StateProvider<String?>` (`currentlyPlayingVideoMessageIdProvider`), which is a different shape than "watch one specific message's field for a change." Before implementing, read how `chat_screen.dart`/`ChatController`'s `state.messages` list is exposed to descendant widgets (likely via `chatControllerProvider(conversation)` itself, the same provider `MessageBubble` already reads its `Message` from) and derive a small provider or `ref.watch` expression that recomputes when the specific message with this `messageId` changes — do not invent a new standalone provider unless the existing `state.messages` stream genuinely can't be filtered down to one message's field cheaply. This is a real design decision left to the implementer's judgment given the actual current provider architecture, not a placeholder to guess at blindly — read the code first.

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/ephemeral_video_viewer_screen_test.dart`
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 4: Implement `EphemeralVideoViewerScreen`**

```dart
// lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart
import 'dart:io';

import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Full-screen one-shot ephemeral video playback. Unlike VideoMessagePlayer
/// (Part 1's gallery-video bubble player, which is reused across a
/// scrolling list and therefore needs lazy controller construction),
/// this screen has exactly one playback per screen instance — the
/// VideoPlayerController is constructed eagerly in initState, matching
/// VoiceMessagePlayer's eager-construction precedent rather than
/// VideoMessagePlayer's lazy one, since the list-reuse concern that
/// motivated lazy construction there doesn't apply to a single full-screen
/// route.
///
/// Calls markVideoViewed on playback completion OR explicit dismissal —
/// both count as "viewed," there is no partial-view distinction (matches
/// real Snapchat behavior).
class EphemeralVideoViewerScreen extends ConsumerStatefulWidget {
  const EphemeralVideoViewerScreen({
    super.key,
    required this.messageId,
    required this.videoUrl,
    required this.relationshipId,
  });

  final String messageId;
  final String videoUrl;
  final String relationshipId;

  @override
  ConsumerState<EphemeralVideoViewerScreen> createState() =>
      _EphemeralVideoViewerScreenState();
}

class _EphemeralVideoViewerScreenState
    extends ConsumerState<EphemeralVideoViewerScreen> {
  VideoPlayerController? _controller;
  bool _hasMarkedViewed = false;
  bool _expiredElsewhere = false;

  @override
  void initState() {
    super.initState();
    final controller = widget.videoUrl.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
        : VideoPlayerController.file(File(widget.videoUrl));
    controller.addListener(_onPlaybackUpdate);
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _controller = controller);
      controller.play();
    }).catchError((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _onPlaybackUpdate() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      unawaited(_markViewedAndClose());
    }
  }

  Future<void> _markViewedAndClose() async {
    if (_hasMarkedViewed) return;
    _hasMarkedViewed = true;
    await ref
        .read(chatRepositoryProvider)
        .markVideoViewed(messageId: widget.messageId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlaybackUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cross-device revocation while this screen is open: see this task's
    // implementer note above for how this ref.watch/listen expression is
    // actually derived against the live provider architecture — the
    // exact expression here is illustrative of the CONTRACT (react to
    // this message's isEphemeralVideoExpired becoming true) rather than
    // a literal copy-paste, since the concrete provider shape depends on
    // what Step 4's own investigation into chat_screen.dart's message
    // exposure found.
    ref.listen<bool>(
      /* derived provider watching widget.messageId's isEphemeralVideoExpired */,
      (previous, isExpired) {
        if (isExpired == true && !_expiredElsewhere) {
          setState(() => _expiredElsewhere = true);
        }
      },
    );

    if (_expiredElsewhere) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Already viewed',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => unawaited(_markViewedAndClose()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
```

**Implementer note**: the `ref.listen` call above has an illustrative placeholder (`/* derived provider watching widget.messageId's isEphemeralVideoExpired */`) — same category of "resolve against actual architecture, don't guess" note as Task 6's `chatControllerProvider` placeholder. This must be resolved to a real, working expression before this task is done; it is flagged explicitly rather than filled with a guess because the correct answer depends on investigation this plan cannot fully do in advance (specifically: does `chatControllerProvider(conversation)`'s `state.messages` list already get rebuilt/re-emitted when a realtime `UPDATE` lands for one message, in a way a `ref.watch` selector can cheaply key off of? Read `ChatController`'s realtime-event-handling code, likely a `watchConversationEvents`-driven refresh path, before implementing this).

Also: the on-tap-dismiss behavior in `build()` above (`onTap: () => unawaited(_markViewedAndClose())`) means ANY tap anywhere on the screen — not just an explicit close button — marks viewed and closes. Confirm this matches the design spec's intent ("or the viewer explicitly dismisses the full-screen viewer mid-playback... both count as 'viewed'") — a tap-anywhere-to-dismiss affordance is a reasonable, common full-screen-viewer UX pattern and is consistent with the spec's own framing, but if a more explicit close button (not tap-anywhere) is preferred, that's a one-line change (move the `GestureDetector`'s `onTap` to a dedicated close `IconButton` instead) — implementer's judgment, not re-litigated here since the spec doesn't specify which literal gesture, only that both completion and dismissal count.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/chat/ephemeral_video_viewer_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run `dart analyze`**

Run: `dart analyze lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart test/features/chat/ephemeral_video_viewer_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart test/features/chat/ephemeral_video_viewer_screen_test.dart test/features/chat/support/chat_test_harness.dart
git commit -m "feat(chat): add EphemeralVideoViewerScreen with one-shot playback and markVideoViewed on completion/dismissal"
```

---

### Task 8: `MessageBubble` sealed-tile/tombstone rendering; `ChatTextField`/`chat_screen.dart` capture wiring

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (new `chatEphemeralVideoEnabledProvider`)
- Test: `test/features/chat/presentation/widgets/message_bubble_test.dart` and/or `test/features/chat/message_bubble_test.dart` (Part 1 confirmed both exist — check which one is the right home for new tests, or whether both need updating)
- Test: `test/features/chat/chat_text_field_test.dart`

**Interfaces:**
- Consumes: `Message.isEphemeralVideoAvailable`/`isEphemeralVideoExpired` (Task 3), `EphemeralVideoViewerScreen` (Task 7), `EphemeralCameraScreen` (Task 6).
- Produces: `ChatTextField.showCaptureVideo`/`onCaptureVideo` (purely additive, new pair alongside the three existing pairs); `chatEphemeralVideoEnabledProvider` (mirrors `chatVideoSharingEnabledProvider`'s exact `FutureProvider<bool>`/`ChatFeatureFlags.isEnabled` pattern).

**Critical flag-gating requirement, verified against the live RPC before this task was written**: `chat_ephemeral_video` must be gated on top of Part 1's EXISTING `videoAttachEnabled` derivation (`chat_screen.dart:634-636`, `videoSharingEnabled AND imageSharingEnabled`), not as an independent check. The final capture-entry gate is a THREE-way AND: `chatEphemeralVideoEnabledProvider AND chatVideoSharingEnabledProvider AND chatImageSharingEnabledProvider`. This is because `create_chat_media_upload_intent` has no way to distinguish an ephemeral video intent from a gallery one — confirmed directly against the RPC's source during this plan's file-verification phase (Task 2's migration file header comment states this explicitly). Getting this wrong reproduces the exact class of bug Part 1's final review caught (client/server flag-gating mismatch) — a user could open the camera, record, and burn a full compress+send cycle before hitting a confusing server rejection if this three-way AND is not enforced client-side.

- [ ] **Step 1: Write the failing `MessageBubble` branch-ordering tests**

```dart
// Add to whichever of test/features/chat/message_bubble_test.dart or
// test/features/chat/presentation/widgets/message_bubble_test.dart is the
// established home for _BubbleBody-level tests — check both files' current
// content before choosing, per this task's own file-verification note.

  testWidgets('an isViewOnce unviewed video renders the sealed tile, not VideoMessagePlayer',
      (tester) async {
    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'other',
      content: '',
      createdAt: DateTime(2026, 8, 16),
      status: MessageStatus.sent,
      isMine: false,
      mediaType: 'video',
      isViewOnce: true,
      signedMediaUrl: 'https://example.com/clip.mp4',
    );
    // Pump MessageBubble(message: message, isMine: false) inside a
    // MaterialApp/ProviderScope per this test file's existing harness
    // pattern, then assert:
    // - find.byType(VideoMessagePlayer) returns nothing (the ordering
    //   requirement — an isViewOnce video message must NOT fall into the
    //   existing hasVideo branch, even though mediaType is also 'video').
    // - find.byIcon(Icons.play_arrow_rounded) or whatever sealed-tile
    //   affordance this task's implementation actually uses is present.
  });

  testWidgets('an isViewOnce viewed video renders the "Video expired" tombstone',
      (tester) async {
    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'other',
      content: '',
      createdAt: DateTime(2026, 8, 16),
      status: MessageStatus.sent,
      isMine: false,
      mediaType: 'video',
      isViewOnce: true,
      viewedAt: DateTime(2026, 8, 16, 12),
    );
    // Pump and assert: find.text('Video expired') is present, and no
    // tappable/interactive widget wraps it (per the design spec's "no
    // interactivity" requirement for the tombstone).
  });

  testWidgets('a non-view-once video message still renders VideoMessagePlayer unaffected',
      (tester) async {
    // Regression guard: an ordinary Part 1 gallery-pick video message
    // (isViewOnce == false, hasVideo == true) must render EXACTLY as it
    // did before this task — this is the test that would catch an
    // accidental branch-ordering regression breaking Part 1's existing
    // video messages.
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/message_bubble_test.dart` (and/or the presentation/widgets path — whichever this task's Step 1 targeted)
Expected: FAIL — no sealed-tile/tombstone rendering exists yet.

- [ ] **Step 3: Implement the `_BubbleBody` branches**

In `lib/features/chat/presentation/widgets/message_bubble.dart`, insert two new branches immediately BEFORE the existing `if (message.hasVideo)` check (before line ~420 per this plan's confirmed current line numbers):

```dart
    if (message.isEphemeralVideoExpired) {
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              'Video expired',
              style: TextStyle(color: color, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    } else if (message.isEphemeralVideoAvailable) {
      final videoUrl = message.localMediaPath ?? message.signedMediaUrl;
      if (videoUrl != null) {
        children.add(
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EphemeralVideoViewerScreen(
                    messageId: message.id,
                    videoUrl: videoUrl,
                    relationshipId: message.relationshipId,
                  ),
                ),
              );
            },
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded, size: 48),
              ),
            ),
          ),
        );
      }
    }
```

Add the required import at the top of `message_bubble.dart`:
```dart
import 'package:attune/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart';
```

**Note on `message.id` vs `message.clientMessageId`**: unlike `VoiceMessagePlayer`/`VideoMessagePlayer` (Part 1), which are keyed on `clientMessageId` because they're widgets held across the optimistic-to-canonical swap, `EphemeralVideoViewerScreen` is pushed fresh on every tap and passed `message.id` directly as its `messageId` param for the `markVideoViewed` RPC call — this is correct because by the time a user can tap to view an ephemeral video, the send has already completed and the message has a real server-assigned `id` (an optimistic, still-sending ephemeral video has no `signedMediaUrl` yet and `localMediaPath` only, so `isEphemeralVideoAvailable` is still true via the local-path branch — **confirm this is the intended pre-send-completion viewing behavior, or whether ephemeral videos should be un-tappable until fully sent**, since tapping to view your own not-yet-uploaded clip would pass a synthetic `_local_<clientMessageId>` id to `markVideoViewed`, which would fail server-side since no such row exists yet. This is a real edge case this task must resolve: either gate the sealed tile's tap handler on `!message.id.startsWith('_local_')` additionally, or accept that tapping before send-completion is a no-op/error the RPC call handles gracefully (it will simply find no matching row and no-op, per Task 2's RPC design) — the RPC's own no-op-on-no-match behavior actually makes this safe by construction, but confirm the UI doesn't show a confusing state (e.g. the viewer screen opening and immediately closing with no video visibly played) — consider disabling the tap handler while `message.status == MessageStatus.sending` as a UX improvement, not a correctness requirement.

- [ ] **Step 4: Add `chatEphemeralVideoEnabledProvider`**

In `lib/features/chat/presentation/state/chat_state.dart`, add next to `chatVideoSharingEnabledProvider` (wherever that's defined — Part 1 added it in the same file as `chatImageSharingEnabledProvider`):

```dart
final chatEphemeralVideoEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.ephemeralVideo,
  );
});
```

This requires `ChatFeatureFlags.ephemeralVideo` to exist as a constant — check `lib/features/chat/domain/services/chat_feature_flags.dart` for the exact convention Part 1 used for `videoSharing = 'chat_video_sharing'` and add `ephemeralVideo = 'chat_ephemeral_video'` following the identical pattern (matching the flag key this plan's Task 2 migration inserted).

- [ ] **Step 5: Add `showCaptureVideo`/`onCaptureVideo` to `ChatTextField`**

In `lib/features/chat/presentation/widgets/chat_text_field.dart`, add a fourth pair alongside the existing three (`onAttachImage`/`showAttachImage`, `onAttachVideo`/`showAttachVideo`, `onVoiceMessageRecorded`/`showVoiceMessage`):

```dart
    this.onCaptureVideo,
    // (in the constructor param list, alongside the other three pairs)
    this.showCaptureVideo = false,
```
```dart
  final VoidCallback? onCaptureVideo;
  final bool showCaptureVideo;
```

Add a new leading icon, alongside the existing Photo/Video icon (not inside its sheet — per the design spec's explicit choice of "new dedicated camera icon, leading position," not folded into the existing Photo/Video dispatcher):

```dart
          if (widget.showCaptureVideo)
            IconButton(
              onPressed: widget.enabled ? widget.onCaptureVideo : null,
              icon: const Icon(Icons.camera_alt_outlined),
              tooltip: 'Record a video',
            ),
```

Place this in the leading icon row alongside the existing conditional `if (widget.showAttachImage)` block — check the exact current widget tree structure before inserting, to place it visually adjacent per the design spec's "alongside the existing Photo/Video attach icon" requirement.

- [ ] **Step 6: Wire `EphemeralCameraScreen` into `chat_screen.dart`**

In `lib/features/chat/presentation/screens/chat_screen.dart`, add the flag watch and derived gate next to the existing `videoAttachEnabled` derivation (after line 636):

```dart
    final ephemeralVideoEnabled = ref.watch(chatEphemeralVideoEnabledProvider);
    // Same reasoning as videoAttachEnabled above: create_chat_media_upload_intent
    // cannot distinguish an ephemeral video intent from a gallery one (both
    // request media_type = 'video'), so chat_ephemeral_video must be layered
    // ON TOP of the existing chat_video_sharing AND chat_image_sharing gate,
    // not checked independently — see the 20260816130000 migration's header
    // comment, which is the source of truth to keep in sync with.
    final captureVideoEnabled =
        ephemeralVideoEnabled.valueOrNull == true && videoAttachEnabled;
```

Add the `_attachEphemeralCamera` method (near `_attachVideo`):

```dart
  Future<void> _attachEphemeralCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EphemeralCameraScreen(
          relationshipId: widget.conversation.relationshipId,
        ),
      ),
    );
  }
```

Wire it into the `ChatTextField` call site, alongside the existing `showAttachVideo`/`onAttachVideo` wiring:

```dart
              showCaptureVideo: captureVideoEnabled,
              onCaptureVideo:
                  captureVideoEnabled
                      ? () {
                        unawaited(_attachEphemeralCamera());
                      }
                      : null,
```

Add the required import:
```dart
import 'package:attune/features/chat/presentation/screens/ephemeral_camera_screen.dart';
```

- [ ] **Step 7: Write the `ChatTextField` additive-only and flag-gating tests**

```dart
// Add to test/features/chat/chat_text_field_test.dart

  testWidgets('camera icon absent by default, existing photo/video/voice icons unaffected',
      (tester) async {
    // Pump ChatTextField with none of showCaptureVideo/onCaptureVideo
    // passed, alongside the existing showAttachImage/showAttachVideo/
    // showVoiceMessage params exactly as Part 1's own tests already do —
    // assert find.byIcon(Icons.camera_alt_outlined) finds nothing, and
    // every pre-existing icon/behavior is unaffected (mirrors Part 1's
    // Task 7 test pattern exactly: this task must not disturb any
    // existing test in this file).
  });

  testWidgets('camera icon appears and calls onCaptureVideo when showCaptureVideo is true',
      (tester) async {
    var captureVideoCalled = 0;
    // Pump with showCaptureVideo: true, onCaptureVideo: () => captureVideoCalled++,
    // tap find.byIcon(Icons.camera_alt_outlined), assert captureVideoCalled == 1.
  });
```

Add a test in `chat_screen`-level tests (check whether one exists that already exercises `videoAttachEnabled`'s flag combinations from Part 1's own final-review fix — if so, mirror it exactly for the new three-way AND):

```dart
// A chat_screen-level or provider-level test asserting captureVideoEnabled
// is true ONLY when all three of chat_ephemeral_video, chat_video_sharing,
// AND chat_image_sharing are enabled — false for every other combination
// of the three flags. This is the direct test-coverage closure for the
// exact bug class Part 1's final review found (client gating that didn't
// mirror the server's actual requirement) — built in from the start here.
```

- [ ] **Step 8: Run all new/modified tests**

Run: `flutter test test/features/chat/message_bubble_test.dart test/features/chat/presentation/widgets/message_bubble_test.dart test/features/chat/chat_text_field_test.dart`
Expected: all PASS, including every pre-existing test in these files unmodified.

- [ ] **Step 9: Run `dart analyze` on every file this task touched**

Run: `dart analyze lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/widgets/chat_text_field.dart lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/domain/services/chat_feature_flags.dart`
Expected: `No issues found!`

- [ ] **Step 10: Run the full chat test suite for regressions**

Run: `flutter test test/features/chat/`
Expected: only the 2 known baseline failures — specifically confirm Part 1's `hasVideo`/`hasImage`/`hasAudio` bubble rendering and Part 1's Photo/Video attach-sheet tests all still pass unmodified.

- [ ] **Step 11: Commit**

```bash
git add lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/widgets/chat_text_field.dart lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/domain/services/chat_feature_flags.dart test/features/chat/message_bubble_test.dart test/features/chat/presentation/widgets/message_bubble_test.dart test/features/chat/chat_text_field_test.dart
git commit -m "feat(chat): wire ephemeral video sealed-tile/tombstone rendering, capture icon, three-way flag gate"
```

---

### Task 9: Screenshot detection — `ScreenshotDetectionService`, system-message convention, notice delivery

**Files:**
- Create: `lib/core/services/media/screenshot_detection_service.dart`
- Create platform code: `ios/Runner/` (a small Swift addition for the `UIApplication.userDidTakeScreenshotNotification` platform channel — exact file TBD by whoever implements, following this app's existing `ios/Runner/AppDelegate.swift` platform-channel registration pattern if one exists for another feature, or adding a new minimal channel registration if not) and `android/app/src/main/kotlin/` (a `ContentObserver`-based best-effort implementation, same investigate-existing-pattern-first approach)
- Modify: `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart` (wire the service in, scoped to this screen only)
- Modify: `supabase/migrations/20260816130000_chat_video_messages.sql` is ALREADY COMMITTED by Task 2 — this task adds a NEW, separate migration for the system-message convention (do not edit Task 2's committed file)
- Modify: `lib/features/chat/domain/entities/message.dart` (add the minimal system-message marker)
- Test: `test/core/services/media/screenshot_detection_service_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks except `EphemeralVideoViewerScreen` (Task 7) as the sole consumer scoping the service's lifetime.
- Produces: `ScreenshotDetectionService` exposing `Stream<void> get onScreenshotDetected` (or similar — exact name confirmed during implementation against whatever this task's own investigation into the codebase's existing service-class conventions turns out to prefer, mirroring `VoiceRecorderService`/`ImagePickerService`'s constructor-per-call-site-instantiation pattern, not a singleton).

**Confirmed by this plan's own file-verification phase**: there is NO existing system-message convention anywhere in this codebase (zero hits for `message_kind`, `is_system`, `SystemMessage`, or similar across `lib/features/chat/` and `supabase/migrations/`). This task genuinely invents one from scratch — the smallest viable addition, not a general-purpose system-message framework, since the only current use case is the screenshot notice.

- [ ] **Step 1: Add the minimal system-message convention (migration + `Message` field)**

Create `supabase/migrations/20260816140000_chat_screenshot_notice.sql`:

```sql
-- supabase/migrations/20260816140000_chat_screenshot_notice.sql
--
-- The smallest viable addition to support one new use case: an in-chat
-- notice when a screenshot is detected during ephemeral video viewing (see
-- design spec Section 7.5). Confirmed by direct search across this
-- codebase before writing this migration: there is NO existing
-- system-message/message_kind convention to reuse — this genuinely
-- invents the minimal one needed, not a general framework speculatively
-- built for hypothetical future system-message types.
--
-- A screenshot notice is NOT actually "authored by nobody" — per the
-- design spec, it's "authored as if from the viewer (the person who
-- screenshotted)" and rides the ordinary sender_id/insert path unchanged.
-- The only new thing is a flag distinguishing "this row is a system
-- notice, render it as plain informational text, not a normal bubble" —
-- everything else about how it's inserted, synced, and delivered reuses
-- the existing messages pipeline entirely.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS is_system_notice boolean NOT NULL DEFAULT false;
```

In `lib/features/chat/domain/entities/message.dart`, add one new field mirroring the exact same pattern as `isViewOnce` from Task 3 (field, constructor param, `fromRow`, `copyWith`, `toJson`/`fromJson` — `isSystemNotice` does NOT need an `optimistic` factory param, since a screenshot notice is never sent via the optimistic-outbox flow, only inserted directly server-confirmed):

```dart
  final bool isSystemNotice;
  // constructor: this.isSystemNotice = false,
  // fromRow: isSystemNotice: (row['is_system_notice'] as bool?) ?? false,
  // copyWith param + body: bool? isSystemNotice, / isSystemNotice: isSystemNotice ?? this.isSystemNotice,
  // toJson: 'isSystemNotice': isSystemNotice,
  // fromJson: isSystemNotice: (json['isSystemNotice'] as bool?) ?? false,
```

Widen `_messageColumns` (Task 4's location, `supabase_chat_repository.dart`) to add `,is_system_notice`, and widen `ChatRepository.sendTextMessage`/its implementation with one more optional param, `bool isSystemNotice = false`, threaded into the insert map — same mechanical pattern as `isViewOnce` in Task 4, not repeated in full here since it's identical in shape.

In `message_bubble.dart`'s `_BubbleBody.build()`, add a check at the very top (before the `isDeleted` check, since a system notice should never show the "deleted" treatment even if somehow both flags were set):

```dart
    if (message.isSystemNotice) {
      return Text(
        message.content,
        style: TextStyle(color: color, fontStyle: FontStyle.italic, fontSize: 13),
      );
    }
```

- [ ] **Step 2: Write the failing `ScreenshotDetectionService` tests**

```dart
// test/core/services/media/screenshot_detection_service_test.dart
import 'package:attune/core/services/media/screenshot_detection_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform channel degradation in test host', () {
    test('constructing the service and listening does not throw even with no real platform channel implementation', () async {
      // Mirrors the established pattern for VoiceRecorderService/
      // ChatVideoPreparer's native-call degradation: a pure-Dart
      // flutter test VM host has no real iOS/Android screenshot-detection
      // implementation registered, so any MethodChannel call this service
      // makes will throw MissingPluginException — the service itself must
      // catch this and simply never emit, not crash the caller.
      final service = ScreenshotDetectionService();
      var eventCount = 0;
      final subscription = service.onScreenshotDetected.listen((_) => eventCount++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 0); // no crash, no spurious emission
      await subscription.cancel();
      service.dispose();
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/core/services/media/screenshot_detection_service_test.dart`
Expected: FAIL — `screenshot_detection_service.dart` doesn't exist yet.

- [ ] **Step 4: Implement `ScreenshotDetectionService`**

```dart
// lib/core/services/media/screenshot_detection_service.dart
import 'dart:async';

import 'package:flutter/services.dart';

/// Best-effort screenshot detection, scoped to whatever screen constructs
/// it (per-call-site instantiation, not a singleton — mirrors
/// VoiceRecorderService/ImagePickerService's established pattern).
///
/// iOS: backed by UIApplication.userDidTakeScreenshotNotification via a
/// platform channel — a genuine, reliable system API.
/// Android: backed by a best-effort ContentObserver on the device's
/// screenshot media store path — acknowledged unreliable across
/// OEMs/launchers, shipped anyway per the design spec's explicit choice.
/// Neither platform detects screen RECORDING — not reliably available on
/// either OS.
///
/// In a pure-Dart test host (no real platform channel registered), method
/// calls throw MissingPluginException — caught and treated as "detection
/// unavailable," never surfaced as an error to callers, since this is
/// purely best-effort instrumentation and must never block the core
/// capture/send/view flow.
class ScreenshotDetectionService {
  static const _channel = MethodChannel('attune/screenshot_detection');

  final _controller = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _methodCallSubscription;

  Stream<void> get onScreenshotDetected => _controller.stream;

  ScreenshotDetectionService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshot') {
        _controller.add(null);
      }
    });
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _channel.invokeMethod<void>('startDetection');
    } catch (_) {
      // No real platform implementation (test host, or a platform this
      // service doesn't support) — silently no-op, per this service's
      // best-effort contract.
    }
  }

  void dispose() {
    unawaited(_channel.invokeMethod<void>('stopDetection').catchError((_) {}));
    _methodCallSubscription?.cancel();
    unawaited(_controller.close());
  }
}
```

**Implementer note on native platform code**: the actual iOS Swift (`UIApplication.userDidTakeScreenshotNotification` observer registered on `startDetection`, posting to the `attune/screenshot_detection` channel's `onScreenshot` method) and Android Kotlin (`ContentObserver` on `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` filtering for paths containing `Screenshot`, same best-effort caveat as the design spec states) are genuine native code this plan cannot fully write in advance without knowing the exact current `ios/Runner/AppDelegate.swift` and `android/app/src/main/kotlin/.../MainActivity.kt` structure. Read both files first to find the established pattern (if any other feature already registers a platform channel — check for one before assuming none exists) and add the channel handler following that exact convention. This is real, required implementation work for this task to be complete — not optional polish — but the Dart-side contract above (the `MethodChannel` name, the two method names, the stream shape) is what Task 7's `EphemeralVideoViewerScreen` integration (Step 5 below) depends on, so get that contract right even if the native implementation needs iteration.

- [ ] **Step 5: Wire `ScreenshotDetectionService` into `EphemeralVideoViewerScreen`**

In `lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart` (from Task 7), add the service, scoped to this screen's lifecycle only (constructed in `initState`, disposed in `dispose`):

```dart
  final _screenshotDetection = ScreenshotDetectionService();
  StreamSubscription<void>? _screenshotSubscription;

  // in initState, after the existing controller setup:
  _screenshotSubscription = _screenshotDetection.onScreenshotDetected.listen((_) {
    unawaited(_notifyScreenshot());
  });

  Future<void> _notifyScreenshot() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    await ref.read(chatRepositoryProvider).sendTextMessage(
      relationshipId: widget.relationshipId,
      senderId: user.id,
      clientMessageId: const Uuid().v4(),
      content: '${user.displayName ?? 'Someone'} took a screenshot',
      isSystemNotice: true,
    );
  }

  // in dispose, alongside the existing controller disposal:
  _screenshotSubscription?.cancel();
  _screenshotDetection.dispose();
```

**Implementer note**: `user.displayName` above is illustrative — confirm the actual current user-display-name accessor by checking how any other feature in this app already renders a user's name in a message/notification context (e.g. how reply-quote previews or typing indicators reference the other party's name), and use that exact accessor rather than guessing at a field name that may not exist on the current user model. This is a small, resolvable-by-reading-existing-code detail, not a structural decision.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/services/media/screenshot_detection_service_test.dart`
Expected: PASS.

- [ ] **Step 7: Run `dart analyze`**

Run: `dart analyze lib/core/services/media/screenshot_detection_service.dart lib/features/chat/domain/entities/message.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/core/services/media/screenshot_detection_service_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Run the full chat test suite for regressions**

Run: `flutter test`
Expected: only the 2 known baseline failures across the whole project — this is the first whole-project run in this plan, matching Part 1's own final-integration-task rigor requirement of naming every failure, not just asserting "no regressions."

- [ ] **Step 9: Commit**

```bash
git add supabase/migrations/20260816140000_chat_screenshot_notice.sql lib/core/services/media/screenshot_detection_service.dart lib/features/chat/domain/entities/message.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/ephemeral_video_viewer_screen.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart test/core/services/media/screenshot_detection_service_test.dart ios/ android/
git commit -m "feat(chat): add screenshot detection with in-chat system-notice delivery for ephemeral video viewing"
```

---

## Plan Self-Review

**Spec coverage check** — every section of `docs/superpowers/specs/2026-08-16-ephemeral-video-capture-design.md` maps to a task:
- Section 2 (reused infrastructure) → confirmed unchanged throughout, explicitly verified in each task's file-state notes rather than assumed.
- Section 3 (data model: `is_view_once`/`viewed_at`, no new media type) → Task 2 (migration), Task 3 (`Message` fields).
- Section 4 (`ChatVideoPreparer` extension) → Task 1.
- Section 5 (`mark_video_viewed` RPC) → Task 2, including the atomicity test the Global Constraints specifically demand.
- Section 6 (revocation delivery via existing subscription, offline-sender lazy discovery) → confirmed as a zero-new-code consequence of Task 2's RPC design + the app's existing realtime subscription; Task 7's `EphemeralVideoViewerScreen` handles the "currently open and gets revoked" UI case explicitly.
- Section 7.1-7.3 (capture entry point, camera screen, `sendEphemeralVideoMessage`) → Task 8 (composer wiring), Task 6 (camera screen), Task 5 (send method).
- Section 7.4 (bubble rendering, symmetric sender/receiver treatment, sealed tile → full-screen viewer, sender's-own-view-also-revokes confirmed) → Task 8 (bubble branches), Task 7 (viewer screen).
- Section 7.5 (screenshot detection, best-effort both platforms, in-chat delivery) → Task 9, including the from-scratch system-message convention this plan's own file-verification confirmed was genuinely needed.
- Section 8 (error handling table) → distributed across Task 6 (camera/permission errors, `ChatVideoRejected` mapping), Task 7 (network-retry-safe `markVideoViewed`, revoked-mid-view handling), Task 9 (screenshot-detection-failure silent no-op).
- Section 9 (explicitly out of scope) — confirmed no task drifts into screen-recording detection, push notifications, group ephemeral sends, forwarding/saving, or any change to Part 1's gallery-pick flow beyond Task 1's purely-additive optional parameters.
- Section 10 (feature flag, checklist scope) → Task 8's three-way AND gate resolves the "does this need paired-flag treatment" question definitively (yes, confirmed against the live RPC); `[MOBILE][MUTATION]` scope applied via Task 2's explicit citation of checklist items 1.1/2.18.

**Placeholder scan** — three places in this plan intentionally flag "resolve against actual architecture during implementation" rather than a blind guess: Task 6's `chatControllerProvider` conversation-param wiring, Task 7's `ref.listen` derived-provider expression for cross-device revocation, and Task 9's native iOS/Android platform-channel code and `user.displayName` accessor. Each of these is flagged with an explicit **Implementer note** explaining exactly what to read first and why the answer can't be fully determined without that read — this is different from a bare "TBD," since each note names the specific file/pattern to investigate and the specific contract that must be preserved regardless of how the investigation resolves. No bare "add appropriate handling" or "similar to Task N" placeholders were found on re-scan.

**Type/signature consistency check across tasks:**
- `ChatVideoPreparer.prepare()`'s new `maxDuration`/`maxBytes` params (Task 1) — consumed with identical names/types in Task 6's `VideoPrepareProgressDialog.show()` call.
- `mark_video_viewed(p_message_id uuid)` (Task 2) — consumed as `ChatRepository.markVideoViewed({required String messageId})` (Task 7), correctly bridging Postgres's `uuid` param name to Dart's camelCase convention, matching every other RPC-wrapping method in `supabase_chat_repository.dart`.
- `Message.isViewOnce`/`viewedAt`/`isEphemeralVideoAvailable`/`isEphemeralVideoExpired` (Task 3) — consumed identically in Task 5 (`sendEphemeralVideoMessage`'s optimistic `Message` construction), Task 8 (`_BubbleBody`'s branch conditions).
- `PendingSend.isViewOnce` (Task 5) — threaded through `_attemptSend`'s existing `sendTextMessage` call with the exact param name `isViewOnce` matching `ChatRepository.sendTextMessage`'s widened signature (Task 4).
- `ChatController.sendEphemeralVideoMessage({localPath, durationMs, thumbnailLocalPath, width, height})` (Task 5) — consumed with identical param names in Task 6's `EphemeralCameraScreen._prepareAndSend`.
- `EphemeralVideoViewerScreen({messageId, videoUrl, relationshipId})` (Task 7) — consumed identically in Task 8's `_BubbleBody` tap handler.
- `ChatTextField.showCaptureVideo`/`onCaptureVideo` (Task 8) — new pair, verified purely additive against the existing three pairs, no name collisions.
- `chatEphemeralVideoEnabledProvider`/`ChatFeatureFlags.ephemeralVideo` (Task 8) — new names, verified against Part 1's exact `chatVideoSharingEnabledProvider`/`ChatFeatureFlags.videoSharing` naming convention for consistency.
- `Message.isSystemNotice` (Task 9) — new field, deliberately NOT added to `Message.optimistic`'s param list (documented reasoning: never sent via the optimistic-outbox flow), consistent with how `viewedAt` was also deliberately excluded from `optimistic` in Task 3 for the analogous reason.

**Known gaps/decisions flagged explicitly within the plan itself** (not silently hidden): the atomicity test's live-vs-static verification split (Task 2, mirroring the exact same environment-availability caveat every migration task in this feature-family has carried since Part 1); the accepted, documented risk of `mark_video_viewed`'s deletion step failing after `viewed_at` is already committed (Task 2, explicitly not fixed in this task, with reasoning for why); the three genuinely-investigation-dependent implementer notes (Tasks 6, 7, 9) called out above; the tap-before-send-completion edge case for the sealed tile (Task 8), resolved by relying on `mark_video_viewed`'s own no-op-on-no-match safety rather than requiring new UI-layer gating, with an optional UX improvement noted but not mandated.
