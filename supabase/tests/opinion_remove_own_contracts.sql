-- supabase/tests/opinion_remove_own_contracts.sql
-- Spec 1 W9b (§4.3 W9b, §7.1, §9; OPN-DELETE-RLS): as authenticated, the
-- author's remove_my_opinion sets removed_at and the opinion leaves
-- Discover, its tag page and the Following feed; remove_my_comment sets
-- removed_at and lowers the parent's comment_count by exactly 1, once; a
-- second call changes nothing; someone else's call changes nothing; a
-- banned author can still remove; anon is refused; comment_count never goes
-- below 0; and a direct client UPDATE of removed_at by the author is still
-- refused (the fix is the RPC, not a looser policy). Fix round 1: a post's
-- author cannot remove someone else's comment on it, no other post's count
-- moves, replies stay, and the count helpers' grant state is pinned (A).
-- Section C (batch-5
-- carry): the same calls give the same outcome with opinions_safety_v1 off
-- and on, a banned author removes a comment too, and a repeat never
-- re-stamps removed_at.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_remove_own_contracts.sql
-- Fixture ids 5f9c0000-0000-0000-0000-0000000000NN, phones +155586020NN
-- (spec §7.1's W9 range) on auth.users and public.users.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- The message raised by [p_sql] run as [p_user] (NULL when it ran).
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- Does [p_viewer] see opinion [p_id] in Discover, on the tag page and in
-- Following?
CREATE FUNCTION pg_temp.seen(p_viewer uuid, p_id uuid, p_tag text)
RETURNS TABLE (discover boolean, tag boolean, following boolean) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user(p_viewer);
  discover := EXISTS (SELECT 1 FROM public.get_discover_opinions(200, 0, NULL) AS d WHERE d.id = p_id);
  tag := EXISTS (SELECT 1 FROM public.get_opinions_by_tag(p_tag, 200, 0) AS t WHERE t.id = p_id);
  following := EXISTS (SELECT 1 FROM public.get_following_opinions(200, 0) AS f WHERE f.id = p_id);
  RESET ROLE;
  RETURN NEXT;
END $$;

INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586020' || n FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586020' || n, 'W9b remove ' || n FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02']) AS n
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Grants: signed-in only; no SELECT policy was loosened.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.remove_my_opinion(uuid)') IS NULL
     OR to_regprocedure('public.remove_my_comment(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove_my_opinion / remove_my_comment are missing';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.remove_my_opinion(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.remove_my_comment(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.remove_my_opinion(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.remove_my_comment(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove_my_* grants are wrong (signed-in only, never anon)';
  END IF;
  -- Fix round 1, I-3: the unowned count helpers keep EXECUTE for
  -- authenticated in W9 (a pre-W9 build's deleteComment still calls
  -- decrement after its direct UPDATE); never anon or PUBLIC. The revoke is
  -- an owner-checklist item once the W9 client is the minimum supported
  -- build; the migration that does it flips this check.
  IF NOT has_function_privilege('authenticated', 'public.increment_opinion_comment_count(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.decrement_opinion_comment_count(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.increment_opinion_comment_count(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.decrement_opinion_comment_count(uuid)', 'EXECUTE')
     OR EXISTS (
          SELECT 1
            FROM pg_proc AS f, aclexplode(f.proacl) AS a
           WHERE f.oid IN ('public.increment_opinion_comment_count(uuid)'::regprocedure,
                           'public.decrement_opinion_comment_count(uuid)'::regprocedure)
             AND a.grantee = 0) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the comment-count helpers changed grant state (W9: authenticated keeps EXECUTE until the owner revoke; never anon or PUBLIC)';
  END IF;
  IF (SELECT qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'opinions' AND policyname = 'opinions_public_read')
       IS DISTINCT FROM '((removed_at IS NULL) AND (hidden_pending_review = false))'
     OR (SELECT qual FROM pg_policies WHERE schemaname = 'public' AND tablename = 'opinion_comments' AND policyname = 'opinion_comments_public_read')
       IS DISTINCT FROM '((removed_at IS NULL) AND (hidden_pending_review = false))' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a SELECT policy on opinions or opinion_comments was changed';
  END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN
    PERFORM public.remove_my_opinion(gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon ran remove_my_opinion';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.remove_my_comment(gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon ran remove_my_comment';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $$;

-- =====================================================================
-- B. Opinions and comments.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.id('01');
  v_b constant uuid := pg_temp.id('02');
  v_tag constant text := (SELECT slug FROM public.tags ORDER BY slug LIMIT 1);
  v_o uuid;
  v_o2 uuid;
  v_o3 uuid;
  v_c1 uuid;
  v_c2 uuid;
  v_cb uuid;
  v_r1 uuid;
  v_r2 uuid;
  v_handle text;
  v_msg text;
  s record;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'W9b contract: my post, to delete.') RETURNING id INTO v_o;
  INSERT INTO public.opinions (user_id, content, comment_count) VALUES (v_a, 'W9b contract: a post with comments.', 0) RETURNING id INTO v_o2;
  -- Fix round 1, I-1: a control post whose count no removal may touch.
  INSERT INTO public.opinions (user_id, content, comment_count) VALUES (v_a, 'W9b contract: a control post.', 5) RETURNING id INTO v_o3;
  INSERT INTO public.opinion_tags (opinion_id, tag_id) SELECT v_o, t.id FROM public.tags AS t WHERE t.slug = v_tag;
  -- B follows A (by the opaque handle, as the app does).
  PERFORM pg_temp.as_user(v_b);
  SELECT d.author_handle INTO v_handle FROM public.get_discover_opinions(200, 0, NULL) AS d WHERE d.id = v_o;
  PERFORM public.follow_opinion_author(v_handle);
  RESET ROLE;
  SELECT * INTO s FROM pg_temp.seen(v_b, v_o, v_tag);
  IF NOT (s.discover AND s.tag AND s.following) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: B does not see the post before removal (%, %, %)', s.discover, s.tag, s.following;
  END IF;

  -- A direct client UPDATE of removed_at is still refused (RLS).
  v_msg := pg_temp.err_as(v_a, format('UPDATE public.opinions SET removed_at = now() WHERE id = %L', v_o));
  IF coalesce(v_msg, '') !~ 'row-level security' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client UPDATE of removed_at was not refused by RLS (%)', v_msg;
  END IF;

  -- Someone else: nothing changes, nothing is raised. (Each call is its own
  -- statement: a check in the same statement would read the snapshot from
  -- before the call.)
  v_msg := pg_temp.err_as(v_b, format('SELECT public.remove_my_opinion(%L)', v_o));
  IF v_msg IS NOT NULL OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user removed the opinion, or the call raised';
  END IF;

  -- A banned author still removes (removing is not posting).
  UPDATE public.profiles SET banned_until = now() + interval '7 days' WHERE id = v_a;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o));
  IF v_msg IS NOT NULL OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author could not remove their own opinion';
  END IF;
  SELECT * INTO s FROM pg_temp.seen(v_b, v_o, v_tag);
  IF s.discover OR s.tag OR s.following THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a removed opinion still shows (discover %, tag %, following %)', s.discover, s.tag, s.following;
  END IF;
  -- Again: nothing, no error; a missing id: nothing.
  IF pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o)) IS NOT NULL
     OR pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', gen_random_uuid())) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeat or missing remove_my_opinion raised';
  END IF;
  UPDATE public.profiles SET banned_until = NULL WHERE id = v_a;

  -- Comments: A's two comments on A's post, counted 2.
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_o2, v_a, 'W9b contract: first') RETURNING id INTO v_c1;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_o2, v_a, 'W9b contract: second') RETURNING id INTO v_c2;
  -- Fix round 1: B's comment on A's post (I-2), and two replies to v_c1,
  -- one by A and one by B (M-1). The count is a fixture value.
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_o2, v_b, 'W9b contract: B on A''s post') RETURNING id INTO v_cb;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content, reply_to_comment_id) VALUES (v_o2, v_a, 'W9b contract: A replies', v_c1) RETURNING id INTO v_r1;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content, reply_to_comment_id) VALUES (v_o2, v_b, 'W9b contract: B replies', v_c1) RETURNING id INTO v_r2;
  UPDATE public.opinions SET comment_count = 2 WHERE id = v_o2;
  v_msg := pg_temp.err_as(v_a, format('UPDATE public.opinion_comments SET removed_at = now() WHERE id = %L', v_c1));
  IF coalesce(v_msg, '') !~ 'row-level security' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client UPDATE of a comment''s removed_at was not refused (%)', v_msg;
  END IF;
  v_msg := pg_temp.err_as(v_b, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c1) IS NOT NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another user''s remove_my_comment changed the comment or the count';
  END IF;
  -- Fix round 1, I-2: owning the post is not owning the comment.
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_cb));
  IF v_msg IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_cb) IS NOT NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the post''s author removed someone else''s comment on their post, or the call raised (%)', v_msg;
  END IF;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c1) IS NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author''s remove_my_comment did not remove it and lower the count by 1 (count %)',
      (SELECT comment_count FROM public.opinions WHERE id = v_o2);
  END IF;
  -- Fix round 1, I-1: no other post's count moved.
  IF (SELECT comment_count FROM public.opinions WHERE id = v_o3) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove_my_comment changed another post''s comment_count (control %)',
      (SELECT comment_count FROM public.opinions WHERE id = v_o3);
  END IF;
  -- Fix round 1, M-1: the comment's replies (A's and B's) stay as they were.
  IF (SELECT removed_at FROM public.opinion_comments WHERE id = v_r1) IS NOT NULL
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_r2) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing a comment also removed its replies';
  END IF;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c1));
  IF v_msg IS NOT NULL OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second remove_my_comment decremented again';
  END IF;
  -- Never below 0.
  UPDATE public.opinions SET comment_count = 0 WHERE id = v_o2;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c2));
  IF v_msg IS NOT NULL
     OR (SELECT comment_count FROM public.opinions WHERE id = v_o2) <> 0
     OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c2) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: comment_count went below 0, or the comment stayed';
  END IF;
END $$;

-- =====================================================================
-- C. Ungated (batch-5 carry): the same calls give the same outcome with
-- opinions_safety_v1 off and on (removing is never a posting act, so a
-- banned author removes a comment as well as a post), and a repeat on an
-- already-removed opinion or comment never re-stamps removed_at (a
-- moderator's removal time is kept).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.id('01');
  v_b constant uuid := pg_temp.id('02');
  v_then constant timestamptz := now() - interval '1 day';
  v_flag boolean;
  v_o uuid;
  v_c uuid;
  v_msg text;
BEGIN
  FOREACH v_flag IN ARRAY ARRAY[false, true] LOOP
    UPDATE public.feature_flags SET enabled = v_flag WHERE key = 'opinions_safety_v1';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: no opinions_safety_v1 flag row';
    END IF;
    INSERT INTO public.opinions (user_id, content, comment_count)
    VALUES (v_a, 'W9b contract C: flag ' || v_flag, 1) RETURNING id INTO v_o;
    INSERT INTO public.opinion_comments (opinion_id, user_id, content)
    VALUES (v_o, v_a, 'W9b contract C: comment, flag ' || v_flag) RETURNING id INTO v_c;

    -- Someone else: nothing changes, nothing is raised.
    v_msg := coalesce(pg_temp.err_as(v_b, format('SELECT public.remove_my_opinion(%L)', v_o)), '')
          || coalesce(pg_temp.err_as(v_b, format('SELECT public.remove_my_comment(%L)', v_c)), '');
    IF v_msg <> ''
       OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NOT NULL
       OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c) IS NOT NULL
       OR (SELECT comment_count FROM public.opinions WHERE id = v_o) <> 1 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 %, another user''s remove changed something or raised (%)', v_flag, v_msg;
    END IF;

    -- The author, banned (removing is never a posting act): both removed,
    -- the count lowered once.
    UPDATE public.profiles SET banned_until = now() + interval '7 days' WHERE id = v_a;
    v_msg := coalesce(pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c)), '')
          || coalesce(pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o)), '');
    IF v_msg <> ''
       OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS NULL
       OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c) IS NULL
       OR (SELECT comment_count FROM public.opinions WHERE id = v_o) <> 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 %, the author''s remove did not hold (count %, %)',
        v_flag, (SELECT comment_count FROM public.opinions WHERE id = v_o), v_msg;
    END IF;
    UPDATE public.profiles SET banned_until = NULL WHERE id = v_a;

    -- A repeat keeps the first removal time.
    UPDATE public.opinions SET removed_at = v_then WHERE id = v_o;
    UPDATE public.opinion_comments SET removed_at = v_then WHERE id = v_c;
    v_msg := coalesce(pg_temp.err_as(v_a, format('SELECT public.remove_my_opinion(%L)', v_o)), '')
          || coalesce(pg_temp.err_as(v_a, format('SELECT public.remove_my_comment(%L)', v_c)), '');
    IF v_msg <> ''
       OR (SELECT removed_at FROM public.opinions WHERE id = v_o) IS DISTINCT FROM v_then
       OR (SELECT removed_at FROM public.opinion_comments WHERE id = v_c) IS DISTINCT FROM v_then THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: with opinions_safety_v1 %, a repeat remove re-stamped removed_at or raised', v_flag;
    END IF;
  END LOOP;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_remove_own_contracts: all held'; END $$;
ROLLBACK;
