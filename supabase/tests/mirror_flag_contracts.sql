-- supabase/tests/mirror_flag_contracts.sql
-- The Mirror attentiveness flag is gone (Spec 1b Task 7; research 06 §3 F6
-- (3); owner Q11 "Remove"): no stored judgement about how well someone
-- reads their partner. The score stays, self-only. Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8f100000-0000-0000-0000-0000000000a1'),
  ('8f100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8f100000-0000-0000-0000-0000000000a1', '+233598500001', 'Mirror A'),
  ('8f100000-0000-0000-0000-0000000000b2', '+233598500002', 'Mirror B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('8f200000-0000-0000-0000-000000000001', '8f100000-0000-0000-0000-0000000000a1',
   '8f100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. No flag column, and nothing writes one.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'mirror_scores' AND column_name = 'flagged') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mirror_scores.flagged still exists';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE proname = 'finalise_mirror_scores') LIKE '%flagged%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalise_mirror_scores still computes a flag';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.finalise_mirror_scores(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.finalise_mirror_scores(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: finalise_mirror_scores grants changed';
  END IF;
END $$;

-- 2. The score still works and stays self-only. Four rounds: A is the
--    subject of 1-2 (B guesses: 1 right), B of 3-4 (A guesses: 2 right).
DO $$
DECLARE v_n int; v_score int;
BEGIN
  INSERT INTO public.game_sessions (id, relationship_id, initiator_id, game_type, status)
  VALUES ('8f300000-0000-0000-0000-000000000001', '8f200000-0000-0000-0000-000000000001',
          '8f100000-0000-0000-0000-0000000000a1', 'mirror', 'active');
  INSERT INTO public.game_session_rounds (id, session_id, round_number) VALUES
    ('8f400000-0000-0000-0000-000000000001', '8f300000-0000-0000-0000-000000000001', 1),
    ('8f400000-0000-0000-0000-000000000002', '8f300000-0000-0000-0000-000000000001', 2),
    ('8f400000-0000-0000-0000-000000000003', '8f300000-0000-0000-0000-000000000001', 3),
    ('8f400000-0000-0000-0000-000000000004', '8f300000-0000-0000-0000-000000000001', 4);
  INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text, was_correct) VALUES
    ('8f400000-0000-0000-0000-000000000001', '8f100000-0000-0000-0000-0000000000a1', 'tired', true),
    ('8f400000-0000-0000-0000-000000000002', '8f100000-0000-0000-0000-0000000000a1', 'hopeful', false),
    ('8f400000-0000-0000-0000-000000000003', '8f100000-0000-0000-0000-0000000000b2', 'calm', true),
    ('8f400000-0000-0000-0000-000000000004', '8f100000-0000-0000-0000-0000000000b2', 'busy', true);
  PERFORM pg_temp.as_user('8f100000-0000-0000-0000-0000000000a1');
  PERFORM public.finalise_mirror_scores('8f300000-0000-0000-0000-000000000001');
  SELECT count(*), max(score) INTO v_n, v_score FROM public.mirror_scores
   WHERE session_id = '8f300000-0000-0000-0000-000000000001';
  RESET ROLE;
  IF v_n <> 1 OR v_score <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % score rows (max %), want only their own 2', v_n, v_score;
  END IF;
  IF (SELECT score FROM public.mirror_scores
      WHERE session_id = '8f300000-0000-0000-0000-000000000001'
        AND user_id = '8f100000-0000-0000-0000-0000000000b2') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: B''s score was not written';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'mirror_flag_contracts: all held'; END $$;
ROLLBACK;
