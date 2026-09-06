-- Paint Ball v3: move the hide_position boundary from "never" to "resolved".
--
-- v2 withheld hide_position from every client payload unconditionally. That
-- was right while a shot resolved against a PREVIOUS round's hide: the
-- position stayed live indefinitely, so any disclosure leaked a secret still
-- in play.
--
-- v3 resolves both shots of a round together, so once resolved_at is set the
-- position is finished history -- and the replay (§5.5) is built from exactly
-- that. Withholding it now would mean the game can never show the players
-- what happened, which is the whole point of the round.
--
-- The boundary is therefore per-round, not per-session: a resolved round
-- gives up both hides; a round still awaiting its second half gives up
-- neither, or the closer could read the opener's position and shoot it.

-- CREATE OR REPLACE cannot change a function's return type (42P13), and
-- remote may hold an older signature returning jsonb. Drop first so this
-- migration applies to a database at any prior revision.
DROP FUNCTION IF EXISTS public.get_paint_ball_session_state(uuid);

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
      -- THE BOUNDARY. The key is ABSENT entirely while the round is
      -- half-played, not merely null: a null still tells a reader the
      -- field exists and invites a client to look for it, and a contract
      -- test that greps the payload for the name is the strictest and
      -- most durable form of this rule. Once resolved, the position is
      -- finished history and the replay is built from it.
      || CASE
           WHEN r.resolved_at IS NOT NULL
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
