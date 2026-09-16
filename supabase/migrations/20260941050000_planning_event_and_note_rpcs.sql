-- Mutation RPCs for planning_events, planning_event_tasks, and
-- planning_notes. Spec §4.2.

CREATE OR REPLACE FUNCTION public.upsert_planning_event(
  p_id uuid, p_relationship_id uuid, p_title text, p_note text, p_event_date date
) RETURNS public.planning_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_events;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_event_date IS NULL THEN
    RAISE EXCEPTION 'An event needs a date';
  END IF;

  SELECT * INTO v_row FROM public.planning_events WHERE id = p_id;

  IF v_row.id IS NULL THEN
    IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    INSERT INTO public.planning_events (id, relationship_id, created_by, title, note, event_date)
    VALUES (p_id, p_relationship_id, v_actor, btrim(p_title), p_note, p_event_date)
    RETURNING * INTO v_row;
  ELSE
    IF v_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    UPDATE public.planning_events
    SET title = btrim(p_title), note = p_note, event_date = p_event_date
    WHERE id = p_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.upsert_planning_event(uuid, uuid, text, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_planning_event(uuid, uuid, text, text, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_event(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_events;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_events WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL OR v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  DELETE FROM public.planning_event_tasks WHERE event_id = p_id;
  UPDATE public.planning_events SET deleted_at = now() WHERE id = p_id;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_event(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.link_planning_event_task(
  p_event_id uuid, p_item_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_event public.planning_events;
  v_item public.planning_items;
  v_link_count int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_event FROM public.planning_events
  WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF v_event.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_event.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_item FROM public.planning_items
  WHERE id = p_item_id AND deleted_at IS NULL;
  -- Only a top-level Task may be linked -- a Goal's child has no
  -- independent life outside its checklist (spec §3.2).
  IF v_item.id IS NULL
     OR v_item.item_kind IS DISTINCT FROM 'task'
     OR v_item.parent_goal_id IS NOT NULL
     OR v_item.relationship_id IS DISTINCT FROM v_event.relationship_id THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT count(*) INTO v_link_count
  FROM public.planning_event_tasks WHERE event_id = p_event_id;
  IF v_link_count >= 100 THEN
    RAISE EXCEPTION 'An event may link at most 100 tasks';
  END IF;

  INSERT INTO public.planning_event_tasks (relationship_id, event_id, item_id)
  VALUES (v_event.relationship_id, p_event_id, p_item_id)
  ON CONFLICT (event_id, item_id) DO NOTHING;

  PERFORM public.bump_planning_signal(v_event.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.link_planning_event_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_planning_event_task(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_planning_event_task(
  p_event_id uuid, p_item_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT relationship_id INTO v_relationship_id
  FROM public.planning_event_tasks WHERE event_id = p_event_id AND item_id = p_item_id;
  IF v_relationship_id IS NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  DELETE FROM public.planning_event_tasks
  WHERE event_id = p_event_id AND item_id = p_item_id;

  PERFORM public.bump_planning_signal(v_relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.unlink_planning_event_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_planning_event_task(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_planning_note(
  p_id uuid, p_relationship_id uuid, p_title text, p_body text
) RETURNS public.planning_notes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_notes;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_notes WHERE id = p_id;

  IF v_row.id IS NULL THEN
    IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    INSERT INTO public.planning_notes (id, relationship_id, created_by, title, body)
    VALUES (p_id, p_relationship_id, v_actor, btrim(p_title), COALESCE(p_body, ''))
    RETURNING * INTO v_row;
  ELSE
    IF v_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    -- Last-write-wins: no version check, no merge. This save simply
    -- replaces the body; whichever save commits last is authoritative
    -- (spec §5.3/§9's stated, deliberate concurrent-edit shape).
    UPDATE public.planning_notes
    SET title = btrim(p_title), body = COALESCE(p_body, '')
    WHERE id = p_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.upsert_planning_note(uuid, uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_planning_note(uuid, uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_note(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_notes;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_notes WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL OR v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  UPDATE public.planning_notes SET deleted_at = now() WHERE id = p_id;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_note(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_note(uuid) TO authenticated;
