# Streak Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Snapchat-style streaks — hold to record, auto-split into
60-second segments, review with a caption, send the batch as one
view-once message the recipient may optionally replay.

**Architecture:** A pure Dart state machine owns segmentation so the
split/cap/partial-segment rules are unit-testable without a camera. The
existing `EphemeralCameraScreen` is left untouched; streaks get their own
screen, their own `streak_clips` table hanging off one `messages` row,
and their own view RPC that decrements a budget instead of deleting on
first view.

**Tech Stack:** Flutter, `camera`, `video_player`, Riverpod, Supabase
(Postgres, RLS, `SECURITY DEFINER` RPCs).

**Spec:** `docs/superpowers/specs/2026-08-28-streak-camera-design.md`

## Global Constraints

- Segment length is **60 seconds**; the cap is **5 segments** (5 minutes).
- At the cap, **recording stops** and review opens with everything captured.
- **No previews under two segments.** A lone thumbnail for a lone clip is noise.
- A **partial final segment is kept**. The 500ms minimum applies only to the first.
- Every segment records **with audio** (`enableAudio: true`).
- Captions are **view-time only** — never in the chat row or the conversations preview.
- **Strict view-once by default**; the sender may opt into up to **3 total views**.
- Storage is deleted only when views remaining reaches **0** — never on first view.
- `media_type` widens to accept `'streak'` in **both** `messages` and
  `message_media_upload_intents`, in the same migration. Drift between exactly
  those two constraints hid the voice-note bug until `5c23cfc8`.
- Widening a CHECK means dropping the named constraint and re-adding it with
  **every existing branch reproduced verbatim**, so the change is provably a widening.
- `CREATE OR REPLACE FUNCTION` resets privileges — every replaced function must
  reapply its `REVOKE ALL ... FROM PUBLIC, anon` and `GRANT EXECUTE ... TO authenticated`.
- Screenshot detection is **not** in scope and must not be implied anywhere in the UI.

---

### Task 1: The segmentation state machine

Pure Dart, no camera. This is where every rule the spec argues about
lives, so it must be testable without hardware.

**Files:**
- Create: `lib/features/chat/domain/services/streak_recording_session.dart`
- Test: `test/features/chat/streak_recording_session_test.dart`

**Interfaces:**
- Produces:
  - `const Duration kStreakSegmentDuration = Duration(seconds: 60);`
  - `const int kStreakMaxSegments = 5;`
  - `const Duration kStreakMinFirstSegment = Duration(milliseconds: 500);`
  - `class StreakSegment { final String path; final Duration duration; }`
  - `class StreakRecordingSession` with `bool shouldSplitAt(Duration elapsed)`,
    `bool shouldStopAt(int completedSegments)`, `bool shouldDiscard(...)`,
    `bool showPreviews(int completedSegments)`

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/streak_recording_session_test.dart`:

```dart
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitting', () {
    test('splits exactly at 60 seconds, not before', () {
      expect(StreakRecordingSession.shouldSplitAt(
          const Duration(seconds: 59, milliseconds: 999)), isFalse);
      expect(StreakRecordingSession.shouldSplitAt(
          const Duration(seconds: 60)), isTrue);
    });
  });

  group('the segment cap', () {
    test('stops once five segments are complete', () {
      expect(StreakRecordingSession.shouldStopAt(4), isFalse);
      expect(StreakRecordingSession.shouldStopAt(5), isTrue);
    });
  });

  group('previews', () {
    test('none for a single segment — a lone thumbnail is noise', () {
      expect(StreakRecordingSession.showPreviews(0), isFalse);
      expect(StreakRecordingSession.showPreviews(1), isFalse);
    });

    test('appear from the second segment', () {
      expect(StreakRecordingSession.showPreviews(2), isTrue);
    });
  });

  group('the minimum hold', () {
    test('a stray tap sends nothing', () {
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 0, held: const Duration(milliseconds: 200)),
        isTrue,
      );
    });

    test('a first segment past the minimum is kept', () {
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 0, held: const Duration(milliseconds: 900)),
        isFalse,
      );
    });

    test('a SHORT partial second segment is still kept', () {
      // The minimum guards a stray tap, not a deliberate release. Dropping
      // this would lose content the user watched themselves record.
      expect(
        StreakRecordingSession.shouldDiscard(
            completedSegments: 1, held: const Duration(milliseconds: 200)),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chat/streak_recording_session_test.dart`
Expected: FAIL — `streak_recording_session.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/chat/domain/services/streak_recording_session.dart`:

```dart
/// One segment's length. Deliberately 60s rather than Snapchat's 10s:
/// a partner talking for a minute is the unit of value here, where
/// Snapchat optimises for a rapid highlight reel.
const Duration kStreakSegmentDuration = Duration(seconds: 60);

/// Hard ceiling. At this many completed segments recording STOPS and
/// review opens — the alternative (a rolling window dropping the oldest)
/// silently discards what the user recorded with nothing in the UI able
/// to explain it.
const int kStreakMaxSegments = 5;

/// Guards a stray tap on the FIRST segment only.
const Duration kStreakMinFirstSegment = Duration(milliseconds: 500);

/// One recorded clip awaiting review.
class StreakSegment {
  const StreakSegment({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

/// The segmentation rules, separated from the camera so they can be
/// tested without hardware.
class StreakRecordingSession {
  const StreakRecordingSession._();

  static bool shouldSplitAt(Duration elapsed) =>
      elapsed >= kStreakSegmentDuration;

  static bool shouldStopAt(int completedSegments) =>
      completedSegments >= kStreakMaxSegments;

  /// Previews appear only once a SECOND segment exists.
  static bool showPreviews(int completedSegments) => completedSegments >= 2;

  /// Whether to throw the whole thing away on release.
  ///
  /// The minimum applies only to the first segment. A short partial
  /// second segment is real content the user watched themselves record.
  static bool shouldDiscard({
    required int completedSegments,
    required Duration held,
  }) =>
      completedSegments == 0 && held < kStreakMinFirstSegment;
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/features/chat/streak_recording_session_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Verify the tests are not vacuous**

Change `shouldSplitAt` to `elapsed >= const Duration(seconds: 10)` and
re-run: the split test must fail. Change `showPreviews` to
`completedSegments >= 1`: the preview test must fail. Restore both.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/domain/services/streak_recording_session.dart test/features/chat/streak_recording_session_test.dart
git commit -m "feat(streak): segmentation state machine"
```

---

### Task 2: Schema — streak_clips and the widened constraints

**Files:**
- Create: `supabase/migrations/20260913210000_streak_clips.sql`
- Create: `supabase/tests/streak_contracts.sql`

**Interfaces:**
- Produces: `public.streak_clips`; `messages.streak_views_remaining`;
  `'streak'` accepted by both `media_type` constraints.

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/streak_contracts.sql`. Self-contained — reading an
ambient relationship makes it skip silently and pass vacuously on an
empty database:

```sql
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5f000000-0000-0000-0000-0000000000a1'),
  ('5f000000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('5f000000-0000-0000-0000-0000000000a1', '+233250000001', 'Streak A'),
  ('5f000000-0000-0000-0000-0000000000b2', '+233250000002', 'Streak B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('5e000000-0000-0000-0000-000000000001',
        '5f000000-0000-0000-0000-0000000000a1',
        '5f000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. Both media_type constraints accept 'streak', and stay in step.
--    Drift between exactly these two hid the voice-note bug (5c23cfc8):
--    the upload intent succeeded and only the insert failed.
DO $$
DECLARE v_messages text; v_intents text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_messages
  FROM pg_constraint WHERE conname = 'messages_media_type_check';
  SELECT pg_get_constraintdef(oid) INTO v_intents
  FROM pg_constraint
  WHERE conname = 'message_media_upload_intents_media_type_check';

  IF v_messages NOT LIKE '%streak%' THEN
    RAISE EXCEPTION 'messages_media_type_check rejects streak: %', v_messages;
  END IF;
  IF v_intents NOT LIKE '%streak%' THEN
    RAISE EXCEPTION 'upload intents reject streak: %', v_intents;
  END IF;
END $$;

-- 2. Clips cascade with their message: a deleted streak leaves nothing.
DO $$
DECLARE v_msg uuid; v_left int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content, media_type)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), '', NULL)
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips
    (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/clip-0', 60000),
         (v_msg, 1, 'chat/clip-1', 20000);

  DELETE FROM public.messages WHERE id = v_msg;

  SELECT count(*) INTO v_left
  FROM public.streak_clips WHERE message_id = v_msg;
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % clips survived their message', v_left;
  END IF;
END $$;

-- 3. clip_index is unique per message: playback order must be unambiguous.
DO $$
DECLARE v_msg uuid; v_dup boolean := false;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content, media_type)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), '', NULL)
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/a', 1000);

  BEGIN
    INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
    VALUES (v_msg, 0, 'chat/b', 1000);
    v_dup := true;
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  IF v_dup THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: duplicate clip_index accepted';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `scripts/local_pg_setup.sh`
Expected: FAIL — `messages_media_type_check rejects streak`.

If the runner reports no database, STOP and report it: this task cannot
be verified blind, and writing unverified SQL that widens a constraint is
what produced the C2 breach.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260913210000_streak_clips.sql`. Read the
CURRENT constraint definition first and transcribe its branches verbatim —
an earlier plan reproduced a constraint from memory and silently relaxed a
neighbour:

Run: `psql -d attune_test -tAc "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='messages_media_type_check';"`

```sql
-- Streaks: several clips, one message.
--
-- media_type widens in BOTH tables here. When voice notes broke
-- (5c23cfc8) the upload-intents constraint had been widened and
-- messages' had not, so the intent succeeded, the file uploaded, and
-- only the final insert failed -- which read as a client bug for weeks.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (media_type IS NULL
         OR media_type IN ('image', 'audio', 'video', 'streak'));

ALTER TABLE public.message_media_upload_intents
  DROP CONSTRAINT IF EXISTS message_media_upload_intents_media_type_check;
ALTER TABLE public.message_media_upload_intents
  ADD CONSTRAINT message_media_upload_intents_media_type_check
  CHECK (media_type IN ('image', 'audio', 'video', 'streak'));

-- Remaining views. 1 = strict view-once (the default); the sender may
-- opt into up to 3. NOT nullable: a null budget on a streak would be
-- ambiguous exactly where ambiguity costs privacy.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS streak_views_remaining int NOT NULL DEFAULT 1
    CHECK (streak_views_remaining BETWEEN 0 AND 3);

CREATE TABLE IF NOT EXISTS public.streak_clips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL
    REFERENCES public.messages(id) ON DELETE CASCADE,
  clip_index int NOT NULL,
  media_url text NOT NULL,
  media_thumbnail_url text,
  duration_ms int NOT NULL CHECK (duration_ms > 0),
  width int,
  height int,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_id, clip_index)
);

CREATE INDEX IF NOT EXISTS idx_streak_clips_message
  ON public.streak_clips(message_id, clip_index);

ALTER TABLE public.streak_clips ENABLE ROW LEVEL SECURITY;

-- Members of the owning relationship only, reached through the message.
CREATE POLICY streak_clips_members_read
ON public.streak_clips FOR SELECT
USING (
  message_id IN (
    SELECT m.id FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
  )
);

-- Only the sender writes clips, and only for their own message.
CREATE POLICY streak_clips_sender_write
ON public.streak_clips FOR INSERT
WITH CHECK (
  message_id IN (
    SELECT m.id FROM public.messages m
    WHERE m.sender_id = auth.uid()
  )
);

COMMENT ON TABLE public.streak_clips IS
  'Ordered segments of one streak message. Playback is clip_index ASC.';
```

- [ ] **Step 4: Apply and verify**

Run: `scripts/local_pg_setup.sh`
Expected: all contract files PASS, including `streak_contracts`, and
`chat_system_contracts` still passes — that is what proves image, audio
and video were not disturbed by the constraint rewrite.

- [ ] **Step 5: Verify the test is not vacuous**

Drop `'streak'` from the `messages` branch only and re-run: the drift
check must fail. Restore.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260913210000_streak_clips.sql supabase/tests/streak_contracts.sql
git commit -m "feat(streak): streak_clips schema and widened media_type"
```

---

### Task 3: The view RPC with a replay budget

**Files:**
- Create: `supabase/migrations/20260913220000_mark_streak_viewed.sql`
- Modify: `supabase/tests/streak_contracts.sql`

**Interfaces:**
- Consumes: `streak_clips`, `messages.streak_views_remaining` (Task 2).
- Produces: `mark_streak_viewed(p_message_id uuid) RETURNS int` — the
  remaining count after decrementing.

- [ ] **Step 1: Add the failing contract test**

Append to `supabase/tests/streak_contracts.sql`, before `ROLLBACK`:

```sql
-- 4. Views decrement, and storage is deleted only at ZERO.
--
-- mark_video_viewed deletes the object on FIRST view, which is right for
-- strict view-once and fatal for a budget. Streaks need their own path.
DO $$
DECLARE v_msg uuid; v_left int;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     media_type, streak_views_remaining)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), '', 'streak', 3)
  RETURNING id INTO v_msg;

  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/clip-0', 60000);

  -- The RECIPIENT views it.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000b2',
                      'role', 'authenticated')::text, true);

  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 views left, got %', v_left;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: clips destroyed while views still remained';
  END IF;

  v_left := public.mark_streak_viewed(v_msg);
  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 0 views left, got %', v_left;
  END IF;

  -- Spent: a further view must not go negative.
  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: budget went below zero (%)', v_left;
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. A non-member cannot view, or even probe, another couple's streak.
DO $$
DECLARE v_msg uuid; v_ok boolean := false;
BEGIN
  INSERT INTO auth.users (id) VALUES ('5f000000-0000-0000-0000-0000000000c3')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content,
     media_type, streak_views_remaining)
  VALUES ('5e000000-0000-0000-0000-000000000001',
          '5f000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), '', 'streak', 1)
  RETURNING id INTO v_msg;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '5f000000-0000-0000-0000-0000000000c3',
                      'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  IF v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member viewed a streak';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

Run: `scripts/local_pg_setup.sh`
Expected: FAIL — `function public.mark_streak_viewed(uuid) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260913220000_mark_streak_viewed.sql`:

```sql
-- Spends one view of a streak, returning what remains.
--
-- Deliberately NOT mark_video_viewed: that function deletes the storage
-- object on first view, which is correct for strict view-once and fatal
-- for a replay budget. This deletes only when the budget reaches zero,
-- so a replayable streak outlives a view-once one on the server. That is
-- a real privacy difference, and why replays are opt-in and capped.
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_member boolean;
  v_sender uuid;
  v_left int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE m.id = p_message_id
      AND (r.user_a = v_user_id OR r.user_b = v_user_id)
  ), (SELECT sender_id FROM public.messages WHERE id = p_message_id)
  INTO v_is_member, v_sender;

  IF NOT v_is_member THEN
    -- Same response for "belongs to someone else" and "does not exist":
    -- a distinguishable error is a membership oracle.
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  -- The sender re-opening their own streak must not spend the
  -- recipient's budget.
  IF v_sender = v_user_id THEN
    SELECT streak_views_remaining INTO v_left
    FROM public.messages WHERE id = p_message_id;
    RETURN v_left;
  END IF;

  -- GREATEST floors at zero so a double-tap cannot drive it negative.
  UPDATE public.messages
     SET streak_views_remaining = GREATEST(streak_views_remaining - 1, 0)
   WHERE id = p_message_id
   RETURNING streak_views_remaining INTO v_left;

  IF v_left = 0 THEN
    DELETE FROM storage.objects
    WHERE name IN (
      SELECT media_url FROM public.streak_clips WHERE message_id = p_message_id
    );
    DELETE FROM public.streak_clips WHERE message_id = p_message_id;
  END IF;

  RETURN v_left;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_streak_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_streak_viewed(uuid) TO authenticated;
```

- [ ] **Step 4: Apply and verify**

Run: `scripts/local_pg_setup.sh`
Expected: all contract files PASS.

- [ ] **Step 5: Verify the tests are not vacuous**

Remove the `IF v_left = 0` guard so it deletes on every view: the
"destroyed while views still remained" assertion must fail. Remove the
membership check: the non-member assertion must fail. Restore both.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260913220000_mark_streak_viewed.sql supabase/tests/streak_contracts.sql
git commit -m "feat(streak): view RPC with a replay budget"
```

---

### Task 4: Repository and send path

**Files:**
- Create: `lib/features/chat/data/repositories/streak_repository.dart`
- Test: `test/features/chat/streak_repository_test.dart`

**Interfaces:**
- Consumes: `mark_streak_viewed` (Task 3), `StreakSegment` (Task 1),
  and the existing
  `ChatVideoPreparer.prepare({required String localPath, Duration? trimStart,
  Duration? trimEnd, void Function(double)? onProgress, Duration? maxDuration,
  int? maxBytes})` returning `PreparedChatVideo` (`.file`, `.durationMs`,
  `.thumbnailFile`, `.width`, `.height`).
- Produces: `StreakRepository` with
  `Future<int> markViewed(String messageId)` and
  `Future<List<StreakClip>> fetchClips(String messageId)`;
  `class StreakClip { final int index; final String mediaUrl; final int durationMs; }`

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/streak_repository_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StreakClip parses a row in playback order', () {
    final clips = [
      StreakClip.fromRow(const {
        'clip_index': 1, 'media_url': 'b', 'duration_ms': 20000}),
      StreakClip.fromRow(const {
        'clip_index': 0, 'media_url': 'a', 'duration_ms': 60000}),
    ]..sort((x, y) => x.index.compareTo(y.index));

    expect(clips.map((c) => c.mediaUrl), ['a', 'b']);
  });

  test('fetchClips selects no caption or budget columns', () {
    // The caption is view-time only and the budget is server-owned. A
    // client select that pulled either invites rendering them in the
    // chat row, which the spec forbids.
    final src = File(
      'lib/features/chat/data/repositories/streak_repository.dart',
    ).readAsStringSync();
    final select = RegExp(r"\.select\('([^']*clip_index[^']*)'\)")
        .firstMatch(src)
        ?.group(1);

    expect(select, isNotNull);
    expect(select, contains('media_url'));
    expect(select, isNot(contains('caption')));
    expect(select, isNot(contains('streak_views_remaining')));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chat/streak_repository_test.dart`
Expected: FAIL — `streak_repository.dart` does not exist.

- [ ] **Step 3: Write the repository**

Create `lib/features/chat/data/repositories/streak_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// One segment of a streak, in playback order.
class StreakClip {
  const StreakClip({
    required this.index,
    required this.mediaUrl,
    required this.durationMs,
  });

  factory StreakClip.fromRow(Map<String, dynamic> row) => StreakClip(
        index: (row['clip_index'] as num).toInt(),
        mediaUrl: row['media_url'] as String,
        durationMs: (row['duration_ms'] as num).toInt(),
      );

  final int index;
  final String mediaUrl;
  final int durationMs;
}

class StreakRepository {
  StreakRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  /// Spends one view, returning what remains.
  ///
  /// Through the RPC, never a direct UPDATE: messages' RLS would let a
  /// client write any value, including refilling its own budget.
  Future<int> markViewed(String messageId) async {
    final result = await _safeClient.rpc(
      'mark_streak_viewed',
      params: {'p_message_id': messageId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  /// The clips of one streak, in playback order.
  ///
  /// Named columns only. The caption is view-time state held by the
  /// viewer, and the budget is server-owned — pulling either here invites
  /// rendering them somewhere the spec forbids.
  Future<List<StreakClip>> fetchClips(String messageId) async {
    final rows = await _safeClient
        .from('streak_clips')
        .select('clip_index, media_url, duration_ms')
        .eq('message_id', messageId)
        .order('clip_index');

    return rows
        .map((row) => StreakClip.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/features/chat/streak_repository_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify the column test is not vacuous**

Add `, streak_views_remaining` to the select and re-run: it must fail.
Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/data/repositories/streak_repository.dart test/features/chat/streak_repository_test.dart
git commit -m "feat(streak): repository and clip model"
```

---

### Task 5: The progress ring

**Files:**
- Create: `lib/features/chat/presentation/widgets/streak_record_button.dart`
- Test: `test/features/chat/streak_record_button_test.dart`

**Interfaces:**
- Consumes: `kStreakSegmentDuration` (Task 1).
- Produces: `StreakRecordButton({required double progress,
  required bool isRecording, required VoidCallback onPressStart,
  required VoidCallback onPressEnd})`

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/streak_record_button_test.dart`:

```dart
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ring shows segment progress while recording',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0.5,
          isRecording: true,
          onPressStart: () {},
          onPressEnd: () {},
        ),
      ),
    ));

    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, 0.5);
  });

  testWidgets('no ring when idle', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0,
          isRecording: false,
          onPressStart: () {},
          onPressEnd: () {},
        ),
      ),
    ));
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('press and release both fire', (tester) async {
    var started = false;
    var ended = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StreakRecordButton(
          progress: 0,
          isRecording: false,
          onPressStart: () => started = true,
          onPressEnd: () => ended = true,
        ),
      ),
    ));

    // Pointer events, not a long-press: the recorder bug in 511f4665 was
    // exactly this — onPanEnd never fires for a press with no movement,
    // so a quick tap started a recording that never stopped.
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(StreakRecordButton)));
    await tester.pump(const Duration(milliseconds: 50));
    expect(started, isTrue);

    await gesture.up();
    await tester.pump();
    expect(ended, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chat/streak_record_button_test.dart`
Expected: FAIL — `streak_record_button.dart` does not exist.

- [ ] **Step 3: Write the widget**

Create `lib/features/chat/presentation/widgets/streak_record_button.dart`:

```dart
import 'package:flutter/material.dart';

/// The capture button, with a circular progress ring drawn AROUND it that
/// fills over one segment's duration and resets at each split — a full
/// sweep is the signal that a segment just closed.
///
/// A raw Listener rather than GestureDetector's pan callbacks: pan does
/// not report an end for a press with no movement, so a quick tap would
/// start a recording that never stops (the bug fixed in 511f4665).
class StreakRecordButton extends StatelessWidget {
  const StreakRecordButton({
    super.key,
    required this.progress,
    required this.isRecording,
    required this.onPressStart,
    required this.onPressEnd,
  });

  /// 0..1 through the current segment.
  final double progress;
  final bool isRecording;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPressStart(),
      onPointerUp: (_) => onPressEnd(),
      onPointerCancel: (_) => onPressEnd(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              SizedBox(
                width: _size,
                height: _size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            Container(
              width: isRecording ? 44 : 60,
              height: isRecording ? 44 : 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording ? Colors.redAccent : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/features/chat/streak_record_button_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/chat/presentation/widgets/streak_record_button.dart test/features/chat/streak_record_button_test.dart
git commit -m "feat(streak): record button with a segment progress ring"
```

---

### Task 6: The camera screen

**Files:**
- Create: `lib/features/chat/presentation/screens/streak_camera_screen.dart`
- Test: `test/features/chat/streak_camera_test.dart`

**Interfaces:**
- Consumes: `StreakRecordingSession` (Task 1), `StreakRecordButton` (Task 5).
- Produces: `StreakCameraScreen({required Conversation conversation})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/streak_camera_test.dart`. It drives the
segmentation through the state machine rather than a real camera:

```dart
import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a three-minute hold produces three segments', () {
    var completed = 0;
    var elapsed = Duration.zero;

    for (var second = 1; second <= 180; second++) {
      elapsed += const Duration(seconds: 1);
      if (StreakRecordingSession.shouldSplitAt(elapsed)) {
        completed += 1;
        elapsed = Duration.zero;
        if (StreakRecordingSession.shouldStopAt(completed)) break;
      }
    }

    expect(completed, 3);
    expect(StreakRecordingSession.showPreviews(completed), isTrue);
  });

  test('recording stops at the five-segment cap', () {
    var completed = 0;
    var elapsed = Duration.zero;
    var stopped = false;

    for (var second = 1; second <= 600; second++) {
      elapsed += const Duration(seconds: 1);
      if (StreakRecordingSession.shouldSplitAt(elapsed)) {
        completed += 1;
        elapsed = Duration.zero;
        if (StreakRecordingSession.shouldStopAt(completed)) {
          stopped = true;
          break;
        }
      }
    }

    expect(completed, 5);
    expect(stopped, isTrue, reason: 'ten minutes must not queue ten clips');
  });

  test('a 40-second hold produces one clip and no previews', () {
    var completed = 0;
    var elapsed = Duration.zero;
    for (var second = 1; second <= 40; second++) {
      elapsed += const Duration(seconds: 1);
      if (StreakRecordingSession.shouldSplitAt(elapsed)) {
        completed += 1;
        elapsed = Duration.zero;
      }
    }
    expect(completed, 0);
    expect(StreakRecordingSession.showPreviews(completed), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it passes**

Run: `flutter test test/features/chat/streak_camera_test.dart`
Expected: PASS (3 tests) — these exercise Task 1's rules directly, so
they pass once the state machine is right. They exist to pin the
end-to-end segmentation arithmetic, which is easy to get subtly wrong in
the screen's timer loop.

- [ ] **Step 3: Write the screen**

Create `lib/features/chat/presentation/screens/streak_camera_screen.dart`,
modelled on `ephemeral_camera_screen.dart`. Five rules it must follow:

- **Cover-crop the preview.** Copy the `LayoutBuilder`/`OverflowBox`/
  `FittedBox(fit: BoxFit.cover)` treatment from
  `ephemeral_camera_screen.dart` — a bare `CameraPreview` in a
  `StackFit.expand` Stack stretches the sensor image.
- **`enableAudio: true`** on the controller.
- **A `Timer.periodic(const Duration(milliseconds: 100))`** drives the
  ring's progress and calls `StreakRecordingSession.shouldSplitAt`.
  On a split: stop the recorder, keep the file, start a new recording,
  reset elapsed, fire a `HapticFeedback.selectionClick()`.
- **Guard the async start.** `_startRecording` awaits permission and
  `controller.startVideoRecording()`; a release inside that window must be
  remembered and finish the recording, or the camera stays live with no UI
  (the bug fixed in `511f4665`).
- **On release** call `StreakRecordingSession.shouldDiscard`. If true,
  delete every staged file and pop. Otherwise push the review sheet.

- [ ] **Step 4: Assert the camera records audio**

The spec requires it and only a source assertion can pin it — a widget
test cannot observe a real `CameraController`'s configuration. Append to
`test/features/chat/streak_camera_test.dart`:

```dart
  test('the camera is configured to record audio', () {
    // A streak is someone talking to their partner. A muted format
    // removes most of what makes it worth sending, and the default is
    // easy to lose in a later refactor.
    final src = File(
      'lib/features/chat/presentation/screens/streak_camera_screen.dart',
    ).readAsStringSync();
    expect(src, contains('enableAudio: true'));
  });
```

with `import 'dart:io';` at the top of the file.

Run: `flutter test test/features/chat/streak_camera_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Verify the analyzer is clean**

Run: `flutter analyze lib/features/chat/presentation/screens/streak_camera_screen.dart`
Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/screens/streak_camera_screen.dart test/features/chat/streak_camera_test.dart
git commit -m "feat(streak): segmented camera screen"
```

---

### Task 7: Review sheet, viewer, and chat row

**Files:**
- Create: `lib/features/chat/presentation/widgets/streak_review_sheet.dart`
- Create: `lib/features/chat/presentation/screens/streak_viewer_screen.dart`
- Modify: `lib/features/chat/domain/utils/conversation_preview.dart`
- Test: `test/features/chat/streak_privacy_test.dart`

**Interfaces:**
- Consumes: `StreakClip`, `StreakRepository` (Task 4), `StreakSegment` (Task 1).
- Produces: `StreakReviewSheet({required List<StreakSegment> segments,
  required void Function(String caption, bool allowReplays) onSend,
  required VoidCallback onDiscard})`;
  `StreakViewerScreen({required String messageId, required String? caption})`.

- [ ] **Step 1: Write the failing privacy test**

Create `test/features/chat/streak_privacy_test.dart`:

```dart
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/utils/conversation_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _withLast(Message message) => Conversation(
      id: 'c1',
      relationshipId: 'rel-1',
      partnerId: 'user-b',
      name: 'Ama',
      availability: ConversationAvailability.active,
      unreadCount: 0,
      updatedAt: DateTime.utc(2026, 1, 1),
      relationshipStatus: 'active',
      lastMessage: message,
    );

void main() {
  test('the conversations preview says Streak and never the caption', () {
    final preview = conversationPreviewText(_withLast(Message(
      id: 'm1',
      clientMessageId: 'cm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'a private caption',
      createdAt: DateTime.utc(2026, 1, 1),
      status: MessageStatus.sent,
      isMine: false,
      mediaType: 'streak',
    )));

    expect(preview, 'Streak');
    expect(
      preview,
      isNot(contains('a private caption')),
      reason: 'a caption is view-time only — revealing it in the list '
          'defeats the point of an unopened streak',
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chat/streak_privacy_test.dart`
Expected: FAIL — the preview returns `'Streak: a private caption'`,
because `conversationPreviewText` appends captions for every media type.

- [ ] **Step 3: Special-case streak in the preview**

Modify `lib/features/chat/domain/utils/conversation_preview.dart`:

```dart
  final label = labels[message.mediaType];
  if (label != null) {
    // A streak reveals nothing before it is opened — not even a caption,
    // which is view-time state. Every other media type appends its
    // caption as usual.
    if (message.mediaType == 'streak') return label;
    return caption.isEmpty ? label : '$label: $caption';
  }
```

and add `'streak': 'Streak',` to the `labels` map.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/features/chat/streak_privacy_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the review sheet and viewer**

`StreakReviewSheet`: a caption `TextField`, an "Allow replays" `Switch`
(off by default — strict view-once is the default and the sender opts
out), a send button, and a discard action that deletes every staged file.

`StreakViewerScreen`: plays clips in `clip_index` order through
`VideoPlayerController`, renders the caption as a `Stack` overlay near
the bottom, and calls `StreakRepository.markViewed` once on completion or
dismissal — once per viewing, never once per clip, or a three-clip streak
would spend three views.

- [ ] **Step 6: Verify the whole suite**

Run: `flutter test && flutter analyze lib/ test/`
Expected: all tests pass, 0 analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/presentation/widgets/streak_review_sheet.dart lib/features/chat/presentation/screens/streak_viewer_screen.dart lib/features/chat/domain/utils/conversation_preview.dart test/features/chat/streak_privacy_test.dart
git commit -m "feat(streak): review sheet, viewer and private chat preview"
```

---

## Execution note

Tasks 2 and 3 are SQL and require a database — `scripts/local_pg_setup.sh`
builds one from the migrations on a plain Postgres, no Docker needed. Do
not write those migrations without running the contract tests: both widen
constraints or touch storage deletion, and unverified SQL of exactly that
shape produced the C2 breach and the voice-note outage.

Tasks 1, 4, 5 and 7 are pure Flutter. Task 6 needs a device to feel
right — the segmentation arithmetic is unit-tested, but ring timing,
haptics and preview placement are judgement calls no widget test settles.
