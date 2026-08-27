-- Mirror's third value, its judgement, and a derived score.
--
-- §8.4 gives Mirror three values per round: each partner's guess and the
-- subject's real answer. submit_session_game_answer writes only
-- answer_a/answer_b, and mirror_round_truth has no client write path at
-- all — so both_answered could flip on two guesses with no truth
-- recorded, and mirror_scores stayed empty. Mirror could never produce a
-- scoreable round.

-- ---------------------------------------------------------------------
-- 1. The judgement lives on the row that already exists per round
-- ---------------------------------------------------------------------

-- Nullable: NULL means "not yet judged". Keeping the judgement on
-- mirror_round_truth means one Mirror round is one row, with no second
-- table keyed on the same round_id and no second RLS policy to keep in
-- step.
ALTER TABLE public.mirror_round_truth
  ADD COLUMN IF NOT EXISTS was_correct boolean,
  ADD COLUMN IF NOT EXISTS judged_at timestamptz;

-- ---------------------------------------------------------------------
-- 2. submit_session_game_answer routes mirror writes by subject
--
-- The signature does NOT change. The function already looks up the round
-- and joins to relationships, so it can compare auth.uid() against
-- active_partner_id and derive the destination itself. That is the whole
-- point: the client keeps calling submitAnswer(roundId, answer) and
-- cannot write a truth row for a round it is not the subject of. A
-- p_is_truth parameter would move that decision to the client and turn a
-- constraint into a convention.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_session_game_answer(
  p_round_id uuid,
  p_answer text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game_type text;
  v_user_a uuid;
  v_user_b uuid;
  v_is_a boolean;
  v_answer_a text;
  v_answer_b text;
  v_option_keys text[];
  v_subject_id uuid;
  v_truth_exists boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- FOR UPDATE OF r locks the round row for the rest of this
  -- transaction. A concurrent caller blocks here and, under READ
  -- COMMITTED, re-reads the row once the lock is granted — so it sees
  -- the partner's committed answer rather than a stale NULL. Without it,
  -- two partners submitting at the same moment each read the other's
  -- slot as NULL, neither flips both_answered, and the round is stuck
  -- un-revealed forever.
  SELECT s.game_type, rel.user_a, rel.user_b, r.answer_a, r.answer_b,
         r.active_partner_id
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b,
         v_subject_id
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF r;

  IF v_game_type IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  IF v_game_type NOT IN ('mirror', 'sliding_scale', 'scenario') THEN
    RAISE EXCEPTION 'Unsupported game type';
  END IF;

  IF v_game_type = 'sliding_scale' THEN
    IF p_answer !~ '^([1-9]|10)$' THEN
      RAISE EXCEPTION 'Rating must be an integer from 1 to 10';
    END IF;
  ELSIF v_game_type = 'scenario' THEN
    SELECT array_agg(opt->>'key')
      INTO v_option_keys
    FROM public.game_session_rounds r
    JOIN public.game_questions q ON q.id = r.question_id
    CROSS JOIN LATERAL jsonb_array_elements(q.options) AS opt
    WHERE r.id = p_round_id;

    IF v_option_keys IS NULL OR NOT (p_answer = ANY(v_option_keys)) THEN
      RAISE EXCEPTION 'Answer is not one of this question''s options';
    END IF;
  ELSE
    IF p_answer IS NULL OR char_length(trim(p_answer)) = 0 THEN
      RAISE EXCEPTION 'Answer cannot be empty';
    END IF;
    IF char_length(p_answer) > 400 THEN
      RAISE EXCEPTION 'Answer is too long';
    END IF;
  END IF;

  v_is_a := (v_user_a = v_user_id);

  -- Mirror, and this caller is the round's subject: their text is the
  -- TRUTH about themselves, not a guess, so it goes to
  -- mirror_round_truth rather than an answer slot.
  IF v_game_type = 'mirror' AND v_subject_id = v_user_id THEN
    IF EXISTS (
      SELECT 1 FROM public.mirror_round_truth WHERE round_id = p_round_id
    ) THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;

    INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text)
    VALUES (p_round_id, v_user_id, p_answer);

    v_truth_exists := true;
  ELSE
    -- Everyone else — both partners in the other two games, and the
    -- guesser in Mirror — writes their own answer slot.
    IF v_is_a AND v_answer_a IS NOT NULL THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;
    IF NOT v_is_a AND v_answer_b IS NOT NULL THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;

    IF v_is_a THEN
      UPDATE public.game_session_rounds
         SET answer_a = p_answer,
             answer_a_submitted_at = now()
       WHERE id = p_round_id;
      v_answer_a := p_answer;
    ELSE
      UPDATE public.game_session_rounds
         SET answer_b = p_answer,
             answer_b_submitted_at = now()
       WHERE id = p_round_id;
      v_answer_b := p_answer;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.mirror_round_truth WHERE round_id = p_round_id
    ) INTO v_truth_exists;
  END IF;

  -- both_answered is derived here and nowhere else. For mirror the two
  -- writers are the truth row and the guesser's slot; for the other
  -- games they are the two answer slots. Either way the client has no
  -- path to this flag and cannot force an early reveal.
  IF v_game_type = 'mirror' THEN
    IF v_truth_exists AND (v_answer_a IS NOT NULL OR v_answer_b IS NOT NULL) THEN
      UPDATE public.game_session_rounds
         SET both_answered = true,
             reveal_triggered_at = COALESCE(reveal_triggered_at, now())
       WHERE id = p_round_id
         AND both_answered = false;
      RETURN true;
    END IF;
  ELSIF v_answer_a IS NOT NULL AND v_answer_b IS NOT NULL THEN
    UPDATE public.game_session_rounds
       SET both_answered = true,
           reveal_triggered_at = COALESCE(reveal_triggered_at, now())
     WHERE id = p_round_id
       AND both_answered = false;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- CREATE OR REPLACE resets privileges to the default, so the original
-- grants must be reapplied or this becomes a privilege regression.
REVOKE ALL ON FUNCTION public.submit_session_game_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_session_game_answer(uuid, text)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Judging a revealed guess
--
-- §8.4: the subject marks whether their partner read them accurately.
-- Correctness is a subjective judgement and the subject is the only
-- authority on it — no string match or AI could stand in, since
-- "she's stressed about work" and "work has been overwhelming" are the
-- same answer.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.judge_mirror_round(
  p_round_id uuid,
  p_was_correct boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_subject_id uuid;
  v_both_answered boolean;
  v_already_judged boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT t.subject_id, r.both_answered, (t.was_correct IS NOT NULL)
    INTO v_subject_id, v_both_answered, v_already_judged
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  WHERE t.round_id = p_round_id
  FOR UPDATE OF t;

  IF v_subject_id IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  -- Only the subject may judge: it is their own inner state that was
  -- being guessed at.
  IF v_subject_id <> v_user_id THEN
    RAISE EXCEPTION 'Only this round''s subject may judge it';
  END IF;

  -- Judging before the reveal would mean judging a guess you have not
  -- seen.
  IF NOT v_both_answered THEN
    RAISE EXCEPTION 'Round is not revealed yet';
  END IF;

  IF v_already_judged THEN
    RAISE EXCEPTION 'Round already judged';
  END IF;

  UPDATE public.mirror_round_truth
     SET was_correct = p_was_correct,
         judged_at = now()
   WHERE round_id = p_round_id;
END;
$$;

REVOKE ALL ON FUNCTION public.judge_mirror_round(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.judge_mirror_round(uuid, boolean)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 4. mirror_scores is derived, never incremented
--
-- Computed from SUM(was_correct) so it is re-derivable and retry-safe.
-- An incrementing counter would be neither: a double-submit or a retry
-- would silently corrupt the total, and nothing could rebuild it.
--
-- The score belongs to the GUESSER — the partner who was not the
-- subject — since it measures how well they read the other person.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalise_mirror_scores(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT rel.user_a, rel.user_b
    INTO v_user_a, v_user_b
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'mirror'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- One row per guesser. A round's guesser is whichever partner is NOT
  -- its subject, so the score counts the rounds where that person read
  -- their partner correctly.
  INSERT INTO public.mirror_scores (session_id, user_id, score, flagged)
  SELECT
    p_session_id,
    guesser.id,
    count(*) FILTER (WHERE t.was_correct)::int,
    -- §8.4: "below 6.5/8 = attentiveness flag". With the subject
    -- alternating across 8 rounds each partner guesses 4 times, so the
    -- proportional threshold is 6.5/8 of their own round count.
    (count(*) FILTER (WHERE t.was_correct)::numeric
       / NULLIF(count(*), 0)) < (6.5 / 8.0)
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  CROSS JOIN LATERAL (
    SELECT CASE WHEN t.subject_id = v_user_a THEN v_user_b
                ELSE v_user_a END AS id
  ) AS guesser
  WHERE r.session_id = p_session_id
    AND t.was_correct IS NOT NULL
  GROUP BY guesser.id
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET score = EXCLUDED.score,
        flagged = EXCLUDED.flagged;
END;
$$;

REVOKE ALL ON FUNCTION public.finalise_mirror_scores(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalise_mirror_scores(uuid)
  TO authenticated;
