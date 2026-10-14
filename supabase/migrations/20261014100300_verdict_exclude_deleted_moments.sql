-- Soft-deleted moments must not make a couple verdict-eligible or count
-- as strength/concern evidence (Together spec §8.1 #10). Verbatim copy of
-- request_verdict_generation from 20260703183000 with two filters added.

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
      AND te.deleted_at IS NULL
      AND te.visibility = 'shared'
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
      AND te.deleted_at IS NULL
      AND te.visibility = 'shared'
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

REVOKE ALL ON FUNCTION public.request_verdict_generation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_verdict_generation(uuid) TO authenticated;
