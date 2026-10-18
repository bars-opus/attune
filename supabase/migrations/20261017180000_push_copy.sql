-- supabase/migrations/20261017180000_push_copy.sql
--
-- Push copy carries no plan titles (Spec 1b; research 06 §3 F8 (4): "no
-- event titles that could out an intimate plan"). A lock screen is read by
-- whoever holds the phone.
--
-- (1) A copy guard on the queue rewrites the fields that ARE a plan's title,
--     by push type, for every present and future inserter. It runs before
--     scheduled_notifications_quiet_guard (BEFORE triggers fire in name
--     order). Names stay in titles ("Ama suggested a plan"); body copy is
--     neutral.
-- (2) A declined proposal's note is the partner's own words, like a chat
--     preview: it reaches the lock screen only when the recipient shows
--     message previews (chat_message_preview_enabled, default off), and
--     then without the plan's title.
-- (3) The daily summary and the date poll wove a title into a sentence;
--     both generators are restated without it.

CREATE OR REPLACE FUNCTION public.scheduled_notifications_copy_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_meta jsonb := coalesce(NEW.metadata, '{}'::jsonb);
  v_type text := v_meta->>'type';
  v_neutral constant text := 'Open Attune to see it.';
  v_title text;
  v_prefix text;
  v_note text;
  v_preview boolean;
BEGIN
  IF v_type = 'together_event' THEN
    v_meta := v_meta || jsonb_build_object('title', 'Your plan');
  ELSIF v_type = 'reminder_upcoming' THEN
    v_meta := v_meta || jsonb_build_object('title', 'Reminder');
  ELSIF v_type IN ('together_proposal', 'together_handoff', 'together_handoff_reply') THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  ELSIF v_type = 'together_proposal_reply' THEN
    -- The body is the title, or (a decline with a note) left(title, 60),
    -- ': ' and the note (decide_couple_event).
    IF v_meta ? 'event_id' THEN
      SELECT ce.title INTO v_title FROM public.couple_events ce
       WHERE ce.id = (v_meta->>'event_id')::uuid;
      v_prefix := left(v_title, 60) || ': ';
      IF v_title IS NOT NULL
         AND left(v_meta->>'body', char_length(v_prefix)) = v_prefix THEN
        v_note := nullif(btrim(substr(v_meta->>'body', char_length(v_prefix) + 1)), '');
      END IF;
    END IF;
    SELECT ns.chat_message_preview_enabled INTO v_preview
      FROM public.notification_settings ns WHERE ns.user_id = NEW.user_id;
    v_meta := v_meta || jsonb_build_object('body',
      CASE WHEN v_note IS NOT NULL AND coalesce(v_preview, false) THEN v_note ELSE v_neutral END);
  ELSIF v_type IN ('together_ritual', 'together_ritual_reply', 'moment_logged') THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  ELSIF v_type = 'planning_entry' AND NEW.source_key LIKE 'planning_countdown:%' THEN
    v_meta := v_meta || jsonb_build_object('body', v_neutral);
  END IF;
  NEW.metadata := v_meta;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.scheduled_notifications_copy_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS scheduled_notifications_copy_guard ON public.scheduled_notifications;
CREATE TRIGGER scheduled_notifications_copy_guard
  BEFORE INSERT ON public.scheduled_notifications
  FOR EACH ROW EXECUTE FUNCTION public.scheduled_notifications_copy_guard();

-- The daily summary (20261014130000): the same candidates, placement and
-- visibility rules, said without titles. One summary line ("2 plans today,
-- first at 19:00" / "3 plans this week, first Tue 19:00"), then the
-- partner's big days ("Kofi's big day at 10:00 — a word of luck?"), then the
-- waiting suggestion. together_enqueue_daily still joins the first three.
CREATE OR REPLACE FUNCTION public.together_digest_lines(
  p_relationship_id uuid, p_user uuid, p_from date, p_to date, p_tz text,
  p_care boolean, p_week boolean
) RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH cand AS (
    SELECT ce.*, d.d AS ev_day,
      CASE WHEN ce.all_day THEN NULL
           WHEN ce.rrule IS NULL THEN ce.starts_at
           ELSE ((d.d + (ce.starts_at AT TIME ZONE ce.tz)::time) AT TIME ZONE ce.tz) END AS at
    FROM public.couple_events ce
    CROSS JOIN LATERAL public.together_event_dates(ce, p_from - 1, p_to + 1) AS d(d)
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed'
      AND (ce.rrule IS NOT NULL
           OR (ce.all_day AND d.d = greatest(p_from, ce.start_date))
           OR (NOT ce.all_day AND d.d = (ce.starts_at AT TIME ZONE ce.tz)::date))
  ), occ AS (
    SELECT cand.*,
      CASE WHEN at IS NULL THEN ev_day ELSE (at AT TIME ZONE p_tz)::date END AS on_day
    FROM cand
  ), placed AS (
    SELECT * FROM occ WHERE on_day BETWEEN p_from AND p_to
  ), mine AS (
    SELECT on_day, at FROM placed
    WHERE p_user = ANY (participant_ids) AND (visibility = 'shared' OR created_by = p_user)
  ), summary AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 0 AS ord,
      s.n || CASE WHEN s.n = 1 THEN ' plan' ELSE ' plans' END
          || CASE WHEN p_week THEN ' this week' ELSE ' today' END
          || CASE
               WHEN p_week THEN CASE WHEN s.n = 1 THEN ': ' ELSE ', first ' END
                    || to_char(s.f_day, 'Dy')
                    || coalesce(' ' || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI'), '')
               WHEN s.f_at IS NULL THEN ''
               ELSE CASE WHEN s.n = 1 THEN ' at ' ELSE ', first at ' END
                    || to_char(s.f_at AT TIME ZONE p_tz, 'HH24:MI')
             END AS line
    FROM (SELECT count(*) AS n,
                 (array_agg(on_day ORDER BY on_day, at NULLS FIRST))[1] AS f_day,
                 (array_agg(at ORDER BY on_day, at NULLS FIRST))[1] AS f_at
          FROM mine) s
    WHERE s.n > 0
  ), big AS (
    SELECT on_day, at, 1 AS ord,
      CASE WHEN p_week THEN to_char(on_day, 'Dy') || ': ' ELSE '' END
      || public.together_name(created_by) || '''s big day'
      || CASE WHEN at IS NULL THEN '' ELSE ' at ' || to_char(at AT TIME ZONE p_tz, 'HH24:MI') END
      || ' — a word of luck?' AS line
    FROM placed
    WHERE p_care AND kind = 'big_day' AND visibility = 'shared'
      AND created_by <> p_user AND NOT (p_user = ANY (participant_ids))
  ), sugg AS (
    SELECT p_from AS on_day, NULL::timestamptz AS at, 2 AS ord, 'A suggestion is waiting for you'::text AS line
    WHERE NOT p_week AND EXISTS (
      SELECT 1 FROM public.couple_events ce
      WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
        AND ce.status = 'proposed' AND ce.proposed_to = p_user AND ce.proposal_expires_at > now())
  ), lines AS (
    SELECT on_day, at, ord, line FROM summary
    UNION ALL SELECT on_day, at, ord, line FROM big
    UNION ALL SELECT on_day, at, ord, line FROM sugg
  )
  SELECT coalesce(array_agg(line ORDER BY ord, on_day, at NULLS FIRST, line), '{}') FROM lines
$$;
REVOKE ALL ON FUNCTION public.together_digest_lines(uuid, uuid, date, date, text, boolean, boolean) FROM PUBLIC, anon, authenticated;

-- The date poll (20261012200900): "Ama suggested dates", not "… for Bali".
CREATE OR REPLACE FUNCTION public.planning_v2_notify_poll(p_block public.planning_blocks, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries; v_partner uuid; v_name text;
BEGIN
  SELECT * INTO v_entry FROM public.planning_entries WHERE id = p_block.entry_id;
  IF v_entry.is_template OR p_actor IS NULL THEN RETURN; END IF;
  SELECT CASE WHEN r.user_a = p_actor THEN r.user_b ELSE r.user_a END INTO v_partner
  FROM public.relationships r WHERE r.id = p_block.relationship_id;
  SELECT coalesce(nullif(btrim(display_name), ''), 'Your partner') INTO v_name FROM public.users WHERE id = p_actor;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_partner, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'planning_entry', 'relationship_id', p_block.relationship_id,
            'entry_id', p_block.entry_id, 'title', 'New dates to vote on',
            'body', left(coalesce(v_name, 'Your partner') || ' suggested dates', 160)),
          'planning_poll:' || p_block.id || ':' || v_partner || ':'
            || to_char(date_trunc('hour', clock_timestamp() AT TIME ZONE 'UTC'), 'YYYYMMDDHH24'))
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_notify_poll(public.planning_blocks, uuid) FROM PUBLIC, anon, authenticated;
