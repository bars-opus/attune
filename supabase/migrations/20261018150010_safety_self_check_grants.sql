-- Spec 8: grants for 20261018150000. The predicates are the server's (C1).
REVOKE ALL ON public.safety_self_checks FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.submit_my_safety_check(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_safety_check(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.user_safety_flagged(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.relationship_ai_suppressed(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_my_safety_check(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_safety_check(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_safety_flagged(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.relationship_ai_suppressed(uuid) TO service_role;
