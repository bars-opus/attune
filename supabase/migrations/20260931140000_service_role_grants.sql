-- Table privileges for every table in public, and for tables added later.
--
-- 20260930190000 granted the 13 game tables after the Paint Ball lobby
-- failed with 42501. That fixed the symptom in front of us. A project-wide
-- audit then found 103 public tables with NO grant to service_role at all
-- -- messages, profiles, push_tokens, game_sessions, verdicts, and every
-- worker queue among them.
--
-- Supabase grants table privileges PLATFORM-SIDE when a table is created
-- through its API. A table created by a migration gets whatever default
-- privileges exist at that moment, so the grant depended entirely on how
-- each table happened to come into existence. Nothing in the codebase
-- decided it.
--
-- How this stayed invisible: the Edge Function workers read through
-- PostgREST as service_role, and a missing SELECT grant there returns an
-- EMPTY RESULT, not an error. process-chat-safety-outbox booted every two
-- minutes, queried message_safety_outbox, got nothing, and returned
-- {processed: 0} -- while 89 messages sat pending. The cron job logged
-- `succeeded` because net.http_post returns as soon as the request is
-- queued. Three layers of green while nothing happened.
--
-- RLS remains the real gate. Every table here has it enabled with
-- policies, and service_role bypasses RLS by design -- that is what makes
-- it the workers' identity. A grant widens nothing on its own: Postgres
-- checks the table privilege FIRST and the policy second, which is why a
-- missing grant reads as 42501 (direct SQL) or as silence (PostgREST).

-- Everything that exists now, in one statement rather than a list that
-- goes stale the moment a table is added.
GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA public
  TO service_role;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- And everything added from here on. Without this, the next migration to
-- create a table reintroduces exactly this bug, and the next person sees
-- an empty queue with no error to explain it.
--
-- Scoped to the roles that create tables in this project: default
-- privileges apply per creating role, so one set for postgres does not
-- cover a table created by supabase_admin.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO service_role;

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public '
          'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role';
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public '
          'GRANT USAGE, SELECT ON SEQUENCES TO service_role';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'skipped default privileges for postgres (not owner)';
  WHEN undefined_object THEN
    -- The local contract harness has no postgres role.
    RAISE NOTICE 'skipped default privileges for postgres (role absent)';
END $$;

DO $$
BEGIN
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public '
          'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role';
  EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public '
          'GRANT USAGE, SELECT ON SEQUENCES TO service_role';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'skipped default privileges for supabase_admin (not owner)';
  WHEN undefined_object THEN
    RAISE NOTICE 'skipped default privileges for supabase_admin (role absent)';
END $$;

-- The anon and authenticated roles are deliberately NOT touched here.
-- Client access is granted per table alongside the RLS policies that
-- constrain it; a blanket grant to those roles would hand every future
-- table to clients by default, which is the opposite of what this fixes.

-- PostgREST caches table privileges in its schema cache. A grant applied
-- by migration is invisible to the API until that cache reloads -- the
-- privilege is in the database, every has_table_privilege() check passes,
-- and the workers still read empty queues, because PostgREST is still
-- enforcing the permissions it loaded at startup.
--
-- That is indistinguishable from the missing grant itself from the
-- outside, which is the trap: fixing the grant appears not to work, and
-- the obvious conclusion is that the grant was not the problem.
NOTIFY pgrst, 'reload schema';
