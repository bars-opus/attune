-- Spec 5: grants for 20261018130300.
REVOKE ALL ON FUNCTION public.save_loving_now(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_loving_now(jsonb) TO authenticated;
