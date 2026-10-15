-- supabase/migrations/20261015130000_together_followups.sql
--
-- Follow-ups to 20261015110000/120000 (already deployed):
--
-- 1. Skipped occurrences move with their series. "All repeats" from one
--    occurrence moves the whole series; it now says how (excluded_shift:
--    {"days": n} for daily/weekly, {"months": m, "day": k} for monthly,
--    {"years": y, "month": mo, "day": k} for yearly) and the skipped dates
--    move the same way, so a deleted "this one" doesn't come back a day
--    later. Without it (any other update), skips stay where they were.
-- 2. Deleting a family member takes only their birthday reminder; any
--    other reminder linked to them stays, unlinked (it was ON DELETE
--    CASCADE since 20261015100000).
-- 3. Members are renamed only through upsert_family_member, which keeps
--    their birthday reminder's title in step; a direct UPDATE skipped that.

-- [p_dates] moved as [p_shift] says; anything it doesn't describe stays.
CREATE OR REPLACE FUNCTION public.together_move_dates(p_dates date[], p_shift jsonb)
RETURNS date[] LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(
    CASE
      WHEN p_shift ? 'days' THEN x + (p_shift->>'days')::int
      WHEN p_shift ? 'months' AND p_shift ? 'day' THEN (
        SELECT make_date(extract(year FROM m)::int, extract(month FROM m)::int,
                         least((p_shift->>'day')::int, public.together_last_day(m::date)))
        FROM (SELECT date_trunc('month', x) + make_interval(months => (p_shift->>'months')::int) AS m) t)
      WHEN p_shift ? 'years' AND p_shift ? 'month' AND p_shift ? 'day' THEN (
        SELECT make_date(y, (p_shift->>'month')::int,
                         least((p_shift->>'day')::int,
                               public.together_last_day(make_date(y, (p_shift->>'month')::int, 1))))
        FROM (SELECT extract(year FROM x)::int + (p_shift->>'years')::int AS y) t)
      ELSE x
    END ORDER BY x), '{}')
  FROM unnest(p_dates) AS x
$$;
REVOKE ALL ON FUNCTION public.together_move_dates(date[], jsonb) FROM PUBLIC, anon, authenticated;

-- "All repeats" (as in 20261015120000, plus the skip move above).
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
      -- Skips move the way the series was moved, when the app says how
      -- ("All repeats" from one occurrence); otherwise they stay put.
      excluded_dates = CASE WHEN e.rrule IS NULL THEN '{}'::date[]
        ELSE ARRAY(SELECT DISTINCT x FROM unnest(
               CASE WHEN p_event ? 'excluded_shift'
                    THEN public.together_move_dates(excluded_dates, p_event->'excluded_shift')
                    ELSE excluded_dates END) AS x
             WHERE x >= v_anchor ORDER BY x) END,
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

-- ---- Family members ---------------------------------------------------------------

DO $$
DECLARE v_name text;
BEGIN
  SELECT conname INTO v_name FROM pg_constraint
  WHERE conrelid = 'public.reminders'::regclass AND contype = 'f'
    AND conkey = ARRAY[(SELECT attnum FROM pg_attribute
                        WHERE attrelid = 'public.reminders'::regclass AND attname = 'family_member_id')];
  IF v_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.reminders DROP CONSTRAINT %I', v_name);
  END IF;
END;
$$;
ALTER TABLE public.reminders
  ADD CONSTRAINT reminders_family_member_id_fkey
  FOREIGN KEY (family_member_id) REFERENCES public.couple_family_members(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.family_member_drop_birthday()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM public.reminders
  WHERE family_member_id = OLD.id AND reminder_type = 'birthday';
  RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION public.family_member_drop_birthday() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS family_member_drop_birthday ON public.couple_family_members;
CREATE TRIGGER family_member_drop_birthday
  BEFORE DELETE ON public.couple_family_members
  FOR EACH ROW EXECUTE FUNCTION public.family_member_drop_birthday();

REVOKE UPDATE ON public.couple_family_members FROM authenticated;
REVOKE UPDATE (name, birthday) ON public.couple_family_members FROM authenticated;
