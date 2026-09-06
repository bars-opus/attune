-- Paint Ball specification completion.
--
-- The hidden-information rebuild established the right mechanic, but its final
-- take-turn replacement stopped advancing current_round and omitted fields the
-- client needs to restore a session. This migration makes the server contract
-- complete and keeps every outcome and secret server-authoritative.

CREATE OR REPLACE FUNCTION public.paint_ball_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'     THEN 'Please sign in to play games.'
      WHEN 'FORBIDDEN'        THEN 'You don''t have access to this game.'
      WHEN 'NOT_FOUND'        THEN 'Game session not found.'
      WHEN 'NOT_YOUR_TURN'    THEN 'It''s not your turn yet.'
      WHEN 'GAME_OVER'        THEN 'This game has already finished.'
      WHEN 'SESSION_EXPIRED'  THEN 'This session expired. Start a new game.'
      WHEN 'RATE_LIMITED'     THEN 'Too many attempts. Please wait a moment.'
      WHEN 'INVALID_INPUT'    THEN 'Invalid value provided.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

REVOKE ALL ON FUNCTION public.paint_ball_error(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_error(text) TO authenticated;

-- The shared Games policies predate hidden-position play and grant relationship
-- members FOR ALL on both tables. That is appropriate for the answer-based
-- games, but would let a Paint Ball client read hide_position or directly edit
-- lives and turn ownership. Preserve the existing access for every other game
-- while making Paint Ball mutations and round reads RPC-only.
DROP POLICY IF EXISTS "game_sessions_relationship_members"
  ON public.game_sessions;
DROP POLICY IF EXISTS "game_sessions_relationship_members_select"
  ON public.game_sessions;
DROP POLICY IF EXISTS "game_sessions_relationship_members_insert"
  ON public.game_sessions;
DROP POLICY IF EXISTS "game_sessions_relationship_members_update"
  ON public.game_sessions;
DROP POLICY IF EXISTS "game_sessions_relationship_members_delete"
  ON public.game_sessions;

CREATE POLICY "game_sessions_relationship_members_select"
ON public.game_sessions FOR SELECT
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

CREATE POLICY "game_sessions_relationship_members_insert"
ON public.game_sessions FOR INSERT
WITH CHECK (
  game_type <> 'paint_ball'
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

CREATE POLICY "game_sessions_relationship_members_update"
ON public.game_sessions FOR UPDATE
USING (
  game_type <> 'paint_ball'
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
)
WITH CHECK (
  game_type <> 'paint_ball'
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

CREATE POLICY "game_sessions_relationship_members_delete"
ON public.game_sessions FOR DELETE
USING (
  game_type <> 'paint_ball'
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS "game_rounds_relationship_members"
  ON public.game_session_rounds;
DROP POLICY IF EXISTS "game_rounds_relationship_members_select"
  ON public.game_session_rounds;
DROP POLICY IF EXISTS "game_rounds_relationship_members_insert"
  ON public.game_session_rounds;
DROP POLICY IF EXISTS "game_rounds_relationship_members_update"
  ON public.game_session_rounds;
DROP POLICY IF EXISTS "game_rounds_relationship_members_delete"
  ON public.game_session_rounds;

CREATE POLICY "game_rounds_relationship_members_select"
ON public.game_session_rounds FOR SELECT
USING (
  session_id IN (
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

CREATE POLICY "game_rounds_relationship_members_insert"
ON public.game_session_rounds FOR INSERT
WITH CHECK (
  session_id IN (
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

CREATE POLICY "game_rounds_relationship_members_update"
ON public.game_session_rounds FOR UPDATE
USING (
  session_id IN (
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
)
WITH CHECK (
  session_id IN (
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

CREATE POLICY "game_rounds_relationship_members_delete"
ON public.game_session_rounds FOR DELETE
USING (
  session_id IN (
    SELECT s.id
    FROM public.game_sessions s
    WHERE s.game_type <> 'paint_ball'
      AND s.relationship_id IN (
        SELECT id FROM public.relationships
        WHERE user_a = auth.uid() OR user_b = auth.uid()
      )
  )
);

-- A relationship ending is also the end of its live games. The relationship
-- schema's abandon_reason constraint predates this trigger, so reuse the
-- existing user_initiated value rather than widening a shared enum solely for
-- Paint Ball. Clearing the turn prevents a stale client from presenting the
-- abandoned row as playable before its realtime refresh lands.
CREATE OR REPLACE FUNCTION public.abandon_paint_ball_on_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' AND NEW.chat_archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.game_sessions
  SET status = 'abandoned',
      abandon_reason = 'user_initiated',
      abandoned_at = now(),
      current_turn_user_id = NULL
  WHERE relationship_id = NEW.id
    AND game_type = 'paint_ball'
    AND status IN ('invited', 'active');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS abandon_paint_ball_on_relationship_change
  ON public.relationships;
CREATE TRIGGER abandon_paint_ball_on_relationship_change
AFTER UPDATE OF status, chat_archived_at ON public.relationships
FOR EACH ROW
WHEN (
  OLD.status IS DISTINCT FROM NEW.status
  OR OLD.chat_archived_at IS DISTINCT FROM NEW.chat_archived_at
)
EXECUTE FUNCTION public.abandon_paint_ball_on_relationship_change();

REVOKE ALL ON FUNCTION public.abandon_paint_ball_on_relationship_change()
  FROM PUBLIC, anon, authenticated;

-- Bring rows that predate the trigger under the same invariant.
UPDATE public.game_sessions s
SET status = 'abandoned',
    abandon_reason = 'user_initiated',
    abandoned_at = now(),
    current_turn_user_id = NULL
FROM public.relationships r
WHERE r.id = s.relationship_id
  AND s.game_type = 'paint_ball'
  AND s.status IN ('invited', 'active')
  AND (r.status <> 'active' OR r.chat_archived_at IS NOT NULL);

-- Creation remains inside the shared game_sessions table. An advisory lock on
-- the relationship closes the race where two different idempotency keys could
-- otherwise create two simultaneous Paint Ball invitations.
CREATE OR REPLACE FUNCTION public.paint_ball_create_session(
  p_relationship_id uuid,
  p_tone text,
  p_idempotency_key text,
  p_allow_partner_authored boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF p_tone IS NULL OR p_tone NOT IN ('playful', 'connecting', 'romantic')
     OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = '' THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND chat_archived_at IS NULL
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
  FROM public.session_idempotency_keys k
  JOIN public.game_sessions s ON s.id = k.session_id
  WHERE k.key = p_idempotency_key;

  IF v_session IS NOT NULL THEN
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.paint_ball_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> 'paint_ball' THEN
      RETURN public.paint_ball_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  SELECT id INTO v_session
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'paint_ball'
    AND status IN ('invited', 'active')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_session IS NOT NULL THEN
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND created_at > now() - interval '1 hour';

  IF v_recent >= 5 THEN
    RETURN public.paint_ball_error('RATE_LIMITED');
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id,
    initiator_id,
    game_type,
    tone,
    status,
    lives_a,
    lives_b,
    current_round,
    total_rounds,
    total_rounds_completed,
    penalty_allow_partner_authored
  )
  VALUES (
    p_relationship_id,
    v_user,
    'paint_ball',
    p_tone,
    'invited',
    3,
    3,
    1,
    0,
    0,
    COALESCE(p_allow_partner_authored, false)
  )
  RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_create_session(uuid, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_create_session(uuid, text, text, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.paint_ball_accept_session(
  p_session_id uuid
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session
  FROM public.game_sessions
  WHERE id = p_session_id
    AND game_type = 'paint_ball'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'active' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  IF v_session.status <> 'invited' THEN
    RETURN public.paint_ball_error('SESSION_EXPIRED');
  END IF;

  IF v_session.initiator_id = v_user THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  UPDATE public.game_sessions
  SET status = 'active',
      started_at = now(),
      current_round = 1,
      current_turn_user_id = v_session.initiator_id
  WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_accept_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_accept_session(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.paint_ball_decline_session(
  p_session_id uuid
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session
  FROM public.game_sessions
  WHERE id = p_session_id
    AND game_type = 'paint_ball'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'abandoned' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  IF v_session.status <> 'invited' THEN
    RETURN public.paint_ball_error('SESSION_EXPIRED');
  END IF;

  UPDATE public.game_sessions
  SET status = 'abandoned',
      abandoned_at = now(),
      abandon_reason = 'user_initiated'
  WHERE id = p_session_id;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_decline_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_decline_session(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.paint_ball_take_turn(
  p_session_id uuid,
  p_round_number int,
  p_hide_position smallint,
  p_shot_position smallint
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
  v_defender_hid smallint;
  v_hit boolean := false;
  v_result text;
  v_defender_lives int;
  v_knockout boolean := false;
  v_penalty_type text;
  v_penalty_source text;
  v_penalty_prompt_id uuid;
  v_penalty_snapshot text;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF p_round_number IS NULL OR p_round_number < 1 THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  IF p_hide_position IS NULL OR p_hide_position NOT BETWEEN 0 AND 2
     OR p_shot_position IS NULL OR p_shot_position NOT BETWEEN 0 AND 2 THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  v_shooter_is_a := v_rel.user_a = v_user;
  v_defender := CASE WHEN v_shooter_is_a THEN v_rel.user_b ELSE v_rel.user_a END;

  -- Idempotency precedes lifecycle checks, but only the original shooter may
  -- receive the replayed result and defender reveal.
  SELECT * INTO v_existing
  FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number;

  IF FOUND THEN
    IF v_existing.active_partner_id IS DISTINCT FROM v_user THEN
      RETURN public.paint_ball_error('NOT_YOUR_TURN');
    END IF;

    SELECT r.hide_position INTO v_defender_hid
    FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_defender
      AND r.round_number < p_round_number
      AND r.hide_position IS NOT NULL
    ORDER BY r.round_number DESC
    LIMIT 1;

    RETURN jsonb_build_object(
      'session_id', p_session_id,
      'lives_a', v_session.lives_a,
      'lives_b', v_session.lives_b,
      'shot_result', v_existing.shot_result,
      'life_lost', COALESCE(v_existing.life_lost, false),
      'defender_was_at', v_defender_hid,
      'round_number', p_round_number,
      'current_turn_user_id', v_session.current_turn_user_id,
      'knockout', v_session.winner_user_id IS NOT NULL,
      'penalty_type', v_session.penalty_type,
      'penalty_source', v_session.penalty_source,
      'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
      'existing', true
    );
  END IF;

  IF v_session.status <> 'active' THEN
    RETURN public.paint_ball_error('SESSION_EXPIRED');
  END IF;

  IF v_session.winner_user_id IS NOT NULL THEN
    RETURN public.paint_ball_error('GAME_OVER');
  END IF;

  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RETURN public.paint_ball_error('NOT_YOUR_TURN');
  END IF;

  -- The shared session table historically defaulted current_round to 0.
  -- Treat that legacy value as round one; all newly-created Paint Ball rows
  -- are written as 1 explicitly.
  IF p_round_number <> GREATEST(COALESCE(v_session.current_round, 1), 1) THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_user
      AND r.created_at > now() - interval '2 seconds'
  ) THEN
    RETURN public.paint_ball_error('RATE_LIMITED');
  END IF;

  SELECT r.hide_position INTO v_defender_hid
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id
    AND r.active_partner_id = v_defender
    AND r.hide_position IS NOT NULL
  ORDER BY r.round_number DESC
  LIMIT 1;

  v_hit := v_defender_hid IS NOT NULL AND v_defender_hid = p_shot_position;
  v_result := CASE
    WHEN v_defender_hid IS NULL THEN 'opening'
    WHEN v_hit THEN 'hit'
    ELSE 'miss'
  END;

  INSERT INTO public.game_session_rounds (
    session_id,
    round_number,
    active_partner_id,
    hide_position,
    shot_position,
    shot_result,
    life_lost
  )
  VALUES (
    p_session_id,
    p_round_number,
    v_user,
    p_hide_position,
    p_shot_position,
    v_result,
    v_hit
  );

  IF v_hit THEN
    IF v_shooter_is_a THEN
      UPDATE public.game_sessions
      SET lives_b = lives_b - 1
      WHERE id = p_session_id AND lives_b > 0;
    ELSE
      UPDATE public.game_sessions
      SET lives_a = lives_a - 1
      WHERE id = p_session_id AND lives_a > 0;
    END IF;
  END IF;

  SELECT CASE WHEN v_shooter_is_a THEN lives_b ELSE lives_a END
    INTO v_defender_lives
  FROM public.game_sessions
  WHERE id = p_session_id;

  v_knockout := v_defender_lives = 0;

  IF v_knockout THEN
    v_penalty_type := CASE WHEN random() < 0.5 THEN 'truth' ELSE 'dare' END;

    IF v_session.penalty_allow_partner_authored THEN
      SELECT id, content
        INTO v_penalty_prompt_id, v_penalty_snapshot
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
      PERFORM public.increment_custom_question_usage(v_penalty_prompt_id);
    ELSE
      v_penalty_source := 'app_random';

      SELECT q.id, q.question_text
        INTO v_penalty_prompt_id, v_penalty_snapshot
      FROM public.game_questions q
      WHERE q.game_type = 'truth_or_dare'
        AND q.question_subtype = v_penalty_type
        AND q.tone = v_session.tone
        AND q.active = true
        AND NOT EXISTS (
          SELECT 1
          FROM public.game_questions_seen seen
          WHERE seen.relationship_id = v_session.relationship_id
            AND seen.question_id = q.id
        )
      ORDER BY random()
      LIMIT 1;

      -- Exhausting the unseen bank permits a repeat; it must never produce an
      -- empty penalty card.
      IF v_penalty_prompt_id IS NULL THEN
        SELECT q.id, q.question_text
          INTO v_penalty_prompt_id, v_penalty_snapshot
        FROM public.game_questions q
        WHERE q.game_type = 'truth_or_dare'
          AND q.question_subtype = v_penalty_type
          AND q.tone = v_session.tone
          AND q.active = true
        ORDER BY random()
        LIMIT 1;
      END IF;

      IF v_penalty_prompt_id IS NOT NULL THEN
        INSERT INTO public.game_questions_seen (
          relationship_id,
          question_id,
          game_type
        )
        VALUES (
          v_session.relationship_id,
          v_penalty_prompt_id,
          'truth_or_dare'
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;

    IF v_penalty_prompt_id IS NULL OR btrim(COALESCE(v_penalty_snapshot, '')) = '' THEN
      RAISE EXCEPTION 'paint_ball_penalty_prompt_unavailable';
    END IF;

    UPDATE public.game_sessions
    SET current_turn_user_id = NULL,
        winner_user_id = v_user,
        penalty_type = v_penalty_type,
        penalty_source = v_penalty_source,
        penalty_prompt_id = v_penalty_prompt_id,
        penalty_prompt_snapshot = v_penalty_snapshot,
        penalty_status = 'pending',
        total_rounds_completed = COALESCE(total_rounds_completed, 0) + 1
    WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions
    SET current_turn_user_id = v_defender,
        current_round = p_round_number + 1,
        total_rounds_completed = COALESCE(total_rounds_completed, 0) + 1
    WHERE id = p_session_id;

    INSERT INTO public.scheduled_notifications (
      user_id,
      notification_type,
      scheduled_for,
      status,
      metadata,
      source_key,
      created_at,
      updated_at
    )
    VALUES (
      v_defender,
      'immediate',
      now(),
      'pending',
      jsonb_build_object(
        'title', 'Your turn',
        'body', 'A Paint Ball move is waiting for you.',
        'type', 'game_turn',
        'relationship_id', v_session.relationship_id,
        'session_id', p_session_id,
        'game_type', 'paint_ball'
      ),
      'paint_ball_turn:' || p_session_id::text || ':' || p_round_number::text,
      now(),
      now()
    )
    ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  END IF;

  SELECT * INTO v_session
  FROM public.game_sessions
  WHERE id = p_session_id;

  RETURN jsonb_build_object(
    'session_id', p_session_id,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'shot_result', v_result,
    'life_lost', v_hit,
    'defender_was_at', v_defender_hid,
    'round_number', p_round_number,
    'current_turn_user_id', v_session.current_turn_user_id,
    'knockout', v_knockout,
    'penalty_type', v_session.penalty_type,
    'penalty_source', v_session.penalty_source,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'existing', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN public.paint_ball_error('INTERNAL_ERROR');
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_take_turn(uuid, int, smallint, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_take_turn(uuid, int, smallint, smallint)
  TO authenticated;

-- Restores the full session shape after the position-safe rebuild. Round
-- payloads deliberately contain shot_position but never hide_position.
CREATE OR REPLACE FUNCTION public.get_paint_ball_session_state(
  p_session_id uuid
)
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED')::json;
  END IF;

  SELECT * INTO v_session
  FROM public.game_sessions
  WHERE id = p_session_id
    AND game_type = 'paint_ball';

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND')::json;
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN')::json;
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'round_number', r.round_number,
        'shot_result', r.shot_result,
        'life_lost', r.life_lost,
        'created_at', r.created_at,
        'shot_position', r.shot_position,
        'active_partner_id', r.active_partner_id
      )
      ORDER BY r.round_number
    ),
    '[]'::json
  ) INTO v_rounds
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id;

  RETURN json_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'user_a_id', v_rel.user_a,
    'user_b_id', v_rel.user_b,
    'status', v_session.status,
    'game_type', v_session.game_type,
    'tone', v_session.tone,
    'current_round', GREATEST(COALESCE(v_session.current_round, 1), 1),
    'total_rounds_completed', COALESCE(v_session.total_rounds_completed, 0),
    'current_turn_user_id', v_session.current_turn_user_id,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'winner_user_id', v_session.winner_user_id,
    'penalty_type', v_session.penalty_type,
    'penalty_status', v_session.penalty_status,
    'penalty_prompt_id', v_session.penalty_prompt_id,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'penalty_source', v_session.penalty_source,
    'penalty_allow_partner_authored',
      COALESCE(v_session.penalty_allow_partner_authored, false),
    'rounds', v_rounds,
    'is_my_turn', v_session.current_turn_user_id = v_user,
    'is_winner', v_session.winner_user_id = v_user,
    'is_loser',
      v_session.winner_user_id IS NOT NULL AND v_session.winner_user_id <> v_user,
    'existing', false,
    'started_at', v_session.started_at,
    'completed_at', v_session.completed_at,
    'abandoned_at', v_session.abandoned_at,
    'created_at', v_session.created_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_paint_ball_session_state(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_paint_ball_session_state(uuid)
  TO authenticated;

-- The client opens Paint Ball from a relationship, so it needs a secure way to
-- discover an invitation or active session before it knows a session id.
-- Remote holds an earlier revision of this function with a different return
-- type, created outside the migration history. CREATE OR REPLACE cannot
-- change a return type (42P13), so drop first.
DROP FUNCTION IF EXISTS public.get_active_paint_ball_session(uuid);

CREATE OR REPLACE FUNCTION public.get_active_paint_ball_session(
  p_relationship_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session_id uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  SELECT id INTO v_session_id
  FROM public.game_sessions
  WHERE relationship_id = p_relationship_id
    AND game_type = 'paint_ball'
    AND status IN ('invited', 'active')
  ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, created_at DESC
  LIMIT 1;

  IF v_session_id IS NULL THEN
    RETURN jsonb_build_object('session', NULL);
  END IF;

  RETURN jsonb_build_object(
    'session', public.get_paint_ball_session_state(v_session_id)::jsonb
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_paint_ball_session(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_paint_ball_session(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.get_paint_ball_history(
  p_relationship_id uuid,
  p_limit int DEFAULT 20,
  p_cursor timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit int := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_items jsonb;
  v_count int;
  v_next_cursor timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'session_id', page.id,
          'tone', page.tone,
          'winner_user_id', page.winner_user_id,
          'penalty_type', page.penalty_type,
          'penalty_status', page.penalty_status,
          'total_rounds_completed', page.total_rounds_completed,
          'completed_at', page.cursor_at
        )
        ORDER BY page.cursor_at DESC
      ),
      '[]'::jsonb
    ),
    count(*),
    min(page.cursor_at)
  INTO v_items, v_count, v_next_cursor
  FROM (
    SELECT
      s.id,
      s.tone,
      s.winner_user_id,
      s.penalty_type,
      s.penalty_status,
      s.total_rounds_completed,
      COALESCE(s.completed_at, s.created_at) AS cursor_at
    FROM public.game_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.game_type = 'paint_ball'
      AND s.status = 'completed'
      AND NOT (v_user = ANY(COALESCE(s.hidden_by_user_ids, ARRAY[]::uuid[])))
      AND (
        p_cursor IS NULL
        OR COALESCE(s.completed_at, s.created_at) < p_cursor
      )
    ORDER BY cursor_at DESC
    LIMIT v_limit
  ) page;

  RETURN jsonb_build_object(
    'items', v_items,
    'next_cursor', CASE
      WHEN v_count = v_limit THEN v_next_cursor
      ELSE NULL
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_paint_ball_history(uuid, int, timestamptz)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_paint_ball_history(uuid, int, timestamptz)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.paint_ball_hide_session(
  p_session_id uuid
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session
  FROM public.game_sessions
  WHERE id = p_session_id
    AND game_type = 'paint_ball'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF v_session.status <> 'completed' THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  UPDATE public.game_sessions
  SET hidden_by_user_ids = array_append(
    COALESCE(hidden_by_user_ids, ARRAY[]::uuid[]),
    v_user
  )
  WHERE id = p_session_id
    AND NOT (v_user = ANY(COALESCE(hidden_by_user_ids, ARRAY[]::uuid[])));

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_hide_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_hide_session(uuid) TO authenticated;

-- Completion belongs to penalty resolution. The loser may freely complete or
-- decline; the winner is notified only that the shared game has wrapped up.
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.paint_ball_error('UNAUTHORIZED');
  END IF;

  IF p_outcome IS NULL OR p_outcome NOT IN ('completed', 'declined') THEN
    RETURN public.paint_ball_error('INVALID_INPUT');
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball'
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN public.paint_ball_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel
  FROM public.relationships
  WHERE id = v_session.relationship_id;

  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  -- Idempotency belongs to the loser who was allowed to resolve the prompt;
  -- completing the row does not grant the winner that mutation permission.
  IF v_session.winner_user_id = v_user THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;

  IF v_session.status <> 'active'
     OR v_session.penalty_status <> 'pending'
     OR v_session.winner_user_id IS NULL
     OR v_session.winner_user_id = v_user THEN
    RETURN public.paint_ball_error('FORBIDDEN');
  END IF;

  UPDATE public.game_sessions
  SET penalty_status = p_outcome,
      status = 'completed',
      completed_at = now()
  WHERE id = p_session_id;

  INSERT INTO public.scheduled_notifications (
    user_id,
    notification_type,
    scheduled_for,
    status,
    metadata,
    source_key,
    created_at,
    updated_at
  )
  VALUES (
    v_session.winner_user_id,
    'immediate',
    now(),
    'pending',
    jsonb_build_object(
      'title', 'Paint Ball complete',
      'body', 'Your game has wrapped up.',
      'type', 'game_complete',
      'relationship_id', v_session.relationship_id,
      'session_id', p_session_id,
      'game_type', 'paint_ball'
    ),
    'paint_ball_complete:' || p_session_id::text,
    now(),
    now()
  )
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.paint_ball_resolve_penalty(uuid, text)
  TO authenticated;
