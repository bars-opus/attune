-- supabase/tests/dating_v2_launch_contracts.sql
-- Spec 2 W10 (§8 W10 tests; §2.2, §3.3.5, §5.9, §6.4, §6.9; R-6, Q19b):
-- the launch guards and get_dating_launch_readiness().
--   L1 (R-6): with every other gate green, the readiness is red while the
--      project reads development, and the environment is its only red gate.
--   L2: in production mode it is green, and each gate turns it red alone.
--   L3: in production, opening a place needs the launch gates green;
--      a reduction is never refused; a DEV- reference in the checklist is
--      refused (dev_reference), and only reported in development. Fix
--      round 1: same-gender on and a looser tier are openings too; a
--      region added while every region is open is a region newly open;
--      same-gender off and a stricter tier are reductions (M-3, M-4).
--   L4: a gated flag's DEV- (or blank) evidence is no evidence in
--      production; the DEV- rule reads past Unicode spaces and dashes.
--   L5: the console's readiness, metrics (n >= 50) and fairness, the
--      safety owner's alone; L6: grants.
-- W9 is read by the readiness only through the gate row of its flag
-- dating_couple_link (W9's migration 20261123100000 inserts it; this file
-- needs it and stubs nothing).
-- Fixture ids 8aa00000-0000-0000-0000-0000000000nn, phones +1555982nn.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_launch_contracts.sql
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('8aa00000-0000-0000-0000-' || lpad(p_n, 12, '0'))::uuid;
$$;
-- The project's environment for the rest of the transaction ('' reads development).
CREATE FUNCTION pg_temp.env(p_env text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.settings.attune_environment', p_env, true);
$$;
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception THEN
  RETURN SQLERRM;
END;
$$;
-- The red gates of a readiness answer, sorted.
CREATE FUNCTION pg_temp.red(v jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(g ->> 'gate' ORDER BY g ->> 'gate'), ARRAY[]::text[])
    FROM jsonb_array_elements(v -> 'gates') AS g WHERE (g ->> 'ok')::boolean IS NOT TRUE;
$$;
CREATE FUNCTION pg_temp.detail(v jsonb, p_gate text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT g -> 'detail' FROM jsonb_array_elements(v -> 'gates') AS g WHERE g ->> 'gate' = p_gate;
$$;
-- The server's log settings can't be set from a test (superuser only):
-- where they are unsafe, that gate stays red and every check allows it.
CREATE FUNCTION pg_temp.logs_ok() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (public.get_dating_operational_health() ->> 'log_settings_safe')::boolean;
$$;
CREATE FUNCTION pg_temp.expect(p_label text, p_got text[], p_want text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_want text[] := p_want;
BEGIN
  IF NOT pg_temp.logs_ok() THEN
    v_want := ARRAY(SELECT DISTINCT x FROM unnest(p_want || ARRAY['log_settings_safe']) AS x ORDER BY x);
  END IF;
  IF p_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: %: red gates % (expected %)', p_label, p_got, v_want;
  END IF;
END;
$$;
CREATE FUNCTION pg_temp.ready_red(p_country text DEFAULT NULL) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT pg_temp.red(public.get_dating_launch_readiness(p_country));
$$;
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.id(p_n);
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_u, '1555982' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (v_u, '+1555982' || p_n, 'Launch ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  RETURN v_u;
END;
$$;
-- The country's current checklist with [p_patch] over it (a publish
-- replaces the whole object, and the checklist only grows).
CREATE FUNCTION pg_temp.checklist(p_country text, p_patch jsonb) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('legal_checklist', (public.dating_country_config(p_country)).legal_checklist || p_patch);
$$;
CREATE FUNCTION pg_temp.resource(p_country text, p_verified date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.support_resources (id, country_code, category, name, phone, verified_at, verified_by, catalogue_version)
  VALUES (gen_random_uuid(), p_country, 'dv', 'Launch fixture line ' || p_country, '+1 555 0100', p_verified,
          'w10-fixture', 'w10');
$$;

-- =====================================================================
-- The green world (every gate but the environment), in development.
-- =====================================================================
DO $$
BEGIN
  -- Vault is read first; a value there would shadow the settings below.
  BEGIN
    DELETE FROM vault.secrets WHERE name IN ('attune_environment', 'age_assurance_mode', 'dating_push_key',
      'moderation_alert_webhook', 'dating_exclusion_key', 'dating_field_key', 'supabase_url');
  EXCEPTION WHEN insufficient_privilege OR undefined_table THEN NULL;
  END;
  PERFORM pg_temp.env('');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w10-launch-key', true);
  -- The field key from Vault: production mode reads it nowhere else (W1d).
  PERFORM vault.create_secret('spec2-w10-field-key-0123456789abcdef-0123', 'dating_field_key');
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w10-push-key', true);
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.example.invalid/w10', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
SELECT private.seed_dating_field_key_fingerprint() AS seeded_field \gset

SELECT pg_temp.person('01') AS owner_id, pg_temp.person('02') AS mod_id, pg_temp.person('03') AS stranger_id,
       pg_temp.person('04') AS tester_id \gset
INSERT INTO public.dating_moderators (user_id, role, sensitive_routing_allowed, languages)
VALUES (pg_temp.id('01'), 'safety_owner', true, '{en}'), (pg_temp.id('02'), 'moderator', false, '{en,tw}');

UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now()
 WHERE state = 'active' AND version <> 'introductions_v2';
UPDATE public.dating_algorithm_configs
   SET state = 'active', activated_at = coalesce(activated_at, now()), product_review_ref = 'W5-PRODUCT-2026-12',
       clinical_review_ref = 'W5-CLINICAL-2026-12', fairness_review_ref = 'W5-FAIRNESS-2026-12',
       safety_review_ref = 'W5-SAFETY-2026-12'
 WHERE version = 'introductions_v2';
UPDATE public.dating_safety_configs SET state = 'active', review_ref = 'W6-SAFETY-2026-12', activated_at = coalesce(activated_at, now())
 WHERE version = 'dating_chat_v1';

-- W9's flag and its gate row (W9's migration; never stubbed here).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_couple_link')
     OR NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'dating_couple_link') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W9''s flag dating_couple_link or its production gate row is missing';
  END IF;
END $$;
UPDATE private.flag_production_gates SET review_ref = 'W10-REVIEW-' || flag_key WHERE review_ref IS NULL OR private.is_dev_reference(review_ref);

SELECT public.publish_country_config('GH', '{"resources_verified_at": "now", "legal_checklist": {
  "ghana_legal_opinion": "GH-COUNSEL-2026-12", "dpc_registration": "DPC-REG-0001", "dpia": "DPIA-v3-SIGNED",
  "pen_test": "PENTEST-2026-12-CLEAN", "safety_owner_and_moderator": "MOD-ROTA-2026-12",
  "reviewer_signoffs": "SIGNOFFS-2026-12"}}') AS gh_fill \gset
SELECT public.publish_country_config('GB', '{"resources_verified_at": "now", "legal_checklist": {
  "osa_illegal_harms_assessment": "OSA-IH-2026", "osa_childrens_access_assessment": "OSA-CA-2026",
  "highly_effective_age_assurance": "HEAA-2026", "dpia": "DPIA-v3-SIGNED", "pen_test": "PENTEST-2026-12-CLEAN",
  "safety_owner_and_moderator": "MOD-ROTA-2026-12", "reviewer_signoffs": "SIGNOFFS-2026-12"}}') AS gb_fill \gset
DO $$ BEGIN PERFORM pg_temp.resource('GH', current_date - 10); PERFORM pg_temp.resource('GB', current_date); END $$;

-- =====================================================================
-- L1 (R-6): development reads red, the environment its only red gate.
-- =====================================================================
DO $$
DECLARE
  v jsonb := public.get_dating_launch_readiness();
BEGIN
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'ready')::boolean IS NOT FALSE
     OR v ->> 'environment' IS DISTINCT FROM 'development'
     OR v -> 'countries' IS DISTINCT FROM '["GH", "GB"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L1 development did not read red: %', v;
  END IF;
  PERFORM pg_temp.expect('L1 development', pg_temp.red(v), ARRAY['environment']);
  -- An unrecognised environment value is production (Spec 1's rule), so it
  -- is never a way round the gate.
  PERFORM pg_temp.env('staging');
  IF public.get_dating_launch_readiness() ->> 'environment' IS DISTINCT FROM 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L1 a typo did not read production';
  END IF;
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L2: production reads green; each gate alone turns it red.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.env('production');
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 all green', pg_temp.red(v), ARRAY[]::text[]);
  IF pg_temp.logs_ok() AND (v ->> 'ready')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 every gate green but not ready: %', v;
  END IF;
  IF (v ->> 'environment') IS DISTINCT FROM 'production' OR v -> 'open' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 environment or open countries wrong: %', v;
  END IF;

  -- Provider mode: only live counts.
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  PERFORM pg_temp.expect('L2 sandbox', pg_temp.ready_red(), ARRAY['age_assurance_live']);
  PERFORM set_config('app.settings.age_assurance_mode', 'fake', true);
  PERFORM pg_temp.expect('L2 fake', pg_temp.ready_red(), ARRAY['age_assurance_live']);
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);

  -- The people.
  UPDATE public.dating_moderators SET active = false WHERE role = 'safety_owner';
  PERFORM pg_temp.expect('L2 no safety owner', pg_temp.ready_red(), ARRAY['safety_owner']);
  UPDATE public.dating_moderators SET active = true WHERE role = 'safety_owner';
  UPDATE public.dating_moderators SET active = false WHERE role = 'moderator';
  PERFORM pg_temp.expect('L2 no moderator', pg_temp.ready_red(), ARRAY['moderator']);
  UPDATE public.dating_moderators SET active = true WHERE role = 'moderator';

  -- The keys.
  PERFORM set_config('app.settings.dating_push_key', '', true);
  PERFORM pg_temp.expect('L2 no push key', pg_temp.ready_red(), ARRAY['keys']);
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w10-push-key', true);
  PERFORM vault.update_secret((SELECT s.id FROM vault.secrets AS s WHERE s.name = 'dating_field_key'),
                              'spec2-w10-another-field-key-0123456789ab');
  PERFORM pg_temp.expect('L2 rotated field key', pg_temp.ready_red(), ARRAY['keys']);
  PERFORM vault.update_secret((SELECT s.id FROM vault.secrets AS s WHERE s.name = 'dating_field_key'),
                              'spec2-w10-field-key-0123456789abcdef-0123');

  -- DEV- references left active from development (the flip doesn't fire
  -- the configs' triggers): the introductions and chat configs.
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET fairness_review_ref = ' dev-fairness' WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 DEV- introductions ref', pg_temp.ready_red(), ARRAY['introductions_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET fairness_review_ref = 'W5-FAIRNESS-2026-12' WHERE state = 'active';
  UPDATE public.dating_algorithm_configs SET state = 'retired', retired_at = now() WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 no introductions config', pg_temp.ready_red(), ARRAY['introductions_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_algorithm_configs SET state = 'active', retired_at = NULL WHERE version = 'introductions_v2';
  UPDATE public.dating_safety_configs SET review_ref = 'DEV-safety' WHERE state = 'active';
  PERFORM pg_temp.env('production');
  PERFORM pg_temp.expect('L2 DEV- chat ref', pg_temp.ready_red(), ARRAY['chat_config']);
  PERFORM pg_temp.env('');
  UPDATE public.dating_safety_configs SET review_ref = 'W6-SAFETY-2026-12' WHERE state = 'active';
  PERFORM pg_temp.env('production');

  -- Flag evidence: a DEV- or missing reference, and a launch flag with no
  -- gate row at all.
  UPDATE private.flag_production_gates SET review_ref = 'DEV-couple' WHERE flag_key = 'dating_couple_link';
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 DEV- flag evidence', pg_temp.red(v), ARRAY['flag_evidence']);
  IF pg_temp.detail(v, 'flag_evidence') IS DISTINCT FROM '["dating_couple_link"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 flag_evidence detail: %', pg_temp.detail(v, 'flag_evidence');
  END IF;
  UPDATE private.flag_production_gates SET review_ref = 'W9-COUNSEL-EXPORT' WHERE flag_key = 'dating_couple_link';
  DELETE FROM private.flag_production_gates WHERE flag_key = 'csam_hash_matching';
  PERFORM pg_temp.expect('L2 no gate row', pg_temp.ready_red(), ARRAY['flag_evidence']);
  INSERT INTO private.flag_production_gates (flag_key, gate, review_ref) VALUES ('csam_hash_matching', 'restored', 'S1-W7B-2026');

  -- A gated flag on with DEV- evidence (switched on in development).
  PERFORM pg_temp.env('');
  UPDATE private.flag_production_gates SET review_ref = 'DEV-text' WHERE flag_key = 'text_scale_v2';
  UPDATE public.feature_flags SET enabled = true WHERE key = 'text_scale_v2';
  PERFORM pg_temp.env('production');
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 flag violation', pg_temp.red(v), ARRAY['no_flag_violations']);
  IF pg_temp.detail(v, 'no_flag_violations') IS DISTINCT FROM '["text_scale_v2"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 violation detail: %', pg_temp.detail(v, 'no_flag_violations');
  END IF;
  PERFORM pg_temp.env('');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'text_scale_v2';
  UPDATE private.flag_production_gates SET review_ref = 'W10-REVIEW-text_scale_v2' WHERE flag_key = 'text_scale_v2';
  PERFORM pg_temp.env('production');

  -- A pass the fake providers made still stands.
  INSERT INTO public.dating_age_verifications (user_id, age_method, age_result, challenge_age, age_vendor, age_decided_at)
  VALUES (pg_temp.id('04'), 'fae', 'pass', 25, 'fake', now());
  v := public.get_dating_launch_readiness();
  PERFORM pg_temp.expect('L2 fake pass', pg_temp.red(v), ARRAY['no_test_verifications']);
  IF pg_temp.detail(v, 'no_test_verifications') IS DISTINCT FROM '1'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 fake pass count: %', pg_temp.detail(v, 'no_test_verifications');
  END IF;
  UPDATE public.dating_age_verifications SET revoked_at = now(), revoke_reason = 'w10_fixture' WHERE user_id = pg_temp.id('04');
  PERFORM pg_temp.expect('L2 fake pass revoked', pg_temp.ready_red(), ARRAY[]::text[]);

  -- A same-gender purge left pending.
  INSERT INTO private.dating_kill_switch_pending (scope, last_sqlstate) VALUES ('GH', '40P01');
  PERFORM pg_temp.expect('L2 kill switch pending', pg_temp.ready_red(), ARRAY['kill_switch_clear']);
  DELETE FROM private.dating_kill_switch_pending WHERE scope = 'GH';

  -- The SLA alerts have nowhere to go.
  PERFORM set_config('app.settings.moderation_alert_webhook', '', true);
  PERFORM pg_temp.expect('L2 no SLA webhook', pg_temp.ready_red(), ARRAY['sla_alerts']);
  PERFORM set_config('app.settings.moderation_alert_webhook', 'https://alerts.example.invalid/w10', true);

  -- Support resources: one entry past 90 days, or none at all.
  UPDATE public.support_resources SET verified_at = current_date - 91 WHERE country_code = 'GH' AND verified_by = 'w10-fixture';
  PERFORM pg_temp.expect('L2 stale resource', pg_temp.ready_red(), ARRAY['resources:GH']);
  PERFORM pg_temp.expect('L2 one country asked', pg_temp.ready_red('gb'), ARRAY[]::text[]);
  UPDATE public.support_resources SET verified_at = current_date - 90 WHERE country_code = 'GH' AND verified_by = 'w10-fixture';
  PERFORM pg_temp.expect('L2 a resource at 90 days', pg_temp.ready_red(), ARRAY[]::text[]);
  UPDATE public.support_resources SET active = false WHERE country_code = 'GB';
  PERFORM pg_temp.expect('L2 no resource', pg_temp.ready_red(), ARRAY['resources:GB']);
  UPDATE public.support_resources SET active = true WHERE country_code = 'GB' AND verified_by = 'w10-fixture';

  -- An invalid country is refused, never read as Ghana and the UK.
  IF public.get_dating_launch_readiness('XX') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.get_dating_launch_readiness('GHA') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 an invalid country was read';
  END IF;
  PERFORM pg_temp.env('');
END $$;

-- The checklist as a row the gates read (p_row), each gap alone.
DO $$
DECLARE
  r public.country_safety_config := public.dating_country_config('GH');
  v jsonb;
BEGIN
  PERFORM pg_temp.env('production');
  r.legal_checklist := r.legal_checklist || '{"ghana_legal_opinion": "dev-opinion"}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 DEV- checklist', pg_temp.red(v), ARRAY['checklist:GH']);
  IF pg_temp.detail(v, 'checklist:GH') IS DISTINCT FROM '["dev_reference"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 checklist detail: %', pg_temp.detail(v, 'checklist:GH');
  END IF;
  r := public.dating_country_config('GB');
  r.legal_checklist := r.legal_checklist || '{"same_gender_reconsideration": {"legal_opinion": "DEV-opinion"}}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GB'], r));
  PERFORM pg_temp.expect('L2 nested DEV- reference', pg_temp.red(v), ARRAY['checklist:GB']);
  IF pg_temp.detail(v, 'checklist:GB') IS DISTINCT FROM '["dev_reference"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 nested checklist detail: %', pg_temp.detail(v, 'checklist:GB');
  END IF;
  r := public.dating_country_config('GH');
  r.legal_checklist := r.legal_checklist || '{"dpc_registration": null}';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 missing evidence', pg_temp.red(v), ARRAY['checklist:GH']);
  -- Fix round 1 (M-5): a no-break space first and a minus sign for the hyphen.
  r := public.dating_country_config('GH');
  r.legal_checklist := r.legal_checklist || jsonb_build_object('dpia', E'\u00a0dev\u2212dpia');
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 Unicode DEV- checklist', pg_temp.red(v), ARRAY['checklist:GH']);
  IF pg_temp.detail(v, 'checklist:GH') IS DISTINCT FROM '["dev_reference"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L2 Unicode checklist detail: %', pg_temp.detail(v, 'checklist:GH');
  END IF;
  r := public.dating_country_config('GH');
  r.resources_verified_at := now() - interval '91 days';
  v := jsonb_build_object('gates', private.dating_launch_gates(ARRAY['GH'], r));
  PERFORM pg_temp.expect('L2 row resources old', pg_temp.red(v), ARRAY['resources:GH']);
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L3: opening a place in production; reductions; DEV- in the checklist.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_version integer := (public.dating_country_config('GH')).version;
BEGIN
  PERFORM pg_temp.env('production');
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  v := public.publish_country_config('GH', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:launch_not_ready", "gates": ["age_assurance_live"]}'::jsonb
     AND pg_temp.logs_ok() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 Ghana opened while a gate was red: %', v;
  END IF;
  IF (public.dating_country_config('GH')).version <> v_version OR (public.dating_country_config('GH')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a refused opening published a version';
  END IF;
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  IF NOT pg_temp.logs_ok() THEN
    RAISE NOTICE 'dating_v2_launch_contracts: the server''s log settings are unsafe; the green opening is not checked here';
  ELSE
    -- The publish that opens may bring the last piece of evidence itself:
    -- the gates read the row it publishes, not the current one.
    PERFORM pg_temp.env('');
    PERFORM public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpc_registration": null}'));
    PERFORM pg_temp.env('production');
    v := public.publish_country_config('GH', '{"dating_enabled": true}'
                                             || pg_temp.checklist('GH', '{"dpc_registration": "DPC-REG-0001"}'));
    IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'dating_enabled')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 Ghana did not open with every gate green: %', v;
    END IF;
    IF public.get_dating_launch_readiness() -> 'open' IS DISTINCT FROM '["GH"]'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 open countries: %', public.get_dating_launch_readiness() -> 'open';
    END IF;
    -- A region newly open is an opening too.
    PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
    v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "CP"]}');
    IF v ->> 'reason' IS DISTINCT FROM 'config:launch_not_ready' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a region opened while a gate was red: %', v;
    END IF;
    -- A reduction is never refused: a region closed, then the country.
    v := public.publish_country_config('GH', '{"open_regions": ["AA"]}');
    IF (v ->> 'ok')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 narrowing was refused: %', v;
    END IF;
    v := public.publish_country_config('GH', '{"dating_enabled": false}');
    IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'dating_enabled')::boolean IS NOT FALSE THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L3 closing was refused: %', v;
    END IF;
    PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  END IF;

  -- A DEV- reference in the checklist: refused in production...
  v := public.publish_country_config('GH', '{"dating_enabled": true}' || pg_temp.checklist('GH', '{"dpia": "DEV-dpia"}'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed'
     OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a DEV- checklist reference was not refused in production: %', v;
  END IF;
  v := public.publish_country_config('GB', '{"dating_enabled": true}' || pg_temp.checklist('GB', '{"tier_review": " Dev-tier"}'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed' OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a padded dev- reference was not refused: %', v;
  END IF;
  -- ...reported, not enforced, in development.
  PERFORM pg_temp.env('');
  v := public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpia": "DEV-dpia"}'));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR NOT (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 development did not publish and report the DEV- reference: %', v;
  END IF;
  v := public.publish_country_config('GH', pg_temp.checklist('GH', '{"dpia": "DPIA-v3-SIGNED"}'));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v -> 'checks') ? 'dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a real reference still reads as DEV-: %', v;
  END IF;
END $$;

-- =====================================================================
-- L3 (fix round 1, M-3 and M-4): the other openings and reductions, on
-- the UK (Tier 3, same-gender on, every region open: open_regions NULL).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_regions constant jsonb := (public.dating_country_config('GB')).region_list;
  v_review constant jsonb := pg_temp.checklist('GB', '{"tier_review": "GB-TIER-REVIEW-2026-12"}');
BEGIN
  IF NOT pg_temp.logs_ok() THEN
    RAISE NOTICE 'dating_v2_launch_contracts: the server''s log settings are unsafe; L3''s UK cases are not checked here';
    RETURN;
  END IF;
  PERFORM pg_temp.env('production');
  v := public.publish_country_config('GB', '{"dating_enabled": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (public.dating_country_config('GB')).open_regions IS NOT NULL
     OR (public.dating_country_config('GB')).tier <> 3 OR NOT (public.dating_country_config('GB')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 the UK did not open in every region with every gate green: %', v;
  END IF;
  PERFORM set_config('app.settings.age_assurance_mode', 'sandbox', true);
  -- A region added to the list while every region is open is newly open.
  v := public.publish_country_config('GB', jsonb_build_object('region_list',
         v_regions || '[{"code": "ZZ", "sides": [], "name_key": "dating_region_gb_zz"}]'::jsonb));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:launch_not_ready", "gates": ["age_assurance_live"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a region added with open_regions NULL opened while a gate was red: %', v;
  END IF;
  -- Same-gender off (the kill switch) is a reduction: never refused.
  v := public.publish_country_config('GB', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'same_gender_enabled')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 same-gender off was refused: %', v;
  END IF;
  -- On again is an opening (M-4).
  v := public.publish_country_config('GB', '{"same_gender_enabled": true}');
  IF v ->> 'reason' IS DISTINCT FROM 'config:launch_not_ready' OR NOT (v -> 'gates') ? 'age_assurance_live' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 same-gender went on while a gate was red: %', v;
  END IF;
  -- A stricter tier is a reduction: never refused.
  v := public.publish_country_config('GB', '{"tier": 2}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (public.dating_country_config('GB')).tier <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a stricter tier was refused: %', v;
  END IF;
  -- A looser one, with its own review (the publisher's checks pass), is an opening (M-4).
  v := public.publish_country_config('GB', v_review || '{"tier": 3}');
  IF v ->> 'reason' IS DISTINCT FROM 'config:launch_not_ready' OR NOT (v -> 'gates') ? 'age_assurance_live' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 the tier loosened while a gate was red: %', v;
  END IF;
  IF (public.dating_country_config('GB')).tier <> 2 OR (public.dating_country_config('GB')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 a refused opening published a version';
  END IF;
  -- With every gate green both are published, then the UK closes.
  PERFORM set_config('app.settings.age_assurance_mode', 'live', true);
  v := public.publish_country_config('GB', v_review || '{"tier": 3}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (public.dating_country_config('GB')).tier <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 the tier did not loosen with every gate green: %', v;
  END IF;
  v := public.publish_country_config('GB', '{"same_gender_enabled": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'same_gender_enabled')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 same-gender did not go on with every gate green: %', v;
  END IF;
  v := public.publish_country_config('GB', '{"dating_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L3 closing the UK was refused: %', v;
  END IF;
  PERFORM pg_temp.env('');
END $$;

-- =====================================================================
-- L4: a gated flag's DEV- evidence is no evidence in production.
-- =====================================================================
DO $$
DECLARE
  v_msg text;
BEGIN
  -- Fix round 1 (M-5): the DEV- rule reads past Unicode spaces and treats
  -- a Unicode hyphen or dash as '-'; a blank of them is no reference.
  IF EXISTS (SELECT 1 FROM unnest(ARRAY[E'\u2010', E'\u2011', E'\u2012', E'\u2013', E'\u2014', E'\u2015',
                                        E'\u2212', E'\ufe63', E'\uff0d']) AS h(c)
              WHERE NOT private.is_dev_reference('dev' || h.c || 'x') OR private.is_real_reference('DEV' || h.c || 'x'))
     OR EXISTS (SELECT 1 FROM unnest(ARRAY[E'\u00a0', E'\u202f', E'\u200b', E'\ufeff']) AS s(c)
                 WHERE NOT private.is_dev_reference(s.c || E'\t' || s.c || 'DEV-x') OR private.is_real_reference(s.c || ' ' || s.c))
     OR private.is_dev_reference('W5-DEV-1') OR private.is_dev_reference('DEVX-1') OR NOT private.is_real_reference('W5-1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 the DEV- rule missed a Unicode space or dash (or read a real reference as DEV-)';
  END IF;
  PERFORM pg_temp.env('production');
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', E'\u00a0Dev\u2011launch')$q$);
  IF v_msg IS DISTINCT FROM 'flag:dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 Unicode DEV- evidence was recorded (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', 'DEV-launch')$q$);
  IF v_msg IS DISTINCT FROM 'flag:dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 DEV- evidence was recorded in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', E'\t dev-launch')$q$);
  IF v_msg IS DISTINCT FROM 'flag:dev_reference' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 padded dev- evidence was recorded (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- In development it is recorded (the dev project's own testing) ...
  PERFORM pg_temp.env('');
  v_msg := pg_temp.err($q$SELECT public.record_flag_gate_evidence('dating_mode_enabled', 'DEV-launch')$q$);
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 development refused DEV- evidence (got %)', v_msg;
  END IF;
  -- ... and in production it never lets the flag on.
  PERFORM pg_temp.env('production');
  v_msg := pg_temp.err($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 a flag went on in production on DEV- evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- Real evidence still lets it on (Spec 1's rule unchanged).
  PERFORM public.record_flag_gate_evidence('dating_mode_enabled', 'W10-LAUNCH-2026-12');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF EXISTS (SELECT 1 FROM public.production_flag_violations() AS x WHERE x = 'dating_mode_enabled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 real evidence still reads as a violation';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  -- Fix round 1 (M-2): a blank reference written straight into the table
  -- is none: the flag can't go on, and on from development it is listed.
  UPDATE private.flag_production_gates SET review_ref = E' \t' WHERE flag_key = 'dating_mode_enabled';
  v_msg := pg_temp.err($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 a flag went on in production on blank evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.env('');
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.env('production');
  IF NOT EXISTS (SELECT 1 FROM public.production_flag_violations() AS x WHERE x = 'dating_mode_enabled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L4 a flag on with blank evidence is not a violation';
  END IF;
  PERFORM pg_temp.env('');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  UPDATE private.flag_production_gates SET review_ref = 'W10-LAUNCH-2026-12' WHERE flag_key = 'dating_mode_enabled';
END $$;

-- =====================================================================
-- L5: the console's readiness, metrics and fairness (the safety owner's).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_before bigint;
BEGIN
  v_before := coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                         WHERE c.key = 'dating.moderation.not_moderator'), 0);
  IF public.moderation_launch_readiness(pg_temp.id('03'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('03'), 7) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('03'), 4) IS DISTINCT FROM '{"ok": false, "reason": "not_moderator"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 someone who is not a moderator was answered';
  END IF;
  IF coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                WHERE c.key = 'dating.moderation.not_moderator'), 0) <> v_before + 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a not_moderator refusal was not counted';
  END IF;
  IF public.moderation_launch_readiness(pg_temp.id('02'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('02'), 7) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('02'), 4) IS DISTINCT FROM '{"ok": false, "reason": "safety_owner_only"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a moderator read the safety owner''s pages';
  END IF;
  v := public.moderation_launch_readiness(pg_temp.id('01'), 'gh');
  IF v -> 'countries' IS DISTINCT FROM '["GH"]'::jsonb OR (v ->> 'ready')::boolean IS NOT FALSE
     OR pg_temp.red(v) IS DISTINCT FROM (CASE WHEN pg_temp.logs_ok() THEN ARRAY['environment']
                                              ELSE ARRAY['environment', 'log_settings_safe'] END) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the owner''s readiness: %', v;
  END IF;
  IF public.moderation_launch_readiness(pg_temp.id('01'), 'XX') IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 an invalid country was read';
  END IF;

  -- Metrics: dating.* keys summed over the window, shown at n >= 50.
  DELETE FROM public.metric_counters;
  INSERT INTO public.metric_counters (day, key, count) VALUES
    ((now() AT TIME ZONE 'utc')::date, 'dating.mutual', 30),
    ((now() AT TIME ZONE 'utc')::date - 6, 'dating.mutual', 20),
    ((now() AT TIME ZONE 'utc')::date - 7, 'dating.mutual', 1000),
    ((now() AT TIME ZONE 'utc')::date, 'dating.block', 49),
    ((now() AT TIME ZONE 'utc')::date, 'dating.activated', 75),
    ((now() AT TIME ZONE 'utc')::date, 'stories.viewed', 500);
  v := public.moderation_metrics(pg_temp.id('01'), 7);
  IF v -> 'metrics' IS DISTINCT FROM '[{"key": "dating.activated", "count": 75}, {"key": "dating.mutual", "count": 50}]'::jsonb
     OR (v ->> 'suppressed')::int IS DISTINCT FROM 1 OR (v ->> 'min_count')::int IS DISTINCT FROM 50
     OR (v ->> 'days')::int IS DISTINCT FROM 7
     OR (v ->> 'from')::date IS DISTINCT FROM (now() AT TIME ZONE 'utc')::date - 6
     OR (v ->> 'to')::date IS DISTINCT FROM (now() AT TIME ZONE 'utc')::date THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the 7-day metrics: %', v;
  END IF;
  v := public.moderation_metrics(pg_temp.id('01'), 28);
  IF v -> 'metrics' -> 1 IS DISTINCT FROM '{"key": "dating.mutual", "count": 1050}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the 28-day metrics: %', v;
  END IF;
  IF public.moderation_metrics(pg_temp.id('01'), 30) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.moderation_metrics(pg_temp.id('01'), NULL) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a window other than 7, 28 or 90 days was read';
  END IF;

  -- Fairness: the last weeks' reports, flagged cohorts first.
  DELETE FROM public.dating_fairness_reports;
  INSERT INTO public.dating_fairness_reports (week, country_code, cohort_key, active_bucket, introductions_per_active,
                                              mutual_rate, flagged) VALUES
    (current_date - 3, 'GH', 'gender:woman', '100–499', 2.10, 0.12, false),
    (current_date - 3, 'GH', 'region:AA', '100–499', 1.40, 0.09, true),
    (current_date - 10, 'GB', 'age:25_34', '50–99', 2.00, NULL, false),
    (current_date - 90, 'GH', 'top_decile', '500+', 9.00, 0.20, true);
  v := public.moderation_fairness(pg_temp.id('01'), 4);
  IF jsonb_array_length(v -> 'reports') <> 3 OR (v ->> 'flagged')::int <> 1
     OR v -> 'reports' -> 0 ->> 'cohort' IS DISTINCT FROM 'region:AA'
     OR v -> 'reports' -> 1 ->> 'cohort' IS DISTINCT FROM 'gender:woman'
     OR v -> 'reports' -> 2 ->> 'country' IS DISTINCT FROM 'GB'
     OR v -> 'reports' -> 2 -> 'mutual_rate' IS DISTINCT FROM 'null'::jsonb
     OR v -> 'reports' -> 0 ->> 'active' IS DISTINCT FROM '100–499' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 the fairness reports: %', v;
  END IF;
  IF public.moderation_fairness(pg_temp.id('01'), 0) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb
     OR public.moderation_fairness(pg_temp.id('01'), 13) IS DISTINCT FROM '{"ok": false, "reason": "invalid"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L5 a window outside 1-12 weeks was read';
  END IF;
END $$;

-- =====================================================================
-- L6: grants. The readiness and the console's reads are the service
-- role's alone; the helpers nobody's.
-- =====================================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.get_dating_launch_readiness(text)', 'public.moderation_launch_readiness(uuid,text)',
                           'public.moderation_metrics(uuid,integer)', 'public.moderation_fairness(uuid,integer)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
       OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L6 % is granted wrongly', f;
    END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['private.is_dev_reference(text)', 'private.is_real_reference(text)',
                           'private.dating_launch_gates(text[],public.country_safety_config)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
       OR has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: L6 % is granted to an API role', f;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.publish_country_config(text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: L6 a re-created function lost or gained a grant';
  END IF;
  RAISE NOTICE 'dating_v2_launch_contracts: all held';
END $$;

ROLLBACK;
