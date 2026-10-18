-- Spec 8 (research 06 B3 (a), 05 Part C; plan review C2, I4, M3, §4):
-- "Take a pause".
--   * the sender picks one of three fixed messages, each naming a return in
--     the 20-45 minute range; the server holds the words, the client sends
--     only which one. It is an ordinary message (push, preview, delete,
--     export) with media_type 'pause' and message_analysis_skipped = true,
--     so no Pulse signal or AI reads it;
--   * the partner may answer once with "Okay. I'll be here.", only within
--     60 minutes and only before they have written anything else. Every
--     "no" is the same "no", so the chip's absence is the normal state.
--     It does not read the private safety check (final review I-5): gating
--     it let whoever holds the recipient's phone probe the check by sending
--     a pause and looking for the chip, and this fixed, ignorable line is
--     not a conjoint step worth that tell;
--   * neither is ever edited; nothing counts pauses; no timer is stored.
-- Grants in 20261018150110.
INSERT INTO public.feature_flags (key, enabled) VALUES ('conflict_toolkit', false)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_media_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_media_type_check CHECK (
  media_type IS NULL OR media_type = ANY (ARRAY['image', 'audio', 'video', 'streak', 'game',
                                                'place', 'game_trail', 'appreciation',
                                                'pause', 'pause_reply'])
);

-- One answer per pause, whatever the path.
CREATE UNIQUE INDEX IF NOT EXISTS messages_one_pause_reply_idx
  ON public.messages (reply_to_message_id) WHERE media_type = 'pause_reply';

-- Only send_pause and send_pause_reply make these: a client's own insert,
-- or an update turning a message into one, is refused.
CREATE OR REPLACE FUNCTION public.messages_pause_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.media_type IN ('pause', 'pause_reply')
     AND (TG_OP = 'INSERT' OR OLD.media_type IS DISTINCT FROM NEW.media_type)
     AND coalesce(current_setting('attune.send_pause', true), '') <> 'on' THEN
    RAISE EXCEPTION 'pause:server_only';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_pause_guard ON public.messages;
CREATE TRIGGER messages_pause_guard
  BEFORE INSERT OR UPDATE OF media_type ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_pause_guard();

-- The three fixed messages. Variants 2 and 3 await clinician wording.
CREATE OR REPLACE FUNCTION public.pause_text(p_variant integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT CASE p_variant
    WHEN 1 THEN 'I''m getting flooded. I''m stepping back for 30 minutes, not away from you. I''ll come back.'
    WHEN 2 THEN '[DRAFT] I need a short break so I don''t say something I don''t mean. I''ll be back in 20 minutes.'
    WHEN 3 THEN '[DRAFT] This matters to me and I want to get it right. Can we come back to it in 45 minutes?'
  END;
$$;

CREATE OR REPLACE FUNCTION public.send_pause(
  p_relationship_id uuid, p_client_message_id uuid, p_variant integer
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_text text := public.pause_text(p_variant);
  v_id uuid;
BEGIN
  -- The toolkit is on only with the safety check's flag too (plan review I5).
  IF NOT (public.feature_flag_on('conflict_toolkit') AND public.feature_flag_on('private_safety_check')) THEN
    RAISE EXCEPTION 'pause:not_allowed';
  END IF;
  IF v_uid IS NULL OR p_client_message_id IS NULL
     OR NOT public.relationship_active_for_me(p_relationship_id)
     OR EXISTS (SELECT 1 FROM public.relationships r
                WHERE r.id = p_relationship_id AND r.chat_archived_at IS NOT NULL) THEN
    RAISE EXCEPTION 'pause:not_allowed';
  END IF;
  IF v_text IS NULL THEN
    RAISE EXCEPTION 'pause:invalid';
  END IF;

  PERFORM set_config('attune.send_pause', 'on', true);
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type,
                               source, is_system_notice, message_analysis_skipped)
  VALUES (p_relationship_id, v_uid, p_client_message_id, v_text, 'pause',
          'native', false, true)
  ON CONFLICT (sender_id, client_message_id) DO NOTHING
  RETURNING id INTO v_id;
  PERFORM set_config('attune.send_pause', 'off', true);
  IF v_id IS NULL THEN
    SELECT m.id INTO v_id FROM public.messages m
    WHERE m.sender_id = v_uid AND m.client_message_id = p_client_message_id
      AND m.relationship_id = p_relationship_id AND m.media_type = 'pause';
    IF v_id IS NULL THEN RAISE EXCEPTION 'pause:invalid'; END IF;
  END IF;
  RETURN v_id;
END;
$$;

-- Whether p_user may answer p_pause now. Internal; one rule for the chip
-- and the write.
CREATE OR REPLACE FUNCTION public.pause_reply_allowed(p_user uuid, p_pause uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT p_user IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.messages p
    JOIN public.relationships r ON r.id = p.relationship_id
    WHERE p.id = p_pause AND p.media_type = 'pause' AND p.deleted_at IS NULL
      AND p.sender_id <> p_user
      AND p_user IN (r.user_a, r.user_b)
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND p.created_at > now() - interval '60 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.messages m
                      WHERE m.relationship_id = p.relationship_id AND m.sender_id = p_user
                        AND m.created_at > p.created_at)
      AND NOT EXISTS (SELECT 1 FROM public.messages m
                      WHERE m.reply_to_message_id = p.id AND m.media_type = 'pause_reply'));
$$;

CREATE OR REPLACE FUNCTION public.pause_reply_state(p_pause_message_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN public.pause_reply_allowed(auth.uid(), p_pause_message_id)
              THEN 'available' ELSE 'unavailable' END;
$$;

CREATE OR REPLACE FUNCTION public.send_pause_reply(
  p_pause_message_id uuid, p_client_message_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_rel uuid;
  v_quoted text;
  v_allowed boolean;
BEGIN
  IF v_uid IS NULL OR p_client_message_id IS NULL
     OR NOT (public.feature_flag_on('conflict_toolkit') AND public.feature_flag_on('private_safety_check')) THEN
    RAISE EXCEPTION 'pause:not_allowed';
  END IF;
  -- A replay of the same reply returns it.
  SELECT m.id INTO v_id FROM public.messages m
  WHERE m.sender_id = v_uid AND m.client_message_id = p_client_message_id
    AND m.media_type = 'pause_reply' AND m.reply_to_message_id = p_pause_message_id;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  -- Serialise answers to one pause.
  SELECT p.relationship_id, p.content INTO v_rel, v_quoted
  FROM public.messages p WHERE p.id = p_pause_message_id FOR UPDATE;
  v_allowed := public.pause_reply_allowed(v_uid, p_pause_message_id);
  IF v_rel IS NULL OR NOT v_allowed THEN
    RAISE EXCEPTION 'pause:not_allowed';
  END IF;

  PERFORM set_config('attune.send_pause', 'on', true);
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type,
                               reply_to_message_id, quoted_text,
                               source, is_system_notice, message_analysis_skipped)
  VALUES (v_rel, v_uid, p_client_message_id, 'Okay. I''ll be here.', 'pause_reply',
          p_pause_message_id, v_quoted, 'native', false, true)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  PERFORM set_config('attune.send_pause', 'off', true);
  IF v_id IS NULL THEN RAISE EXCEPTION 'pause:not_allowed'; END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.edit_message(p_message_id uuid, p_new_content text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_sender_id uuid;
  v_created_at timestamptz;
  v_deleted_at timestamptz;
  v_current_content text;
  v_relationship_id uuid;
  v_message_origin text;
  v_media_type text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  -- Length bound matches the messages_content_length CHECK (<= 10000) so the
  -- RPC rejects with a clean error code instead of letting a 23514 surface
  -- (Checklist 2.1 -- validated server-side, not just in the client).
  IF p_new_content IS NULL OR char_length(btrim(p_new_content)) = 0
     OR char_length(p_new_content) > 10000 THEN
    RAISE EXCEPTION 'invalid_content' USING ERRCODE = '22023';
  END IF;

  -- Lock first, check second (Checklist 2.16). Reading the fields into
  -- variables rather than testing content IS NULL directly matters here: a
  -- media-only message has NULL content legitimately, so the brief's
  -- "v_current_content IS NULL means not editable" shortcut would both
  -- misreport a media message as not-editable and, worse, mask a NOT NULL
  -- violation on message_edit_history.previous_content.
  SELECT sender_id, created_at, deleted_at, content, relationship_id,
         message_origin, media_type
    INTO v_sender_id, v_created_at, v_deleted_at, v_current_content,
         v_relationship_id, v_message_origin, v_media_type
  FROM public.messages
  WHERE id = p_message_id
  FOR UPDATE;

  -- Attune Assist messages are immutable-in-place regardless of
  -- sender/window (spec §5.3). Checked with its own dedicated error code
  -- so a client can distinguish "this is an Assist message" from every
  -- other not_editable cause and skip straight to offering delete instead
  -- of a retry. Placed right after the lock/read, before the general
  -- not_editable predicate below, so an Assist message never falls through
  -- to that shared error and loses this distinction.
  IF v_message_origin = 'attune_assist' THEN
    RAISE EXCEPTION 'assist_message_immutable' USING ERRCODE = '42501';
  END IF;

  -- Single error for every failure mode, same rationale as delete_message.
  -- The final NOT EXISTS disjunct is the same "active, not archived"
  -- condition pin_message enforces: editing is a write into a live
  -- conversation, so a paused/ended/archived chat (reachable via the
  -- read-only "Previous relationships" view) must reject it.
  IF v_sender_id IS NULL
     OR v_sender_id <> v_uid
     OR v_deleted_at IS NOT NULL
     OR v_created_at <= now() - interval '5 minutes'
     OR v_current_content IS NULL
     -- Spec 7 (plan review I4): an "I noticed…" note is never rewritten
     -- under its leaf; it can be deleted. Spec 8 (plan review I4): nor is
     -- a pause or its fixed reply.
     OR v_media_type IN ('appreciation', 'pause', 'pause_reply')
     OR NOT EXISTS (
       SELECT 1 FROM public.relationships r
       WHERE r.id = v_relationship_id
         AND r.status = 'active'
         AND r.chat_archived_at IS NULL
     ) THEN
    RAISE EXCEPTION 'not_editable' USING ERRCODE = '42501';
  END IF;

  -- Append the PRE-edit content. Written under SECURITY DEFINER, which is
  -- the only write path into this table -- authenticated holds SELECT only.
  INSERT INTO public.message_edit_history (message_id, previous_content)
  VALUES (p_message_id, v_current_content);

  UPDATE public.messages
  SET content = p_new_content,
      edited_at = now()
  WHERE id = p_message_id;
END;
$function$;
