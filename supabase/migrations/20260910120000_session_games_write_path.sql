-- Server-side write path for the three session games.
--
-- Closes two holes the data-layer plan deferred here. Both stem from
-- game_session_rounds' policy being FOR ALL for relationship members
-- (20260625120000), which grants a member full write access to their own
-- couple's rounds:
--
--   1. Nothing constrains a sliding_scale rating to 1-10. A member can
--      UPDATE answer_a = '999' via plain PostgREST today. The read-side
--      guard added in 20260909150000 filters such a row out of the
--      aggregate, but the row still exists and still renders in the UI.
--
--   2. A member can set both_answered = true on their own round and then
--      legitimately call get_revealed_round, which honours the flag. The
--      read gate holds; the write side does not. §8.4 calls the reveal
--      mechanic non-negotiable, so a client must not own that flag.
--
-- The fix is to take answer writes away from the client entirely for
-- these three games: this RPC validates the answer for its game type,
-- writes it to the correct slot, and flips both_answered ONLY when both
-- slots are genuinely populated. The client never writes both_answered.

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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Membership and game type in one lookup. A caller who is not a member
  -- of this round's relationship finds nothing and is rejected — the
  -- function never reveals whether the round exists.
  SELECT s.game_type, rel.user_a, rel.user_b, r.answer_a, r.answer_b
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_game_type IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  IF v_game_type NOT IN ('mirror', 'sliding_scale', 'scenario') THEN
    RAISE EXCEPTION 'Unsupported game type';
  END IF;

  -- Per-type answer validation. This is the write-time constraint the
  -- read-side regex could not provide.
  IF v_game_type = 'sliding_scale' THEN
    IF p_answer !~ '^([1-9]|10)$' THEN
      RAISE EXCEPTION 'Rating must be an integer from 1 to 10';
    END IF;
  ELSIF v_game_type = 'scenario' THEN
    -- The answer must be one of the option keys this question actually
    -- offers, so a client cannot invent a choice that no UI presented.
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
    -- mirror: free text, bounded to match mirror_round_truth's own limit.
    IF p_answer IS NULL OR char_length(trim(p_answer)) = 0 THEN
      RAISE EXCEPTION 'Answer cannot be empty';
    END IF;
    IF char_length(p_answer) > 400 THEN
      RAISE EXCEPTION 'Answer is too long';
    END IF;
  END IF;

  v_is_a := (v_user_a = v_user_id);

  -- First write wins: a resubmission must not overwrite an answer the
  -- partner may already have seen at reveal.
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

  -- both_answered is derived here and nowhere else. The client has no
  -- path to set it, so it cannot force an early reveal.
  IF v_answer_a IS NOT NULL AND v_answer_b IS NOT NULL THEN
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

REVOKE ALL ON FUNCTION public.submit_session_game_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_session_game_answer(uuid, text)
  TO authenticated;
