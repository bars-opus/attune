-- Spec 1 W7b: grants for 20261103140100_media_scan_enqueue.sql. The
-- trigger function, the sweep and the install are the database's own:
-- nothing is granted to anyone.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.enqueue_media_scan() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.storage_objects_changed_since(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_new_storage_objects() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.reconcile_media_scan_queue() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.install_media_scan_enqueue(boolean) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
