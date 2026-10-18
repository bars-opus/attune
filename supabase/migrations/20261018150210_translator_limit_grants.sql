-- Spec 8: grants for 20261018150200.
REVOKE ALL ON public.translator_daily_use FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reserve_translator_use() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_translator_use() TO authenticated;
