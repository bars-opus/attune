-- supabase/tests/chapter_canary_contracts.sql
-- Spec 3b (research 06 §3 F13 (1); 05 D.3 #2 "chapters never leak"): two
-- former partners (A, B) and one new partner (C). While R1 is open, A and B
-- read its games and C reads nothing; once R1 is archived, nobody reads any
-- of R1's rows through any table, RPC or realtime-published table, and
-- nobody can write into it. The table set is discovered, not listed.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('9a100000-0000-0000-0000-00000000000a'), ('9a100000-0000-0000-0000-00000000000b'),
  ('9a100000-0000-0000-0000-00000000000c')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9a100000-0000-0000-0000-00000000000a', '+233599500001', 'Ana'),
  ('9a100000-0000-0000-0000-00000000000b', '+233599500002', 'Ben'),
  ('9a100000-0000-0000-0000-00000000000c', '+233599500003', 'Cee')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.a() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a100000-0000-0000-0000-00000000000a'::uuid $$;
CREATE FUNCTION pg_temp.b() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a100000-0000-0000-0000-00000000000b'::uuid $$;
CREATE FUNCTION pg_temp.c() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a100000-0000-0000-0000-00000000000c'::uuid $$;
CREATE FUNCTION pg_temp.r1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a200000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.r2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a200000-0000-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION pg_temp.s1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a300000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.rd1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a400000-0000-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION pg_temp.lm1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a400000-0000-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION pg_temp.j1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '9a500000-0000-0000-0000-000000000001'::uuid $$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at)
VALUES (pg_temp.r1(), pg_temp.a(), pg_temp.b(), 'active', CURRENT_DATE, now() - interval '200 days', now());
INSERT INTO public.relationships (id, user_a, user_b, status, invite_code, invite_expires_at, created_at)
VALUES (pg_temp.r2(), pg_temp.a(), pg_temp.c(), 'pending', 'CANARY-R2', now() + interval '1 day', now());

-- R1's chapter: a game with rounds and answers, a Love map round with a
-- mirror truth, a 36-question journey with a reflection, Pulse, patterns,
-- timeline, a reminder, a family member, the Ask-2 state, the
-- compatibility card, seen-questions, a mirror score, a penalty.
SET LOCAL session_replication_role = replica;
INSERT INTO public.game_sessions (id, relationship_id, initiator_id, game_type, journey_id)
VALUES (pg_temp.s1(), pg_temp.r1(), pg_temp.a(), 'thirty_six', pg_temp.j1());
INSERT INTO public.thirty_six_question_journeys (id, relationship_id) VALUES (pg_temp.j1(), pg_temp.r1());
INSERT INTO public.chapter_reflections (journey_id, chapter) VALUES (pg_temp.j1(), 1);
INSERT INTO public.game_session_rounds (id, session_id, round_number, both_answered)
VALUES (pg_temp.rd1(), pg_temp.s1(), 1, true);
INSERT INTO public.game_session_rounds (id, relationship_id, round_number, both_answered)
VALUES (pg_temp.lm1(), pg_temp.r1(), 1, true);
INSERT INTO public.thirty_six_question_answers (round_id, user_id, answer_text)
VALUES (pg_temp.rd1(), pg_temp.a(), 'ana'), (pg_temp.rd1(), pg_temp.b(), 'ben');
INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text) VALUES (pg_temp.lm1(), pg_temp.a(), 'truth');
INSERT INTO public.mirror_scores (session_id, user_id, score) VALUES (pg_temp.s1(), pg_temp.a(), 3);
INSERT INTO public.paint_ball_penalties (session_id, user_id, penalty_type, penalty_source, penalty_prompt_snapshot)
VALUES (pg_temp.s1(), pg_temp.a(), 'truth', 'app_random', 'x');
INSERT INTO public.session_idempotency_keys (session_id, key) VALUES (pg_temp.s1(), 'canary');
INSERT INTO public.game_questions_seen (relationship_id, question_id, game_type) VALUES (pg_temp.r1(), gen_random_uuid(), 'love_map');
INSERT INTO public.thirty_six_questions_seen (relationship_id, canonical_question_id) VALUES (pg_temp.r1(), gen_random_uuid());
INSERT INTO public.pulse_scores (relationship_id, week_ending, overall_score, communication, connection, conflict_health, alignment)
VALUES (pg_temp.r1(), CURRENT_DATE, 60, 60, 60, 60, 60);
INSERT INTO public.patterns (relationship_id, pattern_type, severity) VALUES (pg_temp.r1(), 'pursue_withdraw', 'watch');
INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
VALUES (pg_temp.r1(), pg_temp.a(), 'milestone', 'First trip', CURRENT_DATE);
INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at)
VALUES (pg_temp.r1(), pg_temp.a(), 'anniversary', 'Our day', now() + interval '10 days');
INSERT INTO public.couple_family_members (relationship_id, name, created_by) VALUES (pg_temp.r1(), 'Mum', pg_temp.a());
INSERT INTO public.ask2_state (relationship_id) VALUES (pg_temp.r1());
INSERT INTO public.attachment_compatibility_cache (relationship_id, type_a, type_b, pairing_name, pairing_description, natural_strength, watch_area)
VALUES (pg_temp.r1(), 'secure', 'secure', 'x', 'x', 'x', 'x');
SET LOCAL session_replication_role = origin;

-- 1. While R1 is open: A and B read it, C reads nothing.
DO $$
DECLARE v_n int; v_p uuid;
BEGIN
  FOREACH v_p IN ARRAY ARRAY[pg_temp.a(), pg_temp.b()] LOOP
    PERFORM pg_temp.as_user(v_p);
    SELECT count(*) INTO v_n FROM public.game_sessions WHERE id = pg_temp.s1();
    RESET ROLE;
    IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % cannot read its open game', v_p; END IF;
  END LOOP;
  PERFORM pg_temp.as_user(pg_temp.c());
  SELECT count(*) INTO v_n FROM public.game_sessions WHERE id = pg_temp.s1();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: C reads R1''s game'; END IF;
END $$;

-- R1 ends; A starts R2 with C, which archives R1 (3a R3-6).
DO $$
BEGIN
  PERFORM pg_temp.as_user(pg_temp.a());
  PERFORM public.end_relationship(pg_temp.r1());
  RESET ROLE;
  UPDATE public.relationships SET status = 'active', invite_code = NULL, invite_accepted_at = now(), started_at = CURRENT_DATE
  WHERE id = pg_temp.r2();
  IF (SELECT status FROM public.relationships WHERE id = pg_temp.r1()) <> 'archived' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: R1 should be archived';
  END IF;
END $$;

-- 2. The discovered table set: every public table with a relationship_id,
--    plus every table that reaches one through a session, round or journey.
CREATE TEMP TABLE canary_tables (tbl regclass PRIMARY KEY, key_col text, key_ids uuid[]);
DO $$
DECLARE v record;
BEGIN
  INSERT INTO canary_tables
  SELECT (c.table_schema || '.' || c.table_name)::regclass, 'relationship_id', ARRAY[pg_temp.r1()]
  FROM information_schema.columns c
  JOIN information_schema.tables t USING (table_schema, table_name)
  WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE' AND c.column_name = 'relationship_id';
  FOR v IN
    SELECT DISTINCT k.conrelid::regclass AS tbl, a.attname AS col, k.confrelid::regclass AS parent
    FROM pg_constraint k
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
    WHERE k.contype = 'f'
      AND k.confrelid IN ('public.game_sessions'::regclass, 'public.game_session_rounds'::regclass,
                          'public.thirty_six_question_journeys'::regclass)
  LOOP
    INSERT INTO canary_tables VALUES (
      v.tbl, v.col,
      CASE v.parent
        WHEN 'public.game_sessions'::regclass THEN ARRAY[pg_temp.s1()]
        WHEN 'public.game_session_rounds'::regclass THEN ARRAY[pg_temp.rd1(), pg_temp.lm1()]
        ELSE ARRAY[pg_temp.j1()]
      END)
    ON CONFLICT (tbl) DO NOTHING;
  END LOOP;
  -- A future schema change must not shrink the set silently.
  IF EXISTS (
    SELECT 1 FROM unnest(ARRAY['public.thirty_six_question_answers', 'public.chapter_reflections',
      'public.mirror_round_truth', 'public.mirror_scores', 'public.paint_ball_penalties',
      'public.session_idempotency_keys', 'public.game_sessions', 'public.pulse_scores']::regclass[]) need
    WHERE need NOT IN (SELECT tbl FROM canary_tables)
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the canary table set lost a class-D table';
  END IF;
END $$;
GRANT SELECT ON canary_tables TO authenticated;

-- 3. After the archive nobody reads a row of R1, anywhere. Own-row tables by
--    design (R3b-2, 3a): the relationships row, insights, translator logs,
--    Healing, seals, the dating exclusion.
DO $$
DECLARE v record; v_n int; v_p uuid;
BEGIN
  FOREACH v_p IN ARRAY ARRAY[pg_temp.a(), pg_temp.b(), pg_temp.c()] LOOP
    FOR v IN SELECT * FROM canary_tables
      WHERE tbl NOT IN ('public.relationships'::regclass, 'public.personal_insights'::regclass,
        'public.translator_logs'::regclass, 'public.healing_ending_snapshots'::regclass,
        'public.healing_journeys'::regclass, 'public.relationship_seals'::regclass,
        'public.dating_former_partner_exclusions'::regclass)
    LOOP
      IF NOT has_any_column_privilege('authenticated', v.tbl, 'SELECT') THEN
        CONTINUE;  -- not readable by clients at all
      END IF;
      PERFORM pg_temp.as_user(v_p);
      EXECUTE format('SELECT count(*) FROM %s WHERE %I = ANY ($1)', v.tbl, v.key_col)
        INTO v_n USING v.key_ids;
      RESET ROLE;
      IF v_n <> 0 THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % reads % archived R1 rows in %', v_p, v_n, v.tbl;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- 4. Read RPCs given R1 ids answer A and B exactly what they answer C, who
--    was never a member: nothing, or the function's own refusal.
CREATE FUNCTION pg_temp.answer(p uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_out text;
BEGIN
  PERFORM pg_temp.as_user(p);
  BEGIN
    EXECUTE p_sql INTO v_out;
  EXCEPTION WHEN OTHERS THEN
    v_out := 'error: ' || SQLERRM;
  END;
  RESET ROLE;
  RETURN coalesce(v_out, 'null');
END $$;

DO $$
DECLARE v_p uuid; v_sql text; v_outsider text; v_got text;
BEGIN
  FOREACH v_sql IN ARRAY ARRAY[
    format('SELECT count(*)::text FROM public.get_revealed_round(%L)', pg_temp.lm1()),
    format('SELECT public.session_game_round_state(%L)::text', pg_temp.s1()),
    format('SELECT public.this_or_that_round_state(%L)::text', pg_temp.s1()),
    format('SELECT public.get_paint_ball_session_state(%L)::text', pg_temp.s1()),
    format('SELECT public.get_snakes_session_state(%L)::text', pg_temp.s1()),
    format('SELECT public.get_word_hunt_state(%L)::text', pg_temp.s1()),
    format('SELECT count(*)::text FROM public.get_paint_ball_history(%L)', pg_temp.r1()),
    format('SELECT public.get_active_paint_ball_session(%L)::text', pg_temp.r1()),
    format('SELECT public.get_thirty_six_seen_map(%L)::text', pg_temp.r1())
  ] LOOP
    v_outsider := pg_temp.answer(pg_temp.c(), v_sql);
    FOREACH v_p IN ARRAY ARRAY[pg_temp.a(), pg_temp.b()] LOOP
      v_got := pg_temp.answer(v_p, v_sql);
      IF v_got IS DISTINCT FROM v_outsider THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % got "%" (an outsider gets "%") from %', v_p, v_got, v_outsider, v_sql;
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- 5. Nothing is written into the closed chapter, by policy or by RPC.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user(pg_temp.a());
  UPDATE public.game_sessions SET status = 'completed' WHERE id = pg_temp.s1();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A updated R1''s game after the end'; END IF;
  PERFORM pg_temp.as_user(pg_temp.a());
  BEGIN
    PERFORM public.mark_thirty_six_round_complete(pg_temp.rd1());
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an RPC wrote into R1''s game after the end';
  EXCEPTION WHEN raise_exception THEN
    RESET ROLE;
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
END $$;

-- 6. Every SELECT path of a client-readable table in the set is gated
--    (realtime evaluates the same policies), apart from the own-row tables.
DO $$
DECLARE v record;
BEGIN
  FOR v IN
    SELECT p.tablename, p.policyname, p.qual
    FROM pg_policies p
    JOIN canary_tables c ON c.tbl = ('public.' || p.tablename)::regclass
    WHERE p.schemaname = 'public' AND p.cmd IN ('SELECT', 'ALL')
      AND p.tablename NOT IN ('relationships', 'personal_insights', 'translator_logs',
        'healing_ending_snapshots', 'healing_journeys', 'relationship_seals', 'dating_former_partner_exclusions')
      AND p.qual NOT LIKE '%relationship_chat_open%'
      AND p.qual NOT LIKE '%status = ''active''%'
      AND p.qual NOT LIKE '%story_relationship_is_open%'
      -- A policy that admits only the reader's own rows reveals nothing of a
      -- chapter to anyone else (the person's own check-ins, uploads, scores).
      AND p.qual !~ '^\(*(auth\.uid\(\) = [a-z_]+|[a-z_]+ = auth\.uid\(\))\)*$'
  LOOP
    RAISE EXCEPTION 'CONTRACT VIOLATED: %.% reads without the chapter gate: %', v.tablename, v.policyname, v.qual;
  END LOOP;
END $$;

-- Final review M-2: the gate's helpers are not an oracle for anon.
DO $$
DECLARE v_fn text;
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.chapter_rpc_open(text,uuid)', 'public.game_session_relationship(uuid)',
    'public.game_round_relationship(uuid)', 'public.relationship_active_for_me(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: anon can execute %', v_fn;
    END IF;
    IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: policies can no longer call %', v_fn;
    END IF;
  END LOOP;
END $$;

DO $$ BEGIN RAISE NOTICE 'chapter_canary_contracts: all held'; END $$;
ROLLBACK;
