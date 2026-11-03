-- Spec 1 W6a: grants for 20261103100100_access_token_hook.sql. The hook is
-- Supabase Auth's only (supabase_auth_admin); the two new public tables
-- are the service role's; everything else is server-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.account_activity, public.fresh_start_challenges FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_activity, public.fresh_start_challenges TO service_role;
REVOKE ALL ON private.auth_hook_failures FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.auth_hook_failures_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.fresh_start_key(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.seal_fresh_start(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.open_fresh_start(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.access_token_refusal(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.attune_access_token_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.attune_access_token_hook(jsonb) TO supabase_auth_admin;
COMMIT;
