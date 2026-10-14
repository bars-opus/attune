-- Private photos for the Reflection Journal (spec 2026-10-14 §4.4).
-- Paths are "<user_id>/<entry_id>/<file>.jpg": only the owner may write,
-- only into one of their own live entries; only the owner may read.
INSERT INTO storage.buckets (id, name, public) VALUES ('journal-media', 'journal-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets SET file_size_limit = 10485760, allowed_mime_types = ARRAY['image/jpeg']
               WHERE id = 'journal-media'$q$;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.journal_storage_can_write(p_name text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_name IS NULL OR p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$' THEN RETURN false; END IF;
  RETURN split_part(p_name, '/', 1) = auth.uid()::text
     AND EXISTS (SELECT 1 FROM public.reflection_journal_entries
                  WHERE id = split_part(p_name, '/', 2)::uuid AND user_id = auth.uid() AND deleted_at IS NULL);
END $$;

CREATE OR REPLACE FUNCTION public.journal_storage_can_read(p_name text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_name IS NOT NULL AND split_part(p_name, '/', 1) = auth.uid()::text
$$;

REVOKE ALL ON FUNCTION public.journal_storage_can_write(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.journal_storage_can_read(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.journal_storage_can_write(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.journal_storage_can_read(text) TO authenticated;

DROP POLICY IF EXISTS journal_media_insert ON storage.objects;
CREATE POLICY journal_media_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'journal-media' AND public.journal_storage_can_write(name));
DROP POLICY IF EXISTS journal_media_select ON storage.objects;
CREATE POLICY journal_media_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'journal-media' AND public.journal_storage_can_read(name));
