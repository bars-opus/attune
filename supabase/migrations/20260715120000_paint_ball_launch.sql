-- Paint Ball launch migration
-- Additive only: reuses the existing shared games schema and preserves all data.
-- Paint Ball uses game_type = 'paint_ball' inside the shared game_sessions table.

ALTER TABLE IF EXISTS public.game_sessions
  ADD COLUMN IF NOT EXISTS current_turn_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS lives_a smallint NOT NULL DEFAULT 3 CHECK (lives_a BETWEEN 0 AND 3),
  ADD COLUMN IF NOT EXISTS lives_b smallint NOT NULL DEFAULT 3 CHECK (lives_b BETWEEN 0 AND 3),
  ADD COLUMN IF NOT EXISTS winner_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS penalty_type text CHECK (penalty_type IN ('truth', 'dare')),
  ADD COLUMN IF NOT EXISTS penalty_source text CHECK (penalty_source IN ('app_random', 'partner_authored')),
  ADD COLUMN IF NOT EXISTS penalty_status text CHECK (penalty_status IN ('pending', 'completed', 'declined')),
  ADD COLUMN IF NOT EXISTS penalty_prompt_id uuid,
  ADD COLUMN IF NOT EXISTS penalty_prompt_snapshot text,
  ADD COLUMN IF NOT EXISTS penalty_allow_partner_authored boolean NOT NULL DEFAULT false;

ALTER TABLE IF EXISTS public.game_session_rounds
  ADD COLUMN IF NOT EXISTS shot_result text CHECK (shot_result IN ('hit', 'miss')),
  ADD COLUMN IF NOT EXISTS life_lost boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_paint_ball_sessions_relationship
  ON public.game_sessions(relationship_id, game_type, status)
  WHERE game_type = 'paint_ball';

CREATE INDEX IF NOT EXISTS idx_paint_ball_turn
  ON public.game_sessions(current_turn_user_id)
  WHERE game_type = 'paint_ball' AND status = 'active';

CREATE OR REPLACE FUNCTION public.get_paint_ball_session_state(
  p_session_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_session record;
  v_rounds json;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'UNAUTHORIZED', 'message', 'Please sign in to play games.');
  END IF;

  SELECT s.*, r.user_a AS user_a_id, r.user_b AS user_b_id
  INTO v_session
  FROM public.game_sessions s
  JOIN public.relationships r ON r.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'paint_ball';

  IF v_session.id IS NULL THEN
    RETURN json_build_object('error', true, 'code', 'NOT_FOUND', 'message', 'Game session not found.');
  END IF;

  IF v_user_id NOT IN (v_session.user_a_id, v_session.user_b_id) THEN
    RETURN json_build_object('error', true, 'code', 'FORBIDDEN', 'message', 'You don''t have access to this game.');
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'round_number', r.round_number,
        'shot_result', r.shot_result,
        'life_lost', r.life_lost,
        'created_at', r.created_at
      )
      ORDER BY r.round_number
    ),
    '[]'::json
  )
  INTO v_rounds
  FROM public.game_session_rounds r
  WHERE r.session_id = p_session_id;

  RETURN json_build_object(
    'session_id', v_session.id,
    'relationship_id', v_session.relationship_id,
    'initiator_id', v_session.initiator_id,
    'user_a_id', v_session.user_a_id,
    'user_b_id', v_session.user_b_id,
    'status', v_session.status,
    'game_type', v_session.game_type,
    'tone', v_session.tone,
    'current_round', v_session.current_round,
    'total_rounds_completed', v_session.total_rounds_completed,
    'current_turn_user_id', v_session.current_turn_user_id,
    'lives_a', v_session.lives_a,
    'lives_b', v_session.lives_b,
    'winner_user_id', v_session.winner_user_id,
    'penalty_type', v_session.penalty_type,
    'penalty_status', v_session.penalty_status,
    'penalty_prompt_id', v_session.penalty_prompt_id,
    'penalty_prompt_snapshot', v_session.penalty_prompt_snapshot,
    'penalty_source', v_session.penalty_source,
    'penalty_allow_partner_authored', v_session.penalty_allow_partner_authored,
    'rounds', v_rounds,
    'is_my_turn', v_session.current_turn_user_id = v_user_id,
    'is_winner', v_session.winner_user_id = v_user_id,
    'is_loser', v_session.winner_user_id IS NOT NULL AND v_session.winner_user_id <> v_user_id,
    'existing', false,
    'started_at', v_session.started_at,
    'completed_at', v_session.completed_at,
    'abandoned_at', v_session.abandoned_at,
    'created_at', v_session.created_at
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object('error', true, 'code', 'INTERNAL_ERROR', 'message', 'Something went wrong. Please try again.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_paint_ball_session_state(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_paint_ball_session_state(uuid) FROM PUBLIC, anon;

-- ---------------------------------------------------------------------------
-- Abandonment sweep.
--
-- The spec's §4.2 said Paint Ball "inherits the shared abandoned-session cron."
-- There is no such shared cron: the only expiry that exists is the
-- expire-thirty-six-chapters edge function, and it is hardcoded to
-- game_type = '36_questions' with a 7-day inactivity window measured from
-- started_at. Paint Ball needs different semantics: a 24h inactivity window
-- measured from LAST ACTIVITY (the most recent round), not from started_at —
-- otherwise a game in active back-and-forth for 25h would be wrongly abandoned
-- mid-play. So Paint Ball gets its own correct sweep here.
--
-- Schedule this with pg_cron (see the note at the end of this migration). It is
-- SECURITY DEFINER and takes no caller input, so it is safe to run on a timer.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_paint_ball_sessions()
RETURNS TABLE (expired_invites int, expired_inactive int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invites int := 0;
  v_inactive int := 0;
BEGIN
  -- Invitations with no response in 48h.
  WITH expired AS (
    UPDATE public.game_sessions
    SET status = 'abandoned',
        abandon_reason = 'invite_expired',
        abandoned_at = now()
    WHERE game_type = 'paint_ball'
      AND status = 'invited'
      AND created_at < now() - interval '48 hours'
    RETURNING 1
  )
  SELECT count(*) INTO v_invites FROM expired;

  -- Active games idle for 24h, measured from the last round (or started_at if no
  -- shot has been fired yet). Using the latest round's created_at is what makes
  -- "inactivity" mean inactivity, not "game age".
  WITH stale AS (
    UPDATE public.game_sessions s
    SET status = 'abandoned',
        abandon_reason = 'inactivity',
        abandoned_at = now()
    WHERE s.game_type = 'paint_ball'
      AND s.status = 'active'
      AND COALESCE(
            (SELECT max(r.created_at)
             FROM public.game_session_rounds r
             WHERE r.session_id = s.id),
            s.started_at
          ) < now() - interval '24 hours'
    RETURNING 1
  )
  SELECT count(*) INTO v_inactive FROM stale;

  RETURN QUERY SELECT v_invites, v_inactive;
END;
$$;

-- Least privilege: this is an operational sweep, not a user action.
REVOKE ALL ON FUNCTION public.expire_paint_ball_sessions() FROM PUBLIC, anon, authenticated;
-- (Grant EXECUTE to the role your pg_cron / scheduler runs as, e.g. postgres or a
--  dedicated cron role. Left ungranted here so it is never callable by clients.)

-- SCHEDULING (run once, outside this migration, by an operator with pg_cron):
--   SELECT cron.schedule('expire_paint_ball', '*/30 * * * *',
--     $$SELECT public.expire_paint_ball_sessions();$$);
-- A 30-minute cadence is ample for 24h/48h windows.
