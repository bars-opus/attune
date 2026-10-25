-- Spec 1 W1b: grants for 20261025100300_paths_and_home_state.sql. The path
-- writer and both seams are server-only; the three RPCs are the app's.
BEGIN;
REVOKE ALL ON FUNCTION private.spec1_flag_on(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_my_home_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_my_path(text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_home_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_path(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_my_pending_invites(boolean) TO authenticated;
COMMIT;
