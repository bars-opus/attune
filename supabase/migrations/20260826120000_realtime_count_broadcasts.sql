-- Broadcasts opinion/forum count changes to every viewer, not just the
-- actor, via Realtime Broadcast — so User B's like ticks up on User A's
-- screen live, matching how YouTube/Twitter counts move for every viewer.
--
-- Broadcast, not postgres_changes: postgres_changes authorizes off the
-- table's RLS SELECT policy, and anon has no SELECT grant on opinions/
-- forum_topics/forum_posts (only on the user_id-free public_* views —
-- see 20260716140000_forums_opinions_anonymity_hardening.sql), while
-- authenticated's raw-table SELECT still carries user_id on the row. A
-- postgres_changes subscription on the base tables would either be
-- unreachable for guests or leak user_id to signed-in viewers. Broadcast
-- sidesteps RLS entirely: the SECURITY DEFINER RPC below constructs its own
-- payload by hand, so it can emit exactly {entity id, counts} and nothing
-- else — anonymity-safe for every viewer, including anon, by construction
-- rather than by policy.
--
-- Topic naming: "<entity>-counts:<id>", one channel per row, mirroring the
-- existing chat:$relationshipId convention (supabase_chat_repository.dart).
-- Non-private (no RLS check) since the payload has nothing to protect.

CREATE OR REPLACE FUNCTION public.increment_opinion_like_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  UPDATE public.opinions
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_like_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  UPDATE public.opinions
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_opinion_dislike_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  UPDATE public.opinions
  SET dislike_count = COALESCE(dislike_count, 0) + 1
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_opinion_dislike_count(p_opinion_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
  v_dislike_count int;
BEGIN
  UPDATE public.opinions
  SET dislike_count = GREATEST(COALESCE(dislike_count, 0) - 1, 0)
  WHERE id = p_opinion_id
  RETURNING like_count, dislike_count INTO v_like_count, v_dislike_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'opinion_id', p_opinion_id,
      'like_count', v_like_count,
      'dislike_count', v_dislike_count
    ),
    'counts',
    'opinion-counts:' || p_opinion_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_upvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upvote_count int;
  v_downvote_count int;
BEGIN
  UPDATE public.forum_topics
  SET upvote_count = COALESCE(upvote_count, 0) + 1
  WHERE id = p_topic_id
  RETURNING upvote_count, downvote_count INTO v_upvote_count, v_downvote_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'topic_id', p_topic_id,
      'upvote_count', v_upvote_count,
      'downvote_count', v_downvote_count
    ),
    'counts',
    'topic-counts:' || p_topic_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_topic_upvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upvote_count int;
  v_downvote_count int;
BEGIN
  UPDATE public.forum_topics
  SET upvote_count = GREATEST(COALESCE(upvote_count, 0) - 1, 0)
  WHERE id = p_topic_id
  RETURNING upvote_count, downvote_count INTO v_upvote_count, v_downvote_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'topic_id', p_topic_id,
      'upvote_count', v_upvote_count,
      'downvote_count', v_downvote_count
    ),
    'counts',
    'topic-counts:' || p_topic_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_topic_downvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upvote_count int;
  v_downvote_count int;
BEGIN
  UPDATE public.forum_topics
  SET downvote_count = COALESCE(downvote_count, 0) + 1
  WHERE id = p_topic_id
  RETURNING upvote_count, downvote_count INTO v_upvote_count, v_downvote_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'topic_id', p_topic_id,
      'upvote_count', v_upvote_count,
      'downvote_count', v_downvote_count
    ),
    'counts',
    'topic-counts:' || p_topic_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_topic_downvote_count(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upvote_count int;
  v_downvote_count int;
BEGIN
  UPDATE public.forum_topics
  SET downvote_count = GREATEST(COALESCE(downvote_count, 0) - 1, 0)
  WHERE id = p_topic_id
  RETURNING upvote_count, downvote_count INTO v_upvote_count, v_downvote_count;

  PERFORM realtime.send(
    jsonb_build_object(
      'topic_id', p_topic_id,
      'upvote_count', v_upvote_count,
      'downvote_count', v_downvote_count
    ),
    'counts',
    'topic-counts:' || p_topic_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.increment_forum_post_like_count(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
BEGIN
  UPDATE public.forum_posts
  SET like_count = COALESCE(like_count, 0) + 1
  WHERE id = p_post_id
  RETURNING like_count INTO v_like_count;

  PERFORM realtime.send(
    jsonb_build_object('post_id', p_post_id, 'like_count', v_like_count),
    'counts',
    'post-counts:' || p_post_id,
    false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_forum_post_like_count(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_like_count int;
BEGIN
  UPDATE public.forum_posts
  SET like_count = GREATEST(COALESCE(like_count, 0) - 1, 0)
  WHERE id = p_post_id
  RETURNING like_count INTO v_like_count;

  PERFORM realtime.send(
    jsonb_build_object('post_id', p_post_id, 'like_count', v_like_count),
    'counts',
    'post-counts:' || p_post_id,
    false
  );
END;
$$;

-- Grants are unchanged by this migration (same functions, same signatures) —
-- REVOKE/GRANT from 20260716120000_forums_opinions_launch.sql still applies,
-- listed here only as a reminder that CREATE OR REPLACE does not reset them.
