-- supabase/migrations/20260727130000_forum_activity_notifications.sql
--
-- FORUM.md §10 notifications #5 ("new activity in forums you contribute to")
-- and #6 ("forum going quiet"). Only #4 (topic activated) existed before this.
--
-- Delivery goes through the established pipeline: these functions only INSERT
-- into public.scheduled_notifications; the process-scheduled-notifications
-- edge function picks the rows up on its cron and delivers via OneSignal.
-- Nothing here calls OneSignal, pg_net, or an HTTP endpoint directly.
--
-- ---------------------------------------------------------------------------
-- DESIGN NOTE 1 — why a dedicated forum_topic_visits table instead of reusing
-- topic_impressions.
--
-- topic_impressions looks like a "last visited" signal (it has seen_at and
-- UNIQUE(topic_id, user_id)) but it is not one, for two independent reasons:
--
--   a) It records FEED IMPRESSIONS, not topic visits. It is written by
--      TopicImpressionTracker when a topic CARD is ~2s visible while scrolling
--      the forum list -- the user never opened the topic. §10's "NEVER
--      NOTIFIED: activity in forums you only browsed (not contributed to)"
--      makes browse and visit semantically different things, so overloading
--      one column to mean both would make the read-watermark fire for people
--      who merely scrolled past a card.
--
--   b) It is effectively write-once per client session anyway. The tracker
--      guards on a `_hasRecorded` bool for the lifetime of the widget, so
--      seen_at is "first time this card scrolled into view", not "last visit".
--
-- Critically, topic_impressions' write path is also load-bearing for topic
-- ACTIVATION and must not be disturbed: forum_repository.recordImpression()
-- upserts the impression and then unconditionally calls
-- increment_topic_seen_count(), which feeds the
-- `upvote_count / seen_count > 0.5 AND seen_count >= 20` activation threshold
-- in activate_pending_topics(). Repurposing seen_at to update on every visit
-- would mean touching that same call path, and any change there risks skewing
-- the activation maths. A separate table keeps the read-watermark completely
-- isolated from the activation counters.
--
-- (Pre-existing, deliberately NOT fixed here as it is outside this task's
-- scope: recordImpression() bumps seen_count on every call while the impression
-- row is upserted, so a user re-viewing a topic card in a new app session
-- inflates seen_count without inflating upvote_count. That biases the >50%
-- ratio downward. Flagged for the forums track rather than changed here,
-- because altering activation behaviour is a separate decision.)
--
-- ---------------------------------------------------------------------------
-- DESIGN NOTE 2 — the 2-hour rate limit for #5.
--
-- Implemented by querying scheduled_notifications for a prior row with the same
-- user_id and metadata->>'topic_id' inside the last 2 hours, rather than adding
-- a dedicated tracking table. Reasons:
--   * scheduled_notifications is already the single source of truth for "did we
--     actually queue a push for this user"; a side table can drift from it when
--     a row is later marked failed/skipped.
--   * The lookup is made cheap by a partial index (below) restricted to
--     forum_activity rows, so the jsonb extraction only ever runs over this
--     notification type's rows, not the whole table.
-- The window is measured against created_at, and counts rows in any status --
-- a queued-but-failed push still consumed the user's 2-hour slot, which is the
-- conservative reading of "maximum once per 2 hours per forum per user".
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- 1. Schema: read watermark + once-only quiet flag
-- ===========================================================================

-- Per-user, per-topic read watermark. Written when a user actually OPENS a
-- forum topic (not when they scroll past its card), so "3 new posts since your
-- last visit" is measured against a real visit.
CREATE TABLE IF NOT EXISTS public.forum_topic_visits (
  topic_id uuid NOT NULL REFERENCES public.forum_topics(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_visited_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (topic_id, user_id)
);

ALTER TABLE public.forum_topic_visits ENABLE ROW LEVEL SECURITY;

-- A visit row is only ever the visitor's own. Matches the topic_impressions
-- owner policy so a user can never read which OTHER users have visited a topic
-- (that would leak identity in an anonymous forum -- FORUM.md §3).
DROP POLICY IF EXISTS forum_topic_visits_owner ON public.forum_topic_visits;
CREATE POLICY forum_topic_visits_owner
ON public.forum_topic_visits FOR ALL TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

REVOKE ALL ON public.forum_topic_visits FROM PUBLIC, anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.forum_topic_visits TO authenticated;

-- Drives "sent once only, not repeated" for #6.
ALTER TABLE public.forum_topics
  ADD COLUMN IF NOT EXISTS quiet_notification_sent boolean NOT NULL DEFAULT false;

-- Supports the quiet sweep's `status = 'quiet' AND quiet_notification_sent = false`
-- scan without walking every topic.
CREATE INDEX IF NOT EXISTS idx_forum_topics_quiet_pending
  ON public.forum_topics(status)
  WHERE status = 'quiet' AND quiet_notification_sent = false;

-- Makes the per-topic "who posted here" lookup cheap for both notifications.
CREATE INDEX IF NOT EXISTS idx_forum_posts_topic_user
  ON public.forum_posts(topic_id, user_id);

-- Rate-limit lookup for #5. Partial so the jsonb extraction only spans
-- forum-activity rows.
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_forum_activity
  ON public.scheduled_notifications(user_id, ((metadata->>'topic_id')), created_at)
  WHERE metadata->>'type' = 'forum_activity';

-- ===========================================================================
-- 2. Visit recording RPC (writes the read watermark)
-- ===========================================================================

-- Called by the client when a topic detail screen is opened. Bumping the
-- watermark also resets the user's unread baseline, so notification #5 counts
-- only posts made after they last looked.
CREATE OR REPLACE FUNCTION public.record_forum_topic_visit(p_topic_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.forum_topic_visits (topic_id, user_id, last_visited_at)
  VALUES (p_topic_id, v_uid, now())
  ON CONFLICT (topic_id, user_id)
  DO UPDATE SET last_visited_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.record_forum_topic_visit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_forum_topic_visit(uuid) TO authenticated;

-- ===========================================================================
-- 3. Notification #5 -- "3 new posts in the debate"
-- ===========================================================================

-- Queues activity notifications for a topic. Recipients are the users who have
-- POSTED in this topic (never mere browsers -- §10 "NEVER NOTIFIED"), excluding
-- the author of the post that triggered this call, minus anyone who is already
-- caught up or inside their 2-hour rate-limit window.
--
-- SECURITY DEFINER and used server-side only: it reads other users' user_ids to
-- decide who to notify, but each queued row targets that recipient's own device
-- and its metadata carries no other user's identity -- only the topic. The
-- function is deliberately NOT granted to authenticated; it is invoked from
-- inside create_forum_post (also SECURITY DEFINER), so a client can never call
-- it directly to probe who participates in a topic.
CREATE OR REPLACE FUNCTION private.queue_forum_activity_notifications(
  p_topic_id uuid,
  p_exclude_user_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_content text;
  v_status text;
  v_short_title text;
  v_queued integer := 0;
BEGIN
  SELECT content, status INTO v_content, v_status
  FROM public.forum_topics
  WHERE id = p_topic_id;

  -- Only live debates generate activity pings.
  IF v_content IS NULL OR v_status <> 'active' THEN
    RETURN 0;
  END IF;

  -- §10 #5 title is the topic's short title.
  v_short_title := CASE
    WHEN char_length(v_content) > 50 THEN substr(v_content, 1, 50) || '...'
    ELSE v_content
  END;

  WITH participants AS (
    -- Everyone who has posted in this forum, except the person who just posted.
    SELECT DISTINCT fp.user_id
    FROM public.forum_posts fp
    WHERE fp.topic_id = p_topic_id
      AND fp.user_id <> p_exclude_user_id
      AND fp.removed_at IS NULL
  ),
  unread AS (
    -- Posts made since each participant last opened the topic. A participant
    -- with no visit row has never opened it, so everything counts (treated as
    -- epoch), which is why last_visited_at is COALESCEd rather than joined
    -- with an inner join.
    SELECT
      p.user_id,
      (
        SELECT count(*)
        FROM public.forum_posts np
        WHERE np.topic_id = p_topic_id
          AND np.removed_at IS NULL
          AND np.user_id <> p.user_id
          AND np.created_at > COALESCE(v.last_visited_at, '-infinity'::timestamptz)
      ) AS new_posts
    FROM participants p
    LEFT JOIN public.forum_topic_visits v
      ON v.topic_id = p_topic_id AND v.user_id = p.user_id
  ),
  eligible AS (
    SELECT u.user_id, u.new_posts
    FROM unread u
    -- §10 #5: fires when the count increases by 3 since the user's last visit.
    WHERE u.new_posts >= 3
      -- Rate limit: max once per 2 hours per forum per user.
      AND NOT EXISTS (
        SELECT 1
        FROM public.scheduled_notifications sn
        WHERE sn.user_id = u.user_id
          AND sn.metadata->>'type' = 'forum_activity'
          AND sn.metadata->>'topic_id' = p_topic_id::text
          AND sn.created_at > now() - interval '2 hours'
      )
  ),
  inserted AS (
    INSERT INTO public.scheduled_notifications (
      user_id,
      notification_type,
      scheduled_for,
      status,
      metadata,
      created_at,
      updated_at
    )
    SELECT
      e.user_id,
      'immediate',
      now(),
      'pending',
      jsonb_build_object(
        'title', v_short_title,
        'body', e.new_posts || ' new posts in the debate',
        'type', 'forum_activity',
        'topic_id', p_topic_id::text
      ),
      now(),
      now()
    FROM eligible e
    RETURNING 1
  )
  SELECT count(*) INTO v_queued FROM inserted;

  RETURN v_queued;
END;
$$;

REVOKE ALL ON FUNCTION private.queue_forum_activity_notifications(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Hook #5 into create_forum_post.
--
-- Re-declared verbatim from 20260716140000_forums_opinions_anonymity_hardening.sql
-- with two additions at the end: the poster's own read watermark is bumped (they
-- have by definition just seen the topic, so they should not be told about their
-- own post), then the activity notifications are queued. Everything above that
-- -- the ban gate, the §7 10/forum/24h limit, the 30s cooldown, the
-- relationship_status capture and the counter bumps -- is unchanged.
--
-- Notification queueing is wrapped so a failure there can never roll back a
-- successfully written post.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_forum_post(
  p_topic_id uuid,
  p_side text,
  p_content text,
  p_reply_to_post_id uuid DEFAULT NULL,
  p_quoted_text text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_count int;
  v_last timestamptz;
  v_banned_until timestamptz;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_side NOT IN ('for', 'against') THEN
    RAISE EXCEPTION 'invalid_side' USING ERRCODE = '22023';
  END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 280 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  -- Ban gate.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = v_uid;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  -- Per-forum limit: 10 posts / 24h in THIS topic, 30s cooldown in this topic.
  SELECT count(*), max(created_at) INTO v_count, v_last
  FROM public.forum_posts
  WHERE user_id = v_uid AND topic_id = p_topic_id
    AND created_at > now() - interval '24 hours';
  IF v_count >= 10 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
  IF v_last IS NOT NULL AND v_last > now() - interval '30 seconds' THEN
    RAISE EXCEPTION 'cooldown' USING ERRCODE = '53400';
  END IF;

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.forum_posts (
    topic_id, user_id, side, content, relationship_status_at_post,
    reply_to_post_id, quoted_text
  )
  VALUES (p_topic_id, v_uid, p_side, p_content, v_status, p_reply_to_post_id, p_quoted_text)
  RETURNING id INTO v_id;

  UPDATE public.forum_topics
  SET total_posts = COALESCE(total_posts, 0) + 1,
      for_posts = for_posts + CASE WHEN p_side = 'for' THEN 1 ELSE 0 END,
      against_posts = against_posts + CASE WHEN p_side = 'against' THEN 1 ELSE 0 END,
      last_post_at = now()
  WHERE id = p_topic_id;

  -- Posting is itself a visit: bump the poster's watermark so the post they
  -- just wrote never counts toward their own "new posts since last visit".
  INSERT INTO public.forum_topic_visits (topic_id, user_id, last_visited_at)
  VALUES (p_topic_id, v_uid, now())
  ON CONFLICT (topic_id, user_id)
  DO UPDATE SET last_visited_at = now();

  -- §10 #5. Never let a notification failure lose the post.
  BEGIN
    PERFORM private.queue_forum_activity_notifications(p_topic_id, v_uid);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'queue_forum_activity_notifications failed for topic %: %',
      p_topic_id, SQLERRM;
  END;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_forum_post(uuid, text, text, uuid, text) TO authenticated;

-- ===========================================================================
-- 4. Notification #6 -- "Debate going quiet"
-- ===========================================================================

-- FORUM.md §11 step 35 defines quiet as "7 days no posts". This function does
-- that transition, mirroring the shape of activate_pending_topics() /
-- expire_old_topics() -- but it is NOT scheduled and NOT called by
-- forum-quiet-check. Kept only as the documented fix for a gap discovered
-- after this migration first shipped:
--
-- A pre-existing pg_cron job, `mark-quiet-forums`, already performs this same
-- transition daily -- registered directly against the database with no
-- migration or source file anywhere in this repo, found only by querying
-- cron.job. Its condition is `last_post_at < NOW() - INTERVAL '7 days' AND
-- last_post_at IS NOT NULL`, which means a topic that activated but never
-- received a single post can NEVER go quiet (last_post_at stays NULL
-- forever). This function's WHERE clause fixes that one gap with
-- COALESCE(last_post_at, activated_at).
--
-- Rather than register a second, competing "quiet" sweep on a different clock
-- (this would run every 15 min via forum-quiet-check, mark-quiet-forums runs
-- daily), the fix is applied directly to the existing job instead -- see
-- supabase/sql/patch_mark_quiet_forums_null_last_post.sql. This function is
-- left in place, unregistered, as a record of the fix and in case the
-- decision to patch the existing job in place is ever revisited.
CREATE OR REPLACE FUNCTION public.mark_quiet_topics()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  quiet_count integer := 0;
BEGIN
  WITH went_quiet AS (
    UPDATE public.forum_topics
    SET status = 'quiet'
    WHERE status = 'active'
      AND COALESCE(last_post_at, activated_at) < now() - interval '7 days'
    RETURNING id
  )
  SELECT count(*) INTO quiet_count FROM went_quiet;

  RETURN quiet_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_quiet_topics() FROM PUBLIC, anon;

-- Queues the going-quiet notification for everyone who posted in the topic and
-- flips quiet_notification_sent so it can never fire twice ("sent once only").
--
-- The flag is flipped in the same statement-level transaction as the inserts,
-- and the UPDATE re-asserts `quiet_notification_sent = false` so two concurrent
-- sweeps cannot both queue the batch -- the second one updates zero rows and
-- returns 0 without inserting.
CREATE OR REPLACE FUNCTION public.notify_quiet_topic(p_topic_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_content text;
  v_short_title text;
  v_claimed uuid;
  v_queued integer := 0;
BEGIN
  -- Claim the topic first. If another sweep already claimed it, bail out.
  UPDATE public.forum_topics
  SET quiet_notification_sent = true
  WHERE id = p_topic_id
    AND status = 'quiet'
    AND quiet_notification_sent = false
  RETURNING id, content INTO v_claimed, v_content;

  IF v_claimed IS NULL THEN
    RETURN 0;
  END IF;

  v_short_title := CASE
    WHEN char_length(v_content) > 50 THEN substr(v_content, 1, 50) || '...'
    ELSE v_content
  END;

  WITH participants AS (
    SELECT DISTINCT fp.user_id
    FROM public.forum_posts fp
    WHERE fp.topic_id = p_topic_id
      AND fp.removed_at IS NULL
  ),
  inserted AS (
    INSERT INTO public.scheduled_notifications (
      user_id,
      notification_type,
      scheduled_for,
      status,
      metadata,
      created_at,
      updated_at
    )
    SELECT
      p.user_id,
      'immediate',
      now(),
      'pending',
      jsonb_build_object(
        'title', 'Debate going quiet',
        'body', '''' || v_short_title || ''' has gone quiet. Keep it going →',
        'type', 'forum_quiet',
        'topic_id', p_topic_id::text
      ),
      now(),
      now()
    FROM participants p
    RETURNING 1
  )
  SELECT count(*) INTO v_queued FROM inserted;

  RETURN v_queued;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_quiet_topic(uuid) FROM PUBLIC, anon;
