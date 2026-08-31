-- Tells the partner a game is waiting for them.
--
-- A session was created with status 'invited' and nothing announced it:
-- no push, no realtime subscription, no trigger. The invite sat silent
-- until the partner happened to open the Games hub, so "send a game" did
-- not reach them at all unless they went looking. Chat messages get a push
-- on every send; a game invite got nothing.
--
-- Writes to scheduled_notifications, the queue the chat notification
-- worker already drains, rather than inventing a second delivery path.
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
  -- Only a fresh invite. An UPDATE to 'active' is the partner accepting,
  -- which needs no notification, and re-notifying on every status change
  -- would make one game several alerts.
  IF NEW.status <> 'invited' THEN
    RETURN NEW;
  END IF;

  SELECT CASE
           WHEN r.user_a = NEW.initiator_id THEN r.user_b
           ELSE r.user_a
         END
    INTO v_recipient
    FROM public.relationships r
   WHERE r.id = NEW.relationship_id
     AND r.status = 'active'
     AND r.chat_archived_at IS NULL;

  -- No active relationship, or the row is mid-teardown: nothing to send.
  IF v_recipient IS NULL THEN
    RETURN NEW;
  END IF;

  -- Mirrors gameTypeDisplayName in the client so the push and the hub
  -- name the same game. Unknown types fall back to the raw value here
  -- rather than title-casing in SQL — a push naming an unrecognised game
  -- is strictly better than no push.
  v_label := CASE NEW.game_type
    WHEN 'this_or_that'  THEN 'This or That'
    WHEN 'truth_or_dare' THEN 'Truth or Dare'
    WHEN '36_questions'  THEN '36 Questions'
    WHEN 'mirror'        THEN 'Mirror'
    WHEN 'sliding_scale' THEN 'Sliding Scale'
    WHEN 'scenario'      THEN 'Scenario'
    WHEN 'love_map'      THEN 'Love Map'
    WHEN 'paint_ball'    THEN 'Paint Ball'
    ELSE NEW.game_type
  END;

  INSERT INTO public.scheduled_notifications (
    user_id, notification_type, scheduled_for, status, metadata,
    created_at, updated_at
  )
  VALUES (
    v_recipient,
    'immediate',
    now(),
    'pending',
    jsonb_build_object(
      'title', 'A game is waiting',
      'body', v_label || ' — your turn to play.',
      'type', 'game_invite',
      'relationship_id', NEW.relationship_id,
      'session_id', NEW.id,
      'game_type', NEW.game_type
    ),
    now(),
    now()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_game_invite ON public.game_sessions;
CREATE TRIGGER notify_game_invite
  AFTER INSERT ON public.game_sessions
  FOR EACH ROW EXECUTE FUNCTION public.notify_game_invite();

REVOKE ALL ON FUNCTION public.notify_game_invite() FROM PUBLIC, anon;
