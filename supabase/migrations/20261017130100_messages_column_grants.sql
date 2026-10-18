-- supabase/migrations/20261017130100_messages_column_grants.sql
--
-- messages: the client SELECT allowlist (Spec 1a Task 3); message_reads:
-- no client grant at all.
--
-- 20260914130000_streak_grants.sql:19 re-granted table-level SELECT, INSERT,
-- UPDATE on messages to authenticated, cancelling the column allowlist from
-- 20260705190000:35-47. Since then both partners could read read_at AND the
-- per-message analysis columns (tone_score, nvc_violations, bid_type,
-- sentiment ...), which SOUL §8 forbids showing to a partner. Table-level
-- REVOKE does not remove column grants, so every private column is revoked
-- by name as well, then the allowlist is granted. The allowlist is exactly
-- what the Dart client selects (supabase_chat_repository._messageColumns) --
-- read_receipt_at in, read_at out -- and read_receipt_contracts.sql asserts
-- the two sets are equal, so a new column is private until added here.
--
-- Replayed from scripts/local_pg_grants.sql after its blanket grant.
REVOKE SELECT, UPDATE, DELETE ON public.messages FROM PUBLIC, anon, authenticated;
REVOKE SELECT (
  read_at, tone_score, nvc_violations, bid_type, sentiment,
  message_analysis_done, message_analysis_skipped, included_in_session_id,
  safety_processed_at, safety_error_at, safety_error_code,
  import_job_id, source_line_number
) ON public.messages FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, relationship_id, sender_id, client_message_id, content, created_at,
  sort_at, game_session_id, delivered_at, read_receipt_at, media_url,
  media_thumbnail_url, media_type, media_duration_ms, media_waveform,
  media_width, media_height, source, reply_to_message_id, quoted_text,
  deleted_at, edited_at, is_view_once, viewed_at, is_system_notice,
  streak_views_remaining, story_item_id, message_origin, assistant_payload
) ON public.messages TO authenticated;
REVOKE ALL ON public.message_reads FROM PUBLIC, anon, authenticated;
