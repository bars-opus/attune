-- supabase/migrations/20260902120000_chat_ephemeral_video_final_review_fixes.sql
--
-- Final whole-branch review of the ephemeral (view-once) video capture
-- feature (20260816130000_chat_ephemeral_video.sql,
-- 20260816140000_chat_screenshot_notice.sql) found three Critical gaps that
-- only a cross-task, whole-branch view could catch — every per-task review
-- in this branch tested against FakeChatRepository
-- (test/features/chat/support/chat_test_harness.dart), which reimplements
-- mark_video_viewed as an in-memory copyWith with zero real Postgres
-- constraint/grant enforcement, so none of this was ever exercised against
-- actual SQL. Per this repo's own convention (see
-- 20260828120000_chat_message_replies_select_grant.sql, a follow-up file
-- rather than an edit to the migration it fixes), this ships as a new file
-- rather than editing either already-committed migration.
--
-- ---------------------------------------------------------------------
-- FIX 1 (Critical): mark_video_viewed's final UPDATE violates
-- messages_payload_present on every real call.
-- ---------------------------------------------------------------------
--
-- messages_payload_present, as last defined by
-- 20260831120000_message_actions.sql (lines 43-59), requires:
--   deleted_at IS NOT NULL
--   OR (content IS NOT NULL AND char_length(btrim(content)) > 0)
--   OR media_url IS NOT NULL
--
-- An ephemeral video message is sent with content = '' (or possibly NULL —
-- either way btrim/char_length yields not-satisfied) and deleted_at IS
-- NULL. mark_video_viewed's final statement
-- (20260816130000_chat_ephemeral_video.sql:103-105) does:
--   UPDATE public.messages SET media_url = NULL, media_thumbnail_url = NULL
--   WHERE id = p_message_id;
-- which drives all three disjuncts false simultaneously -> 23514 constraint
-- violation -> the entire function's transaction rolls back, including the
-- earlier viewed_at write in the SAME function invocation. Net effect: the
-- video is never deleted, silently, and the client's RPC call fails on
-- every single real invocation, not just an edge case.
--
-- Fix: widen the constraint to also admit a viewed, view-once row, exactly
-- mirroring how 20260831120000_message_actions.sql itself widened this
-- same constraint for soft-deleted rows (deleted_at IS NOT NULL). This
-- keeps every existing guarantee intact for every other row shape (a live,
-- non-view-once message must still carry content or media_url) while
-- allowing the one new legitimate empty-payload shape: a tombstoned
-- view-once video.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_payload_present'
  ) THEN
    ALTER TABLE public.messages DROP CONSTRAINT messages_payload_present;
  END IF;

  ALTER TABLE public.messages
    ADD CONSTRAINT messages_payload_present
    CHECK (
      deleted_at IS NOT NULL
      OR (is_view_once = true AND viewed_at IS NOT NULL)
      OR (content IS NOT NULL AND char_length(btrim(content)) > 0)
      OR media_url IS NOT NULL
    );
END
$$;

-- ---------------------------------------------------------------------
-- FIX 2 (Critical): missing column-level grants for is_view_once,
-- viewed_at, is_system_notice — breaks ALL chat sends, not just ephemeral.
-- ---------------------------------------------------------------------
--
-- This table has never used a table-wide GRANT; every column authenticated
-- can read/write is an explicit allowlist (established
-- 20260705190000_chat_system_v1_3.sql, most recently extended by
-- 20260831120000_message_actions.sql for SELECT and
-- 20260827120000_chat_message_replies.sql for INSERT). Neither
-- 20260816130000_chat_ephemeral_video.sql nor
-- 20260816140000_chat_screenshot_notice.sql added grants for the three
-- columns they introduced (is_view_once, viewed_at, is_system_notice).
--
-- SupabaseChatRepository.sendTextMessage
-- (lib/features/chat/data/repositories/supabase_chat_repository.dart)
-- unconditionally includes is_view_once and is_system_notice keys in
-- EVERY insert it issues, ephemeral or not, and _messageColumns
-- unconditionally selects is_view_once, viewed_at, is_system_notice on
-- EVERY read. Without this grant, every chat message send/read in
-- production — not just ephemeral video — fails with 42501.
--
-- While tracing the "confirm the complete current INSERT/SELECT column
-- list" instruction against the live files, this review also found FOUR
-- PRE-EXISTING columns with the exact same gap, predating this feature
-- branch: media_duration_ms, media_waveform (added by
-- 20260815120000_chat_voice_messages.sql) and media_width, media_height
-- (added by 20260816120000_chat_video_media_dimensions.sql) — grep across
-- every migration confirms no GRANT statement, INSERT or SELECT, has ever
-- named any of these four columns, yet sendTextMessage's insert map and
-- _messageColumns both reference all four unconditionally today. Since
-- this fix wave is already rebuilding the complete, current, correct
-- allowlist from the live insert/select code (per the review brief's own
-- instruction not to guess or transcribe an incomplete list), these four
-- are included here too — leaving them out would just leave a second,
-- already-live 42501 trap sitting next to the one this migration exists to
-- close.
--
-- SELECT: additive grant, safe to add without touching any other column.
GRANT SELECT (
  is_view_once,
  viewed_at,
  is_system_notice,
  media_duration_ms,
  media_waveform,
  media_width,
  media_height
) ON public.messages TO authenticated;

-- INSERT: this table's INSERT grant is REPLACED wholesale on each widening
-- (REVOKE INSERT then re-GRANT the full list), not additive per-column
-- like SELECT — matching the exact pattern
-- 20260827120000_chat_message_replies.sql used. The list below is the
-- complete, current set of every key
-- SupabaseChatRepository.sendTextMessage's insert map sends today
-- (verified directly against that file's insert({...}) call, not
-- transcribed from memory):
--   relationship_id, sender_id, client_message_id, content, media_url,
--   media_type, media_duration_ms, media_waveform, media_thumbnail_url,
--   media_width, media_height, reply_to_message_id, quoted_text,
--   is_view_once, is_system_notice
--
-- viewed_at is DELIBERATELY EXCLUDED from this INSERT grant — see FIX 3's
-- comment below for why this must never be added.
REVOKE INSERT ON public.messages FROM authenticated;
GRANT INSERT (
  relationship_id,
  sender_id,
  client_message_id,
  content,
  media_url,
  media_type,
  media_duration_ms,
  media_waveform,
  media_thumbnail_url,
  media_width,
  media_height,
  reply_to_message_id,
  quoted_text,
  is_view_once,
  is_system_notice
) ON public.messages TO authenticated;

-- ---------------------------------------------------------------------
-- FIX 3 (Critical, documentation only): is_view_once has no server-side
-- enforcement against the chat_ephemeral_video feature flag.
-- ---------------------------------------------------------------------
--
-- There is no CHECK, trigger, or RLS policy tying is_view_once = true to
-- the chat_ephemeral_video feature flag being enabled. The three-way
-- client-side flag gate (chat_video_sharing AND chat_image_sharing AND
-- chat_ephemeral_video, wired in chat_screen.dart) is UI convenience only.
-- A client with video/image sharing enabled but chat_ephemeral_video
-- disabled could still construct an is_view_once: true insert directly —
-- create_chat_media_upload_intent has no way to know a video intent is
-- "for an ephemeral capture" (see 20260816130000_chat_ephemeral_video.sql's
-- own header comment), and now that FIX 2 above grants INSERT (is_view_once)
-- broadly to authenticated, nothing stops a client from setting it on any
-- video/image send regardless of that flag's state.
--
-- ACCEPTED, DOCUMENTED GAP for this iteration (not fixed here — a
-- BEFORE INSERT trigger enforcing this is a larger, separate piece of work
-- better suited to its own reviewed task):
--   - is_view_once and is_system_notice are NOT server-validated against
--     their respective feature flags (chat_ephemeral_video,
--     and there is no flag at all gating is_system_notice — screenshot
--     notices were deliberately built with no feature-flag concept, see
--     20260816140000_chat_screenshot_notice.sql).
--   - Blast radius is limited: a user can only make their OWN sent message
--     more ephemeral (self-revoking on view) or attach a fake system-notice
--     label to their OWN message. Neither lets a user affect another
--     user's messages, read another user's data, or bypass relationship
--     membership — mark_video_viewed independently re-validates relationship
--     membership (via the `relationship_id IN (SELECT id FROM
--     relationships WHERE status = 'active' AND ...)` predicate) regardless
--     of how is_view_once got set on the row, so this gap does not weaken
--     mark_video_viewed's own authorization.
--   - Candidate future fix, if this becomes a real concern: a BEFORE INSERT
--     trigger on public.messages that checks feature_flags for
--     'chat_ephemeral_video' the same way create_chat_media_upload_intent
--     already does per-media-type flag checks
--     (20260815130000_chat_video_messages.sql), rejecting an insert with
--     is_view_once = true when the flag is disabled.
--
-- This comment supersedes the impression left by
-- 20260816130000_chat_ephemeral_video.sql's own header comment, which
-- describes the client-side gate without stating explicitly that no
-- server-side backstop exists at all for is_view_once itself (as opposed
-- to the video-vs-image media type gate, which IS server-enforced).
