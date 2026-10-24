-- supabase/tests/story_membership_contracts.sql
--
-- Stories Wave 5, Task 4 (review 05 #4): nobody can ask the server whether
-- some other pair of people is an open couple. Policies use a helper that
-- only ever answers for the caller; the two-argument helper is server-only.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('00000000-0000-0000-0000-0000000937a1'), ('00000000-0000-0000-0000-0000000937b2'),
  ('00000000-0000-0000-0000-0000000937c3'), ('00000000-0000-0000-0000-0000000937d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('00000000-0000-0000-0000-0000000937a1', '+15550937001', 'MA'),
  ('00000000-0000-0000-0000-0000000937b2', '+15550937002', 'MB'),
  ('00000000-0000-0000-0000-0000000937c3', '+15550937003', 'MC'),
  ('00000000-0000-0000-0000-0000000937d4', '+15550937004', 'MD')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
  ('00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937a1', '00000000-0000-0000-0000-0000000937b2', 'active'),
  ('00000000-0000-0000-0000-0000000937e2', '00000000-0000-0000-0000-0000000937c3', '00000000-0000-0000-0000-0000000937d4', 'active');
INSERT INTO public.story_items (client_story_id, relationship_id, author_id, media_type, media_key,
  thumbnail_key, media_width, media_height, occurred_on, created_at, expires_at)
VALUES (gen_random_uuid(), '00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937b2',
  'image', 'story-media/m937/b-media', 'story-media/m937/b-thumbnail', 100, 100, CURRENT_DATE, now(), now() + interval '24 hours');

-- M1. Privileges.
DO $$
BEGIN
  IF has_function_privilege('authenticated', 'public.story_relationship_is_open(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.story_relationship_is_open(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can ask about any user (05 #4)';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.story_relationship_is_open_for_me(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.story_relationship_is_open_for_me(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story_relationship_is_open_for_me grants are wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid IN ('public.story_relationship_is_open(uuid,uuid)'::regprocedure,
                                                  'public.story_relationship_is_open_for_me(uuid)'::regprocedure)
             AND NOT ('search_path=""' = ANY (coalesce(proconfig, '{}')))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a membership helper does not pin search_path';
  END IF;
  -- Batch 2 review #1: a nested definer call cannot be inlined and costs
  -- 4-7x per row on every invoker story read.
  IF pg_get_functiondef('public.story_relationship_is_open_for_me(uuid)'::regprocedure)
     LIKE '%story_relationship_is_open(%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the policy helper must not nest a definer call (per-row cost)';
  END IF;
END $$;

-- M2. No policy calls the two-argument helper; the four story policies use the new one.
DO $$
DECLARE v record; v_n int;
BEGIN
  FOR v IN SELECT schemaname, tablename, policyname FROM pg_policies
           WHERE coalesce(qual, '') ~ 'story_relationship_is_open\('
              OR coalesce(with_check, '') ~ 'story_relationship_is_open\(' LOOP
    RAISE EXCEPTION 'CONTRACT VIOLATED: %.%.% still calls the two-argument helper', v.schemaname, v.tablename, v.policyname;
  END LOOP;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE policyname IN ('story_items_read_members', 'story_signals_read_members',
                        'story_places_read_members', 'story_media_select_authorized')
     AND qual LIKE '%story_relationship_is_open_for_me(%';
  IF v_n <> 4 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % of 4 story policies use the caller-only helper', v_n; END IF;
END $$;

-- M3. The helper answers only for the caller; the old one refuses clients.
DO $$
DECLARE v_ok boolean; v_n int;
BEGIN
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937c3');
  IF public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider is told another couple is open';
  END IF;
  BEGIN
    v_ok := public.story_relationship_is_open('00000000-0000-0000-0000-0000000937e1', '00000000-0000-0000-0000-0000000937a1');
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: the two-argument oracle answered a client';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider reads % stories', v_n; END IF;
  RESET ROLE;

  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937a1');
  IF NOT public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a member is told their own couple is closed';
  END IF;
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 1 THEN RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a member reads % of 1 stories', v_n; END IF;
  RESET ROLE;

  UPDATE public.relationships SET status = 'paused' WHERE id = '00000000-0000-0000-0000-0000000937e1';
  PERFORM pg_temp.as_user('00000000-0000-0000-0000-0000000937a1');
  SELECT count(*) INTO v_n FROM public.story_items WHERE relationship_id = '00000000-0000-0000-0000-0000000937e1';
  IF v_n <> 0 OR public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1') THEN
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a paused couple''s stories are readable';
  END IF;
  RESET ROLE;
END $$;

-- M4. The caller-only helper keeps the two-argument predicate (it carries its
-- own copy for per-row cost): same answer for a member and an outsider in
-- every state.
DO $$
DECLARE v_case record; v_user uuid; v_mine boolean; v_two boolean;
BEGIN
  FOR v_case IN SELECT * FROM (VALUES
      ('active', false), ('active', true), ('paused', false),
      ('ended', false), ('archived', false)) AS c(status, chat_archived) LOOP
    UPDATE public.relationships
       SET status = v_case.status,
           ended_at = CASE WHEN v_case.status IN ('ended', 'archived') THEN coalesce(ended_at, now()) END,
           chat_archived_at = CASE WHEN v_case.chat_archived OR v_case.status = 'archived' THEN now() END
     WHERE id = '00000000-0000-0000-0000-0000000937e1';
    FOREACH v_user IN ARRAY ARRAY['00000000-0000-0000-0000-0000000937a1',
                                  '00000000-0000-0000-0000-0000000937b2',
                                  '00000000-0000-0000-0000-0000000937c3']::uuid[] LOOP
      v_two := public.story_relationship_is_open('00000000-0000-0000-0000-0000000937e1', v_user);
      PERFORM pg_temp.as_user(v_user);
      v_mine := public.story_relationship_is_open_for_me('00000000-0000-0000-0000-0000000937e1');
      RESET ROLE;
      IF v_mine IS DISTINCT FROM v_two THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: the helpers disagree for % on % (archived %): % vs %',
          v_user, v_case.status, v_case.chat_archived, v_mine, v_two;
      END IF;
    END LOOP;
  END LOOP;
END $$;

ROLLBACK;
