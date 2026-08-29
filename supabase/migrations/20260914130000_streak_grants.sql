-- Grant the privileges a streak send needs.
--
-- Supabase issues table grants platform-side when a table is created, so
-- every migration since has quietly relied on them. Two things break that
-- for streaks:
--
--   1. streak_clips was created by 20260913210000, AFTER those grants were
--      applied, so authenticated has no privilege on it at all.
--   2. messages itself reported the 42501, so whatever the platform
--      granted there is not sufficient for this insert on remote.
--
-- Reproduced by revoking streak_clips' grants locally: the contract test
-- then fails exactly as production did. It passed before only because the
-- test harness grants every table blanket -- the harness hid the bug it
-- was meant to catch, which is now asserted instead.
-- messages: the error reported this table by name, so its grant is
-- reasserted here rather than assumed. Idempotent -- if the platform
-- grant is already present this changes nothing.
GRANT SELECT, INSERT, UPDATE ON public.messages TO authenticated;

-- streak_clips: created after the platform grants, so it has none at all.
-- This is the one that provably fails a production-shaped check.
GRANT SELECT, INSERT ON public.streak_clips TO authenticated;

-- The view RPC is SECURITY DEFINER and deletes clips itself, so clients
-- never need DELETE here.
