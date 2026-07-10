-- Phase 13 hotfix: explicitly REVOKE EXECUTE on redeem_promotion FROM
-- authenticated.
--
-- Symptom (2026-06-06): after 20260606000200 widened the signature and
-- ran `REVOKE ALL ... FROM PUBLIC`, post-push verification showed
-- has_function_privilege('authenticated', ..., 'EXECUTE') = true. The
-- REVOKE FROM PUBLIC only strips the implicit world-grant; it does NOT
-- remove a direct grant to a specific role.
--
-- The original 4-arg signature had an explicit GRANT EXECUTE TO
-- authenticated. When 20260606000200 dropped that 4-arg signature and
-- created the 5-arg variant, Supabase's default project policy
-- re-granted EXECUTE on the new function to authenticated (Supabase
-- runs a post-migration step that grants default privileges to the
-- authenticated role on public functions).
--
-- Fix: explicit REVOKE FROM authenticated. Belt-and-suspenders: also
-- REVOKE FROM anon (which doesn't normally have access but defensive
-- against any default grant policy changes).

REVOKE EXECUTE ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_promotion(UUID, UUID, UUID, NUMERIC, UUID) FROM anon;

-- service_role retains EXECUTE (it bypasses GRANTs as a superuser-like
-- role inside Supabase). Webhooks invoke this via service_role only.
