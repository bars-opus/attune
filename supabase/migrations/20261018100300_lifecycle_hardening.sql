-- Spec 3a hardening (plan review 2026-10-18: C2, I1, I2, I4, I5, I6). Pausing
-- or ending freezes the chat for writes as well as sends; nothing the ex can
-- read says who left for whom; reminders stop; Dating sees a paused space as
-- a relationship; pause no longer revokes calendar links (ending still does).
-- Every function below is restated from its live definition; each change is
-- marked "Spec 3a".

-- C2. Writes that tested only chat_archived_at now need an active space.
DROP POLICY IF EXISTS message_pins_delete ON public.message_pins;
CREATE POLICY message_pins_delete ON public.message_pins
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = message_pins.relationship_id
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      AND r.chat_archived_at IS NULL
      AND r.status = 'active'
  ));

DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
CREATE POLICY message_reactions_delete ON public.message_reactions
  FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = message_reactions.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS place_updates_author_write ON public.place_updates;
CREATE POLICY place_updates_author_write ON public.place_updates
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = place_updates.relationship_id
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.chat_archived_at IS NULL
        AND r.status = 'active'
    )
  );

DROP POLICY IF EXISTS place_updates_author_delete ON public.place_updates;
CREATE POLICY place_updates_author_delete ON public.place_updates
  FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = place_updates.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS streak_clips_sender_write ON public.streak_clips;
CREATE POLICY streak_clips_sender_write ON public.streak_clips
  FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.relationships r ON r.id = m.relationship_id
    WHERE m.id = streak_clips.message_id
      AND m.sender_id = auth.uid()
      AND r.status = 'active' AND r.chat_archived_at IS NULL
  ));

-- I4. Nothing new is logged into a paused, ended or archived chapter.
DROP POLICY IF EXISTS timeline_insert_members ON public.timeline_events;
CREATE POLICY timeline_insert_members ON public.timeline_events
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = logged_by
    AND relationship_id IN (
      SELECT r.id FROM public.relationships r
      WHERE (r.user_a = auth.uid() OR r.user_b = auth.uid())
        AND r.status = 'active'
    )
  );

-- I1 (column privileges on relationships) lives in 20261018100100_relationship_lifecycle_grants.sql.

-- Restated functions (C2 mark_delivered, mark_relationship_delivered,
-- set_chat_presence, mark_conversation_read; I5 dating; I6 feeds; I2
-- reminders).
CREATE OR REPLACE FUNCTION public.mark_delivered(p_message_ids uuid[])
 RETURNS TABLE(id uuid, delivered_at timestamp with time zone, read_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  RETURN QUERY
  WITH candidate_messages AS (
    SELECT m.id
    FROM public.messages m
    JOIN public.relationships r
      ON r.id = m.relationship_id
    WHERE m.id = ANY(p_message_ids)
      AND m.sender_id <> auth.uid()
      AND r.chat_archived_at IS NULL
      AND r.status = 'active'  -- Spec 3a: no ticks after a pause or an ending
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
      -- Only rows that will actually change. Without this the UPDATE
      -- rewrites every already-delivered row on every replay.
      AND m.delivered_at IS NULL
    LIMIT 200
  ),
  updated AS (
    UPDATE public.messages m
    SET delivered_at = now()
    FROM candidate_messages c
    WHERE m.id = c.id
    RETURNING m.id, m.delivered_at, m.read_at
  )
  SELECT updated.id, updated.delivered_at, updated.read_at
  FROM updated;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.mark_relationship_delivered(p_relationship_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       AND r.status = 'active'  -- Spec 3a
       -- Only rows that will actually change, so a repeated call does not
       -- move an existing timestamp forward.
       AND m.delivered_at IS NULL
    RETURNING m.id
  )
  SELECT count(*) INTO v_count FROM updated;

  RETURN v_count;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.set_chat_presence(p_relationship_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_active uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- NULL clears presence (backgrounded / left the conversation).
  IF p_relationship_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = p_relationship_id
        AND r.chat_archived_at IS NULL
        AND r.status = 'active'  -- Spec 3a: no presence after a pause or an ending
        AND (r.user_a = v_user_id OR r.user_b = v_user_id)
    ) THEN
      -- Not a current member; record no active conversation rather than error
      -- (avoids leaking whether the relationship exists).
      v_active := NULL;
    ELSE
      v_active := p_relationship_id;
    END IF;
  ELSE
    v_active := NULL;
  END IF;

  INSERT INTO public.chat_presence (user_id, active_relationship_id, updated_at)
  VALUES (v_user_id, v_active, now())
  ON CONFLICT (user_id) DO UPDATE
    SET active_relationship_id = EXCLUDED.active_relationship_id,
        updated_at = now();
END;
$function$

;
CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_relationship_id uuid)
 RETURNS TABLE(id uuid, delivered_at timestamp with time zone, read_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_on boolean;
  v_floor timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.chat_archived_at IS NULL
      AND r.status IN ('active', 'paused')  -- Spec 3a: refuse in the ended window
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    RETURN;
  END IF;

  -- Spec 1b: pushes about this conversation that have not gone out are moot.
  UPDATE public.scheduled_notifications s
     SET status = 'cancelled', source_key = NULL,
         last_error = 'read_before_send', updated_at = now()
   WHERE s.user_id = v_uid
     AND s.status = 'pending'
     AND s.metadata->>'type' IN ('new_message', 'message_reaction')
     AND s.metadata->>'relationship_id' = p_relationship_id::text;

  v_on := public.seen_receipts_effective(p_relationship_id);
  SELECT w.read_through - interval '10 minutes' INTO v_floor
  FROM public.message_read_marks w
  WHERE w.relationship_id = p_relationship_id AND w.reader_id = v_uid;
  v_floor := COALESCE(v_floor, '-infinity'::timestamptz);

  RETURN QUERY
  WITH marked (mid, rat) AS (
    -- The private marker. Never touches messages.
    INSERT INTO public.message_reads (message_id, reader_id)
    SELECT m.id, v_uid
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.created_at > v_floor
      AND m.sender_id <> v_uid
      AND m.read_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.message_reads x WHERE x.message_id = m.id)
    ON CONFLICT (message_id) DO NOTHING
    RETURNING message_reads.message_id, message_reads.read_at
  ),
  ticked (tid) AS (
    -- The sender-visible tick, only while on. With v_on false this UPDATE
    -- matches no row, so nothing is written and nothing streams.
    UPDATE public.messages m
    SET read_receipt_at = now(),
        delivered_at = COALESCE(m.delivered_at, now())
    FROM marked
    WHERE v_on AND m.id = marked.mid
    RETURNING m.id
  ),
  moved AS (
    -- Forward only; nothing marked, nothing written.
    INSERT INTO public.message_read_marks (relationship_id, reader_id, read_through)
    SELECT p_relationship_id, v_uid, max(m.created_at)
    FROM marked
    JOIN public.messages m ON m.id = marked.mid
    HAVING count(*) > 0
    ON CONFLICT (relationship_id, reader_id) DO UPDATE
      SET read_through = GREATEST(message_read_marks.read_through, EXCLUDED.read_through)
    RETURNING 1
  )
  SELECT marked.mid, m.delivered_at, marked.rat
  FROM marked
  JOIN public.messages m ON m.id = marked.mid
  LEFT JOIN ticked ON ticked.tid = marked.mid;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.dating_has_relationship(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
      AND r.status IN ('pending', 'active', 'paused')  -- Spec 3a (I5)
  );
$function$

;
CREATE OR REPLACE FUNCTION public.sync_dating_pause_on_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('pending', 'active', 'paused') THEN  -- Spec 3a (I5)
    IF NEW.user_a IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_a);
    END IF;
    IF NEW.user_b IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_b);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.together_revoke_feeds_on_end()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (OLD.status IN ('active', 'paused') AND NEW.status IN ('ended', 'archived'))
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    UPDATE public.calendar_feed_tokens SET revoked_at = now()
    WHERE revoked_at IS NULL AND user_id IN (OLD.user_a, OLD.user_b);
  END IF;
  RETURN NULL;
END;
$function$

;
CREATE OR REPLACE FUNCTION public.generate_reminder_notifications(p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int;
BEGIN
  WITH ins AS (
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  SELECT d.user_id, 'immediate', p_now, 'pending',
    jsonb_build_object(
      'title', d.title,
      'body', CASE d.days_until WHEN 0 THEN 'Today' WHEN 1 THEN 'Tomorrow'
                ELSE 'In ' || d.days_until || ' days' END,
      'type', 'reminder_upcoming',
      'reminder_id', d.reminder_id,
      'relationship_id', d.relationship_id,
      'days_until', d.days_until),
    'reminder:' || d.reminder_id || ':' || d.next_on || ':' || d.user_id || ':' || d.days_until,
    p_now, p_now
  FROM (
    SELECT r.id AS reminder_id, r.relationship_id, r.title, r.remind_days_before, m.user_id,
           public.reminder_next_on((r.remind_at AT TIME ZONE 'UTC')::date, r.recurrence, m.local_day) AS next_on,
           public.reminder_next_on((r.remind_at AT TIME ZONE 'UTC')::date, r.recurrence, m.local_day)
             - m.local_day AS days_until
    FROM public.reminders r
    JOIN (
      SELECT rel.id AS relationship_id, u AS user_id, (p_now AT TIME ZONE z.tz)::date AS local_day
      FROM public.relationships rel
      CROSS JOIN LATERAL unnest(ARRAY[rel.user_a, rel.user_b]) AS u
      CROSS JOIN LATERAL (SELECT public.notification_local_zone(u, rel.id) AS tz) z
      WHERE rel.status = 'active' AND u IS NOT NULL
        AND (p_now AT TIME ZONE z.tz)::time >= time '09:00'
    ) m ON m.relationship_id = r.relationship_id
    WHERE r.recurrence = 'yearly'
       -- One-offs near today: every zone's today is within a day of UTC's,
       -- and the furthest ahead anyone hears is a week.
       OR (r.recurrence = 'none'
           AND (r.remind_at AT TIME ZONE 'UTC')::date
               BETWEEN (p_now AT TIME ZONE 'UTC')::date - 1 AND (p_now AT TIME ZONE 'UTC')::date + 8)
  ) d
  WHERE d.days_until = ANY (d.remind_days_before)
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING
  RETURNING (metadata->>'reminder_id')::uuid AS reminder_id,
            (metadata->>'days_until')::int AS days_until
  ),
  -- Bookkeeping only (see 20261015100000): this run's day-of pushes.
  marked AS (
    UPDATE public.reminders r SET sent = true
    FROM ins
    WHERE r.id = ins.reminder_id AND ins.days_until = 0
      AND r.recurrence = 'none' AND NOT r.sent
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ins;
  RETURN v_n;
END;
$function$


;CREATE OR REPLACE FUNCTION public.handle_relationship_dating_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('pending', 'active', 'paused') THEN  -- Spec 3a (I5)
    PERFORM public.pause_dating_for_relationship_user(NEW.user_a);
    IF NEW.user_b IS NOT NULL THEN
      PERFORM public.pause_dating_for_relationship_user(NEW.user_b);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$

;

-- Final review MIN-4: pause freezes, ending purges. Busy blocks stay while
-- paused (nobody can read them: the overlay is active-only) and go at
-- ended/archived. Restated from 20261014170000.
CREATE OR REPLACE FUNCTION public.together_purge_busy_on_end()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF (OLD.status IN ('active', 'paused') AND NEW.status IN ('ended', 'archived'))
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.couple_busy_blocks WHERE relationship_id = OLD.id;
  END IF;
  RETURN NULL;
END;
$function$;
