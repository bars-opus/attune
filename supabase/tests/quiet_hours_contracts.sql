-- supabase/tests/quiet_hours_contracts.sql
-- Engine-level quiet hours (Spec 1b Task 2; research 06 §3 F6 (1)): a push
-- whose send time is in the recipient's local 22:00–08:00 waits for 08:00
-- local, deferred never dropped; safety resources and plan alarms never
-- wait; a retry at night waits too; overnight chat collapses to one push per
-- conversation; "Today"/"Tomorrow" copy deferred across midnight goes
-- neutral. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8c100000-0000-0000-0000-0000000000a1'),
  ('8c100000-0000-0000-0000-0000000000b2'),
  ('8c100000-0000-0000-0000-0000000000c3'),
  ('8c100000-0000-0000-0000-0000000000d4'),
  ('8c100000-0000-0000-0000-0000000000e5')
ON CONFLICT (id) DO NOTHING;
-- A: Accra (UTC+0, no DST). B: New York. C and D: zones picked below so the
-- REAL clock is 23:xx (C) or 12:xx (D) local -- the retry path defers from
-- now(), which a contract cannot pin.
INSERT INTO public.users (id, phone, display_name, timezone) VALUES
  ('8c100000-0000-0000-0000-0000000000a1', '+233598200001', 'Quiet A', 'Africa/Accra'),
  ('8c100000-0000-0000-0000-0000000000b2', '+233598200002', 'Quiet B', 'America/New_York'),
  ('8c100000-0000-0000-0000-0000000000c3', '+233598200003', 'Quiet C', NULL),
  ('8c100000-0000-0000-0000-0000000000d4', '+233598200004', 'Quiet D', NULL),
  ('8c100000-0000-0000-0000-0000000000e5', '+233598200005', 'Quiet E', NULL)
ON CONFLICT (id) DO NOTHING;

-- An Etc/GMT zone in which the real now() is p_hour:xx local
-- (Etc/GMT-N is UTC+N; the range -11..+12 exists in tzdata).
CREATE FUNCTION pg_temp.zone_at(p_hour int) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN n = 0 THEN 'Etc/GMT'
              WHEN n > 0 THEN 'Etc/GMT-' || n
              ELSE 'Etc/GMT+' || (-n) END
  FROM (SELECT CASE WHEN m > 12 THEN m - 24 ELSE m END AS n
        FROM (SELECT (((p_hour - extract(hour FROM now() AT TIME ZONE 'UTC')::int) % 24) + 24) % 24 AS m) a) b $$;
UPDATE public.users SET timezone = pg_temp.zone_at(23) WHERE id = '8c100000-0000-0000-0000-0000000000c3';
UPDATE public.users SET timezone = pg_temp.zone_at(12) WHERE id = '8c100000-0000-0000-0000-0000000000d4';

-- Queue one push as the server does; returns its id (NULL when collapsed).
CREATE FUNCTION pg_temp.push(p_user uuid, p_type text, p_at timestamptz,
  p_extra jsonb DEFAULT '{}'::jsonb, p_key text DEFAULT NULL, p_status text DEFAULT 'pending')
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (p_user, 'immediate', p_at, p_status,
          jsonb_build_object('type', p_type, 'title', 'T', 'body', 'B',
                             'relationship_id', '8c200000-0000-0000-0000-000000000001') || p_extra,
          p_key)
  RETURNING id $$;
CREATE FUNCTION pg_temp.at(p_id uuid) RETURNS timestamptz LANGUAGE sql AS $$
  SELECT scheduled_for FROM public.scheduled_notifications WHERE id = p_id $$;

-- 0. The window, including its edges and a DST morning.
DO $$
BEGIN
  IF public.quiet_hours_release_at('2026-11-10 23:30+00', 'Africa/Accra') <> '2026-11-11 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 22:00+00', 'Africa/Accra') <> '2026-11-11 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 03:00+00', 'Africa/Accra') <> '2026-11-10 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 07:59+00', 'Africa/Accra') <> '2026-11-10 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a night send time is not released at 08:00 local';
  END IF;
  IF public.quiet_hours_release_at('2026-11-10 08:00+00', 'Africa/Accra') <> '2026-11-10 08:00+00'
     OR public.quiet_hours_release_at('2026-11-10 21:59+00', 'Africa/Accra') <> '2026-11-10 21:59+00'
     OR public.quiet_hours_release_at('2026-11-10 12:00+00', 'Africa/Accra') <> '2026-11-10 12:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime send time moved';
  END IF;
  -- 22:30 EST on 10 Nov is 03:30Z on the 11th; 08:00 EST is 13:00Z.
  IF public.quiet_hours_release_at('2026-11-11 03:30+00', 'America/New_York') <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recipient''s own zone is not used';
  END IF;
  -- Spring forward (8 Mar 2026, 02:00 EST -> 03:00 EDT): 01:30 EST is
  -- 06:30Z; 08:00 EDT is 12:00Z.
  IF public.quiet_hours_release_at('2026-03-08 06:30+00', 'America/New_York') <> '2026-03-08 12:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the DST morning is not released at 08:00 local';
  END IF;
END $$;

-- 1. Every inserter is covered: a night push waits, a day push does not.
DO $$
DECLARE v_night uuid; v_day uuid;
BEGIN
  v_night := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 23:30+00');
  v_day := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 12:00+00');
  IF pg_temp.at(v_night) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 23:30 push was not deferred (%)', pg_temp.at(v_night);
  END IF;
  IF (SELECT metadata->>'quiet_deferred' FROM public.scheduled_notifications WHERE id = v_night) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred push is not marked';
  END IF;
  IF pg_temp.at(v_day) <> '2026-11-10 12:00+00'
     OR (SELECT metadata ? 'quiet_deferred' FROM public.scheduled_notifications WHERE id = v_day) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime push was touched';
  END IF;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_night) <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred push is not pending (dropped?)';
  END IF;
END $$;

-- 2. Safety resources and short-notice plan alarms never wait (owner
--    decision D1); a day-ahead heads-up is still true at 08:00 and waits.
DO $$
DECLARE v_safe uuid; v_alarm uuid; v_far uuid;
BEGIN
  v_safe := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'safety_resources', '2026-11-10 23:30+00');
  v_alarm := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{}'::jsonb, 'together_alarm:8c-ev:2026-11-10:60:8c100000-0000-0000-0000-0000000000a1');
  v_far := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{}'::jsonb, 'together_alarm:8c-ev:2026-11-11:1440:8c100000-0000-0000-0000-0000000000a1');
  IF pg_temp.at(v_safe) <> '2026-11-10 23:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety push was held until morning';
  END IF;
  IF pg_temp.at(v_alarm) <> '2026-11-10 23:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plan alarm was held until morning';
  END IF;
  IF pg_temp.at(v_far) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a day-ahead heads-up rang at night (%)', pg_temp.at(v_far);
  END IF;
END $$;

-- 3. The recipient's own zone decides.
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000b2', 'moment_logged', '2026-11-11 03:30+00');
  IF pg_temp.at(v) <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: New York 22:30 released at % (want 13:00Z)', pg_temp.at(v);
  END IF;
END $$;

-- 4. A retry or a stale-lease reset at night waits too; by day it doesn't.
DO $$
DECLARE v_c uuid; v_d uuid; v_tz text; v_before timestamptz := now() - interval '1 minute';
BEGIN
  v_c := pg_temp.push('8c100000-0000-0000-0000-0000000000c3', 'moment_logged', v_before, '{}'::jsonb, NULL, 'processing');
  v_d := pg_temp.push('8c100000-0000-0000-0000-0000000000d4', 'moment_logged', v_before, '{}'::jsonb, NULL, 'processing');
  IF pg_temp.at(v_c) <> v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a processing row was moved on insert'; END IF;
  UPDATE public.scheduled_notifications SET status = 'pending', retry_count = 1 WHERE id IN (v_c, v_d);
  SELECT timezone INTO v_tz FROM public.users WHERE id = '8c100000-0000-0000-0000-0000000000c3';
  IF pg_temp.at(v_c) <= now() OR (pg_temp.at(v_c) AT TIME ZONE v_tz)::time <> time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry at 23:xx local goes out at % (zone %)', pg_temp.at(v_c), v_tz;
  END IF;
  IF pg_temp.at(v_d) <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daytime retry was delayed';
  END IF;
  -- The worker's claim and finish (other statuses) pass straight through.
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_d;
  UPDATE public.scheduled_notifications SET status = 'sent' WHERE id = v_d;
  IF pg_temp.at(v_d) <> v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: claim/finish moved a row'; END IF;
END $$;

-- 5. Overnight chat: one push per conversation, sent at 08:00 (owner
--    decision D2). By day, nothing collapses.
DO $$
DECLARE v1 uuid; v2 uuid; v3 uuid; v_other uuid; v_n int; v_m jsonb;
BEGIN
  v1 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:10+00');
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:20+00');
  v3 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'message_reaction', '2026-11-11 02:40+00');
  v_other := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-10 23:30+00',
                          '{"relationship_id":"8c200000-0000-0000-0000-000000000099"}'::jsonb);
  IF v1 IS NULL OR v2 IS NOT NULL OR v3 IS NOT NULL OR v_other IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: overnight chat did not collapse per conversation (% % % %)', v1, v2, v3, v_other;
  END IF;
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE user_id = '8c100000-0000-0000-0000-0000000000a1' AND status = 'pending'
     AND metadata->>'type' IN ('new_message', 'message_reaction')
     AND metadata->>'relationship_id' = '8c200000-0000-0000-0000-000000000001';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % overnight chat pushes for one conversation', v_n; END IF;
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE id = v1;
  IF v_m->>'title' <> 'New messages in Attune' OR v_m->>'body' <> 'Open Attune to read them.'
     OR (v_m->>'quiet_count')::int <> 3 OR pg_temp.at(v1) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the collapsed push is wrong: % at %', v_m, pg_temp.at(v1);
  END IF;
  -- The collapse row is claimed at 08:00 while a late night message is
  -- still being queued: no duplicate-key error, a second neutral push.
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v1;
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 07:59+00',
                     '{"body":"a preview"}'::jsonb);
  IF v2 IS NULL OR (SELECT source_key FROM public.scheduled_notifications WHERE id = v2) IS NOT NULL
     OR (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v2) <> 'Open Attune to read them.'
     OR pg_temp.at(v2) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a message after the collapse row was claimed was mishandled';
  END IF;
  -- By day each message is its own push.
  v1 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 12:05+00');
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'new_message', '2026-11-11 12:06+00');
  IF v1 IS NULL OR v2 IS NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: daytime chat collapsed'; END IF;
END $$;

-- 6. "Today"/"Tomorrow" deferred across local midnight go neutral; within
--    the same local date they stand. Nothing is dropped.
DO $$
DECLARE v_late uuid; v_early uuid; v_cd uuid; v_m jsonb;
BEGIN
  v_late := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'reminder_upcoming', '2026-11-10 23:30+00',
                         '{"body":"Tomorrow"}'::jsonb);
  v_early := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'reminder_upcoming', '2026-11-10 03:00+00',
                          '{"body":"Tomorrow"}'::jsonb);
  v_cd := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'planning_entry', '2026-11-10 23:30+00',
                       '{"title":"Today''s the day","body":"B"}'::jsonb,
                       'planning_countdown:8c-test:8c100000-0000-0000-0000-0000000000a1:2026-11-10');
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v_late) <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Tomorrow" arrives a day late unchanged';
  END IF;
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v_early) <> 'Tomorrow' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a same-day deferral changed correct copy';
  END IF;
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE id = v_cd;
  IF v_m->>'title' <> 'Your plan' OR v_m->>'body' <> 'Open Attune to see it.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred countdown still says today: %', v_m;
  END IF;
END $$;

-- 7. A user whose zone is unknown is never deferred: no guess, no 03:00
--    release (review C1).
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000e5', 'moment_logged', '2026-11-10 23:30+00');
  IF pg_temp.at(v) <> '2026-11-10 23:30+00'
     OR (SELECT metadata ? 'quiet_deferred' FROM public.scheduled_notifications WHERE id = v) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push for a user with no known zone was moved (to %)', pg_temp.at(v);
  END IF;
END $$;

-- 8. Game pushes (owner follow-up 2026-10-17): a push about a game session
--    skips quiet hours only while the game is live -- the recipient was in
--    the app in the last 15 minutes, or the session had a move in the last
--    15 minutes. Otherwise it waits like everything else (an invite to a
--    partner who may be asleep).
DO $$
DECLARE v_wait uuid; v_live uuid; v_inapp uuid; v_old uuid;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
    ('8c200000-0000-0000-0000-000000000001', '8c100000-0000-0000-0000-0000000000a1',
     '8c100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.game_sessions (id, relationship_id, initiator_id, game_type, status) VALUES
    ('8c300000-0000-0000-0000-000000000001', '8c200000-0000-0000-0000-000000000001',
     '8c100000-0000-0000-0000-0000000000a1', 'mirror', 'active'),
    ('8c300000-0000-0000-0000-000000000002', '8c200000-0000-0000-0000-000000000001',
     '8c100000-0000-0000-0000-0000000000a1', 'mirror', 'active');
  -- Session 1 had a move a minute ago; session 2's last move was yesterday.
  INSERT INTO public.game_session_rounds (session_id, round_number, answer_a_submitted_at, created_at) VALUES
    ('8c300000-0000-0000-0000-000000000001', 1, now() - interval '1 minute', now() - interval '20 minutes'),
    ('8c300000-0000-0000-0000-000000000002', 1, now() - interval '1 day', now() - interval '1 day');
  -- B (New York, 22:30 local): live game -> now; stale game -> 08:00.
  v_live := pg_temp.push('8c100000-0000-0000-0000-0000000000b2', 'game_turn', '2026-11-11 03:30+00',
                         '{"session_id":"8c300000-0000-0000-0000-000000000001"}'::jsonb);
  v_old := pg_temp.push('8c100000-0000-0000-0000-0000000000b2', 'game_invite', '2026-11-11 03:30+00',
                        '{"session_id":"8c300000-0000-0000-0000-000000000002"}'::jsonb);
  IF pg_temp.at(v_live) <> '2026-11-11 03:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a turn in a game being played right now waited until morning';
  END IF;
  IF pg_temp.at(v_old) <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a push about a game not being played rang at night';
  END IF;
  -- A (Accra 23:30): an invite waits -- unless A was in the app just now.
  v_wait := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'game_invite', '2026-11-10 23:30+00',
                         '{"session_id":"8c300000-0000-0000-0000-000000000002"}'::jsonb);
  IF pg_temp.at(v_wait) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invite to a partner who may be asleep rang at night';
  END IF;
  INSERT INTO public.chat_presence (user_id, active_relationship_id, updated_at)
  VALUES ('8c100000-0000-0000-0000-0000000000a1', NULL, now() - interval '2 minutes')
  ON CONFLICT (user_id) DO UPDATE SET updated_at = EXCLUDED.updated_at;
  v_inapp := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'game_invite', '2026-11-10 23:30+00',
                          '{"session_id":"8c300000-0000-0000-0000-000000000002"}'::jsonb);
  IF pg_temp.at(v_inapp) <> '2026-11-10 23:30+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invite to a partner in the app right now waited until morning';
  END IF;
  -- Being in the app never exempts a non-game push.
  IF pg_temp.at(pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'moment_logged', '2026-11-10 23:30+00'))
     <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: being in the app exempted a non-game push';
  END IF;
  DELETE FROM public.chat_presence WHERE user_id = '8c100000-0000-0000-0000-0000000000a1';
END $$;

-- 9. A chat push retried into the night joins the overnight push (or
--    becomes it), never arriving alone with its preview (follow-up M1).
DO $$
DECLARE v_first uuid; v_retry uuid; v_lone uuid; v_m jsonb;
BEGIN
  -- C's zone puts the real clock at 23:xx.
  v_first := pg_temp.push('8c100000-0000-0000-0000-0000000000c3', 'new_message', now());
  v_retry := pg_temp.push('8c100000-0000-0000-0000-0000000000c3', 'new_message', now() - interval '1 minute',
                          '{"title":"Kofi","body":"are you up?"}'::jsonb, NULL, 'processing');
  UPDATE public.scheduled_notifications SET status = 'pending', retry_count = 1 WHERE id = v_retry;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_retry) <> 'cancelled'
     OR (SELECT (metadata->>'quiet_count')::int FROM public.scheduled_notifications WHERE id = v_first) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried chat push did not join the overnight push';
  END IF;
  -- With no overnight push yet, the retried one becomes it, neutral.
  v_lone := pg_temp.push('8c100000-0000-0000-0000-0000000000c3', 'new_message', now() - interval '1 minute',
                         '{"title":"Kofi","body":"are you up?","relationship_id":"8c200000-0000-0000-0000-000000000077"}'::jsonb,
                         NULL, 'processing');
  UPDATE public.scheduled_notifications SET status = 'pending' WHERE id = v_lone;
  SELECT metadata INTO v_m FROM public.scheduled_notifications WHERE id = v_lone;
  IF (SELECT status FROM public.scheduled_notifications WHERE id = v_lone) <> 'pending'
     OR (SELECT source_key FROM public.scheduled_notifications WHERE id = v_lone) NOT LIKE 'quiet_chat:%'
     OR v_m->>'body' <> 'Open Attune to read them.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lone retried chat push kept its preview: %', v_m;
  END IF;
END $$;

-- 10. An inserter's own source_key on a chat push is kept (follow-up M2):
--     no collapse, but neutral copy and still deferred.
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000b2', 'new_message', '2026-11-11 03:30+00',
                    '{"body":"a preview"}'::jsonb, 'my_own_key:1');
  IF (SELECT source_key FROM public.scheduled_notifications WHERE id = v) <> 'my_own_key:1'
     OR (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v) <> 'Open Attune to read them.'
     OR pg_temp.at(v) <> '2026-11-11 13:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inserter''s source_key was overwritten or the push mishandled';
  END IF;
END $$;

-- 11. A day-ahead alarm held to 08:00 says how far the plan really is
--     (follow-up M5): fired 23:30 for a plan at 23:30 the next night ->
--     "Today"; two days ahead -> "Tomorrow"; fired 03:00 -> "Tomorrow".
DO $$
DECLARE v1 uuid; v2 uuid; v3 uuid;
BEGIN
  v1 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{"body":"In 1 day"}'::jsonb, 'together_alarm:8c-ev1:2026-11-11:1440:8c100000-0000-0000-0000-0000000000a1');
  v2 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
    '{"body":"In 2 days"}'::jsonb, 'together_alarm:8c-ev2:2026-11-12:2880:8c100000-0000-0000-0000-0000000000a1');
  v3 := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 03:00+00',
    '{"body":"In 1 day"}'::jsonb, 'together_alarm:8c-ev3:2026-11-11:1440:8c100000-0000-0000-0000-0000000000a1');
  IF (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v1) <> 'Today'
     OR (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v2) <> 'Tomorrow'
     OR (SELECT metadata->>'body' FROM public.scheduled_notifications WHERE id = v3) <> 'Tomorrow' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deferred day-ahead alarm says the wrong day';
  END IF;
END $$;

-- 12. A malformed alarm key is not exempt and never errors (follow-up M6).
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.push('8c100000-0000-0000-0000-0000000000a1', 'together_event', '2026-11-10 23:30+00',
                    '{}'::jsonb, 'together_alarm:8c-ev:x:abc:8c100000-0000-0000-0000-0000000000a1');
  IF pg_temp.at(v) <> '2026-11-11 08:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed alarm key was treated as a short alarm';
  END IF;
END $$;

-- 13. The worker's claim re-checks the window (follow-up M7): a row queued
--     before its recipient's zone was known, or reached late in a backlog,
--     is bounced back to pending until 08:00 instead of sent at night.
DO $$
DECLARE v_e uuid; v_safe uuid; v_status text; v_tz text;
BEGIN
  v_e := pg_temp.push('8c100000-0000-0000-0000-0000000000e5', 'moment_logged', now() - interval '1 minute');
  v_safe := pg_temp.push('8c100000-0000-0000-0000-0000000000e5', 'safety_resources', now() - interval '1 minute');
  UPDATE public.users SET timezone = pg_temp.zone_at(23) WHERE id = '8c100000-0000-0000-0000-0000000000e5';
  SELECT timezone INTO v_tz FROM public.users WHERE id = '8c100000-0000-0000-0000-0000000000e5';
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_e AND status = 'pending'
  RETURNING status INTO v_status;
  IF v_status IS DISTINCT FROM 'pending' OR pg_temp.at(v_e) <= now()
     OR (pg_temp.at(v_e) AT TIME ZONE v_tz)::time <> time '08:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the worker claimed a push at 23:xx local (status %, at %)', v_status, pg_temp.at(v_e);
  END IF;
  UPDATE public.scheduled_notifications SET status = 'processing' WHERE id = v_safe AND status = 'pending'
  RETURNING status INTO v_status;
  IF v_status IS DISTINCT FROM 'processing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety push could not be claimed at night';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'quiet_hours_contracts: all held'; END $$;
ROLLBACK;
