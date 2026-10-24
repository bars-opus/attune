-- supabase/migrations/20261024100200_story_membership_for_me.sql
--
-- Stories Wave 5 (review 05 #4): story_relationship_is_open(rel, user) was
-- granted to authenticated for its RLS callers, so anyone holding two uuids
-- could ask whether that pairing is open. The policies now call a helper
-- that answers only for auth.uid(); the two-argument helper becomes
-- server-only (every function calling it is SECURITY DEFINER and runs as the
-- owner). One transaction, so no policy is ever missing.
BEGIN;

-- Each policy swap takes an ACCESS EXCLUSIVE lock on its table, and
-- storage.objects is the busiest table in the project: give up rather than
-- queue every Storage request behind a long reader. On a timeout the whole
-- file rolls back; re-run the push.
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.story_relationship_is_open(
  p_relationship_id uuid,
  p_user uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
     WHERE r.id = p_relationship_id
       AND r.status = 'active'
       AND r.chat_archived_at IS NULL
       AND (r.user_a = p_user OR r.user_b = p_user)
  );
$$;

CREATE OR REPLACE FUNCTION public.story_relationship_is_open_for_me(
  p_relationship_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- The predicate itself, not a call to the two-argument helper: a nested
  -- SECURITY DEFINER call cannot be inlined and costs 4-7x per row on every
  -- invoker story read (batch 2 review #1). Keep in step with
  -- story_relationship_is_open above; story_membership_contracts M4 pins
  -- the two to the same answer.
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
     WHERE r.id = p_relationship_id
       AND r.status = 'active'
       AND r.chat_archived_at IS NULL
       AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
  );
$$;

REVOKE ALL ON FUNCTION public.story_relationship_is_open_for_me(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_relationship_is_open_for_me(uuid) TO authenticated;

DROP POLICY IF EXISTS story_items_read_members ON public.story_items;
CREATE POLICY story_items_read_members ON public.story_items
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND public.story_relationship_is_open_for_me(relationship_id)
  );

DROP POLICY IF EXISTS story_signals_read_members ON public.story_change_signals;
CREATE POLICY story_signals_read_members ON public.story_change_signals
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open_for_me(relationship_id));

DROP POLICY IF EXISTS story_places_read_members ON public.story_places;
CREATE POLICY story_places_read_members ON public.story_places
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open_for_me(relationship_id));

-- Same predicate as 20260940120000, helper swapped.
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
         AND public.story_relationship_is_open_for_me(si.relationship_id)
    )
    OR public.story_media_intent_is_active(name)
  )
);

REVOKE EXECUTE ON FUNCTION public.story_relationship_is_open(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

COMMIT;
