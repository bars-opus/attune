-- Spec 1 W1a: grants for 20261025100000_identity_users_lockdown.sql.
-- users: SELECT stays (own-row RLS). INSERT goes: a users row is written by
-- record_eula_acceptance, complete_sign_up (W1b) and the invite functions'
-- service role, always with the phone from auth.users. UPDATE is limited to
-- the three self-service columns (timezone stays: set_my_timezone is the
-- app's path and user_timezone_contracts.sql:133 relies on a direct write).
-- The policy "users insert own profile" stays; it is inert without INSERT.
-- anon never writes users (RLS refuses it anyway); the hosted project's
-- default privileges grant it table DML, so that goes too. Migration 1 runs
-- the same three users statements before its one-time pass (batch 2 review
-- M3); they stay here for the from-scratch replay.
BEGIN;
REVOKE INSERT, UPDATE ON public.users FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.users FROM anon;
GRANT UPDATE (display_name, avatar_url, timezone) ON public.users TO authenticated;

-- profiles: no client DELETE (D5, S-1). The strike writer only UPDATEs an
-- existing row, so a clean author who deleted theirs would never be struck.
-- No client deletes profiles; account deletion cascades from auth.users as
-- the table owner. The guard's DELETE branch stays as defence in depth, and
-- the policy "profiles delete own" is inert without the grant. Migration 1
-- revokes it too, as it does pause_dating_for_relationship_user (batch 3 fix
-- round 1, M-6).
REVOKE DELETE ON public.profiles FROM authenticated, anon;

REVOKE ALL ON FUNCTION public.verified_phone(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.sync_users_phone_from_auth() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.release_stale_users_phone(text, uuid, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.users_phone_from_auth_on_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.reconcile_users_phones() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_profile_moderation_columns() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.strip_name_controls(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.name_is_blank(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.normalize_display_name(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.users_display_name_clean() FROM PUBLIC, anon, authenticated;

-- The five dating functions keep exactly the grants they had (CREATE OR
-- REPLACE keeps an ACL); re-asserted so the twin states them.
REVOKE ALL ON FUNCTION public.activate_dating_profile(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_dating_mode(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_dating_profile(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_dating_for_relationship_user(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_dating_profile(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile(text) TO authenticated;
COMMIT;
