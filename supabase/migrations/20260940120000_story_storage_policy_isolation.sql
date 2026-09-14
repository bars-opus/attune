-- Keep story-media's private intent table out of storage.objects policies.
--
-- story_media_upload_intents intentionally has no client table grants. The
-- original storage policies nevertheless selected it directly. PostgreSQL is
-- free to evaluate that subquery while planning/checking an unrelated bucket,
-- so signing a message-media or relationship-avatars object failed with 42501
-- (`permission denied for table story_media_upload_intents`).
--
-- A narrowly-scoped SECURITY DEFINER predicate preserves the zero-table-grant
-- contract while exposing only the one boolean Storage needs for the current
-- caller and exact object key.

CREATE OR REPLACE FUNCTION public.story_media_intent_is_active(
  p_storage_key text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.story_media_upload_intents intent
     WHERE intent.storage_key = p_storage_key
       AND intent.requester_id = auth.uid()
       AND intent.used_at IS NULL
       AND intent.expires_at > now()
  );
$$;

REVOKE ALL ON FUNCTION public.story_media_intent_is_active(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_media_intent_is_active(text)
  TO authenticated;

DROP POLICY IF EXISTS story_media_insert_by_intent ON storage.objects;
CREATE POLICY story_media_insert_by_intent
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'story-media'
  AND public.story_media_intent_is_active(name)
);

DROP POLICY IF EXISTS story_media_select_authorized ON storage.objects;
CREATE POLICY story_media_select_authorized
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'story-media'
  AND (
    EXISTS (
      SELECT 1
        FROM public.story_items si
       WHERE (si.media_key = name OR si.thumbnail_key = name)
         AND si.deleted_at IS NULL
         AND public.story_relationship_is_open(si.relationship_id, auth.uid())
    )
    OR public.story_media_intent_is_active(name)
  )
);
