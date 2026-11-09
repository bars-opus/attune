-- supabase/tests/storage_bucket_policies.sql
-- Spec 2 §4.5, §7.1 (I-10, F-1): the Dating buckets are private, their
-- storage.objects policies are exactly the listed ones, no trigger on
-- storage.objects is Dating's, and dating-profile-photos is not in Spec 1's
-- scan-trigger bucket list (each Dating photo is scanned once, inline, by
-- process-dating-photo). W4a adds dating-verification-review.
-- Because a policy can reach a bucket without naming it (bucket_id LIKE
-- 'dating%', USING (true), owner = auth.uid()), every permissive
-- storage.objects policy must also open with one bucket literal as a
-- top-level AND term (USING and WITH CHECK alike), and a seeded photo
-- object is checked to be invisible to anon and to a signed-in stranger.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/storage_bucket_policies.sql
BEGIN;

DO $$
DECLARE
  v_bucket text;
  v_got text;
  v_want constant jsonb := jsonb_build_object(
    'dating-profile-photos',
    'dating_profile_photos_insert_by_intent:INSERT:{authenticated};dating_profile_photos_select_owner:SELECT:{authenticated}');
BEGIN
  FOR v_bucket IN SELECT jsonb_object_keys(v_want) LOOP
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = v_bucket) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: bucket % does not exist', v_bucket;
    END IF;
    IF (SELECT public FROM storage.buckets WHERE id = v_bucket) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: bucket % is public', v_bucket;
    END IF;
    SELECT string_agg(p.policyname || ':' || p.cmd || ':' || p.roles::text, ';' ORDER BY p.policyname) INTO v_got
      FROM pg_policies AS p
     WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
       AND (coalesce(p.qual, '') || coalesce(p.with_check, '')) LIKE '%' || quote_literal(v_bucket) || '%';
    IF v_got IS DISTINCT FROM v_want ->> v_bucket THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % policies are [%], expected [%]', v_bucket, v_got, v_want ->> v_bucket;
    END IF;
  END LOOP;

  -- W1 final fix (M-5 p1): each listed Dating policy's expressions are
  -- pinned too (md5 of USING || '|' || WITH CHECK, as deparsed), so a policy
  -- weakened under the same name (WITH CHECK (bucket_id = ... AND true))
  -- fails here. A deliberate policy change updates its hash in the same
  -- migration's batch.
  SELECT string_agg(p.policyname || '=' || md5(coalesce(p.qual, '') || '|' || coalesce(p.with_check, '')), ';' ORDER BY p.policyname)
    INTO v_got
    FROM pg_policies AS p
   WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
     AND p.policyname IN ('dating_profile_photos_insert_by_intent', 'dating_profile_photos_select_owner');
  -- Spec 2 W3c (R-2): both policies call definer predicates now.
  IF v_got IS DISTINCT FROM 'dating_profile_photos_insert_by_intent=9d7dc3110cf2de1a35eb71135348cca5;'
                            'dating_profile_photos_select_owner=91e5256f5bc6ddfba83d30e571585244' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating storage policy''s expression changed: %', v_got;
  END IF;
  -- Spec 2 W3c fix round 1 (M-3): the policies call definer predicates, so
  -- a predicate weakened under the same name changes no policy hash: the
  -- two predicates' bodies, definer flag and settings are pinned too.
  SELECT string_agg(p.proname || '=' || md5(p.prosrc || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ','), '')),
                    ';' ORDER BY p.proname)
    INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname IN ('dating_storage_intent_open', 'dating_storage_owns');
  IF v_got IS DISTINCT FROM 'dating_storage_intent_open=e06c835fdb2d5569b475e782c3052437;'
                            'dating_storage_owns=2c9a38d7244b6e2211bdcb298f1262e0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating storage predicate changed: %', v_got;
  END IF;

  -- I-2: the shape of every permissive policy on storage.objects. The
  -- deparsed expression of "bucket_id = 'x' AND ..." starts with exactly
  -- "((bucket_id = 'x'::text) AND " (or is "(bucket_id = 'x'::text)");
  -- an OR at the top, a pattern match or no bucket term at all does not.
  SELECT string_agg(p.policyname, ', ' ORDER BY p.policyname) INTO v_got
    FROM pg_policies AS p
   WHERE p.schemaname = 'storage' AND p.tablename = 'objects' AND p.permissive = 'PERMISSIVE'
     AND (coalesce(p.qual IS NOT NULL
                   AND p.qual !~ '^(\(bucket_id = ''[a-z0-9-]+''::text\)|\(\(bucket_id = ''[a-z0-9-]+''::text\) AND .*\))$', true)
          OR coalesce(p.with_check IS NOT NULL
                   AND p.with_check !~ '^(\(bucket_id = ''[a-z0-9-]+''::text\)|\(\(bucket_id = ''[a-z0-9-]+''::text\) AND .*\))$', true)
          OR (p.qual IS NULL AND p.with_check IS NULL));
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: storage.objects policies not scoped to one bucket literal: %', v_got;
  END IF;

  SELECT string_agg(t.tgname, ', ') INTO v_got
    FROM pg_trigger AS t JOIN pg_proc AS f ON f.oid = t.tgfoid
   WHERE t.tgrelid = 'storage.objects'::regclass AND NOT t.tgisinternal
     AND (t.tgname ~* 'dating' OR f.proname ~* 'dating' OR f.prosrc ~ 'dating-');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: storage.objects has a Dating trigger (F-1): %', v_got;
  END IF;

  IF to_regprocedure('private.media_scan_buckets()') IS NOT NULL
     AND 'dating-profile-photos' = ANY (private.media_scan_buckets()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating-profile-photos is in the scan-trigger bucket list (I-10: inline only)';
  END IF;
END $$;

-- I-2, the effect: a Dating photo object (unrelated owner, no photo row)
-- is invisible to anon and to a signed-in stranger. Storage's own setup
-- (RLS on, the API roles' SELECT) is emulated here for the local harness,
-- whose storage.objects is a stub; on a Supabase stack both already hold.
-- Undone by this file's ROLLBACK.
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON storage.objects TO anon, authenticated;
INSERT INTO storage.objects (bucket_id, name, owner)
VALUES ('dating-profile-photos', 'spec2-w1-bucket-probe/photo.jpg', '5e2a0000-0000-0000-0000-0000000000f1');

DO $$
DECLARE
  v_role text;
  v_n integer;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    EXECUTE format('SET LOCAL ROLE %I', v_role);
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', '5e2a0000-0000-0000-0000-0000000000f2', 'role', v_role)::text, true);
    PERFORM set_config('request.jwt.claim.sub', '5e2a0000-0000-0000-0000-0000000000f2', true);
    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'dating-profile-photos';
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    IF v_n IS DISTINCT FROM 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % can see % dating-profile-photos object(s) it does not own', v_role, v_n;
    END IF;
  END LOOP;
END $$;

DO $$ BEGIN RAISE NOTICE 'storage_bucket_policies: all held'; END $$;
ROLLBACK;
