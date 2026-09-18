-- Consent RPCs. Spec §7.2, §10.1. The server owns the "current"
-- policy_version constant below -- bump it here (a single migration
-- adding a new DEFAULT-driving constant, or hardcode a new literal in
-- both functions in a follow-up migration) when the disclosure text
-- materially changes; a version bump requires two fresh grants under
-- the new version per spec §7.2.
CREATE OR REPLACE FUNCTION public.ai_current_consent_policy_version()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'v1'::text;
$$;

CREATE OR REPLACE FUNCTION public.record_ai_processing_consent(
  p_relationship_id uuid, p_action text, p_idempotency_key uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_action NOT IN ('granted', 'withdrawn') THEN
    RAISE EXCEPTION 'Invalid action';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  -- created_at is stamped explicitly with clock_timestamp(), not the
  -- column's now()-based DEFAULT: now() is frozen to transaction-start
  -- time, so two calls to this RPC inside one transaction (e.g. a rapid
  -- grant-then-withdraw, or this migration's own multi-call test) would
  -- otherwise get byte-identical created_at values, leaving "latest
  -- event" (Spec §7.2) to fall back on id DESC -- a random UUID with no
  -- relationship to insertion order. clock_timestamp() advances on every
  -- call regardless of transaction state, which is what actually makes
  -- (created_at DESC, id DESC) a correct "latest wins" ordering.
  INSERT INTO public.ai_processing_consent_events
    (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES (
    p_relationship_id, v_actor, public.ai_current_consent_policy_version(),
    p_action, p_idempotency_key, clock_timestamp()
  )
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.record_ai_processing_consent(uuid, text, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_ai_processing_consent(uuid, text, uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_ai_processing_consent_status(
  p_relationship_id uuid
) RETURNS TABLE (caller_granted boolean, both_granted boolean, policy_version text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version text := public.ai_current_consent_policy_version();
  v_user_a uuid;
  v_user_b uuid;
  v_a_granted boolean;
  v_b_granted boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT r.user_a, r.user_b INTO v_user_a, v_user_b
  FROM public.relationships r
  WHERE r.id = p_relationship_id
    AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = v_actor OR r.user_b = v_actor);
  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  -- "Current" for a user = their latest event at the CURRENT policy
  -- version. An event at an older version never counts as granted --
  -- this is what makes a version bump require two fresh grants.
  SELECT (e.action = 'granted') INTO v_a_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = p_relationship_id AND e.user_id = v_user_a
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  SELECT (e.action = 'granted') INTO v_b_granted
  FROM public.ai_processing_consent_events e
  WHERE e.relationship_id = p_relationship_id AND e.user_id = v_user_b
    AND e.policy_version = v_version
  ORDER BY e.created_at DESC, e.id DESC LIMIT 1;

  RETURN QUERY SELECT
    COALESCE(CASE WHEN v_actor = v_user_a THEN v_a_granted ELSE v_b_granted END, false),
    COALESCE(v_a_granted, false) AND COALESCE(v_b_granted, false),
    v_version;
END;
$$;
REVOKE ALL ON FUNCTION public.get_ai_processing_consent_status(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ai_processing_consent_status(uuid)
  TO authenticated;
