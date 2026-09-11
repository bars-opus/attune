-- Membership, in one place.
--
-- SECURITY DEFINER so a storage policy can call it without granting
-- clients SELECT on the tables it reads. ACTIVE and unarchived, matching
-- the chat-media precedent rather than the laxer timeline one: stories
-- are personal media, and access ends when the relationship does.
CREATE OR REPLACE FUNCTION public.story_relationship_is_open(
  p_relationship_id uuid,
  p_user uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
     WHERE r.id = p_relationship_id
       AND r.status = 'active'
       AND r.chat_archived_at IS NULL
       AND (r.user_a = p_user OR r.user_b = p_user)
  );
$$;

REVOKE ALL ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  TO authenticated;

ALTER TABLE public.story_items          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_views          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.story_change_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY story_items_read_members ON public.story_items
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND public.story_relationship_is_open(relationship_id, auth.uid())
  );

-- No INSERT, UPDATE or DELETE policy exists, by design (§3.3).

CREATE POLICY story_signals_read_members ON public.story_change_signals
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open(relationship_id, auth.uid()));

-- story_views gets NO policy at all: RLS on with no policy denies
-- everything, which is exactly the contract (§3.4).

-- Table-level REVOKE/GRANT for these three tables (plus
-- story_media_upload_intents from 20260938030000) lives in
-- 20260938100000_stories_table_grants.sql, not here. That migration is
-- also \i-sourced by scripts/local_pg_grants.sql AFTER the local
-- harness's blanket "GRANT ... ON ALL TABLES ... TO authenticated" runs,
-- so the same statements serve as both the real privilege and the local
-- harness's re-assertion of it -- one source of truth, matching the
-- game/word-hunt table-grants precedent. Keeping it here instead would
-- let the harness's blanket grant silently re-open these tables on every
-- rebuild while still passing here, exactly the failure mode those two
-- precedents exist to prevent.
