-- supabase/migrations/20261019110335_release_push_subscription_grants.sql
-- Plan 1b final review I1: a signed-out phone pays its owed release as anon.
REVOKE ALL ON FUNCTION public.release_push_subscription(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_push_subscription(text) TO anon, authenticated;
