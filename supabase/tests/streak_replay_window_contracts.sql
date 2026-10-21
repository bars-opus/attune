-- supabase/tests/streak_replay_window_contracts.sql
-- Replays are readable for 30 minutes after the first view, and not a second
-- longer (review 06 M-8). Until 20261019140000 the window was checked only
-- when the viewer FINISHED, so an expired replay played in full once more.
--
-- Run: psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_replay_window_contracts.sql
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('6a000000-0000-0000-0000-0000000000a1'),
  ('6a000000-0000-0000-0000-0000000000b2'),
  ('6a000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('6a000000-0000-0000-0000-0000000000a1', '+233260000001', 'Window A'),
  ('6a000000-0000-0000-0000-0000000000b2', '+233260000002', 'Window B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('6b000000-0000-0000-0000-000000000001',
        '6a000000-0000-0000-0000-0000000000a1',
        '6a000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- A streak from A to B with [p_left] views, first viewed [p_viewed_ago] ago
-- (NULL = never viewed). Returns the message id.
--
-- content is a placeholder word, not '' and not a media_url:
-- messages_payload_present needs content OR media_url, and a media_url on
-- insert trips the upload-intent trigger ("Chat media upload intent is
-- invalid or expired"). Same shape as streak_contracts.sql's fixtures.
-- (Dry-run on attune_spec3a: no messages trigger rejects media_type
-- 'streak' + viewed_at in the one INSERT, so no INSERT-then-UPDATE needed.)
CREATE FUNCTION pg_temp.streak(p_left int, p_viewed_ago interval, p_key text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_msg uuid;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content, media_type,
     streak_views_remaining, viewed_at)
  VALUES ('6b000000-0000-0000-0000-000000000001',
          '6a000000-0000-0000-0000-0000000000a1',
          gen_random_uuid(), 'streak parent', 'streak', p_left,
          CASE WHEN p_viewed_ago IS NULL THEN NULL ELSE now() - p_viewed_ago END)
  RETURNING id INTO v_msg;
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, p_key, 3000);
  RETURN v_msg;
END $$;

-- 0. Grants: clients reach clips through the RPC; the destroy step is
--    internal (callable only from inside the SECURITY DEFINER functions).
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated',
       'public.streak_clips_for_viewing(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot call streak_clips_for_viewing';
  END IF;
  IF has_function_privilege('anon',
       'public.streak_clips_for_viewing(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can call streak_clips_for_viewing';
  END IF;
  IF has_function_privilege('authenticated',
       'public.expire_streak_clips(uuid)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.expire_streak_clips(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can call expire_streak_clips';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid IN ('public.streak_clips_for_viewing(uuid)'::regprocedure,
                    'public.expire_streak_clips(uuid)'::regprocedure)
      AND (NOT p.prosecdef
           OR NOT ('search_path=""' = ANY (COALESCE(p.proconfig, '{}'))))
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read-gate function is not SECURITY DEFINER with an empty search_path';
  END IF;
  -- Named columns only: the caption is view-time state and the budget is
  -- server-owned, so neither may ride along with the clips.
  IF pg_get_function_result('public.streak_clips_for_viewing(uuid)'::regprocedure)
     <> 'TABLE(clip_index integer, media_url text, duration_ms integer, media_kind text)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: streak_clips_for_viewing returns %',
      pg_get_function_result('public.streak_clips_for_viewing(uuid)'::regprocedure);
  END IF;
END $$;

-- 1. Recipient, never viewed: the clips come back.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(3, NULL, 'chat/w1');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: first view got % clips', v_n; END IF;
  -- Reading is not viewing: the budget and the window belong to
  -- mark_streak_viewed, so a fetch must not start the clock or spend.
  IF EXISTS (SELECT 1 FROM public.messages
             WHERE id = v_msg AND (viewed_at IS NOT NULL OR streak_views_remaining <> 3)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fetching clips touched the view budget or window';
  END IF;
END $$;

-- 2. Recipient, viewed 10 minutes ago with budget left: replay is readable.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(2, interval '10 minutes', 'chat/w2');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: in-window replay got % clips', v_n; END IF;
END $$;

-- 3. Recipient, viewed 31 minutes ago with budget left: NOTHING is readable,
--    the clips are destroyed, the budget reads 0 and the object is queued.
DO $$
DECLARE v_msg uuid; v_n int; v_left int;
BEGIN
  v_msg := pg_temp.streak(2, interval '31 minutes', 'chat/w3');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expired replay got % clips', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired clips survived the read';
  END IF;
  SELECT streak_views_remaining INTO v_left FROM public.messages WHERE id = v_msg;
  IF v_left <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expired budget reads %', v_left; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'message-media' AND object_name = 'chat/w3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expired object was not queued for deletion';
  END IF;
  -- The finish-time RPC still agrees afterwards (last line of defence).
  IF public.mark_streak_viewed(v_msg) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_streak_viewed revived an expired streak';
  END IF;
END $$;

-- 4. Recipient with no budget: nothing.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(0, interval '1 minute', 'chat/w4');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: spent streak got % clips', v_n; END IF;
END $$;

-- 5. Sender: readable until the recipient opens it, then not.
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(1, NULL, 'chat/w5');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender replay before open got %', v_n; END IF;
  UPDATE public.messages SET viewed_at = now() WHERE id = v_msg;
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sender replay after open got %', v_n; END IF;
END $$;

-- 6. A non-member cannot read or probe: "someone else's" and "does not
--    exist" fail with the same message.
DO $$
DECLARE v_msg uuid; v_ok boolean := false; v_err_other text; v_err_none text;
BEGIN
  v_msg := pg_temp.streak(1, NULL, 'chat/w6');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_err_other := SQLERRM;
  END;
  IF v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member read a streak'; END IF;
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(gen_random_uuid());
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_err_none := SQLERRM;
  END;
  IF v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a missing streak read as empty'; END IF;
  IF v_err_other IS DISTINCT FROM v_err_none THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: membership oracle (% vs %)', v_err_other, v_err_none;
  END IF;
  -- Exactly the one refusal (review M-4: not "any error").
  IF v_err_other IS DISTINCT FROM 'Streak unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member got %', v_err_other;
  END IF;
  -- And nobody signed in reads nothing.
  PERFORM set_config('request.jwt.claims', '', true);
  v_ok := false;
  v_err_none := NULL;
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);
    v_ok := true;
  EXCEPTION WHEN OTHERS THEN v_err_none := SQLERRM;
  END;
  IF v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an anonymous caller read a streak'; END IF;
  IF v_err_none IS DISTINCT FROM 'Not authenticated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an anonymous caller got %', v_err_none;
  END IF;
END $$;

-- 7. The table itself agrees for the recipient: direct SELECT under RLS
--    (the old client's read) shows nothing past the window and something
--    inside it. The sender keeps table visibility of their own clips (the
--    RPC gates them after open, contract 5) because the client's attach
--    upsert, ON CONFLICT (message_id, clip_index), needs SELECT and would
--    otherwise fail with an RLS error once the recipient has opened it.
DO $$
DECLARE v_in uuid; v_out uuid; v_unopened uuid; v_n int;
BEGIN
  v_in := pg_temp.streak(2, interval '10 minutes', 'chat/w7in');
  v_out := pg_temp.streak(2, interval '31 minutes', 'chat/w7out');
  v_unopened := pg_temp.streak(1, NULL, 'chat/w7new');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_in;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS hid an in-window clip'; END IF;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_out;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS exposed an expired clip'; END IF;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_unopened;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS hid an unopened clip from its recipient'; END IF;
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_unopened;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS hid an unopened clip from its sender'; END IF;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_in;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: RLS hid the sender''s own clip'; END IF;
  -- The sender's attach path (INSERT policy) is untouched, including the
  -- client's upsert shape (ON CONFLICT DO NOTHING), on an unopened streak.
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_in, 1, 'chat/w7in-1', 1000);
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_unopened, 0, 'chat/w7new', 3000)
  ON CONFLICT (message_id, clip_index) DO NOTHING;
  -- A retried upsert after the recipient opened it (sender can no longer
  -- SELECT the row) is still a quiet no-op, not an RLS error.
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_in, 0, 'chat/w7in', 3000)
  ON CONFLICT (message_id, clip_index) DO NOTHING;
  RESET ROLE;
  -- The view-budget RPC still spends through the new policy.
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  IF public.mark_streak_viewed(v_in) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_streak_viewed no longer spends an in-window replay';
  END IF;
END $$;

-- 8. Mutation check: a function WITHOUT the window branch fails contract 3.
SAVEPOINT mutate_fn;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
  FROM public.streak_clips c WHERE c.message_id = p_message_id ORDER BY c.clip_index $$;
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(2, interval '31 minutes', 'chat/w8');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 3 passed without the window check';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_fn;

-- 9. Mutation check: a permissive read policy fails contract 7.
SAVEPOINT mutate_rls;
DROP POLICY streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.messages m
                 WHERE m.id = streak_clips.message_id
                   AND public.relationship_chat_open(m.relationship_id)));
DO $$
DECLARE v_out uuid; v_n int;
BEGIN
  v_out := pg_temp.streak(2, interval '31 minutes', 'chat/w9');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_out;
  RESET ROLE;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: the permissive policy still hid the expired clip';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_rls;

-- 10. Mutation check: a function without the membership check fails
--     contract 6 (a non-member reads the clips).
SAVEPOINT mutate_member;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE c.message_id = p_message_id
    AND COALESCE(m.streak_views_remaining, 0) > 0
    AND (m.viewed_at IS NULL OR m.viewed_at > now() - interval '30 minutes')
  ORDER BY c.clip_index $$;
DO $$
DECLARE v_msg uuid; v_n int := 0;
BEGIN
  v_msg := pg_temp.streak(1, NULL, 'chat/w10');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000c3');
  BEGIN
    SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  EXCEPTION WHEN OTHERS THEN v_n := 0;
  END;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 6 passed without the membership check';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_member;

-- 11. Mutation check: a function that lets the sender replay after the
--     recipient opened it fails contract 5.
SAVEPOINT mutate_sender;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE c.message_id = p_message_id
    AND public.relationship_chat_open_for(m.relationship_id, auth.uid())
    AND (m.sender_id = auth.uid()
         OR (COALESCE(m.streak_views_remaining, 0) > 0
             AND (m.viewed_at IS NULL OR m.viewed_at > now() - interval '30 minutes')))
  ORDER BY c.clip_index $$;
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.streak(1, interval '1 minute', 'chat/w11');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 5 passed with sender replay after open';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_sender;

-- 12. Mutation check: the brief's original sender branch (hide opened
--     clips from the sender) breaks the attach upsert in contract 7.
SAVEPOINT mutate_sender_rls;
DROP POLICY streak_clips_members_read ON public.streak_clips;
CREATE POLICY streak_clips_members_read ON public.streak_clips FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.messages m
                 WHERE m.id = streak_clips.message_id
                   AND public.relationship_chat_open(m.relationship_id)
                   AND CASE WHEN m.sender_id = auth.uid() THEN m.viewed_at IS NULL
                            ELSE COALESCE(m.streak_views_remaining, 0) > 0
                                 AND (m.viewed_at IS NULL
                                      OR m.viewed_at > now() - interval '30 minutes')
                       END));
DO $$
DECLARE v_opened uuid; v_failed boolean := false;
BEGIN
  v_opened := pg_temp.streak(2, interval '1 minute', 'chat/w13');
  PERFORM pg_temp.as_user('6a000000-0000-0000-0000-0000000000a1');
  SET LOCAL ROLE authenticated;
  BEGIN
    INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
    VALUES (v_opened, 0, 'chat/w13', 3000)
    ON CONFLICT (message_id, clip_index) DO NOTHING;
  EXCEPTION WHEN insufficient_privilege THEN v_failed := true;
  END;
  RESET ROLE;
  IF NOT v_failed THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: a sender-hiding policy left the attach upsert working';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_sender_rls;

-- 13. Mutation check: granting the destroy step to clients fails contract 0.
SAVEPOINT mutate_grant;
GRANT EXECUTE ON FUNCTION public.expire_streak_clips(uuid) TO authenticated;
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated',
       'public.expire_streak_clips(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 0 cannot see a client grant on expire_streak_clips';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate_grant;

ROLLBACK;
