-- supabase/tests/streak_view_once_hardening_contracts.sql
-- View-once streak hardening (20261019140100): storage signing follows the
-- replay window, abandoned streaks are swept, the clip read requires a live
-- streak, the spend is idempotent per open, and the 30:00 boundary is one
-- convention everywhere (viewable strictly inside: viewed_at > now() - 30m).
--
-- Run: psql -X -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/streak_view_once_hardening_contracts.sql
--
-- now() is the transaction's start time and does not move inside it, so
-- "viewed exactly 30 minutes ago" below is exact, not approximate.
BEGIN;

-- The Storage API runs these checks with RLS on and authenticated holding
-- SELECT; the local harness has neither, so both are added for this
-- transaction only (rolled back at the end).
GRANT SELECT ON storage.objects TO authenticated;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

INSERT INTO auth.users (id) VALUES
  ('7a000000-0000-0000-0000-0000000000a1'),
  ('7a000000-0000-0000-0000-0000000000b2'),
  ('7a000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7a000000-0000-0000-0000-0000000000a1', '+233270000001', 'Once A'),
  ('7a000000-0000-0000-0000-0000000000b2', '+233270000002', 'Once B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7b000000-0000-0000-0000-000000000001',
        '7a000000-0000-0000-0000-0000000000a1',
        '7a000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name) VALUES ('message-media', 'message-media')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.a() RETURNS uuid LANGUAGE sql AS $$ SELECT '7a000000-0000-0000-0000-0000000000a1'::uuid $$;
CREATE FUNCTION pg_temp.b() RETURNS uuid LANGUAGE sql AS $$ SELECT '7a000000-0000-0000-0000-0000000000b2'::uuid $$;

-- A message from A to B. media_url is set AFTER the insert: the
-- upload-intent trigger fires on INSERT only, and a streak's key lives in
-- messages.media_url exactly as the client sends it. With p_clip, a
-- streak_clips row for the same key, and a storage object either way.
CREATE FUNCTION pg_temp.msg(p_type text, p_left int, p_viewed_ago interval,
                            p_key text, p_clip boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_msg uuid;
BEGIN
  INSERT INTO public.messages
    (relationship_id, sender_id, client_message_id, content, media_type,
     streak_views_remaining, viewed_at)
  VALUES ('7b000000-0000-0000-0000-000000000001', pg_temp.a(),
          gen_random_uuid(), 'once parent', p_type, p_left,
          CASE WHEN p_viewed_ago IS NULL THEN NULL ELSE now() - p_viewed_ago END)
  RETURNING id INTO v_msg;
  UPDATE public.messages SET media_url = p_key WHERE id = v_msg;
  IF p_clip THEN
    INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
    VALUES (v_msg, 0, p_key, 3000);
  END IF;
  INSERT INTO storage.objects (bucket_id, name) VALUES ('message-media', p_key);
  RETURN v_msg;
END $$;

-- What the storage SELECT policy lets [p_user] see (= sign) for [p_key].
CREATE FUNCTION pg_temp.signable(p_user uuid, p_key text) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM storage.objects
  WHERE bucket_id = 'message-media' AND name = p_key;
  RESET ROLE;
  RETURN v_n > 0;
END $$;

-- ── 0. Grants and function shape ─────────────────────────────────────────
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.mark_streak_viewed(uuid, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.mark_streak_viewed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated cannot call a mark_streak_viewed form';
  END IF;
  IF has_function_privilege('anon', 'public.mark_streak_viewed(uuid, uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.mark_streak_viewed(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can call mark_streak_viewed';
  END IF;
  IF has_function_privilege('authenticated', 'public.sweep_abandoned_streaks()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.sweep_abandoned_streaks()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can call sweep_abandoned_streaks';
  END IF;
  -- Review M-4: anon too, not only authenticated.
  IF has_function_privilege('authenticated', 'public.expire_streak_clips(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.expire_streak_clips(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can call expire_streak_clips';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid IN ('public.mark_streak_viewed(uuid, uuid)'::regprocedure,
                    'public.mark_streak_viewed(uuid)'::regprocedure,
                    'public.sweep_abandoned_streaks()'::regprocedure,
                    'public.expire_streak_clips(uuid)'::regprocedure,
                    'public.streak_clips_for_viewing(uuid)'::regprocedure,
                    'public.streak_replay_open(uuid)'::regprocedure,
                    'public.streak_recipient_may_sign(uuid)'::regprocedure)
      AND (NOT p.prosecdef
           OR NOT ('search_path=""' = ANY (COALESCE(p.proconfig, '{}'))))
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a streak function is not SECURITY DEFINER with an empty search_path';
  END IF;
  -- The ledger: RLS on, no policies, no client privilege.
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.streak_view_spends'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: streak_view_spends has RLS off';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'streak_view_spends') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: streak_view_spends has a client policy';
  END IF;
  IF has_table_privilege('authenticated', 'public.streak_view_spends', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('anon', 'public.streak_view_spends', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client holds a privilege on streak_view_spends';
  END IF;
END $$;

-- ── 1. Storage signs a streak's key only while it is viewable ────────────
DO $$
DECLARE
  v_new uuid; v_in uuid; v_out uuid; v_edge uuid; v_spent uuid; v_img uuid;
BEGIN
  v_new   := pg_temp.msg('streak', 1, NULL, 'chat/o1-new');
  v_in    := pg_temp.msg('streak', 2, interval '29 minutes 59 seconds', 'chat/o1-in');
  v_out   := pg_temp.msg('streak', 2, interval '31 minutes', 'chat/o1-out');
  v_edge  := pg_temp.msg('streak', 2, interval '30 minutes', 'chat/o1-edge');
  v_spent := pg_temp.msg('streak', 0, interval '1 minute', 'chat/o1-spent');
  v_img   := pg_temp.msg('image', 1, interval '2 hours', 'chat/o1-img', false);

  -- Recipient. Fix round 2: an unopened streak is signable only after the
  -- gated read has started its window (contract 8).
  IF pg_temp.signable(pg_temp.b(), 'chat/o1-new') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed a streak never read through the RPC';
  END IF;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/o1-in') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient cannot sign inside the window (29:59)';
  END IF;
  IF pg_temp.signable(pg_temp.b(), 'chat/o1-out') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed a streak past its window';
  END IF;
  IF pg_temp.signable(pg_temp.b(), 'chat/o1-edge') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed a streak at exactly 30:00';
  END IF;
  IF pg_temp.signable(pg_temp.b(), 'chat/o1-spent') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed a spent streak';
  END IF;
  -- Sender: until the recipient opens it.
  IF NOT pg_temp.signable(pg_temp.a(), 'chat/o1-new') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sender cannot sign their unopened streak';
  END IF;
  IF pg_temp.signable(pg_temp.a(), 'chat/o1-in') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sender signed a streak the recipient opened';
  END IF;
  -- Not a streak: unchanged (an opened image stays signable).
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/o1-img')
     OR NOT pg_temp.signable(pg_temp.a(), 'chat/o1-img') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the streak clause hid ordinary chat media';
  END IF;
  -- A non-member never.
  IF pg_temp.signable('7a000000-0000-0000-0000-0000000000c3', 'chat/o1-new') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member signed a streak';
  END IF;
END $$;

-- ── 2. The sweep destroys abandoned streaks, once ────────────────────────
DO $$
DECLARE
  v_job record; v_gone uuid; v_live uuid; v_new uuid; v_noclip uuid; v_n int;
BEGIN
  v_gone   := pg_temp.msg('streak', 2, interval '45 minutes', 'chat/o2-gone');
  v_live   := pg_temp.msg('streak', 2, interval '5 minutes', 'chat/o2-live');
  v_new    := pg_temp.msg('streak', 1, NULL, 'chat/o2-new');
  v_noclip := pg_temp.msg('streak', 1, interval '2 hours', 'chat/o2-noclip', false);

  -- What pg_cron runs, exactly as registered.
  SELECT * INTO v_job FROM cron.job WHERE jobname = 'sweep-abandoned-streaks';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sweep-abandoned-streaks is not scheduled';
  END IF;
  IF v_job.schedule <> '*/10 * * * *' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sweep runs on %, not every 10 minutes', v_job.schedule;
  END IF;
  EXECUTE v_job.command;

  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_gone) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left an abandoned streak''s clips';
  END IF;
  IF (SELECT streak_views_remaining FROM public.messages WHERE id = v_gone) <> 0
     OR (SELECT streak_views_remaining FROM public.messages WHERE id = v_noclip) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left an abandoned streak''s budget';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'message-media' AND object_name = 'chat/o2-gone'
                   AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep did not queue the abandoned object';
  END IF;
  IF pg_temp.signable(pg_temp.b(), 'chat/o2-gone') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a swept streak is still signable';
  END IF;
  -- Inside the window, or never opened: untouched.
  IF (SELECT count(*) FROM public.streak_clips WHERE message_id IN (v_live, v_new)) <> 2
     OR (SELECT streak_views_remaining FROM public.messages WHERE id = v_live) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep touched a viewable streak';
  END IF;
  -- Idempotent: nothing left to do, and nothing rewritten.
  v_n := public.sweep_abandoned_streaks();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second sweep found % streaks again', v_n;
  END IF;
  -- The partial index exists for it.
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname = 'messages_streak_first_anchor_idx') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep''s partial index is missing';
  END IF;
END $$;

-- ── 3. The clip read requires a live streak ──────────────────────────────
DO $$
DECLARE v_img uuid; v_del uuid; v_zero uuid; v_err text; v_n int; v_ctid tid;
BEGIN
  -- (a) A view-once video addressed to B, viewed long ago: not a streak.
  v_img := pg_temp.msg('video', 1, interval '2 hours', 'chat/o3-img', false);
  SELECT ctid INTO v_ctid FROM public.messages WHERE id = v_img;
  PERFORM pg_temp.as_user(pg_temp.b());
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(v_img);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Streak unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-streak id answered % (want Streak unavailable)', v_err;
  END IF;
  IF (SELECT ctid FROM public.messages WHERE id = v_img) <> v_ctid THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: reading a non-streak id wrote to it';
  END IF;

  -- (b) Deleted for everyone: empty, even with the clip row still there.
  v_del := pg_temp.msg('streak', 1, NULL, 'chat/o3-del');
  UPDATE public.messages SET deleted_at = now() WHERE id = v_del;
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_del);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted streak handed out % clips', v_n;
  END IF;

  -- (c) The destroy step touches messages only when it changes something.
  v_zero := pg_temp.msg('streak', 0, interval '1 minute', 'chat/o3-zero');
  SELECT ctid INTO v_ctid FROM public.messages WHERE id = v_zero;
  PERFORM public.expire_streak_clips(v_zero);
  IF (SELECT ctid FROM public.messages WHERE id = v_zero) <> v_ctid THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expire_streak_clips rewrote an already-spent message';
  END IF;
END $$;

-- ── 4. The spend is idempotent per open ──────────────────────────────────
DO $$
DECLARE
  v_msg uuid; v_open uuid := gen_random_uuid(); v_left int; v_again int;
  v_viewed timestamptz; v_err text;
BEGIN
  v_msg := pg_temp.msg('streak', 3, NULL, 'chat/o4');
  PERFORM pg_temp.as_user(pg_temp.b());

  v_left := public.mark_streak_viewed(v_msg, v_open);
  v_again := public.mark_streak_viewed(v_msg, v_open);
  IF v_left <> 2 OR v_again <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same open answered % then %', v_left, v_again;
  END IF;
  IF (SELECT streak_views_remaining FROM public.messages WHERE id = v_msg) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same open id decremented twice';
  END IF;
  SELECT viewed_at INTO v_viewed FROM public.messages WHERE id = v_msg;
  IF v_viewed IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first spend did not open the window';
  END IF;

  -- A different open is a different view.
  v_left := public.mark_streak_viewed(v_msg, gen_random_uuid());
  IF v_left <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second open left %, want 1', v_left;
  END IF;
  -- Retrying the first open still answers its own stored count.
  IF public.mark_streak_viewed(v_msg, v_open) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried open did not answer its stored count';
  END IF;

  -- The old 1-arg form still spends, once per call.
  v_left := public.mark_streak_viewed(v_msg);
  IF v_left <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 1-arg spend left %, want 0', v_left;
  END IF;
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clips survived the last view';
  END IF;
  -- The last view's object waits out the signed-URL TTL (10 min) so the
  -- clip being played right now is not drained mid-stream.
  IF NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                 WHERE bucket_id = 'message-media' AND object_name = 'chat/o4'
                   AND deleted_at IS NULL
                   AND not_before >= now() + interval '10 minutes') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the last view queued its object without the playback grace';
  END IF;
  IF (SELECT count(*) FROM public.streak_view_spends WHERE message_id = v_msg) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ledger does not hold one row per charged open';
  END IF;

  -- Sender: in flight spends nothing and records nothing; opened refuses.
  v_msg := pg_temp.msg('streak', 2, NULL, 'chat/o4-sender');
  PERFORM pg_temp.as_user(pg_temp.a());
  IF public.mark_streak_viewed(v_msg, gen_random_uuid()) <> 2
     OR EXISTS (SELECT 1 FROM public.messages WHERE id = v_msg AND viewed_at IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.streak_view_spends WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sender replay spent, opened or recorded';
  END IF;
  UPDATE public.messages SET viewed_at = now() WHERE id = v_msg;
  v_err := NULL;
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Streak already opened' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sender after open got %', v_err;
  END IF;

  -- Exact refusals (review M-4: not "any error").
  PERFORM pg_temp.as_user(pg_temp.b());
  v_err := NULL;
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg, NULL);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Open id required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a null open id got %', v_err;
  END IF;
  v_err := NULL;
  BEGIN
    PERFORM public.mark_streak_viewed(pg_temp.msg('image', 1, NULL, 'chat/o4-img', false), gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Streak unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: spending a non-streak got %', v_err;
  END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000c3');
  v_err := NULL;
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Streak unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-member spend got %', v_err;
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  v_err := NULL;
  BEGIN
    PERFORM public.mark_streak_viewed(v_msg, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS DISTINCT FROM 'Not authenticated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an anonymous spend got %', v_err;
  END IF;
END $$;

-- ── 5. One boundary: at exactly 30:00 the streak is gone everywhere ──────
DO $$
DECLARE v_rpc uuid; v_mark uuid; v_rls uuid; v_in uuid; v_n int;
BEGIN
  v_rpc  := pg_temp.msg('streak', 2, interval '30 minutes', 'chat/o5-rpc');
  v_mark := pg_temp.msg('streak', 2, interval '30 minutes', 'chat/o5-mark');
  v_rls  := pg_temp.msg('streak', 2, interval '30 minutes', 'chat/o5-rls');
  v_in   := pg_temp.msg('streak', 2, interval '29 minutes 59 seconds', 'chat/o5-in');
  PERFORM pg_temp.as_user(pg_temp.b());

  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_rpc);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the read RPC served % clips at exactly 30:00', v_n;
  END IF;
  IF public.mark_streak_viewed(v_mark, gen_random_uuid()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the spend RPC treated 30:00 as inside the window';
  END IF;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_rls;
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the table policy showed a clip at exactly 30:00';
  END IF;
  -- One second inside is still a replay.
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_in);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the read RPC refused a replay at 29:59';
  END IF;
  IF public.mark_streak_viewed(v_in, gen_random_uuid()) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the spend RPC refused a replay at 29:59';
  END IF;
END $$;

-- ── 6. Fix round 1 (review I-1): the first READ opens the window ────────
-- A recipient who fetched the clips but never spent used to keep an open
-- window forever (only the spend set viewed_at). first_read_at is stamped
-- by the recipient's first read of an attached streak; the window runs
-- from LEAST(viewed_at, first_read_at) everywhere it is checked (fix
-- round 2: strictly the first of the two; contract 9).
DO $$
DECLARE
  v_msg uuid; v_first timestamptz; v_n int; v_sender uuid; v_bare uuid;
  v_stale uuid; v_swept uuid;
BEGIN
  -- Server-only: clients can neither read nor write it.
  IF has_column_privilege('authenticated', 'public.messages', 'first_read_at', 'SELECT')
     OR has_column_privilege('authenticated', 'public.messages', 'first_read_at', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.messages', 'first_read_at', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach messages.first_read_at';
  END IF;

  -- A recipient read stamps it, spends nothing, and is not "Opened".
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/o6');
  PERFORM pg_temp.as_user(pg_temp.b());
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: first read got % clips', v_n; END IF;
  SELECT first_read_at INTO v_first FROM public.messages WHERE id = v_msg;
  IF v_first IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recipient read did not stamp first_read_at (%)', v_first;
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = v_msg
             AND (viewed_at IS NOT NULL OR streak_views_remaining <> 1)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a read spent the budget or marked it Opened';
  END IF;
  -- A repeat read keeps the FIRST value.
  UPDATE public.messages SET first_read_at = now() - interval '5 minutes' WHERE id = v_msg;
  PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);
  IF (SELECT first_read_at FROM public.messages WHERE id = v_msg)
     IS DISTINCT FROM now() - interval '5 minutes' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat read moved first_read_at';
  END IF;

  -- The sender's replay does not stamp it.
  v_sender := pg_temp.msg('streak', 1, NULL, 'chat/o6-sender');
  PERFORM pg_temp.as_user(pg_temp.a());
  PERFORM count(*) FROM public.streak_clips_for_viewing(v_sender);
  IF (SELECT first_read_at FROM public.messages WHERE id = v_sender) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sender read stamped first_read_at';
  END IF;

  -- Nothing to see yet (clip row not attached): no stamp.
  v_bare := pg_temp.msg('streak', 1, NULL, 'chat/o6-bare', false);
  PERFORM pg_temp.as_user(pg_temp.b());
  PERFORM count(*) FROM public.streak_clips_for_viewing(v_bare);
  IF (SELECT first_read_at FROM public.messages WHERE id = v_bare) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an empty read stamped first_read_at';
  END IF;

  -- 30 minutes after the first read, a never-spent streak is gone: not
  -- signable, not readable from the table, not readable via the RPC.
  v_stale := pg_temp.msg('streak', 1, NULL, 'chat/o6-stale');
  UPDATE public.messages SET first_read_at = now() - interval '30 minutes' WHERE id = v_stale;
  IF pg_temp.signable(pg_temp.b(), 'chat/o6-stale') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a streak read 30 min ago is still signable';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.b());
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_stale;
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the table policy showed a streak read 30 min ago';
  END IF;
  -- Still inside: 29:59 after the first read is readable and signable.
  v_n := 0;
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/o6-inside');
  UPDATE public.messages SET first_read_at = now() - interval '29 minutes 59 seconds' WHERE id = v_msg;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/o6-inside') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a streak read 29:59 ago is not signable';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.b());
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_stale);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the RPC served a streak read 30 min ago';
  END IF;
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_stale)
     OR (SELECT streak_views_remaining FROM public.messages WHERE id = v_stale) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the RPC did not destroy a streak read 30 min ago';
  END IF;
  -- And the spend agrees.
  v_msg := pg_temp.msg('streak', 2, NULL, 'chat/o6-spend');
  UPDATE public.messages SET first_read_at = now() - interval '31 minutes' WHERE id = v_msg;
  IF public.mark_streak_viewed(v_msg, gen_random_uuid()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the spend charged a streak read 31 min ago';
  END IF;

  -- The sweep expires a streak that was read and never spent.
  v_swept := pg_temp.msg('streak', 1, NULL, 'chat/o6-swept');
  UPDATE public.messages SET first_read_at = now() - interval '45 minutes' WHERE id = v_swept;
  PERFORM public.sweep_abandoned_streaks();
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_swept)
     OR (SELECT streak_views_remaining FROM public.messages WHERE id = v_swept) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep left a read-but-never-spent streak';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname = 'messages_streak_first_anchor_idx'
                 AND indexdef LIKE '%LEAST(viewed_at, first_read_at)%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep''s anchor index is missing';
  END IF;
  -- Earlier drafts of 140100 created these (task-5b re-review M-3); a dev
  -- database that ran one must not keep a stale second index on messages.
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
             AND indexname IN ('messages_streak_open_window_idx',
                               'messages_streak_window_anchor_idx')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft streak index survived the migration';
  END IF;
  -- The helper the policies use is callable by the signing role only.
  IF NOT has_function_privilege('authenticated', 'public.streak_replay_open(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.streak_replay_open(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.streak_recipient_may_sign(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.streak_recipient_may_sign(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: streak_replay_open grants are wrong';
  END IF;
END $$;

-- ── 7. Fix round 1 (review M-1): a tap before the clip row lands is free ─
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/o7', false);  -- not attached yet
  PERFORM pg_temp.as_user(pg_temp.b());
  -- The viewer's empty-fetch budget sync.
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: clips before attach'; END IF;
  IF public.mark_streak_viewed(v_msg, gen_random_uuid()) <> 1
     OR public.mark_streak_viewed(v_msg) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a spend before the attach charged the streak';
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE id = v_msg
             AND (viewed_at IS NOT NULL OR streak_views_remaining <> 1))
     OR EXISTS (SELECT 1 FROM public.streak_view_spends WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a spend before the attach opened, charged or recorded';
  END IF;
  -- The attach lands: now it is viewable.
  INSERT INTO public.streak_clips (message_id, clip_index, media_url, duration_ms)
  VALUES (v_msg, 0, 'chat/o7', 3000);
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the attached streak is not viewable'; END IF;
  IF public.mark_streak_viewed(v_msg, gen_random_uuid()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the attached streak did not spend';
  END IF;
END $$;

-- ── 8. Fix round 2: no signing before the gated read ────────────────────
-- A client that never called streak_clips_for_viewing (key taken from
-- messages.media_url, signed directly) left the window unanchored and
-- could sign an unopened streak forever. The recipient may now sign only
-- once the window has started (first read or first view).
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/o8');
  IF pg_temp.signable(pg_temp.b(), 'chat/o8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed before any read';
  END IF;
  -- The sender is unchanged: their unopened streak signs.
  IF NOT pg_temp.signable(pg_temp.a(), 'chat/o8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sender can no longer sign their unopened streak';
  END IF;
  -- The honest order: read RPC (stamps), then sign.
  PERFORM pg_temp.as_user(pg_temp.b());
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: read got %', v_n; END IF;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/o8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient cannot sign after the read';
  END IF;
  -- 30 minutes after that read: refused again.
  UPDATE public.messages SET first_read_at = now() - interval '30 minutes' WHERE id = v_msg;
  IF pg_temp.signable(pg_temp.b(), 'chat/o8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recipient signed 30 min after the read';
  END IF;
  -- The read RPC is VOLATILE, so PostgREST runs it read-write and the
  -- stamp commits with the call, before the client's sign request.
  IF (SELECT provolatile FROM pg_proc
      WHERE oid = 'public.streak_clips_for_viewing(uuid)'::regprocedure) <> 'v' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: streak_clips_for_viewing is not VOLATILE (its stamp would not commit)';
  END IF;
END $$;

-- ── 9. Fix round 2: the window is anchored strictly at the first read ───
-- Read at T, spend at T+29 (viewed_at = T+29): the window still closes at
-- T+30. Simulated at "now = T+30": first_read_at = now()-30m,
-- viewed_at = now()-1m.
DO $$
DECLARE v_msg uuid; v_spend uuid; v_sweep uuid; v_n int;
BEGIN
  v_msg   := pg_temp.msg('streak', 3, interval '1 minute', 'chat/o9');
  v_spend := pg_temp.msg('streak', 3, interval '1 minute', 'chat/o9-spend');
  v_sweep := pg_temp.msg('streak', 3, interval '1 minute', 'chat/o9-sweep');
  UPDATE public.messages SET first_read_at = now() - interval '30 minutes'
  WHERE id IN (v_msg, v_spend, v_sweep);
  IF pg_temp.signable(pg_temp.b(), 'chat/o9') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late spend extended the signing window';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.b());
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.streak_clips WHERE message_id = v_msg;
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late spend extended the table read window';
  END IF;
  IF public.mark_streak_viewed(v_spend, gen_random_uuid()) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late spend extended the spend window';
  END IF;
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a late spend extended the read window';
  END IF;
  PERFORM public.sweep_abandoned_streaks();
  IF EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_sweep) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep honoured a late spend''s window';
  END IF;
  -- A spend later than the read never moves the anchor (the honest flow:
  -- read at T, presented seconds later): one second inside still plays.
  v_msg := pg_temp.msg('streak', 3, interval '1 minute', 'chat/o9-in');
  UPDATE public.messages SET first_read_at = now() - interval '29 minutes 59 seconds'
  WHERE id = v_msg;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/o9-in') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: refused inside the first-read window';
  END IF;
END $$;

-- ── Mutation checks: each key rule, broken, is caught ────────────────────

-- M1. The storage policy without the streak clause (the pre-140100 one)
--     lets the recipient sign past the window: contract 1 would fail.
SAVEPOINT m_storage;
DROP POLICY message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'message-media'
         AND EXISTS (SELECT 1 FROM public.messages m
                     WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name)
                       AND public.relationship_chat_open(m.relationship_id)));
DO $$
BEGIN
  PERFORM pg_temp.msg('streak', 2, interval '31 minutes', 'chat/m1');
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/m1') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 1 passed without the storage streak clause';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_storage;

-- M1b. A sender branch of `true` lets the sender sign after open.
SAVEPOINT m_storage_sender;
DROP POLICY message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'message-media'
         AND EXISTS (SELECT 1 FROM public.messages m
                     WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name)
                       AND public.relationship_chat_open(m.relationship_id)
                       AND (m.media_type IS DISTINCT FROM 'streak'
                            OR m.sender_id = auth.uid()
                            OR (COALESCE(m.streak_views_remaining, 0) > 0
                                AND (m.viewed_at IS NULL
                                     OR m.viewed_at > now() - interval '30 minutes')))));
DO $$
BEGIN
  PERFORM pg_temp.msg('streak', 2, interval '1 minute', 'chat/m1b');
  IF NOT pg_temp.signable(pg_temp.a(), 'chat/m1b') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 1 passed with sender signing after open';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_storage_sender;

-- M2. A sweep that does nothing leaves the abandoned clips: contract 2.
SAVEPOINT m_sweep;
CREATE OR REPLACE FUNCTION public.sweep_abandoned_streaks() RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT 0 $$;
DO $$
DECLARE v_msg uuid; v_cmd text;
BEGIN
  v_msg := pg_temp.msg('streak', 2, interval '45 minutes', 'chat/m2');
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'sweep-abandoned-streaks';
  EXECUTE v_cmd;
  IF NOT EXISTS (SELECT 1 FROM public.streak_clips WHERE message_id = v_msg) THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 2 passed with a no-op sweep';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_sweep;

-- M3. The read without the live-streak check writes to a non-streak id
--     (the 140000 body): contract 3a.
SAVEPOINT m_live;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_msg public.messages%ROWTYPE;
BEGIN
  SELECT * INTO v_msg FROM public.messages m WHERE m.id = p_message_id;
  IF v_msg.sender_id <> auth.uid()
     AND COALESCE(v_msg.streak_views_remaining, 0) > 0
     AND v_msg.viewed_at <= now() - interval '30 minutes' THEN
    PERFORM public.expire_streak_clips(p_message_id);
    RETURN;
  END IF;
  RETURN QUERY SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c WHERE c.message_id = p_message_id;
END $$;
DO $$
DECLARE v_img uuid; v_err text; v_ctid tid;
BEGIN
  v_img := pg_temp.msg('video', 1, interval '2 hours', 'chat/m3', false);
  SELECT ctid INTO v_ctid FROM public.messages WHERE id = v_img;
  PERFORM pg_temp.as_user(pg_temp.b());
  BEGIN
    PERFORM count(*) FROM public.streak_clips_for_viewing(v_img);
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  IF v_err IS NOT DISTINCT FROM 'Streak unavailable'
     AND (SELECT ctid FROM public.messages WHERE id = v_img) = v_ctid THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 3a passed without the live-streak check';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_live;

-- M3b. The destroy step without `AND streak_views_remaining <> 0`
--      rewrites a spent message: contract 3c.
SAVEPOINT m_expire;
CREATE OR REPLACE FUNCTION public.expire_streak_clips(p_message_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  DELETE FROM public.streak_clips c WHERE c.message_id = p_message_id;
  UPDATE public.messages m SET streak_views_remaining = 0 WHERE m.id = p_message_id;
END $$;
DO $$
DECLARE v_zero uuid; v_ctid tid;
BEGIN
  v_zero := pg_temp.msg('streak', 0, interval '1 minute', 'chat/m3b');
  SELECT ctid INTO v_ctid FROM public.messages WHERE id = v_zero;
  PERFORM public.expire_streak_clips(v_zero);
  IF (SELECT ctid FROM public.messages WHERE id = v_zero) = v_ctid THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 3c passed with an unconditional UPDATE';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_expire;

-- M4. A spend without the ledger decrements on every call: contract 4.
SAVEPOINT m_ledger;
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid, p_open_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_left int;
BEGIN
  UPDATE public.messages m
     SET streak_views_remaining = GREATEST(COALESCE(m.streak_views_remaining, 0) - 1, 0),
         viewed_at = COALESCE(m.viewed_at, now())
   WHERE m.id = p_message_id RETURNING m.streak_views_remaining INTO v_left;
  RETURN v_left;
END $$;
DO $$
DECLARE v_msg uuid; v_open uuid := gen_random_uuid();
BEGIN
  v_msg := pg_temp.msg('streak', 3, NULL, 'chat/m4');
  PERFORM pg_temp.as_user(pg_temp.b());
  PERFORM public.mark_streak_viewed(v_msg, v_open);
  PERFORM public.mark_streak_viewed(v_msg, v_open);
  IF (SELECT streak_views_remaining FROM public.messages WHERE id = v_msg) = 2 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 4 passed without the ledger';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_ledger;

-- M5. The old `<` boundary still serves at exactly 30:00: contract 5.
SAVEPOINT m_boundary;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_msg public.messages%ROWTYPE;
BEGIN
  SELECT * INTO v_msg FROM public.messages m WHERE m.id = p_message_id;
  IF v_msg.viewed_at < now() - interval '30 minutes' THEN
    PERFORM public.expire_streak_clips(p_message_id);
    RETURN;
  END IF;
  RETURN QUERY SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c WHERE c.message_id = p_message_id;
END $$;
DO $$
DECLARE v_msg uuid; v_n int;
BEGIN
  v_msg := pg_temp.msg('streak', 2, interval '30 minutes', 'chat/m5');
  PERFORM pg_temp.as_user(pg_temp.b());
  SELECT count(*) INTO v_n FROM public.streak_clips_for_viewing(v_msg);
  IF v_n = 0 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 5 passed with the < boundary';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_boundary;

-- M6. A client grant on the sweep or on the ledger: contract 0.
SAVEPOINT m_grant;
GRANT EXECUTE ON FUNCTION public.sweep_abandoned_streaks() TO authenticated;
GRANT SELECT ON public.streak_view_spends TO authenticated;
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.sweep_abandoned_streaks()', 'EXECUTE')
     OR NOT has_table_privilege('authenticated', 'public.streak_view_spends', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 0 cannot see a client grant';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_grant;

-- M7. A read that does not stamp first_read_at leaves the window unanchored:
--     contract 6.
SAVEPOINT m_first_read;
CREATE OR REPLACE FUNCTION public.streak_clips_for_viewing(p_message_id uuid)
RETURNS TABLE (clip_index int, media_url text, duration_ms int, media_kind text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN QUERY SELECT c.clip_index, c.media_url, c.duration_ms, c.media_kind
    FROM public.streak_clips c WHERE c.message_id = p_message_id;
END $$;
DO $$
DECLARE v_msg uuid;
BEGIN
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/m7');
  PERFORM pg_temp.as_user(pg_temp.b());
  PERFORM count(*) FROM public.streak_clips_for_viewing(v_msg);
  IF (SELECT first_read_at FROM public.messages WHERE id = v_msg) IS NOT NULL THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 6 passed with a read that stamps nothing';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_first_read;

-- M7b. A window anchored on viewed_at alone (the pre-fix helper) keeps a
--      read-but-never-spent streak signable: contract 6.
SAVEPOINT m_anchor;
CREATE OR REPLACE FUNCTION public.streak_replay_open(p_message_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.messages m WHERE m.id = p_message_id
    AND COALESCE(m.streak_views_remaining, 0) > 0
    AND (m.viewed_at IS NULL OR m.viewed_at > now() - interval '30 minutes')) $$;
DO $$
DECLARE v_msg uuid;
BEGIN
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/m7b');
  UPDATE public.messages SET first_read_at = now() - interval '2 hours' WHERE id = v_msg;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/m7b') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 6 passed with a viewed_at-only anchor';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_anchor;

-- M8. A spend without the "not attached yet" guard burns the streak:
--     contract 7.
SAVEPOINT m_unattached;
CREATE OR REPLACE FUNCTION public.mark_streak_viewed(p_message_id uuid, p_open_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_left int;
BEGIN
  UPDATE public.messages m
     SET streak_views_remaining = GREATEST(COALESCE(m.streak_views_remaining, 0) - 1, 0),
         viewed_at = COALESCE(m.viewed_at, now())
   WHERE m.id = p_message_id RETURNING m.streak_views_remaining INTO v_left;
  RETURN v_left;
END $$;
DO $$
DECLARE v_msg uuid;
BEGIN
  v_msg := pg_temp.msg('streak', 1, NULL, 'chat/m8', false);
  PERFORM pg_temp.as_user(pg_temp.b());
  IF public.mark_streak_viewed(v_msg, gen_random_uuid()) = 1 THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 7 passed without the attach guard';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_unattached;

-- M9. A storage recipient branch without the "window started" check signs
--     a streak nobody read through the RPC: contract 8.
SAVEPOINT m_started;
DROP POLICY message_media_select_relationship_members ON storage.objects;
CREATE POLICY message_media_select_relationship_members ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'message-media'
         AND EXISTS (SELECT 1 FROM public.messages m
                     WHERE (m.media_url = objects.name OR m.media_thumbnail_url = objects.name)
                       AND public.relationship_chat_open(m.relationship_id)
                       AND (m.media_type IS DISTINCT FROM 'streak'
                            OR CASE WHEN m.sender_id = auth.uid() THEN m.viewed_at IS NULL
                                    ELSE public.streak_replay_open(m.id) END)));
DO $$
BEGIN
  PERFORM pg_temp.msg('streak', 1, NULL, 'chat/m9');
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/m9') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 8 passed without the started check';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_started;

-- M10. A COALESCE anchor lets a late spend move the window: contract 9.
SAVEPOINT m_coalesce;
CREATE OR REPLACE FUNCTION public.streak_replay_open(p_message_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.messages m WHERE m.id = p_message_id
    AND COALESCE(m.streak_views_remaining, 0) > 0
    AND (COALESCE(m.viewed_at, m.first_read_at) IS NULL
         OR COALESCE(m.viewed_at, m.first_read_at) > now() - interval '30 minutes')) $$;
DO $$
DECLARE v_msg uuid;
BEGIN
  v_msg := pg_temp.msg('streak', 3, interval '1 minute', 'chat/m10');
  UPDATE public.messages SET first_read_at = now() - interval '30 minutes' WHERE id = v_msg;
  IF NOT pg_temp.signable(pg_temp.b(), 'chat/m10') THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: contract 9 passed with a COALESCE anchor';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_coalesce;

-- M11. A draft index left behind is caught: contract 6's draft-index check.
SAVEPOINT m_draft_index;
CREATE INDEX messages_streak_open_window_idx ON public.messages (viewed_at)
  WHERE media_type = 'streak' AND streak_views_remaining > 0;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
                 AND indexname IN ('messages_streak_open_window_idx',
                                   'messages_streak_window_anchor_idx')) THEN
    RAISE EXCEPTION 'MUTATION NOT DETECTED: a draft streak index went unseen';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT m_draft_index;

ROLLBACK;
