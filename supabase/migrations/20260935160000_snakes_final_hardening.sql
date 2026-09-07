-- Snakes and Ladders: close the lifecycle and integrity gaps left by the
-- first review pass. This is forward-only because the earlier migrations
-- may already be deployed.

-- A pinned board version must continue to exist. The immutability trigger
-- guarded feature edits, but a primary-key rename could still orphan every
-- session using that board.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'game_sessions_snakes_board_version_fkey'
      AND conrelid = 'public.game_sessions'::regclass
  ) THEN
    ALTER TABLE public.game_sessions
      ADD CONSTRAINT game_sessions_snakes_board_version_fkey
      FOREIGN KEY (board_version)
      REFERENCES public.snakes_boards(version);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.guard_snakes_board_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF EXISTS (SELECT 1 FROM public.game_sessions
                WHERE board_version = OLD.version) THEN
      RAISE EXCEPTION
        'board % has been played on and cannot be deleted', OLD.version;
    END IF;
    RETURN OLD;
  END IF;

  IF (OLD.version IS DISTINCT FROM NEW.version
      OR OLD.features IS DISTINCT FROM NEW.features)
     AND EXISTS (SELECT 1 FROM public.game_sessions
                  WHERE board_version = OLD.version) THEN
    RAISE EXCEPTION
      'board % has been played on; add a new version instead', OLD.version;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.guard_snakes_board_immutable()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_snakes_board()
  FROM PUBLIC, anon, authenticated;

-- Ending or archiving a relationship ends its live games immediately.
CREATE OR REPLACE FUNCTION public.abandon_snakes_on_relationship_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' AND NEW.chat_archived_at IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.game_sessions
     SET status = 'abandoned',
         abandon_reason = 'user_initiated',
         abandoned_at = now(),
         current_turn_user_id = NULL
   WHERE relationship_id = NEW.id
     AND game_type = 'snakes_and_ladders'
     AND status IN ('invited', 'active');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS abandon_snakes_on_relationship_change
  ON public.relationships;
CREATE TRIGGER abandon_snakes_on_relationship_change
AFTER UPDATE OF status, chat_archived_at ON public.relationships
FOR EACH ROW
WHEN (
  OLD.status IS DISTINCT FROM NEW.status
  OR OLD.chat_archived_at IS DISTINCT FROM NEW.chat_archived_at
)
EXECUTE FUNCTION public.abandon_snakes_on_relationship_change();

REVOKE ALL ON FUNCTION public.abandon_snakes_on_relationship_change()
  FROM PUBLIC, anon, authenticated;

UPDATE public.game_sessions s
   SET status = 'abandoned',
       abandon_reason = 'user_initiated',
       abandoned_at = now(),
       current_turn_user_id = NULL
  FROM public.relationships r
 WHERE r.id = s.relationship_id
   AND s.game_type = 'snakes_and_ladders'
   AND s.status IN ('invited', 'active')
   AND (r.status <> 'active' OR r.chat_archived_at IS NOT NULL);

CREATE OR REPLACE FUNCTION public.expire_snakes_for_relationship(
  p_relationship_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.game_sessions s
     SET status = 'abandoned', abandoned_at = now(),
         current_turn_user_id = NULL
   WHERE s.relationship_id = p_relationship_id
     AND s.game_type = 'snakes_and_ladders'
     AND (
       (s.status = 'invited'
        AND s.created_at < now() - interval '48 hours')
       OR
       (s.status = 'active'
        AND COALESCE(
          (SELECT max(r.created_at) FROM public.game_session_rounds r
            WHERE r.session_id = s.id),
          s.started_at, s.created_at
        ) < now() - interval '24 hours')
     );
$$;

REVOKE ALL ON FUNCTION public.expire_snakes_for_relationship(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.snakes_create_session(
  p_relationship_id uuid,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session uuid;
  v_key_relationship uuid;
  v_key_game_type text;
  v_recent int;
  v_board text;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;
  IF p_relationship_id IS NULL
     OR p_idempotency_key IS NULL OR btrim(p_idempotency_key) = ''
     OR char_length(p_idempotency_key) > 200 THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND status = 'active'
      AND chat_archived_at IS NULL
      AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  -- Both locks are needed: relationship serialises competing invitations;
  -- key serialises the same idempotency key used across relationships.
  PERFORM pg_advisory_xact_lock(hashtext(p_relationship_id::text));
  PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));

  SELECT k.session_id, s.relationship_id, s.game_type
    INTO v_session, v_key_relationship, v_key_game_type
    FROM public.session_idempotency_keys k
    JOIN public.game_sessions s ON s.id = k.session_id
   WHERE k.key = p_idempotency_key;
  IF v_session IS NOT NULL THEN
    IF v_key_relationship <> p_relationship_id THEN
      RETURN public.snakes_error('FORBIDDEN');
    END IF;
    IF v_key_game_type <> 'snakes_and_ladders' THEN
      RETURN public.snakes_error('INVALID_INPUT');
    END IF;
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  PERFORM public.expire_snakes_for_relationship(p_relationship_id);
  SELECT id INTO v_session
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND game_type = 'snakes_and_ladders'
     AND status IN ('invited', 'active')
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_session IS NOT NULL THEN
    RETURN jsonb_build_object('session_id', v_session, 'existing', true);
  END IF;

  SELECT count(*) INTO v_recent
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND created_at > now() - interval '1 hour';
  IF v_recent >= 5 THEN
    RETURN public.snakes_error('RATE_LIMITED');
  END IF;

  SELECT version INTO v_board
    FROM public.snakes_boards
   WHERE retired_at IS NULL
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_board IS NULL THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  INSERT INTO public.game_sessions (
    relationship_id, initiator_id, game_type, status,
    board_position_a, board_position_b, board_version,
    current_round, total_rounds, total_rounds_completed
  ) VALUES (
    p_relationship_id, v_user, 'snakes_and_ladders', 'invited',
    0, 0, v_board, 1, 0, 0
  ) RETURNING id INTO v_session;

  INSERT INTO public.session_idempotency_keys (key, session_id)
  VALUES (p_idempotency_key, v_session);
  RETURN jsonb_build_object('session_id', v_session, 'existing', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_active_snakes_session(
  p_relationship_id uuid
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
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
     WHERE id = p_relationship_id
       AND status = 'active'
       AND chat_archived_at IS NULL
       AND (user_a = v_user OR user_b = v_user)
  ) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  PERFORM public.expire_snakes_for_relationship(p_relationship_id);
  SELECT id INTO v_session
    FROM public.game_sessions
   WHERE relationship_id = p_relationship_id
     AND game_type = 'snakes_and_ladders'
     AND status IN ('invited', 'active')
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_session IS NULL THEN
    RETURN jsonb_build_object('session_id', NULL);
  END IF;
  RETURN public.get_snakes_session_state(v_session);
END;
$$;

CREATE OR REPLACE FUNCTION public.snakes_accept_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'snakes_and_ladders'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  IF v_session.status = 'active' THEN
    RETURN jsonb_build_object('ok', true, 'existing', true);
  END IF;
  IF v_session.status <> 'invited'
     OR v_rel.status <> 'active'
     OR v_rel.chat_archived_at IS NOT NULL
     OR v_session.created_at < now() - interval '48 hours' THEN
    IF v_session.status = 'invited' THEN
      UPDATE public.game_sessions
         SET status = 'abandoned', abandoned_at = now(),
             current_turn_user_id = NULL
       WHERE id = p_session_id;
    END IF;
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;
  IF v_session.initiator_id = v_user THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  UPDATE public.game_sessions
     SET status = 'active', started_at = COALESCE(started_at, now()),
         current_turn_user_id = v_user
   WHERE id = p_session_id;
  RETURN jsonb_build_object('ok', true, 'existing', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.snakes_roll_die(
  p_session_id uuid,
  p_round_number int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_session public.game_sessions%ROWTYPE;
  v_rel public.relationships%ROWTYPE;
  v_existing public.game_session_rounds%ROWTYPE;
  v_partner uuid;
  v_is_a boolean;
  v_from smallint;
  v_roll smallint;
  v_features jsonb;
  v_move jsonb;
  v_to smallint;
  v_won boolean;
  v_last_activity timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RETURN public.snakes_error('UNAUTHORIZED');
  END IF;
  IF p_round_number IS NULL OR p_round_number < 1 THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  SELECT * INTO v_session FROM public.game_sessions
  WHERE id = p_session_id AND game_type = 'snakes_and_ladders'
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  SELECT * INTO v_rel FROM public.relationships
  WHERE id = v_session.relationship_id;
  IF NOT FOUND OR (v_rel.user_a <> v_user AND v_rel.user_b <> v_user) THEN
    RETURN public.snakes_error('FORBIDDEN');
  END IF;

  -- Idempotency is intentionally the first rejection after identity and
  -- membership. A committed roll remains recoverable after completion,
  -- expiry, rate limiting, or relationship teardown.
  SELECT * INTO v_existing FROM public.game_session_rounds
  WHERE session_id = p_session_id
    AND round_number = p_round_number
    AND active_partner_id = v_user;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'existing', true,
      'die_roll', v_existing.die_roll,
      'moved_from', v_existing.moved_from,
      'rolled_to', v_existing.rolled_to,
      'moved_to', v_existing.moved_to,
      'movement_kind', v_existing.movement_kind,
      'did_bounce', v_existing.did_bounce,
      'round_number', p_round_number,
      'position_a', v_session.board_position_a,
      'position_b', v_session.board_position_b,
      'current_turn_user_id', v_session.current_turn_user_id,
      'winner_user_id', v_session.winner_user_id,
      'won', v_session.winner_user_id = v_user
    );
  END IF;

  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;

  SELECT COALESCE(max(r.created_at), v_session.started_at, v_session.created_at)
    INTO v_last_activity
    FROM public.game_session_rounds r
   WHERE r.session_id = p_session_id;
  IF v_session.status = 'active'
     AND v_last_activity < now() - interval '24 hours' THEN
    UPDATE public.game_sessions
       SET status = 'abandoned', abandoned_at = now(),
           current_turn_user_id = NULL
     WHERE id = p_session_id;
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.game_session_rounds r
    WHERE r.session_id = p_session_id
      AND r.active_partner_id = v_user
      AND r.created_at > now() - interval '1 second'
  ) THEN
    RETURN public.snakes_error('RATE_LIMITED');
  END IF;
  IF v_session.status = 'completed' THEN
    RETURN public.snakes_error('GAME_OVER');
  END IF;
  IF v_session.status <> 'active' THEN
    RETURN public.snakes_error('SESSION_EXPIRED');
  END IF;
  IF v_session.current_turn_user_id IS DISTINCT FROM v_user THEN
    RETURN public.snakes_error('NOT_YOUR_TURN');
  END IF;
  IF p_round_number <> GREATEST(COALESCE(v_session.current_round, 1), 1) THEN
    RETURN public.snakes_error('INVALID_INPUT');
  END IF;

  SELECT features INTO v_features FROM public.snakes_boards
  WHERE version = v_session.board_version;
  IF v_features IS NULL THEN
    RETURN public.snakes_error('NOT_FOUND');
  END IF;

  v_is_a := v_rel.user_a = v_user;
  v_partner := CASE WHEN v_is_a THEN v_rel.user_b ELSE v_rel.user_a END;
  v_from := CASE WHEN v_is_a
                 THEN v_session.board_position_a
                 ELSE v_session.board_position_b END;
  v_roll := floor(random() * 6)::smallint + 1;
  v_move := public.snakes_resolve_move(v_from, v_roll, v_features);
  v_to := (v_move->>'moved_to')::smallint;

  INSERT INTO public.game_session_rounds (
    session_id, round_number, active_partner_id, game_type,
    die_roll, moved_from, rolled_to, moved_to, movement_kind, did_bounce
  ) VALUES (
    p_session_id, p_round_number, v_user, 'snakes_and_ladders',
    v_roll, v_from, (v_move->>'rolled_to')::smallint, v_to,
    v_move->>'movement_kind', (v_move->>'did_bounce')::boolean
  );

  v_won := v_to = 100;
  IF v_is_a THEN
    UPDATE public.game_sessions SET board_position_a = v_to
     WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions SET board_position_b = v_to
     WHERE id = p_session_id;
  END IF;

  IF v_won THEN
    UPDATE public.game_sessions
       SET status = 'completed', completed_at = now(),
           winner_user_id = v_user, current_turn_user_id = NULL,
           total_rounds_completed = p_round_number
     WHERE id = p_session_id;
  ELSE
    UPDATE public.game_sessions
       SET current_turn_user_id = v_partner,
           current_round = p_round_number + 1,
           total_rounds_completed = p_round_number
     WHERE id = p_session_id;
  END IF;

  SELECT * INTO v_session FROM public.game_sessions WHERE id = p_session_id;
  RETURN jsonb_build_object(
    'ok', true, 'existing', false,
    'die_roll', v_roll,
    'moved_from', v_from,
    'rolled_to', (v_move->>'rolled_to')::smallint,
    'moved_to', v_to,
    'movement_kind', v_move->>'movement_kind',
    'did_bounce', (v_move->>'did_bounce')::boolean,
    'round_number', p_round_number,
    'position_a', v_session.board_position_a,
    'position_b', v_session.board_position_b,
    'current_turn_user_id', v_session.current_turn_user_id,
    'winner_user_id', v_session.winner_user_id,
    'won', v_won
  );
END;
$$;

-- Helpers are implementation details. SECURITY DEFINER entry points can call
-- them as owner; players need only the public game RPCs.
REVOKE ALL ON FUNCTION public.snakes_error(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.snakes_resolve_move(smallint, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- Keep SQL-generated cards and push notifications aligned with the client.
CREATE OR REPLACE FUNCTION public.game_type_display_name(p_game_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    CASE p_game_type
      WHEN 'this_or_that'       THEN 'This or That'
      WHEN 'truth_or_dare'      THEN 'Truth or Dare'
      WHEN '36_questions'       THEN '36 Questions'
      WHEN 'mirror'             THEN 'Mirror'
      WHEN 'sliding_scale'      THEN 'Sliding Scale'
      WHEN 'scenario'           THEN 'Scenario'
      WHEN 'love_map'           THEN 'Love Map'
      WHEN 'paint_ball'         THEN 'Paint Ball'
      WHEN 'snakes_and_ladders' THEN 'Snakes and Ladders'
    END,
    initcap(replace(p_game_type, '_', ' '))
  );
$$;

CREATE OR REPLACE FUNCTION public.notify_game_invite()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_recipient uuid;
  v_label text;
BEGIN
  IF NEW.status <> 'invited' THEN
    RETURN NEW;
  END IF;
  SELECT CASE WHEN r.user_a = NEW.initiator_id THEN r.user_b ELSE r.user_a END
    INTO v_recipient
    FROM public.relationships r
   WHERE r.id = NEW.relationship_id
     AND r.status = 'active'
     AND r.chat_archived_at IS NULL;
  IF v_recipient IS NULL THEN
    RETURN NEW;
  END IF;

  v_label := public.game_type_display_name(NEW.game_type);
  INSERT INTO public.scheduled_notifications (
    user_id, notification_type, scheduled_for, status, metadata,
    created_at, updated_at
  ) VALUES (
    v_recipient, 'immediate', now(), 'pending',
    jsonb_build_object(
      'title', 'A game is waiting',
      'body', v_label || U&' \2014 your turn to play.',
      'type', 'game_invite',
      'relationship_id', NEW.relationship_id,
      'session_id', NEW.id,
      'game_type', NEW.game_type
    ), now(), now()
  );
  RETURN NEW;
END;
$$;
