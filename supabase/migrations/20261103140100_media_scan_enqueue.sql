-- Spec 1 W7b, migration 15b (spec §4.4 enqueue_media_scan, review F-1;
-- plan P-15, P-16): how a new upload reaches the queue.
--   * private.enqueue_media_scan(): AFTER INSERT OR UPDATE OF metadata,
--     name, bucket_id ON storage.objects. An insert, an update that changed
--     the bytes (the eTag or the mime type; a picture written over in
--     place, plan P-17), or a move / rename (the new key, B4 fix m1) is
--     passed to private.enqueue_media_object, which applies the flag and
--     the buckets. Inside an exception block, with a 2-second lock
--     timeout: a failure is counted and its object recorded in
--     private.media_scan_state and NEVER blocks the upload; the daily
--     reconcile queues it later (B4 fix m8).
--   * private.storage_objects_changed_since(): the objects in the scanned
--     buckets created or changed after a time, read with the columns this
--     storage schema has (updated_at, owner_id: newer schemas; B4 fix m11),
--     for the sweep and the reconcile.
--   * private.enqueue_new_storage_objects(): the F-1 fallback, a one-minute
--     sweep of objects created or changed since the last sweep (2-minute
--     overlap, ON CONFLICT in the writer). It moves the watermark even
--     while the flag is off, so the sweep (like the trigger) queues nothing
--     from before the flag went on. The reconcile below does: its first run
--     after the switch-on queues the objects changed in the 25 hours before
--     it, up to 25 hours of pre-switch uploads; older objects are never
--     queued (final review M-2; a backfill is an owner decision).
--   * private.reconcile_media_scan_queue(): daily on either path (cron
--     media-scan-reconcile), the last 25 hours of objects through the same
--     writer, so an upload whose enqueue failed is still scanned (B4 fix
--     m8). Only with the flag on.
--   * Never silent (final review M-1): a failed object, or a read of
--     storage.objects by the sweep or the reconcile that fails as a whole
--     (so nothing at all is queued), is counted through
--     private.note_media_scan_enqueue_failure (identity health, and one
--     webhook alert through media_scan_enqueue_alerts_due). After a failed
--     read the sweep keeps its watermark, so the next sweep reads the same
--     window again.
--   * private.install_media_scan_enqueue(p_force_sweep): the F-1 spike,
--     done by the migration itself (the development project can't be
--     touched first, plan P-16): keep the trigger if it is there in its
--     current form, else CREATE OR REPLACE it (needs only the TRIGGER
--     right); on insufficient_privilege (hosted Supabase may not let
--     postgres put a trigger on storage.objects), or on lock_not_available
--     (storage.objects busy past the migration's lock_timeout, PF-M4),
--     keep an earlier trigger if there is one, else schedule the sweep;
--     the owner can run SELECT private.install_media_scan_enqueue() again
--     later. Moving from the sweep to the trigger runs one last sweep
--     first (B4 fix m9). Either way it records the path in
--     private.media_scan_state (identity health's media_scan_enqueue_path)
--     and raises a NOTICE, saying why, that db push prints.
--     SECURITY INVOKER: it must run with the migration's own rights.
-- Grants in 20261103140110_media_scan_enqueue_grants.sql (none: nothing
-- here is granted to anyone).
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.enqueue_media_scan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_row jsonb;
  v_owner text;
BEGIN
  BEGIN
    IF TG_OP = 'UPDATE'
       AND OLD.name IS NOT DISTINCT FROM NEW.name
       AND OLD.bucket_id IS NOT DISTINCT FROM NEW.bucket_id
       AND (OLD.metadata ->> 'eTag') IS NOT DISTINCT FROM (NEW.metadata ->> 'eTag')
       AND (OLD.metadata ->> 'mimetype') IS NOT DISTINCT FROM (NEW.metadata ->> 'mimetype') THEN
      RETURN NULL;
    END IF;
    -- owner (uuid) on today's storage schema, owner_id (text) on newer
    -- ones: read by name so either schema works.
    v_row := to_jsonb(NEW);
    v_owner := coalesce(v_row ->> 'owner', v_row ->> 'owner_id');
    PERFORM private.enqueue_media_object(
      NEW.bucket_id,
      NEW.name,
      CASE WHEN v_owner ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           THEN v_owner::uuid END,
      coalesce(NEW.metadata ->> 'mimetype', NEW.metadata ->> 'contentType'),
      now());
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      PERFORM private.note_media_scan_enqueue_failure(NEW.bucket_id, NEW.name, false);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.storage_objects_changed_since(p_from timestamptz)
RETURNS TABLE (bucket_id text, name text, owner_text text, mime text, changed_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_updated boolean;
  v_owner boolean;
  v_owner_id boolean;
BEGIN
  SELECT bool_or(a.attname = 'updated_at'), bool_or(a.attname = 'owner'), bool_or(a.attname = 'owner_id')
    INTO v_updated, v_owner, v_owner_id
    FROM pg_catalog.pg_attribute AS a
   WHERE a.attrelid = 'storage.objects'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND a.attname IN ('updated_at', 'owner', 'owner_id');
  RETURN QUERY EXECUTE format(
    $q$SELECT o.bucket_id, o.name, %s, coalesce(o.metadata ->> 'mimetype', o.metadata ->> 'contentType'), %s
         FROM storage.objects AS o
        WHERE o.bucket_id = ANY (private.media_scan_buckets()) AND (o.created_at > $1%s)$q$,
    CASE WHEN coalesce(v_owner, false) AND coalesce(v_owner_id, false) THEN 'coalesce(o.owner::text, o.owner_id)'
         WHEN coalesce(v_owner, false) THEN 'o.owner::text'
         WHEN coalesce(v_owner_id, false) THEN 'o.owner_id'
         ELSE 'NULL::text' END,
    CASE WHEN coalesce(v_updated, false) THEN 'greatest(o.created_at, coalesce(o.updated_at, o.created_at))'
         ELSE 'o.created_at' END,
    CASE WHEN coalesce(v_updated, false) THEN ' OR o.updated_at > $1' ELSE '' END)
  USING p_from;
END;
$$;

CREATE OR REPLACE FUNCTION private.enqueue_new_storage_objects()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
  v_from timestamptz;
  v_object record;
  v_count int := 0;
BEGIN
  SELECT s.sweep_watermark INTO v_from FROM private.media_scan_state AS s FOR UPDATE;
  v_from := coalesce(v_from, v_now) - interval '2 minutes';
  IF private.spec1_flag_on('csam_hash_matching') THEN
    BEGIN
      FOR v_object IN SELECT * FROM private.storage_objects_changed_since(v_from) LOOP
        BEGIN
          PERFORM private.enqueue_media_object(
            v_object.bucket_id,
            v_object.name,
            CASE WHEN v_object.owner_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 THEN v_object.owner_text::uuid END,
            v_object.mime,
            v_object.changed_at);
          v_count := v_count + 1;
        EXCEPTION WHEN OTHERS THEN
          PERFORM private.note_media_scan_enqueue_failure(v_object.bucket_id, v_object.name, false);
        END;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      -- The read failed as a whole (M-1): counted, and the watermark stays
      -- where it was, so the next sweep reads this window again.
      PERFORM private.note_media_scan_enqueue_failure(NULL, NULL, true);
      RETURN 0;
    END;
  END IF;
  UPDATE private.media_scan_state SET sweep_watermark = v_now;
  RETURN v_count;
END;
$$;

-- media-scan-reconcile: the last 25 hours again, on either path, so an
-- object whose enqueue failed (trigger or sweep) is still scanned. The
-- writer's ON CONFLICT leaves rows already queued alone.
CREATE OR REPLACE FUNCTION private.reconcile_media_scan_queue()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_object record;
  v_count int := 0;
BEGIN
  IF NOT private.spec1_flag_on('csam_hash_matching') THEN
    RETURN 0;
  END IF;
  BEGIN
    FOR v_object IN SELECT * FROM private.storage_objects_changed_since(now() - interval '25 hours') LOOP
      BEGIN
        PERFORM private.enqueue_media_object(
          v_object.bucket_id,
          v_object.name,
          CASE WHEN v_object.owner_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
               THEN v_object.owner_text::uuid END,
          v_object.mime,
          v_object.changed_at);
        v_count := v_count + 1;
      EXCEPTION WHEN OTHERS THEN
        PERFORM private.note_media_scan_enqueue_failure(v_object.bucket_id, v_object.name, false);
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    -- The read failed as a whole (M-1): counted, never silent.
    PERFORM private.note_media_scan_enqueue_failure(NULL, NULL, true);
    RETURN 0;
  END;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION private.install_media_scan_enqueue(p_force_sweep boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_path text := 'sweep';
  v_why text := 'asked for (p_force_sweep)';
  v_was text := (SELECT s.enqueue_path FROM private.media_scan_state AS s);
  v_def text := (SELECT pg_catalog.pg_get_triggerdef(t.oid) FROM pg_catalog.pg_trigger AS t
                  WHERE t.tgrelid = 'storage.objects'::regclass AND t.tgname = 'enqueue_media_scan');
BEGIN
  IF NOT p_force_sweep THEN
    -- The current form: inserts, new bytes, and moves (B4 fix m1).
    IF v_def ~ 'AFTER INSERT OR UPDATE OF metadata, name, bucket_id ON storage\.objects FOR EACH ROW EXECUTE FUNCTION private\.enqueue_media_scan\(\)' THEN
      v_path := 'trigger';
      v_why := 'the trigger was already there';
    ELSE
      -- CREATE OR REPLACE TRIGGER needs only the TRIGGER right (dropping
      -- would need ownership of storage.objects).
      BEGIN
        CREATE OR REPLACE TRIGGER enqueue_media_scan
          AFTER INSERT OR UPDATE OF metadata, name, bucket_id ON storage.objects
          FOR EACH ROW EXECUTE FUNCTION private.enqueue_media_scan();
        v_path := 'trigger';
        v_why := CASE WHEN v_def IS NULL THEN 'the trigger was created' ELSE 'the trigger was brought up to date' END;
      EXCEPTION
        WHEN insufficient_privilege THEN
          v_path := CASE WHEN v_def IS NULL THEN 'sweep' ELSE 'trigger' END;
          v_why := 'this role may not put a trigger on storage.objects (' || SQLERRM || ')'
                   || CASE WHEN v_def IS NULL THEN '' ELSE '; the earlier trigger is kept as it is' END;
        WHEN lock_not_available THEN
          v_path := CASE WHEN v_def IS NULL THEN 'sweep' ELSE 'trigger' END;
          v_why := 'storage.objects was busy past the lock timeout (' || SQLERRM
                   || CASE WHEN v_def IS NULL THEN '' ELSE '; the earlier trigger is kept as it is' END
                   || '); run SELECT private.install_media_scan_enqueue() again when it is quiet';
      END;
    END IF;
  ELSE
    BEGIN
      DROP TRIGGER IF EXISTS enqueue_media_scan ON storage.objects;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END IF;

  -- From the sweep to the trigger: what the sweep hasn't seen yet is swept
  -- once more, before its cron goes (B4 fix m9).
  IF v_was = 'sweep' AND v_path = 'trigger' THEN
    PERFORM private.enqueue_new_storage_objects();
  END IF;

  PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'enqueue-new-storage-objects';
  IF v_path = 'sweep' THEN
    PERFORM cron.schedule('enqueue-new-storage-objects', '* * * * *',
                          'SELECT private.enqueue_new_storage_objects()');
  END IF;

  UPDATE private.media_scan_state AS s
     SET enqueue_path = v_path,
         path_recorded_at = now(),
         sweep_watermark = coalesce(s.sweep_watermark, now());
  RAISE NOTICE 'media_scan: new uploads reach the scan queue by % (why: %)',
    CASE v_path WHEN 'trigger' THEN 'the storage.objects trigger (enqueue_media_scan)'
                ELSE 'the one-minute sweep (cron enqueue-new-storage-objects)' END,
    v_why;
  RETURN v_path;
END;
$$;

REVOKE ALL ON FUNCTION private.enqueue_media_scan() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.storage_objects_changed_since(timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_new_storage_objects() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.reconcile_media_scan_queue() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.install_media_scan_enqueue(boolean) FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'media-scan-reconcile';
END;
$$;
SELECT cron.schedule('media-scan-reconcile', '41 4 * * *', $cron$SELECT private.reconcile_media_scan_queue()$cron$);

SELECT private.install_media_scan_enqueue();

COMMIT;
