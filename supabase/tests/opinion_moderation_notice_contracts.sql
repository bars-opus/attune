-- supabase/tests/opinion_moderation_notice_contracts.sql
-- Spec 1 W9b (D17, §4.3 W9b, §7.1, §7.4; OPN-BAN-42702): as the service
-- role, admin_confirm_content_removal queues "Post removed" for the author
-- of each removal it confirms (opinion_id or comment_id), nothing for
-- content already removed, and "Posting paused" when the 7-day ban starts
-- or moves. It reaches strike 3 without 42702, sets the first ban 7 days
-- ahead and moves a later one forward from the existing ban, never back,
-- with the W1a profiles guard in place. Strikes 1 and 2 return exactly what
-- the live function returned. Clients cannot call it. Nobody but the author
-- is told anything.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_moderation_notice_contracts.sql
-- Fixture ids 5f9b0000-0000-0000-0000-0000000000NN, phones +155586010NN
-- (spec §7.1's W9 range) on auth.users and public.users.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f9b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- The connecting (owner) role with a service-role JWT: how the SQL editor
-- and edge functions reach admin_confirm_content_removal.
CREATE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
END $$;

-- Pending notices of [p_type] for [p_user].
CREATE FUNCTION pg_temp.notices(p_user uuid, p_type text) RETURNS SETOF jsonb LANGUAGE sql AS $$
  SELECT n.metadata FROM public.scheduled_notifications AS n
   WHERE n.user_id = p_user AND n.metadata->>'type' = p_type
   ORDER BY n.created_at, n.id;
$$;

INSERT INTO auth.users (id, phone)
SELECT pg_temp.id(n), '155586010' || n FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name)
SELECT pg_temp.id(n), '+155586010' || n, 'W9b notices ' || n FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id)
SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02', '03']) AS n
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Grants and the guard: service role only; the W1a moderation guard is
--    on profiles (the definer still moves both columns, below).
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  IF has_function_privilege('anon', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: admin_confirm_content_removal must be the service role''s only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.profiles'::regclass
                  AND tgname = 'profiles_guard_moderation_columns' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1a profiles guard is missing, so this contract proves nothing about it';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', pg_temp.id('01'), 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_confirm_content_removal('opinion', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in client ran admin_confirm_content_removal';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF coalesce(v_msg, '') !~ 'permission denied' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected permission denied (42501), got %', v_msg;
    END IF;
  END;
  RESET ROLE;
  -- The function's own gate: a client JWT is refused even for its owner.
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_confirm_content_removal('opinion', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: admin_confirm_content_removal answered an authenticated JWT';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'forbidden' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected forbidden, got %', v_msg; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- =====================================================================
-- B. The ladder: A's five opinions removed one by one (the fifth after
--    A's ban has run out); B's comment once; a repeat removal changes
--    nothing.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.id('01');
  v_b constant uuid := pg_temp.id('02');
  v_bystander constant uuid := pg_temp.id('03');
  v_o uuid[] := ARRAY[]::uuid[];
  v_c uuid;
  v_id uuid;
  v_before_others int;
  v_first_ban timestamptz;
  r record;
  m jsonb;
  i int;
BEGIN
  FOR i IN 1 .. 5 LOOP
    INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'W9b contract: post ' || i) RETURNING id INTO v_id;
    v_o := v_o || v_id;
  END LOOP;
  INSERT INTO public.opinion_comments (opinion_id, user_id, content)
  VALUES (v_o[1], v_b, 'W9b contract: a comment to remove') RETURNING id INTO v_c;
  SELECT count(*) INTO v_before_others FROM public.scheduled_notifications WHERE user_id NOT IN (v_a, v_b);

  PERFORM pg_temp.as_service();

  -- Strike 1: exactly the live answer, and one removal notice with the opinion.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[1]);
  IF r.violation_count IS DISTINCT FROM 1 OR r.banned_until IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 1 returned (%, %), expected (1, NULL)', r.violation_count, r.banned_until;
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 1 queued % removal notices, expected 1', (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed'));
  END IF;
  m := (SELECT x FROM pg_temp.notices(v_a, 'forum_content_removed') AS x LIMIT 1);
  IF m->>'opinion_id' IS DISTINCT FROM v_o[1]::text OR m ? 'comment_id'
     OR m->>'title' IS DISTINCT FROM 'Post removed'
     OR m->>'body' IS DISTINCT FROM 'One of your posts was removed for breaking the Opinions guidelines.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the removal notice is wrong: %', m;
  END IF;

  -- The same opinion again: nothing.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[1]);
  IF r.violation_count IS DISTINCT FROM 0 OR r.banned_until IS NOT NULL
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 1
     OR (SELECT confirmed_violation_count FROM public.profiles WHERE id = v_a) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing already-removed content changed something';
  END IF;

  -- A comment: one notice with the comment.
  SELECT * INTO r FROM public.admin_confirm_content_removal('comment', v_c);
  IF r.violation_count IS DISTINCT FROM 1
     OR (SELECT count(*) FROM pg_temp.notices(v_b, 'forum_content_removed')) <> 1
     OR (SELECT x->>'comment_id' FROM pg_temp.notices(v_b, 'forum_content_removed') AS x LIMIT 1) IS DISTINCT FROM v_c::text
     OR (SELECT x ? 'opinion_id' FROM pg_temp.notices(v_b, 'forum_content_removed') AS x LIMIT 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a comment removal did not queue one notice with comment_id';
  END IF;

  -- Strike 2: exactly the live answer; no ban notice yet.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[2]);
  IF r.violation_count IS DISTINCT FROM 2 OR r.banned_until IS NOT NULL
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 2 returned (%, %) or queued a ban notice', r.violation_count, r.banned_until;
  END IF;

  -- Strike 3 (OPN-BAN-42702): no 42702; the first ban, 7 days ahead.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[3]);
  IF r.violation_count IS DISTINCT FROM 3 OR r.banned_until IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 returned (%, %), expected (3, now() + 7 days)', r.violation_count, r.banned_until;
  END IF;
  IF (SELECT confirmed_violation_count FROM public.profiles WHERE id = v_a) <> 3
     OR (SELECT banned_until FROM public.profiles WHERE id = v_a) IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 did not leave count 3 and a ban 7 days ahead';
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 1
     OR (SELECT x->>'body' FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x LIMIT 1) IS DISTINCT FROM 'You can''t post in Opinions for 7 days.'
     OR (SELECT x->>'title' FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x LIMIT 1) IS DISTINCT FROM 'Posting paused'
     OR (SELECT bool_or(x ? 'opinion_id' OR x ? 'comment_id') FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 3 did not queue one new-ban notice: %',
      (SELECT jsonb_agg(x) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x);
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A has % removal notices after three removals', (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_content_removed'));
  END IF;
  v_first_ban := (SELECT banned_until FROM public.profiles WHERE id = v_a);

  -- Strike 4, during the ban: forward 7 days from the ban, never back.
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[4]);
  IF r.violation_count IS DISTINCT FROM 4 OR r.banned_until IS DISTINCT FROM v_first_ban + interval '7 days'
     OR (SELECT banned_until FROM public.profiles WHERE id = v_a) IS DISTINCT FROM v_first_ban + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 4 gave a ban of %, expected % (the existing ban + 7 days)', r.banned_until, v_first_ban + interval '7 days';
  END IF;
  -- (One transaction gives both notices the same created_at, so they are
  -- counted by body, not ordered.)
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 2
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'Your pause on posting in Opinions has been extended.') <> 1
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'You can''t post in Opinions for 7 days.') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 4 did not queue the extended-ban notice';
  END IF;

  -- Strike 5, after the ban has run out (batch-4 fix round 1, I-2): a new
  -- 7-day ban from now, never from the old end date, and the new-ban
  -- wording, not "extended". The owner role passes the W1a guard.
  RESET ROLE;
  UPDATE public.profiles SET banned_until = now() - interval '1 day' WHERE id = v_a;
  PERFORM pg_temp.as_service();
  SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[5]);
  IF r.violation_count IS DISTINCT FROM 5 OR r.banned_until IS DISTINCT FROM now() + interval '7 days'
     OR (SELECT banned_until FROM public.profiles WHERE id = v_a) IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 5 after an expired ban gave (%, %), expected (5, now() + 7 days)', r.violation_count, r.banned_until;
  END IF;
  IF (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned')) <> 3
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'You can''t post in Opinions for 7 days.') <> 2
     OR (SELECT count(*) FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x
          WHERE x->>'body' = 'Your pause on posting in Opinions has been extended.') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strike 5 after an expired ban did not queue the new-ban notice: %',
      (SELECT jsonb_agg(x->>'body') FROM pg_temp.notices(v_a, 'forum_posting_banned') AS x);
  END IF;

  -- The kept forum branch and the type check are unchanged.
  SELECT * INTO r FROM public.admin_confirm_content_removal('forum_post', gen_random_uuid());
  IF r.violation_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the forum_post branch changed';
  END IF;
  BEGIN
    PERFORM public.admin_confirm_content_removal('poll', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown content type was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  RESET ROLE;

  -- Only the authors were told anything.
  IF (SELECT count(*) FROM public.scheduled_notifications WHERE user_id NOT IN (v_a, v_b)) <> v_before_others
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_bystander) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone other than the author was notified';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_moderation_notice_contracts: all held'; END $$;
ROLLBACK;
