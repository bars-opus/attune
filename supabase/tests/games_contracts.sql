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

ROLLBACK;
