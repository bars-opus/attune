-- supabase/tests/put_away_gently_contracts.sql
-- Spec 7 (research 06 B9 (c); plan review I2): "Put this away gently"
-- archives a plan without a sound: its pending countdown pushes are
-- cancelled, it leaves Recent and the shared calendar, and its activity
-- time is untouched (nothing announces it).
BEGIN;
DO $$
DECLARE
  v_rel uuid := '9fe00000-0000-0000-0000-000000000001';
  v_a uuid := '9fe00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fe00000-0000-0000-0000-0000000000b2';
  v_x uuid := '9fe00000-0000-0000-0000-0000000000c3';
  v_trips uuid; v_entry uuid := '9fe00000-0000-0000-0000-00000000e001';
  v_other uuid := '9fe00000-0000-0000-0000-00000000e002';
  v_date uuid := '9fe00000-0000-0000-0000-00000000b001';
  v_n int; v_before timestamptz; v_recent jsonb; v_failed boolean := false;
BEGIN
  INSERT INTO auth.users (id) VALUES (v_a), (v_b), (v_x) ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a, '+233599630001', 'Ama'), (v_b, '+233599630002', 'Kofi'), (v_x, '+233599630003', 'X') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_trips FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  PERFORM public.create_planning_entry(v_entry, v_trips, 'Baby shower', false, 'GHS');
  PERFORM public.create_planning_entry(v_other, v_trips, 'Bali', false, 'GHS');
  PERFORM public.add_planning_block(v_date, v_entry, 'date', '{}', DATE '2026-11-20', NULL, NULL);
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_a, 'immediate', now() + interval '1 day', 'pending',
          jsonb_build_object('type', 'planning_entry', 'entry_id', v_entry), 'planning_countdown:x1:' || v_a || ':2026-11-19'),
         (v_b, 'immediate', now() + interval '1 day', 'pending',
          jsonb_build_object('type', 'planning_entry', 'entry_id', v_entry), 'planning_countdown:x1:' || v_b || ':2026-11-19'),
         (v_a, 'immediate', now() + interval '1 day', 'pending',
          jsonb_build_object('type', 'planning_entry', 'entry_id', v_other), 'planning_countdown:x2:' || v_a || ':2026-11-19');
  SELECT last_activity_at INTO v_before FROM public.planning_entries WHERE id = v_entry;

  -- A stranger cannot.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_x), true);
  BEGIN
    PERFORM public.put_planning_entry_away(v_entry);
  EXCEPTION WHEN OTHERS THEN v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger put a plan away'; END IF;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', v_b), true);
  PERFORM public.put_planning_entry_away(v_entry);
  IF (SELECT status FROM public.planning_entries WHERE id = v_entry) <> 'archived' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not archived';
  END IF;
  IF (SELECT last_activity_at FROM public.planning_entries WHERE id = v_entry) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: putting away counted as activity';
  END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE metadata->>'entry_id' = v_entry::text AND status = 'pending';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % countdown pushes still pending', v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.scheduled_notifications
                 WHERE metadata->>'entry_id' = v_other::text AND status = 'pending') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another plan''s push was cancelled';
  END IF;
  v_recent := public.list_planning_recent(v_rel, NULL, NULL, 20);
  IF v_recent::text LIKE '%' || v_entry || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a put-away plan is still in Recent';
  END IF;
  IF v_recent::text NOT LIKE '%' || v_other || '%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setup: the other plan is missing from Recent: %', v_recent;
  END IF;
  SELECT count(*) INTO v_n FROM public.together_items_for(v_b, v_rel, DATE '2026-11-01', DATE '2026-11-30')
  WHERE item_kind LIKE 'planning%' AND (source_ref->>'entry_id') = v_entry::text;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a put-away plan is still on the calendar'; END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'put_away_gently_contracts: all held'; END $$;
ROLLBACK;
