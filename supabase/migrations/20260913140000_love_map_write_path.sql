-- Love Map uses Mirror's guess-and-truth write path. Three changes to
-- submit_session_game_answer, everything else reproduced verbatim from the
-- live definition: resolve the relationship through either owner column,
-- accept love_map in the allowlist, and let the truth branch serve both
-- guess-and-truth games.
--
-- The signature does not change, and the client still never decides where
-- its answer lands -- the RPC derives that from active_partner_id.
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
  -- Love Map rounds have no session, so the relationship is reached
  -- through either owner column. COALESCE(s.game_type, 'love_map') is safe
  -- because the owner CHECK guarantees a null session_id means Love Map.
  SELECT COALESCE(s.game_type, 'love_map'),
         rel.user_a, rel.user_b, r.answer_a, r.answer_b,
         r.active_partner_id
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b,
         v_subject_id
  FROM public.game_session_rounds r
  LEFT JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel
    ON rel.id = COALESCE(s.relationship_id, r.relationship_id)
  WHERE r.id = p_round_id
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF r;

  IF v_game_type IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  IF v_game_type NOT IN ('mirror', 'sliding_scale', 'scenario', 'love_map') THEN
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
  IF v_game_type IN ('mirror', 'love_map') AND v_subject_id = v_user_id THEN
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
  IF v_game_type IN ('mirror', 'love_map') THEN
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
