-- get_ai_session_capabilities(): the client-readable half of spec §12's
-- capability flags (Plan D Task 5, PF2 option (b)).
-- Run: psql -q -d attune_test -f supabase/tests/ai_session_capability_availability_contracts.sql
--
-- The thing this file must actually prove is NOT "a function exists".
-- PF2's failure mode was a kill switch that looked live and was dead:
-- five client providers that would read `false` forever no matter what
-- an operator set. So Contract 2 flips a flag inside a transaction and
-- asserts the client-visible answer CHANGES. That is the only contract
-- here that could have caught the bug this function was written to fix,
-- and it is deliberately asymmetric (one key flipped, the others
-- asserted still false) so a function returning a constant `true` on
-- every key fails too.
--
-- Every UPDATE below runs inside a sub-transaction that is rolled back,
-- so this file cannot leave a capability enabled. Contract 7 asserts
-- that at exit, which is the standing requirement that the flags stay
-- OFF and nothing in the build may flip them.
\set ON_ERROR_STOP on

-- The function is gated on `auth.uid() IS NOT NULL` and returns NULL
-- without a subject, so this file must supply one or every contract
-- below would read NULL and the "dead switch" check would fire for the
-- wrong reason. Found by running it without this: Contract 2 reported
-- `still reports NULL` on the first key. Set at session scope so the
-- sub-transactions in Contract 2 cannot lose it.
SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000c0de","role":"authenticated"}',
  false
);

-- Anti-vacuity for the line above: if set_config stopped taking effect,
-- every contract here would be testing a NULL and Contract 4's
-- anti-vacuity guard is the only one that would notice. Fail loudly and
-- immediately instead.
DO $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION
      'HARNESS: auth.uid() is still NULL, so get_ai_session_capabilities would return NULL and every contract below would be vacuous';
  END IF;
END $$;

-- Contract 0: WITHOUT a subject the function returns NULL rather than an
-- all-false object. The Dart side distinguishes "server said no" from
-- "could not ask", and this is the source of that distinction.
DO $$
DECLARE v_unauthed jsonb;
BEGIN
  SET LOCAL request.jwt.claims TO '';
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'HARNESS: could not clear the JWT subject for Contract 0';
  END IF;
  v_unauthed := public.get_ai_session_capabilities();
  IF v_unauthed IS NOT NULL THEN
    RAISE EXCEPTION
      'CONTRACT 0: with no authenticated subject the function returned % instead of NULL -- an expired session would now be indistinguishable from a deliberate server-side disable',
      v_unauthed::text;
  END IF;
END $$;

SELECT set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-00000000c0de","role":"authenticated"}',
  false
);

DO $$
DECLARE
  -- The five keys the function is contracted to report. Transcribed
  -- from the migration; Contract 4 asserts the function's actual key
  -- set equals this one IN BOTH DIRECTIONS, so this array cannot drift
  -- into a stale copy without failing.
  v_reported text[] := ARRAY[
    'ai_assist_enabled',
    'ai_sessions_private_enabled',
    'ai_sessions_shared_enabled',
    'ai_sessions_recent_window_enabled',
    'ai_sessions_nearby_enabled'
  ];
  v_key text;
  v_result jsonb;
  v_actual_keys text[];
  v_missing text[];
  v_extra text[];
  v_still_on text[];
BEGIN
  -- -------------------------------------------------------------------
  -- Contract 1: every reported key names a REAL feature_flags row.
  --
  -- A typo in the function would make ai_capability_enabled COALESCE an
  -- absent key to false -- i.e. it would read as "capability off"
  -- forever and look perfectly healthy. This is the same dead-switch
  -- shape as PF2 itself, one layer down, so it gets its own contract.
  -- -------------------------------------------------------------------
  FOREACH v_key IN ARRAY v_reported LOOP
    IF NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key = v_key) THEN
      RAISE EXCEPTION
        'BROKEN: get_ai_session_capabilities reports %, which is not a feature_flags row -- it would COALESCE to false forever',
        v_key;
    END IF;
  END LOOP;

  -- -------------------------------------------------------------------
  -- Contract 2: THE KILL SWITCH IS LIVE. An operator flip is visible to
  -- the client, and only the flipped key moves.
  --
  -- This is the contract PF2 needed and the direct-table-read approach
  -- would have failed: there, the answer was false before the flip and
  -- false after it.
  --
  -- READ AS `authenticated`, NOT AS THE TEST'S OWN ROLE. This is not
  -- ceremony: mutation M-SQL2 rewrote the function to read
  -- public.feature_flags directly with SECURITY INVOKER -- i.e. it
  -- reintroduced PF2 verbatim -- and this contract PASSED, because the
  -- local harness runs as a superuser and a superuser BYPASSES RLS. The
  -- `ai\_%` rows the client cannot see are plainly visible to it. So the
  -- flip-visibility check is only evidence about a client if it is
  -- performed with a client's privileges. SET LOCAL ROLE is scoped to
  -- this sub-transaction and reverts with it.
  -- -------------------------------------------------------------------
  FOREACH v_key IN ARRAY v_reported LOOP
    BEGIN
      UPDATE public.feature_flags SET enabled = true WHERE key = v_key;

      SET LOCAL ROLE authenticated;
      v_result := public.get_ai_session_capabilities();
      RESET ROLE;

      IF (v_result -> v_key) IS DISTINCT FROM 'true'::jsonb THEN
        RAISE EXCEPTION
          'DEAD SWITCH: % was set enabled=true but get_ai_session_capabilities still reports % -- the client can never learn this flag turned on',
          v_key, COALESCE((v_result -> v_key)::text, 'NULL');
      END IF;

      -- Asymmetry guard: a function hardcoding `true` for everything
      -- would pass the check above. Every OTHER key must still be
      -- false, which also proves §12's "subcapability disable closes
      -- affected sessions, not unrelated chat" is expressible -- the
      -- five flags are independent, not one flag reported five times.
      SELECT array_agg(other ORDER BY other) INTO v_still_on
      FROM unnest(v_reported) AS other
      WHERE other <> v_key
        AND (v_result -> other) IS DISTINCT FROM 'false'::jsonb;

      IF v_still_on IS NOT NULL THEN
        RAISE EXCEPTION
          'NOT INDEPENDENT: flipping % also reported % as enabled -- the five capabilities are not separately killable',
          v_key, v_still_on;
      END IF;

      -- Undo before the next key, so each iteration tests exactly one
      -- flag against four off ones.
      RAISE EXCEPTION 'rollback_this_probe';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'rollback_this_probe' THEN RAISE; END IF;
    END;
  END LOOP;

  -- -------------------------------------------------------------------
  -- Contract 3: with every flag off -- the state this branch ships in --
  -- the client is told `false` for all five. Explicitly `false`, never
  -- NULL or absent: the Dart side distinguishes "server said no" from
  -- "could not read", and a NULL here would silently become the latter.
  -- -------------------------------------------------------------------
  -- Anti-vacuity for the role switches above and below: prove that
  -- acting as `authenticated` actually restricts what this session can
  -- see, so a SET LOCAL ROLE that silently stopped taking effect (the
  -- exact failure that made M-SQL2 pass) cannot go unnoticed. As the
  -- harness role the ai_ rows are visible; as a client they must not be.
  IF (SELECT count(*) FROM public.feature_flags WHERE key LIKE 'ai\_%') = 0 THEN
    RAISE EXCEPTION
      'HARNESS: the test role cannot see the ai_ rows even unrestricted, so the privilege comparison below proves nothing';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    IF (SELECT count(*) FROM public.feature_flags WHERE key LIKE 'ai\_%') <> 0 THEN
      RAISE EXCEPTION
        'VACUOUS ROLE SWITCH: acting as `authenticated` still sees ai_ rows in feature_flags. Either RLS is off for this role or SET LOCAL ROLE is not taking effect -- and every "as a client" contract in this file is then meaningless (this is how mutation M-SQL2 survived)';
    END IF;
    RESET ROLE;
  END;

  SET LOCAL ROLE authenticated;
  v_result := public.get_ai_session_capabilities();
  RESET ROLE;
  FOREACH v_key IN ARRAY v_reported LOOP
    IF (v_result -> v_key) IS DISTINCT FROM 'false'::jsonb THEN
      RAISE EXCEPTION
        'FLAG NOT OFF (or not a JSON boolean): % reported as %, expected false',
        v_key, COALESCE((v_result -> v_key)::text, 'absent');
    END IF;
  END LOOP;

  -- -------------------------------------------------------------------
  -- Contract 4: the reported key set is EXACTLY these five -- asserted
  -- against the function's own output, in both directions.
  --
  -- The `v_extra` half is the half that matters and it is not
  -- symmetric busywork: it is what catches a future author who adds a
  -- sixth key to the function WITHOUT knowing this test exists. A
  -- one-directional "all five are present" check would pass for them,
  -- and `ai_understand_enabled` or a `dating_%` key would start
  -- reaching clients unreviewed -- which is precisely
  -- 20260712150000's finding.
  -- -------------------------------------------------------------------
  SELECT array_agg(k ORDER BY k) INTO v_actual_keys
  FROM jsonb_object_keys(v_result) AS k;

  SELECT array_agg(k ORDER BY k) INTO v_missing
  FROM unnest(v_reported) AS k
  WHERE NOT (k = ANY (COALESCE(v_actual_keys, ARRAY[]::text[])));

  SELECT array_agg(k ORDER BY k) INTO v_extra
  FROM unnest(COALESCE(v_actual_keys, ARRAY[]::text[])) AS k
  WHERE NOT (k = ANY (v_reported));

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'BROKEN: get_ai_session_capabilities no longer reports % -- a client entry point would render on stale/default state',
      v_missing;
  END IF;
  IF v_extra IS NOT NULL THEN
    RAISE EXCEPTION
      'UNREVIEWED DISCLOSURE: get_ai_session_capabilities now reports %. Every key here is capability state leaving the server for a client; adding one is a disclosure decision (see 20260712150000_dating_flag_defense_in_depth.sql) and must be argued in the migration, not inherited',
      v_extra;
  END IF;

  -- Anti-vacuity: the comparison above is only meaningful if the
  -- function actually returned an object with keys.
  IF v_actual_keys IS NULL OR array_length(v_actual_keys, 1) <> 5 THEN
    RAISE EXCEPTION
      'VACUOUS: get_ai_session_capabilities returned % keys, so Contract 4 compared nothing',
      COALESCE(array_length(v_actual_keys, 1), 0);
  END IF;

  -- -------------------------------------------------------------------
  -- Contract 5: it is NOT a key-by-key oracle.
  --
  -- ai_capability_enabled(text) stays service_role-only; this function
  -- takes NO argument, so a client cannot ask about a key of its
  -- choosing and so cannot probe for capabilities this function does
  -- not name. Asserted on the catalog rather than by trying a call, so
  -- it fails if someone adds a p_key overload.
  -- -------------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_ai_session_capabilities'
      AND p.pronargs > 0
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: a parameterised get_ai_session_capabilities overload exists -- a client can now probe arbitrary flag keys';
  END IF;
  IF has_function_privilege('authenticated', 'public.ai_capability_enabled(text)', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: `authenticated` regained EXECUTE on ai_capability_enabled(text) -- the per-key oracle is back';
  END IF;

  -- -------------------------------------------------------------------
  -- Contract 6: grants. `authenticated` yes; `anon` no, so an
  -- unauthenticated key cannot poll for the launch moment.
  -- -------------------------------------------------------------------
  IF NOT has_function_privilege('authenticated', 'public.get_ai_session_capabilities()', 'EXECUTE') THEN
    RAISE EXCEPTION
      'BROKEN: `authenticated` cannot EXECUTE get_ai_session_capabilities, so the Flutter client is back to reading false forever (PF2)';
  END IF;
  IF has_function_privilege('anon', 'public.get_ai_session_capabilities()', 'EXECUTE') THEN
    RAISE EXCEPTION
      'EXPLOIT: `anon` can EXECUTE get_ai_session_capabilities and poll for launch';
  END IF;

  -- -------------------------------------------------------------------
  -- Contract 7: this FILE left every capability off. Contract 2 ran
  -- five UPDATEs; if any sub-transaction rollback failed to undo one,
  -- this names it.
  -- -------------------------------------------------------------------
  SELECT array_agg(key ORDER BY key) INTO v_still_on
  FROM public.feature_flags
  WHERE key LIKE 'ai\_%' AND enabled;

  IF v_still_on IS NOT NULL THEN
    RAISE EXCEPTION
      'THIS TEST LEFT A CAPABILITY ENABLED: %. The flags must stay off; flipping them is an operator act, never a test or build side effect',
      v_still_on;
  END IF;

  -- -------------------------------------------------------------------
  -- Contract 8: this function cannot WRITE a flag. Read the body from
  -- the catalog and assert it contains no write verb -- so "nothing the
  -- client can call may flip a flag" is checked against the shipped
  -- definition rather than trusted from review.
  -- -------------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'get_ai_session_capabilities'
      AND (p.prosrc ~* '\m(update|insert|delete|truncate|execute)\M' OR p.provolatile = 'v')
  ) THEN
    RAISE EXCEPTION
      'EXPLOIT: get_ai_session_capabilities contains a write verb or is VOLATILE -- a client-callable function must not be able to flip a rollout flag';
  END IF;

  RAISE NOTICE 'ai_session_capability_availability_contracts: all contracts passed';
END $$;
