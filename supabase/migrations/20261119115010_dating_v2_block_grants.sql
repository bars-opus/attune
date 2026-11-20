-- Spec 2 W5b Task 7b: grants for 20261119115000_dating_v2_block.sql. The
-- card's Block is the app's (authenticated only), never anon's or the
-- service role's (it acts as the caller, auth.uid()). block_dating_user
-- and the setup lock stay the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.block_dating_introduction(text, uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.block_dating_introduction(text, uuid) TO authenticated;
COMMIT;
