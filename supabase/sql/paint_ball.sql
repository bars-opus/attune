-- ============================================================
-- PAINT BALL — RPC Functions
-- Reuses shared game infrastructure. All functions are SECURITY DEFINER.
-- ============================================================

-- ============================================================
-- 1. paint_ball_create_session
-- Creates a new Paint Ball game session (idempotent)
-- ============================================================
CREATE OR REPLACE FUNCTION paint_ball_create_session(
  p_relationship_id uuid,
  p_tone text DEFAULT 'playful',
  p_idempotency_key text DEFAULT NULL,
  p_allow_partner_authored boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session_id uuid;
  v_existing_session_id uuid;
  v_is_member boolean;
  v_initiation_count int;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  -- Verify relationship membership
  SELECT EXISTS (
    SELECT 1 FROM relationships
    WHERE id = p_relationship_id
      AND (user_a = v_user_id OR user_b = v_user_id)
      AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this relationship.');
  END IF;

  -- Idempotency check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT session_id INTO v_existing_session_id
    FROM session_idempotency_keys
    WHERE key = p_idempotency_key
      AND created_at > now() - interval '5 minutes';

    IF v_existing_session_id IS NOT NULL THEN
      RETURN json_build_object(
        'session_id', v_existing_session_id,
        'existing', true
      );
    END IF;
  END IF;

  -- Rate limit: max 5 initiations per hour per couple. Count by creation time
  -- only — this is an initiation rate, not a concurrency cap. Counting only
  -- unfinished ('invited','active') sessions would let 5 slow-played games block
  -- every new one indefinitely, which is not what GAMES.md §5.4 specifies.
  SELECT COUNT(*) INTO v_initiation_count
  FROM game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'paint_ball'
    AND created_at > now() - interval '1 hour';

  IF v_initiation_count >= 5 THEN
    RETURN json_build_object('error', true, 'code', 'RATE_LIMITED', 'message', 'Too many game initiations. Please wait a moment.');
  END IF;

  -- Create session
  INSERT INTO game_sessions (
    relationship_id,
    initiator_id,
    game_type,
    tone,
    status,
    current_round,
    total_rounds_completed,
    lives_a,
    lives_b,
    penalty_allow_partner_authored
  ) VALUES (
    p_relationship_id,
    v_user_id,
    'paint_ball',
    COALESCE(p_tone, 'playful'),
    'invited',
    1,
    0,
    3,
    3,
    COALESCE(p_allow_partner_authored, false)
  )
  RETURNING id INTO v_session_id;

  -- Store idempotency key
  IF p_idempotency_key IS NOT NULL THEN
    INSERT INTO session_idempotency_keys (key, session_id, created_at)
    VALUES (p_idempotency_key, v_session_id, now());
  END IF;

  RETURN json_build_object(
    'session_id', v_session_id,
    'existing', false
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION paint_ball_create_session TO authenticated;
REVOKE ALL ON FUNCTION paint_ball_create_session FROM anon, public;

-- ============================================================
-- 2. paint_ball_accept_session
-- Accepts an invitation and starts the game
-- ============================================================
CREATE OR REPLACE FUNCTION paint_ball_accept_session(
  p_session_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
  v_updated_id uuid;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  -- Get session with relationship
  SELECT s.*, r.user_a, r.user_b INTO v_session
  FROM game_sessions s
  JOIN relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball';

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  -- Must be the invited partner (not initiator)
  IF v_user_id = v_session.initiator_id THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You cannot accept your own invitation.');
  END IF;

  -- Must be in the relationship
  IF v_user_id NOT IN (v_session.user_a, v_session.user_b) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  -- Must be invited
  IF v_session.status != 'invited' THEN
    RETURN json_build_object('error', true, 'code', 'SESSION_EXPIRED', 'message', 'This session expired. Start a new game.');
  END IF;

  -- Accept: initiator goes first
  UPDATE game_sessions
  SET status = 'active',
      started_at = now(),
      current_turn_user_id = v_session.initiator_id
  WHERE id = p_session_id
    AND status = 'invited'
  RETURNING id INTO v_updated_id;

  IF v_updated_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'SESSION_EXPIRED', 'message', 'This session expired. Start a new game.');
  END IF;

  RETURN json_build_object(
    'success', true,
    'session_id', p_session_id,
    'current_turn_user_id', v_session.initiator_id
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION paint_ball_accept_session TO authenticated;
REVOKE ALL ON FUNCTION paint_ball_accept_session FROM anon, public;

-- ============================================================
-- 3. paint_ball_decline_session
-- Declines an invitation
-- ============================================================
CREATE OR REPLACE FUNCTION paint_ball_decline_session(
  p_session_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
BEGIN
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  SELECT s.*, r.user_a, r.user_b INTO v_session
  FROM game_sessions s
  JOIN relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball';

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  -- Must be the invited partner
  IF v_user_id = v_session.initiator_id THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You cannot decline your own invitation.');
  END IF;

  IF v_user_id NOT IN (v_session.user_a, v_session.user_b) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  IF v_session.status != 'invited' THEN
    RETURN json_build_object('error', true, 'code', 'SESSION_EXPIRED', 'message', 'This session already ended.');
  END IF;

  UPDATE game_sessions
  SET status = 'abandoned',
      abandoned_at = now()
  WHERE id = p_session_id
    AND status = 'invited';

  RETURN json_build_object(
    'success', true,
    'session_id', p_session_id
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION paint_ball_decline_session TO authenticated;
REVOKE ALL ON FUNCTION paint_ball_decline_session FROM anon, public;

-- ============================================================
-- 4. get_paint_ball_session_state
-- Returns the authoritative session snapshot + rounds for restore/reopen
-- ============================================================
CREATE OR REPLACE FUNCTION get_paint_ball_session_state(
  p_session_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
  v_rounds json;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  SELECT s.*, r.user_a AS user_a_id, r.user_b AS user_b_id
  INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball';

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  IF v_user_id NOT IN (v_session.user_a_id, v_session.user_b_id) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'round_number', r.round_number,
        'shot_result', r.shot_result,
        'life_lost', r.life_lost,
        'created_at', r.created_at
      )
      ORDER BY r.round_number
    ),
    '[]'::json
  )
  INTO v_rounds
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id;

  RETURN json_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'user_a_id', v_session.user_a_id,
    'user_b_id', v_session.user_b_id,
    'status', v_session.status,
    'game_type', v_session.game_type,
    'tone', v_session.tone,
    'current_round', v_session.current_round,
    'total_rounds_completed', v_session.total_rounds_completed,
    'current_turn_user_id', v_session.current_turn_user_id,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'winner_user_id', v_session.winner_user_id,
    'penalty_type', v_session.penalty_type,
    'penalty_status', v_session.penalty_status,
    'penalty_prompt_id', v_session.penalty_prompt_id,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'penalty_source', v_session.penalty_source,
    'penalty_allow_partner_authored', v_session.penalty_allow_partner_authored,
    'rounds', v_rounds,
    'is_my_turn', v_session.current_turn_user_id = v_user_id,
    'is_winner', v_session.winner_user_id = v_user_id,
    'is_loser', v_session.winner_user_id IS NOT NULL AND v_session.winner_user_id <> v_user_id,
    'existing', false,
    'started_at', v_session.started_at,
    'completed_at', v_session.completed_at,
    'abandoned_at', v_session.abandoned_at,
    'created_at', v_session.created_at
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION get_paint_ball_session_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION get_paint_ball_session_state(uuid) FROM anon, public;

-- ============================================================
-- 4. paint_ball_fire_shot
-- Resolves one shot for the current turn holder (idempotent per round)
-- ============================================================
CREATE OR REPLACE FUNCTION paint_ball_fire_shot(
  p_session_id uuid,
  p_round_number int,
  p_hit boolean,
  p_idempotency_key text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
  v_existing_round record;
  v_round_id uuid;
  v_penalty_type text;
  v_penalty_source text;
  v_penalty_prompt_id uuid;
  v_penalty_prompt_snapshot text;
  v_lives_a smallint;
  v_lives_b smallint;
  v_question_id uuid;
  v_question_text text;
  v_custom_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  SELECT s.*, r.user_a, r.user_b
  INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball'
  FOR UPDATE OF s;

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  IF v_user_id NOT IN (v_session.user_a, v_session.user_b) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  IF v_session.status = 'completed' OR v_session.penalty_status IS NOT NULL THEN
    RETURN json_build_object('error', true, 'code', 'GAME_OVER', 'message', 'This game has already finished.');
  END IF;

  IF v_session.status <> 'active' THEN
    RETURN json_build_object('error', true, 'code', 'SESSION_EXPIRED', 'message', 'This session expired. Start a new game.');
  END IF;

  IF v_session.current_turn_user_id IS DISTINCT FROM v_user_id THEN
    RETURN json_build_object('error', true, 'code', 'NOT_YOUR_TURN', 'message', 'It''s not your turn yet.');
  END IF;

  SELECT *
  INTO v_existing_round
  FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number;

  IF FOUND THEN
    -- Idempotent replay. Report knockout from authoritative session state, not a
    -- hardcoded false: if THIS round was the winning shot, the client retrying it
    -- must still be told to show the penalty screen. penalty_status is set only
    -- on the knockout round, so it is the reliable signal.
    RETURN json_build_object(
      'session_id', p_session_id,
      'round_number', p_round_number,
      'shot_result', v_existing_round.shot_result,
      'life_lost', v_existing_round.life_lost,
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'current_turn_user_id', v_session.current_turn_user_id,
      'knockout', (v_session.penalty_status IS NOT NULL),
      'penalty_type', v_session.penalty_type,
      'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
      'existing', true
    );
  END IF;

  IF p_round_number IS NULL OR p_round_number <> v_session.current_round THEN
    RETURN json_build_object('error', true, 'code', 'INVALID_INPUT', 'message', 'Invalid value provided.');
  END IF;

  -- The session row is locked (FOR UPDATE OF s), so a concurrent fire for the
  -- same round cannot reach here in parallel; but guard the UNIQUE(session_id,
  -- round_number) violation anyway and treat it as a replay rather than leaking
  -- an INTERNAL_ERROR.
  BEGIN
    INSERT INTO public.game_session_rounds (
      session_id,
      round_number,
      active_partner_id,
      shot_result,
      life_lost,
      created_at
    ) VALUES (
      p_session_id,
      p_round_number,
      v_user_id,
      CASE WHEN p_hit THEN 'hit' ELSE 'miss' END,
      COALESCE(p_hit, false),
      now()
    )
    RETURNING id INTO v_round_id;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT * INTO v_existing_round
      FROM public.game_session_rounds
      WHERE session_id = p_session_id AND round_number = p_round_number;
      RETURN json_build_object(
        'session_id', p_session_id,
        'round_number', p_round_number,
        'shot_result', v_existing_round.shot_result,
        'life_lost', v_existing_round.life_lost,
        'lives_a', v_session.lives_a,
        'lives_b', v_session.lives_b,
        'current_turn_user_id', v_session.current_turn_user_id,
        'knockout', (v_session.penalty_status IS NOT NULL),
        'penalty_type', v_session.penalty_type,
        'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
        'existing', true
      );
  END;

  v_lives_a := v_session.lives_a;
  v_lives_b := v_session.lives_b;

  -- Apply the life change with a floored, guarded UPDATE. The WHERE lives_x > 0
  -- clause makes a below-zero life structurally impossible even under a replayed
  -- or racing call, and RETURNING gives us the authoritative post-decrement value
  -- rather than trusting the local copy. The defender is the member who is NOT the
  -- firer. (Reaching here on an already-0 defender is unreachable — the game would
  -- have ended — so we simply no-op rather than orphan a round with an error.)
  IF p_hit THEN
    IF v_user_id = v_session.user_a THEN
      UPDATE public.game_sessions
      SET lives_b = lives_b - 1
      WHERE id = p_session_id AND lives_b > 0
      RETURNING lives_b INTO v_lives_b;
    ELSE
      UPDATE public.game_sessions
      SET lives_a = lives_a - 1
      WHERE id = p_session_id AND lives_a > 0
      RETURNING lives_a INTO v_lives_a;
    END IF;
  END IF;

  IF v_lives_a = 0 OR v_lives_b = 0 THEN
    v_penalty_type := CASE WHEN random() < 0.5 THEN 'truth' ELSE 'dare' END;

    IF v_session.penalty_allow_partner_authored THEN
      SELECT id, content
      INTO v_custom_id, v_penalty_prompt_snapshot
      FROM public.custom_truth_or_dare_questions
      WHERE user_id = v_user_id
        AND question_type = v_penalty_type
        AND tone = v_session.tone
        AND is_private = false
        AND hidden_for_review = false
      ORDER BY random()
      LIMIT 1;

      IF v_custom_id IS NOT NULL THEN
        v_penalty_source := 'partner_authored';
        v_penalty_prompt_id := v_custom_id;
        PERFORM public.increment_custom_question_usage(v_custom_id);
      END IF;
    END IF;

    IF v_penalty_prompt_snapshot IS NULL THEN
      SELECT id, question_text
      INTO v_question_id, v_question_text
      FROM public.game_questions
      WHERE game_type = 'truth_or_dare'
        AND question_subtype = v_penalty_type
        AND tone = v_session.tone
        AND active = true
        AND id NOT IN (
          SELECT question_id
          FROM public.game_questions_seen
          WHERE relationship_id = v_session.relationship_id
            AND game_type = 'truth_or_dare'
        )
      ORDER BY random()
      LIMIT 1;

      IF v_question_id IS NULL THEN
        SELECT id, question_text
        INTO v_question_id, v_question_text
        FROM public.game_questions
        WHERE game_type = 'truth_or_dare'
          AND question_subtype = v_penalty_type
          AND tone = v_session.tone
          AND active = true
        ORDER BY random()
        LIMIT 1;
      END IF;

      -- If the tone-matched bank is exhausted AND all-seen fallback also found
      -- nothing (an effectively empty bank for this tone+subtype), do not return
      -- INTERNAL_ERROR here: the round row is already inserted and the life
      -- already decremented, so returning now would COMMIT a bricked half-knockout
      -- (lives at 0, no winner, no penalty, no way forward). Instead RAISE so the
      -- whole transaction rolls back — the shot never happened and the client can
      -- retry. This should be unreachable in production (the bank is seeded), but a
      -- rollback is the only safe failure here.
      IF v_question_id IS NULL THEN
        RAISE EXCEPTION 'paint_ball_no_penalty_prompt for tone=% subtype=%',
          v_session.tone, v_penalty_type;
      END IF;

      v_penalty_source := 'app_random';
      v_penalty_prompt_id := v_question_id;
      v_penalty_prompt_snapshot := v_question_text;

      INSERT INTO public.game_questions_seen (relationship_id, question_id, game_type)
      VALUES (v_session.relationship_id, v_question_id, 'truth_or_dare')
      ON CONFLICT (relationship_id, question_id) DO NOTHING;
    END IF;

    UPDATE public.game_sessions
    SET winner_user_id = v_user_id,
        penalty_type = v_penalty_type,
        penalty_source = v_penalty_source,
        penalty_status = 'pending',
        penalty_prompt_id = v_penalty_prompt_id,
        penalty_prompt_snapshot = v_penalty_prompt_snapshot,
        current_turn_user_id = NULL,
        total_rounds_completed = total_rounds_completed + 1
    WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions
    SET current_turn_user_id = CASE
          WHEN v_user_id = v_session.user_a THEN v_session.user_b
          ELSE v_session.user_a
        END,
        current_round = current_round + 1,
        total_rounds_completed = total_rounds_completed + 1
    WHERE id = p_session_id;
  END IF;

  RETURN json_build_object(
    'session_id', p_session_id,
    'round_id', v_round_id,
    'round_number', p_round_number,
    'shot_result', CASE WHEN p_hit THEN 'hit' ELSE 'miss' END,
    'life_lost', COALESCE(p_hit, false),
    'lives_a', v_lives_a,
    'lives_b', v_lives_b,
    'current_turn_user_id', (
      SELECT current_turn_user_id
      FROM public.game_sessions
      WHERE id = p_session_id
    ),
    'knockout', (v_lives_a = 0 OR v_lives_b = 0),
    'penalty_type', v_penalty_type,
    'penalty_prompt_snapshot', v_penalty_prompt_snapshot,
    'existing', false
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION paint_ball_fire_shot(uuid, int, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION paint_ball_fire_shot(uuid, int, boolean, text) FROM anon, public;

-- ============================================================
-- 5. paint_ball_resolve_penalty
-- Completes or skips the knockout prompt and ends the session
-- ============================================================
CREATE OR REPLACE FUNCTION paint_ball_resolve_penalty(
  p_session_id uuid,
  p_outcome text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  -- Lock the session row: two rapid resolve calls must not both pass the
  -- pending-status read and both proceed. Without FOR UPDATE the guarded UPDATE
  -- protects DB state but the second caller would still return a fresh 'success'
  -- with its own outcome rather than the clean idempotent no-op the spec requires.
  SELECT s.*, r.user_a, r.user_b
  INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball'
  FOR UPDATE OF s;

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  IF v_user_id NOT IN (v_session.user_a, v_session.user_b) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  IF v_session.winner_user_id IS NULL OR v_session.penalty_status IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'GAME_OVER', 'message', 'This game has already finished.');
  END IF;

  IF v_user_id = v_session.winner_user_id THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You cannot resolve the other player''s penalty.');
  END IF;

  IF p_outcome NOT IN ('completed', 'declined') THEN
    RETURN json_build_object('error', true, 'code', 'INVALID_INPUT', 'message', 'Invalid value provided.');
  END IF;

  -- Idempotent: if the penalty is already resolved (not 'pending'), return the
  -- already-recorded outcome without changing anything. Spec §10.5: "a second
  -- call after completed returns success without change."
  IF v_session.penalty_status <> 'pending' THEN
    RETURN json_build_object(
      'success', true,
      'session_id', p_session_id,
      'penalty_status', v_session.penalty_status
    );
  END IF;

  UPDATE public.game_sessions
  SET penalty_status = p_outcome,
      status = 'completed',
      completed_at = COALESCE(completed_at, now())
  WHERE id = p_session_id
    AND penalty_status = 'pending';

  RETURN json_build_object(
    'success', true,
    'session_id', p_session_id,
    'penalty_status', p_outcome
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION paint_ball_resolve_penalty(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION paint_ball_resolve_penalty(uuid, text) FROM anon, public;

-- ============================================================
-- 6. get_active_paint_ball_session
-- Returns the current resumable Paint Ball session for a relationship, or null.
-- Without this the invited partner never sees an incoming invite: their lobby
-- opens with only a relationship_id and no session loaded, so there is no way to
-- surface Accept/Decline. Resolves the newest non-terminal session (invited or
-- active) for the couple, then delegates to get_paint_ball_session_state (defined
-- above) so the client parses one consistent shape.
-- ============================================================
CREATE OR REPLACE FUNCTION get_active_paint_ball_session(
  p_relationship_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_is_member boolean;
  v_session_id uuid;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = v_user_id OR user_b = v_user_id)
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this relationship.');
  END IF;

  -- Newest resumable session. A pending penalty keeps status = 'active' until the
  -- loser resolves it, so it is correctly covered here.
  SELECT id INTO v_session_id
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'paint_ball'
    AND status IN ('invited', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_session_id IS NULL THEN
    RETURN json_build_object('session', null);
  END IF;

  RETURN json_build_object('session', public.get_paint_ball_session_state(v_session_id));

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION get_active_paint_ball_session(uuid) TO authenticated;
REVOKE ALL ON FUNCTION get_active_paint_ball_session(uuid) FROM anon, public;
