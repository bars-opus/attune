-- One invite lifecycle for every game.
--
-- Three games (Snakes, Word Hunt, Paint Ball) had an invitation: a
-- game_sessions row with status 'invited', which the post_game_message
-- trigger turns into a card in the conversation. The other seven opened
-- straight into themselves, so there was no way to ASK someone to play --
-- the partner learned about it only if they happened to open the game.
--
-- Nothing about that split was structural. game_sessions.game_type is
-- free text and the trigger fires on any invited row, so a Mirror invite
-- already posts a correctly labelled card; no game had one because no RPC
-- ever inserted the row. These three functions are that RPC, written once
-- rather than ten times.
--
-- Deliberately generic: this creates the SESSION and nothing else. A game
-- with its own setup (Snakes' board version, Paint Ball's tone) keeps its
-- own create function, which does that setup and is unaffected by this.
-- This is the entry point for a game whose invite needs no setup at all.

-- ---------------------------------------------------------------------
-- Errors. Same shape as every other game family: a code the client maps
-- and a sentence it can show, never a raw database message (2.4, 5.5).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_invite_error(p_code text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT jsonb_build_object(
    'error', true,
    'code', p_code,
    'message', CASE p_code
      WHEN 'UNAUTHORIZED'  THEN 'Please sign in to play games.'
      WHEN 'FORBIDDEN'     THEN 'You don''t have access to this game.'
      WHEN 'NOT_FOUND'     THEN 'Game session not found.'
      WHEN 'ALREADY_OPEN'  THEN 'You already have this game open.'
      WHEN 'RATE_LIMITED'  THEN 'Slow down a moment.'
      WHEN 'INVALID_INPUT' THEN 'Invalid value provided.'
      ELSE 'Something went wrong. Please try again.'
    END
  );
$$;

-- The games that may be invited through this path.
--
-- An allowlist rather than free text (2.1). game_type is unconstrained in
-- the table, so without this any string a client sent would become a
-- session and a card -- a chat message with attacker-chosen content,
-- posted by a SECURITY DEFINER function.
CREATE OR REPLACE FUNCTION public.game_invite_type_allowed(p_game_type text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_game_type IN (
    'this_or_that',
    'truth_or_dare',
    '36_questions',
    'mirror',
    'sliding_scale',
    'scenario',
    'love_map',
    'paint_ball',
    'snakes_and_ladders',
    'word_hunt'
  );
$$;

-- ---------------------------------------------------------------------
-- Create.
--
-- Modelled on snakes_create_session, which is the hardened reference in
-- this codebase. The order matters and is not incidental:
--   auth -> input -> membership -> locks -> key replay -> reuse ->
--   rate limit -> insert.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_invite_create(
  p_relationship_id uuid,
  p_game_type text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.game_invite_error('UNAUTHORIZED');
  END IF;

  IF p_relationship_id IS NULL
     OR p_game_type IS NULL
     OR p_idempotency_key IS NULL
     OR length(p_idempotency_key) = 0
     OR length(p_idempotency_key) > 200
     OR NOT public.game_invite_type_allowed(p_game_type)
  THEN
    RETURN public.game_invite_error('INVALID_INPUT');
  END IF;

  -- 1.4: membership is checked here, before anything is written, and the
  -- relationship must be active -- inviting into an ended relationship
  -- would post a card into a conversation that is over.
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
     WHERE id = p_relationship_id
       AND status = 'active'
       AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.game_invite_error('FORBIDDEN');
  END IF;

  -- Both locks are needed: the relationship serialises competing
  -- invitations, the key serialises the same idempotency key arriving
  -- twice at once. Taken in this order everywhere (1.6, 2.16).
  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));
  PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));

  -- 1.1 / 2.18: a retry of the SAME create returns the SAME session
  -- rather than starting a second game. Checked under the lock, so two
  -- concurrent retries cannot both miss it.
  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
    FROM public.session_idempotency_keys k
    JOIN public.game_sessions s ON s.id = k.session_id
   WHERE k.key = p_idempotency_key;
  IF v_session IS NOT NULL THEN
    -- A key that belongs to someone else's relationship, or to a
    -- different game, is not a retry -- it is a collision or a probe.
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.game_invite_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> p_game_type THEN
      RETURN public.game_invite_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  -- One game of a kind at a time per couple. Returned as the existing
  -- session rather than an error: the player asked to play this game and
  -- there is one, so hand it to them.
  SELECT id INTO v_session
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND game_type = p_game_type
     AND status IN ('invited', 'active')
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_session IS NOT NULL THEN
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  -- 2.5 / 3.8: a bounded number of invites per hour per couple. Without
  -- it, a loop here is a loop of chat messages -- the trigger posts a
  -- card for every invite.
  SELECT count(*) INTO v_recent
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND created_at > now() - interval '1 hour';
  IF v_recent >= 5 THEN
    RETURN public.game_invite_error('RATE_LIMITED');
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, status
  ) VALUES (
    p_relationship_id, v_user, p_game_type, 'invited'
  ) RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);

  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

-- ---------------------------------------------------------------------
-- Accept.
--
-- Idempotent on purpose: accepting a game already active returns success
-- rather than an error, because the tap that accepts is also the tap that
-- opens, and a double tap must not show a failure for something that
-- worked.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_invite_accept(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session record;
  v_is_member boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.game_invite_error('UNAUTHORIZED');
  END IF;
  IF p_session_id IS NULL THEN
    RETURN public.game_invite_error('INVALID_INPUT');
  END IF;

  -- Locked for update: two taps racing must not both move the row.
  SELECT * INTO v_session
    FROM public.game_sessions
   WHERE id = p_session_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.game_invite_error('NOT_FOUND');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.relationships
     WHERE id = v_session.relationship_id
       AND (user_a = v_user OR user_b = v_user)
  ) INTO v_is_member;
  IF NOT v_is_member THEN
    -- Deliberately FORBIDDEN and not NOT_FOUND: membership was already
    -- established as the question, and the row's existence is not a
    -- secret from a signed-in user who guessed a uuid.
    RETURN public.game_invite_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'active' THEN
    RETURN jsonb_build_object('session_id', p_session_id, 'status', 'active');
  END IF;
  IF v_session.status <> 'invited' THEN
    RETURN public.game_invite_error('NOT_FOUND');
  END IF;

  UPDATE public.game_sessions
     SET status = 'active',
         started_at = COALESCE(started_at, now())
   WHERE id = p_session_id;

  RETURN jsonb_build_object('session_id', p_session_id, 'status', 'active');
END;
$$;

-- ---------------------------------------------------------------------
-- Decline, which is also cancel: the sender withdrawing and the receiver
-- refusing are the same transition, and which one happened is readable
-- from initiator_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.game_invite_decline(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session record;
  v_is_member boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.game_invite_error('UNAUTHORIZED');
  END IF;
  IF p_session_id IS NULL THEN
    RETURN public.game_invite_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_session
    FROM public.game_sessions
   WHERE id = p_session_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.game_invite_error('NOT_FOUND');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.relationships
     WHERE id = v_session.relationship_id
       AND (user_a = v_user OR user_b = v_user)
  ) INTO v_is_member;
  IF NOT v_is_member THEN
    RETURN public.game_invite_error('FORBIDDEN');
  END IF;

  -- Already abandoned is success, for the same reason accept is
  -- idempotent: a second tap must not report a failure.
  IF v_session.status = 'abandoned' THEN
    RETURN jsonb_build_object('session_id', p_session_id, 'status', 'abandoned');
  END IF;
  -- A game underway is not declinable -- that is quitting, which each
  -- game owns because only it knows what quitting costs.
  IF v_session.status <> 'invited' THEN
    RETURN public.game_invite_error('NOT_FOUND');
  END IF;

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandoned_at = COALESCE(abandoned_at, now())
   WHERE id = p_session_id;

  RETURN jsonb_build_object('session_id', p_session_id, 'status', 'abandoned');
END;
$$;

-- ---------------------------------------------------------------------
-- Grants. Least privilege (7.4): authenticated callers only, and the
-- helpers stay callable because the RPCs above are SECURITY DEFINER and
-- run them as the definer regardless.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.game_invite_create(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.game_invite_accept(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.game_invite_decline(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.game_invite_create(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_invite_accept(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.game_invite_decline(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.game_invite_error(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.game_invite_type_allowed(text) FROM PUBLIC, anon;
