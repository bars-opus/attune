-- create_forum_topic left the submitter's auto-upvote/auto-impression as
-- bare DEFAULT-1 counters on forum_topics (upvote_count, seen_count) with no
-- corresponding row in topic_votes/topic_impressions. FORUM.md §5.2:
-- "submitter's vote = 'up' automatically... submitter's impression
-- recorded (they count as having seen it)" — describes real rows, not just
-- a starting counter value.
--
-- Consequence of the gap: activate-topics' voter notification query
-- (`SELECT user_id, vote_type FROM topic_votes WHERE topic_id = ...`, see
-- the activate-topics edge function) never finds the submitter, so they are
-- never notified when their own topic goes live. And since
-- topic_impressions has UNIQUE(topic_id, user_id) with no submitter row, the
-- submitter could in principle still trigger a fresh impression insert later
-- (client impression tracking is keyed off ON CONFLICT DO NOTHING, so this
-- was harmless, but it left seen_count's "starts at 1" claim unbacked by an
-- actual impression record).

CREATE OR REPLACE FUNCTION public.create_forum_topic(p_content text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF p_content IS NULL OR char_length(btrim(p_content)) = 0 OR char_length(p_content) > 120 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  PERFORM private.assert_can_post(v_uid, 'topic');

  SELECT relationship_status INTO v_status FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.forum_topics (submitted_by, relationship_status_at_submit, content)
  VALUES (v_uid, v_status, p_content)
  RETURNING id INTO v_id;

  -- Submitter counts as the first upvote and the first impression — the
  -- table already defaults upvote_count/seen_count to 1 for exactly this,
  -- but the actual rows were missing. Insert them now so voter-notification
  -- and impression-dedup queries see the submitter like any other voter.
  INSERT INTO public.topic_votes (topic_id, user_id, vote_type)
  VALUES (v_id, v_uid, 'up');

  INSERT INTO public.topic_impressions (topic_id, user_id)
  VALUES (v_id, v_uid);

  RETURN v_id;
END;
$$;
