-- supabase/migrations/20261024100410_story_ring_summary_expiry.sql
--
-- Stories Wave 5 (review 03 M2; Wave 4 M-6): the ring summary returns each
-- author's soonest expiry (next_expires_at) and the server's clock
-- (server_now), so the client re-reads exactly when a story leaves the ring,
-- on the server's clock rather than the phone's. The Wave 4 client already
-- parses next_expires_at; it reads server_now from this release.
-- The RETURNS TABLE shape changes, so DROP + CREATE in one transaction, and
-- the grants are re-applied. Otherwise identical to 20261017140000, with
-- search_path pinned to ''.
BEGIN;

DROP FUNCTION IF EXISTS public.get_story_ring_summary(uuid);

CREATE FUNCTION public.get_story_ring_summary(
  p_relationship_id uuid
)
RETURNS TABLE (
  author_id             uuid,
  active_count          bigint,
  unviewed_count        bigint,
  newest_thumbnail_key  text,
  newest_created_at     timestamptz,
  next_expires_at       timestamptz,
  server_now            timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    si.author_id,
    count(*) AS active_count,
    count(*) FILTER (
      WHERE si.author_id <> auth.uid() AND NOT si.has_been_viewed
    ) AS unviewed_count,
    (array_agg(si.thumbnail_key ORDER BY si.created_at DESC, si.id DESC))[1]
      AS newest_thumbnail_key,
    max(si.created_at) AS newest_created_at,
    min(si.expires_at) AS next_expires_at,
    now() AS server_now
  FROM public.story_items si
 WHERE si.relationship_id = p_relationship_id
   AND si.deleted_at IS NULL
   AND public.story_relationship_is_open(p_relationship_id, auth.uid())
   AND si.expires_at > now()
 GROUP BY si.author_id
$$;

REVOKE ALL ON FUNCTION public.get_story_ring_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_story_ring_summary(uuid) TO authenticated;

COMMIT;
