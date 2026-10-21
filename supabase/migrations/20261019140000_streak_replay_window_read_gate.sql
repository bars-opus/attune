-- Streak replays: readable for 30 minutes after the first view, then gone.
--
-- mark_streak_viewed enforced the window only when the viewer FINISHED, so
-- an expired replay played in full once more and only then was destroyed
-- (chat robustness review 06 M-8). This gates the READ: the client fetches
-- clips through streak_clips_for_viewing, which returns rows only while the
-- streak is viewable for this caller and destroys an expired one on the
-- spot, and the table's own SELECT policy mirrors the same rule for the
-- recipient, so an older client's direct table read is gated too. This
-- gates the clip ROWS only: the storage object stays signable by key
-- (messages.media_url) until 20261019140100 adds the same rule to the
-- message-media storage policy and sweeps abandoned streaks; until then a
-- modified client holding the key could still sign it. mark_streak_viewed
-- is unchanged here: it remains the budget owner and the last line of
-- defence at finish time.
--
-- Grants live in 20261019140010_streak_replay_window_read_gate_grants.sql.

-- Shared destroy step (mark_streak_viewed inlines the same three
-- statements; kept identical). Internal: nobody calls this directly. The
-- explicit queue call is redundant with the BEFORE DELETE trigger
-- streak_clips_queue_media_before_delete (20261018110000) but harmless
-- (queue_media_deletion is idempotent), and keeps parity with
-- mark_streak_viewed. Never DELETE from storage.objects here: hosted
-- refuses it; the queue drains through the Storage API.
CREATE OR REPLACE FUNCTION public.expire_streak_clips(p_message_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM public.queue_media_deletion('message-media', c.media_url)
  FROM public.streak_clips c WHERE c.message_id = p_message_id;

  DELETE FROM public.streak_clips c WHERE c.message_id = p_message_id;
  UPDATE public.messages m SET streak_views_remaining = 0
  WHERE m.id = p_message_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_msg public.messages%ROWTYPE;
  v_member boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_msg FROM public.messages m WHERE m.id = p_message_id;
  IF FOUND THEN
    -- A member of the relationship whose chat is still open to them
    -- (not archived, not sealed on their side, active/paused or within
    -- the 30-day ended grace) — the same rule as streak_clips' SELECT
    -- policy via relationship_chat_open.
    SELECT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_msg.relationship_id
        AND (r.user_a = v_user OR r.user_b = v_user)
        AND public.relationship_chat_open_for(r.id, v_user)
    ) INTO v_member;
  END IF;
  IF NOT v_member THEN
    -- Same answer for "someone else's" and "does not exist": no oracle.
    RAISE EXCEPTION 'Streak unavailable';
  END IF;

  IF v_msg.sender_id = v_user THEN
    -- The sender may replay until the recipient has opened it.
    IF v_msg.viewed_at IS NOT NULL THEN RETURN; END IF;
  ELSE
    IF COALESCE(v_msg.streak_views_remaining, 0) <= 0 THEN RETURN; END IF;
    IF v_msg.viewed_at IS NOT NULL
       AND v_msg.viewed_at < now() - interval '30 minutes' THEN
      -- Expired by time with plays left: destroy now, before anything is
      -- handed out, and report nothing.
      PERFORM public.expire_streak_clips(p_message_id);
      RETURN;
    END IF;
  END IF;

  -- OUT names shadow the columns: every reference stays alias-qualified.
  RETURN QUERY
    SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c
    WHERE c.message_id = p_message_id
    ORDER BY c.clip_index;
END;
$$;

-- The table agrees with the RPC for the RECIPIENT, whose replay window is
-- the rule: past it, or with no plays left, a direct read sees nothing.
--
-- The sender keeps seeing their own clips in the table. The client attaches
-- a clip with an upsert, INSERT ... ON CONFLICT (message_id, clip_index) DO
-- NOTHING, and a conflict target needs SELECT on those columns, so Postgres
-- checks this policy against the new row too: hiding opened clips from the
-- sender here turns a retried attach (lost response, or the recipient
-- opening it before the attach landed) into "new row violates row-level
-- security policy". streak_clips_for_viewing still refuses the sender once
-- the recipient has opened it; a direct read only reaches the sender's own
-- content, and mark_streak_viewed refuses them at finish. The INSERT policy
-- is untouched.
DROP POLICY IF EXISTS streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.messages m
      WHERE m.id = streak_clips.message_id
        AND public.relationship_chat_open(m.relationship_id)
        AND CASE
              WHEN m.sender_id = auth.uid() THEN true
              ELSE COALESCE(m.streak_views_remaining, 0) > 0
                   AND (m.viewed_at IS NULL
                        OR m.viewed_at > now() - interval '30 minutes')
            END
    )
  );
