-- Together: "this one only" for repeating events. A series keeps the
-- dates its occurrences were skipped or moved away from; together_event_dates
-- leaves those out, so the list, the ICS feed, the alarms and the digest
-- all agree. Dates are in the event's own zone (the date space
-- together_event_dates yields). Not client-writable: create_couple_event
-- and update_couple_event never read it from the payload.

ALTER TABLE public.couple_events
  ADD COLUMN excluded_dates date[] NOT NULL DEFAULT '{}';

-- As before, minus the skipped dates. A one-off ignores the column (it is
-- always empty for one; a stray value must never hide an event).
CREATE OR REPLACE FUNCTION public.together_event_dates(e public.couple_events, p_start date, p_end date)
RETURNS SETOF date LANGUAGE sql STABLE AS $$
  WITH a AS (
    SELECT
      CASE WHEN e.all_day THEN e.start_date
           ELSE (e.starts_at AT TIME ZONE e.tz)::date END AS anchor,
      CASE WHEN e.all_day THEN coalesce(e.end_date, e.start_date)
           ELSE (coalesce(e.ends_at, e.starts_at) AT TIME ZONE e.tz)::date END AS last_day,
      substring(e.rrule FROM 'FREQ=([A-Z]+)') AS freq,
      coalesce(substring(e.rrule FROM 'INTERVAL=([0-9]+)')::int, 1) AS step,
      string_to_array(substring(e.rrule FROM 'BYDAY=([A-Z,]+)'), ',') AS bydays
  )
  SELECT d::date
  FROM a, generate_series(
    greatest(p_start, a.anchor),
    least(p_end, CASE WHEN e.rrule IS NULL THEN a.last_day
                      ELSE coalesce(e.recurrence_until, p_end) END),
    interval '1 day') AS d
  WHERE (e.rrule IS NULL OR d::date <> ALL (coalesce(e.excluded_dates, '{}')))
    AND (e.rrule IS NULL
     OR (a.freq = 'DAILY' AND (d::date - a.anchor) % a.step = 0)
     OR (a.freq = 'WEEKLY'
         AND (ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM d)::int]
             = ANY (coalesce(a.bydays,
                ARRAY[(ARRAY['MO','TU','WE','TH','FR','SA','SU'])[extract(isodow FROM a.anchor)::int]]))
         AND (((d::date - (extract(isodow FROM d)::int - 1))
               - (a.anchor - (extract(isodow FROM a.anchor)::int - 1))) / 7) % a.step = 0)
     OR (a.freq = 'MONTHLY'
         AND ((extract(year FROM d)::int * 12 + extract(month FROM d)::int)
              - (extract(year FROM a.anchor)::int * 12 + extract(month FROM a.anchor)::int)) % a.step = 0
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date)))
     OR (a.freq = 'YEARLY'
         AND (extract(year FROM d)::int - extract(year FROM a.anchor)::int) % a.step = 0
         AND extract(month FROM d) = extract(month FROM a.anchor)
         AND extract(day FROM d)::int
             = least(extract(day FROM a.anchor)::int, public.together_last_day(d::date))))
$$;

-- Skip one date of a confirmed repeating event. Who may: exactly who may
-- edit it (together_editable_event). Rituals skip a week their own way.
CREATE FUNCTION public.skip_couple_event_occurrence(p_event_id uuid, p_on date)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_row public.couple_events := public.together_editable_event(p_event_id);
BEGIN
  IF p_on IS NULL OR v_row.rrule IS NULL OR v_row.kind = 'ritual_occurrence' THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  -- Already skipped: nothing to do (a retried request must not fail).
  IF p_on = ANY (v_row.excluded_dates) THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.together_event_dates(v_row, p_on, p_on)) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  UPDATE public.couple_events
  SET excluded_dates = array_append(excluded_dates, p_on)
  WHERE id = v_row.id AND NOT (p_on = ANY (excluded_dates));
END;
$$;

-- "This one only": skip p_on on the series and make a one-off from
-- p_event in its place, in one step (a refused one-off skips nothing).
-- The one-off goes through create_couple_event's checks with any repeat
-- stripped, then stays the series creator's: created_by (so who may
-- change its visibility doesn't flip to whoever moved it) and, for a
-- partner, the kind (as update_couple_event keeps it). A partner may not
-- change visibility on the way out, as in update_couple_event.
CREATE FUNCTION public.detach_couple_event_occurrence(p_event_id uuid, p_on date, p_event jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.couple_events := public.together_editable_event(p_event_id);
  v_actor uuid := auth.uid();
  v_visibility text := coalesce(p_event->>'visibility', v_row.visibility);
  v_owner uuid := nullif(p_event->>'owner_id', '')::uuid;
  v_id uuid;
BEGIN
  PERFORM public.skip_couple_event_occurrence(p_event_id, p_on);
  IF v_row.created_by <> v_actor AND v_visibility <> v_row.visibility THEN
    PERFORM public.together_fail('forbidden');
  END IF;
  -- The holder, judged against the series (as an update is): whoever holds
  -- it keeps holding this one, and taking it yourself is fine; naming
  -- anyone else is a hand-off, which is asked, not saved. create alone
  -- would see every holder but the actor as a hand-off.
  IF v_owner IS NOT NULL AND v_owner <> v_actor
     AND v_owner IS DISTINCT FROM v_row.owner_id THEN
    PERFORM public.together_fail(CASE WHEN EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = v_row.relationship_id AND v_owner IN (r.user_a, r.user_b))
      THEN 'owner_handoff' ELSE 'invalid_input' END);
  END IF;
  v_id := public.create_couple_event(v_row.relationship_id,
    coalesce(p_event, '{}'::jsonb) || jsonb_build_object(
      'rrule', NULL, 'recurrence_until', NULL, 'visibility', v_visibility,
      'owner_id', NULL));
  UPDATE public.couple_events
  SET created_by = v_row.created_by,
      owner_id = v_owner,
      kind = CASE WHEN v_row.created_by <> v_actor THEN v_row.kind ELSE kind END
  WHERE id = v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.skip_couple_event_occurrence(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.detach_couple_event_occurrence(uuid, date, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.skip_couple_event_occurrence(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.detach_couple_event_occurrence(uuid, date, jsonb) TO authenticated;

-- "All repeats" (update_couple_event, re-created as in Phase 1a with one
-- more column): skipped dates before the new start are history and go;
-- later ones stay, even if the rule no longer lands on them (harmless).
-- An event that stops repeating drops them all, so a one-off can never
-- be hidden by its own past.
CREATE OR REPLACE FUNCTION public.update_couple_event(p_event_id uuid, p_event jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_row public.couple_events := public.together_editable_event(p_event_id);
  v_actor uuid := auth.uid();
  e public.together_event_input;
  v_anchor date;
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
  v_anchor := coalesce(e.start_date, (e.starts_at AT TIME ZONE coalesce(e.tz, 'UTC'))::date);
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
      excluded_dates = CASE WHEN e.rrule IS NULL THEN '{}'::date[]
        ELSE ARRAY(SELECT x FROM unnest(excluded_dates) AS x WHERE x >= v_anchor ORDER BY x) END,
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
