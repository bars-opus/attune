-- A Love Map invitation opens active, not invited.
--
-- Love Map is deliberately sessionless: its rounds carry relationship_id
-- and no session (see the comment on game_session_rounds.relationship_id),
-- and a weekly cron opens three prompts per couple. There is nothing to
-- accept -- the prompts are already there for both partners.
--
-- Left as 'invited', its card would read "Waiting for them" forever,
-- because no code path in Love Map ever accepts a session. So the
-- invitation is created active: the card is a pointer to a shared
-- surface, which is what saying "let's do our Love Map" actually means.
--
-- The session row still exists so the card exists. That is its whole
-- job: post_game_message fires on the INSERT (status 'invited'), and the
-- row is moved to 'active' in the same transaction, so the card is
-- posted and the game is immediately open.
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

  -- Love Map has nothing to accept, so it opens already accepted. The
  -- INSERT above has already fired post_game_message and posted the
  -- card; this only changes what that card says.
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
