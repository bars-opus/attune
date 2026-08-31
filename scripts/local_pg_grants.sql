-- Applied AFTER all migrations. ALTER DEFAULT PRIVILEGES only covers tables
-- created afterwards by the same role, so a blanket grant is what actually
-- reproduces Supabase's platform-side privileges across the whole schema.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
  TO authenticated, service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
  TO authenticated, service_role, anon;
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
