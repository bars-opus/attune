-- supabase/tests/media_scan_contracts.sql
-- Spec 1 W7b (§4.2, §4.3 W7b, §4.4, §4.6, §7.1, §7.4; reviews F-1, I-10):
-- image safety. New uploads in the listed buckets are queued (by the
-- trigger, or by the sweep where the trigger can't be created), never a
-- dating-profile-photos object, only with csam_hash_matching on; a failing
-- queue insert never blocks the upload; a queued match and an inline match
-- each give exactly one hold and one escalation through the one path; an
-- inline match twice is idempotent; no client reaches the queue, the
-- escalations or the quarantine. One BEGIN ... ROLLBACK.
-- Batch 4 fix round 1 adds: every object in a scanned bucket is queued
-- whatever its declared mime (I-3); an answer must carry its claim's
-- lease (I-1); unquarantined evidence is never deleted by another
-- pipeline (I-2); moves (m1), the deletion upsert (m2), one hold per user
-- (m3), retention with the flag off (m4), the alert count (m5), the hosted
-- storage shape (m6), the reconcile of a failed enqueue (m8) and the last
-- sweep on a switch to the trigger (m9). Not shown here: FOR UPDATE SKIP
-- LOCKED between two scan-media runs (needs a second session).
-- Batch 5 fix round 1 adds (I-4): each csam_match escalation records the
-- exact safety-quarantine path of its copy, NULL when not copied; a repeat
-- keeps the first copy's path, or records a copy where there was none
-- without marking it quarantined; one signature per entry point.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/media_scan_contracts.sql
-- Fixture ids 5f7b0000-0000-0000-0000-0000000000NN; phones +15558500NN
-- (§7.1's 85xx range), on auth.users and public.users; objects under
-- w7-contract/. Every refusal is checked by its message or SQLSTATE.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f7b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (pg_temp.id(p_n), '15558500' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, path)
  VALUES (pg_temp.id(p_n), '15558500' || p_n, 'Person ' || p_n, 'just_me');
  RETURN pg_temp.id(p_n);
END $$;

-- An upload, the way Storage writes the row. Where storage.objects has
-- updated_at (hosted: DEFAULT now()), an upload made "earlier" changed
-- then too (B4 fix m6).
CREATE FUNCTION pg_temp.upload(p_bucket text, p_name text, p_owner uuid, p_mime text,
                               p_created timestamptz DEFAULT now()) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name, owner, metadata, created_at)
  VALUES (p_bucket, 'w7-contract/' || p_name, p_owner,
          jsonb_build_object('mimetype', p_mime, 'eTag', '"' || md5(p_name) || '"', 'size', 1024), p_created);
  IF pg_temp.has_column('updated_at') THEN
    EXECUTE 'UPDATE storage.objects SET updated_at = $3 WHERE bucket_id = $1 AND name = $2'
      USING p_bucket, 'w7-contract/' || p_name, p_created;
  END IF;
END $$;

-- The lease the contract's hand-made claims carry (B4 fix I-1).
CREATE FUNCTION pg_temp.lease() RETURNS uuid LANGUAGE sql AS $$
  SELECT '5f7b0000-0000-0000-0000-00000000ee01'::uuid;
$$;

CREATE FUNCTION pg_temp.queued(p_bucket text, p_name text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT q.status FROM private.media_scan_queue AS q
           WHERE q.bucket = p_bucket AND q.object_name = 'w7-contract/' || p_name);
END $$;

CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('csam_hash_matching', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;

-- [p_sql] as the service role: NULL, or the refusal's message.
CREATE FUNCTION pg_temp.service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- The SQLSTATE (or NULL) of [p_sql] as [p_role].
CREATE FUNCTION pg_temp.client_error(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLSTATE;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- How uploads reach the queue on this database: 'trigger' or 'sweep'.
CREATE FUNCTION pg_temp.path() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT s.enqueue_path FROM private.media_scan_state AS s);
END $$;

-- On the sweep path, run the sweep now (what its cron does every minute);
-- on the trigger path the uploads are already queued.
CREATE FUNCTION pg_temp.settle() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF pg_temp.path() = 'sweep' THEN
    UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
    PERFORM private.enqueue_new_storage_objects();
  END IF;
END $$;

-- The job id of an object.
CREATE FUNCTION pg_temp.job(p_bucket text, p_name text) RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT q.id FROM private.media_scan_queue AS q
           WHERE q.bucket = p_bucket AND q.object_name = 'w7-contract/' || p_name);
END $$;

-- Whether storage.objects has [p_col]. Newer storage schemas have
-- updated_at and owner_id (text); the local stub has neither, and the
-- forced-sweep run adds both inside its rolled-back transaction (PF-L3).
CREATE FUNCTION pg_temp.has_column(p_col text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_attribute
                  WHERE attrelid = 'storage.objects'::regclass AND attname = p_col
                    AND attnum > 0 AND NOT attisdropped);
$$;

-- New bytes written over an object in place (an upsert): a new eTag, and
-- updated_at where the schema has one; then the sweep, where it is the
-- path. False where this database can't show the change to the sweep (the
-- sweep path without updated_at), and nothing is written.
CREATE FUNCTION pg_temp.overwrite(p_bucket text, p_name text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  IF pg_temp.path() = 'sweep' AND NOT pg_temp.has_column('updated_at') THEN
    RETURN false;
  END IF;
  -- The object was first uploaded an hour ago (so only its updated_at can
  -- show the sweep the new bytes); not an UPDATE OF metadata.
  UPDATE storage.objects SET created_at = now() - interval '1 hour'
   WHERE bucket_id = p_bucket AND name = 'w7-contract/' || p_name;
  UPDATE storage.objects SET metadata = metadata || jsonb_build_object('eTag', '"' || md5(random()::text) || '"')
   WHERE bucket_id = p_bucket AND name = 'w7-contract/' || p_name;
  IF pg_temp.has_column('updated_at') THEN
    EXECUTE 'UPDATE storage.objects SET updated_at = now() WHERE bucket_id = $1 AND name = $2'
      USING p_bucket, 'w7-contract/' || p_name;
  END IF;
  PERFORM pg_temp.settle();
  RETURN true;
END $$;

-- Buckets the fixtures need that this database may not have.
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('dating-profile-photos', 'dating-profile-photos', false) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('data-exports', 'data-exports', false) ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Objects, grants and the crons; nothing reaches a client (§4.2, §7.1).
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regclass('private.media_scan_queue') IS NULL
     OR to_regclass('public.safety_escalations') IS NULL
     OR to_regclass('private.media_scan_state') IS NULL
     OR to_regprocedure('private.handle_csam_match(text,text,uuid,text,text,boolean,text)') IS NULL
     OR to_regprocedure('public.claim_media_scan_jobs(integer)') IS NULL
     OR to_regprocedure('public.complete_media_scan(bigint,text,text,text,uuid,text)') IS NULL
     OR to_regprocedure('private.guard_unquarantined_evidence()') IS NULL
     OR to_regprocedure('private.release_guarded_evidence()') IS NULL
     OR to_regprocedure('private.guard_safety_hold_release()') IS NULL
     OR to_regprocedure('private.reconcile_media_scan_queue()') IS NULL
     OR to_regprocedure('private.storage_objects_changed_since(timestamp with time zone)') IS NULL
     OR to_regprocedure('public.record_inline_csam_match(text,text,uuid,text,text,boolean,text)') IS NULL
     OR to_regprocedure('private.enqueue_media_scan()') IS NULL
     OR to_regprocedure('private.enqueue_new_storage_objects()') IS NULL
     OR to_regprocedure('private.install_media_scan_enqueue(boolean)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'safety-quarantine' AND NOT public) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W7b objects are missing';
  END IF;
  -- One signature per entry point (B5 fix I-4): the drafts without the
  -- quarantine path are gone, and the escalation has the column.
  IF to_regprocedure('private.handle_csam_match(text,text,uuid,text,text,boolean)') IS NOT NULL
     OR to_regprocedure('public.complete_media_scan(bigint,text,text,text,uuid)') IS NOT NULL
     OR to_regprocedure('public.record_inline_csam_match(text,text,uuid,text,text,boolean)') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'safety_escalations'
                       AND column_name = 'quarantine_path' AND data_type = 'text') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the quarantine path has no column, or a signature without it remains (B5 fix I-4)';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.safety_escalations'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'safety_escalations')
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
                 AND (coalesce(qual, '') || coalesce(with_check, '')) ~ 'safety-quarantine') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: escalations or the quarantine have a client policy';
  END IF;
  SELECT string_agg(r || ' ' || t, ', ') INTO v_bad
    FROM unnest(ARRAY['anon', 'authenticated']) AS r,
         unnest(ARRAY['private.media_scan_queue', 'public.safety_escalations', 'private.media_scan_state']) AS t
   WHERE has_table_privilege(r, t, 'SELECT') OR has_table_privilege(r, t, 'INSERT')
      OR has_table_privilege(r, t, 'UPDATE') OR has_table_privilege(r, t, 'DELETE');
  IF v_bad IS NOT NULL
     OR has_table_privilege('service_role', 'private.media_scan_queue', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.safety_escalations', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.safety_escalations', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: table grants are wrong (no client; the service role works the escalations; the queue is function-only): %', v_bad;
  END IF;
  -- The two id sequences too (PF-L2): the database's default privileges
  -- would otherwise hand a client USAGE on a new public sequence.
  SELECT string_agg(r || ' ' || s || ' ' || p, ', ') INTO v_bad
    FROM unnest(ARRAY['anon', 'authenticated']) AS r,
         unnest(ARRAY['public.safety_escalations_id_seq', 'private.media_scan_queue_id_seq']) AS s,
         unnest(ARRAY['USAGE', 'SELECT', 'UPDATE']) AS p
   WHERE has_sequence_privilege(r, s, p);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client holds a right on a W7b id sequence: %', v_bad;
  END IF;
  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['public.claim_media_scan_jobs(integer)', 'public.complete_media_scan(bigint,text,text,text,uuid,text)',
                      'public.record_inline_csam_match(text,text,uuid,text,text,boolean,text)',
                      'public.csam_escalations_due()', 'public.scan_failed_escalations_due()',
                      'public.mark_safety_escalations_alerted(bigint[])']) AS f
   WHERE has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
      OR NOT has_function_privilege('service_role', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W7b service function has the wrong grants: %', v_bad;
  END IF;
  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['private.handle_csam_match(text,text,uuid,text,text,boolean,text)',
                      'private.enqueue_media_object(text,text,uuid,text,timestamp with time zone)',
                      'private.enqueue_media_scan()', 'private.enqueue_new_storage_objects()',
                      'private.install_media_scan_enqueue(boolean)', 'private.expire_media_scan_jobs()',
                      'private.media_scan_retention()', 'private.identity_health_w7b()',
                      'private.guard_unquarantined_evidence()', 'private.release_guarded_evidence()',
                      'private.guard_safety_hold_release()', 'private.reconcile_media_scan_queue()',
                      'private.storage_objects_changed_since(timestamp with time zone)']) AS f
   WHERE has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
      OR has_function_privilege('service_role', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server-only W7b function is executable by a role: %', v_bad;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scan-media' AND schedule = '* * * * *'
                  AND command ~ 'invoke_edge_function\(''scan-media''\)')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'media-scan-retention' AND schedule = '27 4 * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the scan-media or media-scan-retention cron is missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'media-scan-reconcile' AND schedule = '41 4 * * *'
                  AND command = 'SELECT private.reconcile_media_scan_queue()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the media-scan-reconcile cron is missing (B4 fix m8)';
  END IF;
  -- Every W7b SECURITY DEFINER function pins search_path to '' (B4 fix m7).
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p
   WHERE p.oid IN (SELECT to_regprocedure(f) FROM unnest(ARRAY[
           'private.media_scan_buckets()', 'private.enqueue_media_object(text,text,uuid,text,timestamp with time zone)',
           'private.handle_csam_match(text,text,uuid,text,text,boolean,text)', 'public.claim_media_scan_jobs(integer)',
           'private.expire_media_scan_jobs()', 'public.complete_media_scan(bigint,text,text,text,uuid,text)',
           'public.record_inline_csam_match(text,text,uuid,text,text,boolean,text)', 'private.safety_escalations_due(text)',
           'public.csam_escalations_due()', 'public.scan_failed_escalations_due()',
           'public.mark_safety_escalations_alerted(bigint[])', 'private.media_scan_retention()',
           'private.identity_health_w7b()', 'public.get_identity_health()',
           'private.guard_unquarantined_evidence()', 'private.release_guarded_evidence()',
           'private.guard_safety_hold_release()', 'private.enqueue_media_scan()',
           'private.storage_objects_changed_since(timestamp with time zone)',
           'private.enqueue_new_storage_objects()', 'private.reconcile_media_scan_queue()']) AS f)
     AND p.prosecdef AND NOT coalesce(p.proconfig, '{}') @> ARRAY['search_path=""'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W7b SECURITY DEFINER function does not pin search_path to '''': %', v_bad;
  END IF;
  -- Every client storage.objects policy names its bucket, so none reaches
  -- safety-quarantine by accident (B4 fix m7).
  SELECT string_agg(policyname, ', ') INTO v_bad FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND roles && ARRAY['anon', 'authenticated', 'public']::name[]
     AND (coalesce(qual, '') || coalesce(with_check, '')) !~ 'bucket_id = ';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client storage.objects policy names no bucket: %', v_bad;
  END IF;
  -- The scan-media run is only called while csam_hash_matching is on (PF-L10).
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scan-media'
                  AND command ~ 'WHERE\s+private\.spec1_flag_on\(''csam_hash_matching''\)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the scan-media cron is not gated on csam_hash_matching (PF-L10)';
  END IF;
  -- Both entry points go through the one path; nothing tells anyone.
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.complete_media_scan(bigint,text,text,text,uuid,text)'::regprocedure) !~ 'private\.handle_csam_match'
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'public.record_inline_csam_match(text,text,uuid,text,text,boolean,text)'::regprocedure) !~ 'private\.handle_csam_match' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match entry point does not use private.handle_csam_match (review I-10)';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'private.handle_csam_match(text,text,uuid,text,text,boolean,text)'::regprocedure)
       ~* '(notification|push|net\.http|invoke_edge_function|relationships|messages)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match path reaches beyond the hold, the escalation and the deletion (nothing may tell anyone)';
  END IF;
END $$;

-- =====================================================================
-- B. The trigger (§4.4): listed buckets, images and videos, with the flag;
--    never dating-profile-photos (I-10); a picture written over in place
--    is queued again (plan P-17).
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.person('01');
BEGIN
  -- The recorded path is the real one: a trigger and no sweep, or the
  -- sweep's cron and no trigger (plan P-16). Locally it is the trigger.
  IF pg_temp.path() IS NULL
     OR (pg_temp.path() = 'trigger') IS DISTINCT FROM
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR (pg_temp.path() = 'sweep') IS DISTINCT FROM
        EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recorded enqueue path (%) is not the one installed', pg_temp.path();
  END IF;

  PERFORM pg_temp.flag(false);
  PERFORM pg_temp.upload('message-media', 'off.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.settle();
  IF pg_temp.queued('message-media', 'off.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upload was queued with csam_hash_matching off';
  END IF;

  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.upload('message-media', 'chat.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('story-media', 'story.mp4', v_ama, 'video/mp4');
  PERFORM pg_temp.upload('relationship-avatars', 'pair.png', v_ama, 'image/png');
  PERFORM pg_temp.upload('journal-media', 'note.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('planning-media', 'plan.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('avatars', 'me.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('dating-profile-photos', 'dating.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('data-exports', 'export.zip', v_ama, 'application/zip');
  PERFORM pg_temp.upload('message-media', 'voice.m4a', v_ama, 'audio/mp4');
  PERFORM pg_temp.upload('avatars', 'raw.jpg', v_ama, 'application/octet-stream');
  PERFORM pg_temp.upload('message-media', 'blank.bin', v_ama, NULL);
  PERFORM pg_temp.upload('message-media', 'empty.bin', v_ama, '');
  PERFORM pg_temp.settle();

  IF pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('story-media', 'story.mp4') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('journal-media', 'note.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an image or video in a listed bucket was not queued';
  END IF;
  IF pg_temp.queued('dating-profile-photos', 'dating.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating-profile-photos object was queued (Spec 2 matches it inline, review I-10)';
  END IF;
  IF pg_temp.queued('data-exports', 'export.zip') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an object in an unlisted bucket was queued';
  END IF;
  -- The declared mime is the client's: every object in a scanned bucket is
  -- queued, and scan-media decides from the bytes (B4 fix I-3).
  IF pg_temp.queued('message-media', 'voice.m4a') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('avatars', 'raw.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('message-media', 'blank.bin') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('message-media', 'empty.bin') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an object in a scanned bucket was not queued whatever its declared mime (I-3)';
  END IF;
  IF (SELECT mime FROM private.media_scan_queue WHERE id = pg_temp.job('avatars', 'raw.jpg')) IS DISTINCT FROM 'application/octet-stream'
     OR (SELECT mime FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'blank.bin')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queued mime is not the one given (I-3)';
  END IF;
  IF (SELECT owner_user_id FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'chat.jpg')) IS DISTINCT FROM v_ama
     OR (SELECT source FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'chat.jpg')) IS DISTINCT FROM 'queue' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queued row does not name its uploader or source';
  END IF;

  -- Newer storage schemas name the uploader in owner_id (text), with owner
  -- empty: still the uploader (PF-L3).
  IF pg_temp.has_column('owner_id') THEN
    EXECUTE $q$INSERT INTO storage.objects (bucket_id, name, owner, owner_id, metadata)
               VALUES ('message-media', 'w7-contract/owner-id.jpg', NULL, $1,
                       '{"mimetype": "image/jpeg", "eTag": "\"owner-id\"", "size": 1024}')$q$
      USING v_ama::text;
    PERFORM pg_temp.settle();
    IF (SELECT owner_user_id FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'owner-id.jpg'))
         IS DISTINCT FROM v_ama THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an upload named by owner_id (text) was queued without its uploader';
    END IF;
  ELSE
    RAISE NOTICE 'media_scan_contracts: B owner_id case skipped (storage.objects has no owner_id)';
  END IF;

  -- The trigger fires for Storage's own role too (B4 fix m7): an insert as
  -- authenticated (granted here, rolled back) is queued.
  IF pg_temp.path() = 'trigger' THEN
    BEGIN
      IF NOT has_table_privilege('authenticated', 'storage.objects', 'INSERT') THEN
        EXECUTE 'GRANT INSERT ON storage.objects TO authenticated';
      END IF;
      EXECUTE 'SET LOCAL ROLE authenticated';
      INSERT INTO storage.objects (bucket_id, name, owner, metadata)
      VALUES ('message-media', 'w7-contract/as-user.jpg', v_ama, '{"mimetype": "image/jpeg", "eTag": "\"as-user\""}');
      RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN
      RESET ROLE;
      RAISE NOTICE 'media_scan_contracts: B authenticated case skipped (%)', SQLERRM;
    END;
    IF EXISTS (SELECT 1 FROM storage.objects WHERE name = 'w7-contract/as-user.jpg')
       AND pg_temp.queued('message-media', 'as-user.jpg') IS DISTINCT FROM 'pending' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an upload by Storage''s authenticated role was not queued (m7)';
    END IF;
  END IF;

  -- A move or rename: the new key is queued (B4 fix m1).
  IF pg_temp.path() = 'sweep' AND NOT pg_temp.has_column('updated_at') THEN
    RAISE NOTICE 'media_scan_contracts: B move case skipped (the sweep path without storage.objects.updated_at)';
  ELSE
    PERFORM pg_temp.upload('message-media', 'tomove.jpg', v_ama, 'image/jpeg', now() - interval '1 hour');
    PERFORM pg_temp.settle();
    UPDATE storage.objects SET name = 'w7-contract/moved.jpg'
     WHERE bucket_id = 'message-media' AND name = 'w7-contract/tomove.jpg';
    IF pg_temp.has_column('updated_at') THEN
      EXECUTE 'UPDATE storage.objects SET updated_at = now() WHERE bucket_id = $1 AND name = $2'
        USING 'message-media', 'w7-contract/moved.jpg';
    END IF;
    PERFORM pg_temp.settle();
    IF pg_temp.queued('message-media', 'moved.jpg') IS DISTINCT FROM 'pending' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a moved object was not queued under its new name (m1)';
    END IF;
  END IF;

  -- The avatar was scanned clear, then written over in place: queued again
  -- (the trigger compares the eTag; the sweep, where it runs, sees the
  -- row's updated_at, where the schema has one, PF-L3).
  IF pg_temp.path() = 'sweep' AND NOT pg_temp.has_column('updated_at') THEN
    RAISE NOTICE 'media_scan_contracts: B overwrite case skipped (the sweep path without storage.objects.updated_at)';
    RETURN;
  END IF;
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now(), enqueued_at = now() - interval '1 hour'
   WHERE id = pg_temp.job('avatars', 'me.jpg');
  PERFORM pg_temp.overwrite('avatars', 'me.jpg');
  IF pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a picture written over in place was not queued again';
  END IF;
  -- The sweep sees updated_at move on any change, so only the trigger can
  -- tell new bytes from a metadata change (an extra scan on the sweep path).
  IF pg_temp.path() <> 'trigger' THEN
    RETURN;
  END IF;
  -- A metadata change that isn't new bytes queues nothing.
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now(), enqueued_at = now() - interval '1 hour'
   WHERE id = pg_temp.job('avatars', 'me.jpg');
  UPDATE storage.objects SET metadata = metadata || '{"cacheControl": "max-age=60"}'
   WHERE bucket_id = 'avatars' AND name = 'w7-contract/me.jpg';
  IF pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'clear' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a metadata change without new bytes queued the object again';
  END IF;
END $$;

-- =====================================================================
-- C. A failing queue insert never blocks the upload (§4.4, R13); the
--    failure is counted for identity health.
-- =====================================================================
DO $$
DECLARE
  v_before bigint := (SELECT enqueue_failures FROM private.media_scan_state);
BEGIN
  ALTER TABLE private.media_scan_queue ADD CONSTRAINT w7_contract_refuse CHECK (object_name <> 'w7-contract/refused.jpg');
  BEGIN
    PERFORM pg_temp.upload('message-media', 'refused.jpg', pg_temp.id('01'), 'image/jpeg');
    PERFORM pg_temp.settle();
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing queue insert blocked the upload (%)', SQLERRM;
  END;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'message-media' AND name = 'w7-contract/refused.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing queue insert blocked the upload';
  END IF;
  IF pg_temp.queued('message-media', 'refused.jpg') IS NOT NULL
     OR (SELECT enqueue_failures FROM private.media_scan_state) <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the failed enqueue was not counted';
  END IF;
  -- Recorded with its object and time, and queued by the daily reconcile
  -- once the cause is gone (B4 fix m8).
  IF (SELECT last_failed_bucket || '/' || last_failed_object FROM private.media_scan_state)
       IS DISTINCT FROM 'message-media/w7-contract/refused.jpg'
     OR (SELECT last_enqueue_failure_at FROM private.media_scan_state) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the failed enqueue did not record its object (m8)';
  END IF;
  ALTER TABLE private.media_scan_queue DROP CONSTRAINT w7_contract_refuse;
  PERFORM private.reconcile_media_scan_queue();
  IF pg_temp.queued('message-media', 'refused.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the daily reconcile did not queue an upload whose enqueue failed (m8)';
  END IF;
END $$;

-- =====================================================================
-- D. The sweep (F-1 fallback), called directly, on uploads the trigger
--    didn't queue (made with the flag off): what changed since the last
--    sweep (2-minute overlap), the same buckets and rules, once each; with
--    the flag off it queues nothing but moves on.
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.id('01');
BEGIN
  PERFORM pg_temp.flag(false);
  PERFORM pg_temp.upload('message-media', 'old.jpg', v_ama, 'image/jpeg', now() - interval '1 hour');
  PERFORM pg_temp.upload('message-media', 'swept.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('dating-profile-photos', 'swept-dating.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('journal-media', 'swept.txt', v_ama, 'text/plain');
  PERFORM pg_temp.flag(true);
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep did not queue a new upload';
  END IF;
  IF pg_temp.queued('message-media', 'old.jpg') IS NOT NULL
     OR pg_temp.queued('dating-profile-photos', 'swept-dating.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep queued an old or a dating object';
  END IF;
  IF pg_temp.queued('journal-media', 'swept.txt') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left an object in a scanned bucket unqueued for its declared mime (I-3)';
  END IF;
  IF (SELECT sweep_watermark FROM private.media_scan_state) < now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep did not move its watermark';
  END IF;
  -- Again: nothing new, nothing doubled.
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now() WHERE id = pg_temp.job('message-media', 'swept.jpg');
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept.jpg') IS DISTINCT FROM 'clear'
     OR (SELECT count(*) FROM private.media_scan_queue WHERE object_name = 'w7-contract/swept.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second sweep queued an object again';
  END IF;
  -- Flag off: nothing queued, the watermark still moves.
  PERFORM pg_temp.flag(false);
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
  PERFORM pg_temp.upload('message-media', 'swept-off.jpg', v_ama, 'image/jpeg');
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept-off.jpg') IS NOT NULL
     OR (SELECT sweep_watermark FROM private.media_scan_state) < now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep queued with the flag off, or stood still';
  END IF;
  PERFORM pg_temp.flag(true);
END $$;

-- =====================================================================
-- E. The F-1 choice (plan P-16): without the right to put a trigger on
--    storage.objects, the install schedules the sweep and records it; with
--    it, the trigger and no sweep.
-- =====================================================================
CREATE ROLE w7_contract_not_owner NOLOGIN;
GRANT USAGE ON SCHEMA private, cron, storage TO w7_contract_not_owner;
GRANT SELECT, UPDATE ON private.media_scan_state TO w7_contract_not_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron.job TO w7_contract_not_owner;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA cron TO w7_contract_not_owner;
GRANT EXECUTE ON FUNCTION private.install_media_scan_enqueue(boolean) TO w7_contract_not_owner;
DO $$
DECLARE
  v text;
BEGIN
  -- Only where this role may drop the trigger (locally, where it owns
  -- storage.objects); a hosted-like CI database keeps it and skips E.
  BEGIN
    DROP TRIGGER IF EXISTS enqueue_media_scan ON storage.objects;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'media_scan_contracts: section E skipped (this role cannot drop a storage.objects trigger)';
    RETURN;
  END;
  EXECUTE 'SET LOCAL ROLE w7_contract_not_owner';
  BEGIN
    v := private.install_media_scan_enqueue();
  EXCEPTION WHEN OTHERS THEN
    v := 'refused: ' || SQLERRM;
  END;
  RESET ROLE;
  IF v IS DISTINCT FROM 'sweep'
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects' AND schedule = '* * * * *'
                     AND command = 'SELECT private.enqueue_new_storage_objects()')
     OR (SELECT enqueue_path FROM private.media_scan_state) IS DISTINCT FROM 'sweep' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the trigger right the install did not fall back to the recorded sweep (got %)', v;
  END IF;
  IF (public.get_identity_health() ->> 'media_scan_enqueue_path') IS DISTINCT FROM 'sweep' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health does not report the sweep path';
  END IF;

  -- An upload the sweep hasn't seen yet when the trigger takes over.
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
  PERFORM pg_temp.upload('message-media', 'between.jpg', pg_temp.id('01'), 'image/jpeg');

  -- With the right, the trigger alone again (the sweep's cron removed).
  v := private.install_media_scan_enqueue();
  IF v IS DISTINCT FROM 'trigger'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects')
     OR pg_temp.path() IS DISTINCT FROM 'trigger' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the trigger right the install did not choose the trigger alone (got %)', v;
  END IF;
  IF pg_temp.queued('message-media', 'between.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: switching from the sweep to the trigger missed an upload the sweep had not seen (m9)';
  END IF;
  IF (SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
       !~ 'UPDATE OF metadata, name, bucket_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trigger does not see moves (m1)';
  END IF;
END $$;

-- =====================================================================
-- F. Claiming (§4.3): due jobs only, a lease, nothing with the flag off.
-- =====================================================================
DO $$
DECLARE
  v_ids bigint[];
  v_row record;
  v_old uuid;
BEGIN
  -- Only this file's jobs are due.
  UPDATE private.media_scan_queue SET next_attempt_at = now() + interval '1 day'
   WHERE object_name NOT LIKE 'w7-contract/%' AND status IN ('pending', 'scanning');
  UPDATE private.media_scan_queue SET next_attempt_at = now() + interval '1 day'
   WHERE object_name LIKE 'w7-contract/%' AND status = 'pending';
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second'
   WHERE id IN (pg_temp.job('message-media', 'chat.jpg'), pg_temp.job('journal-media', 'note.jpg'),
                pg_temp.job('planning-media', 'plan.jpg'));

  PERFORM pg_temp.flag(false);
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id) INTO v_ids FROM public.claim_media_scan_jobs(10) AS c;
  RESET ROLE;
  IF v_ids IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: jobs were claimed with csam_hash_matching off';
  END IF;
  PERFORM pg_temp.flag(true);

  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id ORDER BY c.id) INTO v_ids FROM public.claim_media_scan_jobs(2) AS c;
  RESET ROLE;
  IF cardinality(v_ids) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM private.media_scan_queue WHERE id = ANY (v_ids)
                 AND (status <> 'scanning' OR attempts <> 1 OR next_attempt_at < now() + interval '9 minutes'
                      OR lease_id IS NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim did not lease exactly the jobs asked for: %', v_ids;
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id) INTO v_ids FROM public.claim_media_scan_jobs(10) AS c;
  RESET ROLE;
  IF cardinality(v_ids) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a leased job was claimed twice, or a due one missed: %', v_ids;
  END IF;
  -- A lease that lapsed (the run died) is claimed again, with a new lease.
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second' WHERE id = v_ids[1];
  v_old := (SELECT lease_id FROM private.media_scan_queue WHERE id = v_ids[1]);
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT * INTO v_row FROM public.claim_media_scan_jobs(10);
  RESET ROLE;
  IF v_row.id IS DISTINCT FROM v_ids[1] OR v_row.attempts <> 2
     OR v_row.lease_id IS NULL OR v_row.lease_id IS NOT DISTINCT FROM v_old THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lapsed lease was not claimed again';
  END IF;
END $$;

-- =====================================================================
-- G. Completing (§4.3): clear, skipped, the back-off, 24 hours -> failed
--    and one scan_failed escalation; a stale answer changes nothing.
-- =====================================================================
DO $$
DECLARE
  v_job bigint := pg_temp.job('journal-media', 'note.jpg');
  v_got text;
BEGIN
  IF pg_temp.service(format('SELECT public.complete_media_scan(%s, ''maybe'', ''stub'', NULL)', v_job))
       IS DISTINCT FROM 'media_scan:invalid_result'
     OR pg_temp.service('SELECT public.complete_media_scan(-1, ''clear'', ''stub'', NULL)') IS DISTINCT FROM 'media_scan:no_job' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad completion was not refused by its message';
  END IF;

  -- unavailable: 1, 5, 15, 60 minutes.
  FOR i IN 1..5 LOOP
    UPDATE private.media_scan_queue SET status = 'scanning', attempts = i, lease_id = pg_temp.lease() WHERE id = v_job;
    v_got := pg_temp.service(format('SELECT public.complete_media_scan(%s, ''unavailable'', ''photodna'', ''code:3208'', ''5f7b0000-0000-0000-0000-00000000ee01'')', v_job));
    IF v_got IS NOT NULL
       OR (SELECT status FROM private.media_scan_queue WHERE id = v_job) <> 'pending'
       OR abs(extract(epoch FROM (SELECT next_attempt_at FROM private.media_scan_queue WHERE id = v_job) - now())
              - CASE i WHEN 1 THEN 60 WHEN 2 THEN 300 WHEN 3 THEN 900 ELSE 3600 END) > 5 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: attempt % did not back off as §4.3 says', i;
    END IF;
  END LOOP;

  -- clear, and a stale clear for a job that isn't scanning changes nothing.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', ''t-1'', ''5f7b0000-0000-0000-0000-00000000ee01'')', v_job));
  IF (SELECT status || '/' || vendor || '/' || vendor_ref FROM private.media_scan_queue WHERE id = v_job) IS DISTINCT FROM 'clear/photodna/t-1'
     OR (SELECT scanned_at FROM private.media_scan_queue WHERE id = v_job) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clear result was not recorded';
  END IF;
  UPDATE private.media_scan_queue SET status = 'pending', lease_id = pg_temp.lease() WHERE id = pg_temp.job('planning-media', 'plan.jpg');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', NULL, ''5f7b0000-0000-0000-0000-00000000ee01'')', pg_temp.job('planning-media', 'plan.jpg')));
  IF pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale clear (the job was queued again) was recorded';
  END IF;

  -- skipped (a video, or gone): never clear.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = pg_temp.job('story-media', 'story.mp4');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''skipped'', ''photodna'', ''video_not_hashed'', ''5f7b0000-0000-0000-0000-00000000ee01'')', pg_temp.job('story-media', 'story.mp4')));
  IF pg_temp.queued('story-media', 'story.mp4') IS DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skipped result was not recorded as skipped';
  END IF;

  -- 24 hours unavailable: failed, one scan_failed escalation, no hold.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease(), enqueued_at = now() - interval '25 hours'
   WHERE id = pg_temp.job('relationship-avatars', 'pair.png');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''unavailable'', ''stub'', ''stub_refused_in_production'', ''5f7b0000-0000-0000-0000-00000000ee01'')',
                                 pg_temp.job('relationship-avatars', 'pair.png')));
  IF pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'failed'
     OR (SELECT count(*) FROM public.safety_escalations
          WHERE kind = 'scan_failed' AND object_name = 'w7-contract/pair.png' AND status = 'open'
            AND vendor_ref = 'stub_refused_in_production') <> 1
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = pg_temp.id('01')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 24 hours unscanned did not fail with one scan_failed escalation (and no hold)';
  END IF;

  -- A job nobody answers is expired too (the claim and the retention).
  UPDATE private.media_scan_queue SET status = 'pending', enqueued_at = now() - interval '25 hours', next_attempt_at = now() + interval '1 day'
   WHERE id = pg_temp.job('planning-media', 'plan.jpg');
  -- Not while csam_hash_matching is off (B4 fix m4).
  PERFORM pg_temp.flag(false);
  PERFORM private.media_scan_retention();
  PERFORM pg_temp.flag(true);
  IF pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'pending'
     OR EXISTS (SELECT 1 FROM public.safety_escalations WHERE kind = 'scan_failed' AND object_name = 'w7-contract/plan.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retention expired and escalated a job while csam_hash_matching was off (m4)';
  END IF;
  PERFORM private.media_scan_retention();
  IF pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'failed'
     OR NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE kind = 'scan_failed' AND object_name = 'w7-contract/plan.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job left 24 hours was not failed and escalated';
  END IF;
END $$;

-- G (I-1). Run A claims a picture; the user writes new bytes over it, so
-- it is queued again and run B claims it; A's clear for the old bytes
-- changes nothing, and B's answer is the one taken.
DO $$
DECLARE
  v_job bigint;
  v_a uuid;
  v_b uuid;
BEGIN
  PERFORM pg_temp.upload('avatars', 'lease.jpg', pg_temp.id('01'), 'image/jpeg');
  PERFORM pg_temp.settle();
  v_job := pg_temp.job('avatars', 'lease.jpg');
  UPDATE private.media_scan_queue SET next_attempt_at = now() + interval '1 day'
   WHERE status IN ('pending', 'scanning') AND id <> v_job;
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second' WHERE id = v_job;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT c.lease_id INTO v_a FROM public.claim_media_scan_jobs(5) AS c WHERE c.id = v_job;
  RESET ROLE;

  UPDATE private.media_scan_queue SET enqueued_at = now() - interval '1 hour' WHERE id = v_job;
  IF NOT pg_temp.overwrite('avatars', 'lease.jpg') THEN
    PERFORM private.enqueue_media_object('avatars', 'w7-contract/lease.jpg', pg_temp.id('01'), 'image/jpeg', now());
  END IF;
  IF pg_temp.queued('avatars', 'lease.jpg') IS DISTINCT FROM 'pending'
     OR (SELECT lease_id FROM private.media_scan_queue WHERE id = v_job) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new bytes under a claim were not queued again with the lease cleared (I-1)';
  END IF;
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second' WHERE id = v_job;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT c.lease_id INTO v_b FROM public.claim_media_scan_jobs(5) AS c WHERE c.id = v_job;
  RESET ROLE;
  IF v_a IS NULL OR v_b IS NULL OR v_a = v_b THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim did not give a fresh lease (I-1)';
  END IF;

  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', ''v1'', %L)', v_job, v_a));
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''unavailable'', ''photodna'', ''v1'', NULL)', v_job));
  IF (SELECT status || '/' || lease_id::text FROM private.media_scan_queue WHERE id = v_job)
       IS DISTINCT FROM 'scanning/' || v_b::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an answer from an earlier claim (or none) completed the re-queued job (I-1)';
  END IF;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', ''v2'', %L)', v_job, v_b));
  IF (SELECT status || '/' || vendor_ref FROM private.media_scan_queue WHERE id = v_job) IS DISTINCT FROM 'clear/v2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the answer of the current claim was not taken (I-1)';
  END IF;
END $$;

-- G (claim expiry, B4 fix m7). A claim expires a job left 24 hours too:
-- not handed out, failed, and a scan_failed escalation.
DO $$
DECLARE
  v_job bigint;
  v_ids bigint[];
BEGIN
  PERFORM pg_temp.upload('journal-media', 'stale.jpg', pg_temp.id('01'), 'image/jpeg');
  PERFORM pg_temp.settle();
  v_job := pg_temp.job('journal-media', 'stale.jpg');
  UPDATE private.media_scan_queue SET enqueued_at = now() - interval '25 hours', next_attempt_at = now() - interval '1 second'
   WHERE id = v_job;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id) INTO v_ids FROM public.claim_media_scan_jobs(50) AS c;
  RESET ROLE;
  IF v_job = ANY (coalesce(v_ids, ARRAY[]::bigint[]))
     OR pg_temp.queued('journal-media', 'stale.jpg') IS DISTINCT FROM 'failed'
     OR NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE kind = 'scan_failed' AND object_name = 'w7-contract/stale.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim handed out a job left 24 hours instead of failing and escalating it';
  END IF;
END $$;

-- =====================================================================
-- H. A match: one path for the queue and inline (I-10); exactly one hold,
--    one escalation, the deletion queued after quarantine; idempotent; a
--    failed quarantine keeps the original (plan P-18).
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.id('01');
  v_kofi constant uuid := pg_temp.person('02');
  v_job bigint := pg_temp.job('message-media', 'chat.jpg');
  v_esc bigint;
  v_again bigint;
  v_refused text;
BEGIN
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-1'', NULL, %L)',
                                 v_job, 'message-media/w7-contract/chat.jpg/m-1'));
  SELECT id INTO v_esc FROM public.safety_escalations WHERE kind = 'csam_match' AND object_name = 'w7-contract/chat.jpg';
  IF pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'match'
     OR v_esc IS NULL
     OR (SELECT user_id::text || '/' || status || '/' || vendor || '/' || vendor_ref || '/' || quarantined
           FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM v_ama::text || '/open/photodna/track-1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match did not open its escalation with the vendor reference';
  END IF;
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE id = v_esc)
       IS DISTINCT FROM 'message-media/w7-contract/chat.jpg/m-1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a quarantined match did not record the exact quarantine path (B5 fix I-4)';
  END IF;
  IF (SELECT count(*) FROM public.account_holds WHERE user_id = v_ama AND kind = 'safety_review' AND resolved_at IS NULL
         AND reason_ref = 'safety_escalation:' || v_esc) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/chat.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match did not hold the uploader and queue the original''s deletion';
  END IF;
  -- The same answer twice: still one of each, and no error.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = v_job;
  IF pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-2'', NULL, %L)',
                            v_job, 'message-media/w7-contract/chat.jpg/m-2')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated queued match was refused';
  END IF;
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE id = v_esc)
       IS DISTINCT FROM 'message-media/w7-contract/chat.jpg/m-1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated match replaced the first copy''s quarantine path (B5 fix I-4)';
  END IF;
  IF (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/chat.jpg') <> 1
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_ama) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE object_name = 'w7-contract/chat.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated queued match made a second escalation, hold or deletion';
  END IF;

  -- Inline (Spec 2's process-dating-photo): the same path, once per object.
  EXECUTE 'SET LOCAL ROLE service_role';
  v_esc := public.record_inline_csam_match('dating-profile-photos', 'w7-contract/inline.jpg', v_kofi, 'photodna', 'track-3');
  RESET ROLE;
  IF v_esc IS NULL
     OR (SELECT source || '/' || status FROM private.media_scan_queue
          WHERE bucket = 'dating-profile-photos' AND object_name = 'w7-contract/inline.jpg') IS DISTINCT FROM 'inline/match'
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_kofi AND kind = 'safety_review'
          AND reason_ref = 'safety_escalation:' || v_esc) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w7-contract/inline.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match did not take the same path (queue row, hold, deletion)';
  END IF;
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE id = v_esc) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match that named no path recorded one (B5 fix I-4)';
  END IF;
  -- A reviewer clears the hold (a false match); the pipeline retries: the
  -- same escalation, and the resolved hold stays resolved.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract reviewer' WHERE user_id = v_kofi;
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    v_again := public.record_inline_csam_match('dating-profile-photos', 'w7-contract/inline.jpg', v_kofi, 'photodna', 'track-4');
  EXCEPTION WHEN OTHERS THEN
    v_again := NULL;
  END;
  RESET ROLE;
  IF v_again IS DISTINCT FROM v_esc
     OR (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/inline.jpg') <> 1
     OR (SELECT resolved_at FROM public.account_holds WHERE user_id = v_kofi) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match twice was not idempotent';
  END IF;

  -- The quarantine copy failed: held and escalated, the original kept.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false, %L)',
                                 'message-media', 'w7-contract/unquarantined.jpg', v_ama, 'photodna', 'track-5',
                                 'message-media/w7-contract/unquarantined.jpg/not-a-copy'));
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unquarantined match recorded a quarantine path (B5 fix I-4)';
  END IF;
  -- The same failed copy again (a retry): still no path.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false, %L)',
                                 'message-media', 'w7-contract/unquarantined.jpg', v_ama, 'photodna', 'track-5',
                                 'message-media/w7-contract/unquarantined.jpg/not-a-copy-2'));
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated unquarantined match recorded a quarantine path (B5 fix I-4)';
  END IF;
  IF (SELECT quarantined FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') IS DISTINCT FROM false
     OR (SELECT notes FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') !~ 'still in place'
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'w7-contract/unquarantined.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match without a quarantine copy queued the evidence for deletion';
  END IF;
  -- Nothing else deletes that evidence meanwhile (B4 fix I-2): a deletion
  -- any pipeline queues waits, and so does one queued before the match.
  PERFORM public.queue_media_deletion('message-media', 'w7-contract/unquarantined.jpg');
  PERFORM public.queue_story_media_deletion('message-media', 'w7-contract/unquarantined.jpg', now());
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/unquarantined.jpg')
       IS DISTINCT FROM 'infinity'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another pipeline queued the deletion of unquarantined evidence (I-2)';
  END IF;
  PERFORM public.queue_story_media_deletion('story-media', 'w7-contract/expiring.jpg', now() + interval '1 hour');
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'story-media', 'w7-contract/expiring.jpg', v_ama, 'photodna', 'track-5b'));
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/expiring.jpg')
       IS DISTINCT FROM 'infinity'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion queued before an unquarantined match was not held back (I-2)';
  END IF;
  -- A person copies it by hand and marks it quarantined: the deletions go.
  UPDATE public.safety_escalations SET quarantined = true WHERE object_name = 'w7-contract/unquarantined.jpg';
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/unquarantined.jpg') > now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marking the evidence quarantined did not release its deletion (I-2)';
  END IF;
  -- match_unquarantined through the queue: the same.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = pg_temp.job('avatars', 'me.jpg');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match_unquarantined'', ''photodna'', ''track-6'', NULL, %L)',
                                 pg_temp.job('avatars', 'me.jpg'), 'avatars/w7-contract/me.jpg/not-a-copy'));
  IF (SELECT quarantined FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg') IS DISTINCT FROM false
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'w7-contract/me.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match_unquarantined queued the evidence for deletion';
  END IF;
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match_unquarantined recorded a quarantine path (B5 fix I-4)';
  END IF;
  -- A later scan of the same bytes copies it: the path is recorded, but a
  -- person still checks it and marks the escalation (nothing is released).
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-6b'', NULL, %L)',
                                 pg_temp.job('avatars', 'me.jpg'), 'avatars/w7-contract/me.jpg/m-later'));
  IF (SELECT quarantine_path || '/' || quarantined FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg')
       IS DISTINCT FROM 'avatars/w7-contract/me.jpg/m-later/false'
     OR (SELECT notes FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg') !~ 'A later scan copied it'
     OR (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg') <> 1
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'w7-contract/me.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later copy of unquarantined evidence was not recorded, or was marked quarantined (B5 fix I-4)';
  END IF;

  -- No owner (a server upload): escalated, nobody held.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L)',
                                 'story-media', 'w7-contract/ownerless.jpg', 'photodna', 'track-7'));
  IF (SELECT user_id FROM public.safety_escalations WHERE object_name = 'w7-contract/ownerless.jpg') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE object_name = 'w7-contract/ownerless.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ownerless match was not escalated';
  END IF;
  -- A match is never dropped, even for a job no longer scanning.
  UPDATE private.media_scan_queue SET status = 'pending' WHERE id = pg_temp.job('story-media', 'story.mp4');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-8'')', pg_temp.job('story-media', 'story.mp4')));
  IF NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE object_name = 'w7-contract/story.mp4' AND kind = 'csam_match') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match for a job that was not scanning was dropped';
  END IF;

  -- A quarantined match brings forward a deletion some pipeline queued for
  -- later (a story's archive time): the repo's upsert (B4 fix m2).
  PERFORM public.queue_story_media_deletion('story-media', 'w7-contract/archived.jpg', now() + interval '1 day');
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L, true, %L)',
                                 'story-media', 'w7-contract/archived.jpg', 'photodna', 'track-7b',
                                 'story-media/w7-contract/archived.jpg/m-inline'));
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/archived.jpg') > now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a quarantined match left its original''s deletion for later (m2)';
  END IF;
  IF (SELECT quarantine_path FROM public.safety_escalations WHERE object_name = 'w7-contract/archived.jpg')
       IS DISTINCT FROM 'story-media/w7-contract/archived.jpg/m-inline' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline quarantined match did not record the exact quarantine path (B5 fix I-4)';
  END IF;

  -- An inline match after a person closed the earlier one (new bytes):
  -- a new escalation, and the queue row records the new reference (B4 fix m11).
  UPDATE public.safety_escalations SET status = 'closed' WHERE object_name = 'w7-contract/inline.jpg';
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L)',
                                 'dating-profile-photos', 'w7-contract/inline.jpg', v_kofi, 'photodna', 'track-4b'));
  IF (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/inline.jpg') <> 2
     OR (SELECT vendor_ref FROM private.media_scan_queue
          WHERE bucket = 'dating-profile-photos' AND object_name = 'w7-contract/inline.jpg') IS DISTINCT FROM 'track-4b' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match after a closed one kept the old record (m11)';
  END IF;

  -- One hold per user (B4 fix m3): Ama's later matches kept the hold of
  -- her first and say so; it can't be resolved while they are open.
  v_esc := (SELECT id FROM public.safety_escalations WHERE kind = 'csam_match' AND object_name = 'w7-contract/chat.jpg');
  IF (SELECT reason_ref FROM public.account_holds WHERE user_id = v_ama AND kind = 'safety_review')
       IS DISTINCT FROM 'safety_escalation:' || v_esc
     OR position('already held (safety_escalation:' || v_esc || ')' IN
                 (SELECT notes FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg')) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later match of a held uploader moved the hold''s reference or did not name it (m3)';
  END IF;
  BEGIN
    UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract reviewer'
     WHERE user_id = v_ama AND kind = 'safety_review';
    v_refused := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_refused := SQLERRM;
  END;
  IF coalesce(v_refused, '') !~ '^hold:still_needed'
     OR (SELECT resolved_at FROM public.account_holds WHERE user_id = v_ama AND kind = 'safety_review') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hold another open match still needs was resolved (m3)';
  END IF;
END $$;

-- H (PF-M2). New bytes at a path whose match a person closed are queued
-- again, and a second match is a second escalation and a new hold; while
-- the match is open, new bytes change nothing (the match stands).
DO $$
DECLARE
  v_esi constant uuid := pg_temp.person('03');
  v_job bigint;
  v_first bigint;
  v_second bigint;
BEGIN
  PERFORM pg_temp.upload('message-media', 'again.jpg', v_esi, 'image/jpeg');
  PERFORM pg_temp.settle();
  v_job := pg_temp.job('message-media', 'again.jpg');
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-9'')', v_job));
  SELECT id INTO v_first FROM public.safety_escalations WHERE kind = 'csam_match' AND object_name = 'w7-contract/again.jpg';
  IF v_first IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the PF-M2 fixture match opened no escalation';
  END IF;

  -- New bytes while the escalation is open: not queued again.
  UPDATE private.media_scan_queue SET enqueued_at = now() - interval '1 hour' WHERE id = v_job;
  IF NOT pg_temp.overwrite('message-media', 'again.jpg') THEN
    PERFORM private.enqueue_media_object('message-media', 'w7-contract/again.jpg', v_esi, 'image/jpeg', now());
  END IF;
  IF pg_temp.queued('message-media', 'again.jpg') IS DISTINCT FROM 'match' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new bytes at a path whose match is still open were queued again (PF-M2)';
  END IF;

  -- A person resolves the hold and closes the escalation; the original was
  -- deleted. New bytes at the same path: queued again.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract reviewer' WHERE user_id = v_esi;
  UPDATE public.safety_escalations SET status = 'closed' WHERE id = v_first;
  UPDATE public.media_deletion_queue SET deleted_at = now()
   WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/again.jpg';
  -- (where the sweep can't see the change, what it would do on seeing it)
  IF NOT pg_temp.overwrite('message-media', 'again.jpg') THEN
    PERFORM private.enqueue_media_object('message-media', 'w7-contract/again.jpg', v_esi, 'image/jpeg', now());
  END IF;
  IF pg_temp.queued('message-media', 'again.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new bytes at a path whose match was closed were not queued again (PF-M2)';
  END IF;

  -- They match too: a second escalation and a new hold.
  UPDATE private.media_scan_queue SET status = 'scanning', lease_id = pg_temp.lease() WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-10'')', v_job));
  SELECT id INTO v_second FROM public.safety_escalations
   WHERE kind = 'csam_match' AND object_name = 'w7-contract/again.jpg' AND status <> 'closed';
  IF v_second IS NULL OR v_second = v_first
     OR (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/again.jpg') <> 2
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_esi AND kind = 'safety_review'
          AND resolved_at IS NULL AND reason_ref = 'safety_escalation:' || v_second) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match after a closed one did not open a second escalation and a new hold (PF-M2)';
  END IF;
  IF (SELECT count(*) FROM public.media_deletion_queue
       WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/again.jpg' AND deleted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second match did not queue the new bytes for deletion (PF-M2)';
  END IF;
END $$;

-- =====================================================================
-- I. The webhook's sources: ids, a count and times, never a person or a
--    path; marked once sent (plan P-21).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_ids bigint[];
BEGIN
  UPDATE public.safety_escalations SET alerted_at = now() WHERE object_name NOT LIKE 'w7-contract/%';
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.csam_escalations_due();
  RESET ROLE;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at']
     OR v::text ~ '(w7-contract|5f7b0000|photodna|track)'
     OR (v ->> 'count')::int <> 11 THEN  -- H's six; I-2, m2 and m11's one each; H (PF-M2)'s two
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match alert carries more than ids, a count and times, or the wrong count: %', v;
  END IF;
  SELECT array_agg(x::bigint) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_safety_escalations_alerted(v_ids);
  v := public.csam_escalations_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alerted escalations were due again';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.scan_failed_escalations_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 3 THEN  -- G's two, and G (claim expiry)'s one
    RAISE EXCEPTION 'CONTRACT VIOLATED: the scan_failed source counted wrongly: %', v;
  END IF;
  -- A burst: the count covers all of it, the ids at most 500 (B4 fix m5).
  INSERT INTO public.safety_escalations (kind, bucket, object_name)
  SELECT 'scan_failed', 'message-media', 'w7-contract/burst-' || g FROM generate_series(1, 501) AS g;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.scan_failed_escalations_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 504 OR jsonb_array_length(v -> 'ids') <> 500 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in a burst the alert under-counted or sent over 500 ids: count %', v ->> 'count';
  END IF;
END $$;

-- =====================================================================
-- J. Retention (§4.6, §4.8): clear and skipped rows go after 7 days;
--    matches and failures stay with their escalation. Identity health.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  UPDATE private.media_scan_queue SET scanned_at = now() - interval '8 days'
   WHERE object_name LIKE 'w7-contract/%' AND status IN ('clear', 'skipped', 'match', 'failed');
  PERFORM private.media_scan_retention();
  IF pg_temp.queued('journal-media', 'note.jpg') IS NOT NULL
     OR pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'match'
     OR pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retention removed a match or a failure, or kept a clear row';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF NOT (v ?& ARRAY['media_scan_enqueue_path', 'media_scan_enqueue_failures',
                     'media_scan_last_enqueue_failure_at', 'media_scan_pending',
                     'media_scan_oldest_pending_minutes', 'media_scan_skipped_7d',
                     'safety_escalations_open', 'safety_escalations_unalerted',
                     'fresh_starts_7d', 'accounts_without_path'])
     OR (v ->> 'media_scan_enqueue_path') IS DISTINCT FROM pg_temp.path()
     OR (v ->> 'media_scan_enqueue_failures')::int < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health lacks the W7b lines (or lost the earlier ones): %', v;
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_identity_health()'::regprocedure)
       ~* '(media_scan_queue|safety_escalations|media_scan_state)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_identity_health names a W7 table itself (keep them in private.identity_health_w7b)';
  END IF;
END $$;

-- =====================================================================
-- K. No client reaches the queue, the escalations or the functions.
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.client_error('authenticated', 'SELECT count(*) FROM public.safety_escalations') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT count(*) FROM private.media_scan_queue') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT count(*) FROM public.safety_escalations') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT * FROM public.claim_media_scan_jobs(5)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT public.complete_media_scan(1, ''clear'', ''x'', NULL)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', format('SELECT public.record_inline_csam_match(''avatars'', ''x'', %L, ''x'', NULL)', pg_temp.id('02'))) IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.csam_escalations_due()') IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client reached the image-safety tables or functions';
  END IF;
END $$;

-- =====================================================================
-- L. A match whose copy failed (final review I-2): the reviewer copies it
--    by hand, marks the escalation quarantined with that path through
--    mark_escalation_quarantined (service role only; it refuses while the
--    copy is not in safety-quarantine), and only then does the original's
--    deletion go ahead, whether it was queued before or after the mark.
-- =====================================================================
DO $$
DECLARE
  v_yaw constant uuid := pg_temp.person('04');
  v_esc bigint;
  v_out jsonb;
  v_refused text;
  v_other_ctid tid;
BEGIN
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'message-media', 'w7-contract/handcopy.jpg', v_yaw, 'photodna', 'track-l1'));
  -- A second unquarantined match of the same uploader, its deletion held
  -- too (re-review N-1): marking the first must leave this one alone.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'message-media', 'w7-contract/handcopy-b.jpg', v_yaw, 'photodna', 'track-l1b'));
  PERFORM pg_temp.service($q$SELECT public.queue_media_deletion('message-media', 'w7-contract/handcopy-b.jpg')$q$);
  SELECT ctid INTO v_other_ctid FROM public.media_deletion_queue
   WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/handcopy-b.jpg';
  SELECT id INTO v_esc FROM public.safety_escalations
   WHERE kind = 'csam_match' AND object_name = 'w7-contract/handcopy.jpg';
  IF v_esc IS NULL
     OR (SELECT notes FROM public.safety_escalations WHERE id = v_esc) !~ 'mark_escalation_quarantined'
     OR (SELECT notes FROM public.safety_escalations WHERE id = v_esc) !~ 'then queue' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unquarantined match''s note does not say to mark it quarantined before queuing the deletion (I-2)';
  END IF;
  -- Queued by hand before the mark (the order the old note gave): held.
  PERFORM pg_temp.service($q$SELECT public.queue_media_deletion('message-media', 'w7-contract/handcopy.jpg')$q$);
  IF (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/handcopy.jpg')
       IS DISTINCT FROM 'infinity'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion of unquarantined evidence was not held (I-2 fixture)';
  END IF;
  -- Refused: no copy yet; a path outside <bucket>/<object>/; a client.
  v_refused := pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                      v_esc, 'message-media/w7-contract/handcopy.jpg/hand-1'));
  IF coalesce(v_refused, '') !~ '^media_scan:quarantine_copy_missing'
     OR (SELECT quarantined FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM false
     OR (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/handcopy.jpg')
          IS DISTINCT FROM 'infinity'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the evidence was marked quarantined before its copy existed: %', v_refused;
  END IF;
  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES ('safety-quarantine', 'message-media/w7-contract/handcopy.jpg/hand-1', '{"size": 1024}'::jsonb),
         ('safety-quarantine', 'message-media/w7-contract/other.jpg/hand-1', '{"size": 1024}'::jsonb);
  IF coalesce(pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                     v_esc, 'message-media/w7-contract/other.jpg/hand-1')), '') !~ '^media_scan:invalid_quarantine_path'
     OR coalesce(pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                        v_esc, 'message-media/w7-contract/handcopy.jpg/')), '') !~ '^media_scan:invalid_quarantine_path'
     OR coalesce(pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, NULL)', v_esc)), '') !~ '^media_scan:invalid_quarantine_path'
     OR coalesce(pg_temp.service('SELECT public.mark_escalation_quarantined(-1, ''x/y/z'')'), '') !~ '^media_scan:no_escalation'
     OR pg_temp.client_error('authenticated', format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                                     v_esc, 'message-media/w7-contract/handcopy.jpg/hand-1')) IS DISTINCT FROM '42501'
     OR has_function_privilege('anon', 'public.mark_escalation_quarantined(bigint,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.mark_escalation_quarantined(bigint,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.mark_escalation_quarantined(bigint,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_escalation_quarantined took a wrong path, an unknown escalation or a client';
  END IF;
  IF (SELECT quarantined FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused mark changed the escalation';
  END IF;
  -- The copy exists: marked, the path recorded, the held deletion released
  -- and due for the drain (deleted_at NULL, not_before <= now()).
  EXECUTE 'SET LOCAL ROLE service_role';
  v_out := public.mark_escalation_quarantined(v_esc, 'message-media/w7-contract/handcopy.jpg/hand-1');
  RESET ROLE;
  IF (SELECT quarantined::text || '/' || quarantine_path FROM public.safety_escalations WHERE id = v_esc)
       IS DISTINCT FROM 'true/message-media/w7-contract/handcopy.jpg/hand-1'
     OR (v_out ->> 'released')::int IS DISTINCT FROM 1
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                     WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/handcopy.jpg'
                       AND deleted_at IS NULL AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marking the hand copy did not release the original''s deletion (I-2): %', v_out;
  END IF;
  -- Only that object's deletion was touched (re-review N-1): the same
  -- uploader's other held evidence is still held, and its row was not even
  -- rewritten (the evidence guard would re-hold it, which hides a release
  -- that lost its object filter from not_before alone).
  IF (SELECT not_before FROM public.media_deletion_queue
       WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/handcopy-b.jpg')
       IS DISTINCT FROM 'infinity'::timestamptz
     OR (SELECT ctid FROM public.media_deletion_queue
          WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/handcopy-b.jpg')
          IS DISTINCT FROM v_other_ctid
     OR (SELECT not_before FROM public.media_deletion_queue WHERE object_name = 'w7-contract/expiring.jpg')
          IS DISTINCT FROM 'infinity'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marking one object touched another object''s held deletion (N-1)';
  END IF;
  -- The same mark again is a no-op; another path is refused (the first
  -- copy stays the evidence); a closed escalation is refused.
  IF pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                            v_esc, 'message-media/w7-contract/handcopy.jpg/hand-1')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same mark twice was refused';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES ('safety-quarantine', 'message-media/w7-contract/handcopy.jpg/hand-2', '{"size": 1024}'::jsonb);
  IF coalesce(pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                     v_esc, 'message-media/w7-contract/handcopy.jpg/hand-2')), '') !~ '^media_scan:other_quarantine_path' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second copy replaced the recorded evidence path';
  END IF;

  -- The runbook's order on a new match: copy, mark, then queue: the
  -- deletion is due straight away (the guard no longer holds it).
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'story-media', 'w7-contract/handcopy2.jpg', v_yaw, 'photodna', 'track-l2'));
  SELECT id INTO v_esc FROM public.safety_escalations
   WHERE kind = 'csam_match' AND object_name = 'w7-contract/handcopy2.jpg';
  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES ('safety-quarantine', 'story-media/w7-contract/handcopy2.jpg/hand-1', '{"size": 1024}'::jsonb);
  PERFORM pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                 v_esc, 'story-media/w7-contract/handcopy2.jpg/hand-1'));
  PERFORM pg_temp.service($q$SELECT public.queue_media_deletion('story-media', 'w7-contract/handcopy2.jpg')$q$);
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                  WHERE bucket_id = 'story-media' AND object_name = 'w7-contract/handcopy2.jpg'
                    AND deleted_at IS NULL AND not_before <= now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion queued after the mark was still held (I-2)';
  END IF;
  UPDATE public.safety_escalations SET status = 'closed' WHERE id = v_esc;
  IF coalesce(pg_temp.service(format('SELECT public.mark_escalation_quarantined(%s, %L)',
                                     v_esc, 'story-media/w7-contract/handcopy2.jpg/hand-1')), '') !~ '^media_scan:escalation_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed escalation was marked';
  END IF;
END $$;

-- =====================================================================
-- M. The scanner never scans nothing silently (final review M-1): a sweep
--    or reconcile whose read of storage.objects fails as a whole is
--    counted (identity health), the sweep keeps its watermark, and every
--    enqueue failure is alerted once (media_scan_enqueue_alerts_due).
-- =====================================================================
DO $$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_mark timestamptz;
  v_due jsonb;
  v_ids bigint[];
  v_raised text;
BEGIN
  PERFORM pg_temp.flag(true);
  EXECUTE 'SET LOCAL ROLE service_role';
  v_before := public.get_identity_health();
  RESET ROLE;
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '5 minutes';
  v_mark := (SELECT sweep_watermark FROM private.media_scan_state);
  -- The read fails as a whole (as when the role can't read the table).
  -- The stand-in is undone with this block (sub-transaction); what it
  -- saw is kept in variables.
  BEGIN
    EXECUTE $f$CREATE OR REPLACE FUNCTION private.storage_objects_changed_since(p_from timestamptz)
      RETURNS TABLE (bucket_id text, name text, owner_text text, mime text, changed_at timestamptz)
      LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $b$
      BEGIN RAISE EXCEPTION 'permission denied for table objects' USING ERRCODE = '42501'; END $b$ $f$;
    BEGIN
      PERFORM private.enqueue_new_storage_objects();
      PERFORM private.reconcile_media_scan_queue();
      v_raised := NULL;
    EXCEPTION WHEN OTHERS THEN
      v_raised := SQLERRM;
    END;
    EXECUTE 'SET LOCAL ROLE service_role';
    v_after := public.get_identity_health();
    v_due := public.media_scan_enqueue_alerts_due();
    RESET ROLE;
    IF (SELECT sweep_watermark FROM private.media_scan_state) IS DISTINCT FROM v_mark THEN
      v_raised := coalesce(v_raised, 'watermark moved');
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'contract:undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'contract:undo' THEN
      RAISE;
    END IF;
  END;
  IF v_raised IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed storage.objects read raised or moved the sweep''s watermark (M-1): %', v_raised;
  END IF;
  IF (v_after ->> 'media_scan_enqueue_read_failures')::int - coalesce((v_before ->> 'media_scan_enqueue_read_failures')::int, 0)
       IS DISTINCT FROM 2
     OR (v_after ->> 'media_scan_enqueue_failures')::int - (v_before ->> 'media_scan_enqueue_failures')::int
       IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed storage.objects read was not counted in identity health (M-1): % -> %', v_before, v_after;
  END IF;
  IF jsonb_array_length(v_due -> 'ids') <> 1 OR (v_due ->> 'count')::int < 2
     OR v_due::text ~ '(w7-contract|5f7b0000|message-media|story-media)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: enqueue failures are not due for an alert, or the alert names an object (M-1): %', v_due;
  END IF;

  -- The alert pair as the webhook run uses it: due, marked, then none due
  -- until the next failure; a failure between the read and the mark stays
  -- due.
  EXECUTE 'SET LOCAL ROLE service_role';
  v_due := public.media_scan_enqueue_alerts_due();
  RESET ROLE;
  IF (v_due ->> 'count')::int < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the per-object enqueue failures (C) are not due for an alert (M-1): %', v_due;
  END IF;
  SELECT array_agg(x::bigint) INTO v_ids FROM jsonb_array_elements_text(v_due -> 'ids') AS x;
  PERFORM private.note_media_scan_enqueue_failure('message-media', 'w7-contract/late.jpg', false);
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_media_scan_enqueue_alerted(v_ids);
  v_due := public.media_scan_enqueue_alerts_due();
  RESET ROLE;
  IF (v_due ->> 'count')::int <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failure after the alert''s read was marked with it, or the marked ones are due again: %', v_due;
  END IF;
  SELECT array_agg(x::bigint) INTO v_ids FROM jsonb_array_elements_text(v_due -> 'ids') AS x;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_media_scan_enqueue_alerted(v_ids);
  v_due := public.media_scan_enqueue_alerts_due();
  RESET ROLE;
  IF (v_due ->> 'count')::int <> 0 OR jsonb_array_length(v_due -> 'ids') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marked enqueue failures were due again: %', v_due;
  END IF;
  IF pg_temp.client_error('authenticated', 'SELECT public.media_scan_enqueue_alerts_due()') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.mark_media_scan_enqueue_alerted(ARRAY[1]::bigint[])') IS DISTINCT FROM '42501'
     OR NOT has_function_privilege('service_role', 'public.media_scan_enqueue_alerts_due()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.mark_media_scan_enqueue_alerted(bigint[])', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.note_media_scan_enqueue_failure(text,text,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the enqueue alert pair has the wrong grants (M-1)';
  END IF;
END $$;

-- =====================================================================
-- N. Server thumbnails of a matched original (final review M-5): the
--    service role writes them (process-chat-media, process-relationship-
--    avatar), so they have no owner. A match of the original queues their
--    deletion with it (quarantined or not: the original stays the
--    evidence); a match of a thumbnail itself names the original's
--    uploader (held) and the original.
-- =====================================================================
DO $$
DECLARE
  v_efua constant uuid := pg_temp.person('05');
  v_kwame constant uuid := pg_temp.person('06');
  v_rel constant uuid := '5f7b0000-0000-0000-0000-0000000000f1';
  v_esc bigint;
BEGIN
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at,
                                    chat_avatar_url, chat_avatar_thumbnail_url)
  VALUES (v_rel, v_efua, v_kwame, 'active', CURRENT_DATE, now(), now(),
          'w7-contract/pair-orig.jpg', 'w7-contract/thumb-pair.thumb');
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content, media_url, media_thumbnail_url, media_type)
  VALUES ('5f7b0000-0000-0000-0000-0000000000f2', v_rel, v_efua, gen_random_uuid(), NULL,
          'w7-contract/chat-orig.jpg', 'chat-thumbnails/w7-contract-1.thumb', 'image'),
         ('5f7b0000-0000-0000-0000-0000000000f3', v_rel, v_kwame, gen_random_uuid(), NULL,
          'w7-contract/chat-orig2.jpg', 'chat-thumbnails/w7-contract-2.thumb', 'image'),
         ('5f7b0000-0000-0000-0000-0000000000f4', v_rel, v_kwame, gen_random_uuid(), NULL,
          'w7-contract/chat-orig3.jpg', 'chat-thumbnails/w7-contract-3.thumb', 'image'),
         ('5f7b0000-0000-0000-0000-0000000000f5', v_rel, v_efua, gen_random_uuid(), NULL,
          'w7-contract/chat-orig4.jpg', 'chat-thumbnails/w7-contract-4.thumb', 'image'),
         -- A prefix sibling of chat-orig.jpg (re-review N-2): same sender.
         ('5f7b0000-0000-0000-0000-0000000000f6', v_rel, v_efua, gen_random_uuid(), NULL,
          'w7-contract/chat-orig.jpg2', 'chat-thumbnails/w7-contract-1b.thumb', 'image'),
         ('5f7b0000-0000-0000-0000-0000000000f7', v_rel, v_efua, gen_random_uuid(), NULL,
          'w7-contract/chat-orig4.jpg2', 'chat-thumbnails/w7-contract-4b.thumb', 'image');
  INSERT INTO public.message_media_upload_intents (relationship_id, requester_id, storage_key, media_type, mime_type, expires_at, used_at)
  VALUES (v_rel, v_efua, 'w7-contract/chat-orig4.jpg', 'image', 'image/jpeg', now() + interval '1 hour', now()),
         (v_rel, v_efua, 'w7-contract/chat-orig4.jpg2', 'image', 'image/jpeg', now() + interval '1 hour', now());
  PERFORM set_config('session_replication_role', 'origin', true);
  PERFORM pg_temp.upload('relationship-avatars', 'pair-orig.jpg', v_kwame, 'image/jpeg');
  PERFORM pg_temp.settle();

  -- The original matched and was quarantined: its thumbnail goes with it.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, true, %L)',
                                 'message-media', 'w7-contract/chat-orig.jpg', v_efua, 'photodna', 'track-n1',
                                 'message-media/w7-contract/chat-orig.jpg/m-n1'));
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                  WHERE bucket_id = 'message-media' AND object_name = 'chat-thumbnails/w7-contract-1.thumb'
                    AND deleted_at IS NULL AND not_before <= now())
     OR (SELECT notes FROM public.safety_escalations WHERE object_name = 'w7-contract/chat-orig.jpg') !~ 'server thumbnail' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a matched original''s server thumbnail was not queued for deletion with it (M-5)';
  END IF;
  -- Exact keys only (re-review N-2): the thumbnail of chat-orig.jpg2 stays.
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue
              WHERE bucket_id = 'message-media' AND object_name = 'chat-thumbnails/w7-contract-1b.thumb') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a near-name sibling''s thumbnail was queued for deletion (N-2)';
  END IF;
  -- Its thumbnail's own scan matches before the drain: the escalation
  -- names the original's uploader, who is already held, and the original.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L, true, %L)',
                                 'message-media', 'chat-thumbnails/w7-contract-1.thumb', 'photodna', 'track-n2',
                                 'message-media/chat-thumbnails/w7-contract-1.thumb/m-n2'));
  SELECT id INTO v_esc FROM public.safety_escalations WHERE object_name = 'chat-thumbnails/w7-contract-1.thumb';
  IF (SELECT user_id FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM v_efua
     OR position('w7-contract/chat-orig.jpg' IN (SELECT notes FROM public.safety_escalations WHERE id = v_esc)) = 0
     OR (SELECT notes FROM public.safety_escalations WHERE id = v_esc) !~ 'already held'
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_efua AND kind = 'safety_review' AND resolved_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server thumbnail''s match escalated without its original''s uploader (M-5)';
  END IF;

  -- A thumbnail matched first (its original not, or not yet): the
  -- original's uploader is held for it.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L, true, %L)',
                                 'message-media', 'chat-thumbnails/w7-contract-2.thumb', 'photodna', 'track-n3',
                                 'message-media/chat-thumbnails/w7-contract-2.thumb/m-n3'));
  SELECT id INTO v_esc FROM public.safety_escalations WHERE object_name = 'chat-thumbnails/w7-contract-2.thumb';
  IF (SELECT user_id FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM v_kwame
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_kwame AND kind = 'safety_review'
          AND resolved_at IS NULL AND reason_ref = 'safety_escalation:' || v_esc) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server thumbnail''s match did not hold its original''s uploader (M-5)';
  END IF;

  -- The original matched but its copy failed: the original is held as the
  -- evidence, its thumbnail (which the partner sees) is still deleted.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'message-media', 'w7-contract/chat-orig3.jpg', v_kwame, 'photodna', 'track-n4'));
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                  WHERE bucket_id = 'message-media' AND object_name = 'chat-thumbnails/w7-contract-3.thumb'
                    AND deleted_at IS NULL AND not_before <= now())
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/chat-orig3.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unquarantined original''s thumbnail was kept, or the original was queued (M-5)';
  END IF;

  -- An original matched with no owner known: its thumbnail is found
  -- through the message's upload intent.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L, true, %L)',
                                 'message-media', 'w7-contract/chat-orig4.jpg', 'photodna', 'track-n4b',
                                 'message-media/w7-contract/chat-orig4.jpg/m-n4b'));
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                  WHERE bucket_id = 'message-media' AND object_name = 'chat-thumbnails/w7-contract-4.thumb'
                    AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ownerless original''s thumbnail was not found through its upload intent (M-5)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue
              WHERE bucket_id = 'message-media' AND object_name = 'chat-thumbnails/w7-contract-4b.thumb') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a near-name sibling''s thumbnail was queued through its intent (N-2)';
  END IF;

  -- The couple's chat picture: the original's match deletes its thumbnail;
  -- the thumbnail's own match names the original's uploader (from the
  -- queue row the upload made).
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, true, %L)',
                                 'relationship-avatars', 'w7-contract/pair-orig.jpg', v_kwame, 'photodna', 'track-n6',
                                 'relationship-avatars/w7-contract/pair-orig.jpg/m-n6'));
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                  WHERE bucket_id = 'relationship-avatars' AND object_name = 'w7-contract/thumb-pair.thumb'
                    AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a matched chat picture''s thumbnail was not queued for deletion (M-5)';
  END IF;
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L, true, %L)',
                                 'relationship-avatars', 'w7-contract/thumb-pair.thumb', 'photodna', 'track-n5',
                                 'relationship-avatars/w7-contract/thumb-pair.thumb/m-n5'));
  IF (SELECT user_id FROM public.safety_escalations WHERE object_name = 'w7-contract/thumb-pair.thumb') IS DISTINCT FROM v_kwame
     OR position('w7-contract/pair-orig.jpg' IN (SELECT notes FROM public.safety_escalations
                                                  WHERE object_name = 'w7-contract/thumb-pair.thumb')) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a chat picture thumbnail''s match did not name its original''s uploader (M-5)';
  END IF;
  -- The lookups only read (nothing may tell anyone).
  IF EXISTS (SELECT 1 FROM pg_proc
              WHERE oid IN ('private.media_derived_objects(text,text,uuid)'::regprocedure,
                            'private.media_derived_from(text,text)'::regprocedure)
                AND (provolatile <> 's' OR prosrc ~* '(notification|push|net\.http|invoke_edge_function)'))
     OR has_function_privilege('service_role', 'private.media_derived_objects(text,text,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.media_derived_from(text,text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.queue_derived_media_deletions(text,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a derived-object lookup writes, reaches out, or is granted (M-5)';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'media_scan_contracts: all held'; END $$;

ROLLBACK;
