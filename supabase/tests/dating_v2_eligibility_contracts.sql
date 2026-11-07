-- supabase/tests/dating_v2_eligibility_contracts.sql
-- Spec 2 W1b (and W2) (§2.1, §7.1, §7.5; I-14, A-10): dating_eligibility's
-- base gates 1-4 (A), its country and region gate 6 (B, from W1c, once
-- profiles carry a country), Spec 1's re-created home-summary seam (C) and
-- NULL-safety: no NULL answer ever counts as passing (D).
-- W2 adds the gentle wait, the shim and the path trigger.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql
-- Fixture ids 5e2c0000-0000-0000-0000-0000000000NN; phones 15558702NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-eligibility-key', true);
END $$;
-- Fix round 1 (I-1, M-4): the owner seeds the key's fingerprint; nobody is
-- eligible until it matches.
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An adult [p_n] who passes gates 1-4: a DOB 30 years ago, a confirmed
-- Auth phone, EULA v2, no relationship, nothing held.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558702' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558702' || p_n, 'Person ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.both(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT public.dating_eligibility(p_user, 'setup') || '/' || public.dating_eligibility(p_user);
$$;

-- =====================================================================
-- A. (W1b) Gates 1-4, in order; the default scope is 'candidate'.
-- =====================================================================
DO $$
DECLARE
  v_ok constant uuid := pg_temp.person('01');
  v_young constant uuid := pg_temp.person('02');
  v_nodob constant uuid := pg_temp.person('03');
  v_unconfirmed constant uuid := pg_temp.person('04');
  v_eula1 constant uuid := pg_temp.person('05');
  v_noeula constant uuid := pg_temp.person('06');
  v_restricted constant uuid := pg_temp.person('07');
  v_held constant uuid := pg_temp.person('08');
  v_coupled constant uuid := pg_temp.person('09');
  v_partner constant uuid := pg_temp.person('10');
  v_safety constant uuid := pg_temp.person('11');
  v_resolved constant uuid := pg_temp.person('12');
  v_recorded constant uuid := pg_temp.person('13');
  v_banned constant uuid := pg_temp.person('14');
  v_nohmac constant uuid := pg_temp.person('15');
  v_eighteen constant uuid := pg_temp.person('16');
  v_almost constant uuid := pg_temp.person('17');
  v_utc_today constant date := (now() AT TIME ZONE 'UTC')::date;
  v_count bigint;
  v_msg text;
BEGIN
  IF has_function_privilege('authenticated', 'public.dating_eligibility(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.dating_eligibility(uuid,text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_eligibility(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_eligibility is callable outside the database';
  END IF;

  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'feature_unavailable/feature_unavailable'
     OR pg_temp.both(v_young) IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with dating_mode_enabled off the first reason is not feature_unavailable';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  UPDATE public.account_birthdates SET birth_date = current_date - interval '17 years' WHERE user_id = v_young;
  DELETE FROM public.account_birthdates WHERE user_id = v_nodob;
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_unconfirmed;
  UPDATE public.users SET eula_version = '1' WHERE id = v_eula1;
  UPDATE public.users SET eula_accepted_at = NULL WHERE id = v_noeula;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_restricted, 'suspended');
  PERFORM public.place_account_hold(v_held, 'age_review', 'spec2-w1b-contract');
  PERFORM public.place_account_hold(v_safety, 'safety_review', 'spec2-w1b-contract');
  PERFORM public.place_account_hold(v_resolved, 'age_review', 'spec2-w1b-contract');
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'spec2-w1b-contract' WHERE user_id = v_resolved;
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_coupled, v_partner, 'active');

  IF pg_temp.both(v_ok) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an adult with no Dating country yet is % (expected eligible to set up, not a candidate)', pg_temp.both(v_ok);
  END IF;
  IF pg_temp.both(v_young) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_nodob) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 or undated account passed gate 2';
  END IF;
  IF pg_temp.both(v_unconfirmed) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed phone passed gate 2';
  END IF;
  IF pg_temp.both(v_eula1) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_noeula) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account without EULA v2 passed gate 2';
  END IF;
  IF pg_temp.both(v_restricted) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_held) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted or held account passed gate 3';
  END IF;
  -- Batch-5 ruling (Spec 1 hold semantics): either enforced hold kind makes
  -- the account ineligible, under the same generic reason (the hold kind
  -- never reaches the wire); a resolved hold no longer counts.
  IF pg_temp.both(v_safety) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety_review hold passed gate 3 (%)', pg_temp.both(v_safety);
  END IF;
  IF pg_temp.both(v_resolved) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold still gates Dating (%)', pg_temp.both(v_resolved);
  END IF;
  IF pg_temp.both(NULL) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL user is % (expected account_unavailable)', pg_temp.both(NULL);
  END IF;
  IF pg_temp.both(v_coupled) IS DISTINCT FROM 'relationship_active/relationship_active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account in a relationship is % (expected relationship_active)', pg_temp.both(v_coupled);
  END IF;
  -- First failing reason: an under-18 or restricted account in a
  -- relationship is account_unavailable.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_young, NULL, 'pending', 'W1BELIG1', now() + interval '1 day'),
         (v_restricted, NULL, 'pending', 'W1BELIG2', now() + interval '1 day');
  IF pg_temp.both(v_young) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_restricted) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gates are not checked in order';
  END IF;
  -- Fix round 1 (I-1): the enforcement-record leg of gate 3, an Auth ban,
  -- and a person whose own HMAC can't be computed although the key is set
  -- (their carried record can't be read, so they are not eligible).
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_recorded), 'dating', 'suspended', now() + interval '1 year'),
         (public.dating_phone_hmac_for_user(v_nohmac), 'dating', 'suspended', now() + interval '1 year');
  UPDATE auth.users SET phone = NULL WHERE id = v_nohmac;
  UPDATE auth.users SET banned_until = now() + interval '1 day' WHERE id = v_banned;
  IF public.dating_phone_hmac_for_user(v_nohmac) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture: the NULL-HMAC person has an HMAC';
  END IF;
  IF pg_temp.both(v_recorded) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried enforcement record passed gate 3 (%)', pg_temp.both(v_recorded);
  END IF;
  IF pg_temp.both(v_banned) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Auth ban passed gate 3 (%)', pg_temp.both(v_banned);
  END IF;
  IF pg_temp.both(v_nohmac) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person whose HMAC is NULL under a set key passed gate 3 (%)', pg_temp.both(v_nohmac);
  END IF;
  -- Fix round 1 (I-1, ruling): no key, a rotated key or an unseeded
  -- fingerprint: nobody is eligible, under the generic system reason
  -- (never a personal one), and each refusal is counted.
  v_count := (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.eligibility.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'feature_unavailable/feature_unavailable'
     OR pg_temp.both(v_nohmac) IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no exclusion key a person is % (expected feature_unavailable)', pg_temp.both(v_ok);
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-rotated-key', true);
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'feature_unavailable/feature_unavailable'
     OR pg_temp.both(v_recorded) IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a rotated exclusion key a person is % (expected feature_unavailable)', pg_temp.both(v_ok);
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-eligibility-key', true);
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no stored fingerprint a person is % (expected feature_unavailable)', pg_temp.both(v_ok);
  END IF;
  IF (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.eligibility.key_not_ready')
     IS DISTINCT FROM v_count + 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the key-not-ready refusals were not counted (% -> %)', v_count,
      (SELECT coalesce(sum(count), 0) FROM public.metric_counters WHERE key = 'dating.eligibility.key_not_ready');
  END IF;
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an eligibility check seeded the key fingerprint';
  END IF;
  PERFORM private.seed_dating_exclusion_key_fingerprint();
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the re-seeded key did not make the person eligible again (%)', pg_temp.both(v_ok);
  END IF;
  -- Fix round 1 (M-1): 18 on the UTC calendar day of the birthday
  -- (private.age_on_utc_today), not the day before.
  UPDATE public.account_birthdates SET birth_date = (v_utc_today - interval '18 years')::date WHERE user_id = v_eighteen;
  UPDATE public.account_birthdates SET birth_date = (v_utc_today - interval '18 years' + interval '1 day')::date WHERE user_id = v_almost;
  IF pg_temp.both(v_eighteen) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person on their 18th birthday is % (expected eligible to set up)', pg_temp.both(v_eighteen);
  END IF;
  IF pg_temp.both(v_almost) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person the day before their 18th birthday is %', pg_temp.both(v_almost);
  END IF;
  -- No Healing journey and no readiness score: Healing never gates Dating.
  IF EXISTS (SELECT 1 FROM public.healing_journeys WHERE user_id = v_ok) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture has a Healing journey';
  END IF;
  BEGIN
    PERFORM public.dating_eligibility(v_ok, 'browse');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown scope was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'eligibility:invalid_scope' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown scope raised %', v_msg;
    END IF;
  END;
END $$;

-- =====================================================================
-- B. (W1c) Gate 6: the profile's Dating country and region are open.
-- =====================================================================
DO $$
DECLARE
  v_accra constant uuid := pg_temp.person('20');
  v_volta constant uuid := pg_temp.person('21');
  v_lagos constant uuid := pg_temp.person('22');
  v_noregion constant uuid := pg_temp.person('23');
  v_london constant uuid := pg_temp.person('24');
BEGIN
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_accra, 'Accra', 'GH', 'AA'), (v_volta, 'Volta', 'GH', 'TV'), (v_lagos, 'Lagos', 'NG', NULL),
    (v_noregion, 'No region', 'GH', NULL), (v_london, 'London', 'GB', NULL);
  IF pg_temp.both(v_accra) IS DISTINCT FROM 'eligible/eligible' OR pg_temp.both(v_london) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open country and region failed gate 6 (%, %)', pg_temp.both(v_accra), pg_temp.both(v_london);
  END IF;
  IF pg_temp.both(v_volta) IS DISTINCT FROM 'region_closed/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed Ghana region is % (expected region_closed)', pg_temp.both(v_volta);
  END IF;
  IF pg_temp.both(v_lagos) IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country is % (expected country_closed)', pg_temp.both(v_lagos);
  END IF;
  IF pg_temp.both(v_noregion) IS DISTINCT FROM 'eligible/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana without a region yet is % (eligible to set up, not a candidate)', pg_temp.both(v_noregion);
  END IF;
  PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
  IF pg_temp.both(v_accra) IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing Ghana did not close it for its people at once';
  END IF;
END $$;

-- =====================================================================
-- C. (W1b, A-10) Spec 1's seam keeps exactly {enabled, enrolled}.
-- =====================================================================
DO $$
DECLARE
  v_ok constant uuid := pg_temp.id('01');
  v_young constant uuid := pg_temp.id('02');
  v jsonb;
BEGIN
  v := private.dating_home_summary(v_ok);
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['enabled', 'enrolled']
     OR v IS DISTINCT FROM '{"enabled": true, "enrolled": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary is %', v;
  END IF;
  -- Enabled means the feature is on for the person, not that they qualify.
  IF private.dating_home_summary(v_young) IS DISTINCT FROM '{"enabled": true, "enrolled": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary.enabled followed a later gate';
  END IF;
  -- 'enrolled' is Spec 1's line, unchanged: an exited enrolment is not one.
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_young, 'exited');
  IF private.dating_home_summary(v_young) IS DISTINCT FROM '{"enabled": true, "enrolled": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an exited enrolment counts as enrolled';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_ok, 'profile_draft');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF private.dating_home_summary(v_ok) IS DISTINCT FROM '{"enabled": false, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the summary is %', private.dating_home_summary(v_ok);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- Through Spec 1's home state, as the person.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ok, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_ok::text, true);
  v := public.get_my_home_state() -> 'dating';
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v IS DISTINCT FROM '{"enabled": true, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_home_state().dating is %', v;
  END IF;
END $$;

-- =====================================================================
-- D. (W1b, batch-5 ruling) NULL never counts as passing: a gate whose
--    dependency answers NULL fails closed, and the seam never reads a NULL
--    eligibility as enabled. Each probe swaps dependencies for stubs inside
--    a block that is rolled back, so nothing outlives the probe.
-- =====================================================================
-- Runs [p_setup] then returns [p_probe]'s value, undoing both.
CREATE FUNCTION pg_temp.probe(p_setup text[], p_probe text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
  v_sql text;
BEGIN
  BEGIN
    FOREACH v_sql IN ARRAY p_setup LOOP
      EXECUTE v_sql;
    END LOOP;
    EXECUTE p_probe INTO v;
    RAISE EXCEPTION 'w1b:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w1b:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;

-- A profile for [p_n] in Ghana's region [p_region] (the country column is
-- W1c's; ADD COLUMN IF NOT EXISTS is a no-op once it exists), and a stub
-- current Ghana row with [p_assign] applied.
CREATE FUNCTION pg_temp.gh_setup(p_n text, p_region text, p_assign text) RETURNS text[] LANGUAGE sql AS $gh$
  SELECT ARRAY[
    'ALTER TABLE public.dating_profiles ADD COLUMN IF NOT EXISTS country_code char(2), ADD COLUMN IF NOT EXISTS region_code text',
    format('INSERT INTO public.dating_profiles (user_id, display_name, city_region_code, relationship_intention, country_code, region_code)
            VALUES (%L, %L, %L, %L, %L, %L)', pg_temp.id(p_n), 'Probe ' || p_n, 'AA', 'long_term', 'GH', p_region),
    format($s$CREATE OR REPLACE FUNCTION public.dating_country_config(p_country text)
             RETURNS public.country_safety_config LANGUAGE plpgsql STABLE AS $f$
             DECLARE r public.country_safety_config;
             BEGIN
               SELECT * INTO r FROM public.country_safety_config AS c WHERE c.country_code = 'GH' AND c.is_current;
               %s
               RETURN r;
             END $f$$s$, p_assign)];
$gh$;

DO $d$
DECLARE
  v_ok constant uuid := pg_temp.id('01');
  v_gh constant uuid := pg_temp.person('30');
  v_both constant text := format('SELECT pg_temp.both(%L)', v_ok);
  v_gh_both constant text := format('SELECT pg_temp.both(%L)', v_gh);
  v text;
BEGIN
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_flag_enabled(p_key text) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    v_both);
  IF v IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL feature flag passed gate 1 (%)', v;
  END IF;
  -- Fix round 1 (I-1): a NULL key-readiness answer is not ready.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_exclusion_key_ready() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    v_both);
  IF v IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL key-readiness answer passed gate 1b (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    v_both);
  IF v IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL standing passed gate 3 (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_has_relationship(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    v_both);
  IF v IS DISTINCT FROM 'relationship_active/relationship_active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL relationship answer passed gate 4 (%)', v;
  END IF;

  -- Gate 6 through a stub Ghana row: open in AA is eligible (the probe
  -- reaches gate 6); closed, NULL-open, unknown and NULL-region rows are not.
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r.dating_enabled := true; r.open_regions := ARRAY[''AA''];'), v_gh_both);
  IF v IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate-6 probe does not reach an eligible person (%)', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', NULL, 'r.dating_enabled := true; r.open_regions := ARRAY[''AA''];'), v_gh_both);
  IF v IS DISTINCT FROM 'eligible/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana with no region yet is % (eligible to set up, not a candidate)', v;
  END IF;
  -- Fix round 1 (M-2, spec §2.1 row 6): open_regions NULL opens the whole
  -- country, with or without a region chosen.
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r.dating_enabled := true; r.open_regions := NULL;'), v_gh_both);
  IF v IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a whole-country-open row (open_regions NULL) is % for a region', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', NULL, 'r.dating_enabled := true; r.open_regions := NULL;'), v_gh_both);
  IF v IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a whole-country-open row (open_regions NULL) is % with no region', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r.dating_enabled := false;'), v_gh_both);
  IF v IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country passed gate 6 (%)', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r.dating_enabled := NULL;'), v_gh_both);
  IF v IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL dating_enabled passed gate 6 (%)', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r := NULL;'), v_gh_both);
  IF v IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country with no config passed gate 6 (%)', v;
  END IF;
  v := pg_temp.probe(pg_temp.gh_setup('30', 'AA', 'r.dating_enabled := true; r.open_regions := ARRAY[''AH'', NULL];'), v_gh_both);
  IF v IS DISTINCT FROM 'region_closed/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a region outside a list holding NULL passed gate 6 (%)', v;
  END IF;

  -- The seam: a NULL eligibility is not enabled.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format('SELECT private.dating_home_summary(%L)::text', v_ok));
  IF v IS DISTINCT FROM '{"enabled": false, "enrolled": true}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with a NULL eligibility the summary is %', v;
  END IF;
  -- Nothing outlived the probes.
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'eligible/country_closed'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_gh) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a probe outlived its block';
  END IF;
END $d$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_eligibility_contracts: all held'; END $$;
ROLLBACK;
