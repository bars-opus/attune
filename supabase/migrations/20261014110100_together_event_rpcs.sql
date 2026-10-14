-- Together write RPCs (spec §3.4, §5.4). Errors are P0001 'together:<code>'.

CREATE TYPE public.together_event_input AS (
  kind text, title text, note text, location_name text, all_day boolean,
  start_date date, end_date date, starts_at timestamptz, ends_at timestamptz,
  tz text, rrule text, recurrence_until date, participant_ids uuid[],
  owner_id uuid, visibility text, remind_offsets_min int[],
  about_member_id uuid, planning_entry_id uuid
);

CREATE FUNCTION public.together_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'together:' || p_code;
END;
$$;
REVOKE ALL ON FUNCTION public.together_fail(text) FROM PUBLIC, anon, authenticated;

-- The caller, who must be a member of this active relationship.
CREATE FUNCTION public.together_actor(p_relationship_id uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = v_uid OR r.user_b = v_uid)
  ) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  RETURN v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.together_actor(uuid) FROM PUBLIC, anon, authenticated;

-- Checks what the table's CHECKs can't: people, references, zones.
CREATE FUNCTION public.together_validate_input(
  p_relationship_id uuid, p_actor uuid, e public.together_event_input,
  p_existing_owner uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_members uuid[];
BEGIN
  SELECT array_remove(ARRAY[r.user_a, r.user_b], NULL) INTO v_members
  FROM public.relationships r WHERE r.id = p_relationship_id;

  IF e.title IS NULL OR btrim(e.title) = ''
     OR coalesce(e.kind, 'event') NOT IN ('event', 'trip', 'big_day')
     OR e.all_day IS NULL
     OR e.participant_ids IS NULL OR cardinality(e.participant_ids) = 0
     OR NOT (e.participant_ids <@ v_members)
     OR cardinality(ARRAY(SELECT DISTINCT unnest(e.participant_ids))) <> cardinality(e.participant_ids)
     OR (e.tz IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = e.tz))
     -- busy_only and private events hold only their creator (R9; review fix):
     -- the partner can't be in an event they can't see or leave.
     OR (coalesce(e.visibility, 'shared') <> 'shared' AND e.participant_ids <> ARRAY[p_actor])
     -- a repeat that ends before it starts would never appear
     OR (e.recurrence_until IS NOT NULL AND e.recurrence_until <
          coalesce(e.start_date, (e.starts_at AT TIME ZONE coalesce(e.tz, 'UTC'))::date))
     OR (e.about_member_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.couple_family_members f
          WHERE f.id = e.about_member_id AND f.relationship_id = p_relationship_id))
     OR (e.planning_entry_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM public.planning_entries pe
          WHERE pe.id = e.planning_entry_id AND pe.relationship_id = p_relationship_id
            AND pe.deleted_at IS NULL))
  THEN
    PERFORM public.together_fail('invalid_input');
  END IF;

  IF e.owner_id IS NOT NULL AND e.owner_id <> p_actor
     AND e.owner_id IS DISTINCT FROM p_existing_owner THEN
    IF e.owner_id = ANY (v_members) THEN
      PERFORM public.together_fail('owner_handoff');
    END IF;
    PERFORM public.together_fail('invalid_input');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.together_validate_input(uuid, uuid, public.together_event_input, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.create_couple_event(p_relationship_id uuid, p_event jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.together_actor(p_relationship_id);
  e public.together_event_input;
  v_id uuid;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.together_fail('invalid_input');
  END;
  PERFORM public.together_validate_input(p_relationship_id, v_actor, e);
  BEGIN
    INSERT INTO public.couple_events (
      relationship_id, created_by, kind, title, note, location_name, all_day,
      start_date, end_date, starts_at, ends_at, tz, rrule, recurrence_until,
      participant_ids, owner_id, visibility, remind_offsets_min,
      about_member_id, planning_entry_id)
    VALUES (
      p_relationship_id, v_actor, coalesce(e.kind, 'event'), btrim(e.title),
      nullif(btrim(e.note), ''), nullif(btrim(e.location_name), ''), e.all_day,
      e.start_date, e.end_date, e.starts_at, e.ends_at, e.tz, e.rrule, e.recurrence_until,
      e.participant_ids, e.owner_id, coalesce(e.visibility, 'shared'),
      coalesce(e.remind_offsets_min, '{}'), e.about_member_id, e.planning_entry_id)
    RETURNING id INTO v_id;
  EXCEPTION WHEN check_violation OR not_null_violation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  RETURN v_id;
END;
$$;

-- The row the caller may change: shared events by either partner,
-- busy_only/private ones by their creator only (others: not_found).
CREATE FUNCTION public.together_editable_event(p_event_id uuid)
RETURNS public.couple_events
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events; v_actor uuid;
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  -- A sent proposal can't be changed by anyone (Phase 2a review): the
  -- partner answers what they were sent. Only its creator withdraws it,
  -- through delete_couple_event.
  IF NOT FOUND OR v_row.status <> 'confirmed' THEN PERFORM public.together_fail('not_found'); END IF;
  v_actor := public.together_actor(v_row.relationship_id);
  IF v_row.visibility <> 'shared' AND v_row.created_by <> v_actor THEN
    PERFORM public.together_fail('not_found');
  END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.together_editable_event(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.update_couple_event(p_event_id uuid, p_event jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.couple_events := public.together_editable_event(p_event_id);
  v_actor uuid := auth.uid();
  e public.together_event_input;
BEGIN
  BEGIN
    e := jsonb_populate_record(NULL::public.together_event_input, p_event);
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.together_fail('invalid_input');
  END;
  -- A payload without visibility keeps the event's own (review fix):
  -- defaulting to shared could reveal a private event.
  e.visibility := coalesce(e.visibility, v_row.visibility);
  -- A ritual occurrence stays one when a week is moved (Phase 3 R5); the
  -- validator only knows client kinds, so it checks this as a plain event.
  IF v_row.kind = 'ritual_occurrence' THEN e.kind := 'event'; END IF;
  PERFORM public.together_validate_input(v_row.relationship_id, v_actor, e, v_row.owner_id);
  IF v_row.created_by <> v_actor AND e.visibility <> v_row.visibility THEN
    PERFORM public.together_fail('forbidden');
  END IF;
  BEGIN
    UPDATE public.couple_events SET
      -- Only the creator decides what kind it is (a partner's save must not
      -- turn their big day back into a plain event; Phase 2b review).
      kind = CASE WHEN v_row.kind = 'ritual_occurrence' OR v_row.created_by <> v_actor
                  THEN v_row.kind ELSE coalesce(e.kind, 'event') END,
      title = btrim(e.title),
      note = nullif(btrim(e.note), ''), location_name = nullif(btrim(e.location_name), ''),
      all_day = e.all_day, start_date = e.start_date, end_date = e.end_date,
      starts_at = e.starts_at, ends_at = e.ends_at, tz = e.tz,
      rrule = e.rrule, recurrence_until = e.recurrence_until,
      participant_ids = e.participant_ids, owner_id = e.owner_id,
      visibility = coalesce(e.visibility, 'shared'),
      remind_offsets_min = coalesce(e.remind_offsets_min, '{}'),
      about_member_id = e.about_member_id, planning_entry_id = e.planning_entry_id,
      -- A pending hand-off ends if the event stops being shared with them.
      owner_proposed_to = CASE
        WHEN coalesce(e.visibility, 'shared') <> 'shared'
          OR NOT (owner_proposed_to = ANY (e.participant_ids)) THEN NULL
        ELSE owner_proposed_to END,
      owner_proposed_at = CASE
        WHEN coalesce(e.visibility, 'shared') <> 'shared'
          OR NOT (owner_proposed_to = ANY (e.participant_ids)) THEN NULL
        ELSE owner_proposed_at END
    WHERE id = v_row.id;
  EXCEPTION WHEN check_violation OR not_null_violation THEN
    PERFORM public.together_fail('invalid_input');
  END;
END;
$$;

CREATE FUNCTION public.delete_couple_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events;
BEGIN
  SELECT * INTO v_row FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  -- Withdrawing a sent proposal: its creator only.
  IF FOUND AND v_row.status = 'proposed' THEN
    PERFORM public.together_actor(v_row.relationship_id);
    IF v_row.created_by <> auth.uid() THEN PERFORM public.together_fail('not_found'); END IF;
  ELSE
    v_row := public.together_editable_event(p_event_id);
  END IF;
  -- A ritual's week is skipped, not deleted: a deleted week frees its slot
  -- and the daily cron would lay it out again (Phase 3 review #2).
  IF v_row.kind = 'ritual_occurrence' THEN
    UPDATE public.couple_events SET status = 'cancelled' WHERE id = v_row.id;
  ELSE
    UPDATE public.couple_events SET deleted_at = now() WHERE id = v_row.id;
  END IF;
END;
$$;

-- Step out of an event someone else put you in (spec §3.4): silent, and
-- the event goes away when nobody is left in it.
CREATE FUNCTION public.leave_couple_event(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
        v_actor uuid := auth.uid();
BEGIN
  IF NOT (v_actor = ANY (v_row.participant_ids)) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  IF cardinality(v_row.participant_ids) = 1 THEN
    UPDATE public.couple_events SET deleted_at = now() WHERE id = v_row.id;
  ELSE
    UPDATE public.couple_events
    SET participant_ids = array_remove(participant_ids, v_actor),
        owner_id = CASE WHEN owner_id = v_actor THEN NULL ELSE owner_id END,
        owner_proposed_to = CASE WHEN owner_proposed_to = v_actor THEN NULL ELSE owner_proposed_to END,
        owner_proposed_at = CASE WHEN owner_proposed_to = v_actor THEN NULL ELSE owner_proposed_at END
    WHERE id = v_row.id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.create_couple_event(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_couple_event(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_couple_event(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.leave_couple_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_couple_event(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_couple_event(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_couple_event(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_couple_event(uuid) TO authenticated;
