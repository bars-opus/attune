-- Nearby staging/publish/discard. Spec §6.1, §7.1, §8.2.2.
CREATE OR REPLACE FUNCTION public.stage_ai_session_nearby_result(
  p_worker_token uuid, p_request_id uuid, p_reply_text text, p_sources jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_session_expiry timestamptz;
BEGIN
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL OR v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request not found or not in a stageable state';
  END IF;

  SELECT expires_at INTO v_session_expiry FROM public.ai_sessions WHERE id = v_request.session_id;

  INSERT INTO public.ai_session_staging (session_id, request_id, requester_id, reply_text, sources, expires_at)
  VALUES (
    v_request.session_id, p_request_id, v_request.actor_id, p_reply_text, p_sources,
    LEAST(now() + interval '2 minutes', COALESCE(v_session_expiry, now() + interval '2 minutes'))
  )
  ON CONFLICT (session_id, request_id) DO NOTHING;

  UPDATE public.ai_session_requests SET state = 'staged' WHERE id = p_request_id;
END;
$$;
REVOKE ALL ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stage_ai_session_nearby_result(uuid, uuid, text, jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.publish_ai_session_nearby_result(
  p_actor_id uuid, p_request_id uuid
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_staging public.ai_session_staging;
  v_user_ord smallint;
  v_attune_ord smallint;
BEGIN
  IF p_actor_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_request FROM public.ai_session_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  IF v_request.state = 'committed' THEN
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
    RETURN;
  END IF;

  SELECT * INTO v_staging FROM public.ai_session_staging
  WHERE request_id = p_request_id;
  IF v_staging.request_id IS NULL THEN
    RAISE EXCEPTION 'No staged result for this request';
  END IF;
  IF v_staging.requester_id != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may publish a staged Nearby result';
  END IF;
  IF v_staging.expires_at <= now() THEN
    RAISE EXCEPTION 'Staged result has expired';
  END IF;

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'nearby_result',
     jsonb_build_object('instruction', 'nearby')),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'nearby_result',
     jsonb_build_object('reply_text', v_staging.reply_text, 'sources', v_staging.sources));

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;
  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 2::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_ai_session_nearby_result(uuid, uuid)
  TO service_role;

CREATE OR REPLACE FUNCTION public.discard_ai_session_nearby_staging(
  p_actor_id uuid, p_request_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid;
BEGIN
  SELECT requester_id INTO v_actor FROM public.ai_session_staging WHERE request_id = p_request_id;
  IF v_actor IS NULL THEN
    RETURN; -- already discarded/published/expired -- idempotent no-op
  END IF;
  IF v_actor != p_actor_id THEN
    RAISE EXCEPTION 'Only the requester may discard their own staged result';
  END IF;

  DELETE FROM public.ai_session_staging WHERE request_id = p_request_id;
  -- Terminal, counted, no partner pair (spec §8.2.2) -- NOT a quota
  -- release. provider_started_at is already set for this request (it
  -- reached 'staged' only via claim_ai_session_dispatch), so this
  -- outcome must remain a counted terminal state, never 'cancelled'/
  -- 'rejected'.
  UPDATE public.ai_session_requests SET state = 'cancelled' WHERE id = p_request_id;
  PERFORM public.mark_ai_assistant_usage_outcome(p_actor_id, p_request_id, 'succeeded', 2::smallint);
END;
$$;
REVOKE ALL ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discard_ai_session_nearby_staging(uuid, uuid)
  TO service_role;
