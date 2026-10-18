-- supabase/tests/share_a_win_contracts.sql
-- Spec 7 (research 06 B2; plan review C2, I8, M1, M6): a win is a shared
-- highlight that never pushes; the partner gets an in-app card for 3 days
-- until they tap or dismiss it; a client cannot mark anything a win.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9fd00000-0000-0000-0000-0000000000a1'), ('9fd00000-0000-0000-0000-0000000000b2'),
  ('9fd00000-0000-0000-0000-0000000000c3'), ('9fd00000-0000-0000-0000-0000000000d4'),
  ('9fd00000-0000-0000-0000-0000000000e5')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('9fd00000-0000-0000-0000-0000000000a1', '+233599620001', 'Ama', 'Africa/Accra'),
  ('9fd00000-0000-0000-0000-0000000000b2', '+233599620002', 'Kofi', 'Africa/Accra'),
  ('9fd00000-0000-0000-0000-0000000000c3', '+233599620003', 'Stranger', NULL),
  ('9fd00000-0000-0000-0000-0000000000d4', '+233599620004', 'Pat', NULL),
  ('9fd00000-0000-0000-0000-0000000000e5', '+233599620005', 'Pip', NULL)
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9fd10000-0000-0000-0000-000000000001', '9fd00000-0000-0000-0000-0000000000a1', '9fd00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9fd10000-0000-0000-0000-000000000002', '9fd00000-0000-0000-0000-0000000000d4', '9fd00000-0000-0000-0000-0000000000e5', 'paused', CURRENT_DATE - 50, now() - interval '50 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.refused(p_user uuid, p_sql text, p_code text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: accepted: %', p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg LIKE 'CONTRACT VIOLATED%' OR v_msg <> p_code THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % gave "%" (want %)', p_sql, v_msg, p_code;
    END IF;
  END;
END $$;

DO $$
DECLARE
  v_rel uuid := '9fd10000-0000-0000-0000-000000000001';
  v_a uuid := '9fd00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fd00000-0000-0000-0000-0000000000b2';
  v_c uuid := '9fd00000-0000-0000-0000-0000000000c3';
  v_d uuid := '9fd00000-0000-0000-0000-0000000000d4';
  v_win uuid; v_plain uuid; v_forged uuid; r record; v_n int; v_fn text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'share_a_win') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: share_a_win not seeded off';
  END IF;
  -- The server refuses while the flag is off (sync_fixes_contracts); on
  -- for the rest of this file.
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('share_a_win');
  FOREACH v_fn IN ARRAY ARRAY['public.share_a_win(uuid,text,text,date)', 'public.list_win_cards(uuid)',
                              'public.dismiss_win_card(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: grants on %', v_fn;
    END IF;
  END LOOP;
  IF has_table_privilege('authenticated', 'public.win_card_dismissals', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients read dismissals directly';
  END IF;

  -- 1. A shared highlight, on the sharer's local day, with no push.
  PERFORM pg_temp.as_user(v_a);
  v_win := public.share_a_win(v_rel, 'Got the grant!', 'Three years of work');
  RESET ROLE;
  SELECT * INTO r FROM public.timeline_events WHERE id = v_win;
  IF r.event_type <> 'highlight' OR r.visibility <> 'shared' OR NOT r.is_win OR r.logged_by <> v_a
     OR r.occurred_at <> (now() AT TIME ZONE 'Africa/Accra')::date OR r.note <> 'Three years of work' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stored win: %', row_to_json(r);
  END IF;
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE source_key LIKE 'moment:' || v_win || '%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a win sent a push';
  END IF;
  -- An ordinary moment still tells the partner (regression).
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES (v_rel, v_a, 'highlight', 'Dinner out', CURRENT_DATE) RETURNING id INTO v_plain;
  IF NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE source_key LIKE 'moment:' || v_plain || '%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary moment stopped telling the partner';
  END IF;
  -- M1: nothing but share_a_win makes a win.
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, is_win)
  VALUES (v_rel, v_a, 'highlight', 'Forged', CURRENT_DATE, true) RETURNING id INTO v_forged;
  IF (SELECT is_win FROM public.timeline_events WHERE id = v_forged) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct insert marked a win';
  END IF;
  UPDATE public.timeline_events SET is_win = true WHERE id = v_plain;
  IF (SELECT is_win FROM public.timeline_events WHERE id = v_plain) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct update marked a win';
  END IF;

  -- 2. Refused input.
  PERFORM pg_temp.refused(v_a, format('SELECT public.share_a_win(%L, %L)', v_rel, '   '), 'win:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.share_a_win(%L, %L)', v_rel, repeat('x', 81)), 'win:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.share_a_win(%L, %L, %L)', v_rel, 'Win', repeat('x', 301)), 'win:invalid');
  PERFORM pg_temp.refused(v_a, format('SELECT public.share_a_win(%L, %L, NULL, %L)', v_rel, 'Win', CURRENT_DATE - 5), 'win:invalid');
  PERFORM pg_temp.refused(v_c, format('SELECT public.share_a_win(%L, %L)', v_rel, 'Win'), 'win:not_allowed');
  PERFORM pg_temp.refused(v_d, format('SELECT public.share_a_win(%L, %L)', '9fd10000-0000-0000-0000-000000000002', 'Win'), 'win:not_allowed');

  -- 3. The partner's card: theirs only, until dismissed, for 3 days.
  PERFORM pg_temp.as_user(v_b);
  SELECT * INTO r FROM public.list_win_cards(v_rel);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_rel);
  RESET ROLE;
  IF v_n <> 1 OR r.event_id <> v_win OR r.title <> 'Got the grant!' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner''s card: % %', v_n, row_to_json(r);
  END IF;
  PERFORM pg_temp.as_user(v_a);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_rel);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the sharer is asked about their own win'; END IF;
  PERFORM pg_temp.refused(v_c, format('SELECT public.list_win_cards(%L)', v_rel), 'together:not_found');
  PERFORM pg_temp.refused(v_c, format('SELECT public.dismiss_win_card(%L)', v_win), 'together:not_found');
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.dismiss_win_card(v_win);
  PERFORM public.dismiss_win_card(v_win);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_rel);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a dismissed card came back'; END IF;
  PERFORM pg_temp.as_user(v_a);
  v_win := public.share_a_win(v_rel, 'Second win');
  RESET ROLE;
  UPDATE public.timeline_events SET created_at = now() - interval '4 days' WHERE id = v_win;
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.list_win_cards(v_rel);
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a card outlived 3 days'; END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'share_a_win_contracts: all held'; END $$;
ROLLBACK;
