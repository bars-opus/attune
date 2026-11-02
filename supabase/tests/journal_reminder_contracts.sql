-- supabase/tests/journal_reminder_contracts.sql
-- Spec 1 W3c (§3.10 J3, §4.2, §4.3 W3c, §4.6, §7.1): the weekly journal
-- reminder. Own row only (read through RLS, written through the RPC);
-- 08:00-21:59 local only; one neutral push per local day at the chosen
-- minute in the person's own zone (never guessed); a change cancels what
-- was queued; no client runs the enqueue. One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/journal_reminder_contracts.sql
-- Fixture ids 3e3c0000-0000-0000-0000-0000000000NN; phones +15558800NN, set
-- on auth.users and public.users. Every refusal is checked by its message.
BEGIN;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege OR check_violation THEN
  RETURN SQLERRM;
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('3e3c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- A person in [p_zone] (NULL: unknown) with a reminder, its settings
-- dated well before the test's clock.
CREATE FUNCTION pg_temp.person(p_n text, p_zone text, p_weekday int, p_time time) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+155588000' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, timezone)
  VALUES (pg_temp.id(p_n), '+155588000' || p_n, 'Ama ' || p_n, p_zone);
  IF p_weekday IS NOT NULL THEN
    INSERT INTO public.journal_reminder_settings (user_id, enabled, iso_weekday, local_time, updated_at)
    VALUES (pg_temp.id(p_n), true, p_weekday, p_time, TIMESTAMPTZ '2026-10-01 00:00Z');
  END IF;
END $$;

CREATE FUNCTION pg_temp.queued(p_n text) RETURNS int LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.scheduled_notifications
   WHERE user_id = pg_temp.id(p_n) AND metadata->>'type' = 'journal_reminder'
     AND status = 'pending';
$$;

-- =====================================================================
-- A. Objects and grants.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.journal_reminder_settings') IS NULL
     OR to_regprocedure('public.set_my_journal_reminder(boolean,smallint,time)') IS NULL
     OR to_regprocedure('public.get_my_journal_reminder()') IS NULL
     OR to_regprocedure('public.enqueue_journal_reminders(timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W3c objects are missing (journal_reminder_settings, set/get_my_journal_reminder, enqueue_journal_reminders)';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.journal_reminder_settings'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: journal_reminder_settings has no RLS';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.journal_reminder_settings', 'SELECT')
     OR has_table_privilege('authenticated', 'public.journal_reminder_settings', 'INSERT')
     OR has_table_privilege('authenticated', 'public.journal_reminder_settings', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.journal_reminder_settings', 'DELETE')
     OR has_table_privilege('anon', 'public.journal_reminder_settings', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client table grants are wrong (authenticated SELECT only, anon nothing)';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.journal_reminder_settings', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.journal_reminder_settings', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: service_role lost DML on journal_reminder_settings';
  END IF;
  -- B6 review N-4: the worker's EXECUTE is granted explicitly.
  IF NOT has_function_privilege('service_role', 'public.enqueue_journal_reminders(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: service_role cannot run enqueue_journal_reminders';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.set_my_journal_reminder(boolean,smallint,time)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_journal_reminder()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_my_journal_reminder(boolean,smallint,time)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_journal_reminder()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.enqueue_journal_reminders(timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.enqueue_journal_reminders(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reminder function grants are wrong';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'enqueue-journal-reminders' AND schedule = '*/15 * * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: enqueue-journal-reminders is not scheduled every 15 minutes';
  END IF;
END $$;

-- =====================================================================
-- B. Own row only; written through the RPC; checked values.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
  v_n int;
  v jsonb;
BEGIN
  PERFORM pg_temp.person('01', 'Africa/Accra', NULL, NULL);
  PERFORM pg_temp.person('02', 'Africa/Accra', NULL, NULL);

  PERFORM pg_temp.as_user(pg_temp.id('01'));
  PERFORM public.set_my_journal_reminder(true, 1::smallint, time '20:00');
  v := public.get_my_journal_reminder();
  RESET ROLE;
  IF v <> '{"enabled": true, "iso_weekday": 1, "local_time": "20:00"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_journal_reminder read back %', v;
  END IF;

  -- Someone else sees nothing of it.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  SELECT count(*) INTO v_n FROM public.journal_reminder_settings;
  v := public.get_my_journal_reminder();
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person can read % reminder rows', v_n;
  END IF;
  IF v <> '{"enabled": false, "iso_weekday": null, "local_time": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no row did not read as off: %', v;
  END IF;

  -- No direct writes.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.journal_reminder_settings (user_id, enabled) VALUES (%L, false)', pg_temp.id('02')));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'permission denied for table journal_reminder_settings' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote its row directly (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Refusals.
  PERFORM pg_temp.as_user(pg_temp.id('02'));
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(true, NULL, time ''20:00'')');
  IF v_msg IS DISTINCT FROM 'journal_reminder:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: on without a day (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(true, 8::smallint, time ''20:00'')');
  IF v_msg IS DISTINCT FROM 'journal_reminder:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: weekday 8 (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(true, 3::smallint, time ''22:30'')');
  IF v_msg IS DISTINCT FROM 'journal_reminder:quiet_hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 22:30 was accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(true, 3::smallint, time ''07:59'')');
  IF v_msg IS DISTINCT FROM 'journal_reminder:quiet_hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 07:59 was accepted (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(true, 3::smallint, time ''08:00'')');
  RESET ROLE;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 08:00 was refused (%)', v_msg;
  END IF;

  PERFORM pg_temp.as_user(NULL);
  v_msg := pg_temp.error_of('SELECT public.set_my_journal_reminder(false, NULL, NULL)');
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'journal_reminder:not_signed_in' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no session (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Off keeps the day and time.
  PERFORM pg_temp.as_user(pg_temp.id('01'));
  PERFORM public.set_my_journal_reminder(false, NULL, NULL);
  v := public.get_my_journal_reminder();
  RESET ROLE;
  IF v <> '{"enabled": false, "iso_weekday": 1, "local_time": "20:00"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning off forgot the day and time: %', v;
  END IF;
END $$;

-- =====================================================================
-- C. Enqueue: the local minute, once per local day, neutral.
--    Monday 2026-11-02. Accra is UTC; Chicago is UTC-6 (CST from 1 Nov).
-- =====================================================================
DO $$
DECLARE
  r record;
BEGIN
  PERFORM pg_temp.person('11', 'Africa/Accra', 1, time '20:00');
  PERFORM pg_temp.person('12', 'America/Chicago', 1, time '20:00');
  PERFORM pg_temp.person('13', NULL, 1, time '20:00');
  PERFORM pg_temp.person('14', 'Africa/Accra', 2, time '20:00');
  PERFORM pg_temp.person('15', 'Africa/Accra', 1, time '20:00');
  UPDATE public.journal_reminder_settings SET enabled = false WHERE user_id = pg_temp.id('15');
  PERFORM pg_temp.person('16', 'Africa/Accra', 1, time '20:00');
  INSERT INTO public.account_holds (user_id, kind) VALUES (pg_temp.id('16'), 'age_review');

  -- 19:44Z: Accra's 20:00 is 16 minutes away: not yet.
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 19:44Z');
  IF pg_temp.queued('11') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: queued more than 15 minutes early';
  END IF;
  -- 19:46Z: queued for 20:00 itself; the runs after add nothing.
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 19:46Z');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 20:00Z');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 20:14Z');
  IF pg_temp.queued('11') <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('11') AND scheduled_for = TIMESTAMPTZ '2026-11-02 20:00Z'
          AND source_key = 'journal_reminder:' || pg_temp.id('11') || ':2026-11-02') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Accra got % reminders, or not for 20:00 Monday', pg_temp.queued('11');
  END IF;
  IF (SELECT last_enqueued_for FROM public.journal_reminder_settings WHERE user_id = pg_temp.id('11'))
     IS DISTINCT FROM DATE '2026-11-02' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: last_enqueued_for was not the local Monday';
  END IF;
  -- Not Chicago (14:00 there), not Tuesday's, not off, not held, never a
  -- guessed zone.
  IF pg_temp.queued('12') + pg_temp.queued('13') + pg_temp.queued('14')
     + pg_temp.queued('15') + pg_temp.queued('16') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else was reminded at 20:00Z';
  END IF;

  -- Chicago's Monday 20:00 is Tuesday 02:00Z; its key is the local Monday.
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-03 01:50Z');
  IF pg_temp.queued('12') <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('12') AND scheduled_for = TIMESTAMPTZ '2026-11-03 02:00Z'
          AND source_key = 'journal_reminder:' || pg_temp.id('12') || ':2026-11-02') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Chicago''s reminder is missing or keyed to the UTC day';
  END IF;
  IF pg_temp.queued('13') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown zone was guessed';
  END IF;

  -- The copy names nobody and is never moved by quiet hours.
  FOR r IN SELECT * FROM public.scheduled_notifications
            WHERE metadata->>'type' = 'journal_reminder' AND user_id::text LIKE '3e3c0000-%' LOOP
    IF r.metadata <> '{"type": "journal_reminder", "title": "Attune", "body": "A few quiet minutes for you, if you''d like."}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the reminder is not the neutral copy: %', r.metadata;
    END IF;
    IF r.notification_type <> 'immediate' OR r.delivery_channel <> 'push' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: not an immediate push: % %', r.notification_type, r.delivery_channel;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- D. A change cancels what was queued, and the new time can still go out
--    today; a time set after today's minute waits a week.
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.person('21', 'Africa/Accra', 1, time '20:00');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 19:50Z');
  IF pg_temp.queued('21') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first reminder was not queued';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('21'));
  PERFORM public.set_my_journal_reminder(true, 1::smallint, time '21:00');
  RESET ROLE;
  IF pg_temp.queued('21') <> 0 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('21') AND status = 'cancelled' AND source_key IS NULL
          AND last_error = 'journal_reminder_changed') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the old reminder was not cancelled and its key freed';
  END IF;
  -- The change is "now" (the real clock): date it before 21:00 Monday so
  -- the test's Monday reads as after it.
  UPDATE public.journal_reminder_settings SET updated_at = TIMESTAMPTZ '2026-11-02 19:55Z'
   WHERE user_id = pg_temp.id('21');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 20:50Z');
  IF pg_temp.queued('21') <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('21') AND status = 'pending'
          AND scheduled_for = TIMESTAMPTZ '2026-11-02 21:00Z') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the changed reminder did not go out at 21:00';
  END IF;

  -- Set at 20:30 for 20:00 the same Monday: next week, not now.
  PERFORM pg_temp.person('22', 'Africa/Accra', 1, time '20:00');
  UPDATE public.journal_reminder_settings SET updated_at = TIMESTAMPTZ '2026-11-02 20:05Z'
   WHERE user_id = pg_temp.id('22');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 20:10Z');
  IF pg_temp.queued('22') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder set after its time fired at once';
  END IF;
END $$;

-- =====================================================================
-- E. The account goes, the reminder goes.
-- =====================================================================
DO $$
BEGIN
  DELETE FROM public.users WHERE id = pg_temp.id('22');
  IF EXISTS (SELECT 1 FROM public.journal_reminder_settings WHERE user_id = pg_temp.id('22')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted account kept its reminder';
  END IF;
END $$;

-- =====================================================================
-- F. Late or skipped cron runs (B6 review I-2, ruling M-1): a missed
--    reminder still goes out later the same local day, sent at the run
--    (never back-dated), up to 21:59; a day missed until 22:00 is skipped,
--    never moved to the next morning. Monday 2026-11-02, Accra (UTC).
-- =====================================================================
DO $$
BEGIN
  -- One run skipped: the first run after 20:00 is 20:10.
  PERFORM pg_temp.person('17', 'Africa/Accra', 1, time '20:00');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 20:10Z');
  IF pg_temp.queued('17') <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('17') AND status = 'pending'
          AND scheduled_for = TIMESTAMPTZ '2026-11-02 20:10Z'
          AND source_key = 'journal_reminder:' || pg_temp.id('17') || ':2026-11-02')
     OR (SELECT last_enqueued_for FROM public.journal_reminder_settings WHERE user_id = pg_temp.id('17'))
        IS DISTINCT FROM DATE '2026-11-02' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late run missed or misdated the reminder';
  END IF;

  -- Many runs skipped: the first run is 90 minutes late, still Monday.
  PERFORM pg_temp.person('18', 'Africa/Accra', 1, time '20:00');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 21:30Z');
  IF pg_temp.queued('18') <> 1 OR NOT EXISTS (
       SELECT 1 FROM public.scheduled_notifications
        WHERE user_id = pg_temp.id('18') AND status = 'pending'
          AND scheduled_for = TIMESTAMPTZ '2026-11-02 21:30Z') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reminder missed by several runs was lost for the day';
  END IF;

  -- Missed until 22:00: skipped that day, not sent at night, not moved to
  -- Tuesday morning.
  PERFORM pg_temp.person('19', 'Africa/Accra', 1, time '21:55');
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-02 22:05Z');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = pg_temp.id('19')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a run after 22:00 queued the day''s reminder';
  END IF;
  PERFORM public.enqueue_journal_reminders(TIMESTAMPTZ '2026-11-03 08:00Z');
  IF EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = pg_temp.id('19')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missed reminder was moved to the next day';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'journal_reminder_contracts: all held'; END $$;
ROLLBACK;
