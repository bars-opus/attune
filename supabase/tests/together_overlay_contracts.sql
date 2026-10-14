-- Together Phase 6 contracts: busy overlay + finder. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f700000-0000-0000-0000-0000000000a1'), ('7f700000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f700000-0000-0000-0000-0000000000a1', '+233330000001', 'Ana'),
  ('7f700000-0000-0000-0000-0000000000b2', '+233330000002', 'Luca') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1',
        '7f700000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
-- Ana is in London, Luca in Toronto (5 hours behind in November).
INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone) VALUES
  ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'Europe/London'),
  ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', 'America/Toronto');
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.windows(p_now timestamptz, p_day date) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(to_char(starts_at AT TIME ZONE 'UTC', 'HH24:MI') || '-' || to_char(ends_at AT TIME ZONE 'UTC', 'HH24:MI'), ',' ORDER BY starts_at), '')
  FROM public.list_together_free_windows('7f800000-0000-0000-0000-000000000001', p_now)
  WHERE (starts_at AT TIME ZONE 'UTC')::date = p_day $$;

-- 0. Busy-only by construction: the table has no room for details.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'couple_busy_blocks'
             AND column_name NOT IN ('id', 'relationship_id', 'user_id', 'starts_at', 'ends_at', 'uploaded_at')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_busy_blocks can hold more than times';
  END IF;
END $$;

-- 1. Off by default; uploading while off is refused; nothing until both opt in.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  IF public.get_together_overlay('7f800000-0000-0000-0000-000000000001')->>'level' <> 'off' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: overlay not off by default';
  END IF;
  BEGIN
    PERFORM public.replace_my_busy_blocks('7f800000-0000-0000-0000-000000000001', '[]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: upload accepted while off';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
  END;
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  IF pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10') <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: windows shown before both opted in';
  END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 1b. Malformed uploads are refused, never stored as a 14-day busy block.
DO $$
DECLARE v_msg text; v_bad jsonb;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  FOREACH v_bad IN ARRAY ARRAY['[{}]'::jsonb, '["x"]'::jsonb, '[{"ends_at":"2026-11-10T10:00:00Z"}]'::jsonb,
                              '[{"starts_at":"2026-11-10T09:00:00Z"}]'::jsonb] LOOP
    BEGIN
      PERFORM public.replace_my_busy_blocks('7f800000-0000-0000-0000-000000000001', v_bad);
      RAISE EXCEPTION 'CONTRACT VIOLATED: malformed upload % accepted', v_bad;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
    END;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE user_id = '7f700000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed upload left rows';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Waking hours in each zone: London 08-22 UTC, Toronto 13-03 UTC → 13:00-22:00.
--    Luca's busy 15:10-15:40 rounds out to 15:00-16:00 and splits the day.
--    An all-day "Pay rent" doesn't block; a trip does.
DO $$
DECLARE v_n int; v text;
BEGIN
  -- Stored as of Nov 10 (the RPC itself always uses the real clock).
  v_n := public.together_store_busy_blocks('7f800000-0000-0000-0000-000000000001',
    '7f700000-0000-0000-0000-0000000000b2',
    '[{"starts_at":"2026-11-10T15:10:00Z","ends_at":"2026-11-10T15:40:00Z"},
      {"starts_at":"2026-12-30T10:00:00Z","ends_at":"2026-12-30T11:00:00Z"}]'::jsonb,
    '2026-11-10T00:00:00Z');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a block beyond 14 days was kept (% stored)', v_n; END IF;
  IF (SELECT count(*) FROM public.couple_busy_blocks
      WHERE user_id = '7f700000-0000-0000-0000-0000000000b2'
        AND starts_at = '2026-11-10T15:00:00Z' AND ends_at = '2026-11-10T16:00:00Z') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy time not rounded outward to 30 minutes';
  END IF;
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'Pay rent', true, '2026-11-10',
          ARRAY['7f700000-0000-0000-0000-0000000000a1','7f700000-0000-0000-0000-0000000000b2']::uuid[]);
  INSERT INTO public.couple_events (relationship_id, created_by, kind, title, all_day, start_date, participant_ids)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'trip', 'Lisbon', true, '2026-11-11',
          ARRAY['7f700000-0000-0000-0000-0000000000a1']::uuid[]);
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Nov 10 windows %', v; END IF;
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-11');
  IF v <> '' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a trip day had windows %', v; END IF;
  -- partner-local times come back for display
  IF (SELECT partner_from || '-' || partner_to FROM public.list_together_free_windows('7f800000-0000-0000-0000-000000000001', '2026-11-10T00:00:00Z')
      ORDER BY starts_at LIMIT 1) <> '08:00-10:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner-local window times wrong';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Across Toronto's clock change (Oct 31 is EDT, UTC-4): overlap is 12:00-22:00 UTC
--    (London is already UTC+0 after Oct 25), an hour earlier than Nov 10's 13:00.
DO $$
DECLARE v text;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-10-31T00:00:00Z', '2026-10-31');
  IF v <> '12:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Oct 31 (EDT) windows %', v; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Private events: Luca's private 18:00-19:00 doesn't shrink Ana's windows,
--    but shrinks his own (spec §3.6).
DO $$
DECLARE v text;
BEGIN
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids, visibility)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', 'Ring shopping', false,
          '2026-11-10T18:00:00Z', '2026-11-10T19:00:00Z', 'America/Toronto',
          ARRAY['7f700000-0000-0000-0000-0000000000b2']::uuid[], 'private');
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner private event leaked into my windows %', v; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-18:00,19:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: my private event ignored %', v; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. Strips: at free_windows nobody sees the other's blocks; at strips the
--    partner (if opted in) sees them; I always see my own.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE NOT is_mine;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner blocks reached me at free_windows'; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'strips');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE is_mine;
  IF v_n < 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: I cannot see my own blocks'; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE NOT is_mine;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: strips level not shared (%)', v_n; END IF;
  -- if Ana turns off, she sees nothing of Luca's either (same rules for both)
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'off');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: strips shown to someone opted out'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Turning off deletes my rows at once; the daily purge removes past blocks;
--    ending the relationship removes everyone's.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  PERFORM public.together_store_busy_blocks('7f800000-0000-0000-0000-000000000001',
    '7f700000-0000-0000-0000-0000000000a1',
    '[{"starts_at":"2026-11-12T09:00:00Z","ends_at":"2026-11-12T10:00:00Z"}]'::jsonb, '2026-11-11T00:00:00Z');
  IF NOT EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE user_id = '7f700000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture block not stored';
  END IF;
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'off');
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE user_id = '7f700000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning off left my busy times on the server';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  INSERT INTO public.couple_busy_blocks (relationship_id, user_id, starts_at, ends_at)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', date_trunc('hour', now()) - interval '3 days', date_trunc('hour', now()) - interval '3 days' + interval '30 minutes');
  PERFORM public.together_purge_busy_blocks();
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE ends_at < now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past blocks survived the purge';
  END IF;

  UPDATE public.relationships SET status = 'ended', chat_archived_at = now()
  WHERE id = '7f800000-0000-0000-0000-000000000001';
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE relationship_id = '7f800000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy times outlived the relationship';
  END IF;
END $$;

ROLLBACK;
