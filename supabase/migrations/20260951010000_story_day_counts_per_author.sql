-- ---------------------------------------------------------------------
-- list_story_day_counts: add per-author breakdown for the calendar.
--
-- The original (20260938080000) returned only (occurred_on, item_count),
-- which is enough to say "this date has stories" but NOT enough to draw
-- the calendar's per-author story avatars: a date where both partners
-- posted must show one thumbnail per author, and a thumbnail needs both
-- the author id and that author's newest thumbnail_key for the day.
--
-- Superseded here rather than by editing the original migration (this
-- repo's convention: migration history is append-only).
--
-- DROP before CREATE, not CREATE OR REPLACE: Postgres refuses to
-- replace a function whose RETURNS TABLE shape changes
-- ("cannot change return type of existing function", SQLSTATE 42P13),
-- and this migration's whole purpose is changing that shape. The
-- argument signature is unchanged — (uuid, date, date) — so the DROP
-- targets it exactly. Dropping also discards the original's
-- REVOKE/GRANT, which is why they are re-applied at the bottom; they
-- are not optional boilerplate here.
--
-- Shape change: one row per (occurred_on, author_id) instead of one row
-- per occurred_on. `item_count` is now that AUTHOR's count for the day,
-- and `day_item_count` carries the whole day's total so a caller that
-- only wants "N stories on this date" does not have to re-sum client
-- side. Callers that previously read (occurred_on, item_count) must now
-- aggregate — StoryDayCount.fromRow and storyDayCountsProvider are
-- updated in the same change.
--
-- Like the original, this INCLUDES expired items (expiry hides an item
-- from the reel, it does not remove it from the couple's calendar —
-- stories spec §1/§3.2) and excludes soft-deleted ones. Deletion
-- filtering is left to RLS/the `story_items_read_members` policy exactly
-- as the original did: no `deleted_at` predicate is added here, since
-- duplicating it would risk drifting from that policy.
--
-- Still SECURITY INVOKER and still bounded by [p_start_on, p_end_on] —
-- an unbounded group-by over all history is the exact failure mode
-- stories spec §5.5 calls out.
-- ---------------------------------------------------------------------
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
  newest_created_at    timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH per_author AS (
    SELECT
      si.occurred_on,
      si.author_id,
      count(*) AS item_count,
      max(si.created_at) AS newest_created_at
    FROM public.story_items si
    WHERE si.relationship_id = p_relationship_id
      AND si.occurred_on BETWEEN p_start_on AND p_end_on
    GROUP BY si.occurred_on, si.author_id
  )
  SELECT
    pa.occurred_on,
    pa.author_id,
    pa.item_count,
    sum(pa.item_count) OVER (PARTITION BY pa.occurred_on) AS day_item_count,
    -- That author's newest item for the day supplies the thumbnail the
    -- calendar avatar renders, matching get_story_ring_summary's own
    -- "newest item fills the circle" rule (§5.1). DISTINCT ON over the
    -- same (occurred_on, author_id) grouping key picks exactly one row.
    newest.thumbnail_key AS newest_thumbnail_key,
    pa.newest_created_at
  FROM per_author pa
  LEFT JOIN LATERAL (
    SELECT si2.thumbnail_key
      FROM public.story_items si2
     WHERE si2.relationship_id = p_relationship_id
       AND si2.occurred_on = pa.occurred_on
       AND si2.author_id = pa.author_id
     ORDER BY si2.created_at DESC, si2.id DESC
     LIMIT 1
  ) AS newest ON true
  ORDER BY pa.occurred_on, pa.newest_created_at DESC, pa.author_id
$$;

REVOKE ALL ON FUNCTION public.list_story_day_counts(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_counts(uuid, date, date)
  TO authenticated;
