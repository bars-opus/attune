-- supabase/migrations/20261024100500_story_day_reads_by_author.sql
--
-- Stories Wave 5 (review 04 #4; Wave 4 deps):
--   * list_story_day_items takes p_author_id, so one author's calendar ring
--     reads only that author's stories instead of paging the whole day. It
--     is LAST with DEFAULT NULL; the 5-argument version is DROPPED (not
--     overloaded) so an old client's call still resolves and PostgREST never
--     sees two candidates (PGRST203).
--   * list_story_day_counts returns unviewed_count per (day, author): the
--     caller's unviewed stories of that author (0 on the caller's own rows),
--     so a day ring is right on a day with more than 50 stories. It reads
--     has_been_viewed, which clients cannot select (20261017140100), so it
--     becomes SECURITY DEFINER. It applies story_items_read_members' rule
--     itself: deleted_at IS NULL, and the same open-relationship rule as
--     story_relationship_is_open_for_me, through the two-argument helper
--     (definers keep calling that one), like the other story reads.
--   * The newest thumbnail per (day, author) is taken in the same pass
--     (array_agg ordered by created_at DESC, id DESC), so the read stays
--     one scan however wide the range (fix round 1: a lateral re-scanning a
--     materialized CTE per group took 127 ms over 365 days).
-- Both pin search_path to ''. Shape changes, so DROP + CREATE in one
-- transaction; grants re-applied.
BEGIN;

DROP FUNCTION IF EXISTS public.list_story_day_items(uuid, date, timestamptz, uuid, int);
-- Re-runnable: drop this migration's own shape too before re-creating it.
DROP FUNCTION IF EXISTS public.list_story_day_items(uuid, date, timestamptz, uuid, int, uuid);

CREATE FUNCTION public.list_story_day_items(
  p_relationship_id   uuid,
  p_occurred_on       date,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50,
  p_author_id         uuid DEFAULT NULL
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (jsonb_populate_record(si, jsonb_build_object(
            'has_been_viewed',
              CASE WHEN si.author_id = auth.uid() THEN (s.v_on AND si.seen_shown)
                   ELSE si.has_been_viewed END,
            'seen_shown', false))).*
    FROM public.story_items si
   CROSS JOIN (SELECT public.seen_receipts_effective(p_relationship_id) AS v_on) s
   WHERE si.relationship_id = p_relationship_id
     AND si.occurred_on = p_occurred_on
     AND (p_author_id IS NULL OR si.author_id = p_author_id)
     AND si.deleted_at IS NULL
     AND public.story_relationship_is_open(si.relationship_id, auth.uid())
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

REVOKE ALL ON FUNCTION public.list_story_day_items(uuid, date, timestamptz, uuid, int, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_items(uuid, date, timestamptz, uuid, int, uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.list_story_day_counts(uuid, date, date);

CREATE FUNCTION public.list_story_day_counts(
  p_relationship_id uuid,
  p_start_on        date,
  p_end_on          date
)
RETURNS TABLE (
  occurred_on          date,
  author_id            uuid,
  item_count           bigint,
  day_item_count       bigint,
  newest_thumbnail_key text,
  newest_created_at    timestamptz,
  unviewed_count       bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH per_author AS (
    SELECT si.occurred_on,
           si.author_id,
           count(*) AS item_count,
           max(si.created_at) AS newest_created_at,
           (array_agg(si.thumbnail_key ORDER BY si.created_at DESC, si.id DESC))[1]
             AS newest_thumbnail_key,
           count(*) FILTER (WHERE si.author_id <> me.id AND NOT si.has_been_viewed)
             AS unviewed_count
      FROM public.story_items si
     CROSS JOIN (SELECT auth.uid() AS id) me
     WHERE si.relationship_id = p_relationship_id
       AND si.occurred_on BETWEEN p_start_on AND p_end_on
       AND si.deleted_at IS NULL
       AND public.story_relationship_is_open(p_relationship_id, me.id)
     GROUP BY si.occurred_on, si.author_id
  )
  SELECT pa.occurred_on,
         pa.author_id,
         pa.item_count,
         (sum(pa.item_count) OVER (PARTITION BY pa.occurred_on))::bigint AS day_item_count,
         pa.newest_thumbnail_key,
         pa.newest_created_at,
         pa.unviewed_count
    FROM per_author pa
   ORDER BY pa.occurred_on, pa.newest_created_at DESC, pa.author_id
$$;

REVOKE ALL ON FUNCTION public.list_story_day_counts(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_counts(uuid, date, date) TO authenticated;

COMMIT;
