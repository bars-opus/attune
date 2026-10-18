-- supabase/migrations/20261017130300_read_marks_grants.sql
-- Replayed by scripts/local_pg_grants.sql after its blanket grant.
REVOKE ALL ON public.message_read_marks FROM PUBLIC, anon, authenticated;
