-- Chat W1a (#7, #8): an incremental sync cursor for messages.
--
-- A phone only ever refetched the newest page, so an edit, deletion,
-- reaction or receipt on an older message never reached the other phone
-- until it fell out of the cache. updated_at lets a client ask for
-- "everything that changed since the newest server timestamp I hold"
-- on every resume and reconnect.
--
-- updated_at moves only when a column a client can SEE moves. The safety
-- and analysis workers rewrite messages rows too; without the diff every
-- phone would refetch rows on which nothing visible changed.
--
-- A reaction add/remove bumps the parent message. Besides feeding the
-- cursor, that emits a messages UPDATE frame through the RLS-checked
-- messages subscription, so un-react arrives live without putting whole
-- message_reactions rows on DELETE frames (REPLICA IDENTITY FULL).

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

UPDATE public.messages
SET updated_at = GREATEST(
  created_at,
  COALESCE(sort_at, created_at),
  COALESCE(edited_at, created_at),
  COALESCE(deleted_at, created_at),
  COALESCE(delivered_at, created_at),
  COALESCE(read_receipt_at, created_at),
  COALESCE(viewed_at, created_at)
)
WHERE updated_at IS DISTINCT FROM GREATEST(
  created_at,
  COALESCE(sort_at, created_at),
  COALESCE(edited_at, created_at),
  COALESCE(deleted_at, created_at),
  COALESCE(delivered_at, created_at),
  COALESCE(read_receipt_at, created_at),
  COALESCE(viewed_at, created_at)
);

CREATE INDEX IF NOT EXISTS messages_relationship_updated_idx
  ON public.messages (relationship_id, updated_at);

CREATE OR REPLACE FUNCTION public.messages_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- An explicit bump (the reaction touch below) is kept as given.
  IF NEW.updated_at IS DISTINCT FROM OLD.updated_at THEN
    RETURN NEW;
  END IF;
  IF (NEW.content, NEW.media_url, NEW.media_thumbnail_url, NEW.media_type,
      NEW.media_duration_ms, NEW.media_waveform, NEW.media_width, NEW.media_height,
      NEW.delivered_at, NEW.read_receipt_at, NEW.deleted_at, NEW.edited_at,
      NEW.viewed_at, NEW.streak_views_remaining, NEW.sort_at,
      NEW.reply_to_message_id, NEW.quoted_text, NEW.is_view_once,
      NEW.is_system_notice, NEW.game_session_id, NEW.story_item_id,
      NEW.message_origin, NEW.assistant_payload)
     IS DISTINCT FROM
     (OLD.content, OLD.media_url, OLD.media_thumbnail_url, OLD.media_type,
      OLD.media_duration_ms, OLD.media_waveform, OLD.media_width, OLD.media_height,
      OLD.delivered_at, OLD.read_receipt_at, OLD.deleted_at, OLD.edited_at,
      OLD.viewed_at, OLD.streak_views_remaining, OLD.sort_at,
      OLD.reply_to_message_id, OLD.quoted_text, OLD.is_view_once,
      OLD.is_system_notice, OLD.game_session_id, OLD.story_item_id,
      OLD.message_origin, OLD.assistant_payload) THEN
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS messages_touch_updated_at ON public.messages;
CREATE TRIGGER messages_touch_updated_at
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_touch_updated_at();

CREATE OR REPLACE FUNCTION public.message_reactions_touch_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- On a cascade from a deleted message the parent row is already gone and
  -- this matches nothing, which is fine.
  UPDATE public.messages
     SET updated_at = now()
   WHERE id = COALESCE(NEW.message_id, OLD.message_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS message_reactions_touch_message ON public.message_reactions;
CREATE TRIGGER message_reactions_touch_message
  AFTER INSERT OR UPDATE OR DELETE ON public.message_reactions
  FOR EACH ROW EXECUTE FUNCTION public.message_reactions_touch_message();

-- Filtered DELETE events are only delivered when the old row carries the
-- filter column; with the primary key alone an unpin never reached the
-- partner. A pin row is ids and timestamps only.
ALTER TABLE public.message_pins REPLICA IDENTITY FULL;

COMMENT ON COLUMN public.messages.updated_at IS
  'Moves when a client-visible column moves, or when a reaction on this message is added/removed. Chat sync cursor (W1a).';
