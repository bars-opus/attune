-- Spec 1 W9b: grants for 20261104120000_opinion_moderation_notices.sql.
-- admin_confirm_content_removal stays the service role's only (and the SQL
-- editor's, as its owner); no client may call it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
COMMIT;
