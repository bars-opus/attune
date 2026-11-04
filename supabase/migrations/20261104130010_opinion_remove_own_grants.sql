-- Spec 1 W9b: grants for 20261104130000_opinion_remove_own.sql. Signed-in
-- only; never anon.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.remove_my_opinion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_my_comment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_my_opinion(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_my_comment(uuid) TO authenticated;
COMMIT;
