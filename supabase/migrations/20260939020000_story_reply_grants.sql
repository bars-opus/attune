-- The messages INSERT/SELECT column allowlist for story replies.
--
-- Split out of 20260939010000_story_replies.sql so that
-- scripts/local_pg_grants.sql can \i-replay it AFTER its blanket
-- "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES" -- otherwise the
-- blanket grant re-opens every column locally and the harness cannot see
-- what production actually enforces.
--
-- NOTE: this list must be a SUPERSET of every column any earlier
-- migration granted, because the REVOKE above drops the whole
-- column-level INSERT privilege before this re-grants it. The last
-- migration to widen it was 20260902120000_chat_ephemeral_video_final_
-- review_fixes.sql (15 columns: the media_* set, is_view_once,
-- is_system_notice). Omitting any of them silently breaks voice notes
-- (media_waveform/media_duration_ms), image and video sends
-- (media_width/media_height/media_thumbnail_url) and view-once media in
-- PRODUCTION ONLY -- the local harness's blanket "GRANT INSERT ON ALL
-- TABLES" masks the loss entirely, so no local test can catch it.
-- Verified on a scratch database by replaying 20260902120000's grant,
-- then this block: without these columns listed,
-- has_column_privilege(...,'media_width','INSERT') flips true -> false.
-- streak_views_remaining is listed because the client writes it directly
-- (supabase_chat_repository.dart's sendMessage payload) even though no
-- earlier GRANT names it -- it has been riding on the platform's
-- table-level INSERT, which this REVOKE removes.
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
  is_system_notice,
  streak_views_remaining,
  story_item_id
) ON public.messages TO authenticated;

-- messages' SELECT privilege is column-level too (20260705190000,
-- extended by 20260828120000 for reply_to_message_id/quoted_text) -- the
-- same additive-allowlist shape, and the same class of bug
-- 20260828120000 fixed (an INSERT grant added without its SELECT
-- counterpart) if skipped here.
GRANT SELECT (
  story_item_id
) ON public.messages TO authenticated;
