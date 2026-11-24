-- Spec 3 (forum removal) W3, migration 4 of 6: the kept poll and report
-- tables lose their forum columns (Spec 3 §3.9, §6.3 step 4; V6, V7; D7,
-- D8). One transaction with the two poll functions that read or wrote
-- post_polls.topic_id, so no moment exists where a live function names a
-- dropped column.
--   * private.create_poll_for_post and public.get_post_poll: their live
--     bodies (20260726120000_polls_on_opinions_and_topics.sql; md5 checked
--     by migration 1) with only the topic handling changed. Signatures and
--     defaults unchanged, so get_post_poll keeps its anon grant (V3: guest
--     Opinions polls) and an old client passing p_topic_id gets no rows;
--     create_poll_for_post refuses a topic (topic_polls_retired, 22023).
--     search_path '' (house rule; every relation was already qualified).
--     Removed, verbatim: in create_poll_for_post
--       INSERT INTO public.post_polls (opinion_id, topic_id, created_by)
--       VALUES (p_opinion_id, p_topic_id, p_user_id)
--     and in get_post_poll
--          OR (p_topic_id IS NOT NULL AND p.topic_id = p_topic_id)
--   * post_polls: post_polls_one_parent, post_polls_unique_topic and
--     idx_post_polls_topic, then topic_id; opinion_id NOT NULL keeps "every
--     poll has its one parent" (topic polls were deleted by migration 3).
--   * forum_reports: forum_reports_check, the two forum dedup indexes and
--     the two forum indexes, then forum_post_id and topic_id;
--     forum_reports_target_check keeps "every report names an opinion or a
--     comment" (forum-only reports were deleted by migration 3). The
--     opinion and comment columns, their dedup indexes (report_opinion's
--     ON CONFLICT target), RLS and grants are unchanged.
-- Idempotent: CREATE OR REPLACE, IF EXISTS, the CHECK added once.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.create_poll_for_post(p_user_id uuid, p_opinion_id uuid, p_topic_id uuid, p_options text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_poll_id uuid;
  v_label text;
  v_position int := 0;
  v_clean text[];
BEGIN
  -- Spec 3 W3: topic polls are retired with the forums. p_topic_id stays in
  -- the signature, so the one caller (create_opinion_with_poll, which passes
  -- NULL) is unchanged; a topic is refused.
  IF p_topic_id IS NOT NULL THEN
    RAISE EXCEPTION 'topic_polls_retired' USING ERRCODE = '22023';
  END IF;
  -- 2-4 options (§8.11). Reject anything else rather than silently truncating.
  IF p_options IS NULL OR array_length(p_options, 1) IS NULL THEN
    RAISE EXCEPTION 'poll_requires_options' USING ERRCODE = '22023';
  END IF;

  SELECT array_agg(btrim(opt))
  INTO v_clean
  FROM unnest(p_options) AS opt
  WHERE btrim(opt) <> '';

  IF v_clean IS NULL OR array_length(v_clean, 1) < 2 OR array_length(v_clean, 1) > 4 THEN
    RAISE EXCEPTION 'poll_option_count' USING ERRCODE = '22023';
  END IF;

  FOREACH v_label IN ARRAY v_clean LOOP
    IF char_length(v_label) > 60 THEN
      RAISE EXCEPTION 'poll_option_too_long' USING ERRCODE = '22023';
    END IF;
  END LOOP;

  INSERT INTO public.post_polls (opinion_id, created_by) -- Spec 3 W3: no topic_id
  VALUES (p_opinion_id, p_user_id) -- Spec 3 W3
  RETURNING id INTO v_poll_id;

  FOREACH v_label IN ARRAY v_clean LOOP
    INSERT INTO public.poll_options (poll_id, option_position, label)
    VALUES (v_poll_id, v_position, v_label);
    v_position := v_position + 1;
  END LOOP;

  RETURN v_poll_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_post_poll(p_opinion_id uuid DEFAULT NULL::uuid, p_topic_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(poll_id uuid, option_id uuid, option_position integer, label text, vote_count integer, total_votes integer, my_option_id uuid, has_voted boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
  -- Spec 3 W3: topic polls are retired. The second parameter stays so the
  -- signature, and the anon grant guest Opinions polls need, never change;
  -- it matches nothing.
  WITH target AS (
    SELECT p.id
    FROM public.post_polls p
    WHERE p_opinion_id IS NOT NULL AND p.opinion_id = p_opinion_id -- Spec 3 W3
    LIMIT 1
  ),
  mine AS (
    SELECT v.option_id
    FROM public.poll_votes v
    JOIN target t ON t.id = v.poll_id
    WHERE v.user_id = auth.uid()
  ),
  totals AS (
    SELECT COALESCE(sum(o.vote_count), 0)::int AS total
    FROM public.poll_options o
    JOIN target t ON t.id = o.poll_id
  )
  SELECT
    o.poll_id,
    o.id AS option_id,
    o.option_position,
    o.label,
    -- Masked until the caller has voted.
    CASE WHEN (SELECT option_id FROM mine) IS NOT NULL
         THEN o.vote_count END AS vote_count,
    CASE WHEN (SELECT option_id FROM mine) IS NOT NULL
         THEN (SELECT total FROM totals) END AS total_votes,
    (SELECT option_id FROM mine) AS my_option_id,
    ((SELECT option_id FROM mine) IS NOT NULL) AS has_voted
  FROM public.poll_options o
  JOIN target t ON t.id = o.poll_id
  ORDER BY o.option_position;
$function$;

-- The ACLs as they are (re-asserted): the poll writer is the database's own;
-- the poll read is for guests and signed-in people (V3).
REVOKE ALL ON FUNCTION private.create_poll_for_post(uuid, uuid, uuid, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_post_poll(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon, authenticated;

ALTER TABLE public.post_polls DROP CONSTRAINT IF EXISTS post_polls_one_parent;
ALTER TABLE public.post_polls DROP CONSTRAINT IF EXISTS post_polls_unique_topic;
DROP INDEX IF EXISTS public.idx_post_polls_topic;
ALTER TABLE public.post_polls DROP COLUMN IF EXISTS topic_id RESTRICT;
ALTER TABLE public.post_polls ALTER COLUMN opinion_id SET NOT NULL;

ALTER TABLE public.forum_reports DROP CONSTRAINT IF EXISTS forum_reports_check;
DROP INDEX IF EXISTS public.forum_reports_unique_reporter_forum_post;
DROP INDEX IF EXISTS public.forum_reports_unique_reporter_topic;
DROP INDEX IF EXISTS public.idx_forum_reports_forum_post_id;
DROP INDEX IF EXISTS public.idx_forum_reports_topic_id;
ALTER TABLE public.forum_reports
  DROP COLUMN IF EXISTS forum_post_id RESTRICT,
  DROP COLUMN IF EXISTS topic_id RESTRICT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
                  WHERE conrelid = 'public.forum_reports'::pg_catalog.regclass
                    AND conname = 'forum_reports_target_check') THEN
    ALTER TABLE public.forum_reports
      ADD CONSTRAINT forum_reports_target_check CHECK (opinion_id IS NOT NULL OR comment_id IS NOT NULL);
  END IF;
END
$$;

COMMIT;
