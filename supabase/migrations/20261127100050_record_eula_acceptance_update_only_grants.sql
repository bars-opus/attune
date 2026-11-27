-- Entry gates: grants for 20261127100040_record_eula_acceptance_update_only.sql,
-- as 20260817120000_eula_acceptance.sql set them: the app's alone (anon
-- revoked explicitly, since Supabase's default privileges grant it).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.record_eula_acceptance(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_eula_acceptance(text) TO authenticated;
COMMIT;
