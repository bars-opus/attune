-- Spec 1 W9d: grants for 20261107110000_opinion_enforcement_restore.sql.
-- complete_sign_up keeps its grants (signed-in only, as 20261025100210 left
-- them); the restore helper and the restore log are no API role's, the
-- service role included; the owner's undo is the service role's only; the
-- auth.users restore trigger's function is no API role's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;
REVOKE ALL ON FUNCTION private.opinion_restore_on_sign_up(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE private.opinion_restores FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.undo_opinion_restore(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.undo_opinion_restore(uuid) TO service_role;
REVOKE ALL ON FUNCTION private.opinion_restore_on_auth_user() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
