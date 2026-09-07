-- This or That authoritative answer and source-selection contracts.

BEGIN;

DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-00000000a701';
  b uuid := '00000000-0000-0000-0000-00000000b702';
  c uuid := '00000000-0000-0000-0000-00000000c703';
  d uuid := '00000000-0000-0000-0000-00000000d704';
  e uuid := '00000000-0000-0000-0000-00000000e705';
  rel uuid := '10000000-0000-0000-0000-00000000a701';
  rel_lifecycle uuid := '10000000-0000-0000-0000-00000000a711';
  rel_reverse uuid := '10000000-0000-0000-0000-00000000a712';
  session uuid := '20000000-0000-0000-0000-00000000a701';
  q1 uuid;
  q2 uuid;
  q3 uuid;
BEGIN
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (a,'authenticated','authenticated','tot-a@example.test','x',now(),'{}','{}',now(),now()),
    (b,'authenticated','authenticated','tot-b@example.test','x',now(),'{}','{}',now(),now()),
    (c,'authenticated','authenticated','tot-c@example.test','x',now(),'{}','{}',now(),now()),
    (d,'authenticated','authenticated','tot-d@example.test','x',now(),'{}','{}',now(),now()),
    (e,'authenticated','authenticated','tot-e@example.test','x',now(),'{}','{}',now(),now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users(id, phone, display_name, mode) VALUES
    (a,'+233290000701','TOT A','couples'),
    (b,'+233290000702','TOT B','couples'),
    (c,'+233290000703','TOT C','couples'),
    (d,'+233290000704','TOT D','couples'),
    (e,'+233290000705','TOT E','couples')
  ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

  INSERT INTO public.relationships(id, user_a, user_b, status, started_at, created_at)
  VALUES (rel, a, b, 'active', CURRENT_DATE, now())
  ON CONFLICT (id) DO UPDATE
    SET user_a = EXCLUDED.user_a,
        user_b = EXCLUDED.user_b,
        status = EXCLUDED.status;

  INSERT INTO public.relationships(
    id, user_a, user_b, status, started_at, created_at
  ) VALUES
    (rel_lifecycle, d, e, 'active', CURRENT_DATE, now()),
    (rel_reverse, d, e, 'active', CURRENT_DATE, now())
  ON CONFLICT (id) DO UPDATE
    SET user_a = EXCLUDED.user_a,
        user_b = EXCLUDED.user_b,
        status = EXCLUDED.status;

  SELECT id INTO q1 FROM public.game_questions
  WHERE game_type = 'this_or_that' AND tone = 'connecting'
  ORDER BY created_at LIMIT 1;
  SELECT id INTO q2 FROM public.game_questions
  WHERE game_type = 'this_or_that' AND tone = 'connecting' AND id <> q1
  ORDER BY created_at LIMIT 1;
  SELECT id INTO q3 FROM public.game_questions
  WHERE game_type = 'this_or_that' AND tone = 'connecting' AND id NOT IN (q1, q2)
  ORDER BY created_at LIMIT 1;

  INSERT INTO public.game_sessions(
    id, relationship_id, initiator_id, game_type, tone, status,
    total_rounds, current_round
  ) VALUES (
    session, rel, a, 'this_or_that', 'connecting', 'active', 3, 1
  );

  INSERT INTO public.game_session_rounds(
    id, session_id, round_number, question_id
  ) VALUES
    ('30000000-0000-0000-0000-00000000a701', session, 1, q1),
    ('30000000-0000-0000-0000-00000000a702', session, 2, q2),
    ('30000000-0000-0000-0000-00000000a703', session, 3, q3);

  INSERT INTO public.custom_this_or_that_questions(
    id, user_id, question_text, option_a, option_b, tone, is_private
  ) VALUES (
    '40000000-0000-0000-0000-00000000b702', b,
    'Tea on the balcony or music in the kitchen?',
    'Balcony tea', 'Kitchen music', 'connecting', false
  );
END $$;

CREATE OR REPLACE FUNCTION public.test_set_tot_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text,
    true
  );
END;
$$;

RESET ROLE;
DO $$
BEGIN
  IF has_function_privilege(
    'anon',
    'public.submit_this_or_that_answer(uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon can submit a This or That answer';
  END IF;
  IF has_function_privilege(
    'anon',
    'public.choose_this_or_that_next_question(uuid,integer,text,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon can choose a This or That question';
  END IF;
  IF has_function_privilege(
    'anon',
    'public.create_this_or_that_session(uuid,text,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.accept_this_or_that_session(uuid,boolean,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.complete_this_or_that_session(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon can mutate the This or That lifecycle';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'this_or_that_round_answers'
  ) THEN
    RAISE EXCEPTION 'private answer table unexpectedly has a client RLS policy';
  END IF;
END $$;

-- Full lifecycle: creation is idempotent, only the invited partner can
-- accept, the deck appears atomically, and completion derives its own score.
SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000d704');
SELECT public.create_this_or_that_session(
  '10000000-0000-0000-0000-00000000a711',
  'connecting',
  'tot-lifecycle-key'
);
SELECT public.create_this_or_that_session(
  '10000000-0000-0000-0000-00000000a711',
  'connecting',
  'tot-lifecycle-key'
);
DO $$
DECLARE
  rejected boolean := false;
  created_session_id uuid;
BEGIN
  SELECT session_id INTO created_session_id
  FROM public.session_idempotency_keys
  WHERE key = 'tot-lifecycle-key';

  IF created_session_id IS NULL OR (
    SELECT count(*) FROM public.game_sessions
    WHERE relationship_id = '10000000-0000-0000-0000-00000000a711'
      AND game_type = 'this_or_that'
      AND status IN ('invited', 'active')
  ) <> 1 THEN
    RAISE EXCEPTION 'idempotent creation made an invalid session count';
  END IF;

  BEGIN
    PERFORM public.accept_this_or_that_session(
      created_session_id, false, NULL
    );
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'initiator accepted their own invitation';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000e705');
SELECT public.accept_this_or_that_session(
  (SELECT session_id FROM public.session_idempotency_keys
   WHERE key = 'tot-lifecycle-key'),
  false,
  NULL
);
DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-lifecycle-key'
  );
  rejected boolean := false;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = created_session_id
      AND status = 'active'
      AND current_round = 1
  ) OR (
    SELECT count(*) FROM public.game_session_rounds
    WHERE session_id = created_session_id
  ) <> 10 THEN
    RAISE EXCEPTION 'acceptance did not atomically build a ten-round deck';
  END IF;

  BEGIN
    PERFORM public.complete_this_or_that_session(created_session_id);
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'an incomplete session was marked completed';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000d704');
DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-lifecycle-key'
  );
BEGIN
  PERFORM public.submit_this_or_that_answer(
    (SELECT id FROM public.game_session_rounds
     WHERE session_id = created_session_id AND round_number = 1),
    'a'
  );
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000e705');
DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-lifecycle-key'
  );
BEGIN
  PERFORM public.submit_this_or_that_answer(
    (SELECT id FROM public.game_session_rounds
     WHERE session_id = created_session_id AND round_number = 1),
    'a'
  );
END $$;
RESET ROLE;

-- Completion remains server-derived. Prepare the rest of this synthetic deck
-- as the database owner so the lifecycle assertion stays independent of the
-- alternating next-question contract exercised below.
UPDATE public.game_session_rounds
   SET answer_a = 'a',
       answer_b = 'a',
       answer_a_submitted_at = now(),
       answer_b_submitted_at = now(),
       both_answered = true,
       reveal_triggered_at = now()
 WHERE session_id = (
   SELECT session_id FROM public.session_idempotency_keys
   WHERE key = 'tot-lifecycle-key'
 );

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000e705');
SELECT public.complete_this_or_that_session(
  (SELECT session_id FROM public.session_idempotency_keys
   WHERE key = 'tot-lifecycle-key')
);
RESET ROLE;

DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-lifecycle-key'
  );
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = created_session_id
      AND status = 'completed'
      AND total_rounds_completed = 10
      AND match_count = 10
      AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'completion did not derive the authoritative score';
  END IF;
END $$;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000d704');
SELECT public.hide_this_or_that_session(
  (SELECT session_id FROM public.session_idempotency_keys
   WHERE key = 'tot-lifecycle-key')
);
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = (
      SELECT session_id FROM public.session_idempotency_keys
      WHERE key = 'tot-lifecycle-key'
    )
      AND '00000000-0000-0000-0000-00000000d704'::uuid =
          ANY(hidden_by_user_ids)
  ) THEN
    RAISE EXCEPTION 'history hide did not record the authenticated user';
  END IF;
END $$;

-- Consent flags follow relationship membership even when partner B starts
-- the invitation. The accepted intimate deck must preserve both consents and
-- contain a meaningful number of level-4 prompts.
SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000e705');
SELECT public.create_this_or_that_session(
  '10000000-0000-0000-0000-00000000a712',
  'intimate',
  'tot-reverse-intimate-key'
);
RESET ROLE;

DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-reverse-intimate-key'
  );
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = created_session_id
      AND intimate_consent_a = false
      AND intimate_consent_b = true
  ) THEN
    RAISE EXCEPTION 'partner B initiation stored consent under the wrong user';
  END IF;
END $$;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000d704');
SELECT public.accept_this_or_that_session(
  (SELECT session_id FROM public.session_idempotency_keys
   WHERE key = 'tot-reverse-intimate-key'),
  true,
  NULL
);
RESET ROLE;

DO $$
DECLARE
  created_session_id uuid := (
    SELECT session_id FROM public.session_idempotency_keys
    WHERE key = 'tot-reverse-intimate-key'
  );
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = created_session_id
      AND intimate_consent_a = true
      AND intimate_consent_b = true
  ) THEN
    RAISE EXCEPTION 'accepted intimate session did not preserve both consents';
  END IF;
  IF (
    SELECT count(*)
    FROM public.game_session_rounds round_row
    JOIN public.game_questions question ON question.id = round_row.question_id
    WHERE round_row.session_id = created_session_id
      AND question.tone_level = 4
  ) < 5 THEN
    RAISE EXCEPTION 'intimate deck contains fewer than five level-4 prompts';
  END IF;
END $$;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000a701');
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a701',
  'a'
);
-- A player may change their private pick until the partner answers.
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a701',
  'b'
);
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.this_or_that_round_answers
    WHERE round_id = '30000000-0000-0000-0000-00000000a701'
      AND user_id = '00000000-0000-0000-0000-00000000a701'
      AND choice = 'b'
  ) OR EXISTS (
    SELECT 1 FROM public.game_session_rounds
    WHERE id = '30000000-0000-0000-0000-00000000a701'
      AND (answer_a IS NOT NULL OR answer_b IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'unrevealed pick was not kept exclusively private';
  END IF;
END $$;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000a701');
DO $$
DECLARE
  rejected boolean := false;
BEGIN
  BEGIN
    UPDATE public.game_session_rounds
       SET answer_a = 'a'
     WHERE id = '30000000-0000-0000-0000-00000000a701';
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'authenticated client directly changed a game round';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000a701');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.this_or_that_round_answers) THEN
    RAISE EXCEPTION 'authenticated client can read the private answer table';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000c703');
DO $$
DECLARE
  rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.submit_this_or_that_answer(
      '30000000-0000-0000-0000-00000000a701',
      'a'
    );
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'outsider submitted an answer';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a701',
  'b'
);
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_session_rounds
    WHERE id = '30000000-0000-0000-0000-00000000a701'
      AND both_answered = true
      AND reveal_triggered_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'second answer did not reveal the round';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.game_questions_seen
    WHERE relationship_id = '10000000-0000-0000-0000-00000000a701'
      AND question_id = (
        SELECT question_id FROM public.game_session_rounds
        WHERE id = '30000000-0000-0000-0000-00000000a701'
      )
  ) THEN
    RAISE EXCEPTION 'completed preset question was not marked seen';
  END IF;
END $$;

-- Round 2 belongs to partner A. Partner B cannot choose it.
SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
DO $$
DECLARE
  rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.choose_this_or_that_next_question(
      '20000000-0000-0000-0000-00000000a701', 2, 'preset', NULL
    );
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'partner B chose partner A''s round';
  END IF;
END $$;
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000a701');
SELECT public.choose_this_or_that_next_question(
  '20000000-0000-0000-0000-00000000a701', 2, 'preset', NULL
);
RESET ROLE;

-- Partner B answers first. Partner A may see that an answer exists, but the
-- private choice itself must not reach A's client before the reveal.
SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a702', 'b'
);
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000a701');
DO $$
DECLARE
  state jsonb;
BEGIN
  SELECT value INTO state
  FROM public.this_or_that_round_state(
    '20000000-0000-0000-0000-00000000a701'
  ) AS state_rows(value)
  WHERE (value->>'round_number')::integer = 2;

  IF state->>'answer_b' IS NOT NULL THEN
    RAISE EXCEPTION 'partner B''s private pick leaked before reveal';
  END IF;
  IF COALESCE((state->>'has_answer_b')::boolean, false) IS NOT true THEN
    RAISE EXCEPTION 'partner answer-presence signal was not exposed';
  END IF;
END $$;
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a702', 'a'
);
RESET ROLE;

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
SELECT public.choose_this_or_that_next_question(
  '20000000-0000-0000-0000-00000000a701',
  3,
  'custom',
  '00000000-0000-0000-0000-00000000b702'
);
RESET ROLE;

-- Reminders are available only after the answering partner has waited, target
-- the unanswered partner, and cannot be repeated inside the cooldown window.
SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
SELECT public.submit_this_or_that_answer(
  '30000000-0000-0000-0000-00000000a703',
  'a'
);
RESET ROLE;

UPDATE public.this_or_that_round_answers
   SET submitted_at = now() - interval '3 hours'
 WHERE round_id = '30000000-0000-0000-0000-00000000a703'
   AND user_id = '00000000-0000-0000-0000-00000000b702';

SELECT public.test_set_tot_auth('00000000-0000-0000-0000-00000000b702');
DO $$
DECLARE
  result jsonb;
  rejected boolean := false;
BEGIN
  result := public.request_this_or_that_reminder(
    '20000000-0000-0000-0000-00000000a701'
  );
  IF result->>'recipient_id' <> '00000000-0000-0000-0000-00000000a701'
     OR NOT EXISTS (
       SELECT 1 FROM public.game_sessions
       WHERE id = '20000000-0000-0000-0000-00000000a701'
         AND remind_last_sent_at IS NOT NULL
     ) THEN
    RAISE EXCEPTION 'reminder did not target the unanswered partner';
  END IF;

  BEGIN
    PERFORM public.request_this_or_that_reminder(
      '20000000-0000-0000-0000-00000000a701'
    );
  EXCEPTION WHEN OTHERS THEN
    rejected := true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'reminder cooldown was not enforced';
  END IF;
END $$;
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.game_session_rounds
    WHERE id = '30000000-0000-0000-0000-00000000a703'
      AND question_id IS NULL
      AND is_custom = true
      AND custom_question_data->>'custom_question_id' =
          '40000000-0000-0000-0000-00000000b702'
  ) THEN
    RAISE EXCEPTION 'custom deck did not prepare an FK-safe custom round';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = '20000000-0000-0000-0000-00000000a701'
      AND current_round = 3
      AND total_rounds_completed = 2
      AND match_count = 1
  ) THEN
    RAISE EXCEPTION 'server did not derive session progress';
  END IF;
END $$;

-- Invitations and stalled rounds use This or That's shorter lifecycle
-- windows. A fresh active session must survive the same sweep.
DO $$
DECLARE
  stale_invite uuid := '20000000-0000-0000-0000-00000000a721';
  stale_active uuid := '20000000-0000-0000-0000-00000000a722';
  fresh_active uuid := '20000000-0000-0000-0000-00000000a723';
  swept integer;
BEGIN
  INSERT INTO public.game_sessions(
    id, relationship_id, initiator_id, game_type, tone, status,
    total_rounds, current_round, started_at, created_at
  ) VALUES
    (
      stale_invite,
      '10000000-0000-0000-0000-00000000a701',
      '00000000-0000-0000-0000-00000000a701',
      'this_or_that', 'connecting', 'invited', 10, 0, NULL,
      now() - interval '49 hours'
    ),
    (
      stale_active,
      '10000000-0000-0000-0000-00000000a701',
      '00000000-0000-0000-0000-00000000a701',
      'this_or_that', 'connecting', 'active', 10, 1,
      now() - interval '25 hours', now() - interval '25 hours'
    ),
    (
      fresh_active,
      '10000000-0000-0000-0000-00000000a701',
      '00000000-0000-0000-0000-00000000a701',
      'this_or_that', 'connecting', 'active', 10, 1,
      now(), now()
    );

  swept := public.expire_stale_session_games();

  IF swept < 2 THEN
    RAISE EXCEPTION 'stale-session sweep reported only % rows', swept;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = stale_invite
      AND status = 'abandoned'
      AND abandon_reason = 'invite_expired'
  ) THEN
    RAISE EXCEPTION '49-hour This or That invitation was not expired';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = stale_active
      AND status = 'abandoned'
      AND abandon_reason = 'inactivity'
  ) THEN
    RAISE EXCEPTION '25-hour stalled This or That round was not abandoned';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.game_sessions
    WHERE id = fresh_active AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'fresh This or That session was swept';
  END IF;
END $$;

ROLLBACK;
