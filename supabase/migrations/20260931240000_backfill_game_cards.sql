-- Chat cards for game sessions that predate the trigger.
--
-- post_game_message fires AFTER INSERT, so every session created before
-- 20260931200000 shipped has no message row: the partner sees nothing in
-- the chat, and the invite is reachable only through the games sheet's
-- "Continue playing" list. An invite you cannot see is an invite that
-- does not exist as far as the person receiving it is concerned.
--
-- Restricted to sessions that are still live (invited or active). A
-- completed or abandoned game does not need a card retrofitted into a
-- conversation it was never part of.
--
-- created_at is copied from the SESSION, not set to now(): the card
-- belongs where the invite actually happened in the conversation, not at
-- the bottom of the chat as though it had just been sent. sort_at is set
-- to the same value, so history is not reordered by this backfill.
INSERT INTO public.messages (
  relationship_id,
  sender_id,
  client_message_id,
  content,
  media_type,
  game_session_id,
  source,
  created_at,
  sort_at
)
SELECT
  gs.relationship_id,
  gs.initiator_id,
  gs.id,
  public.game_type_display_name(gs.game_type),
  'game',
  gs.id,
  'native',
  gs.created_at,
  gs.created_at
FROM public.game_sessions gs
WHERE gs.status IN ('invited', 'active')
  AND NOT EXISTS (
    SELECT 1 FROM public.messages m WHERE m.game_session_id = gs.id
  )
ON CONFLICT (game_session_id) WHERE game_session_id IS NOT NULL
DO NOTHING;
