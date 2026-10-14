-- Together Phase 5 contracts: the calendar feed. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f500000-0000-0000-0000-0000000000a1'), ('7f500000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f500000-0000-0000-0000-0000000000a1', '+233320000001', 'Ama'),
  ('7f500000-0000-0000-0000-0000000000b2', '+233320000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1',
        '7f500000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_tok (name text PRIMARY KEY, token text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.h(t text) RETURNS text LANGUAGE sql AS $$
  SELECT encode(sha256(convert_to(t, 'UTF8')), 'hex') $$;

-- Fixtures: Ama's shared dinner; Kofi's busy-only and private events; Ama's
-- proposal; a yearly reminder; a moment. All on 2026-11-07.
INSERT INTO public.couple_events (relationship_id, created_by, title, note, all_day, starts_at, ends_at, tz, participant_ids)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'Dinner, at Buka', 'Bring cash', false,
        '2026-11-07T18:00:00Z', '2026-11-07T20:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000a1','7f500000-0000-0000-0000-0000000000b2']::uuid[]);
INSERT INTO public.couple_events (relationship_id, created_by, title, note, all_day, starts_at, ends_at, tz, participant_ids, visibility)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000b2', 'Therapy', 'Room 4', false,
        '2026-11-07T09:00:00Z', '2026-11-07T10:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000b2']::uuid[], 'busy_only'),
       ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000b2', 'Ring shopping', NULL, false,
        '2026-11-07T11:00:00Z', '2026-11-07T12:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000b2']::uuid[], 'private');
INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids, status, proposed_to, proposal_expires_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'Beach?', true, '2026-11-08',
        ARRAY['7f500000-0000-0000-0000-0000000000a1','7f500000-0000-0000-0000-0000000000b2']::uuid[],
        'proposed', '7f500000-0000-0000-0000-0000000000b2', now() + interval '7 days');
INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'birthday', 'Kofi''s birthday',
        '2020-11-09T00:00:00Z', 'yearly');
INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'highlight', 'Moment', '2026-11-07');

-- 1. A token is shown once and stored hashed; a new one replaces the old.
DO $$
DECLARE v_t1 text; v_t2 text; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  v_t1 := public.create_calendar_feed_token();
  IF v_t1 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: token shape %', v_t1; END IF;
  SELECT count(*) INTO v_n FROM public.calendar_feed_tokens WHERE token_hash = pg_temp.h(v_t1) AND revoked_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: token not stored as its hash'; END IF;
  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens WHERE token_hash = v_t1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: plaintext token stored';
  END IF;
  v_t2 := public.create_calendar_feed_token();
  IF public.together_calendar_feed(pg_temp.h(v_t1), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the replaced link still works';
  END IF;
  IF NOT (SELECT is_active FROM public.get_calendar_feed_status()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: status not active';
  END IF;
  INSERT INTO t_tok VALUES ('ama', v_t2);
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000b2');
  INSERT INTO t_tok VALUES ('kofi', public.create_calendar_feed_token());
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Ama's feed: her dinner (with details), Kofi's busy block as "Busy" only,
--    never his private event, no proposal, the birthday, no moment.
DO $$
DECLARE v jsonb; v_titles text[]; v_busy jsonb;
BEGIN
  v := public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01');
  SELECT array_agg(i->>'title' ORDER BY i->>'title') INTO v_titles FROM jsonb_array_elements(v->'items') i;
  IF v_titles IS DISTINCT FROM ARRAY['Busy', 'Dinner, at Buka', 'Kofi''s birthday'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s feed has %', v_titles;
  END IF;
  SELECT i INTO v_busy FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Busy';
  IF v_busy->>'note' IS NOT NULL OR v_busy->>'location' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy block leaks details %', v_busy;
  END IF;
  IF (SELECT i->>'note' FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Dinner, at Buka') <> 'Bring cash' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dinner lost its note';
  END IF;
  -- Kofi sees his own private and busy events in full.
  v := public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'kofi')), '2026-11-01');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Ring shopping')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Therapy' AND i->>'note' = 'Room 4') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kofi''s own events missing from his feed';
  END IF;
  IF public.together_calendar_feed(pg_temp.h('0000000000000000000000000000000000000000000000000000000000000000'), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown token served a feed';
  END IF;
END $$;

-- 3. Only the service role reads feeds; the app's read keeps its cap.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.together_calendar_feed('x');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user called the feed RPC';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.together_items_for('7f500000-0000-0000-0000-0000000000b2', '7f600000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user read as someone else';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.list_together_items('7f600000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 93-day cap is gone';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:range' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Turning it off, and ending the relationship, stop links at once.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000b2');
  PERFORM public.revoke_calendar_feed();
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'kofi')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revoked link still works';
  END IF;
  IF (SELECT is_active FROM public.get_calendar_feed_status()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: status still active after turning off';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  UPDATE public.relationships SET status = 'ended', chat_archived_at = now()
  WHERE id = '7f600000-0000-0000-0000-000000000001';
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a link outlived the relationship';
  END IF;
  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens
             WHERE user_id = '7f500000-0000-0000-0000-0000000000a1' AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ending the relationship did not revoke the link';
  END IF;
END $$;

-- 5. Re-pairing doesn't revive an old link; a fresh one serves the new couple.
DO $$
DECLARE v_new text;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7f600000-0000-0000-0000-000000000002', '7f500000-0000-0000-0000-0000000000a1',
          '7f500000-0000-0000-0000-0000000000b2', 'active', now(), now());
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an old link came back with the new couple';
  END IF;
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  v_new := public.create_calendar_feed_token();
  PERFORM set_config('request.jwt.claims', '', true);
  IF public.together_calendar_feed(pg_temp.h(v_new), '2026-11-01') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh link does not serve the new couple';
  END IF;
END $$;

ROLLBACK;
