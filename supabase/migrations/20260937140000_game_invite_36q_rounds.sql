-- A 36 Questions invitation arrives with its twelve questions.
--
-- game_invite_create made the session, the journey and chapter 1, but no
-- rounds -- on the assumption that the game would build them when the
-- card was opened. It does on one path (the continuation banner, through
-- sendContinuationInvite) and not on the other: the journey overview's
-- "Start" button routes straight into the chapter with whatever rounds
-- exist, which for an invited session was none.
--
-- Building them here rather than adding a third client call site: the
-- rounds are what makes the invitation real, and a session that only
-- becomes playable if you reach it the right way is a trap for the next
-- reader.
--
-- The selection matches the client's: chapter's active canonical
-- questions in intensity_order, the first twelve, with the English text
-- snapshotted onto the round. Locale is not a parameter because the
-- snapshot is a fallback -- the client re-reads translations for display
-- and only falls back to this text when a locale is missing.
CREATE OR REPLACE FUNCTION public.game_invite_build_36q_rounds(
  p_session_id uuid,
  p_chapter int
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  -- Idempotent: both partners may open the card at the same moment, and
  -- a second set of rounds would give them different questions for the
  -- same chapter.
  SELECT count(*) INTO v_count
    FROM public.game_session_rounds
   WHERE session_id = p_session_id;
  IF v_count > 0 THEN
    RETURN;
  END IF;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, canonical_question_id,
    question_text_snapshot, level
  )
  SELECT
    p_session_id,
    row_number() OVER (ORDER BY c.intensity_order, c.id),
    c.id,
    COALESCE(t.question_text, ''),
    p_chapter
  FROM public.thirty_six_questions_canonical c
  LEFT JOIN public.thirty_six_questions_translations t
    ON t.canonical_id = c.id AND t.locale = 'en'
  WHERE c.chapter = p_chapter
    AND c.active = true
  ORDER BY c.intensity_order, c.id
  LIMIT 12;

  -- A chapter with fewer than twelve questions is a content problem, not
  -- a user problem, but it must not become an invitation that opens onto
  -- a short chapter silently.
  SELECT count(*) INTO v_count
    FROM public.game_session_rounds
   WHERE session_id = p_session_id;
  IF v_count <> 12 THEN
    RAISE EXCEPTION
      'chapter % has % questions, needs 12', p_chapter, v_count;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.game_invite_build_36q_rounds(uuid, int)
  FROM PUBLIC, anon;

-- Wire it into the invite. Everything else about game_invite_create is
-- unchanged; this only adds the rounds for 36 Questions, after the
-- session exists.
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
    CASE WHEN v_rounds > 0 THEN 1 ELSE 0 END,
    p_tone = 'intimate',
    v_journey,
    CASE WHEN p_game_type = '36_questions' THEN 1 ELSE NULL END
  ) RETURNING id INTO v_session;

  -- The twelve questions, so every path into the chapter finds a real
  -- one rather than only the path that happens to build them.
  IF p_game_type = '36_questions' THEN
    PERFORM public.game_invite_build_36q_rounds(v_session, 1);
  END IF;

  IF p_game_type = 'love_map' THEN
    UPDATE public.game_sessions
       SET status = 'active', started_at = now()
     WHERE id = v_session;
  END IF;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

REVOKE ALL ON FUNCTION public.game_invite_create(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.game_invite_create(uuid, text, text, text)
  TO authenticated;
