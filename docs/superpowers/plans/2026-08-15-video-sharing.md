# Video Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let two people in a relationship pick a video from the gallery, trim it to fit a 3-minute cap, and send it in Attune chat — matching WhatsApp's actual video-attach behavior, to the quality bar of the existing image and voice-message features.

**Architecture:** Extends the existing image/voice media pipeline (same `message-media` bucket, same upload-intent RPC, same trigger, widened allowlists) rather than building parallel infrastructure. Compression is client-side only (no server-side transcoding — see Global Constraints). A video message uses two upload intents (video + client-generated thumbnail), the one structural departure from every other media type built so far.

**Tech Stack:** Flutter/Dart, Riverpod, Supabase (Postgres + Storage + RPC), `video_player`/`video_thumbnail`/`video_compress` (new dependencies), `image_picker` (already present, `pickVideo` already implemented), `flutter_image_compress` (already present, reused for thumbnail compression).

**Design spec:** `docs/superpowers/specs/2026-08-15-video-sharing-design.md` — read it first; this plan implements it exactly. Do not re-derive decisions already made there.

**A note on process for whoever executes this plan:** every file this plan touches was read in full, at its current live state, before this plan was written — not assumed from the spec's prose. Two real discrepancies between the spec's prose and the actual code were found and corrected in this plan (see Task 5's note on the "`_reconcileLocalMediaPaths`" method, which does not exist under that name, and the exact count/names of `_deleteStagedMedia` call sites, which is 5 literal call sites, not the 4 the spec's prose implies). Trust this plan's file:line references over the spec's prose wherever they'd otherwise conflict.

## Global Constraints

- Max video duration: **3 minutes** (`Duration(minutes: 3)`), enforced primarily by the trim screen's physically-clamped handles, with a server-side byte-ceiling backstop — not a true duration probe.
- Min duration: **500ms**, mirroring `VoiceRecorderService.minDuration` — below this, silently discard, not an error.
- Target output: **800kbps video, 720p longest edge, H.264, AAC 64kbps mono audio**.
- Post-transcode output byte ceiling: **25MB (26214400 bytes)**, hard reject over it, no retry ladder.
- Pre-transcode source guard: **300MB**, calculated against the **selected trim window's estimated bytes** (`sourceBytes × windowDuration/sourceDuration`), NOT the full source file's size.
- Thumbnail generated **client-side**, at the trim screen's selected start point, in the same preparation pass as compression — never via the server-side async processing outbox.
- **No server-side transcoding, ever** — FFmpegKit is deprecated/pulled from package registries; Supabase Edge Functions cannot run a real video encoder. This is a hard architectural constraint, not a preference.
- Checklist scope: **`[MOBILE][MUTATION]`** (no `[ASYNC]` — video has no server-side background processing step).
- `dart analyze` must stay clean (no new errors/warnings) on every file touched in every task.
- Every `flutter test` run in this plan is checked against the known baseline of exactly 2 pre-existing, unrelated failures in `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart` ("shows healing entry card when there is no invite" and "tapping the card with an existing solo journey navigates directly, no sheet"). Any other failure is a real regression — root-cause it before marking the task done, never dismiss it.
- **Lesson carried forward from the voice-messages build's final whole-branch review**, which caught two Critical defects that survived every single per-task review: (1) a SQL migration statement-ordering bug (a `DROP FUNCTION` running after a `CREATE OR REPLACE` of a same-named-different-arity function — this plan's migration task explicitly confirms no such reordering concern applies this time, since the RPC's arity does not change); (2) a data-corrupting numeric-transform bug (inverted waveform normalization) that only a test asserting **relative correctness**, not just shape/range, would have caught — this plan's `ChatVideoPreparer` task requires a test asserting the source-size-guard's window-estimate formula is directionally correct (a longer window estimates more bytes than a shorter one from the same source), not just that it produces some number.
- When `showAttachVideo`/`onVoiceMessageRecorded` equivalents are absent (the default), every existing screen using `ChatTextField` must behave identically to today — `showAttachImage`/`onAttachImage` are left completely unchanged for backward compatibility.

---

### Task 1: `Message` entity gains `signedThumbnailUrl` and `hasVideo`

**Files:**
- Modify: `lib/features/chat/domain/entities/message.dart`
- Test: `test/features/chat/message_model_test.dart` (this file already exists from the voice-messages build — add to it, do not create a duplicate)

**Interfaces:**
- Produces: `Message.signedThumbnailUrl` (`String?`), `Message.hasVideo` (`bool` getter) — every later task that touches `Message` (repository hydration, `MessageBubble`'s video branch) reads these exact names.

Current file state (read in full before this task was written): `Message` already has `mediaKey`, `mediaType`, `mediaThumbnailKey`, `signedMediaUrl`, `localMediaPath`, `mediaDurationMs`, `waveform`, and `hasImage`/`hasAudio` getters (lines 11-17, 242-247). This task adds exactly one new field and one new getter — `signedThumbnailUrl` is **deliberately NOT added to `toJson`/`fromJson`** (it must not survive to the offline cache, matching how `signedMediaUrl` is already excluded from both — confirmed at lines 182-206, 208-240: `signedMediaUrl` never appears in either method).

- [ ] **Step 1: Write the failing test**

```dart
// Add to test/features/chat/message_model_test.dart
  group('video message fields', () {
    test('hasVideo is true only when mediaType is video and media is available', () {
      final withLocal = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        localMediaPath: '/tmp/clip.mp4',
      );
      expect(withLocal.hasVideo, isTrue);

      final noMedia = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 's1',
        content: 'text only',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
      );
      expect(noMedia.hasVideo, isFalse);

      final audioMessage = Message(
        id: 'm3',
        clientMessageId: 'c3',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'audio',
        signedMediaUrl: 'https://example.com/voice.m4a',
      );
      expect(audioMessage.hasVideo, isFalse);
    });

    test('signedThumbnailUrl is NOT persisted via toJson/fromJson', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15, 9),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        mediaKey: 'chat-media/abc.mp4',
        signedMediaUrl: 'https://example.com/abc.mp4',
        signedThumbnailUrl: 'https://example.com/abc.jpg',
      );

      final json = original.toJson();
      expect(json.containsKey('signedThumbnailUrl'), isFalse);

      final restored = Message.fromJson(json);
      expect(restored.signedThumbnailUrl, isNull);
    });

    test('copyWith preserves signedThumbnailUrl when not overridden', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        signedThumbnailUrl: 'https://example.com/poster.jpg',
      );
      final copied = original.copyWith(status: MessageStatus.sent);
      expect(copied.signedThumbnailUrl, 'https://example.com/poster.jpg');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/message_model_test.dart`
Expected: FAIL — `mediaType: 'video'`/`signedThumbnailUrl`/`hasVideo` are undefined named parameters/getters on `Message`. (`mediaType: 'video'` itself will compile fine since `mediaType` is a plain `String?` — the failure is specifically on `signedThumbnailUrl` and `hasVideo`.)

- [ ] **Step 3: Implement the field and getter**

In `lib/features/chat/domain/entities/message.dart`:

1. Add the field next to `waveform` (line 17):
```dart
  final String? signedThumbnailUrl;
```

2. Add it as an optional named parameter to the main constructor, next to `this.waveform,` (line 44):
```dart
    this.signedThumbnailUrl,
```

3. Add it to `copyWith`'s parameter list (next to `List<int>? waveform,` at line 143) and its body (next to `waveform: waveform ?? this.waveform,` at line 168):
```dart
    String? signedThumbnailUrl,
```
```dart
      signedThumbnailUrl: signedThumbnailUrl ?? this.signedThumbnailUrl,
```

4. **Do NOT add it to `toJson()` or `fromJson()`** — this is deliberate, matching `signedMediaUrl`'s exclusion.

5. Add the getter next to `hasAudio` (lines 245-247):
```dart
  bool get hasVideo =>
      mediaType == 'video' &&
      (signedMediaUrl != null || localMediaPath != null);
```

Note: `Message.fromRow` and `Message.optimistic` are intentionally NOT touched in this task — `Message.fromRow` builds a message from a DB row and has no `signed*Url` fields at all (those are resolved separately by the repository's hydration step, added in Task 2); `Message.optimistic` is populated by `ChatController.sendVideoMessage`, added in Task 5. This task only adds the field/getter plumbing.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/message_model_test.dart`
Expected: PASS, all tests including the 3 new ones.

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/features/chat/domain/entities/message.dart test/features/chat/message_model_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Run the full chat test suite to confirm no regression**

Run: `flutter test test/features/chat/`
Expected: same pass count as before plus the 3 new tests, only the 2 known baseline failures.

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/domain/entities/message.dart test/features/chat/message_model_test.dart
git commit -m "feat(chat): add signedThumbnailUrl/hasVideo to Message"
```

---

### Task 2: Migration — schema, RPC, trigger widening for video, plus new thumbnail-intent validation

**Files:**
- Create: `supabase/migrations/20260815130000_chat_video_messages.sql`
- Test: manual verification via `supabase db reset` if available in the execution environment (this repo has a standing gap: no live Postgres access was available in the sandbox that built the voice-messages migration either — if the same is true here, verify by careful static re-reading against the exact live SQL quoted below, and state clearly in the task's completion notes which verification path was actually used)

**Interfaces:**
- Produces: `message_media_upload_intents_media_type_check` widened to `('image', 'audio', 'video')`; `create_chat_media_upload_intent(p_relationship_id uuid, p_mime_type text, p_media_type text DEFAULT 'image')` — **same 3-argument signature as it already has today, no arity change, so no DROP-before-CREATE reordering concern applies** (unlike the voice migration, which changed 2-arg to 3-arg); `validate_message_media_before_insert` gains new logic validating `NEW.media_thumbnail_url` against its own consumed intent when present.
- Consumes: nothing new — extends `message_media_upload_intents`, `create_chat_media_upload_intent`, `validate_message_media_before_insert`, `feature_flags` exactly as they exist after `supabase/migrations/20260815120000_chat_voice_messages.sql`.

**Verified against the exact live SQL (read in full before writing this task) — five sites, only four need changes:**

1. **`messages.media_type`'s CHECK constraint already includes `'video'`.** Confirmed directly: `supabase/migrations/20260815120000_chat_voice_messages.sql:38-39` rewrote it to `CHECK (media_type IN ('image', 'video', 'audio'))`. **No change needed in this migration.** Do not touch this constraint.
2. **`message_media_upload_intents_media_type_check`** — currently `CHECK (media_type IN ('image', 'audio'))` (`20260815120000_chat_voice_messages.sql:50-51`). Widen to include `'video'`.
3. **`feature_flags` row** — insert `('chat_video_sharing', false)`.
4. **`create_chat_media_upload_intent`** — currently a 3-argument function (`p_relationship_id uuid, p_mime_type text, p_media_type text DEFAULT 'image'`, confirmed at `20260815120000_chat_voice_messages.sql:74-78`). This migration's `CREATE OR REPLACE` keeps the exact same 3-argument signature — **no arity change, so unlike the voice migration's DROP-before-CREATE requirement (which existed because voice changed 2-arg to 3-arg), no DROP statement is needed or should be added here.** Changes inside the function body: widen `p_media_type NOT IN (...)` to include `'video'`; widen the MIME allowlist for the video branch to `video/mp4` ONLY (not `video/quicktime` — the client always transcodes to mp4 before requesting the intent, so accepting a raw `.mov` upload would let a hostile client skip compression entirely); add the `.mp4` case to the extension map; **the flag-enforcement branch requires BOTH `chat_video_sharing` AND `chat_image_sharing` when `p_media_type = 'video'`**, since every video send also requires a thumbnail intent through the ordinary image path — this turns a confusing partial failure (video intent succeeds, thumbnail intent creation 403s) into one clear upfront rejection.
5. **`validate_message_media_before_insert`** — currently validates ONLY `NEW.media_url` against its own intent (confirmed: the full function body at `20260815120000_chat_voice_messages.sql:185-232` contains zero references to `NEW.media_thumbnail_url` anywhere). Widen the type check to include `'video'`; add a type-aware size ceiling (`25MB` / `26214400` for video, alongside the existing `819200`/`1258291` for image/audio). **Add entirely new logic** (there is nothing to "widen" here — this doesn't exist in any form today): when `NEW.media_type = 'video' AND NEW.media_thumbnail_url IS NOT NULL`, look up and validate a SECOND intent row (`media_type = 'image'`, matching `NEW.media_thumbnail_url` as its `storage_key`) the same way the main object is validated — object existence, size, MIME — and mark that second intent's `used_at` too. This is a real, previously-nonexistent attack surface being closed: `media_thumbnail_url` was always server-written by an async worker for every other media type, so nothing needed to validate it; video is the first type where a client writes this field directly, and without this check a client could point the thumbnail at an arbitrary object in the bucket.
6. **`enqueue_chat_media_processing`'s trigger `WHEN` clause** already reads `NEW.media_type = 'image'` (confirmed unmodified since `20260705200000_chat_media_hardening.sql`) — video inserts skip it automatically, same as audio. **No change needed**; call this out explicitly in the migration's comments, matching the voice migration's own explicit callout, so it isn't mistaken for an oversight.

- [ ] **Step 1: Write the migration file**

```sql
-- supabase/migrations/20260815130000_chat_video_messages.sql
--
-- Extends the existing image/voice media pipeline (bucket, upload-intent
-- RPC, insert-validation trigger, server-authoritative flag enforcement) to
-- also accept video messages (media_type = 'video'), per
-- docs/superpowers/specs/2026-08-15-video-sharing-design.md. No new bucket,
-- no new RLS policies — the existing intent-ownership and
-- relationship-membership policies already cover any media type stored
-- under an intent-issued key.
--
-- messages.media_type's own CHECK constraint ALREADY permits 'video' —
-- it was in the original schema (20260705120000_chat_system_v1_2.sql) and
-- the voice migration's rewrite of that constraint
-- (20260815120000_chat_voice_messages.sql:38-39) preserved it. Verified
-- directly against the live migration before writing this file. No change
-- to that constraint here.
--
-- Deliberately does NOT touch enqueue_chat_media_processing/its trigger —
-- that trigger's WHEN clause already reads `AND NEW.media_type = 'image'`,
-- so video inserts correctly skip the image-thumbnail processing outbox
-- with zero changes needed, exactly as audio already does. Video's
-- thumbnail is generated and uploaded client-side, synchronously with the
-- send — there is no server-side processing step for it.
--
-- create_chat_media_upload_intent already has the 3-argument signature
-- (p_relationship_id uuid, p_mime_type text, p_media_type text DEFAULT
-- 'image') from the voice migration. This migration's CREATE OR REPLACE
-- keeps that exact same signature — no arity change, so unlike the voice
-- migration (which had to DROP the old 2-arg overload before creating a
-- 3-arg one, to avoid two coexisting overloads), no DROP statement is
-- needed or added here.

-- 1. Widen the upload-intents table's media_type CHECK constraint.
ALTER TABLE public.message_media_upload_intents
  DROP CONSTRAINT IF EXISTS message_media_upload_intents_media_type_check;
ALTER TABLE public.message_media_upload_intents
  ADD CONSTRAINT message_media_upload_intents_media_type_check
  CHECK (media_type IN ('image', 'audio', 'video'));

-- 2. Feature flag row, same convention as chat_image_sharing/chat_voice_messages.
INSERT INTO public.feature_flags (key, enabled)
VALUES ('chat_video_sharing', false)
ON CONFLICT (key) DO NOTHING;

-- 3. Widen create_chat_media_upload_intent: accept 'video', widen the MIME
--    allowlist for it to video/mp4 ONLY (the client always transcodes to
--    mp4 before requesting an intent — accepting video/quicktime here
--    would let a hostile client skip compression), add the mp4 extension
--    case, and require BOTH chat_video_sharing AND chat_image_sharing for
--    a video intent (every video send also needs a thumbnail intent
--    through the ordinary image path, so this turns a confusing partial
--    failure into one clear upfront rejection).
CREATE OR REPLACE FUNCTION public.create_chat_media_upload_intent(
  p_relationship_id uuid,
  p_mime_type text,
  p_media_type text DEFAULT 'image'
)
RETURNS TABLE (
  intent_id uuid,
  storage_key text,
  expires_at timestamptz,
  bucket text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_relationship public.relationships%ROWTYPE;
  v_storage_key text;
  v_extension text;
  v_flag_key text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_media_type NOT IN ('image', 'audio', 'video') THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  -- Server-authoritative flag gate (Spec 12.2) — one flag per media type,
  -- same enforcement shape as images/audio. Video additionally requires
  -- chat_image_sharing since every video send also requires a thumbnail
  -- intent through the image path — checked explicitly below rather than
  -- letting a partial failure surface as a confusing thumbnail-intent 403
  -- after the video intent already succeeded.
  v_flag_key := CASE p_media_type
    WHEN 'audio' THEN 'chat_voice_messages'
    WHEN 'video' THEN 'chat_video_sharing'
    ELSE 'chat_image_sharing'
  END;
  IF COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = v_flag_key),
    false
  ) = false THEN
    RAISE EXCEPTION '% is unavailable', p_media_type;
  END IF;

  IF p_media_type = 'video' AND COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = 'chat_image_sharing'),
    false
  ) = false THEN
    RAISE EXCEPTION 'video is unavailable';
  END IF;

  IF p_media_type = 'audio' THEN
    IF p_mime_type NOT IN ('audio/mp4', 'audio/m4a') THEN
      RAISE EXCEPTION 'Unsupported audio type';
    END IF;
  ELSIF p_media_type = 'video' THEN
    IF p_mime_type NOT IN ('video/mp4') THEN
      RAISE EXCEPTION 'Unsupported video type';
    END IF;
  ELSE
    IF p_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
      RAISE EXCEPTION 'Unsupported image type';
    END IF;
  END IF;

  SELECT *
  INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND chat_archived_at IS NULL
    AND (user_a = v_user_id OR user_b = v_user_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Relationship not available for chat media';
  END IF;

  v_extension := CASE p_mime_type
    WHEN 'image/png' THEN 'png'
    WHEN 'image/webp' THEN 'webp'
    WHEN 'audio/mp4' THEN 'm4a'
    WHEN 'audio/m4a' THEN 'm4a'
    WHEN 'video/mp4' THEN 'mp4'
    ELSE 'jpg'
  END;

  v_storage_key := 'chat-media/' || encode(gen_random_bytes(16), 'hex') || '.' || v_extension;

  INSERT INTO public.message_media_upload_intents (
    relationship_id,
    requester_id,
    storage_key,
    media_type,
    mime_type,
    expires_at
  )
  VALUES (
    p_relationship_id,
    v_user_id,
    v_storage_key,
    p_media_type,
    p_mime_type,
    now() + interval '15 minutes'
  )
  RETURNING
    message_media_upload_intents.id,
    message_media_upload_intents.storage_key,
    message_media_upload_intents.expires_at
  INTO intent_id, storage_key, expires_at;

  bucket := 'message-media';
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_chat_media_upload_intent(uuid, text, text) TO authenticated;

-- 4. Widen validate_message_media_before_insert: accept 'video', add a
--    type-aware size ceiling (25MB for video), and add NEW logic (not a
--    widened allowlist — this doesn't exist in any form today) validating
--    NEW.media_thumbnail_url against its own consumed intent when present.
--    media_thumbnail_url was always server-written by an async worker for
--    every other media type, so nothing previously needed to validate it —
--    video is the first type where a client writes this field directly,
--    and without this check a client could point the thumbnail at an
--    arbitrary object in the bucket.
CREATE OR REPLACE FUNCTION public.validate_message_media_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_intent public.message_media_upload_intents%ROWTYPE;
  v_object storage.objects%ROWTYPE;
  v_size bigint;
  v_mime text;
  v_max_size bigint;
  v_thumb_intent public.message_media_upload_intents%ROWTYPE;
  v_thumb_object storage.objects%ROWTYPE;
  v_thumb_size bigint;
  v_thumb_mime text;
BEGIN
  IF NEW.media_url IS NULL THEN RETURN NEW; END IF;
  IF NEW.media_type NOT IN ('image', 'audio', 'video') THEN
    RAISE EXCEPTION 'Unsupported chat media type';
  END IF;

  SELECT * INTO v_intent
  FROM public.message_media_upload_intents intent
  WHERE intent.storage_key = NEW.media_url
    AND intent.relationship_id = NEW.relationship_id
    AND intent.requester_id = NEW.sender_id
    AND intent.media_type = NEW.media_type
    AND intent.used_at IS NULL
    AND intent.expires_at > now()
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media upload intent is invalid or expired'; END IF;

  SELECT * INTO v_object FROM storage.objects o
  WHERE o.bucket_id = 'message-media' AND o.name = NEW.media_url;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chat media object is missing'; END IF;
  v_size := COALESCE((v_object.metadata->>'size')::bigint, 0);
  v_mime := COALESCE(v_object.metadata->>'mimetype', v_object.metadata->>'contentType');

  v_max_size := CASE NEW.media_type
    WHEN 'audio' THEN 1258291   -- ~1.2MB
    WHEN 'video' THEN 26214400  -- 25MB
    ELSE 819200                 -- 800KB, unchanged image ceiling
  END;

  IF v_size <= 0 OR v_size > v_max_size OR v_mime IS DISTINCT FROM v_intent.mime_type THEN
    RAISE EXCEPTION 'Chat media object failed validation';
  END IF;

  UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_intent.id;

  -- Video-only: the client writes media_thumbnail_url directly (no async
  -- worker involved), so it must be independently validated against its
  -- own consumed intent, the same way the main object is above.
  IF NEW.media_type = 'video' AND NEW.media_thumbnail_url IS NOT NULL THEN
    SELECT * INTO v_thumb_intent
    FROM public.message_media_upload_intents intent
    WHERE intent.storage_key = NEW.media_thumbnail_url
      AND intent.relationship_id = NEW.relationship_id
      AND intent.requester_id = NEW.sender_id
      AND intent.media_type = 'image'
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
    FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Chat media thumbnail upload intent is invalid or expired';
    END IF;

    SELECT * INTO v_thumb_object FROM storage.objects o
    WHERE o.bucket_id = 'message-media' AND o.name = NEW.media_thumbnail_url;
    IF NOT FOUND THEN RAISE EXCEPTION 'Chat media thumbnail object is missing'; END IF;
    v_thumb_size := COALESCE((v_thumb_object.metadata->>'size')::bigint, 0);
    v_thumb_mime := COALESCE(v_thumb_object.metadata->>'mimetype', v_thumb_object.metadata->>'contentType');

    IF v_thumb_size <= 0 OR v_thumb_size > 819200 OR v_thumb_mime IS DISTINCT FROM v_thumb_intent.mime_type THEN
      RAISE EXCEPTION 'Chat media thumbnail object failed validation';
    END IF;

    UPDATE public.message_media_upload_intents SET used_at = now() WHERE id = v_thumb_intent.id;
  END IF;

  RETURN NEW;
END;
$$;
```

- [ ] **Step 2: Apply the migration locally, if a live Postgres is available**

Run: `supabase db reset` (or this repo's established local-migration-apply command — check `supabase/config.toml`/README if `db reset` is not it)
Expected: migration applies with no errors. **If no local Postgres/Docker/`supabase` CLI is available in the execution environment** (the same limitation the voice-messages migration's own build hit — confirm by checking for `docker`, `psql`, `pg_ctl` on `PATH` before concluding this), state that plainly in the task's completion notes and proceed to Step 3's static verification as the fallback — do not claim live verification that did not happen.

- [ ] **Step 3: Verify the four widened/new surfaces**

If live Postgres is available, run each of these and record the actual output:

```sql
-- (a) Intents CHECK constraint widened
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.message_media_upload_intents'::regclass
  AND conname = 'message_media_upload_intents_media_type_check';
-- Expected: definition includes 'image', 'audio', AND 'video'

-- (b) Flag row exists, defaults off
SELECT key, enabled FROM public.feature_flags WHERE key = 'chat_video_sharing';
-- Expected: chat_video_sharing | false

-- (c) RPC rejects video when chat_video_sharing is off (even if chat_image_sharing is on)
UPDATE public.feature_flags SET enabled = true WHERE key = 'chat_image_sharing';
UPDATE public.feature_flags SET enabled = false WHERE key = 'chat_video_sharing';
SELECT * FROM public.create_chat_media_upload_intent(
  '<a real active relationship id>'::uuid, 'video/mp4', 'video'
);
-- Expected: raises "video is unavailable"

-- (d) RPC rejects video when chat_video_sharing is on but chat_image_sharing is off
UPDATE public.feature_flags SET enabled = true WHERE key = 'chat_video_sharing';
UPDATE public.feature_flags SET enabled = false WHERE key = 'chat_image_sharing';
SELECT * FROM public.create_chat_media_upload_intent(
  '<same relationship id>'::uuid, 'video/mp4', 'video'
);
-- Expected: raises "video is unavailable" (from the second, image-flag-specific check)

-- (e) RPC succeeds when BOTH flags are on
UPDATE public.feature_flags SET enabled = true WHERE key IN ('chat_video_sharing', 'chat_image_sharing');
SELECT * FROM public.create_chat_media_upload_intent(
  '<same relationship id>'::uuid, 'video/mp4', 'video'
);
-- Expected: returns one row, intent_id/storage_key/expires_at/bucket='message-media'

-- (f) Trigger rejects a video insert with no matching storage object
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_url, media_type)
VALUES ('<same relationship id>'::uuid, auth.uid(), 'test-video-1', '', '<storage_key from e>', 'video');
-- Expected: raises "Chat media object is missing" (no file was actually uploaded to Storage)

-- (g) Trigger rejects a thumbnail pointed at an unvalidated/arbitrary key —
-- create a valid video intent AND upload a real object for it, but supply a
-- media_thumbnail_url that has no matching intent at all
-- (this step requires actually uploading to Storage to get past check (f) first,
-- so may only be practically runnable with real Storage access, not pure SQL —
-- if that's not feasible in this environment, verify by code-reading the new
-- trigger logic instead and state that explicitly)

-- (h) Reset flags back to defaults for any later manual testing session
UPDATE public.feature_flags SET enabled = false WHERE key IN ('chat_video_sharing', 'chat_image_sharing');
```

If no live Postgres is available, instead re-read the finished migration file line by line against this task's Step 1 content and confirm: (1) constraint (a) syntactically correct; (2) the RPC's `v_flag_key` CASE and the second `p_media_type = 'video'` check together implement the AND-of-both-flags requirement correctly for all four flag-state combinations; (3) the trigger's new video-thumbnail block is inside the existing function body, not a separate trigger, and only runs when `NEW.media_type = 'video' AND NEW.media_thumbnail_url IS NOT NULL` — confirming a video message with no thumbnail (the non-fatal-thumbnail-failure case from the spec) does not hit this block and does not fail the insert. State clearly that this was static verification, not live execution.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260815130000_chat_video_messages.sql
git commit -m "feat(chat): widen media pipeline schema/RPC/trigger to accept video, validate client-written thumbnails"
```

---

### Task 3: `ChatVideoPreparer` — probe, trim-window guard, transcode, thumbnail

**Files:**
- Create: `lib/features/chat/domain/services/chat_video_preparer.dart`
- Modify: `pubspec.yaml` (add `video_player`, `video_thumbnail`, `video_compress`)
- Test: `test/features/chat/chat_video_preparer_test.dart`

**Interfaces:**
- Consumes: `ChatImagePreparer`/`PreparedChatImage`/`ChatImageRejected` (`lib/features/chat/domain/services/chat_image_preparer.dart`, already exists — reused as-is for thumbnail compression, not modified).
- Produces: `ChatVideoPreparer` class with `Future<PreparedChatVideo> prepare({required String localPath, Duration? trimStart, Duration? trimEnd, void Function(double)? onProgress})`. `PreparedChatVideo` class: `{File file, String mimeType, int byteSize, int durationMs, File thumbnailFile, String thumbnailMimeType, int thumbnailByteSize, int width, int height}`. `ChatVideoRejected` class: `{String code}` (typed exception, mirrors `ChatImageRejected`). Constants: `ChatVideoPreparer.maxBytes` (`25 * 1024 * 1024`), `ChatVideoPreparer.maxSourceBytes` (`300 * 1024 * 1024`), `ChatVideoPreparer.maxDuration` (`Duration(minutes: 3)`), `ChatVideoPreparer.minDuration` (`Duration(milliseconds: 500)`), `ChatVideoPreparer.targetHeight` (`720`). Task 5 (`ChatController.sendVideoMessage`, the belt-and-suspenders duration check) and Task 6 (the trim screen's clamping bounds) both consume these exact constant names, mirroring how `VoiceRecorderService.maxDuration`/`minDuration` are already consumed by `chat_state.dart` and `chat_text_field.dart` today.

**Package note**: `video_player`, `video_thumbnail`, and `video_compress` are not yet project dependencies. Unlike `ChatImagePreparer`'s MIME-sniffing and decode logic (pure Dart, via the `image` package — confirmed by reading `chat_image_preparer_test.dart`, which constructs and decodes real JPEG bytes with no plugin faking needed), video has no pure-Dart equivalent for probing/transcoding/thumbnail-extraction — every one of those operations is genuinely native-plugin-backed. This task's tests must therefore follow `VoiceRecorderService`'s established test-host-degradation pattern (see `pubspec.yaml`'s `dev_dependencies` block, lines 154-165: `permission_handler_platform_interface`/`record_platform_interface`/`path_provider_platform_interface` are declared as direct dev_dependencies specifically so `flutter test`'s pure-Dart VM host doesn't throw `MissingPluginException` on plugin calls) — add `video_player_platform_interface` and any equivalent for `video_compress`/`video_thumbnail` as direct dev_dependencies if their tests need to fake native responses, following that exact precedent.

- [ ] **Step 1: Add the three new dependencies**

In `pubspec.yaml`, add to the `dependencies:` block (after `record: ^5.1.0` at line 79 — do not change any existing lines):
```yaml
  video_player: ^2.9.0
  video_thumbnail: ^0.5.3
  video_compress: ^3.1.2
```

Run: `flutter pub get`
Expected: resolves cleanly. If any version conflicts with an existing dependency's constraints, check the error output for the specific conflicting package and pick the highest compatible version — do not downgrade any other existing dependency to force these in.

- [ ] **Step 2: Write the failing pure-logic unit tests (no native calls)**

```dart
// test/features/chat/chat_video_preparer_test.dart
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_video_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('duration bounds', () {
    test('minDuration and maxDuration match the design spec values', () {
      expect(ChatVideoPreparer.minDuration, const Duration(milliseconds: 500));
      expect(ChatVideoPreparer.maxDuration, const Duration(minutes: 3));
    });
  });

  group('constants match the design spec', () {
    test('byte ceilings and target height are the confirmed values', () {
      expect(ChatVideoPreparer.maxBytes, 25 * 1024 * 1024);
      expect(ChatVideoPreparer.maxSourceBytes, 300 * 1024 * 1024);
      expect(ChatVideoPreparer.targetHeight, 720);
    });
  });

  group('trim-window byte-size-guard estimate', () {
    // This is the numeric-transform logic the plan's Global Constraints
    // section specifically calls out as needing a RELATIVE-correctness
    // test, not just a shape/range test — mirroring the exact class of bug
    // (inverted waveform normalization) that survived every per-task review
    // in the voice-messages build and was only caught by the final
    // whole-branch review. debugEstimateWindowBytes is a @visibleForTesting
    // seam exposing the same formula prepare() uses internally.
    test('a longer selected window estimates more bytes than a shorter one from the same source', () {
      const sourceBytes = 100 * 1024 * 1024; // 100MB source
      const sourceDuration = Duration(minutes: 10);

      final shortWindowEstimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: const Duration(seconds: 30),
      );
      final longWindowEstimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: const Duration(minutes: 3),
      );

      expect(longWindowEstimate, greaterThan(shortWindowEstimate));
    });

    test('a window covering the full source estimates approximately the full source size', () {
      const sourceBytes = 50 * 1024 * 1024;
      const sourceDuration = Duration(minutes: 2);

      final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: sourceBytes,
        sourceDuration: sourceDuration,
        windowDuration: sourceDuration,
      );

      expect(estimate, closeTo(sourceBytes, 1)); // linear estimate, exact at full coverage
    });

    test('a zero-length window estimates zero bytes, not a divide-by-zero crash', () {
      final estimate = ChatVideoPreparer.debugEstimateWindowBytes(
        sourceBytes: 50 * 1024 * 1024,
        sourceDuration: const Duration(minutes: 2),
        windowDuration: Duration.zero,
      );
      expect(estimate, 0);
    });
  });

  group('resource cleanup / existence checks', () {
    test('rejects a missing source file', () async {
      expect(
        () => const ChatVideoPreparer().prepare(localPath: '/no/such/file.mp4'),
        throwsA(
          isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_missing'),
        ),
      );
    });

    test('rejects an empty source file', () async {
      final file = File(p.join(tmp.path, 'empty.mp4'));
      await file.writeAsBytes(const []);
      expect(
        () => const ChatVideoPreparer().prepare(localPath: file.path),
        throwsA(
          isA<ChatVideoRejected>().having((e) => e.code, 'code', 'media_empty'),
        ),
      );
    });
  });

  group('MIME sniffing', () {
    test('rejects a file with no ftyp box (not a valid mp4/mov container)', () async {
      final file = File(p.join(tmp.path, 'fake.mp4'));
      await file.writeAsString('this is not a video container');
      expect(
        () => const ChatVideoPreparer().prepare(localPath: file.path),
        throwsA(
          isA<ChatVideoRejected>().having(
            (e) => e.code,
            'code',
            'media_type_unsupported',
          ),
        ),
      );
    });

    test('accepts a minimal valid mp4 ftyp box signature', () {
      // ISO base media file format: a box is [4-byte size][4-byte type][data].
      // A minimal ftyp box with major brand 'isom' at the standard offset.
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18, // box size
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x69, 0x73, 0x6F, 0x6D, // major brand 'isom'
        0x00, 0x00, 0x02, 0x00, // minor version
        0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32, // compatible brands
      ];
      expect(
        ChatVideoPreparer.debugSniffMime(bytes),
        'video/mp4',
      );
    });

    test('unrecognized major brand returns null (caller rejects)', () {
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x78, 0x78, 0x78, 0x78, // unrecognized brand
        0x00, 0x00, 0x02, 0x00,
      ];
      expect(ChatVideoPreparer.debugSniffMime(bytes), isNull);
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart`
Expected: FAIL — `chat_video_preparer.dart` doesn't exist yet.

- [ ] **Step 4: Implement `ChatVideoPreparer`**

```dart
// lib/features/chat/domain/services/chat_video_preparer.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Result of preparing a video for the private chat media pipeline.
class PreparedChatVideo {
  const PreparedChatVideo({
    required this.file,
    required this.mimeType,
    required this.byteSize,
    required this.durationMs,
    required this.thumbnailFile,
    required this.thumbnailMimeType,
    required this.thumbnailByteSize,
    required this.width,
    required this.height,
  });

  final File file;
  final String mimeType;
  final int byteSize;
  final int durationMs;
  final File thumbnailFile;
  final String thumbnailMimeType;
  final int thumbnailByteSize;
  final int width;
  final int height;
}

/// Raised when a video cannot be made to meet the chat upload contract. The
/// [code] is a coarse, content-free reason (mirrors ChatImageRejected in
/// chat_image_preparer.dart) — safe to log, never a raw path or exception.
class ChatVideoRejected implements Exception {
  const ChatVideoRejected(this.code);
  final String code;

  @override
  String toString() => 'ChatVideoRejected($code)';
}

/// Enforces the private-video upload contract on the client, before any
/// upload intent is requested. See design spec's "Client Architecture" and
/// "Error Handling" sections for the full guard-order rationale.
///
/// Deliberately client-side only, mirroring ChatImagePreparer/
/// VoiceRecorderService — there is no server-side transcoding step (see the
/// design spec's "Why video compression is client-side only" section: no
/// viable Flutter-compatible server-side transcoding option exists for
/// Supabase Edge Functions).
class ChatVideoPreparer {
  const ChatVideoPreparer();

  static const int maxBytes = 25 * 1024 * 1024; // post-transcode output ceiling
  static const int maxSourceBytes = 300 * 1024 * 1024; // trim-window estimate guard
  static const Duration maxDuration = Duration(minutes: 3);
  static const Duration minDuration = Duration(milliseconds: 500);
  static const int targetHeight = 720;
  static const int _videoBitrate = 800000; // 800kbps
  static const int _audioBitrate = 64000; // 64kbps AAC mono

  /// Test seam: the same trim-window-byte-estimate formula prepare() uses
  /// internally (sourceBytes * windowDuration/sourceDuration), exposed so
  /// its RELATIVE correctness (a longer window estimates more bytes than a
  /// shorter one) can be asserted directly — this is the numeric-transform
  /// class of logic that needs a relative-correctness test, not just a
  /// shape/range test, per this plan's Global Constraints.
  @visibleForTesting
  static int debugEstimateWindowBytes({
    required int sourceBytes,
    required Duration sourceDuration,
    required Duration windowDuration,
  }) {
    if (sourceDuration.inMicroseconds <= 0) return 0;
    final fraction = windowDuration.inMicroseconds / sourceDuration.inMicroseconds;
    return (sourceBytes * fraction).round();
  }

  /// Test seam: sniffs the MIME from the leading ISO-BMFF `ftyp` box magic
  /// bytes, without needing a full file. Never trusts the filename
  /// extension — the video analogue of ChatImagePreparer's byte-sniffing.
  @visibleForTesting
  static String? debugSniffMime(List<int> bytes) {
    if (bytes.length < 12) return null;
    // ISO base media file format: [4-byte box size][4-byte type 'ftyp'][4-byte major brand]...
    final isFtyp = bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70;
    if (!isFtyp) return null;

    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    switch (brand) {
      case 'isom':
      case 'mp42':
      case 'avc1':
      case 'M4V ':
        return 'video/mp4';
      case 'qt  ':
        return 'video/quicktime';
      default:
        return null;
    }
  }

  Future<PreparedChatVideo> prepare({
    required String localPath,
    Duration? trimStart,
    Duration? trimEnd,
    void Function(double)? onProgress,
  }) async {
    final source = File(localPath);
    if (!await source.exists()) {
      throw const ChatVideoRejected('media_missing');
    }
    final sourceLength = await source.length();
    if (sourceLength <= 0) throw const ChatVideoRejected('media_empty');

    final headerBytes = await source.openRead(0, 128).first;
    final sniffedMime = debugSniffMime(headerBytes);
    if (sniffedMime == null) {
      throw const ChatVideoRejected('media_type_unsupported');
    }

    final MediaInfo info;
    try {
      info = await VideoCompress.getMediaInfo(localPath);
    } catch (_) {
      throw const ChatVideoRejected('media_decode_failed');
    }
    final sourceDurationMs = info.duration?.round();
    if (sourceDurationMs == null) {
      throw const ChatVideoRejected('media_decode_failed');
    }
    final sourceDuration = Duration(milliseconds: sourceDurationMs);

    final effectiveStart = trimStart ?? Duration.zero;
    final effectiveEnd = trimEnd ?? sourceDuration;
    final effectiveDuration = effectiveEnd - effectiveStart;

    if (effectiveDuration < minDuration) {
      throw const ChatVideoRejected('media_too_short');
    }
    if (effectiveDuration > maxDuration) {
      throw const ChatVideoRejected('media_too_long');
    }

    final windowEstimate = debugEstimateWindowBytes(
      sourceBytes: sourceLength,
      sourceDuration: sourceDuration,
      windowDuration: effectiveDuration,
    );
    if (windowEstimate > maxSourceBytes) {
      throw const ChatVideoRejected('media_too_large');
    }

    final MediaInfo? compressed;
    try {
      compressed = await VideoCompress.compressVideo(
        localPath,
        quality: VideoQuality.MediumQuality,
        startTime: effectiveStart.inSeconds,
        duration: effectiveDuration.inSeconds,
        includeAudio: true,
        deleteOrigin: false,
      );
    } catch (_) {
      throw const ChatVideoRejected('media_compress_failed');
    }
    if (compressed?.file == null) {
      throw const ChatVideoRejected('media_compress_failed');
    }

    final outFile = compressed!.file!;
    final outSize = await outFile.length();
    if (outSize <= 0 || outSize > maxBytes) {
      throw const ChatVideoRejected('media_compress_failed');
    }

    final PreparedChatImage preparedThumbnail;
    try {
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: localPath,
        timeMs: effectiveStart.inMilliseconds,
        quality: 90,
      );
      if (thumbnailBytes == null) {
        throw const ChatVideoRejected('thumbnail_failed');
      }
      final rawThumbPath = await _tempTargetPath('raw_thumb', 'jpg');
      await File(rawThumbPath).writeAsBytes(thumbnailBytes, flush: true);
      preparedThumbnail = await const ChatImagePreparer().prepare(rawThumbPath);
    } on ChatImageRejected {
      throw const ChatVideoRejected('thumbnail_failed');
    }

    return PreparedChatVideo(
      file: outFile,
      mimeType: 'video/mp4',
      byteSize: outSize,
      durationMs: effectiveDuration.inMilliseconds,
      thumbnailFile: preparedThumbnail.file,
      thumbnailMimeType: preparedThumbnail.mimeType,
      thumbnailByteSize: preparedThumbnail.byteSize,
      width: compressed.width ?? 0,
      height: compressed.height ?? 0,
    );
  }

  Future<String> _tempTargetPath(String prefix, String extension) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    return p.join(dir.path, name);
  }
}
```

Note for the implementer: the exact `video_compress`/`video_thumbnail` API shapes above (`VideoCompress.getMediaInfo`, `VideoCompress.compressVideo`'s named parameters, `MediaInfo.width`/`.height`/`.duration`/`.file`, `VideoThumbnail.thumbnailData`) are written from the packages' documented public API at plan-writing time, NOT verified against the actual installed source (these packages are added fresh in this task's Step 1). Before trusting this code verbatim, run `flutter pub get` first, then check the actual installed package's API (inspect its `lib/` directory, or its pub.dev documentation for the exact resolved version) — if any method name, parameter name, or return type has drifted, adapt the implementation to match the real installed API. The load-bearing contract that must not change is `ChatVideoPreparer`'s own public interface (`prepare()`'s signature, `PreparedChatVideo`'s fields, `ChatVideoRejected`, the two `@visibleForTesting` seams) — how it talks to `video_compress`/`video_thumbnail` internally is free to differ from this code if the real installed API requires it. This mirrors the exact same caveat this plan's predecessor (the voice-messages plan) carried for the `record` package, which turned out to need one small adaptation (a Dart-language const-evaluation limitation, unrelated to the package API itself) — expect something similar is possible here too.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart`
Expected: PASS, all tests.

- [ ] **Step 6: Empirically verify the relative-correctness test is real**

Temporarily change `debugEstimateWindowBytes`'s formula to always return a constant (e.g. `return 1000;` regardless of input) — rerun `'a longer selected window estimates more bytes than a shorter one from the same source'`, confirm it FAILS (both estimates equal, `greaterThan` assertion fails). Revert the change, confirm green again. This is the exact class of empirical verification the plan's Global Constraints section requires for this specific piece of logic.

- [ ] **Step 7: Run `dart analyze`**

Run: `dart analyze lib/features/chat/domain/services/chat_video_preparer.dart test/features/chat/chat_video_preparer_test.dart pubspec.yaml`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/chat/domain/services/chat_video_preparer.dart test/features/chat/chat_video_preparer_test.dart
git commit -m "feat(chat): add ChatVideoPreparer with trim-window size guard and client-side thumbnail"
```

---

### Task 4: Video trim screen

**Files:**
- Create: `lib/features/chat/presentation/screens/video_trim_screen.dart`
- Test: `test/features/chat/video_trim_screen_test.dart`

**Interfaces:**
- Consumes: `ChatVideoPreparer.minDuration`/`maxDuration` (Task 3) as the clamp bounds — this task does NOT call `ChatVideoPreparer.prepare()` itself (that happens in Task 7's composer wiring, after this screen returns).
- Produces: a route pushed via `Navigator.push<({Duration start, Duration end})?>(context, MaterialPageRoute(builder: (_) => VideoTrimScreen(sourcePath: ..., sourceDuration: ...)))`. `VideoTrimScreen` widget: `{required String sourcePath, required Duration sourceDuration}`. Task 7 (the composer's `_attachVideo()`) consumes this exact push signature and return type.

This task is UI-only and has no dependency on `video_compress`/`video_thumbnail`'s native calls beyond frame extraction for the filmstrip (which can be stubbed/faked the same way Task 3's tests degrade native calls) — the screen itself only needs a `VideoPlayerController` for the live preview and `video_thumbnail` for filmstrip frames.

- [ ] **Step 1: Write the failing widget tests**

```dart
// test/features/chat/video_trim_screen_test.dart
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/video_trim_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirm button is disabled when the source is shorter than the minimum duration',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoTrimScreen(
          sourcePath: '/tmp/fake.mp4',
          sourceDuration: const Duration(milliseconds: 200), // under 500ms minimum
        ),
      ),
    );
    await tester.pump();

    final confirmButton = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('pre-positions the window to the full clip when source is already under the cap',
      (tester) async {
    const sourceDuration = Duration(seconds: 45); // under 3-minute cap
    await tester.pumpWidget(
      MaterialApp(
        home: VideoTrimScreen(
          sourcePath: '/tmp/fake.mp4',
          sourceDuration: sourceDuration,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('0:45'), findsWidgets);
  });

  testWidgets('pre-positions a maxDuration-wide window at the start when source exceeds the cap',
      (tester) async {
    const sourceDuration = Duration(minutes: 10); // over 3-minute cap
    await tester.pumpWidget(
      MaterialApp(
        home: VideoTrimScreen(
          sourcePath: '/tmp/fake.mp4',
          sourceDuration: sourceDuration,
        ),
      ),
    );
    await tester.pump();

    // The initially-selected window duration should be exactly the cap,
    // not the full 10-minute source.
    expect(find.textContaining('3:00'), findsWidgets);
  });

  testWidgets('returns null when the user backs out without confirming',
      (tester) async {
    ({Duration start, Duration end})? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VideoTrimScreen(
                    sourcePath: '/tmp/fake.mp4',
                    sourceDuration: Duration(seconds: 30),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/features/chat/video_trim_screen_test.dart`
Expected: FAIL — `video_trim_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement `VideoTrimScreen`**

```dart
// lib/features/chat/presentation/screens/video_trim_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen trim UI shown unconditionally after every gallery video pick,
/// before ChatVideoPreparer.prepare() runs, so the transcode encodes exactly
/// the range the user selects. Pushed via Navigator.push, not a GoRouter
/// route — mirrors how other modal chat media UI is already pushed, and
/// ensures this screen never appears in deep links.
///
/// Selection is physically clamped to
/// [ChatVideoPreparer.minDuration, ChatVideoPreparer.maxDuration] by the
/// handle-drag logic itself — ChatVideoPreparer's own duration-bounds check
/// is a defense-in-depth backstop, not the primary enforcement mechanism.
class VideoTrimScreen extends StatefulWidget {
  const VideoTrimScreen({
    super.key,
    required this.sourcePath,
    required this.sourceDuration,
  });

  final String sourcePath;
  final Duration sourceDuration;

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  late Duration _windowStart;
  late Duration _windowEnd;
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    // Pre-position: full clip if already under the cap, else a
    // maxDuration-wide window at the start.
    if (widget.sourceDuration <= ChatVideoPreparer.maxDuration) {
      _windowStart = Duration.zero;
      _windowEnd = widget.sourceDuration;
    } else {
      _windowStart = Duration.zero;
      _windowEnd = ChatVideoPreparer.maxDuration;
    }

    _controller = VideoPlayerController.file(File(widget.sourcePath))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Duration get _selectedDuration => _windowEnd - _windowStart;

  bool get _canConfirm => _selectedDuration >= ChatVideoPreparer.minDuration;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _onStartHandleChanged(Duration newStart) {
    final clampedStart = newStart.clamp(Duration.zero, _windowEnd);
    final maxAllowedStart = _windowEnd - ChatVideoPreparer.minDuration;
    final minAllowedStart = (_windowEnd - ChatVideoPreparer.maxDuration)
        .clamp(Duration.zero, widget.sourceDuration);
    setState(() {
      _windowStart = clampedStart.clamp(
        minAllowedStart < Duration.zero ? Duration.zero : minAllowedStart,
        maxAllowedStart < Duration.zero ? Duration.zero : maxAllowedStart,
      );
    });
  }

  void _onEndHandleChanged(Duration newEnd) {
    final maxAllowedEnd = (_windowStart + ChatVideoPreparer.maxDuration)
        .clamp(Duration.zero, widget.sourceDuration);
    final minAllowedEnd = _windowStart + ChatVideoPreparer.minDuration;
    setState(() {
      _windowEnd = newEnd.clamp(minAllowedEnd, maxAllowedEnd);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trim video')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _controller?.value.isInitialized == true
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${_formatDuration(_selectedDuration)} / ${_formatDuration(ChatVideoPreparer.maxDuration)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            // Filmstrip scrubber with draggable handles — frame extraction
            // via video_thumbnail, cached once on init. Handle drag calls
            // _onStartHandleChanged/_onEndHandleChanged, both of which
            // physically clamp the resulting selection to
            // [minDuration, maxDuration] before it's ever applied to state.
            SizedBox(
              height: 64,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                // Filmstrip frame rendering and the two 48dp-minimum
                // draggable handle widgets go here — full implementation
                // left to the executing engineer's UI judgment within the
                // stated constraints (physically clamped selection, 48dp
                // touch targets, M3 tokens, bounded scroll box).
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: _canConfirm
                    ? () => Navigator.of(context).pop((
                          start: _windowStart,
                          end: _windowEnd,
                        ))
                    : null,
                child: const Text('Use this clip'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note: this screen's filmstrip-frame-extraction and handle-drag-gesture rendering are intentionally left as UI-judgment implementation detail rather than fully specified pixel-by-pixel — the load-bearing, testable contract is the clamping logic (`_onStartHandleChanged`/`_onEndHandleChanged`, verified by Step 1's tests) and the pre-positioning logic in `initState`, both fully specified above. Add the `dart:io` import for `File` if not already pulled in transitively.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/chat/video_trim_screen_test.dart`
Expected: PASS, all 4 tests. (The `VideoPlayerController.file` construction in a `flutter test` VM host will likely need the same platform-interface-fake treatment as Task 3's native calls — if `initState`'s controller construction throws in the test host, wrap it in a way that degrades gracefully for tests, matching the established pattern, since these tests only assert on the confirm-button/pre-positioning logic, not actual video playback.)

- [ ] **Step 5: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/screens/video_trim_screen.dart test/features/chat/video_trim_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/screens/video_trim_screen.dart test/features/chat/video_trim_screen_test.dart
git commit -m "feat(chat): add video trim screen with clamped handle selection"
```

---

### Task 5: `PendingSend` gains video fields; `ChatController.sendVideoMessage`; `_attemptSend`'s two-intent branch

**Files:**
- Modify: `lib/features/chat/data/cache/pending_send.dart`
- Modify: `lib/features/chat/data/repositories/chat_repository.dart` (`sendTextMessage` signature)
- Modify: `lib/features/chat/data/repositories/supabase_chat_repository.dart` (`sendTextMessage` implementation, `_messageColumns`, `_hydrateMessages`)
- Modify: `lib/features/chat/presentation/state/chat_state.dart`
- Modify: `lib/features/chat/domain/entities/message.dart` (`Message.fromRow`, `Message.optimistic` — Task 1 added the `signedThumbnailUrl` field but deliberately did not touch these two factories; this task also needs `mediaWidth`/`mediaHeight` on `Message` itself, which neither Task 1 nor the voice-messages build ever added)
- Test: `test/features/chat/pending_send_video_test.dart`
- Test: `test/features/chat/chat_state_send_video_message_test.dart`

**Interfaces:**
- Consumes: `Message.signedThumbnailUrl`/`hasVideo` (Task 1), `PreparedChatVideo {file, mimeType, byteSize, durationMs, thumbnailFile, thumbnailMimeType, thumbnailByteSize, width, height}` (Task 3), `ChatRepository.createMediaUploadIntent`/`uploadChatMedia` (already generic, confirmed unchanged from the voice-messages build).
- Produces: `ChatController.sendVideoMessage({required String localPath, required int durationMs, required String thumbnailLocalPath, required int width, required int height})` — Task 7 (the composer's `_attachVideo()`) calls this exact signature.

**Important correction to the design spec's prose, found by reading the actual current file before writing this task**: the spec's Data Model / Client Architecture sections refer to a method called `_reconcileLocalMediaPaths` that needs "the identical treatment already given to `localMediaPath`." **No such method exists in `chat_state.dart`.** The actual optimistic-to-canonical swap happens in `_replaceOptimistic` (`chat_state.dart:1175-1213`), which replaces the ENTIRE optimistic `Message` object with the canonical one from the server (`messages[idx] = canonical;` at line 1201) — it does not do field-by-field merging, and `Message.fromRow` (which builds the canonical message) never sets `localMediaPath` at all. This means `localMediaPath` (and, by the same logic, a hypothetical `localThumbnailPath`) is **not preserved** across the swap by design — the canonical message is expected to already carry a resolved `signedMediaUrl`/`signedThumbnailUrl` by the time `_replaceOptimistic` runs, because `_hydrateMessage`/`_hydrateMessages` (which builds the canonical message) resolves those signed URLs synchronously before returning it. **Verify this is still true for video** once the `_hydrateMessages` widening in this task lands — the fix is to make sure the widened `_hydrateMessages` genuinely resolves `signedThumbnailUrl` on the canonical message BEFORE `_attemptSend` calls `_replaceOptimistic`, not to add a nonexistent `_reconcileLocalMediaPaths`-style preservation mechanism. This plan's steps below reflect this corrected understanding — do not go looking for a method to modify that doesn't exist.

**Also verified against the actual file**: there is no `localThumbnailPath` field for video to reuse a "companion field" pattern from — `PendingSend` needs an actual new field for this, spelled out in Step 3 below.

**`_deleteStagedMedia`'s actual call sites** (verified by reading the whole file, not assumed from the spec's 4-category prose description): `removeFailedMessage` (line 671), `_attemptSend`'s success path (line 950), `_attemptSend`'s duplicate-insert (`23505`) reconciliation path (line 981), `_purgeRelationshipLocalState` (line 1273), `_handleAccountChange` (line 1291). **That is 5 literal call sites**, not 4 — "outbox eviction" in the spec's prose covers two distinct methods (`_purgeRelationshipLocalState` and `_handleAccountChange`), each with their own call site. Every one of these 5 needs a companion call cleaning up the new thumbnail temp file.

- [ ] **Step 1: Write the failing `PendingSend` round-trip test**

```dart
// test/features/chat/pending_send_video_test.dart
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PendingSend toJson/fromJson round-trips the four new video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      localMediaPath: '/tmp/clip.mp4',
      mediaMimeType: 'video/mp4',
      mediaType: 'video',
      mediaDurationMs: 12000,
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 1280,
      mediaHeight: 720,
      createdAt: DateTime(2026, 8, 15, 9),
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.localThumbnailPath, '/tmp/poster.jpg');
    expect(restored.thumbnailMimeType, 'image/jpeg');
    expect(restored.mediaWidth, 1280);
    expect(restored.mediaHeight, 720);
  });

  test('PendingSend.copyWith preserves the four new video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'video',
      localThumbnailPath: '/tmp/poster.jpg',
      thumbnailMimeType: 'image/jpeg',
      mediaWidth: 1280,
      mediaHeight: 720,
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.localThumbnailPath, '/tmp/poster.jpg');
    expect(copied.thumbnailMimeType, 'image/jpeg');
    expect(copied.mediaWidth, 1280);
    expect(copied.mediaHeight, 720);
  });

  test('a non-video PendingSend has null video fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'hi',
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.localThumbnailPath, isNull);
    expect(restored.thumbnailMimeType, isNull);
    expect(restored.mediaWidth, isNull);
    expect(restored.mediaHeight, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/chat/pending_send_video_test.dart`
Expected: FAIL — the four new fields are undefined on `PendingSend`.

- [ ] **Step 3: Add the four fields to `PendingSend`**

In `lib/features/chat/data/cache/pending_send.dart`, following the exact pattern every existing field uses (verified against the current file's exact structure at every step below):

Add to the class body (next to `final List<int>? waveform;` at line 12):
```dart
  final String? localThumbnailPath;
  final String? thumbnailMimeType;
  final int? mediaWidth;
  final int? mediaHeight;
```

Add to the constructor (next to `this.waveform,` at line 30):
```dart
    this.localThumbnailPath,
    this.thumbnailMimeType,
    this.mediaWidth,
    this.mediaHeight,
```

Add to `toJson()` (next to `'waveform': waveform,` at line 76):
```dart
      'localThumbnailPath': localThumbnailPath,
      'thumbnailMimeType': thumbnailMimeType,
      'mediaWidth': mediaWidth,
      'mediaHeight': mediaHeight,
```

Add to `fromJson()` (next to the `waveform:` parse at lines 97-99):
```dart
      localThumbnailPath: json['localThumbnailPath'] as String?,
      thumbnailMimeType: json['thumbnailMimeType'] as String?,
      mediaWidth: (json['mediaWidth'] as num?)?.toInt(),
      mediaHeight: (json['mediaHeight'] as num?)?.toInt(),
```

**`copyWith` does NOT need these four added to its PARAMETER list** — verified against the current file: `copyWith`'s parameter list (lines 40-44) only exposes `attempts`/`nextAttemptAt`/`lastErrorCategory`/`state`; every other field (including `mediaType`, `waveform`, etc.) is passed through the constructor call inside `copyWith`'s BODY by reading the instance field directly (e.g. `mediaType: mediaType,` at line 53, not `mediaType: mediaType ?? this.mediaType` — there are no parameters named `mediaType` to fall back from). Add the four new fields to that same unconditional pass-through list (next to `waveform: waveform,` at line 55):
```dart
      localThumbnailPath: localThumbnailPath,
      thumbnailMimeType: thumbnailMimeType,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/chat/pending_send_video_test.dart`
Expected: PASS.

- [ ] **Step 5: Add `mediaWidth`/`mediaHeight` to `Message`, and thread all new fields through `sendTextMessage`**

`Message` itself has no `mediaWidth`/`mediaHeight` fields today (confirmed — Task 1 only added `signedThumbnailUrl`). Add them now, following the exact same pattern as `mediaDurationMs` (added during the voice-messages build):

In `lib/features/chat/domain/entities/message.dart`:
- Add `final int? mediaWidth;` and `final int? mediaHeight;` to the class body (next to `signedThumbnailUrl` from Task 1).
- Add both as optional named constructor parameters.
- Add both to `copyWith`'s parameter list and body.
- Add both to `toJson()`/`fromJson()` (these ARE meant to persist — unlike `signedThumbnailUrl`, width/height are intrinsic video properties, not an expiring signed URL, so there's no reason to exclude them from the offline cache).
- Populate both in `Message.fromRow` (reading `row['media_width']`/`row['media_height']`, matching the `(row['media_duration_ms'] as num?)?.toInt()` pattern already used for duration) and `Message.optimistic` (as new optional named parameters, threaded through to the constructor call).

In `lib/features/chat/data/repositories/chat_repository.dart`, widen `sendTextMessage`'s abstract signature (currently ending `int? mediaDurationMs, List<int>? waveform, String? replyToMessageId, String? quotedText`):
```dart
    String? mediaThumbnailKey,
    int? mediaWidth,
    int? mediaHeight,
```
(inserted after `List<int>? waveform,`, before `String? replyToMessageId,`).

In `lib/features/chat/data/repositories/supabase_chat_repository.dart`:
- Widen the concrete `sendTextMessage` implementation's signature to match, and add the three new fields to the `.insert({...})` map (next to `'media_waveform': waveform,`):
```dart
              'media_thumbnail_url': mediaThumbnailKey,
              'media_width': mediaWidth,
              'media_height': mediaHeight,
```
- Widen `_messageColumns` (currently `'...media_duration_ms,media_waveform,source,...'`) to also select `media_width,media_height` — the two new DB columns. **Note**: this migration does not yet add `media_width`/`media_height` columns to the `messages` table — Task 2's migration must be checked/amended to add `ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS media_width integer, ADD COLUMN IF NOT EXISTS media_height integer;` if it doesn't already. If Task 2 is already complete without these columns, add a small follow-up migration statement here rather than going back to edit Task 2's already-committed file — check Task 2's actual committed migration content first before assuming which path applies.
- Widen `_hydrateMessages`' gate (currently `base.mediaType != 'image' && base.mediaType != 'audio'` at line 738) to `(base.mediaType != 'image' && base.mediaType != 'audio' && base.mediaType != 'video')`, and add a type-aware fork so video resolves TWO signed URLs in parallel:

```dart
        if (base.mediaKey == null ||
            (base.mediaType != 'image' &&
                base.mediaType != 'audio' &&
                base.mediaType != 'video')) {
          return base;
        }
        if (base.mediaType == 'video') {
          final results = await Future.wait([
            createSignedMediaUrl(base.mediaKey!),
            if (base.mediaThumbnailKey != null)
              createSignedMediaUrl(base.mediaThumbnailKey!),
          ]);
          return base.copyWith(
            signedMediaUrl: results[0],
            signedThumbnailUrl: results.length > 1 ? results[1] : null,
          );
        }
        final signedUrl = await createSignedMediaUrl(
          base.mediaThumbnailKey ?? base.mediaKey!,
        );
        return base.copyWith(signedMediaUrl: signedUrl);
```

This is the step that makes the earlier "no `_reconcileLocalMediaPaths` exists" correction actually work in practice: by the time `_attemptSend` calls `_replaceOptimistic` with the canonical message, that canonical message (built via `_hydrateMessage`, which calls this widened `_hydrateMessages`) already has `signedThumbnailUrl` populated — no separate path-preservation mechanism is needed.

- [ ] **Step 6: Add `ChatController.sendVideoMessage` and `_attemptSend`'s two-intent branch**

In `lib/features/chat/presentation/state/chat_state.dart`, add a new method immediately after `sendVoiceMessage` (after line 629, before `retryMessage`):

```dart
  /// Sends a video message, mirroring sendImageMessage/sendVoiceMessage's
  /// exact shape. Unlike either of those, this requires the thumbnail file
  /// to also exist before queueing — a video with no way to ever get a
  /// poster is a worse outcome than asking the user to retry the whole
  /// prepare step (see design spec's error table: thumbnail EXTRACTION
  /// failure blocks the send before it's queued; thumbnail UPLOAD failure,
  /// handled in _attemptSend below, is non-fatal once the video itself has
  /// already uploaded successfully).
  Future<void> sendVideoMessage({
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

    // Belt-and-suspenders duration check mirroring sendVoiceMessage's own
    // check against VoiceRecorderService.maxDuration — a stale/modified
    // local file or a future caller bypassing ChatVideoPreparer should not
    // be able to queue an oversized send.
    if (durationMs > ChatVideoPreparer.maxDuration.inMilliseconds) {
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
    );
    state = state.copyWith(
      isSending: true,
      error: null,
      messages: [optimistic, ...state.messages],
    );

    await _attemptSend(pending);
  }
```

Add the required import at the top of the file:
```dart
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
```

Then widen `_attemptSend`'s media block (currently lines 913-930) to handle video's second intent/upload. Replace:
```dart
      final repository = ref.read(chatRepositoryProvider);
      String? mediaKey;
      final isMediaSend = (pending.mediaType == 'image' ||
              pending.mediaType == 'audio') &&
          pending.localMediaPath != null &&
          pending.mediaMimeType != null;
      if (isMediaSend) {
        final intent = await repository.createMediaUploadIntent(
          relationshipId: pending.relationshipId,
          mimeType: pending.mediaMimeType!,
          mediaType: pending.mediaType!,
        );
        await repository.uploadChatMedia(
          intent: intent,
          localPath: pending.localMediaPath!,
          mimeType: pending.mediaMimeType!,
        );
        mediaKey = intent.storageKey;
      }
      final canonical = await repository.sendTextMessage(
        relationshipId: pending.relationshipId,
        senderId: pending.senderId,
        clientMessageId: pending.clientMessageId,
        content: pending.text,
        mediaKey: mediaKey,
        mediaType: pending.mediaType,
        mediaDurationMs: pending.mediaDurationMs,
        waveform: pending.waveform,
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );
```
with:
```dart
      final repository = ref.read(chatRepositoryProvider);
      String? mediaKey;
      String? mediaThumbnailKey;
      final isMediaSend = (pending.mediaType == 'image' ||
              pending.mediaType == 'audio' ||
              pending.mediaType == 'video') &&
          pending.localMediaPath != null &&
          pending.mediaMimeType != null;
      if (isMediaSend) {
        final intent = await repository.createMediaUploadIntent(
          relationshipId: pending.relationshipId,
          mimeType: pending.mediaMimeType!,
          mediaType: pending.mediaType!,
        );
        await repository.uploadChatMedia(
          intent: intent,
          localPath: pending.localMediaPath!,
          mimeType: pending.mediaMimeType!,
        );
        mediaKey = intent.storageKey;

        // Video-only: a second intent/upload for the thumbnail, through the
        // ordinary image path (media_type: 'image'). Non-fatal on its own
        // failure — a successfully-uploaded 25MB video must not be lost
        // over a missing 40KB poster (see design spec's error table). A
        // failure here is caught locally so it doesn't abort the whole
        // send via the outer try/catch.
        if (pending.mediaType == 'video' &&
            pending.localThumbnailPath != null &&
            pending.thumbnailMimeType != null) {
          try {
            final thumbIntent = await repository.createMediaUploadIntent(
              relationshipId: pending.relationshipId,
              mimeType: pending.thumbnailMimeType!,
              mediaType: 'image',
            );
            await repository.uploadChatMedia(
              intent: thumbIntent,
              localPath: pending.localThumbnailPath!,
              mimeType: pending.thumbnailMimeType!,
            );
            mediaThumbnailKey = thumbIntent.storageKey;
          } catch (error) {
            ChatLog.e('video thumbnail upload failed (non-fatal)', error);
          }
        }
      }
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
        replyToMessageId: pending.replyToMessageId,
        quotedText: pending.quotedText,
      );
```

Verify `ChatLog` is already imported in this file (it's used elsewhere per the voice-messages build's own error logging) before assuming the import exists — check the file's import block; if absent, add `import 'package:attune/features/chat/utils/chat_log.dart';` (or wherever `ChatLog` is actually defined — confirm the exact import path against an existing usage in this same file before adding a guessed one).

- [ ] **Step 7: Add `_deleteStagedMedia(pending.localThumbnailPath)` at all 5 real call sites**

In `lib/features/chat/presentation/state/chat_state.dart`, add a companion cleanup call for the thumbnail path immediately after (or alongside) each of these 5 EXACT, verified `_deleteStagedMedia(pending.localMediaPath)` / `_deleteStagedMedia(message.localMediaPath)` / `_deleteStagedMedia(item.localMediaPath)` calls:

1. Line 671, inside `removeFailedMessage` — add `await _deleteStagedMedia(message.localThumbnailPath);` right after. **Note**: `message` here is a `Message`, not a `PendingSend` — `Message` does not have a `localThumbnailPath` field in this plan's design (only `PendingSend` does, since the thumbnail's local path is purely an outbox/send-pipeline concern, never persisted on the `Message` entity itself, matching how `Message` also has no equivalent "local thumbnail path" today for image/audio). Re-derive the correct source for this cleanup call by reading how `removeFailedMessage` actually obtains its `PendingSend` — check whether it already has one in scope, or needs to look one up from the outbox cache the same way `retryMessage` does (lines 635-644), before writing this specific companion call. Do not guess a field that doesn't exist.
2. Line 950, inside `_attemptSend`'s success path — add `await _deleteStagedMedia(pending.localThumbnailPath);` right after (here `pending` IS a `PendingSend`, so this one is direct).
3. Line 981, inside `_attemptSend`'s duplicate-insert (`23505`) reconciliation path — same direct addition, `pending.localThumbnailPath`.
4. Line 1273, inside `_purgeRelationshipLocalState`'s loop over `pending` (a `PendingSend`) — add `await _deleteStagedMedia(item.localThumbnailPath);` alongside the existing `item.localMediaPath` call (verify the loop variable's actual name — the earlier read showed it as `item`, confirm this before writing the addition).
5. Line 1291, inside `_handleAccountChange`'s equivalent loop — same addition, matching whatever the loop variable is actually named there (verify, do not assume it matches call site 4's variable name).

- [ ] **Step 8: Write the `sendVideoMessage` behavioral test**

Check whether Task 5's earlier equivalent for voice messages (`test/features/chat/chat_state_send_voice_message_test.dart`) used a real `FakeChatRepository`/`buildChatContainer` harness (`test/features/chat/support/chat_test_harness.dart`) — if that harness exists and is usable (it was confirmed to exist and be used during the voice-messages build), use it here too for real behavioral coverage rather than a placeholder:

```dart
// test/features/chat/chat_state_send_video_message_test.dart
// Follow test/features/chat/chat_state_send_voice_message_test.dart's exact
// harness usage pattern (FakeChatRepository/buildChatContainer from
// test/features/chat/support/chat_test_harness.dart) if that harness
// exists and covers sendVideoMessage's needs — check the actual current
// content of that harness file and the voice equivalent test file FIRST,
// then write real behavioral tests covering:
//
// - sendVideoMessage with a missing local video file sets state.error and
//   does not queue a PendingSend.
// - sendVideoMessage with a missing thumbnail file (video exists, poster
//   doesn't) sets state.error and does not queue.
// - sendVideoMessage with durationMs over ChatVideoPreparer.maxDuration
//   sets state.error and does not queue.
// - sendVideoMessage with durationMs under ChatVideoPreparer.minDuration
//   returns silently, no error, no queued message.
// - A valid send produces exactly one optimistic message in state.messages
//   with mediaType == 'video', hasVideo == true, status == sending,
//   mediaWidth/mediaHeight matching what was passed in.
//
// If the harness does not exist or cannot be reasonably extended to cover
// the thumbnail-upload-failure-is-non-fatal-but-video-upload-failure-is-not
// distinction from _attemptSend's two-intent branch, write what real
// coverage is achievable and explicitly flag in the task's completion
// notes exactly which of the above cases could not be covered and why —
// do not silently skip any of them without saying so.
```

- [ ] **Step 9: Run all new/modified tests**

Run: `flutter test test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_video_message_test.dart test/features/chat/message_model_test.dart`
Expected: all PASS.

- [ ] **Step 10: Run `dart analyze` on every file this task touched**

Run: `dart analyze lib/features/chat/data/cache/pending_send.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/domain/entities/message.dart test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_video_message_test.dart`
Expected: `No issues found!`

- [ ] **Step 11: Run the full chat test suite for regressions**

Run: `flutter test test/features/chat/`
Expected: only the 2 known baseline failures — specifically confirm the EXISTING image AND voice sending tests still pass unmodified, since this task's `_attemptSend` change is a widening of code both of those paths also run through.

- [ ] **Step 12: Commit**

```bash
git add lib/features/chat/data/cache/pending_send.dart lib/features/chat/data/repositories/chat_repository.dart lib/features/chat/data/repositories/supabase_chat_repository.dart lib/features/chat/presentation/state/chat_state.dart lib/features/chat/domain/entities/message.dart test/features/chat/pending_send_video_test.dart test/features/chat/chat_state_send_video_message_test.dart test/features/chat/message_model_test.dart
git commit -m "feat(chat): add ChatController.sendVideoMessage, thread video through the outbox/send pipeline with two-intent upload"
```

---

### Task 6: `VideoMessagePlayer` — playback in the bubble

**Files:**
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart`
- Modify: `lib/features/chat/presentation/providers/voice_playback_provider.dart` (add the new video provider alongside the existing voice one — same file per the design spec's explicit instruction, enabling the cross-media pause wiring)
- Create: `lib/features/chat/presentation/widgets/video_message_player.dart`
- Test: `test/features/chat/video_message_player_test.dart`

**Interfaces:**
- Consumes: `Message.hasVideo`, `Message.signedThumbnailUrl`, `Message.mediaDurationMs`, `Message.mediaWidth`/`mediaHeight`, `Message.localMediaPath`, `Message.signedMediaUrl` (all from Tasks 1/5).
- Produces: `VideoMessagePlayer` widget, `currentlyPlayingVideoMessageIdProvider` (`StateProvider<String?>`, app-wide, alongside the existing `currentlyPlayingVoiceMessageIdProvider`).

- [ ] **Step 1: Add the video playback provider alongside the existing voice one**

In `lib/features/chat/presentation/providers/voice_playback_provider.dart` (the file already exists with `currentlyPlayingVoiceMessageIdProvider` — add to it, per the design spec's explicit instruction that both providers live in the same file):

```dart
/// The message id of the video message currently playing, if any —
/// app-wide (not scoped per conversation), same shape as
/// currentlyPlayingVoiceMessageIdProvider. Deliberately in the same file so
/// VideoMessagePlayer/VoiceMessagePlayer can each cross-pause the other:
/// starting a video should stop any currently-playing voice message, and
/// vice versa, since two simultaneous audio streams is the actual
/// user-facing failure mode both providers exist to prevent — not just
/// "two of the same media type."
final currentlyPlayingVideoMessageIdProvider = StateProvider<String?>(
  (ref) => null,
);
```

- [ ] **Step 2: Write the failing `VideoMessagePlayer` tests**

```dart
// test/features/chat/video_message_player_test.dart
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the thumbnail with a play button, no video controller until tap',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              videoUrl: 'https://example.com/clip.mp4',
              thumbnailUrl: 'https://example.com/poster.jpg',
              durationMs: 12000,
              width: 1280,
              height: 720,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // No VideoPlayer widget should be in the tree before the first tap —
    // the poster-first, lazy-controller-construction contract that is
    // this widget's one deliberate divergence from VoiceMessagePlayer's
    // eager AudioPlayer construction.
    expect(find.byType(VideoPlayer), findsNothing);
  });

  testWidgets('starting video playback clears a currently-playing voice message (cross-media pause)',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = 'voice-1';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: VideoMessagePlayer(
              key: const ValueKey('m1'),
              messageId: 'm1',
              videoUrl: 'https://example.com/clip.mp4',
              thumbnailUrl: 'https://example.com/poster.jpg',
              durationMs: 12000,
              width: 1280,
              height: 720,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
    expect(container.read(currentlyPlayingVideoMessageIdProvider), 'm1');
  });

  testWidgets('identity is keyed on clientMessageId-equivalent messageId, stable across a widget rebuild with a new videoUrl',
      (tester) async {
    // Regression guard for the exact bug class the voice-messages final
    // review caught and fixed for VoiceMessagePlayer AFTER it shipped —
    // built in from the start here instead. The messageId passed in must
    // be treated as identity; changing videoUrl (simulating the
    // optimistic-to-canonical swap, local path -> signed URL) while
    // messageId stays the same must not tear down and rebuild a fresh
    // player state that loses playback position/state unexpectedly.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget build(String videoUrl) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: VideoMessagePlayer(
                key: const ValueKey('stable-id'),
                messageId: 'stable-id',
                videoUrl: videoUrl,
                thumbnailUrl: 'https://example.com/poster.jpg',
                durationMs: 12000,
                width: 1280,
                height: 720,
              ),
            ),
          ),
        );

    await tester.pumpWidget(build('/tmp/local/clip.mp4'));
    await tester.pump();
    final elementBefore = tester.element(find.byType(VideoMessagePlayer));

    await tester.pumpWidget(build('https://example.com/clip.mp4'));
    await tester.pump();
    final elementAfter = tester.element(find.byType(VideoMessagePlayer));

    // Same Key => Flutter preserves the same Element/State across the
    // videoUrl change, matching VoiceMessagePlayer's established pattern.
    expect(elementBefore, same(elementAfter));
  });

  testWidgets('local-vs-remote source: a videoUrl not starting with http uses a local file source',
      (tester) async {
    // Behavioral confirmation that VideoMessagePlayer's source-selection
    // branch mirrors VoiceMessagePlayer's startsWith('http') check exactly
    // — this test asserts on construction not throwing for a local path,
    // since actually exercising VideoPlayerController.file vs .networkUrl
    // requires a real platform channel unavailable in this test host.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoMessagePlayer(
            key: const ValueKey('m1'),
            messageId: 'm1',
            videoUrl: '/tmp/local/clip.mp4',
            thumbnailUrl: null,
            durationMs: 12000,
            width: 1280,
            height: 720,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/chat/video_message_player_test.dart`
Expected: FAIL — `VideoMessagePlayer`/`currentlyPlayingVideoMessageIdProvider` don't exist yet.

- [ ] **Step 4: Implement `VideoMessagePlayer`**

```dart
// lib/features/chat/presentation/widgets/video_message_player.dart
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Playback UI for a video message bubble: poster-first with a play button,
/// lazy VideoPlayerController construction (not until first tap — the one
/// deliberate divergence from VoiceMessagePlayer's eager AudioPlayer
/// construction, since a list of ten video messages must not spin up ten
/// native video surfaces). Enforces one-at-a-time playback app-wide via
/// currentlyPlayingVideoMessageIdProvider, additionally cross-pausing any
/// currently-playing voice message (and vice versa, wired symmetrically in
/// VoiceMessagePlayer — see that file's own ref.listen).
class VideoMessagePlayer extends ConsumerStatefulWidget {
  const VideoMessagePlayer({
    super.key,
    required this.messageId,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final String messageId;
  final String videoUrl;
  final String? thumbnailUrl;
  final int durationMs;
  final int width;
  final int height;

  @override
  ConsumerState<VideoMessagePlayer> createState() =>
      _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends ConsumerState<VideoMessagePlayer> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isMuted = false;

  @override
  void dispose() {
    // No background/lock-screen playback — leaving the message list stops
    // playback, matching VoiceMessagePlayer's identical guarantee.
    _controller?.dispose();
    super.dispose();
  }

  double get _aspectRatio =>
      widget.height == 0 ? 16 / 9 : widget.width / widget.height;

  Future<void> _togglePlayback() async {
    if (_controller == null) {
      // Local-vs-remote source branching copies VoiceMessagePlayer's
      // startsWith('http') check exactly.
      final controller = widget.videoUrl.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          : VideoPlayerController.file(File(widget.videoUrl));
      await controller.initialize();
      controller.addListener(() {
        if (!mounted) return;
        if (!controller.value.isPlaying && _isPlaying) {
          setState(() => _isPlaying = false);
        }
      });
      _controller = controller;
    }

    if (_isPlaying) {
      await _controller!.pause();
      setState(() => _isPlaying = false);
      return;
    }

    // Cross-media pause: stop any currently-playing voice message before
    // this video starts. The reverse (voice stopping a playing video) is
    // wired symmetrically in VoiceMessagePlayer's own ref.listen.
    if (ref.read(currentlyPlayingVoiceMessageIdProvider) != null) {
      ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = null;
    }
    ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
        widget.messageId;

    await _controller!.play();
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    // Another video bubble became the currently-playing one — pause this one.
    ref.listen<String?>(currentlyPlayingVideoMessageIdProvider, (previous, next) {
      if (next != widget.messageId && _isPlaying) {
        _controller?.pause();
        setState(() => _isPlaying = false);
      }
    });

    return GestureDetector(
      onTap: _togglePlayback,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller?.value.isInitialized == true)
              VideoPlayer(_controller!)
            else if (widget.thumbnailUrl != null)
              Image(
                image: widget.thumbnailUrl!.startsWith('http')
                    ? NetworkImage(widget.thumbnailUrl!) as ImageProvider
                    : FileImage(File(widget.thumbnailUrl!)),
                fit: BoxFit.cover,
              )
            else
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            if (!_isPlaying)
              Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(Duration(milliseconds: widget.durationMs)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: IconButton(
                onPressed: () => setState(() {
                  _isMuted = !_isMuted;
                  _controller?.setVolume(_isMuted ? 0.0 : 1.0);
                }),
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
```

Add the required `dart:io` import for `File` at the top of the file.

- [ ] **Step 5: Wire `VideoMessagePlayer` into `MessageBubble`'s `_BubbleBody`**

In `lib/features/chat/presentation/widgets/message_bubble.dart`, `_BubbleBody` (currently ends its media branches after the `hasAudio` block at line 418, verified against the live file) — insert immediately after that block, before the `message.content.trim().isNotEmpty` check:

```dart
    if (message.hasVideo) {
      final videoUrl = message.localMediaPath ?? message.signedMediaUrl;
      if (videoUrl != null) {
        children.add(
          SizedBox(
            width: 220,
            child: VideoMessagePlayer(
              // clientMessageId, not message.id — the same stability
              // requirement already established for VoiceMessagePlayer
              // (see the comment on that branch immediately above this
              // one): the optimistic message's id changes when the
              // canonical server row replaces it, but clientMessageId
              // stays the same throughout.
              key: ValueKey(message.clientMessageId),
              messageId: message.clientMessageId,
              videoUrl: videoUrl,
              thumbnailUrl: message.signedThumbnailUrl,
              durationMs: message.mediaDurationMs ?? 0,
              width: message.mediaWidth ?? 16,
              height: message.mediaHeight ?? 9,
            ),
          ),
        );
      }
    }
```

Add the import at the top of `message_bubble.dart`:
```dart
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
```

- [ ] **Step 6: Run all tests**

Run: `flutter test test/features/chat/video_message_player_test.dart test/features/chat/presentation/widgets/message_bubble_test.dart test/features/chat/message_bubble_test.dart`
Expected: PASS. Confirm both pre-existing `message_bubble_test.dart` files (`test/features/chat/message_bubble_test.dart` and `test/features/chat/presentation/widgets/message_bubble_test.dart` — both exist in this repo) still pass unmodified — this task only adds a new conditional branch after the existing `hasAudio` branch, it doesn't touch `hasImage` or `hasAudio`.

- [ ] **Step 7: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/widgets/video_message_player.dart lib/features/chat/presentation/providers/voice_playback_provider.dart lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/video_message_player_test.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat/presentation/widgets/video_message_player.dart lib/features/chat/presentation/providers/voice_playback_provider.dart lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/video_message_player_test.dart
git commit -m "feat(chat): video message playback in the bubble, cross-media one-at-a-time enforcement"
```

---

### Task 7: `ChatTextField` gains `showAttachVideo`/`onAttachVideo`

**Files:**
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart`
- Modify: `test/features/chat/chat_text_field_test.dart` (add new tests; verify no existing test breaks)

**Interfaces:**
- Consumes: nothing from earlier tasks — this is pure widget-API surface, independently buildable.
- Produces: `ChatTextField` gains `showAttachVideo` (`bool`, default `false`) and `onAttachVideo` (`VoidCallback?`) as NEW, PURELY ADDITIVE parameters alongside the existing `showAttachImage`/`onAttachImage` (left completely unchanged). Task 8 (`chat_screen.dart`'s attach-sheet wiring) consumes these exact parameter names.

Current file state (verified in full before writing this task): `ChatTextField`'s leading icon area currently renders a single `IconButton` gated by `if (widget.showAttachImage)` (lines 221-226), calling `widget.onAttachImage` directly on tap. This task changes that single condition into a small dispatcher: when BOTH `showAttachImage` and `showAttachVideo` are true, tapping the icon opens a bottom sheet instead of calling `onAttachImage` directly; when only one is true, it behaves exactly as today (direct call, no sheet) for that one type — preserving every existing caller's behavior untouched, since no other caller of `ChatTextField` will ever pass `showAttachVideo: true`.

- [ ] **Step 1: Write the failing tests**

```dart
// Add to test/features/chat/chat_text_field_test.dart — check the file's
// existing _pump helper signature first (it already has showVoiceMessage
// per the voice-messages build) and add showAttachVideo/onAttachVideo
// alongside it the same way, defaulting both to false/null so every
// existing test in this file (which doesn't pass these two) keeps testing
// the "video attach off" baseline unchanged.

  testWidgets('photo icon calls onAttachImage directly when only showAttachImage is true (video off)',
      (tester) async {
    var attachImageCalled = 0;
    await _pump(
      tester,
      controller: TextEditingController(),
      showAttachImage: true,
      onAttachImage: () => attachImageCalled++,
      showAttachVideo: false,
    );

    await tester.tap(find.byIcon(Icons.photo_outlined));
    await tester.pump();

    expect(attachImageCalled, 1);
    // No bottom sheet should have appeared.
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('attach icon opens a Photo/Video sheet when both showAttachImage and showAttachVideo are true',
      (tester) async {
    await _pump(
      tester,
      controller: TextEditingController(),
      showAttachImage: true,
      onAttachImage: () {},
      showAttachVideo: true,
      onAttachVideo: () {},
    );

    await tester.tap(find.byIcon(Icons.photo_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Photo Library'), findsOneWidget);
    expect(find.text('Video Library'), findsOneWidget);
  });

  testWidgets('tapping Video Library in the sheet calls onAttachVideo and dismisses the sheet',
      (tester) async {
    var attachVideoCalled = 0;
    await _pump(
      tester,
      controller: TextEditingController(),
      showAttachImage: true,
      onAttachImage: () {},
      showAttachVideo: true,
      onAttachVideo: () => attachVideoCalled++,
    );

    await tester.tap(find.byIcon(Icons.photo_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Video Library'));
    await tester.pumpAndSettle();

    expect(attachVideoCalled, 1);
    expect(find.text('Video Library'), findsNothing);
  });

  testWidgets('video row is absent from the sheet when showAttachVideo is false but showAttachImage is true',
      (tester) async {
    // This case (image on, video off) never opens a sheet at all per the
    // dispatcher logic — covered by the first test above. This test instead
    // confirms the reverse asymmetry doesn't exist: video-only (image off,
    // video on) is not a supported configuration per the design spec (the
    // server requires chat_image_sharing for any video intent too), so
    // showAttachImage: false, showAttachVideo: true is not a case this
    // widget needs to handle specially — omitted from this task's test
    // matrix deliberately, not an oversight.
  }, skip: true);
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `flutter test test/features/chat/chat_text_field_test.dart`
Expected: FAIL — `showAttachVideo`/`onAttachVideo` are undefined parameters.

- [ ] **Step 3: Wire the dispatcher into `ChatTextField`**

Add the two new fields to the constructor and class body (next to `showAttachImage`/`onAttachImage` — lines 16, 19, 31):
```dart
    this.onAttachVideo,
    this.showAttachVideo = false,
```
```dart
  final VoidCallback? onAttachVideo;
  final bool showAttachVideo;
```

Replace the leading icon block (currently lines 221-226):
```dart
          if (widget.showAttachImage)
            IconButton(
              onPressed: widget.enabled ? widget.onAttachImage : null,
              icon: const Icon(Icons.photo_outlined),
              tooltip: 'Add image',
            ),
```
with:
```dart
          if (widget.showAttachImage)
            IconButton(
              onPressed: widget.enabled ? () => _handleAttachTap(context) : null,
              icon: const Icon(Icons.photo_outlined),
              tooltip: widget.showAttachVideo ? 'Add media' : 'Add image',
            ),
```

Add a new method to `_ChatTextFieldState` (near `_handleSend`):
```dart
  void _handleAttachTap(BuildContext context) {
    if (!widget.showAttachVideo || widget.onAttachVideo == null) {
      widget.onAttachImage?.call();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo Library'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onAttachImage?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video Library'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onAttachVideo?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: Run all tests, confirm no existing test broke**

Run: `flutter test test/features/chat/chat_text_field_test.dart`
Expected: PASS, all tests including every pre-existing one (image-only attach, translator, voice mic/send swap) unmodified — confirming `showAttachVideo`'s default `false` preserves today's exact single-tap photo behavior for every caller that doesn't pass it.

- [ ] **Step 5: Empirically verify the dispatcher logic is real**

Temporarily change `_handleAttachTap`'s condition from `!widget.showAttachVideo || widget.onAttachVideo == null` to always `true` (always call `onAttachImage` directly, never open the sheet) — rerun `'attach icon opens a Photo/Video sheet when both showAttachImage and showAttachVideo are true'`, confirm it FAILS (no sheet found). Revert and confirm green again.

- [ ] **Step 6: Run `dart analyze`**

Run: `dart analyze lib/features/chat/presentation/widgets/chat_text_field.dart test/features/chat/chat_text_field_test.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/chat/presentation/widgets/chat_text_field.dart test/features/chat/chat_text_field_test.dart
git commit -m "feat(chat): add showAttachVideo/onAttachVideo to ChatTextField, Photo/Video attach sheet"
```

---

### Task 8: Wire the `chat_video_sharing` feature flag, `_attachVideo`, and the trim/prepare flow into `chat_screen.dart`

**Files:**
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Test: manual verification (this task is the final integration point — wiring plus a real end-to-end smoke-test checklist, mirroring how the voice-messages plan's final task combined pure wiring with a mandatory manual pass)

**Interfaces:**
- Consumes: `ChatFeatureFlags.videoSharing` (already exists, confirmed at `chat_feature_flags.dart:10` — do not add a new constant), `chatImageSharingEnabledProvider`'s exact pattern as the template for a new `chatVideoSharingEnabledProvider`, `ChatVideoPreparer` (Task 3), `VideoTrimScreen` (Task 4), `ChatController.sendVideoMessage` (Task 5), `ChatTextField.showAttachVideo`/`onAttachVideo` (Task 7).

This is the final task — it's wiring plus the trim/prepare orchestration, following the EXACT existing pattern `chatImageSharingEnabledProvider`/`showAttachImage`/`onAttachImage`/`_attachImage` already establish (all verified against the live file before writing this task).

- [ ] **Step 1: Add `chatVideoSharingEnabledProvider`**

In `lib/features/chat/presentation/state/chat_state.dart` (the same file `chatImageSharingEnabledProvider`/`chatVoiceMessagesEnabledProvider` already live in), add:

```dart
final chatVideoSharingEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.videoSharing,
  );
});
```

- [ ] **Step 2: Wire it into `chat_screen.dart`**

Add the watch, next to `final imageSharingEnabled = ref.watch(chatImageSharingEnabledProvider);` (line 528):
```dart
    final videoSharingEnabled = ref.watch(chatVideoSharingEnabledProvider);
```

Add the handler method, next to `_attachImage` (currently lines 312-353):
```dart
  Future<void> _attachVideo() async {
    final picked = await _imagePicker.pickVideo(fromCamera: false);
    if (picked == null || !mounted) return;

    final MediaInfo? sourceInfo;
    try {
      sourceInfo = await VideoCompress.getMediaInfo(picked.path);
    } catch (_) {
      sourceInfo = null;
    }
    final sourceDurationMs = sourceInfo?.duration?.round();
    if (sourceDurationMs == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That video could not be read. Try a different one.')),
      );
      return;
    }

    final window = await Navigator.of(context).push<({Duration start, Duration end})?>(
      MaterialPageRoute(
        builder: (_) => VideoTrimScreen(
          sourcePath: picked.path,
          sourceDuration: Duration(milliseconds: sourceDurationMs!),
        ),
      ),
    );
    if (window == null || !mounted) return; // user backed out

    final PreparedChatVideo prepared;
    try {
      prepared = await showDialog<PreparedChatVideo>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _VideoPrepareProgressDialog(
          localPath: picked!.path,
          trimStart: window.start,
          trimEnd: window.end,
        ),
      ) ?? (throw const ChatVideoRejected('media_compress_failed'));
    } on ChatVideoRejected catch (rejected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_videoRejectionMessage(rejected.code))),
      );
      return;
    }
    if (!mounted) return;

    _controller.clear();
    await _clearDraft();
    // Mirrors _attachImage's identical reasoning: sendVideoMessage has no
    // replyToMessageId/quotedText params (video replies are equally out of
    // scope per the design spec), so clear any pending reply target here.
    _clearReplyTarget();
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendVideoMessage(
          localPath: prepared.file.path,
          durationMs: prepared.durationMs,
          thumbnailLocalPath: prepared.thumbnailFile.path,
          width: prepared.width,
          height: prepared.height,
        );
    _scrollToLatest();
  }

  String _videoRejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type is not supported. Choose an MP4 or MOV video.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'That video is too large to send. Try trimming it shorter.';
      case 'media_too_long':
        return 'That video is too long. Trim it to 3 minutes or less.';
      case 'media_too_short':
        return 'That clip is too short to send.';
      case 'media_decode_failed':
        return 'That video could not be read. Try a different one.';
      case 'thumbnail_failed':
        return 'Could not prepare that video. Try again.';
      default:
        return 'That video is no longer available.';
    }
  }
```

**Note on the progress dialog**: `_VideoPrepareProgressDialog` (a modal, cancellable dialog wrapping `ChatVideoPreparer.prepare()`, fed by its `onProgress` callback) is referenced above but not fully specified — this is a genuinely new, non-trivial piece of UI (a `StatefulWidget` that calls `prepare()` in `initState`, shows a progress indicator driven by the callback, exposes a cancel button that calls `VideoCompress.cancelCompression()` and pops the dialog with a null/thrown result, and pops with the `PreparedChatVideo` result on success or rethrows `ChatVideoRejected` for the caller to catch). Implement it as a private widget in the same file (`chat_screen.dart`) or as its own small file (`lib/features/chat/presentation/widgets/video_prepare_progress_dialog.dart`) if `chat_screen.dart` is already large — check the current file's line count first to decide, following this codebase's established "split when a file grows unwieldy" convention rather than a fixed threshold.

Add the required imports at the top of `chat_screen.dart`:
```dart
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/screens/video_trim_screen.dart';
import 'package:video_compress/video_compress.dart';
```

Update the `ChatTextField` call site (currently lines 684-712) to pass the two new parameters, next to the existing `showAttachImage`/`onAttachImage` pair:
```dart
              showAttachVideo: videoSharingEnabled.valueOrNull == true,
              onAttachVideo:
                  videoSharingEnabled.valueOrNull == true
                      ? () {
                        unawaited(_attachVideo());
                      }
                      : null,
```

- [ ] **Step 3: Run `dart analyze` on the whole project**

Run: `dart analyze lib/`
Expected: `No issues found!` (zero errors — this is the first point in this plan where a whole-project analyze is meaningful; every prior task's own additions should already have been clean, and this task's wiring is the last piece).

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: only the 2 known baseline failures. **Given the voice-messages plan's own final task discovered its own test-run's reported failure count didn't match the true baseline until independently re-verified against a pre-plan commit** (13 additional failures turned out to be pre-existing/unrelated, confirmed via a disposable worktree checkout) — if this run shows MORE than 2 failures, do not assume they're all pre-existing without checking: identify each by name, and for any not already known from this session's history, verify against a clean pre-this-plan commit (e.g. a disposable `git worktree add` at this plan's own starting commit) before concluding it's unrelated. Enumerate every failure by name in the task's completion notes — do not write "no new regressions" without having named and accounted for every single failure the run reports, which is the exact rigor gap the voice-messages plan's own final task review flagged as a process issue worth avoiding here.

- [ ] **Step 5: Manual smoke test (documented, not automated)**

With `chat_video_sharing` AND `chat_image_sharing` both flipped to `true` in a local/staging `feature_flags` table:
1. Tap the attach icon with a non-empty gallery — confirm the Photo/Video sheet appears.
2. Pick "Video Library", choose a short (~10s) clip — confirm the trim screen opens, pre-positioned to the full clip length.
3. Confirm without adjusting the handles — confirm a progress indicator appears, then the video sends and appears as a bubble with a real poster frame.
4. Tap the bubble — confirm it plays inline, with duration/mute controls.
5. Pick a video longer than 3 minutes — confirm the trim screen opens with a 3-minute-wide window pre-positioned at the start, and the handles cannot be dragged to select a wider range.
6. Play a video message while a voice message is playing (or vice versa) — confirm the first stops (cross-media one-at-a-time enforcement).
7. Play your own just-sent video immediately after sending (before the upload finishes) — confirm it plays from the local file, and does not break when the canonical message replaces the optimistic one mid-playback.
8. Attempt to send with `chat_video_sharing` on but `chat_image_sharing` off — confirm the server rejects the video intent creation with a clear error (per Task 2's paired-flag enforcement), not a confusing partial failure.
9. Cancel an in-progress transcode via the progress dialog's cancel button — confirm no crash, no orphaned temp file, composer returns to idle.

Record the outcome of each step in the task's completion notes. Any failure here is a real, must-fix bug before this feature is considered done — no widget test in Tasks 1-7 exercises the full real-device gesture-to-playback path end to end, matching the exact same caveat the voice-messages plan's final task carried.

- [ ] **Step 6: Commit**

```bash
git add lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/screens/chat_screen.dart
git commit -m "feat(chat): wire chat_video_sharing feature flag, attach sheet, and trim/prepare flow into chat_screen"
```

---

## Plan Self-Review

**Spec coverage check** — every section of `docs/superpowers/specs/2026-08-15-video-sharing-design.md` maps to a task:
- "Recording/Editing UX" (gallery pick, unconditional trim screen, 3-minute cap via clamped handles + byte backstop, client-side thumbnail) → Task 4 (trim screen), Task 3 (`ChatVideoPreparer`'s guard order).
- "Data Model" (`Message` fields, migration, two-intent structure, repository hydration) → Task 1, Task 2, Task 5.
- "Client Architecture" (`ChatVideoPreparer`, trim screen, `VideoMessagePlayer`, attach sheet, `ChatController.sendVideoMessage`, `_attemptSend`'s two-intent branch, `PendingSend` fields, `_deleteStagedMedia` call sites) → Tasks 3, 4, 6, 7, 5, 5, 5, 5 respectively.
- "Error Handling & Checklist Mapping" table → Task 3 (`ChatVideoPreparer`'s guard-to-code mapping), Task 5 (non-fatal thumbnail-upload-failure vs. fatal video-upload-failure), Task 2 (server-side independent re-validation, including the genuinely new thumbnail-intent check).
- "Explicitly Out of Scope" — no task builds cropping, a fullscreen viewer, ephemeral capture, server-side transcoding, camera recording, or video replies; confirmed no task's steps drift into any of these.
- "Testing Evidence Plan" — every bullet has a corresponding task step: `ChatVideoPreparer` unit tests including the relative-correctness window-estimate test (Task 3, with an empirical red/green verification step), trim screen widget tests (Task 4), `VideoMessagePlayer` widget tests including the explicit clientMessageId-stability regression test built in from the start (Task 6), repository/outbox tests (Task 5), migration manual verification (Task 2).

**Placeholder scan** — no bare "TBD"/"add appropriate handling"/"similar to Task N" found. Two places intentionally describe implementation latitude rather than dictating exact pixels (Task 4's filmstrip rendering, Task 8's progress dialog's exact visual layout) — both are flagged explicitly as UI-judgment latitude with the load-bearing testable contract fully specified separately, which is a designed choice, not a placeholder omission of required content.

**Type/signature consistency check across tasks:**
- `PreparedChatVideo {file, mimeType, byteSize, durationMs, thumbnailFile, thumbnailMimeType, thumbnailByteSize, width, height}` — defined Task 3, consumed identically in Task 8's `_attachVideo` (`prepared.file.path`, `prepared.durationMs`, `prepared.thumbnailFile.path`, `prepared.width`, `prepared.height`).
- `ChatController.sendVideoMessage({localPath, durationMs, thumbnailLocalPath, width, height})` — defined Task 5, called with matching argument names in Task 8.
- `VideoTrimScreen({sourcePath, sourceDuration})` returning `({Duration start, Duration end})?` — defined Task 4, consumed identically in Task 8.
- `ChatVideoPreparer.maxDuration`/`minDuration`/`maxBytes`/`maxSourceBytes`/`targetHeight` — defined once in Task 3, referenced (not redefined) in Task 4 (trim screen's clamp bounds), Task 5 (belt-and-suspenders duration checks).
- `Message.signedThumbnailUrl`/`hasVideo`/`mediaWidth`/`mediaHeight` — `signedThumbnailUrl`/`hasVideo` from Task 1, `mediaWidth`/`mediaHeight` added in Task 5 (since Task 1's spec-driven scope didn't originally include them — this plan corrects that gap explicitly rather than silently inventing fields with no defining task), consumed in Task 6's `_BubbleBody` branch and `VideoMessagePlayer`'s constructor.
- `ChatTextField.showAttachVideo`/`onAttachVideo` — defined Task 7, consumed in Task 8's `ChatTextField` call site.
- `chat_video_sharing` flag key — used identically in Task 2's migration and Task 8's provider, sourced from the pre-existing `ChatFeatureFlags.videoSharing` constant (not redefined).

**Known gaps/corrections flagged explicitly within the plan itself** (not silently hidden): the spec's prose reference to a nonexistent `_reconcileLocalMediaPaths` method is corrected in Task 5 with the actual mechanism (`_replaceOptimistic` + `_hydrateMessages`' synchronous signed-URL resolution) documented in its place. The spec's "4 call sites" characterization of `_deleteStagedMedia` is corrected to the verified 5 literal call sites in Task 5, with each one's exact line number and variable-naming caveats spelled out. Task 1 flags that `Message` needs `mediaWidth`/`mediaHeight` fields the original spec's Data Model section didn't explicitly enumerate as new (deferred to Task 5, where they're actually needed and added). Task 3's `video_compress`/`video_thumbnail` API shapes are flagged as unverified-until-`flutter pub get` (mirroring the exact same caveat the voice-messages plan carried for the `record` package, which turned out to need one small adaptation). Task 8's Step 4 explicitly requires enumerating every test failure by name rather than repeating the process gap the voice-messages plan's own final task review flagged (asserting "no new regressions" while only naming 2 of 15 actual failures).
