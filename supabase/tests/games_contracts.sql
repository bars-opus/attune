-- Games contract tests — RLS + RPC authorization proof (GAMES-1/2/3).
--
-- Runs inside BEGIN/ROLLBACK. Verifies the launch-hardening migration closes:
--   GAMES-1: a single reporter cannot hide a custom question; hiding requires a
--            report THRESHOLD (>= 2 distinct reporters).
--   GAMES-2: usage/community counter RPCs reject an unauthenticated caller.
--   GAMES-3: every Games RPC is revoked from anon and granted to authenticated.
--   Round-complete + skip RPCs enforce relationship membership.
--
-- Accounts: A (a1) + B (b2) are an active couple with a game session and one
-- round. C (c3) is an outsider. D (d4) owns a custom question and also acts as
-- the second reporter.

BEGIN;

DO $$
DECLARE
  a uuid := '00000000-0000-0000-0000-0000000000a1';
  b uuid := '00000000-0000-0000-0000-0000000000b2';
  c uuid := '00000000-0000-0000-0000-0000000000c3';
  d uuid := '00000000-0000-0000-0000-0000000000d4';
  v_rel uuid := '10000000-0000-0000-0000-0000000000a1';
BEGIN
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (a,'authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now()),
    (b,'authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now()),
    (c,'authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now()),
    (d,'authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now())
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users(id, phone,display_name,mode) VALUES
    (a,'+233200000005','User A','couples'),
    (b,'+233200000006','User B','couples'),
    (c,'+233200000007','User C','couples'),
    (d,'+233200000008','User D','couples')
  ON CONFLICT (id) DO UPDATE SET display_name=EXCLUDED.display_name;

  INSERT INTO public.relationships(id,user_a,user_b,status,started_at,created_at)
  VALUES (v_rel,a,b,'active',CURRENT_DATE,now())
  ON CONFLICT (id) DO UPDATE SET user_a=EXCLUDED.user_a,user_b=EXCLUDED.user_b,status=EXCLUDED.status;

  -- An active This-or-That session with one round both answered-ready.
  INSERT INTO public.game_sessions(id,relationship_id,initiator_id,game_type,tone,status,total_rounds,current_round)
  VALUES ('20000000-0000-0000-0000-0000000000a1',v_rel,a,'this_or_that','connecting','active',5,1)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.game_session_rounds(id,session_id,round_number,answer_a,answer_b,both_answered)
  VALUES ('30000000-0000-0000-0000-0000000000a1','20000000-0000-0000-0000-0000000000a1',1,'a','b',false)
  ON CONFLICT (id) DO NOTHING;

  -- A community-shared custom question owned by D (the report target).
  INSERT INTO public.custom_this_or_that_questions(
    id,user_id,question_text,option_a,option_b,tone,is_private,shared_to_community
  ) VALUES (
    '40000000-0000-0000-0000-0000000000d4',d,'Q?','A','B','connecting',false,true
  ) ON CONFLICT (id) DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.test_set_games_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub',p_user_id::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',json_build_object('sub',p_user_id,'role','authenticated')::text,true);
END;
$$;

-- ---------------------------------------------------------------------------
-- 1. GAMES-3: RPCs revoked from anon, granted to authenticated.
-- ---------------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.report_custom_question(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute report_custom_question';
  END IF;
  IF has_function_privilege('anon','public.increment_custom_question_usage(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute increment_custom_question_usage';
  END IF;
  IF has_function_privilege('anon','public.mark_round_complete(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute mark_round_complete';
  END IF;
  IF has_function_privilege('anon','public.increment_skip_count(uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute increment_skip_count';
  END IF;
  IF NOT has_function_privilege('authenticated','public.report_custom_question(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute report_custom_question';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. GAMES-1: a single reporter cannot hide a question; a second distinct
--    reporter crosses the threshold and hides it.
-- ---------------------------------------------------------------------------
SELECT public.test_set_games_auth('00000000-0000-0000-0000-0000000000a1'); -- reporter 1
DO $$ DECLARE v_hidden boolean; BEGIN
  PERFORM public.report_custom_question('40000000-0000-0000-0000-0000000000d4','inappropriate');
  RESET ROLE;
  SELECT hidden_for_review INTO v_hidden FROM public.custom_this_or_that_questions
  WHERE id='40000000-0000-0000-0000-0000000000d4';
  IF v_hidden THEN RAISE EXCEPTION 'GAMES-1: one report hid the question (must need threshold)'; END IF;
END $$;

-- Same reporter again = idempotent, still one distinct reporter, still not hidden.
SELECT public.test_set_games_auth('00000000-0000-0000-0000-0000000000a1');
DO $$ DECLARE v_hidden boolean; v_reports int; BEGIN
  PERFORM public.report_custom_question('40000000-0000-0000-0000-0000000000d4','inappropriate');
  RESET ROLE;
  SELECT count(*) INTO v_reports FROM public.custom_question_reports
  WHERE question_id='40000000-0000-0000-0000-0000000000d4';
  IF v_reports <> 1 THEN RAISE EXCEPTION 'GAMES-1: duplicate report from same reporter (got % rows)', v_reports; END IF;
  SELECT hidden_for_review INTO v_hidden FROM public.custom_this_or_that_questions
  WHERE id='40000000-0000-0000-0000-0000000000d4';
  IF v_hidden THEN RAISE EXCEPTION 'GAMES-1: same reporter twice hid the question'; END IF;
END $$;

-- A second DISTINCT reporter crosses the threshold → hidden.
SELECT public.test_set_games_auth('00000000-0000-0000-0000-0000000000b2'); -- reporter 2
DO $$ DECLARE v_hidden boolean; BEGIN
  PERFORM public.report_custom_question('40000000-0000-0000-0000-0000000000d4','offensive');
  RESET ROLE;
  SELECT hidden_for_review INTO v_hidden FROM public.custom_this_or_that_questions
  WHERE id='40000000-0000-0000-0000-0000000000d4';
  IF NOT v_hidden THEN RAISE EXCEPTION 'GAMES-1: two distinct reporters did not hide the question'; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. GAMES-2: counter RPCs reject an unauthenticated caller.
-- ---------------------------------------------------------------------------
RESET ROLE;  -- superuser, but auth.uid() is NULL here (no JWT claim set)
DO $$ DECLARE v_raised boolean := false; BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','',true);
  BEGIN
    PERFORM public.increment_custom_question_usage('40000000-0000-0000-0000-0000000000d4');
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'GAMES-2: usage counter accepted an unauthenticated caller'; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. Round-complete + skip enforce membership: outsider C cannot complete the
--    A/B round, and cannot skip in the A/B session.
-- ---------------------------------------------------------------------------
SELECT public.test_set_games_auth('00000000-0000-0000-0000-0000000000c3'); -- outsider
DO $$ DECLARE v_ok boolean; v_raised boolean := false; BEGIN
  -- mark_round_complete returns false for a non-member (no row updated).
  SELECT public.mark_this_or_that_round_complete('30000000-0000-0000-0000-0000000000a1') INTO v_ok;
  IF v_ok THEN RAISE EXCEPTION 'outsider completed a round they are not a member of'; END IF;
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM public.game_session_rounds
            WHERE id='30000000-0000-0000-0000-0000000000a1' AND both_answered=true) THEN
    RAISE EXCEPTION 'outsider round-complete mutated the round';
  END IF;

  -- increment_skip_count for another user id must be forbidden.
  PERFORM public.test_set_games_auth('00000000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.increment_skip_count(
      '20000000-0000-0000-0000-0000000000a1',
      '00000000-0000-0000-0000-0000000000a1',  -- forging A's user id
      'skips_used_a');
  EXCEPTION WHEN OTHERS THEN v_raised := true;
  END;
  IF NOT v_raised THEN RAISE EXCEPTION 'outsider forged a skip for another user'; END IF;
END $$;

RESET ROLE;

-- A game invite notifies the partner.
--
-- Sessions were created with status 'invited' and nothing announced them:
-- no push, no realtime, no trigger. The invite sat silent until the
-- partner happened to open the Games hub.
DO $$
DECLARE
  v_session uuid;
  v_notifications int;
  v_meta jsonb;
BEGIN
  INSERT INTO public.game_sessions
    (relationship_id, initiator_id, game_type, status, total_rounds)
  VALUES ('10000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-0000000000a1',
          'mirror', 'invited', 8)
  RETURNING id INTO v_session;

  SELECT count(*) INTO v_notifications
  FROM public.scheduled_notifications
  WHERE (metadata->>'session_id')::uuid = v_session;

  SELECT metadata INTO v_meta
  FROM public.scheduled_notifications
  WHERE (metadata->>'session_id')::uuid = v_session
  LIMIT 1;

  IF v_notifications <> 1 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: an invite queued % notifications, expected 1',
      v_notifications;
  END IF;

  -- The PARTNER, never the initiator.
  IF (SELECT user_id FROM public.scheduled_notifications
      WHERE (metadata->>'session_id')::uuid = v_session)
     <> '00000000-0000-0000-0000-0000000000b2' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the invite notified the wrong user';
  END IF;

  -- Named, not raw: "mirror" in a push is a database value on a lock
  -- screen.
  IF v_meta->>'body' NOT LIKE 'Mirror%' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the push names the raw game_type (body: %)',
      v_meta->>'body';
  END IF;

  DELETE FROM public.scheduled_notifications
  WHERE (metadata->>'session_id')::uuid = v_session;
  DELETE FROM public.game_sessions WHERE id = v_session;
END $$;

-- Accepting an invite must not notify again.
DO $$
DECLARE v_session uuid; v_count int;
BEGIN
  INSERT INTO public.game_sessions
    (relationship_id, initiator_id, game_type, status, total_rounds)
  VALUES ('10000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-0000000000a1',
          'scenario', 'active', 8)
  RETURNING id INTO v_session;

  SELECT count(*) INTO v_count FROM public.scheduled_notifications
  WHERE (metadata->>'session_id')::uuid = v_session;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a non-invited session queued % notifications',
      v_count;
  END IF;

  DELETE FROM public.game_sessions WHERE id = v_session;
END $$;

-- Every RPC the client calls must exist.
--
-- PaintBallService calls five paint_ball_* functions. The launch
-- migration created only get_paint_ball_session_state and
-- expire_paint_ball_sessions, so all five WRITE-path functions were
-- missing: creating, accepting, declining, firing a shot and resolving a
-- penalty each failed at runtime. The game is offered in the hub and is
-- tappable, so this was reachable, and no test caught it because nothing
-- checked that a called function exists.
DO $$
DECLARE
  v_missing text;
BEGIN
  SELECT string_agg(expected, ', ' ORDER BY expected) INTO v_missing
  FROM unnest(ARRAY[
    'paint_ball_create_session',
    'paint_ball_accept_session',
    'paint_ball_decline_session',
    'paint_ball_fire_shot',
    'paint_ball_resolve_penalty',
    'get_paint_ball_session_state',
    'expire_paint_ball_sessions'
  ]) AS expected
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = expected
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: PaintBallService calls functions that do not exist: %',
      v_missing;
  END IF;
END $$;

-- Truth answers are queued for the safety scan (TRUTH_OR_DARE.md §4.4).
--
-- SafetyTriggerService.checkTruthAnswer was a stub returning false, called
-- from nowhere, and safety_triggered was read by the client but never
-- written. A free-text field in an intimate game had no safety net.
RESET ROLE;

DO $$
DECLARE
  v_session uuid;
  v_round uuid;
  v_queued int;
  v_answering uuid;
BEGIN
  INSERT INTO public.game_sessions
    (relationship_id, initiator_id, game_type, status, total_rounds)
  VALUES ('10000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-0000000000a1',
          'truth_or_dare', 'active', 8)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds
    (session_id, round_number, chosen_type)
  VALUES (v_session, 1, 'truth')
  RETURNING id INTO v_round;

  -- Nothing queued yet: the round exists but carries no answer.
  SELECT count(*) INTO v_queued
  FROM public.truth_answer_safety_outbox WHERE round_id = v_round;
  IF v_queued <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: an empty round queued a scan';
  END IF;

  -- Partner A answers.
  UPDATE public.game_session_rounds
     SET answer_a = 'something a partner wrote',
         answer_b = '__revealed__'
   WHERE id = v_round;

  SELECT count(*) INTO v_queued
  FROM public.truth_answer_safety_outbox WHERE round_id = v_round;

  SELECT answering_user_id INTO v_answering
  FROM public.truth_answer_safety_outbox WHERE round_id = v_round LIMIT 1;

  IF v_queued <> 1 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a truth answer queued % scans, expected 1', v_queued;
  END IF;

  -- The ANSWERING partner is recorded, so the worker can send resources to
  -- the other one — the reader.
  IF v_answering <> '00000000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the wrong partner was recorded as answering';
  END IF;

  DELETE FROM public.game_sessions WHERE id = v_session;
END $$;

-- A dare has no free text and must not be queued.
DO $$
DECLARE v_session uuid; v_round uuid; v_queued int;
BEGIN
  INSERT INTO public.game_sessions
    (relationship_id, initiator_id, game_type, status, total_rounds)
  VALUES ('10000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-0000000000a1',
          'truth_or_dare', 'active', 8)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds
    (session_id, round_number, chosen_type)
  VALUES (v_session, 1, 'dare')
  RETURNING id INTO v_round;

  UPDATE public.game_session_rounds
     SET answer_a = 'did the dare' WHERE id = v_round;

  SELECT count(*) INTO v_queued
  FROM public.truth_answer_safety_outbox WHERE round_id = v_round;
  IF v_queued <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dare queued a safety scan';
  END IF;

  DELETE FROM public.game_sessions WHERE id = v_session;
END $$;

-- The reveal sentinel is not an answer and must not be scanned.
DO $$
DECLARE v_session uuid; v_round uuid; v_queued int;
BEGIN
  INSERT INTO public.game_sessions
    (relationship_id, initiator_id, game_type, status, total_rounds)
  VALUES ('10000000-0000-0000-0000-0000000000a1',
          '00000000-0000-0000-0000-0000000000a1',
          'truth_or_dare', 'active', 8)
  RETURNING id INTO v_session;

  INSERT INTO public.game_session_rounds
    (session_id, round_number, chosen_type)
  VALUES (v_session, 1, 'truth')
  RETURNING id INTO v_round;

  UPDATE public.game_session_rounds
     SET answer_b = '__revealed__' WHERE id = v_round;

  SELECT count(*) INTO v_queued
  FROM public.truth_answer_safety_outbox WHERE round_id = v_round;
  IF v_queued <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the reveal sentinel was queued as an answer';
  END IF;

  DELETE FROM public.game_sessions WHERE id = v_session;
END $$;

-- The outbox names rounds across every relationship: server-side only.
DO $$
DECLARE v_rls boolean; v_policies int;
BEGIN
  SELECT relrowsecurity INTO v_rls
  FROM pg_class WHERE relname = 'truth_answer_safety_outbox';
  SELECT count(*) INTO v_policies
  FROM pg_policies WHERE tablename = 'truth_answer_safety_outbox';

  IF NOT COALESCE(v_rls, false) OR v_policies <> 0 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: the truth-answer outbox is reachable by clients';
  END IF;
END $$;

-- And something must drain it: a queue nobody reads is worse than no
-- safety net, because it looks implemented.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'drain-truth-answer-safety'
  ) THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: nothing drains the truth-answer safety outbox';
  END IF;
END $$;

-- A full Paint Ball game, played through the RPCs (PAINT_BALL §10).
DO $$
DECLARE
  v_session uuid;
  v_result jsonb;
  a uuid := '00000000-0000-0000-0000-0000000000a1';
  b uuid := '00000000-0000-0000-0000-0000000000b2';
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);

  v_session := public.paint_ball_create_session(
    '10000000-0000-0000-0000-0000000000a1', 'playful', 'pb-key-1', true);

  -- §10.1: a repeated key returns the SAME session, never a second one.
  IF public.paint_ball_create_session(
       '10000000-0000-0000-0000-0000000000a1', 'playful', 'pb-key-1', true)
     <> v_session THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: idempotency key created a second session';
  END IF;

  IF (SELECT lives_a FROM public.game_sessions WHERE id = v_session) <> 3
     OR (SELECT lives_b FROM public.game_sessions WHERE id = v_session) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new game did not start with 3 lives each';
  END IF;

  -- §10.2: the initiator may NOT accept their own invite.
  BEGIN
    PERFORM public.paint_ball_accept_session(v_session);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the initiator accepted their own invite';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  -- The partner accepts; the INITIATOR fires first.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_accept_session(v_session);

  IF (SELECT current_turn_user_id FROM public.game_sessions WHERE id = v_session)
     <> a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the initiator does not fire first';
  END IF;

  -- §10.3 step 2: firing out of turn is refused.
  BEGIN
    PERFORM public.paint_ball_fire_shot(v_session, 1, true, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a partner fired out of turn';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- A hits B three times, alternating turns back each round.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_fire_shot(v_session, 1, true, NULL);

  IF (v_result->>'lives_b')::int <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit did not cost a life (lives_b=%)',
      v_result->>'lives_b';
  END IF;
  IF (v_result->>'knockout')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: knockout declared at 2 lives';
  END IF;

  -- §10.3 step 4: replaying round 1 must not decrement again.
  v_result := public.paint_ball_fire_shot(v_session, 1, true, NULL);
  IF (v_result->>'lives_b')::int <> 2 THEN
    RAISE EXCEPTION
      'CONTRACT VIOLATED: a replayed shot decremented twice (lives_b=%)',
      v_result->>'lives_b';
  END IF;

  -- B fires and misses; no life lost.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_fire_shot(v_session, 2, false, NULL);
  IF (v_result->>'lives_a')::int <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a miss cost a life';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_fire_shot(v_session, 3, true, NULL);

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_fire_shot(v_session, 4, false, NULL);

  -- The knockout blow.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_result := public.paint_ball_fire_shot(v_session, 5, true, NULL);

  IF (v_result->>'lives_b')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the third hit did not reach 0 lives';
  END IF;
  IF NOT (v_result->>'knockout')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 0 lives did not trigger a knockout';
  END IF;
  IF (SELECT winner_user_id FROM public.game_sessions WHERE id = v_session) <> a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shooter did not win';
  END IF;
  IF (SELECT penalty_status FROM public.game_sessions WHERE id = v_session)
     <> 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no penalty was queued on knockout';
  END IF;
  -- §10.3 step 7: the turn is NOT advanced into another round.
  IF (SELECT current_turn_user_id FROM public.game_sessions WHERE id = v_session)
     <> a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the turn advanced past a knockout';
  END IF;

  -- §10.5: the WINNER may not resolve their own penalty.
  BEGIN
    PERFORM public.paint_ball_resolve_penalty(v_session, 'completed');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the winner resolved the penalty';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  -- The loser resolves, and the game completes.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_resolve_penalty(v_session, 'completed');

  IF (SELECT status FROM public.game_sessions WHERE id = v_session)
     <> 'completed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resolving the penalty did not end the game';
  END IF;

  -- Idempotent once completed.
  PERFORM public.paint_ball_resolve_penalty(v_session, 'completed');

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- Lives can never go below zero, even if a hit is forced past a knockout.
DO $$
DECLARE
  v_session uuid;
  a uuid := '00000000-0000-0000-0000-0000000000a1';
  b uuid := '00000000-0000-0000-0000-0000000000b2';
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_session := public.paint_ball_create_session(
    '10000000-0000-0000-0000-0000000000a1', 'playful', 'pb-key-floor', true);

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', b, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_accept_session(v_session);

  -- Drive B to zero directly, then fire once more at a dead defender.
  UPDATE public.game_sessions SET lives_b = 0 WHERE id = v_session;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM public.paint_ball_fire_shot(v_session, 1, true, NULL);

  IF (SELECT lives_b FROM public.game_sessions WHERE id = v_session) < 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: lives fell below zero';
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
