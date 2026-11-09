-- supabase/tests/country_safety_config_contracts.sql
-- Spec 2 W1b and W1d (§2.2, §2.3, §2.4, §7.1, §7.5; R-6, I-3, Q19b): the
-- seeds (A), immutable rows (B), the environment and production-mode
-- refusals (C), the exclusion-key readiness check (C3), public-config
-- parity (D), turning same-gender off (E0: the kill switch's locks; E:
-- W1d's kill switch; E2: an
-- exposure-reducing publish is never refused in production), the effective
-- context (F; the away streak F2 from W1c), validation (G) and the dev
-- script's refusal in production mode (H).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, FROM THE REPO ROOT
-- (section H reads supabase/sql/dev_enable_spec2_dating_flags.sql):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql
-- Fixture ids 5e2b0000-0000-0000-0000-0000000000NN; phones 15558701NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', '', true);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);
  -- C3: the contract key's fingerprint is stored, as the owner does once
  -- after setting the key (checklist items 2 and 11; fix round 1, M-4).
  PERFORM private.seed_dating_exclusion_key_fingerprint();
  -- W1d (batch-10 carry): Dating opens only under a ready field key too, so
  -- the contract key is in the GUC (development) and Vault (production),
  -- its fingerprint seeded as the owner does (checklist item 15).
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef', true);
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef');
  IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the contract field key could not be seeded';
  END IF;
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_owner() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- publish_country_config as the service role (its only caller).
CREATE FUNCTION pg_temp.publish(p_country text, p_values jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.publish_country_config(p_country, p_values);
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.current(p_country text) RETURNS public.country_safety_config LANGUAGE sql AS $$
  SELECT * FROM public.country_safety_config WHERE country_code = p_country AND is_current;
$$;

-- Anon's view of the two public reads.
CREATE FUNCTION pg_temp.anon_config() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  v := jsonb_build_object('public', public.get_public_app_config(), 'availability', public.get_dating_availability());
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

-- The message [p_sql] raised (as the owner), or NULL.
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception THEN
  RETURN SQLERRM;
END $$;

CREATE TEMP TABLE public_before (config jsonb) ON COMMIT DROP;
INSERT INTO public_before SELECT pg_temp.anon_config() -> 'public';

-- =====================================================================
-- A. Seeds: one current row per country, every one closed (R-6).
-- =====================================================================
DO $$
DECLARE
  v_gh public.country_safety_config := pg_temp.current('GH');
  v_gb public.country_safety_config := pg_temp.current('GB');
  v_fr public.country_safety_config := public.dating_country_config('fr');
BEGIN
  IF (SELECT count(*) FROM public.country_safety_config WHERE version = 1) IS DISTINCT FROM 73
     OR EXISTS (SELECT 1 FROM public.country_safety_config GROUP BY country_code HAVING count(*) FILTER (WHERE is_current) IS DISTINCT FROM 1)
     OR EXISTS (SELECT 1 FROM public.country_safety_config WHERE version = 1 AND dating_enabled) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seeds are not 73 closed rows with one current row each';
  END IF;
  IF (SELECT count(*) FROM public.country_safety_config WHERE version = 1 AND tier = 1) IS DISTINCT FROM 28
     OR (SELECT count(*) FROM public.country_safety_config WHERE version = 1 AND tier = 2) IS DISTINCT FROM 44
     OR EXISTS (SELECT 1 FROM public.country_safety_config WHERE tier IN (1, 2) AND same_gender_enabled)
     OR (SELECT tier FROM public.country_safety_config WHERE country_code = 'NE' AND version = 1) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Tier 1/2 seeds are wrong (28 + 44, same-gender off, Niger Tier 1)';
  END IF;
  IF v_gh.tier IS DISTINCT FROM 1 OR v_gh.open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] OR v_gh.same_gender_enabled
     OR jsonb_array_length(v_gh.region_list) IS DISTINCT FROM 16 OR v_gh.reference_tz IS DISTINCT FROM 'Africa/Accra' OR v_gh.generation_hour_utc IS DISTINCT FROM 3
     OR (SELECT jsonb_agg(s ->> 'code' ORDER BY s ->> 'code') FROM jsonb_array_elements(v_gh.region_list) AS r,
                jsonb_array_elements(r -> 'sides') AS s) IS DISTINCT FROM '["accra", "kumasi", "outside_kumasi", "tema"]'::jsonb
     OR jsonb_array_length(v_gh.id_documents) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana seed is wrong';
  END IF;
  IF v_gb.tier IS DISTINCT FROM 3 OR v_gb.open_regions IS NOT NULL OR NOT v_gb.same_gender_enabled
     OR jsonb_array_length(v_gb.region_list) IS DISTINCT FROM 12 OR v_gb.reference_tz IS DISTINCT FROM 'Europe/London' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK seed is wrong';
  END IF;
  IF v_fr.version IS DISTINCT FROM 0 OR v_fr.tier IS DISTINCT FROM 3 OR v_fr.dating_enabled OR NOT v_fr.same_gender_enabled
     OR (public.dating_country_config('X1')).country_code IS NOT NULL THEN -- batch 4: a row IS NOT NULL only when no field is NULL
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country with no row does not resolve to the default (tier 3, closed, same-gender allowed)';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.country_safety_config'::regclass)
     OR has_table_privilege('anon', 'public.country_safety_config', 'SELECT')
     OR has_table_privilege('authenticated', 'public.country_safety_config', 'SELECT')
     OR has_function_privilege('authenticated', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.get_dating_availability()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.record_dating_session_context(uuid,text,text)', 'EXECUTE') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the country config grants are wrong';
  END IF;
  -- Fix round 1, C-1: the service role reads the config and never writes it.
  IF has_table_privilege('service_role', 'public.country_safety_config', 'SELECT') IS NOT TRUE
     OR has_table_privilege('service_role', 'public.country_safety_config', 'INSERT') IS NOT FALSE
     OR has_table_privilege('service_role', 'public.country_safety_config', 'UPDATE') IS NOT FALSE
     OR has_table_privilege('service_role', 'public.country_safety_config', 'DELETE') IS NOT FALSE
     OR has_table_privilege('service_role', 'public.country_safety_config', 'TRUNCATE') IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can write country_safety_config';
  END IF;
  -- Fix round 1, I-1: a code that is no assigned ISO 3166-1 country has no
  -- config; M-4: every country with a row has a calling code.
  IF (public.dating_country_config('ZZ')).country_code IS NOT NULL
     OR (public.dating_country_config('EU')).country_code IS NOT NULL
     OR private.dating_iso_country(' gb ') IS DISTINCT FROM 'GB'
     OR private.dating_iso_country('XK') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.country_safety_config AS c WHERE private.dating_iso_country(c.country_code) IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-ISO code resolves to a country config';
  END IF;
  IF EXISTS (SELECT 1 FROM public.country_safety_config AS c
              WHERE NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = c.country_code)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a configured country has no calling code';
  END IF;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_same_gender_matching') IS DISTINCT FROM false
     OR (SELECT count(*) FROM private.flag_production_gates
          WHERE flag_key IN ('dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
                             'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')) IS DISTINCT FROM 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_same_gender_matching is not inserted off, or a Dating flag has no production gate row';
  END IF;
END $$;

-- =====================================================================
-- B. A published row never changes and is never deleted.
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.err('UPDATE public.country_safety_config SET tier = 3 WHERE country_code = ''NG'' AND version = 1')
       IS DISTINCT FROM 'config:immutable'
     OR pg_temp.err('UPDATE public.country_safety_config SET is_current = false, dating_enabled = true WHERE country_code = ''NG''')
       IS DISTINCT FROM 'config:immutable'
     OR pg_temp.err('DELETE FROM public.country_safety_config WHERE country_code = ''NG''')
       IS DISTINCT FROM 'config:immutable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a published country row could be changed or deleted';
  END IF;
END $$;

-- =====================================================================
-- E0. (W1d, batch-7 I-5) The kill switch's locks, checked before any
--    other section turns the global flag off (an advisory lock is held
--    until ROLLBACK, so later checks would see every lock already held):
--    one country's switch takes that country's same-gender lock
--    EXCLUSIVE, and only that one; the global flag off takes every
--    configured country's.
-- =====================================================================
-- This session holds the country's same-gender lock EXCLUSIVE.
CREATE FUNCTION pg_temp.sg_exclusive(p_code text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_locks AS l
                  WHERE l.locktype = 'advisory' AND l.pid = pg_backend_pid() AND l.granted
                    AND l.mode = 'ExclusiveLock' AND l.objsubid = 2
                    AND l.classid = ((hashtext('dating_same_gender')::bigint + 4294967296) % 4294967296)::oid
                    AND l.objid = ((hashtext(p_code)::bigint + 4294967296) % 4294967296)::oid);
$$;

DO $$
DECLARE
  v jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM (SELECT DISTINCT country_code::text AS c FROM public.country_safety_config) AS x
              WHERE pg_temp.sg_exclusive(x.c)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section E0 must run before anything holds a same-gender lock exclusive';
  END IF;
  PERFORM pg_temp.publish('IE', '{"same_gender_enabled": true}');
  v := pg_temp.publish('IE', '{"same_gender_enabled": false}');
  IF (v ->> 'switched')::boolean IS NOT TRUE OR (v ->> 'affected')::int IS DISTINCT FROM 0
     OR NOT pg_temp.sg_exclusive('IE') OR pg_temp.sg_exclusive('GB') OR pg_temp.sg_exclusive('GH') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ireland''s switch did not take exactly Ireland''s same-gender lock exclusive: %', v;
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF EXISTS (SELECT 1 FROM (SELECT DISTINCT country_code::text AS c FROM public.country_safety_config) AS x
              WHERE NOT pg_temp.sg_exclusive(x.c)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning the global flag off did not lock every country exclusive';
  END IF;
  -- Section B2 truncates: no publish's deferred check may still be pending.
  SET CONSTRAINTS public.country_safety_config_has_current IMMEDIATE;
  SET CONSTRAINTS public.country_safety_config_has_current DEFERRED;
END $$;

-- =====================================================================
-- B2. (Fix round 1, C-1, M-5) The service role can't write the table; a
--     TRUNCATE is refused; a country left with no current row reads closed,
--     Tier 1, same-gender off, and a transaction can't end that way.
-- =====================================================================
DO $$
DECLARE
  v_state text;
  v_cfg public.country_safety_config;
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    INSERT INTO public.country_safety_config (country_code, version, tier, dating_enabled, same_gender_enabled, published_by)
    VALUES ('NL', 1, 3, true, true, 'direct');
    v_state := 'inserted';
  EXCEPTION WHEN insufficient_privilege THEN
    v_state := 'refused';
  END;
  IF v_state IS DISTINCT FROM 'refused' THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role inserted a country row directly (%)', v_state;
  END IF;
  BEGIN
    UPDATE public.country_safety_config SET is_current = false WHERE country_code = 'IR' AND is_current;
    v_state := 'updated';
  EXCEPTION WHEN insufficient_privilege THEN
    v_state := 'refused';
  END;
  PERFORM pg_temp.as_owner();
  IF v_state IS DISTINCT FROM 'refused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role un-currented a country row directly (%)', v_state;
  END IF;

  IF pg_temp.err('TRUNCATE public.country_safety_config') IS DISTINCT FROM 'config:immutable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: country_safety_config could be truncated';
  END IF;

  -- The reviewer's reproduction, as the owner with triggers off: Iran has
  -- rows but no current one.
  SET LOCAL session_replication_role = replica;
  UPDATE public.country_safety_config SET is_current = false WHERE country_code = 'IR' AND is_current;
  SET LOCAL session_replication_role = origin;
  v_cfg := public.dating_country_config('IR');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v := public.dating_effective_context('IR', 'GB', 'IR', NULL);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF v_cfg.tier IS DISTINCT FROM 1 OR v_cfg.same_gender_enabled IS NOT FALSE OR v_cfg.dating_enabled IS NOT FALSE
     OR v_cfg.is_current IS NOT FALSE OR v_cfg.version IS DISTINCT FROM 1
     OR (v ->> 'same_gender_allowed_here')::boolean IS NOT FALSE OR (v ->> 'effective_tier')::int IS DISTINCT FROM 1
     OR (v ->> 'dating_allowed_here')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphaned country fell back to a permissive default: % / %', to_jsonb(v_cfg), v;
  END IF;
  SET LOCAL session_replication_role = replica;
  UPDATE public.country_safety_config SET is_current = true WHERE country_code = 'IR' AND version = 1;
  SET LOCAL session_replication_role = origin;
  -- The UK (Tier 3, same-gender on) orphaned reads Tier 1, same-gender off too.
  SET LOCAL session_replication_role = replica;
  UPDATE public.country_safety_config SET is_current = false WHERE country_code = 'GB' AND is_current;
  SET LOCAL session_replication_role = origin;
  v_cfg := public.dating_country_config('GB');
  IF v_cfg.tier IS DISTINCT FROM 1 OR v_cfg.same_gender_enabled IS NOT FALSE OR v_cfg.dating_enabled IS NOT FALSE
     OR jsonb_array_length(v_cfg.region_list) IS DISTINCT FROM 12 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphaned Tier 3 country did not read closed, Tier 1, same-gender off: %', to_jsonb(v_cfg);
  END IF;
  SET LOCAL session_replication_role = replica;
  -- Spec 2 W3b (I-3): the newest row was the current one before the probe.
  UPDATE public.country_safety_config SET is_current = true WHERE country_code = 'GB'
     AND version = (SELECT max(c.version) FROM public.country_safety_config AS c WHERE c.country_code = 'GB');
  SET LOCAL session_replication_role = origin;

  -- With triggers on, orphaning a country fails when the constraint is checked.
  v_state := NULL;
  BEGIN
    UPDATE public.country_safety_config SET is_current = false WHERE country_code = 'IR' AND is_current;
    SET CONSTRAINTS public.country_safety_config_has_current IMMEDIATE;
    v_state := 'orphaned';
  EXCEPTION WHEN raise_exception THEN
    v_state := SQLERRM;
  END;
  SET CONSTRAINTS public.country_safety_config_has_current DEFERRED;
  IF v_state IS DISTINCT FROM 'config:no_current_row' OR (pg_temp.current('IR')).version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a transaction could leave a country with no current row (%)', v_state;
  END IF;
END $$;

-- =====================================================================
-- C. Environment (R-6): development reports the checks, production
--    enforces them.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_gh_before integer; -- Spec 2 W3b (I-3)
  v_gb_before integer; -- Spec 2 W3b (I-3)
  v_evidence constant jsonb := '{"osa_illegal_harms_assessment": "REF-1", "osa_childrens_access_assessment": "REF-2",
    "highly_effective_age_assurance": "REF-3", "dpia": "REF-4", "pen_test": "REF-5",
    "safety_owner_and_moderator": "REF-6", "reviewer_signoffs": "REF-7"}';
BEGIN
  IF private.attune_environment() IS DISTINCT FROM 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with attune_environment unset the project does not read development';
  END IF;
  -- Spec 2 W3b (I-3): a later migration may have published GH again (its
  -- faith list), so the new version is the current one plus one.
  v_gh_before := (pg_temp.current('GH')).version;
  v := pg_temp.publish('GH', '{"dating_enabled": true, "published_by": "contract"}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'version')::int IS DISTINCT FROM v_gh_before + 1
     OR v -> 'checks' IS DISTINCT FROM '["evidence_missing", "resources_not_verified"]'::jsonb
     OR NOT (pg_temp.current('GH')).dating_enabled
     OR (SELECT is_current FROM public.country_safety_config WHERE country_code = 'GH' AND version = v_gh_before) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not publish GH with the checks reported: %', v;
  END IF;

  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_gb_before := (pg_temp.current('GB')).version; -- Spec 2 W3b (I-3)
  v := pg_temp.publish('GB', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["evidence_missing", "resources_not_verified"]}'::jsonb
     OR (pg_temp.current('GB')).version IS DISTINCT FROM v_gb_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production published Dating on without evidence: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence,
                                                 'resources_verified_at', now() - interval '91 days'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed' OR v -> 'checks' IS DISTINCT FROM '["resources_not_verified"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted support resources verified over 90 days ago: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence || '{"pen_test": " "}',
                                                 'resources_verified_at', now()));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted a blank evidence reference: %', v;
  END IF;
  v := pg_temp.publish('NG', '{"same_gender_enabled": true}');
  IF v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb OR (pg_temp.current('NG')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production turned same-gender on in a Tier 1 country without the reconsideration: %', v;
  END IF;
  v := pg_temp.publish('NG', '{"same_gender_enabled": true, "legal_checklist": {"same_gender_reconsideration":
          {"legal_opinion": "REF-A", "lgbtq_consultation": "REF-B", "tier1_protections": ""}}}');
  IF v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted a blank Tier 1 protections reference: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence,
                                                 'resources_verified_at', now()));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '[]'::jsonb OR NOT (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a fully evidenced publish: %', v;
  END IF;
  -- A country with no row has an empty checklist: never "every key has
  -- evidence".
  v := pg_temp.publish('FR', jsonb_build_object('dating_enabled', true, 'resources_verified_at', now()));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb OR (public.dating_country_config('FR')).version IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened a country with an empty legal checklist: %', v;
  END IF;
  -- Closing a country needs no evidence.
  v := pg_temp.publish('GB', '{"dating_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused to close a country: %', v;
  END IF;

  -- Fix round 1, I-2: a downgrade keeps the Tier 1/2 reconsideration and
  -- needs its own review, in one step or two.
  v := pg_temp.publish('NG', '{"tier": 3, "same_gender_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed",
                          "checks": ["same_gender_reconsideration_missing", "tier_review_missing"]}'::jsonb
     OR (pg_temp.current('NG')).version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production downgraded a Tier 1 country and turned same-gender on in one step: %', v;
  END IF;
  v := pg_temp.publish('NG', '{"tier": 3}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["tier_review_missing"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production downgraded a Tier 1 country without a tier review: %', v;
  END IF;
  v := pg_temp.publish('SO', '{"tier": 3, "legal_checklist": {"tier_review": " "}}');
  IF v -> 'checks' IS DISTINCT FROM '["tier_review_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted a blank tier review: %', v;
  END IF;
  v := pg_temp.publish('SO', '{"tier": 3, "legal_checklist": {"tier_review": "REF-T"}}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('SO')).tier IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused an evidenced tier review: %', v;
  END IF;
  -- W1 final fix (M-7): each downgrade needs its own review reference
  -- (the one a first downgrade gave never covers a later one), and a
  -- reference that is not a string (an object) is no reference. (Yemen:
  -- no other section uses it.)
  v := pg_temp.publish('YE', '{"tier": 2, "legal_checklist": {"tier_review": {}}}');
  IF v -> 'checks' IS DISTINCT FROM '["tier_review_missing"]'::jsonb OR (pg_temp.current('YE')).tier IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted an object as a tier review: %', v;
  END IF;
  v := pg_temp.publish('YE', '{"tier": 2, "legal_checklist": {"tier_review": "REF-YE-1"}}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('YE')).tier IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a first evidenced downgrade: %', v;
  END IF;
  v := pg_temp.publish('YE', '{"tier": 3}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["tier_review_missing"]}'::jsonb
     OR (pg_temp.current('YE')).tier IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second downgrade reused the first one''s tier review: %', v;
  END IF;
  v := pg_temp.publish('YE', '{"tier": 3, "legal_checklist": {"tier_review": "REF-YE-1"}}');
  IF v -> 'checks' IS DISTINCT FROM '["tier_review_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second downgrade restating the old tier review was accepted: %', v;
  END IF;
  v := pg_temp.publish('YE', '{"tier": 3, "legal_checklist": {"tier_review": "REF-YE-2"}}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('YE')).tier IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a second downgrade with its own review: %', v;
  END IF;

  -- Fix round 1, I-3: dropping checklist keys is refused; a checklist
  -- without the baseline never counts as evidence.
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', '{"dpia": "REF"}'::jsonb,
                                                 'resources_verified_at', now()));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:checklist_keys_removed"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a publish dropped legal checklist keys: %', v;
  END IF;
  v := pg_temp.publish('GH', '{"dating_enabled": true, "legal_checklist": {"same_gender_reconsideration": {}}}');
  IF v ->> 'reason' IS DISTINCT FROM 'config:checklist_keys_removed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s checklist could be replaced by an empty reconsideration: %', v;
  END IF;
  v := pg_temp.publish('FR', jsonb_build_object('dating_enabled', true, 'resources_verified_at', now(),
                                                 'legal_checklist', '{"same_gender_reconsideration": {}}'::jsonb));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened a country whose only checklist key is the reconsideration: %', v;
  END IF;
  v := pg_temp.publish('FR', jsonb_build_object('dating_enabled', true, 'resources_verified_at', now(),
                                                 'legal_checklist', '{"x": "y"}'::jsonb));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb OR (public.dating_country_config('FR')).version IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened a country without the baseline evidence: %', v;
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
END $$;

-- =====================================================================
-- C3. (W1b, batch-2 carry, I-5) Dating opens in a country only under a
--    set dating_exclusion_key whose stored fingerprint matches it: a
--    missing key, a missing fingerprint or a rotated key is reported as
--    exclusion_key_not_ready (development) and refused (production).
--    Closing a country never needs it, and a publish never seeds it. (The
--    preamble seeds the contract key's fingerprint through the owner's
--    seeder, so sections C and H read a ready key.)
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_refused constant jsonb := '{"ok": false, "reason": "config:production_checks_failed", "checks": ["exclusion_key_not_ready"]}';
  v_open constant jsonb := jsonb_build_object('dating_enabled', true, 'resources_verified_at', now());
BEGIN
  IF (pg_temp.current('GB')).dating_enabled
     OR NOT ((pg_temp.current('GB')).legal_checklist ? 'reviewer_signoffs') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section C did not leave GB closed and evidenced';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'production', true);

  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := pg_temp.publish('GB', v_open);
  IF v IS DISTINCT FROM v_refused OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened GB without dating_exclusion_key: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);

  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  v := pg_temp.publish('GB', v_open);
  IF v IS DISTINCT FROM v_refused OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened GB with no stored key fingerprint: %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a publish seeded the key fingerprint';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := pg_temp.publish('GB', v_open);
  IF v IS DISTINCT FROM v_refused OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened GB with neither a key nor a fingerprint: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);
  PERFORM private.seed_dating_exclusion_key_fingerprint();

  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-rotated-exclusion-key', true);
  v := pg_temp.publish('GB', v_open);
  IF v IS DISTINCT FROM v_refused OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened GB under a rotated dating_exclusion_key: %', v;
  END IF;
  -- Closing needs no key.
  v := pg_temp.publish('GB', '{"dating_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused to close GB under a rotated key: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);

  v := pg_temp.publish('GB', v_open);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '[]'::jsonb
     OR NOT (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused GB under the matching key: %', v;
  END IF;
  v := pg_temp.publish('GB', '{"dating_enabled": false}');

  -- Development reports it and publishes.
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := pg_temp.publish('GB', v_open);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '["exclusion_key_not_ready"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not report a missing key: %', v;
  END IF;
  v := pg_temp.publish('GB', '{"dating_enabled": false}');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);
  IF (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section C3 left GB open';
  END IF;
END $$;

-- =====================================================================
-- D. Public config (I-3): the seam reads the table; the interim row is
--    gone; a close drops the country in the same transaction; every
--    other key of get_public_app_config is unchanged.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_before jsonb := (SELECT config FROM public_before);
BEGIN
  IF EXISTS (SELECT 1 FROM public.app_public_config WHERE key = 'dating_open_countries') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the interim app_public_config row is still there';
  END IF;
  IF v_before #> '{config,dating_open_countries}' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with every seed closed the open-country list is %', v_before #> '{config,dating_open_countries}';
  END IF;
  PERFORM pg_temp.publish('GB', '{"dating_enabled": true}');
  v := pg_temp.anon_config();
  IF v #> '{public,config,dating_open_countries}' IS DISTINCT FROM '["GB", "GH"]'::jsonb
     OR (SELECT jsonb_agg(c ->> 'code' ORDER BY c ->> 'code') FROM jsonb_array_elements(v #> '{availability,countries}') AS c)
          IS DISTINCT FROM v #> '{public,config,dating_open_countries}'
     OR v #> '{availability,countries}' IS DISTINCT FROM
          '[{"code": "GB", "open_regions": null},
            {"code": "GH", "open_regions": [{"code": "AA", "name_key": "dating_region_gh_aa"},
                                            {"code": "AH", "name_key": "dating_region_gh_ah"}]}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the public open-country list and get_dating_availability disagree: %', v;
  END IF;
  PERFORM pg_temp.publish('GB', '{"dating_enabled": false}');
  v := pg_temp.anon_config();
  IF v #> '{public,config,dating_open_countries}' IS DISTINCT FROM '["GH"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing GB did not drop it from the public list in the same transaction: %', v;
  END IF;
  IF (v -> 'public') #- '{config,dating_open_countries}' IS DISTINCT FROM v_before #- '{config,dating_open_countries}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another get_public_app_config key changed: % vs %', v -> 'public', v_before;
  END IF;
  -- Fix round 1, M-9: the interim row can't come back.
  BEGIN
    INSERT INTO public.app_public_config (key, value) VALUES ('dating_open_countries', '["NL"]');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the interim dating_open_countries row could be written again';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $$;

-- =====================================================================
-- E. (W1d) The kill switch (§2.4, 10 S3): turning same-gender off for a
--    country, or the global flag off (or its row deleted or renamed),
--    deletes the disallowed answers, pauses those people, takes the
--    country out of not-plain people's other-countries lists, invalidates
--    every open introduction there that isn't man-woman and closes every
--    such active match ('other', sealed 30 days; owner ruling 2026-11-06),
--    in the publishing transaction, under the country's EXCLUSIVE
--    same-gender lock; man-woman people, introductions and matches are
--    untouched; an unreadable row takes the restrictive path, counted;
--    nothing is sent. Without a usable field key the switch is published
--    and the purge is reported pending (nothing is wiped).
-- =====================================================================
CREATE FUNCTION pg_temp.sg_person(p_n text, p_country text, p_identity jsonb, p_seeking jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (pg_temp.id(p_n), '15558701' || p_n, now());
  INSERT INTO public.users (id, phone, display_name) VALUES (pg_temp.id(p_n), '15558701' || p_n, 'SG ' || p_n);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (pg_temp.id(p_n), 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code, profile_state, gender_visible)
  VALUES (pg_temp.id(p_n), 'SG ' || p_n, p_country, CASE p_country WHEN 'GH' THEN 'AA' ELSE 'TLI' END, 'active', true);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (pg_temp.id(p_n), private.dating_field_encrypt(p_identity), private.dating_field_encrypt(p_seeking));
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid, p_state text DEFAULT 'presented', p_alg text DEFAULT 'w1d-switch')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(p_a, p_b), p_alg) RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(p_a, p_b), p_alg) RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', p_state,
          p_alg, v_low, v_high, 0.5) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- The stored (decrypted) answers.
CREATE FUNCTION pg_temp.identity_of(p_u uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT private.dating_field_decrypt(s.identity_enc) FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_u;
$$;
CREATE FUNCTION pg_temp.seeking_of(p_u uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT private.dating_field_decrypt(s.seeking_enc) FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_u;
$$;
CREATE FUNCTION pg_temp.enrolled(p_u uuid) RETURNS text LANGUAGE sql AS $$
  SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = p_u;
$$;
CREATE FUNCTION pg_temp.intro_state(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT i.state FROM public.dating_introductions AS i WHERE i.id = p_id;
$$;
-- The pending purges (fix round 1, I-1), as scopes in code order.
CREATE FUNCTION pg_temp.pending() RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(k.scope, ',' ORDER BY k.scope COLLATE "C"), '') FROM private.dating_kill_switch_pending AS k;
$$;

CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid, p_state text DEFAULT 'active') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason, closed_at)
  VALUES (least(p_a, p_b), greatest(p_a, p_b), p_state,
          CASE WHEN p_state = 'active' THEN NULL ELSE p_state END, CASE WHEN p_state = 'active' THEN NULL ELSE now() END)
  RETURNING id;
$$;

-- The match's state/reason, and whether it is sealed about 30 days from now.
CREATE FUNCTION pg_temp.match_is(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT m.state || '/' || coalesce(m.closed_reason, '-') || '/'
         || CASE WHEN m.evidence_until IS NULL THEN 'unsealed'
                 WHEN m.evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days' THEN 'sealed30'
                 ELSE 'sealed?' END
    FROM public.dating_matches AS m WHERE m.id = p_id;
$$;

CREATE FUNCTION pg_temp.counter(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(c.count), 0)::bigint FROM public.metric_counters AS c WHERE c.key = p_key;
$$;

CREATE FUNCTION pg_temp.sent() RETURNS bigint LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM public.scheduled_notifications) + (SELECT count(*) FROM public.in_app_notifications)
         + (SELECT count(*) FROM public.message_notification_outbox);
$$;

DO $$
DECLARE
  v_key constant text := 'spec2-w1d-switch-field-key-0123456789abcdef';
  v_nb uuid;
  v_man uuid;
  v_woman uuid;
  v_uk_nb uuid;
  v_uk_man uuid;
  v_pronouns uuid;
  v_uk_plain uuid;
  v_uk_unreadable uuid;
  v_uk_nb_abroad uuid;
  v_gh_unreadable uuid;
  v_i_nb_woman uuid;
  v_i_man_woman uuid;
  v_i_man_uknb uuid;
  v_i_uk uuid;
  v_m_nb_woman uuid;
  v_m_man_woman uuid;
  v_m_pron_man uuid;
  v_m_man_uknb uuid;
  v_m_uk uuid;
  v_m_old uuid;
  v_m_unreadable uuid;
  v_spec uuid;
  v_pools uuid;
  v_draft uuid;
  v_paused_user uuid;
  v_uk_unreadable2 uuid;
  v_uk_unreadable3 uuid;
  v_i_gen uuid;
  v_i_int uuid;
  v_i_unreadable uuid;
  v_uk_unanswered uuid;
  v_i_unanswered uuid;
  v_mover uuid;
  v_partner uuid;
  v_m_movers uuid;
  v_unreadable_g bigint;
  v_plain_woman constant jsonb := '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}';
  v_plain_man constant jsonb := '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}';
  v jsonb;
  v_sent bigint := pg_temp.sent();
  v_unreadable bigint := pg_temp.counter('dating.kill_switch.unreadable');
  v_pending bigint;
  v_msg text;
BEGIN
  -- Development reads Vault first: this section keys through the GUC only
  -- (same key, same seeded fingerprint), so it can take the key away.
  DELETE FROM vault.secrets WHERE name = 'dating_field_key';
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM pg_temp.publish('GH', '{"same_gender_enabled": true}');
  v_nb := pg_temp.sg_person('10', 'GH', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": "they/them", "pools": ["non_binary", "woman"]}',
                            '{"seeking": ["man", "non_binary", "woman"]}');
  v_man := pg_temp.sg_person('11', 'GH', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                             '{"seeking": ["woman"]}');
  v_woman := pg_temp.sg_person('12', 'GH', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                               '{"seeking": ["man"]}');
  v_uk_nb := pg_temp.sg_person('13', 'GB', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary", "woman"]}',
                               '{"seeking": ["man", "non_binary", "woman"]}');
  v_pronouns := pg_temp.sg_person('15', 'GH', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": "she/her", "pools": ["woman"]}',
                                  '{"seeking": ["man"]}');
  v_uk_man := pg_temp.sg_person('14', 'GB', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                                '{"seeking": ["man"]}');
  -- Batch-8 I-2c: three UK people open to Ghana (plain, unreadable, not plain).
  v_uk_plain := pg_temp.sg_person('16', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                  '{"seeking": ["man"]}');
  v_uk_unreadable := pg_temp.sg_person('17', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                       '{"seeking": ["man"]}');
  v_uk_nb_abroad := pg_temp.sg_person('18', 'GB', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary"]}',
                                      '{"seeking": ["non_binary"]}');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, open_abroad)
  VALUES (v_uk_plain, 18, 99, '{GH}'), (v_uk_unreadable, 18, 99, '{GH}'), (v_uk_nb_abroad, 18, 99, '{GH}');
  -- Batch-6 I-3: a Ghana person whose answers can't be read.
  v_gh_unreadable := pg_temp.sg_person('19', 'GH', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                                       '{"seeking": ["woman"]}');
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x01deadbeef'::bytea WHERE user_id IN (v_gh_unreadable, v_uk_unreadable);
  v_i_nb_woman := pg_temp.intro(v_nb, v_woman);
  v_i_man_woman := pg_temp.intro(v_man, v_woman);
  v_i_man_uknb := pg_temp.intro(v_man, v_uk_nb);
  v_i_uk := pg_temp.intro(v_uk_nb, v_uk_man);
  -- Owner ruling 2026-11-06: matches.
  v_m_nb_woman := pg_temp.match(v_nb, v_woman);
  v_m_man_woman := pg_temp.match(v_man, v_woman);
  v_m_pron_man := pg_temp.match(v_pronouns, v_man);
  v_m_man_uknb := pg_temp.match(v_man, v_uk_nb);
  v_m_uk := pg_temp.match(v_uk_nb, v_uk_man);
  v_m_old := pg_temp.match(v_nb, v_man, 'unmatched');
  v_m_unreadable := pg_temp.match(v_gh_unreadable, v_woman);
  -- Fix round 1, I-4: a specific term, extra pools, a draft, a pause of
  -- one's own, open introductions in every state and an unreadable outsider.
  v_spec := pg_temp.sg_person('24', 'GH', '{"identity": "woman", "specific": "trans_woman", "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                              '{"seeking": ["man"]}');
  v_pools := pg_temp.sg_person('25', 'GH', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man", "woman"]}',
                               '{"seeking": ["woman"]}');
  v_draft := pg_temp.sg_person('27', 'GH', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary"]}',
                               '{"seeking": ["woman"]}');
  UPDATE public.dating_enrollments SET state = 'profile_draft' WHERE user_id = v_draft;
  UPDATE public.dating_profiles SET profile_state = 'draft' WHERE user_id = v_draft;
  v_paused_user := pg_temp.sg_person('28', 'GH', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary"]}',
                                     '{"seeking": ["woman"]}');
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user', paused_at = now() - interval '2 days' WHERE user_id = v_paused_user;
  UPDATE public.dating_profiles SET profile_state = 'paused' WHERE user_id = v_paused_user;
  v_uk_unreadable2 := pg_temp.sg_person('26', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                        '{"seeking": ["man"]}');
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x01deadbeef'::bytea WHERE user_id = v_uk_unreadable2;
  v_i_gen := pg_temp.intro(v_man, v_uk_nb, 'generated', 'w1d-generated');
  v_i_int := pg_temp.intro(v_man, v_uk_nb, 'interested', 'w1d-interested');
  v_i_unreadable := pg_temp.intro(v_man, v_uk_unreadable2);
  -- I-3: a UK person who hasn't answered (no stored identity), introduced to
  -- a Ghana man: an unknown pair is never man-woman.
  v_uk_unanswered := pg_temp.sg_person('33', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                       '{"seeking": ["man"]}');
  UPDATE public.dating_profile_sensitive SET identity_enc = NULL, seeking_enc = NULL WHERE user_id = v_uk_unanswered;
  v_i_unanswered := pg_temp.intro(v_man, v_uk_unanswered);

  v := pg_temp.publish('GH', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'switched')::boolean IS NOT TRUE OR (v ->> 'affected')::int IS DISTINCT FROM 7
     OR (pg_temp.current('GH')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly seven people: %', v;
  END IF;
  IF NOT pg_temp.sg_exclusive('GH') THEN -- (E0 pins that it is taken by the switch itself)
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not take Ghana''s same-gender lock exclusive (batch-7 I-5)';
  END IF;
  IF (SELECT identity_enc IS NOT NULL OR seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_nb)
     OR (SELECT gender_visible FROM public.dating_profiles WHERE user_id = v_nb)
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_nb) IS DISTINCT FROM 'paused/same_gender_switch'
     OR (SELECT profile_state FROM public.dating_profiles WHERE user_id = v_nb) IS DISTINCT FROM 'paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana non-binary answers were not deleted with a same_gender_switch pause';
  END IF;
  -- Fix round 1, M-4 and I-4: a woman/man identity loses only its pronouns,
  -- specific term or extra pools (stored as the plain base), keeps a plain
  -- who-to-meet, and is paused, hidden.
  IF pg_temp.identity_of(v_pronouns) IS DISTINCT FROM v_plain_woman OR pg_temp.seeking_of(v_pronouns) IS DISTINCT FROM '{"seeking": ["man"]}'::jsonb
     OR pg_temp.identity_of(v_spec) IS DISTINCT FROM v_plain_woman OR pg_temp.seeking_of(v_spec) IS DISTINCT FROM '{"seeking": ["man"]}'::jsonb
     OR pg_temp.identity_of(v_pools) IS DISTINCT FROM v_plain_man OR pg_temp.seeking_of(v_pools) IS DISTINCT FROM '{"seeking": ["woman"]}'::jsonb
     OR pg_temp.enrolled(v_pronouns) || pg_temp.enrolled(v_spec) || pg_temp.enrolled(v_pools)
          IS DISTINCT FROM 'paused/same_gender_switchpaused/same_gender_switchpaused/same_gender_switch'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id IN (v_pronouns, v_spec, v_pools) AND gender_visible) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a woman/man identity with pronouns, a specific term or extra pools was not stripped to its plain base, paused (% / % / %)',
      pg_temp.identity_of(v_pronouns), pg_temp.identity_of(v_spec), pg_temp.identity_of(v_pools);
  END IF;
  IF pg_temp.enrolled(v_draft) IS DISTINCT FROM 'paused/same_gender_switch'
     OR (SELECT profile_state FROM public.dating_profiles WHERE user_id = v_draft) IS DISTINCT FROM 'draft'
     OR pg_temp.enrolled(v_paused_user) IS DISTINCT FROM 'paused/user'
     OR (SELECT bool_or(identity_enc IS NOT NULL OR seeking_enc IS NOT NULL) FROM public.dating_profile_sensitive
          WHERE user_id IN (v_draft, v_paused_user)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft was not paused, or a person paused by choice lost their reason (% / %)',
      pg_temp.enrolled(v_draft), pg_temp.enrolled(v_paused_user);
  END IF;
  IF pg_temp.intro_state(v_i_gen) IS DISTINCT FROM 'invalidated' OR pg_temp.intro_state(v_i_int) IS DISTINCT FROM 'invalidated'
     OR pg_temp.intro_state(v_i_unreadable) IS DISTINCT FROM 'invalidated'
     OR pg_temp.intro_state(v_i_unanswered) IS DISTINCT FROM 'invalidated'
     OR pg_temp.enrolled(v_uk_unanswered) IS DISTINCT FROM 'active/-' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a generated, an interested, an unreadable-member or an unanswered-member introduction touching Ghana stayed open, or the UK member was paused (% / % / % / %)',
      pg_temp.intro_state(v_i_gen), pg_temp.intro_state(v_i_int), pg_temp.intro_state(v_i_unreadable), pg_temp.intro_state(v_i_unanswered);
  END IF;
  IF (SELECT identity_enc IS NOT NULL OR seeking_enc IS NOT NULL OR gender_visible
        FROM public.dating_profile_sensitive JOIN public.dating_profiles USING (user_id) WHERE user_id = v_gh_unreadable)
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_gh_unreadable) IS DISTINCT FROM 'paused/same_gender_switch'
     OR pg_temp.counter('dating.kill_switch.unreadable') - v_unreadable IS DISTINCT FROM 2::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable row did not take the restrictive path, counted (batch-6 I-3; % counted)',
      pg_temp.counter('dating.kill_switch.unreadable') - v_unreadable;
  END IF;
  IF (SELECT identity_enc IS NULL OR seeking_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_man)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_man) IS DISTINCT FROM 'active'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_uk_nb) IS DISTINCT FROM 'active'
     OR (SELECT identity_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_nb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch touched a man-woman person in Ghana or anyone in the UK';
  END IF;
  IF (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_uk_plain) IS DISTINCT FROM '{GH}'::char(2)[]
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_uk_unreadable) IS DISTINCT FROM '{}'::char(2)[]
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_uk_nb_abroad) IS DISTINCT FROM '{}'::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana did not leave exactly the not-plain (or unreadable) UK people''s other-countries lists (batch-8 I-2c)';
  END IF;
  IF (SELECT state FROM public.dating_introductions WHERE id = v_i_nb_woman) IS DISTINCT FROM 'invalidated'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_man_uknb) IS DISTINCT FROM 'invalidated'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_man_woman) IS DISTINCT FROM 'presented'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_uk) IS DISTINCT FROM 'presented' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not invalidate exactly the not-man-woman introductions touching Ghana (cross-border included)';
  END IF;
  IF pg_temp.match_is(v_m_nb_woman) IS DISTINCT FROM 'closed/other/sealed30'
     OR pg_temp.match_is(v_m_man_uknb) IS DISTINCT FROM 'closed/other/sealed30'
     OR pg_temp.match_is(v_m_man_woman) IS DISTINCT FROM 'active/-/unsealed'
     OR pg_temp.match_is(v_m_pron_man) IS DISTINCT FROM 'active/-/unsealed'
     OR pg_temp.match_is(v_m_uk) IS DISTINCT FROM 'active/-/unsealed'
     OR pg_temp.match_is(v_m_old) IS DISTINCT FROM 'unmatched/unmatched/unsealed'
     OR pg_temp.match_is(v_m_unreadable) IS DISTINCT FROM 'closed/other/sealed30' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not close exactly the active not-man-woman matches touching Ghana, as other, sealed 30 days (owner ruling; % % % % % % %)',
      pg_temp.match_is(v_m_nb_woman), pg_temp.match_is(v_m_man_uknb), pg_temp.match_is(v_m_man_woman),
      pg_temp.match_is(v_m_pron_man), pg_temp.match_is(v_m_uk), pg_temp.match_is(v_m_old), pg_temp.match_is(v_m_unreadable);
  END IF;
  IF pg_temp.sent() IS DISTINCT FROM v_sent THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the kill switch queued a notification';
  END IF;
  -- A version-0 country turning same-gender off has nobody to switch (it
  -- needs a calling code first, M-4).
  INSERT INTO private.dating_calling_codes (prefix, country_code) VALUES ('351', 'PT');
  v := pg_temp.publish('PT', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'switched' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country with no row yet ran the switch: %', v;
  END IF;

  -- Fix round 1, I-3 (the reviewer's reproduction): two UK women in a match;
  -- one moves her Dating country to Ghana, which clears her gender answers
  -- (D3). An unknown pair is never man-woman: the global switch closes it.
  v_mover := pg_temp.sg_person('29', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                               '{"seeking": ["woman"]}');
  v_partner := pg_temp.sg_person('30', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                 '{"seeking": ["woman"]}');
  v_m_movers := pg_temp.match(v_mover, v_partner);
  UPDATE public.dating_profile_sensitive SET identity_enc = NULL, seeking_enc = NULL WHERE user_id = v_mover;
  UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA', gender_visible = false WHERE user_id = v_mover;
  -- M-9: an unreadable UK person whose other-countries list names a switched
  -- country is counted once, not twice (step 2 deletes what it can't read
  -- before step 3 reads the lists).
  v_uk_unreadable3 := pg_temp.sg_person('32', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                        '{"seeking": ["man"]}');
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x01deadbeef'::bytea WHERE user_id = v_uk_unreadable3;
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, open_abroad) VALUES (v_uk_unreadable3, 18, 99, '{IE}');
  v_unreadable_g := pg_temp.counter('dating.kill_switch.unreadable');

  -- The global flag off: the UK too (E0 pins its locks).
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_nb)
     OR (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_man)
     OR (SELECT identity_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_man)
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_uk) IS DISTINCT FROM 'invalidated'
     OR pg_temp.match_is(v_m_uk) IS DISTINCT FROM 'closed/other/sealed30'
     OR pg_temp.match_is(v_m_man_woman) IS DISTINCT FROM 'active/-/unsealed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning dating_same_gender_matching off did not switch every country';
  END IF;
  -- A re-run keeps a man-woman match whose pronouns the first run took away
  -- (she is stored as a plain woman now, M-4).
  IF pg_temp.match_is(v_m_pron_man) IS DISTINCT FROM 'active/-/unsealed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second switch closed a man-woman match whose pronouns the first one deleted';
  END IF;
  IF pg_temp.match_is(v_m_movers) IS DISTINCT FROM 'closed/other/sealed30'
     OR pg_temp.enrolled(v_mover) IS DISTINCT FROM 'paused/same_gender_switch' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a woman-woman match survived the global switch because one of them had no stored identity (I-3; %, %)',
      pg_temp.match_is(v_m_movers), pg_temp.enrolled(v_mover);
  END IF;
  IF pg_temp.counter('dating.kill_switch.unreadable') - v_unreadable_g IS DISTINCT FROM 3::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the global switch did not count each unreadable person once (M-9; % counted)',
      pg_temp.counter('dating.kill_switch.unreadable') - v_unreadable_g;
  END IF;

  -- Without the key the switch is still published; the purge is reported
  -- pending and counted.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v_pending := pg_temp.counter('dating.kill_switch.pending');
  BEGIN
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key, turning same-gender off raised (%)', SQLERRM;
  END;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'affected' IS DISTINCT FROM 'null'::jsonb OR (pg_temp.current('GB')).same_gender_enabled
     OR pg_temp.counter('dating.kill_switch.pending') - v_pending IS DISTINCT FROM 1::bigint
     OR v ->> 'pending_sqlstate' IS DISTINCT FROM 'P0001' OR pg_temp.pending() IS DISTINCT FROM 'GB' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key the UK switch was not published with its purge pending, visibly (%; pending %)', v, pg_temp.pending();
  END IF;
  BEGIN
    UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key, turning the global flag off raised (%)', SQLERRM;
  END;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_same_gender_matching')
     OR pg_temp.counter('dating.kill_switch.pending') - v_pending IS DISTINCT FROM 2::bigint THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge that cannot run blocked turning the global flag off, or was not counted';
  END IF;
  v := public.get_dating_operational_health() -> 'kill_switch_pending';
  IF pg_temp.pending() IS DISTINCT FROM '*,GB'
     OR (SELECT jsonb_agg(e ->> 'scope' ORDER BY e ->> 'scope') FROM jsonb_array_elements(v) AS e) IS DISTINCT FROM '["*", "GB"]'::jsonb
     OR (SELECT e ->> 'sqlstate' FROM jsonb_array_elements(v) AS e WHERE e ->> 'scope' = 'GB') IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not list both pending purges (I-1): % / %', pg_temp.pending(), v;
  END IF;
  IF pg_temp.err('SELECT public.apply_same_gender_switch(''GB'')') IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: apply_same_gender_switch ran without the key';
  END IF;

  -- A replaced key (a stored fingerprint that differs) never wipes the
  -- answers it can't read: pending, and nothing changes.
  INSERT INTO private.dating_key_fingerprints (name, fingerprint)
  VALUES ('dating_field_key', encode(extensions.hmac('attune:dating_field_key:fingerprint:v1', v_key, 'sha256'), 'hex'))
  ON CONFLICT (name) DO UPDATE SET fingerprint = EXCLUDED.fingerprint;
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
  v := to_jsonb(pg_temp.sg_person('21', 'GB', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary"]}',
                                  '{"seeking": ["non_binary"]}'));
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-a-replaced-field-key-0123456789', true);
  v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'affected' IS DISTINCT FROM 'null'::jsonb
     OR (SELECT identity_enc IS NULL OR seeking_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = pg_temp.id('21'))
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = pg_temp.id('21')) IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced field key the switch wiped answers it could not read: %', v;
  END IF;
  -- M-6: the owner's re-run says why (present but not the stored one).
  IF pg_temp.err('SELECT public.apply_same_gender_switch(''GB'')') IS DISTINCT FROM 'dating:field_key_not_ready'
     OR (SELECT attempts FROM private.dating_kill_switch_pending WHERE scope = 'GB') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced key the re-run did not answer dating:field_key_not_ready, or the GB marker did not count a second failure';
  END IF;
  -- The owner's re-run, once the key is back.
  PERFORM set_config('app.settings.dating_field_key', v_key, true);
  v := to_jsonb(public.apply_same_gender_switch(' gb '));
  IF v IS DISTINCT FROM '1'::jsonb
     OR (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = pg_temp.id('21')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-running apply_same_gender_switch(''gb'') did not switch the pending person';
  END IF;
  -- I-1: a re-run that completes clears only what it switched; the global one
  -- clears everything; a country re-run with nothing to do clears its own.
  IF pg_temp.pending() IS DISTINCT FROM '*' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-running the UK did not clear exactly the UK marker (%)', pg_temp.pending();
  END IF;
  PERFORM public.apply_same_gender_switch(NULL);
  IF pg_temp.pending() IS DISTINCT FROM '' OR public.get_dating_operational_health() -> 'kill_switch_pending' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the global re-run did not clear every pending purge (%)', pg_temp.pending();
  END IF;
  PERFORM private.dating_kill_switch_mark('FR', '40P01');
  PERFORM public.apply_same_gender_switch('FR');
  IF pg_temp.pending() IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-run for a country with nothing to switch left its marker (%)', pg_temp.pending();
  END IF;
  PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');

  -- Deleting or renaming the flag's row is the switch too, and never blocked.
  v := to_jsonb(pg_temp.sg_person('22', 'GB', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                                  '{"seeking": ["man"]}'));
  DELETE FROM public.feature_flags WHERE key = 'dating_same_gender_matching';
  IF (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = pg_temp.id('22')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deleting the dating_same_gender_matching row did not switch every country';
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_same_gender_matching', true);
  v := to_jsonb(pg_temp.sg_person('23', 'GB', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                                  '{"seeking": ["woman"]}'));
  UPDATE public.feature_flags SET key = 'dating_same_gender_matching_x' WHERE key = 'dating_same_gender_matching';
  IF (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = pg_temp.id('23')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: renaming the dating_same_gender_matching row did not switch every country';
  END IF;
  DELETE FROM public.feature_flags WHERE key = 'dating_same_gender_matching_x';
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_same_gender_matching', false);
  -- Fix round 1, M-2: a TRUNCATE leaves the flag missing (off): the switch too (undone after).
  BEGIN
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
    v := to_jsonb(pg_temp.sg_person('31', 'GB', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                                    '{"seeking": ["man"]}'));
    TRUNCATE public.feature_flags;
    IF (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = pg_temp.id('31')) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: truncating feature_flags did not switch every country';
    END IF;
    RAISE EXCEPTION 'w1d:truncate_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w1d:truncate_undo' THEN
      RAISE;
    END IF;
  END;

  -- The pending marker is the database's own (fix round 1, I-1): RLS on, no
  -- API role can read or write it, nor call the marker function.
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'private.dating_kill_switch_pending'::regclass)
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r(role),
                       unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) AS q(priv)
                 WHERE has_table_privilege(r.role, 'private.dating_kill_switch_pending', q.priv))
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['anon', 'authenticated', 'service_role']) AS r(role)
                 WHERE has_function_privilege(r.role, 'private.dating_kill_switch_mark(text,text)', 'EXECUTE')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can reach the kill-switch pending marker';
  END IF;

  -- Health reads the two counters (raw).
  v := public.get_dating_operational_health() -> 'safety_counters_7d';
  IF NOT (v ?& ARRAY['dating.kill_switch.pending', 'dating.kill_switch.unreadable'])
     OR (v ->> 'dating.kill_switch.pending')::bigint IS DISTINCT FROM pg_temp.counter('dating.kill_switch.pending')
     OR (v ->> 'dating.kill_switch.unreadable')::bigint IS DISTINCT FROM pg_temp.counter('dating.kill_switch.unreadable') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not surface the kill-switch counters: %', v;
  END IF;

  -- Pre-validation: a malformed country is one fixed message, never a raw
  -- error or the input.
  FOREACH v_msg IN ARRAY ARRAY['', ' ', 'zz', 'ZZ', 'GHA', 'G1', 'gh;', repeat('x', 5000)] LOOP
    IF pg_temp.err(format('SELECT public.apply_same_gender_switch(%L)', v_msg)) IS DISTINCT FROM 'dating:invalid_country' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: apply_same_gender_switch(%) did not answer dating:invalid_country', left(v_msg, 10);
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- E1r. (Fix round 1, I-2) A deadlock, a lock timeout or a serialization
--    failure in the purge is retried up to three times, in the publish
--    and in the flag trigger; another error is not retried; a purge that
--    still fails is left pending with its SQLSTATE. (The switch is swapped
--    for a stand-in that fails a set number of times, all undone after.)
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  BEGIN
    CREATE TEMP SEQUENCE w1d_switch_calls;
    ALTER FUNCTION public.apply_same_gender_switch(text) RENAME TO apply_same_gender_switch_w1d_real;
    CREATE FUNCTION public.apply_same_gender_switch(p_country text) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $w$
    BEGIN
      IF nextval('pg_temp.w1d_switch_calls') <= current_setting('w1d.fail_n')::bigint THEN
        RAISE EXCEPTION 'w1d: simulated failure' USING ERRCODE = current_setting('w1d.fail_code');
      END IF;
      RETURN public.apply_same_gender_switch_w1d_real(p_country);
    END $w$;
    IF pg_temp.pending() IS DISTINCT FROM '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: section E1r expects nothing pending';
    END IF;

    -- Two deadlocks, then it completes.
    PERFORM set_config('w1d.fail_n', '2', true);
    PERFORM set_config('w1d.fail_code', '40P01', true);
    PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
    IF v -> 'affected' IS NULL OR v -> 'affected' = 'null'::jsonb OR v ? 'pending_sqlstate'
       OR currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 3::bigint OR pg_temp.pending() IS DISTINCT FROM '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: two deadlocks were not retried to a completed purge (%; % calls)', v, currval('pg_temp.w1d_switch_calls');
    END IF;
    -- Three lock timeouts: pending, with the SQLSTATE.
    PERFORM set_config('w1d.fail_n', '3', true);
    PERFORM set_config('w1d.fail_code', '55P03', true);
    PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
    IF v -> 'affected' IS DISTINCT FROM 'null'::jsonb OR v ->> 'pending_sqlstate' IS DISTINCT FROM '55P03'
       OR currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 3::bigint OR pg_temp.pending() IS DISTINCT FROM 'GB'
       OR (SELECT last_sqlstate || '/' || attempts FROM private.dating_kill_switch_pending WHERE scope = 'GB') IS DISTINCT FROM '55P03/1' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: three lock timeouts were not retried, then left pending visibly (%; % calls)', v, currval('pg_temp.w1d_switch_calls');
    END IF;
    -- Serialization failures are retried too.
    PERFORM set_config('w1d.fail_n', '1', true);
    PERFORM set_config('w1d.fail_code', '40001', true);
    PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
    IF v ? 'pending_sqlstate' OR currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 2::bigint OR pg_temp.pending() IS DISTINCT FROM '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a serialization failure was not retried (or the completed purge left GB pending): %', v;
    END IF;
    -- Any other error: one attempt, pending.
    PERFORM set_config('w1d.fail_n', '9', true);
    PERFORM set_config('w1d.fail_code', '22012', true);
    PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
    IF v ->> 'pending_sqlstate' IS DISTINCT FROM '22012' OR currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 1::bigint
       OR pg_temp.pending() IS DISTINCT FROM 'GB' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: another error was retried, or not left pending (%; % calls)', v, currval('pg_temp.w1d_switch_calls');
    END IF;

    -- The flag trigger, the same way.
    PERFORM set_config('w1d.fail_n', '2', true);
    PERFORM set_config('w1d.fail_code', '40P01', true);
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
    IF currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 3::bigint OR pg_temp.pending() IS DISTINCT FROM '' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the flag trigger did not retry two deadlocks to a completed purge (% calls; pending %)',
        currval('pg_temp.w1d_switch_calls'), pg_temp.pending();
    END IF;
    PERFORM set_config('w1d.fail_n', '3', true);
    PERFORM set_config('w1d.fail_code', '55P03', true);
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
    IF currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 3::bigint OR pg_temp.pending() IS DISTINCT FROM '*'
       OR (SELECT last_sqlstate FROM private.dating_kill_switch_pending WHERE scope = '*') IS DISTINCT FROM '55P03'
       OR (SELECT enabled FROM public.feature_flags WHERE key = 'dating_same_gender_matching') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the flag trigger did not retry, then leave the global purge pending (% calls; pending %)',
        currval('pg_temp.w1d_switch_calls'), pg_temp.pending();
    END IF;
    PERFORM set_config('w1d.fail_n', '9', true);
    PERFORM set_config('w1d.fail_code', '22012', true);
    UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
    PERFORM setval('pg_temp.w1d_switch_calls', 1, false);
    UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
    IF currval('pg_temp.w1d_switch_calls') IS DISTINCT FROM 1::bigint THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the flag trigger retried another error (% calls)', currval('pg_temp.w1d_switch_calls');
    END IF;
    RAISE EXCEPTION 'w1d:retry_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w1d:retry_undo' THEN
      RAISE;
    END IF;
  END;
  IF pg_temp.pending() IS DISTINCT FROM '' OR to_regprocedure('public.apply_same_gender_switch_w1d_real(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'fixture: section E1r was not undone';
  END IF;
END $$;

-- =====================================================================
-- E2. (PF-F1, batch-5 M-3) An exposure-reducing publish (closing,
--    narrowing the open regions, tightening the tier, same-gender off)
--    is never refused in production for lapsed evidence, the tier review,
--    the reconsideration, a key that isn't ready or a missing calling
--    code; the checks are still returned. A publish that widens anything,
--    changes the ID documents or reduces nothing is held to every check.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_refused constant text := 'config:production_checks_failed';
BEGIN
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef');
  IF (pg_temp.current('GH')).dating_enabled IS NOT TRUE OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH']
     OR (pg_temp.current('GH')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section E2 expects Ghana open in AA and AH, same-gender off';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  -- Same-gender turned on alongside a narrowing is not a reduction.
  v := pg_temp.publish('GH', '{"same_gender_enabled": true, "open_regions": ["AA"]}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same-gender turned on alongside a narrowing skipped the checks: %', v;
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.publish('GH', '{"same_gender_enabled": true}');
  PERFORM set_config('app.settings.attune_environment', 'production', true);

  -- Narrowing the regions.
  v := pg_temp.publish('GH', '{"open_regions": ["AA"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT (v -> 'checks' ? 'evidence_missing')
     OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused narrowing Ghana''s regions, or hid the checks: %', v;
  END IF;
  -- Widening, a neutral change, the ID documents, a looser tier or
  -- same-gender on alongside a reduction: every check applies.
  v := pg_temp.publish('GH', '{"open_regions": ["AA", "AH"]}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production widened Ghana''s regions without evidence: %', v;
  END IF;
  v := pg_temp.publish('GH', '{"source_url": "https://example.org/w1d"}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production took a publish that reduces nothing as a reduction: %', v;
  END IF;
  v := pg_temp.publish('GH', jsonb_build_object('dating_enabled', false, 'id_documents',
          (pg_temp.current('GH')).id_documents || '[{"code": "voter_id", "name_key": "dating_id_voter_id"}]'::jsonb));
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a close that also added an ID document skipped the checks: %', v;
  END IF;
  -- Fix round 1, M-8: removing an accepted ID document only tightens (a
  -- reduction on its own).
  v := pg_temp.publish('GH', '{"open_regions": ["AA"], "id_documents": [{"code": "passport", "name_key": "dating_id_passport"}]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR jsonb_array_length((pg_temp.current('GH')).id_documents) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a narrowing that also removed an ID document: %', v;
  END IF;
  v := pg_temp.publish('GH', '{"dating_enabled": false, "tier": 2}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a close that also loosened the tier skipped the checks: %', v;
  END IF;
  -- Closing a Tier 1 country with same-gender on and no reconsideration.
  v := pg_temp.publish('GH', '{"dating_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('GH')).dating_enabled
     OR v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused to close Ghana for its missing reconsideration: %', v;
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.publish('GH', '{"dating_enabled": true}');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  -- Same-gender off in an open country with lapsed evidence.
  v := pg_temp.publish('GH', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'switched')::boolean IS NOT TRUE OR NOT (v -> 'checks' ? 'evidence_missing')
     OR (pg_temp.current('GH')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a same-gender switch-off for lapsed evidence: %', v;
  END IF;
  -- Opening a region-less country while tightening its tier is still opening.
  v := pg_temp.publish('KE', '{"dating_enabled": true, "tier": 1}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Kenya while tightening its tier skipped the checks: %', v;
  END IF;

  -- Tightening the tier (GB is evidenced; tier 2 with same-gender on lacks
  -- the reconsideration).
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.publish('GB', '{"dating_enabled": true, "open_regions": ["TLC", "TLD"]}');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v := pg_temp.publish('GB', '{"tier": 2}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb
     OR (pg_temp.current('GB')).tier IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused tightening the UK''s tier: %', v;
  END IF;
  v := pg_temp.publish('GB', '{"tier": 1, "open_regions": ["TLC", "TLD", "TLE"]}');
  IF v ->> 'reason' IS DISTINCT FROM v_refused THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tighter tier with a wider region list skipped the checks: %', v;
  END IF;
  -- A key that isn't ready never blocks a reduction (and still blocks an opening).
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := pg_temp.publish('GB', '{"tier": 1}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT (v -> 'checks' ? 'exclusion_key_not_ready') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unready exclusion key blocked tightening the UK''s tier: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);
  DELETE FROM vault.secrets WHERE name = 'dating_field_key';
  v := pg_temp.publish('GB', '{"open_regions": ["TLC"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '["field_key_not_ready", "same_gender_reconsideration_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unready field key blocked narrowing the UK''s regions: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('open_regions', '["TLC", "TLD"]'::jsonb, 'legal_checklist',
          (pg_temp.current('GB')).legal_checklist || '{"same_gender_reconsideration":
          {"legal_opinion": "REF-A", "lgbtq_consultation": "REF-B", "tier1_protections": "REF-C"}}'::jsonb));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["field_key_not_ready"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production widened the UK without a ready field key (batch-10 carry): %', v;
  END IF;
  INSERT INTO vault.secrets (name, secret) VALUES ('dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef');
  -- A key that is present but not seeded is not ready either.
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_field_key';
  v := pg_temp.publish('GB', jsonb_build_object('open_regions', '["TLC", "TLD"]'::jsonb, 'legal_checklist',
          (pg_temp.current('GB')).legal_checklist || '{"same_gender_reconsideration":
          {"legal_opinion": "REF-A", "lgbtq_consultation": "REF-B", "tier1_protections": "REF-C"}}'::jsonb));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["field_key_not_ready"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production widened the UK under an unseeded field key: %', v;
  END IF;
  IF private.seed_dating_field_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the contract field key could not be re-seeded';
  END IF;

  -- A missing calling code never blocks a reduction (reported), and still
  -- refuses anything else (undone after).
  BEGIN
    DELETE FROM private.dating_calling_codes WHERE country_code = 'GB';
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
    IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT (v -> 'checks' ? 'no_calling_code') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a missing calling code blocked the UK''s same-gender switch-off: %', v;
    END IF;
    PERFORM set_config('app.settings.attune_environment', '', true);
    v := pg_temp.publish('GB', '{"same_gender_enabled": true}');
    IF v IS DISTINCT FROM '{"ok": false, "reason": "config:no_calling_code"}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a missing calling code no longer refuses a widening: %', v;
    END IF;
    RAISE EXCEPTION 'w1d:e2_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w1d:e2_undo' THEN
      RAISE;
    END IF;
  END;

  -- Back to what sections F and H expect.
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.publish('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"], "same_gender_enabled": false}');
  PERFORM pg_temp.publish('GB', '{"dating_enabled": false, "open_regions": null, "tier": 3, "same_gender_enabled": true}');
  IF (pg_temp.current('GB')).tier IS DISTINCT FROM 3 OR (pg_temp.current('GB')).dating_enabled
     OR NOT (pg_temp.current('GB')).same_gender_enabled OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH']
     OR (pg_temp.current('GH')).same_gender_enabled OR NOT (pg_temp.current('GH')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section E2 did not restore GB and GH';
  END IF;
END $$;

-- =====================================================================
-- F. The effective context (§2.3) and the session row.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('01');
  v jsonb;
BEGIN
  IF private.dating_phone_country('233244123456') IS DISTINCT FROM 'GH'
     OR private.dating_phone_country('+44 7700 900123') IS DISTINCT FROM 'GB'
     OR private.dating_phone_country('77011234567') IS DISTINCT FROM 'KZ'
     OR private.dating_phone_country('79161234567') IS DISTINCT FROM 'RU'
     OR private.dating_phone_country('18765551234') IS DISTINCT FROM 'JM'
     OR private.dating_phone_country('15551234567') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_phone_country is not the longest calling-code prefix';
  END IF;
  -- Tier: the highest (lowest number) of the four.
  IF (public.dating_effective_context('GH', 'GB', NULL, NULL) ->> 'effective_tier')::int IS DISTINCT FROM 1
     OR (public.dating_effective_context('FR', 'GB', 'FR', NULL) ->> 'effective_tier')::int IS DISTINCT FROM 3
     OR (public.dating_effective_context(NULL, 'GB', 'FR', 'KE') ->> 'effective_tier')::int IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: effective_tier is not the highest tier of the sources';
  END IF;
  -- Allowed here: false in a closed Tier 1/2 place or network; travel to a
  -- closed Tier 3 country changes nothing; an unresolved IP falls back to
  -- the phone country.
  IF (public.dating_effective_context('GB', 'GB', 'AE', NULL) ->> 'dating_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', 'GB', 'GB', 'AE') ->> 'dating_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', 'GB', 'FR', NULL) ->> 'dating_allowed_here')::boolean IS NOT TRUE
     OR (public.dating_effective_context('AE', 'GB', NULL, NULL) ->> 'dating_allowed_here')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_allowed_here is wrong';
  END IF;
  -- Same-gender here: the flag, the Dating country, the place and the network.
  IF (public.dating_effective_context('GB', 'GB', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same-gender was allowed with the global flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  IF (public.dating_effective_context('GB', 'GB', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT TRUE
     OR (public.dating_effective_context('GB', 'GB', 'GH', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', 'GB', 'GB', 'GH') ->> 'same_gender_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GH', 'GH', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', NULL, 'GB', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GH', 'GB', NULL, NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same_gender_allowed_here is wrong (a Ghana SIM in London, a UK user in Accra, no Dating country, an unresolved IP on a Ghana phone)';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF (public.dating_effective_context('GB', 'GB', 'FR', NULL) ->> 'away_from_home')::boolean IS NOT TRUE
     OR (public.dating_effective_context('FR', 'GB', NULL, NULL) ->> 'away_from_home')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', NULL, 'FR', NULL) ->> 'away_from_home')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', 'GB', NULL, NULL) ->> 'ip_resolved')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: away_from_home or ip_resolved is wrong';
  END IF;

  -- The row: one per person, overwritten (W1c adds the away streak, once
  -- profiles carry a Dating country), and the table holds no country.
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_u, '1555870101', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_u, '1555870101', 'Context');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'FR', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT ip_resolved AND dating_allowed_here FROM public.dating_session_context WHERE user_id = v_u) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the session row did not store the resolved IP (fix round 1, I-4)';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, NULL, 'AE');
  PERFORM pg_temp.as_owner();
  IF (SELECT count(*) FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM 1
     OR (SELECT dating_allowed_here OR ip_resolved OR away_from_home OR mismatch_streak IS DISTINCT FROM 0
           FROM public.dating_session_context WHERE user_id = v_u) IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the session row is not one overwritten row of the latest check';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                AND table_name = 'dating_session_context' AND (column_name LIKE '%country%' OR column_name LIKE '%ip%address%')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_session_context stores a country or an address';
  END IF;
END $$;

-- =====================================================================
-- F-I. (Fix round 1, I-1, I-4) A code that is no ISO country (ZZ, EU, XK)
--     is unresolved, so the phone fallback applies; the stored session row
--     carries the computed tier, place and same-gender values.
-- =====================================================================
DO $$
DECLARE
  v_g constant uuid := pg_temp.id('03');
  v_row public.dating_session_context;
BEGIN
  IF (public.dating_effective_context('IR', 'GB', 'ZZ', NULL) ->> 'dating_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('IR', 'GB', 'ZZ', NULL) ->> 'ip_resolved')::boolean IS NOT FALSE
     OR (public.dating_effective_context('IR', 'GB', 'EU', NULL) ->> 'dating_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('IR', 'GB', 'xk', 'ZZ') ->> 'dating_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('ir', 'GB', NULL, NULL) ->> 'effective_tier')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-ISO IP code was taken as a permissive country';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  IF (public.dating_effective_context('GH', 'GB', 'ZZ', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE
     OR (public.dating_effective_context('GB', 'EU', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-ISO code allowed same-gender matching';
  END IF;

  -- A Ghana phone (GH is open since section C), flag on.
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_g, '233244870103', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_g, '233244870103', 'Accra');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_g, 'AE', NULL);
  PERFORM pg_temp.as_owner();
  SELECT * INTO v_row FROM public.dating_session_context WHERE user_id = v_g;
  IF v_row.effective_tier IS DISTINCT FROM 1 OR v_row.dating_allowed_here IS NOT FALSE
     OR v_row.same_gender_allowed_here IS NOT FALSE OR v_row.ip_resolved IS NOT TRUE
     OR v_row.away_from_home IS NOT FALSE OR v_row.mismatch_streak IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stored context for a Ghana phone in the UAE is wrong: %', to_jsonb(v_row);
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_g, 'ZZ', NULL);
  PERFORM pg_temp.as_owner();
  SELECT * INTO v_row FROM public.dating_session_context WHERE user_id = v_g;
  IF v_row.effective_tier IS DISTINCT FROM 1 OR v_row.dating_allowed_here IS NOT TRUE
     OR v_row.same_gender_allowed_here IS NOT FALSE OR v_row.ip_resolved IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stored context for a Ghana phone with an unknown IP is wrong: %', to_jsonb(v_row);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
END $$;

-- =====================================================================
-- F2. (W1c) The away streak, once profiles carry a Dating country:
--    consecutive checks away from it count up, one at home resets it.
--    (Batch-4 carry, I-4) With the flag on, a GB profile checked in GB
--    stores same-gender true, and checked in GH stores it false.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('02');
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_u, '1555870102', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_u, '1555870102', 'Traveller');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Traveller', 'GB', 'TLI');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'FR', NULL);
  PERFORM public.record_dating_session_context(v_u, 'ES', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT mismatch_streak::text || away_from_home::text FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM '2true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two checks away did not count a streak of 2';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'GB', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT mismatch_streak::text || away_from_home::text FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM '0false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check at home did not reset the away streak';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'GB', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT same_gender_allowed_here FROM public.dating_session_context WHERE user_id = v_u) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a GB profile checked in GB with the flag on did not store same-gender true';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'GH', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT same_gender_allowed_here::text || away_from_home::text || mismatch_streak::text
        FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM 'falsetrue1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a GB profile checked in GH did not store same-gender false, away, streak 1';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
END $$;

-- =====================================================================
-- G. Validation: nothing is published from a malformed request.
-- =====================================================================
DO $$
DECLARE
  v_version int := (pg_temp.current('GH')).version;
BEGIN
  IF pg_temp.publish('G1', '{}') ->> 'reason' IS DISTINCT FROM 'config:invalid_country'
     OR pg_temp.publish('GH', '[]') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"is_current": false}') ->> 'reason' IS DISTINCT FROM 'config:unknown_key'
     OR pg_temp.publish('GH', '{"tier": 4}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"tier": "x"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"reference_tz": "Mars/Base"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_tz'
     OR pg_temp.publish('GH', '{"open_regions": ["AA", "ZZ"]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_regions'
     OR pg_temp.publish('GH', '{"region_list": [{"code": "AA"}, {"code": "AA"}], "open_regions": null}') ->> 'reason'
          IS DISTINCT FROM 'config:invalid_regions'
     OR pg_temp.publish('GH', '{"region_list": [{"name": "no code"}]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed publish was not refused with its reason';
  END IF;
  IF (pg_temp.current('GH')).version IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused publish wrote a version';
  END IF;
END $$;

-- =====================================================================
-- G2. (W1b, batch 4) Fail-closed edges: the helpers are no API role's
--     (the service role included); a NULL field never passes a check; a
--     country open in no region is never reported as open everywhere; an
--     unknown person gets no session row; NULL and wrongly typed values
--     are refused with their reason.
-- =====================================================================
DO $$
DECLARE
  v_role text;
  v_fn text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    FOREACH v_fn IN ARRAY ARRAY['private.country_config_checks(public.country_safety_config)',
                                'private.country_safety_config_immutable()', 'private.dating_phone_country(text)',
                                'private.country_safety_config_has_current()', 'private.dating_iso_country(text)',
                                'public.dating_country_config(text)', 'public.dating_effective_context(text,text,text,text)'] LOOP
      IF has_function_privilege(v_role, v_fn, 'EXECUTE') IS NOT FALSE THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can execute %', v_role, v_fn;
      END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('service_role', 'public.get_dating_availability()', 'EXECUTE') IS NOT FALSE
     OR has_function_privilege('anon', 'public.record_dating_session_context(uuid,text,text)', 'EXECUTE') IS NOT FALSE
     OR has_function_privilege('authenticated', 'public.record_dating_session_context(uuid,text,text)', 'EXECUTE') IS NOT FALSE
     OR has_function_privilege('authenticated', 'public.get_dating_availability()', 'EXECUTE') IS NOT TRUE
     OR has_table_privilege('anon', 'public.dating_session_context', 'SELECT') IS NOT FALSE
     OR has_table_privilege('authenticated', 'public.dating_session_context', 'SELECT') IS NOT FALSE
     OR has_table_privilege('anon', 'public.dating_notify_requests', 'SELECT') IS NOT FALSE
     OR has_table_privilege('authenticated', 'public.dating_notify_requests', 'SELECT') IS NOT FALSE
     OR (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE oid IN ('public.dating_session_context'::regclass, 'public.dating_notify_requests'::regclass)) IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the availability, session-context or notify-request grants are wrong';
  END IF;
END $$;

DO $$
DECLARE
  v_row public.country_safety_config := public.dating_country_config('NG');
  v_checks text[];
BEGIN
  -- A NULL dating_enabled is checked as on; a NULL checklist is empty.
  v_row.dating_enabled := NULL;
  v_row.resources_verified_at := now();
  v_row.legal_checklist := '{}'::jsonb;
  v_checks := private.country_config_checks(v_row);
  IF NOT (coalesce(v_checks, ARRAY[]::text[]) @> ARRAY['evidence_missing']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL dating_enabled skipped the evidence checks: %', v_checks;
  END IF;
  v_row.dating_enabled := true;
  v_row.legal_checklist := NULL;
  v_checks := private.country_config_checks(v_row);
  IF NOT (coalesce(v_checks, ARRAY[]::text[]) @> ARRAY['evidence_missing']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL legal checklist passed as evidenced: %', v_checks;
  END IF;
  -- A NULL same-gender switch or tier is checked as on and Tier 1.
  v_row := public.dating_country_config('NG');
  v_row.same_gender_enabled := NULL;
  v_checks := private.country_config_checks(v_row);
  IF NOT (coalesce(v_checks, ARRAY[]::text[]) @> ARRAY['same_gender_reconsideration_missing']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL same_gender_enabled skipped the reconsideration check: %', v_checks;
  END IF;
  v_row.same_gender_enabled := true;
  v_row.tier := NULL;
  v_checks := private.country_config_checks(v_row);
  IF NOT (coalesce(v_checks, ARRAY[]::text[]) @> ARRAY['same_gender_reconsideration_missing']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL tier skipped the reconsideration check: %', v_checks;
  END IF;
END $$;

DO $$
DECLARE
  v jsonb;
  v_version int;
BEGIN
  -- GH is open (section C). Fix round 1, M-2: open in no region is
  -- refused, and open regions are stored once each, sorted.
  IF (pg_temp.current('GH')).dating_enabled IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: G2 expects GH open from section C';
  END IF;
  v_version := (pg_temp.current('GH')).version;
  v := pg_temp.publish('GH', '{"open_regions": []}');
  IF v ->> 'reason' IS DISTINCT FROM 'config:invalid_regions' OR (pg_temp.current('GH')).version IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open country was published open in no region: %', v;
  END IF;
  v := pg_temp.publish('GH', '{"open_regions": ["AH", "AA", "AA"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: open regions were not stored once each: %', v;
  END IF;
  -- Defence in depth: a row written open in no region another way (the
  -- owner) is still reported as [], never as null (null means every region).
  DECLARE
    v_gh public.country_safety_config := pg_temp.current('GH');
  BEGIN
    UPDATE public.country_safety_config SET is_current = false WHERE country_code = 'GH' AND is_current;
    v_gh.version := v_gh.version + 1;
    v_gh.open_regions := ARRAY[]::text[];
    INSERT INTO public.country_safety_config SELECT v_gh.*;
  END;
  v := pg_temp.anon_config();
  IF (SELECT c -> 'open_regions' FROM jsonb_array_elements(v #> '{availability,countries}') AS c
       WHERE c ->> 'code' = 'GH') IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country open in no region was reported as open everywhere: %', v -> 'availability';
  END IF;
  v := pg_temp.publish('GH', '{"open_regions": ["AA", "AH"]}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: GH''s open regions could not be restored: %', v;
  END IF;

  -- NULL and wrongly typed values; M-1 a verification date in the future;
  -- I-1 a code that is no ISO country.
  v_version := (pg_temp.current('GH')).version;
  IF pg_temp.publish('GH', '{"resources_verified_at": "2099-01-01T00:00:00Z"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('ZZ', '{}') ->> 'reason' IS DISTINCT FROM 'config:invalid_country'
     OR pg_temp.publish('EU', '{"tier": 3}') ->> 'reason' IS DISTINCT FROM 'config:invalid_country' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a future verification date or a non-ISO country was published';
  END IF;
  IF pg_temp.publish('GH', '{"tier": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"dating_enabled": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GB', '{"same_gender_enabled": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"generation_hour_utc": 24}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"generation_hour_utc": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"open_regions": "AA"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"reference_tz": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_tz'
     OR pg_temp.publish('GH', '{"legal_checklist": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists'
     OR pg_temp.publish('GH', '{"legal_checklist": []}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists'
     OR pg_temp.publish('GH', '{"faith_list": {}}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists'
     OR pg_temp.publish('GH', '{"id_documents": null}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists'
     OR pg_temp.publish('GH', '{"region_list": ["AA"]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists'
     OR pg_temp.publish('GH', '{"open_regions": [null]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_regions'
     OR pg_temp.publish(NULL, '{}') ->> 'reason' IS DISTINCT FROM 'config:invalid_country'
     OR pg_temp.publish('GH', NULL) ->> 'reason' IS DISTINCT FROM 'config:invalid_values' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL or wrongly typed value was not refused with its reason';
  END IF;
  IF (pg_temp.current('GH')).version IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused publish wrote a version';
  END IF;
END $$;

DO $$
DECLARE
  v_ghost constant uuid := gen_random_uuid();
  v1 jsonb;
  v2 jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v1 := public.record_dating_session_context(v_ghost, 'GB', NULL);
  v2 := public.record_dating_session_context(NULL, 'GB', NULL);
  PERFORM pg_temp.as_owner();
  IF v1 IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR v2 IS DISTINCT FROM '{"ok": false, "reason": "unavailable"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_session_context WHERE user_id = v_ghost) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown or NULL person was not refused: % / %', v1, v2;
  END IF;
END $$;

-- Fix round 1, M-3, M-4, M-6.
DO $$
DECLARE
  v jsonb;
  v_state text;
BEGIN
  -- M-4: a restricting country needs a calling code.
  v := pg_temp.publish('UA', '{"tier": 1}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:no_calling_code"}'::jsonb
     OR pg_temp.publish('FR', '{"same_gender_enabled": false}') ->> 'reason' IS DISTINCT FROM 'config:no_calling_code' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricting country was published without a calling code: %', v;
  END IF;
  INSERT INTO private.dating_calling_codes (prefix, country_code) VALUES ('380', 'UA'), ('33', 'FR');
  IF private.dating_phone_country('380441234567') IS DISTINCT FROM 'UA' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phone country does not read the calling-code table';
  END IF;
  -- M-3: a country first published as Tier 1 starts same-gender off; a
  -- country with no row yet turns same-gender off without the kill switch.
  v := pg_temp.publish('UA', '{"tier": 1}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('UA')).same_gender_enabled IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new Tier 1 country inherited same-gender on: %', v;
  END IF;
  v := pg_temp.publish('FR', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('FR')).same_gender_enabled IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country with no row could not start same-gender off: %', v;
  END IF;
  -- M-6: the notify request's region is a code.
  BEGIN
    INSERT INTO public.dating_notify_requests (user_id, country_code, region_code) VALUES (pg_temp.id('01'), 'GH', 'Greater Accra');
    v_state := 'stored';
  EXCEPTION WHEN check_violation THEN
    v_state := 'refused';
  END;
  INSERT INTO public.dating_notify_requests (user_id, country_code, region_code) VALUES (pg_temp.id('01'), 'GH', 'AA')
  ON CONFLICT (user_id) DO NOTHING;
  IF v_state IS DISTINCT FROM 'refused'
     OR (SELECT region_code FROM public.dating_notify_requests WHERE user_id = pg_temp.id('01')) IS DISTINCT FROM 'AA' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a notify request stored a region that is not a code (%)', v_state;
  END IF;
END $$;

-- =====================================================================
-- H. (W1b, R-6, mutant 25) The dev script: refused in production mode
--    before it changes anything; in development it turns every Dating
--    flag on and opens GH and GB, and a re-run publishes nothing new.
--    (-v dev_script_path=<file> runs another copy, for the mutant.)
-- =====================================================================
\if :{?dev_script_path}
\else
\set dev_script_path supabase/sql/dev_enable_spec2_dating_flags.sql
\endif
\set dev_script `cat :dev_script_path`
CREATE TEMP TABLE dev_script ON COMMIT DROP AS SELECT :'dev_script'::text AS body;

DO $$
DECLARE
  v_body constant text := (SELECT body FROM dev_script);
  v_msg text;
  v_versions int;
BEGIN
  IF coalesce(v_body, '') = '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script is missing or empty';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key LIKE 'dating\_%';
  PERFORM pg_temp.publish('GH', '{"dating_enabled": false}');
  PERFORM pg_temp.publish('GB', '{"dating_enabled": false}');

  PERFORM set_config('app.settings.attune_environment', 'production', true);
  BEGIN
    EXECUTE v_body;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v_msg IS DISTINCT FROM 'env:not_development'
     OR EXISTS (SELECT 1 FROM public.feature_flags WHERE key LIKE 'dating\_%' AND enabled)
     OR (pg_temp.current('GH')).dating_enabled IS NOT FALSE OR (pg_temp.current('GB')).dating_enabled IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script was not refused in production mode before any change (%)', v_msg;
  END IF;
  IF v_body ~* '(set_config\s*\(\s*''app\.settings\.attune_environment''|SET\s+(LOCAL\s+)?app\.settings\.attune_environment|create_secret\s*\([^)]*''attune_environment'')' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script sets attune_environment';
  END IF;
  -- Batch-5 ruling: it opens countries only through publish_country_config.
  IF v_body ~* '(INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE(\s+TABLE)?)\s+(ONLY\s+)?(public\.)?country_safety_config' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script writes country_safety_config directly';
  END IF;

  -- Fix round 1 (M-7): a country the script can't open raises, and the
  -- script, one statement, changes nothing (here GH loses its calling
  -- code, so publish refuses config:no_calling_code; undone after).
  BEGIN
    DELETE FROM private.dating_calling_codes WHERE country_code = 'GH';
    v_msg := NULL;
    BEGIN
      EXECUTE v_body;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    IF v_msg IS NULL OR v_msg NOT LIKE 'dev_enable_spec2_dating_flags: GH was not opened: %'
       OR EXISTS (SELECT 1 FROM public.feature_flags WHERE key LIKE 'dating\_%' AND enabled)
       OR (pg_temp.current('GH')).dating_enabled IS NOT FALSE OR (pg_temp.current('GB')).dating_enabled IS NOT FALSE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a refused publish did not stop the dev script before any change (%)', v_msg;
    END IF;
    RAISE EXCEPTION 'w1b:h_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w1b:h_undo' THEN
      RAISE;
    END IF;
  END;

  EXECUTE v_body;
  -- Fix round 1 (M-6): NULL-safe (a missing flag or current row fails).
  IF (SELECT count(*) FROM public.feature_flags
       WHERE key IN ('dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
                     'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')
         AND enabled) IS DISTINCT FROM 6::bigint
     OR (pg_temp.current('GH')).dating_enabled IS NOT TRUE OR (pg_temp.current('GB')).dating_enabled IS NOT TRUE
     OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in development the dev script did not turn every Dating flag on and open GH and GB';
  END IF;
  v_versions := (SELECT count(*) FROM public.country_safety_config);
  EXECUTE v_body;
  IF (SELECT count(*) FROM public.country_safety_config) IS DISTINCT FROM v_versions THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-running the dev script published new versions';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'country_safety_config_contracts: all held'; END $$;
ROLLBACK;
