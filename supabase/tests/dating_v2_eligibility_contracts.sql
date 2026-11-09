-- supabase/tests/dating_v2_eligibility_contracts.sql
-- Spec 2 W1b (and W2) (§2.1, §7.1, §7.5; I-14, A-10): dating_eligibility's
-- base gates 1-4 (A), its country and region gate 6 (B, from W1c, once
-- profiles carry a country), Spec 1's re-created home-summary seam (C) and
-- NULL-safety: no NULL answer ever counts as passing (D).
-- W2 adds the gentle wait (E), begin and the candidate check (E2), the
-- shim (F), the gate cron (G), Healing (H) and the path trigger (I).
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

-- =====================================================================
-- E. (W2, §2.1 gate 5, A-9) The gentle wait: inside the 30-day ending
--    window of a relationship of theirs that ended here, for candidates
--    only; the window, not the status alone; both members; an archived
--    space is no wait; Healing gates nothing.
-- =====================================================================
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
CREATE FUNCTION pg_temp.as_person(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- The error [p_sql] raises ('no error' when none).
CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'no error';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END $$;

-- [p_user] begins enrolment under key [p_key]: the error (or 'no error'),
-- then the enrolment's state, read afterwards.
CREATE FUNCTION pg_temp.begin_as(p_user uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p_user);
  v := pg_temp.error_of(format('SELECT public.begin_dating_enrollment(%L, %L)', '1', p_key));
  PERFORM pg_temp.as_db();
  RETURN v || '/' || coalesce((SELECT e.state FROM public.dating_enrollments AS e WHERE e.user_id = p_user), 'none');
END $$;

CREATE FUNCTION pg_temp.enrolled(p_n text, p_state text, p_reason text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v constant uuid := pg_temp.person(p_n);
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason, paused_at)
  VALUES (v, p_state, p_reason, CASE WHEN p_state = 'paused' THEN now() - interval '1 day' END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state)
  VALUES (v, 'Enrolled ' || p_n, CASE p_state WHEN 'active' THEN 'active' WHEN 'paused' THEN 'paused' ELSE 'draft' END);
  RETURN v;
END $$;

-- The enrolment's state/reason and the profile's state for [p].
CREATE FUNCTION pg_temp.pause_of(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = p), 'none')
         || '/' || coalesce((SELECT d.profile_state FROM public.dating_profiles AS d WHERE d.user_id = p), 'none');
$$;


DO $$
DECLARE
  v_wait constant uuid := pg_temp.person('40');
  v_wait_b constant uuid := pg_temp.person('41');
  v_past constant uuid := pg_temp.person('42');
  v_past_b constant uuid := pg_temp.person('43');
  v_sealed constant uuid := pg_temp.person('44');
  v_sealed_b constant uuid := pg_temp.person('45');
  v_solo constant uuid := pg_temp.person('46');
  v_edge constant uuid := pg_temp.person('47');
  v_edge_b constant uuid := pg_temp.person('48');
  v_two constant uuid := pg_temp.person('49');
  v_two_b constant uuid := pg_temp.person('50');
  v_two_c constant uuid := pg_temp.person('51');
  v_left constant uuid := pg_temp.person('52');
  v_moved_on constant uuid := pg_temp.person('53');
  v_new constant uuid := pg_temp.person('54');
  v_ended timestamptz;
  v_journey uuid;
  v_rel uuid;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_wait, v_wait_b, 'ended', now() - interval '10 days'),
    (v_past, v_past_b, 'ended', now() - interval '30 days' - interval '1 hour'),
    (v_edge, v_edge_b, 'ended', now() - interval '30 days' + interval '1 hour'),
    (v_two, v_two_b, 'ended', now() - interval '20 days'),
    (v_two, v_two_c, 'ended', now() - interval '5 days'),
    (v_left, v_moved_on, 'ended', now() - interval '3 days');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at, chat_archived_at, chat_archived_reason)
  VALUES (v_sealed, v_sealed_b, 'archived', now() - interval '2 days', now() - interval '1 day', 'both_sealed');

  -- Setup goes ahead during the wait; a candidate waits (and gate 5 comes
  -- before gate 6: with no Dating country yet the candidate's first reason
  -- is the wait).
  IF pg_temp.both(v_wait) IS DISTINCT FROM 'eligible/gentle_wait'
     OR pg_temp.both(v_wait_b) IS DISTINCT FROM 'eligible/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: inside the ending window the reasons are % and % (expected eligible/gentle_wait for both members)',
      pg_temp.both(v_wait), pg_temp.both(v_wait_b);
  END IF;
  IF pg_temp.both(v_edge) IS DISTINCT FROM 'eligible/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an hour before the open date the reason is % (expected eligible/gentle_wait)', pg_temp.both(v_edge);
  END IF;
  -- A-9: past ended_at + 30 days it is open, though the sweep hasn't
  -- archived the space yet (status still 'ended').
  IF pg_temp.both(v_past) IS DISTINCT FROM 'eligible/country_closed'
     OR (SELECT r.status FROM public.relationships AS r WHERE r.user_a = v_past) IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the open date, before the sweep, the reason is % (the gate read the status, not the window)', pg_temp.both(v_past);
  END IF;
  -- Archived by both seals: open at once.
  IF pg_temp.both(v_sealed) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a space both sealed still holds the wait (%)', pg_temp.both(v_sealed);
  END IF;
  -- The latest ending in its window decides the open date.
  SELECT max(r.ended_at) INTO v_ended FROM public.relationships AS r WHERE r.user_a = v_two;
  IF private.dating_gentle_wait_opens_at(v_two) IS DISTINCT FROM v_ended + interval '30 days'
     OR private.dating_gentle_wait_opens_at(v_wait) IS DISTINCT FROM
        (SELECT r.ended_at FROM public.relationships AS r WHERE r.user_a = v_wait) + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open date is not the latest ending + 30 days (%, %)',
      private.dating_gentle_wait_opens_at(v_two), private.dating_gentle_wait_opens_at(v_wait);
  END IF;
  IF private.dating_gentle_wait_opens_at(v_past) IS NOT NULL OR private.dating_gentle_wait_opens_at(v_solo) IS NOT NULL
     OR private.dating_gentle_wait_opens_at(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open date exists with no ending in its window';
  END IF;
  -- The other member starts a new relationship: the space is archived and
  -- the wait ends for the one left behind (A-9).
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_moved_on, NULL, 'pending', 'W2GWAIT1', now() + interval '1 day') RETURNING id INTO v_rel;
  UPDATE public.relationships SET user_b = v_new, status = 'active', invite_code = NULL, invite_accepted_at = now()
   WHERE id = v_rel;
  IF (SELECT r.status FROM public.relationships AS r WHERE r.user_a = v_left) IS DISTINCT FROM 'archived'
     OR pg_temp.both(v_left) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the other member''s new relationship the reason is % (expected the wait to end)', pg_temp.both(v_left);
  END IF;
  -- An open country: the wait is the only reason; after it, eligible.
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_wait, 'Waits', 'GH', 'AA'), (v_past, 'Open', 'GH', 'AA'), (v_wait_b, 'Lagos', 'NG', NULL);
  IF pg_temp.both(v_wait) IS DISTINCT FROM 'eligible/gentle_wait' OR pg_temp.both(v_past) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in an open country the reasons are % and % (expected eligible/gentle_wait, eligible/eligible)',
      pg_temp.both(v_wait), pg_temp.both(v_past);
  END IF;
  IF pg_temp.both(v_wait_b) IS DISTINCT FROM 'country_closed/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country during the wait is % (expected country_closed/gentle_wait: gate 5 before 6)', pg_temp.both(v_wait_b);
  END IF;
  -- Healing gates nothing (§2.1): a journey with a readiness score of 10.
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status)
  VALUES (v_solo, now() - interval '1 day', 'user_reported', 'active') RETURNING id INTO v_journey;
  INSERT INTO public.healing_readiness_attempts (journey_id, user_id, answers, score, scoring_version)
  VALUES (v_journey, v_solo, '{}'::jsonb, 10, 'healing_readiness_v1_1');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_solo, 'Solo', 'GH', 'AH');
  IF pg_temp.both(v_solo) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Healing readiness score of 10 gates Dating (%)', pg_temp.both(v_solo);
  END IF;
  IF to_regprocedure('public.dating_healing_gates_hold(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname IN ('public', 'private')
                   AND (p.prosrc LIKE '%dating_healing_gates_hold%' OR p.prosrc LIKE '%''eligible_for_dating_opt_in''%')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Healing gate (or a Healing Dating status writer) is still there';
  END IF;
  IF has_function_privilege('authenticated', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open date is callable outside the database';
  END IF;
END $$;


-- E2. (W2, §4.10) begin_dating_enrollment and the candidate check go
--     through dating_eligibility: setup begins during the wait, a candidate
--     waits, NULL never passes, and begin takes the shared lock order first
--     and retries a lock conflict.
DO $e2$
DECLARE
  v_wait constant uuid := pg_temp.id('40');
  v_past constant uuid := pg_temp.id('42');
  v_young constant uuid := pg_temp.id('02');
  v_retry constant uuid := pg_temp.person('56');
  v_device constant uuid := pg_temp.person('57');
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_src text;
  v text;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT u, 'w2-begin-' || p || '-' || right(u::text, 2), p, 'granted', '1', clock_timestamp()
    FROM unnest(ARRAY[v_wait, v_young, v_retry, v_device]) AS u, unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  v := pg_temp.begin_as(v_wait, 'spec2-w2-begin-0040');
  IF v IS DISTINCT FROM 'no error/profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: during the gentle wait setup could not begin (%)', v;
  END IF;
  v := pg_temp.begin_as(v_young, 'spec2-w2-begin-0002');
  IF v IS DISTINCT FROM 'not_eligible/exited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account began enrolment (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.begin_as(%L, 'spec2-w2-begin-0057')$q$, v_device));
  IF v IS DISTINCT FROM 'reverify_device/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device began enrolment (%)', v;
  END IF;
  -- Two lock conflicts on the write are retried (a sequence outlives each
  -- rolled-back savepoint).
  CREATE TEMP SEQUENCE w2_begin_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE FUNCTION public.w2_flaky_enrolment() RETURNS trigger LANGUAGE plpgsql AS $f$
       BEGIN
         IF nextval('pg_temp.w2_begin_calls') <= 2 THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF;
         RETURN NEW;
       END $f$$s$,
    $s$CREATE TRIGGER w2_flaky BEFORE INSERT ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w2_flaky_enrolment()$s$,
    $s$SELECT 1$s$],
    format($s$SELECT pg_temp.begin_as(%L, 'spec2-w2-begin-0056') || '/' || currval('pg_temp.w2_begin_calls')$s$, v_retry));
  IF v IS DISTINCT FROM 'no error/profile_draft/3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock conflicts were not retried into an enrolment (%; expected no error/profile_draft/3)', v;
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.begin_dating_enrollment(text,text)'::regprocedure);
  IF position('private.dating_lock_setup(v_user_id)' IN v_src) = 0
     OR position('private.dating_lock_setup(v_user_id)' IN v_src) > position('dating_exclusion_key_mismatch' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin_dating_enrollment does not take the shared lock order first';
  END IF;
  -- The candidate check: the wait keeps an active, ready person out; NULL
  -- never passes.
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id = v_wait;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_past, 'active');
  v := pg_temp.probe(v_ready, format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE) || '/' || (public.dating_candidate_is_current(%L) IS TRUE)$q$, v_wait, v_past));
  IF v IS DISTINCT FROM 'true/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the candidate check ignores the gentle wait (in the wait not current, after it current: %)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility made a current candidate (or a NULL answer)';
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL readiness answer made a current candidate (or a NULL answer)';
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL age answer made a current candidate (or a NULL answer)';
  END IF;
  UPDATE public.dating_enrollments SET state = 'profile_draft' WHERE user_id = v_wait;
  DELETE FROM public.dating_enrollments WHERE user_id = v_past;
END $e2$;

-- =====================================================================
-- F. (W3a, I-4, R21) get_dating_eligibility() is gone. Its W2 fixture
--    (person 55 and the pending relationship) stays for later sections.
-- =====================================================================
DO $shim$
DECLARE
  v_inviter constant uuid := pg_temp.person('55');
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_inviter, NULL, 'pending', 'W2SHIM01', now() + interval '1 day');
  IF to_regprocedure('public.get_dating_eligibility()') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_eligibility() still exists (W3a drops it)';
  END IF;
END $shim$;

-- =====================================================================
-- G. (W2, W1 B10 M-6) The 15-minute gate cron pauses only on the person's
--    own gates (2-4, age, readiness), never on the gentle wait, a closed
--    country or the feature switch; every pause has a reason; one person's
--    lock conflict is counted and the run goes on.
-- =====================================================================
-- Runs the cron, then: how many enrolments it paused without a reason
-- (any person, M-6), and [p_people]'s states in order.
CREATE FUNCTION pg_temp.cron_states(p_people uuid[]) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM public.enforce_dating_lifecycle_gates();
  EXCEPTION WHEN OTHERS THEN
    RETURN 'raised ' || SQLSTATE || ' ' || SQLERRM;
  END;
  RETURN (SELECT count(*) FROM public.dating_enrollments AS e
           WHERE e.state = 'paused' AND e.pause_reason IS NULL AND e.updated_at = now()) || ':'
         || (SELECT string_agg(pg_temp.pause_of(x), ',' ORDER BY o) FROM unnest(p_people) WITH ORDINALITY AS t(x, o));
END $$;

DO $h$
DECLARE
  v_wait constant uuid := pg_temp.enrolled('70', 'active');
  v_held constant uuid := pg_temp.enrolled('71', 'active');
  v_closed constant uuid := pg_temp.enrolled('72', 'active');
  v_partner constant uuid := pg_temp.person('73');
  v_people uuid[];
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_before bigint;
  v text;
BEGIN
  v_people := ARRAY[v_wait, v_held, v_closed];
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_partner, 'ended', now() - interval '3 days');
  UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id IN (v_wait, v_held);
  UPDATE public.dating_profiles SET country_code = 'NG' WHERE user_id = v_closed;
  PERFORM public.place_account_hold(v_held, 'safety_review', 'spec2-w2-cron');
  v := pg_temp.probe(v_ready, format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused,active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate cron gave % (expected only the held person paused, with the reason gates)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[$s$UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled'$s$],
                     format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused,active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the gate cron gave % (the switch pauses nobody; standing still does)', v;
  END IF;
  -- A NULL readiness answer never counts as ready.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:paused/gates/paused,paused/gates/paused,paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL readiness answer kept a person active (%)', v;
  END IF;
  -- Without the readiness stand-ins, an incomplete v1 profile is paused too, with a reason.
  v := pg_temp.probe(ARRAY[]::text[], format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:paused/gates/paused,paused/gates/paused,paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: incomplete profiles gave % (expected all three paused, each with a reason)', v;
  END IF;
  -- One person's lock conflicts: counted, the run goes on.
  v_before := pg_temp.metric('dating.gates.busy');
  v := pg_temp.probe(v_ready || ARRAY[
    format($s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN IF p_user_id = %L THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF; END $f$$s$, v_held),
    $s$UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id = '5e2c0000-0000-0000-0000-000000000072'$s$,
    $s$SELECT public.place_account_hold('5e2c0000-0000-0000-0000-000000000072', 'age_review', 'spec2-w2-cron')$s$],
    format($s$SELECT pg_temp.cron_states(%L) || '/' || (pg_temp.metric('dating.gates.busy') - %s)$s$, v_people, v_before));
  IF v IS DISTINCT FROM '0:active/-/active,active/-/active,paused/gates/paused/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lock conflict stopped the gate cron or went uncounted (%)', v;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc AS p WHERE p.oid = 'public.enforce_dating_lifecycle_gates()'::regprocedure
              AND (position('private.dating_lock_setup(v_user_id)' IN p.prosrc) = 0
                   OR position('private.dating_lock_setup(v_user_id)' IN p.prosrc) > position('UPDATE public.dating_enrollments' IN p.prosrc))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate cron writes before the shared lock';
  END IF;
END $h$;

-- =====================================================================
-- H. (W2, R7) Healing never grants Dating: a ready journey is completed
--    whatever the score; the readiness answer names no Dating date; no row
--    keeps the old status.
-- =====================================================================
DO $i$
DECLARE
  v_high constant uuid := pg_temp.person('75');
  v_low constant uuid := pg_temp.person('76');
  v_short constant uuid := pg_temp.person('a1');
  v_journey uuid;
  v_low_journey uuid;
  v_short_journey uuid;
  v jsonb;
  v_low_answer jsonb;
  v_short_answer jsonb;
BEGIN
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, reflection_completed_at,
                                       post_mortem_status, post_mortem_completed_at, pattern_awareness_completed_at,
                                       portrait_status, portrait_completed_at)
  VALUES (v_high, now() - interval '12 weeks', 'user_reported', 'active', now(), 'completed', now(), now(), 'completed', now())
  RETURNING id INTO v_journey;
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, reflection_completed_at,
                                       post_mortem_status, post_mortem_completed_at, pattern_awareness_completed_at,
                                       portrait_status, portrait_completed_at)
  VALUES (v_low, now() - interval '2 weeks', 'user_reported', 'active', now(), 'completed', now(), now(), 'completed', now())
  RETURNING id INTO v_low_journey;
  UPDATE public.healing_journeys SET eligible_for_dating_opt_in_at = now() - interval '1 day' WHERE id = v_journey;
  PERFORM pg_temp.as_person(v_high);
  v := public.submit_healing_readiness(v_journey, '{"q1":5,"q2":5,"q3":5,"q4":5,"q5":5,"q6":5,"q7":5}');
  PERFORM pg_temp.as_person(v_low);
  v_low_answer := public.submit_healing_readiness(v_low_journey, '{"q1":1,"q2":1,"q3":1,"q4":1,"q5":1,"q6":1,"q7":1}');
  PERFORM pg_temp.as_db();
  IF (SELECT j.status || '/' || (j.eligible_for_dating_opt_in_at IS NULL) FROM public.healing_journeys AS j WHERE j.id = v_journey)
     IS DISTINCT FROM 'completed/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ready journey with a score of 100 is not simply completed';
  END IF;
  IF v ->> 'score' IS DISTINCT FROM '100' OR v ->> 'is_eligible' IS DISTINCT FROM 'true'
     OR v ->> 'message' IS DISTINCT FROM 'Your check-in is complete. Healing stays here whenever you want it.'
     OR v_low_answer ->> 'message' IS DISTINCT FROM 'Your answers suggest there may be more you want to explore. Go at your own pace.'
     OR (v::text || v_low_answer::text) ILIKE '%dating%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the readiness answer still speaks of Dating (%, %)', v, v_low_answer;
  END IF;
  -- (Final review I-1) is_eligible is the result screen's success styling:
  -- a completed journey with a score above 70. A score of 0 completes the
  -- journey but never gets the success ring; a score of 100 on a journey a
  -- stage short gets it neither.
  IF v_low_answer ->> 'is_eligible' IS DISTINCT FROM 'false'
     OR (SELECT j.status FROM public.healing_journeys AS j WHERE j.id = v_low_journey) IS DISTINCT FROM 'completed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a low score was shown as a success, or did not complete the journey (%, %)',
      v_low_answer, (SELECT j.status FROM public.healing_journeys AS j WHERE j.id = v_low_journey);
  END IF;
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, reflection_completed_at,
                                       post_mortem_status, post_mortem_completed_at, pattern_awareness_completed_at,
                                       portrait_status, portrait_completed_at)
  VALUES (v_short, now() - interval '12 weeks', 'user_reported', 'active', now(), 'completed', now(), NULL, 'completed', now())
  RETURNING id INTO v_short_journey;
  PERFORM pg_temp.as_person(v_short);
  v_short_answer := public.submit_healing_readiness(v_short_journey, '{"q1":5,"q2":5,"q3":5,"q4":5,"q5":5,"q6":5,"q7":5}');
  PERFORM pg_temp.as_db();
  IF v_short_answer ->> 'is_eligible' IS DISTINCT FROM 'false' OR v_short_answer ->> 'score' IS DISTINCT FROM '100' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a score of 100 on an unfinished journey was shown as a success (%)', v_short_answer;
  END IF;
  IF EXISTS (SELECT 1 FROM public.healing_journeys WHERE status = 'eligible_for_dating_opt_in' OR eligible_for_dating_opt_in_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a journey still holds a Dating outcome';
  END IF;
END $i$;
-- =====================================================================
-- G2. (W2 batch 1, fail-closed sweep) Every NULL-safe or bounded branch
--     migration 1 adds holds on its own: begin refuses a NULL eligibility
--     and a NULL device answer and gives up after three lock conflicts;
--     the shim never reads a NULL age answer as verified; the gate cron
--     pauses on a NULL age, standing or relationship answer and on a
--     gate-2 failure no other line sees, and retries a lock conflict.
-- =====================================================================
DO $g2$
DECLARE
  v_null_elig constant uuid := pg_temp.person('80');
  v_null_device constant uuid := pg_temp.person('81');
  v_busy constant uuid := pg_temp.person('82');
  v_cron constant uuid := pg_temp.enrolled('83', 'active');
  v_eula constant uuid := pg_temp.enrolled('84', 'active');
  v_wait constant uuid := pg_temp.id('40');
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_before bigint;
  v text;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT u, 'w2-b1-' || p || '-' || right(u::text, 2), p, 'granted', '1', clock_timestamp()
    FROM unnest(ARRAY[v_null_elig, v_null_device, v_busy]) AS u, unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id IN (v_cron, v_eula);

  -- begin: a NULL eligibility refuses.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format($q$SELECT pg_temp.begin_as(%L, 'spec2-w2-b1-0080')$q$, v_null_elig));
  IF v IS DISTINCT FROM 'not_eligible/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility began enrolment (%)', v;
  END IF;
  -- begin: a NULL device answer refuses.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format($q$SELECT pg_temp.begin_as(%L, 'spec2-w2-b1-0081')$q$, v_null_device));
  IF v IS DISTINCT FROM 'reverify_device/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL device answer began enrolment (%)', v;
  END IF;
  -- begin: three lock conflicts give up, as dating:busy, writing nothing.
  CREATE TEMP SEQUENCE w2_b1_begin_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE FUNCTION public.w2_b1_busy_enrolment() RETURNS trigger LANGUAGE plpgsql AS $f$
       BEGIN
         PERFORM nextval('pg_temp.w2_b1_begin_calls');
         RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01';
       END $f$$s$,
    $s$CREATE TRIGGER w2_b1_busy BEFORE INSERT ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w2_b1_busy_enrolment()$s$],
    format($s$SELECT pg_temp.begin_as(%L, 'spec2-w2-b1-0082') || '/' || currval('pg_temp.w2_b1_begin_calls')$s$, v_busy));
  IF v IS DISTINCT FROM 'dating:busy/none/3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: three lock conflicts did not end as dating:busy after three tries (%)', v;
  END IF;

  -- The gate cron: each own-gate answer that is NULL pauses.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron]));
  IF v IS DISTINCT FROM '0:paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL age answer kept a person active (%)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron]));
  IF v IS DISTINCT FROM '0:paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL standing answer kept a person active (%)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_has_relationship(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron]));
  IF v IS DISTINCT FROM '0:paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL relationship answer kept a person active (%)', v;
  END IF;
  -- Gate 2 (EULA v2) is seen only through dating_eligibility's setup scope.
  v := pg_temp.probe(v_ready || ARRAY[
    format($s$UPDATE public.users SET eula_version = '1' WHERE id = %L$s$, v_eula)],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron, v_eula]));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gate-2 failure (EULA v1) left the person % (expected active, then paused/gates/paused)', v;
  END IF;
  -- Two lock conflicts on one person are retried into a pause, uncounted
  -- (calls: two failed tries, then the profile trigger's and the cron's own).
  CREATE TEMP SEQUENCE w2_b1_cron_calls;
  v_before := pg_temp.metric('dating.gates.busy');
  v := pg_temp.probe(v_ready || ARRAY[
    format($s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN IF p_user_id = %L THEN IF nextval('pg_temp.w2_b1_cron_calls') <= 2 THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF; END IF; END $f$$s$, v_eula),
    format($s$UPDATE public.users SET eula_version = '1' WHERE id = %L$s$, v_eula)],
    format($s$SELECT pg_temp.cron_states(%L) || '/' || (pg_temp.metric('dating.gates.busy') - %s) || '/' || currval('pg_temp.w2_b1_cron_calls')$s$,
           ARRAY[v_eula], v_before));
  IF v IS DISTINCT FROM '0:paused/gates/paused/0/4' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock conflicts were not retried into a pause (%; expected 0:paused/gates/paused/0/4)', v;
  END IF;
END $g2$;
-- =====================================================================
-- E3. (W2 batch 1 fix round 1; owner ruling on I-1, gate erosion) No path
--     silently shortens the wait: a former partner who deleted their
--     account has not sealed; a member who moved on to a relationship that
--     then ended (a second account's, deleted or sealed) keeps the first
--     ending's wait; both members' seals still open it, and stay open when
--     one later deletes. An ending with no date never counts as no wait
--     (M-3). The 30 days are UTC days, whatever the session's zone (M-1).
-- =====================================================================
DO $e3$
DECLARE
  v_alone constant uuid := pg_temp.person('87');
  v_gone constant uuid := pg_temp.person('88');
  v_mover constant uuid := pg_temp.person('89');
  v_left constant uuid := pg_temp.person('90');
  v_sock constant uuid := pg_temp.person('91');
  v_mover2 constant uuid := pg_temp.person('92');
  v_left2 constant uuid := pg_temp.person('93');
  v_sock2 constant uuid := pg_temp.person('94');
  v_undated constant uuid := pg_temp.person('95');
  v_dst constant uuid := pg_temp.person('96');
  v_dst_b constant uuid := pg_temp.person('97');
  v_arch constant uuid := pg_temp.person('98');
  v_sealed constant uuid := pg_temp.person('74');
  v_sealed_gone constant uuid := pg_temp.person('79');
  v_rel uuid;
  v_r1 uuid;
  v_r2 uuid;
  v_ended timestamptz;
  v_before bigint;
  v_tz constant text := current_setting('TimeZone');
  v_doy integer;
  v_zone text;
  v_opens timestamptz;
  v text;
BEGIN
  -- 1. The former partner deleted their account; the one left seals alone.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_alone, v_gone, 'ended', now() - interval '5 days') RETURNING id, ended_at INTO v_rel, v_ended;
  DELETE FROM public.users WHERE id = v_gone;
  DELETE FROM auth.users WHERE id = v_gone;
  PERFORM pg_temp.as_person(v_alone);
  PERFORM public.seal_my_side(v_rel);
  PERFORM pg_temp.as_db();
  v := (SELECT r.status || '/' || r.chat_archived_reason FROM public.relationships AS r WHERE r.id = v_rel);
  IF v IS DISTINCT FROM 'archived/last_member_sealed' OR pg_temp.both(v_alone) IS DISTINCT FROM 'eligible/gentle_wait'
     OR private.dating_gentle_wait_opens_at(v_alone) IS DISTINCT FROM v_ended + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the former partner deleted their account, a lone seal gave % and % (expected archived/last_member_sealed, eligible/gentle_wait)',
      v, pg_temp.both(v_alone);
  END IF;

  -- 2. The second-account bypass: accept a sock's invite (the real ex's
  --    space is archived), the sock deletes its account, seal alone.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_mover, v_left, 'ended', now() - interval '10 days') RETURNING id INTO v_r1;
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_sock, NULL, 'pending', 'W2SOCK01', now() + interval '1 day') RETURNING id INTO v_r2;
  UPDATE public.relationships SET user_b = v_mover, status = 'active', invite_code = NULL, invite_accepted_at = now() WHERE id = v_r2;
  PERFORM public.relationship_end_internal(v_r2, v_sock);
  DELETE FROM public.users WHERE id = v_sock;
  DELETE FROM auth.users WHERE id = v_sock;
  PERFORM pg_temp.as_person(v_mover);
  PERFORM public.seal_my_side(v_r2);
  PERFORM pg_temp.as_db();
  v := (SELECT string_agg(r.status || '/' || r.chat_archived_reason, ',' ORDER BY r.id = v_r2) FROM public.relationships AS r WHERE r.id IN (v_r1, v_r2));
  IF v IS DISTINCT FROM 'archived/partner_new_relationship,archived/last_member_sealed'
     OR pg_temp.both(v_mover) IS DISTINCT FROM 'eligible/gentle_wait'
     OR private.dating_gentle_wait_opens_at(v_mover) IS DISTINCT FROM now() + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second-account bypass (new relationship, the other account deleted, a lone seal) gave % and % (expected the wait from the second ending)',
      v, pg_temp.both(v_mover);
  END IF;
  -- The one left behind by the move: open at once (A-9, unchanged), an
  -- older relationship of theirs from long before makes no one a mover.
  INSERT INTO public.relationships (user_a, user_b, status, created_at, ended_at, chat_archived_at, chat_archived_reason)
  VALUES (v_left, NULL, 'archived', now() - interval '500 days', now() - interval '400 days', now() - interval '370 days', 'window_closed');
  IF pg_temp.both(v_left) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the one left behind by a new relationship waits (%)', pg_temp.both(v_left);
  END IF;

  -- 3. The same with both seals on the second relationship: the first
  --    ending's wait still holds for the one who moved on.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_mover2, v_left2, 'ended', now() - interval '10 days') RETURNING id, ended_at INTO v_r1, v_ended;
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_sock2, NULL, 'pending', 'W2SOCK02', now() + interval '1 day') RETURNING id INTO v_r2;
  UPDATE public.relationships SET user_b = v_mover2, status = 'active', invite_code = NULL, invite_accepted_at = now() WHERE id = v_r2;
  PERFORM public.relationship_end_internal(v_r2, v_mover2);
  PERFORM pg_temp.as_person(v_sock2);
  PERFORM public.seal_my_side(v_r2);
  PERFORM pg_temp.as_person(v_mover2);
  PERFORM public.seal_my_side(v_r2);
  PERFORM pg_temp.as_db();
  IF (SELECT r.chat_archived_reason FROM public.relationships AS r WHERE r.id = v_r2) IS DISTINCT FROM 'both_sealed'
     OR pg_temp.both(v_mover2) IS DISTINCT FROM 'eligible/gentle_wait'
     OR private.dating_gentle_wait_opens_at(v_mover2) IS DISTINCT FROM v_ended + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sealed second relationship erased the first ending''s wait (%, opens %)',
      pg_temp.both(v_mover2), private.dating_gentle_wait_opens_at(v_mover2);
  END IF;
  IF pg_temp.both(v_left2) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the one left behind waits after the other''s sealed second relationship (%)', pg_temp.both(v_left2);
  END IF;

  -- 4. Both sealed, then one deletes their account: still open (no wait
  --    comes back).
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_sealed, v_sealed_gone, 'ended', now() - interval '4 days') RETURNING id INTO v_rel;
  PERFORM pg_temp.as_person(v_sealed_gone);
  PERFORM public.seal_my_side(v_rel);
  PERFORM pg_temp.as_person(v_sealed);
  PERFORM public.seal_my_side(v_rel);
  PERFORM pg_temp.as_db();
  DELETE FROM public.users WHERE id = v_sealed_gone;
  DELETE FROM auth.users WHERE id = v_sealed_gone;
  IF (SELECT r.chat_archived_reason FROM public.relationships AS r WHERE r.id = v_rel) IS DISTINCT FROM 'both_sealed'
     OR pg_temp.both(v_sealed) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both sealed, then one deleted: % (expected both_sealed and open)', pg_temp.both(v_sealed);
  END IF;

  -- 5. (M-3) An 'ended' row with no date: no candidate, counted; setup goes
  --    ahead. An archived row with no ended_at waits from its archive time.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_undated, NULL, 'ended', NULL);
  v_before := pg_temp.metric('dating.gentle_wait.undated');
  v := pg_temp.both(v_undated);
  IF v IS DISTINCT FROM 'eligible/account_unavailable' OR pg_temp.metric('dating.gentle_wait.undated') - v_before < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending with no date gave % (counted %; expected eligible/account_unavailable, counted)',
      v, pg_temp.metric('dating.gentle_wait.undated') - v_before;
  END IF;
  INSERT INTO public.relationships (user_a, user_b, status, ended_at, chat_archived_at, chat_archived_reason)
  VALUES (v_arch, NULL, 'archived', NULL, now() - interval '2 days', 'manual_end');
  IF pg_temp.both(v_arch) IS DISTINCT FROM 'eligible/gentle_wait'
     OR private.dating_gentle_wait_opens_at(v_arch) IS DISTINCT FROM now() - interval '2 days' + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archive with no ended_at gave % (opens %; expected the wait from its archive time)',
      pg_temp.both(v_arch), private.dating_gentle_wait_opens_at(v_arch);
  END IF;

  -- 6. (M-1) A summer-time change inside the window: a zone whose DST starts
  --    today (POSIX rule, any date of the year) moves nothing.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_dst, v_dst_b, 'ended', now() - interval '10 days') RETURNING ended_at INTO v_ended;
  v_doy := extract(doy FROM now() AT TIME ZONE 'utc')::integer - 1;
  v_zone := format('WGA0WGB,%s/0,%s/0', v_doy, (v_doy + 180) % 365);
  PERFORM set_config('TimeZone', v_zone, true);
  v_opens := private.dating_gentle_wait_opens_at(v_dst);
  IF v_ended + interval '30 days' = v_ended + interval '720 hours' THEN
    PERFORM set_config('TimeZone', v_tz, true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: test setup: zone % has no change inside the window', v_zone;
  END IF;
  PERFORM set_config('TimeZone', v_tz, true);
  IF v_opens IS DISTINCT FROM v_ended + interval '720 hours' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: across a summer-time change the open date moved (% vs %)', v_opens, v_ended + interval '720 hours';
  END IF;
END $e3$;

-- =====================================================================
-- E4. (W2 final review M-4) private.dating_gentle_wait_can_shorten: closing
--     the space together can still end the wait only when every ending
--     that holds it is an 'ended' space with both accounts present.
-- =====================================================================
DO $e4$
DECLARE
  v_a constant uuid := pg_temp.person('b1');
  v_b constant uuid := pg_temp.person('b2');
  v_alone constant uuid := pg_temp.person('b3');
  v_gone constant uuid := pg_temp.person('b4');
  v_mover constant uuid := pg_temp.person('b5');
  v_left constant uuid := pg_temp.person('b6');
  v_sock constant uuid := pg_temp.person('b7');
  v_none constant uuid := pg_temp.person('b8');
  v_undated constant uuid := pg_temp.person('b9');
  v_rel uuid;
  v_r2 uuid;
  v text;
BEGIN
  -- Both present, nobody sealed, then one seal: still shortenable.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_a, v_b, 'ended', now() - interval '5 days') RETURNING id INTO v_rel;
  v := private.dating_gentle_wait_can_shorten(v_a)::text || ',' || private.dating_gentle_wait_can_shorten(v_b)::text;
  PERFORM pg_temp.as_person(v_b);
  PERFORM public.seal_my_side(v_rel);
  PERFORM pg_temp.as_db();
  v := v || ',' || private.dating_gentle_wait_can_shorten(v_a)::text;
  IF v IS DISTINCT FROM 'true,true,true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh ending with both accounts present is not shortenable (%; expected true,true,true)', v;
  END IF;
  -- The former partner deleted their account: never shortenable, before
  -- and after the lone seal.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_alone, v_gone, 'ended', now() - interval '5 days') RETURNING id INTO v_rel;
  DELETE FROM public.users WHERE id = v_gone;
  DELETE FROM auth.users WHERE id = v_gone;
  v := private.dating_gentle_wait_can_shorten(v_alone)::text;
  PERFORM pg_temp.as_person(v_alone);
  PERFORM public.seal_my_side(v_rel);
  PERFORM pg_temp.as_db();
  v := v || ',' || private.dating_gentle_wait_can_shorten(v_alone)::text || ',' || public.dating_eligibility(v_alone);
  IF v IS DISTINCT FROM 'false,false,gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the former partner deleted their account the wait reads as shortenable (%; expected false,false,gentle_wait)', v;
  END IF;
  -- The one who moved on (to a second relationship that ended, both
  -- present): the first ending's archived space still holds the wait.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at)
  VALUES (v_mover, v_left, 'ended', now() - interval '10 days');
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_sock, NULL, 'pending', 'W2SOCK0F', now() + interval '1 day') RETURNING id INTO v_r2;
  UPDATE public.relationships SET user_b = v_mover, status = 'active', invite_code = NULL, invite_accepted_at = now() WHERE id = v_r2;
  PERFORM public.relationship_end_internal(v_r2, v_sock);
  v := private.dating_gentle_wait_can_shorten(v_mover)::text || ',' || public.dating_eligibility(v_mover)
       || ',' || private.dating_gentle_wait_can_shorten(v_left)::text;
  IF v IS DISTINCT FROM 'false,gentle_wait,false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the one who moved on reads as shortenable, or the one left behind as waiting (%; expected false,gentle_wait,false)', v;
  END IF;
  -- No wait at all, and an undated ending: false, never NULL.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_undated, NULL, 'ended', NULL);
  v := private.dating_gentle_wait_can_shorten(v_none)::text || ',' || coalesce(private.dating_gentle_wait_can_shorten(v_undated)::text, 'NULL');
  IF v IS DISTINCT FROM 'false,false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no wait or an undated ending read as shortenable (%; expected false,false)', v;
  END IF;
END $e4$;

-- =====================================================================
-- G3. (W2 batch 1 fix round 1, I-2 and M-4) The gate cron's own NULL-safe
--     lines hold with the feature switch off (no eligibility line to lean
--     on); a person paused by someone else mid-run is not counted or
--     touched again; a raise in one person's gates is counted and the run
--     goes on.
-- =====================================================================
-- Runs the cron, then (a separate statement) [p_people]'s states.
CREATE FUNCTION pg_temp.cron_count(p_people uuid[]) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_n bigint;
BEGIN
  v_n := public.enforce_dating_lifecycle_gates();
  RETURN v_n || ':' || (SELECT string_agg(pg_temp.pause_of(x), ',' ORDER BY o) FROM unnest(p_people) WITH ORDINALITY AS t(x, o));
END $$;

DO $g3$
DECLARE
  v_cron constant uuid := pg_temp.id('83');
  v_first constant uuid := pg_temp.enrolled('85', 'active');
  v_second constant uuid := pg_temp.enrolled('86', 'active');
  v_raises constant uuid := pg_temp.enrolled('77', 'active');
  v_eula constant uuid := pg_temp.enrolled('78', 'active');
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_flag_off constant text := $s$UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled'$s$;
  v_before bigint;
  v text;
BEGIN
  UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id IN (v_first, v_second, v_raises, v_eula);
  -- I-2: with the switch off the eligibility line pauses nobody, so the
  -- standalone lines must.
  v := pg_temp.probe(v_ready || ARRAY[v_flag_off,
    $s$CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron]));
  IF v IS DISTINCT FROM '0:paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the switch off a NULL standing answer kept a person active (%)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[v_flag_off,
    $s$CREATE OR REPLACE FUNCTION public.dating_has_relationship(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', ARRAY[v_cron]));
  IF v IS DISTINCT FROM '0:paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the switch off a NULL relationship answer kept a person active (%)', v;
  END IF;
  -- I-2: two people fail gate 2; pausing the first pauses the second by
  -- another hand (the stand-in). The second is neither counted nor touched.
  v := pg_temp.probe(v_ready || ARRAY[
    format($s$UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active' AND user_id NOT IN (%L, %L)$s$, v_first, v_second),
    format($s$UPDATE public.users SET eula_version = '1' WHERE id IN (%L, %L)$s$, v_first, v_second),
    format($s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN IF p_user_id = %L THEN
         UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user', paused_at = now() WHERE user_id = %L AND state = 'active';
       END IF; END $f$$s$, v_first, v_second)],
    format('SELECT pg_temp.cron_count(%L)', ARRAY[v_first, v_second]));
  IF v IS DISTINCT FROM '1:paused/gates/paused,paused/user/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person paused mid-run by another hand gave % (expected 1:paused/gates/paused,paused/user/active)', v;
  END IF;
  -- M-4: one person's gates raise; counted, skipped, the run goes on.
  v_before := pg_temp.metric('dating.gates.failed');
  v := pg_temp.probe(ARRAY[
    format($s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE plpgsql STABLE AS $f$
       BEGIN IF p_user_id = %L THEN RAISE EXCEPTION 'bad row stand-in'; END IF; RETURN true; END $f$$s$, v_raises),
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    format($s$UPDATE public.users SET eula_version = '1' WHERE id = %L$s$, v_eula)],
    format($s$SELECT pg_temp.cron_states(%L) || '/' || (pg_temp.metric('dating.gates.failed') - %s)$s$, ARRAY[v_raises, v_eula], v_before));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a raise in one person''s gates gave % (expected 0:active/-/active,paused/gates/paused/1)', v;
  END IF;
END $g3$;
-- =====================================================================
-- I. (W2, I-5, Spec 1 D18, R13) One writer per pause reason: Dating ->
--    Just for me is paused by the path trigger with path_change; Dating ->
--    Relationship by Spec 1's set_user_path_internal with relationship,
--    and the trigger does nothing; a paused enrolment keeps its first
--    reason; the trigger takes the shared lock order, retries a lock
--    conflict and never raises.
-- =====================================================================
DO $$
DECLARE
  v_just constant uuid := pg_temp.enrolled('60', 'active');
  v_rel constant uuid := pg_temp.enrolled('61', 'active');
  v_user_paused constant uuid := pg_temp.enrolled('62', 'paused', 'user');
  v_draft constant uuid := pg_temp.enrolled('63', 'profile_draft');
  v_none constant uuid := pg_temp.person('64');
  v_back constant uuid := pg_temp.person('65');
  v_paused_at timestamptz;
  v_src text;
BEGIN
  PERFORM pg_temp.as_person(v_just);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_just) IS DISTINCT FROM 'paused/path_change/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Just for me left %, expected paused/path_change/paused', pg_temp.pause_of(v_just);
  END IF;
  PERFORM pg_temp.as_person(v_rel);
  PERFORM public.set_my_path('relationship', true);
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_rel) IS DISTINCT FROM 'paused/relationship/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Relationship left %, expected paused/relationship/paused (Spec 1''s one pause, D18)', pg_temp.pause_of(v_rel);
  END IF;
  SELECT e.paused_at INTO v_paused_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user_paused;
  PERFORM pg_temp.as_person(v_user_paused);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_user_paused) IS DISTINCT FROM 'paused/user/paused'
     OR (SELECT e.paused_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user_paused) IS DISTINCT FROM v_paused_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enrolment already paused by the person lost its first reason (%)', pg_temp.pause_of(v_user_paused);
  END IF;
  PERFORM pg_temp.as_person(v_draft);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_draft) IS DISTINCT FROM 'paused/path_change/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft left on Dating -> Just for me is %', pg_temp.pause_of(v_draft);
  END IF;
  PERFORM pg_temp.as_person(v_none);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_none) IS DISTINCT FROM 'none/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger wrote Dating rows for someone never enrolled (%)', pg_temp.pause_of(v_none);
  END IF;
  -- A move to Dating (here from Just for me, with an active enrolment) changes nothing.
  UPDATE public.users SET path = 'just_me' WHERE id = v_back;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_back, 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state) VALUES (v_back, 'Back', 'active');
  UPDATE public.users SET path = 'dating' WHERE id = v_back;
  IF pg_temp.pause_of(v_back) IS DISTINCT FROM 'active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a move to Dating paused it (%)', pg_temp.pause_of(v_back);
  END IF;
  -- One writer per reason, by body: only the guard trigger and Spec 1's
  -- path setter call the relationship pause, and only the path trigger
  -- writes path_change.
  IF (SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'private') AND p.prosrc LIKE '%pause_dating_for_relationship_user(%'
         AND p.proname <> 'pause_dating_for_relationship_user')
     IS DISTINCT FROM 'set_user_path_internal,sync_dating_pause_on_relationship'
     OR (SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
          WHERE n.nspname IN ('public', 'private') AND p.prosrc LIKE '%''path_change''%')
     IS DISTINCT FROM 'dating_apply_path_pause' THEN -- W2 Task 3 fix round 1 (I-1): the one helper
    RAISE EXCEPTION 'CONTRACT VIOLATED: another function pauses Dating for a path change';
  END IF;
  -- The shared lock order: the setup lock before the first row.
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'private.dating_apply_path_pause(uuid)'::regprocedure); -- W2 Task 3 fix round 1 (I-1)
  IF position('private.dating_lock_setup(p_user)' IN v_src) = 0
     OR position('private.dating_lock_setup(p_user)' IN v_src) > position('UPDATE public.dating_enrollments' IN v_src)
     OR position('FOR UPDATE' IN v_src) = 0 -- W2 Task 3 fix round 1 (M-2): never vacuous
     OR position('FOR UPDATE' IN v_src) > position('UPDATE public.dating_profiles' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger does not take the shared lock order';
  END IF;
  -- W2 Task 3 fix round 1 (C-1): its own 1s lock_timeout (3 tries stay
  -- inside Auth's 8s statement timeout), in the trigger and the helper.
  IF (SELECT coalesce('lock_timeout=1s' = ANY (p.proconfig), false) FROM pg_proc AS p
       WHERE p.oid = 'public.dating_pause_on_path_change()'::regprocedure) IS NOT TRUE
     OR (SELECT coalesce('lock_timeout=1s' = ANY (p.proconfig), false) FROM pg_proc AS p
          WHERE p.oid = 'private.dating_apply_path_pause(uuid)'::regprocedure) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path pause has no 1s lock_timeout of its own';
  END IF;
  IF has_function_privilege('authenticated', 'public.dating_pause_on_path_change()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_pause_on_path_change()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_apply_path_pause(uuid)', 'EXECUTE') -- W2 Task 3 fix round 1
     OR has_function_privilege('service_role', 'private.dating_apply_path_pause(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger function is callable by an API role';
  END IF;
END $$;

-- I2. The trigger never raises: a failing pause is counted and the path
--     change still goes through; a lock conflict is retried (two failures
--     then success pauses; three are counted).
-- [p] moves to Just for me: the error (or 'no error'), then the path, the
-- Dating states and how many path-pause failures were counted since [p_before].
CREATE FUNCTION pg_temp.leave_dating(p uuid, p_before bigint) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  PERFORM pg_temp.as_db();
  RETURN v || '/' || (SELECT u.path FROM public.users AS u WHERE u.id = p) || '/' || pg_temp.pause_of(p)
         || '/' || (pg_temp.metric('dating.path_pause.failed') - p_before);
END $$;

DO $i2$
DECLARE
  v_fail constant uuid := pg_temp.enrolled('66', 'active');
  v_retry constant uuid := pg_temp.enrolled('67', 'active');
  v_busy constant uuid := pg_temp.enrolled('68', 'active');
  v text;
BEGIN
  -- Each stand-in lives inside a probe, which undoes it.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'boom'; END $f$$s$],
    format('SELECT pg_temp.leave_dating(%L, %s)', v_fail, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing pause raised, or went uncounted, or half-paused (%; expected no error/just_me/active/-/active/1)', v;
  END IF;
  -- A sequence counts the calls: it outlives each retry's rolled-back savepoint.
  CREATE TEMP SEQUENCE w2_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$
       BEGIN
         IF nextval('pg_temp.w2_calls') <= 2 THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF;
       END $f$$s$],
    format($s$SELECT pg_temp.leave_dating(%L, %s) || '/' || currval('pg_temp.w2_calls')$s$, v_retry, pg_temp.metric('dating.path_pause.failed')));
  -- Calls: two failed attempts, then the profile trigger's and the pause's own.
  IF v IS DISTINCT FROM 'no error/just_me/paused/path_change/paused/0/4' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock conflicts were not retried into a pause (%; expected no error/just_me/paused/path_change/paused/0/4)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END $f$$s$],
    format('SELECT pg_temp.leave_dating(%L, %s)', v_busy, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: three lock conflicts raised or went uncounted (%; expected no error/just_me/active/-/active/1)', v;
  END IF;
  IF (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.path_pause.failed''%'
     OR (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.gates.busy''%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the path-pause failures and the busy gate runs';
  END IF;
END $i2$;
-- =====================================================================
-- I3. (W2 Task 3 carries) A pause holds until its own way out: a begin
--     re-tap never lifts a pause (the kill switch's, path_change, the
--     person's own); resume and activation refuse while the person's
--     chosen path is Just for me or Relationship (a never-chosen path
--     keeps today's behaviour); each path change writes exactly one pause,
--     by its one writer; the path trigger leaves every change that isn't
--     away from Dating alone and retries only lock conflicts; health
--     shows the gate cron's failures and the undated endings.
-- =====================================================================
-- [p] runs [p_sql] as themselves: the error (or 'no error'), then the
-- enrolment's state/reason and the profile's state.
CREATE FUNCTION pg_temp.call_as(p uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := pg_temp.error_of(p_sql);
  PERFORM pg_temp.as_db();
  RETURN v || '/' || pg_temp.pause_of(p);
END $$;

-- [p] moves to [p_path] while a spy records every enrolment write that
-- changes the state or the pause reason: the writes, in order.
CREATE FUNCTION pg_temp.pause_writes(p uuid, p_path text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := pg_temp.error_of(format('SELECT public.set_my_path(%L, true)', p_path));
  PERFORM pg_temp.as_db();
  RETURN v || '/' || coalesce((SELECT string_agg(w.what, ',' ORDER BY w.n) FROM pg_temp.w3_writes AS w), 'no write');
END $$;

DO $i3$
DECLARE
  v_sg constant uuid := pg_temp.enrolled('31', 'paused', 'same_gender_switch');
  v_pc constant uuid := pg_temp.enrolled('32', 'active');
  v_user constant uuid := pg_temp.enrolled('33', 'paused', 'user');
  v_draft constant uuid := pg_temp.enrolled('34', 'profile_draft');
  v_rel constant uuid := pg_temp.enrolled('35', 'active');
  v_pc_draft constant uuid := pg_temp.enrolled('36', 'profile_draft');
  v_unchosen constant uuid := pg_temp.enrolled('37', 'paused', 'user');
  v_spy_just constant uuid := pg_temp.enrolled('38', 'active');
  v_spy_rel constant uuid := pg_temp.enrolled('39', 'active');
  v_from_rel constant uuid := pg_temp.enrolled('25', 'active');
  v_from_null constant uuid := pg_temp.enrolled('26', 'active');
  v_boom constant uuid := pg_temp.enrolled('27', 'active');
  v_busy constant uuid := pg_temp.enrolled('28', 'active');
  v_rel_draft constant uuid := pg_temp.enrolled('29', 'profile_draft');
  v_suspended constant uuid := pg_temp.enrolled('18', 'suspended');
  v_unchosen_draft constant uuid := pg_temp.person('19');
  v_exited_just constant uuid := pg_temp.enrolled('a2', 'exited');
  v_exited_rel constant uuid := pg_temp.enrolled('a3', 'exited');
  v_rate constant uuid := pg_temp.enrolled('a4', 'profile_draft');
  v_gates constant uuid := pg_temp.enrolled('a5', 'paused', 'gates');
  v_gates_ok constant uuid := pg_temp.enrolled('a6', 'paused', 'gates');
  v_user_noage constant uuid := pg_temp.enrolled('a7', 'paused', 'user');
  v_null_begin constant uuid := pg_temp.person('a8');
  -- Activation's and resume's other gates pass (each probe undoes them).
  v_open constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_field_key_usable() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_complete(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION private.dating_consent_granted(p_user uuid, p_purpose text) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_spy constant text[] := ARRAY[
    $s$CREATE TEMP TABLE w3_writes (n serial, what text)$s$,
    $s$CREATE FUNCTION public.w3_spy() RETURNS trigger LANGUAGE plpgsql AS $f$
       BEGIN
         IF NEW.state IS DISTINCT FROM OLD.state OR NEW.pause_reason IS DISTINCT FROM OLD.pause_reason THEN
           INSERT INTO pg_temp.w3_writes (what) VALUES (NEW.state || ':' || coalesce(NEW.pause_reason, '-'));
         END IF;
         RETURN NEW;
       END $f$$s$,
    $s$CREATE TRIGGER w3_spy BEFORE UPDATE ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w3_spy()$s$];
  v text;
  v_mid text;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT u, 'w2-t3-' || p || '-' || right(u::text, 2), p, 'granted', '1', clock_timestamp()
    FROM unnest(ARRAY[v_sg, v_pc, v_user, v_draft, v_pc_draft, v_suspended]) AS u, unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;

  -- A begin re-tap keeps every pause: the kill switch's on a draft, the
  -- path trigger's, the person's own. A draft still begins.
  v := pg_temp.call_as(v_sg, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-t3-begin-31')$q$);
  IF v IS DISTINCT FROM 'no error/paused/same_gender_switch/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a begin re-tap lifted the kill switch''s pause (%; expected no error/paused/same_gender_switch/paused)', v;
  END IF;
  PERFORM pg_temp.as_person(v_pc);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  v := pg_temp.call_as(v_pc, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-t3-begin-32')$q$);
  IF v IS DISTINCT FROM 'path_not_dating/paused/path_change/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a begin re-tap off the Dating path was not refused, or lifted the path pause (%; expected path_not_dating/paused/path_change/paused)', v;
  END IF;
  -- (Final review M-1) After an exit, on Just for me or Relationship, begin
  -- refuses: no draft a sweep would mislabel as a path pause. A
  -- never-chosen path still begins (above: v_draft keeps 'dating').
  UPDATE public.users SET path = 'just_me' WHERE id = v_exited_just;
  UPDATE public.users SET path = 'relationship' WHERE id = v_exited_rel;
  v := pg_temp.call_as(v_exited_just, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-final-begin-a2')$q$);
  IF v IS DISTINCT FROM 'path_not_dating/exited/-/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin on Just for me after an exit gave % (expected path_not_dating/exited/-/draft)', v;
  END IF;
  -- A path never chosen (Spec 1's legacy NULL) still begins.
  UPDATE public.users SET path = NULL WHERE id = v_null_begin;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_null_begin, 'w2-final-a8-' || p, p, 'granted', '1', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  v := pg_temp.call_as(v_null_begin, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-final-begin-a8')$q$);
  IF v IS DISTINCT FROM 'no error/profile_draft/-/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin refused a person who never chose a path (%; expected no error/profile_draft/-/none)', v;
  END IF;
  -- On Relationship, with the five begins a day spent: the path answers
  -- first (the refusal comes before the rate limit).
  INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count)
  VALUES (v_exited_rel, 'begin_enrollment', now(), 5);
  v := pg_temp.call_as(v_exited_rel, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-final-begin-a3')$q$);
  IF v IS DISTINCT FROM 'path_not_dating/exited/-/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin on Relationship after an exit gave % (expected path_not_dating/exited/-/draft, before the rate limit)', v;
  END IF;
  v := pg_temp.call_as(v_user, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-t3-begin-33')$q$);
  IF v IS DISTINCT FROM 'no error/paused/user/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a begin re-tap lifted the person''s own pause (%)', v;
  END IF;
  v := pg_temp.call_as(v_suspended, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-t3-begin-18')$q$);
  IF v IS DISTINCT FROM 'no error/suspended/-/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a begin re-tap lifted a suspension (%)', v;
  END IF;
  v := pg_temp.call_as(v_draft, $q$SELECT public.begin_dating_enrollment('1', 'spec2-w2-t3-begin-34')$q$);
  IF v IS DISTINCT FROM 'no error/profile_draft/-/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft no longer begins (%)', v;
  END IF;

  -- Resume refuses while the person is on Just for me (the path pause) or
  -- on Relationship (Spec 1's pause, no relationship row yet); back on
  -- Dating it resumes.
  UPDATE public.dating_enrollments SET activated_at = now() - interval '2 days' WHERE user_id IN (v_pc, v_rel, v_unchosen);
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-t3-resume-32'')')$q$, v_pc));
  IF v IS DISTINCT FROM 'path_not_dating/paused/path_change/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume lifted the path pause off the Dating path (%; expected path_not_dating/paused/path_change/paused)', v;
  END IF;
  PERFORM pg_temp.as_person(v_rel);
  PERFORM public.set_my_path('relationship', true);
  PERFORM pg_temp.as_db();
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-t3-resume-35'')')$q$, v_rel));
  IF v IS DISTINCT FROM 'path_not_dating/paused/relationship/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume lifted Spec 1''s pause on the Relationship path (%; expected path_not_dating/paused/relationship/paused)', v;
  END IF;
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.set_my_path(''dating'')')
                                        || ' then ' || pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-t3-resume-32b'')')$q$, v_pc, v_pc));
  IF v IS DISTINCT FROM 'no error/paused/path_change/paused then no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: back on Dating, resume did not lift the path pause (%)', v;
  END IF;
  -- A path never chosen (Spec 1's legacy NULL) keeps today's behaviour.
  UPDATE public.users SET path = NULL WHERE id = v_unchosen;
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-t3-resume-37'')')$q$, v_unchosen));
  IF v IS DISTINCT FROM 'no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume refused a person who never chose a path (%)', v;
  END IF;

  -- Activation refuses a path-paused draft off the Dating path, after a
  -- begin re-tap too; back on Dating it activates.
  PERFORM pg_temp.as_person(v_pc_draft);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.begin_dating_enrollment(''1'', ''spec2-w2-t3-begin-36'')')
                                        || ' then ' || pg_temp.call_as(%L, 'SELECT public.activate_dating_profile(''spec2-w2-t3-activate-36'')')$q$, v_pc_draft, v_pc_draft));
  IF v IS DISTINCT FROM 'path_not_dating/paused/path_change/draft then path_not_dating/paused/path_change/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation lifted the path pause off the Dating path (%)', v;
  END IF;
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.set_my_path(''dating'')')
                                        || ' then ' || pg_temp.call_as(%L, 'SELECT public.activate_dating_profile(''spec2-w2-t3-activate-36b'')')$q$, v_pc_draft, v_pc_draft));
  IF v IS DISTINCT FROM 'no error/paused/path_change/draft then no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: back on Dating, activation did not go through (%)', v;
  END IF;
  UPDATE public.users SET path = NULL WHERE id = v_unchosen_draft;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_unchosen_draft, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state) VALUES (v_unchosen_draft, 'Enrolled 19', 'draft');
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.activate_dating_profile(''spec2-w2-t3-activate-19'')')$q$, v_unchosen_draft));
  IF v IS DISTINCT FROM 'no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation refused a person who never chose a path (%)', v;
  END IF;
  PERFORM pg_temp.as_person(v_rel_draft);
  PERFORM public.set_my_path('relationship', true);
  PERFORM pg_temp.as_db();
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.activate_dating_profile(''spec2-w2-t3-activate-29'')')$q$, v_rel_draft));
  IF v IS DISTINCT FROM 'path_not_dating/paused/relationship/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation lifted Spec 1''s pause on the Relationship path (%)', v;
  END IF;

  -- (Final review M-2) Off the Dating path, activation answers
  -- path_not_dating before the rate limit and the gates: with its ten
  -- activations spent and its gates failing, the person still hears
  -- "choose Dating".
  UPDATE public.users SET path = 'just_me' WHERE id = v_rate;
  INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count)
  VALUES (v_rate, 'profile_activation', now(), 10);
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.activate_dating_profile(''spec2-w2-final-activate-a4'')')$q$, v_rate));
  IF v IS DISTINCT FROM 'path_not_dating/paused/path_change/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activation off the Dating path answered % (expected path_not_dating before the rate limit and the gates)', v;
  END IF;

  -- (Final review M-3) A 'gates' pause (the cron's) resumes only while the
  -- age gate holds; with it, resume goes ahead. Other pauses keep today's
  -- rule.
  UPDATE public.dating_enrollments SET activated_at = now() - interval '2 days' WHERE user_id IN (v_gates, v_gates_ok, v_user_noage);
  v := pg_temp.probe(v_open || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-final-resume-a5'')')$q$, v_gates));
  IF v IS DISTINCT FROM 'resume_gates_not_met/paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gates pause resumed while the age gate fails (%; expected resume_gates_not_met/paused/gates/paused)', v;
  END IF;
  v := pg_temp.probe(v_open || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-final-resume-a5n'')')$q$, v_gates));
  IF v IS DISTINCT FROM 'resume_gates_not_met/paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gates pause resumed on a NULL age gate (%)', v;
  END IF;
  v := pg_temp.probe(v_open, format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-final-resume-a6'')')$q$, v_gates_ok));
  IF v IS DISTINCT FROM 'no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gates pause whose cause is gone did not resume (%)', v;
  END IF;
  v := pg_temp.probe(v_open || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.call_as(%L, 'SELECT public.resume_dating_mode(''spec2-w2-final-resume-a7'')')$q$, v_user_noage));
  IF v IS DISTINCT FROM 'no error/active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the age-gate rule reached a pause other than gates (%)', v;
  END IF;

  -- One writer per change (I-5, D18): each path change writes exactly one
  -- pause, with its own reason.
  v := pg_temp.probe(v_spy, format('SELECT pg_temp.pause_writes(%L, %L)', v_spy_just, 'just_me'));
  IF v IS DISTINCT FROM 'no error/paused:path_change' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Just for me did not write exactly one path_change pause (%)', v;
  END IF;
  v := pg_temp.probe(v_spy, format('SELECT pg_temp.pause_writes(%L, %L)', v_spy_rel, 'relationship'));
  IF v IS DISTINCT FROM 'no error/paused:relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Relationship did not write exactly one relationship pause (%)', v;
  END IF;

  -- (Fix round 1, coordinator ruling on I-2) Choosing Just for me pauses,
  -- whatever the old value (Relationship, never chosen); a move to
  -- Relationship, to Dating, or to a merely NULL path writes nothing.
  UPDATE public.users SET path = 'relationship' WHERE id = v_from_rel;
  v_mid := pg_temp.pause_of(v_from_rel);
  UPDATE public.users SET path = 'just_me' WHERE id = v_from_rel;
  UPDATE public.users SET path = NULL WHERE id = v_from_null;
  v_mid := v_mid || ',' || pg_temp.pause_of(v_from_null);
  UPDATE public.users SET path = 'dating' WHERE id = v_from_null;
  UPDATE public.users SET path = NULL WHERE id = v_from_null;
  v_mid := v_mid || ',' || pg_temp.pause_of(v_from_null);
  UPDATE public.users SET path = 'just_me' WHERE id = v_from_null;
  IF v_mid IS DISTINCT FROM 'active/-/active,active/-/active,active/-/active'
     OR pg_temp.pause_of(v_from_rel) IS DISTINCT FROM 'paused/path_change/paused'
     OR pg_temp.pause_of(v_from_null) IS DISTINCT FROM 'paused/path_change/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger paused a move that was no choice of Just for me, or missed one (%; then % and %)',
      v_mid, pg_temp.pause_of(v_from_rel), pg_temp.pause_of(v_from_null);
  END IF;

  -- Only lock conflicts are retried: any other error is tried once, and
  -- an inner retry's dating:busy is not retried again; both are counted.
  CREATE TEMP SEQUENCE w3_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN PERFORM nextval('pg_temp.w3_calls'); RAISE EXCEPTION 'boom'; END $f$$s$],
    format($s$SELECT pg_temp.leave_dating(%L, %s) || '/' || currval('pg_temp.w3_calls')$s$, v_boom, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-lock failure was retried or went uncounted (%; expected no error/just_me/active/-/active/1/1)', v;
  END IF;
  ALTER SEQUENCE pg_temp.w3_calls RESTART;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN PERFORM nextval('pg_temp.w3_calls'); RAISE EXCEPTION 'dating:busy' USING ERRCODE = '40P01'; END $f$$s$],
    format($s$SELECT pg_temp.leave_dating(%L, %s) || '/' || currval('pg_temp.w3_calls')$s$, v_busy, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inner retry''s dating:busy was retried again or went uncounted (%; expected no error/just_me/active/-/active/1/1)', v;
  END IF;

  IF (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.gates.failed''%'
     OR (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.gentle_wait.undated''%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the gate cron''s failures and the undated endings';
  END IF;
END $i3$;

-- =====================================================================
-- I4. (W2 Task 3 fix round 1; batch-2 review C-1, I-1) A path change never
--     fails, a statement timeout included; a failed path pause is caught
--     by the gate cron's sweep (per person, counted, a failure left for the
--     next run), and until then the person is never a candidate; a move
--     into Dating or Relationship, or to a merely NULL path, never touches
--     Dating.
-- =====================================================================
-- Phase 1: 58 (active), 59 (draft) and 00 (active) leave Dating while every
-- pause fails; phase 2: the cron runs while 00's still fails; phase 3: the
-- cron runs with the real pause. 99 (active, path never chosen) is never
-- swept. The gates pass, so only the sweep can pause anyone here.
CREATE FUNCTION pg_temp.sweep_story(p_a uuid, p_d uuid, p_x uuid, p_null uuid) RETURNS text LANGUAGE plpgsql AS $sw$
DECLARE
  v_real constant text := pg_get_functiondef('public.invalidate_dating_for_user(uuid,text)'::regprocedure);
  v_failed constant bigint := pg_temp.metric('dating.path_pause.failed');
  v_swept constant bigint := pg_temp.metric('dating.path_pause.swept');
  v text := '';
  p uuid;
BEGIN
  EXECUTE $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
            LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'boom'; END $f$$s$;
  FOREACH p IN ARRAY ARRAY[p_a, p_d, p_x] LOOP
    PERFORM pg_temp.as_person(p);
    v := v || pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$) || ',';
    PERFORM pg_temp.as_db();
  END LOOP;
  v := v || pg_temp.pause_of(p_a) || ',' || pg_temp.pause_of(p_d) || ','
         || public.dating_eligibility(p_a, 'candidate') || ',' || public.dating_eligibility(p_a, 'setup')
         || ',' || (pg_temp.metric('dating.path_pause.failed') - v_failed);
  EXECUTE v_real;
  EXECUTE format($s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
                   LANGUAGE plpgsql AS $f$ BEGIN IF p_user_id = %L THEN RAISE EXCEPTION 'boom'; END IF; END $f$$s$, p_x);
  PERFORM public.enforce_dating_lifecycle_gates();
  v := v || ' | ' || pg_temp.pause_of(p_a) || ',' || pg_temp.pause_of(p_d) || ',' || pg_temp.pause_of(p_x)
         || ',' || pg_temp.pause_of(p_null) || ',' || (pg_temp.metric('dating.path_pause.swept') - v_swept)
         || ',' || (pg_temp.metric('dating.path_pause.failed') - v_failed);
  EXECUTE v_real;
  PERFORM public.enforce_dating_lifecycle_gates();
  RETURN v || ' | ' || pg_temp.pause_of(p_x) || ',' || pg_temp.pause_of(p_null)
           || ',' || (pg_temp.metric('dating.path_pause.swept') - v_swept);
END $sw$;

-- [p] moves to Relationship, to a merely NULL path and to Dating, as the
-- database: the Dating states and how many path-pause failures were counted.
CREATE FUNCTION pg_temp.early_out(p uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_failed constant bigint := pg_temp.metric('dating.path_pause.failed');
BEGIN
  UPDATE public.users SET path = 'relationship' WHERE id = p;
  UPDATE public.users SET path = NULL WHERE id = p;
  UPDATE public.users SET path = 'dating' WHERE id = p;
  RETURN pg_temp.pause_of(p) || '/' || (pg_temp.metric('dating.path_pause.failed') - v_failed);
END $$;

DO $i4$
DECLARE
  v_a constant uuid := pg_temp.enrolled('58', 'active');
  v_d constant uuid := pg_temp.enrolled('59', 'profile_draft');
  v_x constant uuid := pg_temp.enrolled('00', 'active');
  v_null constant uuid := pg_temp.enrolled('99', 'active');
  v_move constant uuid := pg_temp.enrolled('69', 'active');
  v text;
BEGIN
  UPDATE public.users SET path = NULL WHERE id = v_null;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$],
    format('SELECT pg_temp.sweep_story(%L, %L, %L, %L)', v_a, v_d, v_x, v_null));
  IF v IS DISTINCT FROM
     'no error,no error,no error,active/-/active,profile_draft/-/draft,account_unavailable,eligible,3'
     || ' | paused/path_change/paused,paused/path_change/draft,active/-/active,active/-/active,2,4'
     || ' | paused/path_change/paused,active/-/active,3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed path pause was not caught by the sweep, or the person was a candidate meanwhile (%)', v;
  END IF;
  -- C-1: a statement timeout (57014) inside the pause is caught and counted;
  -- the path change completes.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'cancel stand-in' USING ERRCODE = '57014'; END $f$$s$],
    format('SELECT pg_temp.leave_dating(%L, %s)', v_move, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a statement timeout in the path pause failed the path change or went uncounted (%; expected no error/just_me/active/-/active/1)', v;
  END IF;
  -- A move to Relationship, to NULL or to Dating never reaches the pause
  -- (with every lock failing, nothing is counted).
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_lock_setup(p_user uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'lock stand-in' USING ERRCODE = '55P03'; END $f$$s$],
    format('SELECT pg_temp.early_out(%L)', v_move));
  IF v IS DISTINCT FROM 'active/-/active/0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a move that is not off the Dating path reached the path pause (%; expected active/-/active/0)', v;
  END IF;
  -- The helper itself pauses only a chosen path other than Dating or
  -- Relationship: on Dating, on Relationship, on NULL and for no one it
  -- does nothing; a never-chosen path stays a candidate question for gates 5-6.
  UPDATE public.users SET path = 'relationship' WHERE id = v_a;
  UPDATE public.dating_enrollments SET state = 'active', pause_reason = NULL, paused_at = NULL WHERE user_id = v_a;
  v := private.dating_apply_path_pause(v_move)::text || '/' || pg_temp.pause_of(v_move)
       || ',' || private.dating_apply_path_pause(v_a)::text || '/' || pg_temp.pause_of(v_a)
       || ',' || private.dating_apply_path_pause(v_null)::text || '/' || pg_temp.pause_of(v_null)
       || ',' || private.dating_apply_path_pause(NULL)::text
       || ',' || public.dating_eligibility(v_null, 'candidate');
  IF v IS DISTINCT FROM 'false/active/-/active,false/active/-/active,false/active/-/active,false,country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path pause (or the candidate gate) acted on a path that is Dating, Relationship or never chosen (%)', v;
  END IF;
  IF (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.path_pause.swept''%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the path sweep';
  END IF;
END $i4$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_eligibility_contracts: all held'; END $$;
ROLLBACK;
