-- Stories: the four read RPCs (spec §5.5).
--
-- All four are SECURITY INVOKER. That is the entire security design of
-- this file: they run as the calling `authenticated` role, so every
-- SELECT against story_items is filtered by story_items_read_members
-- (20260938020000) -- deleted_at IS NULL AND
-- story_relationship_is_open(relationship_id, auth.uid()) -- exactly as
-- it is for any other client query. None of these functions re-checks
-- membership, re-checks relationship status, or re-checks deleted_at
-- itself (except list_active_story_items' own expiry filter, which is
-- a DIFFERENT predicate than RLS's, see below). Doing so would be a
-- second, divergence-prone copy of the one the policy already owns --
-- exactly what §5.5 says these RPCs must not do. If the policy is ever
-- wrong, every other story reader breaks the same way, which is a
-- feature: one place to fix, one place to audit.
--
-- The one security-relevant thing INSIDE these functions is the
-- p_limit cap: `LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)`, applied
-- to both paginated reads so a modified client asking for 1000 rows in
-- one call still gets at most 50. This is a resource control, not an
-- authorization one -- RLS still gates WHICH rows, this only gates HOW
-- MANY per call.
--
-- Keyset, never offset: both paginated reads take
-- (p_after_created_at, p_after_id) and filter
-- `(created_at, id) > (p_after_created_at, p_after_id)` using row
-- comparison, ordered ascending on the same tuple. A NULL cursor (first
-- page) is handled by treating "no cursor" as "no lower bound" rather
-- than comparing against NULL, which would evaluate to NULL and match
-- nothing. This is what makes an INSERT during viewing APPEND rather
-- than shift already-seen rows: an offset-based page 2 is defined by
-- position (skip N), which a new row occurring before that position
-- would corrupt (an item skipped or re-shown); a keyset page 2 is
-- defined by VALUE (after this tuple), which a new row cannot corrupt
-- no matter where it lands.

-- ---------------------------------------------------------------------
-- list_active_story_items: one author's reel, oldest first.
-- Excludes expires_at <= now() -- this is the reel; expired items have
-- left it. RLS's own deleted_at IS NULL still applies via the policy.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_active_story_items(
  p_relationship_id   uuid,
  p_author_id         uuid,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT si.*
    FROM public.story_items si
   WHERE si.relationship_id = p_relationship_id
     AND si.author_id = p_author_id
     AND si.expires_at > now()
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

REVOKE ALL ON FUNCTION public.list_active_story_items(
  uuid, uuid, timestamptz, uuid, int
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_active_story_items(
  uuid, uuid, timestamptz, uuid, int
) TO authenticated;

-- ---------------------------------------------------------------------
-- list_story_day_items: one calendar day, oldest first, forever.
-- INCLUDES expired items -- the same row that just left the reel above
-- stays readable from its calendar day, which is the entire point of
-- expiry hiding rather than deleting (§3.2). Only deleted_at IS NULL
-- (via RLS) and occurred_on = p_occurred_on gate it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_story_day_items(
  p_relationship_id   uuid,
  p_occurred_on       date,
  p_after_created_at  timestamptz DEFAULT NULL,
  p_after_id          uuid DEFAULT NULL,
  p_limit             int DEFAULT 50
)
RETURNS SETOF public.story_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT si.*
    FROM public.story_items si
   WHERE si.relationship_id = p_relationship_id
     AND si.occurred_on = p_occurred_on
     AND (
       p_after_created_at IS NULL
       OR (si.created_at, si.id) > (p_after_created_at, p_after_id)
     )
   ORDER BY si.created_at ASC, si.id ASC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 50)
$$;

REVOKE ALL ON FUNCTION public.list_story_day_items(
  uuid, date, timestamptz, uuid, int
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_items(
  uuid, date, timestamptz, uuid, int
) TO authenticated;

-- ---------------------------------------------------------------------
-- list_story_day_counts: one row per occurred_on, bounded by range.
-- Backs the calendar's month view -- never an unbounded group-by over
-- all history (§5.5's "does not fetch an unlimited relationship
-- history and group it in memory" is exactly the failure mode a
-- missing [p_start_on, p_end_on] bound would reproduce server-side).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_story_day_counts(
  p_relationship_id uuid,
  p_start_on        date,
  p_end_on          date
)
RETURNS TABLE (occurred_on date, item_count bigint)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT si.occurred_on, count(*) AS item_count
    FROM public.story_items si
   WHERE si.relationship_id = p_relationship_id
     AND si.occurred_on BETWEEN p_start_on AND p_end_on
   GROUP BY si.occurred_on
   ORDER BY si.occurred_on
$$;

REVOKE ALL ON FUNCTION public.list_story_day_counts(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_story_day_counts(uuid, date, date)
  TO authenticated;

-- ---------------------------------------------------------------------
-- get_story_ring_summary: one row per author with an active story.
--
-- active_count: how many of that author's items are still in the reel
-- (expires_at > now()); the ring's segment count, capped client-side at
-- 12 arcs (§8).
-- newest_thumbnail_key: that author's most recent active item's
-- thumbnail -- what the ring renders (§5.1).
-- unviewed_count: EXCLUDES the caller's own stories. has_been_viewed on
-- YOUR OWN story means "my partner saw it," not "I saw it" -- counting
-- your own unviewed items here would make your own ring bright forever,
-- since the author never marks their own story viewed (mark_story_viewed
-- refuses the author, 20260938060000). So unviewed_count is 0 for the
-- caller's own row by construction (the CASE below), and for the
-- partner's row it counts their un-viewed active items -- the number
-- that actually drives "does my partner have something new for me."
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_story_ring_summary(
  p_relationship_id uuid
)
RETURNS TABLE (
  author_id             uuid,
  active_count          bigint,
  unviewed_count        bigint,
  newest_thumbnail_key  text,
  newest_created_at     timestamptz
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    si.author_id,
    count(*) AS active_count,
    count(*) FILTER (
      WHERE si.author_id <> auth.uid() AND NOT si.has_been_viewed
    ) AS unviewed_count,
    (array_agg(si.thumbnail_key ORDER BY si.created_at DESC))[1]
      AS newest_thumbnail_key,
    max(si.created_at) AS newest_created_at
  FROM public.story_items si
 WHERE si.relationship_id = p_relationship_id
   AND si.expires_at > now()
 GROUP BY si.author_id
$$;

REVOKE ALL ON FUNCTION public.get_story_ring_summary(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_story_ring_summary(uuid)
  TO authenticated;
