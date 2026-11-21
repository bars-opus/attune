-- supabase/tests/dating_v2_matching_contracts.sql
-- Spec 2 W5a (§4.3, §4.10, §5.2, §5.3, §5.7, §5.11, §7.1, §7.5 mutants 2,
-- 3, 6, 20; R12; carries 1-4, 7, 8, 10): the v1 trait objects are gone and
-- no function names one (A); the config, its caps CHECK and the production
-- DEV- guard (B); the hard filters 2-10 over person rows: symmetric over a
-- grid, a passing and a failing fixture each, NULL never admitted (C);
-- filters 1 and 11-14 on real people, kept never-introduce rows included,
-- and a stranger's phone never removes anyone (D); same-gender needs the
-- flag, both countries and fresh contexts, never in Ghana (E); the
-- cool-off and the drop time (F); the v2 read and act (K, W5b); a re-check
-- read back for 72 hours (J); generation (G-I, W5a Task 2); W5b's card, Today,
-- the match moment and notes, the photo keys and the digest (L-P); the W5
-- final fixes (V-Z): freshness through PostgREST, the gate record, a
-- mid-run filter change, the digest's isolation, block's lock order,
-- health's digest counters and the frozen active config.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_matching_contracts.sql
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w5-matching-key', true);
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w5-field-key-0123456789abcdef-0123', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset
INSERT INTO public.feature_flags (key, enabled)
VALUES ('dating_mode_enabled', true), ('dating_candidate_generation', true), ('dating_same_gender_matching', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset
UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e500000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- The device each person's phone sends (32 hex), and its stored hash.
CREATE FUNCTION pg_temp.dev(p_n text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT md5('w5-device-' || p_n);
$$;
-- A current candidate (§5.2 #1) with every answer in [o] over the defaults.
CREATE FUNCTION pg_temp.ready(p_n text, o jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
  d constant jsonb := '{"identity": "woman", "pools": null, "seeking": ["man"], "country": "GH", "region": "AA",
    "side": null, "scope": "region", "intention": "committed", "timeline": null, "timeline_visible": true,
    "years": 30, "min": 25, "max": 40, "days": 40, "have": false, "want": "yes", "must": false, "excl": false,
    "faith": null, "importance": null, "faith_visible": false, "family": null, "abroad": [], "seen_days": 0,
    "tz": null, "open": null}'::jsonb || o;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '155593000' || p_n, now(), now() - make_interval(days => (d ->> 'days')::int));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version, timezone)
  VALUES (v_u, '+155593000' || p_n, 'Match ' || p_n, 'dating', now() - make_interval(days => (d ->> 'days')::int),
          now(), '2', d ->> 'tz');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_u, (current_date - make_interval(years => (d ->> 'years')::int) - interval '10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state, opted_in_at, activated_at) VALUES (v_u, 'active', now(), now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, moderation_state, verification_state,
    country_code, region_code, side_code, intention, marriage_timeline, timeline_visible, not_married_attested_at,
    attestation_version, children_have, children_want, family_involvement, faith_visible)
  VALUES (v_u, 'Match ' || p_n, 'active', 'approved', 'verified', d ->> 'country', d ->> 'region', d ->> 'side',
    d ->> 'intention', d ->> 'timeline', (d ->> 'timeline_visible')::boolean, now(), '2026-10-v1',
    (d ->> 'have')::boolean, d ->> 'want', d ->> 'family', (d ->> 'faith_visible')::boolean);
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, region_scope, open_abroad, want_must_match,
    exclude_parents, intention_open)
  VALUES (v_u, (d ->> 'min')::int, (d ->> 'max')::int, d ->> 'scope',
    ARRAY(SELECT jsonb_array_elements_text(d -> 'abroad'))::char(2)[], (d ->> 'must')::boolean, (d ->> 'excl')::boolean,
    CASE WHEN d -> 'open' = 'null'::jsonb THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text(d -> 'open')) END);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc, faith_enc)
  VALUES (v_u,
    private.dating_field_encrypt(jsonb_build_object('identity', d ->> 'identity',
      'pools', coalesce(nullif(d -> 'pools', 'null'::jsonb), jsonb_build_array(d ->> 'identity')))),
    private.dating_field_encrypt(jsonb_build_object('seeking', d -> 'seeking')),
    CASE WHEN d ->> 'faith' IS NULL THEN NULL ELSE private.dating_field_encrypt(jsonb_build_object(
      'faith', d ->> 'faith', 'denomination', NULL, 'importance', d ->> 'importance')) END);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer, moderation_state)
  SELECT v_u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A matching fixture answer ' || n, 'approved'
    FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  SELECT v_u, 'w5/' || v_u || '/' || n || '.jpg', n, 'approved', 'clear' FROM generate_series(1, 2) AS n;
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, age_vendor, age_decided_at,
    identity_method, identity_result, identity_vendor, identity_decided_at)
  VALUES (v_u, 'id', 'pass', 'contract', now(), 'liveness_compare', 'pass', 'contract', now());
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w5-consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS p;
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (v_u, encode(extensions.digest(pg_temp.dev(p_n), 'sha256'), 'hex'), now(),
          now() - make_interval(days => (d ->> 'seen_days')::int));
  RETURN v_u;
END $$;
CREATE FUNCTION pg_temp.as_person(p uuid, p_device text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', CASE WHEN p_device IS NULL THEN '' ELSE json_build_object('x-attune-device', p_device)::text END, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.headers', '', true);
END $$;
-- [p_sql] as [p] on the phone [p_device] (NULL: no header); the error's
-- SQLSTATE and message when it raises.
CREATE FUNCTION pg_temp.call(p uuid, p_device text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p, p_device);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN coalesce(v, '<NULL>');
EXCEPTION WHEN OTHERS THEN
  PERFORM pg_temp.as_db();
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
-- Runs [p_setup] and [p_probe], then undoes both (a savepoint).
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
    RAISE EXCEPTION 'w5:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w5:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;
-- Both orders of the single-pair predicate, as 'tt', 'ff' or a mix.
CREATE FUNCTION pg_temp.hf(p_a uuid, p_b uuid) RETURNS text LANGUAGE sql AS $$
  SELECT left(public.dating_pair_passes_hard_filters(p_a, p_b)::text, 1) || left(public.dating_pair_passes_hard_filters(p_b, p_a)::text, 1);
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- A person row for the pure filters (§5.2 2-10): the base, then [o].
CREATE FUNCTION pg_temp.pr(p_n int, o jsonb DEFAULT '{}') RETURNS private.dating_gen_person LANGUAGE sql AS $$
  SELECT jsonb_populate_record(NULL::private.dating_gen_person, jsonb_build_object(
    'user_id', ('5e5f0000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid,
    'country', 'GH', 'region', 'AA', 'side', NULL, 'scope', 'region', 'open_abroad', '{}'::text[],
    'age', 30, 'min_age', 25, 'max_age', 40, 'identity', 'woman', 'pools', ARRAY['woman'], 'seeking', ARRAY['man'],
    'intention', 'committed', 'timeline', NULL, 'timeline_visible', true,
    'intention_open', ARRAY['marriage', 'committed', 'companionship', 'not_sure'],
    'children_have', false, 'children_want', 'yes', 'want_must_match', false, 'exclude_parents', false,
    'faith', NULL, 'importance', NULL, 'faith_visible', false, 'family', NULL,
    'same_gender_ok', false, 'abroad_ok', true, 'hmac', md5(p_n::text), 'visible_from', now()) || o);
$$;
CREATE FUNCTION pg_temp.man(p_n int, o jsonb DEFAULT '{}') RETURNS private.dating_gen_person LANGUAGE sql AS $$
  SELECT pg_temp.pr(p_n, '{"identity": "man", "pools": ["man"], "seeking": ["woman"]}'::jsonb || o);
$$;
-- The reviewed config, active for this file (development: DEV- refs pass).
CREATE FUNCTION pg_temp.activate() RETURNS void LANGUAGE sql AS $$
  UPDATE public.dating_algorithm_configs
     SET state = 'active', activated_at = now(), product_review_ref = 'DEV-product', clinical_review_ref = 'DEV-clinical',
         fairness_review_ref = 'DEV-fairness', safety_review_ref = 'DEV-safety'
   WHERE version = 'introductions_v2';
$$;

-- =====================================================================
-- A. (§4.10, R12) The v1 trait objects are gone, no Dating function names
--    one, one introduction per pair ever, a match always carries its pair.
-- =====================================================================
DO $$
DECLARE
  v_got text;
  v_low uuid := pg_temp.id('a1');
  v_high uuid := pg_temp.id('a2');
BEGIN
  IF to_regclass('public.dating_feature_snapshots') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'public' AND p.proname IN ('build_dating_feature_snapshot', 'dating_has_historical_consent',
                   'dating_normalize_scalar', 'dating_alignment_score', 'dating_alignment_reasons', 'dating_component_similarity',
                   'dating_set_similarity', 'generate_dating_candidates_for_user', 'run_dating_candidate_generation'))
     OR to_regprocedure('public.get_my_dating_matches(integer)') IS NOT NULL -- Spec 2 W6a: the v1 read; W6a's takes a boolean
     OR EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'dating_alignment_algorithm_v1')
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'dating_introductions'
                  AND column_name IN ('display_band', 'explanation_features', 'low_summary', 'high_summary', 'internal_score',
                                      'snapshot_low_id', 'snapshot_high_id')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 trait object survived W5a';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY 1) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.prosrc ~ '(dating_feature_snapshots|display_band|explanation_features|internal_score|snapshot_(low|high)_id|(low|high)_summary|dating_alignment_|build_dating_feature_snapshot|run_dating_candidate_generation|generate_dating_candidates_for_user|dating_set_similarity|dating_component_similarity|dating_normalize_scalar|dating_has_historical_consent|get_my_dating_matches)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a function still names a dropped object (R12): %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation' AND command LIKE '%run_dating_candidate_generation%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the weekly v1 generation cron is still scheduled';
  END IF;
  INSERT INTO auth.users (id) VALUES (v_low), (v_high);
  INSERT INTO public.users (id, display_name) VALUES (v_low, 'A1'), (v_high, 'A2');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, algorithm_version)
  VALUES (public.dating_pair_key(v_low, v_high), least(v_low, v_high), greatest(v_low, v_high), 'introductions_v2');
  BEGIN
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, algorithm_version)
    VALUES (public.dating_pair_key(v_low, v_high), least(v_low, v_high), greatest(v_low, v_high), 'introductions_v3');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair was introduced twice';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_got = CONSTRAINT_NAME;
    IF v_got IS DISTINCT FROM 'dating_introductions_pair_key_key' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the second introduction failed on % (expected the pair_key key)', v_got;
    END IF;
  END;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(v_low, v_high), greatest(v_low, v_high), 'closed');
  IF (SELECT pair_key FROM public.dating_matches WHERE user_low_id = least(v_low, v_high)) IS DISTINCT FROM public.dating_pair_key(v_low, v_high) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match was written without its pair';
  END IF;
  DELETE FROM public.dating_matches WHERE user_low_id = least(v_low, v_high);
  DELETE FROM public.dating_introductions WHERE user_low_id = least(v_low, v_high);
END $$;

-- =====================================================================
-- B. (§5.11, §4.3; mutant 20) introductions_v2 is seeded as a draft with
--    its hash; alignment_v1 is retired; daily_new_max can never exceed 3
--    (nor waiting_max 6); the matrix is symmetric; nothing is active until
--    reviewed; in production a DEV- reference can't be activated.
-- =====================================================================
DO $$
DECLARE
  v_cfg jsonb;
  v_got text;
  v_case jsonb;
  a text;
  b text;
BEGIN
  SELECT config INTO v_cfg FROM public.dating_algorithm_configs
   WHERE version = 'introductions_v2' AND config_hash = encode(extensions.digest(config::text, 'sha256'), 'hex');
  IF v_cfg IS NULL OR v_cfg ->> 'daily_new_max' <> '3' OR v_cfg ->> 'waiting_max' <> '6' OR v_cfg ->> 'cool_off_hours' <> '72'
     OR (SELECT state FROM public.dating_algorithm_configs WHERE version = 'alignment_v1') IS DISTINCT FROM 'retired' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the introductions_v2 seed or alignment_v1''s retirement is wrong';
  END IF;
  IF (private.dating_intro_config()).o_version IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a config is active before review';
  END IF;
  -- Fix round 1 (M-6): the cool-off never under 72 hours (§2.8), an
  -- introduction's life never under a day; a non-number is refused by the
  -- same CHECK, never with a cast error.
  FOREACH v_case IN ARRAY ARRAY['{"daily_new_max": 4}', '{"daily_new_max": 5}', '{"daily_new_max": 0}', '{"waiting_max": 7}',
                                '{"daily_new_max": "3x"}', '{"cool_off_hours": 71}', '{"cool_off_hours": 0}',
                                '{"cool_off_hours": "7x"}', '{"lifetime_days": 0}', '{"lifetime_days": -1}']::jsonb[] LOOP
    BEGIN
      INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
      VALUES ('w5-caps-' || md5(v_case::text), 'draft', v_cfg || v_case, md5(v_case::text));
      RAISE EXCEPTION 'CONTRACT VIOLATED: a config with % was accepted', v_case;
    EXCEPTION WHEN check_violation THEN
      GET STACKED DIAGNOSTICS v_got = CONSTRAINT_NAME;
      IF v_got IS DISTINCT FROM 'dating_algorithm_configs_caps_check' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % was refused by % (expected the caps check)', v_case, v_got;
      END IF;
    WHEN raise_exception THEN
      RAISE;
    WHEN OTHERS THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % was refused with % (expected the caps check, 23514)', v_case, SQLSTATE;
    END;
  END LOOP;
  -- At the floors (and above) a config is accepted.
  INSERT INTO public.dating_algorithm_configs (version, state, config, config_hash)
  VALUES ('w5-floors-ok', 'draft', v_cfg || '{"cool_off_hours": 72, "lifetime_days": 1}', 'w5-floors-ok'),
         ('w5-floors-above', 'draft', v_cfg || '{"cool_off_hours": 96, "lifetime_days": 14}', 'w5-floors-above');
  DELETE FROM public.dating_algorithm_configs WHERE version IN ('w5-floors-ok', 'w5-floors-above');
  FOR a, b IN SELECT k, x FROM jsonb_each(v_cfg -> 'intention_matrix') AS m(k, r), jsonb_array_elements_text(m.r) AS x LOOP
    IF NOT (v_cfg -> 'intention_matrix' -> b) ? a THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the intention matrix admits % with % but not % with %', a, b, b, a;
    END IF;
  END LOOP;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  BEGIN
    PERFORM pg_temp.activate();
    RAISE EXCEPTION 'CONTRACT VIOLATED: production activated a config with DEV- review references';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM IS DISTINCT FROM 'config:dev_review_ref' THEN RAISE; END IF;
  END;
  -- Fix round 1 (M-7): any case, any padding.
  FOREACH a IN ARRAY ARRAY['dev-x', ' DEV-x', E'\tDev-x '] LOOP
    BEGIN
      UPDATE public.dating_algorithm_configs
         SET state = 'active', activated_at = now(), product_review_ref = 'PR-1', clinical_review_ref = a,
             fairness_review_ref = 'FR-1', safety_review_ref = 'SR-1'
       WHERE version = 'introductions_v2';
      RAISE EXCEPTION 'CONTRACT VIOLATED: production activated a config with the review reference %', quote_literal(a);
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM IS DISTINCT FROM 'config:dev_review_ref' THEN RAISE; END IF;
    END;
  END LOOP;
  -- Real references (one merely mentions dev) activate in production.
  BEGIN
    v_got := pg_temp.probe(ARRAY[$s$UPDATE public.dating_algorithm_configs
                                      SET state = 'active', activated_at = now(), product_review_ref = 'PR-12 (devices)',
                                          clinical_review_ref = 'CR-3', fairness_review_ref = 'FR-2', safety_review_ref = 'SR-dev-1'
                                    WHERE version = 'introductions_v2'$s$],
                           'SELECT (private.dating_intro_config()).o_version');
  EXCEPTION WHEN check_violation THEN
    v_got := SQLERRM;
  END;
  IF v_got IS DISTINCT FROM 'introductions_v2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a config with real review references (%)', v_got;
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM pg_temp.activate();
  IF (private.dating_intro_config()).o_version IS DISTINCT FROM 'introductions_v2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reviewed config is not the active one';
  END IF;
END $$;

-- =====================================================================
-- C. (§5.2 2-10; mutants 2, 3; carry 2) The pure filters over person
--    rows: admits(x, y) = admits(y, x) over a grid in which every filter
--    differs one way; each filter's passing and failing pair; NULL never.
-- =====================================================================
DO $$
DECLARE
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_grid private.dating_gen_person[];
  x private.dating_gen_person;
  y private.dating_gen_person;
  v_case record;
BEGIN
  v_grid := ARRAY[
    pg_temp.pr(1), pg_temp.man(2),
    pg_temp.man(3, '{"age": 45}'), pg_temp.man(4, '{"min_age": 32}'),
    pg_temp.pr(5, '{"seeking": ["woman"]}'), pg_temp.man(6, '{"seeking": ["man"]}'),
    pg_temp.pr(7, '{"seeking": ["man", "woman"], "same_gender_ok": true}'),
    pg_temp.pr(8, '{"seeking": ["woman"], "same_gender_ok": true}'),
    pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary", "woman"], "seeking": ["man", "woman", "non_binary"], "same_gender_ok": true}'),
    pg_temp.man(10, '{"region": "AH"}'), pg_temp.man(11, '{"region": "AH", "scope": "country"}'),
    pg_temp.man(12, '{"side": "tema", "scope": "side"}'), pg_temp.pr(13, '{"side": "accra", "scope": "side"}'),
    pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'),
    pg_temp.pr(15, '{"open_abroad": ["GB"]}'), pg_temp.pr(16, '{"open_abroad": ["GB"], "abroad_ok": false}'),
    pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(18, '{"intention": "companionship"}'),
    pg_temp.man(19, '{"intention_open": ["marriage"]}'),
    pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(21, '{"children_want": "open"}'),
    pg_temp.man(22, '{"exclude_parents": true}'), pg_temp.pr(23, '{"children_have": true}'),
    pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(25, '{"faith": "christian"}'),
    pg_temp.pr(26, '{"faith": "muslim"}'), pg_temp.pr(27, '{"faith": "prefer_not_to_say"}'),
    pg_temp.pr(28, '{"seeking": null}'), pg_temp.man(29, '{"identity": null, "pools": null}')];
  FOREACH x IN ARRAY v_grid LOOP
    FOREACH y IN ARRAY v_grid LOOP
      IF private.dating_admits(x, y, v_cfg) IS DISTINCT FROM private.dating_admits(y, x, v_cfg) THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: the filters are not symmetric for % and % (mutant 2)',
          right(x.user_id::text, 2), right(y.user_id::text, 2);
      END IF;
    END LOOP;
  END LOOP;
  FOR v_case IN SELECT * FROM (VALUES
    ('base pair passes', pg_temp.pr(1), pg_temp.man(2), true),
    ('2 an age outside the range', pg_temp.pr(1), pg_temp.man(3, '{"age": 45}'), false),
    ('3 a seeking set that misses the pools', pg_temp.pr(5, '{"seeking": ["woman"]}'), pg_temp.man(2), false),
    ('4 two women, both allowed', pg_temp.pr(7, '{"seeking": ["woman"], "same_gender_ok": true}'), pg_temp.pr(8, '{"seeking": ["woman"], "same_gender_ok": true}'), true),
    ('4 two women, one not allowed', pg_temp.pr(7, '{"seeking": ["woman"], "same_gender_ok": true}'), pg_temp.pr(8, '{"seeking": ["woman"]}'), false),
    ('4 a non-binary person and a man, both allowed', pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary"], "seeking": ["man"], "same_gender_ok": true}'), pg_temp.man(2, '{"seeking": ["non_binary"], "same_gender_ok": true}'), true),
    ('4 a non-binary person and a man, not allowed', pg_temp.pr(9, '{"identity": "non_binary", "pools": ["non_binary"], "seeking": ["man"], "same_gender_ok": true}'), pg_temp.man(2, '{"seeking": ["non_binary"]}'), false),
    ('5 across borders, both open, both 14 days', pg_temp.pr(15, '{"open_abroad": ["GB"]}'), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), true),
    ('5 across borders, one not open', pg_temp.pr(1), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), false),
    ('5 across borders, one account under 14 days', pg_temp.pr(16, '{"open_abroad": ["GB"], "abroad_ok": false}'), pg_temp.man(14, '{"country": "GB", "region": "TLI", "open_abroad": ["GH"]}'), false),
    ('6 another region, scope region', pg_temp.pr(1), pg_temp.man(10, '{"region": "AH"}'), false),
    ('6 another region, both scope country', pg_temp.pr(1, '{"scope": "country"}'), pg_temp.man(11, '{"region": "AH", "scope": "country"}'), true),
    ('6 another side, scope side', pg_temp.pr(13, '{"side": "accra", "scope": "side"}'), pg_temp.man(12, '{"side": "tema", "scope": "side"}'), false),
    ('6 another side, scope region', pg_temp.pr(13, '{"side": "accra"}'), pg_temp.man(12, '{"side": "tema"}'), true),
    ('7 marriage and companionship', pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(18, '{"intention": "companionship"}'), false),
    ('7 marriage and committed', pg_temp.man(17, '{"intention": "marriage"}'), pg_temp.pr(1), true),
    ('7 an intention not open to', pg_temp.man(19, '{"intention_open": ["marriage"]}'), pg_temp.pr(1), false),
    ('8 must match, no against yes', pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(1), false),
    ('8 must match, no against open', pg_temp.man(20, '{"want_must_match": true, "children_want": "no"}'), pg_temp.pr(21, '{"children_want": "open"}'), true),
    ('9 parents excluded, a parent', pg_temp.man(22, '{"exclude_parents": true}'), pg_temp.pr(23, '{"children_have": true}'), false),
    ('10 must share, the same', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(25, '{"faith": "christian"}'), true),
    ('10 must share, another faith', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(26, '{"faith": "muslim"}'), false),
    ('10 must share, prefer not to say', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(27, '{"faith": "prefer_not_to_say"}'), false),
    ('10 must share, skipped', pg_temp.man(24, '{"faith": "christian", "importance": "must_share"}'), pg_temp.pr(1), false),
    ('carry 2 no who-to-meet', pg_temp.pr(28, '{"seeking": null}'), pg_temp.man(2), false),
    ('carry 2 no identity', pg_temp.pr(1), pg_temp.man(29, '{"identity": null, "pools": null}'), false)) AS t(why, a, b, expected) LOOP
    IF private.dating_admits(v_case.a, v_case.b, v_cfg) IS DISTINCT FROM v_case.expected
       OR private.dating_admits(v_case.b, v_case.a, v_cfg) IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: filter fixture "%" admitted %/% (expected %)', v_case.why,
        private.dating_admits(v_case.a, v_case.b, v_cfg),
        private.dating_admits(v_case.b, v_case.a, v_cfg), v_case.expected;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- D. (§5.2 1, 11-14; carries 4, 7; R-17) Real people, both orders: a
--    current pair passes; each failing fixture (rolled back) fails both
--    ways: paused, not seen in 14 days, the cool-off past the next drop,
--    hidden by travel, the age check revoked, identity not verified, a
--    path off Dating; a block by id or by phone HMAC; former partners; a
--    never-introduce entry, a kept one too; introduced or matched before.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('11');
  m constant uuid := pg_temp.ready('12', '{"identity": "man", "seeking": ["woman"]}');
  v_probe constant text := format('SELECT pg_temp.hf(%L, %L)', pg_temp.id('11'), pg_temp.id('12'));
  v_case record;
  v text;
BEGIN
  IF pg_temp.hf(w, m) IS DISTINCT FROM 'tt' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a current pair does not pass the hard filters (%)', pg_temp.hf(w, m);
  END IF;
  FOR v_case IN SELECT * FROM (VALUES
    -- Fix round 1 (I-1): a relationship that ended 10 days ago (the 30-day
    -- gentle wait, §2.1 gate 5) keeps the person out of others' days.
    ('1 in the gentle wait', 'ff', ARRAY[
       format('INSERT INTO auth.users (id) VALUES (%L)', pg_temp.id('19')),
       format('INSERT INTO public.users (id, display_name) VALUES (%L, ''Former 19'')', pg_temp.id('19')),
       format('INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (%L, %L, ''ended'', now() - interval ''10 days'')', m, pg_temp.id('19'))]),
    ('1 paused', 'ff', ARRAY[format('UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'' WHERE user_id = %L', m)]),
    ('1 not seen in 14 days', 'ff', ARRAY[format('UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval ''15 days'' WHERE user_id = %L', m)]),
    ('1 seen through the session context', 'tt', ARRAY[
       format('UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval ''15 days'' WHERE user_id = %L', m),
       format('INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved) VALUES (%L, 1, true, false, false, true)', m)]),
    ('1 the cool-off past the next drop (carry 1)', 'ff', ARRAY[format('UPDATE public.users SET created_at = now() WHERE id = %L', m)]),
    ('1 hidden by travel', 'ff', ARRAY[format('INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved) VALUES (%L, 1, false, false, true, true)', m)]),
    ('1 the age check revoked (carry 7)', 'ff', ARRAY[format('UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = ''contract'' WHERE user_id = %L', m)]),
    ('1 identity not verified (carry 7)', 'ff', ARRAY[format('UPDATE public.dating_profiles SET verification_state = ''needs_review'' WHERE user_id = %L', m)]),
    ('1 a path off Dating', 'ff', ARRAY[format('UPDATE public.users SET path = ''just_me'' WHERE id = %L', m)]),
    ('11 a block', 'ff', ARRAY[format('INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (%L, %L, public.dating_pair_key(%L, %L))', m, w, m, w)]),
    ('11 a block by phone HMAC', 'ff', ARRAY[format('INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac) VALUES (public.dating_phone_hmac_for_user(%L), public.dating_phone_hmac_for_user(%L))', w, m)]),
    ('12 former partners', 'ff', ARRAY[format('INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (%L, %L, ''archived'', now() - interval ''90 days'')', w, m)]),
    ('13 on the never-introduce list', 'ff', ARRAY[format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''12'')', w, m)]),
    ('13 kept on the list from before (carry 4)', 'ff', ARRAY[format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''12'', now() - interval ''1 day'')', m, w)]),
    ('14 introduced before', 'ff', ARRAY[format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) VALUES (public.dating_pair_key(%L, %L), least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''passed'', ''introductions_v2'')', w, m, w, m, w, m)]),
    ('14 matched before', 'ff', ARRAY[format('INSERT INTO public.dating_matches (user_low_id, user_high_id, state, closed_reason) VALUES (least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''closed'', ''unmatched'')', w, m, w, m)])
  ) AS t(why, expected, setup) LOOP
    v := pg_temp.probe(v_case.setup, v_probe);
    IF v IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: hard filter fixture "%" answered % (expected %)', v_case.why, v, v_case.expected;
    END IF;
  END LOOP;
  IF pg_temp.hf(w, m) IS DISTINCT FROM 'tt' THEN
    RAISE EXCEPTION 'fixture: a probe was not undone';
  END IF;
END $$;

-- =====================================================================
-- E. (§2.4, §5.2 4; mutant 3; carry 3) Same-gender needs the global flag,
--    both Dating countries and both people's fresh contexts (7 days), and
--    is never made in Ghana, whatever a row says (generation is the
--    backstop for the writers' refusal).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('21', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  b constant uuid := pg_temp.ready('22', '{"country": "GB", "region": "TLI", "seeking": ["woman"]}');
  -- Fix round 1 (M-4): the two Ghana women seek men too, so a Ghana man is
  -- their positive control (each is a current candidate; only the
  -- same-gender rule keeps them apart).
  g1 constant uuid := pg_temp.ready('23', '{"seeking": ["man", "woman"]}');
  g2 constant uuid := pg_temp.ready('24', '{"seeking": ["man", "woman"]}');
  gm constant uuid := pg_temp.ready('25', '{"identity": "man", "seeking": ["woman"]}');
  v_ctx constant text := 'INSERT INTO public.dating_session_context (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home, ip_resolved, checked_at) VALUES (%L, 3, true, %L, false, true, now() - %L::interval)';
  v_case record;
  v text;
BEGIN
  FOR v_case IN SELECT * FROM (VALUES
    ('both allowed and fresh in the UK', 'tt', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '6 days')]),
    ('no context', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day')]),
    ('a context 8 days old', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '8 days')]),
    ('not allowed where one is', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, false, '1 day')]),
    ('the global flag off', 'ff', a, b, ARRAY[format(v_ctx, a, true, '1 day'), format(v_ctx, b, true, '1 day'),
       'UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_same_gender_matching''']),
    ('Ghana, whatever the rows say (carry 3)', 'ff', g1, g2, ARRAY[format(v_ctx, g1, true, '1 day'), format(v_ctx, g2, true, '1 day')]),
    ('Ghana control: the first woman and a Ghana man', 'tt', g1, gm, ARRAY[format(v_ctx, g1, true, '1 day'), format(v_ctx, gm, false, '1 day')]),
    ('Ghana control: the second woman and a Ghana man', 'tt', g2, gm, ARRAY[format(v_ctx, g2, true, '1 day'), format(v_ctx, gm, false, '1 day')])
  ) AS t(why, expected, x, y, setup) LOOP
    v := pg_temp.probe(v_case.setup, format('SELECT pg_temp.hf(%L, %L)', v_case.x, v_case.y));
    IF v IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: same-gender fixture "%" answered % (expected %)', v_case.why, v, v_case.expected;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- F. (§2.8, §5.3; carry 1) The cool-off ends 72 hours (the config's
--    hours) after the account was made; the drop is 19:00 in the person's
--    own zone when it is a real zone, else the country's.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('31', '{"days": 1, "tz": "Africa/Lagos"}');
  x constant uuid := pg_temp.ready('32', '{"tz": "Mars/Olympus"}');
  v_made timestamptz;
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes';
BEGIN
  SELECT created_at INTO v_made FROM public.users WHERE id = u;
  IF private.dating_cool_off_ends_at(u) IS DISTINCT FROM v_made + interval '72 hours'
     -- W5 final (M-7): an active config's values are frozen, so the probe
     -- W5 final takes it out of active, edits it and activates it again.
     OR pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET state = ''reviewed'' WHERE version = ''introductions_v2''', 'UPDATE public.dating_algorithm_configs SET config = config || ''{"cool_off_hours": 96}'' WHERE version = ''introductions_v2''', 'SELECT pg_temp.activate()'],
                      format('SELECT private.dating_cool_off_ends_at(%L) = %L::timestamptz + interval ''96 hours''', u, v_made)) IS DISTINCT FROM 'true'
     OR private.dating_cool_off_ends_at(pg_temp.id('f9')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cool-off does not end at account creation + the config''s hours';
  END IF;
  IF (private.dating_first_drop_at(u, v_at) AT TIME ZONE 'Africa/Lagos')::time IS DISTINCT FROM time '19:00'
     OR (private.dating_first_drop_at(x, v_at) AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '19:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drop is not 19:00 in the person''s own zone (or the country''s for an unknown zone)';
  END IF;
  IF private.dating_person_current(u, v_at, (private.dating_intro_config()).o_config)
     OR NOT private.dating_person_current(u, v_at + interval '3 days', (private.dating_intro_config()).o_config) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a day-old account is a candidate before its cool-off, or not after it (carry 1)';
  END IF;
END $$;

-- =====================================================================
-- K. (§3.4, §4.10; carries 4, 8; R-17) Spec 2 W5b: the v2 read and act.
--    The caller's own trusted phone first, so another phone reads nothing
--    and changes nobody's introduction; nothing before this side's drop
--    (the day says when); a kept never-introduce entry ends the pair and
--    the answer is the one any unavailable introduction gets; mutual
--    interest makes one match and queues no push; a replay answers as the
--    first did and there is no rewind; a pass takes the card away.
--    Task 1 review M-3: the two sides' drops differ (w's still to come,
--    k's past), so a read or act that took the other side's drop fails.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('41');
  m constant uuid := pg_temp.ready('42', '{"identity": "man", "seeking": ["woman"]}');
  k constant uuid := pg_temp.ready('43', '{"identity": "man", "seeking": ["woman"]}');
  v_wm uuid;
  v_wk uuid;
  v jsonb;
  v_pushes bigint := (SELECT count(*) FROM public.scheduled_notifications);
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour', ARRAY['same_intention'])
  RETURNING id INTO v_wm;
  -- M-3: only w's drop is still to come; k's has passed.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, k), least(w, k), greatest(w, k), 'generated', 'introductions_v2',
          CASE WHEN least(w, k) = w THEN now() + interval '1 hour' ELSE now() - interval '1 hour' END,
          CASE WHEN greatest(w, k) = w THEN now() + interval '1 hour' ELSE now() - interval '1 hour' END)
  RETURNING id INTO v_wk;
  v := pg_temp.call(w, pg_temp.dev('41'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF v ->> 'today_state' IS DISTINCT FROM 'delivered' OR jsonb_array_length(v -> 'cards') <> 1
     OR v #>> '{cards,0,id}' IS DISTINCT FROM v_wm::text OR jsonb_array_length(v -> 'waiting') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the person''s own phone reads today as %', v;
  END IF;
  -- Carry 8: another phone (or none) reads nothing.
  IF pg_temp.call(w, pg_temp.dev('99'), 'SELECT public.get_my_dating_today()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'
     OR pg_temp.call(w, NULL, 'SELECT public.get_my_dating_introductions()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone read the introductions (carry 8)';
  END IF;
  -- R-17: acting from another phone is refused before anything changes.
  v := pg_temp.call(w, pg_temp.dev('99'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-stranger'), v_wm))::jsonb;
  IF v IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wm) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another phone''s act answered % and left the introduction %', v,
      (SELECT state FROM public.dating_introductions WHERE id = v_wm);
  END IF;
  -- Not before this side's drop: the day says when.
  UPDATE public.dating_introductions SET visible_from_low = now() - interval '1 hour', visible_from_high = now() - interval '1 hour' WHERE id = v_wm;
  IF pg_temp.probe(ARRAY[format('UPDATE public.dating_introductions SET state = ''passed'', low_action = ''passed'', high_action = ''passed'' WHERE id = %L', v_wm)],
                   format('SELECT pg_temp.call(%L, %L, ''SELECT public.get_my_dating_today()'')::jsonb ->> ''today_state''', w, pg_temp.dev('41')))
       IS DISTINCT FROM 'before_drop'
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-early'), v_wk))
        IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'
     -- H2: one that doesn't exist answers the same.
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-absent'), '5e5e0000-0000-4000-8000-0000000000fe'))
        IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an introduction was answered before this side''s drop, or the day did not say it is coming';
  END IF;
  -- M-3: the other side, whose drop has passed, reads it (positive control).
  IF pg_temp.call(k, pg_temp.dev('43'), 'SELECT public.get_my_dating_introductions()')::jsonb #>> '{cards,0,id}' IS DISTINCT FROM v_wk::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the side whose drop has passed does not read the introduction (M-3)';
  END IF;
  -- Carry 4: a kept never-introduce entry ends the pair at the act, with
  -- the one answer any unavailable introduction gets.
  UPDATE public.dating_introductions SET visible_from_high = now() - interval '1 hour', visible_from_low = now() - interval '1 hour' WHERE id = v_wk;
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (k, public.dating_phone_hmac_for_user(w), '41', now());
  v := pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-kept'), v_wk))::jsonb;
  IF v IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wk) <> 'invalidated'
     OR jsonb_array_length(pg_temp.call(w, pg_temp.dev('41'), 'SELECT public.get_my_dating_introductions()')::jsonb -> 'cards') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce entry did not end the pair (%; %)', v, (SELECT state FROM public.dating_introductions WHERE id = v_wk);
  END IF;
  -- Mutual interest: one match, no push (§3.13); a replay, no rewind.
  v := pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-w'), v_wm))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": false}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first interest answered %', v;
  END IF;
  v := pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m'), v_wm))::jsonb;
  IF v - 'match_id' IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": true}' -- Spec 2 W6a (carry 7)
     OR v ->> 'match_id' IS DISTINCT FROM (SELECT id::text FROM public.dating_matches WHERE introduction_id = v_wm) -- Spec 2 W6a
     OR (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm AND state = 'active') <> 1
     OR (SELECT count(*) FROM public.scheduled_notifications) <> v_pushes THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mutual interest answered %, made % match(es), queued % push(es)', v,
      (SELECT count(*) FROM public.dating_matches WHERE introduction_id = v_wm),
      (SELECT count(*) FROM public.scheduled_notifications) - v_pushes;
  END IF;
  IF pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m'), v_wm))
       IS DISTINCT FROM v::text -- Spec 2 W6a (carry 7): the replay names the same match
     OR pg_temp.call(w, pg_temp.dev('41'), format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', md5('k-w-again'), v_wm))::jsonb
        ->> 'reason' IS DISTINCT FROM 'introduction_unavailable'
     OR (SELECT state || low_action || high_action FROM public.dating_introductions WHERE id = v_wm) <> 'matchedinterestedinterested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay answered differently, or a second answer rewound the first';
  END IF;
  -- No rewind on a card still open either: interested, then "Not for me".
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(m, k), least(m, k), greatest(m, k), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_wk;
  PERFORM pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k-m-k'), v_wk));
  v := pg_temp.call(m, pg_temp.dev('42'), format('SELECT public.act_on_dating_introduction(%L, %L, ''passed'')', md5('k-m-k2'), v_wk))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "action": "interested", "matched": false}' OR (SELECT state FROM public.dating_introductions WHERE id = v_wk) <> 'interested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Not for me" after "Interested" rewound it (%)', v;
  END IF;
END $$;

-- =====================================================================
-- J. (carry 10) A re-check waiting on an untrusted phone is read back for
--    72 hours from its submission, as the sweep keeps it.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('51');
  v jsonb;
BEGIN
  INSERT INTO public.dating_verification_sessions (user_id, kind, step, vendor, state, device_hash, created_at, expires_at, awaiting_since)
  VALUES (u, 'reverify', 'human', 'fake', 'awaiting_review', encode(extensions.digest(pg_temp.dev('59'), 'sha256'), 'hex'),
          now() - interval '50 hours', now() - interval '49 hours', now() - interval '49 hours');
  v := pg_temp.call(u, pg_temp.dev('59'), 'SELECT public.get_my_dating_verification()')::jsonb;
  IF v ->> 'device' IS DISTINCT FROM 'untrusted' OR v #>> '{session,state}' IS DISTINCT FROM 'awaiting_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-check submitted 49 hours ago is not read back (carry 10): %', v;
  END IF;
END $$;

-- =====================================================================
-- G. (§5.3-§5.8; mutant 6; carries 1, 4, 6) Generation. Everyone from the
--    sections above leaves Dating first, so the run sees only G's people.
--    Refusals before any work, each counted; one run: GH's partition and
--    cohort, both sides' drops, the seven days, up to three reasons, the
--    rank detail, a kept never-introduce pair left out, only the best band
--    (§5.4 6); a GB person open to Ghana introduced across the border
--    when both are open; a second run creates 0; the
--    same seed makes the same introductions in the same order; capacity
--    3 a day, 6 waiting, 3 open chats; nobody over 3 in a run; a thin pool
--    yields 0 and is counted; a side's own unanswered seven days end the
--    pair; a run that fails publishes nothing and dead-letters after three
--    tries; every temp table a Dating function makes is dropped at commit.
-- =====================================================================
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '3 hours 17 minutes';
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  w1 uuid;
  w2 uuid;
  m1 uuid;
  m2 uuid;
  g1 uuid;
  v jsonb;
  v_first jsonb;
  v_again jsonb;
  v_n bigint;
  v_bad text;
  v_empty bigint;
  v_move text;
  v_m2 jsonb;
  v_four text; -- fix round 1 (M-7)
  v_six uuid[];
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  w1 := pg_temp.ready('61', '{"abroad": ["GB"], "family": "early"}');
  w2 := pg_temp.ready('62', '{"intention": "marriage", "timeline": "few_years"}');
  m1 := pg_temp.ready('63', '{"identity": "man", "seeking": ["woman"], "family": "early"}');
  m2 := pg_temp.ready('64', '{"identity": "man", "seeking": ["woman"], "intention": "marriage", "timeline": "few_years"}');
  g1 := pg_temp.ready('65', '{"identity": "man", "seeking": ["woman"], "country": "GB", "region": "TLI", "abroad": ["GH"]}');
  -- Carry 4: w2's kept list names m2.
  INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at)
  VALUES (w2, public.dating_phone_hmac_for_user(m2), '64', now() - interval '2 days');
  -- The seed is the cohort date's, so §5.4 1's tie order changes daily: m1
  -- met someone two days ago (exposure 1), so w1 always takes her turn
  -- before m1 and the band check below never depends on the day.
  -- (Spec 2 W6: fixture fix; G2 failed on days m1 sorted before w1.)
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
    visible_from_low, visible_from_high, created_at, expires_at)
  SELECT public.dating_pair_key(m1, o), least(m1, o), greatest(m1, o), 'expired', 'introductions_v2',
         v_at - interval '2 days', v_at - interval '2 days', v_at - interval '2 days', v_at - interval '1 day'
    FROM (SELECT pg_temp.ready('a0') AS o) AS x;
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE user_id = pg_temp.id('a0');

  -- G1. Refusals before any work, each counted.
  IF pg_temp.probe(ARRAY['UPDATE public.feature_flags SET enabled = false WHERE key = ''dating_candidate_generation'''],
       format('SELECT (public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped'') || '':'' || pg_temp.metric(''dating.generation.skipped'')', v_at))
       IS DISTINCT FROM 'flag_disabled:' || (pg_temp.metric('dating.generation.skipped') + 1)
     OR pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET state = ''retired'', retired_at = now() WHERE version = ''introductions_v2'''],
       format('SELECT public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped''', v_at)) IS DISTINCT FROM 'no_active_config'
     OR pg_temp.probe(ARRAY['SELECT set_config(''app.settings.dating_field_key'', '''', true)'],
       format('SELECT public.run_dating_generation_tick(%L, ''GH'') ->> ''skipped''', v_at)) IS DISTINCT FROM 'missing_key'
     -- Before Ghana's hour: nothing runs (fix round 2, N-2: a later hour of
     -- the cohort day catches up, so the check is the hour before).
     OR public.run_dating_generation_tick(v_at - interval '1 hour', 'GH') IS DISTINCT FROM '{"runs": []}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation did not refuse (and count) before any work';
  END IF;

  -- G2. One run.
  v_empty := pg_temp.metric('dating.empty_day.gh.aa');
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF v #>> '{runs,0,partition}' IS DISTINCT FROM 'GH' OR (v #>> '{runs,0,created}')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the run answered % (expected GH with 3 introductions)', v;
  END IF;
  SELECT string_agg(x.pair_key || ': ' || x.why, '; ') INTO v_bad FROM (
    SELECT i.pair_key, concat_ws(', ',
             CASE WHEN i.partition_key IS DISTINCT FROM 'GH' OR i.cohort_window IS DISTINCT FROM (v_at AT TIME ZONE 'Africa/Accra')::date THEN 'partition/cohort' END,
             CASE WHEN i.visible_from_low IS DISTINCT FROM private.dating_first_drop_at(i.user_low_id, v_at)
                    OR i.visible_from_high IS DISTINCT FROM private.dating_first_drop_at(i.user_high_id, v_at) THEN 'drops' END,
             CASE WHEN i.expires_at IS DISTINCT FROM greatest(i.visible_from_low, i.visible_from_high) + interval '7 days' THEN 'expiry' END,
             CASE WHEN cardinality(i.reasons) > 3 OR i.state <> 'generated' THEN 'shape' END,
             CASE WHEN (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(i.rank_detail) AS k) IS DISTINCT FROM ARRAY['exposure', 'f', 'jitter', 'seq', 'v'] THEN 'rank detail' END) AS why
      FROM public.dating_introductions AS i WHERE i.created_at = v_at) AS x WHERE x.why <> '';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an introduction is malformed: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w2, m2))
     -- §5.4 6: g1 (abroad, no shared region) is outside w1's best band.
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, g1))
     OR (SELECT reasons FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, m1))
        IS DISTINCT FROM ARRAY['same_intention', 'children_want_yes', 'family_same_early'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept never-introduce pair or a pair outside the band was introduced, or w1-m1''s reasons are % (carry 4, §5.4, §5.8)',
      (SELECT reasons FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w1, m1));
  END IF;

  -- G3. A second run of the cohort creates 0.
  v_n := (SELECT count(*) FROM public.dating_introductions);
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF v #>> '{runs,0,skipped}' IS DISTINCT FROM 'partition_unavailable' OR (SELECT count(*) FROM public.dating_introductions) <> v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second run of the cohort answered % and created %', v, (SELECT count(*) FROM public.dating_introductions) - v_n;
  END IF;
  -- Fix round 2 (N-2): nor does a later hour of a completed cohort.
  v := public.run_dating_generation_tick(v_at + interval '1 hour', 'GH');
  IF v IS DISTINCT FROM '{"runs": []}'::jsonb OR (SELECT count(*) FROM public.dating_introductions) <> v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later hour of a completed cohort answered %', v;
  END IF;

  -- G4. The same seed, the same introductions in the same order (§5.7).
  SELECT jsonb_agg(jsonb_build_array(i.pair_key, i.rank_detail, i.reasons, i.visible_from_low, i.visible_from_high) ORDER BY (i.rank_detail ->> 'seq')::int)
    INTO v_first FROM public.dating_introductions AS i WHERE i.created_at = v_at;
  DELETE FROM public.dating_introductions WHERE created_at = v_at;
  DELETE FROM public.dating_generation_runs WHERE partition_key = 'GH';
  PERFORM public.run_dating_generation_tick(v_at, 'GH');
  SELECT jsonb_agg(jsonb_build_array(i.pair_key, i.rank_detail, i.reasons, i.visible_from_low, i.visible_from_high) ORDER BY (i.rank_detail ->> 'seq')::int)
    INTO v_again FROM public.dating_introductions AS i WHERE i.created_at = v_at;
  IF v_again IS DISTINCT FROM v_first THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same seed made different introductions: % then %', v_first, v_again;
  END IF;

  -- Fix round 1 (M-7): six current people for the waiting cases (a card
  -- whose other person is not current holds no slot); made after the
  -- runs above, so no run sees them.
  v_six := ARRAY(SELECT pg_temp.ready(n) FROM unnest(ARRAY['66', '67', '68', '69', '79', '80']) AS n ORDER BY n);
  -- G5. Capacity: 3 a day, 6 waiting, 3 open chats.
  IF private.dating_capacity(w1, v_at, v_cfg) <> 1 OR private.dating_capacity(m1, v_at, v_cfg) <> 1
     OR pg_temp.probe(ARRAY[format('UPDATE public.dating_introductions SET created_at = %L::timestamptz - interval ''2 days'' WHERE %L IN (user_low_id, user_high_id)', v_at, w1)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg)) IS DISTINCT FROM '3'
     OR pg_temp.probe(ARRAY[format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, created_at, expires_at) SELECT public.dating_pair_key(%L, o), least(%L::uuid, o), greatest(%L::uuid, o), ''generated'', ''introductions_v2'', %L, %L, %L::timestamptz - interval ''2 days'', %L::timestamptz + interval ''5 days'' FROM unnest(%L::uuid[]) AS o', m2, m2, m2, v_at, v_at, v_at, v_at, v_six),
                           format('UPDATE public.dating_introductions SET created_at = %L::timestamptz - interval ''2 days'' WHERE %L IN (user_low_id, user_high_id) AND created_at = %L', v_at, m2, v_at)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', m2, v_at, v_cfg)) IS DISTINCT FROM '0'
     OR pg_temp.probe(ARRAY[format('INSERT INTO public.dating_matches (user_low_id, user_high_id, state, matched_at) SELECT least(%L::uuid, o), greatest(%L::uuid, o), ''active'', now() FROM unnest(ARRAY[pg_temp.id(''11''), pg_temp.id(''21''), pg_temp.id(''22'')]) AS o', g1, g1)],
                      format('SELECT private.dating_capacity(%L, %L, %L)', g1, v_at + interval '2 days', v_cfg)) IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: capacity is not min(3 - today, 6 - waiting), 0 at 3 open chats';
  END IF;
  -- Task 1 review M-2: an introduction whose pair a never-introduce entry
  -- (or a block) has ended since is never read again (an add changes no
  -- introduction; the act's invalidate rolls back with its raise), so it
  -- holds no waiting slot: w1 with six waiting has no room (the control),
  -- and once one of the six is listed, room for one.
  v_move := format('UPDATE public.dating_introductions SET created_at = %L::timestamptz - interval ''2 days'' WHERE %L IN (user_low_id, user_high_id)', v_at, w1);
  v_four := format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, created_at, expires_at) SELECT public.dating_pair_key(%L, o), least(%L::uuid, o), greatest(%L::uuid, o), ''generated'', ''introductions_v2'', %L, %L, %L::timestamptz - interval ''2 days'', %L::timestamptz + interval ''5 days'' FROM unnest(%L::uuid[]) AS o', w1, w1, w1, v_at, v_at, v_at, v_at, v_six[1:4]);
  v_m2 := to_jsonb(ARRAY[
    pg_temp.probe(ARRAY[v_move, v_four], format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg)),
    pg_temp.probe(ARRAY[v_move, v_four,
                        format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''61'')', v_six[1], w1)],
                  format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg))]);
  IF v_m2 IS DISTINCT FROM '["0", "1"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a pair ended by the never-introduce list since it was introduced holds a waiting slot (Task 1 review M-2): six waiting, then one listed, gave %', v_m2;
  END IF;
  -- Fix round 1 (M-7): as the read, a card whose other person is not
  -- current (paused, or unseen in Dating for 14 days) holds no slot.
  v_m2 := to_jsonb(ARRAY[
    pg_temp.probe(ARRAY[v_move, v_four,
                        format('UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'' WHERE user_id = %L', v_six[2])],
                  format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg)),
    pg_temp.probe(ARRAY[v_move, v_four,
                        format('UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval ''15 days'' WHERE user_id = %L', v_six[3])],
                  format('SELECT private.dating_capacity(%L, %L, %L)', w1, v_at, v_cfg))]);
  IF v_m2 IS DISTINCT FROM '["1", "1"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a card hidden because its other person is paused or unseen for 14 days holds a waiting slot (fix round 1, M-7): paused, unseen gave %', v_m2;
  END IF;
END $$;

-- G6. Nobody over 3 in a run; a thin pool yields 0 and is counted; a
--     side's own unanswered seven days end the pair; a failing run
--     publishes nothing and dead-letters after three tries; temp tables.
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '1 day 3 hours 17 minutes';
  m uuid;
  t uuid;
  w3 uuid;
  g2 uuid;
  v jsonb;
  v_empty bigint;
  v_unreadable bigint;
  v_id uuid;
  v_bad text;
  v_cohort text; -- fix round 1 (I-1)
  v_def text;
  v_reset text[];
  v_list text;
  v_clean text;
  v_got text;
  v_code text;
  v_runs text; -- fix round 2 (N-2)
  v_mid text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  m := pg_temp.ready('70', '{"identity": "man", "seeking": ["woman"]}');
  PERFORM pg_temp.ready(n::text, '{}') FROM generate_series(71, 75) AS n;
  t := pg_temp.ready('76', '{"min": 60, "max": 70}');
  -- §2.6: a woman in Ashanti open to the UK, a London man open to Ghana.
  w3 := pg_temp.ready('77', '{"region": "AH", "abroad": ["GB"]}');
  g2 := pg_temp.ready('78', '{"identity": "man", "seeking": ["woman"], "country": "GB", "region": "TLI", "abroad": ["GH"]}');
  -- An unreadable answer skips that person only, counted.
  UPDATE public.dating_profile_sensitive SET identity_enc = '\x01c30d0407'::bytea WHERE user_id = pg_temp.id('75');
  v_unreadable := pg_temp.metric('dating.generation.unreadable');
  v_empty := pg_temp.metric('dating.empty_day.gh.aa');
  v := public.run_dating_generation_tick(v_at, 'GH');
  IF pg_temp.metric('dating.generation.unreadable') <> v_unreadable + 1
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE pg_temp.id('75') IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable answer stopped the run or was introduced uncounted';
  END IF;
  IF (SELECT count(*) FROM public.dating_introductions WHERE m IN (user_low_id, user_high_id) AND created_at = v_at) <> 3
     OR (v #>> '{runs,0,created}')::int <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one man and five women made % (expected 3: §5.3 daily_new_max; and one across the border)', v;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(w3, g2) AND partition_key = 'GH'
                    AND reasons = ARRAY['same_intention', 'children_want_yes'])
     OR pg_temp.probe(ARRAY[format('DELETE FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(%L, %L)', w3, g2),
                            format('DELETE FROM public.dating_generation_runs WHERE partition_key = ''GH'' AND cohort_window = %L', (v_at AT TIME ZONE 'Africa/Accra')::date::text),
                            format('UPDATE public.dating_preferences SET open_abroad = ''{}'' WHERE user_id = %L', g2),
                            format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at)],
                      format('SELECT count(*) FROM public.dating_introductions WHERE pair_key = public.dating_pair_key(%L, %L)', w3, g2))
        IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the border pair open both ways was not introduced in Ghana''s run, or was when one side is not open (§2.6)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_introductions WHERE t IN (user_low_id, user_high_id))
     OR pg_temp.metric('dating.empty_day.gh.aa') < v_empty + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a thin pool was filled or not counted (§5.6)';
  END IF;
  -- Fix round 1 (I-1): a run that fails at the country's hour runs again at
  -- a LATER hour of the same cohort, and makes what a clean run makes (the
  -- same seed); a later partition's failure or timeout (GH after GB in one
  -- tick) leaves the earlier partition's introductions in place.
  v_cohort := (v_at AT TIME ZONE 'Africa/Accra')::date::text;
  v_def := pg_get_functiondef('private.dating_reasons(private.dating_gen_person,private.dating_gen_person)'::regprocedure);
  v_reset := ARRAY[format('DELETE FROM public.dating_generation_runs WHERE cohort_window = %L', v_cohort),
                   format('DELETE FROM public.dating_introductions WHERE created_at = %L', v_at)];
  v_list := 'SELECT jsonb_agg(jsonb_build_array(i.pair_key, i.rank_detail, i.reasons, i.visible_from_low, i.visible_from_high) ORDER BY (i.rank_detail ->> ''seq'')::int)::text FROM public.dating_introductions AS i WHERE i.created_at = %L';
  v_clean := pg_temp.probe(v_reset || format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at), format(v_list, v_at));
  BEGIN
    v_got := pg_temp.probe(v_reset || ARRAY[
        'CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w5 stand-in failure''; END $f$',
        format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
        v_def,
        format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '1 hour')],
      format('SELECT (SELECT r.state || '':'' || r.attempts FROM public.dating_generation_runs AS r WHERE r.partition_key = ''GH'' AND r.cohort_window = %L) || ''|'' || (%s)',
             v_cohort, format(v_list, v_at + interval '1 hour')));
  EXCEPTION WHEN query_canceled OR raise_exception THEN
    v_got := 'the failing tick raised ' || SQLSTATE;
  END;
  IF v_clean = '<NULL>' OR v_got IS DISTINCT FROM 'completed:2|' || v_clean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed run was not run again an hour later with the same introductions: % (expected completed:2|%)', v_got, v_clean;
  END IF;
  FOREACH v_code IN ARRAY ARRAY['P0001', '57014'] LOOP
    BEGIN
      v_got := pg_temp.probe(v_reset || ARRAY[
          format('CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN IF a.country = ''GH'' THEN RAISE EXCEPTION ''w5 stand-in failure'' USING ERRCODE = %L; END IF; RETURN ''{}''::text[]; END $f$', v_code),
          format('SELECT public.run_dating_generation_tick(%L)', v_at)],
        format('SELECT string_agg(r.partition_key || ''='' || r.state || coalesce('':'' || r.last_error_code, ''''), '','' ORDER BY r.partition_key) || ''|'' || (SELECT count(*) FROM public.dating_introductions AS i WHERE i.created_at = %L AND i.partition_key = ''GB'') FROM public.dating_generation_runs AS r WHERE r.cohort_window = %L',
               v_at, v_cohort));
    EXCEPTION WHEN query_canceled OR raise_exception THEN
      v_got := 'the tick raised ' || SQLSTATE || ', so every partition rolled back';
    END;
    IF v_got IS DISTINCT FROM 'GB=completed,GH=failed:' || v_code || '|1' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: GH failing with % after GB completed gave % (expected GB kept: GB=completed,GH=failed:%|1)', v_code, v_got, v_code;
    END IF;
  END LOOP;
  -- Fix round 2 (N-2): every due partition runs within its cohort day.
  -- GB times out at 03:17, so GH (never reached) is left pending, and at
  -- 04:17 both run: GB's second try, GH's first.
  v_runs := 'SELECT current_setting(''w5.mid'') || ''|'' || (SELECT string_agg(r.partition_key || ''='' || r.state || '':'' || r.attempts, '','' ORDER BY r.partition_key) FROM public.dating_generation_runs AS r WHERE r.cohort_window = %L)'
            || ' || ''|'' || (SELECT count(*) > 0 FROM public.dating_introductions AS i WHERE i.created_at = %L AND i.partition_key = ''GH'')';
  v_mid := format('SELECT set_config(''w5.mid'', (SELECT string_agg(r.partition_key || ''='' || r.state || '':'' || r.attempts, '','' ORDER BY r.partition_key) FROM public.dating_generation_runs AS r WHERE r.cohort_window = %L), true)', v_cohort);
  BEGIN
    v_got := pg_temp.probe(v_reset || ARRAY[
        'CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN IF a.country = ''GB'' THEN RAISE EXCEPTION ''w5 stand-in timeout'' USING ERRCODE = ''57014''; END IF; RETURN ''{}''::text[]; END $f$',
        format('SELECT public.run_dating_generation_tick(%L)', v_at),
        v_mid,
        v_def,
        format('SELECT public.run_dating_generation_tick(%L)', v_at + interval '1 hour')],
      format(v_runs, v_cohort, v_at + interval '1 hour'));
  EXCEPTION WHEN query_canceled OR raise_exception THEN
    v_got := 'the tick raised ' || SQLSTATE;
  END;
  IF v_got IS DISTINCT FROM 'GB=failed:1,GH=pending:0|GB=completed:2,GH=completed:1|true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after GB timed out, GH was not left pending and run later that day: % (expected GB=failed:1,GH=pending:0|GB=completed:2,GH=completed:1|true)', v_got;
  END IF;
  -- A claim that itself fails leaves the partition pending; 04:17 runs it.
  BEGIN
    v_got := pg_temp.probe(v_reset || ARRAY[
        'CREATE FUNCTION private.w5_claim_stand_in() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w5 claim stand-in''; END $f$',
        'CREATE TRIGGER w5_claim_stand_in BEFORE INSERT ON public.dating_generation_runs FOR EACH ROW WHEN (NEW.state = ''processing'' AND NEW.partition_key = ''GH'') EXECUTE FUNCTION private.w5_claim_stand_in()',
        format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
        v_mid,
        'DROP TRIGGER w5_claim_stand_in ON public.dating_generation_runs',
        format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '1 hour')],
      format(v_runs, v_cohort, v_at + interval '1 hour'));
  EXCEPTION WHEN query_canceled OR raise_exception THEN
    v_got := 'the tick raised ' || SQLSTATE;
  END;
  IF v_got IS DISTINCT FROM 'GH=pending:0|GH=completed:1|true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed claim did not leave the partition pending for a later hour: % (expected GH=pending:0|GH=completed:1|true)', v_got;
  END IF;
  -- A missed 03:17 (no run at all) is caught up at 05:17, with what 03:17
  -- would have made.
  v_got := pg_temp.probe(v_reset || format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '2 hours'),
    format('SELECT (SELECT r.state || '':'' || r.attempts FROM public.dating_generation_runs AS r WHERE r.partition_key = ''GH'' AND r.cohort_window = %L) || ''|'' || (%s)',
           v_cohort, format(v_list, v_at + interval '2 hours')));
  IF v_got IS DISTINCT FROM 'completed:1|' || v_clean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missed 03:17 was not caught up at 05:17 with the same introductions: % (expected completed:1|%)', v_got, v_clean;
  END IF;
  -- Fix round 2 (N-4): someone who leaves while the run is open (a stand-in
  -- ends m's enrolment the moment his first introduction is made) keeps
  -- none of the run's introductions (the close); the others keep theirs.
  v_got := pg_temp.probe(v_reset || format($s$CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN IF %L::uuid IN (a.user_id, b.user_id) THEN UPDATE public.dating_enrollments SET state = 'exited', exited_at = now() WHERE user_id = %L; END IF; RETURN '{}'::text[]; END $f$ $s$, m, m)
                                  || format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
    format('SELECT (SELECT count(*) FROM public.dating_introductions AS i WHERE i.created_at = %L AND %L IN (i.user_low_id, i.user_high_id)) || '':'' || (SELECT r.state FROM public.dating_generation_runs AS r WHERE r.partition_key = ''GH'' AND r.cohort_window = %L) || '':'' || (SELECT count(*) > 0 FROM public.dating_introductions AS i WHERE i.created_at = %L)',
           v_at, m, v_cohort, v_at));
  IF v_got IS DISTINCT FROM '0:completed:true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person who left while the run was open kept its introductions: % (expected 0:completed:true) (fix round 2, N-4)', v_got;
  END IF;
  -- Per side: an unanswered side's own seven days end the pair; an
  -- answered side waits for the other's.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, expires_at)
  VALUES ('w5life:a', least(t, m), greatest(t, m), 'generated', 'introductions_v2', now() - interval '8 days', now() - interval '1 day', now() + interval '6 days')
  RETURNING id INTO v_id;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, low_action, algorithm_version, visible_from_low, visible_from_high, expires_at)
  VALUES ('w5life:b', least(t, m), greatest(t, m), 'interested', 'interested', 'introductions_v2', now() - interval '8 days', now() - interval '1 day', now() + interval '6 days');
  PERFORM public.expire_dating_introductions();
  IF (SELECT state FROM public.dating_introductions WHERE pair_key = 'w5life:a') <> 'expired'
     OR (SELECT state FROM public.dating_introductions WHERE pair_key = 'w5life:b') <> 'interested' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seven days are not per side (§5.3)';
  END IF;
  -- Fix round 2 (N-1): the hourly sweep takes every introduction of someone
  -- who has left (as leaving does), whatever its state; the rest stay.
  v_got := pg_temp.probe(ARRAY[
      format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version) VALUES (''w5sweep:gone'', least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''generated'', ''introductions_v2''), (''w5sweep:passed'', least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''passed'', ''introductions_v2''), (''w5sweep:kept'', least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''generated'', ''introductions_v2'')',
             pg_temp.id('71'), pg_temp.id('72'), pg_temp.id('71'), pg_temp.id('72'), pg_temp.id('73'), pg_temp.id('72'), pg_temp.id('73'), pg_temp.id('72'),
             pg_temp.id('71'), pg_temp.id('73'), pg_temp.id('71'), pg_temp.id('73')),
      format('UPDATE public.dating_enrollments SET state = ''exited'', exited_at = now() WHERE user_id = %L', pg_temp.id('72')),
      'SELECT public.expire_dating_introductions()'],
    'SELECT string_agg(pair_key, '','' ORDER BY pair_key) FROM public.dating_introductions WHERE pair_key LIKE ''w5sweep:%''');
  IF v_got IS DISTINCT FROM 'w5sweep:kept' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hourly sweep left % (expected w5sweep:kept: a person who left keeps no introduction) (fix round 2, N-1)', v_got;
  END IF;
  -- A run that fails: nothing published, failed, then retried at each
  -- later hour of the cohort (fix round 1, I-1) and dead-lettered after
  -- the third try; the hour after that tries nothing.
  IF pg_temp.probe(ARRAY[
       'CREATE OR REPLACE FUNCTION private.dating_reasons(a private.dating_gen_person, b private.dating_gen_person) RETURNS text[] LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w5 stand-in failure''; END $f$',
       format('DELETE FROM public.dating_generation_runs WHERE partition_key = ''GH'' AND cohort_window = %L', (v_at AT TIME ZONE 'Africa/Accra')::date::text),
       format('DELETE FROM public.dating_introductions WHERE created_at = %L', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '1 hour'),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '2 hours'),
       format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at + interval '3 hours')],
     format('SELECT r.last_error_code || '':'' || r.state || '':'' || r.attempts || '':'' || (SELECT count(*) FROM public.dating_introductions WHERE created_at >= %L) FROM public.dating_generation_runs AS r WHERE r.partition_key = ''GH'' AND r.cohort_window = %L',
            v_at, (v_at AT TIME ZONE 'Africa/Accra')::date::text)) IS DISTINCT FROM 'P0001:dead_letter:3:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing run published, or was not retried at the later hours and dead-lettered after three tries';
  END IF;
  -- Mutant 6: every temp table a Dating function makes is dropped at commit.
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private') AND p.prosrc ~* 'CREATE\s+TEMP'
     AND (SELECT count(*) FROM regexp_matches(p.prosrc, 'CREATE\s+TEMP(ORARY)?\s+TABLE', 'gi'))
         <> (SELECT count(*) FROM regexp_matches(p.prosrc, 'CREATE\s+TEMP(ORARY)?\s+TABLE[^;]*ON\s+COMMIT\s+DROP', 'gi'))
     AND p.prosrc ~ 'dating_';
  IF v_bad IS NOT NULL OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'dating_generate_partition' AND prosrc ~ 'ON COMMIT DROP') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a temp table of decrypted answers can outlive its transaction (mutant 6): %', v_bad;
  END IF;
END $$;

-- =====================================================================
-- G7. (§5.8; fix round 1, M-4) Two marriage seekers share their intention
--     whether or not a timeline is stated.
-- =====================================================================
DO $$
DECLARE
  v_case record;
BEGIN
  FOR v_case IN SELECT * FROM (VALUES
    ('marriage, one timeline unstated', '{"intention": "marriage", "timeline": null, "children_want": "open"}'::jsonb,
       '{"intention": "marriage", "timeline": "few_years", "region": "AH", "children_want": "open"}'::jsonb, ARRAY['same_intention']),
    ('marriage, neither timeline stated', '{"intention": "marriage", "children_want": "open"}',
       '{"intention": "marriage", "region": "AH", "children_want": "open"}', ARRAY['same_intention']),
    ('marriage, the same timeline shown', '{"intention": "marriage", "timeline": "few_years", "children_want": "open"}',
       '{"intention": "marriage", "timeline": "few_years", "region": "AH", "children_want": "open"}', ARRAY['same_intention_timeline']),
    ('marriage, the same timeline, one hidden', '{"intention": "marriage", "timeline": "few_years", "timeline_visible": false, "children_want": "open"}',
       '{"intention": "marriage", "timeline": "few_years", "region": "AH", "children_want": "open"}', ARRAY['same_intention'])
  ) AS t(why, a, b, expected) LOOP
    IF private.dating_reasons(pg_temp.pr(1, v_case.a), pg_temp.man(2, v_case.b)) IS DISTINCT FROM v_case.expected
       OR private.dating_reasons(pg_temp.man(2, v_case.b), pg_temp.pr(1, v_case.a)) IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: reasons fixture "%" gave %/% (expected %) (§5.8; fix round 1, M-4)', v_case.why,
        private.dating_reasons(pg_temp.pr(1, v_case.a), pg_temp.man(2, v_case.b)),
        private.dating_reasons(pg_temp.man(2, v_case.b), pg_temp.pr(1, v_case.a)), v_case.expected;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- G8. (§5.4 1, §5.5; fix round 1, I-2, M-5) Over partition_people_max a
--     country splits by region, and in a region over it who is left out
--     is the seed's last (so it rotates by cohort) and is counted; people
--     with equal exposure choose in the seed's order, not by id; a person
--     open to two countries gets 3 in a tick, not 3 a partition.
-- =====================================================================
DO $$
DECLARE
  v_t0 constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '2 days 3 hours 17 minutes';
  v_on constant text := 'UPDATE public.dating_enrollments SET state = ''active'', pause_reason = NULL WHERE user_id = ANY (%L::uuid[])';
  v_aa uuid[];
  v_women uuid[];
  v_ah uuid[];
  v_far uuid[];
  g uuid;
  v_t timestamptz;
  v_w date;
  v_seed text;
  v_pred text;
  v_preds text[] := '{}';
  v_got text;
  v_m0 bigint;
  v_k integer;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  v_aa := ARRAY[pg_temp.ready('81'), pg_temp.ready('82'), pg_temp.ready('83', '{"identity": "man", "seeking": ["woman"]}'),
                pg_temp.ready('84', '{"identity": "man", "seeking": ["woman"]}')];
  v_ah := ARRAY[pg_temp.ready('85', '{"region": "AH"}'), pg_temp.ready('86', '{"identity": "man", "seeking": ["woman"], "region": "AH"}')];
  v_women := ARRAY[v_aa[1], v_aa[2], pg_temp.ready('87')];
  g := pg_temp.ready('89', '{"identity": "man", "seeking": ["woman"], "country": "GB", "region": "TLI", "abroad": ["GH"]}');
  v_far := ARRAY(SELECT pg_temp.ready(n::text, '{"abroad": ["GB"]}') FROM generate_series(91, 94) AS n ORDER BY n);
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';

  -- I-2: with partition_people_max 3, six in Ghana split into GH:AA (four)
  -- and GH:AH (two); in GH:AA the seed's last of the four is left out (the
  -- one with no introduction: any three of them all meet someone), and
  -- the run is counted.
  v_m0 := pg_temp.metric('dating.generation.truncated.gh');
  FOR v_k IN 0..7 LOOP
    v_t := v_t0 + make_interval(days => v_k);
    v_w := (v_t AT TIME ZONE 'Africa/Accra')::date;
    v_seed := encode(extensions.digest('introductions_v2' || v_w::text || 'GH:AA', 'sha256'), 'hex');
    SELECT right(x::text, 2) INTO v_pred FROM unnest(v_aa) AS x ORDER BY md5(v_seed || x::text) DESC, x DESC LIMIT 1;
    v_got := pg_temp.probe(ARRAY[
        'UPDATE public.dating_algorithm_configs SET state = ''reviewed'' WHERE version = ''introductions_v2''', -- W5 final (M-7): out of active to edit
        'UPDATE public.dating_algorithm_configs SET config = config || ''{"partition_people_max": 3}'' WHERE version = ''introductions_v2''',
        'SELECT pg_temp.activate()',
        format(v_on, v_aa || v_ah),
        format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_t)],
      format($q$SELECT (SELECT string_agg(r.partition_key || '=' || r.state, ',' ORDER BY r.partition_key) FROM public.dating_generation_runs AS r WHERE r.cohort_window = %L)
                || '|' || (SELECT string_agg(right(x::text, 2), ',' ORDER BY x) FROM unnest(%L::uuid[]) AS x
                            WHERE NOT EXISTS (SELECT 1 FROM public.dating_introductions AS i WHERE x IN (i.user_low_id, i.user_high_id) AND i.created_at = %L))
                || '|' || (SELECT string_agg(DISTINCT i.partition_key, ',') FROM public.dating_introductions AS i WHERE i.created_at = %L AND %L IN (i.user_low_id, i.user_high_id))
                || '|' || (pg_temp.metric('dating.generation.truncated.gh') - %s)$q$,
             v_w::text, v_aa, v_t, v_t, v_ah[1], v_m0));
    IF v_got IS DISTINCT FROM 'GH:AA=completed,GH:AH=completed|' || v_pred || '|GH:AH|1' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: over the bound the cohort % gave % (expected GH:AA=completed,GH:AH=completed|%|GH:AH|1: the seed''s last left out, counted) (fix round 1, I-2)', v_w, v_got, v_pred;
    END IF;
    v_preds := v_preds || v_pred;
  END LOOP;
  IF (SELECT count(DISTINCT x) FROM unnest(v_preds) AS x) < 2 THEN
    RAISE EXCEPTION 'fixture: eight cohorts would leave out the same person (%)', v_preds;
  END IF;

  -- M-5: three women with no introductions and one man introduced
  -- yesterday (so he chooses last): the women choose him in the seed's
  -- order, on a cohort where that is not their id order.
  FOR v_k IN 0..7 LOOP
    v_t := v_t0 + make_interval(days => v_k);
    v_seed := encode(extensions.digest('introductions_v2' || ((v_t AT TIME ZONE 'Africa/Accra')::date)::text || 'GH', 'sha256'), 'hex');
    SELECT string_agg(right(x::text, 2), ',' ORDER BY md5(v_seed || x::text), x) INTO v_pred FROM unnest(v_women) AS x;
    EXIT WHEN v_pred <> '81,82,87';
  END LOOP;
  IF v_pred = '81,82,87' THEN
    RAISE EXCEPTION 'fixture: eight cohorts order the women by id';
  END IF;
  v_got := pg_temp.probe(ARRAY[
      format(v_on, v_women || v_aa[3]),
      format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at) VALUES (public.dating_pair_key(%L, %L), least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''passed'', ''introductions_v2'', %L::timestamptz - interval ''1 day'')',
             v_aa[3], pg_temp.id('11'), v_aa[3], pg_temp.id('11'), v_aa[3], pg_temp.id('11'), v_t),
      format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_t)],
    format('SELECT string_agg(right((CASE WHEN i.user_low_id = %L THEN i.user_high_id ELSE i.user_low_id END)::text, 2), '','' ORDER BY (i.rank_detail ->> ''seq'')::int) FROM public.dating_introductions AS i WHERE i.created_at = %L',
           v_aa[3], v_t));
  IF v_got IS DISTINCT FROM v_pred THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: people with equal exposure chose in the order % (expected the seed''s, %) (§5.4 1; fix round 1, M-5)', v_got, v_pred;
  END IF;

  -- M-5: a London man open to Ghana and four Ghana women open to the UK;
  -- one tick runs GB, then GH: he gets 3 in GB's run and none in Ghana's.
  v_got := pg_temp.probe(ARRAY[format(v_on, g || v_far), format('SELECT public.run_dating_generation_tick(%L)', v_t0)],
    format('SELECT (SELECT count(*) FROM public.dating_introductions AS i WHERE i.created_at = %L AND %L IN (i.user_low_id, i.user_high_id)) || '':'' || (SELECT count(*) FROM public.dating_introductions AS i WHERE i.created_at = %L AND %L IN (i.user_low_id, i.user_high_id) AND i.partition_key = ''GH'')',
           v_t0, g, v_t0, g));
  IF v_got IS DISTINCT FROM '3:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person open to two countries got % introductions in one tick, in GH''s run after the colon (expected 3:0, §5.3)', v_got;
  END IF;
END $$;

-- =====================================================================
-- H. (§4.4 health v2) Today's generation per country and the active
--    config, for an operator.
-- I. (§4.6) The hourly cron.
-- =====================================================================
DO $$
DECLARE
  v jsonb := public.get_dating_operational_health();
BEGIN
  IF v #>> '{generation_by_country,GH,state}' IS DISTINCT FROM 'completed' OR v ->> 'introductions_config' IS DISTINCT FROM 'introductions_v2'
     OR NOT (v -> 'safety_counters_7d') ? 'dating.generation.skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show today''s generation: %', v -> 'generation_by_country';
  END IF;
  -- Fix round 2 (N-3): busy pairs, and people left out over the bound per
  -- country (counted through the registry, as the run counts them).
  PERFORM private.bump_metric_internal('dating.generation.truncated.gh');
  v := public.get_dating_operational_health();
  IF NOT (v -> 'safety_counters_7d') ? 'dating.generation.busy' OR (v #>> '{generation_truncated_7d,gh}')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show busy pairs or people left out over the bound: %, % (fix round 2, N-3)',
      v -> 'safety_counters_7d' -> 'dating.generation.busy', v -> 'generation_truncated_7d';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-candidate-generation' AND schedule = '17 * * * *'
                  AND command = 'SELECT public.run_dating_generation_tick()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hourly generation cron is not scheduled';
  END IF;
END $$;

-- Task 4 ruling: the fixture people are 26-39 (the plan's 81-94 are
-- taken by section G since Task 2's fix rounds).
-- =====================================================================
-- L. (§3.4, §5.8; mutants 18, 19) The card: exactly the allowed keys; who
--    the person would like to meet, their pools, faith importance and any
--    field they hide never; no storage path; captions as photo labels; no
--    photo while the person keeps them for mutual interest. Reasons: faith
--    only when both show it, the timeline only when both show it, at most
--    three in order, across borders when nothing else.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('26', '{"faith": "christian", "importance": "must_share", "faith_visible": false, "family": "early"}');
  m constant uuid := pg_temp.ready('27', '{"identity": "man", "seeking": ["woman"], "faith": "christian", "importance": "must_share", "faith_visible": true}');
  v_id uuid;
  v jsonb;
  v_card jsonb;
  v_bad text;
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
BEGIN
  -- Fix round 1 (M-7): the card lists photos only with the photo flag on.
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_profile_photos', true) ON CONFLICT (key) DO UPDATE SET enabled = true;
  UPDATE public.dating_profile_photos SET caption = 'Me at the beach' WHERE user_id = m AND position = 1;
  -- Fix round 1 (I-2): a caption with contact details (the content filter's).
  UPDATE public.dating_profile_photos SET caption = 'WhatsApp me 0244 123 456' WHERE user_id = m AND position = 2;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  VALUES (m, 'w5/review.jpg', 3, 'needs_review', 'clear');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour',
          ARRAY['same_intention', 'children_want_yes', 'same_region'])
  RETURNING id INTO v_id;
  v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad FROM jsonb_object_keys(v_card) AS k
   WHERE k NOT IN ('id', 'display_name', 'age', 'region_name_key', 'side_name_key', 'intention', 'marriage_timeline', 'children_have',
                   'children_want', 'gender', 'pronouns', 'faith', 'marital', 'prompts', 'reasons', 'photos_after_mutual', 'photos', 'acted');
  IF v_bad IS NOT NULL OR v_card::text ~* ('(seeking|pools|importance|must_share|storage|w5/|pair_key|user_id|' || w::text || '|' || m::text || ')') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card carries % or a hidden value (mutant 18): %', v_bad, v_card;
  END IF;
  IF v_card #>> '{faith,faith}' IS DISTINCT FROM 'christian' OR v_card -> 'gender' IS DISTINCT FROM 'null'::jsonb
     OR jsonb_array_length(v_card -> 'photos') <> 2 OR v_card #>> '{photos,0,caption}' IS DISTINCT FROM 'Me at the beach'
     OR v_card -> 'reasons' IS DISTINCT FROM '["same_intention", "children_want_yes", "same_region"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card does not show what the person chose (faith shown, gender hidden, the two viewable photos, a caption): %', v_card;
  END IF;
  -- Fix round 1 (I-2): a flagged caption never reaches a card (left off,
  -- the photo kept); the owner still sees their own caption unchanged.
  -- (fix round 3: the captions only; a random photo id can contain "0244")
  IF v_card #> '{photos,1,caption}' IS DISTINCT FROM 'null'::jsonb
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_card -> 'photos') AS f WHERE f ->> 'caption' ~* '(whatsapp|0244)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a caption with contact details reached a stranger''s card: %', v_card -> 'photos';
  END IF;
  IF pg_temp.call(m, pg_temp.dev('27'), 'SELECT public.list_dating_profile_photos()')::jsonb #>> '{photos,1,caption}'
       IS DISTINCT FROM 'WhatsApp me 0244 123 456' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner no longer sees their own caption';
  END IF;
  UPDATE public.dating_profile_photos SET caption = 'mail me at ama dot boateng at gmail dot com' WHERE user_id = m AND position = 2;
  v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card #>> '{photos,1,caption}' IS DISTINCT FROM 'mail me at •••' OR v_card::text ~* 'gmail' -- Spec 2 W6a (carry 3): masked, shown
     OR v_card #>> '{photos,0,caption}' IS DISTINCT FROM 'Me at the beach' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an email in words reached a stranger''s card, or a plain caption did not: %', v_card -> 'photos';
  END IF;
  -- Fix round 2: an unkind caption (the content filter's own family; a
  -- placeholder term, as the setup contract's) never reaches a card either.
  INSERT INTO private.content_filter_terms (family, term, match_mode, locale, source, review_ref)
  VALUES ('slur', private.match_form('zzwfivecunkind'), 'token', 'en', 'reviewed', 'contract fixture');
  UPDATE public.dating_profile_photos SET caption = 'Hello zzwfivecunkind' WHERE user_id = m AND position = 2;
  v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card #> '{photos,1,caption}' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unkind caption reached a stranger''s card: %', v_card -> 'photos';
  END IF;
  -- Fix round 2 (I-3): platform words and handles the content filter lets
  -- through never reach a card; dates, times, prices and years still do.
  FOREACH v_bad IN ARRAY ARRAY['my snapchat is amab', 'telegram amab', 'ama boateng at gmail', 'find me on facebook Ama Boateng',
                               '0244 1o3 456', 'zero two four four one two three four', 'wa: amab', 'ama dot com',
                               '0x' || repeat('a1', 20),
                               -- fix round 3 (M-9): the re-review's evasions
                               '024 4l2 3456', '024 4I2 3456', 'my sc is amab', 'my handle is ama_b_99', 's n a p c h a t amab',
                               'tele gram amab', 'whats app me', 'watsapp me', 'wassap me', 'hit me up amab', 'slide into my dms',
                               'cash app $amab', '$amab', 'venmo amab', 'onlyfans amab', 'OF link in bio',
                               -- and the forms caught since round 2 stay caught
                               'sn@p amab', 'amab @ outlook', 'amab(at)gmail(dot)com', 'amab at kofimail dot xyz', 'tiktok.com/@ama',
                               -- fix round 4 (I-5): Ghana's common apps and mobile money
                               'imo 0244', 'botim amab', 'viber amab', 'wechat amab', 'we chat amab', 'discord amab', 'line id amab', 'line: amab',
                               'kik amab', 'youtube amab', 'amab on yt', 'linkedin amab', 'reddit u/amab', 'u/amab', 'momo amab', 'the gram: amab',
                               -- fix round 4 (M-12): the filter's fold, split letters, leetspeak, any separator
                               '0244_123_456', 's.n.a.p amab', 's-n-a-p-c-h-a-t amab', 'sn4pchat', '5nap', 'ⓢⓝⓐⓟ amab', 'Snäpchat amab',
                               'amab at kofimail . xyz', 'amab at kofi site dot xyz', 'amab AT kofimail DOT xyz', 'amab at kofimail dot co dot uk',
                               'amab @gmail', 'amab@ gmail', '1nst4gram amab', 'wh4ts4pp me', 'v1ber amab', 't3l3gram amab', 'd1scord amab'] LOOP
    UPDATE public.dating_profile_photos SET caption = v_bad WHERE user_id = m AND position = 2;
    v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
    IF v_card #> '{photos,1,caption}' IS DISTINCT FROM (CASE WHEN private.dating_caption_invites(v_bad) THEN 'null'::jsonb -- Spec 2 W6a (carry 3)
                                                               ELSE to_jsonb(private.dating_mask_contacts(v_bad)) END) -- Spec 2 W6a: masked
       OR v_card #>> '{photos,1,caption}' IS NOT DISTINCT FROM v_bad -- Spec 2 W6a: never raw
       OR jsonb_array_length(v_card -> 'photos') <> 2 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the caption "%" (contact details) reached a stranger''s card unmasked, or its photo was dropped (I-3): %', v_bad, v_card -> 'photos';
    END IF;
  END LOOP;
  FOREACH v_bad IN ARRAY ARRAY['12/06/2026 at the lake', 'Sunday at 7:30pm', 'GH₵200 well spent', 'Accra, 2019', 'Wa, with my aunt',
                               -- fix round 3 (M-10): an @ with a space, and "at ... dot" far apart, show
                               'Sunset @ Labadi', 'Me @ the beach', 'Kumasi at dusk, dot of light', 'Look at that dot on the horizon',
                               'Graduation, 15.06.2019', '£1,250 trip', 'Room 1204, hotel', 'Ghana vs Nigeria 2-1', 'Me at 25',
                               -- fix round 4: plain words beside the new rules still show
                               'in line for jollof', 'Line dancing at the party', 'A long line at the market', 'Imogen and me',
                               'Kikelomo''s wedding', 'Gramma''s birthday', 'I am a nurse', 'A day at a park', 'Team photo, 2 0 2 4',
                               'Price: $20', 'Born 1994 in Ho', 'Me at Kofi''s dot party', 'Me at home. Great day', 'Lunch at noon. Fun times',
                               'Grade 5 class photo', 'Top 3 moments', 'Bus 4 Accra', 'Love it 100%', 'Ghana won 3-0', '2026-06-12, Labadi',
                               'Café at Labadi'] LOOP
    UPDATE public.dating_profile_photos SET caption = v_bad WHERE user_id = m AND position = 2;
    v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
    IF v_card #>> '{photos,1,caption}' IS DISTINCT FROM v_bad THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the plain caption "%" was left off the card (I-3): %', v_bad, v_card -> 'photos';
    END IF;
  END LOOP;
  -- Fix round 1 (M-7): with the photo flag off the card lists no photo.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_profile_photos';
  v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_profile_photos';
  IF v_card -> 'photos' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card lists photos with the photo flag off (M-7): %', v_card -> 'photos';
  END IF;
  -- m sees w's card: w hides faith.
  v_card := pg_temp.call(m, pg_temp.dev('27'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card -> 'faith' IS DISTINCT FROM 'null'::jsonb OR v_card::text ~* 'christian' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hidden faith reached the other person: %', v_card;
  END IF;
  -- A card from two days ago waits (no date on it); the day is empty.
  UPDATE public.dating_introductions SET visible_from_low = now() - interval '2 days', visible_from_high = now() - interval '2 days' WHERE id = v_id;
  v := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF v ->> 'today_state' IS DISTINCT FROM 'empty' OR jsonb_array_length(v -> 'cards') <> 0 OR jsonb_array_length(v -> 'waiting') <> 1
     OR v::text ~ 'visible_from|expires|created' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older card is not "still waiting", or a date was sent: %', v;
  END IF;
  UPDATE public.dating_profiles SET photos_after_mutual = true WHERE user_id = m;
  v_card := pg_temp.call(w, pg_temp.dev('26'), 'SELECT public.get_my_dating_introductions()')::jsonb #> '{cards,0}';
  IF v_card -> 'photos' IS DISTINCT FROM '[]'::jsonb OR v_card -> 'photos_after_mutual' IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos kept for mutual interest were listed: %', v_card;
  END IF;
  -- Mutant 19: faith reasons only when both show it.
  IF 'same_faith' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "faith_visible": false}'), pg_temp.man(2, '{"faith": "christian", "faith_visible": true}')))
     OR 'faith_matters' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "importance": "must_share", "faith_visible": false}'),
                                                      pg_temp.man(2, '{"faith": "christian", "importance": "must_share", "faith_visible": true}')))
     OR NOT 'same_faith' = ANY (private.dating_reasons(pg_temp.pr(1, '{"faith": "christian", "faith_visible": true, "children_want": "open"}'),
                                                       pg_temp.man(2, '{"faith": "christian", "faith_visible": true, "children_want": "open"}'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a faith reason was cited while one side hides faith, or not when both show it (mutant 19)';
  END IF;
  IF private.dating_reasons(pg_temp.pr(1, '{"intention": "marriage", "timeline": "few_years", "timeline_visible": false}'),
                            pg_temp.man(2, '{"intention": "marriage", "timeline": "few_years"}')) <> ARRAY['same_intention', 'children_want_yes', 'same_region']
     OR private.dating_reasons(pg_temp.pr(1, '{"intention": "marriage", "timeline": "few_years", "children_have": true, "family": "early"}'),
                               pg_temp.man(2, '{"intention": "marriage", "timeline": "few_years", "children_have": true, "family": "early"}'))
        <> ARRAY['same_intention_timeline', 'children_want_yes', 'children_have_both']
     OR private.dating_reasons(pg_temp.pr(1, '{"intention": "companionship", "children_want": "open"}'),
                               pg_temp.man(2, '{"intention": "not_sure", "children_want": "no", "country": "GB", "region": "TLI"}')) <> ARRAY['across_borders'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reasons are not the first three that apply in §5.8''s order';
  END IF;
END $$;

-- =====================================================================
-- M. (Fable C1, §4.1, H2) Four accounts on the new reads: an outsider's
--    act, mark and photo keys on someone else's introduction or match
--    answer exactly as for one that doesn't exist; a blocked pair is
--    neither read nor answered.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('28');
  b constant uuid := pg_temp.ready('29', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('30', '{"identity": "man", "seeking": ["woman"]}');
  v_ab uuid;
  v_m uuid;
  v_cards jsonb;
  v_answer text;
  v_absent text;
  v_mark text;
  v_mark_absent text;
  v_fake constant uuid := '5e5e0000-0000-4000-8000-0000000000ff';
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(a, b), least(a, b), greatest(a, b), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_ab;
  INSERT INTO public.dating_matches (user_low_id, user_high_id, state) VALUES (least(a, b), greatest(a, b), 'active') RETURNING id INTO v_m;
  -- Each call its own statement: an IF's operands have no order.
  v_answer := pg_temp.call(c, pg_temp.dev('30'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('c-forged'), v_ab));
  v_absent := pg_temp.call(c, pg_temp.dev('30'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('c-absent'), v_fake));
  v_mark := pg_temp.call(c, pg_temp.dev('30'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_m));
  v_mark_absent := pg_temp.call(c, pg_temp.dev('30'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_fake));
  IF v_answer IS DISTINCT FROM v_absent OR v_mark IS DISTINCT FROM v_mark_absent
     OR public.dating_photo_keys_for_viewer(c, 'introduction', v_ab, encode(extensions.digest(pg_temp.dev('30'), 'sha256'), 'hex'))
       IS DISTINCT FROM public.dating_photo_keys_for_viewer(c, 'introduction', v_fake, encode(extensions.digest(pg_temp.dev('30'), 'sha256'), 'hex'))
     OR public.dating_photo_keys_for_viewer(c, 'match', v_m, encode(extensions.digest(pg_temp.dev('30'), 'sha256'), 'hex'))
       IS DISTINCT FROM public.dating_photo_keys_for_viewer(c, 'match', v_fake, encode(extensions.digest(pg_temp.dev('30'), 'sha256'), 'hex'))
     OR (SELECT low_moment_seen_at IS NOT NULL OR high_moment_seen_at IS NOT NULL FROM public.dating_matches WHERE id = v_m)
     OR EXISTS (SELECT 1 FROM public.dating_interest_actions WHERE actor_user_id = c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider can tell someone else''s introduction or match from none, or changed it (Fable C1)';
  END IF;
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key) VALUES (b, a, public.dating_pair_key(a, b));
  -- Each call its own statement: an IF's operands have no order.
  v_cards := pg_temp.call(a, pg_temp.dev('28'), 'SELECT public.get_my_dating_introductions()')::jsonb;
  v_answer := pg_temp.call(a, pg_temp.dev('28'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('a-blocked'), v_ab));
  IF jsonb_array_length(v_cards -> 'cards') <> 0 OR v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_ab) <> 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked pair was read or answered';
  END IF;
END $$;

-- =====================================================================
-- N. (§3.4, §3.5, §5.6) The match moment, once per side; the family
--    question once, after the first introduction, and answering it ends
--    nothing; the quiet note after 14 days without one, once.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('33');
  m constant uuid := pg_temp.ready('34', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('35');
  v_id uuid;
  v_match uuid;
  v jsonb;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_id;
  v := pg_temp.call(w, pg_temp.dev('33'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'family_question')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question is not asked after the first introduction: %', v;
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('33'), format('SELECT public.save_dating_family_involvement(%L, ''early'')', md5('fam-w')));
  v := pg_temp.call(w, pg_temp.dev('33'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'family_question')::boolean OR (SELECT state FROM public.dating_introductions WHERE id = v_id) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: answering the family question asked it again or ended the introduction (%)', (SELECT state FROM public.dating_introductions WHERE id = v_id);
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('33'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('n-w'), v_id));
  PERFORM pg_temp.call(m, pg_temp.dev('34'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('n-m'), v_id));
  SELECT id INTO v_match FROM public.dating_matches WHERE introduction_id = v_id;
  IF pg_temp.call(w, pg_temp.dev('33'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments'
       IS DISTINCT FROM jsonb_build_array(jsonb_build_object('match_id', v_match, 'display_name', 'Match 34')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match moment is not offered';
  END IF;
  PERFORM pg_temp.call(w, pg_temp.dev('33'), format('SELECT public.mark_dating_match_moment_seen(%L)', v_match));
  IF jsonb_array_length(pg_temp.call(w, pg_temp.dev('33'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments') <> 0
     OR jsonb_array_length(pg_temp.call(m, pg_temp.dev('34'), 'SELECT public.get_my_dating_today()')::jsonb -> 'moments') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the moment is not once per side';
  END IF;
  UPDATE public.dating_enrollments SET activated_at = now() - interval '20 days' WHERE user_id = q;
  v := pg_temp.call(q, pg_temp.dev('35'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'quiet_note')::boolean IS NOT TRUE
     OR pg_temp.call(q, pg_temp.dev('35'), 'SELECT public.dismiss_dating_today_note(''quiet'')') IS DISTINCT FROM '{"ok": true}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the quiet note is not shown after 14 quiet days: %', v;
  END IF;
  v := pg_temp.call(q, pg_temp.dev('35'), 'SELECT public.get_my_dating_today()')::jsonb;
  IF (v ->> 'quiet_note')::boolean
     OR pg_temp.call(q, pg_temp.dev('35'), 'SELECT public.dismiss_dating_today_note(''loud'')') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the quiet note is shown again, or an unknown note was taken';
  END IF;
END $$;

-- =====================================================================
-- N2. (§5.2; Task 4 ruling) Only a filter input ends the open
--     introductions: a name or marital status change does not; a change to
--     who the person is (their pools), who they'd like to meet or their
--     faith, kept in the sensitive row, does (each re-opened in between).
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('46');
  m constant uuid := pg_temp.ready('47', '{"identity": "man", "seeking": ["woman"]}');
  v_id uuid;
  v_col text;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_id;
  UPDATE public.dating_profiles SET display_name = 'Match 46 again' WHERE user_id = w;
  UPDATE public.dating_profile_sensitive SET marital_enc = private.dating_field_encrypt('{"marital": "divorced"}') WHERE user_id = w;
  IF (SELECT state FROM public.dating_introductions WHERE id = v_id) <> 'generated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name or marital status change ended the open introductions';
  END IF;
  FOREACH v_col IN ARRAY ARRAY['identity_enc', 'seeking_enc', 'faith_enc'] LOOP
    UPDATE public.dating_introductions SET state = 'generated' WHERE id = v_id;
    EXECUTE format('UPDATE public.dating_profile_sensitive SET %I = private.dating_field_encrypt(%L) WHERE user_id = %L', v_col,
      CASE v_col WHEN 'identity_enc' THEN '{"identity": "woman", "pools": ["woman", "non_binary"]}'
                 WHEN 'seeking_enc' THEN '{"seeking": ["man", "woman"]}'
                 ELSE '{"faith": "muslim", "denomination": null, "importance": "must_share"}' END, w);
    IF (SELECT state FROM public.dating_introductions WHERE id = v_id) <> 'invalidated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a change to % (a filter input) did not end the open introductions (Task 4 ruling)', v_col;
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- N3. (§5.8; fix round 2, I-4) The timeline and family feed card reasons
--     only, so changing them ends nothing: the card re-checks those
--     reasons against both people's answers now. Hiding the timeline
--     keeps the introduction, takes the timeline reason and the timeline
--     off the card; changing a family answer keeps every introduction,
--     pending interest on both sides included, and drops a stale
--     family_same_*; with no reason left, §5.8's fallback. A hard-filter
--     column, or whether faith shows, still ends them.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('48', '{"intention": "marriage", "timeline": "few_years", "family": "early"}');
  m constant uuid := pg_temp.ready('49', '{"identity": "man", "seeking": ["woman"], "intention": "marriage", "timeline": "few_years", "family": "early"}');
  k constant uuid := pg_temp.ready('17', '{"identity": "man", "seeking": ["woman"], "family": "early"}');
  v_wm uuid;
  v_wk uuid;
  v text;
  v_card jsonb;
  v_step text;
BEGIN
  -- m said Interested to w; w said Interested to k.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high,
                                           reasons, low_action, high_action)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'interested', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour',
          ARRAY['same_intention_timeline', 'children_want_yes', 'family_same_early'],
          CASE WHEN least(w, m) = m THEN 'interested' END, CASE WHEN greatest(w, m) = m THEN 'interested' END)
  RETURNING id INTO v_wm;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high,
                                           reasons, low_action, high_action)
  VALUES (public.dating_pair_key(w, k), least(w, k), greatest(w, k), 'interested', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour',
          ARRAY['family_same_early'],
          CASE WHEN least(w, k) = w THEN 'interested' END, CASE WHEN greatest(w, k) = w THEN 'interested' END)
  RETURNING id INTO v_wk;
  v_card := pg_temp.call(w, pg_temp.dev('48'), 'SELECT public.get_my_dating_introductions()')::jsonb;
  IF (SELECT c -> 'reasons' FROM jsonb_array_elements(v_card -> 'cards') AS c WHERE c ->> 'id' = v_wm::text)
       IS DISTINCT FROM '["same_intention_timeline", "children_want_yes", "family_same_early"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the card does not keep reasons that still hold: %', v_card;
  END IF;
  -- m hides the timeline through the app's save (the I-1 case).
  v := pg_temp.call(m, pg_temp.dev('49'), format('SELECT public.save_dating_intention(%L, ''marriage'', ''few_years'', false, true, NULL, false)', md5('n3-hide')));
  SELECT c INTO v_card FROM jsonb_array_elements(pg_temp.call(w, pg_temp.dev('48'), 'SELECT public.get_my_dating_introductions()')::jsonb -> 'cards') AS c
   WHERE c ->> 'id' = v_wm::text;
  IF v::jsonb ->> 'ok' IS DISTINCT FROM 'true' OR (SELECT state FROM public.dating_introductions WHERE id = v_wm) <> 'interested'
     OR v_card -> 'reasons' IS DISTINCT FROM '["same_intention", "children_want_yes", "family_same_early"]'::jsonb
     OR v_card -> 'marriage_timeline' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: hiding the timeline (%) ended the introduction (%) or left the timeline on the card: % (I-4)', v,
      (SELECT state FROM public.dating_introductions WHERE id = v_wm), v_card;
  END IF;
  -- w changes the family answer through the app's save.
  v := pg_temp.call(w, pg_temp.dev('48'), format('SELECT public.save_dating_family_involvement(%L, ''when_serious'')', md5('n3-family')));
  IF v::jsonb ->> 'ok' IS DISTINCT FROM 'true'
     OR (SELECT string_agg(state || '/' || coalesce(low_action, '-') || '/' || coalesce(high_action, '-'), ' ' ORDER BY id = v_wk)
           FROM public.dating_introductions WHERE id IN (v_wm, v_wk))
        IS DISTINCT FROM (SELECT string_agg(x, ' ') FROM unnest(ARRAY[
          'interested/' || CASE WHEN least(w, m) = m THEN 'interested/-' ELSE '-/interested' END,
          'interested/' || CASE WHEN least(w, k) = w THEN 'interested/-' ELSE '-/interested' END]) AS x) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: changing the family answer (%) ended an introduction or lost pending interest (I-4)', v;
  END IF;
  SELECT c INTO v_card FROM jsonb_array_elements(pg_temp.call(m, pg_temp.dev('49'), 'SELECT public.get_my_dating_introductions()')::jsonb -> 'cards') AS c
   WHERE c ->> 'id' = v_wm::text;
  IF v_card -> 'reasons' IS DISTINCT FROM '["same_intention", "children_want_yes"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale family reason stayed on the card: % (I-4)', v_card -> 'reasons';
  END IF;
  SELECT c INTO v_card FROM jsonb_array_elements(pg_temp.call(k, pg_temp.dev('17'), 'SELECT public.get_my_dating_introductions()')::jsonb -> 'cards') AS c
   WHERE c ->> 'id' = v_wk::text;
  IF v_card -> 'reasons' IS DISTINCT FROM '["same_region"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with its only reason stale the card did not fall back to §5.8''s: % (I-4)', v_card -> 'reasons';
  END IF;
  -- A hard-filter column, or whether faith shows, still ends them: every
  -- one of the trigger's ten columns (fix round 3, M-11), each its own step.
  FOREACH v_step IN ARRAY ARRAY[
      'UPDATE public.dating_profiles SET country_code = ''GB'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET region_code = ''AH'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET side_code = ''w5-side'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET intention = ''committed'', marriage_timeline = NULL WHERE user_id = %L',
      'UPDATE public.dating_profiles SET children_have = true WHERE user_id = %L',
      'UPDATE public.dating_profiles SET children_want = ''open'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET faith_visible = true WHERE user_id = %L',
      'UPDATE public.dating_profiles SET profile_state = ''paused'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET moderation_state = ''pending'' WHERE user_id = %L',
      'UPDATE public.dating_profiles SET verification_state = ''pending'' WHERE user_id = %L'] LOOP
    UPDATE public.dating_introductions SET state = 'generated', low_action = NULL, high_action = NULL WHERE id = v_wm;
    EXECUTE format(v_step, w);
    IF (SELECT state FROM public.dating_introductions WHERE id = v_wm) <> 'invalidated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a filter input change did not end the open introduction: %', format(v_step, w);
    END IF;
  END LOOP;
END $$;

-- =====================================================================
-- N3b. (§5.8; Spec 2 W5b Task 6 fix round 1, M-4) A faith reason never
--      describes an answer someone has hidden: the card re-checks
--      same_faith and faith_matters live and drops both while either
--      person hides faith, from either side's view; with no reason left,
--      §5.8's fallback, as for the other reasons.
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('97', '{"faith": "christian", "importance": "must_share", "faith_visible": true}');
  b constant uuid := pg_temp.ready('98', '{"identity": "man", "seeking": ["woman"], "faith": "christian", "importance": "must_share", "faith_visible": true}');
  v_i public.dating_introductions;
  v_j public.dating_introductions;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(a, b), least(a, b), greatest(a, b), 'presented', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour',
          ARRAY['same_faith', 'faith_matters', 'children_want_yes'])
  RETURNING * INTO v_i;
  v_j := v_i;
  v_j.reasons := ARRAY['same_faith', 'faith_matters'];
  IF private.dating_card(a, b, v_i) -> 'reasons' IS DISTINCT FROM '["same_faith", "faith_matters", "children_want_yes"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: faith reasons both people show left the card: % (M-4)', private.dating_card(a, b, v_i) -> 'reasons';
  END IF;
  UPDATE public.dating_profiles SET faith_visible = false WHERE user_id = b;
  IF private.dating_card(a, b, v_i) -> 'reasons' IS DISTINCT FROM '["children_want_yes"]'::jsonb
     OR private.dating_card(b, a, v_i) -> 'reasons' IS DISTINCT FROM '["children_want_yes"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a faith reason stayed on the card after faith was hidden: % / % (M-4)',
      private.dating_card(a, b, v_i) -> 'reasons', private.dating_card(b, a, v_i) -> 'reasons';
  END IF;
  IF private.dating_card(a, b, v_j) -> 'reasons' IS DISTINCT FROM '["same_region"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with only hidden-faith reasons the card did not fall back to §5.8''s: % (M-4)', private.dating_card(a, b, v_j) -> 'reasons';
  END IF;
END $$;

-- =====================================================================
-- N4. (§3.4 honest day states; fix round 1, M-3 to M-6) "before_drop"
--     only for an introduction that can still arrive; "queue_full" counts
--     only cards not yet answered; a paused person gets the paused state
--     from Today and the read, never cards; act's lock waits are bounded.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('13');
  m constant uuid := pg_temp.ready('14', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('52');
  p constant uuid := pg_temp.ready('15');
  o constant uuid := pg_temp.ready('16', '{"identity": "man", "seeking": ["woman"]}');
  v_max constant int := coalesce(((private.dating_intro_config()).o_config ->> 'waiting_max')::int, 6);
  v_ids constant text[] := ARRAY['53', '54', '55', '56', '57', '58', '95', '96'];
  v_c uuid;
  v_id uuid;
  v_today constant text := 'SELECT pg_temp.call(%L, %L, ''SELECT public.get_my_dating_today()'')::jsonb ->> ''today_state''';
  n int;
BEGIN
  -- M-3: w's drop is to come.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() + interval '1 hour', now() + interval '1 hour')
  RETURNING id INTO v_id;
  IF pg_temp.probe(ARRAY[]::text[], format(v_today, w, pg_temp.dev('13'))) IS DISTINCT FROM 'before_drop'
     OR pg_temp.probe(ARRAY[format('INSERT INTO public.dating_never_introduce (owner_user_id, phone_hmac, last_two, kept_at) VALUES (%L, public.dating_phone_hmac_for_user(%L), ''13'', now())', m, w)],
                      format(v_today, w, pg_temp.dev('13'))) IS DISTINCT FROM 'empty'
     OR pg_temp.probe(ARRAY[format('UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'', paused_at = now() WHERE user_id = %L', m)],
                      format(v_today, w, pg_temp.dev('13'))) IS DISTINCT FROM 'empty' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the day promised an introduction that can no longer arrive (M-3)';
  END IF;
  -- M-4: q has as many older cards as the queue holds, all answered.
  IF v_max > cardinality(v_ids) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture holds % counterparts, the config waits %', cardinality(v_ids), v_max;
  END IF;
  FOR n IN 1..v_max LOOP
    v_c := pg_temp.ready(v_ids[n], '{"identity": "man", "seeking": ["woman"]}');
    INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high,
                                             low_action, high_action)
    VALUES (public.dating_pair_key(q, v_c), least(q, v_c), greatest(q, v_c), 'interested', 'introductions_v2',
            now() - interval '2 days', now() - interval '2 days',
            CASE WHEN least(q, v_c) = q THEN 'interested' END, CASE WHEN greatest(q, v_c) = q THEN 'interested' END);
  END LOOP;
  IF pg_temp.probe(ARRAY[]::text[], format(v_today, q, pg_temp.dev('52'))) IS DISTINCT FROM 'empty'
     OR pg_temp.probe(ARRAY[format('UPDATE public.dating_introductions SET state = ''generated'', low_action = NULL, high_action = NULL WHERE %L IN (user_low_id, user_high_id)', q)],
                      format(v_today, q, pg_temp.dev('52'))) IS DISTINCT FROM 'queue_full' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: queue_full counts answered cards, or not unanswered ones (M-4)';
  END IF;
  -- M-5: a paused person reads the paused state, never cards.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(p, o), least(p, o), greatest(p, o), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour');
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user', paused_at = now() WHERE user_id = p;
  IF pg_temp.call(p, pg_temp.dev('15'), 'SELECT public.get_my_dating_today()') IS DISTINCT FROM '{"ok": false, "reason": "paused"}'
     OR pg_temp.call(p, pg_temp.dev('15'), 'SELECT public.get_my_dating_introductions()') IS DISTINCT FROM '{"ok": false, "reason": "paused"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person read % / % (M-5)', pg_temp.call(p, pg_temp.dev('15'), 'SELECT public.get_my_dating_today()'),
      pg_temp.call(p, pg_temp.dev('15'), 'SELECT public.get_my_dating_introductions()');
  END IF;
  -- M-6: act gives up a lock wait in 2 s (its retry then answers busy).
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid = 'public.act_on_dating_introduction(text,uuid,text)'::regprocedure
                    AND 'lock_timeout=2s' = ANY (proconfig)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: act waits on a lock without a bound (M-6)';
  END IF;
END $$;

-- =====================================================================
-- O. (§4.4, §4.7; carries 12-14) Photo keys for dating-photo-urls: the
--    viewer's phone first; only viewable photos (approved and cleared:
--    never pending, a hit or rejected); never while the other person keeps
--    photos for mutual interest, but theirs once matched; never without
--    the photo flag.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('36');
  m constant uuid := pg_temp.ready('37', '{"identity": "man", "seeking": ["woman"]}');
  v_hash constant text := encode(extensions.digest(pg_temp.dev('36'), 'sha256'), 'hex');
  v_id uuid;
  v_match uuid;
  v jsonb;
BEGIN
  INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_profile_photos', true) ON CONFLICT (key) DO UPDATE SET enabled = true;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
  VALUES (m, 'w5/hit.jpg', 3, 'rejected', 'hit'), (m, 'w5/pending.jpg', 4, 'pending', 'clear'), (m, 'w5/error.jpg', 5, 'needs_review', 'error');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'generated', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour')
  RETURNING id INTO v_id;
  v := public.dating_photo_keys_for_viewer(w, 'introduction', v_id, v_hash);
  IF v IS DISTINCT FROM jsonb_build_object('ok', true, 'photos', jsonb_build_array(
         jsonb_build_object('position', 1, 'key', 'w5/' || m || '/1.jpg'), jsonb_build_object('position', 2, 'key', 'w5/' || m || '/2.jpg'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo keys are not exactly the viewable photos: %', v;
  END IF;
  IF public.dating_photo_keys_for_viewer(w, 'introduction', v_id, encode(extensions.digest(pg_temp.dev('99'), 'sha256'), 'hex'))
       IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}'
     OR public.dating_photo_keys_for_viewer(w, 'introduction', v_id, NULL) IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo keys were given to another phone (carry 12)';
  END IF;
  UPDATE public.dating_profiles SET photos_after_mutual = true WHERE user_id = m;
  IF public.dating_photo_keys_for_viewer(w, 'introduction', v_id, v_hash) IS DISTINCT FROM '{"ok": false, "reason": "photos_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos kept for mutual interest were keyed before it';
  END IF;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state) VALUES (v_id, least(w, m), greatest(w, m), 'active') RETURNING id INTO v_match;
  IF jsonb_array_length(public.dating_photo_keys_for_viewer(w, 'match', v_match, v_hash) -> 'photos') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match does not see the other''s viewable photos';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_profile_photos';
  IF public.dating_photo_keys_for_viewer(w, 'match', v_match, v_hash) IS DISTINCT FROM '{"ok": false, "reason": "photos_unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photo keys were given with the photo flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_profile_photos';
END $$;

-- =====================================================================
-- P. (§3.13) The digest: at the person's drop, only when on, only with
--    something new; the neutral me_update (no "dating", no id); at most
--    one a day.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('38');
  x constant uuid := pg_temp.ready('39', '{"identity": "man", "seeking": ["woman"]}');
  v_off integer;
  v_tz text;
  v_slot time;
  v_local timestamp;
  v_sent integer;
  v_meta jsonb;
BEGIN
  -- A whole-hour zone where the last half-hour slot is between 07:00 and 22:00.
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    v_local := now() AT TIME ZONE v_tz;
    v_slot := (date_trunc('hour', v_local) + CASE WHEN extract(minute FROM v_local) >= 30 THEN interval '30 minutes' ELSE interval '0' END)::time;
    EXIT WHEN v_slot BETWEEN time '07:00' AND time '22:00';
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id = u;
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push) VALUES (u, v_slot, true);
  -- x: digest on, but it is night where x is (no drop in the last hour).
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    EXIT WHEN extract(hour FROM now() AT TIME ZONE v_tz) BETWEEN 1 AND 5;
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id = x;
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push) VALUES (x, '19:00', true);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w5-push-key', true);
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a digest was sent with nothing new';
  END IF;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(u, x), least(u, x), greatest(u, x), 'generated', 'introductions_v2', now() - interval '1 minute', now() - interval '1 minute');
  -- No push key: nothing, counted, never a raise (the cron's).
  PERFORM set_config('app.settings.dating_push_key', '', true);
  BEGIN
    v_sent := public.send_dating_digests();
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest raised without its push key (%)', SQLERRM;
  END;
  IF v_sent <> 0 OR pg_temp.metric('dating.digest.push_key_missing') < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest without its push key sent or was not counted';
  END IF;
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w5-push-key', true);
  v_sent := public.send_dating_digests();
  SELECT metadata INTO v_meta FROM public.scheduled_notifications
   WHERE user_id = u AND source_key = private.dating_push_source_key(u, 'digest', (now() AT TIME ZONE 'UTC')::date);
  -- (the push queue's quiet-hours guard may mark it deferred: §3.13)
  IF v_sent <> 1 OR v_meta - 'quiet_deferred' IS DISTINCT FROM '{"type": "me_update", "route": "me", "title": "Attune", "body": "You have something new in Attune."}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest was not the one neutral push (% sent, %)', v_sent, v_meta;
  END IF;
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second digest the same day';
  END IF;
  UPDATE public.dating_settings SET digest_push = false, digest_sent_at = NULL WHERE user_id = u;
  DELETE FROM public.scheduled_notifications WHERE user_id = u;
  IF public.send_dating_digests() <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a digest the person turned off';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-digest' AND schedule = '5 * * * *' AND command = 'SELECT public.send_dating_digests()') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the digest cron is not scheduled';
  END IF;
END $$;
-- =====================================================================
-- K2. (§3.4 the card's More, §3.6 Block; Spec 2 W5b Task 7b; Ruling R-36)
--     Block on the card. Fixed answers, never a raise, nothing echoed; an
--     outsider's block answers exactly as for one that doesn't exist and
--     changes nothing; a block only reduces exposure, so another phone (or
--     none) and a paused person may block, but only one of the two people;
--     the limit is 20 a day; the block ends the card for both people,
--     tells the other person nothing (the same answers as for any card
--     that is gone) and queues no push; a replay answers as the first did
--     and counts once; the pair is never generated again, by id or, once
--     the id rows are gone (an account deleted), by phone HMAC.
-- =====================================================================
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '20 days 3 hours 17 minutes';
  v_fake constant uuid := '5e5e0000-0000-4000-8000-0000000000fd';
  w uuid;
  m uuid;
  c uuid;
  v_i uuid;
  v jsonb;
  v_answer text;
  v_absent text;
  v_bad text;
  v_got text;
  v_regen text;
  v_tick text;
  v_w jsonb;
  v_m jsonb;
  v_today jsonb;
  v_act text;
  v_act_absent text;
  v_rate integer;
  v_count bigint;
  v_pushes bigint := (SELECT count(*) FROM public.scheduled_notifications);
BEGIN
  -- The generation runs below see only K2's people (as G's do).
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  w := pg_temp.ready('44');
  m := pg_temp.ready('45', '{"identity": "man", "seeking": ["woman"]}');
  c := pg_temp.ready('50', '{"identity": "man", "seeking": ["woman"]}');
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high, reasons)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'presented', 'introductions_v2', now() - interval '1 hour', now() - interval '1 hour', ARRAY['same_intention'])
  RETURNING id INTO v_i;
  IF pg_temp.call(w, pg_temp.dev('44'), 'SELECT public.get_my_dating_introductions()')::jsonb #>> '{cards,0,id}' IS DISTINCT FROM v_i::text
     OR pg_temp.call(m, pg_temp.dev('45'), 'SELECT public.get_my_dating_introductions()')::jsonb #>> '{cards,0,id}' IS DISTINCT FROM v_i::text THEN
    RAISE EXCEPTION 'fixture: both people do not read the introduction before the block';
  END IF;
  -- The control: with the introduction gone (as leaving deletes it) and no
  -- block, the next run introduces the pair again.
  v_tick := format('SELECT set_config(''k2.tick'', public.run_dating_generation_tick(%L, ''GH'')::text, true)', v_at);
  v_regen := format('SELECT (current_setting(''k2.tick'')::jsonb #>> ''{runs,0,partition}'') || '':'' || (SELECT count(*) FROM public.dating_introductions WHERE pair_key = %L AND created_at = %L)',
                    public.dating_pair_key(w, m), v_at);
  v_got := pg_temp.probe(ARRAY[format('DELETE FROM public.dating_introductions WHERE id = %L', v_i), v_tick], v_regen);
  IF v_got IS DISTINCT FROM 'GH:1' THEN
    RAISE EXCEPTION 'fixture: without a block the run does not introduce the pair again (%)', v_got;
  END IF;

  -- Fixed codes, never a raise, nothing of the input echoed.
  SELECT string_agg(x.k || ' -> ' || x.a, '; ') INTO v_bad FROM (
    SELECT coalesce(t.k, '<null>') AS k, pg_temp.call(w, pg_temp.dev('44'), format('SELECT public.block_dating_introduction(%L, %L)', t.k, t.id)) AS a
      FROM (VALUES ('short', v_i), (repeat('k', 129), v_i), ('k2-quote-' || repeat('x', 12) || ''' OR ''1''=''1', v_i),
                   (md5('k2-null-id'), NULL::uuid), (NULL::text, v_i)) AS t(k, id)) AS x
   WHERE x.a IS DISTINCT FROM '{"ok": false, "reason": "invalid"}';
  IF v_bad IS NOT NULL OR (SELECT state FROM public.dating_introductions WHERE id = v_i) <> 'presented' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed block answered other than {ok: false, reason: invalid} or changed the introduction: %', v_bad;
  END IF;

  -- H2: an outsider's block answers as for none, and changes nothing.
  -- (Each call its own statement: an IF's operands have no order.)
  v_answer := pg_temp.call(c, pg_temp.dev('50'), format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-c-forged'), v_i));
  v_absent := pg_temp.call(c, pg_temp.dev('50'), format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-c-absent'), v_fake));
  IF v_answer IS DISTINCT FROM '{"ok": false, "reason": "introduction_unavailable"}' OR v_answer IS DISTINCT FROM v_absent
     OR EXISTS (SELECT 1 FROM public.dating_blocks WHERE blocker_user_id = c OR blocked_user_id = c)
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = c AND operation = 'block_dating_introduction')
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i) <> 'presented' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider''s block answered % (none: %) or changed the introduction (H2)', v_answer, v_absent;
  END IF;

  -- 20 a day: the 21st answers rate_limited and blocks nothing.
  v_got := pg_temp.probe(ARRAY[
      format('INSERT INTO public.dating_rate_limits (user_id, operation, window_started_at, request_count) VALUES (%L, ''block'', now(), 20) ON CONFLICT (user_id, operation) DO UPDATE SET window_started_at = now(), request_count = 20', w),
      format('SELECT set_config(''k2.answer'', pg_temp.call(%L, %L, %L), true)', w, pg_temp.dev('44'),
             format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-limit'), v_i))],
    format('SELECT current_setting(''k2.answer'') || '':'' || (SELECT count(*) FROM public.dating_blocks WHERE blocker_user_id = %L)', w));
  IF v_got IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 21st block in a day answered % (expected rate_limited, nothing blocked)', v_got;
  END IF;

  -- Ruling R-36: a block reduces exposure: another phone, no phone, and a
  -- paused person all block (each undone).
  SELECT string_agg(x.why || ' -> ' || x.got, '; ') INTO v_bad FROM (
    SELECT t.why, pg_temp.probe(t.setup || format('SELECT set_config(''k2.answer'', pg_temp.call(%L, %L, %L), true)', w, t.device,
                                                  format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-' || t.why), v_i)),
                               format('SELECT current_setting(''k2.answer'') || '':'' || (SELECT state FROM public.dating_introductions WHERE id = %L)', v_i)) AS got
      FROM (VALUES ('another phone', pg_temp.dev('99'), ARRAY[]::text[]),
                   ('no phone', NULL::text, ARRAY[]::text[]),
                   ('paused', pg_temp.dev('44'), ARRAY[format('UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'' WHERE user_id = %L', w)])) AS t(why, device, setup)) AS x
   WHERE x.got IS DISTINCT FROM '{"ok": true}:invalidated';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a block was refused or did not end the introduction (Ruling R-36: never gated by the phone or eligibility): %', v_bad;
  END IF;

  -- The block, from the person's own phone.
  v_count := pg_temp.metric('dating.block');
  v := pg_temp.call(w, pg_temp.dev('44'), format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-w'), v_i))::jsonb;
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the block answered %', v;
  END IF;
  -- Ended for both, by id and by phone HMAC; the pair fails the filters.
  IF (SELECT state FROM public.dating_introductions WHERE id = v_i) <> 'invalidated'
     OR NOT EXISTS (SELECT 1 FROM public.dating_blocks WHERE blocker_user_id = w AND blocked_user_id = m)
     OR NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                     WHERE blocker_hmac = public.dating_phone_hmac_for_user(w) AND blocked_hmac = public.dating_phone_hmac_for_user(m))
     OR pg_temp.hf(w, m) IS DISTINCT FROM 'ff' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the block left the introduction %, or wrote no id or HMAC pair, or the filters still pass (%)',
      (SELECT state FROM public.dating_introductions WHERE id = v_i), pg_temp.hf(w, m);
  END IF;
  -- Nobody is told: the card is gone for both; to the other person it is
  -- any card that is gone (the act answers as for none; nothing in Today
  -- names a block); no push is queued.
  v_w := pg_temp.call(w, pg_temp.dev('44'), 'SELECT public.get_my_dating_introductions()')::jsonb;
  v_m := pg_temp.call(m, pg_temp.dev('45'), 'SELECT public.get_my_dating_introductions()')::jsonb;
  v_today := pg_temp.call(m, pg_temp.dev('45'), 'SELECT public.get_my_dating_today()')::jsonb;
  v_act := pg_temp.call(m, pg_temp.dev('45'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k2-m-act'), v_i));
  v_act_absent := pg_temp.call(m, pg_temp.dev('45'), format('SELECT public.act_on_dating_introduction(%L, %L, ''interested'')', md5('k2-m-absent'), v_fake));
  IF v_w ->> 'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(v_w -> 'cards') <> 0
     OR v_m ->> 'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(v_m -> 'cards') <> 0
     OR v_today ->> 'ok' IS DISTINCT FROM 'true' OR jsonb_array_length(v_today -> 'cards') <> 0 OR v_today::text ~* 'block'
     OR v_act IS DISTINCT FROM v_act_absent
     OR (SELECT count(*) FROM public.scheduled_notifications) <> v_pushes THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the block the cards were % / %, the other''s Today %, their act % (none: %), % push(es)',
      v_w -> 'cards', v_m -> 'cards', v_today, v_act, v_act_absent, (SELECT count(*) FROM public.scheduled_notifications) - v_pushes;
  END IF;
  -- A replay answers as the first did, counts once, uses no more of the
  -- day's limit; the other person may still block (one answer for both).
  v_rate := (SELECT request_count FROM public.dating_rate_limits WHERE user_id = w AND operation = 'block');
  v_answer := pg_temp.call(w, pg_temp.dev('44'), format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-w'), v_i));
  v_absent := pg_temp.call(m, pg_temp.dev('45'), format('SELECT public.block_dating_introduction(%L, %L)', md5('k2-m'), v_i));
  IF v_answer IS DISTINCT FROM '{"ok": true}' OR v_absent IS DISTINCT FROM '{"ok": true}'
     OR (SELECT request_count FROM public.dating_rate_limits WHERE user_id = w AND operation = 'block') IS DISTINCT FROM v_rate
     OR v_rate IS DISTINCT FROM 1
     OR (SELECT count(*) FROM public.dating_blocks WHERE blocker_user_id = w) <> 1
     OR pg_temp.metric('dating.block') <> v_count + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay answered % (the other person: %), the limit went % -> %, % block row(s), counted % (expected 1 + 1)',
      v_answer, v_absent, v_rate, (SELECT request_count FROM public.dating_rate_limits WHERE user_id = w AND operation = 'block'),
      (SELECT count(*) FROM public.dating_blocks WHERE blocker_user_id = w), pg_temp.metric('dating.block') - v_count;
  END IF;

  -- Never introduced again: with the introduction gone the run leaves the
  -- pair out; with the id rows gone too (an account deleted), the phone
  -- HMAC pair still does.
  v_got := pg_temp.probe(ARRAY[format('DELETE FROM public.dating_introductions WHERE id = %L', v_i), v_tick], v_regen);
  v_answer := pg_temp.probe(ARRAY[format('DELETE FROM public.dating_introductions WHERE id = %L', v_i),
                                  format('DELETE FROM public.dating_blocks WHERE pair_key = %L', public.dating_pair_key(w, m)), v_tick], v_regen);
  IF v_got IS DISTINCT FROM 'GH:0' OR v_answer IS DISTINCT FROM 'GH:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blocked pair was introduced again: by id %, by phone HMAC % (expected GH:0 both)', v_got, v_answer;
  END IF;
END $$;
-- =====================================================================
-- Q. (§5.10, §7.2 S10; Ruling R-14) The dragnet: 15 introductions in 14
--    days with "Interested" on 90% or more, and a first message in 20% or
--    fewer of the matches, opens one P2 signal case (never twice) and caps
--    the person at one introduction a day; once today's one is made, they
--    are out of generation (filter 15). Until W6a's messages exist the
--    first-message input is unknown and the rule waits. Under 90%: nothing.
-- =====================================================================
DO $$
DECLARE
  d constant uuid := pg_temp.ready('95', '{"identity": "man", "seeking": ["woman"]}');
  q constant uuid := pg_temp.ready('96', '{"identity": "man", "seeking": ["woman"]}');
  w constant uuid := pg_temp.ready('90');
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '2 days 3 hours 17 minutes';
  v_stub constant text := 'CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamptz, p_at timestamptz) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$';
  v text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active' AND user_id NOT IN (d, q, w);
  -- 15 introductions each in the last 14 days, with 15 other people.
  INSERT INTO auth.users (id) SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid FROM generate_series(1, 15) AS n;
  INSERT INTO public.users (id, display_name) SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'Other' FROM generate_series(1, 15) AS n;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, low_action, high_action, created_at)
  SELECT 'w5drag:' || x.who || ':' || n, least(x.who, o), greatest(x.who, o), 'interested', 'introductions_v2',
         CASE WHEN x.who < o AND (x.who = d OR n <= 12) THEN 'interested' END,
         CASE WHEN x.who > o AND (x.who = d OR n <= 12) THEN 'interested' END, v_at - make_interval(days => n % 13 + 1)
    FROM (VALUES (d), (q)) AS x(who), generate_series(1, 15) AS n,
         LATERAL (SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS o) AS other;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state)
  SELECT i.id, i.user_low_id, i.user_high_id, 'closed' FROM public.dating_introductions AS i
   WHERE i.pair_key IN ('w5drag:' || d || ':1', 'w5drag:' || q || ':1');
  -- Spec 2 W6a (carry 6): the input is the messages. Both wrote in their
  -- one match, so nothing opens; with those messages gone, d's case does.
  -- (The probes below stub the input to none, as W5c did.)
  INSERT INTO public.dating_messages (match_id, sender_side, sender_user_id, body, body_masked, mask_version, idempotency_key)
  SELECT m.id, CASE WHEN m.user_low_id = x.who THEN 'low' ELSE 'high' END, x.who, 'hello', 'hello', 1, 'w6-first-' || x.who
    FROM (VALUES (d), (q)) AS x(who)
    JOIN public.dating_introductions AS i ON i.pair_key = 'w5drag:' || x.who || ':1'
    JOIN public.dating_matches AS m ON m.introduction_id = i.id;
  IF pg_temp.probe(ARRAY['DELETE FROM public.dating_messages WHERE idempotency_key LIKE ''w6-first-%''',
                         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg)],
       format('SELECT count(*)::text FROM public.dating_moderation_cases WHERE signal_kind = ''dragnet'' AND target_user_id = %L', d)) <> '1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no first messages the real input did not open d''s dragnet case (carry 6)';
  END IF;
  PERFORM private.dating_run_signals(v_at, v_cfg);
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dragnet fired on people who wrote in their matches (carry 6)';
  END IF;
  -- The tick runs the signals before any partition (here none: 'ZZ' has
  -- no row); a second run opens no second case.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')', v_at),
         format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')', v_at)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L AND kind = 'signal' AND priority = 'P2' AND state = 'open' AND target_phone_hmac = public.dating_phone_hmac_for_user(%L))
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L)
                 || ':' || private.dating_capacity(%L, %L, %L)
                 || ':' || private.dating_capacity(%L, %L, %L)$q$, d, d, q, d, v_at, v_cfg, w, v_at, v_cfg));
  IF v IS DISTINCT FROM '1:0:1:3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dragnet did not open one case and throttle to 1 (or touched someone under 90%%): %', v;
  END IF;
  -- Fix round 1 (M-3.1): throttled with none made today, the person is
  -- still current: one a day, never none.
  v := pg_temp.probe(ARRAY[v_stub, format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg)],
       format('SELECT private.dating_throttled(%L)::text || '':'' || private.dating_person_current(%L, %L, %L)::text', d, d, v_at, v_cfg));
  IF v IS DISTINCT FROM 'true:true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a throttled person with no introduction today left generation (one a day, not none): %', v;
  END IF;
  -- Fix round 1 (M-3.2): a real Ghana partition in the same tick as the
  -- signals: the newly flagged d gets one introduction, q (under 90%%)
  -- gets more, with four women to choose from.
  v := pg_temp.probe(ARRAY[v_stub,
         'SELECT pg_temp.ready(''05''), pg_temp.ready(''06''), pg_temp.ready(''07'')',
         format('SELECT public.run_dating_generation_tick(%L, ''GH'')', v_at)],
       format($q$SELECT (SELECT count(*) FROM public.dating_introductions WHERE %L IN (user_low_id, user_high_id) AND created_at = %L)
                 || ':' || (SELECT count(*) >= 2 FROM public.dating_introductions WHERE %L IN (user_low_id, user_high_id) AND created_at = %L)
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'dragnet')$q$,
              d, v_at, q, v_at, d));
  IF v IS DISTINCT FROM '1:true:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the tick did not run the signals before its partitions (d''s introductions : q got 2+ : d''s case): %', v;
  END IF;
  -- Fix round 1 (I-1): a moderator's decision sticks: the next tick opens
  -- no new case while the evidence predates it, and the cap is back to 3.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg),
         format('UPDATE public.dating_moderation_cases SET state = ''decided'', decided_at = %L::timestamptz, outcome = ''no_action'' WHERE target_user_id = %L AND signal_kind = ''dragnet''', v_at, d),
         format('SELECT private.dating_run_signals(%L, %L)', v_at + interval '1 hour', v_cfg),
         format('SELECT private.dating_run_signals(%L, %L)', v_at + interval '13 days', v_cfg)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'dragnet' AND state IN ('open', 'in_review'))
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'dragnet')
                 || ':' || private.dating_capacity(%L, %L, %L)$q$, d, d, d, v_at + interval '1 hour', v_cfg));
  IF v IS DISTINCT FROM '0:1:3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a decided dragnet case reopened on a later tick (open : all : capacity): %', v;
  END IF;
  -- Fix round 2 (N-1): the skip ends. After the decision, 15 new
  -- introductions (Interested on all, one match) inside a window that
  -- starts after it: the tick at +15 days opens a new case.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg),
         format('UPDATE public.dating_moderation_cases SET state = ''decided'', decided_at = %L::timestamptz, outcome = ''no_action'' WHERE target_user_id = %L AND signal_kind = ''dragnet''', v_at, d),
         format($s$INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, low_action, high_action, created_at)
                   SELECT 'w5drag3:' || n, least(%L::uuid, o), greatest(%L::uuid, o), 'interested', 'introductions_v2',
                          CASE WHEN %L::uuid < o THEN 'interested' END, CASE WHEN %L::uuid > o THEN 'interested' END,
                          %L::timestamptz + interval '1 day 1 hour' + make_interval(hours => n * 20)
                     FROM generate_series(1, 15) AS n, LATERAL (SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS o) AS other$s$,
                d, d, d, d, v_at),
         'INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state) SELECT i.id, i.user_low_id, i.user_high_id, ''closed'' FROM public.dating_introductions AS i WHERE i.pair_key = ''w5drag3:1''',
         format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')', v_at + interval '15 days')],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'dragnet' AND state = 'open')
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'dragnet')$q$, d, d));
  IF v IS DISTINCT FROM '1:2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new dragnet evidence after a decision never opened a new case (the skip did not end) (open : all): %', v;
  END IF;
  -- Fix round 1 (M-6): the case follows the phone: with the account link
  -- gone (a deletion nulls it), the same number is still throttled and no
  -- second case opens.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg),
         format('UPDATE public.dating_moderation_cases SET target_user_id = NULL WHERE target_user_id = %L AND signal_kind = ''dragnet''', d),
         format('SELECT private.dating_run_signals(%L, %L)', v_at + interval '1 hour', v_cfg)],
       format($q$SELECT private.dating_throttled(%L)::text
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND state = 'open'
                             AND target_phone_hmac = public.dating_phone_hmac_for_user(%L))$q$, d, d));
  IF v IS DISTINCT FROM 'true:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dragnet case did not follow the phone once the account link was gone (throttled : open cases): %', v;
  END IF;
  -- Today's one made: out of generation (filter 15) until a moderator decides.
  v := pg_temp.probe(ARRAY[v_stub,
         format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg),
         format('INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at) VALUES (''w5drag:today'', least(%L::uuid, %L::uuid), greatest(%L::uuid, %L::uuid), ''generated'', ''introductions_v2'', %L::timestamptz - interval ''1 hour'')', d, w, d, w, v_at)],
       format('SELECT private.dating_person_current(%L, %L, %L)::text || '':'' || private.dating_person_current(%L, %L, %L)::text', d, v_at, v_cfg, w, v_at, v_cfg));
  IF v IS DISTINCT FROM 'false:true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a throttled person at 0 stayed in generation (filter 15): %', v;
  END IF;
END $$;

-- =====================================================================
-- Q2. (Task 8 Rulings) A signal that fails never stops generation: the
--     tick counts it and goes on to its partitions (each partition is
--     already its own subtransaction). The several-accounts signal looks a
--     phone's other accounts up by an index, not a scan per person.
-- =====================================================================
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '2 days 3 hours 17 minutes';
  v_boom constant text := 'CREATE OR REPLACE FUNCTION private.dating_run_signals(p_at timestamptz, p_cfg jsonb) RETURNS integer LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION ''w5:signal_boom''; END $f$';
  v_before constant bigint := pg_temp.metric('dating.signal.failed');
  v_busy constant bigint := pg_temp.metric('dating.signal.busy');
  v text;
BEGIN
  BEGIN
    v := pg_temp.probe(ARRAY[v_boom],
           format('SELECT public.run_dating_generation_tick(%L, ''ZZ'')::text || '':'' || (pg_temp.metric(''dating.signal.failed'') - %s)', v_at, v_before));
  EXCEPTION WHEN OTHERS THEN
    v := 'the tick raised ' || SQLERRM;
  END;
  IF v IS DISTINCT FROM '{"runs": []}:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing signal stopped generation, or was not counted: %', v;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'dating_trusted_devices'
                    AND indexname = 'dating_trusted_devices_hash_idx' AND indexdef LIKE '%(device_hash, verified_at)%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the several-accounts signal has no device_hash index (a scan per person each tick)';
  END IF;
  -- Fix round 1 (M-2): a deleted account or a purged match nulls its cases
  -- by index, never by a scan of the queue; M-6's phone look-up likewise.
  IF (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'dating_moderation_cases'
        AND ((indexname = 'dating_moderation_cases_target_idx' AND indexdef LIKE '%(target_user_id)')
          OR (indexname = 'dating_moderation_cases_match_idx' AND indexdef LIKE '%(match_id) WHERE (match_id IS NOT NULL)')
          OR (indexname = 'dating_moderation_cases_phone_idx' AND indexdef LIKE '%(target_phone_hmac, signal_kind)%'))) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue''s foreign keys or phone look-up have no index (M-2, M-6)';
  END IF;
  -- Fix round 1 (I-2, M-1, M-5): health shows a failed signal step, a case
  -- left for later and an unreadable fairness answer.
  IF NOT (public.get_dating_operational_health() -> 'safety_counters_7d'
          ?& ARRAY['dating.signal.failed', 'dating.signal.busy', 'dating.fairness.unreadable']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show failed signals, busy cases or unreadable fairness answers';
  END IF;
  -- Fix round 1 (M-1): a person gone (or whose row a deletion holds)
  -- opens nothing and raises nothing: counted busy, tried next tick.
  BEGIN
    v := private.dating_open_signal_case(gen_random_uuid(), 'dragnet', 'P2')::text || ':' || (pg_temp.metric('dating.signal.busy') - v_busy);
  EXCEPTION WHEN OTHERS THEN
    v := 'raised ' || SQLSTATE;
  END;
  IF v IS DISTINCT FROM 'false:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening a case for a person who is gone did not answer false and count busy: %', v;
  END IF;
END $$;

-- =====================================================================
-- R. (§5.10, §2.8) Several Dating accounts on one phone: two activations
--    from one trusted phone in 30 days open one case for each account;
--    older than 30 days, none. A case only: nothing else changes.
--    Fix round 1: one activation inside 30 days and one outside: none
--    (M-3.3); low priority P3, never enough alone (M-7); a dismissed case
--    stays dismissed (I-1); one person's error costs only their own case
--    (I-2).
-- =====================================================================
DO $$
DECLARE
  a constant uuid := pg_temp.ready('88');
  b constant uuid := pg_temp.ready('18', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('40');
  c2 constant uuid := pg_temp.ready('20');
  c3 constant uuid := pg_temp.ready('19');
  c4 constant uuid := pg_temp.ready('60');
  v text;
  v_shared constant text := encode(extensions.digest('w5-shared-phone', 'sha256'), 'hex');
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_before bigint := pg_temp.metric('dating.signal.device_accounts');
BEGIN
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (a, v_shared, now() - interval '3 days', now()), (b, v_shared, now() - interval '1 day', now()),
         (c, encode(extensions.digest('w5-old-phone', 'sha256'), 'hex'), now() - interval '40 days', now()),
         (c2, encode(extensions.digest('w5-old-phone', 'sha256'), 'hex'), now() - interval '35 days', now()),
         (c3, encode(extensions.digest('w5-half-phone', 'sha256'), 'hex'), now() - interval '5 days', now()),
         (c4, encode(extensions.digest('w5-half-phone', 'sha256'), 'hex'), now() - interval '40 days', now());
  PERFORM private.dating_run_signals(now(), v_cfg);
  IF (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (a, b)) <> 2
     OR EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (c, c2))
     OR pg_temp.metric('dating.signal.device_accounts') <> v_before + 2
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = a) <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two accounts on one phone did not open one case each (and only that)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (c3, c4)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one activation inside 30 days and one outside opened a several-accounts case (M-3)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (a, b) AND priority <> 'P3') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a several-accounts case is not low priority (P3, M-7)';
  END IF;
  -- I-1: a moderator dismisses a's case; later ticks inside the 30 days open none.
  v := pg_temp.probe(ARRAY[
         format('UPDATE public.dating_moderation_cases SET state = ''decided'', decided_at = now(), outcome = ''no_action'' WHERE target_user_id = %L AND signal_kind = ''device_accounts''', a),
         format('SELECT private.dating_run_signals(now() + interval ''1 hour'', %L)', v_cfg),
         format('SELECT private.dating_run_signals(now() + interval ''20 days'', %L)', v_cfg)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'device_accounts' AND state = 'open')
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'device_accounts' AND state = 'open')$q$, a, b));
  IF v IS DISTINCT FROM '0:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dismissed several-accounts case reopened (a open : b open): %', v;
  END IF;
  -- Fix round 2 (N-1): the skip ends. a and b activate again on the shared
  -- phone after the dismissal; at +31 days (a window that starts after
  -- it) a's new case opens.
  v := pg_temp.probe(ARRAY[
         format('UPDATE public.dating_moderation_cases SET state = ''decided'', decided_at = now(), outcome = ''no_action'' WHERE target_user_id = %L AND signal_kind = ''device_accounts''', a),
         format('UPDATE public.dating_trusted_devices SET verified_at = now() + interval ''20 days'' WHERE user_id IN (%L, %L) AND device_hash = %L', a, b, v_shared),
         format('SELECT private.dating_run_signals(now() + interval ''31 days'', %L)', v_cfg)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'device_accounts' AND state = 'open')
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'device_accounts')$q$, a, a));
  IF v IS DISTINCT FROM '1:2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new several-accounts evidence after a dismissal never opened a new case (the skip did not end) (open : all): %', v;
  END IF;
  -- I-2: a's signal raises; b's case still opens, and the error is counted
  -- by class (SQLSTATE), never by message.
  BEGIN
  v := pg_temp.probe(ARRAY[
         format('DELETE FROM public.dating_moderation_cases WHERE target_user_id IN (%L, %L)', a, b),
         format('CREATE OR REPLACE FUNCTION private.dating_device_accounts_hold(p_user uuid, p_at timestamptz) RETURNS boolean LANGUAGE plpgsql AS $f$ BEGIN IF p_user = %L::uuid THEN RAISE EXCEPTION ''w5:device_boom''; END IF; RETURN p_user = %L::uuid; END $f$', a, b),
         format('SELECT private.dating_run_signals(now(), %L)', v_cfg)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L)
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE target_user_id = %L AND signal_kind = 'device_accounts')
                 || ':' || (pg_temp.metric('dating.signal.failed') - %s) || ':' || (pg_temp.metric('dating.signal.failed.p0001') - %s)$q$,
              a, b, pg_temp.metric('dating.signal.failed'), pg_temp.metric('dating.signal.failed.p0001')));
  EXCEPTION WHEN OTHERS THEN
    v := 'the run raised ' || SQLERRM;
  END;
  IF v IS DISTINCT FROM '0:1:1:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s signal error cost others their case, or was not counted by class (a : b : failed : failed.p0001): %', v;
  END IF;
END $$;

-- =====================================================================
-- S. (§2.8, §5.10) No signal reads a country, a region, a network, a phone
--    number or prefix, or a name (the case writer records the phone's
--    HMAC the case carries, §4.3; it decides nothing). No routing column
--    (S-5).
--    Fix round 1 (M-3.5): behaviour first: the same behaviour in another
--    country, region, number and name gives the same cases (two accounts
--    on one handset in London; a dragnet sender in London). The source
--    scan stays as a tripwire for the functions that decide whether a
--    signal holds; the case writer, the throttle and the decision check
--    match the case's phone HMAC (§4.3, M-6) and decide nothing.
-- =====================================================================
DO $$
DECLARE
  x1 constant uuid := pg_temp.ready('08', '{"country": "GB", "region": "TLI"}');
  x2 constant uuid := pg_temp.ready('09', '{"country": "GB", "region": "TLI", "identity": "man", "seeking": ["woman"]}');
  d2 constant uuid := pg_temp.ready('10', '{"country": "GB", "region": "TLI", "identity": "man", "seeking": ["woman"]}');
  d constant uuid := pg_temp.id('95');
  v_cfg constant jsonb := (private.dating_intro_config()).o_config;
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '2 days 3 hours 17 minutes';
  v_stub constant text := 'CREATE OR REPLACE FUNCTION private.dating_first_messages(p_user uuid, p_since timestamptz, p_at timestamptz) RETURNS integer LANGUAGE sql AS $f$ SELECT 0 $f$';
  v text;
BEGIN
  UPDATE public.users SET phone = '+4477009000' || right(id::text, 2), display_name = 'Oliver ' || right(id::text, 2) WHERE id IN (x1, x2, d2);
  UPDATE public.dating_profiles SET display_name = 'Oliver' WHERE user_id IN (x1, x2, d2);
  INSERT INTO public.dating_trusted_devices (user_id, device_hash, verified_at, last_seen_at)
  VALUES (x1, encode(extensions.digest('w5-london-phone', 'sha256'), 'hex'), now() - interval '4 days', now()),
         (x2, encode(extensions.digest('w5-london-phone', 'sha256'), 'hex'), now() - interval '2 days', now());
  -- d2 behaves as Q's d: 15 introductions in 14 days, Interested on all, one match.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, low_action, high_action, created_at)
  SELECT 'w5drag2:' || n, least(d2, o), greatest(d2, o), 'interested', 'introductions_v2',
         CASE WHEN d2 < o THEN 'interested' END, CASE WHEN d2 > o THEN 'interested' END, v_at - make_interval(days => n % 13 + 1)
    FROM generate_series(1, 15) AS n, LATERAL (SELECT ('5e5d0000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS o) AS other;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state)
  SELECT i.id, i.user_low_id, i.user_high_id, 'closed' FROM public.dating_introductions AS i WHERE i.pair_key = 'w5drag2:1';
  v := pg_temp.probe(ARRAY[v_stub, format('SELECT private.dating_run_signals(%L, %L)', v_at, v_cfg)],
       format($q$SELECT (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'device_accounts' AND target_user_id IN (%L, %L))
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L)
                 || ':' || (SELECT count(*) FROM public.dating_moderation_cases WHERE signal_kind = 'dragnet' AND target_user_id = %L)$q$, x1, x2, d, d2));
  IF v IS DISTINCT FROM '2:1:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same behaviour in another country, number and name gave other cases (London handset : d : d2): %', v;
  END IF;
END $$;
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'private'
     AND p.proname IN ('dating_dragnet_holds', 'dating_device_accounts_hold', 'dating_run_signals',
                       'dating_generation_removed', 'dating_first_messages')
     AND p.prosrc ~* '(country|region|side_code|network|phone|display_name|calling|prefix)';
  IF v_bad IS NOT NULL OR (SELECT count(*) FROM pg_proc WHERE proname IN ('dating_dragnet_holds', 'dating_device_accounts_hold', 'dating_run_signals')) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signal reads a country, region, network, phone or name: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'dating_moderation_cases' AND column_name LIKE '%routing%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queue stores routing (S-5)';
  END IF;
END $$;

-- =====================================================================
-- T. (§5.9) Fairness: per country and cohort at n >= 50 only (a smaller
--    cohort is left out, never merged); a cohort below 0.8 of the
--    country's introductions per person is flagged; the top 10% holding
--    over 25% of introductions is flagged; aggregates only; idempotent.
--    Fix round 1: non-binary and specific terms together make "other"
--    (M-4); a cohort whose mutual rate is below 0.8 of the country's is
--    flagged; the flagged counter counts a row once, never on a rerun; an
--    unreadable answer is counted and costs only that person's gender
--    (M-5).
-- =====================================================================
CREATE FUNCTION pg_temp.fair_person(p_n int, p_region text, p_identity text, p_extra jsonb DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := ('5e5fa000-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_u, '1555940' || lpad(p_n::text, 4, '0'), now(), now() - interval '60 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at) VALUES (v_u, '+1555940' || lpad(p_n::text, 4, '0'), 'Fair ' || p_n, 'dating', now() - interval '60 days');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_u, (current_date - interval '30 years 10 days')::date);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_u, 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Fair', 'GH', p_region);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc)
  VALUES (v_u, private.dating_field_encrypt(jsonb_build_object('identity', p_identity, 'pools', jsonb_build_array(p_identity)) || p_extra));
  RETURN v_u;
END $$;
DO $$
DECLARE
  v_week constant date := (date_trunc('week', now()) + interval '7 days')::date;
  v jsonb;
  v_flagged_before constant bigint := pg_temp.metric('dating.fairness.flagged');
  v_after bigint;
  v_t text;
BEGIN
  UPDATE public.dating_enrollments SET state = 'paused', pause_reason = 'user' WHERE state = 'active';
  -- 60 in Greater Accra (two introductions each), 60 in Ashanti (none), 10 in Ahafo.
  PERFORM pg_temp.fair_person(n, CASE WHEN n <= 60 THEN 'AA' WHEN n <= 120 THEN 'AH' ELSE 'AF' END,
                              CASE WHEN n % 2 = 0 THEN 'woman' ELSE 'man' END) FROM generate_series(1, 130) AS n;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at)
  SELECT 'w5fair:' || n, least(a, b), greatest(a, b), CASE WHEN n % 3 = 0 THEN 'matched' ELSE 'passed' END, 'introductions_v2', now() - interval '2 days'
    FROM generate_series(1, 60) AS n,
         LATERAL (SELECT ('5e5fa000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid AS a,
                         ('5e5fa000-0000-0000-0000-' || lpad((n % 60 + 1)::text, 12, '0'))::uuid AS b) AS x;
  -- Fix round 1: 60 in Brong-Ahafo, 30 non-binary and 30 women with a
  -- specific term (both "other", M-4), one introduction each, none mutual.
  PERFORM pg_temp.fair_person(n, 'BA', CASE WHEN n % 2 = 0 THEN 'non_binary' ELSE 'woman' END,
                              CASE WHEN n % 2 = 0 THEN '{}'::jsonb ELSE '{"specific_text": "w5 specific"}'::jsonb END)
     FROM generate_series(131, 190) AS n;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at)
  SELECT 'w5fairba:' || n, ('5e5fa000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
         ('5e5fa000-0000-0000-0000-' || lpad((n + 1)::text, 12, '0'))::uuid, 'passed', 'introductions_v2', now() - interval '2 days'
    FROM generate_series(131, 189, 2) AS n;
  -- An unreadable answer (probe): counted once, and only that person's
  -- gender is lost: every cohort is still written.
  BEGIN
  v_t := pg_temp.probe(ARRAY[
           'UPDATE public.dating_profile_sensitive SET identity_enc = ''\x01c30d0407''::bytea WHERE user_id = ''5e5fa000-0000-0000-0000-000000000002''',
           format('SELECT public.dating_fairness_weekly(%L)', v_week)],
         format($q$SELECT (pg_temp.metric('dating.fairness.unreadable') - %s) || ':'
                   || (SELECT string_agg(cohort_key, ',' ORDER BY cohort_key) FROM public.dating_fairness_reports WHERE week = %L AND country_code = 'GH')$q$,
                pg_temp.metric('dating.fairness.unreadable'), v_week));
  EXCEPTION WHEN OTHERS THEN
    v_t := 'the job raised ' || SQLSTATE;
  END;
  IF v_t IS DISTINCT FROM '1:age:25_34,gender:man,gender:other,gender:woman,region:AA,region:AH,region:BA,top_decile' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unreadable answer was not counted, or cost more than that person''s gender (M-5): %', v_t;
  END IF;
  IF public.dating_fairness_weekly(v_week) < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness job wrote nothing';
  END IF;
  SELECT jsonb_object_agg(cohort_key, jsonb_build_array(active_bucket, introductions_per_active, flagged)) INTO v
    FROM public.dating_fairness_reports WHERE week = v_week AND country_code = 'GH';
  IF v -> 'region:AA' IS DISTINCT FROM '["50–99", 2.0000, false]'::jsonb
     OR v -> 'region:AH' IS DISTINCT FROM '["50–99", 0.0000, true]'::jsonb
     OR v ? 'region:AF'
     OR v -> 'gender:other' IS DISTINCT FROM '["50–99", 1.0000, true]'::jsonb
     OR v -> 'region:BA' IS DISTINCT FROM '["50–99", 1.0000, true]'::jsonb
     OR (v #>> '{age:25_34,2}')::boolean OR (v #>> '{gender:woman,2}')::boolean OR (v #>> '{gender:man,2}')::boolean
     OR (v #>> '{top_decile,2}')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness rows are not the n >= 50 cohorts with their flags: %', v;
  END IF;
  IF pg_temp.metric('dating.fairness.flagged') - v_flagged_before
     IS DISTINCT FROM (SELECT count(*) FROM public.dating_fairness_reports WHERE week = v_week AND flagged) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the flagged counter is not one per flagged row';
  END IF;
  -- The top 10%: 13 people hold nearly every introduction.
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, created_at)
  SELECT 'w5top:' || a || b, ('5e5fa000-0000-0000-0000-' || lpad(a::text, 12, '0'))::uuid,
         ('5e5fa000-0000-0000-0000-' || lpad(b::text, 12, '0'))::uuid, 'passed', 'introductions_v2', now() - interval '2 days'
    FROM generate_series(61, 73) AS a, generate_series(61, 73) AS b WHERE a < b;
  PERFORM public.dating_fairness_weekly(v_week);
  IF (SELECT flagged FROM public.dating_fairness_reports WHERE week = v_week AND country_code = 'GH' AND cohort_key = 'top_decile') IS NOT TRUE
     OR (SELECT count(*) FROM public.dating_fairness_reports WHERE week = v_week AND cohort_key = 'top_decile') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the top decile holding over 25%% was not flagged (or the rerun duplicated rows)';
  END IF;
  -- A rerun of the same week counts nothing again (M-5).
  v_after := pg_temp.metric('dating.fairness.flagged');
  PERFORM public.dating_fairness_weekly(v_week);
  IF pg_temp.metric('dating.fairness.flagged') <> v_after THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a rerun of the fairness week counted its flags again (M-5): % then %', v_after, pg_temp.metric('dating.fairness.flagged');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dating-fairness-weekly' AND schedule = '17 4 * * 1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fairness cron is not scheduled';
  END IF;
END $$;

-- =====================================================================
-- U. (§2.6, §3.12; carry 17) Other countries: the open countries but the
--    person's own, each on or off; eligible only verified, age checked,
--    14+ days; a country whose same-gender rule refuses the person's
--    answers is never offered; another phone reads nothing.
-- =====================================================================
DO $$
DECLARE
  g constant uuid := pg_temp.ready('01');
  y constant uuid := pg_temp.ready('02', '{"days": 5}');
  nb constant uuid := pg_temp.ready('03', '{"country": "GB", "region": "TLI", "identity": "non_binary", "pools": ["non_binary"], "seeking": ["man", "woman", "non_binary"]}');
  p constant uuid := pg_temp.ready('04', '{"country": "GB", "region": "TLI"}');
  v jsonb;
BEGIN
  v := pg_temp.call(g, pg_temp.dev('01'), 'SELECT public.get_dating_abroad_options()')::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "eligible": true, "countries": [{"on": false, "code": "GB"}]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the options are not the other open countries: %', v;
  END IF;
  PERFORM pg_temp.call(g, pg_temp.dev('01'), format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', md5('abroad-g')));
  IF pg_temp.call(g, pg_temp.dev('01'), 'SELECT public.get_dating_abroad_options()')::jsonb #> '{countries,0,on}' IS DISTINCT FROM 'true'::jsonb
     OR (pg_temp.call(y, pg_temp.dev('02'), 'SELECT public.get_dating_abroad_options()')::jsonb ->> 'eligible')::boolean
     OR pg_temp.call(nb, pg_temp.dev('03'), 'SELECT public.get_dating_abroad_options()')::jsonb -> 'countries' IS DISTINCT FROM '[]'::jsonb
     OR pg_temp.call(p, pg_temp.dev('04'), 'SELECT public.get_dating_abroad_options()')::jsonb -> 'countries' IS DISTINCT FROM '[{"on": false, "code": "GH"}]'::jsonb
     OR pg_temp.call(g, pg_temp.dev('99'), 'SELECT public.get_dating_abroad_options()') IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Other countries: not on after turning on, eligible under 14 days, a same-gender-off country offered to a not-plain profile, or read from another phone';
  END IF;
  -- W5 final (client fixer's finding): a person who isn't eligible (y's
  -- account is 5 days old) is offered no country at all, since which ones
  -- are offered follows the same-gender rule and would tell whether the
  -- profile is man-woman; g, eligible with the same answers, sees GB.
  v := pg_temp.call(y, pg_temp.dev('02'), 'SELECT public.get_dating_abroad_options()')::jsonb;
  IF v IS DISTINCT FROM '{"ok": true, "eligible": false, "countries": []}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Other countries listed countries to a person who isn''t eligible: %', v;
  END IF;
END $$;
-- =====================================================================
-- V. (§2.3 freshness, Ruling R-3; W5 final review I-1) The daily reads
--    refresh the trusted phone's last use the way PostgREST calls them:
--    an RPC that is not VOLATILE runs READ ONLY there, where the device
--    check's touch fails and is swallowed (psql runs read-write, so no
--    other case can see it). Each read, called that way with the phone
--    last seen 2 days ago, leaves its last use at now.
-- =====================================================================
DO $$
DECLARE
  u constant uuid := pg_temp.ready('b1');
  v_fn text;
  v_ro boolean;
  v_seen timestamptz;
  v_bad text[] := '{}';
BEGIN
  FOREACH v_fn IN ARRAY ARRAY['public.get_my_dating_today()', 'public.get_my_dating_introductions()',
                              'public.get_dating_abroad_options()'] LOOP
    UPDATE public.dating_trusted_devices SET last_seen_at = now() - interval '2 days' WHERE user_id = u;
    SELECT p.provolatile <> 'v' INTO v_ro FROM pg_catalog.pg_proc AS p WHERE p.oid = v_fn::regprocedure;
    v_seen := NULL;
    BEGIN
      IF v_ro THEN
        PERFORM set_config('transaction_read_only', 'on', true); -- as PostgREST runs a STABLE or IMMUTABLE RPC
      END IF;
      PERFORM pg_temp.call(u, pg_temp.dev('b1'), 'SELECT ' || v_fn || '::text');
      SELECT d.last_seen_at INTO v_seen FROM public.dating_trusted_devices AS d WHERE d.user_id = u;
      RAISE EXCEPTION 'w5:postgrest_undo';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM IS DISTINCT FROM 'w5:postgrest_undo' THEN
        RAISE;
      END IF;
    END;
    IF v_seen IS DISTINCT FROM now() THEN
      v_bad := v_bad || (v_fn || CASE WHEN v_ro THEN ' (runs READ ONLY)' ELSE '' END);
    END IF;
  END LOOP;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a daily read, called as PostgREST calls it, never refreshes the phone''s last use (I-1): %', v_bad;
  END IF;
END $$;

-- =====================================================================
-- W. (§8 W5; W5 final review I-2) The enforced gate record for generation
--    names every W5 production gate the ledger recorded.
-- =====================================================================
DO $$
DECLARE
  v_gate constant text := (SELECT g.gate FROM private.flag_production_gates AS g WHERE g.flag_key = 'dating_candidate_generation');
  v_p text;
  v_missing text[] := '{}';
BEGIN
  FOREACH v_p IN ARRAY ARRAY['dating_exclusion_key provisioned', 'DV sign-off on never-introduce', 'real review refs',
      'any change to its values is a new version', 'commits per partition', 'under ~2 s at the launch partition size',
      '~1,500 people', 'race case 30''s overlap check', 'the signals and the digest commit per step',
      'generation_hour_utc stays aligned', 'publish guard', 'field-key rotation must not end every open introduction',
      'compares ciphertext', 'freshness through PostgREST'] LOOP
    IF position(v_p IN coalesce(v_gate, '')) = 0 THEN
      v_missing := v_missing || v_p;
    END IF;
  END LOOP;
  IF cardinality(v_missing) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W5 production gate record leaves out: %', v_missing;
  END IF;
END $$;

-- =====================================================================
-- X. (§5.2 2-10; W5 final review M-2) A filter answer that changes while
--    a run is open never publishes a card it excludes. The run loads each
--    person once; here the change lands mid-run (a trigger on the run's
--    own insert), with the answer's invalidation trigger off, as it is in
--    life (it can't see the run's uncommitted rows). The control without
--    the change makes the pair.
-- =====================================================================
CREATE FUNCTION pg_temp.w5_mid_run() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.dating_preferences SET min_age = 18, max_age = 25 WHERE user_id = pg_temp.id('b2');
  RETURN NULL;
END $$;
DO $$
DECLARE
  v_at constant timestamptz := date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + interval '30 days 3 hours 17 minutes';
  v_setup constant text[] := ARRAY[
    'UPDATE public.dating_enrollments SET state = ''paused'', pause_reason = ''user'' WHERE state = ''active''',
    'SELECT pg_temp.ready(''b2''), pg_temp.ready(''b3'', ''{"identity": "man", "seeking": ["woman"]}'')'];
  v_mid constant text[] := ARRAY[
    'ALTER TABLE public.dating_preferences DISABLE TRIGGER invalidate_dating_on_preference_change',
    'CREATE TRIGGER zz_w5_mid_run AFTER INSERT ON public.dating_introductions FOR EACH ROW EXECUTE FUNCTION pg_temp.w5_mid_run()'];
  v_tick text;
  v_probe constant text := $p$SELECT (SELECT t.r #>> '{runs,0,created}' FROM pg_temp.w5_tick AS t) || ':'
                                  || (SELECT count(*) FROM public.dating_introductions
                                       WHERE pair_key = public.dating_pair_key(pg_temp.id('b2'), pg_temp.id('b3')))$p$;
  v_control text;
  v_changed text;
BEGIN
  -- (the run is its own statement: a query that calls it can't see its rows)
  v_tick := format('CREATE TEMP TABLE w5_tick AS SELECT public.run_dating_generation_tick(%L, ''GH'') AS r', v_at);
  v_control := pg_temp.probe(v_setup || v_tick, v_probe);
  v_changed := pg_temp.probe(v_setup || v_mid || v_tick, v_probe);
  IF v_control IS DISTINCT FROM '1:1' OR v_changed IS DISTINCT FROM '0:0' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age range changed while the run was open still published the pair it excludes (M-2): control %, changed %',
      v_control, v_changed;
  END IF;
END $$;

-- =====================================================================
-- Y. (§3.13; W5 final review M-3) The digest: one person's error never
--    stops the others' (counted by SQLSTATE only, the person not marked
--    sent); the pushes are queued after every person is read and the
--    sent marks written after every push, so no settings row is locked
--    while the loop still reads.
-- =====================================================================
CREATE TEMP TABLE w5_queue_seen (user_id uuid, sent_marked boolean);
DO $$
DECLARE
  a constant uuid := pg_temp.ready('b4');
  b constant uuid := pg_temp.ready('b5', '{"identity": "man", "seeking": ["woman"]}');
  c constant uuid := pg_temp.ready('b6');
  d constant uuid := pg_temp.ready('b7', '{"identity": "man", "seeking": ["woman"]}');
  v_people constant uuid[] := ARRAY[a, b, c, d];
  v_off integer;
  v_tz text;
  v_slot time;
  v_local timestamp;
  v_sent integer;
  v_err text;
  v_failed constant bigint := pg_temp.metric('dating.digest.failed');
  v_failed_state constant bigint := pg_temp.metric('dating.digest.failed.22023');
  v_marked uuid[];
  v_queued uuid[];
  v_early boolean;
  v_counted text;
BEGIN
  FOR v_off IN -12..14 LOOP
    v_tz := 'Etc/GMT' || CASE WHEN v_off > 0 THEN '-' || v_off WHEN v_off < 0 THEN '+' || (-v_off) ELSE '' END;
    v_local := now() AT TIME ZONE v_tz;
    v_slot := (date_trunc('hour', v_local) + CASE WHEN extract(minute FROM v_local) >= 30 THEN interval '30 minutes' ELSE interval '0' END)::time;
    EXIT WHEN v_slot BETWEEN time '07:00' AND time '22:00';
  END LOOP;
  UPDATE public.users SET timezone = v_tz WHERE id = ANY (v_people);
  INSERT INTO public.dating_settings (user_id, drop_time, digest_push) SELECT p, v_slot, true FROM unnest(v_people) AS p;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version, visible_from_low, visible_from_high)
  VALUES (public.dating_pair_key(a, b), least(a, b), greatest(a, b), 'generated', 'introductions_v2', now() - interval '1 minute', now() - interval '1 minute'),
         (public.dating_pair_key(c, d), least(c, d), greatest(c, d), 'generated', 'introductions_v2', now() - interval '1 minute', now() - interval '1 minute');
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w5-push-key', true);
  BEGIN
    -- The push queue, stubbed: c's push raises; each call notes whether a
    -- fixture's sent mark was already written.
    EXECUTE format($f$CREATE OR REPLACE FUNCTION private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text)
      RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $q$
      BEGIN
        INSERT INTO pg_temp.w5_queue_seen (user_id, sent_marked)
        VALUES (p_user, EXISTS (SELECT 1 FROM public.dating_settings AS t WHERE t.user_id = ANY (%L::uuid[]) AND t.digest_sent_at IS NOT NULL));
        IF p_user = %L::uuid THEN
          RAISE EXCEPTION 'dating:invalid_push' USING ERRCODE = '22023';
        END IF;
        RETURN true;
      END $q$ $f$, v_people, c);
    BEGIN
      v_sent := public.send_dating_digests();
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLSTATE;
    END;
    SELECT array_agg(t.user_id ORDER BY t.user_id) INTO v_marked FROM public.dating_settings AS t
     WHERE t.user_id = ANY (v_people) AND t.digest_sent_at = now();
    SELECT array_agg(q.user_id ORDER BY q.user_id), bool_or(q.sent_marked) INTO v_queued, v_early
      FROM pg_temp.w5_queue_seen AS q WHERE q.user_id = ANY (v_people);
    v_counted := (pg_temp.metric('dating.digest.failed') - v_failed) || ':' || (pg_temp.metric('dating.digest.failed.22023') - v_failed_state);
    RAISE EXCEPTION 'w5:digest_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w5:digest_undo' THEN
      RAISE;
    END IF;
  END;
  IF v_err IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s failing push stopped every digest (M-3): %', v_err;
  END IF;
  IF v_marked IS DISTINCT FROM ARRAY(SELECT x FROM unnest(ARRAY[a, b, d]) AS x ORDER BY x)
     OR v_queued IS DISTINCT FROM ARRAY(SELECT x FROM unnest(ARRAY[a, b, d]) AS x ORDER BY x) -- (c's note goes with its own error block)
     OR v_sent < 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the others'' digests were not all sent (or the failed one was marked sent) (M-3): marked %, queued %, sent %',
      v_marked, v_queued, v_sent;
  END IF;
  IF v_early IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sent mark (a settings row lock) was written while pushes were still being queued (M-3)';
  END IF;
  IF v_counted IS DISTINCT FROM '1:1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the failed digest was not counted once, by its SQLSTATE (M-3): %', v_counted;
  END IF;
END $$;

-- =====================================================================
-- Z. (§3.6 Block; W5 final review M-4, M-5, M-7) Block on a matched
--    introduction closes the match, taking the match's row before the
--    introduction's (exit's order; the race script's case 35 proves no
--    deadlock); health lists the digest's counters but not the signal
--    kinds (§6.9 aggregates for W7b, shown at n >= 50); an active config's
--    values are frozen, its state not.
-- =====================================================================
DO $$
DECLARE
  w constant uuid := pg_temp.ready('b8');
  m constant uuid := pg_temp.ready('b9', '{"identity": "man", "seeking": ["woman"]}');
  v_i uuid;
  v text;
  v_src text;
  v_h jsonb;
  v_case text;
BEGIN
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, state, algorithm_version,
    visible_from_low, visible_from_high, low_action, high_action)
  VALUES (public.dating_pair_key(w, m), least(w, m), greatest(w, m), 'matched', 'introductions_v2',
    now() - interval '1 hour', now() - interval '1 hour', 'interested', 'interested')
  RETURNING id INTO v_i;
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state, matched_at)
  VALUES (v_i, least(w, m), greatest(w, m), 'active', now());
  v := pg_temp.call(w, pg_temp.dev('b8'), format('SELECT public.block_dating_introduction(%L, %L)::text', md5('w5-final-block'), v_i));
  IF v IS DISTINCT FROM '{"ok": true}'
     OR (SELECT string_agg(x.state || '/' || coalesce(x.closed_reason, '-'), ',') FROM public.dating_matches AS x
          WHERE x.introduction_id = v_i) IS DISTINCT FROM 'blocked/blocked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: blocking a matched introduction answered % or left its match %', v,
      (SELECT string_agg(x.state || '/' || coalesce(x.closed_reason, '-'), ',') FROM public.dating_matches AS x WHERE x.introduction_id = v_i);
  END IF;
  -- M-4: the match's row lock comes before the introduction's.
  v_src := (SELECT p.prosrc FROM pg_catalog.pg_proc AS p WHERE p.oid = 'public.block_dating_introduction(text,uuid)'::regprocedure);
  IF position('FROM public.dating_matches' IN v_src) = 0
     OR position('FROM public.dating_matches' IN v_src) > position('FOR UPDATE' IN v_src)
     OR position('FOR UPDATE' IN substr(v_src, position('FOR UPDATE' IN v_src) + 10)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: block does not lock the match before the introduction (exit''s order, M-4)';
  END IF;
  -- M-5 (the ruling: the signal kinds wait for W7b's console).
  v_h := public.get_dating_operational_health() -> 'safety_counters_7d';
  IF NOT coalesce(v_h ? 'dating.digest.push_key_missing', false) OR NOT coalesce(v_h ? 'dating.digest.failed', false)
     OR coalesce((v_h ->> 'dating.digest.push_key_missing')::bigint, 0) < 1
     OR coalesce(v_h ? 'dating.signal.dragnet', false) OR coalesce(v_h ? 'dating.signal.device_accounts', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not list the digest''s push_key_missing and failed counters (or lists a signal kind) (M-5): %', v_h;
  END IF;
  -- M-7: the active config's values are frozen; its state, refs and dates are not.
  IF (private.dating_intro_config()).o_version IS DISTINCT FROM 'introductions_v2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: introductions_v2 is not active here';
  END IF;
  FOREACH v_case IN ARRAY ARRAY[
      'UPDATE public.dating_algorithm_configs SET config = config || ''{"cool_off_hours": 96}'' WHERE version = ''introductions_v2''',
      'UPDATE public.dating_algorithm_configs SET config_hash = ''w5-final-hash'' WHERE version = ''introductions_v2''',
      'UPDATE public.dating_algorithm_configs SET version = ''introductions_v2b'' WHERE version = ''introductions_v2'''] LOOP
    v := NULL;
    BEGIN
      EXECUTE v_case;
      v := 'accepted';
    EXCEPTION WHEN OTHERS THEN
      v := SQLSTATE || ':' || SQLERRM;
    END;
    IF v IS DISTINCT FROM '23514:config:active_frozen' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an active config''s values were edited in place (§5.11, M-7): % gave %', v_case, v;
    END IF;
  END LOOP;
  IF pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET state = ''retired'', retired_at = now() WHERE version = ''introductions_v2''',
                         'UPDATE public.dating_algorithm_configs SET config = config || ''{"cool_off_hours": 96}'' WHERE version = ''introductions_v2'''],
                   'SELECT config ->> ''cool_off_hours'' FROM public.dating_algorithm_configs WHERE version = ''introductions_v2''') IS DISTINCT FROM '96'
     OR pg_temp.probe(ARRAY['UPDATE public.dating_algorithm_configs SET safety_review_ref = ''DEV-safety-2'' WHERE version = ''introductions_v2'''],
                      'SELECT safety_review_ref FROM public.dating_algorithm_configs WHERE version = ''introductions_v2''') IS DISTINCT FROM 'DEV-safety-2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retiring an active config, then editing it, or an active config''s review reference was refused (M-7)';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'dating_v2_matching_contracts: all held'; END $$;
ROLLBACK;
