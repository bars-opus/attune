-- Together Phase 1a contracts (spec 2026-10-14 §3, §5). Self-contained
-- fixtures; every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7b000000-0000-0000-0000-0000000000a1'),
  ('7b000000-0000-0000-0000-0000000000b2'),
  ('7b000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7b000000-0000-0000-0000-0000000000a1', '+233270000001', 'Ama'),
  ('7b000000-0000-0000-0000-0000000000b2', '+233270000002', 'Kofi'),
  ('7b000000-0000-0000-0000-0000000000c3', '+233270000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f000000-0000-0000-0000-000000000001',
        '7b000000-0000-0000-0000-0000000000a1',
        '7b000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated;

-- 1. Ama creates a shared timed event, a busy_only one and a private one.
DO $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  INSERT INTO t_ids VALUES ('shared', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"starts_at":"2026-11-06T19:00:00Z","ends_at":"2026-11-06T21:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"],"note":"Book a table","remind_offsets_min":[60]}'::jsonb));
  INSERT INTO t_ids VALUES ('busy', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Therapy","all_day":false,"starts_at":"2026-11-06T10:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"visibility":"busy_only","note":"private note"}'::jsonb));
  INSERT INTO t_ids VALUES ('private', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Pick up ring","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"visibility":"private","remind_offsets_min":[0]}'::jsonb));
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Invalid input is rejected with together:* codes, never a raw error.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  -- end before start
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","end_date":"2026-11-06","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: end before start accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- a stranger as participant
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000c3"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger participant accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- owner set to the partner is a hand-off (Phase 2)
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Plumber","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000a1"],"owner_id":"7b000000-0000-0000-0000-0000000000b2"}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: owner hand-off accepted directly';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:owner_handoff' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- BYDAY on a non-weekly rule
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","rrule":"FREQ=DAILY;BYDAY=MO","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: BYDAY on DAILY accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  -- a private event that includes the partner
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","visibility":"private","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: private event with partner accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Permissions: the partner can edit and leave a shared event, but can't
--    touch busy_only/private ones; a stranger can't create; the table is
--    not readable directly (R1).
DO $$
DECLARE v_msg text; v_n int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000b2','role','authenticated')::text, true);
  PERFORM public.update_couple_event((SELECT id FROM t_ids WHERE name='shared'),
    '{"title":"Dinner at Buka (8pm)","all_day":false,"starts_at":"2026-11-06T20:00:00Z","tz":"Africa/Accra","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  BEGIN
    PERFORM public.delete_couple_event((SELECT id FROM t_ids WHERE name='busy'));
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner deleted a busy_only event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM public.leave_couple_event((SELECT id FROM t_ids WHERE name='shared'));
  SELECT count(*) INTO v_n FROM public.couple_events
  WHERE id = (SELECT id FROM t_ids WHERE name='shared')
    AND NOT ('7b000000-0000-0000-0000-0000000000b2' = ANY(participant_ids)) AND deleted_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: leave did not remove the partner only'; END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000c3','role','authenticated')::text, true);
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"x","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000c3"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger created an event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.couple_events;
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_events readable directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Recurrence: weekly across DST, monthly on the 31st, yearly Feb 29.
DO $$
DECLARE v_id uuid; v_dates date[]; v_utc timestamptz[];
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Date night","all_day":false,"starts_at":"2026-10-16T18:00:00Z","ends_at":"2026-10-16T20:00:00Z","tz":"Europe/London","rrule":"FREQ=WEEKLY;BYDAY=FR","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT array_agg(item_date ORDER BY item_date), array_agg(starts_at ORDER BY item_date)
  INTO v_dates, v_utc
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-10-15', '2026-11-01')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2026-10-16','2026-10-23','2026-10-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: weekly dates %', v_dates;
  END IF;
  -- 19:00 London is 18:00Z in BST and 19:00Z after the 25 Oct change.
  IF v_utc[1] <> '2026-10-16T18:00:00Z'::timestamptz OR v_utc[3] <> '2026-10-30T19:00:00Z'::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: DST not kept local %', v_utc;
  END IF;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Rent","all_day":true,"start_date":"2026-08-31","rrule":"FREQ=MONTHLY","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT array_agg(item_date ORDER BY item_date) INTO v_dates
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-09-01', '2026-11-30')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2026-09-30','2026-10-31','2026-11-30']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: monthly 31st %', v_dates;
  END IF;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Leap day","all_day":true,"start_date":"2024-02-29","rrule":"FREQ=YEARLY","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT array_agg(item_date) INTO v_dates
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2027-02-01', '2027-03-15')
  WHERE item_id = v_id;
  IF v_dates <> ARRAY['2027-02-28']::date[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 in a non-leap year %', v_dates;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. What the partner sees: busy_only masked, private absent, and the
--    union carries moments, reminders and Planning too.
DO $$
DECLARE v_title text; v_ref jsonb; v_n int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7f000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-0000000000a1', 'highlight', 'Beach', '2026-11-05');
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7f000000-0000-0000-0000-000000000001', '7b000000-0000-0000-0000-0000000000a1', 'birthday', 'Ama''s birthday', '2020-11-04', 'yearly');

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000b2','role','authenticated')::text, true);
  SELECT title, source_ref INTO v_title, v_ref
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='busy');
  IF v_title <> 'Busy' OR v_ref ? 'note' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy_only leaks to the partner (% %)', v_title, v_ref;
  END IF;
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='private');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private event visible to the partner'; END IF;
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE (item_kind = 'moment' AND item_date = '2026-11-05')
     OR (item_kind = 'reminder' AND item_date = '2026-11-04');
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: moment/reminder missing from the union (%)', v_n; END IF;

  -- The creator sees her own private event and the busy one's real title.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  SELECT count(*) INTO v_n
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id IN ((SELECT id FROM t_ids WHERE name='private'), (SELECT id FROM t_ids WHERE name='busy'))
    AND title IN ('Pick up ring', 'Therapy');
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: creator cannot see own events (%)', v_n; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5b. Planning dates and to-dos are in the union; a to-do without text
--     comes back with an empty title, never NULL.
DO $$
DECLARE v_entry uuid; v_block uuid; v_days int; v_item_title text;
BEGIN
  INSERT INTO public.planning_entries (relationship_id, title)
  VALUES ('7f000000-0000-0000-0000-000000000001', 'Lisbon trip') RETURNING id INTO v_entry;
  INSERT INTO public.planning_blocks (entry_id, relationship_id, block_type, date_start, date_end)
  VALUES (v_entry, '7f000000-0000-0000-0000-000000000001', 'date', '2026-11-12', '2026-11-14') RETURNING id INTO v_block;
  INSERT INTO public.planning_block_items (block_id, relationship_id, text, due_date)
  VALUES (v_block, '7f000000-0000-0000-0000-000000000001', NULL, '2026-11-11');

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000b2','role','authenticated')::text, true);
  SELECT count(*) INTO v_days
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_kind = 'planning_date' AND item_id = v_entry;
  IF v_days <> 3 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: planning date block should cover 3 days, got %', v_days; END IF;
  SELECT title INTO v_item_title
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_kind = 'planning_item' AND item_date = '2026-11-11';
  IF v_item_title IS DISTINCT FROM '' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: to-do title %', v_item_title; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Range limits, membership, and no scorecard columns (spec §3.1).
DO $$
DECLARE v_msg text; v_result text;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-01-01', '2026-06-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: >93-day range accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:range' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-06-01', '2026-05-01');
    RAISE EXCEPTION 'CONTRACT VIOLATED: reversed range accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000c3','role','authenticated')::text, true);
  BEGIN
    PERFORM count(*) FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger read the couple''s items';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT pg_get_function_result('public.list_together_items(uuid, date, date)'::regprocedure) INTO v_result;
  IF v_result ~* '(count|total|tally|score)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: list_together_items returns an aggregate column: %', v_result;
  END IF;
END $$;

-- 7. Alarms: a shared event's 60-minute alarm reaches both participants
--    once; a private event's goes to its creator only (R6, spec §3.6).
DO $$
DECLARE v_n int; v_again int; v_private_partner int;
BEGIN
  -- The shared event now starts 2026-11-06 20:00Z with Ama only (Kofi left
  -- in section 3), so add Kofi back via a fresh event for a clean check.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  INSERT INTO t_ids VALUES ('alarm', public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Flight","all_day":false,"starts_at":"2026-11-10T09:00:00Z","tz":"UTC","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"],"remind_offsets_min":[60]}'::jsonb));
  PERFORM set_config('request.jwt.claims', '', true);

  PERFORM public.together_enqueue_event_alarms('2026-11-10T08:05:00Z');
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='alarm') || ':%'
    AND metadata->>'type' = 'together_event';
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 alarm pushes, got %', v_n; END IF;

  PERFORM public.together_enqueue_event_alarms('2026-11-10T08:15:00Z');
  SELECT count(*) INTO v_again FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='alarm') || ':%';
  IF v_again <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: alarm sent twice (%)', v_again; END IF;

  -- private all-day event on 2026-11-07, offset 0 → 08:00 creator-local (UTC here).
  PERFORM public.together_enqueue_event_alarms('2026-11-07T08:05:00Z');
  SELECT count(*) INTO v_private_partner FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='private') || ':%'
    AND user_id = '7b000000-0000-0000-0000-0000000000b2';
  IF v_private_partner <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private alarm reached the partner'; END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE source_key LIKE 'together_alarm:' || (SELECT id FROM t_ids WHERE name='private') || ':%'
    AND user_id = '7b000000-0000-0000-0000-0000000000a1';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private alarm missing for its creator (%)', v_n; END IF;
END $$;

-- 8. Review fixes. (a) busy_only/private events hold only their creator;
--    flipping a shared event with the partner in it to private is refused.
--    (b) A repeat that ends before it starts is refused. (c) An update
--    without a visibility key keeps the event's visibility. (d) A 3-day
--    timed event returns 3 rows, only the first not a continuation.
DO $$
DECLARE v_msg text; v_id uuid; v_vis text; v_rows int; v_first int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub','7b000000-0000-0000-0000-0000000000a1','role','authenticated')::text, true);
  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","visibility":"busy_only","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy_only event with the partner accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Lunch","all_day":true,"start_date":"2026-11-20","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  BEGIN
    PERFORM public.update_couple_event(v_id,
      '{"title":"Lunch","all_day":true,"start_date":"2026-11-20","visibility":"private","participant_ids":["7b000000-0000-0000-0000-0000000000a1","7b000000-0000-0000-0000-0000000000b2"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: shared→private with the partner inside accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;

  BEGIN
    PERFORM public.create_couple_event('7f000000-0000-0000-0000-000000000001',
      '{"title":"Bad","all_day":true,"start_date":"2026-11-07","rrule":"FREQ=WEEKLY","recurrence_until":"2026-11-01","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: repeat ending before the start accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;

  PERFORM public.update_couple_event((SELECT id FROM t_ids WHERE name='private'),
    '{"title":"Pick up the ring","all_day":true,"start_date":"2026-11-07","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT visibility INTO v_vis FROM public.couple_events WHERE id = (SELECT id FROM t_ids WHERE name='private');
  IF v_vis <> 'private' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: update without visibility made it %', v_vis; END IF;

  v_id := public.create_couple_event('7f000000-0000-0000-0000-000000000001',
    '{"title":"Road trip","all_day":false,"starts_at":"2026-11-23T10:00:00Z","ends_at":"2026-11-25T18:00:00Z","tz":"UTC","participant_ids":["7b000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT count(*), count(*) FILTER (WHERE NOT coalesce((source_ref->>'continuation')::boolean, false))
  INTO v_rows, v_first
  FROM public.list_together_items('7f000000-0000-0000-0000-000000000001', '2026-11-20', '2026-11-30')
  WHERE item_id = v_id;
  IF v_rows <> 3 OR v_first <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 3-day timed event rows % (non-continuation %)', v_rows, v_first;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
