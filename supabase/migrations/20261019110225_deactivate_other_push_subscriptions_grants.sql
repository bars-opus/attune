-- supabase/migrations/20261019110225_deactivate_other_push_subscriptions_grants.sql
-- Chat review #18 (fix I2): signed-in callers only.
REVOKE ALL ON FUNCTION public.deactivate_other_push_subscriptions(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deactivate_other_push_subscriptions(text) TO authenticated;
