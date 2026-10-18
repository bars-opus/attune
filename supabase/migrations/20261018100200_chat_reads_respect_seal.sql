-- Spec 3a (R3-3, R3-4, R3-5): every chat READ path asks one question,
-- public.relationship_chat_open(rel): a member, not archived, active or
-- paused or within 30 days of ending, and not sealed by the caller. Each
-- policy below is the live definition with only its member/archive test
-- replaced (see .superpowers/sdd/spec3-map.md §F, class A). Writes that
-- needed only an unarchived chat are tightened in 20261018100300.

DROP POLICY IF EXISTS messages_select_members ON public.messages;
CREATE POLICY messages_select_members ON public.messages
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(messages.relationship_id));

DROP POLICY IF EXISTS message_pins_select ON public.message_pins;
CREATE POLICY message_pins_select ON public.message_pins
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(message_pins.relationship_id));

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(message_reactions.relationship_id));

DROP POLICY IF EXISTS message_edit_history_select ON public.message_edit_history;
CREATE POLICY message_edit_history_select ON public.message_edit_history
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = message_edit_history.message_id
      AND public.relationship_chat_open(m.relationship_id)
  ));

DROP POLICY IF EXISTS streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips
  FOR SELECT
  -- Correlated, so the helper runs for this clip's message only (review I7).
  USING (EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = streak_clips.message_id
      AND public.relationship_chat_open(m.relationship_id)
  ));

DROP POLICY IF EXISTS place_updates_members_read ON public.place_updates;
CREATE POLICY place_updates_members_read ON public.place_updates
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(place_updates.relationship_id));

DROP POLICY IF EXISTS chat_import_jobs_members_read ON public.chat_import_jobs;
CREATE POLICY chat_import_jobs_members_read ON public.chat_import_jobs
  FOR SELECT TO authenticated
  USING (public.relationship_chat_open(chat_import_jobs.relationship_id));

DROP POLICY IF EXISTS chat_import_requests_members_read ON public.chat_import_requests;
CREATE POLICY chat_import_requests_members_read ON public.chat_import_requests
  FOR SELECT TO authenticated
  USING (
    (auth.uid() = uploader_id OR auth.uid() = approver_id)
    AND public.relationship_chat_open(chat_import_requests.relationship_id)
  );

DROP POLICY IF EXISTS message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'message-media'
    AND EXISTS (
      SELECT 1 FROM public.messages m
      WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name)
        AND public.relationship_chat_open(m.relationship_id)
    )
  );

-- Restated (live 20261017130200): the unread count follows the same test.
CREATE OR REPLACE FUNCTION public.count_unread_messages(p_relationship_id uuid)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT count(*)::integer
  FROM public.messages m
  WHERE m.relationship_id = p_relationship_id
    AND public.relationship_chat_open(p_relationship_id)
    -- Sync audit I-7: in the ended window nothing can be marked read
    -- (mark_conversation_read refuses), so nothing counts as unread.
    AND EXISTS (SELECT 1 FROM public.relationships r
                WHERE r.id = p_relationship_id AND r.status IN ('active', 'paused'))
    -- Sync audit M-4: a deleted message or a system notice is not unread.
    AND m.deleted_at IS NULL
    AND NOT m.is_system_notice
    AND m.created_at > COALESCE(
      (SELECT w.read_through - interval '10 minutes'
         FROM public.message_read_marks w
        WHERE w.relationship_id = p_relationship_id AND w.reader_id = auth.uid()),
      '-infinity'::timestamptz)
    AND m.sender_id <> auth.uid()
    AND m.read_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
$function$;

-- Restated (live 20260931220000), R3-14: "is my partner here now" is a live
-- signal; after a pause or an ending it would tell one person that the
-- other is reading their old chat. Active only.
CREATE OR REPLACE FUNCTION public.partner_is_active_in_chat(p_relationship_id uuid, p_window_seconds integer DEFAULT 45)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_partner uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Membership is verified before anything is read; false rather than an
  -- error, so a caller cannot tell "not a member" from "not active".
  SELECT CASE
           WHEN r.user_a = v_user_id THEN r.user_b
           WHEN r.user_b = v_user_id THEN r.user_a
         END
  INTO v_partner
  FROM public.relationships r
  WHERE r.id = p_relationship_id
    AND r.status = 'active'
    AND r.chat_archived_at IS NULL
    AND (r.user_a = v_user_id OR r.user_b = v_user_id);

  IF v_partner IS NULL THEN
    RETURN false;
  END IF;

  -- Bounded so a caller cannot widen a live indicator into last-seen.
  p_window_seconds := least(greatest(coalesce(p_window_seconds, 45), 15), 120);

  RETURN EXISTS (
    SELECT 1 FROM public.chat_presence cp
    WHERE cp.user_id = v_partner
      AND cp.active_relationship_id = p_relationship_id
      AND cp.updated_at > now() - make_interval(secs => p_window_seconds)
  );
END;
$function$;
