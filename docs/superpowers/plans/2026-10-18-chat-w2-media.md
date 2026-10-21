# Chat Robustness Wave 2 — Media Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix chat media issues #20–#29 from the 2026-10-18 chat robustness review so photos arrive sharp, voice notes keep playing while you scroll, broken tiles heal themselves, delete-for-everyone really deletes the bytes, uploads show progress and can be cancelled, and voice/video play offline after the first download.

**Architecture:** Photos get a chat-only picker (`ChatImagePicker`) that hands the untouched source to `ChatImagePreparer`, which stays the single resize/strip/encode pass. Voice playback moves out of the bubble into an app-scoped Riverpod `VoicePlaybackController` that owns one engine (`VoicePlaybackEngine` wrapping audioplayers); bubbles become views. Signed-URL resolution becomes an autoDispose family that never caches a failure, refreshes itself before the token expires and re-resolves when connectivity returns. A `ChatMediaCache` (flutter_cache_manager, key = storage key) stores voice/video bytes once. Uploads go through a streaming `ChatMediaUploader` (raw POST to the Storage object endpoint over `http`) so the controller gets byte progress and a working cancel; `ChatError` classifies storage failures by status code. Two SQL migrations fix `delete_message` (queues both storage objects) and the two mis-registered cron jobs, each with a contract test.

**Tech Stack:** Flutter 3.29, Riverpod 2.6, audioplayers 6.6, flutter_cache_manager 3.3, image_picker 1.2 (platform interface 2.11), http 1.6, storage_client 2.5.5 (Supabase), Postgres 17 + pg_cron, psql contract tests.

**Spec:** `lib/architecture/CHAT_SYSTEM_SPEC.md` (§8.1 upload contract, §8.2 private keys + signed URLs), `docs/superpowers/specs/2026-08-15-voice-messages-design.md` (Playback: one-at-a-time; leaving the chat screen stops playback), `docs/superpowers/specs/2026-08-13-message-actions-design.md` (delete tombstone), review evidence `docs/reviews/2026-10-18-chat-review/04_media.md` and `V2_media_motion_server_verify.md`.

## Global Constraints

- Work on main in the existing working tree (the owner has other uncommitted work; never revert or reformat it). NO COMMITS: replace every "Commit" step with "Checkpoint: run this task's tests and `flutter analyze <touched files>` filtered with `grep -E '^\s*(error|warning) '`; no commit (the owner commits)".
- Never run `dart format` on pre-existing files (repo uses an older formatter; reflowing is a regression). Only new files may be formatted.
- Test-first: every fix starts with a failing test that reproduces the verified failure scenario; watch it fail for the right reason, then fix.
- Flutter tests: `flutter test <path>`; reuse existing harnesses (test/features/chat/support/chat_test_harness.dart, FakeChatRepository, fake cache backends, FakeHaptics). Update old tests only where they encode the wrong behaviour, and say so.
- SQL: new migrations only (never edit an existing migration). Use ONLY your assigned timestamp range (20261019120000–20261019129999). Apply locally with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/<file>.sql`; contract tests in supabase/tests/<name>_contracts.sql in the existing style (BEGIN … RAISE EXCEPTION 'CONTRACT VIOLATED: …' … ROLLBACK; see supabase/tests/home_card_order_contracts.sql and chat_system_contracts.sql), run with `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/<file>.sql`. Include a mutation check for each key rule (temporarily break the rule in a transaction and show the contract fails). NEVER use the attune_test database. Never touch the live project; deploying migrations/functions is an owner step — list them at the end under "Owner deploy steps".
- Edge functions (Deno/TS): follow existing patterns in supabase/functions; if the function has Deno tests, add tests; otherwise extract pure logic into a testable module with a Deno test (`deno test` if available — check `which deno`; if not available, say so and make the logic testable via SQL or Dart instead). (`deno` is at /opt/homebrew/bin/deno; this plan changes no edge function.)
- Owner-only steps (Xcode capabilities, OneSignal dashboard settings, App Store / Apple developer portal) are listed explicitly as "Owner step" with exact instructions; the plan still makes every file change that can be made in the repo (e.g. entitlements/Info.plist edits).
- Display dates via MyDateFormat; user-facing copy plain and warm; respect reduceMotionOf for animations; haptics via hapticsProvider.
- Don't touch ATTUNE_SOUL.md / ATTUNE_THESIS.md. Don't read .env/credentials/keychain.
- Execution order across plans: 1a → 1b → 2 → 3 → 4, sequential on the same tree. Later plans must not assume line numbers from before earlier plans ran; say which files you share with other plans in a "Shared files" note.
- No new pub dependencies. `audio_session` is not in the pub cache (adding it needs network + native session wiring); see the Task 7 ruling.
- Design against function/class names, never line numbers: Wave 1a/1b run first and edit `chat_state.dart` (`_attemptSend`, `_handleSendFailure`, `flushOutbox`).

## Shared files (with other waves)

- `lib/features/chat/presentation/state/chat_state.dart` — Wave 1a/1b (outbox flush, retry caps, 23505 path). This plan touches only: `signedMediaUrlProvider` (Task 6), `_prepareAndAttemptSend`/`removeFailedMessage` raw-source cleanup (Task 3), the `uploadChatMedia` call inside `_attemptSend` plus a new `cancelSend` method and `_uploadCancelTokens` map (Task 9). Re-read the current body before each edit.
- `lib/features/chat/presentation/widgets/message_bubble.dart` — Wave 3 (#31 edited label, #36 status, #38 decode size). This plan touches only the image tile's busy overlay, the voice player call site, and `onCancelSend` threading.
- `lib/features/chat/presentation/screens/chat_screen.dart` — Wave 1 (#10 view-active), Wave 3 (#30/#32/#33). This plan touches only `_attachImage`, the `_imagePicker` field, `_ChatScreenState.initState/dispose` (voice stop), and the `MessageBubble(onCancelSend:)` argument.
- `lib/features/chat/presentation/widgets/voice_message_player.dart` and the new `AudioPlayersVoiceEngine` — Wave 4 (#40 iOS ambient restore after a voice note) should hook the engine's `pause/stop/complete`, not the widget.
- `lib/features/auth/providers/auth_provider.dart` — `signOut()` gains one line (media cache wipe). Plan 1b Task 8 adds a `beforeSignOut()` call to the same method first; add this plan's line inside the existing `try` next to `clearAll()`, leave 1b's block alone.
- `lib/features/chat/domain/services/chat_image_preparer.dart` — Task 3 only (header probe + off-isolate fallback); no other plan touches it.
- `test/features/chat/support/chat_test_harness.dart` — `FakeChatRepository.uploadChatMedia` gains optional `onProgress`/`cancelToken` parameters (Task 9) and `signMediaUrlFailuresBeforeSuccess` (Task 6).

## Review Focus

Inputs the spec implies but no task's tests exercise, most likely to bite first — each line's pin test is added to the owning task:

1. A HEIC photo picked from an iPhone library: image_picker returns the original container when no size options are passed; `ChatImagePreparer` sniffs bytes and must reject with `media_type_unsupported` rather than crash the decoder — pinned in Task 3 (HEIC magic bytes fixture).
2. A voice note tapped while another conversation's note is paused mid-way: the controller must reset position state for the old message, not carry it over — pinned in Task 7 (`switching messages resets position`).
3. The chat opened offline, then the tile scrolls off and back on after reconnect: the autoDispose provider must re-resolve rather than resurrect the error — pinned in Task 6 (`connectivity flip re-resolves`).
4. A 0-byte cached voice file (killed mid-download): `ChatMediaCache.fetch` must treat an empty cache hit as a miss — pinned in Task 8.
5. Cancel tapped after the upload already finished but before the row insert: cancel must be a no-op (the message still lands) — pinned in Task 9.

## File Structure

New files:
- `supabase/migrations/20261019120000_delete_message_queues_media.sql` — `delete_message` redefinition queuing media + thumbnail objects.
- `supabase/tests/delete_message_media_contracts.sql` — contract + mutation check.
- `supabase/migrations/20261019120100_chat_media_cron_fix.sql` — re-registers `recover-stale-chat-workers` and `cleanup-expired-chat-media` as SQL jobs.
- `supabase/tests/chat_media_cron_contracts.sql` — contract + mutation check.
- `lib/features/chat/domain/services/chat_image_picker.dart` — full-resolution gallery pick into a chat-owned temp folder; `ownsPath`; `discard`.
- `test/features/chat/chat_image_picker_test.dart`
- `lib/features/chat/data/repositories/chat_media_uploader.dart` — streaming upload with progress + cancel; `ChatUploadCancelToken`, `ChatUploadCancelled`.
- `test/features/chat/chat_media_uploader_test.dart`
- `lib/features/chat/domain/services/chat_media_cache.dart` — key-based disk cache for voice/video bytes.
- `test/features/chat/chat_media_cache_test.dart`
- `lib/features/chat/presentation/state/voice_playback_controller.dart` — `VoicePlaybackEngine`, `AudioPlayersVoiceEngine`, `VoicePlaybackState`, `VoicePlaybackController`, providers.
- `test/features/chat/voice_playback_controller_test.dart`, `test/features/chat/support/fake_voice_engine.dart`
- `test/features/chat/chat_error_storage_test.dart`, `test/features/chat/signed_media_url_retry_test.dart`, `test/features/chat/chat_upload_progress_cancel_test.dart`, `test/features/chat/chat_image_preparer_resolution_test.dart`

Modified files:
- `lib/features/chat/presentation/screens/chat_screen.dart` — `_attachImage` uses `chatImagePickerProvider`; stops voice playback on dispose; threads `onCancelSend`.
- `lib/features/chat/presentation/state/chat_state.dart` — see Shared files.
- `lib/features/chat/utils/chat_error.dart` — storage status classification; media-aware copy.
- `lib/features/chat/domain/services/chat_video_preparer.dart` — `debugSniffMime` accepts every ISO-BMFF `ftyp`.
- `lib/features/chat/presentation/widgets/resolved_media_url.dart` — tap-to-retry error tile.
- `lib/features/chat/presentation/widgets/voice_message_player.dart` — view of the controller + speed chip + download ring.
- `lib/features/chat/presentation/widgets/message_bubble.dart` — progress/cancel overlay; voice call site passes `mediaKey`.
- `lib/features/chat/presentation/widgets/video_message_thumbnail.dart` — ring shows a cancel glyph only when cancel exists.
- `lib/features/chat/presentation/screens/video_viewer_screen.dart` — plays from `ChatMediaCache`.
- `lib/features/chat/data/repositories/chat_repository.dart`, `supabase_chat_repository.dart` — `uploadChatMedia(onProgress, cancelToken)`.
- `lib/features/chat/domain/entities/message.dart` — `uploadProgress` field.
- `lib/features/auth/providers/auth_provider.dart` — wipe media cache on sign-out.
- Tests updated because they encode the wrong behaviour: `test/features/chat/chat_video_preparer_test.dart` (unrecognised-brand case), `test/features/chat/voice_playback_audio_context_test.dart` (file moved), `test/features/chat/voice_signed_url_freshness_test.dart` (resolver shape), `test/features/chat/voice_message_player_test.dart` (engine override), `test/features/chat/support/chat_test_harness.dart`.

## Issue → task map

| Issue | Task | Ruling |
|---|---|---|
| #23 delete_message leaves bytes | Task 1 | fix |
| #24 cron misregistration | Task 2 | fix |
| #20 photos shrunk to ~500 px | Task 3 | fix (chat-only picker; mandatory crop dropped — it was the 2nd/3rd re-encode; optional crop is review M-9, out of scope) |
| #27 copies in Documents/shop_images | Task 3 | fix (temp dir + cleanup after preparation / on remove) |
| #29 strict MP4 ftyp allowlist | Task 4 | fix client; server unchanged — `create_chat_media_upload_intent` only compares the MIME string and the client always transcodes to `video/mp4` (chat_video_preparer `mimeType: 'video/mp4'`), so no server allowlist is involved |
| #26 StorageException always permanent | Task 5 | fix |
| #22 signed-URL failure cached for the session | Task 6 | fix |
| #21 voice stops when bubble scrolls off | Task 7 | fix (controller); OS interruptions via engine state stream; speed 1×/1.5×/2×; `audio_session` not added (see ruling in Task 7) |
| #28 voice/video never cached | Task 8 | fix (bounded count + stale period; cleared on sign-out) |
| #25 upload progress / cancel / retry; stop glyph | Task 9 | fix progress + cancel + retry; TUS resumability ruled out (25 MB cap, retry restarts; Wave 1 adds connectivity flush) |

---

### Task 1: `delete_message` queues the storage objects (#23)

**Files:**
- Create: `supabase/migrations/20261019120000_delete_message_queues_media.sql`
- Create: `supabase/tests/delete_message_media_contracts.sql`

**Interfaces:**
- Consumes: `public.queue_media_deletion(p_bucket_id text, p_object_name text)` (20260930120000; SECURITY DEFINER, ON CONFLICT DO NOTHING), `public.media_deletion_queue(bucket_id, object_name, requested_at, deleted_at, not_before)`, current `delete_message(uuid)` body from `20260950110000_ai_assist_message_edit_delete_split.sql` (locks `id, message_origin`, UPDATE … RETURNING id, Assist link cleanup).
- Produces: `public.delete_message(uuid)` with identical error contract (`not_authenticated` 42501, `not_deletable` 42501) that additionally inserts up to two `media_deletion_queue` rows in the same transaction. Both chat media and worker thumbnails live in bucket `message-media` (process-chat-media/index.ts uploads `chat-thumbnails/…` into `message-media`).

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/delete_message_media_contracts.sql`:

```sql
-- delete_message must queue the message's storage objects for deletion
-- (chat review 2026-10-18 #23): a soft-deleted photo/voice/video row kept
-- its bytes in the bucket forever because only the BEFORE DELETE trigger
-- queued media and delete_message is an UPDATE.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('d3110000-0000-0000-0000-0000000000a1'),
  ('d3110000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('d3110000-0000-0000-0000-0000000000a1', '+15550003101', 'A'),
  ('d3110000-0000-0000-0000-0000000000b2', '+15550003102', 'B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('d3110000-0000-0000-0000-000000000001',
        'd3110000-0000-0000-0000-0000000000a1',
        'd3110000-0000-0000-0000-0000000000b2', 'active')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- Media rows are inserted with triggers off: validate_message_media_before_insert
-- wants a consumed upload intent + storage object, which is not what is under
-- test here (same technique as relationship_purge_contracts.sql).
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, media_thumbnail_url, created_at)
VALUES
  ('d3110000-0000-0000-0000-000000000101', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-video.mp4', 'video', 'chat-media/d311-poster.jpg', now()),
  ('d3110000-0000-0000-0000-000000000102', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-photo.jpg', 'image', NULL, now()),
  ('d3110000-0000-0000-0000-000000000103', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000b2', gen_random_uuid(), NULL, 'chat-media/d311-partner.jpg', 'image', NULL, now()),
  ('d3110000-0000-0000-0000-000000000104', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'just words', NULL, NULL, NULL, now());
SET LOCAL session_replication_role = origin;

-- 1. Deleting my video queues BOTH the video and its poster, in bucket message-media.
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000101');
DO $$
DECLARE v_rows int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.media_deletion_queue
  WHERE bucket_id = 'message-media'
    AND object_name IN ('chat-media/d311-video.mp4', 'chat-media/d311-poster.jpg')
    AND deleted_at IS NULL;
  IF v_rows <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected video + poster queued, found % rows', v_rows;
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = 'd3110000-0000-0000-0000-000000000101'
             AND (media_url IS NOT NULL OR media_thumbnail_url IS NOT NULL OR deleted_at IS NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: tombstone not applied';
  END IF;
END $$;

-- 2. A photo with no thumbnail queues exactly one row.
SELECT public.delete_message('d3110000-0000-0000-0000-000000000102');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-photo.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo not queued exactly once';
  END IF;
END $$;

-- 3. A rejected delete (partner's message) queues nothing.
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_message('d3110000-0000-0000-0000-000000000103');
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleted the partner''s message';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-partner.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rejected delete queued the partner''s media';
  END IF;
END $$;

-- 4. A text message deletes as before and adds no queue rows.
DO $$
DECLARE v_before int; v_after int;
BEGIN
  SELECT count(*) INTO v_before FROM public.media_deletion_queue;
  PERFORM public.delete_message('d3110000-0000-0000-0000-000000000104');
  SELECT count(*) INTO v_after FROM public.media_deletion_queue;
  IF v_after <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: text delete touched the media queue';
  END IF;
END $$;

-- 5. Mutation check: with queue_media_deletion stubbed to a no-op, contract 1
-- must FAIL. Done under a savepoint so the real function is restored.
SAVEPOINT mutation;
CREATE OR REPLACE FUNCTION public.queue_media_deletion(p_bucket_id text, p_object_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN RETURN; END $$;
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type, created_at)
VALUES ('d3110000-0000-0000-0000-000000000105', 'd3110000-0000-0000-0000-000000000001', 'd3110000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/d311-mutant.jpg', 'image', now());
SET LOCAL session_replication_role = origin;
SELECT pg_temp.as_user('d3110000-0000-0000-0000-0000000000a1');
SELECT public.delete_message('d3110000-0000-0000-0000-000000000105');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'chat-media/d311-mutant.jpg') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: the stubbed queue still recorded a row';
  END IF;
  RAISE NOTICE 'mutation check: contract 1 would fail with queue_media_deletion stubbed (as intended)';
END $$;
ROLLBACK TO SAVEPOINT mutation;

RESET ROLE;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails for the right reason**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/delete_message_media_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: expected video + poster queued, found 0 rows` (contract 1). If instead it fails with a privilege error on `set_config`, check the fixture ids were inserted.

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261019120000_delete_message_queues_media.sql`:

```sql
-- Chat review 2026-10-18 #23: "Delete for everyone" nulled media_url /
-- media_thumbnail_url but never queued the storage objects, so the photo,
-- voice or video bytes stayed in the private bucket indefinitely (and any
-- signed URL minted in the previous 10 minutes kept working). Only the
-- BEFORE DELETE trigger queued media; delete_message is an UPDATE.
--
-- Body below is the 20260950110000 body (read in full) plus: the locking
-- SELECT also reads media_url / media_thumbnail_url, and after the UPDATE
-- succeeded both keys are handed to queue_media_deletion inside the same
-- transaction. queue_media_deletion ignores NULL/empty names and dedups
-- on (bucket_id, object_name), so a text message or a poster-less image is
-- a no-op and a retry cannot double-queue. Both chat media and the worker's
-- chat-thumbnails/… posters live in bucket 'message-media'.
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_locked_id uuid;
  v_locked_origin text;
  v_media_url text;
  v_thumbnail_url text;
  v_updated_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Lock BEFORE the ownership/window check (Checklist 2.16); the media keys
  -- are read under the same lock so a concurrent delete cannot read them
  -- after this transaction has already nulled them.
  SELECT id, message_origin, media_url, media_thumbnail_url
    INTO v_locked_id, v_locked_origin, v_media_url, v_thumbnail_url
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  UPDATE public.messages
  SET content = NULL,
      media_url = NULL,
      media_type = NULL,
      media_thumbnail_url = NULL,
      deleted_at = now(),
      assistant_payload = CASE
        WHEN v_locked_origin = 'attune_assist' THEN NULL
        ELSE assistant_payload
      END,
      message_origin = CASE
        WHEN v_locked_origin = 'attune_assist' THEN 'user'
        ELSE message_origin
      END
  WHERE id = p_message_id
    AND sender_id = v_uid
    AND deleted_at IS NULL
    AND created_at > now() - interval '5 minutes'
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = messages.relationship_id
        AND r.status = 'active'
        AND r.chat_archived_at IS NULL
    )
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RAISE EXCEPTION 'not_deletable' USING ERRCODE = '42501';
  END IF;

  -- Only after the tombstone is committed to this transaction: a rejected
  -- delete must never queue someone else's media.
  PERFORM public.queue_media_deletion('message-media', v_media_url);
  PERFORM public.queue_media_deletion('message-media', v_thumbnail_url);

  IF v_locked_origin = 'attune_assist' THEN
    DELETE FROM public.ai_assist_planning_links WHERE message_id = p_message_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_message(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_message(uuid) TO authenticated;
```

- [ ] **Step 4: Apply and run the contract test**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019120000_delete_message_queues_media.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/delete_message_media_contracts.sql`
Expected: `CREATE FUNCTION`, `REVOKE`, `GRANT`, then the test prints `NOTICE:  mutation check: contract 1 would fail with queue_media_deletion stubbed (as intended)` and ends with `ROLLBACK` and no ERROR.

- [ ] **Step 5: Re-run the existing edit/delete contracts (no regression)**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/message_edit_delete_contracts.sql`
Expected: `NOTICE:  message_edit_delete_contracts.sql: all contracts passed`. (This file writes without a transaction; its fixtures are `ON CONFLICT DO NOTHING`, so re-running is safe in the scratch database.)

- [ ] **Step 6: Checkpoint**

Checkpoint: both SQL files run green; no commit (the owner commits).

---

### Task 2: Fix the two media maintenance cron jobs (#24)

**Files:**
- Create: `supabase/migrations/20261019120100_chat_media_cron_fix.sql`
- Create: `supabase/tests/chat_media_cron_contracts.sql`

**Interfaces:**
- Consumes: `public.recover_stale_chat_worker_leases()` RETURNS TABLE(worker text, recovered bigint) and `public.cleanup_expired_chat_media_intents()` RETURNS int (20260705200000); `cron.job(jobid, jobname, command)`; `message_media_processing_outbox(message_id, state, attempts, processing_started_at, …)`.
- Produces: cron jobs `recover-stale-chat-workers` (`*/5 * * * *`) running `SELECT * FROM public.recover_stale_chat_worker_leases();` and `cleanup-expired-chat-media` (`17 * * * *`) running `SELECT public.cleanup_expired_chat_media_intents();`. `process-chat-media` is untouched.

- [ ] **Step 1: Write the failing contract test**

`supabase/tests/chat_media_cron_contracts.sql`:

```sql
-- Chat review 2026-10-18 #24: both maintenance jobs were registered as
-- invoke_edge_function('process-chat-media'), which never calls the SQL
-- functions they were meant to run. Requires pg_cron (present locally).
BEGIN;
DO $$
DECLARE v_cmd text;
BEGIN
  -- 1. The stale-lease job calls its SQL function, not the edge function.
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'recover-stale-chat-workers';
  IF v_cmd IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover-stale-chat-workers not scheduled';
  END IF;
  IF v_cmd NOT LIKE '%recover_stale_chat_worker_leases()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover-stale-chat-workers runs: %', v_cmd;
  END IF;

  -- 2. The expired-intent cleanup job calls its SQL function.
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'cleanup-expired-chat-media';
  IF v_cmd IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup-expired-chat-media not scheduled';
  END IF;
  IF v_cmd NOT LIKE '%cleanup_expired_chat_media_intents()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup-expired-chat-media runs: %', v_cmd;
  END IF;

  -- 3. The media worker itself is still scheduled every minute.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'process-chat-media'
                 AND command LIKE '%invoke_edge_function(''process-chat-media'')%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: process-chat-media job lost';
  END IF;
END $$;

-- 4. The scheduled commands actually run: exercise each exactly as cron would.
SET LOCAL session_replication_role = replica;
INSERT INTO auth.users (id) VALUES ('c2400000-0000-0000-0000-0000000000a1'), ('c2400000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('c2400000-0000-0000-0000-0000000000a1', '+15550002401', 'A'),
  ('c2400000-0000-0000-0000-0000000000b2', '+15550002402', 'B') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status)
VALUES ('c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000a1', 'c2400000-0000-0000-0000-0000000000b2', 'active') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_type)
VALUES ('c2400000-0000-0000-0000-000000000101', 'c2400000-0000-0000-0000-000000000001', 'c2400000-0000-0000-0000-0000000000a1', gen_random_uuid(), NULL, 'chat-media/c240-stale.jpg', 'image');
DELETE FROM public.message_media_processing_outbox WHERE message_id = 'c2400000-0000-0000-0000-000000000101';
INSERT INTO public.message_media_processing_outbox (message_id, storage_key, state, attempts, processing_started_at)
VALUES ('c2400000-0000-0000-0000-000000000101', 'chat-media/c240-stale.jpg', 'processing', 1, now() - interval '20 minutes');
SET LOCAL session_replication_role = origin;

DO $$
DECLARE v_state text; v_rows int; v_cleaned int;
BEGIN
  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'recover-stale-chat-workers');
  SELECT state INTO v_state FROM public.message_media_processing_outbox
  WHERE message_id = 'c2400000-0000-0000-0000-000000000101';
  IF v_state IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: stale media lease not recovered (state %)', v_state;
  END IF;
  SELECT count(*) INTO v_rows FROM public.recover_stale_chat_worker_leases();
  IF v_rows < 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recover_stale_chat_worker_leases reports % workers', v_rows;
  END IF;

  EXECUTE (SELECT command FROM cron.job WHERE jobname = 'cleanup-expired-chat-media');
  v_cleaned := public.cleanup_expired_chat_media_intents();
  IF v_cleaned IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cleanup_expired_chat_media_intents returned NULL';
  END IF;
END $$;

-- 5. Mutation check: point the job back at the edge function; contract 1 must fail.
SAVEPOINT mutation;
UPDATE cron.job SET command = $$ SELECT public.invoke_edge_function('process-chat-media'); $$
WHERE jobname = 'recover-stale-chat-workers';
DO $$
DECLARE v_cmd text;
BEGIN
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'recover-stale-chat-workers';
  IF v_cmd NOT LIKE '%recover_stale_chat_worker_leases()%' OR v_cmd LIKE '%process-chat-media%' THEN
    RAISE NOTICE 'mutation check: contract 1 would fail with the old command (as intended)';
  ELSE
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 1 passed with the old command';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutation;
ROLLBACK;
```

- [ ] **Step 2: Run it to verify it fails for the right reason**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_media_cron_contracts.sql`
Expected: `ERROR:  CONTRACT VIOLATED: recover-stale-chat-workers runs:  SELECT public.invoke_edge_function('process-chat-media');`

- [ ] **Step 3: Write the migration**

`supabase/migrations/20261019120100_chat_media_cron_fix.sql`:

```sql
-- Chat review 2026-10-18 #24: 20260907120000 registered
-- 'recover-stale-chat-workers' and 'cleanup-expired-chat-media' as
-- invoke_edge_function('process-chat-media'). That worker never calls
-- recover_stale_chat_worker_leases() or cleanup_expired_chat_media_intents(),
-- so stranded 'processing' rows were never recovered and abandoned upload
-- intents' objects were never swept. Both are SECURITY DEFINER SQL
-- functions: schedule them directly (no HTTP hop, no service-role key),
-- like the pure-SQL maintenance block at the end of 20260907120000.
--
-- Idempotent: unschedule by name first (cron.schedule errors on a
-- duplicate jobname). Guarded so a database without pg_cron (a bare local
-- scratch DB) applies the migration without error — the hosted project
-- has pg_cron from 20260907120000.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not installed; chat media maintenance jobs not scheduled here';
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid) FROM cron.job
  WHERE jobname IN ('recover-stale-chat-workers', 'cleanup-expired-chat-media');

  PERFORM cron.schedule(
    'recover-stale-chat-workers',
    '*/5 * * * *',
    'SELECT * FROM public.recover_stale_chat_worker_leases();'
  );

  PERFORM cron.schedule(
    'cleanup-expired-chat-media',
    '17 * * * *',
    'SELECT public.cleanup_expired_chat_media_intents();'
  );
END $$;
```

- [ ] **Step 4: Apply and run the contract test**

Run: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019120100_chat_media_cron_fix.sql && psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/chat_media_cron_contracts.sql && psql -X -d attune_spec3a -Atc "select jobname, schedule, command from cron.job where jobname in ('recover-stale-chat-workers','cleanup-expired-chat-media') order by 1;"`
Expected: `DO`; the test ends with `NOTICE:  mutation check: contract 1 would fail with the old command (as intended)` and `ROLLBACK`; the final query prints
```
cleanup-expired-chat-media|17 * * * *|SELECT public.cleanup_expired_chat_media_intents();
recover-stale-chat-workers|*/5 * * * *|SELECT * FROM public.recover_stale_chat_worker_leases();
```

- [ ] **Step 5: Idempotency**

Run the migration a second time: `psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261019120100_chat_media_cron_fix.sql && psql -X -d attune_spec3a -Atc "select count(*) from cron.job where jobname in ('recover-stale-chat-workers','cleanup-expired-chat-media');"`
Expected: `DO` then `2` (no duplicates).

- [ ] **Step 6: Checkpoint**

Checkpoint: both SQL files run green; no commit (the owner commits).

---

### Task 3: Full-resolution chat photo pick, no stray copies (#20, #27)

**Files:**
- Create: `lib/features/chat/domain/services/chat_image_picker.dart`
- Create: `test/features/chat/chat_image_picker_test.dart`
- Create: `test/features/chat/chat_image_preparer_resolution_test.dart`
- Create: `test/features/chat/chat_image_pick_cleanup_test.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_attachImage` only; `_imagePicker` stays for `pickVideo`)
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`_prepareAndAttemptSend` image branch, `removeFailedMessage`)
- Keep green: `test/features/chat/chat_image_preparer_exif_test.dart`, `test/features/chat/chat_image_preparer_test.dart`

**Interfaces:**
- Consumes: `ImagePicker.pickImage({source, requestFullMetadata})` (image_picker 1.2.1 → `ImagePickerPlatform.getImageFromSource(source:, options: ImagePickerOptions)`), `ChatImagePreparer.prepare(String localPath)` (unchanged; 1600 long edge, ≤ 800 KB, EXIF stripped), `ChatController.sendImageMessage({localPath, caption, onOptimisticMessage})`.
- Produces: `class ChatImagePicker { Future<String?> pickFromGallery(); static bool ownsPath(String? path); static Future<void> discard(String? path); static const folderName = 'chat_picks'; }` and `final chatImagePickerProvider = Provider<ChatImagePicker>`.

Ruling recorded here: the mandatory crop step is dropped for chat. It was the second re-encode (image_cropper writes its own JPEG) feeding the third (`_compressImage`, short edge 500 px); the review (04 M-9) asks for crop to become an optional edit on `ImageCaptionScreen`, which is a UX feature outside this wave. `ImagePickerService` itself is not modified (profile/shop/dating flows use it).

- [ ] **Step 1: Write the failing picker test**

`test/features/chat/chat_image_picker_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records the options the picker was asked for and hands back [sourcePath]
/// the way the real plugin hands back its own temp copy.
class _RecordingPickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _RecordingPickerPlatform(this.sourcePath);
  final String? sourcePath;
  ImageSource? source;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.source = source;
    this.options = options;
    final path = sourcePath;
    return path == null ? null : XFile(path);
  }
}

void main() {
  late Directory tmp;
  late Directory pluginTmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_pick_app_tmp');
    pluginTmp = await Directory.systemTemp.createTemp('chat_pick_plugin');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
    if (await pluginTmp.exists()) await pluginTmp.delete(recursive: true);
  });

  Future<String> writePluginFile() async {
    final f = File(p.join(pluginTmp.path, 'image_picker_ABC.jpg'));
    await f.writeAsBytes(List<int>.filled(4096, 7));
    return f.path;
  }

  test('asks the OS picker for the ORIGINAL bytes (no resize, no quality)',
      () async {
    final platform = _RecordingPickerPlatform(await writePluginFile());
    ImagePickerPlatform.instance = platform;
    final picker = ChatImagePicker(tempDirectory: () async => tmp);

    final path = await picker.pickFromGallery();

    expect(path, isNotNull);
    expect(platform.source, ImageSource.gallery);
    expect(platform.options!.maxWidth, isNull,
        reason: 'any maxWidth re-encodes in the plugin before the preparer');
    expect(platform.options!.maxHeight, isNull);
    expect(platform.options!.imageQuality, isNull,
        reason: 'Android: any quality turns the plugin resizer on; the '
            'untouched original goes to the preparer');
    expect(platform.options!.requestFullMetadata, isFalse,
        reason: 'the preparer strips EXIF anyway; do not ask iOS for it');
  });

  test('on iOS the plugin re-encodes anyway: ask for 92, never a size',
      () async {
    // image_picker_ios always passes the pick through UIImage ->
    // UIImageJPEGRepresentation (HEIC included), at quality 1.0 when none
    // is given — a 24 MP shot then lands near the preparer's 25 MB source
    // cap. 92 is visually lossless at the 1600 px output and a third of
    // the bytes; dimensions stay untouched.
    final platform = _RecordingPickerPlatform(await writePluginFile());
    ImagePickerPlatform.instance = platform;
    final picker =
        ChatImagePicker(tempDirectory: () async => tmp, isIOS: true);
    await picker.pickFromGallery();
    expect(platform.options!.imageQuality, 92);
    expect(platform.options!.maxWidth, isNull);
    expect(platform.options!.maxHeight, isNull);
  });

  test('stages the pick under <temp>/chat_picks and nowhere else', () async {
    final pluginPath = await writePluginFile();
    ImagePickerPlatform.instance = _RecordingPickerPlatform(pluginPath);
    final picker = ChatImagePicker(tempDirectory: () async => tmp);

    final path = (await picker.pickFromGallery())!;

    expect(p.dirname(path), p.join(tmp.path, ChatImagePicker.folderName));
    expect(File(path).lengthSync(), 4096, reason: 'bytes untouched');
    expect(File(pluginPath).existsSync(), isFalse,
        reason: 'the plugin temp copy is removed once staged');
    expect(tmp.listSync().map((e) => p.basename(e.path)).toList(),
        [ChatImagePicker.folderName],
        reason: 'no shop_images or other folder is created');
    expect(ChatImagePicker.ownsPath(path), isTrue);
    expect(ChatImagePicker.ownsPath('/var/mobile/Documents/shop_images/1.jpg'),
        isFalse);
  });

  test('a cancelled pick returns null and writes nothing', () async {
    ImagePickerPlatform.instance = _RecordingPickerPlatform(null);
    final picker = ChatImagePicker(tempDirectory: () async => tmp);
    expect(await picker.pickFromGallery(), isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('discard deletes only chat-owned picks', () async {
    final owned = File(p.join(tmp.path, ChatImagePicker.folderName, 'a.jpg'))
      ..createSync(recursive: true);
    final foreign = File(p.join(tmp.path, 'other', 'b.jpg'))
      ..createSync(recursive: true);
    await ChatImagePicker.discard(owned.path);
    await ChatImagePicker.discard(foreign.path);
    await ChatImagePicker.discard(null);
    expect(owned.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
  });

  test('ChatScreen no longer routes photos through ImagePickerService', () {
    // Source guard in the repo's existing style (voice_signed_url_freshness_test):
    // the generic picker re-encodes at 1024/q85, crops, then compresses to a
    // 500 px short edge, so ChatImagePreparer's 1600 long edge was unreachable.
    final screen = File(
      'lib/features/chat/presentation/screens/chat_screen.dart',
    ).readAsStringSync();
    expect(screen, isNot(contains('_imagePicker.pickImage(')));
    expect(screen, isNot(contains('crop: true')));
    expect(screen, contains('chatImagePickerProvider'));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/chat/chat_image_picker_test.dart`
Expected: compile error `Target of URI doesn't exist: 'package:attune/features/chat/domain/services/chat_image_picker.dart'`. (Verified against image_picker 1.2.1 / platform interface 2.11.1 in pubspec.lock: `ImagePicker.pickImage` forwards to `ImagePickerPlatform.getImageFromSource(source:, options: ImagePickerOptions(maxWidth, maxHeight, imageQuality, requestFullMetadata))`.)

- [ ] **Step 3: Write `ChatImagePicker`**

`lib/features/chat/domain/services/chat_image_picker.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Picks a photo for chat at FULL resolution and stages it in a chat-owned
/// temp folder.
///
/// Deliberately not `ImagePickerService`: that picker re-encodes at
/// 1024 px / q85, crops, then compresses to a 500 px SHORT edge and copies
/// every pick into Documents/shop_images for good (chat review #20, #27).
/// Here the OS hands over the original bytes and `ChatImagePreparer` is the
/// single resize (1600 long edge) + EXIF strip + encode pass. The staged
/// copy lives under the OS temp dir and is deleted by the controller once
/// preparation has produced the upload file, or when a failed send is
/// removed ([discard]).
class ChatImagePicker {
  ChatImagePicker({
    ImagePicker? picker,
    Future<Directory> Function()? tempDirectory,
    bool? isIOS,
  }) : _picker = picker ?? ImagePicker(),
       _tempDirectory = tempDirectory ?? getTemporaryDirectory,
       _isIOS = isIOS ?? Platform.isIOS;

  final ImagePicker _picker;
  final Future<Directory> Function() _tempDirectory;
  final bool _isIOS;

  static const String folderName = 'chat_picks';

  /// Null when the person backed out of the OS picker.
  Future<String?> pickFromGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      // No maxWidth / maxHeight: either makes the plugin scale before the
      // preparer sees the bytes. Android then hands over the untouched
      // original (image_picker_android skips its ImageResizer entirely
      // when nothing is set; the preparer bakes the EXIF orientation).
      // iOS ALWAYS re-encodes through UIImage — HEIC and all become JPEG
      // — at quality 1.0 when none is given, where a 24 MP shot lands
      // near the preparer's 25 MB source cap; 92 is visually lossless at
      // the 1600 px output and a third of the bytes. Not on Android: a
      // quality there switches the resizer on.
      imageQuality: _isIOS ? 92 : null,
      requestFullMetadata: false,
    );
    if (picked == null) return null;

    final dir = Directory(p.join((await _tempDirectory()).path, folderName));
    await dir.create(recursive: true);
    final extension = p.extension(picked.path);
    final target = p.join(
      dir.path,
      'pick_${DateTime.now().microsecondsSinceEpoch}'
      '${extension.isEmpty ? '.jpg' : extension}',
    );
    await picked.saveTo(target);
    // The plugin's own temp copy is ours to drop now; best effort.
    try {
      final source = File(picked.path);
      if (source.path != target && await source.exists()) await source.delete();
    } catch (_) {}
    return target;
  }

  /// True only for files this picker staged. A path handed to
  /// `sendImageMessage` by another feature (a place photo, a share) is never
  /// deleted by chat.
  static bool ownsPath(String? path) =>
      path != null && p.split(path).contains(folderName);

  /// Deletes a staged pick. No-op for paths chat does not own.
  static Future<void> discard(String? path) async {
    if (!ownsPath(path)) return;
    try {
      final file = File(path!);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort temp cleanup; the OS purges tmp eventually.
    }
  }
}

final chatImagePickerProvider = Provider<ChatImagePicker>(
  (ref) => ChatImagePicker(),
);
```

- [ ] **Step 4: Rewrite `_attachImage` in `chat_screen.dart`**

Find `Future<void> _attachImage() async {` and replace the method body up to (not including) `Future<void> _attachVideo()` with:

```dart
  Future<void> _attachImage() async {
    // Chat-only picker: original bytes, staged under tmp/chat_picks, no
    // crop/compress pass before ChatImagePreparer (chat review #20, #27).
    final pickedPath = await ref.read(chatImagePickerProvider).pickFromGallery();
    if (pickedPath == null || !mounted) return;

    // Full-screen preview + caption, shown unconditionally after every
    // pick — matches WhatsApp/iMessage's pick-then-caption flow. Null
    // means the user backed out (closed the screen) rather than sending.
    final caption = await context.pushNamed<String>(
      'imageCaption',
      extra: pickedPath,
    );
    if (caption == null || !mounted) {
      unawaited(ChatImagePicker.discard(pickedPath));
      return;
    }

    await _clearDraft();
    // sendImageMessage has no replyToMessageId/quotedText params (image
    // replies are out of scope), so any pending reply target would silently
    // survive this send and get attached to the NEXT text message instead —
    // clear it here so the "Replying to..." strip never outlives the reply
    // it was showing.
    _clearReplyTarget();
    // sendImageMessage takes the RAW picked path and shows the optimistic
    // bubble before running ChatImagePreparer's compression itself (see its
    // own doc comment).
    await ref
        .read(chatControllerProvider(widget.conversation).notifier)
        .sendImageMessage(
          localPath: pickedPath,
          caption: caption,
          onOptimisticMessage: (_) => _scrollToLatest(),
        );
  }

```

Add the import `import 'package:attune/features/chat/domain/services/chat_image_picker.dart';` next to the other chat imports. Keep `final _imagePicker = ImagePickerService();` (still used by `_attachVideo`).

- [ ] **Step 5: Run the picker test**

Run: `flutter test test/features/chat/chat_image_picker_test.dart`
Expected: 6 tests pass.

- [ ] **Step 6: Write the failing resolution test (the preparer is now reachable)**

`test/features/chat/chat_image_preparer_resolution_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('res'));
  tearDown(() => dir.delete(recursive: true));

  test('a 12 MP photo comes out at a 1600 px long edge, under 800 KB', () async {
    // 4000x3000 with a gradient so JPEG has real work to do.
    final src = img.Image(width: 4000, height: 3000);
    for (final px in src) {
      px
        ..r = px.x % 256
        ..g = px.y % 256
        ..b = (px.x + px.y) % 256;
    }
    final file = File('${dir.path}/big.jpg')
      ..writeAsBytesSync(img.encodeJpg(src, quality: 90));

    final out = await const ChatImagePreparer().prepare(file.path);

    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect(decoded.width, 1600);
    expect(decoded.height, 1200);
    expect(out.byteSize, lessThanOrEqualTo(ChatImagePreparer.maxBytes));
    expect(out.mimeType, 'image/jpeg');
  });

  test('a portrait 3000x4000 keeps its orientation at 1200x1600', () async {
    final src = img.Image(width: 3000, height: 4000);
    final file = File('${dir.path}/tall.jpg')
      ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
    final out = await const ChatImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (1200, 1600));
  });

  test('a small photo is not upscaled', () async {
    final src = img.Image(width: 640, height: 480);
    final file = File('${dir.path}/small.jpg')
      ..writeAsBytesSync(img.encodeJpg(src));
    final out = await const ChatImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (640, 480));
  });

  test('a HEIC original is rejected as unsupported, not crashed on',
      () async {
    // ISO-BMFF 'ftyp' box with major brand 'heic'. iOS never hands this
    // over (image_picker_ios re-encodes every pick to JPEG/PNG); Android
    // does when the gallery stores HEIF and no size/quality option is set,
    // which is exactly how ChatImagePicker asks. The preparer must say
    // "unsupported", not throw from the decoder.
    final bytes = <int>[
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size, 'ftyp'
      0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00, // 'heic', minor
      0x6D, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63, // compatible brands
      ...List<int>.filled(64, 0),
    ];
    final file = File('${dir.path}/photo.heic')..writeAsBytesSync(bytes);
    await expectLater(
      const ChatImagePreparer().prepare(file.path),
      throwsA(isA<ChatImageRejected>()
          .having((e) => e.code, 'code', 'media_type_unsupported')),
    );
  });

  test('the preparer probes the header and keeps the full decode off the UI isolate',
      () {
    // With full-resolution originals now reaching it (#20), a package:image
    // decode of a 12 MP JPEG on the UI isolate is seconds of frozen app per
    // photo. Dimensions come from the container header; the only full
    // Dart decode is the fallback encoder, in a worker isolate.
    final src = File(
      'lib/features/chat/domain/services/chat_image_preparer.dart',
    ).readAsStringSync();
    final prepare = src.substring(
      src.indexOf('Future<PreparedChatImage> prepare('),
      src.indexOf('({int width, int height}) _longestEdgeTarget('),
    );
    expect(prepare, contains('startDecode('));
    expect(prepare.indexOf('startDecode('),
        lessThan(prepare.indexOf('FlutterImageCompress.compressAndGetFile')));
    expect(prepare, isNot(contains('img.decodeImage(')),
        reason: 'the full decode lives in the isolate worker only');
    expect(prepare, contains('Isolate.run('));
    expect(src, contains('img.bakeOrientation('),
        reason: 'an untouched Android original carries its orientation in EXIF');
  });
}
```

- [ ] **Step 7: Run it; the last test fails**

Run: `flutter test test/features/chat/chat_image_preparer_resolution_test.dart`
Expected: the four image tests pass (the preparer already produces 1600 px; the first one is slow — tens of seconds — because today `prepare` decodes the 12 MP fixture with package:image on the calling isolate, which is the point of the next step); `the preparer probes the header …` fails on `contains('startDecode(')`. If `byteSize` exceeds 800 KB, the Dart fallback's quality (60) is too high for this gradient: lower the fixture's noise (use `px.x ~/ 16 % 256`) rather than changing production.

- [ ] **Step 7b: Header-only probe; Dart fallback in a worker isolate (`chat_image_preparer.dart`)**

Today `prepare()` runs `img.decodeImage(bytes)` to validate and measure the source before the native plugin ever sees it. That was invisible while the picker fed it 500 px thumbnails; with originals it is a multi-second UI freeze per photo on the controller's isolate (`_prepareAndAttemptSend` awaits `const ChatImagePreparer().prepare(...)` directly). Keep every rejection code and both encoder paths; move the pixels off the UI thread.

Add `import 'dart:isolate';` to the imports. Replace

```dart
    // Decode fully to validate the file really is a decodable image and to
    // guard against decompression bombs before we ever hand it to the encoder.
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const ChatImageRejected('media_decode_failed');
    if (decoded.width * decoded.height > maxDecodePixels) {
      throw const ChatImageRejected('media_dimensions_excessive');
    }
```

with

```dart
    // Header-only probe (no pixel decode): full-resolution originals reach
    // this code now (chat review #20), and package:image decoding a 12 MP
    // JPEG on the UI isolate froze the app for seconds per photo. SOF/IHDR/
    // VP8 headers give the dimensions for the bomb guard and the resize
    // target; the native plugin decodes natively (sampled) below and the
    // pure-Dart fallback decodes in a worker isolate.
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) throw const ChatImageRejected('media_decode_failed');
    if (info.width * info.height > maxDecodePixels) {
      throw const ChatImageRejected('media_dimensions_excessive');
    }
```

change the `_longestEdgeTarget(` call's arguments from `decoded.width, decoded.height,` to `info.width, info.height,`, and replace the fallback block

```dart
    // Last resort: hard-resize with the pure-Dart encoder, then re-check.
    final resized = _resizeLongestEdge(decoded, maxDimension);
    // The native path drops EXIF (keepExif:false); the pure-Dart encoder
    // would copy it — including GPS — so it's cleared here too.
    resized.exif = img.ExifData();
    final jpeg = img.encodeJpg(resized, quality: 60);
    if (jpeg.lengthInBytes <= maxBytes) {
```

with

```dart
    // Last resort: the pure-Dart path, in a worker isolate so the UI keeps
    // drawing. It bakes the EXIF orientation first (an untouched Android
    // original carries it there; the native path does the same), resizes,
    // and clears EXIF — the encoder would otherwise copy it, GPS included.
    final jpeg = await Isolate.run(
      () => _dartFallbackJpeg(bytes, maxDimension),
    );
    if (jpeg == null) throw const ChatImageRejected('media_decode_failed');
    if (jpeg.lengthInBytes <= maxBytes) {
```

and add, above `class ChatImagePreparer` (top level, so the isolate entry captures nothing but its arguments):

```dart
/// Pure-Dart fallback encoder. Runs in a worker isolate (Isolate.run): no
/// platform channels, no `this`. Null when the bytes do not decode.
Uint8List? _dartFallbackJpeg(Uint8List bytes, int longest) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = const ChatImagePreparer()._resizeLongestEdge(
    img.bakeOrientation(decoded),
    longest,
  );
  resized.exif = img.ExifData();
  return img.encodeJpg(resized, quality: 60);
}
```

(`img.findDecoderForData`, `Decoder.startDecode` → `DecodeInfo.width/height`, and `img.bakeOrientation` are all in image 4.3.0, pubspec.lock. `_resizeLongestEdge` stays an instance method; same-library private access is fine.) What is NOT changed: the rejection codes and their order, `maxSourceBytes`/`maxDecodePixels`/`maxDimension`/`maxBytes`, the native quality ladder, EXIF stripping on both paths, `_tempTargetPath`.

Run: `flutter test test/features/chat/chat_image_preparer_resolution_test.dart test/features/chat/chat_image_preparer_test.dart test/features/chat/chat_image_preparer_exif_test.dart`
Expected: all pass, and the 12 MP case now completes in a few seconds (the decode runs in a worker isolate; the test host still uses the Dart encoder).

- [ ] **Step 8: Write the failing cleanup test (#27 — no copy survives the send)**

`test/features/chat/chat_image_pick_cleanup_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(tempDir.path, 'Documents');
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pick_cleanup');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });
  tearDown(() => tempDir.delete(recursive: true));

  Future<String> stagePick(String name, List<int> bytes) async {
    final f = File(p.join(tempDir.path, ChatImagePicker.folderName, name))
      ..createSync(recursive: true);
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 400));

  test('the staged pick is deleted once the prepared file exists; nothing lands in Documents',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final raw = await stagePick(
      'pick_1.jpg',
      img.encodeJpg(img.Image(width: 64, height: 48)),
    );

    await controller.sendImageMessage(localPath: raw);
    await settle();

    final sent = container.read(chatControllerProvider(convo)).messages.single;
    expect(sent.status, MessageStatus.sent);
    expect(File(raw).existsSync(), isFalse, reason: 'raw pick discarded');
    expect(Directory(p.join(tempDir.path, 'Documents')).existsSync(), isFalse,
        reason: 'no Documents/shop_images copy');
    expect(repo.mediaCallCount, 2, reason: 'one intent, one upload');
  });

  test('a pick that fails preparation is kept for retry and deleted on remove',
      () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final raw = await stagePick('pick_2.jpg', 'not an image'.codeUnits);
    await controller.sendImageMessage(localPath: raw);
    await settle();

    final failed = container.read(chatControllerProvider(convo)).messages.single;
    expect(failed.status, MessageStatus.failed);
    expect(File(raw).existsSync(), isTrue, reason: 'retry needs the source');

    await controller.removeFailedMessage(failed);
    expect(File(raw).existsSync(), isFalse);
    expect(container.read(chatControllerProvider(convo)).messages, isEmpty);
  });

  test('a path chat does not own (place photo) is never deleted', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final foreign = File(p.join(tempDir.path, 'places', 'photo.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 32, height: 32)));

    await controller.sendImageMessage(localPath: foreign.path);
    await settle();

    expect(foreign.existsSync(), isTrue);
  });
}
```

- [ ] **Step 9: Run it to verify the first test fails**

Run: `flutter test test/features/chat/chat_image_pick_cleanup_test.dart`
Expected: test 1 fails at `expect(File(raw).existsSync(), isFalse)` ("raw pick discarded"); test 2 fails at the post-remove `isFalse`; test 3 passes.

- [ ] **Step 10: Discard the staged pick in `chat_state.dart`**

In `_prepareAndAttemptSend`, directly after the line `await ref.read(chatCacheServiceProvider).putOutbox(user.id, prepared);` (the comment above it says "Commit the prepared paths before upload"), add:

```dart
      // The prepared file is now the durable source; the staged pick (only
      // paths ChatImagePicker owns — never a place photo or a share) can go.
      if (prepared.mediaType == 'image') {
        await ChatImagePicker.discard(preparing.localMediaPath);
      }
```

In `removeFailedMessage`, directly after
```dart
    if (pending?.requiresPreparation != true) {
      await _deleteStagedMedia(message.localMediaPath);
    }
```
add:
```dart
    // A preparation-stage image whose source chat itself staged is also
    // gone for good once the person removes the failed row (#27).
    await ChatImagePicker.discard(pending?.localMediaPath);
    await ChatImagePicker.discard(message.localMediaPath);
```

Add `import 'package:attune/features/chat/domain/services/chat_image_picker.dart';` to chat_state.dart's imports.

- [ ] **Step 11: Run the cleanup, EXIF, preparer and chat-screen suites**

Run: `flutter test test/features/chat/chat_image_pick_cleanup_test.dart test/features/chat/chat_image_preparer_exif_test.dart test/features/chat/chat_image_preparer_test.dart test/features/chat/chat_image_picker_test.dart test/features/chat/chat_screen_header_test.dart test/features/chat/chat_controller_test.dart`
Expected: all pass.

- [ ] **Step 12: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/domain/services/chat_image_picker.dart lib/features/chat/domain/services/chat_image_preparer.dart lib/features/chat/presentation/screens/chat_screen.dart lib/features/chat/presentation/state/chat_state.dart test/features/chat/chat_image_picker_test.dart test/features/chat/chat_image_pick_cleanup_test.dart test/features/chat/chat_image_preparer_resolution_test.dart | grep -E '^\s*(error|warning) '` (expect no output); no commit (the owner commits).

---

### Task 4: Accept every ISO-BMFF `ftyp` brand (#29)

**Files:**
- Modify: `lib/features/chat/domain/services/chat_video_preparer.dart` (`debugSniffMime` only)
- Modify: `test/features/chat/chat_video_preparer_test.dart` (`MIME sniffing` group)

**Interfaces:**
- Consumes/produces: `static String? debugSniffMime(List<int> bytes)` → `'video/quicktime'` for brand `qt  `, `'video/mp4'` for any other printable 4-char brand, `null` when there is no `ftyp` box. The preparer still transcodes everything to `video/mp4` before requesting an intent, so the server allowlist (`create_chat_media_upload_intent`: `video/mp4` only) is unaffected — ruling: no server change.

- [ ] **Step 1: Replace the wrong-behaviour test and add the brand cases**

In `test/features/chat/chat_video_preparer_test.dart`, group `'MIME sniffing'`: delete the test `'unrecognized major brand returns null (caller rejects)'` (it pinned the defect) and add:

```dart
    List<int> ftyp(String brand) => <int>[
      0x00, 0x00, 0x00, 0x18,
      0x66, 0x74, 0x79, 0x70, // 'ftyp'
      ...brand.codeUnits, // major brand
      0x00, 0x00, 0x02, 0x00,
    ];

    test('common MP4 brands beyond the old allowlist are accepted', () {
      // ffmpeg -movflags, HEVC exports, 3GPP phones, older encoders.
      for (final brand in [
        'isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42',
        'avc1', 'hev1', 'hvc1', 'M4V ', 'M4A ', 'f4v ', 'dash', '3gp4',
        '3gp5', '3gp6', '3g2a', 'mmp4', 'NDXC',
      ]) {
        expect(ChatVideoPreparer.debugSniffMime(ftyp(brand)), 'video/mp4',
            reason: 'brand "$brand"');
      }
    });

    test('QuickTime keeps its own MIME', () {
      expect(ChatVideoPreparer.debugSniffMime(ftyp('qt  ')), 'video/quicktime');
    });

    test('a non-printable brand is still refused (not an ISO-BMFF video)', () {
      expect(ChatVideoPreparer.debugSniffMime(ftyp('\x00\x01\x02\x03')), isNull);
    });

    test('bytes with no ftyp box are refused', () {
      expect(ChatVideoPreparer.debugSniffMime('RIFF....WEBPVP8 '.codeUnits), isNull);
    });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart --plain-name "common MP4 brands"`
Expected: FAIL — `Expected: 'video/mp4' Actual: <null>` with reason `brand "iso2"`.

- [ ] **Step 3: Relax the sniff**

In `chat_video_preparer.dart`, replace the `switch (brand)` block inside `debugSniffMime` with:

```dart
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (brand == 'qt  ') return 'video/quicktime';
    // Any other ISO base media file format brand (isom, iso2..iso6, mp41,
    // mp42, avc1, hev1, M4V, 3gp*, dash, f4v, ...) is a container the
    // transcode step normalises to mp4 anyway; refusing uncommon brands only
    // rejected valid clips from ffmpeg/HEVC exports (chat review #29). The
    // brand must still be four printable ASCII characters, so random bytes
    // that happen to spell 'ftyp' at offset 4 are not treated as video.
    final printable = brand.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);
    return printable ? 'video/mp4' : null;
```

- [ ] **Step 4: Run the whole preparer suite**

Run: `flutter test test/features/chat/chat_video_preparer_test.dart`
Expected: all pass (including `rejects a file with no ftyp box`).

- [ ] **Step 5: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/domain/services/chat_video_preparer.dart test/features/chat/chat_video_preparer_test.dart | grep -E '^\s*(error|warning) '`; no commit (the owner commits).

---

### Task 5: Classify storage failures; media-aware copy (#26)

**Files:**
- Modify: `lib/features/chat/utils/chat_error.dart`
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`_handleSendFailure`: one expression)
- Create: `test/features/chat/chat_error_storage_test.dart`

**Interfaces:**
- Consumes: `StorageException(message, {error, statusCode: String?})` (storage_client 2.5.5), `http.ClientException` (package:http), `ChatError.isPermanent/isTransient`, `_handleSendFailure(userId, pending, ChatError)`.
- Produces: `ChatError.from(Object? error, {String? correlationId, String? mediaType})`, `ChatError.mediaType`, `ChatError forMedia(String? mediaType)`, `static ChatErrorCategory categorizeStorageStatus(String? statusCode)` (visible for tests). Mapping: no/non-numeric status → `unavailable`; 429 → `rateLimited`; ≥ 500 → `unavailable`; 401/409 → `unavailable` (token refresh / fresh intent on retry); any other 4xx (400, 403, 413, 415, 422) → `mediaRejected` (permanent); `http.ClientException` → `offline`.

- [ ] **Step 1: Write the failing tests**

`test/features/chat/chat_error_storage_test.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  group('ChatError.from(StorageException)', () {
    ChatError from(String? status) =>
        ChatError.from(StorageException('x', statusCode: status));

    test('5xx and transport-level failures are transient', () {
      for (final s in ['500', '502', '503', '504', null, 'timeout']) {
        final e = from(s);
        expect(e.category, ChatErrorCategory.unavailable, reason: 'status $s');
        expect(e.isTransient, isTrue);
        expect(e.isPermanent, isFalse);
      }
    });

    test('429 is rate limited (transient)', () {
      expect(from('429').category, ChatErrorCategory.rateLimited);
    });

    test('401 and 409 retry with a fresh token / intent', () {
      expect(from('401').category, ChatErrorCategory.unavailable);
      expect(from('409').category, ChatErrorCategory.unavailable);
    });

    test('policy, size and type rejections are permanent', () {
      for (final s in ['400', '403', '413', '415', '422']) {
        final e = from(s);
        expect(e.category, ChatErrorCategory.mediaRejected, reason: 'status $s');
        expect(e.isPermanent, isTrue);
      }
    });

    test('a dropped socket from the uploader reads as offline', () {
      final e = ChatError.from(http.ClientException('Connection closed'));
      expect(e.category, ChatErrorCategory.offline);
    });

    test('copy names the kind of media', () {
      final rejected = StorageException('x', statusCode: '413');
      expect(ChatError.from(rejected, mediaType: 'audio').toUserMessage(),
          'That voice message could not be sent. Try recording it again.');
      expect(ChatError.from(rejected, mediaType: 'video').toUserMessage(),
          'That video could not be sent. Try a different one.');
      expect(ChatError.from(rejected, mediaType: 'image').toUserMessage(),
          'That image could not be sent. Try a different one.');
      expect(ChatError.from(rejected).toUserMessage(),
          'That image could not be sent. Try a different one.');
      expect(ChatError.from(rejected).forMedia('video').toUserMessage(),
          'That video could not be sent. Try a different one.');
    });
  });

  group('a storage 503 during a voice upload', () {
    const userId = 'user-a';
    const relId = 'rel-1';
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('storage_err');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    });
    tearDown(() => tempDir.delete(recursive: true));

    test('queues for retry instead of failing the message', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] =
            const StorageException('Service Unavailable', statusCode: '503');
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'v.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendVoiceMessage(
          localPath: path, durationMs: 1500, waveform: const [1, 2, 3]);

      final state = container.read(chatControllerProvider(convo));
      expect(state.messages.single.status, MessageStatus.queued,
          reason: 'a 503 is the server\'s problem, not the recording\'s');
      expect(state.error,
          'Chat is temporarily unavailable. Please try again shortly.');
    });

    test('a 413 fails the message with voice-specific copy', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] =
            const StorageException('Payload Too Large', statusCode: '413');
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'big.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendVoiceMessage(
          localPath: path, durationMs: 1500, waveform: const [1, 2, 3]);

      final state = container.read(chatControllerProvider(convo));
      expect(state.messages.single.status, MessageStatus.failed);
      expect(state.error,
          'That voice message could not be sent. Try recording it again.');
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/chat_error_storage_test.dart`
Expected: compile error on the named parameter `mediaType` / `forMedia`; after temporarily commenting those two tests, `5xx … are transient` fails with `Expected: ChatErrorCategory.unavailable Actual: ChatErrorCategory.mediaRejected`.

- [ ] **Step 3: Implement in `chat_error.dart`**

Add `import 'package:http/http.dart' as http;`. Change the class header and constructor:

```dart
class ChatError implements Exception {
  ChatError(
    this.category, {
    String? correlationId,
    this.cause,
    this.mediaType,
  }) : correlationId = correlationId ?? newCorrelationId();

  final ChatErrorCategory category;
  final String correlationId;
  final Object? cause;

  /// 'image' | 'audio' | 'video' | null — only shapes the copy, never the
  /// category.
  final String? mediaType;

  /// The same error, worded for [mediaType].
  ChatError forMedia(String? mediaType) =>
      mediaType == null || mediaType == this.mediaType
          ? this
          : ChatError(
            category,
            correlationId: correlationId,
            cause: cause,
            mediaType: mediaType,
          );
```

Change the factory signature to `factory ChatError.from(Object? error, {String? correlationId, String? mediaType})`; pass `mediaType: mediaType` into every `ChatError(...)` it constructs (there are seven). Replace the `StorageException` branch and add the `http.ClientException` branch before it:

```dart
    if (error is http.ClientException) {
      // The streaming uploader surfaces a dropped socket this way.
      return ChatError(
        ChatErrorCategory.offline,
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }

    if (error is StorageException) {
      return ChatError(
        categorizeStorageStatus(error.statusCode),
        correlationId: correlationId,
        cause: error,
        mediaType: mediaType,
      );
    }
```

Add the static mapper:

```dart
  /// Storage replies by HTTP status. Only a 4xx the client caused is a
  /// permanent rejection; everything else can succeed on retry (chat review
  /// #26 — a 503 used to fail the send on the first attempt).
  @visibleForTesting
  static ChatErrorCategory categorizeStorageStatus(String? statusCode) {
    final code = int.tryParse(statusCode ?? '');
    if (code == null) return ChatErrorCategory.unavailable;
    if (code == 429) return ChatErrorCategory.rateLimited;
    if (code >= 500) return ChatErrorCategory.unavailable;
    // 401: token refresh then retry. 409: the retry requests a fresh intent
    // (a new object key), so a duplicate-object reply is not final either.
    if (code == 401 || code == 409) return ChatErrorCategory.unavailable;
    if (code >= 400) return ChatErrorCategory.mediaRejected;
    return ChatErrorCategory.unknown;
  }
```

(`@visibleForTesting` needs `import 'package:flutter/foundation.dart' show visibleForTesting;`.) Replace the `mediaRejected` case in `toUserMessage()`:

```dart
      case ChatErrorCategory.mediaRejected:
        switch (mediaType) {
          case 'audio':
            return "That voice message could not be sent. Try recording it again.";
          case 'video':
            return "That video could not be sent. Try a different one.";
          default:
            return "That image could not be sent. Try a different one.";
        }
```

- [ ] **Step 4: Word the banner by media type in `chat_state.dart`**

In `_handleSendFailure`, change `error: error.toUserMessage(),` to `error: error.forMedia(pending.mediaType).toUserMessage(),`.

- [ ] **Step 5: Run**

Run: `flutter test test/features/chat/chat_error_storage_test.dart test/features/chat/chat_state_send_voice_message_test.dart test/features/chat/chat_state_send_video_message_test.dart test/features/chat/chat_edge_cases_test.dart`
Expected: all pass.

- [ ] **Step 6: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/utils/chat_error.dart lib/features/chat/presentation/state/chat_state.dart test/features/chat/chat_error_storage_test.dart | grep -E '^\s*(error|warning) '`; no commit (the owner commits).

---

### Task 6: Signed URLs never cache a failure; refresh before expiry; tap to retry (#22)

**Files:**
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`signedMediaUrlProvider` + new `signedMediaUrlRefreshAfterProvider`)
- Modify: `lib/features/chat/presentation/widgets/resolved_media_url.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (voice `resolveAudioUrl` closure only)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`FakeChatRepository.signMediaUrlFailuresBeforeSuccess`)
- Modify: `test/features/chat/voice_signed_url_freshness_test.dart` (one assertion string — says so below)
- Create: `test/features/chat/signed_media_url_retry_test.dart`

**Interfaces:**
- Consumes: `ChatRepository.createSignedMediaUrl(String key, {bool forceRefresh})` → `String?` (null when every candidate failed; the repository swallows exceptions), `chatConnectivityProvider` (StreamProvider<bool>, `chat_experience_providers.dart`), `SupabaseChatRepository._signedUrlTtl` 600 s / `_signedUrlSafetyMargin` 60 s.
- Produces:
  - `final signedMediaUrlProvider = FutureProvider.autoDispose.family<String, String>` — resolves or THROWS `SignedMediaUrlUnavailable(mediaKey)`; on success calls `ref.keepAlive()` and re-resolves itself after `signedMediaUrlRefreshAfterProvider` (default 8 minutes); rebuilds when connectivity flips (watches `chatConnectivityProvider`); retries twice in-provider with 400 ms / 1200 ms backoff before throwing.
  - `final signedMediaUrlRefreshAfterProvider = Provider<Duration>((_) => const Duration(minutes: 8));`
  - `class SignedMediaUrlUnavailable implements Exception { final String mediaKey; }`
  - `ResolvedMediaUrl`: unchanged constructor; the `error` widget is wrapped in a tap target that calls `ref.invalidate(signedMediaUrlProvider(key))` (Semantics label "Tap to retry").
  - `FakeChatRepository.signMediaUrlFailuresBeforeSuccess` (int, default 0): the first N `createSignedMediaUrl` calls return null, then `signMediaUrls` applies.

- [ ] **Step 1: Add the fake seam**

In `FakeChatRepository` (chat_test_harness.dart) replace `createSignedMediaUrl` with:

```dart
  /// How many leading [createSignedMediaUrl] calls return null before the
  /// normal [signMediaUrls] behaviour applies — models "offline once, then
  /// back" for the signed-URL retry tests.
  int signMediaUrlFailuresBeforeSuccess = 0;

  @override
  Future<String?> createSignedMediaUrl(
    String mediaKey, {
    bool forceRefresh = false,
  }) async {
    signedUrlRequests.add(mediaKey);
    if (signMediaUrlFailuresBeforeSuccess > 0) {
      signMediaUrlFailuresBeforeSuccess--;
      return null;
    }
    // Null by default preserves the behaviour every existing test was
    // written against (no URL resolves); tests that need a real one opt in
    // via [signMediaUrls].
    if (!signMediaUrls) return null;
    return 'https://signed.test/$mediaKey?token=abc';
  }
```

- [ ] **Step 2: Write the failing tests**

`test/features/chat/signed_media_url_retry_test.dart`:

```dart
import 'dart:async';

import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

const key = 'chat-media/photo.jpg';

ProviderContainer makeContainer(
  FakeChatRepository repo, {
  StreamController<bool>? connectivity,
  Duration refreshAfter = const Duration(minutes: 8),
}) {
  final container = ProviderContainer(
    overrides: [
      chatRepositoryProvider.overrideWithValue(repo),
      signedMediaUrlRefreshAfterProvider.overrideWithValue(refreshAfter),
      chatConnectivityProvider.overrideWith(
        (ref) => connectivity?.stream ?? Stream<bool>.value(true),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a failed resolution is not cached: invalidate → next read succeeds',
      () async {
    final repo = FakeChatRepository(currentUserId: 'u1')
      ..signMediaUrls = true
      ..signMediaUrlFailuresBeforeSuccess = 3; // > in-provider retries
    final container = makeContainer(repo);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(signedMediaUrlProvider(key).future),
      throwsA(isA<SignedMediaUrlUnavailable>()),
    );
    expect(repo.signedUrlRequests.length, 3, reason: '1 try + 2 retries');

    container.invalidate(signedMediaUrlProvider(key));
    expect(await container.read(signedMediaUrlProvider(key).future),
        'https://signed.test/$key?token=abc');
  });

  test('with no listener left, an error is disposed and the next mount re-asks',
      () async {
    final repo = FakeChatRepository(currentUserId: 'u1')
      ..signMediaUrls = true
      ..signMediaUrlFailuresBeforeSuccess = 3;
    final container = makeContainer(repo);

    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    await expectLater(container.read(signedMediaUrlProvider(key).future),
        throwsA(isA<SignedMediaUrlUnavailable>()));
    sub.close(); // the tile scrolled away
    await Future<void>.delayed(Duration.zero);

    final sub2 = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub2.close);
    expect(await container.read(signedMediaUrlProvider(key).future),
        contains('token=abc'));
  });

  test('a success is kept alive across unmount/remount (no re-sign)', () async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final container = makeContainer(repo);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    await container.read(signedMediaUrlProvider(key).future);
    sub.close();
    await Future<void>.delayed(Duration.zero);
    final sub2 = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub2.close);
    await container.read(signedMediaUrlProvider(key).future);
    expect(repo.signedUrlRequests.length, 1);
  });

  test('re-signs itself before the token expires', () async {
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final container = makeContainer(
      repo,
      refreshAfter: const Duration(milliseconds: 60),
    );
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub.close);
    await container.read(signedMediaUrlProvider(key).future);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(repo.signedUrlRequests.length, greaterThanOrEqualTo(2));
  });

  test('connectivity returning re-resolves a broken tile', () async {
    // 4 failures: 3 for the first (online) build's try + 2 retries, 1 for
    // the offline rebuild (no retries offline), then success when online.
    final repo = FakeChatRepository(currentUserId: 'u1')
      ..signMediaUrls = true
      ..signMediaUrlFailuresBeforeSuccess = 4;
    final connectivity = StreamController<bool>.broadcast();
    addTearDown(connectivity.close);
    final container = makeContainer(repo, connectivity: connectivity);
    final sub = container.listen(signedMediaUrlProvider(key), (_, __) {});
    addTearDown(sub.close);
    await expectLater(container.read(signedMediaUrlProvider(key).future),
        throwsA(isA<SignedMediaUrlUnavailable>()));

    connectivity.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.signedUrlRequests.length, 4, reason: 'one try while offline');
    expect(container.read(signedMediaUrlProvider(key)).hasError, isTrue);

    connectivity.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await container.read(signedMediaUrlProvider(key).future),
        contains('token=abc'));
  });

  testWidgets('a broken tile is tappable and heals on tap', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'u1')
      ..signMediaUrls = true
      ..signMediaUrlFailuresBeforeSuccess = 3;
    String? built;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          home: ResolvedMediaUrl(
            signedMediaUrl: null,
            mediaKey: key,
            builder: (context, url) {
              built = url;
              return const Text('image');
            },
            loading: const Text('loading'),
            error: const Text('broken'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('broken'), findsOneWidget);
    expect(find.bySemanticsLabel('Tap to retry'), findsOneWidget);

    await tester.tap(find.text('broken'));
    await tester.pumpAndSettle();
    expect(find.text('image'), findsOneWidget);
    expect(built, contains('token=abc'));
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/features/chat/signed_media_url_retry_test.dart`
Expected: compile error `Undefined name 'signedMediaUrlRefreshAfterProvider'` / `SignedMediaUrlUnavailable`.

- [ ] **Step 4: Rewrite the provider in `chat_state.dart`**

Replace the `signedMediaUrlProvider` definition (and its doc comment) with:

```dart
/// Thrown by [signedMediaUrlProvider] when a storage key could not be
/// signed (offline, policy, missing object). Content-free.
class SignedMediaUrlUnavailable implements Exception {
  const SignedMediaUrlUnavailable(this.mediaKey);
  final String mediaKey;
  @override
  String toString() => 'SignedMediaUrlUnavailable';
}

/// How long a resolved signed URL is trusted before the provider re-signs
/// itself. Storage tokens live 10 minutes (SupabaseChatRepository); 8 keeps
/// a 2-minute margin for a slow download that started late.
final signedMediaUrlRefreshAfterProvider = Provider<Duration>(
  (ref) => const Duration(minutes: 8),
);

/// Resolves a signed URL for a chat media storage key on demand.
///
/// autoDispose + keepAlive-on-success (chat review #22): a resolution that
/// FAILED used to sit in a non-autoDispose family as `data(null)` for the
/// rest of the app session, so one photo opened in a tunnel stayed broken
/// until restart. Now a failure is an error state that lives only while a
/// tile listens, retries briefly in place, re-resolves when connectivity
/// returns (watched below) or on tap (ResolvedMediaUrl), and a success is
/// kept and refreshed before its token expires.
final signedMediaUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, mediaKey) async {
      // A flip offline → online rebuilds every listened member.
      final online = ref.watch(
        chatConnectivityProvider.select((state) => state.valueOrNull ?? true),
      );
      final repository = ref.watch(chatRepositoryProvider);

      // Brief in-place retry while online; offline, one try is enough (the
      // connectivity flip above is the retry).
      final backoff =
          online
              ? const [Duration(milliseconds: 400), Duration(milliseconds: 1200)]
              : const <Duration>[];
      String? url;
      for (var attempt = 0; attempt <= backoff.length; attempt++) {
        url = await repository.createSignedMediaUrl(mediaKey);
        if (url != null) break;
        if (attempt < backoff.length) await Future<void>.delayed(backoff[attempt]);
      }
      if (url == null) throw SignedMediaUrlUnavailable(mediaKey);

      final link = ref.keepAlive();
      final refresh = Timer(ref.read(signedMediaUrlRefreshAfterProvider), () {
        link.close();
        ref.invalidateSelf();
      });
      ref.onDispose(refresh.cancel);
      return url;
    });
```

Add `import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';` if not already imported (check: it may already be, for `chatConnectivityProvider`).

- [ ] **Step 5: Tap-to-retry in `resolved_media_url.dart`**

Replace the `build` body's family branch with:

```dart
    final resolved = ref.watch(signedMediaUrlProvider(key));
    return resolved.when(
      data: (url) => builder(context, url),
      loading: () => loading,
      error: (_, _) {
        // A stored URL (if any) is better than a broken tile; otherwise the
        // tile itself is the retry button (chat review #22).
        if (signedMediaUrl != null) return builder(context, signedMediaUrl!);
        return Semantics(
          button: true,
          label: 'Tap to retry',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.invalidate(signedMediaUrlProvider(key)),
            child: error,
          ),
        );
      },
    );
```

(`data` no longer needs `url ?? signedMediaUrl`: the provider never yields null now.)

- [ ] **Step 6: Keep the voice resolver's fallback (message_bubble.dart)**

In the voice `resolveAudioUrl` closure, replace

```dart
                  if (mediaKey != null) {
                    final resolved = await ref.read(
                      signedMediaUrlProvider(mediaKey).future,
                    );
                    return resolved ?? signedUrl;
                  }
```
with
```dart
                  if (mediaKey != null) {
                    // The provider throws when it cannot sign; the stored
                    // URL remains the fallback for a row that carries one.
                    final resolved = await ref
                        .read(signedMediaUrlProvider(mediaKey).future)
                        .then<String?>((url) => url, onError: (_) => null);
                    return resolved ?? signedUrl;
                  }
```

Then in `test/features/chat/voice_signed_url_freshness_test.dart`, the test `'voice playback falls back when re-signing returns null'` still asserts `contains('return resolved ?? signedUrl;')` — unchanged and still true. The widget test `'ResolvedMediaUrl falls back when re-signing returns null'` still passes through the new `error:` branch. No test edit needed here; if the first source test's `indexOf('},' …)` slice no longer contains `signedMediaUrlProvider` because the closure grew, widen that slice to `bubble.indexOf('return signedUrl;', start)` and say so in the test comment.

- [ ] **Step 7: Run**

Run: `flutter test test/features/chat/signed_media_url_retry_test.dart test/features/chat/voice_signed_url_freshness_test.dart test/features/chat/message_bubble_test.dart test/features/chat/chat_media_group_test.dart test/features/chat/voice_message_player_test.dart`
Expected: all pass.

- [ ] **Step 8: Grep for other readers**

Run: `grep -rn "signedMediaUrlProvider" lib --include='*.dart'`
Expected: only `chat_state.dart`, `resolved_media_url.dart`, `message_bubble.dart`. Any other `.future` reader must wrap with `.then((u) => u, onError: (_) => null)` as in Step 6.

- [ ] **Step 9: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/presentation/state/chat_state.dart lib/features/chat/presentation/widgets/resolved_media_url.dart lib/features/chat/presentation/widgets/message_bubble.dart test/features/chat/signed_media_url_retry_test.dart test/features/chat/support/chat_test_harness.dart | grep -E '^\s*(error|warning) '`; no commit (the owner commits).

---

### Task 7: Voice playback owned by a controller, not the bubble (#21)

**Files:**
- Create: `lib/features/chat/presentation/state/voice_playback_controller.dart`
- Create: `test/features/chat/support/fake_voice_engine.dart`
- Create: `test/features/chat/voice_playback_controller_test.dart`
- Modify: `lib/features/chat/presentation/widgets/voice_message_player.dart` (becomes a view; speed chip; loading ring)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`_ChatScreenState.initState` / `dispose`: stop playback when the route is disposed)
- Modify: `test/features/chat/voice_message_player_test.dart` (engine override + two new tests), `test/features/chat/voice_playback_audio_context_test.dart` (file path moved — says so)
- Unchanged: `lib/features/chat/presentation/providers/voice_playback_provider.dart` (`currentlyPlayingVoiceMessageIdProvider` stays the cross-media handshake with `VideoMessagePlayer`)

**Interfaces:**
- Consumes: `audioplayers` `AudioPlayer` (`onPositionChanged`, `onPlayerComplete`, `onPlayerStateChanged`, `play/pause/resume/stop/seek/setPlaybackRate/setAudioContext`), `currentlyPlayingVoiceMessageIdProvider`, `currentlyPlayingVideoMessageIdProvider`, `hapticsProvider` (`selection()`), `ChatLog.diagnostic`.
- Produces:
  - `abstract class VoicePlaybackEngine { Stream<Duration> get positions; Stream<void> get completions; Stream<bool> get playing; Future<void> setAudioContext(AudioContext context); Future<void> play(String source, {required bool isLocalFile, required double rate}); Future<void> pause(); Future<void> resume(); Future<void> stop(); Future<void> seek(Duration position); Future<void> setRate(double rate); Future<void> dispose(); }` — `setAudioContext` is the seam Plan 4 Task 3 hands to `AudioSessionCoordinator.beginPlayback(_engine.setAudioContext)`; the audio-context decision lives in the controller, not the engine.
  - `class AudioPlayersVoiceEngine implements VoicePlaybackEngine`
  - `class VoicePlaybackState { String? messageId; bool isPlaying; bool isLoading; Duration position; double rate; int failureCount; String? failedMessageId; }` with `isCurrent(id)`, `positionFor(id)`, `copyWith`, `static const idle`.
  - `typedef VoiceSourceResolver = Future<String?> Function();`
  - `class VoicePlaybackController extends StateNotifier<VoicePlaybackState> with WidgetsBindingObserver { Future<void> toggle(String messageId, VoiceSourceResolver resolve); Future<void> pause(); Future<void> seek(String messageId, Duration to); Future<void> cycleRate(); Future<void> stop(); static const rates = [1.0, 1.5, 2.0]; }`
  - `final voicePlaybackEngineProvider = Provider<VoicePlaybackEngine>` (override in tests), `final voicePlaybackStallAfterProvider = Provider<Duration>` (default 1500 ms), `final voicePlaybackControllerProvider = StateNotifierProvider<VoicePlaybackController, VoicePlaybackState>` (app scope, not autoDispose: one engine app-wide, matching the spec's app-wide one-at-a-time rule).
  - `VoiceMessagePlayer` keeps its constructor (`messageId, resolveAudioUrl, durationMs, waveform, foregroundColor, metadataColor, accentColor`) and gains `String? mediaKey` (used by Task 8).

Rulings recorded here:
- `audio_session` is not added: it is not in the pub cache (network + native session setup), and the spec rules out background/lock-screen playback, so the only interruption behaviour required is "UI follows reality and resume works". The engine forwards `onPlayerStateChanged`; the controller additionally runs a position **stall watchdog** (no position tick for `voicePlaybackStallAfterProvider` while `isPlaying`) that demotes the state to paused and pauses the engine, which covers phone calls/Siri on both platforms regardless of what the plugin reports. App backgrounding (`AppLifecycleState.paused`) pauses playback (spec: no background playback).
- "Leaving the chat screen stops playback" (spec) is preserved: `_ChatScreenState.dispose` stops the controller. Pushing the media viewer or a game over the chat does NOT stop it (the route is still alive), which is the WhatsApp behaviour.
- Speed: 1× / 1.5× / 2×, app-wide and remembered for the session (not persisted — YAGNI until someone asks).

- [ ] **Step 1: Write the fake engine**

`test/features/chat/support/fake_voice_engine.dart`:

```dart
import 'dart:async';

import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:audioplayers/audioplayers.dart';

/// Scriptable engine: records calls, lets tests push position/completion/
/// playing events as the OS would.
class FakeVoiceEngine implements VoicePlaybackEngine {
  final positionsController = StreamController<Duration>.broadcast();
  final completionsController = StreamController<void>.broadcast();
  final playingController = StreamController<bool>.broadcast();

  final List<String> calls = [];
  final List<AudioContext> contexts = [];
  String? lastSource;
  bool? lastIsLocalFile;
  double lastRate = 1.0;
  Duration? lastSeek;

  /// When set, the next [play] throws it.
  Object? nextPlayError;

  @override
  Stream<Duration> get positions => positionsController.stream;
  @override
  Stream<void> get completions => completionsController.stream;
  @override
  Stream<bool> get playing => playingController.stream;

  @override
  Future<void> setAudioContext(AudioContext context) async {
    calls.add('context');
    contexts.add(context);
  }

  @override
  Future<void> play(String source,
      {required bool isLocalFile, required double rate}) async {
    calls.add('play');
    final error = nextPlayError;
    if (error != null) {
      nextPlayError = null;
      throw error;
    }
    lastSource = source;
    lastIsLocalFile = isLocalFile;
    lastRate = rate;
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    lastSeek = position;
  }

  @override
  Future<void> setRate(double rate) async {
    calls.add('rate:$rate');
    lastRate = rate;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await positionsController.close();
    await completionsController.close();
    await playingController.close();
  }
}
```

- [ ] **Step 2: Write the failing controller tests**

`test/features/chat/voice_playback_controller_test.dart`:

```dart
import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVoiceEngine engine;
  late ProviderContainer container;
  VoicePlaybackController get controller =>
      container.read(voicePlaybackControllerProvider.notifier);
  VoicePlaybackState get state => container.read(voicePlaybackControllerProvider);
  Future<String?> url() async => 'https://example.com/a.m4a';
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  setUp(() {
    engine = FakeVoiceEngine();
    container = ProviderContainer(overrides: [
      voicePlaybackEngineProvider.overrideWithValue(engine),
      voicePlaybackStallAfterProvider.overrideWithValue(
          const Duration(milliseconds: 60)),
    ]);
    addTearDown(container.dispose);
  });

  test('toggle plays the resolved source and publishes the current id',
      () async {
    await controller.toggle('m1', url);
    expect(engine.lastSource, 'https://example.com/a.m4a');
    expect(engine.lastIsLocalFile, isFalse);
    expect(state.messageId, 'm1');
    expect(state.isPlaying, isTrue);
    expect(state.isLoading, isFalse);
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), 'm1');
  });

  test('a local file plays as a file source', () async {
    await controller.toggle('m1', () async => '/tmp/voice/a.m4a');
    expect(engine.lastIsLocalFile, isTrue);
  });

  test('the controller, not the bubble, owns position', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 7));
    await tick();
    expect(state.positionFor('m1'), const Duration(seconds: 7));
    expect(state.positionFor('other'), Duration.zero);
  });

  test('second toggle pauses, third resumes from where it was', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 3));
    await tick();
    await controller.toggle('m1', url);
    expect(state.isPlaying, isFalse);
    expect(state.position, const Duration(seconds: 3));
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);

    await controller.toggle('m1', url);
    expect(engine.calls.last, 'resume');
    expect(engine.calls.where((c) => c == 'play').length, 1);
    expect(state.isPlaying, isTrue);
  });

  test('starting another message stops the first and resets position',
      () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 5));
    await tick();
    await controller.toggle('m2', () async => 'https://example.com/b.m4a');
    expect(engine.calls, containsAllInOrder(['play', 'stop', 'play']));
    expect(state.messageId, 'm2');
    expect(state.position, Duration.zero, reason: 'no carry-over');
    expect(state.positionFor('m1'), Duration.zero);
  });

  test('completion returns the bubble to the start', () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 2));
    engine.completionsController.add(null);
    await tick();
    expect(state.isPlaying, isFalse);
    expect(state.positionFor('m1'), Duration.zero);
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });

  test('an OS interruption reported by the engine shows as paused', () async {
    await controller.toggle('m1', url);
    engine.playingController.add(false);
    await tick();
    expect(state.isPlaying, isFalse);
    await controller.toggle('m1', url);
    expect(engine.calls.last, 'resume');
  });

  test('a stalled position (interruption the plugin did not report) pauses',
      () async {
    await controller.toggle('m1', url);
    engine.positionsController.add(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(state.isPlaying, isFalse);
    expect(engine.calls.last, 'pause');
  });

  test('a video taking the floor pauses the voice note', () async {
    await controller.toggle('m1', url);
    container.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = null;
    await tick();
    expect(state.isPlaying, isFalse);
    expect(engine.calls.last, 'pause');
  });

  test('starting a voice note clears any playing video', () async {
    container.read(currentlyPlayingVideoMessageIdProvider.notifier).state = 'v1';
    await controller.toggle('m1', url);
    expect(container.read(currentlyPlayingVideoMessageIdProvider), isNull);
  });

  test('speed cycles 1 → 1.5 → 2 → 1 and sticks for the next note', () async {
    await controller.toggle('m1', url);
    await controller.cycleRate();
    expect(state.rate, 1.5);
    expect(engine.lastRate, 1.5);
    await controller.cycleRate();
    expect(state.rate, 2.0);
    await controller.cycleRate();
    expect(state.rate, 1.0);
    await controller.cycleRate();
    await controller.toggle('m2', url);
    expect(engine.lastRate, 1.5, reason: 'rate is passed into play');
  });

  test('seek only applies to the current message', () async {
    await controller.toggle('m1', url);
    await controller.seek('m2', const Duration(seconds: 9));
    expect(engine.lastSeek, isNull);
    await controller.seek('m1', const Duration(seconds: 9));
    expect(engine.lastSeek, const Duration(seconds: 9));
    expect(state.position, const Duration(seconds: 9));
  });

  test('an unresolvable source reports a failure for that message', () async {
    await controller.toggle('m1', () async => null);
    expect(state.failureCount, 1);
    expect(state.failedMessageId, 'm1');
    expect(state.messageId, isNull);
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });

  test('an engine error reports a failure and leaves nothing playing', () async {
    engine.nextPlayError = StateError('codec');
    await controller.toggle('m1', url);
    expect(state.failureCount, 1);
    expect(state.isPlaying, isFalse);
  });

  test('backgrounding the app pauses (no background playback)', () async {
    await controller.toggle('m1', url);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tick();
    expect(state.isPlaying, isFalse);
  });

  test('stop() clears everything (leaving the chat screen)', () async {
    await controller.toggle('m1', url);
    await controller.stop();
    expect(state, VoicePlaybackState.idle.copyWith(rate: state.rate));
    expect(engine.calls.last, 'stop');
    expect(container.read(currentlyPlayingVoiceMessageIdProvider), isNull);
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/features/chat/voice_playback_controller_test.dart`
Expected: compile error `Target of URI doesn't exist: '…/voice_playback_controller.dart'`.

- [ ] **Step 4: Write the controller**

`lib/features/chat/presentation/state/voice_playback_controller.dart`:

```dart
import 'dart:async';

import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What voice playback needs from an audio backend. One instance app-wide.
abstract class VoicePlaybackEngine {
  Stream<Duration> get positions;
  Stream<void> get completions;

  /// True while audio is actually coming out; false after pause, stop,
  /// completion, and whenever the OS takes the output away (call, Siri).
  Stream<bool> get playing;

  /// This player's audio session. The controller decides WHICH context
  /// (Plan 4 hands this method to AudioSessionCoordinator.beginPlayback).
  Future<void> setAudioContext(AudioContext context);

  Future<void> play(
    String source, {
    required bool isLocalFile,
    required double rate,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> dispose();
}

/// audioplayers-backed engine.
class AudioPlayersVoiceEngine implements VoicePlaybackEngine {
  AudioPlayersVoiceEngine({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positions => _player.onPositionChanged;
  @override
  Stream<void> get completions => _player.onPlayerComplete;
  @override
  Stream<bool> get playing =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Future<void> setAudioContext(AudioContext context) =>
      _player.setAudioContext(context);

  @override
  Future<void> play(
    String source, {
    required bool isLocalFile,
    required double rate,
  }) async {
    await _player.setPlaybackRate(rate);
    // UrlSource only works for real HTTP(S) URLs; a just-recorded or cached
    // note is a local file.
    await _player.play(
      isLocalFile ? DeviceFileSource(source) : UrlSource(source),
    );
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> resume() => _player.resume();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setPlaybackRate(rate);
  @override
  Future<void> dispose() => _player.dispose();
}

typedef VoiceSourceResolver = Future<String?> Function();

@immutable
class VoicePlaybackState {
  const VoicePlaybackState({
    this.messageId,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.rate = 1.0,
    this.failureCount = 0,
    this.failedMessageId,
  });

  static const idle = VoicePlaybackState();
  static const Object _unset = Object();

  /// The message the engine currently holds (playing, loading or paused).
  final String? messageId;
  final bool isPlaying;

  /// Resolving / downloading before the first audio frame.
  final bool isLoading;
  final Duration position;
  final double rate;

  /// Bumped on every playback failure; [failedMessageId] says whose.
  final int failureCount;
  final String? failedMessageId;

  bool isCurrent(String id) => messageId == id;
  Duration positionFor(String id) => messageId == id ? position : Duration.zero;

  VoicePlaybackState copyWith({
    Object? messageId = _unset,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    double? rate,
    int? failureCount,
    Object? failedMessageId = _unset,
  }) {
    return VoicePlaybackState(
      messageId: identical(messageId, _unset) ? this.messageId : messageId as String?,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      rate: rate ?? this.rate,
      failureCount: failureCount ?? this.failureCount,
      failedMessageId: identical(failedMessageId, _unset)
          ? this.failedMessageId
          : failedMessageId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoicePlaybackState &&
      other.messageId == messageId &&
      other.isPlaying == isPlaying &&
      other.isLoading == isLoading &&
      other.position == position &&
      other.rate == rate &&
      other.failureCount == failureCount &&
      other.failedMessageId == failedMessageId;

  @override
  int get hashCode => Object.hash(
    messageId, isPlaying, isLoading, position, rate, failureCount, failedMessageId,
  );
}

/// Owns the one voice [VoicePlaybackEngine] for the app (chat review #21):
/// the bubble used to own the AudioPlayer, so scrolling it past the list's
/// cacheExtent disposed the player mid-sentence. Bubbles are views of this
/// state; one message plays at a time; leaving the chat screen calls
/// [stop] (spec: no background playback).
class VoicePlaybackController extends StateNotifier<VoicePlaybackState>
    with WidgetsBindingObserver {
  VoicePlaybackController({
    required VoicePlaybackEngine engine,
    required void Function(String? messageId) publishCurrent,
    required VoidCallback stopOtherMedia,
    Duration stallAfter = const Duration(milliseconds: 1500),
  }) : _engine = engine,
       _publishCurrent = publishCurrent,
       _stopOtherMedia = stopOtherMedia,
       _stallAfter = stallAfter,
       super(VoicePlaybackState.idle) {
    _subscriptions.addAll([
      _engine.positions.listen(_onPosition),
      _engine.completions.listen((_) => _onComplete()),
      _engine.playing.listen(_onEnginePlaying),
    ]);
    WidgetsBinding.instance.addObserver(this);
  }

  static const rates = [1.0, 1.5, 2.0];

  final VoicePlaybackEngine _engine;
  final void Function(String?) _publishCurrent;
  final VoidCallback _stopOtherMedia;
  final Duration _stallAfter;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _stallTimer;
  int _generation = 0;

  /// Play, pause or resume [messageId]. [resolve] yields a local file path
  /// or an http(s) URL (null: nothing playable).
  Future<void> toggle(String messageId, VoiceSourceResolver resolve) async {
    if (state.messageId == messageId) {
      if (state.isLoading) return;
      if (state.isPlaying) {
        await pause();
        return;
      }
      // Paused (by the person, a call, or backgrounding): pick up where it
      // stopped.
      _stopOtherMedia();
      _publishCurrent(messageId);
      state = state.copyWith(isPlaying: true);
      _armStallWatchdog();
      try {
        await _engine.resume();
      } catch (error, stack) {
        _fail(messageId, error, stack);
      }
      return;
    }
    await _startFresh(messageId, resolve);
  }

  Future<void> _startFresh(String messageId, VoiceSourceResolver resolve) async {
    final generation = ++_generation;
    _stallTimer?.cancel();
    if (state.messageId != null) {
      try {
        await _engine.stop();
      } catch (error) {
        ChatLog.diagnostic('voice stop before switch failed', error);
      }
    }
    state = VoicePlaybackState(
      messageId: messageId,
      isLoading: true,
      rate: state.rate,
      failureCount: state.failureCount,
    );
    _stopOtherMedia();
    _publishCurrent(messageId);

    String? source;
    try {
      source = await resolve();
    } catch (error, stack) {
      if (generation == _generation) _fail(messageId, error, stack);
      return;
    }
    if (generation != _generation) return; // superseded by another tap
    if (source == null) {
      _fail(messageId, null, null);
      return;
    }
    try {
      // Per-player context, because SoundService sets a PROCESS-WIDE one
      // with respectSilence:true for UI chirps — on iOS the ambient
      // category, muted by the Ring/Silent switch. A voice note the person
      // tapped plays through the switch, as in every messaging app.
      // Plan 4 (#40) replaces this one call with
      // AudioSessionCoordinator.beginPlayback(_engine.setAudioContext) and
      // returns the session from pause/_onComplete/_onEnginePlaying(false)/
      // stop/_fail/dispose.
      await _engine.setAudioContext(
        AudioContextConfig(respectSilence: false).build(),
      );
      await _engine.play(
        source,
        isLocalFile: !source.startsWith('http'),
        rate: state.rate,
      );
    } catch (error, stack) {
      if (generation == _generation) _fail(messageId, error, stack);
      return;
    }
    if (generation != _generation) return;
    state = state.copyWith(isLoading: false, isPlaying: true, position: Duration.zero);
    _armStallWatchdog();
  }

  Future<void> pause() async {
    if (state.messageId == null) return;
    _stallTimer?.cancel();
    state = state.copyWith(isPlaying: false);
    _publishCurrent(null);
    try {
      await _engine.pause();
    } catch (error) {
      ChatLog.diagnostic('voice pause failed', error);
    }
  }

  Future<void> seek(String messageId, Duration to) async {
    if (state.messageId != messageId || state.isLoading) return;
    state = state.copyWith(position: to);
    try {
      await _engine.seek(to);
    } catch (error) {
      ChatLog.diagnostic('voice seek failed', error);
    }
  }

  Future<void> cycleRate() async {
    final next = rates[(rates.indexOf(state.rate) + 1) % rates.length];
    state = state.copyWith(rate: next);
    if (state.messageId != null) {
      try {
        await _engine.setRate(next);
      } catch (error) {
        ChatLog.diagnostic('voice rate failed', error);
      }
    }
  }

  /// Everything off: the chat screen was left.
  Future<void> stop() async {
    _generation++;
    _stallTimer?.cancel();
    final hadMessage = state.messageId != null;
    state = VoicePlaybackState(rate: state.rate, failureCount: state.failureCount);
    _publishCurrent(null);
    if (!hadMessage) return;
    try {
      await _engine.stop();
    } catch (error) {
      ChatLog.diagnostic('voice stop failed', error);
    }
  }

  /// Another player (a video) took the floor: the handshake is the shared
  /// provider going null while we are playing.
  void onCurrentIdCleared() {
    if (state.isPlaying) unawaited(pause());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.paused && state.isPlaying) {
      unawaited(pause());
    }
  }

  void _onPosition(Duration position) {
    if (state.messageId == null || state.isLoading) return;
    state = state.copyWith(position: position);
    if (state.isPlaying) _armStallWatchdog();
  }

  void _onComplete() {
    _stallTimer?.cancel();
    if (state.messageId == null) return;
    state = state.copyWith(isPlaying: false, position: Duration.zero);
    _publishCurrent(null);
  }

  void _onEnginePlaying(bool playing) {
    if (state.messageId == null || state.isLoading) return;
    if (!playing && state.isPlaying) {
      _stallTimer?.cancel();
      state = state.copyWith(isPlaying: false);
      _publishCurrent(null);
    }
  }

  /// Position ticks arrive every ~200 ms while audio plays. Silence for
  /// [_stallAfter] while we believe we are playing means the OS paused us
  /// without telling the plugin (interruption); reflect it and make the
  /// pause real so the next tap resumes cleanly.
  void _armStallWatchdog() {
    _stallTimer?.cancel();
    _stallTimer = Timer(_stallAfter, () {
      if (state.isPlaying) unawaited(pause());
    });
  }

  void _fail(String messageId, Object? error, StackTrace? stack) {
    // diagnostic, not e: a playback failure carries no message content.
    if (error != null) {
      ChatLog.diagnostic('voice playback failed', error);
      if (stack != null) debugPrintStack(stackTrace: stack);
    }
    _stallTimer?.cancel();
    state = VoicePlaybackState(
      rate: state.rate,
      failureCount: state.failureCount + 1,
      failedMessageId: messageId,
    );
    _publishCurrent(null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stallTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    unawaited(_engine.dispose());
    super.dispose();
  }
}

final voicePlaybackEngineProvider = Provider<VoicePlaybackEngine>(
  (ref) => AudioPlayersVoiceEngine(),
);

final voicePlaybackStallAfterProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 1500),
);

final voicePlaybackControllerProvider =
    StateNotifierProvider<VoicePlaybackController, VoicePlaybackState>((ref) {
      final controller = VoicePlaybackController(
        engine: ref.watch(voicePlaybackEngineProvider),
        stallAfter: ref.watch(voicePlaybackStallAfterProvider),
        publishCurrent:
            (id) =>
                ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
                    id,
        stopOtherMedia: () {
          if (ref.read(currentlyPlayingVideoMessageIdProvider) != null) {
            ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
                null;
          }
        },
      );
      // VideoMessagePlayer clears the voice id when a video starts.
      ref.listen<String?>(currentlyPlayingVoiceMessageIdProvider, (_, next) {
        if (next == null) controller.onCurrentIdCleared();
      });
      return controller;
    });
```

- [ ] **Step 5: Run the controller tests**

Run: `flutter test test/features/chat/voice_playback_controller_test.dart`
Expected: 16 tests pass. (`dart format` is allowed on this new file only.)

- [ ] **Step 6: Make `VoiceMessagePlayer` a view**

Replace the whole `_VoiceMessagePlayerState`/widget part of `voice_message_player.dart` (keep `voiceWaveformBars`, `kVoiceWaveformStride`, `_minBarHeight`, `_WaveformPainter` exactly as they are) with:

```dart
import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playback UI for a voice message bubble: play/pause, a tap-to-seek
/// waveform, elapsed/total duration and a speed chip. A VIEW of
/// [voicePlaybackControllerProvider]: the controller owns the engine, so
/// this widget can be recycled by the list while its note keeps playing
/// (chat review #21).
class VoiceMessagePlayer extends ConsumerWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.resolveAudioUrl,
    required this.durationMs,
    required this.waveform,
    this.mediaKey,
    this.foregroundColor,
    this.metadataColor,
    this.accentColor,
  });

  final String messageId;

  /// Resolved on PLAY, not on build. durationMs and waveform both come off
  /// the message row, so the bubble draws itself with no network at all.
  /// Returns null when the media cannot be resolved.
  final Future<String?> Function() resolveAudioUrl;

  /// Storage key, so the controller can cache the bytes on disk (Task 8).
  final String? mediaKey;

  final int durationMs;
  final List<int> waveform;
  final Color? foregroundColor;
  final Color? metadataColor;
  final Color? accentColor;

  static const double _waveformWidth = 172;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackControllerProvider);
    final controller = ref.read(voicePlaybackControllerProvider.notifier);
    final isCurrent = playback.isCurrent(messageId);
    final isPlaying = isCurrent && playback.isPlaying;
    final isLoading = isCurrent && playback.isLoading;
    final position = playback.positionFor(messageId);

    ref.listen<int>(
      voicePlaybackControllerProvider.select((s) => s.failureCount),
      (previous, next) {
        if (ref.read(voicePlaybackControllerProvider).failedMessageId !=
            messageId) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That voice message could not play')),
        );
      },
    );

    final total = Duration(milliseconds: durationMs);
    final progressFraction =
        total.inMilliseconds == 0
            ? 0.0
            : position.inMilliseconds / total.inMilliseconds;

    final colorScheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colorScheme.onSurface;
    final metadata = metadataColor ?? colorScheme.onSurfaceVariant;
    final accent = accentColor ?? colorScheme.primary;

    void seekFromLocalX(double localX) {
      final fraction = (localX / _waveformWidth).clamp(0.0, 1.0);
      unawaited(
        controller.seek(
          messageId,
          Duration(milliseconds: (durationMs * fraction).round()),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label:
              isLoading
                  ? 'Loading voice message'
                  : isPlaying
                  ? 'Pause voice message'
                  : 'Play voice message',
          child: InkWell(
            onTap: () => unawaited(controller.toggle(messageId, resolveAudioUrl)),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                    // ignore: deprecated_member_use
                    color: colorScheme.background,
                  ),
                  if (isLoading)
                    SizedBox(
                      key: const ValueKey('voice_loading_ring'),
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        // ignore: deprecated_member_use
                        color: colorScheme.background,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: _waveformWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                key: const ValueKey('voice_message_waveform'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => seekFromLocalX(details.localPosition.dx),
                onHorizontalDragStart:
                    (details) => seekFromLocalX(details.localPosition.dx),
                onHorizontalDragUpdate:
                    (details) => seekFromLocalX(details.localPosition.dx),
                child: SizedBox(
                  width: _waveformWidth,
                  height: 30,
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      waveform: waveform,
                      progressFraction: progressFraction,
                      color: accent,
                      trackColor: foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  RollingDuration(
                    keyPrefix: 'voice-playback-duration',
                    value: isPlaying || position > Duration.zero ? position : total,
                    alwaysShowMinutes: true,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: metadata,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  // Speed chip only for the note that is current (playing
                  // or paused mid-way), so idle bubbles stay quiet.
                  if (isCurrent && (isPlaying || position > Duration.zero))
                    _SpeedChip(
                      rate: playback.rate,
                      color: metadata,
                      onTap: () {
                        ref.read(hapticsProvider).selection();
                        unawaited(controller.cycleRate());
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.rate, required this.color, required this.onTap});
  final double rate;
  final Color color;
  final VoidCallback onTap;

  static String label(double rate) =>
      '${rate == rate.roundToDouble() ? rate.toInt() : rate}×';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Playback speed ${label(rate)}',
      child: InkWell(
        key: const ValueKey('voice_speed_chip'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withValues(alpha: 0.14),
          ),
          child: Text(
            label(rate),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
```

Remove the now-unused imports (`audioplayers`, `voice_playback_provider`, `chat_log`) from this file.

- [ ] **Step 7: Stop playback when the chat route is disposed (`chat_screen.dart`)**

In `_ChatScreenState` add a field `late final VoicePlaybackController _voicePlayback;`. In `initState()` (first lines) add `_voicePlayback = ref.read(voicePlaybackControllerProvider.notifier);`. In `_ChatScreenState.dispose()` (the one that starts with `WidgetsBinding.instance.removeObserver(this);`) add as the first statement:

```dart
    // Spec: leaving the chat screen stops voice playback (no background
    // playback). The controller is app-scoped, so the route must say so.
    unawaited(_voicePlayback.stop());
```

Import `package:attune/features/chat/presentation/state/voice_playback_controller.dart`.

- [ ] **Step 8: Update the widget tests**

In `test/features/chat/voice_message_player_test.dart`:
1. Change `_wrap` to default-override the engine (the real engine would construct an `AudioPlayer` on a host with no platform):
```dart
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine()),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}
```
and give every `ProviderContainer()` in the file `overrides: [voicePlaybackEngineProvider.overrideWithValue(FakeVoiceEngine())]`. Import `support/fake_voice_engine.dart` and `voice_playback_controller.dart`.
2. Add:

```dart
  testWidgets('playback survives the bubble being recycled by the list',
      (tester) async {
    final engine = FakeVoiceEngine();
    final container = ProviderContainer(overrides: [
      voicePlaybackEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    Widget player() => VoiceMessagePlayer(
          messageId: 'm1',
          resolveAudioUrl: () async => 'https://example.com/voice.m4a',
          durationMs: 120000,
          waveform: List.filled(100, 50),
        );
    Widget host(Widget child) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)));

    await tester.pumpWidget(host(player()));
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    // The bubble scrolls out of cacheExtent: the list disposes its element.
    await tester.pumpWidget(host(const SizedBox()));
    expect(engine.calls, isNot(contains('stop')));
    expect(engine.calls, isNot(contains('pause')));
    expect(container.read(voicePlaybackControllerProvider).isPlaying, isTrue);
    engine.positionsController.add(const Duration(seconds: 30));
    await tester.pump();

    // Scrolled back: the bubble picks up live state, not 0:00.
    await tester.pumpWidget(host(player()));
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    final duration = tester.widget<RollingDuration>(find.byType(RollingDuration));
    expect(duration.value, const Duration(seconds: 30));
  });

  testWidgets('the speed chip appears for the current note and cycles',
      (tester) async {
    final engine = FakeVoiceEngine();
    await tester.pumpWidget(_wrap(
      VoiceMessagePlayer(
        messageId: 'm1',
        resolveAudioUrl: () async => 'https://example.com/voice.m4a',
        durationMs: 9000,
        waveform: List.filled(100, 50),
      ),
      overrides: [voicePlaybackEngineProvider.overrideWithValue(engine)],
    ));
    expect(find.byKey(const ValueKey('voice_speed_chip')), findsNothing);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(find.text('1×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice_speed_chip')));
    await tester.pump();
    expect(find.text('1.5×'), findsOneWidget);
    expect(engine.lastRate, 1.5);
    await tester.tap(find.byKey(const ValueKey('voice_speed_chip')));
    await tester.pump();
    expect(find.text('2×'), findsOneWidget);
  });
```

3. In `test/features/chat/voice_playback_audio_context_test.dart`, the two tests that read `lib/features/chat/presentation/widgets/voice_message_player.dart` now read `lib/features/chat/presentation/state/voice_playback_controller.dart` (the audio context and the `catch` moved with the engine). Update the comment: "the controller, not the widget, owns the player now". Their assertions hold unchanged against the controller file: it contains `setAudioContext` and `respectSilence: false` (in `_startFresh`), `catch`, and no `catch (_)` (every catch names its error and logs it). The `SoundService` assertion is unchanged.

- [ ] **Step 8b: Harness default — no real AudioPlayer in controller/widget tests**

`ChatScreen.initState` now reads `voicePlaybackControllerProvider.notifier`, which would construct `AudioPlayersVoiceEngine()` → `AudioPlayer()` in every ChatScreen widget test (chat_screen_header_test and friends build through `buildChatContainer` + `UncontrolledProviderScope`); on the test host that player's platform channel is absent. In `buildChatContainer` (chat_test_harness.dart) add to the default overrides, next to the prewarmer override:

```dart
      // One fake voice engine per container: ChatScreen touches the
      // playback controller on init, and a real AudioPlayer has no
      // platform channel here (Wave 2 #21).
      voicePlaybackEngineProvider.overrideWith((ref) => FakeVoiceEngine()),
```

with `import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';` and `import 'fake_voice_engine.dart';`. Tests that need to script the engine keep passing their own override through `extraOverrides` (a later override of the same provider wins).

- [ ] **Step 9: Run**

Run: `flutter test test/features/chat/voice_message_player_test.dart test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_playback_audio_context_test.dart test/features/chat/voice_playback_fidelity_test.dart test/features/chat/voice_instant_render_test.dart test/features/chat/voice_local_path_fallback_test.dart test/features/chat/video_message_player_test.dart test/features/chat/message_bubble_test.dart test/features/chat/chat_screen_header_test.dart`
Expected: all pass. A chat-screen test that still fails on a missing audioplayers channel is one that builds its own `ProviderContainer` instead of `buildChatContainer`: give it the same `voicePlaybackEngineProvider` override and say so.

- [ ] **Step 10: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/presentation/state/voice_playback_controller.dart lib/features/chat/presentation/widgets/voice_message_player.dart lib/features/chat/presentation/screens/chat_screen.dart test/features/chat/voice_playback_controller_test.dart test/features/chat/voice_message_player_test.dart test/features/chat/support/fake_voice_engine.dart | grep -E '^\s*(error|warning) '`; no commit (the owner commits).

---

### Task 8: Voice and video bytes cached on disk once (#28)

**Files:**
- Create: `lib/features/chat/domain/services/chat_media_cache.dart`
- Create: `test/features/chat/chat_media_cache_test.dart`
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (voice `resolveAudioUrl` closure)
- Modify: `lib/features/chat/presentation/screens/video_viewer_screen.dart` (`_FullScreenVideo` remote branch)
- Modify: `lib/features/auth/providers/auth_provider.dart` (`signOut`)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`buildChatContainer` default override)
- Modify: `test/features/chat/voice_signed_url_freshness_test.dart` (one assertion string — says so)

**Interfaces:**
- Consumes: `flutter_cache_manager` (`CacheManager(Config(...))`, `getFileFromCache`, `getFileStream(url, key:, withProgress: true)` → `DownloadProgress | FileInfo`, `HttpExceptionWithStatus`, `emptyCache`), `ChatRepository.createSignedMediaUrl(key, forceRefresh: true)`, `signedMediaUrlProvider` (Task 6), `VoiceMessagePlayer.mediaKey` (Task 7).
- Produces:
  - `class ChatMediaCache { ChatMediaCache({BaseCacheManager? manager}); static const cacheKey = 'attune_chat_media'; static const maxObjects = 400; static const stalePeriod = Duration(days: 180); Future<String?> cachedPath(String mediaKey); Future<String> fetch({required String mediaKey, required String url, required Future<String?> Function() refreshUrl, void Function(double fraction)? onProgress}); Future<void> clear(); }`
  - `final chatMediaCacheProvider = Provider<ChatMediaCache>`.
  - `fetch` contract: a cache hit with a non-empty file returns its path without network; an empty hit is removed and treated as a miss; a miss downloads under `mediaKey` and returns the path; a 400/401/403 reply (expired token) refreshes the URL once and retries; any other failure rethrows.

Ruling on "bounded": flutter_cache_manager bounds by object count and age, not bytes. 400 objects × typical 1.2 MB voice / ≤ 25 MB video and 180 days is the bound; a byte budget needs a custom cache store and is noted as a follow-up in the Owner notes. Images stay on `DefaultCacheManager` (unchanged; Wave 3 #38 touches image decoding).

- [ ] **Step 1: Write the failing cache tests**

`test/features/chat/chat_media_cache_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Scriptable cache manager: [store] is what is on disk (by key),
/// [responses] maps a URL to bytes or a thrown error, [downloads] records
/// every network fetch.
class _FakeCacheManager implements BaseCacheManager {
  _FakeCacheManager(this.dir);
  final Directory dir;
  final Map<String, File> store = {};
  final Map<String, Object> responses = {};
  final List<String> downloads = [];
  int emptied = 0;

  FileInfo _info(String key, File f) => FileInfo(
    const LocalFileSystem().file(f.path),
    FileSource.Cache,
    DateTime.now().add(const Duration(days: 1)),
    key,
  );

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async {
    final f = store[key];
    return f == null ? null : _info(key, f);
  }

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) async* {
    downloads.add(url);
    final response = responses[url];
    if (response is Object && response is! List<int>) throw response;
    final bytes = (response as List<int>?) ?? [1, 2, 3];
    yield DownloadProgress(url, bytes.length, bytes.length ~/ 2);
    final f = File(p.join(dir.path, '${key ?? url.hashCode}.bin'))
      ..writeAsBytesSync(bytes);
    store[key ?? url] = f;
    yield _info(key ?? url, f);
  }

  @override
  Future<void> removeFile(String key) async {
    store.remove(key);
  }

  @override
  Future<void> emptyCache() async {
    emptied++;
    store.clear();
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not used');
}

void main() {
  late Directory dir;
  late _FakeCacheManager manager;
  late ChatMediaCache cache;
  const key = 'chat-media/voice.m4a';
  const url = 'https://signed.test/voice.m4a?token=1';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('media_cache');
    manager = _FakeCacheManager(dir);
    cache = ChatMediaCache(manager: manager);
  });
  tearDown(() => dir.delete(recursive: true));

  test('downloads once, then plays from disk with no network', () async {
    final first = await cache.fetch(
        mediaKey: key, url: url, refreshUrl: () async => fail('not needed'));
    final second = await cache.fetch(
        mediaKey: key, url: 'https://signed.test/voice.m4a?token=2',
        refreshUrl: () async => fail('not needed'));
    expect(first, second);
    expect(File(first).existsSync(), isTrue);
    expect(manager.downloads, [url], reason: 'exactly one download');
  });

  test('reports progress on first fetch', () async {
    final seen = <double>[];
    await cache.fetch(mediaKey: key, url: url,
        refreshUrl: () async => null, onProgress: seen.add);
    expect(seen, isNotEmpty);
    expect(seen.last, 1.0);
  });

  test('an empty cached file (killed mid-download) is a miss', () async {
    manager.store[key] = File(p.join(dir.path, 'empty.bin'))..writeAsBytesSync([]);
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    expect(manager.downloads, [url]);
  });

  test('an expired signed URL (403) is refreshed once and retried', () async {
    manager.responses[url] = HttpExceptionWithStatus(403, 'expired', uri: Uri.parse(url));
    var refreshed = 0;
    final path = await cache.fetch(
      mediaKey: key,
      url: url,
      refreshUrl: () async {
        refreshed++;
        return 'https://signed.test/voice.m4a?token=fresh';
      },
    );
    expect(refreshed, 1);
    expect(manager.downloads, [url, 'https://signed.test/voice.m4a?token=fresh']);
    expect(File(path).existsSync(), isTrue);
  });

  test('a server error is rethrown (caller falls back to streaming)', () async {
    manager.responses[url] = HttpExceptionWithStatus(503, 'down', uri: Uri.parse(url));
    await expectLater(
      cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null),
      throwsA(isA<HttpExceptionWithStatus>()),
    );
  });

  test('cachedPath answers without network', () async {
    expect(await cache.cachedPath(key), isNull);
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    expect(await cache.cachedPath(key), isNotNull);
    expect(manager.downloads.length, 1);
  });

  test('clear empties the store (sign-out)', () async {
    await cache.fetch(mediaKey: key, url: url, refreshUrl: () async => null);
    await cache.clear();
    expect(manager.emptied, 1);
    expect(await cache.cachedPath(key), isNull);
  });

  test('sign-out wipes the media cache alongside the chat cache', () {
    final auth = File('lib/features/auth/providers/auth_provider.dart').readAsStringSync();
    final signOut = auth.substring(auth.indexOf('Future<void> signOut()'));
    expect(signOut, contains('chatCacheServiceProvider).clearAll()'));
    expect(signOut.indexOf('chatMediaCacheProvider'), greaterThan(0),
        reason: 'voice/video bytes of the previous person must not survive sign-out');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/chat_media_cache_test.dart`
Expected: compile error (missing `chat_media_cache.dart`).

- [ ] **Step 3: Write `ChatMediaCache`**

`lib/features/chat/domain/services/chat_media_cache.dart`:

```dart
import 'dart:io';

import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Disk cache for voice and video bytes, keyed by the STABLE storage key
/// (never the signed URL, whose token changes every 10 minutes).
///
/// Chat review #28: every replay re-downloaded the note and nothing played
/// offline. Download once here, play from the returned local path forever
/// after. Separate from DefaultCacheManager (images/posters) so its bounds
/// suit large objects: [maxObjects] entries, [stalePeriod] old.
class ChatMediaCache {
  ChatMediaCache({BaseCacheManager? manager}) : _injected = manager;

  static const String cacheKey = 'attune_chat_media';
  static const int maxObjects = 400;
  static const Duration stalePeriod = Duration(days: 180);

  final BaseCacheManager? _injected;
  BaseCacheManager? _resolved;

  /// Built lazily: CacheManager reaches for a platform channel, which
  /// throws on a pure-Dart test host that merely reads the provider.
  BaseCacheManager get _manager =>
      _injected ??
      (_resolved ??= CacheManager(
        Config(
          cacheKey,
          stalePeriod: stalePeriod,
          maxNrOfCacheObjects: maxObjects,
        ),
      ));

  /// Local path when the bytes are already on disk; no network.
  Future<String?> cachedPath(String mediaKey) async {
    try {
      final info = await _manager.getFileFromCache(mediaKey);
      if (info == null) return null;
      final file = File(info.file.path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        // A kill mid-write leaves a zero-byte entry; it is a miss.
        await _manager.removeFile(mediaKey);
        return null;
      }
      return file.path;
    } catch (error) {
      ChatLog.e('media cache lookup failed (non-fatal)', error);
      return null;
    }
  }

  /// Returns a local path for [mediaKey], downloading [url] on a miss. An
  /// expired token (400/401/403) is refreshed through [refreshUrl] once.
  /// Other failures rethrow so the caller can fall back to streaming.
  Future<String> fetch({
    required String mediaKey,
    required String url,
    required Future<String?> Function() refreshUrl,
    void Function(double fraction)? onProgress,
  }) async {
    final hit = await cachedPath(mediaKey);
    if (hit != null) return hit;
    try {
      return await _download(mediaKey, url, onProgress);
    } on HttpExceptionWithStatus catch (error) {
      if (error.statusCode != 400 &&
          error.statusCode != 401 &&
          error.statusCode != 403) {
        rethrow;
      }
      final fresh = await refreshUrl();
      if (fresh == null || fresh == url) rethrow;
      return _download(mediaKey, fresh, onProgress);
    }
  }

  Future<String> _download(
    String mediaKey,
    String url,
    void Function(double)? onProgress,
  ) async {
    String? path;
    await for (final event in _manager.getFileStream(
      url,
      key: mediaKey,
      withProgress: true,
    )) {
      if (event is DownloadProgress) {
        final total = event.totalSize;
        if (total != null && total > 0) {
          onProgress?.call((event.downloaded / total).clamp(0.0, 1.0));
        }
      } else if (event is FileInfo) {
        path = event.file.path;
      }
    }
    if (path == null) {
      throw const FileSystemException('download produced no file');
    }
    onProgress?.call(1.0);
    return path!;
  }

  /// Sign-out: nothing of the previous person's media stays on disk.
  Future<void> clear() async {
    try {
      await _manager.emptyCache();
    } catch (error) {
      ChatLog.e('media cache clear failed (non-fatal)', error);
    }
  }
}

final chatMediaCacheProvider = Provider<ChatMediaCache>(
  (ref) => ChatMediaCache(),
);
```

- [ ] **Step 4: Wipe on sign-out (`auth_provider.dart`)**

In `AuthOperations.signOut()`, inside the existing `try` right after `await ref.read(chatCacheServiceProvider).clearAll();` add:

```dart
        // Voice/video bytes cached by ChatMediaCache belong to this
        // session's person too.
        await ref.read(chatMediaCacheProvider).clear();
```

with `import 'package:attune/features/chat/domain/services/chat_media_cache.dart';`.

- [ ] **Step 5: Run the cache tests**

Run: `flutter test test/features/chat/chat_media_cache_test.dart`
Expected: 8 tests pass.

- [ ] **Step 6: Voice plays from the cache (message_bubble.dart)**

Replace the voice `resolveAudioUrl` closure body's `if (mediaKey != null) { … }` block with:

```dart
                  if (mediaKey != null) {
                    // The provider throws when it cannot sign; the stored
                    // URL remains the fallback for a row that carries one.
                    final resolved = await ref
                        .read(signedMediaUrlProvider(mediaKey).future)
                        .then<String?>((url) => url, onError: (_) => null);
                    final url = resolved ?? signedUrl;
                    if (url == null) return null;
                    // Download once, play from disk after that (#28). A
                    // download failure falls back to streaming the URL.
                    try {
                      return await ref.read(chatMediaCacheProvider).fetch(
                        mediaKey: mediaKey,
                        url: url,
                        refreshUrl: () => ref
                            .read(chatRepositoryProvider)
                            .createSignedMediaUrl(mediaKey, forceRefresh: true),
                      );
                    } catch (_) {
                      return url;
                    }
                  }
                  return signedUrl;
```

and pass `mediaKey: mediaKey,` to the `VoiceMessagePlayer(` call. Import `chat_media_cache.dart`. In `test/features/chat/voice_signed_url_freshness_test.dart` change the assertion `contains('return resolved ?? signedUrl;')` to `contains('resolved ?? signedUrl')` — the fallback is unchanged, only its statement shape moved; note this in the test comment. If that test's `indexOf('},', …)` slice ends inside the new `try {` block, widen it to `bubble.indexOf('return signedUrl;', start)`.

- [ ] **Step 7: Harness default**

In `buildChatContainer` (chat_test_harness.dart) add to the default overrides, after the prewarmer override:

```dart
      // No platform cache in controller tests; voice/video fall back to the
      // URL when fetch throws, which is the production fallback too.
      chatMediaCacheProvider.overrideWith(
        (ref) => ChatMediaCache(manager: _NoPlatformChatCacheManager()),
      ),
```

`_NoPlatformChatCacheManager.getFileFromCache` already returns null; `getFileStream` is not implemented and throws `UnimplementedError`, which `fetch` rethrows and the bubble catches.

- [ ] **Step 8: Video viewer downloads first (video_viewer_screen.dart)**

In `_FullScreenVideo.build`, replace the `: ResolvedMediaUrl(` branch's `builder:` with one that goes through the cache, by introducing a small widget in the same file:

```dart
/// Downloads the video into ChatMediaCache before handing a LOCAL path to
/// the player (#28): the second open plays offline, and the first shows a
/// real progress ring instead of a buffering spinner.
class _CachedVideo extends ConsumerStatefulWidget {
  const _CachedVideo({
    required this.mediaKey,
    required this.url,
    required this.builder,
  });
  final String mediaKey;
  final String url;
  final Widget Function(BuildContext context, String localOrRemotePath) builder;

  @override
  ConsumerState<_CachedVideo> createState() => _CachedVideoState();
}

class _CachedVideoState extends ConsumerState<_CachedVideo> {
  late Future<String> _path;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _path = _fetch();
  }

  Future<String> _fetch() async {
    try {
      return await ref.read(chatMediaCacheProvider).fetch(
        mediaKey: widget.mediaKey,
        url: widget.url,
        refreshUrl: () => ref
            .read(chatRepositoryProvider)
            .createSignedMediaUrl(widget.mediaKey, forceRefresh: true),
        onProgress: (fraction) {
          if (mounted) setState(() => _progress = fraction);
        },
      );
    } catch (_) {
      // Streaming still works when the download does not.
      return widget.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _path,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null) return widget.builder(context, path);
        return Semantics(
          label: 'Downloading video',
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              key: const ValueKey('video_download_ring'),
              value: _progress,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        );
      },
    );
  }
}
```

and change the remote branch to:

```dart
              : ResolvedMediaUrl(
                signedMediaUrl: message.signedMediaUrl,
                mediaKey: message.mediaKey,
                loading: const CircularProgressIndicator(color: Colors.white),
                error: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
                builder:
                    (context, url) => _CachedVideo(
                      mediaKey: message.mediaKey!,
                      url: url,
                      builder:
                          (context, path) => VideoMessagePlayer(
                            key: ValueKey(message.clientMessageId),
                            messageId: message.clientMessageId,
                            videoUrl: path,
                            thumbnailUrl: message.signedThumbnailUrl,
                            durationMs: message.mediaDurationMs ?? 0,
                            width: message.mediaWidth ?? 16,
                            height: message.mediaHeight ?? 9,
                            onRequestFreshUrl: freshUrl,
                            autoPlay: autoPlay,
                          ),
                    ),
              ),
```

(`mediaKey!` is safe: `ResolvedMediaUrl` only calls `builder` through the key branch when `mediaKey != null`; when the key is null it builds from the stored URL — guard with `message.mediaKey == null ? VideoMessagePlayer(... videoUrl: url ...) : _CachedVideo(...)` to keep that path.) Import `chat_media_cache.dart`.

- [ ] **Step 9: Viewer widget test**

Append to `test/features/chat/chat_media_cache_test.dart` (imports: `package:attune/features/chat/presentation/screens/video_viewer_screen.dart`, `.../video_message_player.dart`, `.../presentation/state/chat_state.dart`, `flutter/material.dart`, `flutter_riverpod`, `support/chat_test_harness.dart`, `domain/entities/message.dart`):

```dart
  testWidgets('the viewer shows a download ring, then plays the local file',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('viewer_cache');
    addTearDown(() => dir.delete(recursive: true));
    final manager = _FakeCacheManager(dir);
    final repo = FakeChatRepository(currentUserId: 'u1')..signMediaUrls = true;
    final message = Message(
      id: 'srv-1',
      clientMessageId: 'c1',
      relationshipId: 'rel',
      senderId: 'partner',
      content: '',
      createdAt: DateTime(2026, 10, 18),
      status: MessageStatus.delivered,
      isMine: false,
      mediaKey: 'chat-media/clip.mp4',
      mediaType: 'video',
      mediaDurationMs: 3000,
      mediaWidth: 720,
      mediaHeight: 1280,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repo),
          chatMediaCacheProvider.overrideWithValue(ChatMediaCache(manager: manager)),
        ],
        child: MaterialApp(home: VideoViewerScreen(videos: [message], initialIndex: 0)),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('video_download_ring')), findsOneWidget);
    await tester.pumpAndSettle();
    final player = tester.widget<VideoMessagePlayer>(find.byType(VideoMessagePlayer));
    expect(player.videoUrl, startsWith(dir.path), reason: 'plays the cached file');
    expect(manager.downloads, hasLength(1));
  });
```

`VideoViewerScreen({required this.videos, required this.initialIndex})` is the constructor as of this writing; if it has grown other required parameters, pass `activeConversation('rel')`-style fixtures for them.

- [ ] **Step 10: Run**

Run: `flutter test test/features/chat/chat_media_cache_test.dart test/features/chat/voice_signed_url_freshness_test.dart test/features/chat/message_bubble_test.dart test/features/chat/video_message_player_test.dart test/features/chat/chat_controller_test.dart`
Expected: all pass.

- [ ] **Step 11: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat/domain/services/chat_media_cache.dart lib/features/chat/presentation/widgets/message_bubble.dart lib/features/chat/presentation/screens/video_viewer_screen.dart lib/features/auth/providers/auth_provider.dart test/features/chat/chat_media_cache_test.dart test/features/chat/support/chat_test_harness.dart | grep -E '^\s*(error|warning) '`; no commit (the owner commits).

---

### Task 9: Upload progress, a cancel that works, retry from the failed row (#25)

**Files:**
- Create: `lib/features/chat/data/repositories/chat_media_uploader.dart`
- Create: `test/features/chat/chat_media_uploader_test.dart`
- Create: `test/features/chat/chat_upload_progress_cancel_test.dart`
- Modify: `lib/features/chat/data/repositories/chat_repository.dart`, `supabase_chat_repository.dart` (`uploadChatMedia` signature + streaming uploader)
- Modify: `lib/features/chat/domain/entities/message.dart` (`uploadProgress`)
- Modify: `lib/features/chat/presentation/state/chat_state.dart` (`_attemptSend` upload call, `_settleCancelledSend`, `cancelSend`, `_publishUploadProgress`, `retryMessage`)
- Modify: `lib/features/chat/presentation/widgets/message_bubble.dart` (`onCancelSend` threading; `_MediaBusyOverlay(progress, onCancel)`; video tile)
- Modify: `lib/features/chat/presentation/widgets/video_message_thumbnail.dart` (`onCancel`; stop glyph removed)
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart` (`MessageBubble(onCancelSend:)`)
- Modify: `test/features/chat/support/chat_test_harness.dart` (`FakeChatRepository.uploadChatMedia`)
- Modify: `test/features/chat/video_message_thumbnail_test.dart`, `test/features/chat/message_bubble_test.dart` (add tests)

**Interfaces:**
- Consumes: Supabase Storage object endpoint `POST {storage.url}/object/{bucket}/{key}` with `apikey` + `Authorization: Bearer <session JWT>` plus `content-type`, `x-upsert: false`, `cache-control: max-age=3600` — the same request storage_client 2.5.5 builds, minus multipart (the API accepts a raw body). NOTE (verified in supabase 2.12.1 `supabase_client.dart`): `storage.headers` carries the **anon key** only; the person's JWT is injected per request by the SDK's `AuthHttpClient` (`_getAccessToken`, which also refreshes an expired session). The streaming uploader bypasses that client, so the repository supplies the bearer itself — otherwise Storage RLS sees an anonymous upload (403) and Task 5 classifies it permanent. Also `package:http` `StreamedRequest`/`Client`, `StorageException(message, statusCode:)` so Task 5's classification applies, `_updateOptimisticMessage(clientMessageId, Message Function(Message))` (chat_state), `PendingSendState.failedPermanent`, `MessageStatus.failed`.
- Produces:
  - `class ChatUploadCancelToken { bool get isCancelled; void cancel(); void onCancel(VoidCallback); }`, `class ChatUploadCancelled implements Exception`.
  - `class ChatMediaUploader { ChatMediaUploader({required String Function() storageUrl, required Future<Map<String,String>> Function() headers, http.Client Function()? clientFactory}); Future<void> upload({required String bucket, required String objectKey, required String localPath, required String mimeType, void Function(int sent, int total)? onProgress, ChatUploadCancelToken? cancelToken}); }` (`headers` is async: the repository may refresh the session before answering).
  - `ChatRepository.uploadChatMedia({required ChatMediaUploadIntent intent, required String localPath, required String mimeType, void Function(double fraction)? onProgress, ChatUploadCancelToken? cancelToken})`.
  - `Message.uploadProgress` (`double?`, 0..1; null = not reported).
  - `ChatController.cancelSend(Message message)` (sync; no-op when no upload is in flight).
  - `MessageBubble.onCancelSend: void Function(Message)?`, `VideoMessageThumbnail.onCancel: VoidCallback?`.
  - `FakeChatRepository`: `uploadProgressScript` (List<double>), `uploadGate` (Completer<void>?), `lastUploadCancelToken`.

Ruling: resumable (TUS) uploads are not built. Media is capped at 25 MB, Wave 1 adds flush-on-reconnect, and a restart from byte 0 under a new intent is correct and simple; the stop glyph that did nothing is replaced by a real cancel.

- [ ] **Step 1: Write the failing uploader tests**

`test/features/chat/chat_media_uploader_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

/// Accepts the request body (so progress fires) but never answers until
/// closed, which is what cancelling does to it.
class _HangingClient extends http.BaseClient {
  final _completer = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    unawaited(request.finalize().drain<void>());
    return _completer.future;
  }

  @override
  void close() {
    closed = true;
    if (!_completer.isCompleted) {
      _completer.completeError(http.ClientException('Connection closed'));
    }
  }
}

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uploader');
    file = File('${dir.path}/clip.mp4')
      ..writeAsBytesSync(List<int>.generate(300 * 1024, (i) => i % 251));
  });
  tearDown(() => dir.delete(recursive: true));

  ChatMediaUploader uploader(http.Client client) => ChatMediaUploader(
        storageUrl: () => 'https://x.supabase.co/storage/v1',
        headers: () async => {'Authorization': 'Bearer jwt', 'apikey': 'anon'},
        clientFactory: () => client,
      );

  test('POSTs the raw bytes to the object endpoint with storage headers',
      () async {
    http.BaseRequest? seen;
    var received = 0;
    final client = MockClient.streaming((request, body) async {
      seen = request;
      received = (await body.toBytes()).length;
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"Key":"message-media/k"}')), 200);
    });

    await uploader(client).upload(
      bucket: 'message-media',
      objectKey: 'chat-media/abc.mp4',
      localPath: file.path,
      mimeType: 'video/mp4',
    );

    expect(seen!.method, 'POST');
    expect(seen!.url.toString(),
        'https://x.supabase.co/storage/v1/object/message-media/chat-media/abc.mp4');
    expect(seen!.headers['Authorization'], 'Bearer jwt');
    expect(seen!.headers['apikey'], 'anon');
    expect(seen!.headers['content-type'], 'video/mp4');
    expect(seen!.headers['x-upsert'], 'false');
    expect(seen!.contentLength, 300 * 1024);
    expect(received, 300 * 1024);
  });

  test('reports monotonic progress up to the full length', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    final seen = <int>[];
    await uploader(client).upload(
      bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'audio/mp4',
      onProgress: (sent, total) {
        expect(total, 300 * 1024);
        seen.add(sent);
      },
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 300 * 1024);
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
  });

  test('a non-2xx reply becomes a StorageException with that status', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":"Payload too large"}')), 413);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'image/jpeg'),
      throwsA(isA<StorageException>().having((e) => e.statusCode, 'status', '413')),
    );
  });

  test('a 503 keeps its status too (retryable upstream)', () async {
    final client = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(Stream.value(utf8.encode('down')), 503);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'image/jpeg'),
      throwsA(isA<StorageException>().having((e) => e.statusCode, 'status', '503')),
    );
  });

  test('cancel aborts the request and surfaces ChatUploadCancelled', () async {
    final client = _HangingClient();
    final token = ChatUploadCancelToken();
    var progressed = Completer<void>();
    final future = uploader(client).upload(
      bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
      cancelToken: token,
      onProgress: (sent, total) {
        if (!progressed.isCompleted) progressed.complete();
      },
    );
    await progressed.future;
    token.cancel();
    await expectLater(future, throwsA(isA<ChatUploadCancelled>()));
    expect(client.closed, isTrue);
  });

  test('a token cancelled before the upload starts short-circuits', () async {
    final token = ChatUploadCancelToken()..cancel();
    var sent = false;
    final client = MockClient.streaming((request, body) async {
      sent = true;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4',
          cancelToken: token),
      throwsA(isA<ChatUploadCancelled>()),
    );
    expect(sent, isFalse);
  });

  test('a dropped socket is a ClientException (classified offline upstream)',
      () async {
    final client = MockClient.streaming((request, body) async {
      throw http.ClientException('Connection reset');
    });
    await expectLater(
      uploader(client).upload(
          bucket: 'b', objectKey: 'k', localPath: file.path, mimeType: 'video/mp4'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('the repository signs the streamed upload with the session JWT, not the anon key',
      () {
    // storage.headers holds only the apikey; the SDK's AuthHttpClient adds
    // the person's bearer per request. Bypassing that client without doing
    // the same makes every media upload an anonymous one (Storage RLS 403,
    // which Task 5 rightly calls permanent).
    final src = File(
      'lib/features/chat/data/repositories/supabase_chat_repository.dart',
    ).readAsStringSync();
    final headers = src.substring(src.indexOf('_uploadHeaders() async {'));
    final beforeReturn = headers.substring(0, headers.indexOf('return {'));
    expect(beforeReturn, contains('currentSession?.isExpired'));
    expect(beforeReturn, contains('refreshSession()'));
    expect(beforeReturn, contains('currentSession?.accessToken'));
    expect(headers, contains("'Authorization': 'Bearer \$token'"));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/chat/chat_media_uploader_test.dart`
Expected: compile error (missing `chat_media_uploader.dart`). (The last test is a source guard on the repository; it passes only after Step 5.)

- [ ] **Step 3: Write the uploader**

`lib/features/chat/data/repositories/chat_media_uploader.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

/// Lets the person stop an upload. Cancelling closes the HTTP client, which
/// aborts the in-flight request.
class ChatUploadCancelToken {
  bool _cancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void onCancel(VoidCallback listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }
}

class ChatUploadCancelled implements Exception {
  const ChatUploadCancelled();
  @override
  String toString() => 'ChatUploadCancelled';
}

/// Streams a file to Supabase Storage with byte progress and cancel.
///
/// storage_client 2.5.5 reads the whole file into memory and offers neither
/// progress nor an abort (its StorageRetryController only skips retries), so
/// a 25 MB video showed an indeterminate spinner with a stop glyph that did
/// nothing (chat review #25). This sends the same request the SDK sends —
/// POST /object/{bucket}/{key} with the SDK's own headers — as a raw
/// streamed body. Failures are raised as [StorageException] with the HTTP
/// status so ChatError classifies them like SDK failures.
class ChatMediaUploader {
  ChatMediaUploader({
    required String Function() storageUrl,
    required Future<Map<String, String>> Function() headers,
    http.Client Function()? clientFactory,
  }) : _storageUrl = storageUrl,
       _headers = headers,
       _clientFactory = clientFactory ?? http.Client.new;

  final String Function() _storageUrl;

  /// apikey + the person's CURRENT bearer. Async because the repository may
  /// refresh an expired session first (the SDK's AuthHttpClient does the
  /// same for every request it sends; this uploader bypasses it).
  final Future<Map<String, String>> Function() _headers;
  final http.Client Function() _clientFactory;

  Future<void> upload({
    required String bucket,
    required String objectKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
    final file = File(localPath);
    final total = await file.length();
    final headers = await _headers();
    if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
    final client = _clientFactory();
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('${_storageUrl()}/object/$bucket/$objectKey'),
    )
      ..headers.addAll(headers)
      ..headers['content-type'] = mimeType
      ..headers['x-upsert'] = 'false'
      ..headers['cache-control'] = 'max-age=3600'
      ..contentLength = total;
    cancelToken?.onCancel(client.close);

    final pump = _pump(file, request, total, onProgress, cancelToken);
    try {
      final response = await client.send(request);
      final body = await response.stream.bytesToString();
      if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StorageException(
          body.isEmpty ? 'upload failed' : body,
          statusCode: '${response.statusCode}',
        );
      }
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
      rethrow;
    } finally {
      await pump;
      client.close();
    }
  }

  Future<void> _pump(
    File file,
    http.StreamedRequest request,
    int total,
    void Function(int, int)? onProgress,
    ChatUploadCancelToken? cancelToken,
  ) async {
    var sent = 0;
    try {
      await for (final chunk in file.openRead()) {
        if (cancelToken?.isCancelled == true) return;
        request.sink.add(chunk);
        sent += chunk.length;
        onProgress?.call(sent, total);
      }
    } catch (_) {
      // The request was aborted; send() reports the cause.
    } finally {
      try {
        await request.sink.close();
      } catch (_) {}
    }
  }
}
```

- [ ] **Step 4: Run the uploader tests**

Run: `flutter test test/features/chat/chat_media_uploader_test.dart`
Expected: 7 pass; `the repository signs the streamed upload …` still fails (no `_uploadHeaders` yet) until Step 5.

- [ ] **Step 5: Repository signature + implementation**

`chat_repository.dart`: import `chat_media_uploader.dart`; change the abstract method to

```dart
  /// Uploads the prepared file for [intent]. [onProgress] receives 0..1;
  /// [cancelToken] aborts the request ([ChatUploadCancelled]).
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  });
```

`supabase_chat_repository.dart`: constructor becomes `SupabaseChatRepository(this._supabase, {ChatMediaUploader? uploader}) : _uploader = uploader;` with

```dart
  ChatMediaUploader? _uploader;
  ChatMediaUploader get _mediaUploader =>
      _uploader ??= ChatMediaUploader(
        storageUrl: () => _supabase.storage.url,
        headers: _uploadHeaders,
      );

  /// What the SDK's AuthHttpClient adds to every Storage request, done by
  /// hand because the streaming uploader bypasses that client:
  /// storage.headers carries the apikey only, the person's bearer is
  /// injected per request (supabase 2.12.1 `_getAccessToken`, which also
  /// refreshes an expired session). With the anon key alone Storage RLS
  /// answers 403 and ChatError calls that permanent.
  Future<Map<String, String>> _uploadHeaders() async {
    final auth = _supabase.auth;
    if (auth.currentSession?.isExpired ?? false) {
      try {
        await auth.refreshSession();
      } catch (_) {
        // A failed refresh surfaces as a 401 from Storage, which Task 5
        // classifies transient: the row is retried after the SDK's own
        // refresh lands.
      }
    }
    final token = auth.currentSession?.accessToken;
    return {
      ..._supabase.storage.headers,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) {
    return _mediaUploader.upload(
      bucket: intent.bucket,
      objectKey: intent.storageKey,
      localPath: localPath,
      mimeType: mimeType,
      cancelToken: cancelToken,
      onProgress:
          onProgress == null
              ? null
              : (sent, total) => onProgress(total <= 0 ? 1.0 : sent / total),
    );
  }
```

`FakeChatRepository.uploadChatMedia` (harness; add `import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';`):

```dart
  /// Progress fractions emitted (in order) before an upload completes.
  List<double> uploadProgressScript = const [];

  /// When set, the upload waits on it (mid-flight) before completing; if the
  /// token was cancelled while waiting the upload throws ChatUploadCancelled.
  Completer<void>? uploadGate;
  ChatUploadCancelToken? lastUploadCancelToken;

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    _mediaCallCount++;
    lastUploadCancelToken = cancelToken;
    final failure = mediaCallFailures[_mediaCallCount];
    if (failure != null) throw failure;
    for (final fraction in uploadProgressScript) {
      onProgress?.call(fraction);
    }
    final gate = uploadGate;
    if (gate != null) {
      await gate.future;
      if (cancelToken?.isCancelled == true) throw const ChatUploadCancelled();
    }
  }
```

- [ ] **Step 6: Write the failing controller tests**

`test/features/chat/chat_upload_progress_cancel_test.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_cancel');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });
  tearDown(() => tempDir.delete(recursive: true));

  Future<(ChatController, ChatState Function())> boot(FakeChatRepository repo) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (controller, () => container.read(chatControllerProvider(convo)));
  }

  Future<String> voiceFile(String name) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(List.filled(256, 1));
    return path;
  }

  test('upload progress reaches the optimistic bubble', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadProgressScript = const [0.25, 0.5, 1.0]
      ..uploadGate = Completer<void>();
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('a.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.uploadProgress, 1.0);
    expect(state().messages.single.status, MessageStatus.sending);

    repo.uploadGate!.complete();
    await send;
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('cancel mid-upload fails the row quietly; no auto-retry; retry works',
      () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadGate = Completer<void>();
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('c.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sending);

    controller.cancelSend(state().messages.single);
    expect(repo.lastUploadCancelToken!.isCancelled, isTrue);
    repo.uploadGate!.complete();
    await send;

    final failed = state().messages.single;
    expect(failed.status, MessageStatus.failed);
    expect(state().error, isNull, reason: 'the person asked for this; no banner');
    expect(repo.sendCallCount, 0);

    // The row is parked (failedPermanent), not retried by the next flush.
    await controller.flushOutbox();
    expect(repo.sendCallCount, 0);

    repo.uploadGate = null;
    await controller.retryMessage(failed);
    expect(state().messages.single.status, MessageStatus.sent);
    expect(repo.sendCallCount, 1);
  });

  test('cancel after the bytes are up is a no-op: the message still lands',
      () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..sendDelay = const Duration(milliseconds: 80);
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('d.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // Upload finished instantly (fake); the row insert is in its 80 ms delay.
    controller.cancelSend(state().messages.single);
    await send;
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('retry resets the ring to the start', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadProgressScript = const [0.7]
      ..mediaCallFailures[2] = Exception('boom');
    final (controller, state) = await boot(repo);
    await controller.sendVoiceMessage(
        localPath: await voiceFile('e.m4a'), durationMs: 1000, waveform: const [1]);
    final queued = state().messages.single;
    expect(queued.status, MessageStatus.queued);
    repo.uploadProgressScript = const [];
    await controller.retryMessage(queued);
    expect(state().messages.single.status, MessageStatus.sent);
  });
}
```

Coalescing is asserted at the unit level (the fake emits its script synchronously, so a controller-level count would prove nothing). Add this test at the end of `main`:

```dart
  test('_publishUploadProgress coalesces sub-2% steps', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final (controller, state) = await boot(repo);
    final seen = <double>[];
    for (var i = 1; i <= 100; i++) {
      final v = i / 100;
      if (controller.debugShouldPublishUploadProgress('cid', v)) seen.add(v);
    }
    expect(seen.length, lessThanOrEqualTo(51));
    expect(seen.last, 1.0);
  });
```

- [ ] **Step 7: Run to verify failure**

Run: `flutter test test/features/chat/chat_upload_progress_cancel_test.dart`
Expected: compile errors (`uploadProgressScript`, `uploadGate`, `cancelSend`, `uploadProgress`, `debugShouldPublishUploadProgress` undefined).

- [ ] **Step 8: `Message.uploadProgress`**

In `message.dart`: add `final double? uploadProgress;` beside `compressProgress` with the doc `/// 0..1 while the bytes are being uploaded (null when not reported). Only the optimistic row carries it; the canonical row replaces it.`; add `this.uploadProgress,` to the constructor (after `this.compressProgress,`), `double? uploadProgress,` to `copyWith` and `uploadProgress: uploadProgress ?? this.uploadProgress,` in its body.

- [ ] **Step 9: Controller changes (`chat_state.dart`)**

Add fields near `_inFlightClientIds`:

```dart
  /// In-flight upload cancel tokens by clientMessageId (chat review #25).
  final Map<String, ChatUploadCancelToken> _uploadCancelTokens = {};
  final Map<String, double> _lastPublishedUploadProgress = {};
```

In `_attemptSend`, replace the FIRST `await repository.uploadChatMedia(intent: intent, localPath: pending.localMediaPath!, mimeType: pending.mediaMimeType!);` (the main media upload, not the thumbnail one) with:

```dart
        final cancelToken = ChatUploadCancelToken();
        _uploadCancelTokens[pending.clientMessageId] = cancelToken;
        try {
          await repository.uploadChatMedia(
            intent: intent,
            localPath: pending.localMediaPath!,
            mimeType: pending.mediaMimeType!,
            cancelToken: cancelToken,
            onProgress:
                (fraction) =>
                    _publishUploadProgress(pending.clientMessageId, fraction),
          );
        } finally {
          _uploadCancelTokens.remove(pending.clientMessageId);
        }
```

Between the `on PostgrestException catch (error) { … }` block and the generic `catch (error)` of `_attemptSend`, add:

```dart
    } on ChatUploadCancelled {
      await _settleCancelledSend(user.id, durablePending);
```

Add the methods (after `_handleSendFailure`):

```dart
  /// The person stopped an upload: the row becomes a failed bubble they can
  /// retry or remove. Parked as failedPermanent so no flush retries it, and
  /// no banner — they asked for this.
  Future<void> _settleCancelledSend(String userId, PendingSend pending) async {
    await ref
        .read(chatCacheServiceProvider)
        .putOutbox(
          userId,
          pending.copyWith(
            state: PendingSendState.failedPermanent,
            lastErrorCategory: 'cancelled',
            nextAttemptAt: null,
          ),
        );
    if (!mounted) return;
    state = state.copyWith(
      isSending: false,
      messages:
          state.messages
              .map(
                (message) =>
                    message.clientMessageId == pending.clientMessageId
                        ? message.copyWith(status: MessageStatus.failed)
                        : message,
              )
              .toList(),
    );
  }

  /// Stops the in-flight upload of [message], if there is one. Once the
  /// bytes are up and only the row insert remains there is nothing to stop:
  /// the send completes.
  void cancelSend(Message message) {
    _uploadCancelTokens[message.clientMessageId]?.cancel();
  }

  /// At most ~50 bubble rebuilds per upload: skip steps under 2% except
  /// the final one.
  @visibleForTesting
  bool debugShouldPublishUploadProgress(String clientMessageId, double fraction) {
    final last = _lastPublishedUploadProgress[clientMessageId] ?? -1.0;
    if (fraction < 1.0 && fraction - last < 0.02) return false;
    if (fraction >= 1.0) {
      _lastPublishedUploadProgress.remove(clientMessageId);
    } else {
      _lastPublishedUploadProgress[clientMessageId] = fraction;
    }
    return true;
  }

  void _publishUploadProgress(String clientMessageId, double fraction) {
    if (!debugShouldPublishUploadProgress(clientMessageId, fraction)) return;
    _updateOptimisticMessage(
      clientMessageId,
      (message) => message.copyWith(uploadProgress: fraction),
    );
  }
```

In `retryMessage`, change `entry.copyWith(status: MessageStatus.sending)` to `entry.copyWith(status: MessageStatus.sending, uploadProgress: 0)`. In `dispose()`, cancel nothing (an upload may outlive the screen); the tokens are dropped with the controller. Import `chat_media_uploader.dart`.

- [ ] **Step 10: Run the controller tests**

Run: `flutter test test/features/chat/chat_media_uploader_test.dart test/features/chat/chat_upload_progress_cancel_test.dart test/features/chat/chat_state_send_voice_message_test.dart test/features/chat/chat_state_send_video_message_test.dart test/features/chat/streak_media_send_test.dart test/features/chat/streak_outbox_test.dart`
Expected: all pass (the uploader file now reports 8, including the repository source guard).

- [ ] **Step 11: Failing UI tests — ring with cancel**

Add to `test/features/chat/video_message_thumbnail_test.dart` (inside the busy group):

```dart
    testWidgets('busy ring carries no glyph when there is nothing to cancel',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(
        body: VideoMessageThumbnail(
          thumbnailUrl: null, durationMs: 5000, width: 720, height: 1280,
          showBusyOverlay: true, uploadProgress: 0.3,
        ),
      )));
      expect(find.byIcon(Icons.stop_rounded), findsNothing,
          reason: 'a stop glyph that does nothing is a lie');
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('busy ring shows a cancel glyph that calls onCancel',
        (tester) async {
      var cancelled = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: VideoMessageThumbnail(
          thumbnailUrl: null, durationMs: 5000, width: 720, height: 1280,
          showBusyOverlay: true, uploadProgress: 0.3,
          onCancel: () => cancelled++,
        ),
      )));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Stop sending'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cancelled, 1);
    });
```

Add to `test/features/chat/message_bubble_test.dart` (imports: `dart:io`, `package:image/image.dart as img`):

```dart
  testWidgets('an image on its way out shows a determinate ring and cancel',
      (tester) async {
    final dir = await Directory.systemTemp.createTemp('bubble_img');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/p.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    Message? cancelled;
    final message = Message(
      id: '_local_c9',
      clientMessageId: 'c9',
      relationshipId: 'rel',
      senderId: 'me',
      content: '',
      createdAt: DateTime(2026, 10, 18),
      status: MessageStatus.sending,
      isMine: true,
      mediaType: 'image',
      localMediaPath: file.path,
      uploadProgress: 0.4,
    );
    await _pump(tester, MessageBubble(message: message, onCancelSend: (m) => cancelled = m));
    await tester.pump();
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, closeTo(0.4, 0.001));
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(cancelled?.clientMessageId, 'c9');
  });
```

Run: `flutter test test/features/chat/video_message_thumbnail_test.dart test/features/chat/message_bubble_test.dart`
Expected: the new tests fail (`onCancel`/`onCancelSend` undefined; `stop_rounded` found).

- [ ] **Step 12: UI implementation**

`video_message_thumbnail.dart`: add `this.onCancel,` to the constructor and `final VoidCallback? onCancel;` with doc `/// Stops the send; null while nothing can be stopped (compressing).`. In the busy-ring `Stack`, replace the `Icon(Icons.stop_rounded, …)` child with:

```dart
                        if (widget.onCancel != null)
                          Semantics(
                            button: true,
                            label: 'Stop sending',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onCancel,
                              child: Icon(
                                Icons.close_rounded,
                                size: 22,
                                color: Colors.white.withValues(alpha: 0.95),
                              ),
                            ),
                          ),
```

Update the comment above the ring: "Progress ring over the poster; the centre is a cancel button only while the upload can actually be stopped (chat review #25)". Wrap the whole busy `Center(...)` so the tile's own `onTap` (null while preparing anyway) does not swallow the cancel tap — the GestureDetector above is opaque and inside the ring, which is enough.

`message_bubble.dart`:
1. `MessageBubble`: add `this.onCancelSend,` + `final void Function(Message message)? onCancelSend;` (doc: "Stops an in-flight upload of one of my media messages."); pass `onCancelSend: onCancelSend,` where `_BubbleBody(... onVideoTap: onVideoTap, ...)` is constructed; `_BubbleBody` gets the same field.
2. `_MediaBusyOverlay` becomes:

```dart
class _MediaBusyOverlay extends StatelessWidget {
  const _MediaBusyOverlay({this.progress, this.onCancel});
  /// 0..1 upload progress; null = indeterminate.
  final double? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sending',
      child: Container(
        width: 220,
        height: 220,
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              if (onCancel != null)
                Semantics(
                  button: true,
                  label: 'Stop sending',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCancel,
                    child: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

3. Image tile: `children: [thumbnail, _MediaBusyOverlay(progress: message.uploadProgress, onCancel: onCancelSend == null ? null : () => onCancelSend!(message))]` and update the comment ("Determinate once the uploader reports bytes; the ring centre cancels").
4. Video tile: `uploadProgress: isBusy ? (message.isPreparing ? message.compressProgress : message.uploadProgress) : null,` and `onCancel: (!message.isPreparing && message.isSending && onCancelSend != null) ? () => onCancelSend!(message) : null,`.

`chat_screen.dart`: where `MessageBubble(` is built in the list (the call that passes `onVideoTap: (tapped) async {`), add

```dart
                          onCancelSend:
                              (toCancel) => ref
                                  .read(chatControllerProvider(conversation).notifier)
                                  .cancelSend(toCancel),
```

- [ ] **Step 13: Run the UI and bubble suites**

Run: `flutter test test/features/chat/video_message_thumbnail_test.dart test/features/chat/message_bubble_test.dart test/features/chat/presentation/widgets/message_bubble_test.dart test/features/chat/chat_media_group_test.dart test/features/chat/chat_screen_header_test.dart test/features/chat/pending_send_video_test.dart`
Expected: all pass. The old thumbnail test `'falls back to an indeterminate ring when there is no progress signal (the upload phase)'` still passes (null progress → indeterminate); its name is now historical — leave it.

- [ ] **Step 14: Full chat suite**

Run: `flutter test test/features/chat`
Expected: all pass. Any failure in a test not named in this plan is a regression to fix before the checkpoint, not a test to edit.

- [ ] **Step 15: Checkpoint**

Checkpoint: run this task's tests and `flutter analyze lib/features/chat test/features/chat lib/features/auth/providers/auth_provider.dart | grep -E '^\s*(error|warning) '` (expect no output); no commit (the owner commits).

---

## Self-review

1. **Spec/issue coverage:** #20 → T3, #21 → T7, #22 → T6, #23 → T1, #24 → T2, #25 → T9, #26 → T5, #27 → T3, #28 → T8, #29 → T4. Spec rules kept: one-at-a-time playback app-wide and stop-on-leave (T7 `stop()` in `_ChatScreenState.dispose`), signed URLs never persisted (T6/T8 cache by key only), §8.1 EXIF strip + 1600 + 800 KB (T3 tests), delete tombstone unchanged (T1 keeps the UPDATE and error codes).
2. **Placeholders:** none — every step carries code or an exact command; T9 Step 6 explicitly removes its illustrative second test before running.
3. **Type consistency:** `ChatUploadCancelToken`/`ChatUploadCancelled` (T9) are the names used in the harness and `chat_state`; `ChatMediaCache(manager:)` (T8) matches the harness override; `signMediaUrlFailuresBeforeSuccess` (T6) is the harness field; `VoiceMessagePlayer.mediaKey` is added in T7 and used in T8; `ChatError.forMedia` (T5) is the method `_handleSendFailure` calls; `SignedMediaUrlUnavailable` is thrown by the provider and matched in T6 tests.
4. **Review Focus pins:** HEIC → T3 Step 6; position reset on switch → T7 test `starting another message stops the first and resets position`; connectivity flip → T6 test; empty cached file → T8 test; cancel after bytes up → T9 test.

## Owner deploy steps

1. Apply migrations to the live project in order: `20261019120000_delete_message_queues_media.sql`, `20261019120100_chat_media_cron_fix.sql` (`supabase db push` or the SQL editor). Verify: `select jobname, command from cron.job where jobname in ('recover-stale-chat-workers','cleanup-expired-chat-media');`.
2. No edge function changes in this wave. `process-media-deletion-queue` (already scheduled by 20260930130000) drains the rows `delete_message` now queues; confirm it is scheduled live: `select jobname from cron.job where command like '%process-media-deletion-queue%';`.
3. Device checks (two phones): send a 12 MP photo → pinch-zoom on the receiver is sharp; play a 2-minute voice note and scroll far → keeps playing, speed chip cycles, phone call pauses it and tap resumes; open a photo in airplane mode → broken tile, go online → heals (or tap); delete a photo for everyone → `select * from media_deletion_queue order by requested_at desc limit 3;` shows the key; send a 20 MB video on cellular → ring fills, tap ✕ → "Tap to retry" row, retry sends; replay a voice note in airplane mode after one online play → plays.
4. Follow-ups noted, not built: `audio_session` interruption API (T7 ruling), byte-budgeted media cache (T8 ruling), optional crop on the caption screen (review M-9), TUS resumable uploads (T9 ruling).
