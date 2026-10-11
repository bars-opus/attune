-- approve_ai_session_context / activate_ai_session. Spec §3.2, §4.3, §7.1.
CREATE OR REPLACE FUNCTION public.approve_ai_session_context(
  p_actor_id uuid, p_session_id uuid, p_revision int, p_digest text, p_policy_version text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id AND state = 'preparing' AND revision = p_revision;
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session not found, not preparing, or revision mismatch';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_session.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_actor_id OR r.user_b = p_actor_id)
  ) THEN
    RAISE EXCEPTION 'Not a current member of this relationship';
  END IF;

  INSERT INTO public.ai_session_approvals (session_id, member_id, revision, digest, policy_version)
  VALUES (p_session_id, p_actor_id, p_revision, p_digest, p_policy_version)
  ON CONFLICT (session_id, member_id, revision) DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.approve_ai_session_context(uuid, uuid, int, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_ai_session_context(uuid, uuid, int, text, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.activate_ai_session(
  p_actor_id uuid, p_session_id uuid, p_revision int
) RETURNS TABLE (activated boolean, state text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.ai_sessions;
  v_distinct_digests int;
  v_approver_count int;
  v_required_count int;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_session FROM public.ai_sessions
  WHERE id = p_session_id FOR UPDATE;
  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;
  IF v_session.state != 'preparing' THEN
    RETURN QUERY SELECT (v_session.state = 'active'), v_session.state;
    RETURN;
  END IF;
  IF v_session.revision != p_revision THEN
    RAISE EXCEPTION 'Revision mismatch -- context changed since this client last read it';
  END IF;

  v_required_count := CASE WHEN v_session.visibility = 'shared' THEN 2 ELSE 1 END;

  SELECT count(DISTINCT member_id), count(DISTINCT digest) INTO v_approver_count, v_distinct_digests
  FROM public.ai_session_approvals
  WHERE session_id = p_session_id AND revision = p_revision;

  IF v_approver_count < v_required_count THEN
    RAISE EXCEPTION 'APPROVAL_REQUIRED';
  END IF;
  IF v_distinct_digests > 1 THEN
    RAISE EXCEPTION 'CONTEXT_CHANGED -- approvers did not approve the same snapshot';
  END IF;

  UPDATE public.ai_sessions
  SET state = 'active', activated_at = now(), context_revision = p_revision
  WHERE id = p_session_id;

  RETURN QUERY SELECT true, 'active';
END;
$$;
REVOKE ALL ON FUNCTION public.activate_ai_session(uuid, uuid, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_ai_session(uuid, uuid, int)
  TO service_role;
