-- AI Sessions: enable the §12 capability flags in PRODUCTION.
--
-- RUN THIS YOURSELF. It is a service_role write against the live database —
-- `authenticated` has no UPDATE on public.feature_flags, by design (see
-- 20260712150000_dating_flag_defense_in_depth.sql for why the table is
-- locked down). Nothing in the app or the test suite can perform this.
--
-- PREREQUISITES, in order:
--   1. The two flag-gate findings are fixed and on main. Without them:
--      - a lost response after `prepare` locks the user out of the session
--        they just created until its deadline expires (and on a SHARED
--        session the slot limit is per-relationship, so it blocks the
--        partner too);
--      - the sheet can send a visibility whose capability is off, so a
--        partial rollout gives every user a Start button that always errors.
--   2. Migration 20260953200500 (get_ai_session_capabilities) is deployed.
--      The client fails closed to all-off if it is absent, so a client-first
--      deploy degrades to "feature off" rather than an error.
--
-- ROLLBACK is the same statement with `false`. The client reads these through
-- get_ai_session_capabilities() on each app session, so turning them off
-- takes effect on the next read — this is a live kill switch, not a release.

BEGIN;

-- Flip all six together.
UPDATE public.feature_flags
   SET enabled = true, updated_at = now()
 WHERE key IN (
         'ai_assist_enabled',               -- base Ask Attune gate (§14.1)
         'ai_understand_enabled',           -- base Understand gate
         'ai_sessions_private_enabled',     -- a session only the requester sees
         'ai_sessions_shared_enabled',      -- a session both partners approve
         'ai_sessions_recent_window_enabled', -- the §4.2 recent-chat window
         'ai_sessions_nearby_enabled'       -- the Nearby/Mapbox path
       );

-- Expect 6. Anything less means a key is missing: STOP and check
-- 20260953200000 applied, rather than inserting rows by hand.
SELECT count(*) AS flags_enabled
  FROM public.feature_flags
 WHERE key LIKE 'ai\_%' AND enabled;

COMMIT;


-- OR, to roll out in stages. Private before shared: the sheet defaults to
-- private, and enabling shared first is the order that produced the
-- always-erroring Start button.
--
--   UPDATE public.feature_flags SET enabled = true, updated_at = now()
--    WHERE key IN ('ai_assist_enabled', 'ai_sessions_private_enabled');
--
-- Then verify as a client before widening:
--
--   SET LOCAL ROLE authenticated;
--   SELECT set_config('request.jwt.claims',
--                     json_build_object('sub', '<a real user uuid>')::text, true);
--   SELECT public.get_ai_session_capabilities();
--
-- A direct `SELECT ... FROM feature_flags WHERE key LIKE 'ai\_%'` as
-- `authenticated` returns ZERO rows — that is the RLS policy hiding the
-- rollout plan, not a failure. The RPC is the client's only read path.
