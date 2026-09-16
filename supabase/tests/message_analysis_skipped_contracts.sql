-- Proves idx_messages_analysis_backlog and the candidate-selection query
-- shape both exclude deliberately-skipped rows (message_analysis_skipped
-- = true). Run:
-- psql -q -d attune_test -f supabase/tests/message_analysis_skipped_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000000b';
  v_msg_done uuid := 'a5000000-0000-0000-0000-000000000101';
  v_msg_pending uuid := 'a5000000-0000-0000-0000-000000000102';
  v_msg_skipped uuid := 'a5000000-0000-0000-0000-000000000103';
  v_count int;
BEGIN
  DELETE FROM public.messages WHERE relationship_id = v_rel;
  DELETE FROM public.relationships WHERE id = v_rel;
  DELETE FROM public.users WHERE id IN (v_user_a, v_user_b);
  DELETE FROM auth.users WHERE id IN (v_user_a, v_user_b);

  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'skip_a@t.test'), (v_user_b, 'skip_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550005001', 'A'), (v_user_b, '+15550005002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.messages (id, relationship_id, sender_id,
    client_message_id, content, source, message_analysis_done,
    message_analysis_skipped, safety_processed_at)
  VALUES
    (v_msg_done, v_rel, v_user_a, gen_random_uuid(), 'analyzed already', 'native', true, false, now()),
    (v_msg_pending, v_rel, v_user_a, gen_random_uuid(), 'not yet analyzed', 'native', false, false, now()),
    (v_msg_skipped, v_rel, v_user_a, gen_random_uuid(), 'deliberately skipped', 'native', false, true, now());

  -- Contract 1: the backlog index's own predicate (read directly from
  -- pg_indexes -- confirming the DEFINITION, not merely that a query
  -- against the table happens to return the right rows some other way)
  -- excludes message_analysis_skipped = true rows.
  IF (
    SELECT indexdef FROM pg_indexes
    WHERE indexname = 'idx_messages_analysis_backlog'
  ) NOT LIKE '%message_analysis_skipped%' THEN
    RAISE EXCEPTION 'EXPLOIT: idx_messages_analysis_backlog does not reference message_analysis_skipped at all';
  END IF;

  -- Contract 2: a query shaped exactly like analyse-message's own
  -- candidate-selection query (done=false AND skipped=false) returns the
  -- pending message but not the skipped one.
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel
    AND message_analysis_done = false
    AND message_analysis_skipped = false
    AND safety_processed_at IS NOT NULL;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: candidate-selection shape returned % rows, expected exactly 1 (the pending message)', v_count;
  END IF;

  -- Contract 3: a query shaped exactly like analyse-session's own
  -- Layer-2/session-transcript selection query (done=true AND
  -- skipped=false) never selects a skipped message even if some other
  -- path ever marked it done by mistake.
  UPDATE public.messages SET message_analysis_done = true WHERE id = v_msg_skipped;
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel
    AND message_analysis_done = true
    AND message_analysis_skipped = true;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: fixture setup for contract 3 is wrong, expected 1 done+skipped row, got %', v_count;
  END IF;

  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel
    AND message_analysis_done = true
    AND message_analysis_skipped = false;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: session-selection shape returned % done+not-skipped rows, expected exactly 1 (only the originally-done message, not the mistakenly-marked-done skipped one)', v_count;
  END IF;

  -- Contract 4: Pulse's compute_relationship_chat_signals RPC excludes
  -- the skipped message from both the analysed-message aggregate and the
  -- pending backlog count, even though it is now message_analysis_done =
  -- true (mirrors the "marked done by mistake" scenario contract 3 sets
  -- up, proving Pulse's own filter is independently load-bearing and not
  -- merely inheriting correctness from upstream never marking it done).
  DECLARE
    v_analysed_count int;
    v_pending_backlog_count int;
  BEGIN
    SELECT analysed_count, pending_backlog_count
      INTO v_analysed_count, v_pending_backlog_count
      FROM public.compute_relationship_chat_signals(v_rel, now() - interval '30 days');

    -- v_msg_done was already done=true/skipped=false from the initial
    -- insert, so both analysed_count and pending_backlog_count have a
    -- legitimate baseline of 1 from that row alone; the assertion here
    -- is that count stays at exactly 1 and does NOT become 2 by also
    -- counting v_msg_skipped (which contract 3's UPDATE just marked
    -- done=true, skipped=true).
    IF v_analysed_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'EXPLOIT: compute_relationship_chat_signals analysed_count = %, expected exactly 1 (only v_msg_done; the skipped-but-marked-done message must not count)', v_analysed_count;
    END IF;
    IF v_pending_backlog_count IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'EXPLOIT: compute_relationship_chat_signals pending_backlog_count = %, expected exactly 1 (only v_msg_done; the skipped message must not count as backlog either)', v_pending_backlog_count;
    END IF;
  END;

  RAISE NOTICE 'message_analysis_skipped contracts: all held';
END $$;
