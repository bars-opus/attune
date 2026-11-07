-- Spec 2 W2: grants for 20261107140000_dating_v2_home.sql.
-- The reflections table is no API role's (the service role included): the
-- person reaches it through the two definer RPCs only. The three RPCs are
-- the app's (authenticated only); the helpers and the deletion trigger are
-- no API role's. Health keeps its W1 grant (the service role's, for the
-- edge health check).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_gentle_wait_reflections FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL (user_id, answers, saved_at, seen_at) ON TABLE public.dating_gentle_wait_reflections
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_next_step(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_unavailable_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_drop_at(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_gentle_wait_can_shorten(uuid) FROM PUBLIC, anon, authenticated, service_role; -- W2 final review M-4
REVOKE ALL ON FUNCTION private.dating_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_home() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.save_gentle_wait_reflection(jsonb) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_gentle_wait_reflection() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_home() TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_gentle_wait_reflection(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_gentle_wait_reflection() TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_operational_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_operational_health() TO service_role;
COMMIT;
