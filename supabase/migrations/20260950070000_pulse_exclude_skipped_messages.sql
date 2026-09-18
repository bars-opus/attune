-- Excludes deliberately-skipped messages (message_analysis_skipped = true
-- -- AI Assistant Assist-mode output shared into chat, once Task 6's
-- share RPC sets the flag) from Pulse's chat-signal aggregation.
--
-- 20260830120000_chat_pulse_signals.sql is already shipped and must never
-- be edited in place. Its two `m.message_analysis_done = true` filters
-- live inside public.compute_relationship_chat_signals, a
-- CREATE OR REPLACE FUNCTION -- so this migration replaces that same
-- function definition wholesale (the "new migration supersedes old
-- function" convention already used elsewhere in this codebase, e.g.
-- the Stories finalize-race-fix and archival-dead-letter-fix migrations),
-- with `AND m.message_analysis_skipped = false` added to both the `msgs`
-- CTE (drives avg_tone/violation_rate/severe_rate/bid rates) and the
-- `backlog` CTE (drives pending_backlog_count). Everything else in the
-- function body is unchanged from the shipped version.
--
-- Spec docs/superpowers/specs/2026-09-15-ai-assistant-design.md §8.2.

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
  conflict_session_count int,
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
      AND m.message_analysis_skipped = false
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
      -- Deliberate reading of an ambiguous spec formula (not an oversight):
      -- the spec gates coverage on toned messages existing but describes
      -- measuring from the first of all messages. First *toned* message is
      -- the coherent reading — coverage measures analysed history.
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
      AND m.message_analysis_skipped = false
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
    -- Conflict Health's repair-bonus source is gated on the count of
    -- high-escalation sessions (a smaller population than session_count),
    -- so the edge function needs this figure, not just the rates.
    sc.conflict_session_count::int,
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
