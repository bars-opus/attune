-- Stories: create_story_item, the idempotent finalization RPC.
--
-- Spec §3.3 exact signature:
--   create_story_item(p_relationship_id, p_client_story_id,
--     p_media_intent_id, p_thumbnail_intent_id, p_media_width,
--     p_media_height, p_duration_ms, p_utc_offset_minutes)
-- returning {story_id, existing}.
--
-- This function derives author_id and media_type -- neither is a client
-- parameter (§3.3). It does NOT check the `stories` feature flag: per
-- spec §8's rollout-flag row, the flag gates the camera/rings and NEW
-- upload intents only; finalizing an intent already issued stays enabled
-- so a rollout flip never strands an in-flight upload.
--
-- Idempotency (§3.3, brief contract 1): a retry with the same
-- (author_id, client_story_id) must return the SAME row, not a second
-- one, even though by the time of the retry both intents the first call
-- consumed are already used_at-stamped. So the existing-row lookup runs
-- BEFORE any intent validation -- a replay never re-validates intents it
-- already spent. The INSERT itself still carries
-- ON CONFLICT (author_id, client_story_id) DO NOTHING as a second,
-- concurrency-safe idempotency layer for two simultaneous replays racing
-- each other (the early lookup alone has a TOCTOU gap between two
-- concurrent callers; the ON CONFLICT branch is what closes it).
--
-- Error shape follows the house pattern (story_intent_error, itself
-- following game_invite_error): a code the client maps and a sentence
-- safe to show. Per this task's Global Constraints, "missing," "not a
-- member," "ended relationship" and "already consumed" all return the
-- SAME UNAVAILABLE result -- never an existence oracle for an intent id
-- or relationship uuid the caller does not own.
CREATE OR REPLACE FUNCTION public.create_story_item(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_user            uuid := auth.uid();
  v_existing_id     uuid;
  v_media_intent    public.story_media_upload_intents%ROWTYPE;
  v_thumb_intent    public.story_media_upload_intents%ROWTYPE;
  v_media_object     storage.objects%ROWTYPE;
  v_thumb_object     storage.objects%ROWTYPE;
  v_media_size      bigint;
  v_media_mime      text;
  v_thumb_size      bigint;
  v_thumb_mime      text;
  v_offset          int;
  v_now             timestamptz;
  v_occurred_on     date;
  v_story_id        uuid;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_client_story_id IS NULL
     OR p_media_intent_id IS NULL
     OR p_thumbnail_intent_id IS NULL
     OR p_media_width IS NULL OR p_media_width <= 0
     OR p_media_height IS NULL OR p_media_height <= 0
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- ---------------------------------------------------------------------
  -- Idempotency, checked before anything else touches the intents.
  -- A retry with the same (author_id, client_story_id) returns the
  -- existing item. NULL-safe: author_id/client_story_id are both
  -- NOT NULL columns, so a plain equality lookup here is fine, but the
  -- house rule is IS DISTINCT FROM for every SELECT...INTO comparison,
  -- so that is what gates the branch below.
  -- ---------------------------------------------------------------------
  SELECT id INTO v_existing_id
    FROM public.story_items
   WHERE author_id = v_user
     AND client_story_id = p_client_story_id;
  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
  END IF;

  -- Membership: ACTIVE, unarchived, caller is a party. "Missing," "not
  -- a member" and "ended relationship" all fall through this same false
  -- branch to the same UNAVAILABLE result -- never an existence oracle.
  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- ---------------------------------------------------------------------
  -- Lock BOTH intents FOR UPDATE before validating anything about them,
  -- so a concurrent finalize attempt on the same intents cannot interleave
  -- with this one (brief contract 6: both must be consumed in the same
  -- transaction; failing the second leaves the first unconsumed -- which
  -- this transaction's atomicity gives for free as long as we do not
  -- commit any partial consumption, which we do not: used_at is stamped
  -- for both only once every check below has passed).
  -- ---------------------------------------------------------------------
  SELECT * INTO v_media_intent
    FROM public.story_media_upload_intents
   WHERE id = p_media_intent_id
   FOR UPDATE;
  IF v_media_intent.id IS NULL
     OR v_media_intent.requester_id IS DISTINCT FROM v_user
     OR v_media_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_media_intent.object_kind IS DISTINCT FROM 'media'
     OR v_media_intent.used_at IS NOT NULL
     OR v_media_intent.expires_at <= now()
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_intent
    FROM public.story_media_upload_intents
   WHERE id = p_thumbnail_intent_id
   FOR UPDATE;
  IF v_thumb_intent.id IS NULL
     OR v_thumb_intent.requester_id IS DISTINCT FROM v_user
     OR v_thumb_intent.relationship_id IS DISTINCT FROM p_relationship_id
     OR v_thumb_intent.object_kind IS DISTINCT FROM 'thumbnail'
     OR v_thumb_intent.used_at IS NOT NULL
     OR v_thumb_intent.expires_at <= now()
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- media_type is DERIVED from the media intent, never a client
  -- parameter (§3.3). Duration must agree with it exactly the way
  -- story_duration_matches_type will enforce at insert, checked here
  -- too so a bad combination gets the house error shape instead of a
  -- raw constraint-violation exception.
  IF v_media_intent.media_type = 'video' THEN
    IF p_duration_ms IS NULL OR p_duration_ms < 500 OR p_duration_ms > 60000 THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE -- 'image'
    IF p_duration_ms IS NOT NULL THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  -- ---------------------------------------------------------------------
  -- Object existence, MIME and size, read from storage.objects and
  -- checked against the ceiling this specific intent was issued under
  -- (story_intent_max_bytes, applied at intent-creation time and stored
  -- as max_bytes on the intent row -- see 20260938040000). Same shape as
  -- the chat precedent (validate_message_media_before_insert,
  -- 20260705200000): metadata->>'size' for size,
  -- metadata->>'mimetype' falling back to metadata->>'contentType' for
  -- MIME, since different storage-client versions populate one or the
  -- other.
  -- ---------------------------------------------------------------------
  SELECT * INTO v_media_object
    FROM storage.objects
   WHERE bucket_id = 'story-media' AND name = v_media_intent.storage_key;
  IF v_media_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_media_size := COALESCE((v_media_object.metadata->>'size')::bigint, 0);
  v_media_mime := COALESCE(v_media_object.metadata->>'mimetype',
                           v_media_object.metadata->>'contentType');
  IF v_media_size <= 0
     OR v_media_size > v_media_intent.max_bytes
     OR v_media_mime IS DISTINCT FROM v_media_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  SELECT * INTO v_thumb_object
    FROM storage.objects
   WHERE bucket_id = 'story-media' AND name = v_thumb_intent.storage_key;
  IF v_thumb_object.id IS NULL THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;
  v_thumb_size := COALESCE((v_thumb_object.metadata->>'size')::bigint, 0);
  v_thumb_mime := COALESCE(v_thumb_object.metadata->>'mimetype',
                           v_thumb_object.metadata->>'contentType');
  IF v_thumb_size <= 0
     OR v_thumb_size > v_thumb_intent.max_bytes
     OR v_thumb_mime IS DISTINCT FROM v_thumb_intent.mime_type
  THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- ---------------------------------------------------------------------
  -- One captured `now()` for created_at, expires_at and occurred_on
  -- (§3.3, §3.5). occurred_on is the poster's civil date at v_now --
  -- midnight to midnight, no cutoff -- using p_utc_offset_minutes
  -- clamped to [-840, 840] (spec §3.5's explicit range; same
  -- greatest/least/coalesce clamping shape as the streak RPC precedent,
  -- chat_conversation_streak in 20260711140000_chat_streak_hardening.sql,
  -- which clamps to its own [-720, 840] chat-specific range). The offset
  -- is advisory, not trusted: nothing here re-derives it from anything
  -- server-observed, and the worst a wrong value does is file the story
  -- under the adjacent date in this couple's own calendar.
  -- ---------------------------------------------------------------------
  v_offset := greatest(-840, least(840, coalesce(p_utc_offset_minutes, 0)));
  v_now := now();
  v_occurred_on := (v_now + make_interval(mins => v_offset))::date;

  -- ---------------------------------------------------------------------
  -- Insert. ON CONFLICT (author_id, client_story_id) DO NOTHING is the
  -- concurrency-safe idempotency net for two simultaneous replays (the
  -- early SELECT above already handled the sequential-replay case and
  -- is why a replay never re-validates already-consumed intents).
  -- Every server-owned column here is computed above, not taken from
  -- any client parameter: the signature has no expires_at, occurred_on,
  -- media_key, thumbnail_key or relationship_id-override parameter at
  -- all, so a client cannot supply a storage key or any server-owned
  -- field even if it wanted to.
  -- ---------------------------------------------------------------------
  INSERT INTO public.story_items (
    client_story_id, relationship_id, author_id, media_type,
    media_key, thumbnail_key, media_width, media_height, duration_ms,
    occurred_on, created_at, expires_at
  ) VALUES (
    p_client_story_id, p_relationship_id, v_user, v_media_intent.media_type,
    v_media_intent.storage_key, v_thumb_intent.storage_key,
    p_media_width, p_media_height, p_duration_ms,
    v_occurred_on, v_now, v_now + interval '24 hours'
  )
  ON CONFLICT (author_id, client_story_id) DO NOTHING
  RETURNING id INTO v_story_id;

  IF v_story_id IS NULL THEN
    -- Lost a concurrent race with another replay of the same call.
    -- Neither intent has been consumed by THIS invocation (the UPDATEs
    -- below have not run yet), so nothing to unwind; just report the
    -- winner's row as the existing item.
    SELECT id INTO v_story_id
      FROM public.story_items
     WHERE author_id = v_user AND client_story_id = p_client_story_id;
    RETURN jsonb_build_object('story_id', v_story_id, 'existing', true);
  END IF;

  -- Consume both intents in the same transaction as the insert above.
  -- If either UPDATE somehow failed to find its row, the whole
  -- transaction (including the INSERT) rolls back with it -- there is
  -- no path that commits a story with an unconsumed or partially
  -- consumed intent pair.
  UPDATE public.story_media_upload_intents
     SET used_at = v_now
   WHERE id = v_media_intent.id;
  UPDATE public.story_media_upload_intents
     SET used_at = v_now
   WHERE id = v_thumb_intent.id;

  PERFORM public.bump_story_signal(p_relationship_id);

  RETURN jsonb_build_object('story_id', v_story_id, 'existing', false);
END;
$$;

-- bump_story_signal: shared helper, named exactly this so Task 6 finds
-- it rather than writing its own. UPSERT rather than UPDATE because a
-- relationship's first story is also its first signal row.
CREATE OR REPLACE FUNCTION public.bump_story_signal(p_relationship_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.story_change_signals (relationship_id, version, updated_at)
  VALUES (p_relationship_id, 1, now())
  ON CONFLICT (relationship_id)
  DO UPDATE SET version = public.story_change_signals.version + 1,
                updated_at = now();
$$;

REVOKE ALL ON FUNCTION public.create_story_item(
  uuid, uuid, uuid, uuid, int, int, int, int
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(
  uuid, uuid, uuid, uuid, int, int, int, int
) TO authenticated;

-- Internal helper, called only from SECURITY DEFINER functions (this
-- one now, mark_story_viewed in Task 6). Not granted to authenticated,
-- matching the "internal helper" class this task's own precedent
-- (story_relationship_is_open) argues should stay narrow -- unlike
-- story_intent_error/story_intent_max_bytes, which Task 4 granted
-- broadly and flagged as an unnecessary-widening deferral. This one
-- takes only a relationship id and mutates a signals row with no
-- membership check of its own, so it must never be directly callable.
REVOKE ALL ON FUNCTION public.bump_story_signal(uuid) FROM PUBLIC, anon, authenticated;
