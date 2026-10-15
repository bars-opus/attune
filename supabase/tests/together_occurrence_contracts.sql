-- Together "this one only" contracts: skipping and detaching one occurrence
-- of a repeating couple event. Self-contained fixtures; every check RAISEs
-- on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7c000000-0000-0000-0000-0000000000a1'),
  ('7c000000-0000-0000-0000-0000000000b2'),
  ('7c000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7c000000-0000-0000-0000-0000000000a1', '+233280000001', 'Ama'),
  ('7c000000-0000-0000-0000-0000000000b2', '+233280000002', 'Kofi'),
  ('7c000000-0000-0000-0000-0000000000c3', '+233280000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7c100000-0000-0000-0000-000000000001',
        '7c000000-0000-0000-0000-0000000000a1',
        '7c000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.dates(p_event uuid) RETURNS date[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(item_date ORDER BY item_date), '{}')
  FROM public.list_together_items('7c100000-0000-0000-0000-000000000001', '2026-10-15', '2026-11-01')
  WHERE item_id = p_event $$;
CREATE FUNCTION pg_temp.excluded(p_event uuid) RETURNS date[] LANGUAGE sql AS $$
  SELECT excluded_dates FROM public.couple_events WHERE id = p_event $$;
CREATE FUNCTION pg_temp.expect_fail(p_sql text, p_code text, p_what text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'CONTRACT VIOLATED: % accepted', p_what;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
    IF v_msg <> 'together:' || p_code THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % → % (wanted together:%)', p_what, v_msg, p_code;
    END IF;
  END;
END $$;

-- 0. The column is there and not client-writable through create.
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Date night","all_day":false,"starts_at":"2026-10-16T18:00:00Z","ends_at":"2026-10-16T20:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=FR","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"],"remind_offsets_min":[60],"excluded_dates":["2026-10-16"]}'::jsonb);
  INSERT INTO t_ids VALUES ('weekly', v_id);
  IF pg_temp.excluded(v_id) <> '{}'::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: create took excluded_dates from the client';
  END IF;
  IF pg_temp.dates(v_id) <> ARRAY['2026-10-16','2026-10-23','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: weekly dates %', pg_temp.dates(v_id);
  END IF;
  INSERT INTO t_ids VALUES ('oneoff', public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Dentist","all_day":true,"start_date":"2026-10-20","participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'::jsonb));
  INSERT INTO t_ids VALUES ('private', public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Therapy","all_day":true,"start_date":"2026-10-19","rrule":"FREQ=WEEKLY","visibility":"private","participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'::jsonb));
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 1. The partner skips one Friday: it leaves the list, the alarms and the
--    digest for that day only. Skipping it again is a no-op.
DO $$
DECLARE v_id uuid := (SELECT id FROM t_ids WHERE name='weekly'); v_n int; v_lines text[];
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM public.skip_couple_event_occurrence(v_id, '2026-10-23');
  PERFORM public.skip_couple_event_occurrence(v_id, '2026-10-23');
  IF pg_temp.excluded(v_id) <> ARRAY['2026-10-23']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skip not idempotent %', pg_temp.excluded(v_id);
  END IF;
  IF pg_temp.dates(v_id) <> ARRAY['2026-10-16','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skipped date still listed %', pg_temp.dates(v_id);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  -- 19:00 London on 23 Oct is 18:00Z (BST); the 60-minute alarm would fire at 17:00Z.
  PERFORM public.together_enqueue_event_alarms('2026-10-23T17:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || v_id || ':2026-10-23:%';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: skipped date still alarms (%)', v_n; END IF;
  -- 30 Oct is after the clocks change: 19:00Z, alarm at 18:00Z, both partners.
  PERFORM public.together_enqueue_event_alarms('2026-10-30T18:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || v_id || ':2026-10-30:%';
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the other dates should still alarm (%)', v_n; END IF;

  v_lines := public.together_digest_lines('7c100000-0000-0000-0000-000000000001',
    '7c000000-0000-0000-0000-0000000000a1', '2026-10-23', '2026-10-23', 'Europe/London', true, false);
  IF EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE l LIKE '%Date night%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: skipped date in the digest %', v_lines;
  END IF;
  v_lines := public.together_digest_lines('7c100000-0000-0000-0000-000000000001',
    '7c000000-0000-0000-0000-0000000000a1', '2026-10-30', '2026-10-30', 'Europe/London', true, false);
  IF NOT EXISTS (SELECT 1 FROM unnest(v_lines) l WHERE l LIKE '%Date night%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other dates missing from the digest %', v_lines;
  END IF;
END $$;

-- 2. Refusals: a date that isn't an occurrence, a one-off, a ritual's
--    week, an outsider, and the partner on a private series.
DO $$
DECLARE v_id uuid := (SELECT id FROM t_ids WHERE name='weekly'); v_rit uuid;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)', v_id, '2026-10-24'),
    'invalid_input', 'skipping a Saturday of a Friday series');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)', v_id, '2026-10-09'),
    'invalid_input', 'skipping a date before the series starts');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, NULL)', v_id),
    'invalid_input', 'skipping a null date');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)',
      (SELECT id FROM t_ids WHERE name='oneoff'), '2026-10-20'),
    'invalid_input', 'skipping a one-off event');
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)',
      (SELECT id FROM t_ids WHERE name='oneoff'), '2026-10-20',
      '{"title":"Dentist","all_day":true,"start_date":"2026-10-21","participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'),
    'invalid_input', 'detaching a one-off event');
  PERFORM set_config('request.jwt.claims', '', true);

  INSERT INTO public.couple_events (relationship_id, created_by, kind, title, all_day, starts_at, ends_at, tz,
    participant_ids, visibility, status, ritual_date)
  VALUES ('7c100000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-0000000000a1', 'ritual_occurrence',
    'Walk', false, '2026-10-25T09:00:00Z', '2026-10-25T10:00:00Z', 'UTC',
    ARRAY['7c000000-0000-0000-0000-0000000000a1','7c000000-0000-0000-0000-0000000000b2']::uuid[],
    'shared', 'confirmed', '2026-10-25')
  RETURNING id INTO v_rit;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)', v_rit, '2026-10-25'),
    'invalid_input', 'skipping a ritual week here (rituals have their own skip)');
  PERFORM set_config('request.jwt.claims', '', true);

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000c3');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)', v_id, '2026-10-30'),
    'not_found', 'an outsider skipping');
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)', v_id, '2026-10-30',
      '{"title":"Date night","all_day":false,"starts_at":"2026-10-30T20:00:00Z","tz":"Europe/London","participant_ids":["7c000000-0000-0000-0000-0000000000c3"]}'),
    'not_found', 'an outsider detaching');
  PERFORM set_config('request.jwt.claims', '', true);

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM pg_temp.expect_fail(format('SELECT public.skip_couple_event_occurrence(%L, %L)',
      (SELECT id FROM t_ids WHERE name='private'), '2026-10-26'),
    'not_found', 'the partner skipping a private series');
  PERFORM set_config('request.jwt.claims', '', true);

  IF pg_temp.excluded(v_id) <> ARRAY['2026-10-23']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refusal changed excluded_dates %', pg_temp.excluded(v_id);
  END IF;

  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.skip_couple_event_occurrence(v_id, '2026-10-30');
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may call skip_couple_event_occurrence';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.detach_couple_event_occurrence(v_id, '2026-10-30', '{}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may call detach_couple_event_occurrence';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $$;

-- 3. Detach: the partner moves one Friday an hour later. A one-off appears
--    at the new time, the series loses that date, and the one-off stays
--    the series creator's (visibility, big days) with no repeat of its own.
DO $$
DECLARE v_id uuid := (SELECT id FROM t_ids WHERE name='weekly'); v_new uuid; v_row public.couple_events;
        v_at timestamptz; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  v_new := public.detach_couple_event_occurrence(v_id, '2026-10-30',
    '{"title":"Date night (late)","all_day":false,"starts_at":"2026-10-30T20:00:00Z","ends_at":"2026-10-30T22:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=FR","recurrence_until":"2027-01-01","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"],"remind_offsets_min":[60]}'::jsonb);
  INSERT INTO t_ids VALUES ('detached', v_new);
  IF v_new IS NULL OR v_new = v_id THEN RAISE EXCEPTION 'CONTRACT VIOLATED: detach returned %', v_new; END IF;
  SELECT * INTO v_row FROM public.couple_events WHERE id = v_new;
  IF v_row.rrule IS NOT NULL OR v_row.recurrence_until IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the detached one-off repeats (%)', v_row.rrule;
  END IF;
  IF v_row.starts_at <> '2026-10-30T20:00:00Z'::timestamptz OR v_row.title <> 'Date night (late)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: detached one-off not on the edited time (% %)', v_row.starts_at, v_row.title;
  END IF;
  IF v_row.created_by <> '7c000000-0000-0000-0000-0000000000a1' OR v_row.visibility <> 'shared' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the one-off should stay the series creator''s (% %)', v_row.created_by, v_row.visibility;
  END IF;
  IF pg_temp.excluded(v_id) <> ARRAY['2026-10-23','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: series excluded_dates %', pg_temp.excluded(v_id);
  END IF;
  IF pg_temp.dates(v_id) <> ARRAY['2026-10-16']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: series still lists the detached date %', pg_temp.dates(v_id);
  END IF;
  SELECT starts_at INTO v_at
  FROM public.list_together_items('7c100000-0000-0000-0000-000000000001', '2026-10-15', '2026-11-01')
  WHERE item_id = v_new;
  IF v_at <> '2026-10-30T20:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one-off listed at %', v_at;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  -- The series' alarm for that Friday is gone; the one-off's fires at its new time.
  PERFORM public.together_enqueue_event_alarms('2026-10-30T19:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || v_new || ':2026-10-30:%';
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: one-off alarms %', v_n; END IF;
END $$;

-- 4. Detach is one step: a bad one-off leaves the series untouched. The
--    partner can't change who sees it on the way out; the creator can't
--    change it to something the rules refuse either.
DO $$
DECLARE v_id uuid := (SELECT id FROM t_ids WHERE name='weekly');
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)', v_id, '2026-10-16',
      '{"title":"   ","all_day":false,"starts_at":"2026-10-16T18:00:00Z","tz":"Europe/London","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'),
    'invalid_input', 'detaching into an untitled one-off');
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)', v_id, '2026-10-16',
      '{"title":"Date night","all_day":false,"starts_at":"2026-10-16T18:00:00Z","tz":"Europe/London","visibility":"private","participant_ids":["7c000000-0000-0000-0000-0000000000b2"]}'),
    'forbidden', 'the partner making one occurrence private');
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)', v_id, '2026-10-17',
      '{"title":"Date night","all_day":false,"starts_at":"2026-10-17T18:00:00Z","tz":"Europe/London","participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'),
    'invalid_input', 'detaching a date that is not an occurrence');
  PERFORM set_config('request.jwt.claims', '', true);
  IF pg_temp.excluded(v_id) <> ARRAY['2026-10-23','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed detach skipped the date %', pg_temp.excluded(v_id);
  END IF;
  IF (SELECT count(*) FROM public.couple_events WHERE relationship_id = '7c100000-0000-0000-0000-000000000001'
      AND deleted_at IS NULL AND kind <> 'ritual_occurrence') <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed detach left an event behind';
  END IF;
END $$;

-- 5. "All repeats": an update keeps excluded dates from the new start on,
--    and drops them all when the event stops repeating.
DO $$
DECLARE v_id uuid := (SELECT id FROM t_ids WHERE name='weekly');
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  -- Series moved to start Wed 28 Oct (still Fridays): the 23rd is history.
  PERFORM public.update_couple_event(v_id,
    '{"title":"Date night","all_day":false,"starts_at":"2026-10-28T19:00:00Z","ends_at":"2026-10-28T21:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=FR","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"],"remind_offsets_min":[60],"excluded_dates":[]}'::jsonb);
  IF pg_temp.excluded(v_id) <> ARRAY['2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: update should keep skips from the new start on, got %', pg_temp.excluded(v_id);
  END IF;
  IF pg_temp.dates(v_id) <> '{}'::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the move, Oct should be empty: %', pg_temp.dates(v_id);
  END IF;
  PERFORM public.update_couple_event(v_id,
    '{"title":"Date night","all_day":false,"starts_at":"2026-10-30T19:00:00Z","ends_at":"2026-10-30T21:00:00Z","tz":"Europe/London","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  IF pg_temp.excluded(v_id) <> '{}'::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a one-off keeps skips %', pg_temp.excluded(v_id);
  END IF;
  IF pg_temp.dates(v_id) <> ARRAY['2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a one-off on a once-skipped date must show: %', pg_temp.dates(v_id);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Moving one occurrence of an event someone holds: the holder stays,
--    taking it yourself is fine, and naming anyone else isn't a save.
DO $$
DECLARE v_id uuid; v_new uuid; v_owner uuid;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Gym","all_day":false,"starts_at":"2026-10-19T07:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=MO","owner_id":"7c000000-0000-0000-0000-0000000000a1","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  v_new := public.detach_couple_event_occurrence(v_id, '2026-10-26',
    '{"title":"Gym","all_day":false,"starts_at":"2026-10-26T08:00:00Z","tz":"Europe/London","owner_id":"7c000000-0000-0000-0000-0000000000a1","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT owner_id INTO v_owner FROM public.couple_events WHERE id = v_new;
  IF v_owner IS DISTINCT FROM '7c000000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the moved occurrence lost its holder (%)', v_owner;
  END IF;
  v_new := public.detach_couple_event_occurrence(v_id, '2026-11-02',
    '{"title":"Gym","all_day":false,"starts_at":"2026-11-02T08:00:00Z","tz":"Europe/London","owner_id":"7c000000-0000-0000-0000-0000000000b2","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT owner_id INTO v_owner FROM public.couple_events WHERE id = v_new;
  IF v_owner IS DISTINCT FROM '7c000000-0000-0000-0000-0000000000b2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: taking one occurrence yourself failed (%)', v_owner;
  END IF;
  PERFORM pg_temp.expect_fail(format('SELECT public.detach_couple_event_occurrence(%L, %L, %L::jsonb)', v_id, '2026-11-09',
    '{"title":"Gym","all_day":false,"starts_at":"2026-11-09T08:00:00Z","tz":"Europe/London","owner_id":"7c000000-0000-0000-0000-0000000000c3","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'),
    'invalid_input', 'holding a moved occurrence by an outsider');
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. "All repeats" that moves the series says how, and skipped dates move
--    with it: a day for weekly, the picked day of the month for monthly.
DO $$
DECLARE v_w uuid; v_m uuid; v_d date[];
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_w := public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Swim","all_day":true,"start_date":"2026-10-16","rrule":"FREQ=WEEKLY;BYDAY=FR","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.skip_couple_event_occurrence(v_w, '2026-10-23');
  PERFORM public.update_couple_event(v_w,
    '{"title":"Swim","all_day":true,"start_date":"2026-10-17","rrule":"FREQ=WEEKLY;BYDAY=SA","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"],"excluded_shift":{"days":1}}'::jsonb);
  IF pg_temp.excluded(v_w) <> ARRAY['2026-10-24']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: weekly skip did not move with the series: %', pg_temp.excluded(v_w);
  END IF;
  SELECT coalesce(array_agg(item_date ORDER BY item_date), '{}') INTO v_d
  FROM public.list_together_items('7c100000-0000-0000-0000-000000000001', '2026-10-15', '2026-11-01') WHERE item_id = v_w;
  IF v_d <> ARRAY['2026-10-17','2026-10-31']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the skipped Saturday came back: %', v_d;
  END IF;

  v_m := public.create_couple_event('7c100000-0000-0000-0000-000000000001',
    '{"title":"Rent","all_day":true,"start_date":"2026-10-31","rrule":"FREQ=MONTHLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.skip_couple_event_occurrence(v_m, '2026-12-31');
  PERFORM public.skip_couple_event_occurrence(v_m, '2027-02-28');
  PERFORM public.update_couple_event(v_m,
    '{"title":"Rent","all_day":true,"start_date":"2026-10-29","rrule":"FREQ=MONTHLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"],"excluded_shift":{"months":0,"day":29}}'::jsonb);
  IF pg_temp.excluded(v_m) <> ARRAY['2026-12-29','2027-02-28']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: monthly skips not on the new day: %', pg_temp.excluded(v_m);
  END IF;
  -- Without the instruction, skips stay where they were (as before).
  PERFORM public.update_couple_event(v_m,
    '{"title":"Rent","all_day":true,"start_date":"2026-10-29","rrule":"FREQ=MONTHLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  IF pg_temp.excluded(v_m) <> ARRAY['2026-12-29','2027-02-28']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plain update moved skips: %', pg_temp.excluded(v_m);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
