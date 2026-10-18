-- Spec 7 (research 06 B1; plan review C2, I4, I7, I8): "I noticed…" notes
-- and the appreciation jar.
--   * a note is an ordinary message (push, preview, delete, export) with
--     media_type 'appreciation', kept out of analysis (no Pulse or AI
--     input; sync audit I-5), sent by send_appreciation in
--     one of two fixed forms the server checks: "I noticed you … . Thank
--     you." or "Thankful for you because … ." Which form was chosen is never
--     sent as its own value (SOUL §8 special-category);
--   * never edited (edit_message refuses it); deleting works as usual;
--   * the jar holds notes the recipient chose to keep: theirs alone, no
--     count anywhere, gated by the chapter rules of Spec 3b.
-- Grants in 20261018140210.
INSERT INTO public.feature_flags (key, enabled) VALUES ('appreciation_notes', false)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_media_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_media_type_check CHECK (
  media_type IS NULL OR media_type = ANY (ARRAY['image', 'audio', 'video', 'streak', 'game',
                                                'place', 'game_trail', 'appreciation'])
);

-- Only send_appreciation makes a note (final review I-1): a client's own
-- insert, or an update turning a message into one, is refused.
CREATE OR REPLACE FUNCTION public.messages_appreciation_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.media_type = 'appreciation'
     AND (TG_OP = 'INSERT' OR OLD.media_type IS DISTINCT FROM 'appreciation')
     AND coalesce(current_setting('attune.send_appreciation', true), '') <> 'on' THEN
    RAISE EXCEPTION 'appreciation:server_only';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_appreciation_guard ON public.messages;
CREATE TRIGGER messages_appreciation_guard
  BEFORE INSERT OR UPDATE OF media_type ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_appreciation_guard();

CREATE OR REPLACE FUNCTION public.send_appreciation(
  p_relationship_id uuid, p_client_message_id uuid, p_text text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_text text := btrim(coalesce(p_text, ''));
  v_mid text;
  v_id uuid;
BEGIN
  -- Active and not archived (final review M-3), and only while the
  -- feature is on (sync audit).
  IF NOT public.feature_flag_on('appreciation_notes') THEN
    RAISE EXCEPTION 'appreciation:not_allowed';
  END IF;
  IF v_uid IS NULL OR p_client_message_id IS NULL
     OR NOT public.relationship_active_for_me(p_relationship_id)
     OR EXISTS (SELECT 1 FROM public.relationships r
                WHERE r.id = p_relationship_id AND r.chat_archived_at IS NOT NULL) THEN
    RAISE EXCEPTION 'appreciation:not_allowed';
  END IF;
  IF v_text ~ '[\r\n]' OR char_length(v_text) > 320 THEN
    RAISE EXCEPTION 'appreciation:invalid';
  END IF;
  v_mid := coalesce(substring(v_text FROM '^I noticed you (.+)\. Thank you\.$'),
                    substring(v_text FROM '^Thankful for you because (.+)\.$'));
  IF v_mid IS NULL OR char_length(btrim(v_mid)) = 0 OR char_length(v_mid) > 280 THEN
    RAISE EXCEPTION 'appreciation:invalid';
  END IF;

  PERFORM set_config('attune.send_appreciation', 'on', true);
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, media_type,
                               source, is_system_notice, message_analysis_skipped)
  -- Kept out of analysis (sync audit I-5): never a Pulse or AI input
  -- (Spec 7 "no Pulse inputs"; Spec 8 I8).
  VALUES (p_relationship_id, v_uid, p_client_message_id, v_text, 'appreciation',
          'native', false, true)
  ON CONFLICT (sender_id, client_message_id) DO NOTHING
  RETURNING id INTO v_id;
  PERFORM set_config('attune.send_appreciation', 'off', true);
  IF v_id IS NULL THEN
    SELECT m.id INTO v_id FROM public.messages m
    WHERE m.sender_id = v_uid AND m.client_message_id = p_client_message_id
      AND m.relationship_id = p_relationship_id AND m.media_type = 'appreciation';
    IF v_id IS NULL THEN RAISE EXCEPTION 'appreciation:invalid'; END IF;
  END IF;
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
     -- under its leaf; it can be deleted.
     OR v_media_type = 'appreciation'
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

CREATE TABLE IF NOT EXISTS public.appreciation_jar (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  saved_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);
ALTER TABLE public.appreciation_jar ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.save_to_my_jar(p_message_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF NOT public.feature_flag_on('appreciation_notes') OR v_uid IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id AND m.media_type = 'appreciation' AND m.deleted_at IS NULL
      AND m.sender_id <> v_uid AND public.relationship_active_for_me(m.relationship_id)
      AND NOT EXISTS (SELECT 1 FROM public.relationships r
                      WHERE r.id = m.relationship_id AND r.chat_archived_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'jar:not_allowed';
  END IF;
  INSERT INTO public.appreciation_jar (user_id, message_id) VALUES (v_uid, p_message_id)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_from_my_jar(p_message_id uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  DELETE FROM public.appreciation_jar WHERE user_id = auth.uid() AND message_id = p_message_id;
$$;

-- Notes I kept, newest first; only while I can still read that chat.
CREATE OR REPLACE FUNCTION public.list_my_jar()
RETURNS TABLE (message_id uuid, relationship_id uuid, content text, sent_at timestamptz, saved_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT m.id, m.relationship_id, m.content, m.created_at, j.saved_at
  FROM public.appreciation_jar j
  JOIN public.messages m ON m.id = j.message_id
  WHERE j.user_id = auth.uid() AND m.deleted_at IS NULL AND m.media_type = 'appreciation'
    AND public.relationship_chat_open_for(m.relationship_id, auth.uid())
  ORDER BY m.created_at DESC;
$$;

-- Which notes I kept, ids only: what the chat needs to label its actions
-- (final review M-7), without fetching every note's text.
CREATE OR REPLACE FUNCTION public.list_my_jar_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT j.message_id FROM public.appreciation_jar j
  JOIN public.messages m ON m.id = j.message_id
  WHERE j.user_id = auth.uid() AND m.deleted_at IS NULL
    AND public.relationship_chat_open_for(m.relationship_id, auth.uid());
$$;
