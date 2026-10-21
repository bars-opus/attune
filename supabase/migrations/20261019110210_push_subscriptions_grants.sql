-- supabase/migrations/20261019110210_push_subscriptions_grants.sql
-- Chat review #18: push_tokens is written only through the RPCs. The old
-- direct policy (users_own_tokens, FOR ALL) let a client write any row
-- shape; nothing in the app used it (savePushToken has no caller).
REVOKE ALL ON public.push_tokens FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS users_own_tokens ON public.push_tokens;
REVOKE ALL ON FUNCTION public.register_push_subscription(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.unregister_push_subscription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_subscription(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_subscription(text) TO authenticated;
