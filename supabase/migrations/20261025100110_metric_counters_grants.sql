-- Spec 1 W1b: grants for 20261025100100_metric_counters.sql. No client reads
-- or writes a metric table; service_role keeps DML (service_role_grants_test).
BEGIN;
REVOKE ALL ON public.metric_counters, public.metric_key_prefixes, public.metric_client_keys
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.metric_counters_report FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.metric_counters, public.metric_key_prefixes, public.metric_client_keys TO service_role;
GRANT SELECT ON public.metric_counters_report TO service_role;

REVOKE ALL ON FUNCTION private.metric_increment(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.bump_metric_internal(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bump_metric_server(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bump_metric(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bump_metric_server(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bump_metric(text) TO anon, authenticated;
COMMIT;
