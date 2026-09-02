-- Session games get a chat card too.
--
-- post_game_message fired only on status = 'invited'. The session games
-- (Mirror, Sliding Scale, Scenario) insert straight to 'active' -- they
-- have no invite step, both partners simply answer the same round -- so
-- they never produced a card at all. Playing Scenario left no trace in
-- the chat, which is also where the flow now hands off after answering:
-- the player was returned to a conversation with nothing in it.
--
-- The card is created for any session a partner can join, which is what
-- 'invited' was standing in for.
CREATE OR REPLACE FUNCTION public.post_game_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_label text;
BEGIN
  -- Was: NEW.status <> 'invited'. Now anything still in play, so a game
  -- that never has an invite step is not silently excluded.
  IF NEW.status NOT IN ('invited', 'active') THEN
    RETURN NEW;
  END IF;

  v_label := public.game_type_display_name(NEW.game_type);

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

REVOKE ALL ON FUNCTION public.post_game_message() FROM PUBLIC, anon, authenticated;

-- Backfill the sessions that never got one, for the same reason the
-- earlier backfill existed: a game in play with no card is unreachable
-- from the chat it belongs to.
INSERT INTO public.messages (
  relationship_id, sender_id, client_message_id, content,
  media_type, game_session_id, source, created_at, sort_at
)
SELECT
  gs.relationship_id, gs.initiator_id, gs.id,
  public.game_type_display_name(gs.game_type),
  'game', gs.id, 'native', gs.created_at, gs.created_at
FROM public.game_sessions gs
WHERE gs.status IN ('invited', 'active')
  AND NOT EXISTS (
    SELECT 1 FROM public.messages m WHERE m.game_session_id = gs.id
  )
ON CONFLICT (game_session_id) WHERE game_session_id IS NOT NULL
DO NOTHING;
