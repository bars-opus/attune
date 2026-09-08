-- Word Hunt private tables: revoked, and kept revoked.
--
-- Separated from the schema migration for one reason: this file is
-- replayed by scripts/local_pg_grants.sql AFTER the harness applies its
-- blanket "GRANT ... ON ALL TABLES IN SCHEMA public TO authenticated",
-- exactly as 20260930190000 is. Without that replay the harness hands
-- every client read access to the puzzle and the attempts, and the
-- contract test asserting they are shut passes or fails according to
-- which script ran last rather than according to the schema.
--
-- Which is not a hypothetical: the first clean rebuild after these
-- tables were written failed with
--
--   ERROR:  word_hunt_configs is readable by authenticated
--
-- Production does not have this hazard -- Supabase grants at CREATE time
-- and a later REVOKE stands -- but a future migration applying a blanket
-- grant would, and this file is what stands in its way there too.
--
-- These three tables have NO RLS POLICY AT ALL by design, so the table
-- privilege is the only gate. Everything reaches them through a SECURITY
-- DEFINER RPC running as owner.
REVOKE ALL ON public.word_hunt_configs  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.word_hunt_puzzles  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.word_hunt_attempts FROM PUBLIC, anon, authenticated;

GRANT SELECT, INSERT, UPDATE ON public.word_hunt_configs  TO service_role;
GRANT SELECT, INSERT           ON public.word_hunt_puzzles TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.word_hunt_attempts TO service_role;
