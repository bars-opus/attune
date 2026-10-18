-- Spec 7: grants for 20261018140100. The replaced functions keep their
-- earlier grants (CREATE OR REPLACE preserves them).
REVOKE ALL ON public.hidden_periods FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.user_hides_date(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.add_hidden_period(date, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_hidden_period(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_hidden_periods() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_hidden_period(date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_hidden_period(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_hidden_periods() TO authenticated;
