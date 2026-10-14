-- Together Phase 7: AI capture + date ideas (spec §6.5, D6; plan R2, R6).
-- Off until an operator flips it; then only for couples who both consented.

INSERT INTO public.feature_flags (key, enabled) VALUES ('ai_together_enabled', false)
ON CONFLICT (key) DO NOTHING;

-- Whether Together's AI may run for this couple, and my partner's first name
-- (capture recognises "with Kofi"). Read by the app (to show the entry
-- points) and by the ai-together function (with the caller's own token).
CREATE FUNCTION public.get_together_ai_status(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
BEGIN
  RETURN jsonb_build_object(
    'available', public.ai_capability_enabled('ai_together_enabled')
                 AND public.ai_consent_granted_for_relationship(p_relationship_id),
    'partner_name', coalesce(
      (SELECT split_part(btrim(u.display_name), ' ', 1) FROM public.users u WHERE u.id = v_partner), ''));
END;
$$;
REVOKE ALL ON FUNCTION public.get_together_ai_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_together_ai_status(uuid) TO authenticated;
