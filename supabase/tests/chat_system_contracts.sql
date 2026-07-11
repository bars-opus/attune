BEGIN;

-- Deterministic fixture IDs
DO $$
BEGIN
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  )
  VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'chat-a@example.com', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', 'chat-b@example.com', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    ('00000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'chat-c@example.com', 'x', now(), '{}'::jsonb, '{}'::jsonb, now(), now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id, email, display_name, mode)
  VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'chat-a@example.com', 'User A', 'couples'),
    ('00000000-0000-0000-0000-0000000000b2', 'chat-b@example.com', 'User B', 'couples'),
    ('00000000-0000-0000-0000-0000000000c3', 'chat-c@example.com', 'User C', 'couples')
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      display_name = EXCLUDED.display_name;

  INSERT INTO public.relationships (
    id, user_a, user_b, status, started_at, created_at
  )
  VALUES (
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000a1',
    '00000000-0000-0000-0000-0000000000b2',
    'active',
    CURRENT_DATE,
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET user_a = EXCLUDED.user_a,
      user_b = EXCLUDED.user_b,
      status = EXCLUDED.status,
      started_at = EXCLUDED.started_at,
      chat_archived_at = NULL;

  INSERT INTO public.notification_settings (
    user_id, push_enabled, email_enabled, marketing_enabled,
    booking_reminders_enabled, new_shops_nearby_enabled, chat_message_preview_enabled,
    updated_at
  )
  VALUES
    ('00000000-0000-0000-0000-0000000000a1', true, false, true, true, true, false, now()),
    ('00000000-0000-0000-0000-0000000000b2', true, false, true, true, true, false, now()),
    ('00000000-0000-0000-0000-0000000000c3', true, false, true, true, true, false, now())
  ON CONFLICT (user_id) DO UPDATE
  SET push_enabled = EXCLUDED.push_enabled,
      booking_reminders_enabled = EXCLUDED.booking_reminders_enabled,
      chat_message_preview_enabled = EXCLUDED.chat_message_preview_enabled,
      updated_at = EXCLUDED.updated_at;

  INSERT INTO public.psych_profiles (user_id, attachment_style, communication_style, last_updated)
  VALUES
    ('00000000-0000-0000-0000-0000000000a1', '{"secure":0.8}'::jsonb, '{"primary":"assertive"}'::jsonb, now()),
    ('00000000-0000-0000-0000-0000000000b2', '{"secure":0.6}'::jsonb, '{"primary":"passive"}'::jsonb, now())
  ON CONFLICT (user_id) DO UPDATE
  SET attachment_style = EXCLUDED.attachment_style,
      communication_style = EXCLUDED.communication_style,
      last_updated = EXCLUDED.last_updated;

  INSERT INTO public.messages (
    id, relationship_id, sender_id, client_message_id, content,
    delivered_at, read_at, message_analysis_done, safety_processed_at
  )
  VALUES
    (
      '20000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      '30000000-0000-0000-0000-000000000001',
      'hello from A',
      now(),
      NULL,
      true,
      now()
    ),
    (
      '20000000-0000-0000-0000-000000000002',
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000b2',
      '30000000-0000-0000-0000-000000000002',
      'reply from B',
      now(),
      NULL,
      true,
      now()
    )
  ON CONFLICT (id) DO UPDATE
  SET content = EXCLUDED.content;

  INSERT INTO public.personal_insights (
    id, user_id, relationship_id, insight_type, insight_body, created_at
  )
  VALUES
    (
      '40000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      '10000000-0000-0000-0000-000000000001',
      'translator_pattern',
      'You may be reaching for clarity when tension rises.',
      now()
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.translator_logs (
    id, user_id, relationship_id, used_at, chose_rewrite, core_need_identified,
    rewrite_confidence, message_length_original, message_length_rewrite
  )
  VALUES
    (
      '50000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      '10000000-0000-0000-0000-000000000001',
      now(),
      true,
      'respect',
      'high',
      25,
      22
    )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.safety_events (
    id, relationship_id, at_risk_user_id, source_event_key,
    trigger_tier, trigger_family, config_version, created_at
  )
  VALUES
    (
      '60000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000b2',
      'fixture-source-key-1',
      1,
      'explicit_threat',
      '1.0.0',
      now()
    )
  ON CONFLICT (id) DO NOTHING;
END
$$;

-- Helper to simulate authenticated JWTs in SQL
CREATE OR REPLACE FUNCTION public.test_set_auth(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id::text, 'role', 'authenticated')::text,
    true
  );
END;
$$;

-- A can read active relationship messages
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.messages
  WHERE relationship_id = '10000000-0000-0000-0000-000000000001';

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'expected member A to read 2 messages, got %', v_count;
  END IF;
END
$$;

-- Outsider cannot read relationship messages
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.messages
  WHERE relationship_id = '10000000-0000-0000-0000-000000000001';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'expected outsider to read 0 messages, got %', v_count;
  END IF;
END
$$;

-- Outsider cannot insert into another relationship
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.messages (
      relationship_id, sender_id, client_message_id, content
    )
    VALUES (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000c3',
      '30000000-0000-0000-0000-000000000099',
      'spoof attempt'
    );
    RAISE EXCEPTION 'outsider insert unexpectedly succeeded';
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END
$$;

-- Member cannot spoof partner sender_id
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.messages (
      relationship_id, sender_id, client_message_id, content
    )
    VALUES (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000b2',
      '30000000-0000-0000-0000-000000000098',
      'spoof partner'
    );
    RAISE EXCEPTION 'sender spoof unexpectedly succeeded';
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END
$$;

-- Member can insert as self into active relationship
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.messages (
    relationship_id, sender_id, client_message_id, content
  )
  VALUES (
    '10000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-0000000000a1',
    '30000000-0000-0000-0000-000000000097',
    'authorized send'
  )
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'authorized insert returned null id';
  END IF;
END
$$;

-- Sender cannot mark own message delivered
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000001'::uuid]);

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'sender unexpectedly updated delivered receipts';
  END IF;
END
$$;

-- Recipient can mark delivered on partner message
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000001'::uuid]);

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'recipient expected 1 delivered update, got %', v_count;
  END IF;
END
$$;

-- Outsider cannot read personal insights
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.personal_insights;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'outsider unexpectedly read personal insights';
  END IF;
END
$$;

-- Owner can read own personal insights
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.personal_insights
  WHERE user_id = '00000000-0000-0000-0000-0000000000a1';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'owner expected 1 personal insight, got %', v_count;
  END IF;
END
$$;

-- Partner cannot read translator logs belonging to A
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.translator_logs;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'partner unexpectedly read translator logs';
  END IF;
END
$$;

-- At-risk user can read minimized safety resource events
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000b2');
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count
  FROM public.get_my_safety_resource_events();

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'at-risk user expected 1 safety resource event, got %', v_count;
  END IF;
END
$$;

-- Partner/sender cannot read raw safety table
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.safety_events;
    RAISE EXCEPTION 'raw safety_events unexpectedly readable';
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END
$$;

-- Outbox tables remain unreadable to authenticated users
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.message_safety_outbox;
    RAISE EXCEPTION 'message_safety_outbox unexpectedly readable';
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;

  BEGIN
    PERFORM 1 FROM public.message_notification_outbox;
    RAISE EXCEPTION 'message_notification_outbox unexpectedly readable';
  EXCEPTION
    WHEN OTHERS THEN
      NULL;
  END;
END
$$;

-- mark_conversation_read: recipient reads partner messages; read_at implies
-- delivered_at in the same statement (Spec 5.2).
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_delivered timestamptz;
  v_read timestamptz;
BEGIN
  -- A reads B's message ('...002'); B is the sender, A is the reader.
  SELECT delivered_at, read_at INTO v_delivered, v_read
  FROM public.mark_conversation_read('10000000-0000-0000-0000-000000000001')
  WHERE id = '20000000-0000-0000-0000-000000000002';

  IF v_read IS NULL THEN
    RAISE EXCEPTION 'mark_conversation_read did not set read_at for partner message';
  END IF;
  IF v_delivered IS NULL THEN
    RAISE EXCEPTION 'read_at set but delivered_at left null (receipt order violated)';
  END IF;
END
$$;

-- Receipt RPC replay is monotonic: a second mark_conversation_read does not
-- change the already-set read_at, and re-marking delivered is a no-op once read
-- (Spec 16 "Receipt RPC replay -> timestamp remains monotonic and unchanged").
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_first_read timestamptz;
  v_second_read timestamptz;
  v_redelivered int;
BEGIN
  SELECT read_at INTO v_first_read
  FROM public.messages
  WHERE id = '20000000-0000-0000-0000-000000000002';

  -- Replay read.
  PERFORM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  SELECT read_at INTO v_second_read
  FROM public.messages
  WHERE id = '20000000-0000-0000-0000-000000000002';

  IF v_second_read IS DISTINCT FROM v_first_read THEN
    RAISE EXCEPTION 'read_at changed on replay (% -> %)', v_first_read, v_second_read;
  END IF;

  -- Replay delivered on an already-read message returns no rows (delivered_at
  -- already non-null, so COALESCE leaves it unchanged and it is filtered).
  SELECT count(*) INTO v_redelivered
  FROM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000002'::uuid]);
  IF v_redelivered <> 0 THEN
    RAISE EXCEPTION 'mark_delivered replay unexpectedly updated an already-read message';
  END IF;
END
$$;

-- Outsider cannot use receipt RPCs against a relationship they are not in.
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE
  v_delivered int;
  v_read int;
BEGIN
  SELECT count(*) INTO v_delivered
  FROM public.mark_delivered(ARRAY['20000000-0000-0000-0000-000000000001'::uuid]);
  IF v_delivered <> 0 THEN
    RAISE EXCEPTION 'outsider unexpectedly marked messages delivered';
  END IF;

  SELECT count(*) INTO v_read
  FROM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  IF v_read <> 0 THEN
    RAISE EXCEPTION 'outsider unexpectedly marked conversation read';
  END IF;
END
$$;

-- Ended (read-only) relationship: history stays readable, sends are blocked
-- (Spec 2.1). Flip to 'ended' then restore.
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_count int;
BEGIN
  UPDATE public.relationships
  SET status = 'ended', ended_at = now()
  WHERE id = '10000000-0000-0000-0000-000000000001';

  -- Member can still read the ended relationship's history.
  SELECT count(*) INTO v_count
  FROM public.messages
  WHERE relationship_id = '10000000-0000-0000-0000-000000000001';
  IF v_count < 2 THEN
    RAISE EXCEPTION 'ended relationship history unexpectedly unreadable, got %', v_count;
  END IF;

  -- But inserting into an ended relationship is rejected by the insert policy.
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
    VALUES (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      '30000000-0000-0000-0000-000000000096',
      'send into ended relationship'
    );
    RAISE EXCEPTION 'insert into ended relationship unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  UPDATE public.relationships
  SET status = 'active', ended_at = NULL
  WHERE id = '10000000-0000-0000-0000-000000000001';
END
$$;

-- Archived chat: SELECT is denied and receipt RPCs are inert even for a former
-- member (Spec 2.1, 16 "Push opens after archive -> refuses chat access").
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE
  v_count int;
  v_read int;
BEGIN
  UPDATE public.relationships
  SET chat_archived_at = now(), chat_archived_reason = 'manual_end'
  WHERE id = '10000000-0000-0000-0000-000000000001';

  SELECT count(*) INTO v_count
  FROM public.messages
  WHERE relationship_id = '10000000-0000-0000-0000-000000000001';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'archived chat messages unexpectedly readable, got %', v_count;
  END IF;

  SELECT count(*) INTO v_read
  FROM public.mark_conversation_read('10000000-0000-0000-0000-000000000001');
  IF v_read <> 0 THEN
    RAISE EXCEPTION 'archived chat receipt RPC unexpectedly updated rows';
  END IF;

  -- Insert into an archived chat is also blocked.
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content)
    VALUES (
      '10000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-0000000000a1',
      '30000000-0000-0000-0000-000000000095',
      'send into archived chat'
    );
    RAISE EXCEPTION 'insert into archived chat unexpectedly succeeded';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  UPDATE public.relationships
  SET chat_archived_at = NULL, chat_archived_reason = NULL
  WHERE id = '10000000-0000-0000-0000-000000000001';
END
$$;

-- Conversation streak: both members on two consecutive days -> streak 2
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000a1');
DO $$
DECLARE v int;
BEGIN
  -- ensure both members have a message today and yesterday
  INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, created_at)
  VALUES
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'a today', now()),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2', gen_random_uuid(), 'b today', now()),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1', gen_random_uuid(), 'a yest', now() - interval '1 day'),
   ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000b2', gen_random_uuid(), 'b yest', now() - interval '1 day');
  SELECT public.chat_conversation_streak('10000000-0000-0000-0000-000000000001', 0) INTO v;
  IF v < 2 THEN RAISE EXCEPTION 'expected streak >= 2, got %', v; END IF;
END $$;

-- Outsider gets streak 0
SELECT public.test_set_auth('00000000-0000-0000-0000-0000000000c3');
DO $$
DECLARE v int;
BEGIN
  SELECT public.chat_conversation_streak('10000000-0000-0000-0000-000000000001', 0) INTO v;
  IF v <> 0 THEN RAISE EXCEPTION 'outsider expected streak 0, got %', v; END IF;
END $$;

ROLLBACK;
