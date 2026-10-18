-- supabase/migrations/20261017200100_session_devices_grants.sql
-- Replayed by scripts/local_pg_grants.sql after its blanket grant.
REVOKE ALL ON public.session_devices FROM PUBLIC, anon, authenticated;
