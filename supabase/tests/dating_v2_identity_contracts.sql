-- supabase/tests/dating_v2_identity_contracts.sql
-- Spec 2 W1 (§4.1, §4.2, §6.3, §7.1, §7.5; I-11, R-2, S-5): phone HMACs from
-- auth.users and parked accounts (A), block pairs and standing (B),
-- deletion carry-over (C) (W1a); encryption at rest (D1, D2: W1c);
-- never-introduce (E1), activation, pause, exit, the parked pause and the
-- generation key guard (E2) (W1d). Batch 9 adds E1b: the never-introduce
-- rulings (no phone oracle, only HMACs, strict E.164, the key gate, never
-- gated on eligibility, rate limit, locks, the fail-closed filter, O3).
-- Batch 10 (Task 12) fills E2 (E2-E2j): exit's full hard delete through the
-- CSAM evidence guard, faith-only withdrawal (owner ruling 2), consent
-- input and the server's clock, the setup lock, the device, the NULL-blind
-- sweep, the name re-check, both key fingerprints, health v2. E2's people
-- are 5e2a0000-0000-0000-0000-0000000001NN, phones 15558704NN.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, from the repo root:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql
-- Fixture ids 5e2a0000-0000-0000-0000-0000000000NN; phones 15558700NN on
-- auth.users (Auth's form, no '+'), copied to public.users by Spec 1's
-- trigger. Every refusal is checked by its message.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  PERFORM set_config('app.settings.fresh_start_key', 'spec2-w1-contract-fresh-start-key-0123456789', true);
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An adult account [p_n] on the Dating path, phone 15558700<p_n>.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558700' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558700' || p_n, 'Person ' || p_n, 'dating', now() - interval '400 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_owner() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- [p_sql] run as the service role: its text result, or 'ERROR: <message>'.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  BEGIN
    EXECUTE p_sql INTO v;
  EXCEPTION WHEN raise_exception OR insufficient_privilege OR not_null_violation THEN
    PERFORM pg_temp.as_owner();
    RETURN 'ERROR: ' || SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

-- [p_sql] run as [p_user]: NULL, or the message it raised.
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user(p_user);
  EXECUTE p_sql;
  PERFORM pg_temp.as_owner();
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege OR invalid_parameter_value THEN
  PERFORM pg_temp.as_owner();
  RETURN SQLERRM;
END $$;

-- =====================================================================
-- A. (W1a) HMACs from auth.users; parked accounts; the relationship guard.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.person('01');
  v_b constant uuid := pg_temp.person('02');
  v_park constant uuid := pg_temp.person('03');
  v_nokey constant uuid := pg_temp.person('04');
  v_c constant uuid := pg_temp.person('05');
  v_d constant uuid := pg_temp.person('06');
  v_before text;
  v_nonce text;
  v_got text;
  v_rel uuid;
BEGIN
  IF to_regprocedure('public.dating_phone_hmac_for_user(uuid)') IS NULL
     OR to_regprocedure('public.dating_phone_canonical(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1a HMAC helpers are missing';
  END IF;
  IF has_function_privilege('anon', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dating_phone_canonical(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an HMAC helper is executable outside the database';
  END IF;
  IF public.dating_phone_canonical('+233 (20) 000-0001') IS DISTINCT FROM '+233200000001'
     OR public.dating_phone_canonical('233200000001') IS DISTINCT FROM '+233200000001'
     OR public.dating_phone_canonical('no digits') IS NOT NULL
     OR public.dating_phone_canonical(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_phone_canonical is not ''+'' || digits';
  END IF;

  -- From Auth's number, in the canonical form.
  IF public.dating_phone_hmac_for_user(v_a) IS DISTINCT FROM public.dating_phone_hmac('+1555870001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the HMAC is not dating_phone_hmac(''+'' || digits of auth.users.phone)';
  END IF;
  -- Tamper: rewriting public.users.phone changes nothing (mutant 1).
  UPDATE public.users SET phone = '+15558709999' WHERE id = v_a;
  IF public.dating_phone_hmac_for_user(v_a) IS DISTINCT FROM public.dating_phone_hmac('+1555870001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the HMAC followed public.users.phone (tamper)';
  END IF;

  -- Former partners: ending records both directions from Auth's numbers,
  -- and tampering both mirrors afterwards keeps them excluded.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_a, v_b, 'active') RETURNING id INTO v_rel;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.end_relationship(v_rel);
  PERFORM pg_temp.as_owner();
  UPDATE public.users SET phone = '+15558709998' WHERE id = v_b;
  IF (SELECT count(*) FROM public.dating_former_partner_exclusions WHERE relationship_id = v_rel) IS DISTINCT FROM 2
     OR NOT public.dating_former_partner_excluded(v_a, v_b)
     OR NOT public.dating_former_partner_excluded(v_b, v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the former-partner exclusion did not survive a tampered public.users.phone';
  END IF;
  -- Real number changes afterwards (Spec 1's verified change, in Auth), by
  -- both: still excluded both ways while both accounts exist.
  UPDATE auth.users SET phone = '15558709997' WHERE id = v_b;
  UPDATE auth.users SET phone = '15558709996' WHERE id = v_a;
  IF NOT public.dating_former_partner_excluded(v_a, v_b) OR NOT public.dating_former_partner_excluded(v_b, v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a former partner''s new number undid the exclusion';
  END IF;

  -- Parked (I-11): consume_fresh_start writes the same HMAC the helper gives
  -- before the park; after Auth's +999 rewrite (before and after the mark)
  -- the helper still gives it, never the placeholder's (mutant 27).
  INSERT INTO public.account_activity (user_id, last_active_at) VALUES (v_park, now() - interval '200 days')
  ON CONFLICT (user_id) DO UPDATE SET last_active_at = EXCLUDED.last_active_at;
  v_before := public.dating_phone_hmac_for_user(v_park);
  v_nonce := private.seal_fresh_start(v_park, now());
  v_got := pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce));
  IF v_got IS DISTINCT FROM v_park::text
     OR (SELECT parked_phone_hmac FROM public.users WHERE id = v_park) IS DISTINCT FROM v_before
     OR v_before IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_phone_hmac is not the helper''s pre-park HMAC';
  END IF;
  UPDATE auth.users SET phone = '999123456789203' WHERE id = v_park;
  IF public.dating_phone_hmac_for_user(v_park) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: between the +999 rewrite and the mark, the helper left the real number';
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.mark_fresh_start_parked(%L)::text', v_park));
  IF v_got IS DISTINCT FROM ''
     OR (SELECT phone_released_at FROM public.users WHERE id = v_park) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the park fixture did not complete';
  END IF;
  IF public.dating_phone_hmac_for_user(v_park) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account''s HMAC is not the pre-park one';
  END IF;
  -- Parked while the key was missing: NULL, never the +999 HMAC.
  UPDATE auth.users SET phone = '999123456789204' WHERE id = v_nokey;
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = NULL WHERE id = v_nokey;
  IF public.dating_phone_hmac_for_user(v_nokey) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account without parked_phone_hmac got an HMAC (the +999 one)';
  END IF;

  -- The relationship guard (R6): the trigger calls the null-safe function,
  -- and active, paused and pending relationships all pause Dating.
  IF to_regprocedure('public.handle_relationship_dating_guard()') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'relationship_dating_guard'
                      AND tgrelid = 'public.relationships'::regclass
                      AND tgfoid = 'public.sync_dating_pause_on_relationship()'::regprocedure) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_dating_guard is not wired to sync_dating_pause_on_relationship';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_c, 'active'), (v_d, 'active');
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_c, v_d, 'active') RETURNING id INTO v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active relationship did not pause Dating for both';
  END IF;
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id IN (v_c, v_d);
  UPDATE public.relationships SET status = 'paused', paused_at = now(), paused_by = v_c WHERE id = v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused relationship did not pause Dating for both';
  END IF;
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id IN (v_c, v_d);
  UPDATE public.relationships SET status = 'active', paused_at = NULL, paused_by = NULL WHERE id = v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused back to active did not pause Dating for both';
  END IF;
END $$;

-- A, continued (W1a fix round 1): the grants; the recompute, the backfill
-- and 'archived' with the key set; rows in the stored form written before
-- W1a (the HMAC of Auth's raw number, through the public.users mirror),
-- including a deleted ex-partner who comes back on the same number (§7.1).
DO $$
DECLARE
  v_e constant uuid := pg_temp.person('07');
  v_f constant uuid := pg_temp.person('08');
  v_g constant uuid := pg_temp.person('09');
  v_h constant uuid := pg_temp.person('13');
  v_ex constant uuid := pg_temp.person('14');
  v_sur constant uuid := pg_temp.person('15');
  v_lone constant uuid := pg_temp.person('16');
  v_mid constant uuid := pg_temp.person('17');
  v_x constant uuid := pg_temp.person('18');
  v_rel31 constant uuid := pg_temp.person('31');
  v_new constant uuid := pg_temp.id('19');
  v_sur2 constant uuid := pg_temp.person('32');
  v_ex2 constant uuid := pg_temp.person('33');
  v_arch uuid;
  v_legacy uuid;
  v_gone uuid;
  v_gone2 uuid;
  v_n integer;
  v_failed boolean := false;
BEGIN
  -- Grants: the helpers, the predicate and the recompute are the
  -- database's own; the recorder and the backfill are the service role's.
  IF has_function_privilege('anon', 'public.dating_phone_canonical(text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_phone_canonical(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.dating_former_partner_excluded(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dating_former_partner_excluded(uuid,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_former_partner_excluded(uuid,uuid)', 'EXECUTE')
     OR to_regprocedure('private.dating_recompute_former_partner_exclusions()') IS NULL
     OR has_function_privilege('anon', 'private.dating_recompute_former_partner_exclusions()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_recompute_former_partner_exclusions()', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_recompute_former_partner_exclusions()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.record_dating_former_partner_exclusion(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_dating_former_partner_exclusion(uuid,boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.backfill_dating_former_partner_exclusions()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.backfill_dating_former_partner_exclusions()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server-only exclusion function is executable by an API role';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.record_dating_former_partner_exclusion(uuid,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.backfill_dating_former_partner_exclusions()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role lost the exclusion recorder or the backfill';
  END IF;

  -- The backfill survives a relationship whose user_a deleted their account
  -- (relationships.user_a is ON DELETE SET NULL).
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (NULL, v_lone, 'ended');
  BEGIN
    PERFORM public.backfill_dating_former_partner_exclusions();
  EXCEPTION WHEN not_null_violation THEN
    v_failed := true;
  END;
  IF v_failed THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill failed on a relationship whose user_a is gone';
  END IF;

  -- An archived pair with no rows yet.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_e, v_f, 'archived') RETURNING id INTO v_arch;
  -- A live ended pair whose rows are in the pre-W1a form.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_g, v_h, 'ended') RETURNING id INTO v_legacy;
  INSERT INTO public.dating_former_partner_exclusions (user_id, excluded_phone_hmac, relationship_id) VALUES
    (v_g, public.dating_phone_hmac('1555870013'), v_legacy),
    (v_h, public.dating_phone_hmac('1555870009'), v_legacy);
  -- An ended pair in the pre-W1a form whose user_a then deletes their account.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_ex, v_sur, 'ended') RETURNING id INTO v_gone;
  INSERT INTO public.dating_former_partner_exclusions (user_id, excluded_phone_hmac, relationship_id) VALUES
    (v_ex, public.dating_phone_hmac('1555870015'), v_gone),
    (v_sur, public.dating_phone_hmac('1555870014'), v_gone);
  DELETE FROM public.users WHERE id = v_ex;
  DELETE FROM auth.users WHERE id = v_ex;
  -- The same with user_b deleting.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_sur2, v_ex2, 'ended') RETURNING id INTO v_gone2;
  INSERT INTO public.dating_former_partner_exclusions (user_id, excluded_phone_hmac, relationship_id) VALUES
    (v_sur2, public.dating_phone_hmac('1555870033'), v_gone2),
    (v_ex2, public.dating_phone_hmac('1555870032'), v_gone2);
  DELETE FROM public.users WHERE id = v_ex2;
  DELETE FROM auth.users WHERE id = v_ex2;

  v_n := private.dating_recompute_former_partner_exclusions();
  IF v_n IS NULL OR v_n < 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recompute did not run with the key set (got %)', v_n;
  END IF;
  IF (SELECT count(*) FROM public.dating_former_partner_exclusions WHERE relationship_id = v_arch) IS DISTINCT FROM 2
     OR NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                     WHERE user_id = v_e AND excluded_phone_hmac = public.dating_phone_hmac('+1555870008'))
     OR NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                     WHERE user_id = v_f AND excluded_phone_hmac = public.dating_phone_hmac('+1555870007')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill did not record an archived relationship both ways';
  END IF;
  IF (SELECT count(*) FROM public.dating_former_partner_exclusions WHERE relationship_id = v_legacy) IS DISTINCT FROM 2
     OR NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                     WHERE user_id = v_g AND excluded_phone_hmac = public.dating_phone_hmac('+1555870013'))
     OR NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                     WHERE user_id = v_h AND excluded_phone_hmac = public.dating_phone_hmac('+1555870009')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recompute left a pre-W1a row it could rebuild';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                  WHERE user_id = v_sur AND excluded_phone_hmac = public.dating_phone_hmac('1555870014'))
     OR NOT EXISTS (SELECT 1 FROM public.dating_former_partner_exclusions
                     WHERE user_id = v_sur2 AND excluded_phone_hmac = public.dating_phone_hmac('1555870033')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recompute deleted an exclusion it cannot rebuild (a deleted ex-partner)';
  END IF;

  -- The deleted ex-partner registers again on the same SIM: still excluded
  -- both ways, through the stored pre-W1a row.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_new, '1555870014', now(), now());
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_new, '1555870014', 'Person 19', 'dating', now(), now(), '2');
  IF NOT public.dating_former_partner_excluded(v_new, v_sur) OR NOT public.dating_former_partner_excluded(v_sur, v_new) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted ex-partner who came back on the same number is not excluded';
  END IF;
  -- Tamper: rewriting the mirror changes nothing; the stored form is read
  -- from Auth (§7.1).
  UPDATE public.users SET phone = '15550009999' WHERE id = v_new;
  IF NOT public.dating_former_partner_excluded(v_new, v_sur) OR NOT public.dating_former_partner_excluded(v_sur, v_new) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tampered public.users.phone undid a stored-form exclusion';
  END IF;
  -- Auth's number with a '+' and spaces still matches the stored digits.
  UPDATE auth.users SET phone = '+1 555 870 014' WHERE id = v_new;
  IF NOT public.dating_former_partner_excluded(v_new, v_sur) OR NOT public.dating_former_partner_excluded(v_sur, v_new) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a formatted Auth number missed a stored-form exclusion';
  END IF;

  -- Archived counts as ended: new numbers afterwards don't undo it.
  UPDATE auth.users SET phone = '15558709995' WHERE id = v_e;
  UPDATE auth.users SET phone = '15558709994' WHERE id = v_f;
  IF NOT public.dating_former_partner_excluded(v_e, v_f) OR NOT public.dating_former_partner_excluded(v_f, v_e) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived pair''s new numbers undid the exclusion';
  END IF;

  -- The stored form is never matched for a parked account: not on Auth's
  -- +999 placeholder (before the mark), not once the number is released.
  UPDATE auth.users SET phone = '999123456789217' WHERE id = v_mid;
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = NULL WHERE id = v_rel31;
  INSERT INTO public.dating_former_partner_exclusions (user_id, excluded_phone_hmac, relationship_id) VALUES
    (v_x, public.dating_phone_hmac('999123456789217'), NULL),
    (v_x, public.dating_phone_hmac('1555870031'), NULL);
  IF public.dating_former_partner_excluded(v_mid, v_x) OR public.dating_former_partner_excluded(v_x, v_mid) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stored row matched Auth''s +999 placeholder';
  END IF;
  IF public.dating_former_partner_excluded(v_rel31, v_x) OR public.dating_former_partner_excluded(v_x, v_rel31) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stored row matched a released account''s number';
  END IF;
END $$;

-- A pair's introduction ([p_state]), with the two snapshots today's schema
-- needs (dropped in W5a).
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid, p_state text DEFAULT 'presented') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (least(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (greatest(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', p_state,
          'spec2-w1-contract', v_low, v_high, 0.5)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- An active match between [p_a] and [p_b] (with its introduction).
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state)
  VALUES (pg_temp.intro(p_a, p_b, 'matched'), least(p_a, p_b), greatest(p_a, p_b), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- =====================================================================
-- B. (W1a) Block pairs by HMAC; standing reads restrictions, enforcement
--    records and Spec 1's holds; the new tables are no client's (S-5).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.person('10');
  v_b constant uuid := pg_temp.person('11');
  v_c constant uuid := pg_temp.person('12');
  v_m uuid;
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['public.enforcement_records', 'public.dating_block_hmacs'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = v_t::regclass)
       OR has_table_privilege('anon', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT')
       OR has_table_privilege('authenticated', v_t, 'INSERT')
       OR NOT has_table_privilege('service_role', v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % has the wrong RLS or grants', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['public.dating_introductions', 'public.dating_interest_actions', 'public.dating_matches'] LOOP
    IF has_table_privilege('service_role', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is readable outside definer functions (S-5)', v_t;
    END IF;
  END LOOP;

  -- Blocking writes the HMAC pair and closes the match with its reason
  -- and evidence window.
  v_m := pg_temp.match(v_a, v_b);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  PERFORM public.block_dating_user('spec2-w1-block-0001', v_b);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                  WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_a)
                    AND blocked_hmac = public.dating_phone_hmac_for_user(v_b)
                    AND purge_after IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: block_dating_user wrote no HMAC pair';
  END IF;
  IF (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'blocked/blocked'
     OR coalesce((SELECT evidence_until FROM public.dating_matches WHERE id = v_m)
                 BETWEEN now() + interval '29 days' AND now() + interval '31 days', false) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the blocked match has no closed_reason or 30-day evidence window';
  END IF;

  -- Standing.
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clean account is not in good standing';
  END IF;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, effect_until, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_c), 'dating', 'suspended', NULL, now() + interval '2 years');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an enforcement record for the number';
  END IF;
  UPDATE public.enforcement_records SET effect_until = now() - interval '1 minute'
   WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enforcement record past effect_until still counts';
  END IF;
  UPDATE public.enforcement_records SET scope = 'opinions', effect_until = NULL
   WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions-scope record closed Dating';
  END IF;
  UPDATE public.enforcement_records SET scope = 'dating', effect_until = NULL, purge_after = now() - interval '1 minute'
   WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enforcement record past purge_after still counts';
  END IF;
  DELETE FROM public.enforcement_records WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  PERFORM public.place_account_hold(v_c, 'safety_review', 'spec2-w1-contract');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an unresolved safety_review hold';
  END IF;
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_c;
  PERFORM public.place_account_hold(v_c, 'age_review', 'spec2-w1-contract');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an unresolved age_review hold';
  END IF;
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_c;
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resolved holds still close Dating';
  END IF;
END $$;

-- B2. (W1a) Without the exclusion key a block still works (no HMAC pair is
--     written, nothing raises); dating_matches.closed_reason takes the kill
--     switch's neutral 'other' (owner 2026-11-06, PF-F2) and nothing unknown;
--     every surviving HMAC column takes only 64 lowercase hex (M-2, I-6); a
--     member deleted outside prepare_account_deletion closes the active
--     match with account_deleted and the 30-day window (M-3).
DO $$
DECLARE
  v_d constant uuid := pg_temp.person('34');
  v_e constant uuid := pg_temp.person('35');
  v_f constant uuid := pg_temp.person('36');
  v_g constant uuid := pg_temp.person('37');
  v_good constant text := repeat('a', 64);
  v_m uuid;
  v_m2 uuid;
  v_n integer;
  v_sql text;
BEGIN
  v_m := pg_temp.match(v_d, v_e);
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_d, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.block_dating_user('spec2-w1-block-0002', v_e);
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the exclusion key block_dating_user failed: %', SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  SELECT count(*) INTO v_n FROM public.dating_blocks WHERE blocker_user_id = v_d AND blocked_user_id = v_e;
  IF v_n IS DISTINCT FROM 1
     OR (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'blocked/blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the exclusion key the block or the match close was skipped';
  END IF;

  -- Matches and reports survive a member's, or the introduction's, deletion.
  SELECT count(*) INTO v_n FROM pg_constraint
   WHERE conname IN ('dating_reports_reporter_user_id_fkey', 'dating_reports_target_user_id_fkey',
                     'dating_matches_user_low_id_fkey', 'dating_matches_user_high_id_fkey',
                     'dating_matches_introduction_id_fkey')
     AND confdeltype = 'n';
  IF v_n IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % of the 5 survival foreign keys are ON DELETE SET NULL', v_n;
  END IF;
  DELETE FROM public.dating_introductions WHERE id = (SELECT introduction_id FROM public.dating_matches WHERE id = v_m);
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND introduction_id IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting the introduction deleted its match';
  END IF;

  BEGIN
    UPDATE public.dating_matches SET closed_reason = 'other' WHERE id = v_m;
  EXCEPTION WHEN check_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_matches.closed_reason refuses the kill switch''s ''other''';
  END;
  BEGIN
    UPDATE public.dating_matches SET closed_reason = 'spec2_w1_unknown' WHERE id = v_m;
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_matches.closed_reason took an unknown reason';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- M-2, I-6: the HMAC columns that survive a deletion hold only HMACs.
  FOREACH v_sql IN ARRAY ARRAY[
    format('INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after) VALUES (%L, ''dating'', ''suspended'', now() + interval ''1 day'')', repeat('a', 63)),
    format('INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after) VALUES (%L, ''dating'', ''suspended'', now() + interval ''1 day'')', upper(v_good)),
    format('INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac) VALUES (%L, %L)', repeat('g', 64), v_good),
    format('INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac) VALUES (%L, %L)', v_good, '+233244000000'),
    format('INSERT INTO public.dating_reports (category, target_phone_hmac) VALUES (''spam'', %L)', '233244000000'),
    format('INSERT INTO public.dating_reports (category, target_phone_hmac) VALUES (''spam'', %L)', upper(v_good))
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a surviving HMAC column stored a non-HMAC value: %', v_sql;
    EXCEPTION WHEN check_violation THEN
      NULL;
    END;
  END LOOP;
  BEGIN
    INSERT INTO public.dating_reports (category, target_phone_hmac) VALUES ('spam', v_good);
  EXCEPTION WHEN check_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_reports.target_phone_hmac refused a well-formed HMAC';
  END;
  -- M-4: a carried record lives 2 years at most.
  BEGIN
    INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after)
    VALUES (v_good, 'dating', 'suspended', now() + interval '3 years');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enforcement record outlives the 2-year cap';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- M-3: a deletion that skips prepare_account_deletion still seals the match.
  v_m2 := pg_temp.match(v_f, v_g);
  DELETE FROM public.users WHERE id = v_g;
  IF (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m2)
       IS DISTINCT FROM 'closed/account_deleted'
     OR coalesce((SELECT evidence_until FROM public.dating_matches WHERE id = v_m2)
                 BETWEEN now() + interval '29 days' AND now() + interval '31 days', false) IS NOT TRUE
     OR (SELECT closed_at FROM public.dating_matches WHERE id = v_m2) IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m2
                     AND v_f IN (user_low_id, user_high_id) AND (user_low_id IS NULL OR user_high_id IS NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member deleted directly left the match open (% / %)',
      (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m2),
      (SELECT evidence_until FROM public.dating_matches WHERE id = v_m2);
  END IF;
  -- An already-closed match keeps its own reason and window.
  DELETE FROM public.users WHERE id = v_e;
  IF (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m)
       IS DISTINCT FROM 'blocked/other' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting a member rewrote a closed match';
  END IF;
END $$;

-- B3. (W1a, I-5, owner 2026-11-06; W1b fix round 1, M-4) dating_exclusion_key
--     is fingerprinted only by the owner's seeder, never by a user RPC; an
--     unseeded fingerprint refuses like a mismatch (counted, nothing stored);
--     under a different live key, enrolment, activation and
--     generation refuse quietly (nothing changes, nothing raises) and count
--     dating.exclusion_key.mismatch, so carried restrictions, block pairs and
--     exclusions are never voided silently. A missing key is not a mismatch
--     (its own guards refuse: generation, deletion, health).
CREATE FUNCTION pg_temp.mismatch_count() RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(count), 0)::bigint FROM public.metric_counters WHERE key = 'dating.exclusion_key.mismatch';
$$;

DO $$
DECLARE
  v_h constant uuid := pg_temp.person('41');
  v_fp constant text := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
  v_before bigint;
  v_row public.dating_enrollments%ROWTYPE;
  v jsonb;
BEGIN
  IF v_fp IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: the contract key is not set';
  END IF;
  -- Unseeded: a mismatch, and no user RPC seeds it (M-4).
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: a fingerprint is already stored';
  END IF;
  IF private.dating_exclusion_key_mismatch() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unseeded fingerprint is not a mismatch';
  END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_h, 'role', 'authenticated')::text, true);
  v_before := pg_temp.mismatch_count();
  BEGIN
    v_row := public.begin_dating_enrollment('1', 'spec2-w1-enrol-0000');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with an unseeded fingerprint enrolment did not refuse quietly: %', SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin_dating_enrollment seeded the exclusion key fingerprint';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_h) OR v_row.user_id IS NOT NULL
     OR pg_temp.mismatch_count() IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with an unseeded fingerprint enrolment went ahead or was not counted';
  END IF;
  IF has_function_privilege('authenticated', 'private.seed_dating_exclusion_key_fingerprint()', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.seed_dating_exclusion_key_fingerprint()', 'EXECUTE')
     OR has_function_privilege('anon', 'private.seed_dating_exclusion_key_fingerprint()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can seed the exclusion key fingerprint';
  END IF;
  -- The owner seeds it (checklist items 2 and 11).
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready'
     OR private.dating_exclusion_key_mismatch() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s seed did not make the key match';
  END IF;
  IF (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') IS DISTINCT FROM v_fp THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seeded fingerprint is not the live key''s';
  END IF;

  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-rotated-key', true);
  IF private.dating_exclusion_key_mismatch() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rotated exclusion key is not a mismatch';
  END IF;
  IF (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') IS DISTINCT FROM v_fp
     OR private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'mismatch'
     OR (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') IS DISTINCT FROM v_fp THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rotated key overwrote the stored fingerprint';
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_h, 'role', 'authenticated')::text, true);
  v_before := pg_temp.mismatch_count();
  BEGIN
    v_row := public.begin_dating_enrollment('1', 'spec2-w1-enrol-0001');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key enrolment did not refuse quietly: %', SQLERRM;
  END;
  IF EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_h) OR v_row.user_id IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key enrolment went ahead';
  END IF;
  IF pg_temp.mismatch_count() IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the enrolment refusal was not counted';
  END IF;

  -- Activation: an enrolment that exists stays as it is.
  PERFORM pg_temp.as_owner();
  INSERT INTO public.dating_enrollments (user_id, state, terms_version, opted_in_at) VALUES (v_h, 'profile_draft', '1', now());
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_h, 'role', 'authenticated')::text, true);
  v_before := pg_temp.mismatch_count();
  BEGIN
    v_row := public.activate_dating_profile('spec2-w1-activate-0001');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key activation did not refuse quietly: %', SQLERRM;
  END;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_h) IS DISTINCT FROM 'profile_draft'
     OR v_row.state IS DISTINCT FROM 'profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key activation went ahead';
  END IF;
  IF pg_temp.mismatch_count() IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the activation refusal was not counted';
  END IF;
  PERFORM pg_temp.as_owner();

  -- Generation (its flag on, inside this transaction only).
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
  v_before := pg_temp.mismatch_count();
  v := public.run_dating_candidate_generation(NULL);
  IF v IS DISTINCT FROM '{"skipped": "exclusion_key_mismatch"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key generation did not refuse: %', v;
  END IF;
  IF pg_temp.mismatch_count() IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the generation refusal was not counted';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';

  -- A missing key is not a mismatch; the original key matches again.
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  IF private.dating_exclusion_key_mismatch() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missing key counted as a mismatch';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF private.dating_exclusion_key_mismatch() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fingerprinted key no longer matches';
  END IF;
END $$;
-- =====================================================================
-- C. (W1a) Deletion carry-over (§6.3): enforcement records, block pairs,
--    sealed matches and pseudonymised reports survive; delete, re-register on
--    the same SIM and tamper public.users.phone: still excluded, blocked
--    and restricted; a parked account is carried under its real number.
--    Each restriction carries under the HMAC stamped when it was placed
--    (I-1); the delete's own pass (auth.users trigger) counts, and it reads
--    the key's fingerprint without ever storing it (M-7). A timed
--    restriction keeps its end; a closed match keeps its window; a report
--    that already has an HMAC keeps it (I-3, M-4).
-- =====================================================================
CREATE FUNCTION pg_temp.metric_count(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(count), 0)::bigint FROM public.metric_counters WHERE key = p_key;
$$;

DO $$
DECLARE
  v_gone constant uuid := pg_temp.person('20');
  v_blocker constant uuid := pg_temp.person('21');
  v_blocked constant uuid := pg_temp.person('22');
  v_match_with constant uuid := pg_temp.person('23');
  v_reporter constant uuid := pg_temp.person('24');
  v_reported constant uuid := pg_temp.person('25');
  v_ex constant uuid := pg_temp.person('27');
  v_nokey constant uuid := pg_temp.person('28');
  v_parked constant uuid := pg_temp.person('29');
  v_new constant uuid := pg_temp.id('26');
  v_fresh constant uuid := pg_temp.id('30');
  v_hmac text;
  v_real text;
  v_live uuid;
  v_m uuid;
  v_rel uuid;
  v_got text;
  v_timed uuid;
  v_ends constant timestamptz := now() + interval '20 days';
  v_m_old uuid;
  v_prior constant text := public.dating_phone_hmac('spec2-w1-c-prior-report');
  v_unseeded bigint;
  v_late bigint;
  v_mm bigint;
BEGIN
  v_hmac := public.dating_phone_hmac_for_user(v_gone);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_gone, 'suspended')
  RETURNING id INTO v_live;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, lifted_at)
  VALUES (v_gone, 'under_review', now() - interval '1 day');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, starts_at, ends_at)
  VALUES (v_gone, 'moderation_hold', now() - interval '9 days', now() - interval '2 days');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, ends_at)
  VALUES (v_gone, 'suspended', v_ends) RETURNING id INTO v_timed;
  -- A block made before W1a (no HMAC row yet), and one made through the RPC.
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_blocker, v_gone, public.dating_pair_key(v_blocker, v_gone));
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_gone, 'role', 'authenticated')::text, true);
  PERFORM public.block_dating_user('spec2-w1-block-0020', v_blocked);
  PERFORM pg_temp.as_owner();
  v_m := pg_temp.match(v_gone, v_match_with);
  v_m_old := pg_temp.match(v_gone, v_reporter);
  UPDATE public.dating_matches
     SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '20 days',
         evidence_until = now() + interval '10 days'
   WHERE id = v_m_old;
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES
    (v_reporter, v_gone, 'harassment'), (v_gone, v_reported, 'spam');
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category, target_phone_hmac)
  VALUES (v_blocker, v_gone, 'other', v_prior);
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_gone, v_ex, 'ended', now())
  RETURNING id INTO v_rel;
  PERFORM public.record_dating_former_partner_exclusion(v_rel, true);
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  v_unseeded := pg_temp.metric_count('dating.exclusion_key.unseeded');
  v_late := pg_temp.metric_count('dating.deletion.late_carry');
  v_mm := pg_temp.metric_count('dating.exclusion_key.mismatch');

  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_gone));
  v_got := coalesce(v_got, '') || pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_gone));
  IF v_got IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: prepare_account_deletion failed: %', v_got;
  END IF;
  DELETE FROM auth.users WHERE id = v_gone;

  -- 1. One enforcement record per live restriction, run twice; a timed
  --    one keeps its end.
  IF (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = v_hmac) IS DISTINCT FROM 2
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records
                     WHERE phone_hmac = v_hmac AND scope = 'dating' AND source_restriction_id = v_live
                       AND restriction_type = 'suspended' AND effect_until IS NULL
                       AND purge_after BETWEEN now() + interval '729 days' AND now() + interval '731 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the live restriction was not carried exactly once as a 2-year enforcement record';
  END IF;
  IF (SELECT effect_until FROM public.enforcement_records WHERE source_restriction_id = v_timed) IS DISTINCT FROM v_ends THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timed restriction was not carried with its end as effect_until';
  END IF;
  -- 2. Both block pairs survive, kept 2 years.
  IF (SELECT count(*) FROM public.dating_block_hmacs
       WHERE ((blocker_hmac = public.dating_phone_hmac_for_user(v_blocker) AND blocked_hmac = v_hmac)
           OR (blocker_hmac = v_hmac AND blocked_hmac = public.dating_phone_hmac_for_user(v_blocked)))
         AND purge_after BETWEEN now() + interval '729 days' AND now() + interval '731 days') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the block pairs did not survive the deletion with a 2-year purge';
  END IF;
  -- 3. The match survives, sealed, closed for the deletion, members anonymised.
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches
                  WHERE id = v_m AND state = 'closed' AND closed_reason = 'account_deleted'
                    AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days'
                    AND introduction_id IS NULL
                    AND num_nulls(user_low_id, user_high_id) = 1
                    AND v_match_with IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match did not survive as a sealed, anonymised record';
  END IF;
  IF coalesce((SELECT closed_reason = 'unmatched' AND evidence_until BETWEEN now() + interval '9 days' AND now() + interval '11 days'
                 FROM public.dating_matches WHERE id = v_m_old), false) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion rewrote an already closed match''s reason or evidence window';
  END IF;
  -- 4. Reports survive either side's deletion; the target keeps its HMAC.
  IF NOT EXISTS (SELECT 1 FROM public.dating_reports
                  WHERE reporter_user_id = v_reporter AND target_user_id IS NULL AND target_phone_hmac = v_hmac)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports
                     WHERE reporter_user_id IS NULL AND target_user_id = v_reported) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report did not survive a deletion (with target_phone_hmac)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_reports WHERE target_user_id IS NULL AND target_phone_hmac = v_prior) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion overwrote a report''s existing target_phone_hmac';
  END IF;
  -- 5. The deletion never stores the key's fingerprint (M-7); with none
  --    stored, the delete counts dating.exclusion_key.unseeded once; nothing
  --    was left for the delete's own pass to carry.
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion stored the exclusion key''s fingerprint';
  END IF;
  IF pg_temp.metric_count('dating.exclusion_key.unseeded') IS DISTINCT FROM v_unseeded + 1
     OR pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_mm THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion with no stored fingerprint was not counted once as unseeded';
  END IF;
  IF pg_temp.metric_count('dating.deletion.late_carry') IS DISTINCT FROM v_late THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the delete counted a late carry when prepare had carried everything';
  END IF;
  PERFORM private.seed_dating_exclusion_key_fingerprint(); -- re-seed, as the owner does after setting the key

  -- Delete -> re-register (same SIM) -> tamper public.users.phone.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_new, '1555870020', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_new, '1555870020', 'Back again', 'dating');
  UPDATE public.users SET phone = '+15558709920' WHERE id = v_new;
  IF public.dating_account_in_good_standing(v_new) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number lifted the restriction';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                  WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_blocker)
                    AND blocked_hmac = public.dating_phone_hmac_for_user(v_new)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number escaped the block';
  END IF;
  IF public.dating_former_partner_excluded(v_ex, v_new) IS NOT TRUE OR public.dating_former_partner_excluded(v_new, v_ex) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number escaped the former-partner exclusion';
  END IF;

  -- No key and a live restriction: the deletion is refused, nothing written.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_nokey, 'moderation_hold');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_nokey));
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM 'ERROR: deletion:enforcement_key_missing'
     OR EXISTS (SELECT 1 FROM public.enforcement_records AS e
                  JOIN public.dating_account_restrictions AS d ON d.id = e.source_restriction_id
                 WHERE d.user_id = v_nokey) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without the key went ahead with a live restriction: %', v_got;
  END IF;

  -- No key and NO live restriction: the deletion completes (blocks, a
  -- match), nothing is refused, the match is still sealed.
  v_m := pg_temp.match(v_nokey, v_reported);
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE user_id = v_nokey;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, starts_at, ends_at)
  VALUES (v_nokey, 'suspended', now() - interval '10 days', now() - interval '1 day'); -- expired, never lifted
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_nokey));
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM ''
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND closed_reason = 'account_deleted') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key and with no live restriction the deletion did not complete: %', v_got;
  END IF;

  -- A parked account (I-11, O3 default): nothing is written at parking; the
  -- purge carries the restriction under the REAL number, and its block
  -- pairs get their purge date; a fresh account on that number is closed.
  v_real := public.dating_phone_hmac_for_user(v_parked);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_parked, 'suspended');
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_parked, v_blocker, public.dating_pair_key(v_parked, v_blocker));
  UPDATE public.users SET parked_phone_hmac = v_real WHERE id = v_parked;
  UPDATE auth.users SET phone = '999123456789229' WHERE id = v_parked;
  UPDATE public.users SET phone_released_at = now() WHERE id = v_parked;
  IF EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_real) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parking wrote an enforcement record (built default O3: no)';
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_parked));
  IF v_got IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion of a parked account failed: %', v_got;
  END IF;
  DELETE FROM auth.users WHERE id = v_parked;
  IF (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = v_real) IS DISTINCT FROM 1
     OR EXISTS (SELECT 1 FROM public.enforcement_records
                 WHERE phone_hmac = public.dating_phone_hmac('+999123456789229'))
     OR NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                     WHERE blocker_hmac = v_real AND purge_after IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge of a parked account did not carry it under the real number';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_fresh, '1555870029', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_fresh, '1555870029', 'Fresh', 'dating');
  IF public.dating_account_in_good_standing(v_fresh) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh account on a purged, restricted number is in good standing';
  END IF;
END $$;

-- C2. (W1a; PF-F6, batch-3 fix round 1: I-1, I-2, I-3, M-2, M-3, M-7)
--     A restriction with no stamped HMAC carries nothing; the deletion
--     completes and counts dating.deletion.uncarried once, at the delete.
--     Under a rotated key a record still carries under its stamp and the
--     delete counts dating.exclusion_key.mismatch for a Dating footprint
--     only. A restricted account that moves to someone else's number
--     before deleting restricts and excludes nobody there (I-1). What is
--     written between prepare and the delete still carries (I-2). A failed
--     required step refuses the deletion; the delete's own pass never
--     fails it, and counts (M-3). Restrictions placed while the key was
--     missing are stamped once it is set.
DO $$
DECLARE
  v_unhashed constant uuid := pg_temp.person('42');
  v_bare constant uuid := pg_temp.person('43');
  v_rotated constant uuid := pg_temp.person('44');
  v_plain constant uuid := pg_temp.person('45');
  v_blocked_only constant uuid := pg_temp.person('46');
  v_reported_only constant uuid := pg_temp.person('47');
  v_framer constant uuid := pg_temp.person('48');
  v_ex constant uuid := pg_temp.person('57');
  v_window constant uuid := pg_temp.person('58');
  v_other constant uuid := pg_temp.person('59');
  v_b_fail constant uuid := pg_temp.person('64');
  v_b_blocker constant uuid := pg_temp.person('65');
  v_r_fail constant uuid := pg_temp.person('66');
  v_r_reporter constant uuid := pg_temp.person('67');
  v_m_fail constant uuid := pg_temp.person('68');
  v_m_with constant uuid := pg_temp.person('69');
  v_late_key constant uuid := pg_temp.person('70');
  v_victim constant uuid := pg_temp.id('49');
  v_back constant uuid := pg_temp.id('56');
  v_fp constant text := public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1');
  v_role text;
  v_sig text;
  v_r uuid;
  v_rep uuid;
  v_m uuid;
  v_rel uuid;
  v_stamp text;
  v_h text;
  v_before bigint;
  v_got text;
BEGIN
  -- The stamps and the carry-over's functions are no API role's.
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'private.dating_restriction_hmacs', 'SELECT')
       OR has_table_privilege(v_role, 'private.dating_restriction_hmacs', 'INSERT')
       OR has_table_privilege(v_role, 'private.dating_restriction_hmacs', 'UPDATE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % can read or write the restriction stamps', v_role;
    END IF;
    FOREACH v_sig IN ARRAY ARRAY['private.dating_deletion_carry(uuid,boolean)', 'private.dating_stamp_restriction_hmacs()',
                                 'private.dating_stamp_restriction_on_insert()', 'private.dating_carry_on_auth_user_delete()'] LOOP
      IF has_function_privilege(v_role, v_sig, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can execute %', v_role, v_sig;
      END IF;
    END LOOP;
  END LOOP;
  IF v_fp IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: the contract key is not set';
  END IF;

  -- No stamp (parked before the key existed), a live restriction: prepare
  -- completes and counts nothing (twice); the delete counts it once.
  UPDATE auth.users SET phone = '999123456789242' WHERE id = v_unhashed;
  UPDATE public.users SET phone_released_at = now() WHERE id = v_unhashed;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_unhashed, 'suspended')
  RETURNING id INTO v_r;
  IF public.dating_phone_hmac_for_user(v_unhashed) IS NOT NULL
     OR EXISTS (SELECT 1 FROM private.dating_restriction_hmacs WHERE restriction_id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: the unhashed account has an HMAC or a stamp';
  END IF;
  v_before := pg_temp.metric_count('dating.deletion.uncarried');
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_unhashed));
  v_got := coalesce(v_got, '-') || pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_unhashed));
  IF v_got IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no stamped HMAC the deletion was refused: %', v_got;
  END IF;
  IF pg_temp.metric_count('dating.deletion.uncarried') IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating.deletion.uncarried counted a prepare, not the deletion';
  END IF;
  DELETE FROM auth.users WHERE id = v_unhashed;
  IF EXISTS (SELECT 1 FROM public.enforcement_records WHERE source_restriction_id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction with no stamped HMAC wrote an enforcement record';
  END IF;
  IF pg_temp.metric_count('dating.deletion.uncarried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion that could not carry a live restriction was not counted exactly once (dating.deletion.uncarried)';
  END IF;
  -- The same with nothing live to carry (one lifted, one expired, both
  -- unstamped): not counted.
  UPDATE auth.users SET phone = '999123456789243' WHERE id = v_bare;
  UPDATE public.users SET phone_released_at = now() WHERE id = v_bare;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, lifted_at)
  VALUES (v_bare, 'under_review', now() - interval '1 day');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, starts_at, ends_at)
  VALUES (v_bare, 'suspended', now() - interval '9 days', now() - interval '2 days');
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_bare));
  DELETE FROM auth.users WHERE id = v_bare;
  IF v_got IS DISTINCT FROM '' OR pg_temp.metric_count('dating.deletion.uncarried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion with nothing to carry was refused or counted as uncarried: %', v_got;
  END IF;

  -- A rotated key: the record keeps its stamp; the delete counts a mismatch
  -- for a Dating footprint (a restriction, a block, a report) only.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_rotated, 'moderation_hold')
  RETURNING id INTO v_r;
  v_stamp := (SELECT phone_hmac FROM private.dating_restriction_hmacs WHERE restriction_id = v_r);
  IF v_stamp IS DISTINCT FROM public.dating_phone_hmac_for_user(v_rotated) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction was not stamped with the HMAC of the number it was placed under';
  END IF;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_other, v_blocked_only, public.dating_pair_key(v_other, v_blocked_only));
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (v_other, v_reported_only, 'spam');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-rotated-key', true);
  v_before := pg_temp.metric_count('dating.exclusion_key.mismatch');
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_rotated));
  DELETE FROM auth.users WHERE id = v_rotated;
  IF v_got IS DISTINCT FROM '' THEN
    PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key the deletion was refused: %', v_got;
  END IF;
  IF pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_before + 1 THEN
    PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion under a rotated exclusion key was not counted';
  END IF;
  DELETE FROM auth.users WHERE id = v_plain;
  IF pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_before + 1 THEN
    PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion with no Dating footprint counted a key mismatch';
  END IF;
  DELETE FROM auth.users WHERE id = v_blocked_only;
  IF pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_before + 2 THEN
    PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion with only a block under a rotated key was not counted';
  END IF;
  DELETE FROM auth.users WHERE id = v_reported_only;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_before + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion with only a report under a rotated key was not counted';
  END IF;
  IF (SELECT phone_hmac || '/' || restriction_type FROM public.enforcement_records WHERE source_restriction_id = v_r)
     IS DISTINCT FROM v_stamp || '/moderation_hold' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key the record did not keep its stamp and type';
  END IF;
  IF (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') IS DISTINCT FROM v_fp THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion under a rotated key changed the stored fingerprint';
  END IF;

  -- I-1: a restricted account moves to someone else's number (one OTP on
  -- that SIM), then deletes. Nothing lands on that number; the record and
  -- the ex's exclusion stay on the number the restriction and the
  -- relationship's end were recorded under.
  v_h := public.dating_phone_hmac_for_user(v_framer);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_framer, 'suspended')
  RETURNING id INTO v_r;
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_framer, v_ex, 'ended', now() - interval '30 days') RETURNING id INTO v_rel;
  PERFORM public.record_dating_former_partner_exclusion(v_rel, true);
  UPDATE auth.users SET phone = '15558709948' WHERE id = v_framer;
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_framer));
  DELETE FROM auth.users WHERE id = v_framer;
  IF v_got IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the deletion after a number change failed: %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = public.dating_phone_hmac('+15558709948')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction moved onto the number the account changed to before deleting';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records WHERE source_restriction_id = v_r AND phone_hmac = v_h) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restriction was not carried under the HMAC stamped when it was placed';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_victim, '15558709948', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_victim, '15558709948', 'Victim', 'dating');
  IF public.dating_account_in_good_standing(v_victim) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the number a restricted account moved to before deleting is restricted';
  END IF;
  IF public.dating_former_partner_excluded(v_ex, v_victim) IS NOT FALSE
     OR public.dating_former_partner_excluded(v_victim, v_ex) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the number an account moved to before deleting is excluded from its ex';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_back, '1555870048', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_back, '1555870048', 'Back', 'dating');
  IF public.dating_account_in_good_standing(v_back) IS NOT FALSE
     OR public.dating_former_partner_excluded(v_ex, v_back) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the number the restriction and the relationship were recorded under escaped them';
  END IF;

  -- I-2: written after prepare, before the delete: still carried, counted.
  v_h := public.dating_phone_hmac_for_user(v_window);
  v_before := pg_temp.metric_count('dating.deletion.late_carry');
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_window));
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_window, 'moderation_hold')
  RETURNING id INTO v_r;
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (v_other, v_window, 'harassment')
  RETURNING id INTO v_rep;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_other, v_window, public.dating_pair_key(v_other, v_window));
  DELETE FROM auth.users WHERE id = v_window;
  IF v_got IS DISTINCT FROM ''
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records WHERE source_restriction_id = v_r AND phone_hmac = v_h) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction placed between prepare and the delete was not carried: %', v_got;
  END IF;
  IF (SELECT target_phone_hmac FROM public.dating_reports WHERE id = v_rep) IS DISTINCT FROM v_h THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report filed between prepare and the delete lost its HMAC';
  END IF;
  IF coalesce((SELECT purge_after BETWEEN now() + interval '729 days' AND now() + interval '731 days'
                 FROM public.dating_block_hmacs
                WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_other) AND blocked_hmac = v_h), false) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a block made between prepare and the delete has no 2-year purge';
  END IF;
  IF pg_temp.metric_count('dating.deletion.late_carry') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carry at the delete itself was not counted (dating.deletion.late_carry)';
  END IF;

  -- W1 final fix (M-4, PF-F6; replaces batch 3's M-3 refusal): a failed
  -- carry step (block pairs, reports) is counted at prepare and never
  -- refuses the deletion (only the missing key does, C2 above); at the
  -- delete itself it is counted, never raised; a failed match step warns
  -- and counts (the cascade trigger seals them).
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_b_blocker, v_b_fail, public.dating_pair_key(v_b_blocker, v_b_fail));
  ALTER TABLE public.dating_block_hmacs ADD CONSTRAINT spec2_w1_c2_fail CHECK (false) NOT VALID;
  v_before := pg_temp.metric_count('dating.deletion.prepare_carry_failed');
  BEGIN
    PERFORM public.prepare_account_deletion(v_b_fail);
    v_got := 'completed';
  EXCEPTION WHEN OTHERS THEN
    v_got := 'refused: ' || SQLERRM;
  END;
  IF v_got IS DISTINCT FROM 'completed'
     OR pg_temp.metric_count('dating.deletion.prepare_carry_failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed block-pair step refused the deletion or was not counted (%)', v_got;
  END IF;
  v_before := pg_temp.metric_count('dating.deletion.late_carry_failed');
  BEGIN
    DELETE FROM auth.users WHERE id = v_b_fail;
    v_got := 'deleted';
  EXCEPTION WHEN OTHERS THEN
    v_got := SQLERRM;
  END;
  ALTER TABLE public.dating_block_hmacs DROP CONSTRAINT spec2_w1_c2_fail;
  IF v_got IS DISTINCT FROM 'deleted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed carry at the delete blocked the deletion: %', v_got;
  END IF;
  IF pg_temp.metric_count('dating.deletion.late_carry_failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed carry at the delete was not counted';
  END IF;

  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (v_r_reporter, v_r_fail, 'spam');
  ALTER TABLE public.dating_reports ADD CONSTRAINT spec2_w1_c2_fail CHECK (false) NOT VALID;
  v_before := pg_temp.metric_count('dating.deletion.prepare_carry_failed');
  BEGIN
    PERFORM public.prepare_account_deletion(v_r_fail);
    v_got := 'completed';
  EXCEPTION WHEN OTHERS THEN
    v_got := 'refused: ' || SQLERRM;
  END;
  ALTER TABLE public.dating_reports DROP CONSTRAINT spec2_w1_c2_fail;
  IF v_got IS DISTINCT FROM 'completed'
     OR pg_temp.metric_count('dating.deletion.prepare_carry_failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed report step refused the deletion or was not counted (%)', v_got;
  END IF;

  v_m := pg_temp.match(v_m_fail, v_m_with);
  ALTER TABLE public.dating_matches ADD CONSTRAINT spec2_w1_c2_fail CHECK (false) NOT VALID;
  v_before := pg_temp.metric_count('dating.deletion.step_failed.matches');
  BEGIN
    PERFORM public.prepare_account_deletion(v_m_fail);
    v_got := 'completed';
  EXCEPTION WHEN OTHERS THEN
    v_got := SQLERRM;
  END;
  ALTER TABLE public.dating_matches DROP CONSTRAINT spec2_w1_c2_fail;
  IF v_got IS DISTINCT FROM 'completed'
     OR pg_temp.metric_count('dating.deletion.step_failed.matches') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed match step refused the deletion or was not counted: %', v_got;
  END IF;

  -- A restriction placed while the key was missing has no stamp; once the
  -- key is set the stamping run stamps it (idempotent; -1 without the key).
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_late_key, 'under_review')
  RETURNING id INTO v_r;
  v_got := private.dating_stamp_restriction_hmacs()::text;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM '-1' OR EXISTS (SELECT 1 FROM private.dating_restriction_hmacs WHERE restriction_id = v_r) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction was stamped without the key: %', v_got;
  END IF;
  v_got := private.dating_stamp_restriction_hmacs()::text;
  IF (SELECT phone_hmac FROM private.dating_restriction_hmacs WHERE restriction_id = v_r)
     IS DISTINCT FROM public.dating_phone_hmac_for_user(v_late_key) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction placed while the key was missing was not stamped once it was set';
  END IF;
  v_stamp := public.dating_phone_hmac_for_user(v_late_key);
  UPDATE auth.users SET phone = '15558709970' WHERE id = v_late_key;
  IF private.dating_stamp_restriction_hmacs() IS DISTINCT FROM 0
     OR (SELECT phone_hmac FROM private.dating_restriction_hmacs WHERE restriction_id = v_r) IS DISTINCT FROM v_stamp THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stamping run is not idempotent or re-stamped a restriction from a later number';
  END IF;
  -- A delete while the key is missing counts no key mismatch.
  v_before := pg_temp.metric_count('dating.exclusion_key.mismatch');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  DELETE FROM auth.users WHERE id = v_late_key;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF pg_temp.metric_count('dating.exclusion_key.mismatch') IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delete without the key counted a key mismatch';
  END IF;
END $$;
-- =====================================================================
-- D1. (W1c) The field key and its two functions (§4.2): pgp_sym_encrypt
--    under dating_field_key, a fresh ciphertext each time, no plaintext,
--    nothing without the key, and no API role (the service role included)
--    reads the sensitive table or calls the functions.
--    Batch-6 ruling: authenticated encryption (the OpenPGP MDC packet, a
--    random session key and salt per value), each value tagged with its key
--    version (byte 0 = 1, then the OpenPGP message), compression off, and no
--    error or notice ever carries a decrypted value.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('39');
  v_key constant text := 'spec2-w1c-identity-field-key-0123456789abcdef';
  v_one bytea;
  v_two bytea;
  v_pgp bytea;
  v_t text;
  v_msg text;
  v_detail text;
  v_ctx text;
  v_at constant timestamptz := clock_timestamp() + interval '1 hour';
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  IF NOT private.dating_field_key_present() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 44-character dating_field_key reads as missing';
  END IF;
  IF private.dating_field_key_usable() IS NOT TRUE THEN -- Spec 2 W1d (batch-10 fix round 1, M-11)
    RAISE EXCEPTION 'CONTRACT VIOLATED: a development GUC field key with no fingerprint is not usable';
  END IF;
  v_one := private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}');
  v_two := private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}');
  IF v_one IS NULL OR v_one = v_two
     OR position('woman' IN encode(v_one, 'escape')) IS DISTINCT FROM 0
     OR position('identity' IN encode(v_one, 'escape')) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field ciphertext is deterministic or holds a plaintext marker';
  END IF;
  -- The key-version tag, then the OpenPGP message.
  v_pgp := substring(v_one FROM 2);
  IF get_byte(v_one, 0) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field ciphertext is not tagged with key version 1 (byte 0 = %)', get_byte(v_one, 0);
  END IF;
  IF private.dating_field_decrypt(v_one) IS DISTINCT FROM '{"identity": "woman", "pools": ["woman"]}'::jsonb
     OR extensions.pgp_sym_decrypt(v_pgp, 'spec2-w1c-identity-field-key-0123456789abcdef')::jsonb ->> 'identity'
          IS DISTINCT FROM 'woman'
     OR private.dating_field_encrypt(NULL) IS NOT NULL OR private.dating_field_decrypt(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field functions are not pgp_sym under dating_field_key';
  END IF;
  -- Authenticated: the symmetric-key session packet (tag 3) is followed by
  -- the integrity-protected data packet (tag 18, 0xD2), never tag 9.
  IF get_byte(v_pgp, 0) IS DISTINCT FROM 195 OR get_byte(v_pgp, 2 + get_byte(v_pgp, 1)) IS DISTINCT FROM 210 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field ciphertext is not integrity-protected (no MDC packet)';
  END IF;
  -- Compression off: two answers of one length encrypt to one length,
  -- however compressible either is.
  IF octet_length(private.dating_field_encrypt(jsonb_build_object('t', repeat('a', 200))))
     IS DISTINCT FROM octet_length(private.dating_field_encrypt(jsonb_build_object('t', substr(repeat(md5('w1c'), 7), 1, 200)))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ciphertext length depends on the content (compression is on)';
  END IF;
  -- A tampered value, a value under another key, an untagged or unknown
  -- version and an unprotected packet are each refused; the refusal names
  -- no plaintext (its message, detail and context).
  BEGIN
    PERFORM private.dating_field_decrypt(set_byte(v_one, octet_length(v_one) - 1, get_byte(v_one, octet_length(v_one) - 1) # 1));
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tampered field ciphertext was not refused (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt('\x01'::bytea || extensions.pgp_sym_encrypt('{"x": 1}', 'spec2-w1c-identity-other-key-0123456789abcdef',
                                                                                    'cipher-algo=aes256, compress-algo=0, sess-key=1'));
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a value under another key was not refused (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt('\x01'::bytea || extensions.pgp_sym_encrypt('{"x": 1}', v_key,
                                                                                    'cipher-algo=aes256, compress-algo=0, disable-mdc=1'));
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a value without integrity protection was decrypted (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt(set_byte(v_one, 0, 2));
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a value tagged with an unknown key version was decrypted (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt(v_pgp);
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untagged value was decrypted (%)', v_msg;
  END IF;
  -- Fix round 1 (M-3): an old-format packet header (which pgcrypto itself
  -- accepts) is refused.
  BEGIN
    PERFORM private.dating_field_decrypt('\x01'::bytea || set_byte(v_pgp, 0, 140));
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an old-format packet header was decrypted (%)', v_msg;
  END IF;
  v_two := '\x01'::bytea || extensions.pgp_sym_encrypt('w1csecretword is not json', v_key, 'cipher-algo=aes256, compress-algo=0, sess-key=1');
  BEGIN
    PERFORM private.dating_field_decrypt(v_two);
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL, v_ctx = PG_EXCEPTION_CONTEXT;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_decrypt_failed'
     OR position('w1csecretword' IN concat(v_msg, v_detail, v_ctx)) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed decryption raised % (detail %), or named the plaintext', v_msg, v_detail;
  END IF;
  -- Nothing in the three functions logs or formats a value.
  IF EXISTS (SELECT 1 FROM pg_proc AS p
              WHERE p.oid IN ('private.dating_field_encrypt(jsonb)'::regprocedure, 'private.dating_field_decrypt(bytea)'::regprocedure,
                              'private.dating_field_key_present()'::regprocedure)
                AND (p.prosrc ~* 'RAISE\s+(NOTICE|LOG|INFO|DEBUG|WARNING)' OR p.prosrc ~ 'RAISE[^;]*%' OR p.prosrc ~* 'SQLERRM')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a field-key function logs or formats a value';
  END IF;
  -- Fix round 1 (M-7): the three are SECURITY INVOKER, so a stray grant
  -- fails closed at the key read instead of opening a decryption oracle.
  IF EXISTS (SELECT 1 FROM pg_proc AS p
              WHERE p.oid IN ('private.dating_field_encrypt(jsonb)'::regprocedure, 'private.dating_field_decrypt(bytea)'::regprocedure,
                              'private.dating_field_key_present()'::regprocedure)
                AND p.prosecdef) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a field-key function is SECURITY DEFINER';
  END IF;
  -- Fix round 1 (M-4): in production the key is read from Vault only; a GUC
  -- key (plaintext in pg_db_role_setting) is no key there.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.dating_field_key_present() IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production a GUC dating_field_key reads as present';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['SELECT private.dating_field_encrypt(''{"x": 1}'')', format('SELECT private.dating_field_decrypt(%L::bytea)', v_one)] LOOP
    BEGIN
      EXECUTE v_t;
      v_msg := NULL;
    EXCEPTION WHEN raise_exception THEN
      v_msg := SQLERRM;
    END;
    IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: in production a field function used the GUC key (%)', v_msg;
    END IF;
  END LOOP;
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', v_key);
  -- Spec 2 W1d (batch-6 M-5): in production the key also needs its seeded
  -- fingerprint before anything is encrypted under it (E2g has the rest).
  BEGIN
    PERFORM private.dating_field_encrypt('{"p": 1}');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production an unseeded dating_field_key encrypted (%)', v_msg;
  END IF;
  IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production the Vault dating_field_key could not be seeded';
  END IF;
  IF private.dating_field_key_present() IS NOT TRUE
     OR private.dating_field_decrypt(v_one) ->> 'identity' IS DISTINCT FROM 'woman'
     OR private.dating_field_decrypt(private.dating_field_encrypt('{"p": 1}')) IS DISTINCT FROM '{"p": 1}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production the Vault dating_field_key is not used';
  END IF;
  DELETE FROM vault.secrets WHERE name = 'dating_field_key';
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_field_key'; -- Spec 2 W1d
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- A short key is no key.
  PERFORM set_config('app.settings.dating_field_key', 'too-short', true);
  IF private.dating_field_key_present() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 9-character key reads as present';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['SELECT private.dating_field_encrypt(''{"x": 1}'')', format('SELECT private.dating_field_decrypt(%L::bytea)', v_one)] LOOP
    BEGIN
      EXECUTE v_t;
      v_msg := NULL;
    EXCEPTION WHEN raise_exception THEN
      v_msg := SQLERRM;
    END;
    IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a field function ran under a 9-character key (%)', v_msg;
    END IF;
  END LOOP;
  -- Fix round 1 (M-1): 31 characters is no key; 32 is.
  PERFORM set_config('app.settings.dating_field_key', repeat('k', 31), true);
  IF private.dating_field_key_present() IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 31-character key reads as present';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['SELECT private.dating_field_encrypt(''{"x": 1}'')', format('SELECT private.dating_field_decrypt(%L::bytea)', v_one)] LOOP
    BEGIN
      EXECUTE v_t;
      v_msg := NULL;
    EXCEPTION WHEN raise_exception THEN
      v_msg := SQLERRM;
    END;
    IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a field function ran under a 31-character key (%)', v_msg;
    END IF;
  END LOOP;
  PERFORM set_config('app.settings.dating_field_key', repeat('k', 32), true);
  IF private.dating_field_key_present() IS NOT TRUE
     OR private.dating_field_decrypt(private.dating_field_encrypt('{"k": 32}')) IS DISTINCT FROM '{"k": 32}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 32-character key does not work';
  END IF;
  PERFORM set_config('app.settings.dating_field_key', '', true);
  IF private.dating_field_key_present() IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no key, dating_field_key_present() is % (expected false)', private.dating_field_key_present();
  END IF;
  BEGIN
    PERFORM private.dating_field_encrypt('{"x": 1}');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_field_encrypt ran without the key (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt(v_one);
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_field_decrypt ran without the key (%)', v_msg;
  END IF;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  -- Consent: the latest event decides (a withdrawal ends it; a new grant restores it).
  IF private.dating_consent_granted(v_u, 'special_category_profile') IS NOT FALSE
     OR private.dating_consent_granted(NULL, 'special_category_profile') IS NOT FALSE
     OR private.dating_consent_granted(v_u, NULL) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_consent_granted is not false with no event, a NULL user or a NULL purpose';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c1', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  IF NOT private.dating_consent_granted(v_u, 'special_category_profile')
     OR private.dating_consent_granted(v_u, 'special_category_faith') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_consent_granted does not read the granted purpose';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c2', 'special_category_profile', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF private.dating_consent_granted(v_u, 'special_category_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a withdrawn consent still counts';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c3', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  IF NOT private.dating_consent_granted(v_u, 'special_category_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a consent granted again after a withdrawal does not count';
  END IF;
  -- A grant and a withdrawal at the same instant: the withdrawal wins (fail closed).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c4', 'special_category_faith', 'withdrawn', 'dating-2.0', v_at),
         (v_u, 'w1c-c5', 'special_category_faith', 'granted', 'dating-2.0', v_at);
  IF private.dating_consent_granted(v_u, 'special_category_faith') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a grant and a withdrawal at one instant count as granted';
  END IF;
  -- Fix round 1 (M-2): the same tie, the grant stored first.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c6', 'biometric_verification', 'granted', 'dating-2.0', v_at);
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c7', 'biometric_verification', 'withdrawn', 'dating-2.0', v_at);
  IF private.dating_consent_granted(v_u, 'biometric_verification') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a grant stored before a withdrawal at one instant counts as granted';
  END IF;
  -- Fix round 1 (I-1): column grants count too (has_table_privilege ignores them).
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.dating_profile_sensitive'::regclass)
     OR has_any_column_privilege('service_role', 'public.dating_profile_sensitive', 'SELECT')
     OR has_any_column_privilege('authenticated', 'public.dating_profile_sensitive', 'SELECT')
     OR has_any_column_privilege('anon', 'public.dating_profile_sensitive', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can read dating_profile_sensitive';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['service_role', 'authenticated', 'anon'] LOOP
    IF has_table_privilege(v_t, 'public.dating_profile_sensitive', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege(v_t, 'public.dating_profile_sensitive', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % holds a privilege on dating_profile_sensitive', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['authenticated', 'anon'] LOOP
    IF has_any_column_privilege(v_t, 'public.dating_prompts', 'SELECT, INSERT, UPDATE, REFERENCES')
       OR has_any_column_privilege(v_t, 'public.dating_settings', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % holds a column privilege on dating_prompts or dating_settings', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['private.dating_field_encrypt(jsonb)', 'private.dating_field_decrypt(bytea)',
                             'private.dating_field_key_present()', 'private.dating_consent_granted(uuid,text)',
                             'public.dating_require_trusted_device()'] LOOP
    IF has_function_privilege('service_role', v_t, 'EXECUTE') OR has_function_privilege('authenticated', v_t, 'EXECUTE')
       OR has_function_privilege('anon', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is callable by an API role', v_t;
    END IF;
  END LOOP;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1c trusted-device pass-through does not allow';
  END IF;
END $$;

-- =====================================================================
-- D1b. (W1c) The §4.3 columns: the v1 columns stay (P-22), the new checks
--    refuse what they should, and no NULL slips a check (batch-2 sweep).
-- =====================================================================
CREATE FUNCTION pg_temp.refused(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN false;
EXCEPTION WHEN check_violation OR not_null_violation OR unique_violation THEN
  RETURN true;
END $$;

DO $$
DECLARE
  v_u constant uuid := pg_temp.person('38');
  v_t text;
  v_bad text := '';
BEGIN
  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'dating_profiles'
         AND column_name IN ('city_region_code', 'relationship_intention', 'bio', 'gender_identity') AND is_nullable = 'YES')
     IS DISTINCT FROM 4::bigint
     OR (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'dating_preferences'
            AND column_name IN ('gender_preferences', 'region_preferences', 'intention_preferences')) IS DISTINCT FROM 3::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 column was dropped or is still NOT NULL (P-22)';
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code, side_code, intention, marriage_timeline)
  VALUES (v_u, repeat('n', 30), 'GH', 'AA', 'east', 'marriage', 'few_years');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (v_u, 18, 99);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (v_u, 1, 'perfect_sunday', repeat('a', 10));
  INSERT INTO public.dating_settings (user_id, drop_time) VALUES (v_u, '22:00');
  INSERT INTO public.dating_profile_sensitive (user_id) VALUES (v_u);
  FOREACH v_t IN ARRAY ARRAY[
    format('UPDATE public.dating_profiles SET display_name = %L WHERE user_id = %L', repeat('n', 31), v_u),
    format('UPDATE public.dating_profiles SET display_name = %L WHERE user_id = %L', '  ', v_u),
    format('UPDATE public.dating_profiles SET country_code = %L WHERE user_id = %L', 'gh', v_u),
    format('UPDATE public.dating_profiles SET intention = %L, marriage_timeline = NULL WHERE user_id = %L', 'long_term', v_u),
    format('UPDATE public.dating_profiles SET intention = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET intention = %L WHERE user_id = %L', 'committed', v_u),
    format('UPDATE public.dating_profiles SET marriage_timeline = %L WHERE user_id = %L', 'someday', v_u),
    format('UPDATE public.dating_profiles SET region_code = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET country_code = NULL, side_code = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET children_want = %L WHERE user_id = %L', 'maybe', v_u),
    format('UPDATE public.dating_profiles SET family_involvement = %L WHERE user_id = %L', 'never', v_u),
    format('UPDATE public.dating_preferences SET min_age = 17 WHERE user_id = %L', v_u),
    format('UPDATE public.dating_preferences SET max_age = 100 WHERE user_id = %L', v_u),
    format('UPDATE public.dating_preferences SET region_scope = %L WHERE user_id = %L', 'world', v_u),
    format('UPDATE public.dating_preferences SET intention_open = ARRAY[%L] WHERE user_id = %L', 'fling', v_u),
    format('UPDATE public.dating_preferences SET intention_open = ARRAY[%L, NULL] WHERE user_id = %L', 'marriage', v_u),
    format('UPDATE public.dating_preferences SET intention_open = %L WHERE user_id = %L', '{}', v_u),
    format('UPDATE public.dating_preferences SET open_abroad = %L WHERE user_id = %L', '{gh}', v_u),
    format('UPDATE public.dating_preferences SET open_abroad = %L WHERE user_id = %L', '{GB,NULL}', v_u),
    format('UPDATE public.dating_preferences SET open_abroad = %L WHERE user_id = %L', '{G}', v_u),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'friends_say', repeat(' ', 10)),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'friends_say', '  ' || repeat('a', 9) || '  '),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 4, %L, %L)', v_u, 'friends_say', repeat('a', 10)),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'friends_say', repeat('a', 9)),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'friends_say', repeat('a', 201)),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'favourite_food', repeat('a', 10)),
    format('INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (%L, 2, %L, %L)', v_u, 'perfect_sunday', repeat('a', 10)),
    format('UPDATE public.dating_prompts SET moderation_state = %L WHERE user_id = %L', 'pending', v_u),
    format('UPDATE public.dating_settings SET drop_time = %L WHERE user_id = %L', '06:30', v_u),
    format('UPDATE public.dating_settings SET drop_time = %L WHERE user_id = %L', '22:30', v_u),
    format('UPDATE public.dating_settings SET drop_time = %L WHERE user_id = %L', '19:15', v_u),
    format('UPDATE public.dating_settings SET drop_time = %L WHERE user_id = %L', '19:00:30', v_u),
    format('UPDATE public.dating_profile_sensitive SET key_version = 0 WHERE user_id = %L', v_u)] LOOP
    IF NOT pg_temp.refused(v_t) THEN
      v_bad := v_bad || E'\n  ' || v_t;
    END IF;
  END LOOP;
  IF v_bad IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a §4.3 check let these through:%', v_bad;
  END IF;
  IF (SELECT region_scope || open_abroad::text || want_must_match::text || exclude_parents::text
        FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM 'region{}falsefalse'
     OR (SELECT drop_time::text || data_saver::text || digest_push::text || chat_push::text || show_when_away::text
           FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '22:00:00falsefalsetruefalse'
     OR (SELECT timeline_visible::text || faith_visible::text || marital_visible::text || photos_after_mutual::text
           FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'truefalsefalsefalse'
     OR (SELECT key_version FROM public.dating_profile_sensitive WHERE user_id = v_u) IS DISTINCT FROM 1::smallint
     OR (SELECT moderation_state FROM public.dating_prompts WHERE user_id = v_u) IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a §4.3 default is wrong';
  END IF;
  -- Fix round 1 (M-9): what the tighter checks still accept.
  UPDATE public.dating_preferences SET open_abroad = '{GB,NG}', intention_open = '{marriage}' WHERE user_id = v_u;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES (v_u, 2, 'friends_say', ' ' || repeat('a', 10) || ' ');
END $$;

-- =====================================================================
-- D1c. (W1c, fix round 1, I-2) A v1 name of 31-50 characters keeps working:
--    the 1-30 rule applies to a new or changed name only, so the
--    restriction, relationship-pause and kill-switch writes still succeed
--    on an older profile; v1's 50-character ceiling still holds.
-- =====================================================================
DO $$
DECLARE
  v_restricted constant uuid := pg_temp.person('40');
  v_coupled constant uuid := pg_temp.person('50');
  v_switched constant uuid := pg_temp.person('51');
  v_new constant uuid := pg_temp.person('52');
BEGIN
  -- Rows written before W1c (v1 allowed 1-50).
  ALTER TABLE public.dating_profiles DISABLE TRIGGER dating_profiles_display_name_guard;
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state) VALUES
    (v_restricted, repeat('L', 40), 'active'), (v_coupled, repeat('L', 40), 'active'), (v_switched, repeat('L', 40), 'active');
  IF NOT pg_temp.refused(format('INSERT INTO public.dating_profiles (user_id, display_name) VALUES (%L, %L)', v_new, repeat('L', 51))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: v1''s 50-character display-name ceiling is gone';
  END IF;
  ALTER TABLE public.dating_profiles ENABLE TRIGGER dating_profiles_display_name_guard;
  -- The three writes that pause an older profile.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_restricted, 'suspended');
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_coupled, NULL, 'pending', 'W1CNAME1', now() + interval '1 day');
  UPDATE public.dating_profiles SET profile_state = 'paused', updated_at = now() WHERE user_id = v_switched;
  UPDATE public.dating_profiles SET display_name = display_name WHERE user_id = v_switched;
  IF (SELECT count(*) FROM public.dating_profiles
       WHERE user_id IN (v_restricted, v_coupled, v_switched) AND profile_state = 'paused'
         AND char_length(display_name) = 40) IS DISTINCT FROM 3::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older 40-character name blocked a pause, or was rewritten';
  END IF;
  -- A new or changed name must be 1-30 (trimmed).
  IF NOT pg_temp.refused(format('UPDATE public.dating_profiles SET display_name = %L WHERE user_id = %L', repeat('M', 40), v_switched))
     OR NOT pg_temp.refused(format('UPDATE public.dating_profiles SET display_name = %L WHERE user_id = %L', repeat('M', 31), v_switched))
     OR NOT pg_temp.refused(format('INSERT INTO public.dating_profiles (user_id, display_name) VALUES (%L, %L)', v_new, repeat('N', 31)))
     OR NOT pg_temp.refused(format('INSERT INTO public.dating_profiles (user_id, display_name) VALUES (%L, %L)', v_new, '   ')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new or changed display name over 30 characters (or blank) was stored';
  END IF;
  UPDATE public.dating_profiles SET display_name = repeat('M', 30) || ' ' WHERE user_id = v_switched;
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v_new, repeat('N', 30));
END $$;

-- =====================================================================
-- D2. (W1c) Through the writers and readers: what lands in
--    dating_profile_sensitive is ciphertext only (no plaintext marker, a
--    fresh ciphertext each write), and every special-category writer and
--    the own-profile reader fail closed (unavailable) without the key.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('71');
  v jsonb;
  v_first bytea;
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.as_service('SELECT public.publish_country_config(''GH'', ''{"dating_enabled": true}'')::text');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-consent-profile', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  PERFORM pg_temp.as_user(v_u);
  v := jsonb_build_array(public.save_dating_intention('w1c-identity-d2-0001', 'committed', NULL, true, true, 'widowed', false));
  v := v || jsonb_build_array(public.save_dating_location('w1c-identity-d3-0001', 'GH', 'AA', NULL, 'region'));
  v := v || jsonb_build_array(public.save_dating_identity('w1c-identity-d5-0001', 'woman', NULL, NULL, NULL, false));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e ->> 'ok' IS DISTINCT FROM 'true') THEN
    RAISE EXCEPTION 'fixture: the W1c writers failed: %', v;
  END IF;
  v_first := (SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u);
  IF v_first IS NULL
     OR position('woman' IN encode(v_first, 'escape')) IS DISTINCT FROM 0
     OR position('widowed' IN encode((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'escape')) IS DISTINCT FROM 0
     OR position('identity' IN encode(v_first, 'escape')) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_profile_sensitive holds a plaintext marker';
  END IF;
  PERFORM pg_temp.as_user(v_u);
  PERFORM public.save_dating_identity('w1c-identity-d5-0002', 'woman', NULL, NULL, NULL, false);
  PERFORM pg_temp.as_owner();
  IF (SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u) = v_first THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same answer encrypted to the same ciphertext twice';
  END IF;

  -- Without the key: every special-category writer and the own-profile reader say
  -- unavailable, and nothing changes.
  PERFORM set_config('app.settings.dating_field_key', '', true);
  PERFORM pg_temp.as_user(v_u);
  BEGIN
    v := jsonb_build_array(
      public.save_dating_intention('w1c-identity-d2-0009', 'committed', NULL, true, true, NULL, false),
      public.save_dating_identity('w1c-identity-d5-0009', 'woman', NULL, NULL, NULL, false),
      public.save_dating_who_to_meet('w1c-identity-d6-0009', ARRAY['man'], 25, 35),
      public.get_my_dating_profile());
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer or reader raised (%) instead of answering unavailable', SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb
     OR (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer or reader did not fail closed: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
END $$;
-- [p_user] in Dating: a profile row (any state), which adding a number
-- needs (batch-9 fix round 1, M-1).
CREATE FUNCTION pg_temp.in_dating(p_user uuid) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (p_user, 'Me') ON CONFLICT (user_id) DO NOTHING;
  RETURN p_user;
END $$;

-- =====================================================================
-- E1. (W1d) Never introduce me (§3.12, 10 S5): symmetric; silent (the
--    same "added" whatever the number); HMACs, never numbers; the listed
--    person sees nothing; adding changes nothing the adder can see (an
--    open introduction stays; the pair is excluded: batch-9 fix round 1,
--    I-1); at most 50.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.in_dating(pg_temp.person('60'));
  v_b constant uuid := pg_temp.person('61');
  v_c constant uuid := pg_temp.in_dating(pg_temp.person('62'));
  v_d constant uuid := pg_temp.in_dating(pg_temp.person('63'));
  v_i uuid;
  v jsonb;
  n int;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- Silent: an Attune member's number (B), a number nobody uses, B again
  -- typed with 00 and punctuation (the same number).
  PERFORM pg_temp.as_user(v_a);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-never-0001', '+1 555 870 061', 'Ex'),
    public.add_dating_never_introduce('w1d-never-0002', '+447700900999', NULL),
    public.add_dating_never_introduce('w1d-never-0003', '001 (555) 870-061', 'Again'));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": true, "message": "added"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a number did not answer "added" whatever the number: %', v;
  END IF;
  -- Symmetric: neither is introduced to the other.
  IF NOT public.dating_never_introduce_excludes(v_a, v_b) OR NOT public.dating_never_introduce_excludes(v_b, v_a)
     OR public.dating_never_introduce_excludes(v_b, v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: never-introduce is not symmetric (or matched the wrong person)';
  END IF;
  IF (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_a) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE phone_hmac ~ '555870061')
     OR (SELECT label || ':' || last_two FROM public.dating_never_introduce
          WHERE owner_user_id = v_a AND phone_hmac = public.dating_phone_hmac('+1555870061')) IS DISTINCT FROM 'Again:61' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the list does not hold one HMAC per number with its label and last two digits';
  END IF;
  -- The listed person sees nothing; the table is no client's.
  PERFORM pg_temp.as_user(v_b);
  v := public.list_dating_never_introduce();
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": true, "items": []}'::jsonb
     OR has_table_privilege('authenticated', 'public.dating_never_introduce', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the listed person can see the list: %', v;
  END IF;
  PERFORM pg_temp.as_user(v_a);
  v := public.list_dating_never_introduce();
  PERFORM pg_temp.as_owner();
  IF jsonb_array_length(v -> 'items') IS DISTINCT FROM 2 OR v::text ~ '555870061' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s list is wrong or shows a number: %', v;
  END IF;
  -- Malformed input (no country code; a long label).
  PERFORM pg_temp.as_user(v_a);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-never-0009', '0244 123 456', NULL),
                         public.add_dating_never_introduce('w1d-never-0008', '+233244123456', repeat('x', 21)));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "invalid", "field": "phone"}, {"ok": false, "reason": "invalid", "field": "label"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number without its country code or a long label was accepted: %', v;
  END IF;
  -- An open introduction with the person on that number: nothing the adder
  -- can see changes (ending it at once would confirm whose number it is,
  -- fix round 1, I-1); the pair is excluded, so it can never match.
  v_i := pg_temp.intro(v_c, v_d);
  PERFORM pg_temp.as_user(v_c);
  PERFORM public.add_dating_never_introduce('w1d-never-0010', '+1555870063', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_introductions WHERE id = v_i) IS DISTINCT FROM 'presented'
     OR public.dating_never_introduce_excludes(v_c, v_d) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a number changed an open introduction at once (or the pair is not excluded)';
  END IF;
  -- Remove: own rows only, the same answer for any id.
  v_i := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_a LIMIT 1);
  PERFORM pg_temp.as_user(v_b);
  v := public.remove_dating_never_introduce(v_i);
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_a) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else removed an entry from a list';
  END IF;
  -- At most 50 (re-adding a listed number still says added).
  PERFORM pg_temp.as_user(v_d);
  FOR n IN 1..50 LOOP
    PERFORM public.add_dating_never_introduce('w1d-limit-' || lpad(n::text, 4, '0'), '+4477009' || lpad(n::text, 5, '0'), NULL);
  END LOOP;
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-limit-0051', '+447700999999', NULL),
                         public.add_dating_never_introduce('w1d-limit-0052', '+447700900001', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "limit_reached"}, {"ok": true, "message": "added"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_d) IS DISTINCT FROM 50 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 50-entry limit is wrong: %', v;
  END IF;
END $$;
-- =====================================================================
-- E1b. (W1d, batch 9 rulings) Never introduce: no phone oracle (the same
--    answer and the same table and function work for a member's number
--    and a stranger's); only HMACs (no number in any row, label, claim or
--    counter; a label can't hold a number); strict E.164; the exclusion key
--    must be ready (else feature_unavailable, counted, nothing claimed);
--    adding is never gated on eligibility or the device (exposure-
--    reducing) while removing and listing keep the device check; adds are
--    rate-limited; the setup lock; the helper fails closed; a listed
--    number only stops introductions (Spec 1 O3).
--    Fix round 1: adding changes no introduction (I-1); a trunk 0 after the
--    calling code is dropped where the country dials one, so the HMAC is
--    the account phone's, and refused where it can't be judged (I-2); a
--    Dating profile is needed (M-1); any script's digits count in a label
--    (M-2); a key is bound to its number (M-3) and a replay is "added"
--    past the daily limit (M-4).
-- =====================================================================
CREATE FUNCTION pg_temp.holds_setup_lock(p_user uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted AND l.objsubid = 2
                    AND l.mode = 'ExclusiveLock'
                    AND l.classid::bigint = (hashtext('dating_setup')::bigint + 4294967296) % 4294967296
                    AND l.objid::bigint = (hashtext(p_user::text)::bigint + 4294967296) % 4294967296);
$$;

-- This transaction's table and function work so far (pg_stat_xact_*).
CREATE FUNCTION pg_temp.work() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'tables', (SELECT jsonb_object_agg(s.schemaname || '.' || s.relname,
                        jsonb_build_array(s.seq_scan, s.seq_tup_read, coalesce(s.idx_scan, 0), coalesce(s.idx_tup_fetch, 0),
                                          s.n_tup_ins, s.n_tup_upd, s.n_tup_del, s.n_tup_hot_upd))
                 FROM pg_stat_xact_user_tables AS s),
    'functions', coalesce((SELECT jsonb_object_agg(f.schemaname || '.' || f.funcname || '/' || f.funcid, f.calls)
                             FROM pg_stat_xact_user_functions AS f), '{}'::jsonb));
$$;

-- What changed between two work() snapshots (zero rows left out).
CREATE FUNCTION pg_temp.work_delta(p_a jsonb, p_b jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT coalesce(jsonb_object_agg(x.k, x.d), '{}'::jsonb)
    FROM (SELECT 't:' || t.k AS k,
                 (SELECT jsonb_agg((p_b -> 'tables' -> t.k ->> i)::bigint - coalesce((p_a -> 'tables' -> t.k ->> i)::bigint, 0) ORDER BY i)
                    FROM generate_series(0, 7) AS i) AS d
            FROM jsonb_object_keys(p_b -> 'tables') AS t(k)
          UNION ALL
          SELECT 'f:' || f.k, to_jsonb((p_b -> 'functions' ->> f.k)::bigint - coalesce((p_a -> 'functions' ->> f.k)::bigint, 0))
            FROM jsonb_object_keys(p_b -> 'functions') AS f(k)) AS x
   WHERE x.d::text NOT IN ('[0, 0, 0, 0, 0, 0, 0, 0]', '0');
$$;

DO $$
DECLARE
  v_owner constant uuid := pg_temp.in_dating(pg_temp.person('72'));
  v_m1 constant uuid := pg_temp.person('73');
  v_m2 constant uuid := pg_temp.person('74');
  v_m3 constant uuid := pg_temp.person('75');
  v_m4 constant uuid := pg_temp.person('76');
  v_x constant uuid := pg_temp.person('77');
  v_y constant uuid := pg_temp.person('78');
  v_quiet constant uuid := pg_temp.in_dating(pg_temp.person('79'));
  v_rl constant uuid := pg_temp.in_dating(pg_temp.person('80'));
  v_lock_add constant uuid := pg_temp.person('81');
  v_lock_rm constant uuid := pg_temp.person('82');
  v_gone_phone constant uuid := pg_temp.person('83');
  v_closed constant uuid := pg_temp.in_dating(pg_temp.person('84'));
  v_auth_only constant uuid := pg_temp.id('85');
  v_rel constant uuid := pg_temp.id('86');
  v_trunk constant uuid := pg_temp.in_dating(pg_temp.person('87'));
  v_gh constant uuid := pg_temp.id('88');
  v_gb constant uuid := pg_temp.id('89');
  v_ng constant uuid := pg_temp.id('90');
  v_before text;
  v_i1 uuid; v_i2 uuid; v_i3 uuid; v_i4 uuid; v_ix uuid; v_match uuid;
  v jsonb;
  v_w0 jsonb; v_w1 jsonb; v_w2 jsonb; v_w3 jsonb;
  v_d1 jsonb; v_d2 jsonb; v_d3 jsonb;
  v_elig text;
  v_metric bigint;
  v_rows bigint;
  v_claims bigint;
  v_id uuid;
  n int;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'fixture: the exclusion key fingerprint is not ready';
  END IF;

  -- 1. Strict E.164, every malformed number refused as invalid phone, no raise.
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-p-0001', NULL, NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0002', '', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0003', '+0244123456', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0004', '+1555870', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0005', '+1234567890123456', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0006', '+1555870073x', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0007', '++1555870073', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0008', '+001555870073', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0009', '+1/555/870/073', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0010', U&'+\0661\0665\0665\0665\0668\0667\0660\0660\0667\0663', NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0011', '+' || repeat('1', 5000), NULL),
    public.add_dating_never_introduce('w1d-e1b-p-0012', '1555870073', NULL));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "phone"}'::jsonb)
     OR jsonb_array_length(v) IS DISTINCT FROM 12
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_owner)
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_owner) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed number was not refused as invalid (or was claimed or stored): %', v;
  END IF;

  -- 2. Labels: at most 20 after trimming any Unicode space; never a number,
  --    a control character or an invisible mark; blank is no label. A
  --    number's spaces are Unicode's (pg_c_utf8) whatever the server's libc:
  --    U+0085 is one macOS's libc misses, as glibc misses U+00A0.
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-l-0001', '+447700900601', 'call 0244123456'),
    public.add_dating_never_introduce('w1d-e1b-l-0002', '+447700900601', '1555870073'),
    public.add_dating_never_introduce('w1d-e1b-l-0008', '+447700900601', 'Ex 12345'),
    public.add_dating_never_introduce('w1d-e1b-l-0009', '+447700900601', U&'\FF10\FF12\FF14\FF14\FF11\FF12\FF13\FF14\FF15\FF16'),
    public.add_dating_never_introduce('w1d-e1b-l-0010', '+447700900601', U&'\0660\0662\0664\0664\0661\0662\0663\0664\0665\0666'),
    public.add_dating_never_introduce('w1d-e1b-l-0016', '+447700900601', U&'Ama \0966\0968\0967\0969\096A'),
    public.add_dating_never_introduce('w1d-e1b-l-0017', '+447700900601', U&'Kofi 02\FF14\06F4\09E7'),
    public.add_dating_never_introduce('w1d-e1b-l-0003', '+447700900601', E'E\tx'),
    public.add_dating_never_introduce('w1d-e1b-l-0004', '+447700900601', 'E' || U&'\200B' || 'x'),
    public.add_dating_never_introduce('w1d-e1b-l-0005', '+447700900601', 'E' || U&'\202E' || 'x'),
    public.add_dating_never_introduce('w1d-e1b-l-0006', '+447700900601', repeat('y', 21)),
    public.add_dating_never_introduce('w1d-e1b-l-0007', '+447700900601', repeat('y', 5000)));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "label"}'::jsonb)
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_owner) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a label holding a number, a control or invisible character, or over 20 was accepted: %', v;
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-l-0011', '0044 7700 900 601', U&'\00A0Ex 2019\3000'),
    public.add_dating_never_introduce('w1d-e1b-l-0012', '+447700900602', '   ' || repeat('z', 20) || '  '),
    public.add_dating_never_introduce('w1d-e1b-l-0013', '+447700900603', '   '),
    public.add_dating_never_introduce('w1d-e1b-l-0014', U&'+44\00A07700\3000900\2009\0085604', NULL),
    -- Re-adding a listed number with no label keeps its label.
    public.add_dating_never_introduce('w1d-e1b-l-0015', '+447700900601', NULL));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e IS DISTINCT FROM '{"ok": true, "message": "added"}'::jsonb)
     OR (SELECT string_agg(coalesce(label, '<none>') || ':' || last_two, ',' ORDER BY last_two)
           FROM public.dating_never_introduce WHERE owner_user_id = v_owner)
        IS DISTINCT FROM 'Ex 2019:01,' || repeat('z', 20) || ':02,<none>:03,<none>:04'
     OR (SELECT phone_hmac FROM public.dating_never_introduce WHERE owner_user_id = v_owner AND last_two = '04')
        IS DISTINCT FROM public.dating_phone_hmac('+447700900604') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid label or a number with Unicode spaces was refused or stored wrongly';
  END IF;

  -- 3. Not gated (exposure-reducing): restricted, Dating off and an
  --    untrusted device still add; remove and list keep the device check.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_closed, 'suspended');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v_elig := public.dating_eligibility(v_closed, 'setup');
  IF v_elig IS NOT DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'fixture: the restricted person is eligible';
  END IF;
  BEGIN
    CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS 'SELECT false';
    PERFORM pg_temp.as_user(v_closed);
    v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-g-0001', '+447700900611', 'Gated?'));
    PERFORM pg_temp.as_owner();
    v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_closed);
    PERFORM pg_temp.as_user(v_closed);
    v := v || jsonb_build_array(public.remove_dating_never_introduce(v_id), public.list_dating_never_introduce());
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'w1d-e1b-rollback-stub';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1d-e1b-rollback-stub' THEN
      RAISE;
    END IF;
  END;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": false, "reason": "reverify_device"},
                          {"ok": false, "reason": "reverify_device"}]'::jsonb
     OR public.dating_require_trusted_device() IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding was gated (eligibility, Dating off or the device), or remove/list skipped the device check: %', v;
  END IF;
  PERFORM pg_temp.as_user(v_closed);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-g-0002', '+447700900611', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_closed) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted person could not add a number: %', v;
  END IF;
  -- Outside Dating (a Relationship-path account with no Dating profile):
  -- not_eligible, nothing claimed, counted or stored (fix round 1, M-1).
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_rel, '1555870086', now(), now());
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_rel, '1555870086', 'Person 86', 'relationship', now(), now(), '2');
  PERFORM pg_temp.as_user(v_rel);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-g-0004', '+447700900613', 'Ex'));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "not_eligible"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_rel)
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_rel)
     OR EXISTS (SELECT 1 FROM public.dating_rate_limits WHERE user_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account outside Dating added a number (or was claimed or counted): %', v;
  END IF;
  -- An Auth account with no users row answers, never raises.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_auth_only, NULL, now(), now());
  PERFORM pg_temp.as_user(v_auth_only);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-g-0003', '+447700900612', NULL),
                         public.remove_dating_never_introduce(gen_random_uuid()),
                         public.remove_dating_never_introduce(NULL),
                         public.list_dating_never_introduce());
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "not_eligible"}, {"ok": true}, {"ok": true}, {"ok": true, "items": []}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no users row got a wrong answer: %', v;
  END IF;

  -- 4. The exclusion key must be ready: rotated, missing or unseeded ⇒
  --    feature_unavailable, counted, nothing claimed or written; the helper
  --    fails closed for a pair with a list; the same key works once ready.
  v_metric := pg_temp.metric_count('dating.never_introduce.key_not_ready');
  v_rows := (SELECT count(*) FROM public.dating_never_introduce);
  v_claims := (SELECT count(*) FROM public.dating_rpc_idempotency WHERE user_id = v_owner);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-rotated-key', true);
  IF public.dating_never_introduce_excludes(v_owner, v_y) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_y, v_owner) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_x, v_y) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated key the never-introduce filter failed open (or excluded a pair with no list)';
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-k-0001', '+447700900621', NULL));
  PERFORM pg_temp.as_owner();
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  IF public.dating_never_introduce_excludes(v_owner, v_y) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key the never-introduce filter failed open';
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := v || jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-k-0002', '+447700900622', NULL));
  PERFORM pg_temp.as_owner();
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF public.dating_never_introduce_excludes(v_owner, v_y) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with an unseeded fingerprint the never-introduce filter failed open';
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := v || jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-k-0003', '+447700900623', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "feature_unavailable"}, {"ok": false, "reason": "feature_unavailable"},
                          {"ok": false, "reason": "feature_unavailable"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce) IS DISTINCT FROM v_rows
     OR (SELECT count(*) FROM public.dating_rpc_idempotency WHERE user_id = v_owner) IS DISTINCT FROM v_claims
     OR pg_temp.metric_count('dating.never_introduce.key_not_ready') IS DISTINCT FROM v_metric + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without a ready exclusion key an add was not refused quietly and counted (or claimed or wrote): %', v;
  END IF;
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'fixture: re-seeding the fingerprint failed';
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-k-0001', '+447700900621', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}]'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_never_introduce
                     WHERE owner_user_id = v_owner AND phone_hmac = public.dating_phone_hmac('+447700900621'))
     OR public.dating_never_introduce_excludes(v_owner, v_y) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: once the key was ready the same request did not add (or the filter stayed closed): %', v;
  END IF;

  -- 5. Adding changes no introduction (fix round 1, I-1): the owner's own,
  --    whatever their state, and someone else's with the same person all
  --    stay exactly as they were; each listed pair is excluded. A listed
  --    number only stops introductions: the person's eligibility and other
  --    pairs are untouched.
  v_i1 := pg_temp.intro(v_owner, v_m1, 'interested');
  v_match := pg_temp.match(v_owner, v_m2);
  v_i3 := pg_temp.intro(v_owner, v_m3, 'generated');
  v_i4 := pg_temp.intro(v_owner, v_m4, 'passed');
  v_ix := pg_temp.intro(v_x, v_m1, 'presented');
  v_elig := public.dating_eligibility(v_m1, 'candidate');
  v_before := (SELECT string_agg(to_jsonb(i)::text, ';' ORDER BY i.id) FROM public.dating_introductions AS i
                WHERE v_owner IN (i.user_low_id, i.user_high_id) OR v_m1 IN (i.user_low_id, i.user_high_id))
              || (SELECT string_agg(to_jsonb(m)::text, ';' ORDER BY m.id) FROM public.dating_matches AS m WHERE m.id = v_match);
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-i-0001', '+1555870073', NULL),
    public.add_dating_never_introduce('w1d-e1b-i-0002', '+1555870074', NULL),
    public.add_dating_never_introduce('w1d-e1b-i-0003', '+1555870075', NULL),
    public.add_dating_never_introduce('w1d-e1b-i-0004', '+1555870076', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": true, "message": "added"}]'::jsonb
     OR v_before IS NULL
     OR v_before IS DISTINCT FROM
        (SELECT string_agg(to_jsonb(i)::text, ';' ORDER BY i.id) FROM public.dating_introductions AS i
          WHERE v_owner IN (i.user_low_id, i.user_high_id) OR v_m1 IN (i.user_low_id, i.user_high_id))
        || (SELECT string_agg(to_jsonb(m)::text, ';' ORDER BY m.id) FROM public.dating_matches AS m WHERE m.id = v_match) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a number changed an introduction or a match (the adder would see whose number it is)';
  END IF;
  IF public.dating_never_introduce_excludes(v_owner, v_m1) IS NOT TRUE OR public.dating_never_introduce_excludes(v_m2, v_owner) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_owner, v_m3) IS NOT TRUE OR public.dating_never_introduce_excludes(v_m4, v_owner) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed pair is not excluded';
  END IF;
  IF public.dating_eligibility(v_m1, 'candidate') IS DISTINCT FROM v_elig
     OR public.dating_never_introduce_excludes(v_m1, v_x) IS NOT FALSE
     OR public.dating_never_introduce_excludes(v_m1, v_owner) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed number did more than stop introductions with the list''s owner (Spec 1 O3)';
  END IF;
  -- Only the four never-introduce functions and Task 12's exit (which
  -- deletes the list unless kept) read the list (an introduction filter
  -- only).
  IF (SELECT string_agg(p.oid::regprocedure::text, ',' ORDER BY p.oid::regprocedure::text)
        FROM pg_proc AS p JOIN pg_namespace AS ns ON ns.oid = p.pronamespace
       WHERE ns.nspname NOT IN ('pg_catalog', 'information_schema') AND p.prosrc ~ '\mdating_never_introduce\M')
     IS DISTINCT FROM 'add_dating_never_introduce(text,text,text),dating_never_introduce_excludes(uuid,uuid),list_dating_never_introduce(),private.dating_exit_internal(uuid,boolean),remove_dating_never_introduce(uuid)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a function other than the four never-introduce functions and exit reads the list: %',
      (SELECT string_agg(p.oid::regprocedure::text, ',') FROM pg_proc AS p WHERE p.prosrc ~ '\mdating_never_introduce\M');
  END IF;

  -- 6. The filter fails closed when the other person's HMAC can't be read
  --    (no number), but only for a pair where someone has a list.
  UPDATE auth.users SET phone = NULL WHERE id = v_gone_phone;
  IF public.dating_phone_hmac_for_user(v_gone_phone) IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: the person still has an HMAC';
  END IF;
  IF public.dating_never_introduce_excludes(v_owner, v_gone_phone) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_gone_phone, v_owner) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_gone_phone, v_y) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable HMAC let a pair with a list through (or excluded a pair with none)';
  END IF;

  -- 7. No phone oracle: after a warm-up, adding a member's number, a
  --    stranger's and another member's (each from the same list size: the
  --    entry is removed outside the measured window) gives the same answer
  --    and the same table reads and writes and function calls. Fix round 1:
  --    all three share a calling code (the trunk lookup's cost follows the
  --    code, which the caller typed), and each add's two claims are deleted
  --    outside the windows too (a scan's reads follow the table's size).
  -- Fix round 1 (I-1): the adder is introduced to the member whose number is
  -- measured, where the oracle lived; the introduction must not change.
  v_i2 := pg_temp.intro(v_quiet, v_x, 'presented');
  v_ix := pg_temp.intro(v_quiet, v_y, 'presented');
  v_before := (SELECT string_agg(to_jsonb(i)::text, ';' ORDER BY i.id) FROM public.dating_introductions AS i WHERE i.id IN (v_i2, v_ix));
  PERFORM set_config('track_functions', 'all', true);
  PERFORM pg_temp.as_user(v_quiet);
  PERFORM public.add_dating_never_introduce('w1d-e1b-o-0000', '+447700900630', NULL);
  PERFORM pg_temp.as_owner();
  v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_quiet);
  PERFORM pg_temp.as_user(v_quiet);
  PERFORM public.remove_dating_never_introduce(v_id);
  PERFORM pg_temp.as_owner();
  v_w0 := pg_temp.work();
  PERFORM pg_temp.as_user(v_quiet);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-o-0001', '+1555870084', NULL));
  PERFORM pg_temp.as_owner();
  v_w1 := pg_temp.work();
  v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_quiet);
  PERFORM pg_temp.as_user(v_quiet);
  PERFORM public.remove_dating_never_introduce(v_id);
  PERFORM pg_temp.as_owner();
  DELETE FROM public.dating_rpc_idempotency WHERE user_id = v_quiet AND idempotency_key = 'w1d-e1b-o-0001';
  v_w2 := pg_temp.work();
  PERFORM pg_temp.as_user(v_quiet);
  v := v || jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-o-0002', '+1555870099', NULL));
  PERFORM pg_temp.as_owner();
  v_w3 := pg_temp.work();
  v_d1 := pg_temp.work_delta(v_w0, v_w1);
  v_d2 := pg_temp.work_delta(v_w2, v_w3);
  v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_quiet);
  PERFORM pg_temp.as_user(v_quiet);
  PERFORM public.remove_dating_never_introduce(v_id);
  PERFORM pg_temp.as_owner();
  DELETE FROM public.dating_rpc_idempotency WHERE user_id = v_quiet AND idempotency_key = 'w1d-e1b-o-0002';
  v_w0 := pg_temp.work();
  PERFORM pg_temp.as_user(v_quiet);
  v := v || jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-o-0003', '+1555870077', NULL));
  PERFORM pg_temp.as_owner();
  v_w1 := pg_temp.work();
  PERFORM set_config('track_functions', 'none', true);
  v_d3 := pg_temp.work_delta(v_w0, v_w1);
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": true, "message": "added"}]'::jsonb
     OR NOT (v_d1 ? 't:public.dating_never_introduce') OR NOT (v_d1 ? 't:public.dating_profiles')
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_quiet) IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'fixture: the oracle probe did not run as expected: % %', v, v_d1;
  END IF;
  IF v_d1 IS DISTINCT FROM v_d2 OR v_d2 IS DISTINCT FROM v_d3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a member''s number did different work from a stranger''s (a phone oracle): member % stranger % member %',
      v_d1, v_d2, v_d3;
  END IF;
  IF v_before IS DISTINCT FROM (SELECT string_agg(to_jsonb(i)::text, ';' ORDER BY i.id) FROM public.dating_introductions AS i
                                 WHERE i.id IN (v_i2, v_ix))
     OR (v_d1 ? 't:public.dating_introductions') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding the number of someone introduced to the adder changed that introduction (a phone oracle)';
  END IF;
  IF public.dating_never_introduce_excludes(v_quiet, v_x) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the measured pair is not excluded';
  END IF;

  -- 8. Rate limit: 60 adds a day (invalid input isn't counted); the 61st
  --    answers rate_limited, claims nothing and writes nothing.
  PERFORM pg_temp.as_user(v_rl);
  FOR n IN 1..5 LOOP
    PERFORM public.add_dating_never_introduce('w1d-e1b-r-x' || lpad(n::text, 4, '0'), '0244 123 456', NULL);
  END LOOP;
  FOR n IN 1..60 LOOP
    v := public.add_dating_never_introduce('w1d-e1b-r-' || lpad(n::text, 4, '0'), '+4477009' || lpad(least(n, 50)::text, 5, '0'), NULL);
    IF v IS DISTINCT FROM '{"ok": true, "message": "added"}'::jsonb THEN
      PERFORM pg_temp.as_owner();
      RAISE EXCEPTION 'CONTRACT VIOLATED: add % of 60 in a day was refused: %', n, v;
    END IF;
  END LOOP;
  v := public.add_dating_never_introduce('w1d-e1b-r-0061', '+447700900001', NULL);
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_rl AND idempotency_key = 'w1d-e1b-r-0061')
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_rl) IS DISTINCT FROM 50::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 61st add in a day was not rate-limited (or claimed or wrote): %', v;
  END IF;
  -- Fix round 1 (M-4): a retry of an add that was made answers "added" even
  -- past the limit; (M-3) the key reused for another number is refused and
  -- stores nothing; neither spends the limit.
  PERFORM pg_temp.as_user(v_rl);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-r-0001', '+447700900001', NULL),
    public.add_dating_never_introduce('w1d-e1b-r-0060', '0044 7700 900 050', NULL),
    public.add_dating_never_introduce('w1d-e1b-r-0002', '+447700900777', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"},
                          {"ok": false, "reason": "invalid", "field": "idempotency_key"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_rl) IS DISTINCT FROM 50::bigint
     OR (SELECT request_count FROM public.dating_rate_limits WHERE user_id = v_rl AND operation = 'never_introduce_add') IS DISTINCT FROM 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay past the limit was not "added", or a reused key was not refused (or spent the limit): %', v;
  END IF;

  -- 12. (Fix round 1, I-2) A trunk 0 typed after the calling code: dropped
  --     where the country dials one (Ghana, the UK, Nigeria), kept where it
  --     is part of the number (Italy), refused where it can't be judged (no
  --     trunk 0 there, an unlisted code, a second 0). The HMAC is the account
  --     phone's (Auth's digits), so the person on the number is excluded.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES
    (v_gh, '233244123456', now(), now()), (v_gb, '447700900999', now(), now()), (v_ng, '2348031234567', now(), now());
  PERFORM pg_temp.as_user(v_trunk);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-t-0001', '+233 0244 123 456', 'Gh'),
    public.add_dating_never_introduce('w1d-e1b-t-0002', '00233 0244 123 456', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0003', '+233 (0)244 123456', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0004', '+233 244 123 456', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0005', '+44 (0)7700 900999', 'Gb'),
    public.add_dating_never_introduce('w1d-e1b-t-0006', '+44 07700 900999', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0007', '0044 7700 900999', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0008', '+234 0803 123 4567', 'Ng'),
    public.add_dating_never_introduce('w1d-e1b-t-0009', '+234 803 123 4567', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0010', '002340803-123-4567', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0011', '+39 06 1234 5678', 'It'),
    public.add_dating_never_introduce('w1d-e1b-t-0012', '+258 84 123 4567', 'Mz'));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e IS DISTINCT FROM '{"ok": true, "message": "added"}'::jsonb)
     OR (SELECT string_agg(label || '=' || (phone_hmac = public.dating_phone_hmac(CASE label
                 WHEN 'Gh' THEN '+233244123456' WHEN 'Gb' THEN '+447700900999' WHEN 'Ng' THEN '+2348031234567'
                 WHEN 'It' THEN '+390612345678' WHEN 'Mz' THEN '+258841234567' END))::text, ',' ORDER BY label)
           FROM public.dating_never_introduce WHERE owner_user_id = v_trunk)
        IS DISTINCT FROM 'Gb=true,Gh=true,It=true,Mz=true,Ng=true'
     OR public.dating_never_introduce_excludes(v_trunk, v_gh) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_gb, v_trunk) IS NOT TRUE
     OR public.dating_never_introduce_excludes(v_trunk, v_ng) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number typed with its trunk 0 did not hash as the account phone: %', v;
  END IF;
  PERFORM pg_temp.as_user(v_trunk);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-e1b-t-0101', '+233 00244 123 456', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0102', '+44 0 07700 900999', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0103', '+1 0555 870 073', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0104', '+221 077 123 4567', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0105', '+258 084 123 4567', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0106', '+7 0912 345 6789', NULL),
    public.add_dating_never_introduce('w1d-e1b-t-0107', '+2330', NULL));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "phone"}'::jsonb)
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_trunk) IS DISTINCT FROM 5::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 0 after the calling code that can''t be judged was "Added.": %', v;
  END IF;
  -- The trunk table: codes are prefix-free, every one- and two-digit code is
  -- listed (so an unlisted code has three digits), and no API role reads it.
  IF EXISTS (SELECT 1 FROM private.dating_phone_trunk_rules AS a JOIN private.dating_phone_trunk_rules AS b
              ON a.calling_code <> b.calling_code AND starts_with(b.calling_code, a.calling_code))
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['1', '7', '20', '27', '30', '31', '32', '33', '34', '36', '39', '40', '41', '43', '44', '45',
                                          '46', '47', '48', '49', '51', '52', '53', '54', '55', '56', '57', '58', '60', '61', '62', '63',
                                          '64', '65', '66', '81', '82', '84', '86', '90', '91', '92', '93', '94', '95', '98']) AS c
                 WHERE NOT EXISTS (SELECT 1 FROM private.dating_phone_trunk_rules AS r WHERE r.calling_code = c))
     OR (SELECT string_agg(calling_code || ':' || after_code_zero, ',' ORDER BY calling_code) FROM private.dating_phone_trunk_rules
          WHERE calling_code IN ('233', '234', '44', '39', '1', '221'))
        IS DISTINCT FROM '1:refuse,221:refuse,233:strip,234:strip,39:keep,44:strip'
     OR has_table_privilege('service_role', 'private.dating_phone_trunk_rules', 'SELECT')
     OR has_function_privilege('authenticated', 'private.dating_typed_phone_e164(text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_typed_phone_e164(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the trunk-prefix table is not prefix-free and complete, or an API role reaches it';
  END IF;
  -- (M-3) A key reused for another number before any limit: refused, not
  -- silently dropped.
  PERFORM pg_temp.as_user(v_trunk);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-e1b-t-0001', '+447700900778', NULL),
                         public.add_dating_never_introduce('w1d-e1b-t-0001', '+233-0244-123-456', 'Gh'));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "invalid", "field": "idempotency_key"}, {"ok": true, "message": "added"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_trunk) IS DISTINCT FROM 5::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reused key with another number was not refused (or its replay was not "added"): %', v;
  END IF;
  -- The service role reads no list (fix round 1, M-5).
  IF has_table_privilege('service_role', 'public.dating_never_introduce', 'SELECT')
     OR has_table_privilege('service_role', 'public.dating_never_introduce', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can read or probe the never-introduce list';
  END IF;

  -- 9. No number anywhere: not in the list, a claim, a rate-limit row or a
  --    counter; the owner's list rows have exactly id, label, last_two.
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce AS t WHERE to_jsonb(t)::text ~ '(555870|7700900|244123456|8031234567|841234567|12345678)')
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency AS i WHERE to_jsonb(i)::text ~ '(555870|7700900|244123456|8031234567|841234567|12345678)')
     OR EXISTS (SELECT 1 FROM public.dating_rate_limits AS r WHERE to_jsonb(r)::text ~ '(555870|7700900|244123456|8031234567|841234567|12345678)')
     OR EXISTS (SELECT 1 FROM public.metric_counters AS c WHERE c.key ~ '[0-9]{5}') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a typed number was stored in plaintext somewhere';
  END IF;
  PERFORM pg_temp.as_user(v_owner);
  v := public.list_dating_never_introduce();
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'items') AS e
              WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) AS k) IS DISTINCT FROM ARRAY['id', 'label', 'last_two'])
     OR jsonb_array_length(v -> 'items') IS DISTINCT FROM 9 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a list row is not exactly {id, label, last_two}: %', v;
  END IF;

  -- 10. Remove: the owner's own row goes; any id answers the same.
  v_id := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_owner AND last_two = '73');
  PERFORM pg_temp.as_user(v_owner);
  v := jsonb_build_array(public.remove_dating_never_introduce(v_id), public.remove_dating_never_introduce(v_id),
                         public.remove_dating_never_introduce(NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true}, {"ok": true}, {"ok": true}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE id = v_id)
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_owner) IS DISTINCT FROM 8::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: removing one''s own entry did not remove exactly it: %', v;
  END IF;

  -- 11. Locks: add and remove take the person's setup lock first.
  IF pg_temp.holds_setup_lock(v_lock_add) OR pg_temp.holds_setup_lock(v_lock_rm) THEN
    RAISE EXCEPTION 'fixture: a setup lock is held before the probe';
  END IF;
  PERFORM pg_temp.as_user(v_lock_add);
  PERFORM public.add_dating_never_introduce('w1d-e1b-lk-0001', 'not a number', NULL);
  PERFORM pg_temp.as_user(v_lock_rm);
  PERFORM public.remove_dating_never_introduce(gen_random_uuid());
  PERFORM pg_temp.as_owner();
  IF NOT pg_temp.holds_setup_lock(v_lock_add) OR NOT pg_temp.holds_setup_lock(v_lock_rm) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: add or remove ran without the person''s setup lock';
  END IF;
END $$;
-- =====================================================================
-- E2. (W1d) Activation with explicit "Everyone"; pause, resume and their
--    reasons; exit's hard delete (the never-introduce list kept only if
--    ticked, matches sealed, consents kept; mutants 17, 30); consent
--    withdrawal is exit, except faith's (owner ruling 2); the parked pause
--    (R19); generation's key guard (mutant 5); health v2; no Dating
--    function mentions users.mode. Batch 10 adds: exit covers every
--    Dating row (notify request, upload intents, session row, reflections;
--    PF-F8) and queues photos through the CSAM evidence guard; exit keeps
--    a suspension; consent input is validated and timed by the server
--    (M-12); the lifecycle takes the setup lock; a NULL eligibility
--    refuses; activation and resume re-check the name (B7 I-3/M-5); an
--    unseeded exclusion fingerprint refuses (B2/B5 M-4); the field-key
--    fingerprint (B6 M-5); readiness needs the identity (B7 M-4).
-- =====================================================================
-- E2's own people (the earlier sections use every free 00NN id): ids
-- 5e2a0000-0000-0000-0000-0000000001NN, phones 15558704NN, otherwise as
-- pg_temp.person.
CREATE FUNCTION pg_temp.e2_person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := ('5e2a0000-0000-0000-0000-0000000001' || p_n)::uuid;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '15558704' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '15558704' || p_n, 'Person ' || p_n, 'dating', now() - interval '400 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, current_date - interval '30 years');
  RETURN v_u;
END $$;

-- A person [p_n] in the UK through D2-D10 with [p_seeking], verified, two
-- approved photos: everything activation needs.
CREATE FUNCTION pg_temp.complete(p_n text, p_identity text, p_seeking text[]) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.e2_person(p_n);
  v jsonb := '[]'::jsonb;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w1d-consent-' || c, c, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS c;
  PERFORM pg_temp.as_user(v_u);
  v := v || jsonb_build_array(public.save_dating_intention('w1d-' || p_n || '-d2-0001', 'committed', NULL, true, true, NULL, false));
  v := v || jsonb_build_array(public.save_dating_location('w1d-' || p_n || '-d3-0001', 'GB', 'TLI', NULL, 'region'));
  v := v || jsonb_build_array(public.save_dating_identity('w1d-' || p_n || '-d5-0001', p_identity, NULL, NULL, NULL, false));
  v := v || jsonb_build_array(public.save_dating_who_to_meet('w1d-' || p_n || '-d6-0001', p_seeking, 25, 40));
  v := v || jsonb_build_array(public.save_dating_children('w1d-' || p_n || '-d7-0001', false, 'yes', false, false));
  v := v || jsonb_build_array(public.save_dating_prompts('w1d-' || p_n || '-d10-001',
         '[{"prompt_id": "perfect_sunday", "answer": "A long walk by the river."},
           {"prompt_id": "ask_me_about", "answer": "The book I am reading now."}]'));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e ->> 'ok' IS DISTINCT FROM 'true') THEN
    RAISE EXCEPTION 'fixture: setup failed for %: %', p_n, v;
  END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_u;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'w1d-contract', now());
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (v_u, 'w1d/' || p_n || '-1.jpg', 1, 'approved'), (v_u, 'w1d/' || p_n || '-2.jpg', 2, 'approved');
  RETURN v_u;
END $$;

-- [p_n] complete and active (activated through the RPC).
CREATE FUNCTION pg_temp.active(p_n text, p_identity text, p_seeking text[]) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.complete(p_n, p_identity, p_seeking);
  v_e public.dating_enrollments;
BEGIN
  PERFORM pg_temp.as_user(v_u);
  v_e := public.activate_dating_profile('w1d-' || p_n || '-activate-01');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'fixture: % did not activate (%)', p_n, v_e.state;
  END IF;
  RETURN v_u;
END $$;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('dating_mode_enabled', 'dating_same_gender_matching');
  PERFORM pg_temp.as_service('SELECT public.publish_country_config(''GB'', ''{"dating_enabled": true}'')::text');
  IF private.dating_exclusion_key_ready() IS NOT TRUE OR EXISTS (SELECT 1 FROM private.dating_key_fingerprints WHERE name = 'dating_field_key') THEN
    RAISE EXCEPTION 'fixture: E2 needs the seeded exclusion key and no field-key fingerprint';
  END IF;
END $$;

DO $$
DECLARE
  v_a uuid;
  v_b uuid;
  v_keeper uuid;
  v_withdraw uuid;
  v_parked uuid;
  v_outsider constant uuid := pg_temp.e2_person('55');
  v_e public.dating_enrollments;
  v_m uuid;
  v_closed uuid;
  v_i uuid;
  v jsonb;
  v_answers jsonb;
  v_msg text;
BEGIN
  v_a := pg_temp.complete('50', 'woman', ARRAY['man', 'non_binary', 'woman']);
  v_b := pg_temp.complete('51', 'man', ARRAY['woman']);
  v_keeper := pg_temp.complete('52', 'man', ARRAY['woman']);
  v_withdraw := pg_temp.complete('53', 'woman', ARRAY['man']);
  v_parked := pg_temp.complete('54', 'woman', ARRAY['man']);

  -- Activation: explicit "Everyone" works; no checkbox; dating_profile_ready v2.
  IF public.dating_profile_ready(v_a) OR NOT public.dating_profile_complete(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: readiness before activation is wrong';
  END IF;
  -- Who-to-meet is part of completeness.
  v_answers := jsonb_build_object('seeking', encode((SELECT seeking_enc FROM public.dating_profile_sensitive WHERE user_id = v_keeper), 'base64'));
  UPDATE public.dating_profile_sensitive SET seeking_enc = NULL WHERE user_id = v_keeper;
  IF public.dating_profile_complete(v_keeper) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile with no who-to-meet answer is complete';
  END IF;
  UPDATE public.dating_profile_sensitive SET seeking_enc = decode(v_answers ->> 'seeking', 'base64') WHERE user_id = v_keeper;
  PERFORM pg_temp.as_user(v_a);
  v_e := public.activate_dating_profile('w1d-activate-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' OR NOT public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete profile seeking Everyone did not activate';
  END IF;
  -- Batch 7 M-4: an active profile whose identity is gone (a country
  -- change re-asks D5) is not ready.
  v_answers := jsonb_build_object('identity', encode((SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_a), 'base64'));
  UPDATE public.dating_profile_sensitive SET identity_enc = NULL WHERE user_id = v_a;
  IF public.dating_profile_ready(v_a) OR public.dating_profile_complete(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active profile with no identity answer is ready';
  END IF;
  UPDATE public.dating_profile_sensitive SET identity_enc = decode(v_answers ->> 'identity', 'base64') WHERE user_id = v_a;
  DELETE FROM public.dating_prompts WHERE user_id = v_b AND position = 2;
  PERFORM pg_temp.as_user(v_b);
  BEGIN
    PERFORM public.activate_dating_profile('w1d-activate-b-0001');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'profile_or_preferences_incomplete' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile with one prompt activated (%)', v_msg;
  END IF;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  VALUES (v_b, 2, 'small_thing', 'Fresh bread in the morning.');
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.activate_dating_profile('w1d-activate-b-0002');
  PERFORM pg_temp.as_owner();
  IF NOT public.dating_profile_ready(v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete man-seeking-women profile did not activate';
  END IF;

  -- Pause, resume, reasons.
  PERFORM pg_temp.as_user(v_a);
  v_e := public.pause_dating_mode('w1d-pause-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'paused' OR v_e.pause_reason IS DISTINCT FROM 'user' OR public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing did not pause with the user reason';
  END IF;
  PERFORM public.pause_dating_for_relationship_user(v_a);
  IF (SELECT pause_reason FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'user' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second pause replaced the first reason';
  END IF;
  PERFORM pg_temp.as_user(v_a);
  v_e := public.resume_dating_mode('w1d-resume-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' OR v_e.pause_reason IS NOT NULL OR NOT public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume did not reactivate a complete, eligible profile';
  END IF;
  PERFORM public.pause_dating_for_relationship_user(v_b);
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_b) IS DISTINCT FROM 'paused/relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship pause has no relationship reason';
  END IF;
  -- A later pause keeps the first reason; resuming needs eligibility.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_b, NULL, 'pending', 'W1DRESUME1', now() + interval '1 day');
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.pause_dating_mode('w1d-pause-b-0001');
  BEGIN
    PERFORM public.resume_dating_mode('w1d-resume-b-0001');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'resume_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume ignored eligibility (a pending relationship): %', v_msg;
  END IF;
  IF (SELECT pause_reason FROM public.dating_enrollments WHERE user_id = v_b) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing again replaced the relationship reason';
  END IF;
  DELETE FROM public.relationships WHERE invite_code = 'W1DRESUME1';

  -- Exit: the hard delete (mutants 17, 30). Batch 10: every Dating row of
  -- the person (PF-F8's notify request, an unattached upload, the session
  -- row, a private reflection), photos queued through the CSAM evidence
  -- guard (an object under an open, unquarantined match stays held).
  v_m := pg_temp.match(v_a, v_b);
  -- Fix round 1 (M-11): an already-closed match keeps its reason and window.
  v_closed := pg_temp.match(v_a, v_withdraw);
  UPDATE public.dating_matches SET state = 'unmatched', closed_reason = 'unmatched', closed_at = now() - interval '2 days',
                                   evidence_until = now() + interval '28 days' WHERE id = v_closed;
  INSERT INTO public.dating_notify_requests (user_id, country_code, region_code) VALUES (v_a, 'GH', 'AA');
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at)
  VALUES (v_a, 'w1d/50-unattached.jpg', 'image/jpeg', now() + interval '1 hour');
  INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here,
                                             away_from_home, ip_resolved)
  VALUES (v_a, 3, true, true, false, true);
  INSERT INTO public.dating_date_reflections (match_id, author_user_id, response, idempotency_key)
  VALUES (v_m, v_a, 'good', 'w1d-reflection-a-01'), (v_m, v_b, 'good', 'w1d-reflection-b-01');
  INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name, status, quarantined)
  VALUES ('csam_match', v_a, 'dating-profile-photos', 'w1d/50-2.jpg', 'open', NULL);
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.add_dating_never_introduce('w1d-never-a-0001', '+447700900111', NULL);
  PERFORM public.save_dating_settings('w1d-settings-a-01', '{"digest_push": true}');
  BEGIN
    v_e := public.exit_dating_mode('w1d-exit-a-0001');
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit failed on a row it left behind (%)', SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  IF (SELECT state || '/' || closed_reason || '/' || (evidence_until < now() + interval '29 days')::text
        FROM public.dating_matches WHERE id = v_closed) IS DISTINCT FROM 'unmatched/unmatched/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit relabelled or re-sealed an already-closed match';
  END IF;
  IF v_e.state IS DISTINCT FROM 'exited'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_profile_sensitive WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_prompts WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_settings WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE v_a IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit left Dating data behind';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_photo_upload_intents WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_session_context WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_date_reflections WHERE author_user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_feature_snapshots WHERE user_id = v_a)
     OR NOT EXISTS (SELECT 1 FROM public.dating_date_reflections WHERE author_user_id = v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit left a notify request, an upload, the session row, a reflection or a snapshot (or took the other person''s reflection)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_age_verifications WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit deleted the age assurance result (kept while the account exists, §4.8)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept the never-introduce list by default (R-2)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND state = 'closed' AND closed_reason = 'exit'
                   AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit did not seal the conversation for the 30-day evidence window';
  END IF;
  IF (SELECT count(*) FROM public.dating_consent_events WHERE user_id = v_a AND action = 'granted') IS DISTINCT FROM 3::bigint
     OR NOT EXISTS (SELECT 1 FROM public.dating_consent_events WHERE user_id = v_a AND purpose = 'dating_opt_in' AND action = 'withdrawn')
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                     WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w1d/50-1.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit did not keep the consent record and its withdrawal, or did not queue the photos';
  END IF;
  IF (SELECT not_before FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w1d/50-1.jpg')
       IS NOT DISTINCT FROM 'infinity'::timestamptz
     OR (SELECT not_before FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w1d/50-2.jpg')
       IS DISTINCT FROM 'infinity'::timestamptz
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                     WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w1d/50-unattached.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit''s photo deletions bypassed the CSAM evidence guard or missed the unattached upload';
  END IF;
  -- Kept only when ticked.
  PERFORM pg_temp.as_user(v_keeper);
  PERFORM public.add_dating_never_introduce('w1d-never-k-0001', '+447700900222', NULL);
  PERFORM public.exit_dating_mode('w1d-exit-k-0001', true);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_keeper) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ticked "Keep my list" lost the list';
  END IF;
  -- Withdrawing a consent is leaving Dating (§3.2 D4).
  PERFORM pg_temp.as_user(v_withdraw);
  PERFORM public.record_dating_consent('w1d-withdraw-0001', 'special_category_profile', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_withdraw) IS DISTINCT FROM 'exited'
     OR EXISTS (SELECT 1 FROM public.dating_profile_sensitive WHERE user_id = v_withdraw) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing the special-category consent did not exit and delete';
  END IF;
  -- A replayed withdrawal (same key) is not a second exit: back in Dating,
  -- the replay changes nothing.
  UPDATE public.dating_enrollments SET state = 'profile_draft', exited_at = NULL WHERE user_id = v_withdraw;
  PERFORM pg_temp.as_user(v_withdraw);
  PERFORM public.record_dating_consent('w1d-withdraw-0001', 'special_category_profile', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_withdraw) IS DISTINCT FROM 'profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed withdrawal exited again';
  END IF;
  PERFORM pg_temp.as_user(v_outsider);
  BEGIN
    PERFORM public.record_dating_consent('w1d-oldpurpose-01', 'historical_data', 'granted', 'dating-2.0', '[]');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'invalid_consent_event'
     OR EXISTS (SELECT 1 FROM public.dating_consent_events WHERE purpose IN ('historical_data', 'age_gate')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the v1 consent purposes still exist';
  END IF;
  BEGIN
    INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
    VALUES (v_outsider, 'w1d-direct-age-gate', 'age_gate', 'granted', 'dating-2.0', now());
    v_msg := NULL;
  EXCEPTION WHEN check_violation THEN
    v_msg := 'refused';
  END;
  IF v_msg IS DISTINCT FROM 'refused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the table still accepts a v1 consent purpose';
  END IF;
  IF to_regprocedure('public.delete_dating_profile(text)') IS NOT NULL
     OR to_regprocedure('public.exit_dating_mode(text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'dating_enrollments' AND column_name = 'adults_only_confirmed_at') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete_dating_profile, the one-argument exit or the adults-only checkbox survives';
  END IF;

  -- The parked pause (R19, I-11): Spec 1's mark sets phone_released_at;
  -- the account leaves Today at once; nothing is carried at parking (O3).
  PERFORM pg_temp.as_user(v_parked);
  PERFORM public.activate_dating_profile('w1d-activate-p-0001');
  PERFORM pg_temp.as_owner();
  v_i := pg_temp.intro(v_parked, v_b);
  UPDATE public.users SET phone_released_at = now() WHERE id = v_parked;
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_parked) IS DISTINCT FROM 'paused/account_parked'
     OR (SELECT profile_state FROM public.dating_profiles WHERE user_id = v_parked) IS DISTINCT FROM 'paused'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i) IS DISTINCT FROM 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parking did not pause with account_parked and end the introductions';
  END IF;
  -- (Section C checks that parking writes no enforcement record, O3.)
  -- PF-F9 (a): active again, a later change of the column leaves it so.
  UPDATE public.dating_enrollments SET state = 'active', pause_reason = NULL, paused_at = NULL WHERE user_id = v_parked;
  UPDATE public.users SET phone_released_at = now() + interval '1 minute' WHERE id = v_parked;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_parked) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked trigger fired on a later change';
  END IF;

  -- Generation's key guard (mutant 5).
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := public.run_dating_candidate_generation(NULL);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v := jsonb_build_array(v, public.run_dating_candidate_generation(NULL));
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';
  IF v IS DISTINCT FROM '[{"skipped": "missing_key"}, {"skipped": "missing_key"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_generation_runs WHERE started_at > now() - interval '1 minute') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation ran without dating_exclusion_key or dating_field_key: %', v;
  END IF;

  -- Health v2.
  v := public.get_dating_operational_health();
  IF NOT (v ?& ARRAY['environment', 'field_key_present', 'log_settings_safe', 'enabled_countries'])
     OR v ->> 'environment' IS DISTINCT FROM 'development' OR (v ->> 'field_key_present')::boolean IS NOT TRUE
     OR jsonb_typeof(v -> 'log_settings_safe') IS DISTINCT FROM 'boolean'
     OR v -> 'enabled_countries' IS DISTINCT FROM to_jsonb(private.dating_open_countries()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health v2 is missing or wrong: %', v;
  END IF;

  -- No Dating function body writes (or mentions) users.mode.
  IF EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'private') AND p.proname ~ 'dating'
                AND p.prosrc ~* '(users\M[^;]*\mmode\M|\mu\.mode\M)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating function mentions users.mode';
  END IF;
END $$;

-- [p_sql] as [p_user]: NULL, the 22023/42501 message, or 'raw <SQLSTATE>'
-- for any other error (a raw constraint error must never reach the app).
CREATE FUNCTION pg_temp.err_any(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user(p_user);
  EXECUTE p_sql;
  PERFORM pg_temp.as_owner();
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_owner();
  RETURN CASE WHEN SQLSTATE IN ('22023', '42501') THEN SQLERRM ELSE 'raw ' || SQLSTATE END;
END $$;

-- ---------------------------------------------------------------------
-- E2b. Consent input (pre-validated: a named 22023, never a raw
--      constraint error) and the server's clock (batch-6 M-12: two events
--      in one transaction keep their order; nothing the client sends sets
--      the time).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_u constant uuid := pg_temp.e2_person('71');
  v_t text;
  v_got text[] := ARRAY[]::text[];
  v_g timestamptz;
  v_w timestamptz;
BEGIN
  FOREACH v_t IN ARRAY ARRAY[
    'SELECT public.record_dating_consent(NULL, ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''short'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''w1d bad key!'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-01'', NULL, ''granted'', ''dating-2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-02'', ''dating_terms'', NULL, ''dating-2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-03'', ''dating_terms'', ''granted'', NULL, ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-04'', ''dating_terms'', ''granted'', repeat(''v'', 41), ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-05'', ''dating_terms'', ''granted'', ''dating 2.0'', ''[]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-06'', ''dating_terms'', ''granted'', ''dating-2.0'', ''{}'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-07'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[1]'')',
    'SELECT public.record_dating_consent(''w1d-consent-v-08'', ''dating_terms'', ''granted'', ''dating-2.0'', to_jsonb(array_fill(''x''::text, ARRAY[21])))',
    'SELECT public.record_dating_consent(''w1d-consent-v-09'', ''dating_terms'', ''granted'', ''dating-2.0'', jsonb_build_array(repeat(''c'', 65)))'] LOOP
    v_got := v_got || coalesce(pg_temp.err_any(v_u, v_t), 'accepted');
  END LOOP;
  IF v_got IS DISTINCT FROM ARRAY['idempotency_key_required', 'idempotency_key_invalid', 'idempotency_key_invalid',
                                  'invalid_consent_event', 'invalid_consent_event', 'invalid_consent_event',
                                  'invalid_consent_event', 'invalid_consent_event', 'invalid_consent_event',
                                  'invalid_consent_event', 'invalid_consent_event', 'invalid_consent_event'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: consent input was not refused by name: %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_consent_events WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused consent event was stored';
  END IF;
  -- NULL categories mean none.
  IF pg_temp.err_as(v_u, 'SELECT public.record_dating_consent(''w1d-consent-g-01'', ''dating_terms'', ''grant'', ''dating-2.0'', NULL)') IS NOT NULL
     OR pg_temp.err_as(v_u, 'SELECT public.record_dating_consent(''w1d-consent-w-01'', ''dating_terms'', ''withdraw'', ''dating-2.0'', ''["terms"]'')') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid grant or withdrawal was refused';
  END IF;
  SELECT occurred_at INTO v_g FROM public.dating_consent_events WHERE user_id = v_u AND idempotency_key = 'w1d-consent-g-01';
  SELECT occurred_at INTO v_w FROM public.dating_consent_events WHERE user_id = v_u AND idempotency_key = 'w1d-consent-w-01';
  IF v_g IS NULL OR v_w IS NULL OR NOT (v_g > now() AND v_w > v_g AND v_w <= clock_timestamp())
     OR private.dating_consent_granted(v_u, 'dating_terms') IS NOT FALSE
     OR (SELECT categories FROM public.dating_consent_events WHERE user_id = v_u AND idempotency_key = 'w1d-consent-g-01') IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: consent time is not the server''s clock (grant %, withdrawal %, transaction %)', v_g, v_w, now();
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.record_dating_consent(text,text,text,text,jsonb)'::regprocedure
              AND (pg_get_function_arguments(oid) ~* 'timestamp' OR prosrc !~ 'clock_timestamp\(\)')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the consent writer takes a time from its caller';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2c. Exit keeps a suspension (only the data goes); the lifecycle takes
--      the person's setup lock first (the shared order: setup, then
--      same-gender, then rows), so a setup step can't interleave. The
--      setup writers take that lock too, so the lock checks use people
--      whose rows are written directly (pg_temp.direct), never through a
--      writer.
-- ---------------------------------------------------------------------
-- [p_n] with every row readiness v2 reads, written directly, enrolment
-- [p_state] (profile [p_profile]).
CREATE FUNCTION pg_temp.direct(p_n text, p_state text, p_profile text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.e2_person(p_n);
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w1d-direct-' || c, c, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS c;
  INSERT INTO public.dating_enrollments (user_id, state, terms_version, opted_in_at, paused_at, pause_reason, activated_at)
  VALUES (v_u, p_state, 'dating-2.0', now(), CASE WHEN p_state = 'paused' THEN now() END,
          CASE WHEN p_state = 'paused' THEN 'user' END,
          CASE WHEN p_state IN ('active', 'paused') THEN now() - interval '1 day' END);
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, verification_state, profile_state,
                                      country_code, region_code, intention, not_married_attested_at, attestation_version,
                                      children_have, children_want)
  VALUES (v_u, 'Person ' || p_n, 'approved', 'verified', p_profile, 'GB', 'TLI', 'committed', now(), '2026-10-v1', false, 'yes');
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (v_u, private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}'),
          private.dating_field_encrypt('{"seeking": ["man"]}'));
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (v_u, 25, 40);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES
    (v_u, 1, 'perfect_sunday', 'A long walk by the river.'), (v_u, 2, 'ask_me_about', 'The book I am reading now.');
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (v_u, 'w1d/' || p_n || '-1.jpg', 1, 'approved'), (v_u, 'w1d/' || p_n || '-2.jpg', 2, 'approved');
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'w1d-contract', now());
  IF NOT public.dating_profile_complete(v_u) THEN
    RAISE EXCEPTION 'fixture: % is not complete', p_n;
  END IF;
  RETURN v_u;
END $$;

DO $$
DECLARE
  v_s constant uuid := pg_temp.complete('57', 'woman', ARRAY['man']);
  v_act constant uuid := pg_temp.direct('64', 'profile_draft', 'draft');
  v_pause constant uuid := pg_temp.direct('65', 'active', 'active');
  v_res constant uuid := pg_temp.direct('59', 'paused', 'paused');
  v_exit constant uuid := pg_temp.direct('67', 'active', 'active');
  v_wd constant uuid := pg_temp.direct('68', 'active', 'active');
  v_e public.dating_enrollments;
  v_got text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'suspended', suspended_at = now() WHERE user_id = v_s;
  PERFORM pg_temp.as_user(v_s);
  v_e := public.exit_dating_mode('w1d-exit-s-0001');
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_s) IS DISTINCT FROM 'suspended'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_s)
     OR EXISTS (SELECT 1 FROM public.dating_profile_sensitive WHERE user_id = v_s) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit cleared a suspension (or kept the data): %', v_e.state;
  END IF;
  IF pg_temp.holds_setup_lock(v_act) OR pg_temp.holds_setup_lock(v_pause) OR pg_temp.holds_setup_lock(v_res)
     OR pg_temp.holds_setup_lock(v_exit) OR pg_temp.holds_setup_lock(v_wd) THEN
    RAISE EXCEPTION 'fixture: a setup lock is already held';
  END IF;
  PERFORM pg_temp.as_user(v_act);
  v_e := public.activate_dating_profile('w1d-lock-act-0001');
  v_got := v_e.state;
  PERFORM pg_temp.as_user(v_pause);
  v_e := public.pause_dating_mode('w1d-lock-pause-0001');
  v_got := v_got || '/' || v_e.state;
  PERFORM pg_temp.as_user(v_res);
  v_e := public.resume_dating_mode('w1d-lock-resume-0001');
  v_got := v_got || '/' || v_e.state;
  PERFORM pg_temp.as_user(v_exit);
  v_e := public.exit_dating_mode('w1d-lock-exit-0001');
  v_got := v_got || '/' || v_e.state;
  PERFORM pg_temp.as_user(v_wd);
  PERFORM public.record_dating_consent('w1d-lock-wd-0001', 'dating_terms', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF v_got IS DISTINCT FROM 'active/paused/active/exited'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_wd) IS DISTINCT FROM 'exited' THEN
    RAISE EXCEPTION 'fixture: the lifecycle calls did not run (%)', v_got;
  END IF;
  IF NOT pg_temp.holds_setup_lock(v_act) OR NOT pg_temp.holds_setup_lock(v_pause) OR NOT pg_temp.holds_setup_lock(v_res)
     OR NOT pg_temp.holds_setup_lock(v_exit) OR NOT pg_temp.holds_setup_lock(v_wd) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation, pause, resume, exit or a withdrawal ran without the person''s setup lock';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2d. Owner ruling 2 (PF-F3): withdrawing only the faith consent clears
--      the faith answer (as D8's Skip) and keeps the rest; it works while
--      the person is not eligible (no setup guard on removing one's own
--      answer).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_f constant uuid := pg_temp.direct('56', 'active', 'active'); -- rows written directly: no writer took the setup lock
  v_rows text;
  v_intro uuid;
  v_match uuid;
BEGIN
  UPDATE public.dating_profile_sensitive
     SET faith_enc = private.dating_field_encrypt('{"faith": "christian", "importance": "must_share"}')
   WHERE user_id = v_f;
  -- faith_visible already off, so no profile write ends the introductions:
  -- the withdrawal's own invalidation must (fix round 1, M-7).
  v_intro := pg_temp.intro(v_f, pg_temp.e2_person('87'));
  v_match := pg_temp.match(v_f, pg_temp.e2_person('88'));
  -- Not eligible (Dating switched off), with no other change to the person.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF public.dating_eligibility(v_f, 'setup') IS NOT DISTINCT FROM 'eligible' THEN
    RAISE EXCEPTION 'fixture: the faith person should not be eligible here';
  END IF;
  v_rows := concat_ws('|', (SELECT count(*) FROM public.dating_prompts WHERE user_id = v_f),
                           (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_f),
                           (SELECT encode(identity_enc, 'hex') || encode(seeking_enc, 'hex') FROM public.dating_profile_sensitive WHERE user_id = v_f));
  PERFORM pg_temp.as_user(v_f);
  PERFORM public.record_dating_consent('w1d-faith-withdraw-01', 'special_category_faith', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_f) IS DISTINCT FROM 'active'
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_f AND profile_state = 'active')
     OR concat_ws('|', (SELECT count(*) FROM public.dating_prompts WHERE user_id = v_f),
                       (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_f),
                       (SELECT encode(identity_enc, 'hex') || encode(seeking_enc, 'hex') FROM public.dating_profile_sensitive WHERE user_id = v_f))
        IS DISTINCT FROM v_rows THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing only the faith consent left Dating or touched other answers';
  END IF;
  IF (SELECT faith_enc FROM public.dating_profile_sensitive WHERE user_id = v_f) IS NOT NULL
     OR (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_f) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing the faith consent kept the faith answer';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_consent_events WHERE user_id = v_f AND purpose = 'special_category_faith'
                   AND action = 'withdrawn' AND idempotency_key = 'w1d-faith-withdraw-01')
     OR private.dating_consent_granted(v_f, 'special_category_faith') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the faith withdrawal was not recorded';
  END IF;
  IF NOT pg_temp.holds_setup_lock(v_f) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the faith withdrawal cleared the answer without the setup lock';
  END IF;
  IF (SELECT state FROM public.dating_introductions WHERE id = v_intro) IS DISTINCT FROM 'invalidated'
     OR (SELECT state FROM public.dating_matches WHERE id = v_match) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the faith withdrawal kept an open introduction (or closed a match)';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
END $$;

-- ---------------------------------------------------------------------
-- E2e. A NULL eligibility refuses activation and resume (NULL-blind sweep:
--      IS DISTINCT FROM, never <>); activation and resume re-run the
--      content filter on the name (B7 I-3/M-5: the legacy draft writer
--      sets an unfiltered name).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_n constant uuid := pg_temp.complete('69', 'woman', ARRAY['man']);
  v_r constant uuid := pg_temp.active('66', 'woman', ARRAY['man']);
  v_name constant uuid := pg_temp.complete('58', 'woman', ARRAY['man']);
  v_def text := pg_get_functiondef('public.dating_eligibility(uuid,text)'::regprocedure);
  v_got text[];
BEGIN
  PERFORM pg_temp.as_user(v_r);
  PERFORM public.pause_dating_mode('w1d-null-pause-0001');
  PERFORM pg_temp.as_owner();
  EXECUTE 'CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT ''candidate'') RETURNS text
           LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '''' AS $x$ SELECT NULL::text $x$';
  v_got := ARRAY[pg_temp.err_as(v_n, 'SELECT public.activate_dating_profile(''w1d-null-act-0001'')'),
                 pg_temp.err_as(v_r, 'SELECT public.resume_dating_mode(''w1d-null-res-0001'')')];
  EXECUTE v_def;
  IF v_got IS DISTINCT FROM ARRAY['activation_gates_not_met', 'resume_gates_not_met']
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_n) IS DISTINCT FROM 'profile_draft'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_r) IS DISTINCT FROM 'paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility let activation or resume through: %', v_got;
  END IF;
  -- The name: contact details in it refuse activation and resume.
  UPDATE public.dating_profiles SET display_name = 'Kofi 0244123456' WHERE user_id IN (v_name, v_r);
  v_got := ARRAY[pg_temp.err_as(v_name, 'SELECT public.activate_dating_profile(''w1d-name-act-0001'')'),
                 pg_temp.err_as(v_r, 'SELECT public.resume_dating_mode(''w1d-name-res-0001'')')];
  IF v_got IS DISTINCT FROM ARRAY['profile_or_preferences_incomplete', 'profile_or_preferences_incomplete'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name with contact details went live: %', v_got;
  END IF;
  UPDATE public.dating_profiles SET display_name = 'Kofi' WHERE user_id IN (v_name, v_r);
  v_got := ARRAY[pg_temp.err_as(v_name, 'SELECT public.activate_dating_profile(''w1d-name-act-0002'')'),
                 pg_temp.err_as(v_r, 'SELECT public.resume_dating_mode(''w1d-name-res-0002'')')];
  IF v_got IS DISTINCT FROM ARRAY[NULL, NULL]::text[]
     OR (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_name, v_r) AND state = 'active') IS DISTINCT FROM 2::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clean name was refused: %', v_got;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2f. The exclusion key's fingerprint (B2 I-5, B5 M-4): with none stored,
--      activation and generation refuse quietly and count it (no user path
--      seeds it); generation's order is flag, then mismatch, then
--      missing_key.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_u constant uuid := pg_temp.complete('86', 'woman', ARRAY['man']);
  v_fp constant text := (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key');
  v_before bigint;
  v_e public.dating_enrollments;
  v jsonb;
BEGIN
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  v_before := pg_temp.mismatch_count();
  PERFORM pg_temp.as_user(v_u);
  v_e := public.activate_dating_profile('w1d-unseeded-act-01');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'profile_draft' OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) IS DISTINCT FROM 'profile_draft'
     OR pg_temp.mismatch_count() IS DISTINCT FROM v_before + 1
     OR EXISTS (SELECT 1 FROM private.dating_key_fingerprints) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no stored fingerprint activation went ahead, was not counted or seeded it';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';
  v := jsonb_build_array(public.run_dating_candidate_generation(NULL));
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
  v_before := pg_temp.mismatch_count();
  v := v || jsonb_build_array(public.run_dating_candidate_generation(NULL));
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v := v || jsonb_build_array(public.run_dating_candidate_generation(NULL));
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';
  IF v IS DISTINCT FROM '[{"skipped": "flag_disabled"}, {"skipped": "exclusion_key_mismatch"}, {"skipped": "exclusion_key_mismatch"}]'::jsonb
     OR pg_temp.mismatch_count() IS DISTINCT FROM v_before + 2
     OR EXISTS (SELECT 1 FROM private.dating_key_fingerprints) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no stored fingerprint generation ran, was not counted, or the order is not flag, mismatch, missing_key: %', v;
  END IF;
  INSERT INTO private.dating_key_fingerprints (name, fingerprint) VALUES ('dating_exclusion_key', v_fp);
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the exclusion fingerprint was not restored';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2g. The field key's fingerprint (batch-6 M-5): the owner seeds it; a
--      replaced key is then refused everywhere it would write or run
--      (encrypt: field_key_missing, so writers answer unavailable and
--      store nothing; activation and generation refuse quietly, counted
--      dating.field_key.mismatch) instead of leaving mixed-key rows; in
--      production an unseeded key is refused too (development allows it:
--      contracts use transaction-local keys); health reports it.
-- ---------------------------------------------------------------------
CREATE FUNCTION pg_temp.field_mismatch_count() RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(count), 0)::bigint FROM public.metric_counters WHERE key = 'dating.field_key.mismatch';
$$;

DO $$
DECLARE
  v_key constant text := 'spec2-w1d-identity-field-key-0123456789abcdef';
  v_u constant uuid := pg_temp.complete('70', 'woman', ARRAY['man']);
  v_live text;
  v_before bigint;
  v_e public.dating_enrollments;
  v_snap text;
  v jsonb;
  v_msg text;
BEGIN
  -- Unseeded in development: usable, health says not seeded.
  IF private.dating_field_key_usable() IS NOT TRUE OR private.dating_field_key_ready() IS NOT FALSE
     OR (public.get_dating_operational_health() ->> 'field_key_fingerprint_ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unseeded development field key is not usable, or health calls it seeded';
  END IF;
  IF has_function_privilege('authenticated', 'private.seed_dating_field_key_fingerprint()', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.seed_dating_field_key_fingerprint()', 'EXECUTE')
     OR has_function_privilege('anon', 'private.seed_dating_field_key_fingerprint()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can seed the field key fingerprint';
  END IF;
  v_live := private.dating_field_key_fingerprint();
  IF v_live IS DISTINCT FROM encode(extensions.hmac('attune:dating_field_key:fingerprint:v1', v_key, 'sha256'), 'hex') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field key fingerprint is not the labelled HMAC of the live key';
  END IF;
  -- (The seed's write and the reads that check it are separate statements.)
  IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s seed did not answer ready';
  END IF;
  IF (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_field_key') IS DISTINCT FROM v_live
     OR private.dating_field_key_ready() IS NOT TRUE
     OR (public.get_dating_operational_health() ->> 'field_key_fingerprint_ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s seed did not make the field key ready';
  END IF;
  -- Replaced by another usable-length key.
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-rotated-field-key-0123456789abcdef', true);
  IF private.dating_field_key_usable() IS NOT FALSE OR private.dating_field_key_present() IS NOT TRUE
     OR private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'mismatch'
     OR (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_field_key') IS DISTINCT FROM v_live
     OR (public.get_dating_operational_health() ->> 'field_key_fingerprint_ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replaced field key is usable, or the seeder overwrote the fingerprint';
  END IF;
  BEGIN
    PERFORM private.dating_field_encrypt('{"x": 1}');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_field_encrypt wrote under a replaced key (%)', v_msg;
  END IF;
  v_snap := encode((SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'hex');
  PERFORM pg_temp.as_user(v_u);
  v := public.save_dating_identity('w1d-fk-d5-000001', 'woman', NULL, NULL, NULL, true);
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR encode((SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'hex') IS DISTINCT FROM v_snap THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced field key a writer stored a value or did not answer unavailable: %', v;
  END IF;
  v_before := pg_temp.field_mismatch_count();
  PERFORM pg_temp.as_user(v_u);
  v_e := public.activate_dating_profile('w1d-fk-act-00001');
  PERFORM pg_temp.as_owner();
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
  v := public.run_dating_candidate_generation(NULL);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';
  IF v_e.state IS DISTINCT FROM 'profile_draft' OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) IS DISTINCT FROM 'profile_draft'
     OR v IS DISTINCT FROM '{"skipped": "field_key_mismatch"}'::jsonb
     OR pg_temp.field_mismatch_count() IS DISTINCT FROM v_before + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced field key activation or generation went ahead or was not counted (%, %)', v_e.state, v;
  END IF;
  -- The original key matches again.
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seeded field key no longer matches';
  END IF;
  -- Production: the Vault key unseeded is refused; seeded, it works.
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_field_key';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', v_key);
  BEGIN
    PERFORM private.dating_field_encrypt('{"x": 1}');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' OR private.dating_field_key_usable() IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production an unseeded field key was used (%)', v_msg;
  END IF;
  IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production the field key could not be seeded';
  END IF;
  IF private.dating_field_decrypt(private.dating_field_encrypt('{"p": 2}')) IS DISTINCT FROM '{"p": 2}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in production a seeded field key does not work';
  END IF;
  DELETE FROM vault.secrets WHERE name = 'dating_field_key';
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_field_key';
  PERFORM set_config('app.settings.attune_environment', '', true);
  -- A 31-character key is no key: no fingerprint, nothing to seed.
  PERFORM set_config('app.settings.dating_field_key', repeat('k', 31), true);
  IF private.dating_field_key_fingerprint() IS NOT NULL OR private.dating_field_key_usable() IS NOT FALSE
     OR private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'missing_key' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 31-character field key has a fingerprint or can be seeded';
  END IF;
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints WHERE name = 'dating_field_key') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 31-character field key was seeded';
  END IF;
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
END $$;

-- ---------------------------------------------------------------------
-- E2h. Health v2 (carries): both fingerprints through STABLE comparisons
--      (never the counting mismatch()), and the safety counters.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v jsonb := public.get_dating_operational_health();
  v_fp constant text := (SELECT fingerprint FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key');
BEGIN
  IF NOT (v ?& ARRAY['exclusion_key_fingerprint_ok', 'field_key_fingerprint_ok', 'safety_counters_7d'])
     OR (v ->> 'exclusion_key_fingerprint_ok')::boolean IS NOT TRUE
     OR NOT (v -> 'safety_counters_7d' ?& ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch',
                                                 'dating.exclusion_key.unseeded', 'dating.eligibility.key_not_ready',
                                                 'dating.field_key.mismatch', 'dating.parked_pause.failed'])
     OR (v -> 'safety_counters_7d' ->> 'dating.exclusion_key.mismatch')::bigint IS DISTINCT FROM pg_temp.mismatch_count()
     OR (v -> 'safety_counters_7d' ->> 'dating.field_key.mismatch')::bigint IS DISTINCT FROM pg_temp.field_mismatch_count()
     OR (v -> 'safety_counters_7d' ->> 'dating.field_key.mismatch')::bigint < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health v2 lacks the fingerprints or the safety counters: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-rotated-key', true);
  IF (public.get_dating_operational_health() ->> 'exclusion_key_fingerprint_ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health calls a rotated exclusion key ok';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF (public.get_dating_operational_health() ->> 'exclusion_key_fingerprint_ok')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health calls an unseeded exclusion key ok';
  END IF;
  INSERT INTO private.dating_key_fingerprints (name, fingerprint) VALUES ('dating_exclusion_key', v_fp);
  IF EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.get_dating_operational_health()'::regprocedure
              AND (provolatile IS DISTINCT FROM 's' OR prosrc ~ 'dating_exclusion_key_mismatch')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health is not STABLE or calls the counting mismatch()';
  END IF;
END $$;
-- ---------------------------------------------------------------------
-- E2i. The device (§4.4, W1 B8 ruling): activation, resume and a consent
--      grant refuse an untrusted device; pause, exit and a withdrawal never
--      ask (removing data or exposure never needs it). The W1c pass-through
--      is stubbed to refuse inside this transaction, then restored.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_act constant uuid := pg_temp.direct('91', 'profile_draft', 'draft');
  v_res constant uuid := pg_temp.direct('92', 'paused', 'paused');
  v_pause constant uuid := pg_temp.direct('93', 'active', 'active');
  v_exit constant uuid := pg_temp.direct('94', 'active', 'active');
  v_wd constant uuid := pg_temp.direct('95', 'active', 'active');
  v_def constant text := pg_get_functiondef('public.dating_require_trusted_device()'::regprocedure);
  v_got text[];
BEGIN
  EXECUTE 'CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean
           LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '''' AS $x$ SELECT false $x$';
  v_got := ARRAY[
    pg_temp.err_as(v_act, 'SELECT public.activate_dating_profile(''w1d-dev-act-00001'')'),
    pg_temp.err_as(v_res, 'SELECT public.resume_dating_mode(''w1d-dev-res-00001'')'),
    pg_temp.err_as(v_act, 'SELECT public.record_dating_consent(''w1d-dev-grant-001'', ''dating_terms'', ''granted'', ''dating-2.0'', ''[]'')'),
    pg_temp.err_as(v_pause, 'SELECT public.pause_dating_mode(''w1d-dev-pause-001'')'),
    pg_temp.err_as(v_exit, 'SELECT public.exit_dating_mode(''w1d-dev-exit-0001'')'),
    pg_temp.err_as(v_wd, 'SELECT public.record_dating_consent(''w1d-dev-wd-00001'', ''dating_terms'', ''withdrawn'', ''dating-2.0'', ''[]'')')];
  EXECUTE v_def;
  IF v_got IS DISTINCT FROM ARRAY['reverify_device', 'reverify_device', 'reverify_device', NULL, NULL, NULL]::text[]
     OR (SELECT string_agg(state, '/' ORDER BY user_id) FROM public.dating_enrollments WHERE user_id IN (v_act, v_res, v_pause, v_exit, v_wd))
        IS DISTINCT FROM (SELECT string_agg(s, '/' ORDER BY u) FROM (VALUES (v_act, 'profile_draft'), (v_res, 'paused'), (v_pause, 'paused'),
                                                                     (v_exit, 'exited'), (v_wd, 'exited')) AS x(u, s)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device check is on the wrong lifecycle calls: %', v_got;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2j. Every completeness condition refuses on its own (each change undone
--      before the next); activation's and resume's other refusals; the
--      parked trigger never raises (a failing Dating write leaves the park
--      itself standing, with a WARNING).
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_u constant uuid := pg_temp.direct('96', 'profile_draft', 'draft');
  v_x constant uuid := pg_temp.direct('97', 'exited', 'draft');
  v_p constant uuid := pg_temp.direct('98', 'paused', 'paused');
  v_a constant uuid := pg_temp.direct('99', 'active', 'active');
  v_k constant uuid := pg_temp.direct('90', 'active', 'active');
  v_failed bigint;
  v_sql text;
  v_bad text[] := ARRAY[]::text[];
  v_got text[];
BEGIN
  FOREACH v_sql IN ARRAY ARRAY[
    format('UPDATE public.dating_profiles SET moderation_state = ''pending'' WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET verification_state = ''unverified'' WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET country_code = NULL, region_code = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET region_code = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET intention = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET not_married_attested_at = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET attestation_version = ''2025-01-v0'' WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET children_have = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profiles SET children_want = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profile_sensitive SET identity_enc = NULL WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profile_sensitive SET seeking_enc = NULL WHERE user_id = %L', v_u),
    format('DELETE FROM public.dating_profile_sensitive WHERE user_id = %L', v_u),
    format('DELETE FROM public.dating_preferences WHERE user_id = %L', v_u),
    format('UPDATE public.dating_age_verifications SET revoked_at = now() WHERE user_id = %L', v_u),
    format('UPDATE public.dating_profile_photos SET moderation_state = ''pending'' WHERE user_id = %L AND position = 2', v_u),
    format('UPDATE public.dating_prompts SET moderation_state = ''removed'' WHERE user_id = %L AND position = 2', v_u)] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'w1d-undo:%', public.dating_profile_complete(v_u);
    EXCEPTION
      WHEN raise_exception THEN
        IF SQLERRM IS DISTINCT FROM 'w1d-undo:f' THEN
          v_bad := v_bad || (SQLERRM || ' after ' || v_sql);
        END IF;
      WHEN check_violation THEN
        NULL; -- the table itself refuses that row (e.g. a region with no country)
    END;
  END LOOP;
  IF cardinality(v_bad) > 0 OR NOT public.dating_profile_complete(v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile missing one condition is still complete: %', v_bad;
  END IF;
  -- Activation: an exited enrolment (enrollment_incomplete) and a revoked
  -- age check (gates, before completeness). Resume: not paused, and an
  -- incomplete paused profile.
  UPDATE public.dating_age_verifications SET revoked_at = now() WHERE user_id = v_a;
  DELETE FROM public.dating_prompts WHERE user_id = v_p AND position = 2;
  v_got := ARRAY[
    pg_temp.err_as(v_x, 'SELECT public.activate_dating_profile(''w1d-br-act-00001'')'),
    pg_temp.err_as(v_a, 'SELECT public.activate_dating_profile(''w1d-br-act-00002'')'),
    pg_temp.err_as(v_u, 'SELECT public.resume_dating_mode(''w1d-br-res-00001'')'),
    pg_temp.err_as(v_p, 'SELECT public.resume_dating_mode(''w1d-br-res-00002'')')];
  IF v_got IS DISTINCT FROM ARRAY['enrollment_incomplete', 'activation_gates_not_met', 'not_paused', 'profile_or_preferences_incomplete'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation or resume skipped a refusal: %', v_got;
  END IF;
  -- The parked trigger never raises: a Dating write that fails is a WARNING
  -- and the park stands.
  IF NOT public.dating_profile_ready(v_k) THEN
    RAISE EXCEPTION 'fixture: the park test''s person is not ready';
  END IF;
  v_failed := (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.parked_pause.failed');
  EXECUTE 'CREATE FUNCTION public.w1d_contract_refuse() RETURNS trigger LANGUAGE plpgsql AS $x$
           BEGIN RAISE EXCEPTION ''w1d-contract-refused''; END $x$';
  EXECUTE 'CREATE TRIGGER w1d_contract_refuse BEFORE UPDATE ON public.dating_enrollments
           FOR EACH ROW EXECUTE FUNCTION public.w1d_contract_refuse()';
  BEGIN
    UPDATE public.users SET phone_released_at = now() WHERE id = v_k;
  EXCEPTION WHEN OTHERS THEN
    v_bad := ARRAY[SQLERRM];
  END;
  EXECUTE 'DROP TRIGGER w1d_contract_refuse ON public.dating_enrollments';
  EXECUTE 'DROP FUNCTION public.w1d_contract_refuse()';
  IF cardinality(v_bad) > 0 OR (SELECT phone_released_at FROM public.users WHERE id = v_k) IS NULL
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_k) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked trigger raised into the park (or wrote half): %', v_bad;
  END IF;
  IF public.dating_profile_ready(v_k)
     OR (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.parked_pause.failed') IS DISTINCT FROM v_failed + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account whose pause failed is still ready, or the failure was not counted';
  END IF;
END $$;
-- ---------------------------------------------------------------------
-- E2k. (Batch-10 fix round 1) I-1: activation, resume and readiness need
--      the standing D4 consents; exit withdraws every standing consent, so
--      re-entering needs D4 again (a fresh opt-in included). M-2: a second
--      exit rewrites nothing. M-3: a reused consent key is refused. M-4: a
--      paused draft goes through activation. M-8: exit while restricted
--      can't be used to start again. M-1: a development key in Vault is
--      held to its fingerprint.
-- ---------------------------------------------------------------------
-- [p_u]'s profile rows again (exit deleted them), as the setup writers
-- would leave them; the enrolment back in profile_draft (ensure_profile).
CREATE FUNCTION pg_temp.rebuild(p_u uuid, p_n text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.dating_enrollments SET state = 'profile_draft', exited_at = NULL WHERE user_id = p_u;
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state, verification_state, profile_state,
                                      country_code, region_code, intention, not_married_attested_at, attestation_version,
                                      children_have, children_want)
  VALUES (p_u, 'Person ' || p_n, 'approved', 'verified', 'draft', 'GB', 'TLI', 'committed', now(), '2026-10-v1', false, 'yes');
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (p_u, private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}'),
          private.dating_field_encrypt('{"seeking": ["man"]}'));
  INSERT INTO public.dating_preferences (user_id, min_age, max_age) VALUES (p_u, 25, 40);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES
    (p_u, 1, 'perfect_sunday', 'A long walk by the river.'), (p_u, 2, 'ask_me_about', 'The book I am reading now.');
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (p_u, 'w1d/' || p_n || '-r1.jpg', 1, 'approved'), (p_u, 'w1d/' || p_n || '-r2.jpg', 2, 'approved');
END $$;

DO $$
DECLARE
  v_none constant uuid := pg_temp.direct('80', 'profile_draft', 'draft');
  v_wd constant uuid := pg_temp.direct('81', 'profile_draft', 'draft');
  v_re constant uuid := pg_temp.direct('82', 'active', 'active');
  v_draft constant uuid := pg_temp.direct('83', 'profile_draft', 'draft');
  v_rs constant uuid := pg_temp.direct('84', 'active', 'active');
  v_pz constant uuid := pg_temp.direct('85', 'paused', 'paused');
  v_e public.dating_enrollments;
  v_got text[];
  v_at timestamptz;
  v_n bigint;
  v_c bigint;
  v jsonb;
BEGIN
  -- I-1 (a) no consent at all; (b) one withdrawn (written directly, so the
  -- withdrawal's own exit does not run).
  DELETE FROM public.dating_consent_events WHERE user_id = v_none;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_wd, 'w1d-direct-terms-withdrawn', 'dating_terms', 'withdrawn', 'dating-2.0', clock_timestamp());
  v_got := ARRAY[pg_temp.err_as(v_none, 'SELECT public.activate_dating_profile(''w1d-c-act-00001'')'),
                 pg_temp.err_as(v_wd, 'SELECT public.activate_dating_profile(''w1d-c-act-00002'')')];
  IF v_got IS DISTINCT FROM ARRAY['consent_required', 'consent_required']
     OR public.dating_profile_complete(v_none) OR public.dating_profile_complete(v_wd)
     OR (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_none, v_wd) AND state = 'active') IS DISTINCT FROM 0::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile without the standing D4 consents activated or is complete: %', v_got;
  END IF;

  -- I-1 (c) exit withdraws each standing consent once; re-entering needs D4
  -- again (the special-category writers need special_category_profile, and
  -- activation all three).
  v_c := (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.exit');
  PERFORM pg_temp.as_user(v_re);
  PERFORM public.exit_dating_mode('w1d-re-exit-00001');
  PERFORM pg_temp.as_owner();
  IF (SELECT count(*) FROM public.dating_consent_events WHERE user_id = v_re AND action = 'withdrawn') IS DISTINCT FROM 3::bigint
     OR private.dating_consent_granted(v_re, 'dating_terms') OR private.dating_consent_granted(v_re, 'dating_opt_in')
     OR private.dating_consent_granted(v_re, 'special_category_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit did not withdraw each standing consent exactly once';
  END IF;
  -- M-2: a second exit (a new key) rewrites nothing.
  -- (The first exit dated earlier: in one transaction now() never moves.)
  UPDATE public.dating_enrollments SET exited_at = now() - interval '3 days' WHERE user_id = v_re;
  v_at := (SELECT exited_at FROM public.dating_enrollments WHERE user_id = v_re);
  v_n := (SELECT count(*) FROM public.dating_consent_events WHERE user_id = v_re);
  PERFORM pg_temp.as_user(v_re);
  PERFORM public.exit_dating_mode('w1d-re-exit-00002');
  PERFORM public.record_dating_consent('w1d-re-withdraw-01', 'dating_opt_in', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF (SELECT exited_at FROM public.dating_enrollments WHERE user_id = v_re) IS DISTINCT FROM v_at
     OR (SELECT count(*) FROM public.dating_consent_events WHERE user_id = v_re) IS DISTINCT FROM v_n + 1
     OR (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.exit') IS DISTINCT FROM v_c + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second exit rewrote when the person left, wrote a second record or counted twice';
  END IF;
  -- Back through setup (rows rebuilt directly) with only two of the three
  -- consents granted again: activation still refuses.
  PERFORM pg_temp.rebuild(v_re, '82');
  PERFORM pg_temp.as_user(v_re);
  PERFORM public.record_dating_consent('w1d-re-terms-0001', 'dating_terms', 'granted', 'dating-2.0', '[]');
  PERFORM public.record_dating_consent('w1d-re-profile-01', 'special_category_profile', 'granted', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF public.dating_profile_complete(v_re) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile is complete without a fresh opt-in after exit';
  END IF;
  v_got := ARRAY[pg_temp.err_as(v_re, 'SELECT public.activate_dating_profile(''w1d-re-act-00001'')')];
  PERFORM pg_temp.as_user(v_re);
  PERFORM public.record_dating_consent('w1d-re-optin-0001', 'dating_opt_in', 'granted', 'dating-2.0', '[]');
  v_e := public.activate_dating_profile('w1d-re-act-00002');
  PERFORM pg_temp.as_owner();
  IF v_got IS DISTINCT FROM ARRAY['consent_required'] OR v_e.state IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-entry activated without a fresh opt-in, or not with one (%, %)', v_got, v_e.state;
  END IF;

  -- M-3: a key used for one event is refused for another; exit's prefix
  -- is not a client's; a true replay still answers.
  v_got := ARRAY[
    pg_temp.err_as(v_draft, 'SELECT public.record_dating_consent(''w1d-reuse-key-01'', ''biometric_verification'', ''granted'', ''dating-2.0'', ''[]'')'),
    pg_temp.err_as(v_draft, 'SELECT public.record_dating_consent(''w1d-reuse-key-01'', ''biometric_verification'', ''granted'', ''dating-2.0'', ''[]'')'),
    pg_temp.err_as(v_draft, 'SELECT public.record_dating_consent(''w1d-reuse-key-01'', ''dating_terms'', ''withdrawn'', ''dating-2.0'', ''[]'')'),
    pg_temp.err_as(v_draft, 'SELECT public.record_dating_consent(''exit:dating_opt_in:abc'', ''dating_opt_in'', ''granted'', ''dating-2.0'', ''[]'')')];
  IF v_got IS DISTINCT FROM ARRAY[NULL, NULL, 'idempotency_key_reused', 'idempotency_key_invalid']::text[]
     OR private.dating_consent_granted(v_draft, 'dating_terms') IS NOT TRUE
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_draft) IS DISTINCT FROM 'profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reused consent key was taken (or a replay refused): %', v_got;
  END IF;

  -- M-4: a draft that was paused is never made live by resume.
  PERFORM pg_temp.as_user(v_draft);
  PERFORM public.pause_dating_mode('w1d-draft-pause-01');
  PERFORM pg_temp.as_owner();
  v_got := ARRAY[pg_temp.err_as(v_draft, 'SELECT public.resume_dating_mode(''w1d-draft-res-0001'')')];
  PERFORM pg_temp.as_user(v_draft);
  v_e := public.activate_dating_profile('w1d-draft-act-0001');
  PERFORM pg_temp.as_owner();
  IF v_got IS DISTINCT FROM ARRAY['activation_required'] OR v_e.state IS DISTINCT FROM 'active' OR v_e.activated_at IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume made a never-activated draft live (or activation then failed): %', v_got;
  END IF;

  -- I-1: resume needs the standing consents too (a withdrawal written
  -- directly, so its own exit does not run).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_pz, 'w1d-direct-optin-withdrawn', 'dating_opt_in', 'withdrawn', 'dating-2.0', clock_timestamp());
  v_got := ARRAY[pg_temp.err_as(v_pz, 'SELECT public.resume_dating_mode(''w1d-c-res-00001'')')];
  IF v_got IS DISTINCT FROM ARRAY['consent_required'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume went ahead without the standing consents: %', v_got;
  END IF;

  -- M-8: restricted, then exit: the restriction stays and setup can't start again.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_rs, 'suspended');
  PERFORM pg_temp.as_user(v_rs);
  v_e := public.exit_dating_mode('w1d-rs-exit-00001');
  v := public.save_dating_intention('w1d-rs-d2-000001', 'committed', NULL, true, true, NULL, false);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions WHERE user_id = v_rs AND lifted_at IS NULL)
     OR public.dating_eligibility(v_rs, 'setup') IS DISTINCT FROM 'account_unavailable'
     OR v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_rs) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exiting while restricted let the person start again (%; %)', v_e.state, v;
  END IF;

  -- M-1: in development a field key in Vault is held to its fingerprint
  -- (a hosted project flips to production in place); a GUC key is not.
  IF private.dating_field_key_usable() IS NOT TRUE THEN
    RAISE EXCEPTION 'fixture: the contract''s GUC field key is not usable';
  END IF;
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef');
  IF private.dating_field_key_usable() IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unseeded Vault field key is usable in development';
  END IF;
  DELETE FROM vault.secrets WHERE name = 'dating_field_key';
END $$;
-- ---------------------------------------------------------------------
-- E2l. (Batch-11 fix round 1, I-2, M-7) Leaving during a kill switch: a
--      deadlock, a lock timeout or a serialization failure in the hard
--      delete is retried, so exit completes; after three the error
--      surfaces and nothing is half done; another error is never retried.
--      (The hard delete is swapped for a stand-in that fails a set number
--      of times, all undone after.)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_a constant uuid := pg_temp.direct('72', 'active', 'active');
  v_b constant uuid := pg_temp.direct('73', 'active', 'active');
  v_c constant uuid := pg_temp.direct('74', 'active', 'active');
  v_e public.dating_enrollments;
  v_state text;
BEGIN
  BEGIN
    CREATE TEMP SEQUENCE w1d_exit_calls;
    ALTER FUNCTION private.dating_exit_internal(uuid, boolean) RENAME TO dating_exit_internal_w1d_real;
    CREATE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $w$
    BEGIN
      IF nextval('pg_temp.w1d_exit_calls') <= current_setting('w1d.fail_n')::bigint THEN
        RAISE EXCEPTION 'w1d: simulated failure' USING ERRCODE = current_setting('w1d.fail_code');
      END IF;
      PERFORM private.dating_exit_internal_w1d_real(p_user, p_keep_never_introduce);
    END $w$;

    PERFORM set_config('w1d.fail_n', '2', true);
    PERFORM set_config('w1d.fail_code', '40P01', true);
    PERFORM pg_temp.as_user(v_a);
    v_e := public.exit_dating_mode('w1d-retry-exit-0001');
    PERFORM pg_temp.as_owner();
    IF v_e.state IS DISTINCT FROM 'exited' OR currval('pg_temp.w1d_exit_calls') IS DISTINCT FROM 3::bigint
       OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_a) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: exit failed on two deadlocks instead of retrying (%; % calls)', v_e.state, currval('pg_temp.w1d_exit_calls');
    END IF;

    PERFORM set_config('w1d.fail_n', '3', true);
    PERFORM set_config('w1d.fail_code', '55P03', true);
    PERFORM setval('pg_temp.w1d_exit_calls', 1, false);
    v_state := NULL;
    PERFORM pg_temp.as_user(v_b);
    BEGIN
      v_e := public.exit_dating_mode('w1d-retry-exit-0002');
      v_state := 'returned';
    EXCEPTION WHEN lock_not_available THEN
      v_state := SQLSTATE || CASE WHEN SQLERRM = 'dating:busy' THEN '' ELSE ' (raw: ' || SQLERRM || ')' END; -- W1 final fix (I-1)
    END;
    PERFORM pg_temp.as_owner();
    IF v_state IS DISTINCT FROM '55P03' OR currval('pg_temp.w1d_exit_calls') IS DISTINCT FROM 3::bigint
       OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_b)
       OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_b) IS DISTINCT FROM 'active' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: three lock timeouts in exit did not surface, untouched (%; % calls)', v_state, currval('pg_temp.w1d_exit_calls');
    END IF;

    PERFORM set_config('w1d.fail_n', '9', true);
    PERFORM set_config('w1d.fail_code', '22012', true);
    PERFORM setval('pg_temp.w1d_exit_calls', 1, false);
    v_state := NULL;
    PERFORM pg_temp.as_user(v_c);
    BEGIN
      v_e := public.exit_dating_mode('w1d-retry-exit-0003');
      v_state := 'returned';
    EXCEPTION WHEN division_by_zero THEN
      v_state := SQLSTATE;
    END;
    PERFORM pg_temp.as_owner();
    IF v_state IS DISTINCT FROM '22012' OR currval('pg_temp.w1d_exit_calls') IS DISTINCT FROM 1::bigint THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: exit retried an error that is no lock conflict (%; % calls)', v_state, currval('pg_temp.w1d_exit_calls');
    END IF;
    RAISE EXCEPTION 'w1d:exit_retry_undo';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1d:exit_retry_undo' THEN
      RAISE;
    END IF;
  END;
  IF to_regprocedure('private.dating_exit_internal_w1d_real(uuid,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: section E2l was not undone';
  END IF;
END $$;


-- ---------------------------------------------------------------------
-- E2m. (W1 final fix, I-1, M-3) The shared lock order: every lifecycle
--      writer, a settings writer, never-introduce, the relationship
--      guard's pause, the parked trigger and the account-deletion trigger
--      take the person's same-gender locks (their Dating country and every
--      other country on their list, shared) with the setup lock, before any
--      row, so a kill switch (the same locks exclusive, first) and they
--      serialise. (private.dating_lock_same_gender is swapped for a
--      recorder that counts each country's lock in a sequence, which a
--      refusal's rollback doesn't undo; all undone after.)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_c text;
  v_u uuid;
  v_e public.dating_enrollments;
  v_bad text[] := ARRAY[]::text[];
  v_codes constant text[] := ARRAY['KE', 'UG', 'TZ', 'ZA', 'NG', 'SN', 'CM', 'RW', 'ET', 'MW', 'ZM', 'LS'];
  v_who text[] := ARRAY[]::text[];
BEGIN
  BEGIN
    FOREACH v_c IN ARRAY v_codes LOOP
      EXECUTE format('CREATE TEMP SEQUENCE w1ff_sg_%s', lower(v_c));
    END LOOP;
    ALTER FUNCTION private.dating_lock_same_gender(text) RENAME TO dating_lock_same_gender_w1ff_real;
    CREATE FUNCTION private.dating_lock_same_gender(p_country text) RETURNS void LANGUAGE plpgsql SET search_path = '' AS $w$
    BEGIN
      IF to_regclass('pg_temp.w1ff_sg_' || lower(coalesce(p_country, 'xx'))) IS NOT NULL THEN
        PERFORM nextval(('pg_temp.w1ff_sg_' || lower(p_country))::regclass);
      END IF;
      PERFORM private.dating_lock_same_gender_w1ff_real(p_country);
    END $w$;
    -- One person per writer, each in a country nobody else here uses
    -- (written directly: no writer has locked it yet).
    FOREACH v_c IN ARRAY v_codes[1:11] LOOP
      v_u := pg_temp.direct(lpad((array_position(v_codes, v_c) + 30)::text, 2, '0'),
                            CASE v_c WHEN 'UG' THEN 'paused' WHEN 'TZ' THEN 'profile_draft' ELSE 'active' END,
                            CASE v_c WHEN 'UG' THEN 'paused' WHEN 'TZ' THEN 'draft' ELSE 'active' END);
      UPDATE public.dating_profiles SET country_code = v_c WHERE user_id = v_u;
      v_who := v_who || v_u::text;
    END LOOP;
    UPDATE public.dating_preferences SET open_abroad = ARRAY['LS']::char(2)[] WHERE user_id = v_who[1]::uuid;
    UPDATE public.dating_profile_sensitive SET faith_enc = private.dating_field_encrypt('{"faith": "christian"}') WHERE user_id = v_who[6]::uuid;
    -- Refusals still took the locks first (resume and activation refuse:
    -- those countries are closed).
    PERFORM pg_temp.as_user(v_who[1]::uuid);
    v_e := public.pause_dating_mode('w1ff-lock-pause-01');
    PERFORM pg_temp.as_user(v_who[2]::uuid);
    BEGIN v_e := public.resume_dating_mode('w1ff-lock-resume-01'); EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    PERFORM pg_temp.as_user(v_who[3]::uuid);
    BEGIN v_e := public.activate_dating_profile('w1ff-lock-activate-1'); EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
    PERFORM pg_temp.as_user(v_who[4]::uuid);
    v_e := public.exit_dating_mode('w1ff-lock-exit-0001');
    PERFORM pg_temp.as_user(v_who[5]::uuid);
    PERFORM public.record_dating_consent('w1ff-lock-wd-00001', 'dating_opt_in', 'withdraw', 'dating-2.0', NULL);
    PERFORM pg_temp.as_user(v_who[6]::uuid);
    PERFORM public.record_dating_consent('w1ff-lock-wd-00002', 'special_category_faith', 'withdraw', 'dating-2.0', NULL);
    PERFORM pg_temp.as_owner();
    PERFORM public.pause_dating_for_relationship_user(v_who[7]::uuid);
    UPDATE public.users SET phone_released_at = now() WHERE id = v_who[8]::uuid;
    DELETE FROM auth.users WHERE id = v_who[9]::uuid;
    PERFORM pg_temp.as_user(v_who[10]::uuid);
    PERFORM public.save_dating_settings('w1ff-lock-set-0001', '{"data_saver": true}');
    PERFORM pg_temp.as_user(v_who[11]::uuid);
    PERFORM public.add_dating_never_introduce('w1ff-lock-ni-00001', '+447700900123', NULL);
    PERFORM pg_temp.as_owner();
    FOREACH v_c IN ARRAY v_codes LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname LIKE 'pg_temp%' AND sequencename = 'w1ff_sg_' || lower(v_c)
                        AND last_value IS NOT NULL) THEN
        v_bad := v_bad || (v_c || CASE array_position(v_codes, v_c)
          WHEN 1 THEN ' (pause)' WHEN 2 THEN ' (resume)' WHEN 3 THEN ' (activation)' WHEN 4 THEN ' (exit)'
          WHEN 5 THEN ' (opt-in withdrawal)' WHEN 6 THEN ' (faith withdrawal)' WHEN 7 THEN ' (relationship pause)'
          WHEN 8 THEN ' (parked trigger)' WHEN 9 THEN ' (deletion trigger)' WHEN 10 THEN ' (settings)'
          WHEN 11 THEN ' (never-introduce)' ELSE ' (pause: the other-countries list)' END);
      END IF;
    END LOOP;
    IF cardinality(v_bad) > 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: these took no shared same-gender lock of the person''s country first: %', array_to_string(v_bad, ', ');
    END IF;
    RAISE EXCEPTION 'w1ff:lock_undo';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1ff:lock_undo' THEN
      RAISE;
    END IF;
  END;
  IF to_regprocedure('private.dating_lock_same_gender_w1ff_real(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: section E2m was not undone';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2m2. (W1 final fix, I-1) A writer that adds a country takes its lock in
--      the same sorted pass as the person's own (never later, out of
--      order, which could deadlock with a global switch taking every
--      country exclusive in code order): D3's new country and other
--      countries' new list. (The recorder notes the order in which each
--      country's lock is first taken; all undone after.)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_c text;
  v_abroad uuid;
  v_mover uuid;
  v_order jsonb;
BEGIN
  BEGIN
    CREATE TEMP SEQUENCE w1ff_order;
    FOREACH v_c IN ARRAY ARRAY['mz', 'bw', 'na', 'bi'] LOOP
      EXECUTE format('CREATE TEMP SEQUENCE w1ff_o_%s', v_c);
    END LOOP;
    ALTER FUNCTION private.dating_lock_same_gender(text) RENAME TO dating_lock_same_gender_w1ff_real;
    CREATE FUNCTION private.dating_lock_same_gender(p_country text) RETURNS void LANGUAGE plpgsql SET search_path = '' AS $w$
    BEGIN
      IF to_regclass('pg_temp.w1ff_o_' || lower(coalesce(p_country, 'xx'))) IS NOT NULL
         AND (SELECT s.last_value FROM pg_catalog.pg_sequences AS s
               WHERE s.schemaname LIKE 'pg_temp%' AND s.sequencename = 'w1ff_o_' || lower(p_country)) IS NULL THEN
        PERFORM setval(('pg_temp.w1ff_o_' || lower(p_country))::regclass, nextval('pg_temp.w1ff_order'));
      END IF;
      PERFORM private.dating_lock_same_gender_w1ff_real(p_country);
    END $w$;
    v_abroad := pg_temp.direct('42', 'active', 'active');
    UPDATE public.dating_profiles SET country_code = 'MZ' WHERE user_id = v_abroad;
    v_mover := pg_temp.direct('43', 'active', 'active');
    UPDATE public.dating_profiles SET country_code = 'NA' WHERE user_id = v_mover;
    PERFORM pg_temp.as_user(v_abroad);
    PERFORM public.set_dating_open_abroad('w1ff-order-ab-0001', ARRAY['BW']::char(2)[]);
    PERFORM pg_temp.as_user(v_mover);
    PERFORM public.save_dating_location('w1ff-order-d3-0001', 'BI', 'BM', NULL, 'region');
    PERFORM pg_temp.as_owner();
    SELECT jsonb_object_agg(replace(s.sequencename, 'w1ff_o_', ''), s.last_value) INTO v_order
      FROM pg_catalog.pg_sequences AS s WHERE s.schemaname LIKE 'pg_temp%' AND s.sequencename LIKE 'w1ff_o_%';
    IF coalesce((v_order ->> 'bw')::bigint < (v_order ->> 'mz')::bigint, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: other countries'' new list was locked after the person''s own country (%)', v_order;
    END IF;
    IF coalesce((v_order ->> 'bi')::bigint < (v_order ->> 'na')::bigint, false) IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: D3''s new country was locked after the old one (%)', v_order;
    END IF;
    RAISE EXCEPTION 'w1ff:order_undo';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1ff:order_undo' THEN
      RAISE;
    END IF;
  END;
  IF to_regprocedure('private.dating_lock_same_gender_w1ff_real(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: section E2m2 was not undone';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2n. (W1 final fix, I-1, M-3) Nothing a person does is lost to a kill
--      switch: pause, a consent withdrawal (leaving, and the faith one),
--      resume, activation, D3, the relationship guard's pause, the
--      invalidation every profile change runs, and the parked trigger
--      retry a deadlock, a lock timeout or a serialization failure up to
--      three times, each attempt its own savepoint; the third surfaces as
--      dating:busy with the SQLSTATE (never the raw DETAIL) and nothing is
--      half done; the parked trigger counts it instead (Spec 1's park never
--      fails); any other error is never retried. (A BEFORE trigger fails a
--      set number of times on the named table and operation; all undone.)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_u uuid;
  v_e public.dating_enrollments;
  v_got text;
  v_n integer := 7; -- ids 08-29 (free)
  v_bad text[] := ARRAY[]::text[];
  v_i uuid;
  r record;
BEGIN
  BEGIN
    CREATE TEMP SEQUENCE w1ff_fail_calls;
    CREATE FUNCTION public.w1ff_fail() RETURNS trigger LANGUAGE plpgsql AS $w$
    BEGIN
      IF current_setting('w1ff.target', true) = TG_TABLE_NAME || ':' || TG_OP
         AND nextval('pg_temp.w1ff_fail_calls') <= current_setting('w1ff.fail_n')::bigint THEN
        RAISE EXCEPTION 'w1ff: simulated failure' USING ERRCODE = current_setting('w1ff.fail_code');
      END IF;
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END $w$;
    CREATE TRIGGER zz_w1ff_fail BEFORE UPDATE OR DELETE ON public.dating_profiles FOR EACH ROW EXECUTE FUNCTION public.w1ff_fail();
    CREATE TRIGGER zz_w1ff_fail BEFORE UPDATE OR DELETE ON public.dating_profile_sensitive FOR EACH ROW EXECUTE FUNCTION public.w1ff_fail();
    CREATE TRIGGER zz_w1ff_fail BEFORE UPDATE ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w1ff_fail();
    CREATE TRIGGER zz_w1ff_fail BEFORE UPDATE ON public.dating_introductions FOR EACH ROW EXECUTE FUNCTION public.w1ff_fail();

    -- Each case: (writer, target, how many failures, which SQLSTATE) ->
    -- what must hold after. [the call] runs as the person in its own block.
    CREATE TEMP TABLE w1ff_cases (k int, writer text, target text, n int, code text, want text) ON COMMIT DROP;
    INSERT INTO w1ff_cases VALUES
      (1, 'pause', 'dating_profiles:UPDATE', 2, '40P01', 'done'),
      (2, 'pause', 'dating_profiles:UPDATE', 3, '55P03', 'busy'),
      (3, 'pause', 'dating_profiles:UPDATE', 1, '22012', 'raw'),
      (4, 'withdraw', 'dating_profile_sensitive:DELETE', 2, '40P01', 'done'),
      (5, 'withdraw', 'dating_profile_sensitive:DELETE', 3, '55P03', 'busy'),
      (6, 'faith', 'dating_profile_sensitive:UPDATE', 2, '40001', 'done'),
      (7, 'faith', 'dating_profile_sensitive:UPDATE', 3, '40P01', 'busy'),
      (8, 'resume', 'dating_profiles:UPDATE', 2, '40P01', 'done'),
      (9, 'resume', 'dating_profiles:UPDATE', 3, '55P03', 'busy'),
      (10, 'activate', 'dating_profiles:UPDATE', 2, '40P01', 'done'),
      (11, 'activate', 'dating_profiles:UPDATE', 3, '55P03', 'busy'),
      (12, 'd3', 'dating_profiles:UPDATE', 2, '40P01', 'done'),
      (13, 'd3', 'dating_profiles:UPDATE', 3, '55P03', 'busy'),
      (14, 'relationship', 'dating_profiles:UPDATE', 2, '40P01', 'done'),
      (15, 'relationship', 'dating_profiles:UPDATE', 3, '55P03', 'busy'),
      (16, 'invalidate', 'dating_introductions:UPDATE', 2, '40P01', 'done'),
      (17, 'invalidate', 'dating_introductions:UPDATE', 3, '55P03', 'busy'),
      (18, 'parked', 'dating_enrollments:UPDATE', 2, '40P01', 'done'),
      (19, 'parked', 'dating_enrollments:UPDATE', 3, '55P03', 'counted'),
      -- N-M3: an inner retry (the invalidation's) is never retried again by
      -- its caller: at most three attempts in all, then dating:busy.
      (20, 'faith', 'dating_introductions:UPDATE', 9, '40P01', 'busy'),
      (21, 'relationship', 'dating_introductions:UPDATE', 9, '40P01', 'busy');
    FOR r IN SELECT * FROM w1ff_cases ORDER BY k LOOP
      v_n := v_n + 1;
      v_u := pg_temp.direct(lpad(v_n::text, 2, '0'), CASE r.writer WHEN 'resume' THEN 'paused' WHEN 'activate' THEN 'profile_draft' ELSE 'active' END,
                                       CASE r.writer WHEN 'resume' THEN 'paused' WHEN 'activate' THEN 'draft' ELSE 'active' END);
      IF r.writer = 'faith' THEN
        UPDATE public.dating_profile_sensitive SET faith_enc = private.dating_field_encrypt('{"faith": "christian"}') WHERE user_id = v_u;
        INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
        VALUES (v_u, 'w1ff-faith-' || v_n, 'special_category_faith', 'granted', 'dating-2.0', clock_timestamp());
      END IF;
      v_i := CASE WHEN r.writer = 'invalidate' OR r.target = 'dating_introductions:UPDATE' THEN pg_temp.intro(v_u, pg_temp.id('05')) END;
      PERFORM set_config('w1ff.target', r.target, true);
      PERFORM set_config('w1ff.fail_n', r.n::text, true);
      PERFORM set_config('w1ff.fail_code', r.code, true);
      PERFORM setval('pg_temp.w1ff_fail_calls', 1, false);
      BEGIN
        IF r.writer = 'pause' THEN
          PERFORM pg_temp.as_user(v_u); v_e := public.pause_dating_mode('w1ff-retry-' || r.k || '-0001');
        ELSIF r.writer = 'withdraw' THEN
          PERFORM pg_temp.as_user(v_u); PERFORM public.record_dating_consent('w1ff-retry-' || r.k || '-0001', 'dating_opt_in', 'withdraw', 'dating-2.0', NULL);
        ELSIF r.writer = 'faith' THEN
          PERFORM pg_temp.as_user(v_u); PERFORM public.record_dating_consent('w1ff-retry-' || r.k || '-0001', 'special_category_faith', 'withdraw', 'dating-2.0', NULL);
        ELSIF r.writer = 'resume' THEN
          PERFORM pg_temp.as_user(v_u); v_e := public.resume_dating_mode('w1ff-retry-' || r.k || '-0001');
        ELSIF r.writer = 'activate' THEN
          PERFORM pg_temp.as_user(v_u); v_e := public.activate_dating_profile('w1ff-retry-' || r.k || '-0001');
        ELSIF r.writer = 'd3' THEN
          PERFORM pg_temp.as_user(v_u); PERFORM public.save_dating_location('w1ff-retry-' || r.k || '-0001', 'GB', 'TLD', NULL, 'region');
        ELSIF r.writer = 'relationship' THEN
          PERFORM public.pause_dating_for_relationship_user(v_u);
        ELSIF r.writer = 'invalidate' THEN
          PERFORM public.invalidate_dating_for_user(v_u, 'profile_or_preference_changed');
        ELSIF r.writer = 'parked' THEN
          UPDATE public.users SET phone_released_at = now() WHERE id = v_u;
        END IF;
        v_got := 'returned';
      EXCEPTION WHEN OTHERS THEN
        v_got := SQLSTATE || '/' || SQLERRM;
      END;
      PERFORM pg_temp.as_owner();
      PERFORM set_config('w1ff.target', '', true);
      -- What must hold.
      IF r.want = 'done' AND (v_got IS DISTINCT FROM 'returned' OR currval('pg_temp.w1ff_fail_calls') < 3 OR NOT CASE r.writer
           WHEN 'pause' THEN (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_u) = 'paused/user'
           WHEN 'withdraw' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'exited'
                                AND NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u)
           WHEN 'faith' THEN (SELECT faith_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
           WHEN 'resume' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'active'
           WHEN 'activate' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'active'
           WHEN 'd3' THEN (SELECT region_code FROM public.dating_profiles WHERE user_id = v_u) = 'TLD'
           WHEN 'relationship' THEN (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_u) = 'paused/relationship'
           WHEN 'invalidate' THEN (SELECT state FROM public.dating_introductions WHERE id = v_i) = 'invalidated'
           WHEN 'parked' THEN (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_u) = 'paused/account_parked'
           END) THEN
        v_bad := v_bad || format('case %s (%s, %s x %s): not done after the retries (%s; %s calls)', r.k, r.writer, r.code, r.n, v_got,
                                 currval('pg_temp.w1ff_fail_calls'));
      ELSIF r.want = 'busy' AND (v_got IS DISTINCT FROM r.code || '/dating:busy' OR currval('pg_temp.w1ff_fail_calls') IS DISTINCT FROM 3::bigint
           OR NOT CASE r.writer
           WHEN 'pause' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'active'
                             AND (SELECT profile_state FROM public.dating_profiles WHERE user_id = v_u) = 'active'
           WHEN 'withdraw' THEN EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u)
                                AND private.dating_consent_granted(v_u, 'dating_opt_in')
           WHEN 'faith' THEN (SELECT faith_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
           WHEN 'resume' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'paused'
           WHEN 'activate' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'profile_draft'
           WHEN 'd3' THEN (SELECT region_code FROM public.dating_profiles WHERE user_id = v_u) = 'TLI'
           WHEN 'relationship' THEN (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) = 'active'
           WHEN 'invalidate' THEN (SELECT state FROM public.dating_introductions WHERE id = v_i) = 'presented'
           END) THEN
        v_bad := v_bad || format('case %s (%s, %s x %s): not dating:busy with nothing done (%s; %s calls)', r.k, r.writer, r.code, r.n, v_got,
                                 currval('pg_temp.w1ff_fail_calls'));
      ELSIF r.want = 'raw' AND (v_got IS DISTINCT FROM r.code || '/w1ff: simulated failure' OR currval('pg_temp.w1ff_fail_calls') IS DISTINCT FROM 1::bigint) THEN
        v_bad := v_bad || format('case %s (%s): an error that is no lock conflict was retried or changed (%s; %s calls)', r.k, r.writer, v_got,
                                 currval('pg_temp.w1ff_fail_calls'));
      ELSIF r.want = 'counted' AND (v_got IS DISTINCT FROM 'returned' OR currval('pg_temp.w1ff_fail_calls') IS DISTINCT FROM 3::bigint
           OR (SELECT phone_released_at FROM public.users WHERE id = v_u) IS NULL
           OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) IS DISTINCT FROM 'active') THEN
        v_bad := v_bad || format('case %s (parked): three lock timeouts blocked the park or half-paused (%s; %s calls)', r.k, v_got,
                                 currval('pg_temp.w1ff_fail_calls'));
      END IF;
    END LOOP;
    IF cardinality(v_bad) > 0 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: %', array_to_string(v_bad, E'\n  ');
    END IF;
    RAISE EXCEPTION 'w1ff:retry_undo';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1ff:retry_undo' THEN
      RAISE;
    END IF;
  END;
  IF to_regprocedure('public.w1ff_fail()') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: section E2n was not undone';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2o. (W1 final fix, M-1) Resume repeats activation's quiet field-key
--      gate: under a replaced field key it returns the enrolment
--      unchanged (still paused), counted dating.field_key.mismatch.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_key constant text := 'spec2-w1d-identity-field-key-0123456789abcdef';
  v_u constant uuid := pg_temp.direct('48', 'paused', 'paused');
  v_e public.dating_enrollments;
  v_before bigint;
BEGIN
  BEGIN
    IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
      RAISE EXCEPTION 'fixture: E2o could not seed the field key';
    END IF;
    PERFORM set_config('app.settings.dating_field_key', 'spec2-w1final-rotated-field-key-0123456789', true);
    v_before := pg_temp.field_mismatch_count();
    PERFORM pg_temp.as_user(v_u);
    v_e := public.resume_dating_mode('w1ff-resume-fk-0001');
    PERFORM pg_temp.as_owner();
    IF v_e.state IS DISTINCT FROM 'paused' OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_u) IS DISTINCT FROM 'paused'
       OR pg_temp.field_mismatch_count() IS DISTINCT FROM v_before + 1 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: resume went ahead under a replaced field key, or was not counted (%)', v_e.state;
    END IF;
    RAISE EXCEPTION 'w1ff:resume_fk_undo';
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    IF SQLERRM IS DISTINCT FROM 'w1ff:resume_fk_undo' THEN
      RAISE;
    END IF;
  END;
  IF current_setting('app.settings.dating_field_key', true) IS DISTINCT FROM v_key
     OR EXISTS (SELECT 1 FROM private.dating_key_fingerprints WHERE name = 'dating_field_key') THEN
    RAISE EXCEPTION 'fixture: section E2o was not undone';
  END IF;
  -- With the key usable, the same person resumes.
  PERFORM pg_temp.as_user(v_u);
  v_e := public.resume_dating_mode('w1ff-resume-fk-0002');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume refused a usable field key (%)', v_e.state;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- E2p. (W1 final fix, M-8) A restriction never moves to another account
--      (its stamp is the first account's number); its other columns still
--      change. (M-9) The v1 draft writer is no signed-in user's.
--      (M-4) Health counts a failed carry at prepare and at the delete, and
--      the deletions refused for a missing key in the last 7 days.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_a constant uuid := pg_temp.e2_person('46');
  v_b constant uuid := pg_temp.e2_person('47');
  v_r uuid;
  v_msg text;
  v_h jsonb;
BEGIN
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_a, 'moderation_hold') RETURNING id INTO v_r;
  BEGIN
    UPDATE public.dating_account_restrictions SET user_id = v_b WHERE id = v_r;
    v_msg := 'moved';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:restriction_user_immutable'
     OR (SELECT user_id FROM public.dating_account_restrictions WHERE id = v_r) IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction moved to another account (%)', v_msg;
  END IF;
  UPDATE public.dating_account_restrictions SET user_id = v_a, ends_at = now() + interval '1 day' WHERE id = v_r;
  IF (SELECT ends_at FROM public.dating_account_restrictions WHERE id = v_r) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restriction''s other columns no longer change';
  END IF;

  v_msg := pg_temp.err_as(v_a, 'SELECT public.save_dating_profile_draft(''w1ff-v1-draft-01'', ''Ama'', ''AA'', ''committed'', NULL, 25, 35)');
  IF v_msg IS DISTINCT FROM 'permission denied for function save_dating_profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can still run the v1 draft writer (%)', v_msg;
  END IF;
  -- N-I1: no client can start a Dating upload: both v1 photo writers are
  -- refused, no client can write an upload intent, and no function a client
  -- can run writes one (the bucket's INSERT policy needs an intent).
  v_msg := pg_temp.err_as(v_a, 'SELECT * FROM public.create_dating_photo_upload_intent(''image/jpeg'')');
  IF v_msg IS DISTINCT FROM 'permission denied for function create_dating_photo_upload_intent' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can still create a Dating upload intent (%)', v_msg;
  END IF;
  v_msg := pg_temp.err_as(v_a, format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', gen_random_uuid()));
  IF v_msg IS DISTINCT FROM 'permission denied for function insert_dating_profile_photo' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can still attach a Dating photo (%)', v_msg;
  END IF;
  IF has_table_privilege('authenticated', 'public.dating_photo_upload_intents', 'INSERT')
     OR has_table_privilege('anon', 'public.dating_photo_upload_intents', 'INSERT')
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname IN ('public', 'private') AND p.prosrc ~* 'insert\s+into\s+public\.dating_photo_upload_intents'
                   AND (has_function_privilege('authenticated', p.oid, 'EXECUTE') OR has_function_privilege('anon', p.oid, 'EXECUTE'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can still write a Dating upload intent';
  END IF;

  INSERT INTO public.account_deletion_requests (user_ref, failure_reason, requested_at)
  VALUES (v_b, 'prepare: deletion:enforcement_key_missing', now() - interval '1 day'),
         (v_b, 'prepare: deletion:enforcement_key_missing', now() - interval '8 days'),
         (v_b, 'prepare: something else', now());
  v_h := public.get_dating_operational_health();
  IF NOT (v_h -> 'safety_counters_7d' ? 'dating.deletion.prepare_carry_failed')
     OR NOT (v_h -> 'safety_counters_7d' ? 'dating.deletion.late_carry_failed')
     OR (v_h ->> 'deletions_refused_key_missing_7d')::bigint IS DISTINCT FROM
        (SELECT count(*) FROM public.account_deletion_requests
          WHERE completed_at IS NULL AND requested_at >= now() - interval '7 days'
            AND failure_reason LIKE '%deletion:enforcement_key_missing%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not count failed carries and key-missing refusals: %', v_h;
  END IF;
  IF (v_h ->> 'deletions_refused_key_missing_7d')::bigint < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a key-missing refusal yesterday was not counted';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_identity_contracts: all held'; END $$;
ROLLBACK;
