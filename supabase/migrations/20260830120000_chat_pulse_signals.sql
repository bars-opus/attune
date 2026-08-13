-- Chat analysis → Pulse integration (docs/superpowers/specs/
-- 2026-08-14-chat-pulse-integration-design.md):
--
-- 1. Registers the analyse-session sweep cron. supabase/sql/
--    schedule_analyse_session.sql defines this same job but is an
--    operator-run script, not a migration — its execution against the
--    live project could never be confirmed, so this migration makes the
--    registration a first-class, deployed artifact instead.
-- 2. Adds a Postgres RPC that pre-aggregates 30 days of chat signal per
--    relationship in one row, so compute-pulse never has to select(*)
--    raw message/session rows into the edge function (Algorithm Quality
--    Review Checklist v3.1 item 2.14 — memory growth bounds).
-- 3. Adds a service-role-only diagnostics table for raw chat aggregates
--    — deliberately NOT covered by pulse_scores' existing RLS SELECT
--    policy (which grants the whole row to both partners), since raw
--    violation rates/escalation scores must never reach a client (item
--    1.11 — data privacy; see spec's Privacy section).

-- ---------------------------------------------------------------------
-- 1. Cron registration
-- ---------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'analyse-session-sweep';

SELECT cron.schedule(
  'analyse-session-sweep',
  '7,37 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/analyse-session',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ---------------------------------------------------------------------
-- 2. Chat signal aggregation RPC
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compute_relationship_chat_signals(
  p_relationship_id uuid,
  p_window_start timestamptz
)
RETURNS TABLE (
  analysed_count int,
  avg_tone double precision,
  violation_rate double precision,
  severe_rate double precision,
  bid_turn_rate double precision,
  bids_total int,
  session_count int,
  avg_escalation double precision,
  repair_rate double precision,
  attempt_rate double precision,
  stonewall_rate double precision,
  pursue_withdraw_rate double precision,
  first_analysed_at timestamptz,
  pending_backlog_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH msgs AS (
    SELECT
      m.tone_score,
      m.nvc_violations,
      m.bid_type,
      m.created_at
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.message_analysis_done = true
      AND m.created_at >= p_window_start
  ),
  violation_counts AS (
    SELECT
      count(*) AS msg_count,
      count(*) FILTER (WHERE tone_score IS NOT NULL) AS toned_count,
      COALESCE(avg(tone_score) FILTER (WHERE tone_score IS NOT NULL), NULL) AS avg_tone_val,
      COALESCE(sum(
        CASE WHEN jsonb_typeof(nvc_violations) = 'array'
          THEN jsonb_array_length(nvc_violations)
          ELSE 0
        END
      ), 0) AS total_violations,
      COALESCE(sum(
        CASE WHEN jsonb_typeof(nvc_violations) = 'array'
          THEN (
            SELECT count(*)
            FROM jsonb_array_elements_text(nvc_violations) AS v(val)
            WHERE v.val IN ('contempt', 'character_attack')
          )
          ELSE 0
        END
      ), 0) AS total_severe,
      count(*) FILTER (WHERE bid_type IS NOT NULL) AS bids_total_val,
      count(*) FILTER (WHERE bid_type = 'toward') AS bids_toward_val,
      min(created_at) FILTER (WHERE tone_score IS NOT NULL) AS first_toned_at
    FROM msgs
  ),
  sessions AS (
    SELECT
      s.escalation_score,
      s.repair_attempted,
      s.repair_landed,
      s.stonewalling_signals,
      s.pursue_withdraw_detected
    FROM public.analysis_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.started_at >= p_window_start
      AND s.escalation_score IS NOT NULL
  ),
  session_counts AS (
    SELECT
      count(*) AS session_count_val,
      COALESCE(avg(escalation_score), NULL) AS avg_escalation_val,
      count(*) FILTER (WHERE escalation_score >= 0.5) AS conflict_session_count,
      count(*) FILTER (WHERE escalation_score >= 0.5 AND repair_landed) AS landed_count,
      count(*) FILTER (WHERE escalation_score >= 0.5 AND repair_attempted) AS attempted_count,
      count(*) FILTER (WHERE stonewalling_signals) AS stonewall_count,
      count(*) FILTER (WHERE pursue_withdraw_detected) AS pursue_withdraw_count
    FROM sessions
  ),
  backlog AS (
    SELECT count(*) AS pending_count
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.message_analysis_done = true
      AND m.included_in_session_id IS NULL
  )
  SELECT
    vc.msg_count::int,
    vc.avg_tone_val,
    CASE WHEN vc.msg_count > 0 THEN vc.total_violations::double precision / vc.msg_count ELSE NULL END,
    CASE WHEN vc.msg_count > 0 THEN vc.total_severe::double precision / vc.msg_count ELSE NULL END,
    CASE WHEN vc.bids_total_val >= 5 THEN vc.bids_toward_val::double precision / vc.bids_total_val ELSE NULL END,
    vc.bids_total_val::int,
    sc.session_count_val::int,
    sc.avg_escalation_val,
    CASE WHEN sc.conflict_session_count >= 2 THEN sc.landed_count::double precision / sc.conflict_session_count ELSE NULL END,
    CASE WHEN sc.conflict_session_count >= 2 THEN sc.attempted_count::double precision / sc.conflict_session_count ELSE NULL END,
    CASE WHEN sc.session_count_val > 0 THEN sc.stonewall_count::double precision / sc.session_count_val ELSE NULL END,
    CASE WHEN sc.session_count_val > 0 THEN sc.pursue_withdraw_count::double precision / sc.session_count_val ELSE NULL END,
    vc.first_toned_at,
    b.pending_count::int
  FROM violation_counts vc, session_counts sc, backlog b;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_relationship_chat_signals(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_relationship_chat_signals(uuid, timestamptz) TO service_role;

-- ---------------------------------------------------------------------
-- 3. Diagnostics table (service-role only — never exposed to clients)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pulse_score_diagnostics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  chat_weight double precision,
  raw_signals jsonb,
  UNIQUE (relationship_id, week_ending)
);

ALTER TABLE public.pulse_score_diagnostics ENABLE ROW LEVEL SECURITY;
-- Deliberately no policy for `authenticated` — RLS enabled with zero
-- policies means the table is inaccessible to that role entirely.
-- Only the service-role key (which bypasses RLS) can read/write it.

REVOKE ALL ON public.pulse_score_diagnostics FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_pulse_score_diagnostics_relationship
  ON public.pulse_score_diagnostics (relationship_id, week_ending DESC);
