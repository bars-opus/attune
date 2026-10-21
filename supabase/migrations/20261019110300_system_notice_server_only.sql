-- supabase/migrations/20261019110300_system_notice_server_only.sql
--
-- Chat review #19 (07 M-6): a system notice is written by the server only.
-- The client's INSERT grant included is_system_notice, so a partner (REST,
-- their own token) could write a centred, official-looking line -- never
-- pushed, never unread, no bubble -- and make it look like Attune said it.
--
-- The guard is by role: a direct client INSERT runs as `authenticated`;
-- every legitimate notice is written inside a SECURITY DEFINER function
-- (planning_v2_maybe_celebrate -- the Planning goal notice -- and
-- send_screenshot_notice below) or by a service-role worker, where
-- current_user is the owner / service_role. Those paths need no change.
-- (share_ai_assist_draft, send_appreciation, send_pause and
-- send_pause_reply are definer RPCs too, but write ordinary rows with
-- is_system_notice = false, which the guard never inspects.) The INSERT column grant is deliberately kept
-- so app builds that still send is_system_notice = false keep sending (a
-- forged `true` is what is refused); the new client omits the column.
--
-- Deliberately NOT SECURITY DEFINER (unlike the other guards in this
-- repo): the whole check is "who is current_user", which a definer
-- function would rewrite to its owner.
CREATE OR REPLACE FUNCTION public.messages_system_notice_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.is_system_notice
     AND (TG_OP = 'INSERT' OR OLD.is_system_notice IS DISTINCT FROM NEW.is_system_notice)
     AND current_user IN ('authenticated', 'anon') THEN
    RAISE EXCEPTION 'system_notice:server_only';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS messages_system_notice_guard ON public.messages;
CREATE TRIGGER messages_system_notice_guard
  BEFORE INSERT OR UPDATE OF is_system_notice ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_system_notice_guard();

-- The one notice the app itself raises: "<name> took a screenshot" while
-- viewing a view-once video (ephemeral video design §7.5). Server-authored
-- text; the caller only names the conversation. Idempotent per
-- client_message_id (messages_sender_client_id_unique); a client id the
-- caller already used for anything other than this conversation's
-- screenshot notice is refused rather than answered with that row.
CREATE OR REPLACE FUNCTION public.send_screenshot_notice(p_relationship_id uuid, p_client_message_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_name text;
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR p_client_message_id IS NULL
     OR NOT public.relationship_active_for_me(p_relationship_id)
     OR EXISTS (SELECT 1 FROM public.relationships r
                WHERE r.id = p_relationship_id AND r.chat_archived_at IS NOT NULL) THEN
    RAISE EXCEPTION 'screenshot_notice:not_allowed';
  END IF;
  -- The name the old client wrote: profile display name, then username;
  -- then the account name, then 'Someone'.
  SELECT coalesce(nullif(btrim(p.display_name), ''), nullif(btrim(p.username), ''),
                  nullif(btrim(u.display_name), ''))
    INTO v_name
    FROM public.users u LEFT JOIN public.profiles p ON p.id = u.id
   WHERE u.id = v_uid;
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, source,
                               is_system_notice, message_analysis_skipped)
  VALUES (p_relationship_id, v_uid, p_client_message_id,
          coalesce(v_name, 'Someone') || ' took a screenshot', 'native', true, true)
  ON CONFLICT (sender_id, client_message_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT m.id INTO v_id FROM public.messages m
    WHERE m.sender_id = v_uid AND m.client_message_id = p_client_message_id
      AND m.relationship_id = p_relationship_id AND m.is_system_notice;
    IF v_id IS NULL THEN RAISE EXCEPTION 'screenshot_notice:not_allowed'; END IF;
  END IF;
  RETURN v_id;
END;
$$;
