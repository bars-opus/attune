-- Stories: private bucket, upload intents, and storage policies.
--
-- Follows supabase/migrations/20260705133000_chat_media_month2.sql's shape
-- (lines 140-175): private bucket, an INSERT policy gated on an
-- unconsumed unexpired intent owned by auth.uid(), and a SELECT policy
-- gated on membership. Two deliberate departures from that precedent,
-- both required by spec §4.2:
--
--   1. No DELETE policy. Chat's message_media_delete_owner_unused_intent
--      lets the owner of an unused intent delete straight from
--      storage.objects. Later media work established that Supabase
--      requires the Storage API for physical deletion, not a direct SQL
--      DELETE against storage.objects -- stories must not copy that
--      part. Cleanup of abandoned uploads is the worker's job (Task 9),
--      via media_deletion_queue and the Storage API.
--   2. No UPDATE policy either -- nothing in this feature ever mutates
--      an already-written object; a changed photo is a new key.
--
-- The intents table is server-readable only, same as chat's
-- message_media_upload_intents: no client ever gets a grant on it, and
-- the storage policy's own EXISTS (not a SECURITY DEFINER function) is
-- what reaches it, exactly like the chat precedent.

-- ---------------------------------------------------------------------
-- Bucket. public = false is the whole point of this migration -- see
-- the contract test.  ON CONFLICT DO UPDATE (rather than DO NOTHING)
-- so re-running this migration -- e.g. after the Step 5 mutation test
-- flips public back to true by hand -- restores the correct value
-- instead of leaving a stale bucket row in place.
-- ---------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('story-media', 'story-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- ---------------------------------------------------------------------
-- Upload intents. Task 4 writes two rows per finalized story (media +
-- thumbnail); Task 5's create_story_item consumes them under FOR
-- UPDATE; Task 9's cleanup job re-arms expired, unused keys for
-- physical deletion and prunes old rows.
--
-- media_role names which half of the pair this is ('media' vs
-- 'thumbnail'), matching story_items' media_key/thumbnail_key split.
-- max_bytes is stored per-intent rather than derived from media_role at
-- check time, so create_story_item can enforce the §4.2 object-limits
-- table (5MB image / 25MB video / 800KB thumbnail) against whichever
-- ceiling this specific intent was issued under, without the
-- storage-policy layer needing to know those numbers at all.
-- ---------------------------------------------------------------------
CREATE TABLE public.story_media_upload_intents (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  requested_by      uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,
  media_role        text NOT NULL CHECK (media_role IN ('media', 'thumbnail')),
  storage_key       text NOT NULL UNIQUE,
  mime_type         text NOT NULL,
  max_bytes         bigint NOT NULL CHECK (max_bytes > 0),
  expires_at        timestamptz NOT NULL,
  used_at           timestamptz,
  cleanup_queued_at timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_story_media_upload_intents_lookup
  ON public.story_media_upload_intents (requested_by, relationship_id, expires_at DESC);

-- Supports Task 9's hourly sweep: unused, expired, not yet queued.
CREATE INDEX idx_story_media_upload_intents_cleanup
  ON public.story_media_upload_intents (expires_at)
  WHERE used_at IS NULL AND cleanup_queued_at IS NULL;

ALTER TABLE public.story_media_upload_intents ENABLE ROW LEVEL SECURITY;

-- No policy is created. RLS on with no policy denies all rows to every
-- role, matching story_views' contract elsewhere in this feature. The
-- table is reached only by the storage policies' own EXISTS below and
-- by Task 4/5/9's SECURITY DEFINER functions, never by a client query.
REVOKE ALL ON public.story_media_upload_intents FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Storage policies.
-- ---------------------------------------------------------------------

-- INSERT: permits exactly the unconsumed, unexpired key owned by the
-- caller. Uploads use upsert: false client-side; this policy does not
-- need to re-enforce that since Storage rejects an INSERT onto an
-- existing key on its own when upsert is false.
DROP POLICY IF EXISTS story_media_insert_by_intent ON storage.objects;
CREATE POLICY story_media_insert_by_intent
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'story-media'
  AND EXISTS (
    SELECT 1
    FROM public.story_media_upload_intents intent
    WHERE intent.storage_key = name
      AND intent.requested_by = auth.uid()
      AND intent.used_at IS NULL
      AND intent.expires_at > now()
  )
);

-- SELECT: either the key belongs to a live (deleted_at IS NULL) story
-- in a relationship that's still open per story_relationship_is_open
-- (spec §4.1's read authorization), OR the key belongs to an
-- unconsumed intent owned by the caller -- so a client can verify its
-- own upload landed before calling create_story_item to finalize it.
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
    OR EXISTS (
      SELECT 1
      FROM public.story_media_upload_intents intent
      WHERE intent.storage_key = name
        AND intent.requested_by = auth.uid()
        AND intent.used_at IS NULL
    )
  )
);

-- No UPDATE or DELETE policy on storage.objects for this bucket, by
-- design: physical deletion is the worker's job via the Storage API and
-- media_deletion_queue (Task 9), not a direct SQL policy grant.
