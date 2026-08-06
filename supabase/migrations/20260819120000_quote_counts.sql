-- How many times each opinion has been quoted, so the quote button in the
-- actions row can carry a count like like/dislike/repost/comment already do.
--
-- Deliberately NOT a maintained counter column on opinions (the shape
-- repost_count uses). Adding a column to the feed RPCs' RETURNS TABLE would
-- mean DROPping and recreating all eight of them — get_discover_opinions,
-- get_following_opinions, get_saved_opinions, get_reposted_opinions,
-- get_opinions_by_tag, get_author_reposted_opinions, get_quoted_opinion and
-- the author feed — because Postgres cannot CREATE OR REPLACE a function
-- whose result columns changed. That is a large verbatim rewrite of working
-- ranking/filter logic, plus re-applying every REVOKE/GRANT on each.
--
-- Instead this follows the batch side-data pattern the codebase already uses
-- twice for exactly this situation (get_tags_for_opinions,
-- get_polls_for_opinions): one call per rendered page of ids, joined on the
-- client. It touches no existing function, and it cannot drift the way a
-- trigger-maintained counter can, because it counts the real rows.
--
-- A quote is an opinion in its own right, so a quote count exposes nothing a
-- viewer could not already see by reading the feed — unlike saves, which stay
-- private and countless by design (see 20260727140000_opinion_saves.sql).

CREATE OR REPLACE FUNCTION public.get_quote_counts(p_opinion_ids uuid[])
RETURNS TABLE (opinion_id uuid, quote_count int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
BEGIN
  -- Same page-size ceiling the other batch RPCs enforce: a feed page is 30
  -- rows, so 100 leaves headroom without letting a caller ask for the table.
  IF p_opinion_ids IS NOT NULL AND array_length(p_opinion_ids, 1) > 100 THEN
    RAISE EXCEPTION 'too_many_ids' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT o.quoted_opinion_id AS opinion_id, COUNT(*)::int AS quote_count
  FROM public.opinions o
  WHERE o.quoted_opinion_id = ANY(p_opinion_ids)
    -- Count only quotes a reader could actually reach. A removed or
    -- pending-review quote is invisible in every feed, so counting it would
    -- advertise content that cannot be opened.
    AND o.removed_at IS NULL
    AND o.hidden_pending_review = false
  GROUP BY o.quoted_opinion_id;
END;
$$;

-- Readable by guests for the same reason the feed itself is
-- (20260818120000_public_opinion_reads): this returns aggregate counts over
-- already-public content and no user_id.
REVOKE ALL ON FUNCTION public.get_quote_counts(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_quote_counts(uuid[]) TO authenticated, anon;

-- No new index needed: 20260729120000_opinion_quotes already created the
-- partial index opinions_quoted_opinion_id_idx on (quoted_opinion_id) WHERE
-- quoted_opinion_id IS NOT NULL, which is exactly what the WHERE above needs.
