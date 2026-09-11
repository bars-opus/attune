-- Stories: mark_story_viewed and the private-timestamp / public-boolean
-- split (spec §3.4).
--
-- With an audience of one, WHO viewed is not a disclosure -- there is
-- only one other person. The surface that matters is the exact
-- viewed_at timestamp, which says when a partner was awake and looking
-- at their phone. The product promises seen/not-seen only, so that is
-- all any client gets: story_views has zero policies and zero grants
-- (20260938020000, 20260938100000) and is never readable directly.
--
-- The FIRST successful call therefore does two things in ONE
-- transaction:
--   1. inserts the private timestamp into story_views, ON CONFLICT DO
--      NOTHING (idempotent for repeat views by the same viewer); and
--   2. sets story_items.has_been_viewed = true.
-- The boolean lives on story_items -- a table clients already have a
-- SELECT policy and Realtime access to -- specifically so its UPDATE
-- emits a Realtime event. Subscribing to story_views directly could
-- never work, because Realtime honours its no-SELECT policy same as any
-- other read.
--
-- Refusal is a generic UNAVAILABLE result (story_intent_error, the same
-- house shape create_story_upload_intent/create_story_item use) unless
-- ALL FOUR of §3.4's conditions hold:
--   - the caller belongs to the ACTIVE, unarchived relationship;
--   - the caller is NOT the author (otherwise reviewing your own reel
--     marks your own story seen, and the indicator becomes meaningless);
--   - the story is not deleted; and
--   - expires_at > now() (an expired story opened from the calendar
--     must not record a view -- the state answers "has my partner seen
--     what I posted today," not "did they find it eight months later").
-- "Missing," "not a member," "ended relationship" and "deleted" all
-- fall through to the SAME UNAVAILABLE result -- never an existence
-- oracle for a story_item_id the caller has no business knowing about.
--
-- A successful first view bumps story_change_signals via the existing
-- internal helper bump_story_signal (Task 5, 20260938050000) -- reused,
-- not duplicated, and it stays revoked from authenticated.
CREATE OR REPLACE FUNCTION public.mark_story_viewed(
  p_story_item_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user  uuid := auth.uid();
  v_story public.story_items%ROWTYPE;
  v_inserted boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_story_item_id IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- Row-lock the story so a concurrent delete or a concurrent view by
  -- the same viewer cannot interleave with the checks below.
  SELECT * INTO v_story
    FROM public.story_items
   WHERE id = p_story_item_id
   FOR UPDATE;

  -- All four §3.4 refusal rules, evaluated as one fall-through: missing,
  -- not a member, ended relationship, deleted, author, and expired all
  -- return the identical UNAVAILABLE result.
  IF v_story.id IS NULL
     OR v_story.deleted_at IS NOT NULL
     OR v_story.author_id IS NOT DISTINCT FROM v_user
     OR v_story.expires_at <= now()
     OR NOT public.story_relationship_is_open(v_story.relationship_id, v_user)
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Private timestamp, idempotent per (story_item_id, viewer_id).
  INSERT INTO public.story_views (story_item_id, viewer_id)
  VALUES (p_story_item_id, v_user)
  ON CONFLICT (story_item_id, viewer_id) DO NOTHING;
  v_inserted := FOUND;

  IF v_inserted THEN
    -- Public boolean, in the SAME transaction as the private insert
    -- above -- this is what Realtime actually delivers to clients.
    UPDATE public.story_items
       SET has_been_viewed = true
     WHERE id = p_story_item_id
       AND has_been_viewed = false;

    PERFORM public.bump_story_signal(v_story.relationship_id);
  END IF;

  RETURN jsonb_build_object('error', false, 'viewed', true);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_story_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_story_viewed(uuid) TO authenticated;
