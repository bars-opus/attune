-- Planning P2: the new Planning replaces v1 outright (spec §16).
--
-- The app is in development with one tester and no v1 data worth keeping,
-- so there is no data copy and no compatibility layer: Ask Attune's "Add
-- to Planning", the calendar feed and the Conversations summary are
-- rebuilt on the new tables, then every v1 table and RPC is dropped.
-- planning_change_signals and bump_planning_signal stay (the new Planning
-- uses them).

-- ---- Ask Attune -> Planning ---------------------------------------------

-- Existing link rows point at v1 plans, which are dropped below.
DELETE FROM public.ai_assist_planning_links;
ALTER TABLE public.ai_assist_planning_links DROP COLUMN planning_item_id;
ALTER TABLE public.ai_assist_planning_links DROP COLUMN planning_event_id;
ALTER TABLE public.ai_assist_planning_links ADD COLUMN planning_entry_id uuid NOT NULL;
ALTER TABLE public.ai_assist_planning_links ADD CONSTRAINT ai_assist_planning_links_entry_fkey
  FOREIGN KEY (planning_entry_id, relationship_id)
  REFERENCES public.planning_entries(id, relationship_id) ON DELETE CASCADE;

DROP FUNCTION public.create_planning_from_assist_message(uuid, text, date);

-- Turns an Attune Assist suggestion into a plan in Everyday, once per
-- message (the link row is the idempotency key):
--   task  -> a plan titled with the task, holding one to-do (due on the date)
--   event -> a plan with a Date block on the event's date
-- Plan creation runs through the Planning RPCs themselves, so every
-- Planning rule (membership, title length, limits) applies unchanged.
CREATE FUNCTION public.create_planning_from_assist_message(
  p_message_id uuid, p_edited_title text, p_edited_date date
) RETURNS TABLE (planning_entry_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor    uuid := auth.uid();
  v_message  public.messages;
  v_link     public.ai_assist_planning_links;
  v_proposal jsonb;
  v_kind     text;
  v_title    text;
  v_date     date;
  v_everyday uuid;
  v_entry    uuid := gen_random_uuid();
  v_block    uuid := gen_random_uuid();
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_message FROM public.messages WHERE id = p_message_id AND deleted_at IS NULL FOR UPDATE;
  IF v_message.id IS NULL THEN RAISE EXCEPTION 'Message unavailable'; END IF;
  IF v_message.message_origin IS DISTINCT FROM 'attune_assist' THEN
    RAISE EXCEPTION 'Not an Attune Assist message';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_message.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_actor OR r.user_b = v_actor)
  ) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  -- The message row lock above serializes concurrent conversions of it.
  SELECT * INTO v_link FROM public.ai_assist_planning_links WHERE message_id = p_message_id;
  IF v_link.message_id IS NOT NULL THEN
    RETURN QUERY SELECT v_link.planning_entry_id;
    RETURN;
  END IF;

  v_proposal := v_message.assistant_payload -> 'suggested_planning_item';
  IF v_proposal IS NULL OR v_proposal = 'null'::jsonb THEN
    RAISE EXCEPTION 'This message has no Planning proposal';
  END IF;
  v_kind := v_proposal ->> 'kind';
  v_title := coalesce(p_edited_title, v_proposal ->> 'title');
  v_date := coalesce(p_edited_date, (v_proposal ->> 'event_date')::date);

  PERFORM public.planning_v2_ensure_starters(v_message.relationship_id);
  SELECT id INTO v_everyday FROM public.planning_categories
  WHERE relationship_id = v_message.relationship_id AND seed_key = 'everyday';

  IF v_kind = 'task' THEN
    PERFORM public.create_planning_entry(v_entry, v_everyday, v_title, false, 'USD');
    PERFORM public.add_planning_block(v_block, v_entry, 'checklist', '{"title":"To do"}', NULL, NULL, NULL);
    PERFORM public.add_planning_block_item(gen_random_uuid(), v_block, v_title, NULL, NULL, v_date, NULL);
  ELSIF v_kind = 'event' THEN
    PERFORM public.create_planning_entry(v_entry, v_everyday, v_title, false, 'USD');
    PERFORM public.add_planning_block(v_block, v_entry, 'date', '{}', v_date, NULL, NULL);
  ELSE
    RAISE EXCEPTION 'Unknown proposal kind';
  END IF;

  INSERT INTO public.ai_assist_planning_links (message_id, relationship_id, planning_entry_id, created_by)
  VALUES (p_message_id, v_message.relationship_id, v_entry, v_actor);
  RETURN QUERY SELECT v_entry;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_from_assist_message(uuid, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_from_assist_message(uuid, text, date) TO authenticated;

-- ---- Calendar feed --------------------------------------------------------

DROP FUNCTION public.list_planning_calendar_entries(uuid, date, date);

-- Live, non-template plans only; a block or item counts only while it and
-- its plan are live (review M9). Date blocks show on every day of their
-- range inside the window; dated checklist items on their due date.
CREATE FUNCTION public.list_planning_calendar_entries(
  p_relationship_id uuid, p_start_date date, p_end_date date
) RETURNS TABLE (
  entry_kind text, entry_id uuid, item_id uuid, entry_date date, title text, is_complete boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.planning_v2_actor(p_relationship_id);
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date OR p_end_date - p_start_date > 42 THEN
    RAISE EXCEPTION 'Calendar range must be at most 42 days';
  END IF;

  RETURN QUERY
  SELECT 'date'::text, e.id, NULL::uuid, d::date, e.title, false
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
  CROSS JOIN LATERAL generate_series(
    greatest(b.date_start, p_start_date), least(coalesce(b.date_end, b.date_start), p_end_date), interval '1 day') d
  WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date' AND b.deleted_at IS NULL
    AND b.date_start IS NOT NULL AND b.date_start <= p_end_date AND coalesce(b.date_end, b.date_start) >= p_start_date
    AND e.deleted_at IS NULL AND NOT e.is_template
  UNION ALL
  SELECT 'item'::text, e.id, i.id, i.due_date, i.text, i.checked_at IS NOT NULL
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL
    AND i.due_date BETWEEN p_start_date AND p_end_date
    AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template;
END;
$$;
REVOKE ALL ON FUNCTION public.list_planning_calendar_entries(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_calendar_entries(uuid, date, date) TO authenticated;

-- ---- Conversations summary -----------------------------------------------

DROP FUNCTION public.get_planning_summary(uuid, date);

-- One line for the Conversations card, in order of preference:
--   overdue  -> the oldest unticked dated item before today
--   upcoming -> the soonest dated item or date from today
--   recent   -> the most recently active plan
-- No row when the couple has planned nothing yet.
CREATE FUNCTION public.get_planning_summary(p_relationship_id uuid, p_today date)
RETURNS TABLE (kind text, entry_id uuid, title text, context_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.planning_v2_actor(p_relationship_id);

  RETURN QUERY
  SELECT 'overdue'::text, e.id, i.text, i.due_date
  FROM public.planning_block_items i
  JOIN public.planning_blocks b ON b.id = i.block_id
  JOIN public.planning_entries e ON e.id = b.entry_id
  WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL AND i.checked_at IS NULL
    AND i.due_date < p_today AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
    AND e.status = 'active'
  ORDER BY i.due_date, i.id
  LIMIT 1;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT u.kind, u.entry_id, u.title, u.context_date FROM (
    SELECT 'upcoming'::text AS kind, e.id AS entry_id, i.text AS title, i.due_date AS context_date, i.id AS tie
    FROM public.planning_block_items i
    JOIN public.planning_blocks b ON b.id = i.block_id
    JOIN public.planning_entries e ON e.id = b.entry_id
    WHERE i.relationship_id = p_relationship_id AND i.deleted_at IS NULL AND i.checked_at IS NULL
      AND i.due_date >= p_today AND b.deleted_at IS NULL AND e.deleted_at IS NULL AND NOT e.is_template
      AND e.status = 'active'
    UNION ALL
    SELECT 'upcoming'::text, e.id, e.title, b.date_start, b.id
    FROM public.planning_blocks b
    JOIN public.planning_entries e ON e.id = b.entry_id
    WHERE b.relationship_id = p_relationship_id AND b.block_type = 'date' AND b.deleted_at IS NULL
      AND b.date_start >= p_today AND e.deleted_at IS NULL AND NOT e.is_template AND e.status = 'active'
  ) u
  ORDER BY u.context_date, u.tie
  LIMIT 1;
  IF FOUND THEN RETURN; END IF;

  RETURN QUERY
  SELECT 'recent'::text, e.id, e.title, NULL::date
  FROM public.planning_entries e
  WHERE e.relationship_id = p_relationship_id AND e.deleted_at IS NULL AND NOT e.is_template
  ORDER BY e.last_activity_at DESC, e.id DESC
  LIMIT 1;
END;
$$;
REVOKE ALL ON FUNCTION public.get_planning_summary(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_summary(uuid, date) TO authenticated;

-- ---- Drop v1 ---------------------------------------------------------------

DROP FUNCTION public.add_planning_goal_task(uuid, uuid, text, text, date);
DROP FUNCTION public.create_planning_goal(uuid, uuid, uuid, text, text);
DROP FUNCTION public.create_planning_task(uuid, uuid, text, text, uuid, date);
DROP FUNCTION public.delete_planning_event(uuid);
DROP FUNCTION public.delete_planning_item(uuid);
DROP FUNCTION public.delete_planning_note(uuid);
DROP FUNCTION public.link_planning_event_task(uuid, uuid);
DROP FUNCTION public.list_planning_events(uuid, date, boolean, date, uuid, integer);
DROP FUNCTION public.list_planning_goal_tasks(uuid, timestamptz, uuid, integer);
DROP FUNCTION public.list_planning_goals(uuid, timestamptz, uuid, integer);
DROP FUNCTION public.list_planning_notes(uuid, timestamptz, uuid, integer);
DROP FUNCTION public.list_planning_tasks(uuid, date, timestamptz, uuid, integer);
DROP FUNCTION public.reconcile_planning_goal(uuid, uuid);
DROP FUNCTION public.set_planning_task_completion(uuid, boolean);
DROP FUNCTION public.unlink_planning_event_task(uuid, uuid);
DROP FUNCTION public.update_planning_item(uuid, text, text, uuid, date);
DROP FUNCTION public.upsert_planning_event(uuid, uuid, text, text, date);
DROP FUNCTION public.upsert_planning_note(uuid, uuid, text, text);

DROP TABLE public.planning_event_tasks;
DROP TABLE public.planning_notes;
DROP TABLE public.planning_events;
DROP TABLE public.planning_items;

DROP FUNCTION public.planning_item_reject_deep_nesting();
DROP FUNCTION public.touch_planning_updated_at();
DROP FUNCTION public.planning_is_active_member(uuid, uuid);
