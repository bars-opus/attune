-- supabase/tests/entry_gates_contracts.sql
-- Entry gates (2026-11-27 audit; migrations 20261127100000-100060):
--   A. objects, grants, the restrictive write policies;
--   B. private.account_ready: users row + 18+ DOB + EULA >= 2 + no hold;
--   C. invite accept/eligibility refuse a missing DOB, under 18 or no
--      consent on EITHER side, with flow_signin_v2 OFF and ON;
--   D. an incomplete account can't write an Opinion (direct or RPC) or a
--      weekly check-in; a complete one can;
--   E. the sign-up path still works for an incomplete account;
--   F. record_eula_acceptance never creates a row and never takes v1.
--   Fix round (gates-review.md):
--   G. every SECURITY DEFINER function the app can call that writes a gated
--      or Opinions table checks account_ready (or is on the allowlist);
--   H. account_ready on the 18th birthday and for leap-day birth dates;
--   I. definer RPCs: a couple-content RPC and Opinions RPCs refuse a
--      not-ready account and work for a ready one; reports stay open but a
--      not-ready report never counts; home state reads consent as
--      account_ready does.
--   J. un-reacting always works: a held account's decrements go through,
--      its increments don't.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/entry_gates_contracts.sql
-- Fixture ids ee670000-0000-0000-0000-0000000000NN (relationships
-- ee670000-0000-0000-0000-0000000001NN); phones +15558710NN.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('ee670000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.rel(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('ee670000-0000-0000-0000-0000000001' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_owner() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- p_sql's refusal (message), or NULL when it succeeded.
CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

-- A verified Auth phone; with [p_row], a users row, [p_age] years old
-- (NULL: no DOB; a DOB needs a users row) and [p_eula] its accepted EULA
-- version (NULL: none).
CREATE FUNCTION pg_temp.person(p_n text, p_row boolean, p_age int, p_eula text) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at)
  VALUES (pg_temp.id(p_n), '+15558710' || p_n, now());
  IF p_row THEN
    INSERT INTO public.users (id, phone, display_name, eula_version, eula_accepted_at)
    VALUES (pg_temp.id(p_n), '+15558710' || p_n, 'Gate ' || p_n, p_eula,
            CASE WHEN p_eula IS NOT NULL THEN now() END);
    INSERT INTO public.profiles (id) VALUES (pg_temp.id(p_n)) ON CONFLICT (id) DO NOTHING;
  END IF;
  IF p_row AND p_age IS NOT NULL THEN
    INSERT INTO public.account_birthdates (user_id, birth_date)
    VALUES (pg_temp.id(p_n), ((now() AT TIME ZONE 'utc')::date - make_interval(years => p_age))::date - 1);
  END IF;
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.invite(p_rel text, p_inviter text, p_code text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at)
  VALUES (pg_temp.rel(p_rel), pg_temp.id(p_inviter), 'pending', p_code,
          now() + interval '7 days', now() - interval '1 hour');
END $$;

CREATE FUNCTION pg_temp.accept_error(p_n text, p_code text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.error_of(format(
    'SELECT public.accept_relationship_invite_v2(%L, %L)', pg_temp.id(p_n), p_code));
END $$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

-- =====================================================================
-- A. Objects, grants, policies.
-- =====================================================================
DO $$
DECLARE
  v_t text;
  v_missing text[] := ARRAY[]::text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                  WHERE p.oid = to_regprocedure('private.account_ready(uuid)')
                    AND p.prosecdef AND p.provolatile = 's'
                    AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: private.account_ready(uuid) missing or not STABLE SECURITY DEFINER search_path ''''';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                  WHERE p.oid = to_regprocedure('public.my_account_ready()')
                    AND p.prosecdef AND p.proconfig = ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: public.my_account_ready() missing or not SECURITY DEFINER search_path ''''';
  END IF;
  IF has_function_privilege('authenticated', 'private.account_ready(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.account_ready(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.account_ready(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.my_account_ready()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.my_account_ready()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: account_ready grants are wrong';
  END IF;
  -- record_eula_acceptance: search_path '', the app's alone.
  IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                  WHERE p.oid = 'public.record_eula_acceptance(text)'::regprocedure
                    AND p.prosecdef AND p.proconfig = ARRAY['search_path=""'])
     OR NOT has_function_privilege('authenticated', 'public.record_eula_acceptance(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.record_eula_acceptance(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance lost its shape or grants';
  END IF;
  -- The invite functions stay the service role's.
  IF has_function_privilege('authenticated', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.accept_relationship_invite_v2(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.relationship_invite_eligibility(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the invite functions'' grants changed';
  END IF;
  -- One restrictive INSERT gate per table, and an UPDATE gate where an
  -- update policy exists.
  FOREACH v_t IN ARRAY ARRAY['opinions', 'opinion_comments', 'opinion_reactions', 'opinion_reposts',
                             'opinion_follows', 'comment_likes', 'forum_reports', 'reminders',
                             'weekly_checkins', 'quiz_shares', 'timeline_events', 'place_updates',
                             'couple_family_members'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies AS p
                    WHERE p.schemaname = 'public' AND p.tablename = v_t
                      AND p.policyname = 'account_ready_insert' AND p.permissive = 'RESTRICTIVE'
                      AND p.cmd = 'INSERT' AND p.roles = '{authenticated}'
                      AND p.with_check = 'my_account_ready()') THEN
      v_missing := array_append(v_missing, v_t || ' insert');
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['opinions', 'opinion_comments', 'opinion_reactions', 'opinion_reposts',
                             'opinion_follows', 'comment_likes', 'reminders', 'weekly_checkins',
                             'quiz_shares', 'timeline_events', 'couple_family_members'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_policies AS p
                    WHERE p.schemaname = 'public' AND p.tablename = v_t
                      AND p.policyname = 'account_ready_update' AND p.permissive = 'RESTRICTIVE'
                      AND p.cmd = 'UPDATE' AND p.roles = '{authenticated}'
                      AND p.qual = 'true' AND p.with_check = 'my_account_ready()') THEN
      v_missing := array_append(v_missing, v_t || ' update');
    END IF;
  END LOOP;
  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: account-ready write gates missing: %', v_missing;
  END IF;
  -- Reads are never gated.
  IF EXISTS (SELECT 1 FROM pg_policies AS p
              WHERE p.schemaname = 'public' AND p.policyname LIKE 'account_ready_%'
                AND p.cmd NOT IN ('INSERT', 'UPDATE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account-ready gate covers reads or deletes';
  END IF;
  -- The shared Opinions posting gate checks readiness.
  IF position('private.account_ready(p_user_id)' IN
       (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'private.assert_can_post(uuid,text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: assert_can_post does not check account readiness';
  END IF;
END $$;

-- =====================================================================
-- B. private.account_ready. Fixtures 01-09.
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.person('01', false, 30, NULL);   -- OTP only: no users row
  PERFORM pg_temp.person('02', true, NULL, '2');   -- no DOB
  PERFORM pg_temp.person('03', true, 17, '2');     -- 17
  PERFORM pg_temp.person('04', true, 30, NULL);    -- no consent
  PERFORM pg_temp.person('05', true, 30, '1');     -- old EULA
  PERFORM pg_temp.person('06', true, 30, '2');     -- complete
  PERFORM pg_temp.person('07', true, 30, '2');     -- complete, then held
  PERFORM pg_temp.person('08', true, 30, 'v2');    -- not a number
  PERFORM pg_temp.person('09', true, 30, '10');    -- a later EULA
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (pg_temp.id('07'), 'safety_review', 'contract');

  IF private.account_ready(NULL)
     OR private.account_ready(pg_temp.id('01'))
     OR private.account_ready(pg_temp.id('02'))
     OR private.account_ready(pg_temp.id('03'))
     OR private.account_ready(pg_temp.id('04'))
     OR private.account_ready(pg_temp.id('05'))
     OR private.account_ready(pg_temp.id('07'))
     OR private.account_ready(pg_temp.id('08')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: account_ready true for an incomplete or held account';
  END IF;
  IF NOT private.account_ready(pg_temp.id('06')) OR NOT private.account_ready(pg_temp.id('09')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: account_ready false for a complete account';
  END IF;
  -- A resolved hold no longer counts.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = pg_temp.id('07') AND kind = 'safety_review';
  IF NOT private.account_ready(pg_temp.id('07')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold still blocks';
  END IF;
  -- The wrapper answers for the caller only.
  PERFORM pg_temp.as_user(pg_temp.id('06'));
  IF NOT public.my_account_ready() THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: my_account_ready false for a complete caller';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('03'));
  IF public.my_account_ready() THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: my_account_ready true for a 17-year-old caller';
  END IF;
  PERFORM pg_temp.as_owner();
END $$;

-- =====================================================================
-- C. Invites: both sides, flag OFF and ON. Fixtures 11-19.
-- =====================================================================
DO $$
DECLARE
  v_on boolean;
  v_msg text;
  v jsonb;
BEGIN
  PERFORM pg_temp.person('11', true, 30, '2');     -- complete inviter
  PERFORM pg_temp.person('12', true, NULL, '2');   -- acceptor: no DOB
  PERFORM pg_temp.person('13', true, 17, '2');     -- acceptor: 17
  PERFORM pg_temp.person('14', true, 30, '1');     -- acceptor: EULA 1
  PERFORM pg_temp.person('15', true, NULL, '2');   -- inviter: no DOB
  PERFORM pg_temp.person('16', true, 17, '2');     -- inviter: 17
  PERFORM pg_temp.person('17', true, 30, NULL);    -- inviter: no consent
  PERFORM pg_temp.person('18', true, 30, '2');     -- complete acceptor
  PERFORM pg_temp.person('19', false, 30, NULL);   -- acceptor: no users row
  PERFORM pg_temp.invite('11', '11', 'GATE11');
  PERFORM pg_temp.invite('15', '15', 'GATE15');
  PERFORM pg_temp.invite('16', '16', 'GATE16');
  PERFORM pg_temp.invite('17', '17', 'GATE17');

  FOREACH v_on IN ARRAY ARRAY[false, true] LOOP
    PERFORM pg_temp.flag('flow_signin_v2', v_on);
    -- The acceptor's side.
    v_msg := pg_temp.accept_error('12', 'GATE11');
    IF v_msg IS DISTINCT FROM 'invite:age_required' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: acceptor without a DOB (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    v_msg := pg_temp.accept_error('13', 'GATE11');
    IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: 17-year-old acceptor (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    v_msg := pg_temp.accept_error('14', 'GATE11');
    IF v_msg IS DISTINCT FROM 'invite:consent_required' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: acceptor without consent (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    v_msg := pg_temp.accept_error('19', 'GATE11');
    IF v_msg IS DISTINCT FROM 'invite:phone_required' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: acceptor with no users row (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    -- The inviter's side: uniform not_possible.
    v_msg := pg_temp.accept_error('18', 'GATE15');
    IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: inviter without a DOB (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    v_msg := pg_temp.accept_error('18', 'GATE16');
    IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: 17-year-old inviter (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    v_msg := pg_temp.accept_error('18', 'GATE17');
    IF v_msg IS DISTINCT FROM 'invite:not_possible' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: inviter without consent (got %)', v_on, coalesce(v_msg, 'no error');
    END IF;
    -- The eligibility the edge functions ask first: never 'legacy'.
    IF public.relationship_invite_eligibility(pg_temp.id('19')) <> 'signup_incomplete'
       OR public.relationship_invite_eligibility(pg_temp.id('12')) <> 'age_required'
       OR public.relationship_invite_eligibility(pg_temp.id('13')) <> 'not_possible'
       OR public.relationship_invite_eligibility(pg_temp.id('14')) <> 'consent_required'
       OR public.relationship_invite_eligibility(pg_temp.id('17')) <> 'consent_required'
       OR public.relationship_invite_eligibility(pg_temp.id('18')) <> 'ok' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: flag %: relationship_invite_eligibility answers', v_on;
    END IF;
  END LOOP;

  -- No refusal created a users row or linked anyone.
  IF EXISTS (SELECT 1 FROM public.users WHERE id = pg_temp.id('19'))
     OR EXISTS (SELECT 1 FROM public.relationships
                 WHERE id IN (pg_temp.rel('11'), pg_temp.rel('15'), pg_temp.rel('16'), pg_temp.rel('17'))
                   AND (status <> 'pending' OR user_b IS NOT NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused accept wrote something';
  END IF;

  -- Both complete, flag OFF: the accept goes through.
  PERFORM pg_temp.flag('flow_signin_v2', false);
  v := public.accept_relationship_invite_v2(pg_temp.id('18'), 'GATE11');
  IF v ->> 'status' IS DISTINCT FROM 'active' OR (v ->> 'relationship_id')::uuid IS DISTINCT FROM pg_temp.rel('11') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two complete accounts could not link (%)', v;
  END IF;
END $$;

-- =====================================================================
-- D. Writes: an incomplete account is refused, a complete one is not.
--    Uses fixtures 02 (no DOB), 03 (17), 04 (no consent), 05 (EULA 1),
--    06 (complete); 21 (complete, then an age hold).
-- =====================================================================
DO $$
DECLARE
  v_n text;
  v_msg text;
  v_id uuid;
BEGIN
  PERFORM pg_temp.person('21', true, 30, '2');
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (pg_temp.id('21'), 'age_review', 'contract');

  FOREACH v_n IN ARRAY ARRAY['01', '02', '03', '04', '05', '21'] LOOP
    PERFORM pg_temp.as_user(pg_temp.id(v_n));
    -- An Opinion, straight into the table (the audit's example).
    v_msg := pg_temp.error_of(format(
      'INSERT INTO public.opinions (user_id, content) VALUES (%L, %L)', pg_temp.id(v_n), 'Entry gate contract'));
    IF v_msg IS NULL OR v_msg NOT LIKE 'new row violates row-level security policy%' THEN
      PERFORM pg_temp.as_owner();
      RAISE EXCEPTION 'CONTRACT VIOLATED: account % inserted an Opinion directly (%)', v_n, coalesce(v_msg, 'no error');
    END IF;
    -- An Opinion through the app's RPC.
    v_msg := pg_temp.error_of(format('SELECT public.create_opinion(%L)', 'Entry gate contract via RPC'));
    IF v_msg IS DISTINCT FROM 'account_not_ready' THEN
      PERFORM pg_temp.as_owner();
      RAISE EXCEPTION 'CONTRACT VIOLATED: account % posted through create_opinion (%)', v_n, coalesce(v_msg, 'no error');
    END IF;
    -- A weekly check-in.
    v_msg := pg_temp.error_of(format(
      'INSERT INTO public.weekly_checkins (user_id, week_ending, communication_rating) VALUES (%L, %L, 7)',
      pg_temp.id(v_n), current_date));
    IF v_msg IS NULL OR v_msg NOT LIKE 'new row violates row-level security policy%' THEN
      PERFORM pg_temp.as_owner();
      RAISE EXCEPTION 'CONTRACT VIOLATED: account % wrote a weekly check-in (%)', v_n, coalesce(v_msg, 'no error');
    END IF;
    PERFORM pg_temp.as_owner();
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.opinions WHERE content LIKE 'Entry gate contract%')
     OR EXISTS (SELECT 1 FROM public.weekly_checkins WHERE user_id IN
                  (SELECT pg_temp.id(n) FROM unnest(ARRAY['01', '02', '03', '04', '05', '21']) AS n)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused write left a row';
  END IF;

  -- The complete account writes all three, and updates its own check-in.
  PERFORM pg_temp.as_user(pg_temp.id('06'));
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.opinions (user_id, content) VALUES (%L, %L)', pg_temp.id('06'), 'Entry gate contract ok'));
  IF v_msg IS NOT NULL THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete account could not insert an Opinion (%)', v_msg;
  END IF;
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.weekly_checkins (user_id, week_ending, communication_rating) VALUES (%L, %L, 7)',
    pg_temp.id('06'), current_date));
  v_msg := coalesce(v_msg, pg_temp.error_of(format(
    'UPDATE public.weekly_checkins SET communication_rating = 8 WHERE user_id = %L', pg_temp.id('06'))));
  PERFORM pg_temp.as_owner();
  IF v_msg IS NOT NULL
     OR (SELECT communication_rating FROM public.weekly_checkins WHERE user_id = pg_temp.id('06')) IS DISTINCT FROM 8 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete account could not write its check-in (%)', coalesce(v_msg, 'not updated');
  END IF;
  -- The RPC path, a minute later than the direct post (the cooldown).
  UPDATE public.opinions SET created_at = now() - interval '2 minutes' WHERE user_id = pg_temp.id('06');
  PERFORM pg_temp.as_user(pg_temp.id('06'));
  v_id := public.create_opinion('Entry gate contract ok via RPC');
  PERFORM pg_temp.as_owner();
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete account could not post through create_opinion';
  END IF;

  -- A complete account that is later held can no longer update its rows,
  -- but can still read and delete them.
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (pg_temp.id('06'), 'safety_review', 'contract');
  PERFORM pg_temp.as_user(pg_temp.id('06'));
  v_msg := pg_temp.error_of(format(
    'UPDATE public.weekly_checkins SET communication_rating = 9 WHERE user_id = %L', pg_temp.id('06')));
  IF v_msg IS NULL OR v_msg NOT LIKE 'new row violates row-level security policy%' THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account updated its check-in (%)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT count(*) FROM public.weekly_checkins WHERE user_id = pg_temp.id('06')) <> 1 THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account can no longer read its own check-in';
  END IF;
  DELETE FROM public.weekly_checkins WHERE user_id = pg_temp.id('06');
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM public.weekly_checkins WHERE user_id = pg_temp.id('06')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account could not delete its own check-in';
  END IF;

  -- The service role is never gated (edge functions, crons).
  SET LOCAL ROLE service_role;
  INSERT INTO public.weekly_checkins (user_id, week_ending, communication_rating)
  VALUES (pg_temp.id('03'), current_date, 5);
  RESET ROLE;
END $$;

-- =====================================================================
-- E. The sign-up path still works for an incomplete account.
--    Fixtures 31-35.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_msg text;
BEGIN
  -- complete_sign_up: OTP only, no users row.
  PERFORM pg_temp.person('31', false, NULL, NULL);
  PERFORM pg_temp.as_user(pg_temp.id('31'));
  v := public.complete_sign_up('Gate Signup', DATE '1990-01-01', '2');
  PERFORM pg_temp.as_owner();
  IF v ->> 'created' IS DISTINCT FROM 'true' OR NOT private.account_ready(pg_temp.id('31')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: complete_sign_up for a new account (%)', v;
  END IF;

  -- set_my_birth_date: a pre-Spec-1 account with no DOB.
  PERFORM pg_temp.person('32', true, NULL, '1');
  PERFORM pg_temp.as_user(pg_temp.id('32'));
  v := public.set_my_birth_date(DATE '1991-02-03');
  PERFORM pg_temp.as_owner();
  IF v ->> 'status' IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_birth_date for an incomplete account (%)', v;
  END IF;

  -- record_eula_acceptance: the same account catches up on consent.
  PERFORM pg_temp.as_user(pg_temp.id('32'));
  PERFORM public.record_eula_acceptance('2');
  PERFORM pg_temp.as_owner();
  IF (SELECT eula_version FROM public.users WHERE id = pg_temp.id('32')) IS DISTINCT FROM '2'
     OR NOT private.account_ready(pg_temp.id('32')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance did not bring the account up to date';
  END IF;

  -- set_my_path: a complete account with no path yet.
  PERFORM pg_temp.as_user(pg_temp.id('32'));
  v := public.set_my_path('just_me', false);
  PERFORM pg_temp.as_owner();
  IF (SELECT path FROM public.users WHERE id = pg_temp.id('32')) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_path after the catch-up (%)', v;
  END IF;

  -- Onboarding state and the home state stay open to an incomplete account.
  PERFORM pg_temp.person('33', true, NULL, NULL);
  PERFORM pg_temp.as_user(pg_temp.id('33'));
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.onboarding_profiles (user_id) VALUES (%L)', pg_temp.id('33')));
  IF v_msg IS NOT NULL THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: onboarding_profiles refused an incomplete account (%)', v_msg;
  END IF;
  v := public.get_my_home_state();
  PERFORM pg_temp.as_owner();
  IF NOT (v -> 'needs') ? 'consent' OR NOT (v -> 'needs') ? 'birth_date' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_home_state for an incomplete account (%)', v;
  END IF;
END $$;

-- =====================================================================
-- F. record_eula_acceptance: update only, version 2 or later.
--    Fixtures 41-44.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  -- No users row: refused, nothing created.
  PERFORM pg_temp.person('41', false, 30, NULL);
  PERFORM pg_temp.as_user(pg_temp.id('41'));
  v_msg := pg_temp.error_of($q$SELECT public.record_eula_acceptance('2')$q$);
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'eula:no_account' OR EXISTS (SELECT 1 FROM public.users WHERE id = pg_temp.id('41')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance without an account (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- Version 1, or anything that isn't a number >= 2: refused, unchanged.
  PERFORM pg_temp.person('42', true, 30, NULL);
  PERFORM pg_temp.as_user(pg_temp.id('42'));
  v_msg := pg_temp.error_of($q$SELECT public.record_eula_acceptance('1')$q$);
  IF v_msg IS DISTINCT FROM 'eula:version_not_current' THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance(1) (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of($q$SELECT public.record_eula_acceptance('v2')$q$);
  IF v_msg IS DISTINCT FROM 'eula:version_not_current' THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance(v2) (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of($q$SELECT public.record_eula_acceptance('')$q$);
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'version_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance(blank) (got %)', coalesce(v_msg, 'no error');
  END IF;
  IF (SELECT eula_version FROM public.users WHERE id = pg_temp.id('42')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused record_eula_acceptance stored a version';
  END IF;

  -- Consent never goes down: a stored 3 stays 3 (and keeps its time).
  PERFORM pg_temp.person('43', true, 30, '3');
  UPDATE public.users SET eula_accepted_at = now() - interval '5 days' WHERE id = pg_temp.id('43');
  PERFORM pg_temp.as_user(pg_temp.id('43'));
  PERFORM public.record_eula_acceptance('2');
  PERFORM pg_temp.as_owner();
  IF (SELECT eula_version FROM public.users WHERE id = pg_temp.id('43')) IS DISTINCT FROM '3'
     OR (SELECT eula_accepted_at FROM public.users WHERE id = pg_temp.id('43')) IS DISTINCT FROM now() - interval '5 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: record_eula_acceptance stepped consent down';
  END IF;

  -- anon can't call it at all.
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.record_eula_acceptance('2');
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon called record_eula_acceptance';
  EXCEPTION WHEN insufficient_privilege THEN
    RESET ROLE;
  END;
END $$;

-- =====================================================================
-- G. SECURITY DEFINER writers (review I-1). A definer function runs as the
--    table owner, so the restrictive policies never reach it: every one the
--    app can call (EXECUTE for authenticated) that INSERTs into or UPDATEs
--    a gated table or an Opinions table must check private.account_ready
--    itself, go through private.assert_can_post or public.create_opinion,
--    or be on the allowlist below with its reason. A new writer that is
--    neither fails here.
-- =====================================================================
DO $$
DECLARE
  v_tables constant text[] := ARRAY[
    -- the 13 tables 20261127100060 gates
    'opinions', 'opinion_comments', 'opinion_reactions', 'opinion_reposts', 'opinion_follows',
    'comment_likes', 'forum_reports', 'reminders', 'weekly_checkins', 'quiz_shares',
    'timeline_events', 'place_updates', 'couple_family_members',
    -- the rest of Opinions
    'post_polls', 'poll_votes', 'poll_options', 'opinion_tags', 'tag_follows',
    'opinion_saves', 'opinion_hides', 'opinion_mutes'];
  -- By design, not gated:
  v_allow constant text[] := ARRAY[
    -- removals and undos of one's own rows (like DELETE, always allowed:
    -- a held or not-ready person may still take their content down)
    'remove_my_opinion(uuid)',
    'remove_my_comment(uuid)',
    'unrepost_opinion(uuid)',
    'retract_poll_vote(uuid)',
    'soft_delete_timeline_event(uuid)',
    -- undo of your own action: un-reacting must always work (owner
    -- ruling, 20261127100090); the increments stay gated
    'decrement_opinion_like_count(uuid)',
    'decrement_opinion_dislike_count(uuid)',
    'decrement_opinion_comment_count(uuid)',
    'decrement_comment_like_count(uuid)',
    -- private preferences and safety tools nobody else sees
    'save_opinion(uuid)',
    'hide_opinion(uuid)',
    'mute_opinion_author(text)',
    'follow_tag(text)'];
  v_gated constant text[] := ARRAY[
    'public.save_conflict_quiz_result(jsonb,text)', 'public.save_loving_now(jsonb)',
    'public.follow_opinion_author(text)', 'public.repost_opinion(uuid)',
    'public.edit_opinion(uuid,text)', 'public.edit_opinion_comment(uuid,text)',
    'public.cast_poll_vote(uuid)', 'public.attach_opinion_tags(uuid,text[])',
    'public.upsert_family_member(uuid,text,date)',
    'public.post_place_update(uuid,text,text,numeric,numeric,text,text)',
    'public.add_event_memory(uuid,text)', 'public.share_a_win(uuid,text,text,date)',
    'public.increment_opinion_like_count(uuid)', 'public.increment_opinion_dislike_count(uuid)',
    'public.increment_opinion_comment_count(uuid)', 'public.increment_comment_like_count(uuid)',
    'public.report_opinion(uuid,text)', 'public.report_opinion_comment(uuid,text)'];
  v_bad text;
  v_sig text;
BEGIN
  SELECT string_agg(x.sig, ', ' ORDER BY x.sig) INTO v_bad
    FROM (SELECT DISTINCT replace(p.oid::regprocedure::text, ' ', '') AS sig, p.prosrc
            FROM pg_proc AS p
            JOIN pg_namespace AS n ON n.oid = p.pronamespace
            CROSS JOIN unnest(v_tables) AS t(name)
           WHERE n.nspname = 'public' AND p.prosecdef
             AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
             AND p.prosrc ~* ('(insert\s+into|update)\s+(only\s+)?(public\.)?' || t.name || '\M')) AS x
   WHERE x.prosrc !~ 'private\.account_ready\(|private\.assert_can_post\(|public\.create_opinion\('
     AND NOT (x.sig = ANY (v_allow));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: SECURITY DEFINER writers of user content without account_ready (gate them or allowlist them with a reason): %', v_bad;
  END IF;
  -- The re-created ones kept their grant and took search_path ''.
  FOREACH v_sig IN ARRAY v_gated LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc AS p
                    WHERE p.oid = v_sig::regprocedure AND p.prosecdef
                      AND p.proconfig = ARRAY['search_path=""']
                      AND position('private.account_ready(auth.uid())' IN p.prosrc) > 0)
       OR NOT has_function_privilege('authenticated', v_sig, 'EXECUTE')
       OR has_function_privilege('anon', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % lost its gate, its grant or search_path ''''', v_sig;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- H. Birthdays (review gap). The rule is age_on_utc_today: whole years
--    between the date of birth and today's UTC date. Fixtures 51-56.
-- =====================================================================
DO $$
DECLARE
  v_today constant date := (now() AT TIME ZONE 'utc')::date;
  v_dob date;
  v_year int;
  v_eighteenth date;
  v_n text;
BEGIN
  -- Exactly 18 today: ready. One day short: not.
  PERFORM pg_temp.person('51', true, NULL, '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id('51'), (v_today - interval '18 years')::date);
  PERFORM pg_temp.person('52', true, NULL, '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id('52'), (v_today - interval '18 years')::date + 1);
  IF NOT private.account_ready(pg_temp.id('51')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not ready on the 18th birthday (born %)', (v_today - interval '18 years')::date;
  END IF;
  IF private.account_ready(pg_temp.id('52')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ready the day before the 18th birthday';
  END IF;

  -- Leap day, on fixed dates. age_on_utc_today is whole years of
  -- age(today, dob), which makes someone born 2008-02-29 18 on 2026-03-01
  -- (not 2026-02-28), and someone born 2012-02-29 18 on 2030-03-01.
  IF position('extract(year FROM age((now() AT TIME ZONE ''utc'')::date, p_birth_date))' IN
       (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'private.age_on_utc_today(date)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: age_on_utc_today is no longer whole years of age(today, dob); re-check the leap-day cases';
  END IF;
  IF extract(year FROM age(DATE '2026-02-28', DATE '2008-02-29')) <> 17
     OR extract(year FROM age(DATE '2026-03-01', DATE '2008-02-29')) <> 18
     OR extract(year FROM age(DATE '2030-02-28', DATE '2012-02-29')) <> 17
     OR extract(year FROM age(DATE '2030-03-01', DATE '2012-02-29')) <> 18
     OR extract(year FROM age(DATE '2032-02-28', DATE '2014-02-28')) <> 18 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the leap-day age rule changed';
  END IF;

  -- Leap day, live: account_ready agrees with "18 on 29 Feb when that year
  -- has one, else on 1 Mar" for leap-day births around 18 years ago.
  FOREACH v_n IN ARRAY ARRAY['53', '54', '55', '56'] LOOP
    v_year := CASE v_n WHEN '53' THEN 2004 WHEN '54' THEN 2008 WHEN '55' THEN 2012 ELSE 2016 END;
    v_dob := make_date(v_year, 2, 29);
    v_eighteenth := CASE WHEN (v_year + 18) % 4 = 0 AND ((v_year + 18) % 100 <> 0 OR (v_year + 18) % 400 = 0)
                         THEN make_date(v_year + 18, 2, 29)
                         ELSE make_date(v_year + 18, 3, 1) END;
    PERFORM pg_temp.person(v_n, true, NULL, '2');
    INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (pg_temp.id(v_n), v_dob);
    IF private.account_ready(pg_temp.id(v_n)) IS DISTINCT FROM (v_today >= v_eighteenth) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: born %, 18 on %, today %: account_ready says %',
        v_dob, v_eighteenth, v_today, private.account_ready(pg_temp.id(v_n));
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- I. The definer RPCs (review I-1). Fixtures 61-66: 61 complete and 62
--    without a DOB, an active couple; 63 on EULA 1, 64 complete, 65 the
--    author, 66 complete then held.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
  v_n text;
  v_member uuid;
  v_op uuid := gen_random_uuid();
  v_handle text;
  v jsonb;
BEGIN
  PERFORM pg_temp.person('61', true, 30, '2');
  PERFORM pg_temp.person('62', true, NULL, '2');
  PERFORM pg_temp.person('63', true, 30, '1');
  PERFORM pg_temp.person('64', true, 30, '2');
  PERFORM pg_temp.person('65', true, 30, '2');
  PERFORM pg_temp.person('66', true, 30, '2');
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (pg_temp.id('66'), 'age_review', 'contract');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at)
  VALUES (pg_temp.rel('61'), pg_temp.id('61'), pg_temp.id('62'), 'active', current_date, now());
  INSERT INTO public.opinions (id, user_id, content) VALUES (v_op, pg_temp.id('65'), 'Entry gate contract: the author');
  v_handle := public.opinion_author_handle(pg_temp.id('65'));

  -- A couple-content RPC: upsert_family_member (a family member and the
  -- birthday reminder it makes).
  PERFORM pg_temp.as_user(pg_temp.id('62'));
  v_msg := pg_temp.error_of($q$SELECT public.upsert_family_member(NULL, 'Auntie Esi', DATE '1970-05-01')$q$);
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'account_not_ready'
     OR EXISTS (SELECT 1 FROM public.couple_family_members WHERE relationship_id = pg_temp.rel('61')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: upsert_family_member for a partner without a DOB (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('61'));
  v_member := public.upsert_family_member(NULL, 'Auntie Esi', DATE '1970-05-01');
  PERFORM pg_temp.as_owner();
  IF v_member IS NULL OR NOT EXISTS (SELECT 1 FROM public.reminders WHERE family_member_id = v_member) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: upsert_family_member for a complete partner';
  END IF;

  -- Opinions RPCs: repost, follow, a public count.
  FOREACH v_n IN ARRAY ARRAY['63', '66'] LOOP
    PERFORM pg_temp.as_user(pg_temp.id(v_n));
    IF pg_temp.error_of(format('SELECT public.repost_opinion(%L)', v_op)) IS DISTINCT FROM 'account_not_ready'
       OR pg_temp.error_of(format('SELECT public.follow_opinion_author(%L)', v_handle)) IS DISTINCT FROM 'account_not_ready'
       OR pg_temp.error_of(format('SELECT public.increment_opinion_like_count(%L)', v_op)) IS DISTINCT FROM 'account_not_ready' THEN
      PERFORM pg_temp.as_owner();
      RAISE EXCEPTION 'CONTRACT VIOLATED: account % reposted, followed or moved a count', v_n;
    END IF;
    PERFORM pg_temp.as_owner();
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.opinion_reposts WHERE opinion_id = v_op)
     OR EXISTS (SELECT 1 FROM public.opinion_follows WHERE following_id = pg_temp.id('65'))
     OR (SELECT like_count FROM public.opinions WHERE id = v_op) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused Opinions RPC wrote something';
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('64'));
  PERFORM public.repost_opinion(v_op);
  PERFORM public.follow_opinion_author(v_handle);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.opinion_reposts WHERE opinion_id = v_op AND user_id = pg_temp.id('64'))
     OR NOT EXISTS (SELECT 1 FROM public.opinion_follows WHERE follower_id = pg_temp.id('64') AND following_id = pg_temp.id('65')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete account could not repost or follow';
  END IF;

  -- Reports stay open (a safety tool), but only a ready reporter counts
  -- toward the auto-hide threshold.
  PERFORM pg_temp.as_user(pg_temp.id('63'));
  PERFORM public.report_opinion(v_op, 'Other');
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.forum_reports WHERE opinion_id = v_op AND reported_by = pg_temp.id('63'))
     OR (SELECT report_count FROM public.opinions WHERE id = v_op) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a not-ready report was dropped or counted (count %)',
      (SELECT report_count FROM public.opinions WHERE id = v_op);
  END IF;
  PERFORM pg_temp.as_user(pg_temp.id('64'));
  PERFORM public.report_opinion(v_op, 'Other');
  PERFORM pg_temp.as_owner();
  IF (SELECT report_count FROM public.opinions WHERE id = v_op) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ready report did not count';
  END IF;

  -- Home state reads consent as account_ready does (review M-1): a
  -- version with no accepted time is no consent.
  UPDATE public.users SET eula_accepted_at = NULL WHERE id = pg_temp.id('64');
  PERFORM pg_temp.as_user(pg_temp.id('64'));
  v := public.get_my_home_state();
  PERFORM pg_temp.as_owner();
  IF NOT (v -> 'needs') ? 'consent' OR private.account_ready(pg_temp.id('64')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: home state and account_ready disagree on consent (%)', v -> 'needs';
  END IF;
END $$;

-- =====================================================================
-- J. Un-reacting always works (owner ruling, 20261127100090). A held
--    account removes its own like, dislike and comment like: the rows go
--    (deletes are never gated) and the decrement RPCs move the counts
--    down. Its increments stay refused. Fixtures 71-72.
-- =====================================================================
-- The like/dislike counters broadcast through realtime.send, which a bare
-- local Postgres lacks: a stub for this transaction only (rolled back).
DO $$
BEGIN
  IF to_regnamespace('realtime') IS NULL THEN
    CREATE SCHEMA realtime;
    CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true)
    RETURNS void LANGUAGE sql AS 'SELECT NULL::void';
  END IF;
END $$;

DO $$
DECLARE
  v_op uuid := gen_random_uuid();
  v_op2 uuid := gen_random_uuid();
  v_comment uuid := gen_random_uuid();
BEGIN
  PERFORM pg_temp.person('71', true, 30, '2');   -- the author
  PERFORM pg_temp.person('72', true, 30, '2');   -- reacted while complete, then held
  INSERT INTO public.opinions (id, user_id, content, like_count, dislike_count)
  VALUES (v_op, pg_temp.id('71'), 'Entry gate contract: liked', 1, 0),
         (v_op2, pg_temp.id('71'), 'Entry gate contract: disliked', 0, 1);
  INSERT INTO public.opinion_comments (id, opinion_id, user_id, content, like_count)
  VALUES (v_comment, v_op, pg_temp.id('71'), 'Entry gate contract: a comment', 1);
  INSERT INTO public.opinion_reactions (opinion_id, user_id, reaction_type)
  VALUES (v_op, pg_temp.id('72'), 'like'), (v_op2, pg_temp.id('72'), 'dislike');
  INSERT INTO public.comment_likes (comment_id, user_id) VALUES (v_comment, pg_temp.id('72'));
  INSERT INTO public.account_holds (user_id, kind, reason_ref) VALUES (pg_temp.id('72'), 'safety_review', 'contract');

  -- The app's un-react: delete the row, then the decrement.
  PERFORM pg_temp.as_user(pg_temp.id('72'));
  DELETE FROM public.opinion_reactions WHERE user_id = pg_temp.id('72');
  DELETE FROM public.comment_likes WHERE user_id = pg_temp.id('72');
  PERFORM public.decrement_opinion_like_count(v_op);
  PERFORM public.decrement_opinion_dislike_count(v_op2);
  PERFORM public.decrement_comment_like_count(v_comment);
  -- Its increments stay refused.
  IF pg_temp.error_of(format('SELECT public.increment_opinion_like_count(%L)', v_op)) IS DISTINCT FROM 'account_not_ready'
     OR pg_temp.error_of(format('SELECT public.increment_opinion_dislike_count(%L)', v_op)) IS DISTINCT FROM 'account_not_ready'
     OR pg_temp.error_of(format('SELECT public.increment_comment_like_count(%L)', v_comment)) IS DISTINCT FROM 'account_not_ready' THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account moved a count up';
  END IF;
  PERFORM pg_temp.as_owner();

  IF EXISTS (SELECT 1 FROM public.opinion_reactions WHERE user_id = pg_temp.id('72'))
     OR EXISTS (SELECT 1 FROM public.comment_likes WHERE user_id = pg_temp.id('72')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account could not remove its own reaction';
  END IF;
  IF (SELECT like_count FROM public.opinions WHERE id = v_op) <> 0
     OR (SELECT dislike_count FROM public.opinions WHERE id = v_op2) <> 0
     OR (SELECT like_count FROM public.opinion_comments WHERE id = v_comment) <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account''s un-react left a count up (like %, dislike %, comment like %)',
      (SELECT like_count FROM public.opinions WHERE id = v_op),
      (SELECT dislike_count FROM public.opinions WHERE id = v_op2),
      (SELECT like_count FROM public.opinion_comments WHERE id = v_comment);
  END IF;
END $$;

ROLLBACK;
