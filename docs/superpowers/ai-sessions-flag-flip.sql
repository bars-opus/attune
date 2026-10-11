-- AI Sessions: enable the §12 capability flags in PRODUCTION.
--
-- RUN THIS YOURSELF. It is a service_role write against the live database —
-- `authenticated` has no UPDATE on public.feature_flags, by design (see
-- 20260712150000_dating_flag_defense_in_depth.sql for why the table is
-- locked down). Nothing in the app or the test suite can perform this.
--
-- PREREQUISITES — both now SATISFIED on main at 097a7a36, verified:
--   1. The two flag-gate findings are fixed (merged 097a7a36). Before that
--      fix, a lost response after `prepare` locked the user out of the
--      session they had just created, and the sheet could send a visibility
--      whose capability was off.
--   2. Migration 20260953200500 (get_ai_session_capabilities) is on main.
--      The client fails closed to all-off if it is absent, so a client-first
--      deploy degrades to "feature off" rather than an error.
--
-- SO THE ONLY REMAINING PREREQUISITE IS DEPLOYMENT: this writes flags that
-- the *deployed* client and edge function read. Deploy 097a7a36 — the app
-- build, the edge function, and the migrations through 20260953200600 —
-- BEFORE running this. Flipping a flag that the deployed code does not yet
-- understand is the one ordering that fails open rather than closed.
--
-- ROLLBACK is the same statement with `false`. The client reads these through
-- get_ai_session_capabilities() on each app session, so turning them off
-- takes effect on the next read — this is a live kill switch, not a release.
--
-- KNOWN LIMIT while testing: if a user's FIRST capability read fails (a
-- network blip at app start), the result is cached for that whole app
-- session and every AI entry point is silently absent — indistinguishable
-- from these flags being off. There is no in-app recovery short of a
-- relaunch. If the feature looks dead, relaunch before concluding anything.

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


-- OR, to roll out in stages. Any order is now safe: the sheet clamps its
-- selection to whatever is enabled (merged 097a7a36), so enabling shared
-- before private no longer leaves an unselected chip and a Start button
-- that always errors. Before that fix this order was the hazard.
--
--   UPDATE public.feature_flags SET enabled = true, updated_at = now()
--    WHERE key IN ('ai_assist_enabled', 'ai_sessions_private_enabled');
--
-- Then verify AS A CLIENT before widening — this is the only read path a
-- client has, and it is what the app actually calls:
--
--   BEGIN;
--   SET LOCAL ROLE authenticated;
--   SELECT set_config('request.jwt.claims',
--                     json_build_object('sub', '<a real user uuid>')::text, true);
--   SELECT public.get_ai_session_capabilities();
--   ROLLBACK;
--
-- A direct `SELECT ... FROM feature_flags WHERE key LIKE 'ai\_%'` as
-- `authenticated` returns ZERO rows — that is the RLS policy hiding the
-- rollout plan, not a failure. Do not "fix" it by widening the policy; that
-- is the bug 20260712150000 was written to close.
