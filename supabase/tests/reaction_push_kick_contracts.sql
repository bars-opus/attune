-- supabase/tests/reaction_push_kick_contracts.sql
--
-- Chat review #14 (1b Task 5 fix round): a reaction's outbox row is kicked
-- to process-chat-notification-outbox the moment it is queued, exactly as
-- enqueue_message_downstream_work kicks a message's row -- so a reaction
-- push no longer waits for the minute cron. Every pre-existing behaviour
-- of enqueue_reaction_notification (20260901140000) still holds, and a
-- failed kick never fails the reaction. Every check RAISEs.
--
-- net.http_post is replaced, inside this transaction only, by a recorder;
-- the app settings are SET LOCAL stand-ins (no real credentials).
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8d175000-0000-0000-0000-0000000000a1'),
  ('8d175000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, mode) VALUES
  ('8d175000-0000-0000-0000-0000000000a1', '+233598175001', 'Kick A', 'couples'),
  ('8d175000-0000-0000-0000-0000000000b2', '+233598175002', 'Kick B', 'couples')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('8d175000-0000-0000-0000-000000000011',
        '8d175000-0000-0000-0000-0000000000a1',
        '8d175000-0000-0000-0000-0000000000b2',
        'active', CURRENT_DATE, now())
ON CONFLICT (id) DO NOTHING;
-- A's message; B reacts to it, so A is the recipient.
INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content)
VALUES ('8d175000-0000-0000-0000-000000000021',
        '8d175000-0000-0000-0000-000000000011',
        '8d175000-0000-0000-0000-0000000000a1',
        '8d175000-0000-0000-0000-000000000031', 'hello');

CREATE TEMP TABLE kicks (url text, body jsonb, headers jsonb) ON COMMIT DROP;
CREATE OR REPLACE FUNCTION net.http_post(
  url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('test.kick_fails', true) = 'on' THEN
    RAISE EXCEPTION 'stub: pg_net is down';
  END IF;
  INSERT INTO pg_temp.kicks VALUES (url, body, headers);
  RETURN 1;
END $$;

SET LOCAL app.settings.supabase_url = 'https://stub.supabase.co';
SET LOCAL app.settings.service_role_key = 'stub-key';

-- The outbox kicks recorded for the reaction job on the fixture message.
CREATE FUNCTION pg_temp.reaction_kicks() RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM pg_temp.kicks k
  JOIN public.message_notification_outbox o ON o.id::text = k.body->>'outbox_id'
  WHERE o.message_id = '8d175000-0000-0000-0000-000000000021'
    AND o.notification_type = 'message_reaction'
    AND k.url = 'https://stub.supabase.co/functions/v1/process-chat-notification-outbox'
    AND k.headers->>'Authorization' = 'Bearer stub-key'
    AND k.headers->>'apikey' = 'stub-key' $$;

-- 1. A reaction queues one outbox row for the message's sender and kicks it.
CREATE FUNCTION pg_temp.check_react_kicks() RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
  DELETE FROM pg_temp.kicks;
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES ('8d175000-0000-0000-0000-000000000021', '8d175000-0000-0000-0000-000000000011',
          '8d175000-0000-0000-0000-0000000000b2', '❤️');
  SELECT * INTO r FROM public.message_notification_outbox
  WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction';
  IF NOT FOUND THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a reaction queued no outbox row'; END IF;
  IF r.recipient_id <> '8d175000-0000-0000-0000-0000000000a1'
     OR r.sender_id <> '8d175000-0000-0000-0000-0000000000b2'
     OR r.reactor_id <> '8d175000-0000-0000-0000-0000000000b2'
     OR r.reaction_emoji <> '❤️' OR r.state <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reaction outbox row is wrong: %', row_to_json(r);
  END IF;
  IF pg_temp.reaction_kicks() <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reaction was not kicked to process-chat-notification-outbox (% kicks)',
      pg_temp.reaction_kicks();
  END IF;
END $$;
SAVEPOINT before_react;
SELECT pg_temp.check_react_kicks();

-- 2. A re-react collapses onto the same row (reset to pending) and kicks it again.
DO $$
DECLARE v_before uuid; v_after uuid; v_n int; r record;
BEGIN
  SELECT id INTO v_before FROM public.message_notification_outbox
  WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction';
  UPDATE public.message_notification_outbox SET state = 'done', attempts = 3 WHERE id = v_before;
  DELETE FROM pg_temp.kicks;
  UPDATE public.message_reactions SET emoji = '😂'
  WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND user_id = '8d175000-0000-0000-0000-0000000000b2';
  SELECT count(*), max(id::text)::uuid INTO v_n, v_after FROM public.message_notification_outbox
  WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction';
  IF v_n <> 1 OR v_after <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-react did not collapse onto one outbox row (% rows)', v_n;
  END IF;
  SELECT * INTO r FROM public.message_notification_outbox WHERE id = v_after;
  IF r.reaction_emoji <> '😂' OR r.state <> 'pending' OR r.attempts <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-react did not reset the row: %', row_to_json(r);
  END IF;
  IF pg_temp.reaction_kicks() <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-react was not kicked (% kicks)', pg_temp.reaction_kicks();
  END IF;
END $$;
ROLLBACK TO SAVEPOINT before_react;

-- 3. Reacting to your own message notifies nobody and kicks nothing.
DO $$
BEGIN
  DELETE FROM pg_temp.kicks;
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES ('8d175000-0000-0000-0000-000000000021', '8d175000-0000-0000-0000-000000000011',
          '8d175000-0000-0000-0000-0000000000a1', '❤️');
  IF EXISTS (SELECT 1 FROM public.message_notification_outbox
             WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a self-reaction queued a notification';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_temp.kicks) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a self-reaction kicked the worker';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT before_react;

-- 4. A reaction to a deleted message queues nothing and kicks nothing.
DO $$
BEGIN
  UPDATE public.messages SET deleted_at = now() WHERE id = '8d175000-0000-0000-0000-000000000021';
  DELETE FROM pg_temp.kicks;
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES ('8d175000-0000-0000-0000-000000000021', '8d175000-0000-0000-0000-000000000011',
          '8d175000-0000-0000-0000-0000000000b2', '❤️');
  IF EXISTS (SELECT 1 FROM public.message_notification_outbox
             WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction')
     OR EXISTS (SELECT 1 FROM pg_temp.kicks) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reaction to a deleted message was queued or kicked';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT before_react;

-- 5. A failed kick never fails the reaction: the row is still queued (the cron sweeps it).
DO $$
BEGIN
  PERFORM set_config('test.kick_fails', 'on', true);
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES ('8d175000-0000-0000-0000-000000000021', '8d175000-0000-0000-0000-000000000011',
          '8d175000-0000-0000-0000-0000000000b2', '❤️');
  PERFORM set_config('test.kick_fails', 'off', true);
  IF NOT EXISTS (SELECT 1 FROM public.message_notification_outbox
                 WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed kick lost the reaction outbox row';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT before_react;

-- 6. Unconfigured settings: the row is queued, nothing is kicked, nothing fails.
DO $$
BEGIN
  PERFORM set_config('app.settings.supabase_url', '', true);
  DELETE FROM pg_temp.kicks;
  INSERT INTO public.message_reactions (message_id, relationship_id, user_id, emoji)
  VALUES ('8d175000-0000-0000-0000-000000000021', '8d175000-0000-0000-0000-000000000011',
          '8d175000-0000-0000-0000-0000000000b2', '❤️');
  IF NOT EXISTS (SELECT 1 FROM public.message_notification_outbox
                 WHERE message_id = '8d175000-0000-0000-0000-000000000021' AND notification_type = 'message_reaction') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without settings the reaction outbox row was not queued';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_temp.kicks) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kick was sent with no supabase_url configured';
  END IF;
  PERFORM set_config('app.settings.supabase_url', 'https://stub.supabase.co', true);
END $$;
ROLLBACK TO SAVEPOINT before_react;

-- 7. Mutation check: with the kick removed from the trigger (the
-- 20260901140000 body), check 1 is violated.
SAVEPOINT mutate;
CREATE OR REPLACE FUNCTION public.enqueue_reaction_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_message public.messages%ROWTYPE;
BEGIN
  SELECT * INTO v_message FROM public.messages WHERE id = NEW.message_id;
  IF NOT FOUND OR v_message.deleted_at IS NOT NULL OR v_message.sender_id = NEW.user_id THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.message_notification_outbox (
    message_id, relationship_id, recipient_id, sender_id, notification_type, reaction_emoji, reactor_id)
  VALUES (NEW.message_id, NEW.relationship_id, v_message.sender_id, NEW.user_id,
          'message_reaction', NEW.emoji, NEW.user_id)
  ON CONFLICT (recipient_id, message_id, notification_type) DO UPDATE SET
    reaction_emoji = EXCLUDED.reaction_emoji, reactor_id = EXCLUDED.reactor_id,
    state = 'pending', attempts = 0, created_at = now();
  RETURN NEW;
END $$;
DO $$
BEGIN
  BEGIN
    PERFORM pg_temp.check_react_kicks();
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED: a reaction was not kicked%' THEN
      RAISE NOTICE 'mutation check: without the kick a reaction waits for the cron (as expected)';
      RETURN;
    END IF;
    RAISE;
  END;
  RAISE EXCEPTION 'mutation check broken: check 1 passed with the kick removed';
END $$;
ROLLBACK TO SAVEPOINT mutate;

DO $$ BEGIN RAISE NOTICE 'reaction_push_kick_contracts: all held'; END $$;
ROLLBACK;
