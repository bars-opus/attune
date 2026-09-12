-- Stories: fix create_story_item's idempotency under real concurrency.
--
-- Found by scripts/concurrency/story_races.sh's race 1 (Task 11): two
-- connections calling create_story_item with the SAME (author_id,
-- client_story_id) AND the SAME two intent ids -- exactly the "client
-- lost the response and retried with an identical request body" shape
-- that client_story_id and the table's (author_id, client_story_id)
-- UNIQUE constraint exist to make safe -- deterministically produced
-- ONE caller succeeding and the OTHER receiving UNAVAILABLE, not the
-- same story_id. Reproduced on every run (5/5) against the harness
-- fixture, not an occasional flake.
--
-- Root cause: 20260938050000's early existing-row lookup
-- ("Idempotency, checked before anything else touches the intents")
-- runs once, before either caller has locked anything. When both
-- callers miss it (neither has committed a row yet), the loser then
-- blocks on `SELECT ... FOR UPDATE` against the intent rows until the
-- winner COMMITS -- and the winner's transaction, by the time it
-- commits, has already stamped used_at on both intents as part of the
-- SAME commit that inserted the story row. The loser's lock is granted
-- immediately after, sees used_at IS NOT NULL, and its
-- `used_at IS NOT NULL` guard treats that identically to "this intent
-- was already spent by an unrelated call" -- returning UNAVAILABLE.
-- The INSERT ... ON CONFLICT (author_id, client_story_id) DO NOTHING
-- branch further down is never reached, because the loser fails at the
-- intent-validation step, before it ever gets there. That ON CONFLICT
-- branch is correct and does close the race for the case where the
-- INSERT itself is attempted twice; the bug is that the loser's path
-- never reaches the INSERT in the first place.
--
-- Fix: when (and only when) a caller's own intent lock reveals
-- used_at IS NOT NULL -- i.e. exactly the condition that can only be
-- true because SOME transaction already consumed this intent -- re-run
-- the idempotency lookup before concluding UNAVAILABLE. If a story now
-- exists for this caller's (author_id, client_story_id), this was a
-- losing replay, not a genuine failure, and the winner's row is
-- returned with existing = true, matching the sequential-replay
-- contract exactly. Every OTHER failure reason on the same IF (wrong
-- requester, wrong relationship, wrong object_kind, or a genuinely
-- expired-and-never-consumed intent) leaves v_existing_id NULL, so
-- those still fall through to the same UNAVAILABLE result as before --
-- this migration narrows nothing else about the function's behaviour.
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

  -- Idempotency, checked before anything else touches the intents (as
  -- before). Handles the SEQUENTIAL replay case: a caller whose earlier
  -- call already committed sees its row here and never touches the
  -- intents at all.
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
  -- Lock BOTH intents FOR UPDATE before validating anything about them
  -- (as before). CONCURRENCY FIX: when the lock reveals used_at IS NOT
  -- NULL, re-check idempotency before failing -- see this migration's
  -- header for why that specific condition, and only that condition,
  -- needs the re-check.
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
    IF v_media_intent.used_at IS NOT NULL THEN
      SELECT id INTO v_existing_id
        FROM public.story_items
       WHERE author_id = v_user
         AND client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
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
    IF v_thumb_intent.used_at IS NOT NULL THEN
      SELECT id INTO v_existing_id
        FROM public.story_items
       WHERE author_id = v_user
         AND client_story_id = p_client_story_id;
      IF v_existing_id IS NOT NULL THEN
        RETURN jsonb_build_object('story_id', v_existing_id, 'existing', true);
      END IF;
    END IF;
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
  -- concurrency-safe idempotency net for two simultaneous replays whose
  -- intent pairs DIFFER (so neither blocks on the other's intent locks
  -- above, and both reach this INSERT) -- the case the re-checks above
  -- do not cover, because both intent locks succeed for both callers.
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

-- Grants are unchanged from 20260938050000 -- REPLACE preserves them,
-- but re-issuing is harmless and keeps this migration self-contained.
REVOKE ALL ON FUNCTION public.create_story_item(
  uuid, uuid, uuid, uuid, int, int, int, int
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(
  uuid, uuid, uuid, uuid, int, int, int, int
) TO authenticated;
