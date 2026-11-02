-- Spec 1 W4a: grants for 20261102100000_accept_invite_v2.sql. The accept
-- and the eligibility check are the invite edge functions' (service role);
-- the preview is the app's; note_invite_attempt is accept-invite's
-- (service role); the attempts table, the name, inviter and budget
-- helpers and the purge are server-only. Both withdraw_my_pending_invites
-- overloads, redefined for their lock order (W4 F-3, re-review N-2), keep
-- their W1/W3 grants exactly. Clients don't insert relationships rows
-- (re-review N-1); the service role keeps its DML.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON private.invite_preview_attempts FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.invite_first_name(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.purge_invite_preview_attempts() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.invite_inviter_unavailable(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.take_invite_attempt(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.note_invite_attempt(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.accept_relationship_invite_v2(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_invite_eligibility(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.preview_relationship_invite(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_relationship_invite_v2(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.relationship_invite_eligibility(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.note_invite_attempt(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.preview_relationship_invite(text) TO authenticated;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_my_pending_invites() TO authenticated;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.withdraw_my_pending_invites(boolean) TO authenticated;
REVOKE INSERT ON public.relationships FROM PUBLIC, anon, authenticated;
COMMIT;
