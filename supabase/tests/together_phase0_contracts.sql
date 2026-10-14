-- Together Phase 0 contracts (spec 2026-10-14 §8.1). Self-contained
-- fixtures; every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7a000000-0000-0000-0000-0000000000a1'),
  ('7a000000-0000-0000-0000-0000000000b2'),
  ('7a000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('7a000000-0000-0000-0000-0000000000a1', '+233260000001', 'Ama'),
  ('7a000000-0000-0000-0000-0000000000b2', '+233260000002', 'Kofi'),
  ('7a000000-0000-0000-0000-0000000000c3', '+233260000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7e000000-0000-0000-0000-000000000001',
        '7a000000-0000-0000-0000-0000000000a1',
        '7a000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. Writing a moment or reminder bumps the couple's signal; members can
--    read it, a stranger cannot.
DO $$
DECLARE v_before bigint; v_after bigint; v_seen int;
BEGIN
  SELECT coalesce(max(version), 0) INTO v_before
  FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';

  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'conflict', 'Signal probe', current_date);
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'anniversary', 'Signal probe', now(), 'yearly');

  SELECT version INTO v_after FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_after IS NULL OR v_after < v_before + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: signal not bumped (before %, after %)', v_before, v_after;
  END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000c3', 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_seen FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_seen <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger can read the couple''s signal';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_seen FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_seen <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner cannot read the signal';
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. A non-conflict moment queues exactly one push, for the partner only;
--    a conflict queues none (PULSE.md §10).
DO $$
DECLARE v_id uuid; v_partner int; v_logger int; v_conflict uuid; v_any int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'highlight', 'Beach day', current_date)
  RETURNING id INTO v_id;

  SELECT count(*) INTO v_partner FROM public.scheduled_notifications
  WHERE source_key = 'moment:' || v_id::text || ':7a000000-0000-0000-0000-0000000000b2'
    AND user_id = '7a000000-0000-0000-0000-0000000000b2'
    AND metadata->>'type' = 'moment_logged'
    AND metadata->>'title' = 'Ama added a moment'
    AND metadata->>'body' = 'Beach day';
  IF v_partner <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 1 partner push, got %', v_partner;
  END IF;

  SELECT count(*) INTO v_logger FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_id::text || ':%'
    AND user_id = '7a000000-0000-0000-0000-0000000000a1';
  IF v_logger <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the logger was notified of their own moment';
  END IF;

  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'conflict', 'Argument', current_date)
  RETURNING id INTO v_conflict;
  SELECT count(*) INTO v_any FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_conflict::text || ':%';
  IF v_any <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a conflict moment notified someone';
  END IF;
END $$;

-- 2b. An ended relationship with no partner still saves the moment and
--     queues nothing.
DO $$
DECLARE v_id uuid; v_any int;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7e000000-0000-0000-0000-000000000002',
          '7a000000-0000-0000-0000-0000000000c3', NULL, 'ended', now(), now())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000002',
          '7a000000-0000-0000-0000-0000000000c3', 'first', 'Solo', current_date)
  RETURNING id INTO v_id;
  SELECT count(*) INTO v_any FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_id::text || ':%';
  IF v_any <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pushed with no active partner';
  END IF;
END $$;

-- 3. 'custom' is an accepted reminder type.
DO $$
BEGIN
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'custom', 'Rent day', now(), 'none');
EXCEPTION WHEN check_violation THEN
  RAISE EXCEPTION 'CONTRACT VIOLATED: custom reminder type rejected';
END $$;

-- 4. Verdict eligibility ignores soft-deleted moments.
DO $$
DECLARE v_def text; v_hits int;
BEGIN
  SELECT pg_get_functiondef('public.request_verdict_generation(uuid)'::regprocedure) INTO v_def;
  SELECT count(*) INTO v_hits
  FROM regexp_matches(v_def, 'te\.deleted_at IS NULL', 'g');
  IF v_hits < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verdict eligibility counts deleted moments (% filters)', v_hits;
  END IF;
END $$;

-- 5. Only the logger can delete a moment, and it then disappears for both.
DO $$
DECLARE v_id uuid; v_visible int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'first', 'First trip', current_date)
  RETURNING id INTO v_id;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.soft_delete_timeline_event(v_id);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner deleted someone else''s moment';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true);
  PERFORM public.soft_delete_timeline_event(v_id);

  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_visible FROM public.timeline_events WHERE id = v_id;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_visible <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted moment is still visible';
  END IF;
END $$;

-- 6. Deleting a relationship that has moments, reminders and family rows
--    but no signal row yet still succeeds: the cascade's AFTER DELETE
--    triggers must not insert a signal for a parent that is being deleted.
DO $$
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7e000000-0000-0000-0000-000000000003',
          '7a000000-0000-0000-0000-0000000000c3', NULL, 'ended', now(), now());
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000003',
          '7a000000-0000-0000-0000-0000000000c3', 'first', 'Cascade probe', current_date);
  DELETE FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000003';

  DELETE FROM public.relationships WHERE id = '7e000000-0000-0000-0000-000000000003';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE EXCEPTION 'CONTRACT VIOLATED: the signal trigger blocked a relationship delete: %', SQLERRM;
END $$;

ROLLBACK;
