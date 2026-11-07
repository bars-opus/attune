-- Spec 2 W1b: grants for 20261106130000_dating_v2_country_config.sql.
-- Anyone may read the open countries (get_dating_availability; Spec 1's
-- get_public_app_config keeps its own anon grant). Publishing and the
-- session context are the service role's; the tables are no client's.
-- Fix round 1 (C-1): the service role only reads country_safety_config
-- (publish_country_config, a definer, is its only writer).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.country_safety_config, public.dating_session_context, public.dating_notify_requests
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.country_safety_config FROM service_role;
GRANT SELECT ON public.country_safety_config TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_session_context, public.dating_notify_requests TO service_role;
REVOKE ALL ON private.dating_calling_codes FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_safety_config_has_current(), private.dating_iso_country(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_safety_config_immutable(), public.dating_country_config(text),
  private.country_config_checks(public.country_safety_config), public.publish_country_config(text, jsonb),
  public.get_dating_availability(), private.dating_open_countries(), private.dating_phone_country(text),
  public.dating_effective_context(text, text, text, text), public.record_dating_session_context(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_availability() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_session_context(uuid, text, text) TO service_role;
REVOKE ALL ON public.feature_flags FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.feature_flags TO authenticated;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
