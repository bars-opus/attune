-- Spec §12's six capability flags: seeded off, hidden from clients the
-- way `dating_%` is hidden, and readable only by the server.
-- Run: psql -q -d attune_test -f supabase/tests/ai_capability_flag_contracts.sql
--
-- Every contract here is phrased against a SPECIFIC key and a SPECIFIC
-- expected value. None would pass if the migration's INSERT, its RLS
-- predicate, or its grant were deleted -- which is the point: this file
-- exists because 20260712150000's own header records that a
-- client-readable rollout table WAS a review finding, and a test
-- asserting merely "some policy exists" would not have caught it.
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_expected text[] := ARRAY[
    'ai_assist_enabled',
    'ai_understand_enabled',
    'ai_sessions_private_enabled',
    'ai_sessions_shared_enabled',
    'ai_sessions_recent_window_enabled',
    'ai_sessions_nearby_enabled'
  ];
  v_key text;
  v_enabled boolean;
  v_ai_visible int;
  v_dating_visible int;
  v_chat_visible boolean;
BEGIN
  -- Contract 1: all six §12 keys exist and every one of them is OFF.
  -- Asserted key by key so a missing key names itself in the failure.
  FOREACH v_key IN ARRAY v_expected LOOP
    SELECT enabled INTO v_enabled FROM public.feature_flags WHERE key = v_key;
    IF v_enabled IS NULL THEN
      RAISE EXCEPTION 'MISSING: spec §12 capability flag % was never seeded', v_key;
    END IF;
    IF v_enabled IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'UNSAFE DEFAULT: capability flag % is seeded ENABLED; §12 requires defaults off', v_key;
    END IF;
  END LOOP;

  -- Contract 2: the server-side predicate reports false for each of the
  -- six, and false (not NULL, not an error) for a key that does not
  -- exist at all. A capability nobody seeded must be OFF.
  FOREACH v_key IN ARRAY v_expected LOOP
    IF public.ai_capability_enabled(v_key) IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: ai_capability_enabled(%) did not report false for a disabled capability', v_key;
    END IF;
  END LOOP;
  IF public.ai_capability_enabled('ai_capability_that_does_not_exist') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'EXPLOIT: ai_capability_enabled failed OPEN for an absent key';
  END IF;

  -- Contract 3: the predicate actually READS the flag. Flip one row
  -- inside this transaction, prove the answer follows, flip it back.
  -- Without this, Contract 2 would also pass against a function whose
  -- body were literally `SELECT false`.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'ai_sessions_private_enabled';
  IF public.ai_capability_enabled('ai_sessions_private_enabled') IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: ai_capability_enabled ignored an ENABLED flag row -- it is not reading the table';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'ai_sessions_private_enabled';

  -- Contracts 4-6: read the table as `authenticated` -- the role a
  -- PostgREST client call runs under -- and capture all three facts in
  -- one role switch: the six AI keys are hidden, the dating family is
  -- STILL hidden (the new policy replaces the dating one, and a second
  -- permissive policy would have OR'ed the predicates and silently
  -- un-hidden dating), and chat's own keys still read.
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_ai_visible
    FROM public.feature_flags WHERE key = ANY (v_expected);
  SELECT count(*) INTO v_dating_visible
    FROM public.feature_flags WHERE key LIKE 'dating\_%';
  SELECT EXISTS (
    SELECT 1 FROM public.feature_flags WHERE key = 'chat_image_sharing'
  ) INTO v_chat_visible;
  RESET ROLE;

  IF v_ai_visible <> 0 THEN
    RAISE EXCEPTION
      'EXPLOIT: % of the six unlaunched AI capability flags are readable by `authenticated` -- the rollout plan is enumerable, the exact DATING-H1 finding',
      v_ai_visible;
  END IF;
  IF v_dating_visible <> 0 THEN
    RAISE EXCEPTION
      'REGRESSION: % dating_* flags became readable by `authenticated` -- the new policy un-did 20260712150000',
      v_dating_visible;
  END IF;
  IF v_chat_visible IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'REGRESSION: chat_image_sharing is no longer readable by `authenticated`; chat_feature_flags.dart depends on it';
  END IF;

  -- Contract 7: `authenticated` cannot call the predicate at all.
  -- Hiding the rows is pointless if a client can probe the same state
  -- one key at a time through a SECURITY DEFINER function.
  IF has_function_privilege('authenticated', 'public.ai_capability_enabled(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: `authenticated` can EXECUTE ai_capability_enabled and so enumerate capability state key by key';
  END IF;
  IF has_function_privilege('anon', 'public.ai_capability_enabled(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: `anon` can EXECUTE ai_capability_enabled';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.ai_capability_enabled(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'BROKEN: service_role cannot EXECUTE ai_capability_enabled, so the edge function gate cannot run';
  END IF;

  -- Contract 8: `authenticated` still has no WRITE privilege. A client
  -- that cannot read a flag must equally not be able to set one.
  IF has_table_privilege('authenticated', 'public.feature_flags', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.feature_flags', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: `authenticated` can write public.feature_flags';
  END IF;

  RAISE NOTICE 'ai_capability_flag_contracts: all contracts passed';
END $$;
