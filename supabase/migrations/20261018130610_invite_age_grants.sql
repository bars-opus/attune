-- Spec 5: grants for 20261018130600.
REVOKE ALL ON FUNCTION public.get_my_invite_age() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_invite_age() TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_my_pending_invites() TO authenticated;
