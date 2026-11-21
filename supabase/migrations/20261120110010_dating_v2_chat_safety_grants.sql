-- Spec 2 W6b: grants for 20261120110000_dating_v2_chat_safety.sql. The
-- outbox, configs, events and opener hashes are no API role's (the
-- service role included: the worker reaches them only through its three
-- functions, S-5). The worker's calls are the service role's alone; the
-- cards and their dismissal are the app's; the rest is the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_message_safety_outbox FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_safety_configs FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_safety_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.dating_opener_hashes FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_safety_config_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_open_chat_case(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_card_resource(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_chat_push(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_opener_hash(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_chat_push_read_guard() FROM PUBLIC, anon, authenticated, service_role; -- fix round 1 (M-11)
REVOKE ALL ON FUNCTION public.get_dating_safety_config() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_safety_config() TO service_role;
REVOKE ALL ON FUNCTION public.claim_dating_safety_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_dating_safety_jobs(integer) TO service_role;
REVOKE ALL ON FUNCTION public.complete_dating_safety_job(uuid, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_dating_safety_job(uuid, text, jsonb, text) TO service_role;
REVOKE ALL ON FUNCTION public.recover_stale_dating_safety_jobs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_safety_cards(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_safety_cards(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.dismiss_dating_safety_card(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.dismiss_dating_safety_card(uuid) TO authenticated;
-- Final server fix (I-6, N-7): the push copy and the timed me_update are the database's own.
REVOKE ALL ON FUNCTION private.dating_me_update_body(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_me_update(uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
