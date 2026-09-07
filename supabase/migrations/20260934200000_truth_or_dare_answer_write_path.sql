-- Truth or Dare answers become server-authoritative.
--
-- THE BUG THIS FIXES. Both reveal screens wrote the round row directly
-- from the client, and each write set the PARTNER's answer column to the
-- '__revealed__' sentinel:
--
--   .update({
--      <my column>:      answer,
--      <partner column>: '__revealed__',   -- destroys their answer
--   })
--
-- Whoever answered second therefore overwrote the first person's answer
-- with a placeholder. In a game whose entire point is hearing what your
-- partner said, their answer was silently destroyed on submit. Nothing
-- stopped it: game_session_rounds grants relationship members FOR ALL,
-- so a client may write either column.
--
-- The sentinel existed to mark "this side has seen the prompt", which is
-- a different fact from "this side has answered" and never belonged in
-- the answer column. It becomes its own column.

ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS a_revealed_at timestamptz,
  ADD COLUMN IF NOT EXISTS b_revealed_at timestamptz;

-- Recover what can be recovered: a column holding the sentinel is a lost
-- answer, but the reveal fact it was standing in for is preserved.
UPDATE public.game_session_rounds
SET a_revealed_at = COALESCE(a_revealed_at, answer_a_submitted_at, created_at),
    answer_a = NULL
WHERE answer_a = '__revealed__';

UPDATE public.game_session_rounds
SET b_revealed_at = COALESCE(b_revealed_at, answer_b_submitted_at, created_at),
    answer_b = NULL
WHERE answer_b = '__revealed__';

-- One RPC owns the write. The caller says what THEY did; which column
-- that lands in is derived from auth.uid() against the relationship, so
-- a client can no longer name a column at all.
CREATE OR REPLACE FUNCTION public.submit_truth_or_dare_answer(
  p_round_id uuid,
  p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_round public.game_session_rounds%ROWTYPE;
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_is_a boolean;
  v_both boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', true, 'code', 'UNAUTHORIZED');
  END IF;

  IF p_answer IS NULL OR btrim(p_answer) = '' THEN
    RETURN jsonb_build_object('error', true, 'code', 'EMPTY_ANSWER');
  END IF;

  -- Bounded so a client cannot store an unbounded blob in a shared row.
  IF char_length(p_answer) > 2000 THEN
    RETURN jsonb_build_object('error', true, 'code', 'ANSWER_TOO_LONG');
  END IF;

  SELECT * INTO v_round FROM public.game_session_rounds
  WHERE id = p_round_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', true, 'code', 'NOT_FOUND');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = v_round.session_id AND game_type = 'truth_or_dare';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', true, 'code', 'NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN jsonb_build_object('error', true, 'code', 'FORBIDDEN');
  END IF;

  IF v_session.status <> 'active' THEN
    RETURN jsonb_build_object('error', true, 'code', 'SESSION_EXPIRED');
  END IF;

  v_is_a := v_rel.user_a = v_user;

  -- Idempotent: a retried submit returns the stored state rather than
  -- overwriting an answer the player may have already moved past.
  IF (v_is_a AND v_round.answer_a IS NOT NULL)
     OR (NOT v_is_a AND v_round.answer_b IS NOT NULL) THEN
    RETURN jsonb_build_object(
      'ok', true,
      'existing', true,
      'both_answered', v_round.both_answered
    );
  END IF;

  -- Writes ONLY the caller's own column. The partner's is untouched --
  -- which is the whole point of this function existing.
  IF v_is_a THEN
    UPDATE public.game_session_rounds
       SET answer_a = p_answer,
           answer_a_submitted_at = now(),
           a_revealed_at = COALESCE(a_revealed_at, now())
     WHERE id = p_round_id;
  ELSE
    UPDATE public.game_session_rounds
       SET answer_b = p_answer,
           answer_b_submitted_at = now(),
           b_revealed_at = COALESCE(b_revealed_at, now())
     WHERE id = p_round_id;
  END IF;

  SELECT answer_a IS NOT NULL AND answer_b IS NOT NULL
    INTO v_both
  FROM public.game_session_rounds WHERE id = p_round_id;

  IF v_both AND NOT v_round.both_answered THEN
    UPDATE public.game_session_rounds
       SET both_answered = true,
           revealed_at = COALESCE(revealed_at, now())
     WHERE id = p_round_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'existing', false,
    'both_answered', COALESCE(v_both, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_truth_or_dare_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_truth_or_dare_answer(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.submit_truth_or_dare_answer(uuid, text) IS
  'Writes only the calling partner''s answer. Replaces a client-side '
  'update that set the other partner''s column to a sentinel, destroying '
  'their answer whenever the second player submitted.';
