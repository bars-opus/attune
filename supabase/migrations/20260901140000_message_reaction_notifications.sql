-- Extends the existing message_notification_outbox pipeline
-- (20260705120000_chat_system_v1_2.sql) to also carry reaction
-- notifications, alongside the existing 'new_message' type.

ALTER TABLE public.message_notification_outbox
  DROP CONSTRAINT IF EXISTS message_notification_outbox_notification_type_check;

ALTER TABLE public.message_notification_outbox
  ADD CONSTRAINT message_notification_outbox_notification_type_check
  CHECK (notification_type IN ('new_message', 'message_reaction'));

-- Only meaningful for notification_type = 'message_reaction' — NULL for
-- 'new_message' rows, which don't need them (the message content itself
-- carries the notification body via previewBody() in the edge function).
ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS reaction_emoji text;
ALTER TABLE public.message_notification_outbox
  ADD COLUMN IF NOT EXISTS reactor_id uuid REFERENCES public.users(id) ON DELETE CASCADE;

CREATE OR REPLACE FUNCTION public.enqueue_reaction_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message public.messages%ROWTYPE;
  v_recipient_id uuid;
BEGIN
  SELECT * INTO v_message FROM public.messages WHERE id = NEW.message_id;
  IF NOT FOUND OR v_message.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Notify the MESSAGE'S SENDER (whoever wrote the message being reacted
  -- to), not "the other relationship member" generically — if you react
  -- to your OWN message, sender_id = NEW.user_id and there is nothing to
  -- notify (self-notification is meaningless and would leak your own
  -- action back to yourself as a push).
  v_recipient_id := v_message.sender_id;
  IF v_recipient_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  -- Same UNIQUE-conflict-do-nothing shape as
  -- enqueue_message_downstream_work's message_notification_outbox insert
  -- (20260705120000_chat_system_v1_2.sql:211-223) — a rapid re-react
  -- (emoji A then emoji B within the same debounce window) collapses to
  -- one outbox row via the UPDATE below rather than piling up duplicates,
  -- since (recipient_id, message_id, notification_type) is UNIQUE and
  -- covers 'message_reaction' rows exactly as it already covers
  -- 'new_message' rows.
  INSERT INTO public.message_notification_outbox (
    message_id, relationship_id, recipient_id, sender_id,
    notification_type, reaction_emoji, reactor_id
  )
  VALUES (
    NEW.message_id, NEW.relationship_id, v_recipient_id, NEW.user_id,
    'message_reaction', NEW.emoji, NEW.user_id
  )
  ON CONFLICT (recipient_id, message_id, notification_type)
  DO UPDATE SET
    reaction_emoji = EXCLUDED.reaction_emoji,
    reactor_id = EXCLUDED.reactor_id,
    state = 'pending',
    attempts = 0,
    created_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enqueue_reaction_notification_trigger ON public.message_reactions;
CREATE TRIGGER enqueue_reaction_notification_trigger
AFTER INSERT OR UPDATE ON public.message_reactions
FOR EACH ROW EXECUTE FUNCTION public.enqueue_reaction_notification();
