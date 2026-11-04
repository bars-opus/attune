-- Spec 1 W7a: grants for 20261103130000_support_resources_v2.sql. Anyone,
-- signed in or not, reads the directory through get_support_resources (the
-- Support screen opens before sign-in, spec §5.4); only the service role
-- writes it, through load_support_resources.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.support_resources FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.support_resources TO service_role;
REVOKE ALL ON FUNCTION public.get_support_resources(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.load_support_resources(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_support_resources(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.load_support_resources(jsonb) TO service_role;
COMMIT;
