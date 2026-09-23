-- commit_ai_session_ideas_turn: atomic two-row (user, attune) insert
-- at the correct ordinal pair for this request's own attempt_n. Spec
-- §6.2 step 5, §7.1's "Both rows committed atomically."
--
-- p_proposal is the validated suggested_planning_item jsonb (or NULL) --
-- this RPC does not itself validate the OUTPUT SHAPE (kind/title/
-- event_date bounds); that is Plan C's edge-function-side validation,
-- run on the model's raw output BEFORE this RPC is ever called. This
-- RPC's own job is atomicity and ordinal correctness, not schema
-- validation of content it receives.
CREATE OR REPLACE FUNCTION public.commit_ai_session_ideas_turn(
  p_worker_token uuid,
  p_request_id uuid,
  p_user_instruction text,
  p_reply_text text,
  p_proposal jsonb
) RETURNS TABLE (committed boolean, user_ordinal int, attune_ordinal int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.ai_session_requests;
  v_user_ord smallint;
  v_attune_ord smallint;
BEGIN
  SELECT * INTO v_request FROM public.ai_session_requests
  WHERE id = p_request_id AND worker_token = p_worker_token
  FOR UPDATE;
  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Request not found for this worker token';
  END IF;

  v_user_ord := (v_request.attempt_n * 2) - 1;
  v_attune_ord := v_request.attempt_n * 2;

  IF v_request.state = 'committed' THEN
    -- Idempotent replay: return the same ordinals, insert nothing.
    RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
    RETURN;
  END IF;
  IF v_request.state != 'started' THEN
    RAISE EXCEPTION 'Request is not in a committable state: %', v_request.state;
  END IF;

  INSERT INTO public.ai_session_turns (session_id, request_id, ordinal, role, author_id, kind, payload)
  VALUES
    (v_request.session_id, p_request_id, v_user_ord, 'user', v_request.actor_id, 'ideas_answer',
     jsonb_build_object('instruction', p_user_instruction)),
    (v_request.session_id, p_request_id, v_attune_ord, 'attune', NULL, 'ideas_answer',
     jsonb_build_object('reply_text', p_reply_text, 'suggested_planning_item', p_proposal));

  UPDATE public.ai_session_requests SET state = 'committed' WHERE id = p_request_id;
  UPDATE public.ai_sessions SET revision = revision + 1 WHERE id = v_request.session_id;

  PERFORM public.mark_ai_assistant_usage_outcome(v_request.actor_id, p_request_id, 'succeeded', 1::smallint);

  RETURN QUERY SELECT true, v_user_ord::int, v_attune_ord::int;
END;
$$;
REVOKE ALL ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.commit_ai_session_ideas_turn(uuid, uuid, text, text, jsonb)
  TO service_role;
