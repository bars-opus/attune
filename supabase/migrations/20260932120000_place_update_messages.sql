-- Place updates appear in the chat.
--
-- The update is a deliberate act -- a partner chose a moment and offered
-- it -- so it belongs where the rest of what they choose to say lives.
-- That also puts it in front of the analysis pipeline, and means deleting
-- it works the way deleting any message works.

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_media_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (
    media_type IS NULL
    OR media_type = ANY (
      ARRAY['image', 'audio', 'video', 'streak', 'game', 'place']
    )
  );

-- Deleting the message takes the location with it. A place that read one
-- way tonight may read differently tomorrow, and the exit has to be as
-- easy as the entry -- so there is no way to remove the card and leave
-- the coordinates behind.
CREATE INDEX IF NOT EXISTS place_updates_message_idx
  ON public.place_updates (message_id)
  WHERE message_id IS NOT NULL;

-- Posts a place update: the message and the location, in one transaction.
--
-- One RPC rather than two client writes, so a failure cannot leave a
-- message with no place or a place with no message.
CREATE OR REPLACE FUNCTION public.post_place_update(
  p_relationship_id uuid,
  p_label text,
  p_note text DEFAULT NULL,
  p_latitude numeric DEFAULT NULL,
  p_longitude numeric DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_country text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_message_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND (r.user_a = v_user_id OR r.user_b = v_user_id)
      AND r.chat_archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Not a member of this relationship';
  END IF;

  -- content carries the label: messages_payload_present requires content
  -- or media, and it gives a push preview and any older client something
  -- real to show rather than an empty bubble.
  INSERT INTO public.messages (
    relationship_id, sender_id, client_message_id,
    content, media_type, source
  )
  VALUES (
    p_relationship_id, v_user_id, gen_random_uuid(),
    p_label, 'place', 'native'
  )
  RETURNING id INTO v_message_id;

  INSERT INTO public.place_updates (
    relationship_id, user_id, message_id,
    label, note, latitude, longitude, city, country
  )
  VALUES (
    p_relationship_id, v_user_id, v_message_id,
    p_label, p_note, p_latitude, p_longitude, p_city, p_country
  );

  RETURN v_message_id;
END;
$$;

REVOKE ALL ON FUNCTION public.post_place_update(uuid, text, text, numeric, numeric, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.post_place_update(uuid, text, text, numeric, numeric, text, text)
  TO authenticated;
