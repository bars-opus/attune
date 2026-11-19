-- Spec 2 W4b: grants for 20261109110000_dating_v2_trusted_devices.sql. The
-- device table is no API role's, the service role included (the device
-- check and the trust writer reach it). trust_dating_device is the service
-- role's (dating-verification). The helpers are the database's own; the
-- re-created functions keep their grants (dating_require_trusted_device:
-- no API role, as W1c).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_trusted_devices FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_state(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_touch_device(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_bind_setup_device(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_device_gate(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_reverify_variant(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_check_standing(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.trust_dating_device(uuid, text, uuid) FROM PUBLIC, anon, authenticated; -- Spec 2 W4 final (M-3)
GRANT EXECUTE ON FUNCTION public.trust_dating_device(uuid, text, uuid) TO service_role; -- Spec 2 W4 final (M-3)
REVOKE ALL ON FUNCTION public.dating_storage_owns(text) FROM PUBLIC, anon, service_role; -- Spec 2 W4 final (M-10): as W3's twin
GRANT EXECUTE ON FUNCTION public.dating_storage_owns(text) TO authenticated; -- Spec 2 W4 final (M-10)
REVOKE ALL ON FUNCTION public.dating_require_trusted_device() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
