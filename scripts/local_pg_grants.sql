-- Applied AFTER all migrations, reproducing the privileges Supabase
-- applies platform-side.
--
-- service_role is deliberately NOT blanket-granted here any more.
--
-- It used to be, and that hid a real production fault for the project's
-- entire life: 103 public tables had no service_role grant at all,
-- because Supabase grants privileges when a table is created through its
-- API and a table created by a migration gets only whatever default
-- privileges happen to exist. Every Edge Function worker read empty
-- queues through PostgREST -- a missing SELECT returns NO ROWS rather
-- than an error -- while this harness showed every table reachable.
--
-- 20260931140000 now grants service_role explicitly and sets default
-- privileges for tables added later. Leaving service_role out of the
-- blanket below is what makes that migration load-bearing here: if it is
-- ever dropped or a table escapes it, the contract tests fail locally
-- instead of the queue silently draining nothing in production.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
  TO authenticated, anon;
-- Then re-apply the table REVOKEs migrations make deliberately.
--
-- Same hazard as the function note below, one level up: the blanket grant
-- above runs AFTER migrations, so it silently re-grants write access to
-- tables a migration explicitly revoked. In production Supabase applies
-- its grant at CREATE time and never again, so a later REVOKE stands —
-- here it was being undone, and games_contracts' "clients cannot write the
-- question catalogue" assertion failed against a schema that was correct.
--
-- Sourced from the migration itself rather than duplicated by hand, so
-- the two cannot drift.
\i supabase/migrations/20260930190000_game_table_grants.sql

-- Deliberately NOT granting EXECUTE on all functions.
--
-- Supabase's default is EXECUTE for PUBLIC on new functions, and the
-- migrations then REVOKE it from the SECURITY DEFINER RPCs that must not be
-- callable by clients. A blanket GRANT here would re-grant exactly those and
-- silently defeat every function-privilege contract -- dating_mode_contracts
-- asserts, for instance, that `authenticated` cannot execute
-- block_dating_user(text,uuid), which a blanket grant would make false.
--
-- So function privileges are left exactly as the migrations leave them.
