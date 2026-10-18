-- supabase/tests/loving_now_contracts.sql
-- Spec 5 (R5-5, R5-6): "What feels loving to me right now" is saved only in
-- its v2 shape (five ways, three ratings, four moments), as a new version;
-- an existing share follows the newest answers. The clinical quizzes' flag
-- is seeded off.
BEGIN;
INSERT INTO auth.users (id) VALUES ('9f700000-0000-0000-0000-0000000000a1'), ('9f700000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

DO $$
DECLARE
  v_u uuid := '9f700000-0000-0000-0000-0000000000a1';
  v_p uuid := '9f700000-0000-0000-0000-0000000000b2';
  v_first uuid; v_second uuid; v_msg text; v_bad jsonb;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'quiz_clinical_signoff') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: quiz_clinical_signoff is not seeded off';
  END IF;
  IF has_function_privilege('anon', 'public.save_loving_now(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_loving_now(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: save_loving_now grants';
  END IF;

  PERFORM pg_temp.as_user(v_u);
  PERFORM public.save_loving_now('{"instrument_version":2,"ratings":{"words":"a_lot","time":"a_little"},"moments":["stressed"],"primary":"words"}');
  RESET ROLE;
  SELECT id INTO v_first FROM public.quiz_responses WHERE user_id = v_u AND quiz_type = 'love_language' AND version = 1;
  IF v_first IS NULL
     OR (SELECT result_data->>'instrument_version' FROM public.quiz_responses WHERE id = v_first) <> '2'
     OR (SELECT result_data ? 'primary' FROM public.quiz_responses WHERE id = v_first)
     OR (SELECT love_languages->'ratings'->>'words' FROM public.psych_profiles WHERE user_id = v_u) <> 'a_lot'
     OR NOT (SELECT 'love_language' = ANY (completed_quizzes) FROM public.psych_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v2 save is not stored cleanly';
  END IF;

  -- A share follows the newest answers.
  PERFORM set_config('session_replication_role', 'replica', true);
  INSERT INTO public.quiz_shares (sharer_user_id, recipient_user_id, quiz_type, quiz_response_id)
  VALUES (v_u, v_p, 'love_language', v_first);
  PERFORM set_config('session_replication_role', 'origin', true);
  PERFORM pg_temp.as_user(v_u);
  PERFORM public.save_loving_now('{"instrument_version":2,"ratings":{"touch":"a_lot"},"moments":[]}');
  RESET ROLE;
  SELECT id INTO v_second FROM public.quiz_responses WHERE user_id = v_u AND quiz_type = 'love_language' AND version = 2;
  IF v_second IS NULL OR (SELECT quiz_response_id FROM public.quiz_shares
                          WHERE sharer_user_id = v_u AND quiz_type = 'love_language') <> v_second THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a change did not reach the share';
  END IF;

  -- Anything else is refused.
  FOREACH v_bad IN ARRAY ARRAY[
    '{"instrument_version":2,"ratings":{"words":"always"},"moments":[]}'::jsonb,
    '{"instrument_version":2,"ratings":{"chores":"a_lot"},"moments":[]}'::jsonb,
    '{"instrument_version":2,"ratings":{},"moments":[]}'::jsonb,
    '{"instrument_version":2,"ratings":{"words":"a_lot"},"moments":["angry"]}'::jsonb,
    '{"instrument_version":1,"ratings":{"words":"a_lot"},"moments":[]}'::jsonb
  ] LOOP
    PERFORM pg_temp.as_user(v_u);
    BEGIN
      PERFORM public.save_loving_now(v_bad);
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: an invalid answer was saved: %', v_bad;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      RESET ROLE;
      IF v_msg <> 'loving_now:invalid' THEN RAISE; END IF;
    END;
  END LOOP;
END $$;
DO $$ BEGIN RAISE NOTICE 'loving_now_contracts: all held'; END $$;
ROLLBACK;
