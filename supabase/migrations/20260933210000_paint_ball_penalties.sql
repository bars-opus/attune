-- Paint Ball v3: a double knockout is a draw, and a draw has TWO penalties.
--
-- Both players can hit each other in the same round and both reach zero
-- lives. Spec §10.3 makes that a draw rather than awarding the round to
-- whoever opened it: turn order is an arbitrary tiebreak, and in a couples
-- app a mutual forfeit is a shared moment where a technical win is a sour
-- one. winner_user_id stays NULL.
--
-- game_sessions carries a single set of penalty columns, which cannot hold
-- two. Penalties move to a child table keyed per player.

CREATE TABLE IF NOT EXISTS public.paint_ball_penalties (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL
    REFERENCES public.users(id) ON DELETE CASCADE,
  penalty_type text NOT NULL CHECK (penalty_type IN ('truth', 'dare')),
  penalty_source text NOT NULL
    CHECK (penalty_source IN ('app_random', 'partner_authored')),
  penalty_status text NOT NULL DEFAULT 'pending'
    CHECK (penalty_status IN ('pending', 'completed', 'declined')),
  penalty_prompt_id uuid,
  -- Denormalized so history survives deletion of a custom prompt, the same
  -- pattern 36 Questions uses with question_text_snapshot.
  penalty_prompt_snapshot text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.paint_ball_penalties ENABLE ROW LEVEL SECURITY;

-- Both partners may read both penalties: the game is played together and
-- the end screen shows what each drew. Writes go only through the RPCs.
DROP POLICY IF EXISTS paint_ball_penalties_read_members ON public.paint_ball_penalties;
CREATE POLICY paint_ball_penalties_read_members
ON public.paint_ball_penalties FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.game_sessions gs
    JOIN public.relationships r ON r.id = gs.relationship_id
    WHERE gs.id = paint_ball_penalties.session_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  )
);

REVOKE ALL ON public.paint_ball_penalties FROM anon, authenticated;
GRANT SELECT ON public.paint_ball_penalties TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.paint_ball_penalties TO service_role;

CREATE INDEX IF NOT EXISTS idx_paint_ball_penalties_pending
  ON public.paint_ball_penalties(session_id)
  WHERE penalty_status = 'pending';

-- Backfill from the legacy single-penalty columns so sessions created
-- before v3 keep rendering on the end screen.
INSERT INTO public.paint_ball_penalties (
  session_id, user_id, penalty_type, penalty_source, penalty_status,
  penalty_prompt_id, penalty_prompt_snapshot, created_at
)
SELECT
  gs.id,
  -- The loser is whoever did not win.
  CASE WHEN gs.winner_user_id = r.user_a THEN r.user_b ELSE r.user_a END,
  gs.penalty_type,
  COALESCE(gs.penalty_source, 'app_random'),
  gs.penalty_status,
  gs.penalty_prompt_id,
  COALESCE(gs.penalty_prompt_snapshot, '(prompt no longer available)'),
  COALESCE(gs.completed_at, gs.created_at, now())
FROM public.game_sessions gs
JOIN public.relationships r ON r.id = gs.relationship_id
WHERE gs.game_type = 'paint_ball'
  AND gs.penalty_type IS NOT NULL
  AND gs.penalty_status IS NOT NULL
  AND gs.winner_user_id IS NOT NULL
ON CONFLICT (session_id, user_id) DO NOTHING;

COMMENT ON TABLE public.paint_ball_penalties IS
  'One row per player who must answer a prompt. A normal knockout writes '
  'one; a draw (both players reaching zero in the same round) writes two, '
  'and leaves game_sessions.winner_user_id NULL.';
