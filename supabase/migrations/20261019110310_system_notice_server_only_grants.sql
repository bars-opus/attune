-- supabase/migrations/20261019110310_system_notice_server_only_grants.sql
-- Chat review #19: grants for 20261019110300.
REVOKE ALL ON FUNCTION public.messages_system_notice_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.send_screenshot_notice(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_screenshot_notice(uuid, uuid) TO authenticated;
