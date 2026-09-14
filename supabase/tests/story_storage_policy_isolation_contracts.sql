-- A story-media policy must never break reads from another Storage bucket.
--
-- PostgreSQL may plan/evaluate every SELECT policy attached to
-- storage.objects before proving that its bucket predicate is false. A policy
-- that directly reads a private helper table therefore turns an unrelated
-- signed-URL request into a 42501 error.

BEGIN;

DO $$
DECLARE
  v_policy record;
BEGIN
  FOR v_policy IN
    SELECT policyname, coalesce(qual, '') || coalesce(with_check, '') AS body
      FROM pg_policies
     WHERE schemaname = 'storage'
       AND tablename = 'objects'
       AND policyname IN (
         'story_media_insert_by_intent',
         'story_media_select_authorized'
       )
  LOOP
    IF v_policy.body LIKE '%story_media_upload_intents%' THEN
      RAISE EXCEPTION
        'story storage policy % directly reads its private intent table',
        v_policy.policyname;
    END IF;
  END LOOP;
END
$$;

-- Supabase Storage supplies this platform-side privilege in production. The
-- lightweight local harness intentionally does not emulate Storage's full
-- grant setup, so add it transaction-locally before exercising RLS.
GRANT SELECT ON storage.objects TO authenticated;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-00000000b201',
  true
);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

DO $$
DECLARE
  v_count bigint;
BEGIN
  BEGIN
    SELECT count(*)
      INTO v_count
      FROM storage.objects
     WHERE bucket_id IN ('message-media', 'relationship-avatars');
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE EXCEPTION
        'story storage policy blocked another bucket: %', SQLERRM;
  END;
END
$$;

ROLLBACK;
