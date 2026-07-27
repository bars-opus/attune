-- Polls on opinions and forum topics
--
-- Spec: ATTUNE_MASTER_SPEC.md §8.11 "Polls", FORUM.md §7 "Polls (both features)".
--
-- A poll is an optional attachment on an opinion OR a forum topic. It is the one
-- structured attachment the "strictly text" principle admits: options are plain
-- text and fixed at creation, so there is no upload, no link, and no free-text
-- field a voter can fill.
--
-- Shape (§8.11):
--   2-4 options, each <= 60 chars, IMMUTABLE after creation. One poll per post.
--   Polls never expire.
--
-- Voting (§8.11):
--   Phone-verified users only, one vote per user per poll, changeable and
--   retractable. Results hidden until you vote. Users MAY vote on their own poll
--   (unlike opinion reactions, where reacting to your own post is blocked) — a
--   poll is a question its author is also entitled to answer.
--
-- Polls are NOT topic voting. topic_votes gates a topic into existence (up/down,
-- >50% of seen, 14-day expiry). A poll asks that post's readers a question, gates
-- nothing, and never expires. A topic may carry both.
--
-- Access model follows the anonymity hardening migration: clients NEVER touch
-- these base tables directly. Everything goes through SECURITY DEFINER RPCs, so
-- the vote table's user_id is never reachable from a client.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.post_polls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid REFERENCES public.opinions ON DELETE CASCADE,
  topic_id uuid REFERENCES public.forum_topics ON DELETE CASCADE,
  created_by uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  -- Exactly one parent: a poll hangs off an opinion or a topic, never both.
  CONSTRAINT post_polls_one_parent CHECK (num_nonnulls(opinion_id, topic_id) = 1),
  -- One poll per post (§8.11).
  CONSTRAINT post_polls_unique_opinion UNIQUE (opinion_id),
  CONSTRAINT post_polls_unique_topic UNIQUE (topic_id)
);

-- The order column is `option_position`, NOT `position`. Postgres classifies
-- `position` as "non-reserved (cannot be function or type name)": it is legal
-- in CREATE TABLE, but a RETURNS TABLE declaration parses each entry as
-- `name type`, and that type context rejects it — `position int` there is a
-- syntax error. Rather than have the column legal in one statement and illegal
-- in the next, it carries an unambiguous name everywhere.
CREATE TABLE IF NOT EXISTS public.poll_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id uuid REFERENCES public.post_polls ON DELETE CASCADE NOT NULL,
  option_position int NOT NULL CHECK (option_position BETWEEN 0 AND 3),
  label text NOT NULL CHECK (char_length(btrim(label)) BETWEEN 1 AND 60),
  vote_count int NOT NULL DEFAULT 0,
  CONSTRAINT poll_options_unique_position UNIQUE (poll_id, option_position)
);

-- user_id exists for dedup enforcement ONLY. It is never exposed to any client:
-- there is no SELECT grant on this table, and no RPC returns it. Aggregate
-- results reach clients through poll_options.vote_count.
CREATE TABLE IF NOT EXISTS public.poll_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id uuid REFERENCES public.post_polls ON DELETE CASCADE NOT NULL,
  option_id uuid REFERENCES public.poll_options ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  -- One vote per user per poll (§8.11). Changing a vote UPDATEs this row rather
  -- than inserting a second one.
  CONSTRAINT poll_votes_one_per_user UNIQUE (poll_id, user_id)
);

-- Repairs a partially-applied earlier run of THIS migration. The first attempt
-- created poll_options with a column literally named `position` and then failed
-- at the get_post_poll declaration, where `position int` is a syntax error.
-- CREATE TABLE IF NOT EXISTS above would skip the already-created table and
-- leave the old column name in place, so rename it explicitly. No-op on a clean
-- database, where the column is already option_position.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'poll_options'
      AND column_name = 'position'
  ) THEN
    ALTER TABLE public.poll_options RENAME COLUMN "position" TO option_position;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_post_polls_opinion ON public.post_polls(opinion_id);
CREATE INDEX IF NOT EXISTS idx_post_polls_topic ON public.post_polls(topic_id);
CREATE INDEX IF NOT EXISTS idx_poll_options_poll ON public.poll_options(poll_id, option_position);
CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_user ON public.poll_votes(poll_id, user_id);

-- ---------------------------------------------------------------------------
-- Privileges.
--
-- GRANT is evaluated BEFORE RLS — a table with policies but no grant is simply
-- inaccessible (this bit the core tables in 20260724120000). Here the intended
-- access is "none, ever, for clients": all reads and writes go through the RPCs
-- below, which are SECURITY DEFINER and therefore run as the function owner.
-- Granting nothing to authenticated is what keeps poll_votes.user_id
-- unreachable, and is the load-bearing half of the anonymity guarantee.
-- ---------------------------------------------------------------------------

REVOKE ALL ON public.post_polls FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.poll_options FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.poll_votes FROM PUBLIC, anon, authenticated;

ALTER TABLE public.post_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;

-- RLS with no permissive policy = deny all. Belt and braces alongside the
-- revoked grants: if a future migration grants SELECT to authenticated by
-- mistake, RLS still denies the read rather than leaking every voter.

-- ---------------------------------------------------------------------------
-- Poll creation. Called from create_opinion_with_poll / create_topic_with_poll
-- below, never directly by a client.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.create_poll_for_post(
  p_user_id uuid,
  p_opinion_id uuid,
  p_topic_id uuid,
  p_options text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_poll_id uuid;
  v_label text;
  v_position int := 0;
  v_clean text[];
BEGIN
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

  INSERT INTO public.post_polls (opinion_id, topic_id, created_by)
  VALUES (p_opinion_id, p_topic_id, p_user_id)
  RETURNING id INTO v_poll_id;

  FOREACH v_label IN ARRAY v_clean LOOP
    INSERT INTO public.poll_options (poll_id, option_position, label)
    VALUES (v_poll_id, v_position, v_label);
    v_position := v_position + 1;
  END LOOP;

  RETURN v_poll_id;
END;
$$;
REVOKE ALL ON FUNCTION private.create_poll_for_post(uuid, uuid, uuid, text[])
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Create an opinion with an optional poll. Delegates to create_opinion so
-- content validation, the ban gate and the rate limits stay in one place, then
-- attaches the poll in the SAME transaction — a rate-limit rejection raises
-- before any poll row exists, so an orphan poll is not reachable.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_opinion_with_poll(
  p_content text,
  p_poll_options text[] DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  v_id := public.create_opinion(p_content);

  IF p_poll_options IS NOT NULL AND array_length(p_poll_options, 1) IS NOT NULL THEN
    PERFORM private.create_poll_for_post(v_uid, v_id, NULL, p_poll_options);
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_opinion_with_poll(text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_opinion_with_poll(text, text[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- Create a forum topic with an optional poll. Mirrors create_forum_topic.
-- ---------------------------------------------------------------------------

-- Delegates to create_forum_topic rather than repeating its body: that function
-- owns content validation, the ban gate, the 3-per-7-days limit, and the
-- submitter's auto-upvote/auto-impression rows (added in 20260722120100). A
-- copy here would silently drift the next time topic creation changes.
CREATE OR REPLACE FUNCTION public.create_forum_topic_with_poll(
  p_content text,
  p_poll_options text[] DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  v_id := public.create_forum_topic(p_content);

  IF p_poll_options IS NOT NULL AND array_length(p_poll_options, 1) IS NOT NULL THEN
    PERFORM private.create_poll_for_post(v_uid, NULL, v_id, p_poll_options);
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_forum_topic_with_poll(text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_forum_topic_with_poll(text, text[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- Read a poll.
--
-- Results are hidden until the caller votes (§8.11): when my_option_id IS NULL,
-- every vote_count is returned as NULL rather than a real number. The masking
-- happens HERE, server-side — sending true counts and hiding them in the client
-- would leak the standing to anyone reading the network response.
--
-- total_votes is likewise masked, since it narrows the counts.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_post_poll(
  p_opinion_id uuid DEFAULT NULL,
  p_topic_id uuid DEFAULT NULL
)
RETURNS TABLE (
  poll_id uuid,
  option_id uuid,
  option_position int,
  label text,
  vote_count int,
  total_votes int,
  my_option_id uuid,
  has_voted boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  WITH target AS (
    SELECT p.id
    FROM public.post_polls p
    WHERE (p_opinion_id IS NOT NULL AND p.opinion_id = p_opinion_id)
       OR (p_topic_id IS NOT NULL AND p.topic_id = p_topic_id)
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
$$;
REVOKE ALL ON FUNCTION public.get_post_poll(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Cast or change a vote.
--
-- One statement handles both cases via ON CONFLICT, so a double-tap can never
-- produce two rows or double-count. Counter maintenance is explicit: decrement
-- the previous option, increment the new one, and do nothing at all when the
-- user re-votes for the option they already hold.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cast_poll_vote(p_option_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_poll_id uuid;
  v_previous_option uuid;
  v_banned_until timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  -- Banned users may read but not write (§7/§8), same gate as posting.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = v_uid;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  SELECT poll_id INTO v_poll_id FROM public.poll_options WHERE id = p_option_id;
  IF v_poll_id IS NULL THEN
    RAISE EXCEPTION 'poll_option_not_found' USING ERRCODE = '22023';
  END IF;

  -- Lock the caller's existing vote row (if any) so two concurrent taps
  -- serialise instead of racing the counter updates.
  SELECT option_id INTO v_previous_option
  FROM public.poll_votes
  WHERE poll_id = v_poll_id AND user_id = v_uid
  FOR UPDATE;

  -- Re-voting for the option you already hold is a no-op, not a double count.
  IF v_previous_option = p_option_id THEN
    RETURN;
  END IF;

  INSERT INTO public.poll_votes (poll_id, option_id, user_id)
  VALUES (v_poll_id, p_option_id, v_uid)
  ON CONFLICT (poll_id, user_id)
  DO UPDATE SET option_id = EXCLUDED.option_id, updated_at = now();

  IF v_previous_option IS NOT NULL THEN
    UPDATE public.poll_options
    SET vote_count = greatest(COALESCE(vote_count, 0) - 1, 0)
    WHERE id = v_previous_option;
  END IF;

  UPDATE public.poll_options
  SET vote_count = COALESCE(vote_count, 0) + 1
  WHERE id = p_option_id;
END;
$$;
REVOKE ALL ON FUNCTION public.cast_poll_vote(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cast_poll_vote(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Retract a vote, returning the caller to the pre-vote state (§8.11). This
-- re-hides the results, since get_post_poll masks counts when no vote exists.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.retract_poll_vote(p_poll_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_option_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  DELETE FROM public.poll_votes
  WHERE poll_id = p_poll_id AND user_id = v_uid
  RETURNING option_id INTO v_option_id;

  IF v_option_id IS NOT NULL THEN
    UPDATE public.poll_options
    SET vote_count = greatest(COALESCE(vote_count, 0) - 1, 0)
    WHERE id = v_option_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.retract_poll_vote(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.retract_poll_vote(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed integration: which posts carry a poll.
--
-- The feed RPCs return one row per post, so they cannot carry a poll's option
-- rows. Instead the client asks "which of these posts have polls?" in one round
-- trip and fetches full poll state only for the posts it actually renders.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_polls_for_opinions(p_opinion_ids uuid[])
RETURNS TABLE (opinion_id uuid, poll_id uuid, has_voted boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    p.opinion_id,
    p.id AS poll_id,
    EXISTS (
      SELECT 1 FROM public.poll_votes v
      WHERE v.poll_id = p.id AND v.user_id = auth.uid()
    ) AS has_voted
  FROM public.post_polls p
  WHERE p.opinion_id = ANY(p_opinion_ids);
$$;
REVOKE ALL ON FUNCTION public.get_polls_for_opinions(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_polls_for_opinions(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_polls_for_topics(p_topic_ids uuid[])
RETURNS TABLE (topic_id uuid, poll_id uuid, has_voted boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT
    p.topic_id,
    p.id AS poll_id,
    EXISTS (
      SELECT 1 FROM public.poll_votes v
      WHERE v.poll_id = p.id AND v.user_id = auth.uid()
    ) AS has_voted
  FROM public.post_polls p
  WHERE p.topic_id = ANY(p_topic_ids);
$$;
REVOKE ALL ON FUNCTION public.get_polls_for_topics(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_polls_for_topics(uuid[]) TO authenticated;
