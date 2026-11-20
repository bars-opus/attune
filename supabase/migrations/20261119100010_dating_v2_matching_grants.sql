-- Spec 2 W5a: grants for 20261119100000_dating_v2_matching.sql. The
-- introductions and matches stay no API role's, the service role included
-- (S-5); every new helper is the database's own; the generation tick is
-- cron's (postgres), no API role's, the service role included (it decrypts:
-- §4.2, S-4); the v1 introductions read stays the app's until W5b.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_introductions, public.dating_matches, public.dating_interest_actions
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_matches_pair_key() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_config_review_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_intro_config() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_cool_off_ends_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_last_seen_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_is_man_woman(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_person_current(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_admits(private.dating_gen_person, private.dating_gen_person, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_safe(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_pair_new(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_pair_passes_hard_filters(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_my_dating_introductions(integer) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_dating_introductions(integer) TO authenticated;
REVOKE ALL ON FUNCTION private.dating_open_chats(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_capacity(uuid, timestamptz, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reasons(private.dating_gen_person, private.dating_gen_person) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generation_skip(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_generate_partition(text, text, text, date, timestamptz, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.run_dating_generation_tick(timestamptz, text) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
