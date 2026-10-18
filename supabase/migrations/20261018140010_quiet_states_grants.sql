-- Spec 7: grants for 20261018140000. The table and user_is_quiet are the
-- server's alone (plan review C1).
REVOKE ALL ON public.quiet_states FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.user_is_quiet(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_my_quiet_state(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.end_my_quiet_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_quiet_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_quiet_line_offered() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_quiet_state(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_my_quiet_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_quiet_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_quiet_line_offered() TO authenticated;
-- The service role reads it for the AI ideas tone (ai-together), never a client.
GRANT EXECUTE ON FUNCTION public.user_is_quiet(uuid) TO service_role;
