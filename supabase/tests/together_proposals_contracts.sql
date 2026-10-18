-- Together Phase 2a contracts: proposals, hand-offs, Needs you.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('7c000000-0000-0000-0000-0000000000a1'), ('7c000000-0000-0000-0000-0000000000b2'),
  ('7c000000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7c000000-0000-0000-0000-0000000000a1', '+233280000001', 'Ama'),
  ('7c000000-0000-0000-0000-0000000000b2', '+233280000002', 'Kofi'),
  ('7c000000-0000-0000-0000-0000000000c3', '+233280000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7d000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-0000000000a1',
        '7c000000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 1. Ama proposes Fri or Sat; Kofi gets one push; it isn't a plan yet.
DO $$
DECLARE v_id uuid; v_n int; v_push int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Dinner at Buka","all_day":false,"tz":"Africa/Accra","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"starts_at":"2026-11-06T19:00:00Z","ends_at":"2026-11-06T21:00:00Z"},{"starts_at":"2026-11-07T19:00:00Z","ends_at":"2026-11-07T21:00:00Z"}]'::jsonb);
  INSERT INTO t_ids VALUES ('dinner', v_id);
  SELECT count(*) INTO v_n FROM public.list_together_items('7d000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30') WHERE item_id = v_id;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an unanswered proposal is listed as a plan'; END IF;
  SELECT count(*) INTO v_push FROM public.scheduled_notifications
  WHERE user_id = '7c000000-0000-0000-0000-0000000000b2' AND metadata->>'type' = 'together_proposal' AND metadata->>'event_id' = v_id::text;
  IF v_push <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: proposal push count %', v_push; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'sent_proposal' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender does not see their waiting proposal'; END IF;
END $$;

-- 2. Only Kofi can decide; Ama can't; accepting option 2 sets Saturday's times and lists it.
DO $$
DECLARE v_msg text; v_opt uuid; v_start timestamptz; v_status text; v_n int; v_reply int;
BEGIN
  SELECT id INTO v_opt FROM public.couple_event_options WHERE event_id = (SELECT id FROM t_ids WHERE name='dinner') AND position = 2;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the proposer decided their own proposal';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001')
  WHERE need_kind = 'proposal' AND jsonb_array_length(detail->'options') = 2;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: recipient does not see the proposal with 2 options'; END IF;
  PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
  SELECT starts_at, status INTO v_start, v_status FROM public.couple_events WHERE id = (SELECT id FROM t_ids WHERE name='dinner');
  IF v_start <> '2026-11-07T19:00:00Z'::timestamptz OR v_status <> 'confirmed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: accept gave % %', v_start, v_status;
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7d000000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30')
  WHERE item_id = (SELECT id FROM t_ids WHERE name='dinner') AND item_date = '2026-11-07';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: accepted proposal not listed on Saturday'; END IF;
  SELECT count(*) INTO v_reply FROM public.scheduled_notifications
  WHERE user_id = '7c000000-0000-0000-0000-0000000000a1' AND metadata->>'type' = 'together_proposal_reply';
  IF v_reply <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: proposer reply push count %', v_reply; END IF;
  BEGIN
    PERFORM public.decide_couple_event((SELECT id FROM t_ids WHERE name='dinner'), v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: decided twice';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
END $$;

-- 3. Declining with a note cancels it; an expired proposal can't be decided and is hidden.
DO $$
DECLARE v_id uuid; v_opt uuid; v_status text; v_note text; v_msg text; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Hike","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-14"}]'::jsonb);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Working that day');
  SELECT status, decision_note INTO v_status, v_note FROM public.couple_events WHERE id = v_id;
  IF v_status <> 'cancelled' OR v_note <> 'Working that day' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: decline gave % %', v_status, v_note; END IF;

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Brunch","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-15"}]'::jsonb);
  UPDATE public.couple_events SET proposal_expires_at = now() - interval '1 minute' WHERE id = v_id;
  SELECT id INTO v_opt FROM public.couple_event_options WHERE event_id = v_id;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE item_id = v_id;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an expired proposal still needs you'; END IF;
  BEGIN
    PERFORM public.decide_couple_event(v_id, v_opt, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired proposal accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:expired' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
END $$;

-- 4. Proposals must include the partner, be shared, not repeat, and carry 1–3 options.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Solo","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'::jsonb,
      '[{"start_date":"2026-11-14"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: proposal without the partner accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Too many","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
      '[{"start_date":"2026-11-14"},{"start_date":"2026-11-15"},{"start_date":"2026-11-16"},{"start_date":"2026-11-17"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: four options accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  BEGIN
    PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
      '{"title":"Weekly","all_day":true,"rrule":"FREQ=WEEKLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
      '[{"start_date":"2026-11-14"}]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: repeating proposal accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
END $$;

-- 5. Hand-off: Ama asks Kofi to own a shared event; he accepts and owns it.
DO $$
DECLARE v_id uuid; v_owner uuid; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.create_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Book the plumber","all_day":true,"start_date":"2026-11-10","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_id);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'handoff' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off not waiting on Kofi'; END IF;
  PERFORM public.decide_owner_handoff(v_id, true);
  SELECT owner_id INTO v_owner FROM public.couple_events WHERE id = v_id;
  IF v_owner <> '7c000000-0000-0000-0000-0000000000b2' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: owner after accept %', v_owner; END IF;
END $$;

-- 6. Needs you: unowned to-dos due this week and polls awaiting my vote; no counts.
DO $$
DECLARE v_cat uuid; v_entry uuid; v_block uuid; v_poll uuid; v_opt uuid; v_n int; v_result text;
BEGIN
  -- Planning rows carry client-made ids, a category and sort keys
  -- (20261012200000; sync audit K-8).
  INSERT INTO public.planning_categories (id, relationship_id, name, icon, color, sort_key)
  VALUES (gen_random_uuid(), '7d000000-0000-0000-0000-000000000001', 'Holidays', 'sun', '#996633', 'a') RETURNING id INTO v_cat;
  INSERT INTO public.planning_entries (id, relationship_id, category_id, title)
  VALUES (gen_random_uuid(), '7d000000-0000-0000-0000-000000000001', v_cat, 'Summer') RETURNING id INTO v_entry;
  INSERT INTO public.planning_blocks (id, entry_id, relationship_id, block_type, sort_key)
  VALUES (gen_random_uuid(), v_entry, '7d000000-0000-0000-0000-000000000001', 'checklist', 'a') RETURNING id INTO v_block;
  INSERT INTO public.planning_block_items (id, block_id, relationship_id, sort_key, text, due_date) VALUES
    (gen_random_uuid(), v_block, '7d000000-0000-0000-0000-000000000001', 'a', 'Book summer camp', current_date + 3),
    (gen_random_uuid(), v_block, '7d000000-0000-0000-0000-000000000001', 'b', 'Far off', current_date + 30);
  INSERT INTO public.planning_blocks (id, entry_id, relationship_id, block_type, sort_key)
  VALUES (gen_random_uuid(), v_entry, '7d000000-0000-0000-0000-000000000001', 'date_poll', 'b') RETURNING id INTO v_poll;
  INSERT INTO public.planning_block_items (id, block_id, relationship_id, sort_key, text)
  VALUES (gen_random_uuid(), v_poll, '7d000000-0000-0000-0000-000000000001', 'a', 'Option') RETURNING id INTO v_opt;

  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001')
  WHERE (need_kind = 'unowned_todo' AND title = 'Book summer camp') OR (need_kind = 'poll' AND detail->>'entry_id' = v_entry::text);
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: unowned to-do/poll needs %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE title = 'Far off';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a to-do a month out needs you'; END IF;

  INSERT INTO public.planning_poll_votes (item_id, relationship_id, user_id) VALUES (v_opt, '7d000000-0000-0000-0000-000000000001', '7c000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') WHERE need_kind = 'poll';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a poll I voted on still needs me'; END IF;

  SELECT pg_get_function_result('public.list_together_needs_you(uuid)'::regprocedure) INTO v_result;
  IF v_result ~* '(count|total|tally|score)' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: needs-you returns an aggregate: %', v_result; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 7. Review fixes. A sent proposal can't be edited by anyone; only its
--    creator can withdraw it; a pending hand-off isn't re-pushed, and leaving
--    or going private clears it; a decline note reaches the asker; needs
--    come back in a stable order.
DO $$
DECLARE v_id uuid; v_ev uuid; v_msg text; v_n int; v_pending uuid; v_body text; v_first text;
BEGIN
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Picnic","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-21"}]'::jsonb);
  BEGIN
    PERFORM public.update_couple_event(v_id,
      '{"title":"Picnic","all_day":true,"start_date":"2026-11-21","rrule":"FREQ=WEEKLY","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sent proposal was edited';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  BEGIN
    PERFORM public.delete_couple_event(v_id);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient deleted a proposal';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  PERFORM public.delete_couple_event(v_id);

  -- decline note reaches the asker in the reply push
  v_id := public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Gallery","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-22"}]'::jsonb);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  -- Spec 1b (ruling R-D): the note reaches the asker only with previews on.
  INSERT INTO public.notification_settings (user_id, chat_message_preview_enabled)
  VALUES ('7c000000-0000-0000-0000-0000000000a1', true)
  ON CONFLICT (user_id) DO UPDATE SET chat_message_preview_enabled = true;
  PERFORM public.decide_couple_event(v_id, NULL, false, 'Sunday instead?');
  SELECT metadata->>'body' INTO v_body FROM public.scheduled_notifications
  WHERE source_key = 'together_reply:' || v_id;
  IF v_body IS DISTINCT FROM 'Sunday instead?' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: decline note missing from reply: %', v_body; END IF;

  -- hand-off: no second push while pending; leaving clears it
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_ev := public.create_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Dentist","all_day":true,"start_date":"2026-11-12","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_ev);
  PERFORM public.propose_owner_handoff(v_ev);
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE metadata->>'type' = 'together_handoff' AND metadata->>'event_id' = v_ev::text;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off pushed % times while pending', v_n; END IF;
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  PERFORM public.leave_couple_event(v_ev);
  SELECT owner_proposed_to INTO v_pending FROM public.couple_events WHERE id = v_ev;
  IF v_pending IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off outlived leaving'; END IF;

  -- going private clears a pending hand-off
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000a1');
  v_ev := public.create_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Gift","all_day":true,"start_date":"2026-11-13","participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb);
  PERFORM public.propose_owner_handoff(v_ev);
  PERFORM public.update_couple_event(v_ev,
    '{"title":"Gift","all_day":true,"start_date":"2026-11-13","visibility":"private","participant_ids":["7c000000-0000-0000-0000-0000000000a1"]}'::jsonb);
  SELECT owner_proposed_to INTO v_pending FROM public.couple_events WHERE id = v_ev;
  IF v_pending IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hand-off survived going private'; END IF;

  -- stable order: proposals to me come before to-dos
  PERFORM public.propose_couple_event('7d000000-0000-0000-0000-000000000001',
    '{"title":"Concert","all_day":true,"participant_ids":["7c000000-0000-0000-0000-0000000000a1","7c000000-0000-0000-0000-0000000000b2"]}'::jsonb,
    '[{"start_date":"2026-11-28"}]'::jsonb);
  PERFORM pg_temp.as_user('7c000000-0000-0000-0000-0000000000b2');
  SELECT need_kind INTO v_first FROM public.list_together_needs_you('7d000000-0000-0000-0000-000000000001') LIMIT 1;
  IF v_first <> 'proposal' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: needs not ordered (first %)', v_first; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
