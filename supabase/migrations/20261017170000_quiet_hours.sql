-- supabase/migrations/20261017170000_quiet_hours.sql
--
-- Engine-level quiet hours (Spec 1b; research 06 §3 F6 (1)). A queued push
-- whose send time falls in the recipient's local 22:00–08:00 moves to 08:00
-- local: deferred, never dropped. Exempt: safety resources (never wait) and
-- short-notice Together alarms (offset <= 120 min; at 08:00 "Starting now"
-- would be false -- owner decision D1, 2026-10-17). Overnight chat
-- collapses into one push per conversation at 08:00 (owner decision D2).
--
-- One BEFORE trigger covers every inserter -- SQL functions, triggers, edge
-- functions -- and every return to 'pending' (the worker's retry, the
-- stale-lease reset), so a retry at 23:00 waits too. Rows the worker claims
-- or finishes pass straight through, except the claim itself, which is
-- re-checked (a backlog past 22:00 waits too). A user whose zone is unknown
-- is never deferred (no guessing). A game push skips the window only while
-- the game is live (quiet_hours_game_live). Every overnight chat push is
-- neutral ("New messages in Attune"); an inserter's own source_key on a chat
-- push is kept (that push then does not collapse).
--
-- A collapsed chat insert returns NULL from this trigger: the INSERT
-- succeeds with 0 rows, so `INSERT … RETURNING id INTO v` yields NULL and
-- GET DIAGNOSTICS ROW_COUNT is 0. Today's chat inserters (the outbox,
-- enqueuePush) do not read the row back; a future one must expect this.

CREATE OR REPLACE FUNCTION public.quiet_hours_release_at(p_at timestamptz, p_tz text)
RETURNS timestamptz LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN (p_at AT TIME ZONE p_tz)::time >= time '22:00'
      THEN (((p_at AT TIME ZONE p_tz)::date + 1) + time '08:00') AT TIME ZONE p_tz
    WHEN (p_at AT TIME ZONE p_tz)::time < time '08:00'
      THEN ((p_at AT TIME ZONE p_tz)::date + time '08:00') AT TIME ZONE p_tz
    ELSE p_at
  END
$$;
REVOKE ALL ON FUNCTION public.quiet_hours_release_at(timestamptz, text) FROM PUBLIC, anon, authenticated;

-- A push about a game session skips quiet hours only while the game is
-- live: the recipient was in the app in the last 15 minutes, or the session
-- had a move in the last 15 minutes (owner follow-up 2026-10-17). A "your
-- turn" in a game being played at 22:30 goes now; an invite to a partner who
-- may be asleep waits. Only game pushes carry a game_sessions id.
CREATE OR REPLACE FUNCTION public.quiet_hours_game_live(p_user uuid, p_meta jsonb)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN coalesce(p_meta->>'session_id', '') !~ '^[0-9a-fA-F-]{36}$' THEN false
    ELSE EXISTS (SELECT 1 FROM public.game_sessions gs WHERE gs.id = (p_meta->>'session_id')::uuid)
     AND (EXISTS (SELECT 1 FROM public.chat_presence cp
                  WHERE cp.user_id = p_user AND cp.updated_at > now() - interval '15 minutes')
          OR EXISTS (SELECT 1 FROM public.game_session_rounds r
                     WHERE r.session_id = (p_meta->>'session_id')::uuid
                       AND greatest(r.created_at, r.answer_a_submitted_at, r.answer_b_submitted_at,
                                    r.revealed_at, r.resolved_at) > now() - interval '15 minutes'))
  END
$$;
REVOKE ALL ON FUNCTION public.quiet_hours_game_live(uuid, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.scheduled_notifications_quiet_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_meta jsonb := coalesce(NEW.metadata, '{}'::jsonb);
  v_type text := v_meta->>'type';
  v_claim boolean := TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'processing';
  v_neutral_chat constant jsonb := jsonb_build_object(
    'type', 'new_message', 'title', 'New messages in Attune', 'body', 'Open Attune to read them.');
  v_off int;
  v_base timestamptz;
  v_tz text;
  v_release timestamptz;
  v_days int;
  v_key text;
  v_n int;
BEGIN
  -- Inserts and returns to pending are checked; so is the worker's claim
  -- (pending -> processing), so a row reached late in a backlog, or queued
  -- before the recipient's zone was known, is not sent at night.
  IF NOT v_claim AND NEW.status IS DISTINCT FROM 'pending' THEN RETURN NEW; END IF;
  IF NEW.delivery_channel IS DISTINCT FROM 'push' OR v_type = 'safety_resources' THEN
    RETURN NEW;
  END IF;
  -- Short-notice plan alarms ("Starting now", "In 1 hour"); the offset is the
  -- 4th key field (together_alarm:<event>:<date>:<offset>:<user>). Day-ahead
  -- heads-ups are still true at 08:00 and wait (D1, review I1).
  v_off := CASE WHEN v_type = 'together_event'
                     AND NEW.source_key ~ '^together_alarm:[^:]+:[^:]+:[0-9]+:'
                THEN split_part(NEW.source_key, ':', 4)::int END;
  IF v_off IS NOT NULL AND v_off <= 120 THEN RETURN NEW; END IF;
  IF public.quiet_hours_game_live(NEW.user_id, v_meta) THEN RETURN NEW; END IF;

  IF TG_OP = 'UPDATE' THEN
    -- A pending row being rewritten to pending is left alone.
    IF NOT v_claim AND OLD.status = 'pending' THEN RETURN NEW; END IF;
    v_base := greatest(NEW.scheduled_for, now());
  ELSE
    v_base := coalesce(NEW.scheduled_for, now());
  END IF;

  v_tz := public.notification_recipient_tz(NEW.user_id);
  -- Unknown zone: no guess, no deferral (review C1). The user keeps today's
  -- behaviour until their app reports a zone.
  IF v_tz IS NULL THEN RETURN NEW; END IF;
  v_release := public.quiet_hours_release_at(v_base, v_tz);
  IF v_release <= v_base THEN RETURN NEW; END IF;

  IF v_claim THEN
    -- Bounce the claim: the worker skips a row that did not become
    -- 'processing'; it goes out at 08:00 as queued.
    NEW.status := 'pending';
  END IF;
  NEW.scheduled_for := v_release;
  v_meta := v_meta || jsonb_build_object('quiet_deferred', true);

  -- "Today" / "Tomorrow" / "Today's the day" are false on the next local day.
  IF (v_release AT TIME ZONE v_tz)::date <> (v_base AT TIME ZONE v_tz)::date THEN
    IF v_type = 'reminder_upcoming' THEN
      v_meta := v_meta || jsonb_build_object('body', 'Open Attune to see it.');
    ELSIF v_type = 'planning_entry' AND NEW.source_key LIKE 'planning_countdown:%' THEN
      v_meta := v_meta || jsonb_build_object('title', 'Your plan', 'body', 'Open Attune to see it.');
    END IF;
  END IF;
  -- A day-ahead alarm says how far the plan is from 08:00, not from the night
  -- it was queued (follow-up M5). The plan starts offset minutes after the
  -- alarm was due.
  IF v_off IS NOT NULL THEN
    v_days := ((v_base + make_interval(mins => v_off)) AT TIME ZONE v_tz)::date
              - (v_release AT TIME ZONE v_tz)::date;
    v_meta := v_meta || jsonb_build_object('body',
      CASE WHEN v_days <= 0 THEN 'Today' WHEN v_days = 1 THEN 'Tomorrow'
           ELSE 'In ' || v_days || ' days' END);
  END IF;

  -- Overnight chat: one neutral push per conversation at 08:00. A retried
  -- push joins it too (follow-up M1). A claim bounced back keeps its row.
  IF v_type IN ('new_message', 'message_reaction') AND NOT v_claim THEN
    v_meta := v_meta || v_neutral_chat;
    IF NEW.source_key IS NOT NULL AND NEW.source_key NOT LIKE 'quiet_chat:%' THEN
      -- The inserter's own key (its idempotency) is kept: no collapse
      -- (follow-up M2).
      NEW.metadata := v_meta;
      RETURN NEW;
    END IF;
    v_key := 'quiet_chat:' || NEW.user_id || ':' || coalesce(v_meta->>'relationship_id', '')
             || ':' || to_char(v_release AT TIME ZONE 'UTC', 'YYYYMMDDHH24MI');
    PERFORM pg_advisory_xact_lock(hashtext(v_key));
    UPDATE public.scheduled_notifications s
       SET metadata = s.metadata || v_neutral_chat || jsonb_build_object(
             'quiet_count', coalesce((s.metadata->>'quiet_count')::int, 1) + 1),
           updated_at = now()
     WHERE s.source_key = v_key AND s.status = 'pending' AND s.id IS DISTINCT FROM NEW.id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN
      IF TG_OP = 'INSERT' THEN RETURN NULL; END IF;
      -- A retry joins the overnight push and is itself cancelled.
      NEW.status := 'cancelled';
      NEW.last_error := 'joined_quiet_push';
      NEW.source_key := NULL;
      NEW.metadata := v_meta;
      RETURN NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM public.scheduled_notifications s
               WHERE s.source_key = v_key AND s.id IS DISTINCT FROM NEW.id) THEN
      -- The key's row already left 'pending' (claimed at 08:00, sent,
      -- failed): queue this one on its own. Taking the key would hit the
      -- unique index and dead-letter the chat outbox job (review I4).
      NEW.source_key := NULL;
    ELSE
      NEW.source_key := v_key;
    END IF;
  END IF;

  NEW.metadata := v_meta;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.scheduled_notifications_quiet_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS scheduled_notifications_quiet_guard ON public.scheduled_notifications;
CREATE TRIGGER scheduled_notifications_quiet_guard
  BEFORE INSERT OR UPDATE OF status ON public.scheduled_notifications
  FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_quiet_guard();
