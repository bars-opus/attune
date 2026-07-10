-- Verdict System v1.1
-- Relationship-owned monthly verdicts with per-user delivery state.

CREATE TABLE IF NOT EXISTS public.verdicts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  snapshot_at timestamptz NOT NULL,
  generated_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'published'
    CHECK (status IN ('published', 'withdrawn')),
  data_confidence text NOT NULL
    CHECK (data_confidence IN ('low', 'medium', 'high')),
  confidence_label text NOT NULL,
  headline text NOT NULL,
  strengths jsonb NOT NULL,
  watch_areas jsonb NOT NULL,
  one_action text NOT NULL,
  one_action_evidence_ids text[] NOT NULL DEFAULT '{}',
  patterns_referenced uuid[] NOT NULL DEFAULT '{}',
  disclaimer text NOT NULL,
  input_schema_version text NOT NULL,
  prompt_version text NOT NULL,
  model_provider text NOT NULL,
  model_name text NOT NULL,
  source_updated_at_max timestamptz,
  CHECK (period_end > period_start),
  UNIQUE (relationship_id, period_start)
);

CREATE TABLE IF NOT EXISTS public.verdict_evidence (
  verdict_id uuid NOT NULL REFERENCES public.verdicts(id) ON DELETE CASCADE,
  evidence_id text NOT NULL,
  source_type text NOT NULL,
  source_record_id uuid,
  observed_at timestamptz,
  sample_size integer,
  framework_confidence text NOT NULL
    CHECK (framework_confidence IN ('high', 'medium', 'lower')),
  display_source text NOT NULL,
  PRIMARY KEY (verdict_id, evidence_id)
);

CREATE TABLE IF NOT EXISTS public.verdict_deliveries (
  verdict_id uuid NOT NULL REFERENCES public.verdicts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  viewed_at timestamptz,
  dismissed_at timestamptz,
  notification_status text NOT NULL DEFAULT 'pending'
    CHECK (notification_status IN ('pending', 'suppressed', 'sent', 'failed')),
  notification_sent_at timestamptz,
  PRIMARY KEY (verdict_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.verdict_generation_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end date NOT NULL,
  requested_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  attempt_count integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (relationship_id, period_start)
);

CREATE TABLE IF NOT EXISTS public.verdict_notification_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  verdict_id uuid NOT NULL REFERENCES public.verdicts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type text NOT NULL DEFAULT 'verdict_ready'
    CHECK (event_type IN ('verdict_ready')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sent', 'failed', 'suppressed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  last_error text,
  UNIQUE (verdict_id, user_id, event_type)
);

CREATE INDEX IF NOT EXISTS verdicts_relationship_period_idx
  ON public.verdicts (relationship_id, period_start DESC);
CREATE INDEX IF NOT EXISTS verdict_deliveries_user_unread_idx
  ON public.verdict_deliveries (user_id, viewed_at, verdict_id);
CREATE INDEX IF NOT EXISTS verdict_evidence_source_idx
  ON public.verdict_evidence (source_type, source_record_id);
CREATE INDEX IF NOT EXISTS verdict_jobs_status_idx
  ON public.verdict_generation_jobs (status, created_at);

DROP TRIGGER IF EXISTS set_verdict_generation_jobs_updated_at
  ON public.verdict_generation_jobs;
CREATE TRIGGER set_verdict_generation_jobs_updated_at
BEFORE UPDATE ON public.verdict_generation_jobs
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.verdicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verdict_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verdict_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verdict_generation_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.verdict_notification_outbox ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.verdicts FROM anon;
REVOKE ALL ON public.verdict_evidence FROM anon;
REVOKE ALL ON public.verdict_deliveries FROM anon;
REVOKE ALL ON public.verdict_generation_jobs FROM anon, authenticated;
REVOKE ALL ON public.verdict_notification_outbox FROM anon, authenticated;

DROP POLICY IF EXISTS "verdicts_relationship_members" ON public.verdicts;
CREATE POLICY "verdicts_relationship_members"
ON public.verdicts FOR SELECT
USING (
  status = 'published'
  AND EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = verdicts.relationship_id
      AND r.status = 'active'
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  )
);

DROP POLICY IF EXISTS "verdict_evidence_relationship_members" ON public.verdict_evidence;
CREATE POLICY "verdict_evidence_relationship_members"
ON public.verdict_evidence FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.verdicts v
    JOIN public.relationships r ON r.id = v.relationship_id
    WHERE v.id = verdict_evidence.verdict_id
      AND v.status = 'published'
      AND r.status = 'active'
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  )
);

DROP POLICY IF EXISTS "verdict_deliveries_self_read" ON public.verdict_deliveries;
CREATE POLICY "verdict_deliveries_self_read"
ON public.verdict_deliveries FOR SELECT
USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public._verdict_period_start_utc(p_now timestamptz)
RETURNS date
LANGUAGE sql
STABLE
AS $$
  SELECT (date_trunc('month', timezone('UTC', p_now)) - interval '1 month')::date
$$;

CREATE OR REPLACE FUNCTION public._verdict_period_end_utc(p_now timestamptz)
RETURNS date
LANGUAGE sql
STABLE
AS $$
  SELECT date_trunc('month', timezone('UTC', p_now))::date
$$;

CREATE OR REPLACE FUNCTION public._verdict_relationship_membership(
  p_relationship_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active'
      AND (r.user_a = p_user_id OR r.user_b = p_user_id)
  )
$$;

CREATE OR REPLACE FUNCTION public.mark_verdict_viewed(p_verdict_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  UPDATE public.verdict_deliveries vd
  SET viewed_at = COALESCE(vd.viewed_at, now())
  WHERE vd.verdict_id = p_verdict_id
    AND vd.user_id = v_user_id
    AND EXISTS (
      SELECT 1
      FROM public.verdicts v
      JOIN public.relationships r ON r.id = v.relationship_id
      WHERE v.id = vd.verdict_id
        AND r.status = 'active'
        AND (r.user_a = v_user_id OR r.user_b = v_user_id)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_verdict_dismissed(p_verdict_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  UPDATE public.verdict_deliveries vd
  SET dismissed_at = COALESCE(vd.dismissed_at, now())
  WHERE vd.verdict_id = p_verdict_id
    AND vd.user_id = v_user_id
    AND EXISTS (
      SELECT 1
      FROM public.verdicts v
      JOIN public.relationships r ON r.id = v.relationship_id
      WHERE v.id = vd.verdict_id
        AND r.status = 'active'
        AND (r.user_a = v_user_id OR r.user_b = v_user_id)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_verdict_generation(
  p_relationship_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_relationship public.relationships%ROWTYPE;
  v_period_start date := public._verdict_period_start_utc(now());
  v_period_end date := public._verdict_period_end_utc(now());
  v_existing_verdict uuid;
  v_existing_job public.verdict_generation_jobs%ROWTYPE;
  v_pulse_count integer;
  v_session_count integer;
  v_has_strength boolean;
  v_has_watch boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_relationship
  FROM public.relationships
  WHERE id = p_relationship_id
    AND status = 'active'
    AND (user_a = v_user_id OR user_b = v_user_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'relationship_not_found' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_existing_verdict
  FROM public.verdicts
  WHERE relationship_id = p_relationship_id
    AND period_start = v_period_start
  LIMIT 1;

  IF v_existing_verdict IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'existing',
      'verdict_id', v_existing_verdict
    );
  END IF;

  SELECT * INTO v_existing_job
  FROM public.verdict_generation_jobs
  WHERE relationship_id = p_relationship_id
    AND period_start = v_period_start;

  IF FOUND AND v_existing_job.status IN ('pending', 'processing') THEN
    RETURN jsonb_build_object(
      'status', 'processing',
      'job_id', v_existing_job.id
    );
  END IF;

  SELECT count(*)::int INTO v_pulse_count
  FROM public.pulse_scores
  WHERE relationship_id = p_relationship_id;

  SELECT count(*)::int INTO v_session_count
  FROM public.analysis_sessions
  WHERE relationship_id = p_relationship_id
    AND coalesce(one_sided_session, false) = false
    AND coalesce(truncated, false) = false;

  SELECT EXISTS (
    SELECT 1
    FROM public.pulse_scores ps
    WHERE ps.relationship_id = p_relationship_id
      AND (
        ps.connection >= 65
        OR ps.communication >= 65
        OR ps.overall_score >= 70
      )
  )
  OR EXISTS (
    SELECT 1
    FROM public.timeline_events te
    WHERE te.relationship_id = p_relationship_id
      AND te.occurred_at >= v_period_start
      AND te.occurred_at < v_period_end
      AND te.event_type IN ('milestone', 'highlight', 'anniversary')
  )
  INTO v_has_strength;

  SELECT EXISTS (
    SELECT 1
    FROM public.patterns p
    WHERE p.relationship_id = p_relationship_id
      AND p.severity IN ('watch', 'act')
  )
  OR EXISTS (
    SELECT 1
    FROM public.timeline_events te
    WHERE te.relationship_id = p_relationship_id
      AND te.occurred_at >= v_period_start
      AND te.occurred_at < v_period_end
      AND te.event_type = 'conflict'
  )
  OR EXISTS (
    SELECT 1
    FROM public.pulse_scores ps
    WHERE ps.relationship_id = p_relationship_id
      AND (
        coalesce((ps.delta_vs_previous->>'connection')::int, 0) <= -5
        OR coalesce((ps.delta_vs_previous->>'communication')::int, 0) <= -5
      )
  )
  INTO v_has_watch;

  IF v_pulse_count < 3 THEN
    RETURN jsonb_build_object(
      'status', 'ineligible',
      'reason', 'not_enough_pulse_data',
      'message', 'Not enough shared data yet. Keep using Attune at your own pace.'
    );
  END IF;

  IF v_session_count < 5 THEN
    RETURN jsonb_build_object(
      'status', 'ineligible',
      'reason', 'not_enough_sessions',
      'message', 'Not enough shared data yet. Keep using Attune at your own pace.'
    );
  END IF;

  IF NOT v_has_strength OR NOT v_has_watch THEN
    RETURN jsonb_build_object(
      'status', 'ineligible',
      'reason', 'insufficient_evidence',
      'message', 'Not enough shared data yet. Keep using Attune at your own pace.'
    );
  END IF;

  INSERT INTO public.verdict_generation_jobs (
    relationship_id,
    period_start,
    period_end,
    requested_by,
    status,
    attempt_count,
    last_error
  ) VALUES (
    p_relationship_id,
    v_period_start,
    v_period_end,
    v_user_id,
    'pending',
    0,
    NULL
  )
  ON CONFLICT (relationship_id, period_start) DO UPDATE
    SET status = CASE
          WHEN public.verdict_generation_jobs.status = 'completed'
            THEN public.verdict_generation_jobs.status
          ELSE 'pending'
        END,
        requested_by = EXCLUDED.requested_by,
        last_error = NULL
  RETURNING * INTO v_existing_job;

  RETURN jsonb_build_object(
    'status', 'queued',
    'job_id', v_existing_job.id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.mark_verdict_viewed(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_verdict_dismissed(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_verdict_generation(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.mark_verdict_viewed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_verdict_dismissed(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_verdict_generation(uuid) TO authenticated;
