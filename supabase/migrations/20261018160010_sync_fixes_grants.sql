-- Sync audit: grants for 20261018160000, and M-15 (trigger functions never
-- callable by clients).
REVOKE ALL ON FUNCTION public.presence_purge_on_relationship_close() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cancel_chat_imports_on_relationship_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_one_open_chapter_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_stale_personal_rows() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_stale_personal_rows() TO service_role;
REVOKE ALL ON FUNCTION public.sync_dating_pause_on_relationship() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_purge_busy_on_end() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_revoke_feeds_on_end() FROM PUBLIC, anon, authenticated;
