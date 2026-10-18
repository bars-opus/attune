-- supabase/migrations/20261017140100_story_items_column_grants.sql
--
-- story_items: the client SELECT allowlist (Spec 1a Task 4). has_been_viewed
-- and seen_shown are read only through the SECURITY DEFINER list RPCs, which
-- mask them. Every other column stays readable (the reel, the calendar, the
-- reply-target lookup and the storage policy need them).
--
-- Replayed from scripts/local_pg_grants.sql AFTER the stories replay there,
-- which grants table-level SELECT.
REVOKE SELECT ON public.story_items FROM PUBLIC, anon, authenticated;
REVOKE SELECT (has_been_viewed, seen_shown) ON public.story_items FROM PUBLIC, anon, authenticated;
GRANT SELECT (
  id, client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, duration_ms, occurred_on,
  created_at, expires_at, deleted_at, downscaled_at
) ON public.story_items TO authenticated;
