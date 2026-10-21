-- supabase/migrations/20261019110340_push_tokens_platform_check.sql
--
-- Plan 1b final review M5: push_tokens_platform_check still admitted 'web',
-- a platform register_push_subscription refuses and the contract treats as
-- a violation when active. Dead surface; the table now admits only what the
-- RPC writes.
--
-- Any 'web' row is a legacy raw token from the old direct-insert path,
-- already deactivated by 20261019110200 and never read again (the sender
-- reads active rows only), so it is deleted rather than relabelled.
DELETE FROM public.push_tokens WHERE platform NOT IN ('ios', 'android');

ALTER TABLE public.push_tokens DROP CONSTRAINT IF EXISTS push_tokens_platform_check;
ALTER TABLE public.push_tokens ADD CONSTRAINT push_tokens_platform_check
  CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text]));
