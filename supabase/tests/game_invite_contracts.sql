-- The generic invite path, which every game now uses to ask someone to play.
--
-- These functions are SECURITY DEFINER and their success posts a message
-- into a conversation (post_game_message fires on any invited row), so a
-- hole here is not "a bad game session" -- it is an attacker writing chat
-- messages into someone else's relationship. Every check below is written
-- as an attack that must fail, not a happy path that must pass.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000a101'::uuid),
  ('00000000-0000-0000-0000-00000000a102'::uuid),
  ('00000000-0000-0000-0000-00000000a103'::uuid) ON CONFLICT DO NOTHING;

INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000a101'::uuid, '+15558880001', 'AI1'),
  ('00000000-0000-0000-0000-00000000a102'::uuid, '+15558880002', 'AI2'),
  ('00000000-0000-0000-0000-00000000a103'::uuid, '+15558880003', 'AI3')
  ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.test_set_invite_auth(p_user_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user_id::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user_id, 'role', 'authenticated')::text, true);
END;
$$;

-- ---------------------------------------------------------------------
-- Grants (7.4): anon must not reach any of this.
-- ---------------------------------------------------------------------
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon',
    'public.game_invite_create(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute game_invite_create';
  END IF;
  IF has_function_privilege('anon', 'public.game_invite_accept(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute game_invite_accept';
  END IF;
  IF has_function_privilege('anon', 'public.game_invite_decline(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute game_invite_decline';
  END IF;
  IF NOT has_function_privilege('authenticated',
    'public.game_invite_create(uuid,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated cannot execute game_invite_create';
  END IF;
END $$;

DO $$
DECLARE
  v_rel uuid;
  v_other uuid;
  v_res jsonb;
  v_res2 jsonb;
  v_session uuid;
  v_count int;
  v_status text;
  v_type text;
  v_journey uuid;
  v_chapter int;
BEGIN
  RESET ROLE;
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000a101'::uuid,
          '00000000-0000-0000-0000-00000000a102'::uuid, 'active')
  RETURNING id INTO v_rel;

  -- A relationship the attacker (ai03) is NOT in.
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000a101'::uuid,
          '00000000-0000-0000-0000-00000000a103'::uuid, 'active')
  RETURNING id INTO v_other;

  -- =================================================================
  -- ATTACK 1: invite into a relationship you are not part of.
  -- Success here means writing a chat message into someone else's
  -- conversation.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a103'::uuid);
  v_res := public.game_invite_create(v_rel, 'mirror', 'attack-1', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: outsider created an invite in a foreign relationship: %', v_res;
  END IF;
  IF v_res->>'code' <> 'FORBIDDEN' THEN
    RAISE EXCEPTION 'wrong code for outsider create: %', v_res->>'code';
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.game_sessions WHERE relationship_id = v_rel;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a refused create still wrote a session';
  END IF;

  -- =================================================================
  -- ATTACK 2: an unlisted game_type.
  -- game_type is free text in the table, and the trigger puts
  -- game_type_display_name into a chat message's content.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_rel, 'not_a_game', 'attack-2', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: arbitrary game_type accepted: %', v_res;
  END IF;
  v_res := public.game_invite_create(v_rel, 'Click here http://evil', 'attack-2b', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: attacker-chosen text became a game_type: %', v_res;
  END IF;

  -- =================================================================
  -- Happy path: a member invites, and exactly one card appears.
  -- =================================================================
  v_res := public.game_invite_create(v_rel, 'mirror', 'ok-1', 'connecting');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a member could not invite: %', v_res;
  END IF;
  IF (v_res->>'existing')::boolean THEN
    RAISE EXCEPTION 'a first invite reported itself as existing';
  END IF;
  v_session := (v_res->>'session_id')::uuid;

  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.messages WHERE game_session_id = v_session;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one card for an invite, got %', v_count;
  END IF;

  -- =================================================================
  -- 1.1 / 2.18: the same key returns the same session, not a second game.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res2 := public.game_invite_create(v_rel, 'mirror', 'ok-1', 'connecting');
  IF (v_res2->>'session_id')::uuid <> v_session THEN
    RAISE EXCEPTION 'a retried key started a second game';
  END IF;
  IF NOT (v_res2->>'existing')::boolean THEN
    RAISE EXCEPTION 'a retried key did not report existing';
  END IF;

  RESET ROLE;
  SELECT count(*) INTO v_count
    FROM public.game_sessions WHERE relationship_id = v_rel AND game_type = 'mirror';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'retry created a duplicate session: % rows', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.messages WHERE game_session_id = v_session;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'retry posted a second card: % cards', v_count;
  END IF;

  -- The key path must be what answers a retry, not a happy accident.
  --
  -- With the open-session reuse below it, a retry returns the same id
  -- even if the key lookup is deleted -- so that assertion alone proves
  -- nothing about idempotency. Retried against a session that is NO
  -- longer open, only the key can answer. (Without it the insert hits
  -- the primary key on session_idempotency_keys and the caller gets a
  -- database error instead of their session.)
  RESET ROLE;
  UPDATE public.game_sessions SET status = 'abandoned' WHERE id = v_session;
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res2 := public.game_invite_create(v_rel, 'mirror', 'ok-1', 'connecting');
  IF (v_res2->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a retried key failed once its session closed: %', v_res2;
  END IF;
  IF (v_res2->>'session_id')::uuid <> v_session THEN
    RAISE EXCEPTION 'a retried key did not resolve through the key table';
  END IF;
  RESET ROLE;
  UPDATE public.game_sessions SET status = 'invited' WHERE id = v_session;

  -- =================================================================
  -- ATTACK 3: replay someone else's idempotency key.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_other, 'mirror', 'ok-1', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a key from another relationship was honoured: %', v_res;
  END IF;
  IF v_res->>'code' <> 'FORBIDDEN' THEN
    RAISE EXCEPTION 'wrong code for cross-relationship key replay: %', v_res->>'code';
  END IF;

  -- A key reused for a DIFFERENT game must not hand back the first game.
  v_res := public.game_invite_create(v_rel, 'scenario', 'ok-1', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: a key was reused across game types: %', v_res;
  END IF;

  -- =================================================================
  -- One game of a kind at a time: a second invite for the same game
  -- returns the open one rather than stacking cards.
  -- =================================================================
  v_res := public.game_invite_create(v_rel, 'mirror', 'different-key', 'connecting');
  IF (v_res->>'session_id')::uuid <> v_session THEN
    RAISE EXCEPTION 'a second invite for an open game started another';
  END IF;
  RESET ROLE;
  SELECT count(*) INTO v_count FROM public.messages WHERE game_session_id = v_session;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'a second invite posted another card';
  END IF;

  -- =================================================================
  -- ATTACK 4: accept a game you are not part of.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a103'::uuid);
  v_res := public.game_invite_accept(v_session);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider accepted a game: %', v_res;
  END IF;
  RESET ROLE;
  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status IS DISTINCT FROM 'invited' THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider moved the session to %', v_status;
  END IF;

  -- ATTACK 5: decline a game you are not part of.
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a103'::uuid);
  v_res := public.game_invite_decline(v_session);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider declined a game: %', v_res;
  END IF;
  RESET ROLE;
  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status IS DISTINCT FROM 'invited' THEN
    RAISE EXCEPTION 'EXPLOIT: an outsider abandoned the session';
  END IF;

  -- =================================================================
  -- Accept works for the invited partner, and is idempotent.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a102'::uuid);
  v_res := public.game_invite_accept(v_session);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the invited partner could not accept: %', v_res;
  END IF;
  RESET ROLE;
  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'accept did not activate the session, got %', v_status;
  END IF;

  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a102'::uuid);
  v_res := public.game_invite_accept(v_session);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'a second accept reported failure for something that worked';
  END IF;

  -- An active game cannot be declined: that is quitting, which each game
  -- owns because only it knows what quitting costs.
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a102'::uuid);
  v_res := public.game_invite_decline(v_session);
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'an active game was declined through the invite path';
  END IF;

  -- =================================================================
  -- Decline as cancel: the sender withdrawing an unanswered invite.
  -- =================================================================
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_rel, 'scenario', 'cancel-1', 'connecting');
  v_session := (v_res->>'session_id')::uuid;
  v_res := public.game_invite_decline(v_session);
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the sender could not cancel their own invite: %', v_res;
  END IF;
  RESET ROLE;
  SELECT status INTO v_status FROM public.game_sessions WHERE id = v_session;
  IF v_status IS DISTINCT FROM 'abandoned' THEN
    RAISE EXCEPTION 'cancel did not abandon the session, got %', v_status;
  END IF;

  -- =================================================================
  -- ATTACK 6: invite into an ENDED relationship.
  -- =================================================================
  RESET ROLE;
  UPDATE public.relationships SET status = 'ended' WHERE id = v_other;
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_other, 'mirror', 'ended-1', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: invited into an ended relationship: %', v_res;
  END IF;

  -- =================================================================
  -- Every game can be invited, and each gets the session shape it
  -- expects. A wrong shape is not cosmetic: a card reads its round
  -- count, and 36 Questions is invisible to its own queries without a
  -- journey.
  -- =================================================================
  RESET ROLE;
  FOR v_type IN SELECT unnest(ARRAY[
    'this_or_that','truth_or_dare','36_questions','mirror','sliding_scale',
    'scenario','love_map','paint_ball','snakes_and_ladders','word_hunt'])
  LOOP
    IF NOT public.game_invite_type_allowed(v_type) THEN
      RAISE EXCEPTION 'game % cannot be invited', v_type;
    END IF;
  END LOOP;

  -- ATTACK 7: an unlisted tone. It is written to the row and read back
  -- by the games to pick a question set, and 'intimate' gates consent.
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_rel, 'mirror', 'tone-1', 'anything');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'EXPLOIT: arbitrary tone accepted: %', v_res;
  END IF;

  -- Round counts, so a card never reads "Round 1 of 0".
  RESET ROLE;
  IF public.game_invite_total_rounds('truth_or_dare') <> 10
     OR public.game_invite_total_rounds('this_or_that') <> 10
     OR public.game_invite_total_rounds('36_questions') <> 12 THEN
    RAISE EXCEPTION 'a game lost its round count';
  END IF;
  -- And the games that size themselves later declare none.
  IF public.game_invite_total_rounds('mirror') <> 0
     OR public.game_invite_total_rounds('snakes_and_ladders') <> 0 THEN
    RAISE EXCEPTION 'a game was given a round count it does not use';
  END IF;

  -- 36 Questions gets a journey and chapter 1, or its own queries --
  -- which all filter by journey_id -- never see the session.
  UPDATE public.game_sessions SET created_at = now() - interval '2 hours'
   WHERE relationship_id = v_rel;
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_rel, '36_questions', 'j36', 'connecting');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'could not invite 36 Questions: %', v_res;
  END IF;
  RESET ROLE;
  SELECT journey_id, chapter INTO v_journey, v_chapter
    FROM public.game_sessions WHERE id = (v_res->>'session_id')::uuid;
  IF v_journey IS NULL THEN
    RAISE EXCEPTION '36 Questions invite has no journey: its own queries cannot see it';
  END IF;
  -- IS DISTINCT FROM, not <>: a NULL chapter -- exactly the bug this
  -- guards -- makes `v_chapter <> 1` evaluate to NULL, so the IF never
  -- fires and the test passes while asserting nothing.
  IF v_chapter IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION '36 Questions invite starts at chapter %, not 1',
      COALESCE(v_chapter::text, 'NULL');
  END IF;

  -- And its twelve questions, with real text. The journey overview's
  -- "Start" routes straight into the chapter with whatever rounds
  -- exist, so an invite without them opens onto nothing.
  SELECT count(*) INTO v_count FROM public.game_session_rounds
   WHERE session_id = (v_res->>'session_id')::uuid;
  IF v_count <> 12 THEN
    RAISE EXCEPTION '36 Questions invite has % rounds, needs 12', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.game_session_rounds
   WHERE session_id = (v_res->>'session_id')::uuid
     AND COALESCE(question_text_snapshot, '') = '';
  IF v_count <> 0 THEN
    RAISE EXCEPTION '% of the chapter''s questions have no text', v_count;
  END IF;

  -- Love Map is sessionless by design: nothing in it ever accepts, so an
  -- invitation left 'invited' would read "Waiting for them" forever.
  UPDATE public.game_sessions SET created_at = now() - interval '2 hours'
   WHERE relationship_id = v_rel;
  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  v_res := public.game_invite_create(v_rel, 'love_map', 'lm1', 'connecting');
  RESET ROLE;
  SELECT status INTO v_status
    FROM public.game_sessions WHERE id = (v_res->>'session_id')::uuid;
  IF v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'a Love Map invite waits for an accept that never comes (status %)', v_status;
  END IF;
  -- And it still posted its card.
  SELECT count(*) INTO v_count FROM public.messages
   WHERE game_session_id = (v_res->>'session_id')::uuid;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Love Map invite posted % cards', v_count;
  END IF;

  -- =================================================================
  -- 2.5 / 3.8: invites are rate limited per couple.
  --
  -- Not a nicety. Every invite fires post_game_message, so an unbounded
  -- loop here is an unbounded loop of chat messages -- one player can
  -- fill the other's conversation.
  -- =================================================================
  RESET ROLE;
  DELETE FROM public.messages WHERE relationship_id = v_rel;
  DELETE FROM public.session_idempotency_keys
   WHERE session_id IN (SELECT id FROM public.game_sessions
                         WHERE relationship_id = v_rel);
  DELETE FROM public.game_sessions WHERE relationship_id = v_rel;

  PERFORM public.test_set_invite_auth('00000000-0000-0000-0000-00000000a101'::uuid);
  -- Five distinct games, so the open-session reuse cannot absorb them.
  v_res := public.game_invite_create(v_rel, 'mirror', 'rl-1', 'connecting');
  v_res := public.game_invite_create(v_rel, 'scenario', 'rl-2', 'connecting');
  v_res := public.game_invite_create(v_rel, 'sliding_scale', 'rl-3', 'connecting');
  v_res := public.game_invite_create(v_rel, 'word_hunt', 'rl-4', 'connecting');
  v_res := public.game_invite_create(v_rel, 'paint_ball', 'rl-5', 'connecting');
  IF (v_res->>'error') IS NOT DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'the fifth invite of the hour was refused: %', v_res;
  END IF;

  v_res := public.game_invite_create(v_rel, 'love_map', 'rl-6', 'connecting');
  IF (v_res->>'error') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'EXPLOIT: a sixth invite in the hour was accepted -- one player can '
      'fill the conversation: %', v_res;
  END IF;
  IF v_res->>'code' <> 'RATE_LIMITED' THEN
    RAISE EXCEPTION 'wrong code for a rate-limited invite: %', v_res->>'code';
  END IF;

  RAISE NOTICE 'game_invite contracts: all held';
END $$;

RESET ROLE;
DROP FUNCTION IF EXISTS public.test_set_invite_auth(uuid);
ROLLBACK;
