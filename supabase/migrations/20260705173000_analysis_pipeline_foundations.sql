CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.analysis_sessions
  ADD COLUMN IF NOT EXISTS escalation_score double precision,
  ADD COLUMN IF NOT EXISTS escalation_trajectory text,
  ADD COLUMN IF NOT EXISTS pursue_withdraw_detected boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pursuer text,
  ADD COLUMN IF NOT EXISTS stonewalling_signals boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS repair_attempted boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS repair_landed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS session_resolved boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS one_sided_session boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS truncated boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dominant_topic text,
  ADD COLUMN IF NOT EXISTS root_need_detected text,
  ADD COLUMN IF NOT EXISTS insight_worthy boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS suggested_insight text,
  ADD COLUMN IF NOT EXISTS pattern_memory_done boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pattern_memory_attempted_at timestamptz;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'analysis_sessions_escalation_trajectory_check'
  ) THEN
    ALTER TABLE public.analysis_sessions
      ADD CONSTRAINT analysis_sessions_escalation_trajectory_check
      CHECK (
        escalation_trajectory IS NULL
        OR escalation_trajectory IN ('rising', 'falling', 'stable', 'peaked')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'analysis_sessions_pursuer_check'
  ) THEN
    ALTER TABLE public.analysis_sessions
      ADD CONSTRAINT analysis_sessions_pursuer_check
      CHECK (pursuer IS NULL OR pursuer IN ('user_a', 'user_b'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'analysis_sessions_root_need_detected_check'
  ) THEN
    ALTER TABLE public.analysis_sessions
      ADD CONSTRAINT analysis_sessions_root_need_detected_check
      CHECK (
        root_need_detected IS NULL
        OR root_need_detected IN (
          'respect',
          'fairness',
          'affection',
          'security',
          'autonomy',
          'rest'
        )
      );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.patterns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  pattern_type text NOT NULL,
  severity text NOT NULL
    CHECK (severity IN ('info', 'watch', 'act', 'safety', 'resolved')),
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  occurrence_count int NOT NULL DEFAULT 1,
  topic_cluster text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.personal_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  insight_type text NOT NULL,
  insight_body text NOT NULL,
  source_pattern_id uuid REFERENCES public.patterns(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  viewed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.translator_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  used_at timestamptz NOT NULL DEFAULT now(),
  chose_rewrite boolean,
  core_need_identified text,
  rewrite_confidence text,
  message_length_original int,
  message_length_rewrite int
);

CREATE INDEX IF NOT EXISTS idx_messages_analysis_backlog
  ON public.messages (created_at, id)
  WHERE message_analysis_done = false;

CREATE INDEX IF NOT EXISTS idx_messages_session_backlog
  ON public.messages (relationship_id, created_at, id)
  WHERE message_analysis_done = true AND included_in_session_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_analysis_sessions_relationship_id
  ON public.analysis_sessions(relationship_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_patterns_relationship_id
  ON public.patterns(relationship_id, last_seen_at DESC);

CREATE INDEX IF NOT EXISTS idx_patterns_severity
  ON public.patterns(severity);

CREATE INDEX IF NOT EXISTS idx_personal_insights_user_id
  ON public.personal_insights(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_translator_logs_user
  ON public.translator_logs(user_id, used_at DESC);

CREATE INDEX IF NOT EXISTS idx_translator_logs_relationship
  ON public.translator_logs(relationship_id, used_at DESC);

CREATE OR REPLACE FUNCTION public.bump_relationship_total_sessions(
  p_relationship_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total int;
BEGIN
  UPDATE public.relationships
  SET total_sessions = COALESCE(total_sessions, 0) + 1
  WHERE id = p_relationship_id
  RETURNING total_sessions INTO v_total;

  RETURN COALESCE(v_total, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.bump_relationship_total_sessions(uuid) FROM PUBLIC;

ALTER TABLE public.patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.personal_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.translator_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS patterns_relationship_members ON public.patterns;
CREATE POLICY patterns_relationship_members
ON public.patterns FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = patterns.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  )
);

DROP POLICY IF EXISTS personal_insights_self_only ON public.personal_insights;
CREATE POLICY personal_insights_self_only
ON public.personal_insights FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS translator_logs_private ON public.translator_logs;
CREATE POLICY translator_logs_private
ON public.translator_logs FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
