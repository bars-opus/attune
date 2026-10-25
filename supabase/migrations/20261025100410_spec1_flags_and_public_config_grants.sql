-- Spec 1 W1c: grants for 20261025100400_spec1_flags_and_public_config.sql.
-- Nothing reaches anon except get_public_app_config (spec §4.3 W1c).
BEGIN;
REVOKE ALL ON public.app_public_config FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_public_config TO service_role;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.vault_setting_strict(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.assert_development_project() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_flag_production_gate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_open_countries() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_flag_gate_evidence(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.production_flag_violations() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_public_app_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_attune_environment() TO service_role;
GRANT EXECUTE ON FUNCTION public.record_flag_gate_evidence(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.production_flag_violations() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_public_app_config() TO anon, authenticated;
COMMIT;
