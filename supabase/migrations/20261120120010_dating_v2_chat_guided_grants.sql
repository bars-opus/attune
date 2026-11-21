-- Spec 2 W6c: grants for 20261120120000_dating_v2_chat_guided.sql. The
-- guided skips are no API role's; the guided state, the skip, We met, the
-- timebox cards, Close kindly and the check-in are the app's; the purge is
-- the cron's (postgres) alone; the helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_guided_skips FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_guided_questions() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_guided_answered(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_guided_state(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_message_visible(public.dating_messages, text) FROM PUBLIC, anon, authenticated, service_role;
-- Task 9 fix round 1 (I-2): where a message sits.
REVOKE ALL ON FUNCTION private.dating_message_sort_at(public.dating_messages) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.purge_dating_retention(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
-- Fix round 1 (M-1): the per-step purge and the cron's procedure.
REVOKE ALL ON FUNCTION private.dating_purge_steps() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_purge_step(text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE public.run_dating_retention_purge(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_guided_state(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_guided_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.skip_dating_guided_question(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.skip_dating_guided_question(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.mark_dating_we_met(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.mark_dating_we_met(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.dismiss_dating_timebox(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_dating_timebox(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.close_dating_match_kindly(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.close_dating_match_kindly(text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.schedule_dating_checkin(timestamptz) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.schedule_dating_checkin(timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.cancel_dating_checkin() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_dating_checkin() TO authenticated;
-- Task 10 fix round 1 (I-1, I-3, I-4).
REVOKE ALL ON FUNCTION public.get_my_dating_checkin() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_checkin() TO authenticated;
REVOKE ALL ON FUNCTION private.dating_has_push_device(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.guard_dating_chat_needs_directory() FROM PUBLIC, anon, authenticated, service_role;
-- Final server fix (I-4): the config side of the chat's dependency is the database's own.
REVOKE ALL ON FUNCTION private.guard_dating_chat_keeps_config() FROM PUBLIC, anon, authenticated, service_role;
-- Final server fix (M-4, I-7): re-created (CREATE OR REPLACE keeps their grants; re-asserted).
REVOKE ALL ON FUNCTION public.delete_private_date_reflection(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.delete_private_date_reflection(text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_dating_safety_job(uuid, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_dating_safety_job(uuid, text, jsonb, text) TO service_role;
REVOKE ALL ON FUNCTION private.dating_chat_push_read_guard() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
