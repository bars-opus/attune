-- supabase/migrations/20261024100400_story_ring_index.sql
--
-- Stories Wave 5 (review 03 L7): get_story_ring_summary filters
-- expires_at > now(), but no index led on (relationship_id, expires_at), so
-- every ring refresh range-scanned the relationship's whole history. Plain
-- CREATE INDEX (story_items is small enough that the lock is brief);
-- IF NOT EXISTS keeps it idempotent.
-- lock_timeout: the build needs a SHARE lock, so behind a long transaction
-- on story_items (an export or archival run) it would queue, and every
-- story write would queue behind it. Fail fast instead; re-run the deploy.
SET lock_timeout = '5s';
CREATE INDEX IF NOT EXISTS idx_story_items_active
  ON public.story_items (relationship_id, expires_at)
  WHERE deleted_at IS NULL;
RESET lock_timeout;
