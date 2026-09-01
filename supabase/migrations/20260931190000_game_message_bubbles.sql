-- Game invites appear in the conversation, the way iMessage's games do.
--
-- Sending a game produced a push notification and nothing else: the
-- invite existed only in game_sessions, so the chat -- the place both
-- partners actually look -- showed no trace of it. The partner either
-- caught the push or never knew.
--
-- A game now posts ONE message row that renders a live status card:
-- "Let's play", "Your move", "Their move", "You won". The card's text is
-- never stored here; message_bubble reads it from game_sessions at build
-- time, so a single row stays correct for the life of the game rather
-- than the chat filling with a card per turn. That matters more here than
-- in iMessage: a 36 Questions journey runs for dozens of rounds, and a
-- card each would bury the conversation it is meant to sit inside.

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS game_session_id uuid
    REFERENCES public.game_sessions(id) ON DELETE CASCADE;

-- ON DELETE CASCADE, not SET NULL: a message row whose session is gone
-- would render a card with nothing to read and nowhere to tap.

-- sort_at exists because of resurfacing (below). Chat pagination is
-- keyset on (created_at, id) in both directions, so bumping created_at to
-- move a game to the bottom would corrupt the cursor -- rows served twice
-- or skipped mid-scroll -- and would also move the game under Today's
-- date separator, erasing when it was actually sent.
--
-- Ordering moves to (sort_at, id); created_at keeps its original meaning
-- and still drives the date separators.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sort_at timestamptz;

UPDATE public.messages SET sort_at = created_at WHERE sort_at IS NULL;

ALTER TABLE public.messages
  ALTER COLUMN sort_at SET DEFAULT now(),
  ALTER COLUMN sort_at SET NOT NULL;

-- Backfills sort_at for every insert that does not name it, so no writer
-- -- app, trigger or import -- has to know the column exists.
CREATE OR REPLACE FUNCTION public.messages_default_sort_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.sort_at IS NULL THEN
    NEW.sort_at := NEW.created_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_default_sort_at ON public.messages;
CREATE TRIGGER messages_default_sort_at
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_default_sort_at();

-- The pagination index has to match the new ordering exactly, or every
-- page becomes a sort of the whole conversation.
CREATE INDEX IF NOT EXISTS messages_relationship_sort_idx
  ON public.messages (relationship_id, sort_at DESC, id DESC);

-- One card per session: a re-invite of the same game must move the
-- existing row, never add a second.
CREATE UNIQUE INDEX IF NOT EXISTS messages_game_session_unique_idx
  ON public.messages (game_session_id)
  WHERE game_session_id IS NOT NULL;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (
    media_type IS NULL
    OR media_type = ANY (ARRAY['image', 'audio', 'video', 'streak', 'game'])
  );

-- A game message carries a session and no media, and vice versa. Without
-- this a 'game' row could be written with no session for the card to read.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_game_session_shape_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_game_session_shape_check
  CHECK (
    (media_type = 'game' AND game_session_id IS NOT NULL)
    OR (media_type IS DISTINCT FROM 'game' AND game_session_id IS NULL)
  );
