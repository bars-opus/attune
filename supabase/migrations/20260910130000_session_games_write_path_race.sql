-- Closes a TOCTOU race in submit_session_game_answer's both_answered
-- derivation (20260910120000).
--
-- The original SELECT took no row lock. Under READ COMMITTED, when both
-- partners submit at nearly the same time:
--   - Transaction A reads answer_a NULL, answer_b NULL. Writes answer_a.
--   - Transaction B reads (before A commits) answer_a NULL, answer_b NULL.
--     Writes answer_b.
--   - A checks both_answered with its stale v_answer_b = NULL -> no flip.
--   - B checks both_answered with its stale v_answer_a = NULL -> no flip.
--   Both answers end up stored, but both_answered is never set. Nothing
--   else in the schema repairs the flag — get_revealed_round and the
--   pulse-signal aggregate both trust it strictly — so the round is stuck
--   un-revealed forever. Two people tapping submit at nearly the same
--   moment is the ORDINARY case for a two-player game, not an edge case.
--
-- The fix: lock the round row for the whole transaction via
-- `FOR UPDATE OF r` on the initial SELECT. A concurrent caller then
-- blocks at that SELECT until the first transaction commits, and reads
-- the partner's committed answer rather than a stale NULL. FOR UPDATE OF r
-- scopes the lock to game_session_rounds only — game_sessions and
-- relationships stay unlocked, since only the round row is ever written
-- here and FOR UPDATE cannot be applied to the nullable side of an outer
-- join anyway (none of these joins are outer, but scoping keeps the lock
-- minimal and explicit). Do not remove this lock: without it, concurrent
-- submissions can leave both_answered false with no recovery path.

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
  --
  -- FOR UPDATE OF r locks the round row for the rest of this transaction,
  -- so a concurrent submission for the same round blocks here until this
  -- transaction commits, and then reads the committed answer_a/answer_b
  -- rather than a stale pre-commit NULL. See the migration header for why
  -- this lock exists.
  SELECT s.game_type, rel.user_a, rel.user_b, r.answer_a, r.answer_b
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b
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
  -- path to set it, so it cannot force an early reveal. The partner's
  -- value used here was read under the row lock above, so it reflects
  -- the partner's committed submission rather than a stale NULL.
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
