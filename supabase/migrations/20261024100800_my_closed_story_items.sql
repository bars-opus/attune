-- supabase/migrations/20261024100800_my_closed_story_items.sql
--
-- Stories Wave 5 (review 05 #3; STORIES.md §3.3, §8): delete_story_item has
-- always let an author delete after an ending, but every reader requires an
-- open relationship, so after an ending nobody could find their own stories
-- to delete them. These three functions show an author their OWN stories in
-- spaces that are closed for stories (paused, ended, archived) and delete
-- them, in batches, through delete_story_item (same tombstone, same
-- three-key Storage enqueue). Dates and kinds only: Storage stays closed at
-- an ending, so there are no thumbnails. A space the caller is not in, or
-- that does not exist, lists nothing and deletes nothing.
--
-- can_download says whether the chapter is still in "Download my data"
-- (relationship_chat_open_for: ended under 30 days ago, not sealed by me,
-- not archived), so the delete confirm never offers a copy that cannot be
-- made.
--
-- Idempotent: DROP IF EXISTS + CREATE for the chapter list (its return type
-- grew a column), CREATE OR REPLACE for the rest, and REVOKE/GRANT, all in
-- one transaction so the functions never exist without their grants.
BEGIN;

DROP FUNCTION IF EXISTS public.list_my_closed_story_chapters();

CREATE FUNCTION public.list_my_closed_story_chapters()
RETURNS TABLE (
  relationship_id uuid,
  status          text,
  ended_at        timestamptz,
  story_count     bigint,
  first_on        date,
  last_on         date,
  can_download    boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.id, r.status, r.ended_at, count(*), min(si.occurred_on), max(si.occurred_on),
         public.relationship_chat_open_for(r.id, auth.uid())
    FROM public.story_items si
    JOIN public.relationships r ON r.id = si.relationship_id
   WHERE auth.uid() IS NOT NULL
     AND si.author_id = auth.uid()
     AND si.deleted_at IS NULL
     AND NOT public.story_relationship_is_open(r.id, auth.uid())
   GROUP BY r.id, r.status, r.ended_at
   ORDER BY r.ended_at DESC NULLS FIRST, r.id
$$;

CREATE OR REPLACE FUNCTION public.list_my_closed_story_items(
  p_relationship_id  uuid,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_id         uuid DEFAULT NULL,
  p_limit            int DEFAULT 50
)
RETURNS TABLE (
  id          uuid,
  media_type  text,
  occurred_on date,
  created_at  timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT si.id, si.media_type, si.occurred_on, si.created_at
    FROM public.story_items si
   WHERE auth.uid() IS NOT NULL
     AND si.relationship_id = p_relationship_id
     AND si.author_id = auth.uid()
     AND si.deleted_at IS NULL
     AND NOT public.story_relationship_is_open(p_relationship_id, auth.uid())
     AND (p_after_created_at IS NULL OR (si.created_at, si.id) > (p_after_created_at, p_after_id))
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

CREATE OR REPLACE FUNCTION public.delete_my_closed_story_items(p_relationship_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_id uuid;
  v_ids uuid[];
  v_res jsonb;
  v_deleted int := 0;
  v_left bigint;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;
  IF p_relationship_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;
  -- An open space's stories are deleted from the calendar, one by one.
  IF public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Lock the whole batch first, skipping rows another delete holds. Locking
  -- one story at a time inside the loop would hold story_change_signals
  -- (taken by the first delete_story_item) while waiting on a story row that
  -- a single delete from my other device has locked and that is itself
  -- waiting for the signal row: a deadlock. A skipped row is counted in
  -- "remaining" and the next call picks it up.
  SELECT array_agg(b.id ORDER BY b.created_at, b.id) INTO v_ids
    FROM (
      SELECT si.id, si.created_at
        FROM public.story_items si
       WHERE si.relationship_id = p_relationship_id
         AND si.author_id = v_user
         AND si.deleted_at IS NULL
       ORDER BY si.created_at, si.id
       LIMIT 200
         FOR UPDATE SKIP LOCKED
    ) b;

  FOREACH v_id IN ARRAY coalesce(v_ids, '{}'::uuid[])
  LOOP
    v_res := public.delete_story_item(v_id);
    IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
      v_deleted := v_deleted + 1;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_left
    FROM public.story_items si
   WHERE si.relationship_id = p_relationship_id
     AND si.author_id = v_user
     AND si.deleted_at IS NULL;

  RETURN jsonb_build_object('error', false, 'deleted', v_deleted, 'remaining', v_left);
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_closed_story_chapters() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_closed_story_items(uuid, timestamptz, uuid, int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_my_closed_story_items(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_closed_story_chapters() TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_closed_story_items(uuid, timestamptz, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_closed_story_items(uuid) TO authenticated;

COMMIT;
