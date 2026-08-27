-- Restore service_role write access to the pulse/timeline tables.
--
-- 20260717120000_pulse_timeline_launch.sql revoked these tables from
-- PUBLIC and then granted only `authenticated`:
--
--   REVOKE ALL ON public.pulse_scores FROM PUBLIC, anon;
--   GRANT SELECT ON public.pulse_scores TO authenticated;
--
-- service_role has no grants of its own on these tables; it was reaching
-- them through PUBLIC. Revoking PUBLIC therefore removed the SERVER's
-- write access, not just the clients'. service_role bypasses RLS, but RLS
-- and table privileges are different mechanisms — bypassing the former
-- does nothing about the latter.
--
-- The visible consequence: compute-pulse fails at its upsert with
-- "permission denied for table pulse_scores", so a pulse score has never
-- been successfully written. This went unnoticed because nothing ran
-- compute-pulse on a schedule until 20260907120000 registered its weekly
-- cron — before that it only ran when a client asked, and its
-- already-computed short-circuit returns before the upsert, so the common
-- path looked like a success.
--
-- Grants are per-table and minimal rather than a blanket
-- `GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role`: the latter
-- would silently re-grant every table this project has deliberately
-- locked down, including the ones whose whole purpose is to be
-- unreachable.

-- Written by compute-pulse's upsert.
GRANT SELECT, INSERT, UPDATE ON public.pulse_scores TO service_role;

-- Written by compute-pulse's diagnostics upsert (best-effort, but it logs
-- a permission error on every run without this).
GRANT SELECT, INSERT, UPDATE ON public.pulse_score_diagnostics TO service_role;

-- Read by compute-pulse when scoring dimensions; also written by the
-- reminder/notification workers.
GRANT SELECT, INSERT, UPDATE ON public.timeline_events TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.weekly_checkins TO service_role;

-- Read by the notification workers to honour per-user delivery
-- preferences.
GRANT SELECT, INSERT, UPDATE ON public.user_preferences TO service_role;

-- DELETE is deliberately withheld from all five: nothing in the server
-- pipeline deletes these rows (compute-pulse upserts, the workers insert
-- and update), and account deletion reaches them through ON DELETE
-- CASCADE from users/relationships rather than through a direct DELETE.
