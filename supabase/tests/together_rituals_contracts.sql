-- Together Phase 3 contracts: rituals.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f100000-0000-0000-0000-0000000000a1'), ('7f100000-0000-0000-0000-0000000000b2'), ('7f100000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f100000-0000-0000-0000-0000000000a1', '+233300000001', 'Ama'),
  ('7f100000-0000-0000-0000-0000000000b2', '+233300000002', 'Kofi'),
  ('7f100000-0000-0000-0000-0000000000c3', '+233300000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f200000-0000-0000-0000-000000000001', '7f100000-0000-0000-0000-0000000000a1',
        '7f100000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.occ(p_ritual uuid) RETURNS date[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(ritual_date ORDER BY ritual_date), '{}') FROM public.couple_events
  WHERE ritual_id = p_ritual AND deleted_at IS NULL AND status = 'confirmed' $$;

-- 0. No counters, ever (spec §3.2).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'couple_rituals'
               AND column_name ~* '(streak|count|total|score|missed|tally)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_rituals has a counter column';
  END IF;
END $$;

-- 1. Ama proposes a Friday date night; Kofi sees it in Needs you, gets one push, accepts;
--    the next two Fridays appear at 19:00 Accra (UTC).
DO $$
DECLARE v_id uuid; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"date_night","title":"Date night","cadence":"weekly","weekday":5,"local_time":"19:00","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  INSERT INTO t_ids VALUES ('date', v_id);
  IF EXISTS (SELECT 1 FROM public.couple_events WHERE ritual_id = v_id) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: occurrences before the ritual is agreed';
  END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
  WHERE user_id = '7f100000-0000-0000-0000-0000000000b2' AND metadata->>'type' = 'together_ritual';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual proposal pushes %', v_n; END IF;

  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7f200000-0000-0000-0000-000000000001')
  WHERE need_kind = 'ritual_proposal' AND item_id = v_id;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual proposal not in Needs you'; END IF;
  PERFORM public.decide_ritual(v_id, true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

DO $$
DECLARE v_dates date[]; v_start timestamptz;
BEGIN
  PERFORM public.together_ensure_ritual_occurrences('2026-11-02T03:15:00Z');
  v_dates := pg_temp.occ((SELECT id FROM t_ids WHERE name='date'));
  IF NOT (v_dates @> ARRAY['2026-11-06','2026-11-13']::date[]) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: occurrences %', v_dates;
  END IF;
  SELECT starts_at INTO v_start FROM public.couple_events
  WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-06';
  IF v_start <> '2026-11-06T19:00:00Z'::timestamptz THEN RAISE EXCEPTION 'CONTRACT VIOLATED: start %', v_start; END IF;
  -- idempotent
  PERFORM public.together_ensure_ritual_occurrences('2026-11-02T03:15:00Z');
  IF (SELECT count(*) FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date')
      AND ritual_date = '2026-11-06' AND deleted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: duplicate occurrence';
  END IF;
END $$;

-- 2. Skipping a week sticks; moving one week keeps it a ritual occurrence.
DO $$
DECLARE v_ev uuid; v_kind text; v_rid uuid;
BEGIN
  SELECT id INTO v_ev FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-06';
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  PERFORM public.skip_ritual_occurrence(v_ev);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_ensure_ritual_occurrences('2026-11-03T03:15:00Z');
  IF '2026-11-06'::date = ANY (pg_temp.occ((SELECT id FROM t_ids WHERE name='date'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skipped week came back';
  END IF;

  SELECT id INTO v_ev FROM public.couple_events WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND ritual_date = '2026-11-13';
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  PERFORM public.update_couple_event(v_ev,
    '{"title":"Date night","kind":"event","all_day":false,"starts_at":"2026-11-13T20:00:00Z","ends_at":"2026-11-13T22:00:00Z","tz":"Africa/Accra","participant_ids":["7f100000-0000-0000-0000-0000000000a1","7f100000-0000-0000-0000-0000000000b2"]}'::jsonb);
  SELECT kind, ritual_id INTO v_kind, v_rid FROM public.couple_events WHERE id = v_ev;
  IF v_kind <> 'ritual_occurrence' OR v_rid IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: moved week became % / %', v_kind, v_rid; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Pause removes future weeks; resume brings them back; retiming moves them.
DO $$
DECLARE v_dates date[]; v_start timestamptz;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_ritual_status((SELECT id FROM t_ids WHERE name='date'), 'paused');
  v_dates := pg_temp.occ((SELECT id FROM t_ids WHERE name='date'));
  IF EXISTS (SELECT 1 FROM unnest(v_dates) d WHERE d >= current_date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused ritual kept future weeks %', v_dates;
  END IF;
  PERFORM public.set_ritual_status((SELECT id FROM t_ids WHERE name='date'), 'active');
  PERFORM public.update_ritual((SELECT id FROM t_ids WHERE name='date'),
    '{"title":"Date night","cadence":"weekly","weekday":6,"local_time":"18:30","duration_min":120,"tz":"Africa/Accra"}'::jsonb);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_ensure_ritual_occurrences(now());
  SELECT starts_at INTO v_start FROM public.couple_events
  WHERE ritual_id = (SELECT id FROM t_ids WHERE name='date') AND deleted_at IS NULL AND status = 'confirmed'
    AND ritual_date >= current_date ORDER BY ritual_date LIMIT 1;
  IF v_start IS NULL OR extract(isodow FROM v_start AT TIME ZONE 'Africa/Accra') <> 6
     OR to_char(v_start AT TIME ZONE 'Africa/Accra', 'HH24:MI') <> '18:30' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retimed occurrence %', v_start;
  END IF;
END $$;

-- 4. Listing, permissions, decline.
DO $$
DECLARE v_n int; v_msg text; v_id uuid; v_status text;
BEGIN
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_rituals('7f200000-0000-0000-0000-000000000001') WHERE status = 'active' AND next_starts_at IS NOT NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: active ritual with next occurrence not listed'; END IF;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.list_together_rituals('7f200000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger listed rituals';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: wrong error %', v_msg; END IF;
  END;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"state_of_union","title":"State of the Union","cadence":"weekly","weekday":7,"local_time":"18:00","duration_min":60,"tz":"Africa/Accra"}'::jsonb);
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.decide_ritual(v_id, false);
  SELECT status INTO v_status FROM public.couple_rituals WHERE id = v_id;
  IF v_status <> 'ended' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: declined ritual status %', v_status; END IF;
  BEGIN
    PERFORM public.propose_ritual('7f200000-0000-0000-0000-000000000001',
      '{"title":"Bad","cadence":"daily","weekday":5,"local_time":"19:00","duration_min":60,"tz":"Africa/Accra"}'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: daily cadence accepted';
  EXCEPTION WHEN raise_exception THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. Review fixes: zone-correct times across DST, deleting a week sticks,
--    retiming keeps the fortnight's phase, anchor uses the ritual's own day,
--    and a proposer can withdraw.
DO $$
DECLARE v_id uuid; v_ev uuid; v_local text; v_status text; v_anchor date; v_n int;
BEGIN
  -- A Toronto Sunday 19:00 ritual, either side of the 1 Nov 2026 DST change.
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"weekly_call","title":"Weekly call","cadence":"weekly","weekday":7,"local_time":"19:00","duration_min":60,"tz":"America/Toronto"}'::jsonb);
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  -- the server's own zone must not decide the ritual's first day (#4)
  SET LOCAL timezone = 'Pacific/Kiritimati';
  PERFORM public.decide_ritual(v_id, true);
  SELECT anchor_date INTO v_anchor FROM public.couple_rituals WHERE id = v_id;
  IF v_anchor <> (now() AT TIME ZONE 'America/Toronto')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anchor % is not the ritual''s local day', v_anchor;
  END IF;
  SET LOCAL timezone = 'UTC';
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.couple_rituals SET anchor_date = '2026-10-01' WHERE id = v_id;
  UPDATE public.couple_events SET deleted_at = now() WHERE ritual_id = v_id;
  PERFORM public.together_ensure_ritual_occurrences('2026-10-20T12:00:00Z', v_id);
  FOR v_local IN
    SELECT to_char(starts_at AT TIME ZONE 'America/Toronto', 'YYYY-MM-DD HH24:MI') FROM public.couple_events
    WHERE ritual_id = v_id AND deleted_at IS NULL ORDER BY starts_at
  LOOP
    IF v_local NOT IN ('2026-10-25 19:00', '2026-11-01 19:00') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: Toronto occurrence at % local', v_local;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.couple_events WHERE ritual_id = v_id AND deleted_at IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 2 Toronto occurrences';
  END IF;

  -- Deleting one week from the event sheet must not let the cron bring it back (#2).
  SELECT id INTO v_ev FROM public.couple_events WHERE ritual_id = v_id AND ritual_date = '2026-11-01' AND deleted_at IS NULL;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.delete_couple_event(v_ev);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public.together_ensure_ritual_occurrences('2026-10-20T12:00:00Z', v_id);
  IF '2026-11-01'::date = ANY (pg_temp.occ(v_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted ritual week came back';
  END IF;

  -- Retiming a fortnightly ritual keeps its phase; changing cadence re-anchors (#3).
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.update_ritual(v_id,
    '{"title":"Weekly call","cadence":"fortnightly","weekday":7,"local_time":"19:00","duration_min":60,"tz":"America/Toronto"}'::jsonb);
  UPDATE public.couple_rituals SET anchor_date = '2026-10-05' WHERE id = v_id;
  PERFORM public.update_ritual(v_id,
    '{"title":"Weekly call","cadence":"fortnightly","weekday":3,"local_time":"20:30","duration_min":60,"tz":"America/Toronto"}'::jsonb);
  SELECT anchor_date INTO v_anchor FROM public.couple_rituals WHERE id = v_id;
  IF v_anchor <> '2026-10-05' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: retime moved the fortnight anchor to %', v_anchor; END IF;

  -- The proposer can withdraw a suggestion that hasn't been answered (#5).
  v_id := public.propose_ritual('7f200000-0000-0000-0000-000000000001',
    '{"template":"custom","title":"Walk","cadence":"weekly","weekday":6,"local_time":"08:00","duration_min":60,"tz":"Africa/Accra"}'::jsonb);
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  BEGIN
    PERFORM public.set_ritual_status(v_id, 'ended');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner ended a suggestion meant for them';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT%' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_ritual_status(v_id, 'ended');
  SELECT status INTO v_status FROM public.couple_rituals WHERE id = v_id;
  IF v_status <> 'ended' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawn suggestion is %', v_status; END IF;
  PERFORM pg_temp.as_user('7f100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_needs_you('7f200000-0000-0000-0000-000000000001')
  WHERE item_id = v_id;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawn suggestion still in Needs you'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
