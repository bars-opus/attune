-- Attune forums and opinions launch migration.
-- Additive only: creates the missing forum/opinion contract used by the app.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Profiles hardening
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT c.conname
  INTO constraint_name
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname = 'public'
    AND t.relname = 'profiles'
    AND c.contype = 'c'
    AND pg_get_constraintdef(c.oid) ILIKE '%relationship_status%';

  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE IF EXISTS public.profiles
  ADD COLUMN IF NOT EXISTS banned_until timestamptz;

ALTER TABLE IF EXISTS public.profiles
  ADD CONSTRAINT profiles_relationship_status_check
  CHECK (
    relationship_status IS NULL
    OR relationship_status IN ('single', 'taken', 'figuring_it_out', 'open')
  );

-- ---------------------------------------------------------------------------
-- Opinions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.opinions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text CHECK (
    relationship_status_at_post IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  like_count int NOT NULL DEFAULT 0,
  dislike_count int NOT NULL DEFAULT 0,
  comment_count int NOT NULL DEFAULT 0,
  report_count int NOT NULL DEFAULT 0,
  hidden_pending_review boolean NOT NULL DEFAULT false,
  removed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.opinion_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid NOT NULL REFERENCES public.opinions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reaction_type text NOT NULL CHECK (reaction_type IN ('like', 'dislike')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (opinion_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.opinion_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  opinion_id uuid NOT NULL REFERENCES public.opinions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text CHECK (
    relationship_status_at_post IS NULL
    OR relationship_status_at_post IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  quoted_text text,
  reply_to_comment_id uuid REFERENCES public.opinion_comments(id) ON DELETE SET NULL,
  like_count int NOT NULL DEFAULT 0,
  dislike_count int NOT NULL DEFAULT 0,
  report_count int NOT NULL DEFAULT 0,
  hidden_pending_review boolean NOT NULL DEFAULT false,
  removed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.opinion_follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (follower_id, following_id)
);

CREATE TABLE IF NOT EXISTS public.comment_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid NOT NULL REFERENCES public.opinion_comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Forums
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.forum_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submitted_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  relationship_status_at_submit text CHECK (
    relationship_status_at_submit IS NULL
    OR relationship_status_at_submit IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  content text NOT NULL CHECK (char_length(content) <= 120),
  status text NOT NULL DEFAULT 'voting' CHECK (
    status IN ('voting', 'active', 'quiet', 'archived', 'expired')
  ),
  upvote_count int NOT NULL DEFAULT 1,
  downvote_count int NOT NULL DEFAULT 0,
  seen_count int NOT NULL DEFAULT 1,
  total_posts int NOT NULL DEFAULT 0,
  for_posts int NOT NULL DEFAULT 0,
  against_posts int NOT NULL DEFAULT 0,
  last_post_at timestamptz,
  activated_at timestamptz,
  voting_expires_at timestamptz NOT NULL DEFAULT (now() + interval '14 days'),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.topic_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vote_type text NOT NULL CHECK (vote_type IN ('up', 'down')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.topic_impressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (topic_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.forum_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic_id uuid NOT NULL REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  side text NOT NULL CHECK (side IN ('for', 'against')),
  content text NOT NULL CHECK (char_length(content) <= 280),
  relationship_status_at_post text CHECK (
    relationship_status_at_post IS NULL
    OR relationship_status_at_post IN ('single', 'taken', 'figuring_it_out', 'open')
  ),
  reply_to_post_id uuid REFERENCES public.forum_posts(id) ON DELETE SET NULL,
  quoted_text text,
  like_count int NOT NULL DEFAULT 0,
  report_count int NOT NULL DEFAULT 0,
  hidden_pending_review boolean NOT NULL DEFAULT false,
  removed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.forum_post_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  forum_post_id uuid NOT NULL REFERENCES public.forum_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (forum_post_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.user_forum_sides (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  topic_id uuid NOT NULL REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  side text NOT NULL CHECK (side IN ('for', 'against', 'browse')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, topic_id)
);

CREATE TABLE IF NOT EXISTS public.forum_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reported_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  opinion_id uuid REFERENCES public.opinions(id) ON DELETE CASCADE,
  comment_id uuid REFERENCES public.opinion_comments(id) ON DELETE CASCADE,
  forum_post_id uuid REFERENCES public.forum_posts(id) ON DELETE CASCADE,
  topic_id uuid REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  reason text NOT NULL,
  priority boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending', 'reviewed_removed', 'reviewed_kept', 'escalated')
  ),
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    opinion_id IS NOT NULL
    OR comment_id IS NOT NULL
    OR forum_post_id IS NOT NULL
    OR topic_id IS NOT NULL
  )
);

-- ---------------------------------------------------------------------------
-- Public views
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW public.public_opinions AS
SELECT
  id,
  content,
  relationship_status_at_post,
  like_count,
  dislike_count,
  comment_count,
  report_count,
  created_at
FROM public.opinions
WHERE removed_at IS NULL
  AND hidden_pending_review = false;

CREATE OR REPLACE VIEW public.public_forum_topics AS
SELECT
  id,
  content,
  relationship_status_at_submit,
  status,
  upvote_count,
  downvote_count,
  seen_count,
  total_posts,
  for_posts,
  against_posts,
  last_post_at,
  activated_at,
  voting_expires_at,
  created_at
FROM public.forum_topics;

CREATE OR REPLACE VIEW public.public_forum_posts AS
SELECT
  id,
  topic_id,
  side,
  content,
  relationship_status_at_post,
  reply_to_post_id,
  quoted_text,
  like_count,
  created_at
FROM public.forum_posts
WHERE removed_at IS NULL
  AND hidden_pending_review = false;

CREATE OR REPLACE VIEW public.opinion_follower_counts AS
SELECT
  following_id AS user_id,
  COUNT(*)::int AS follower_count
FROM public.opinion_follows
GROUP BY following_id;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

ALTER TABLE public.opinions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opinion_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opinion_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opinion_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topic_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topic_impressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_forum_sides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.forum_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS opinions_public_read ON public.opinions;
CREATE POLICY opinions_public_read
ON public.opinions FOR SELECT TO authenticated
USING (removed_at IS NULL AND hidden_pending_review = false);

DROP POLICY IF EXISTS opinions_authenticated_insert ON public.opinions;
CREATE POLICY opinions_authenticated_insert
ON public.opinions FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS opinions_owner_update ON public.opinions;
CREATE POLICY opinions_owner_update
ON public.opinions FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS opinions_owner_delete ON public.opinions;
CREATE POLICY opinions_owner_delete
ON public.opinions FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_reactions_owner_read ON public.opinion_reactions;
CREATE POLICY opinion_reactions_owner_read
ON public.opinion_reactions FOR SELECT TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_reactions_owner_write ON public.opinion_reactions;
CREATE POLICY opinion_reactions_owner_write
ON public.opinion_reactions FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_comments_public_read ON public.opinion_comments;
CREATE POLICY opinion_comments_public_read
ON public.opinion_comments FOR SELECT TO authenticated
USING (removed_at IS NULL AND hidden_pending_review = false);

DROP POLICY IF EXISTS opinion_comments_owner_insert ON public.opinion_comments;
CREATE POLICY opinion_comments_owner_insert
ON public.opinion_comments FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_comments_owner_update ON public.opinion_comments;
CREATE POLICY opinion_comments_owner_update
ON public.opinion_comments FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_comments_owner_delete ON public.opinion_comments;
CREATE POLICY opinion_comments_owner_delete
ON public.opinion_comments FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS opinion_follows_owner ON public.opinion_follows;
CREATE POLICY opinion_follows_owner
ON public.opinion_follows FOR ALL TO authenticated
USING (auth.uid() = follower_id)
WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS comment_likes_owner ON public.comment_likes;
CREATE POLICY comment_likes_owner
ON public.comment_likes FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_topics_public_read ON public.forum_topics;
CREATE POLICY forum_topics_public_read
ON public.forum_topics FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS forum_topics_owner_insert ON public.forum_topics;
CREATE POLICY forum_topics_owner_insert
ON public.forum_topics FOR INSERT TO authenticated
WITH CHECK (auth.uid() = submitted_by);

DROP POLICY IF EXISTS topic_votes_owner ON public.topic_votes;
CREATE POLICY topic_votes_owner
ON public.topic_votes FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS topic_impressions_owner ON public.topic_impressions;
CREATE POLICY topic_impressions_owner
ON public.topic_impressions FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_posts_public_read ON public.forum_posts;
CREATE POLICY forum_posts_public_read
ON public.forum_posts FOR SELECT TO authenticated
USING (removed_at IS NULL AND hidden_pending_review = false);

DROP POLICY IF EXISTS forum_posts_owner_insert ON public.forum_posts;
CREATE POLICY forum_posts_owner_insert
ON public.forum_posts FOR INSERT TO authenticated
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_posts_owner_update ON public.forum_posts;
CREATE POLICY forum_posts_owner_update
ON public.forum_posts FOR UPDATE TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_posts_owner_delete ON public.forum_posts;
CREATE POLICY forum_posts_owner_delete
ON public.forum_posts FOR DELETE TO authenticated
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_post_likes_owner ON public.forum_post_likes;
CREATE POLICY forum_post_likes_owner
ON public.forum_post_likes FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_forum_sides_owner ON public.user_forum_sides;
CREATE POLICY user_forum_sides_owner
ON public.user_forum_sides FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS forum_reports_insert_own ON public.forum_reports;
CREATE POLICY forum_reports_insert_own
ON public.forum_reports FOR INSERT TO authenticated
WITH CHECK (auth.uid() = reported_by);

DROP POLICY IF EXISTS forum_reports_no_read ON public.forum_reports;
CREATE POLICY forum_reports_no_read
ON public.forum_reports FOR SELECT TO authenticated
USING (false);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

REVOKE ALL ON public.opinions FROM PUBLIC, anon;
REVOKE ALL ON public.opinion_reactions FROM PUBLIC, anon;
REVOKE ALL ON public.opinion_comments FROM PUBLIC, anon;
REVOKE ALL ON public.opinion_follows FROM PUBLIC, anon;
REVOKE ALL ON public.comment_likes FROM PUBLIC, anon;
REVOKE ALL ON public.forum_topics FROM PUBLIC, anon;
REVOKE ALL ON public.topic_votes FROM PUBLIC, anon;
REVOKE ALL ON public.topic_impressions FROM PUBLIC, anon;
REVOKE ALL ON public.forum_posts FROM PUBLIC, anon;
REVOKE ALL ON public.forum_post_likes FROM PUBLIC, anon;
REVOKE ALL ON public.user_forum_sides FROM PUBLIC, anon;
REVOKE ALL ON public.forum_reports FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.opinions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.opinion_reactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.opinion_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.opinion_follows TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.comment_likes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.forum_topics TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.topic_votes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.topic_impressions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.forum_posts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.forum_post_likes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_forum_sides TO authenticated;
GRANT INSERT ON public.forum_reports TO authenticated;

GRANT SELECT ON public.public_opinions TO authenticated;
GRANT SELECT ON public.public_forum_topics TO authenticated;
GRANT SELECT ON public.public_forum_posts TO authenticated;
GRANT SELECT ON public.opinion_follower_counts TO authenticated;

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_opinions_created_at
  ON public.opinions(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_opinions_user_id
  ON public.opinions(user_id);

CREATE INDEX IF NOT EXISTS idx_opinions_relationship_status
  ON public.opinions(relationship_status_at_post);

CREATE INDEX IF NOT EXISTS idx_opinion_reactions_opinion_id
  ON public.opinion_reactions(opinion_id);

CREATE INDEX IF NOT EXISTS idx_opinion_reactions_user_id
  ON public.opinion_reactions(user_id);

CREATE INDEX IF NOT EXISTS idx_opinion_comments_opinion_id
  ON public.opinion_comments(opinion_id);

CREATE INDEX IF NOT EXISTS idx_opinion_comments_user_id
  ON public.opinion_comments(user_id);

CREATE INDEX IF NOT EXISTS idx_opinion_follows_follower
  ON public.opinion_follows(follower_id);

CREATE INDEX IF NOT EXISTS idx_opinion_follows_following
  ON public.opinion_follows(following_id);

CREATE INDEX IF NOT EXISTS idx_comment_likes_comment_id
  ON public.comment_likes(comment_id);

CREATE INDEX IF NOT EXISTS idx_comment_likes_user_id
  ON public.comment_likes(user_id);

CREATE INDEX IF NOT EXISTS idx_forum_topics_status
  ON public.forum_topics(status);

CREATE INDEX IF NOT EXISTS idx_forum_topics_last_post
  ON public.forum_topics(last_post_at DESC);

CREATE INDEX IF NOT EXISTS idx_forum_topics_voting_expires_at
  ON public.forum_topics(voting_expires_at);

CREATE INDEX IF NOT EXISTS idx_topic_votes_topic_id
  ON public.topic_votes(topic_id);

CREATE INDEX IF NOT EXISTS idx_topic_votes_user_id
  ON public.topic_votes(user_id);

CREATE INDEX IF NOT EXISTS idx_topic_impressions_topic_id
  ON public.topic_impressions(topic_id);

CREATE INDEX IF NOT EXISTS idx_topic_impressions_user_id
  ON public.topic_impressions(user_id);

CREATE INDEX IF NOT EXISTS idx_forum_posts_topic_id
  ON public.forum_posts(topic_id);

CREATE INDEX IF NOT EXISTS idx_forum_posts_user_id
  ON public.forum_posts(user_id);

CREATE INDEX IF NOT EXISTS idx_forum_posts_created_at
  ON public.forum_posts(created_at ASC);

CREATE INDEX IF NOT EXISTS idx_forum_post_likes_post_id
  ON public.forum_post_likes(forum_post_id);

CREATE INDEX IF NOT EXISTS idx_forum_post_likes_user_id
  ON public.forum_post_likes(user_id);

CREATE INDEX IF NOT EXISTS idx_user_forum_sides_topic_id
  ON public.user_forum_sides(topic_id);

CREATE INDEX IF NOT EXISTS idx_user_forum_sides_user_id
  ON public.user_forum_sides(user_id);

CREATE INDEX IF NOT EXISTS idx_forum_reports_opinion_id
  ON public.forum_reports(opinion_id);

CREATE INDEX IF NOT EXISTS idx_forum_reports_comment_id
  ON public.forum_reports(comment_id);

CREATE INDEX IF NOT EXISTS idx_forum_reports_forum_post_id
  ON public.forum_reports(forum_post_id);

CREATE INDEX IF NOT EXISTS idx_forum_reports_topic_id
  ON public.forum_reports(topic_id);

CREATE INDEX IF NOT EXISTS idx_forum_reports_created_at
  ON public.forum_reports(created_at DESC);

-- ---------------------------------------------------------------------------
-- Helper RPCs
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.increment_opinion_like_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_like_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_opinion_dislike_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET dislike_count = COALESCE(dislike_count, 0) + 1
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_dislike_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET dislike_count = GREATEST(COALESCE(dislike_count, 0) - 1, 0)
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_opinion_comment_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET comment_count = COALESCE(comment_count, 0) + 1
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_comment_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET comment_count = GREATEST(COALESCE(comment_count, 0) - 1, 0)
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_opinion_report_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinions
  SET report_count = COALESCE(report_count, 0) + 1
  WHERE id = p_opinion_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_comment_like_count(p_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinion_comments
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_comment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_comment_like_count(p_comment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.opinion_comments
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_comment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_upvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET upvote_count = COALESCE(upvote_count, 0) + 1
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_topic_upvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET upvote_count = GREATEST(COALESCE(upvote_count, 0) - 1, 0)
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_downvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET downvote_count = COALESCE(downvote_count, 0) + 1
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_topic_downvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET downvote_count = GREATEST(COALESCE(downvote_count, 0) - 1, 0)
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_seen_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET seen_count = COALESCE(seen_count, 0) + 1
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_post_count(p_topic_id uuid, p_side text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_topics
  SET
    total_posts = COALESCE(total_posts, 0) + 1,
    last_post_at = now(),
    for_posts = CASE WHEN p_side = 'for' THEN COALESCE(for_posts, 0) + 1 ELSE COALESCE(for_posts, 0) END,
    against_posts = CASE WHEN p_side = 'against' THEN COALESCE(against_posts, 0) + 1 ELSE COALESCE(against_posts, 0) END
  WHERE id = p_topic_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_forum_post_like_count(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_posts
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_forum_post_like_count(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.forum_posts
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_post_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_pending_topics()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  activated_count integer := 0;
BEGIN
  WITH activated AS (
    UPDATE public.forum_topics
    SET status = 'active',
        activated_at = COALESCE(activated_at, now())
    WHERE status = 'voting'
      AND seen_count >= 20
      AND voting_expires_at > now()
      AND (upvote_count::numeric / NULLIF(seen_count, 0)) > 0.5
    RETURNING id
  )
  SELECT count(*) INTO activated_count FROM activated;

  RETURN activated_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_old_topics()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  expired_count integer := 0;
BEGIN
  WITH expired AS (
    UPDATE public.forum_topics
    SET status = 'expired'
    WHERE status = 'voting'
      AND voting_expires_at <= now()
    RETURNING id
  )
  SELECT count(*) INTO expired_count FROM expired;

  RETURN expired_count;
END;
$$;

REVOKE ALL ON FUNCTION public.increment_opinion_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_opinion_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_opinion_dislike_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_opinion_dislike_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_opinion_comment_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_opinion_comment_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_opinion_report_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_comment_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_comment_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_topic_upvote_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_topic_upvote_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_topic_downvote_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_topic_downvote_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_topic_seen_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_topic_post_count(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.increment_forum_post_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.decrement_forum_post_like_count(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.activate_pending_topics() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.expire_old_topics() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.increment_opinion_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_opinion_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_opinion_dislike_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_opinion_dislike_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_opinion_comment_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_opinion_comment_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_opinion_report_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_comment_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_comment_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_topic_upvote_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_topic_upvote_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_topic_downvote_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_topic_downvote_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_topic_seen_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_topic_post_count(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_forum_post_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_forum_post_like_count(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_pending_topics() TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_old_topics() TO authenticated;

