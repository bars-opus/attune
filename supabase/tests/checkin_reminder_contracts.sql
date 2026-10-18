-- supabase/tests/checkin_reminder_contracts.sql
-- Spec 5 (R5-11, A7; plan review C5, I8, I9): a weekly check-in reminder at
-- 18:00-18:59 on the person's own Sunday, once a week, only for an active
-- relationship, skipped after a check-in this local week or when the
-- zone is unknown; the copy names nobody.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9f800000-0000-0000-0000-0000000000a1'), ('9f800000-0000-0000-0000-0000000000b2'),
  ('9f800000-0000-0000-0000-0000000000c3'), ('9f800000-0000-0000-0000-0000000000c4'),
  ('9f800000-0000-0000-0000-0000000000d5'), ('9f800000-0000-0000-0000-0000000000e6'),
  ('9f800000-0000-0000-0000-0000000000f7'), ('9f800000-0000-0000-0000-0000000000a8'),
  ('9f800000-0000-0000-0000-0000000000a9'), ('9f800000-0000-0000-0000-0000000000aa')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('9f800000-0000-0000-0000-0000000000a1', '+233599800001', 'Ama Chicago', 'America/Chicago'),
  ('9f800000-0000-0000-0000-0000000000b2', '+233599800002', 'Kofi Honolulu', 'Pacific/Honolulu'),
  ('9f800000-0000-0000-0000-0000000000c3', '+233599800003', 'Lola London', 'Europe/London'),
  ('9f800000-0000-0000-0000-0000000000c4', '+233599800004', 'Lee London', 'Europe/London'),
  ('9f800000-0000-0000-0000-0000000000d5', '+233599800005', 'Pat Paused', 'America/Chicago'),
  ('9f800000-0000-0000-0000-0000000000e6', '+233599800006', 'Pip Paused', 'America/Chicago'),
  ('9f800000-0000-0000-0000-0000000000f7', '+233599800007', 'Nobody Knows', NULL),
  ('9f800000-0000-0000-0000-0000000000a8', '+233599800008', 'Tomo Tokyo', 'Asia/Tokyo'),
  ('9f800000-0000-0000-0000-0000000000a9', '+233599800009', 'Mo Monday', 'America/Chicago'),
  ('9f800000-0000-0000-0000-0000000000aa', '+233599800010', 'Ash Chicago', 'America/Chicago')
ON CONFLICT (id) DO UPDATE SET timezone = EXCLUDED.timezone;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9f810000-0000-0000-0000-000000000001', '9f800000-0000-0000-0000-0000000000a1', '9f800000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9f810000-0000-0000-0000-000000000002', '9f800000-0000-0000-0000-0000000000c3', '9f800000-0000-0000-0000-0000000000c4', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9f810000-0000-0000-0000-000000000003', '9f800000-0000-0000-0000-0000000000d5', '9f800000-0000-0000-0000-0000000000e6', 'paused', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9f810000-0000-0000-0000-000000000004', '9f800000-0000-0000-0000-0000000000f7', '9f800000-0000-0000-0000-0000000000a8', 'active', CURRENT_DATE - 50, now() - interval '50 days', now()),
  ('9f810000-0000-0000-0000-000000000005', '9f800000-0000-0000-0000-0000000000a9', '9f800000-0000-0000-0000-0000000000aa', 'active', CURRENT_DATE - 50, now() - interval '50 days', now());
-- Lola checked in on Friday.
INSERT INTO public.weekly_checkins (user_id, relationship_id, week_ending, submitted_at)
VALUES ('9f800000-0000-0000-0000-0000000000c3', '9f810000-0000-0000-0000-000000000002', DATE '2026-10-18', TIMESTAMPTZ '2026-10-16 12:00Z'),
-- Mo checked in on Monday morning, 08:00 in Chicago: more than six days
-- before Sunday evening, but the same week (final review M-4).
       ('9f800000-0000-0000-0000-0000000000a9', '9f810000-0000-0000-0000-000000000005', DATE '2026-10-18', TIMESTAMPTZ '2026-10-12 13:00Z');

CREATE FUNCTION pg_temp.n(p_user text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.scheduled_notifications
  WHERE user_id = ('9f800000-0000-0000-0000-0000000000' || p_user)::uuid AND metadata->>'type' = 'checkin_reminder'
$$;

DO $$
DECLARE r record;
BEGIN
  -- Sunday 2026-10-18. 22:59Z is 17:59 in Chicago: not yet.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-18 22:59Z');
  IF pg_temp.n('a1') <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder before 18:00 local'; END IF;
  -- 23:30Z is 18:30 in Chicago: once, however often the job runs.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-18 23:30Z');
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-18 23:45Z');
  IF pg_temp.n('a1') <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Chicago got % reminders, not 1', pg_temp.n('a1'); END IF;
  IF pg_temp.n('b2') <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Honolulu was reminded at 13:30 local'; END IF;
  IF pg_temp.n('d5') + pg_temp.n('e6') <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused relationship was reminded'; END IF;
  IF pg_temp.n('a9') <> 0 OR pg_temp.n('aa') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: this week''s Monday check-in: Mo % (want 0), Ash % (want 1)', pg_temp.n('a9'), pg_temp.n('aa');
  END IF;
  -- Honolulu's own Sunday 18:30 is Monday 04:30Z; its key is the local Sunday.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-19 04:30Z');
  IF pg_temp.n('b2') <> 1 OR NOT EXISTS (SELECT 1 FROM public.scheduled_notifications
       WHERE source_key = 'checkin:9f800000-0000-0000-0000-0000000000b2:2026-10-18') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Honolulu''s reminder is missing or keyed to the UTC day';
  END IF;
  -- Monday evening in Chicago: nothing more.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-19 23:30Z');
  IF pg_temp.n('a1') <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a Monday reminder'; END IF;
  -- London 18:30 BST is 17:30Z: Lee yes; Lola checked in on Friday.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-18 17:30Z');
  IF pg_temp.n('c4') <> 1 OR pg_temp.n('c3') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: London: Lee % (want 1), Lola % (want 0)', pg_temp.n('c4'), pg_temp.n('c3');
  END IF;
  -- Tokyo 18:30 JST is 09:30Z: Tomo yes; an unknown zone is never guessed.
  PERFORM public.generate_checkin_reminders(TIMESTAMPTZ '2026-10-18 09:30Z');
  IF pg_temp.n('a8') <> 1 OR pg_temp.n('f7') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Tokyo % (want 1), unknown zone % (want 0)', pg_temp.n('a8'), pg_temp.n('f7');
  END IF;
  -- The copy names nobody, routes to the check-in, and 18:30 is never deferred.
  FOR r IN SELECT * FROM public.scheduled_notifications WHERE metadata->>'type' = 'checkin_reminder'
           AND user_id::text LIKE '9f800000-%' LOOP
    IF r.metadata->>'title' <> 'Weekly check-in' OR r.metadata->>'body' <> 'A minute to look back on your week.' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: copy %', r.metadata;
    END IF;
    IF r.metadata::text ~* '(Ama|Kofi|Lola|Lee|Tomo|Mo |Ash|Chicago|Honolulu|London|Tokyo)' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder names someone: %', r.metadata;
    END IF;
    IF coalesce((r.metadata->>'quiet_deferred')::boolean, false) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an 18:00 reminder was deferred';
    END IF;
    -- Sync audit M-1: pause and end can cancel it, like every other push.
    IF NOT EXISTS (SELECT 1 FROM public.relationships x
                   WHERE x.id::text = r.metadata->>'relationship_id'
                     AND r.user_id IN (x.user_a, x.user_b)) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder carries no relationship: %', r.metadata;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'generate-checkin-reminders' AND schedule = '10 * * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder generator is not scheduled hourly';
  END IF;
  IF has_function_privilege('authenticated', 'public.generate_checkin_reminders(timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.generate_checkin_reminders(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can run the generator';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'checkin_reminder_contracts: all held'; END $$;
ROLLBACK;
