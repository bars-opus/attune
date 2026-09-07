-- Makes This or That answer and next-question writes authoritative.
-- The client never chooses which partner column to update, and alternating
-- source selection is enforced while the session row is locked.

ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS state_version bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS remind_last_sent_at timestamptz;

-- A single private pick must never live in the broadly readable shared round
-- table. It moves there only when the reveal is ready for both players.
CREATE TABLE IF NOT EXISTS public.this_or_that_round_answers (
  round_id uuid NOT NULL
    REFERENCES public.game_session_rounds(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  choice text NOT NULL CHECK (choice IN ('a', 'b')),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (round_id, user_id)
);

ALTER TABLE public.this_or_that_round_answers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.this_or_that_round_answers
  FROM PUBLIC, anon, authenticated;

-- Preserve any in-flight legacy picks, then erase them from the readable row.
INSERT INTO public.this_or_that_round_answers (
  round_id,
  user_id,
  choice,
  submitted_at
)
SELECT
  round_row.id,
  rel.user_a,
  round_row.answer_a,
  COALESCE(round_row.answer_a_submitted_at, now())
FROM public.game_session_rounds round_row
JOIN public.game_sessions session_row ON session_row.id = round_row.session_id
JOIN public.relationships rel ON rel.id = session_row.relationship_id
WHERE session_row.game_type = 'this_or_that'
  AND round_row.answer_a IS NOT NULL
ON CONFLICT (round_id, user_id) DO NOTHING;

INSERT INTO public.this_or_that_round_answers (
  round_id,
  user_id,
  choice,
  submitted_at
)
SELECT
  round_row.id,
  rel.user_b,
  round_row.answer_b,
  COALESCE(round_row.answer_b_submitted_at, now())
FROM public.game_session_rounds round_row
JOIN public.game_sessions session_row ON session_row.id = round_row.session_id
JOIN public.relationships rel ON rel.id = session_row.relationship_id
WHERE session_row.game_type = 'this_or_that'
  AND round_row.answer_b IS NOT NULL
ON CONFLICT (round_id, user_id) DO NOTHING;

UPDATE public.game_session_rounds round_row
   SET answer_a = NULL,
       answer_b = NULL,
       answer_a_submitted_at = NULL,
       answer_b_submitted_at = NULL
  FROM public.game_sessions session_row
 WHERE session_row.id = round_row.session_id
   AND session_row.game_type = 'this_or_that'
   AND round_row.both_answered = false;

CREATE OR REPLACE FUNCTION public.guard_this_or_that_session_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated')
     AND (CASE
       WHEN TG_OP = 'DELETE' THEN OLD.game_type
       ELSE NEW.game_type
     END) = 'this_or_that' THEN
    RAISE EXCEPTION 'Use the This or That game API';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS guard_this_or_that_session_write
  ON public.game_sessions;
CREATE TRIGGER guard_this_or_that_session_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.game_sessions
  FOR EACH ROW EXECUTE FUNCTION public.guard_this_or_that_session_write();

CREATE OR REPLACE FUNCTION public.guard_this_or_that_round_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_session_id uuid := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.session_id
    ELSE NEW.session_id
  END;
BEGIN
  IF current_user IN ('anon', 'authenticated') AND EXISTS (
    SELECT 1
    FROM public.game_sessions session_row
    WHERE session_row.id = v_session_id
      AND session_row.game_type = 'this_or_that'
  ) THEN
    RAISE EXCEPTION 'Use the This or That game API';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS guard_this_or_that_round_write
  ON public.game_session_rounds;
CREATE TRIGGER guard_this_or_that_round_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.game_session_rounds
  FOR EACH ROW EXECUTE FUNCTION public.guard_this_or_that_round_write();

REVOKE ALL ON FUNCTION public.guard_this_or_that_session_write()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_this_or_that_round_write()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bump_this_or_that_session_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  v_session_id := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.session_id
    ELSE NEW.session_id
  END;
  UPDATE public.game_sessions
     SET state_version = state_version + 1
   WHERE id = v_session_id
     AND game_type = 'this_or_that';
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_this_or_that_session_version()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS bump_this_or_that_session_version
  ON public.game_session_rounds;
CREATE TRIGGER bump_this_or_that_session_version
  AFTER INSERT OR UPDATE OR DELETE ON public.game_session_rounds
  FOR EACH ROW EXECUTE FUNCTION public.bump_this_or_that_session_version();

CREATE OR REPLACE FUNCTION public.bump_this_or_that_answer_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_round_id uuid := CASE
    WHEN TG_OP = 'DELETE' THEN OLD.round_id
    ELSE NEW.round_id
  END;
BEGIN
  UPDATE public.game_sessions session_row
     SET state_version = session_row.state_version + 1
    FROM public.game_session_rounds round_row
   WHERE round_row.id = v_round_id
     AND session_row.id = round_row.session_id
     AND session_row.game_type = 'this_or_that';
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_this_or_that_answer_version()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS bump_this_or_that_answer_version
  ON public.this_or_that_round_answers;
CREATE TRIGGER bump_this_or_that_answer_version
  AFTER INSERT OR UPDATE OR DELETE ON public.this_or_that_round_answers
  FOR EACH ROW EXECUTE FUNCTION public.bump_this_or_that_answer_version();

CREATE OR REPLACE FUNCTION public.this_or_that_round_state(
  p_session_id uuid
)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', r.id,
    'session_id', r.session_id,
    'round_number', r.round_number,
    'question_id', r.question_id,
    'answer_a', CASE
      WHEN r.both_answered THEN r.answer_a
      WHEN rel.user_a = auth.uid() THEN own_answer.choice
      ELSE NULL
    END,
    'answer_b', CASE
      WHEN r.both_answered THEN r.answer_b
      WHEN rel.user_b = auth.uid() THEN own_answer.choice
      ELSE NULL
    END,
    'answer_a_submitted_at', CASE
      WHEN r.both_answered THEN r.answer_a_submitted_at
      WHEN rel.user_a = auth.uid() THEN own_answer.submitted_at
      ELSE NULL
    END,
    'answer_b_submitted_at', CASE
      WHEN r.both_answered THEN r.answer_b_submitted_at
      WHEN rel.user_b = auth.uid() THEN own_answer.submitted_at
      ELSE NULL
    END,
    'has_answer_a', EXISTS (
      SELECT 1
      FROM public.this_or_that_round_answers answer_presence
      WHERE answer_presence.round_id = r.id
        AND answer_presence.user_id = rel.user_a
    ),
    'has_answer_b', EXISTS (
      SELECT 1
      FROM public.this_or_that_round_answers answer_presence
      WHERE answer_presence.round_id = r.id
        AND answer_presence.user_id = rel.user_b
    ),
    'both_answered', r.both_answered,
    'reveal_triggered_at', r.reveal_triggered_at,
    'is_custom', r.is_custom,
    'custom_question_data', r.custom_question_data,
    'game_questions', CASE
      WHEN q.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'question_text', q.question_text,
        'option_a', q.option_a,
        'option_b', q.option_b,
        'emoji_a', q.emoji_a,
        'emoji_b', q.emoji_b,
        'is_interesting', q.is_interesting
      )
    END
  )
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  LEFT JOIN public.game_questions q ON q.id = r.question_id
  LEFT JOIN public.this_or_that_round_answers own_answer
    ON own_answer.round_id = r.id
   AND own_answer.user_id = auth.uid()
  WHERE r.session_id = p_session_id
    AND s.game_type = 'this_or_that'
    AND (rel.user_a = auth.uid() OR rel.user_b = auth.uid())
  ORDER BY r.round_number;
$$;

REVOKE ALL ON FUNCTION public.this_or_that_round_state(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.this_or_that_round_state(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.submit_this_or_that_answer(
  p_round_id uuid,
  p_choice text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
  v_relationship_id uuid;
  v_current_round integer;
  v_round_number integer;
  v_question_id uuid;
  v_answer_a text;
  v_answer_b text;
  v_answer_a_submitted_at timestamptz;
  v_answer_b_submitted_at timestamptz;
  v_both_answered boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_choice NOT IN ('a', 'b') THEN
    RAISE EXCEPTION 'Choice must be a or b';
  END IF;

  SELECT rel.user_a,
         rel.user_b,
         rel.id,
         s.current_round,
         r.round_number,
         r.question_id,
         r.both_answered
    INTO v_user_a,
         v_user_b,
         v_relationship_id,
         v_current_round,
         v_round_number,
         v_question_id,
         v_both_answered
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND s.game_type = 'this_or_that'
    AND s.status = 'active'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF r, s;

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Playable round not found';
  END IF;
  IF v_both_answered THEN
    RAISE EXCEPTION 'Round is already revealed';
  END IF;
  IF v_round_number <> v_current_round THEN
    RAISE EXCEPTION 'Only the current round can be answered';
  END IF;

  INSERT INTO public.this_or_that_round_answers (
    round_id,
    user_id,
    choice,
    submitted_at
  ) VALUES (
    p_round_id,
    v_user_id,
    p_choice,
    now()
  )
  ON CONFLICT (round_id, user_id) DO UPDATE
    SET choice = EXCLUDED.choice,
        submitted_at = EXCLUDED.submitted_at;

  SELECT
    max(private_answer.choice) FILTER (
      WHERE private_answer.user_id = v_user_a
    ),
    max(private_answer.choice) FILTER (
      WHERE private_answer.user_id = v_user_b
    ),
    max(private_answer.submitted_at) FILTER (
      WHERE private_answer.user_id = v_user_a
    ),
    max(private_answer.submitted_at) FILTER (
      WHERE private_answer.user_id = v_user_b
    )
    INTO
      v_answer_a,
      v_answer_b,
      v_answer_a_submitted_at,
      v_answer_b_submitted_at
  FROM public.this_or_that_round_answers private_answer
  WHERE private_answer.round_id = p_round_id;

  IF v_answer_a IS NOT NULL AND v_answer_b IS NOT NULL THEN
    UPDATE public.game_session_rounds
       SET answer_a = v_answer_a,
           answer_b = v_answer_b,
           answer_a_submitted_at = v_answer_a_submitted_at,
           answer_b_submitted_at = v_answer_b_submitted_at,
           both_answered = true,
           reveal_triggered_at = COALESCE(reveal_triggered_at, now())
     WHERE id = p_round_id;

    IF v_question_id IS NOT NULL THEN
      INSERT INTO public.game_questions_seen (
        relationship_id,
        question_id,
        game_type,
        seen_at
      )
      VALUES (
        v_relationship_id,
        v_question_id,
        'this_or_that',
        now()
      )
      ON CONFLICT (relationship_id, question_id)
      DO UPDATE SET seen_at = EXCLUDED.seen_at;
    END IF;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_this_or_that_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_this_or_that_answer(uuid, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.choose_this_or_that_next_question(
  p_session_id uuid,
  p_round_number integer,
  p_source text,
  p_custom_owner_id uuid DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
  v_tone text;
  v_current_round integer;
  v_total_rounds integer;
  v_chooser_id uuid;
  v_tone_level integer;
  v_question public.game_questions%ROWTYPE;
  v_custom public.custom_this_or_that_questions%ROWTYPE;
  v_result text := p_source;
  v_match_count integer;
  v_completed_count integer;
  v_updated_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_source NOT IN ('preset', 'custom') THEN
    RAISE EXCEPTION 'Source must be preset or custom';
  END IF;

  SELECT rel.user_a,
         rel.user_b,
         s.tone,
         s.current_round,
         s.total_rounds
    INTO v_user_a,
         v_user_b,
         v_tone,
         v_current_round,
         v_total_rounds
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'this_or_that'
    AND s.status = 'active'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF s;

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Active session not found';
  END IF;
  IF p_round_number <= v_current_round THEN
    RETURN 'already_selected';
  END IF;
  IF p_round_number <> v_current_round + 1
     OR p_round_number > v_total_rounds THEN
    RAISE EXCEPTION 'Invalid next round';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.game_session_rounds current_round
    WHERE current_round.session_id = p_session_id
      AND current_round.round_number = v_current_round
      AND current_round.both_answered = true
  ) THEN
    RAISE EXCEPTION 'Current round is not complete';
  END IF;

  v_chooser_id := CASE
    WHEN p_round_number % 2 = 0 THEN v_user_a
    ELSE v_user_b
  END;
  IF v_user_id <> v_chooser_id THEN
    RAISE EXCEPTION 'It is not your turn to choose';
  END IF;

  IF p_source = 'custom' THEN
    IF p_custom_owner_id IS NULL
       OR p_custom_owner_id NOT IN (v_user_a, v_user_b) THEN
      RAISE EXCEPTION 'Custom deck owner must be one of the partners';
    END IF;

    SELECT cq.*
      INTO v_custom
    FROM public.custom_this_or_that_questions cq
    WHERE cq.user_id = p_custom_owner_id
      AND cq.is_private = false
      AND cq.hidden_for_review = false
      AND cq.tone = v_tone
      AND NOT EXISTS (
        SELECT 1
        FROM public.game_session_rounds used
        WHERE used.session_id = p_session_id
          AND used.custom_question_data->>'custom_question_id' = cq.id::text
      )
    ORDER BY cq.times_used ASC, cq.last_used_at ASC NULLS FIRST
    LIMIT 1;

    IF v_custom.id IS NULL THEN
      v_result := 'preset_fallback';
    END IF;
  END IF;

  IF p_source = 'preset' OR v_custom.id IS NULL THEN
    v_tone_level := CASE v_tone
      WHEN 'intimate' THEN 4
      WHEN 'spicy' THEN 3
      WHEN 'romantic' THEN 2
      ELSE 1
    END;

    SELECT q.*
      INTO v_question
    FROM public.game_questions q
    WHERE q.game_type = 'this_or_that'
      AND q.active = true
      AND (q.tone = 'playful' OR q.tone_level <= v_tone_level)
      AND NOT EXISTS (
        SELECT 1
        FROM public.game_session_rounds used
        WHERE used.session_id = p_session_id
          AND used.question_id = q.id
      )
    ORDER BY random()
    LIMIT 1;

    IF v_question.id IS NULL THEN
      SELECT q.*
        INTO v_question
      FROM public.game_questions q
      WHERE q.game_type = 'this_or_that'
        AND q.active = true
        AND (q.tone = 'playful' OR q.tone_level <= v_tone_level)
      ORDER BY random()
      LIMIT 1;
    END IF;
    IF v_question.id IS NULL THEN
      RAISE EXCEPTION 'No eligible preset question is available';
    END IF;
  END IF;

  IF v_custom.id IS NOT NULL THEN
    DELETE FROM public.this_or_that_round_answers private_answer
    USING public.game_session_rounds target_round
    WHERE target_round.id = private_answer.round_id
      AND target_round.session_id = p_session_id
      AND target_round.round_number = p_round_number;

    UPDATE public.game_session_rounds
       SET question_id = NULL,
           is_custom = true,
           custom_question_data = jsonb_build_object(
             'custom_question_id', v_custom.id,
             'question_text', v_custom.question_text,
             'option_a', v_custom.option_a,
             'option_b', v_custom.option_b,
             'emoji_a', v_custom.emoji_a,
             'emoji_b', v_custom.emoji_b
           ),
           answer_a = NULL,
           answer_b = NULL,
           answer_a_submitted_at = NULL,
           answer_b_submitted_at = NULL,
           both_answered = false,
           reveal_triggered_at = NULL
     WHERE session_id = p_session_id
       AND round_number = p_round_number;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    UPDATE public.custom_this_or_that_questions
       SET times_used = times_used + 1,
           last_used_at = now()
     WHERE id = v_custom.id;
  ELSE
    DELETE FROM public.this_or_that_round_answers private_answer
    USING public.game_session_rounds target_round
    WHERE target_round.id = private_answer.round_id
      AND target_round.session_id = p_session_id
      AND target_round.round_number = p_round_number;

    UPDATE public.game_session_rounds
       SET question_id = v_question.id,
           is_custom = false,
           custom_question_data = NULL,
           answer_a = NULL,
           answer_b = NULL,
           answer_a_submitted_at = NULL,
           answer_b_submitted_at = NULL,
           both_answered = false,
           reveal_triggered_at = NULL
     WHERE session_id = p_session_id
       AND round_number = p_round_number;
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  END IF;

  IF v_updated_count = 0 THEN
    RAISE EXCEPTION 'Prepared round not found';
  END IF;

  SELECT count(*) FILTER (WHERE both_answered),
         count(*) FILTER (
           WHERE both_answered
             AND answer_a IS NOT NULL
             AND answer_a = answer_b
         )
    INTO v_completed_count, v_match_count
  FROM public.game_session_rounds
  WHERE session_id = p_session_id;

  UPDATE public.game_sessions
     SET current_round = p_round_number,
         total_rounds_completed = v_completed_count,
         match_count = v_match_count
   WHERE id = p_session_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.choose_this_or_that_next_question(
  uuid,
  integer,
  text,
  uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.choose_this_or_that_next_question(
  uuid,
  integer,
  text,
  uuid
) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_this_or_that_session(
  p_relationship_id uuid,
  p_tone text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_session_id uuid;
  v_key_relationship_id uuid;
  v_key_game_type text;
  v_recent_count integer;
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_tone NOT IN ('connecting', 'romantic', 'playful', 'spicy', 'intimate')
     OR p_idempotency_key IS NULL
     OR btrim(p_idempotency_key) = '' THEN
    RAISE EXCEPTION 'Invalid game settings';
  END IF;
  SELECT rel.user_a, rel.user_b INTO v_user_a, v_user_b
  FROM public.relationships rel
  WHERE rel.id = p_relationship_id
    AND rel.status = 'active'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);
  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Relationship unavailable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session_id, v_key_relationship_id, v_key_game_type
  FROM public.session_idempotency_keys k
  JOIN public.game_sessions s ON s.id = k.session_id
  WHERE k.key = p_idempotency_key;

  IF v_session_id IS NOT NULL THEN
    IF v_key_relationship_id <> p_relationship_id
       OR v_key_game_type <> 'this_or_that' THEN
      RAISE EXCEPTION 'Idempotency key unavailable';
    END IF;
    RETURN (
      SELECT to_jsonb(session_row)
      FROM public.game_sessions session_row
      WHERE session_row.id = v_session_id
    );
  END IF;

  SELECT s.id INTO v_session_id
  FROM public.game_sessions s
  WHERE s.relationship_id = p_relationship_id
    AND s.game_type = 'this_or_that'
    AND s.status IN ('invited', 'active')
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_session_id IS NULL THEN
    SELECT count(*) INTO v_recent_count
    FROM public.game_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.created_at > now() - interval '1 hour';
    IF v_recent_count >= 5 THEN
      RAISE EXCEPTION 'Too many games started. Try again later.';
    END IF;

    INSERT INTO public.game_sessions (
      relationship_id,
      initiator_id,
      game_type,
      tone,
      status,
      total_rounds,
      current_round,
      intimate_consent_a,
      intimate_consent_b
    )
    VALUES (
      p_relationship_id,
      v_user_id,
      'this_or_that',
      p_tone,
      'invited',
      10,
      1,
      p_tone = 'intimate' AND v_user_id = v_user_a,
      p_tone = 'intimate' AND v_user_id = v_user_b
    )
    RETURNING id INTO v_session_id;

    INSERT INTO public.session_idempotency_keys (key, session_id)
    VALUES (p_idempotency_key, v_session_id);
  END IF;

  RETURN (
    SELECT to_jsonb(session_row)
    FROM public.game_sessions session_row
    WHERE session_row.id = v_session_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_this_or_that_session(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_this_or_that_session(uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_this_or_that_session(
  p_session_id uuid,
  p_intimate_consent boolean DEFAULT false,
  p_fallback_tone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_user_a uuid;
  v_user_b uuid;
  v_tone text;
  v_tone_level integer;
  v_round_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'this_or_that'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF s;

  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Invitation unavailable';
  END IF;

  SELECT rel.user_a, rel.user_b INTO v_user_a, v_user_b
  FROM public.relationships rel
  WHERE rel.id = v_session.relationship_id;
  IF v_session.status = 'active' THEN
    RETURN to_jsonb(v_session);
  END IF;
  IF v_session.status <> 'invited' THEN
    RAISE EXCEPTION 'Invitation has ended';
  END IF;
  IF v_session.initiator_id = v_user_id THEN
    RAISE EXCEPTION 'Only the invited partner can accept';
  END IF;

  IF p_fallback_tone IS NOT NULL THEN
    IF v_session.tone <> 'intimate' OR p_fallback_tone <> 'spicy' THEN
      RAISE EXCEPTION 'Invalid fallback tone';
    END IF;
    v_tone := 'spicy';
  ELSE
    v_tone := v_session.tone;
  END IF;
  IF v_session.tone = 'intimate'
     AND p_fallback_tone IS NULL
     AND NOT COALESCE(p_intimate_consent, false) THEN
    RAISE EXCEPTION 'Intimate consent is required';
  END IF;

  v_tone_level := CASE v_tone
    WHEN 'intimate' THEN 4
    WHEN 'spicy' THEN 3
    WHEN 'romantic' THEN 2
    ELSE 1
  END;

  -- Legacy clients may have left a partial deck. Rebuilding while the
  -- invitation row is locked makes acceptance atomic and deterministic.
  DELETE FROM public.game_session_rounds
  WHERE session_id = p_session_id;

  WITH custom_candidates AS MATERIALIZED (
    SELECT
      NULL::uuid AS question_id,
      true AS is_custom,
      jsonb_build_object(
        'custom_question_id', custom_question.id,
        'question_text', custom_question.question_text,
        'option_a', custom_question.option_a,
        'option_b', custom_question.option_b,
        'emoji_a', custom_question.emoji_a,
        'emoji_b', custom_question.emoji_b
      ) AS custom_question_data
    FROM public.custom_this_or_that_questions custom_question
    WHERE custom_question.user_id IN (v_user_a, v_user_b)
      AND custom_question.is_private = false
      AND custom_question.hidden_for_review = false
      AND custom_question.tone = v_tone
    ORDER BY
      custom_question.times_used ASC,
      custom_question.last_used_at ASC NULLS FIRST,
      random()
    LIMIT 3
  ),
  preset_candidates AS MATERIALIZED (
    SELECT
      preset.id AS question_id,
      false AS is_custom,
      NULL::jsonb AS custom_question_data
    FROM public.game_questions preset
    WHERE preset.game_type = 'this_or_that'
      AND preset.active = true
      AND (preset.tone = 'playful' OR preset.tone_level <= v_tone_level)
    ORDER BY
      CASE
        WHEN v_tone = 'intimate' AND preset.tone_level = 4 THEN 0
        ELSE 1
      END,
      EXISTS (
        SELECT 1
        FROM public.game_questions_seen seen
        WHERE seen.relationship_id = v_session.relationship_id
          AND seen.question_id = preset.id
      ),
      random()
    LIMIT (10 - (SELECT count(*) FROM custom_candidates))
  ),
  deck AS (
    SELECT * FROM custom_candidates
    UNION ALL
    SELECT * FROM preset_candidates
  ),
  shuffled_deck AS (
    SELECT
      question_id,
      is_custom,
      custom_question_data,
      row_number() OVER (ORDER BY random())::integer AS round_number
    FROM deck
  )
  INSERT INTO public.game_session_rounds (
    session_id,
    round_number,
    question_id,
    is_custom,
    custom_question_data
  )
  SELECT
    p_session_id,
    round_number,
    question_id,
    is_custom,
    custom_question_data
  FROM shuffled_deck;

  GET DIAGNOSTICS v_round_count = ROW_COUNT;
  IF v_round_count <> 10 THEN
    RAISE EXCEPTION 'Not enough eligible questions to start this game';
  END IF;

  UPDATE public.custom_this_or_that_questions custom_question
     SET times_used = custom_question.times_used + 1,
         last_used_at = now()
   WHERE EXISTS (
     SELECT 1
     FROM public.game_session_rounds round_row
     WHERE round_row.session_id = p_session_id
       AND round_row.custom_question_data->>'custom_question_id' =
           custom_question.id::text
   );

  UPDATE public.game_sessions
     SET status = 'active',
         tone = v_tone,
         current_round = 1,
         total_rounds = 10,
         match_count = 0,
         total_rounds_completed = 0,
         intimate_consent_a = CASE
           WHEN v_tone <> 'intimate' THEN false
           WHEN v_user_id = v_user_a THEN p_intimate_consent
           ELSE v_session.intimate_consent_a
         END,
         intimate_consent_b = CASE
           WHEN v_tone <> 'intimate' THEN false
           WHEN v_user_id = v_user_b THEN p_intimate_consent
           ELSE v_session.intimate_consent_b
         END,
         started_at = now()
   WHERE id = p_session_id
   RETURNING * INTO v_session;

  RETURN to_jsonb(v_session);
END;
$$;

REVOKE ALL ON FUNCTION public.accept_this_or_that_session(uuid, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_this_or_that_session(uuid, boolean, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_this_or_that_session(
  p_session_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_completed_count integer;
  v_match_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT s.* INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'this_or_that'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF s;

  IF v_session.id IS NULL THEN
    RAISE EXCEPTION 'Session unavailable';
  END IF;
  IF v_session.status = 'completed' THEN
    RETURN to_jsonb(v_session);
  END IF;
  IF v_session.status <> 'active' THEN
    RAISE EXCEPTION 'Session is not active';
  END IF;

  SELECT
    count(*) FILTER (WHERE round_row.both_answered),
    count(*) FILTER (
      WHERE round_row.both_answered
        AND round_row.answer_a IS NOT NULL
        AND round_row.answer_a = round_row.answer_b
    )
    INTO v_completed_count, v_match_count
  FROM public.game_session_rounds round_row
  WHERE round_row.session_id = p_session_id;

  IF v_completed_count <> v_session.total_rounds THEN
    RAISE EXCEPTION 'Every round must be answered before completion';
  END IF;

  UPDATE public.game_sessions
     SET status = 'completed',
         current_round = total_rounds,
         total_rounds_completed = v_completed_count,
         match_count = v_match_count,
         completed_at = COALESCE(completed_at, now())
   WHERE id = p_session_id
   RETURNING * INTO v_session;

  RETURN to_jsonb(v_session);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_this_or_that_session(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_this_or_that_session(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.hide_this_or_that_session(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE public.game_sessions session_row
     SET hidden_by_user_ids = array_append(
       session_row.hidden_by_user_ids,
       v_user_id
     )
   WHERE session_row.id = p_session_id
     AND session_row.game_type = 'this_or_that'
     AND session_row.status = 'completed'
     AND NOT (v_user_id = ANY(session_row.hidden_by_user_ids))
     AND EXISTS (
       SELECT 1
       FROM public.relationships rel
       WHERE rel.id = session_row.relationship_id
         AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
     );
END;
$$;

REVOKE ALL ON FUNCTION public.hide_this_or_that_session(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.hide_this_or_that_session(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.request_this_or_that_reminder(
  p_session_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
  v_current_round integer;
  v_remind_last_sent_at timestamptz;
  v_answer_a text;
  v_answer_b text;
  v_answer_a_submitted_at timestamptz;
  v_answer_b_submitted_at timestamptz;
  v_recipient_id uuid;
  v_sender_name text;
  v_player_id text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT
    rel.user_a,
    rel.user_b,
    session_row.current_round,
    session_row.remind_last_sent_at
    INTO v_user_a, v_user_b, v_current_round, v_remind_last_sent_at
  FROM public.game_sessions session_row
  JOIN public.relationships rel ON rel.id = session_row.relationship_id
  WHERE session_row.id = p_session_id
    AND session_row.game_type = 'this_or_that'
    AND session_row.status = 'active'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF session_row;

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Active session unavailable';
  END IF;

  SELECT
    max(private_answer.choice) FILTER (
      WHERE private_answer.user_id = v_user_a
    ),
    max(private_answer.choice) FILTER (
      WHERE private_answer.user_id = v_user_b
    ),
    max(private_answer.submitted_at) FILTER (
      WHERE private_answer.user_id = v_user_a
    ),
    max(private_answer.submitted_at) FILTER (
      WHERE private_answer.user_id = v_user_b
    )
    INTO
      v_answer_a,
      v_answer_b,
      v_answer_a_submitted_at,
      v_answer_b_submitted_at
  FROM public.game_session_rounds round_row
  LEFT JOIN public.this_or_that_round_answers private_answer
    ON private_answer.round_id = round_row.id
  WHERE round_row.session_id = p_session_id
    AND round_row.round_number = v_current_round;

  IF v_user_id = v_user_a THEN
    IF v_answer_a IS NULL OR v_answer_b IS NOT NULL THEN
      RAISE EXCEPTION 'A reminder is not available for this round';
    END IF;
    IF v_answer_a_submitted_at > now() - interval '2 hours' THEN
      RAISE EXCEPTION 'The reminder is not ready yet';
    END IF;
    v_recipient_id := v_user_b;
  ELSE
    IF v_answer_b IS NULL OR v_answer_a IS NOT NULL THEN
      RAISE EXCEPTION 'A reminder is not available for this round';
    END IF;
    IF v_answer_b_submitted_at > now() - interval '2 hours' THEN
      RAISE EXCEPTION 'The reminder is not ready yet';
    END IF;
    v_recipient_id := v_user_a;
  END IF;

  IF v_remind_last_sent_at IS NOT NULL
     AND v_remind_last_sent_at > now() - interval '4 hours' THEN
    RAISE EXCEPTION 'A reminder was sent recently';
  END IF;

  UPDATE public.game_sessions
     SET remind_last_sent_at = now()
   WHERE id = p_session_id;

  SELECT profile.display_name INTO v_sender_name
  FROM public.profiles profile
  WHERE profile.id = v_user_id;
  SELECT profile.onesignal_player_id INTO v_player_id
  FROM public.profiles profile
  WHERE profile.id = v_recipient_id;

  RETURN jsonb_build_object(
    'recipient_id', v_recipient_id,
    'player_id', v_player_id,
    'sender_name', COALESCE(v_sender_name, 'Your partner')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_this_or_that_reminder(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_this_or_that_reminder(uuid)
  TO authenticated;

-- This or That is designed as a short asynchronous game. Keep the existing
-- seven-day safety net for the other session games, but enforce this game's
-- documented invitation and current-round windows using actual answer/reveal
-- activity rather than the deck row's creation time.
CREATE OR REPLACE FUNCTION public.expire_stale_session_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH stale AS (
    UPDATE public.game_sessions session_row
       SET status = 'abandoned',
           abandon_reason = CASE
             WHEN session_row.status = 'invited' THEN 'invite_expired'
             ELSE 'inactivity'
           END,
           abandoned_at = now()
     WHERE session_row.status IN ('invited', 'active')
       AND (
         (
           session_row.game_type = 'this_or_that'
           AND (
             (
               session_row.status = 'invited'
               AND session_row.created_at < now() - interval '48 hours'
             )
             OR (
               session_row.status = 'active'
               AND COALESCE(
                 (
                   SELECT CASE
                     WHEN current_round.both_answered
                       THEN current_round.reveal_triggered_at
                     ELSE (
                       SELECT max(private_answer.submitted_at)
                       FROM public.this_or_that_round_answers private_answer
                       WHERE private_answer.round_id = current_round.id
                     )
                   END
                   FROM public.game_session_rounds current_round
                   WHERE current_round.session_id = session_row.id
                     AND current_round.round_number = session_row.current_round
                 ),
                 session_row.started_at,
                 session_row.created_at
               ) < now() - interval '24 hours'
             )
           )
         )
         OR (
           session_row.game_type IN (
             'mirror',
             'sliding_scale',
             'scenario',
             'truth_or_dare'
           )
           AND COALESCE(
             (
               SELECT max(round_row.created_at)
               FROM public.game_session_rounds round_row
               WHERE round_row.session_id = session_row.id
             ),
             session_row.created_at
           ) < now() - interval '7 days'
         )
       )
    RETURNING session_row.id
  )
  SELECT count(*) INTO v_count FROM stale;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.expire_stale_session_games()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_session_games()
  TO service_role;
