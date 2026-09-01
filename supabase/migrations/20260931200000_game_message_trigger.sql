-- Posts the game card into the conversation, and resurfaces it on turn.
--
-- content holds the game's display name rather than being left null:
-- messages_payload_present requires content or media_url, and a game row
-- has no media. It also gives the push preview and any notification
-- surface real text instead of an empty bubble. The CARD's label is not
-- this text -- the client reads live status from game_sessions -- but a
-- client that has not shipped the game bubble yet still shows something
-- meaningful rather than a blank.

-- The display name, extracted from notify_game_invite's inline CASE.
--
-- The card and the push notification must never disagree about what a
-- game is called, and there were already two copies of this mapping (one
-- in SQL, one in Dart's gameTypeDisplayName). This is the SQL one, now
-- named so the invite notification can share it.
--
-- Falls back to title-casing the raw type rather than emitting it bare,
-- so a game added to the database before the app knows about it still
-- reads as words instead of "paint_ball".
CREATE OR REPLACE FUNCTION public.game_type_display_name(p_game_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(
    CASE p_game_type
      WHEN 'this_or_that'  THEN 'This or That'
      WHEN 'truth_or_dare' THEN 'Truth or Dare'
      WHEN '36_questions'  THEN '36 Questions'
      WHEN 'mirror'        THEN 'Mirror'
      WHEN 'sliding_scale' THEN 'Sliding Scale'
      WHEN 'scenario'      THEN 'Scenario'
      WHEN 'love_map'      THEN 'Love Map'
      WHEN 'paint_ball'    THEN 'Paint Ball'
    END,
    initcap(replace(p_game_type, '_', ' '))
  );
$$;

CREATE OR REPLACE FUNCTION public.post_game_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_label text;
BEGIN
  IF NEW.status <> 'invited' THEN
    RETURN NEW;
  END IF;

  v_label := public.game_type_display_name(NEW.game_type);

  -- ON CONFLICT DO NOTHING against the unique partial index on
  -- game_session_id: an invite re-fired for the same session must move
  -- the existing card, never post a second one.
  INSERT INTO public.messages (
    relationship_id,
    sender_id,
    client_message_id,
    content,
    media_type,
    game_session_id,
    source
  )
  VALUES (
    NEW.relationship_id,
    NEW.initiator_id,
    -- client_message_id is a uuid, and the session id is already unique
    -- per game: reusing it makes the insert naturally idempotent against
    -- the table's own client_message_id uniqueness as well as the
    -- game_session_id index below.
    NEW.id,
    v_label,
    'game',
    NEW.id,
    'native'
  )
  ON CONFLICT (game_session_id) WHERE game_session_id IS NOT NULL
  DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS post_game_message ON public.game_sessions;
CREATE TRIGGER post_game_message
  AFTER INSERT ON public.game_sessions
  FOR EACH ROW EXECUTE FUNCTION public.post_game_message();

-- ---------------------------------------------------------------------
-- Resurfacing.
-- ---------------------------------------------------------------------

-- A game played across days would otherwise sit at the position it was
-- SENT, scrolled far up, at exactly the moment it needs attention. When
-- the turn passes to a player, its card moves to the bottom.
--
-- sort_at only. created_at is untouched, so the date separators still say
-- when the game was actually sent, and the keyset cursor -- now on
-- (sort_at, id) -- stays consistent because a bump always moves a row
-- FORWARD past every cursor already issued.
--
-- Deliberately NOT fired on every column change: current_turn_user_id is
-- the signal, so a score update or a skip does not jump the card around
-- mid-conversation.
CREATE OR REPLACE FUNCTION public.resurface_game_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.current_turn_user_id IS DISTINCT FROM OLD.current_turn_user_id
     OR NEW.status IS DISTINCT FROM OLD.status THEN
    -- clock_timestamp(), not now(): now() is fixed for the whole
    -- transaction, so a turn change committed in the same transaction as
    -- the insert would set sort_at equal to created_at and the card would
    -- not move at all.
    UPDATE public.messages
    SET sort_at = clock_timestamp()
    WHERE game_session_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS resurface_game_message ON public.game_sessions;
CREATE TRIGGER resurface_game_message
  AFTER UPDATE ON public.game_sessions
  FOR EACH ROW EXECUTE FUNCTION public.resurface_game_message();
