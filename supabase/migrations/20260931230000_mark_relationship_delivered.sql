-- Delivery marked when the recipient's DEVICE has the message.
--
-- process-chat-notification-outbox used to stamp delivered_at right after
-- queuing a push. That is not delivery: the branch runs whether the
-- recipient's phone is reachable or switched off, so a message sent to
-- someone with no data showed the sender two checks while it sat in a
-- queue nobody had received. Queuing a notification is not receipt.
--
-- Delivery is now claimed only where it is observed -- by the recipient's
-- own client, once the rows are on their device. The existing
-- mark_delivered() takes message ids and is called from the chat screen;
-- this one is scoped to a relationship so the CONVERSATION LIST can mark
-- delivery too. Without that, delivered_at would only ever be written
-- when the recipient opened the chat, which is also when read_at is
-- written -- collapsing the two states into one and losing the double
-- grey tick entirely.
CREATE OR REPLACE FUNCTION public.mark_relationship_delivered(
  p_relationship_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_count int;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  WITH updated AS (
    UPDATE public.messages m
       SET delivered_at = now()
      FROM public.relationships r
     WHERE r.id = m.relationship_id
       AND m.relationship_id = p_relationship_id
       -- The caller marks the PARTNER's messages delivered, never their
       -- own: a sender's device holding its own message is not delivery.
       AND m.sender_id <> v_user_id
       AND (r.user_a = v_user_id OR r.user_b = v_user_id)
       AND r.chat_archived_at IS NULL
       -- Only rows that will actually change, so a repeated call does not
       -- move an existing timestamp forward.
       AND m.delivered_at IS NULL
    RETURNING m.id
  )
  SELECT count(*) INTO v_count FROM updated;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_relationship_delivered(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_relationship_delivered(uuid)
  TO authenticated;
