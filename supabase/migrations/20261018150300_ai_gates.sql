-- Spec 8 (research 06 F15 (1), row 8; plan review I13, I14, I15, §6.4):
-- the gates the AI jobs need before they may resume.
--   * chat_hostility_signals_enabled (off): stonewalling and contempt stay
--     out of Pulse and the Verdict until clinical sign-off;
--   * request_verdict_generation answers a suppressed couple exactly as it
--     answers one with too little data, and queues nothing;
--   * ai_provider_calls: one content-free row per provider call (which job,
--     which prompt, whose relationship, tokens), service-role only, kept 90
--     days; ai_cost_per_relationship sums it per couple per day.
-- Grants in 20261018150310.
INSERT INTO public.feature_flags (key, enabled) VALUES ('chat_hostility_signals_enabled', false)
ON CONFLICT (key) DO NOTHING;

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

  -- Spec 8 (F15 (1); plan review I13): where the safety system has fired
  -- or either member's private check is positive, no new Verdict, with
  -- exactly the answer a couple with too little data gets. After the
  -- queued-job check, so a job queued earlier keeps reading as processing
  -- until the worker cancels it (final review m-11).
  IF public.relationship_ai_suppressed(p_relationship_id) THEN
    RETURN jsonb_build_object(
      'status', 'ineligible',
      'reason', 'insufficient_evidence',
      'message', 'Not enough shared data yet. Keep using Attune at your own pace.'
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

CREATE TABLE IF NOT EXISTS public.ai_provider_calls (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now(),
  fn text NOT NULL CHECK (char_length(fn) BETWEEN 1 AND 64),
  prompt_id text NOT NULL CHECK (char_length(prompt_id) BETWEEN 1 AND 64),
  relationship_id uuid REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  model text CHECK (model IS NULL OR char_length(model) <= 64),
  prompt_tokens integer NOT NULL DEFAULT 0 CHECK (prompt_tokens >= 0),
  output_tokens integer NOT NULL DEFAULT 0 CHECK (output_tokens >= 0)
);
ALTER TABLE public.ai_provider_calls ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS ai_provider_calls_created_idx ON public.ai_provider_calls (created_at);
CREATE INDEX IF NOT EXISTS ai_provider_calls_relationship_idx
  ON public.ai_provider_calls (relationship_id, created_at);

CREATE OR REPLACE VIEW public.ai_cost_per_relationship
WITH (security_invoker = true) AS
SELECT relationship_id,
       (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)::int AS calls,
       sum(prompt_tokens)::bigint AS prompt_tokens,
       sum(output_tokens)::bigint AS output_tokens
FROM public.ai_provider_calls
GROUP BY relationship_id, (created_at AT TIME ZONE 'UTC')::date;

CREATE OR REPLACE FUNCTION public.purge_old_ai_provider_calls()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  DELETE FROM public.ai_provider_calls WHERE created_at < now() - interval '90 days';
$$;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge-ai-provider-calls';
END;
$$;
SELECT cron.schedule(
  'purge-ai-provider-calls',
  '17 3 * * *',
  $$ SELECT public.purge_old_ai_provider_calls(); $$
);
