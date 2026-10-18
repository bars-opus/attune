-- Spec 8: grants for 20261018150300 (request_verdict_generation keeps its own).
REVOKE ALL ON public.ai_provider_calls FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.ai_provider_calls TO service_role;
REVOKE ALL ON public.ai_cost_per_relationship FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ai_cost_per_relationship TO service_role;
REVOKE ALL ON FUNCTION public.purge_old_ai_provider_calls() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_ai_provider_calls() TO service_role;
REVOKE ALL ON FUNCTION public.request_verdict_generation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_verdict_generation(uuid) TO authenticated;
