-- Entry gates: grants for 20261127100020_invite_gates_always.sql, exactly
-- as 20261102100010_accept_invite_v2_grants.sql set them: both functions
-- are the invite edge functions' (service role) alone.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_invite_eligibility(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_relationship_invite_v2(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.relationship_invite_eligibility(uuid) TO service_role;
COMMIT;
