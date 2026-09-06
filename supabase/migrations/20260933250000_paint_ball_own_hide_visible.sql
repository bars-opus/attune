-- Your own hiding place is not a secret from you.
--
-- The disclosure boundary was "resolved rounds only", which withheld a
-- player's OWN unresolved position from them. In practice that meant: you
-- move to the right cover, you shoot, and your choice vanishes -- the
-- client had nothing to restore it from, so reopening the game put you
-- somewhere random. Position was supposed to persist until you changed it.
--
-- The secret the game turns on is your PARTNER's live position, never your
-- own. So the rule becomes: a hide_position is visible when its round has
-- resolved, OR when it is yours.
--
-- The partner's unresolved position stays withheld exactly as before, which
-- is the half that matters: a closer who could read the opener's hide would
-- simply shoot it.

CREATE OR REPLACE FUNCTION public.get_paint_ball_session_state(p_session_id uuid)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_rounds json;
  v_penalties json;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED')::json;
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'paint_ball';
  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND')::json;
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN')::json;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'round_number', r.round_number,
        'shot_result', r.shot_result,
        'life_lost', r.life_lost,
        'created_at', r.created_at,
        'shot_position', r.shot_position,
        'active_partner_id', r.active_partner_id,
        'resolved_at', r.resolved_at
      )
      -- THE BOUNDARY. The key is ABSENT entirely rather than null: a null
      -- still tells a reader the field exists and invites a client to look
      -- for it, and a contract test that greps the payload for the name is
      -- the strictest form of this rule.
      --
      -- Visible when the round has resolved (it is history the replay is
      -- built from), or when the row is the caller's own (they chose it).
      -- Withheld only for a partner's still-live position.
      || CASE
           WHEN r.resolved_at IS NOT NULL OR r.active_partner_id = v_user
             THEN jsonb_build_object('hide_position', r.hide_position)
           ELSE '{}'::jsonb
         END
      ORDER BY r.round_number, r.created_at
    ),
    '[]'::jsonb
  )::json INTO v_rounds
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id;

  SELECT COALESCE(
    json_agg(json_build_object(
      'user_id', p.user_id,
      'penalty_type', p.penalty_type,
      'penalty_source', p.penalty_source,
      'penalty_status', p.penalty_status,
      'penalty_prompt_snapshot', p.penalty_prompt_snapshot
    )),
    '[]'::json
  ) INTO v_penalties
  FROM public.paint_ball_penalties p
  WHERE p.session_id = p_session_id;

  RETURN json_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'status', v_session.status,
    'tone', v_session.tone,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'user_a', v_rel.user_a,
    'user_b', v_rel.user_b,
    'current_round', GREATEST(COALESCE(v_session.current_round, 1), 1),
    'current_turn_user_id', v_session.current_turn_user_id,
    'total_rounds_completed', COALESCE(v_session.total_rounds_completed, 0),
    'winner_user_id', v_session.winner_user_id,
    'penalty_status', v_session.penalty_status,
    'penalty_type', v_session.penalty_type,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'penalties', v_penalties,
    'is_winner', v_session.winner_user_id = v_user,
    'is_loser',
      v_session.winner_user_id IS NOT NULL AND v_session.winner_user_id <> v_user,
    'created_at', v_session.created_at,
    'rounds', v_rounds
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_paint_ball_session_state(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_paint_ball_session_state(uuid)
  TO authenticated;
