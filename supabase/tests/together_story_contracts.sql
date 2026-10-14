-- Together Phase 4 contracts: the story layer. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f300000-0000-0000-0000-0000000000a1'), ('7f300000-0000-0000-0000-0000000000b2'), ('7f300000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f300000-0000-0000-0000-0000000000a1', '+233310000001', 'Ama'),
  ('7f300000-0000-0000-0000-0000000000b2', '+233310000002', 'Kofi'),
  ('7f300000-0000-0000-0000-0000000000c3', '+233310000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
        '7f300000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 1. A private conflict is its logger's alone: the table, the hub read, the verdict.
DO $$
DECLARE v_priv uuid; v_n int; v_def text;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
          'conflict', 'Money talk', '2026-10-10', 'private') RETURNING id INTO v_priv;
  INSERT INTO t_ids VALUES ('priv', v_priv);

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.timeline_events WHERE id = v_priv;
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner can read a private conflict'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7f400000-0000-0000-0000-000000000001', '2026-10-01', '2026-10-31')
  WHERE item_id = v_priv;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hub read leaks a private conflict'; END IF;

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.timeline_events WHERE id = v_priv;
  RESET ROLE;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: logger cannot read their private conflict'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7f400000-0000-0000-0000-000000000001', '2026-10-01', '2026-10-31')
  WHERE item_id = v_priv AND visibility = 'private';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: logger hub read lost the private conflict'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  BEGIN
    INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility)
    VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
            'highlight', 'Beach', '2026-10-11', 'private');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a private highlight was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SELECT pg_get_functiondef('public.request_verdict_generation(uuid)'::regprocedure) INTO v_def;
  SELECT count(*) INTO v_n FROM regexp_matches(v_def, 'te\.visibility = ''shared''', 'g');
  IF v_n < 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: verdict eligibility counts private moments (% filters)', v_n; END IF;
END $$;

-- Story fixtures (dated in the past: a memory needs an event that has begun
-- by the real clock): a lived shared dinner (Accra, timed), a Toronto-zoned all-day
-- picnic, and a private event.
DO $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Dinner at Buka', false,
          '2026-10-03T18:00:00Z', '2026-10-03T20:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[])
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('dinner', v);
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'Picnic', true, '2026-10-04',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[])
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('picnic', v);
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids, visibility)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Ring shopping', false,
          '2026-10-03T10:00:00Z', '2026-10-03T11:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1']::uuid[], 'private')
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('secret', v);
END $$;

-- 2. Prompts: after the dinner ends, both get one; not before, not after 3 days;
--    an all-day picnic ends at midnight in the viewer's zone (Review Focus 3).
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T19:00:00Z');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt before the event ended'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no prompt after the dinner'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-07T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt older than 3 days'; END IF;
  -- Picnic on Oct 4: over at Oct 5 00:00 Toronto (EDT) = 04:00Z; not yet at 03:00Z.
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'America/Toronto', '2026-10-05T03:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'picnic');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: all-day prompt used UTC, not the viewer zone'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'America/Toronto', '2026-10-05T05:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'picnic');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no all-day prompt after its day'; END IF;
  -- a private event never prompts (not both of us)
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'secret');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private event prompted'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Adding a memory: a highlight linked to the event on its local day; my prompt
--    goes, my partner's stays; bad lines and hidden events refused (Review Focus 4).
DO $$
DECLARE v_m uuid; v_type text; v_day date; v_link uuid; v_n int; v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  v_m := public.add_event_memory((SELECT id FROM t_ids WHERE name = 'dinner'), '  The jollof was perfect  ');
  INSERT INTO t_ids VALUES ('memory', v_m);
  SELECT event_type, occurred_at, couple_event_id INTO v_type, v_day, v_link FROM public.timeline_events WHERE id = v_m;
  IF v_type <> 'highlight' OR v_day <> '2026-10-03' OR v_link <> (SELECT id FROM t_ids WHERE name = 'dinner') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: memory saved as % on % linked %', v_type, v_day, v_link;
  END IF;
  IF (SELECT note FROM public.timeline_events WHERE id = v_m) <> 'The jollof was perfect' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: memory line not trimmed';
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt stayed after I added a memory'; END IF;
  BEGIN
    PERFORM public.add_event_memory((SELECT id FROM t_ids WHERE name = 'dinner'), '   ');
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank memory accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
  END;

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: my memory removed my partner''s prompt'; END IF;
  BEGIN
    PERFORM public.add_event_memory((SELECT id FROM t_ids WHERE name = 'secret'), 'peek');
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner added a memory to a private event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  -- "Not now" hides it for good, for me only
  PERFORM public.dismiss_memory_prompt((SELECT id FROM t_ids WHERE name = 'dinner'));
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: dismissed prompt came back'; END IF;
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'UTC');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger read prompts';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. On this day: earlier years, same day; no conflicts; no private conflict of my
--    partner's; an event with a memory shows once (as the memory); Feb 29 on Feb 28.
DO $$
DECLARE v_n int; v_kinds text[];
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'first', 'First date', '2024-10-03'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'conflict', 'Big fight', '2025-10-03'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'highlight', 'Leap day', '2024-02-29');
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'conflict', 'Kofi private', '2025-10-03', 'private');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT array_agg(item_kind || ':' || title ORDER BY item_date DESC, title) INTO v_kinds
  FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-10-03');
  IF v_kinds IS DISTINCT FROM ARRAY['moment:Dinner at Buka', 'moment:First date'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: on this day returned %', v_kinds;
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-10-03')
  WHERE title = 'First date' AND years_ago = 3;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: years_ago wrong'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2026-10-03');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: this year''s items counted as on-this-day (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-02-28')
  WHERE title = 'Leap day';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 not shown on Feb 28 of a common year'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2028-02-28')
  WHERE title = 'Leap day';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 shown on Feb 28 of a leap year'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. Ritual memories: moments on that ritual's weeks only; partner's private never.
DO $$
DECLARE v_rit uuid; v_ev uuid; v_n int;
BEGIN
  INSERT INTO public.couple_rituals (relationship_id, created_by, title, cadence, weekday, local_time, duration_min, tz, status)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Date night', 'weekly', 6,
          '19:00', 120, 'Africa/Accra', 'active') RETURNING id INTO v_rit;
  INSERT INTO public.couple_events (relationship_id, created_by, kind, title, all_day, starts_at, ends_at, tz, participant_ids, ritual_id, ritual_date)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'ritual_occurrence', 'Date night', false,
          '2026-10-03T19:00:00Z', '2026-10-03T21:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[], v_rit, '2026-10-03')
  RETURNING id INTO v_ev;
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  PERFORM public.add_event_memory(v_ev, 'Dancing after');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_ritual_memories(v_rit);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual memories %', v_n; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Archive pages: no skips or repeats across same-day ties; private stays private
--    (Review Focus 1, 5).
DO $$
DECLARE r record; v_seen uuid[] := '{}'; v_date date; v_id uuid; v_pages int := 0; v_total int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 1', '2026-09-01'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 2', '2026-09-01'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 3', '2026-09-01');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  LOOP
    v_pages := v_pages + 1;
    EXIT WHEN v_pages > 50;
    v_total := 0;
    FOR r IN SELECT * FROM public.list_together_moments('7f400000-0000-0000-0000-000000000001', v_date, v_id, 2) LOOP
      IF r.id = ANY (v_seen) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: archive repeated %', r.title; END IF;
      IF r.visibility = 'private' AND r.logged_by <> '7f300000-0000-0000-0000-0000000000b2' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: archive leaked a private conflict';
      END IF;
      v_seen := v_seen || r.id; v_date := r.occurred_at; v_id := r.id; v_total := v_total + 1;
    END LOOP;
    EXIT WHEN v_total < 2;
  END LOOP;
  IF cardinality(v_seen) <> (SELECT count(*) FROM public.timeline_events
      WHERE relationship_id = '7f400000-0000-0000-0000-000000000001' AND deleted_at IS NULL
        AND (visibility = 'shared' OR logged_by = '7f300000-0000-0000-0000-0000000000b2')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: archive skipped moments (% seen)', cardinality(v_seen);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. Review fixes: a repeating event and a one-person event take no memory
--    (the prompt never offers them; the server agrees).
DO $$
DECLARE v_rep uuid; v_solo uuid; v_msg text;
BEGIN
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids, rrule)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Walk', false,
          '2026-09-01T07:00:00Z', '2026-09-01T08:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[], 'FREQ=WEEKLY')
  RETURNING id INTO v_rep;
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Dentist', false,
          '2026-09-02T07:00:00Z', '2026-09-02T08:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1']::uuid[])
  RETURNING id INTO v_solo;
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.add_event_memory(v_rep, 'Nice walk');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeating event took a memory (dated to its first week)';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.add_event_memory(v_solo, 'Ouch');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a one-person event took a memory';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
