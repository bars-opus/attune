-- supabase/migrations/20261024100100_story_media_bucket_limits.sql
--
-- Stories Wave 5 (review 05 #5, 01 #17; checklist P0-U 2.5): a size and type
-- ceiling on the story-media bucket itself, so Storage refuses an oversize
-- or foreign object at upload instead of holding it until the hourly intent
-- sweep. 25 MB is the largest per-intent ceiling (media/video in
-- story_intent_max_bytes); create_story_item_core still enforces the 5 MB
-- and 800 KB tiers. The archival worker's renditions are image/jpeg.
-- Guarded like 20261014200000_journal_media_bucket.sql: the local harness's
-- storage.buckets has no limit columns. Idempotent; no transaction needed.
INSERT INTO storage.buckets (id, name, public) VALUES ('story-media', 'story-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets
               SET file_size_limit = 26214400,
                   allowed_mime_types = ARRAY['image/jpeg', 'video/mp4']
               WHERE id = 'story-media'$q$;
  END IF;
END $$;
