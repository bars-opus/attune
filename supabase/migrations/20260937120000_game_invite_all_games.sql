-- Every game can be invited.
--
-- game_invite_create inserted a bare session row, which four games could
-- not start from: they need columns the row did not carry, or rows in
-- other tables. The previous migration handled that by refusing them --
-- honest, but it left four games without an invitation.
--
-- The shape each game needs is small and knowable, so it lives here
-- rather than in four client call sites. What this does NOT do is
-- duplicate a game's own create: Snakes still picks its board, Paint
-- Ball still takes a tone from its lobby, This or That still builds its
-- rounds in create_this_or_that_session. This makes the SESSION each
-- game expects to find, and the game does the rest on open.

CREATE OR REPLACE FUNCTION public.game_invite_type_allowed(p_game_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_game_type IN (
    'this_or_that',
    'truth_or_dare',
    '36_questions',
    'mirror',
    'sliding_scale',
    'scenario',
    'love_map',
    'paint_ball',
    'snakes_and_ladders',
    'word_hunt'
  );
$$;

-- How many rounds a game's session declares up front.
--
-- Zero means the game decides later: the session games size themselves
-- from the questions actually available, and Snakes and Word Hunt have
-- no round count at all. A wrong number here is not cosmetic -- a card
-- reads "Round 1 of 0" from it, and This or That clamps its progress
-- against it.
CREATE OR REPLACE FUNCTION public.game_invite_total_rounds(p_game_type text)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_game_type
    WHEN 'truth_or_dare' THEN 10
    WHEN '36_questions'  THEN 12
    WHEN 'this_or_that'  THEN 10
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.game_invite_create(
  p_relationship_id uuid,
  p_game_type text,
  p_idempotency_key text,
  p_tone text DEFAULT 'connecting'
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
  v_rounds int;
  v_journey uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.game_invite_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_game_type IS NULL
     OR p_idempotency_key IS NULL
     OR length(p_idempotency_key) = 0
     OR length(p_idempotency_key) > 200
     OR NOT public.game_invite_type_allowed(p_game_type)
     -- Allowlisted, not free text: tone is written to the row and read
     -- back by the games to pick their question set, and 'intimate'
     -- gates consent.
     OR p_tone IS NULL
     OR p_tone NOT IN ('connecting', 'playful', 'romantic', 'intimate')
  THEN
    RETURN public.game_invite_error('INVALID_INPUT');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
     WHERE id = p_relationship_id
       AND status = 'active'
       AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.game_invite_error('FORBIDDEN');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));
  PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
    FROM public.session_idempotency_keys k
    JOIN public.game_sessions s ON s.id = k.session_id
   WHERE k.key = p_idempotency_key;
  IF v_session IS NOT NULL THEN
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.game_invite_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> p_game_type THEN
      RETURN public.game_invite_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  SELECT id INTO v_session
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND game_type = p_game_type
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
    RETURN public.game_invite_error('RATE_LIMITED');
  END IF;

  v_rounds := public.game_invite_total_rounds(p_game_type);

  -- 36 Questions is a journey of three chapters, and every one of its
  -- own queries filters by journey_id -- a session without one is
  -- invisible to the game that owns it. An invitation starts at
  -- chapter 1, resuming an in-progress journey if the couple has one,
  -- because the invite is "let's do this together", not "start over".
  IF p_game_type = '36_questions' THEN
    SELECT id INTO v_journey
      FROM public.thirty_six_question_journeys
     WHERE relationship_id = p_relationship_id
       AND status = 'in_progress'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_journey IS NULL THEN
      INSERT INTO public.thirty_six_question_journeys (
        relationship_id, status
      ) VALUES (p_relationship_id, 'in_progress')
      RETURNING id INTO v_journey;
    END IF;
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, status, tone,
    total_rounds, current_round,
    intimate_consent_a,
    journey_id, chapter
  ) VALUES (
    p_relationship_id, v_user, p_game_type, 'invited', p_tone,
    v_rounds,
    -- A game with rounds starts on the first one. Zero would read as
    -- "Round 0", which is not a round anyone can be on.
    CASE WHEN v_rounds > 0 THEN 1 ELSE 0 END,
    -- The inviter consents by choosing the tone; the partner's consent
    -- is theirs to give when they accept.
    p_tone = 'intimate',
    v_journey,
    CASE WHEN p_game_type = '36_questions' THEN 1 ELSE NULL END
  ) RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.game_invite_create(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.game_invite_create(uuid, text, text, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.game_invite_total_rounds(text) FROM PUBLIC, anon;

-- The 3-argument form is gone: leaving it would keep an entry point that
-- creates sessions without a tone, and callers would silently keep using it.
DROP FUNCTION IF EXISTS public.game_invite_create(uuid, text, text);
