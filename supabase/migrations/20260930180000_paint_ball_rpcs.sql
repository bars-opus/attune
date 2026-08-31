-- Paint Ball's write path. None of it existed.
--
-- 20260715120000_paint_ball_launch.sql created the schema and the two
-- READ-side functions (get_paint_ball_session_state,
-- expire_paint_ball_sessions) but none of the five RPCs
-- PaintBallService calls. The game is offered in the hub and is
-- tappable, so every attempt to create, accept, decline, fire or resolve
-- failed at runtime: Paint Ball could not be played at all.
--
-- Implements PAINT_BALL_GAME_SPEC.md §10 and the §11 inheritances from
-- GAMES.md §5 (auth, idempotency, concurrency, rate limiting).

-- §10.1 --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.paint_ball_create_session(
  p_relationship_id uuid,
  p_tone text,
  p_idempotency_key text,
  p_allow_partner_authored boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_recent int;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- §11.1: membership, with a generic message so a non-member cannot
  -- distinguish "not yours" from "does not exist".
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- §10.1: return the existing session on a repeated key rather than
  -- creating a second one.
  SELECT session_id INTO v_session
  FROM public.session_idempotency_keys WHERE key = p_idempotency_key;
  IF v_session IS NOT NULL THEN
    RETURN v_session;
  END IF;

  -- An in-flight session is itself the answer: one Paint Ball at a time
  -- per couple.
  SELECT id INTO v_session
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'paint_ball'
    AND status IN ('invited', 'active')
  LIMIT 1;
  IF v_session IS NOT NULL THEN
    RETURN v_session;
  END IF;

  -- §10.1: max 5 game initiations per hour per couple.
  SELECT count(*) INTO v_recent
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND created_at > now() - interval '1 hour';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = '53400';
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, tone, status,
    lives_a, lives_b, penalty_allow_partner_authored, total_rounds
  )
  VALUES (
    p_relationship_id, v_user, 'paint_ball', p_tone, 'invited',
    3, 3, COALESCE(p_allow_partner_authored, true), 0
  )
  RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session)
  ON CONFLICT (key) DO NOTHING;

  RETURN v_session;
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_create_session(uuid, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_create_session(uuid, text, text, boolean)
  TO authenticated;

-- §10.2 --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.paint_ball_accept_session(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND (r.user_a = v_user OR r.user_b = v_user)
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- Already accepted: idempotent, not an error.
  IF v_session.status = 'active' THEN
    RETURN;
  END IF;

  IF v_session.status <> 'invited' THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = '22023';
  END IF;

  -- §10.2: only the NON-initiator accepts. The initiator accepting their
  -- own invite would start a game the partner never agreed to.
  IF v_session.initiator_id = v_user THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.game_sessions
     SET status = 'active',
         started_at = now(),
         -- The initiator fires first.
         current_turn_user_id = v_session.initiator_id
   WHERE id = p_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_accept_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_accept_session(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.paint_ball_decline_session(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_status text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT s.status INTO v_status
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND (r.user_a = v_user OR r.user_b = v_user)
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF v_status = 'abandoned' THEN
    RETURN;
  END IF;

  IF v_status <> 'invited' THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = '22023';
  END IF;

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandoned_at = now(),
         abandon_reason = 'user_initiated'
   WHERE id = p_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_decline_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_decline_session(uuid) TO authenticated;

-- §10.3 / §10.4 -------------------------------------------------------
-- The client's p_hit is trusted (§5.5) but the STRUCTURE is not: turn
-- ownership, a single decrement, the floor at zero, one winner and one
-- penalty are all enforced here and cannot be spoofed.
CREATE OR REPLACE FUNCTION public.paint_ball_fire_shot(
  p_session_id uuid,
  p_round_number int,
  p_hit boolean,
  p_idempotency_key text DEFAULT NULL
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
  v_defender uuid;
  v_shooter_is_a boolean;
  v_existing public.game_session_rounds%ROWTYPE;
  v_knockout boolean := false;
  v_penalty_type text;
  v_penalty_source text;
  v_penalty_prompt_id uuid;
  v_penalty_snapshot text;
  v_defender_lives int;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- §11.3: the row lock plus the turn check below is what makes a
  -- simultaneous double-fire impossible rather than merely unlikely.
  SELECT s.* INTO v_session
  FROM public.game_sessions s
  WHERE s.id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;

  -- §10.3 step 1.
  IF v_rel.user_a <> v_user AND v_rel.user_b <> v_user THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- §10.3 step 4: idempotency BEFORE the state checks, so a retry of a
  -- shot that ended the game still returns its result rather than
  -- SESSION_EXPIRED.
  SELECT * INTO v_existing
  FROM public.game_session_rounds
  WHERE session_id = p_session_id AND round_number = p_round_number;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'shot_result', v_existing.shot_result,
      'life_lost', COALESCE(v_existing.life_lost, false),
      'round_number', p_round_number,
      'current_turn_user_id', v_session.current_turn_user_id,
      'knockout', v_session.winner_user_id IS NOT NULL,
      'penalty_type', v_session.penalty_type,
      'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot
    );
  END IF;

  -- §10.3 step 3.
  IF v_session.status <> 'active' THEN
    RAISE EXCEPTION 'SESSION_EXPIRED' USING ERRCODE = '22023';
  END IF;

  -- §10.3 step 2.
  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RAISE EXCEPTION 'NOT_YOUR_TURN' USING ERRCODE = '22023';
  END IF;

  v_shooter_is_a := (v_rel.user_a = v_user);
  v_defender := CASE WHEN v_shooter_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  -- §10.3 step 5.
  -- session_id only: game_session_rounds_owner_check requires exactly one
  -- of (session_id, relationship_id), since a round belongs either to a
  -- session or to a relationship-scoped game, never to both.
  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id, shot_result, life_lost
  )
  VALUES (
    p_session_id, p_round_number, v_user,
    CASE WHEN p_hit THEN 'hit' ELSE 'miss' END,
    p_hit
  );

  -- §10.3 step 6: the lives_x > 0 guard makes a below-zero life
  -- structurally impossible even under a replayed or racing call.
  IF p_hit THEN
    IF v_shooter_is_a THEN
      UPDATE public.game_sessions SET lives_b = lives_b - 1
       WHERE id = p_session_id AND lives_b > 0;
    ELSE
      UPDATE public.game_sessions SET lives_a = lives_a - 1
       WHERE id = p_session_id AND lives_a > 0;
    END IF;
  END IF;

  SELECT CASE WHEN v_shooter_is_a THEN lives_b ELSE lives_a END
    INTO v_defender_lives
  FROM public.game_sessions WHERE id = p_session_id;

  -- §10.3 step 7.
  IF v_defender_lives = 0 THEN
    v_knockout := true;

    -- §10.4: the roll happens once and the prompt is then FIXED —
    -- reopening the penalty screen must show the same prompt, never a
    -- reroll.
    v_penalty_type := CASE WHEN random() < 0.5 THEN 'truth' ELSE 'dare' END;

    IF v_session.penalty_allow_partner_authored THEN
      -- Tone is an EXACT match, never a range: it is the couple's consent
      -- boundary, so a Playful session must not surface a Spicy prompt.
      SELECT id, content INTO v_penalty_prompt_id, v_penalty_snapshot
      FROM public.custom_truth_or_dare_questions
      WHERE user_id = v_user
        AND question_type = v_penalty_type
        AND tone = v_session.tone
        AND is_private = false
        AND hidden_for_review = false
      ORDER BY random()
      LIMIT 1;
    END IF;

    IF v_penalty_prompt_id IS NOT NULL THEN
      v_penalty_source := 'partner_authored';
    ELSE
      v_penalty_source := 'app_random';

      SELECT q.id, q.question_text INTO v_penalty_prompt_id, v_penalty_snapshot
      FROM public.game_questions q
      WHERE q.game_type = 'truth_or_dare'
        AND q.question_subtype = v_penalty_type
        AND q.tone = v_session.tone
        AND q.active = true
        AND NOT EXISTS (
          SELECT 1 FROM public.game_questions_seen s
          WHERE s.relationship_id = v_session.relationship_id
            AND s.question_id = q.id
        )
      ORDER BY random()
      LIMIT 1;

      IF v_penalty_prompt_id IS NOT NULL THEN
        INSERT INTO public.game_questions_seen
          (relationship_id, question_id, game_type)
        VALUES
          (v_session.relationship_id, v_penalty_prompt_id, 'truth_or_dare')
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    UPDATE public.game_sessions
       SET winner_user_id = v_user,
           penalty_type = v_penalty_type,
           penalty_source = v_penalty_source,
           penalty_prompt_id = v_penalty_prompt_id,
           penalty_prompt_snapshot = v_penalty_snapshot,
           penalty_status = 'pending',
           total_rounds_completed = COALESCE(total_rounds_completed, 0) + 1
     WHERE id = p_session_id;
    -- Turn deliberately NOT advanced: the game is entering the penalty
    -- phase, not another round.
  ELSE
    -- §10.3 step 8.
    UPDATE public.game_sessions
       SET current_turn_user_id = v_defender,
           current_round = COALESCE(current_round, 1) + 1,
           total_rounds_completed = COALESCE(total_rounds_completed, 0) + 1
     WHERE id = p_session_id;
  END IF;

  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'shot_result', CASE WHEN p_hit THEN 'hit' ELSE 'miss' END,
    'life_lost', p_hit,
    'round_number', p_round_number,
    'current_turn_user_id', v_session.current_turn_user_id,
    'knockout', v_knockout,
    'penalty_type', v_session.penalty_type,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot
  );
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_fire_shot(uuid, int, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_fire_shot(uuid, int, boolean, text)
  TO authenticated;

-- §10.5 --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.paint_ball_resolve_penalty(
  p_session_id uuid,
  p_outcome text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_outcome NOT IN ('completed', 'declined') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND (r.user_a = v_user OR r.user_b = v_user)
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  -- Idempotent once completed (§11.2).
  IF v_session.status = 'completed' THEN
    RETURN;
  END IF;

  -- §10.5: only the LOSER resolves. The winner marking their own penalty
  -- done would let them close the game without the other partner acting.
  IF v_session.winner_user_id IS NULL OR v_session.winner_user_id = v_user THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.game_sessions
     SET penalty_status = p_outcome,
         status = 'completed',
         completed_at = now()
   WHERE id = p_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  TO authenticated;
