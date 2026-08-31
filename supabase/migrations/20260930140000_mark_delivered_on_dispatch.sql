-- Records delivery when the push is dispatched, not when the recipient
-- opens the conversation.
--
-- mark_delivered is auth.uid()-scoped and called from ChatController,
-- which exists only while a conversation is on screen. So a message stayed
-- on one tick until the recipient OPENED that chat — and opening also
-- marks it read, so in practice it jumped straight from one tick to blue
-- and the delivered state was never seen. Nothing recorded delivery while
-- the app was closed, which is most of the time.
--
-- Separate from mark_delivered rather than a widened version of it: this
-- one takes the recipient as an argument because the caller is the
-- notification worker running as service_role, with no auth.uid() at all.
-- Keeping the client's function untouched means its authorization rules
-- stay exactly as they were.
CREATE OR REPLACE FUNCTION public.mark_delivered_for_recipient(
  p_message_id uuid,
  p_recipient_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivered timestamptz;
BEGIN
  UPDATE public.messages m
     SET delivered_at = now()
    FROM public.relationships r
   WHERE m.id = p_message_id
     AND r.id = m.relationship_id
     -- The recipient must be the OTHER party: a sender's own device
     -- receiving its own push must never mark its own message delivered.
     AND m.sender_id <> p_recipient_id
     AND (r.user_a = p_recipient_id OR r.user_b = p_recipient_id)
     AND r.chat_archived_at IS NULL
     -- Only rows that will actually change, so a retried job does not
     -- rewrite an already-delivered row and move its timestamp forward.
     AND m.delivered_at IS NULL
  RETURNING m.delivered_at INTO v_delivered;

  RETURN v_delivered;
END;
$$;

-- service_role only. No client should be able to assert delivery on
-- another user's behalf; the client keeps mark_delivered, which is scoped
-- to its own auth.uid().
REVOKE ALL ON FUNCTION public.mark_delivered_for_recipient(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_delivered_for_recipient(uuid, uuid)
  TO service_role;
