-- Game cards in the conversation.
--
-- A game invite used to produce a push and nothing else: the invite lived
-- only in game_sessions, so the chat showed no trace of it and a partner
-- who missed the push never knew a game was waiting.
--
-- One message row now represents a game for its whole life. The row holds
-- only game_session_id; the card's label is read live from the session by
-- the client, so "Let's play" becomes "Your move" becomes "You won"
-- without a second bubble. These tests pin the invariants that model
-- depends on.

BEGIN;

INSERT INTO auth.users(id) VALUES
  ('00000000-0000-0000-0000-00000000ce01'),
  ('00000000-0000-0000-0000-00000000ce02') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-00000000ce01', '+15559990001', 'CE1'),
  ('00000000-0000-0000-0000-00000000ce02', '+15559990002', 'CE2')
  ON CONFLICT (id) DO NOTHING;

DO $$
DECLARE
  v_rel uuid;
  v_sess uuid;
  v_msg record;
  v_count int;
  v_sort timestamptz;
BEGIN
  INSERT INTO public.relationships(user_a, user_b, status)
  VALUES ('00000000-0000-0000-0000-00000000ce01',
          '00000000-0000-0000-0000-00000000ce02', 'active')
  RETURNING id INTO v_rel;

  -- An invite posts exactly one card.
  INSERT INTO public.game_sessions(relationship_id, initiator_id, game_type, status)
  VALUES (v_rel, '00000000-0000-0000-0000-00000000ce01', 'paint_ball', 'invited')
  RETURNING id INTO v_sess;

  SELECT * INTO v_msg FROM public.messages WHERE game_session_id = v_sess;
  IF v_msg IS NULL THEN
    RAISE EXCEPTION 'no card posted for a game invite';
  END IF;
  IF v_msg.media_type <> 'game' THEN
    RAISE EXCEPTION 'card is not media_type game, got %', v_msg.media_type;
  END IF;

  -- content carries the display name: messages_payload_present requires
  -- content or media_url, and a game row has no media. It is also what a
  -- push preview and any not-yet-updated client will show.
  IF v_msg.content <> 'Paint Ball' THEN
    RAISE EXCEPTION 'card content should be the display name, got %', v_msg.content;
  END IF;

  -- The sender is the initiator, so the card sits on their side of the
  -- conversation exactly as a message they sent would.
  IF v_msg.sender_id <> '00000000-0000-0000-0000-00000000ce01' THEN
    RAISE EXCEPTION 'card sender is not the initiator';
  END IF;

  IF v_msg.sort_at <> v_msg.created_at THEN
    RAISE EXCEPTION 'a fresh card must sort at its creation time';
  END IF;

  v_sort := v_msg.sort_at;

  -- Resurfacing: the turn passing moves the card to the bottom.
  UPDATE public.game_sessions
  SET current_turn_user_id = '00000000-0000-0000-0000-00000000ce02'
  WHERE id = v_sess;

  SELECT * INTO v_msg FROM public.messages WHERE game_session_id = v_sess;
  IF v_msg.sort_at <= v_sort THEN
    RAISE EXCEPTION 'the card did not resurface when the turn changed';
  END IF;

  -- created_at is untouched, so the date separator still reports when the
  -- game was actually sent, and the keyset cursor stays coherent.
  IF v_msg.created_at <> (SELECT created_at FROM public.messages WHERE id = v_msg.id) THEN
    RAISE EXCEPTION 'created_at was rewritten by resurfacing';
  END IF;

  -- Still exactly one card after all of that.
  SELECT count(*) INTO v_count FROM public.messages WHERE game_session_id = v_sess;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected 1 card for the session, found %', v_count;
  END IF;

  -- A status change resurfaces too: a game ending is worth seeing.
  v_sort := v_msg.sort_at;
  UPDATE public.game_sessions SET status = 'active' WHERE id = v_sess;
  SELECT * INTO v_msg FROM public.messages WHERE game_session_id = v_sess;
  IF v_msg.sort_at <= v_sort THEN
    RAISE EXCEPTION 'a status change did not resurface the card';
  END IF;
END $$;

-- A game row without a session, or a session on a non-game row, must be
-- rejected: either would render a card with nothing to read.
DO $$
DECLARE
  v_rel uuid;
  v_refused boolean := false;
BEGIN
  SELECT id INTO v_rel FROM public.relationships
  WHERE user_a = '00000000-0000-0000-0000-00000000ce01' LIMIT 1;

  BEGIN
    INSERT INTO public.messages(relationship_id, sender_id, client_message_id,
                                content, media_type, source)
    VALUES (v_rel, '00000000-0000-0000-0000-00000000ce01', gen_random_uuid(),
            'orphan', 'game', 'native');
  EXCEPTION WHEN check_violation THEN
    v_refused := true;
  END;

  IF NOT v_refused THEN
    RAISE EXCEPTION 'a game message with no session was accepted';
  END IF;
END $$;

-- Ordinary messages must be unaffected: sort_at defaults to created_at,
-- so every existing conversation keeps its exact order.
DO $$
DECLARE
  v_rel uuid;
  v_id uuid;
BEGIN
  SELECT id INTO v_rel FROM public.relationships
  WHERE user_a = '00000000-0000-0000-0000-00000000ce01' LIMIT 1;

  INSERT INTO public.messages(relationship_id, sender_id, client_message_id,
                              content, source)
  VALUES (v_rel, '00000000-0000-0000-0000-00000000ce01', gen_random_uuid(),
          'hello', 'native')
  RETURNING id INTO v_id;

  IF (SELECT sort_at <> created_at FROM public.messages WHERE id = v_id) THEN
    RAISE EXCEPTION 'an ordinary message did not sort at its creation time';
  END IF;
END $$;

-- The keyset cursor must stay coherent when a card resurfaces.
--
-- This is the invariant the whole sort_at column exists to protect.
-- Pagination is keyset on (sort_at, id) descending: page 1 takes the
-- newest N and page 2 asks for everything older than the last row it saw.
-- A resurfaced card always moves FORWARD (to now()), so it can never fall
-- between two already-issued cursors -- which is exactly what bumping
-- created_at would have done, serving a row twice or skipping it.
DO $$
DECLARE
  v_rel uuid;
  v_sess uuid;
  v_cursor_sort timestamptz;
  v_cursor_id uuid;
  v_page2 int;
  v_dupes int;
BEGIN
  SELECT id INTO v_rel FROM public.relationships
  WHERE user_a = '00000000-0000-0000-0000-00000000ce01' LIMIT 1;

  -- A conversation with enough rows to page through.
  INSERT INTO public.messages(relationship_id, sender_id, client_message_id,
                              content, source, created_at, sort_at)
  SELECT v_rel, '00000000-0000-0000-0000-00000000ce01', gen_random_uuid(),
         'm' || g, 'native', now() - (g || ' minutes')::interval,
         now() - (g || ' minutes')::interval
  FROM generate_series(1, 10) g;

  INSERT INTO public.game_sessions(relationship_id, initiator_id, game_type, status)
  VALUES (v_rel, '00000000-0000-0000-0000-00000000ce01', 'mirror', 'invited')
  RETURNING id INTO v_sess;

  -- Page 1: the newest 5. Remember the cursor it ends on.
  SELECT sort_at, id INTO v_cursor_sort, v_cursor_id
  FROM public.messages
  WHERE relationship_id = v_rel
  ORDER BY sort_at DESC, id DESC
  LIMIT 5 OFFSET 4;

  -- The card resurfaces while the reader sits between pages.
  UPDATE public.game_sessions
  SET current_turn_user_id = '00000000-0000-0000-0000-00000000ce02'
  WHERE id = v_sess;

  -- Page 2, using the cursor issued BEFORE the bump.
  SELECT count(*) INTO v_page2
  FROM public.messages
  WHERE relationship_id = v_rel
    AND (sort_at < v_cursor_sort
         OR (sort_at = v_cursor_sort AND id < v_cursor_id));

  -- The resurfaced card must NOT appear in page 2: it moved to the top,
  -- which the reader already has. Appearing here is the duplicate-row bug.
  SELECT count(*) INTO v_dupes
  FROM public.messages
  WHERE relationship_id = v_rel
    AND game_session_id = v_sess
    AND (sort_at < v_cursor_sort
         OR (sort_at = v_cursor_sort AND id < v_cursor_id));

  IF v_dupes <> 0 THEN
    RAISE EXCEPTION
      'a resurfaced card fell behind an already-issued cursor: it would '
      'be served twice while scrolling';
  END IF;

  IF v_page2 = 0 THEN
    RAISE EXCEPTION 'page 2 came back empty; the cursor is not paging';
  END IF;
END $$;

-- Session games get a card too.
--
-- post_game_message fired only on status = 'invited', and the session
-- games (Mirror, Sliding Scale, Scenario) insert straight to 'active' --
-- they have no invite step. So playing Scenario left no trace in the
-- chat at all, which is also where the flow now hands off after
-- answering: the player was returned to a conversation with nothing in
-- it.
DO $$
DECLARE
  v_rel uuid;
  v_session uuid;
  v_count int;
  v_viewer boolean;
  v_partner boolean;
BEGIN
  SELECT id INTO v_rel FROM public.relationships
  WHERE user_a = '00000000-0000-0000-0000-00000000ce01' LIMIT 1;

  INSERT INTO public.game_sessions(relationship_id, initiator_id, game_type, status)
  VALUES (v_rel, '00000000-0000-0000-0000-00000000ce01', 'scenario', 'active')
  RETURNING id INTO v_session;

  SELECT count(*) INTO v_count
  FROM public.messages WHERE game_session_id = v_session;

  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'a session game inserted straight to active produced no card';
  END IF;

  -- And the card can say whose move it is. Session games carry no
  -- current_turn_user_id -- both partners answer the SAME round -- so
  -- without this the card could only show a round number, which cannot
  -- tell you whether anything is waiting on you.
  INSERT INTO public.game_session_rounds(session_id, round_number, answer_a_submitted_at)
  VALUES (v_session, 1, now());

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-00000000ce01',
                      'role', 'authenticated')::text, true);
  SELECT viewer_answered, partner_answered INTO v_viewer, v_partner
  FROM public.session_game_round_state(v_session);

  IF NOT v_viewer OR v_partner THEN
    RAISE EXCEPTION
      'the player who answered should read as waiting, got viewer=% partner=%',
      v_viewer, v_partner;
  END IF;

  -- The same round, read by the other partner, must say the OPPOSITE.
  -- If these ever agree, one partner is told to act when they already
  -- have.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '00000000-0000-0000-0000-00000000ce02',
                      'role', 'authenticated')::text, true);
  SELECT viewer_answered, partner_answered INTO v_viewer, v_partner
  FROM public.session_game_round_state(v_session);

  IF v_viewer OR NOT v_partner THEN
    RAISE EXCEPTION
      'the waiting partner should read as their turn, got viewer=% partner=%',
      v_viewer, v_partner;
  END IF;
END $$;

ROLLBACK;
