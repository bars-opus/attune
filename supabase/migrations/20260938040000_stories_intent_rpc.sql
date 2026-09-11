-- Stories: create_story_upload_intent, with abuse limits.
--
-- Spec §4.2 exact signature:
--   create_story_upload_intent(p_relationship_id, p_object_kind,
--     p_media_type, p_mime_type)
-- returning an intent id, a storage key, the story-media bucket and a
-- 15-minute expiry. This is the ONLY writer of
-- public.story_media_upload_intents (Task 3 left that table with zero
-- policies and REVOKEd from every client role) and the only path that
-- issues a key the storage INSERT policy (20260938030000) will accept.
--
-- Task 4's brief header names the parameter p_media_role; the spec
-- (binding authority, §4.2) names it p_object_kind with a fourth
-- parameter p_media_type carried separately, matching the table this
-- function writes into (object_kind + media_type are separate NOT NULL
-- columns per 20260938030000). This migration follows the spec.
--
-- Error shape follows the house pattern
-- (20260937100000_generic_game_invites.sql's game_invite_error): a code
-- the client maps and a sentence safe to show, never a raw database
-- message. "Missing", "not a member" and "ended relationship" all return
-- the SAME FORBIDDEN result -- never an existence oracle for a
-- relationship uuid the caller does not belong to.
CREATE OR REPLACE FUNCTION public.story_intent_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'  THEN 'Please sign in to add to your story.'
      WHEN 'FORBIDDEN'     THEN 'You don''t have access to this story.'
      WHEN 'UNAVAILABLE'   THEN 'Stories aren''t available right now.'
      WHEN 'RATE_LIMITED'  THEN 'Slow down a moment before adding more.'
      WHEN 'INVALID_INPUT' THEN 'Invalid value provided.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

-- ---------------------------------------------------------------------
-- max_bytes per (object_kind, media_type), spec §4.2's limits table.
-- Centralised here so Task 5's create_story_item enforces the ceiling
-- this intent was actually issued under, without re-deriving it.
--   media/image     -> 5MB   (5242880)
--   media/video      -> 25MB  (26214400)
--   thumbnail/image  -> 800KB (819200)  -- thumbnail MUST be image/jpeg
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.story_intent_max_bytes(
  p_object_kind text,
  p_media_type text
)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_object_kind = 'thumbnail' THEN 819200::bigint
    WHEN p_object_kind = 'media' AND p_media_type = 'image' THEN 5242880::bigint
    WHEN p_object_kind = 'media' AND p_media_type = 'video' THEN 26214400::bigint
    ELSE NULL
  END;
$$;

-- ---------------------------------------------------------------------
-- create_story_upload_intent.
--
-- Order: auth -> input validation -> membership (open relationship) ->
-- feature flag -> abuse limits -> insert. Membership is checked before
-- the flag or the limits, matching the game-invite precedent, so a
-- non-member never learns whether the relationship exists, is open, or
-- is flag-gated from a different error code or timing.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_story_upload_intent(
  p_relationship_id uuid,
  p_object_kind text,
  p_media_type text,
  p_mime_type text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_storage_key text;
  v_max_bytes bigint;
  v_open_intents int;
  v_recent_calls int;
  v_intent_id uuid;
  v_expires_at timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.story_intent_error('UNAUTHORIZED');
  END IF;

  -- Input validation. p_object_kind is 'media' or 'thumbnail'; a
  -- thumbnail MUST be image/jpeg; main media MUST be image/jpeg or
  -- video/mp4 (spec §4.2). media_type must agree with mime_type so the
  -- stored media_type column (which Task 5 trusts to derive the
  -- finalized story's media_type, per the storage migration's comment)
  -- can never disagree with the MIME the object will actually be.
  IF p_relationship_id IS NULL
     OR p_object_kind IS NULL
     OR p_media_type IS NULL
     OR p_mime_type IS NULL
     OR p_object_kind NOT IN ('media', 'thumbnail')
     OR p_media_type NOT IN ('image', 'video')
  THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  IF p_object_kind = 'thumbnail' THEN
    IF p_media_type <> 'image' OR p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  ELSE -- p_object_kind = 'media'
    IF p_media_type = 'image' AND p_mime_type <> 'image/jpeg' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
    IF p_media_type = 'video' AND p_mime_type <> 'video/mp4' THEN
      RETURN public.story_intent_error('INVALID_INPUT');
    END IF;
  END IF;

  v_max_bytes := public.story_intent_max_bytes(p_object_kind, p_media_type);
  IF v_max_bytes IS NULL THEN
    RETURN public.story_intent_error('INVALID_INPUT');
  END IF;

  -- Membership: ACTIVE, unarchived, and the caller is a party to it.
  -- story_relationship_is_open is the shared SECURITY DEFINER helper
  -- (20260938020000) -- reused rather than rewriting the predicate, per
  -- the brief. "Missing", "not a member" and "ended relationship" all
  -- fall through this same false branch to the same FORBIDDEN result.
  IF NOT public.story_relationship_is_open(p_relationship_id, v_user) THEN
    RETURN public.story_intent_error('FORBIDDEN');
  END IF;

  -- §8: the stories flag gates NEW upload intents only. Finalization of
  -- an already-issued intent, reads, and author deletion are unaffected
  -- and stay enabled -- that is Tasks 5/7/8's business, not this
  -- function's.
  IF COALESCE(
    (SELECT enabled FROM public.feature_flags WHERE key = 'stories'),
    false
  ) = false THEN
    RETURN public.story_intent_error('UNAVAILABLE');
  END IF;

  -- Abuse limit 1: at most 20 unconsumed, unexpired intents held at
  -- once. Checked before the hourly cap so a caller sitting at the
  -- intent ceiling gets the same RATE_LIMITED code regardless of how
  -- many calls they made this hour.
  SELECT count(*) INTO v_open_intents
    FROM public.story_media_upload_intents
   WHERE requester_id = v_user
     AND used_at IS NULL
     AND expires_at > now();
  IF v_open_intents >= 20 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  -- Abuse limit 2: at most 120 intent calls per rolling one-hour
  -- server window. Every finalized story consumes two intents, so 120
  -- still allows 60 stories/hour while bounding abandoned-upload abuse
  -- (spec §4.2). Counted against ALL intents created in the window,
  -- consumed or not -- this is a call-rate cap, not a "how many do you
  -- hold" cap (that's the check above).
  SELECT count(*) INTO v_recent_calls
    FROM public.story_media_upload_intents
   WHERE requester_id = v_user
     AND created_at > now() - interval '1 hour';
  IF v_recent_calls >= 120 THEN
    RETURN public.story_intent_error('RATE_LIMITED');
  END IF;

  v_storage_key := 'story-media/' || p_relationship_id::text || '/'
    || v_user::text || '/' || encode(gen_random_bytes(16), 'hex')
    || '-' || p_object_kind;
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO public.story_media_upload_intents (
    relationship_id, requester_id, object_kind, media_type, mime_type,
    storage_key, max_bytes, expires_at
  ) VALUES (
    p_relationship_id, v_user, p_object_kind, p_media_type, p_mime_type,
    v_storage_key, v_max_bytes, v_expires_at
  ) RETURNING id INTO v_intent_id;

  RETURN jsonb_build_object(
    'intent_id', v_intent_id,
    'storage_key', v_storage_key,
    'bucket', 'story-media',
    'expires_at', v_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_upload_intent(uuid, text, text, text)
  TO authenticated;

REVOKE ALL ON FUNCTION public.story_intent_error(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_intent_error(text) TO authenticated;

REVOKE ALL ON FUNCTION public.story_intent_max_bytes(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.story_intent_max_bytes(text, text) TO authenticated;
