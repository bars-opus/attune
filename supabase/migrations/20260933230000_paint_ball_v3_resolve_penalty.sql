-- Paint Ball v3: resolve a penalty from the per-player table.
--
-- The v2 function gated on `winner_user_id = v_user` and required
-- `winner_user_id IS NOT NULL`. Both break on a draw (§10.3): a double
-- knockout leaves winner_user_id NULL, so the old checks would have refused
-- BOTH players the forfeit they just earned.
--
-- The question is now simply "does this caller have a pending penalty?",
-- which is the actual thing being asked and holds for a knockout and a draw
-- alike. The session completes when no pending penalty remains -- on a draw
-- that is after the second player resolves, so neither is cut off by the
-- other finishing first.

CREATE OR REPLACE FUNCTION public.paint_ball_resolve_penalty(
  p_session_id uuid,
  p_outcome text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_penalty public.paint_ball_penalties%ROWTYPE;
  v_remaining int;
  v_partner uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF p_outcome IS NULL OR p_outcome NOT IN ('completed', 'declined') THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'paint_ball'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  SELECT * INTO v_penalty FROM public.paint_ball_penalties
  WHERE session_id = p_session_id AND user_id = v_user;

  -- Ownership is checked BEFORE the completed-session shortcut. A winner
  -- has no penalty of their own, and must be refused whether or not the
  -- game has since finished -- otherwise completing the session would
  -- quietly turn a forbidden call into a success.
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  IF v_penalty.penalty_status <> 'pending' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  UPDATE public.paint_ball_penalties
  SET penalty_status = p_outcome, resolved_at = now()
  WHERE session_id = p_session_id AND user_id = v_user;

  SELECT count(*) INTO v_remaining
  FROM public.paint_ball_penalties
  WHERE session_id = p_session_id AND penalty_status = 'pending';

  IF v_remaining = 0 THEN
    UPDATE public.game_sessions
    SET penalty_status = p_outcome,
        status = 'completed',
        completed_at = now()
    WHERE id = p_session_id;

    -- Tell the other player the game is done. On a draw there is no
    -- winner to congratulate, so the copy must not imply one.
    v_partner := CASE WHEN v_rel.user_a = v_user THEN v_rel.user_b
                      ELSE v_rel.user_a END;

    INSERT INTO public.scheduled_notifications (
      user_id, notification_type, scheduled_for, status, metadata,
      source_key, created_at, updated_at
    )
    VALUES (
      v_partner,
      'immediate',
      now(),
      'pending',
      jsonb_build_object(
        'title', 'Paint Ball complete',
        'body', CASE
          WHEN v_session.winner_user_id IS NULL
            THEN 'You got each other. Tap to see how it ended.'
          ELSE 'Tap to see how it ended.'
        END,
        'route', '/paintBallHistory',
        'session_id', p_session_id
      ),
      'paint_ball_done:' || p_session_id::text || ':' || v_partner::text,
      now(),
      now()
    )
    ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'penalty_status', p_outcome,
    'session_completed', v_remaining = 0,
    'awaiting_partner_penalty', v_remaining > 0
  );
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  TO authenticated;
