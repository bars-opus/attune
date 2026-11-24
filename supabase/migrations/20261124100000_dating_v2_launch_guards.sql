-- Spec 2 W10, migration 1 (§8 W10, §4.9 W10, §2.2, §3.3.5, §5.9, §6.4,
-- §6.9; R-6, Q19b): dating_v2_launch_guards.
--   * private.is_dev_reference(text) and private.is_real_reference(text):
--     the one rule for a DEV- reference (W5a's) and for real evidence.
--   * Production-mode guards. They apply only while
--     private.attune_environment() reads 'production'; nothing here sets
--     it (R-6), and no flag or country is turned on.
--     - checklist: country_config_checks also reports dev_reference for a
--       DEV- reference anywhere in legal_checklist, so publish_country_config
--       refuses it in production (a reduction is still published, W1d);
--     - DEV- refs: a gated flag's DEV- (or blank) evidence is no evidence there (the
--       gate trigger, production_flag_violations), and
--       record_flag_gate_evidence refuses one (flag:dev_reference);
--     - provider mode and the rest: a publish that opens a place (the
--       country, or a region newly open) or, with Dating on, turns
--       same-gender matching on or loosens the tier is refused with
--       config:launch_not_ready and the red gates unless the launch gates
--       for that country are green (age_assurance_mode 'live', the safety
--       owner and a moderator active, no DEV- reference active, ...).
--   * get_dating_launch_readiness(p_country) (service role): every gate,
--     ready only when all are green, so never in development.
--   * The console's readiness and dashboards, the safety owner's:
--     moderation_launch_readiness, moderation_metrics (dating.* counters at
--     n >= 50, §6.9) and moderation_fairness (§5.9).
-- Re-created from their LIVE bodies, changed lines marked -- Spec 2 W10:
-- private.guard_flag_production_gate, public.record_flag_gate_evidence,
-- public.production_flag_violations, private.country_config_checks,
-- public.publish_country_config (their grants are kept).
-- Grants in 20261124100010_dating_v2_launch_guards_grants.sql. Ends by
-- revoking everything it creates from every API role (the W6 final
-- pattern: a push that stops between this file and its twin fails closed).
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- 1. A development reference (W5a's rule, fix round 1 M-7: 'DEV-' in any
--    case, after any padding) and a reference that counts as evidence.
--    W10 fix round 1 (M-5): the padding includes the no-break, narrow
--    no-break and zero-width spaces and the byte-order mark, and a Unicode
--    hyphen or dash (U+2010-2015, U+2212, U+FE63, U+FF0D) reads as '-'.
--    (W5a's and W6b's config triggers keep their own ASCII rule; the
--    readiness reads their active rows with this one.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.is_dev_reference(p_ref text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(pg_catalog.upper(
           pg_catalog.translate(
             pg_catalog.btrim(p_ref, E' \t\r\n\u00a0\u202f\u200b\ufeff'),
             E'\u2010\u2011\u2012\u2013\u2014\u2015\u2212\ufe63\uff0d', '---------')) LIKE 'DEV-%', false);
$$;

CREATE OR REPLACE FUNCTION private.is_real_reference(p_ref text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT coalesce(pg_catalog.btrim(p_ref, E' \t\r\n\u00a0\u202f\u200b\ufeff') <> '', false)
         AND NOT private.is_dev_reference(p_ref);
$$;

-- ---------------------------------------------------------------------
-- 2. The launch gates (§8 W10's gate line and every earlier wave's
--    machine-checkable one). One row per gate: {gate, ok} and, where it
--    helps the owner, detail (what is red). p_row, when given, stands in
--    for the current row of its country (publish_country_config checks the
--    row it is about to publish). W9 is read only through its flag's gate
--    row (dating_couple_link, a string), so W9 not applied reads red,
--    never an error; the export function is never named (the canary's S-4
--    scan follows names, and it decrypts).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.dating_launch_gates(p_countries text[],
                                                       p_row public.country_safety_config DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- Every flag Dating's launch turns on (W11's dating_voice_calls is not
  -- created yet and is not a launch flag), and the Spec 1 flags Dating
  -- needs on with it (Get help's directory, inline CSAM hashing).
  v_flags constant text[] := ARRAY['dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
    'dating_profile_photos', 'dating_same_gender_matching', 'dating_age_assurance', 'dating_traveller_detection',
    'dating_couple_link', 'support_resources_v2', 'csam_hash_matching'];
  v_h constant jsonb := public.get_dating_operational_health();
  v_gates jsonb := '[]'::jsonb;
  v_red text[];
  v_n integer;
  v_code text;
  v_row public.country_safety_config;
BEGIN
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    -- R-6: red until the owner has set the project to production mode.
    pg_catalog.jsonb_build_object('gate', 'environment', 'ok', private.attune_environment() = 'production'),
    -- §3.3.5: real verification (never fake, never sandbox).
    pg_catalog.jsonb_build_object('gate', 'age_assurance_live', 'ok', private.dating_verification_mode() = 'live'),
    -- W7: a safety owner and a moderator, both active.
    pg_catalog.jsonb_build_object('gate', 'safety_owner', 'ok',
      EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'safety_owner')),
    pg_catalog.jsonb_build_object('gate', 'moderator', 'ok',
      EXISTS (SELECT 1 FROM public.dating_moderators AS m WHERE m.active AND m.role = 'moderator')),
    -- W1, W5, W6: the three keys set and their fingerprints seeded.
    pg_catalog.jsonb_build_object('gate', 'keys', 'ok',
      coalesce((v_h ->> 'exclusion_key_fingerprint_ok')::boolean, false)
      AND coalesce((v_h ->> 'field_key_fingerprint_ok')::boolean, false)
      AND coalesce(public.app_setting('dating_push_key'), '') <> ''),
    -- W5 gate: the introductions config active with real review references.
    pg_catalog.jsonb_build_object('gate', 'introductions_config', 'ok',
      EXISTS (SELECT 1 FROM public.dating_algorithm_configs AS c WHERE c.state = 'active')
      AND NOT EXISTS (SELECT 1 FROM public.dating_algorithm_configs AS c
                       WHERE c.state = 'active'
                         AND NOT (private.is_real_reference(c.product_review_ref)
                                  AND private.is_real_reference(c.clinical_review_ref)
                                  AND private.is_real_reference(c.fairness_review_ref)
                                  AND private.is_real_reference(c.safety_review_ref)))),
    -- W6 gate: the chat's lexicon active with the reviewers' reference.
    pg_catalog.jsonb_build_object('gate', 'chat_config', 'ok',
      EXISTS (SELECT 1 FROM public.dating_safety_configs AS c WHERE c.state = 'active')
      AND NOT EXISTS (SELECT 1 FROM public.dating_safety_configs AS c
                       WHERE c.state = 'active' AND NOT private.is_real_reference(c.review_ref))));

  -- Each launch flag has its production gate row with real evidence.
  v_red := ARRAY(SELECT f.key FROM unnest(v_flags) AS f(key)
                  WHERE NOT EXISTS (SELECT 1 FROM private.flag_production_gates AS g
                                     WHERE g.flag_key = f.key AND private.is_real_reference(g.review_ref))
                  ORDER BY f.key);
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'flag_evidence', 'ok', cardinality(v_red) = 0, 'detail', to_jsonb(v_red)));
  -- No gated flag (any spec's) is on without real evidence.
  v_red := ARRAY(SELECT v FROM public.production_flag_violations() AS v ORDER BY v);
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'no_flag_violations', 'ok', cardinality(v_red) = 0, 'detail', to_jsonb(v_red)));
  -- No age or identity pass made by the fake providers still stands.
  SELECT count(*) INTO v_n FROM public.dating_age_verifications AS v
   WHERE v.revoked_at IS NULL AND (v.age_vendor = 'fake' OR v.identity_vendor = 'fake');
  v_gates := v_gates || pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('gate', 'no_test_verifications', 'ok', v_n = 0, 'detail', v_n),
    -- W1d: no same-gender purge left pending.
    pg_catalog.jsonb_build_object('gate', 'kill_switch_clear', 'ok',
      coalesce(pg_catalog.jsonb_array_length(v_h -> 'kill_switch_pending'), 1) = 0),
    -- W1d (§2.4): nothing can write an RPC's parameters to the log.
    pg_catalog.jsonb_build_object('gate', 'log_settings_safe', 'ok', coalesce((v_h ->> 'log_settings_safe')::boolean, false)),
    -- W7: the SLA alerts have somewhere to go.
    pg_catalog.jsonb_build_object('gate', 'sla_alerts', 'ok',
      coalesce(public.app_setting('moderation_alert_webhook'), '') <> ''));

  -- Per country: the checklist complete with real references (§2.2, as
  -- the publisher checks a row with Dating on; never its name here: the
  -- canary's S-4 scan follows names), and the support
  -- resources verified within 90 days (the row's date and every active
  -- entry of Spec 1's directory for the country, at least one).
  FOREACH v_code IN ARRAY coalesce(p_countries, ARRAY[]::text[]) LOOP
    v_row := CASE WHEN (p_row).country_code IS NOT DISTINCT FROM v_code THEN p_row
                  ELSE public.dating_country_config(v_code) END;
    v_row.dating_enabled := true;
    -- (the resources and the keys are gates of their own)
    v_red := ARRAY(SELECT c FROM unnest(private.country_config_checks(v_row)) AS c
                    WHERE c NOT IN ('resources_not_verified', 'exclusion_key_not_ready', 'field_key_not_ready')
                    ORDER BY c);
    v_gates := v_gates || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object('gate', 'checklist:' || v_code, 'ok', cardinality(v_red) = 0,
                                    'detail', to_jsonb(v_red)),
      pg_catalog.jsonb_build_object('gate', 'resources:' || v_code, 'ok',
        coalesce(v_row.resources_verified_at >= now() - interval '90 days', false)
        AND EXISTS (SELECT 1 FROM public.support_resources AS s WHERE s.country_code = v_code AND s.active)
        AND NOT EXISTS (SELECT 1 FROM public.support_resources AS s
                         WHERE s.country_code = v_code AND s.active
                           AND (s.verified_at IS NULL OR s.verified_at < current_date - 90))));
  END LOOP;
  RETURN v_gates;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. The readiness (service role: the owner from the SQL editor, the
--    console through moderation_launch_readiness). ready only when every
--    gate is green, so never while the project reads development (R-6).
--    Ghana and the UK unless one country is asked for.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_dating_launch_readiness(p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code constant text := upper(btrim(coalesce(p_country, '')));
  v_countries text[];
  v_gates jsonb;
BEGIN
  IF p_country IS NULL THEN
    v_countries := ARRAY['GH', 'GB'];
  ELSIF v_code ~ '^[A-Z]{2}$' AND private.dating_iso_country(v_code) IS NOT NULL THEN
    v_countries := ARRAY[v_code];
  ELSE
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_gates := private.dating_launch_gates(v_countries);
  RETURN pg_catalog.jsonb_build_object('ok', true,
    'ready', NOT EXISTS (SELECT 1 FROM pg_catalog.jsonb_array_elements(v_gates) AS g
                          WHERE (g ->> 'ok')::boolean IS NOT TRUE),
    'environment', private.attune_environment(),
    'countries', to_jsonb(v_countries),
    'open', to_jsonb(ARRAY(SELECT c FROM unnest(v_countries) AS c
                            WHERE (public.dating_country_config(c)).dating_enabled ORDER BY c)),
    'gates', v_gates);
END;
$$;

-- ---------------------------------------------------------------------
-- 4. The console's readiness and dashboards (§6.4, §6.9, §5.9): the safety
--    owner's (a moderator gets safety_owner_only; anyone else
--    not_moderator, counted). Reads, never audited, as the other lists.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.moderation_launch_readiness(p_actor uuid, p_country text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  RETURN public.get_dating_launch_readiness(p_country);
END;
$$;

-- §6.9: every dating.* counter summed over the last 7, 28 or 90 UTC days,
-- shown only at n >= 50 (the rest are counted, never named).
CREATE OR REPLACE FUNCTION public.moderation_metrics(p_actor uuid, p_days integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
  v_to constant date := (now() AT TIME ZONE 'utc')::date;
  v_from date;
  v jsonb;
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_days IS NULL OR p_days NOT IN (7, 28, 90) THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  v_from := v_to - (p_days - 1);
  SELECT pg_catalog.jsonb_build_object('ok', true, 'days', p_days, 'from', v_from, 'to', v_to, 'min_count', 50,
           'metrics', coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('key', x.key, 'count', x.n)
                                                    ORDER BY x.key) FILTER (WHERE x.n >= 50), '[]'::jsonb),
           'suppressed', count(*) FILTER (WHERE x.n < 50))
    INTO v
    FROM (SELECT c.key, sum(c.count) AS n
            FROM public.metric_counters AS c
           WHERE c.day BETWEEN v_from AND v_to AND left(c.key, 7) = 'dating.'
           GROUP BY c.key) AS x;
  RETURN v;
END;
$$;

-- §5.9: the weekly fairness reports of the last 1-12 weeks (rows exist
-- only for n >= 50), flagged cohorts first.
CREATE OR REPLACE FUNCTION public.moderation_fairness(p_actor uuid, p_weeks integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_mod public.dating_moderators := private.dating_moderator(p_actor);
BEGIN
  IF v_mod.user_id IS NULL THEN
    PERFORM private.bump_metric_internal('dating.moderation.not_moderator');
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_moderator');
  END IF;
  IF v_mod.role <> 'safety_owner' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'safety_owner_only');
  END IF;
  IF p_weeks IS NULL OR p_weeks NOT BETWEEN 1 AND 12 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'invalid');
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'weeks', p_weeks,
    'flagged', (SELECT count(*) FROM public.dating_fairness_reports AS r
                 WHERE r.flagged AND r.week > current_date - 7 * p_weeks),
    'reports', coalesce((
      SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('week', r.week, 'country', r.country_code,
               'cohort', r.cohort_key, 'active', r.active_bucket,
               'introductions_per_active', r.introductions_per_active, 'mutual_rate', r.mutual_rate,
               'flagged', r.flagged)
             ORDER BY r.flagged DESC, r.week DESC, r.country_code, r.cohort_key)
        FROM public.dating_fairness_reports AS r
       WHERE r.week > current_date - 7 * p_weeks), '[]'::jsonb));
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Re-created from their LIVE bodies (changed lines marked -- Spec 2 W10).
-- ---------------------------------------------------------------------

-- private.guard_flag_production_gate()
CREATE OR REPLACE FUNCTION private.guard_flag_production_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.enabled
     AND private.attune_environment() = 'production'
     AND EXISTS (SELECT 1 FROM private.flag_production_gates AS g
                  WHERE g.flag_key = NEW.key -- Spec 2 W10
                    AND NOT private.is_real_reference(g.review_ref)) THEN -- Spec 2 W10: a DEV- or blank reference is none
    RAISE EXCEPTION 'flag:gate_evidence_required';
  END IF;
  RETURN NEW;
END;
$function$
;

-- public.record_flag_gate_evidence(text,text)
CREATE OR REPLACE FUNCTION public.record_flag_gate_evidence(p_flag text, p_review_ref text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF p_review_ref IS NULL OR btrim(p_review_ref) = '' THEN
    RAISE EXCEPTION 'flag:review_ref_required';
  END IF;
  -- Spec 2 W10 (§8 W10): in production a DEV- reference is no evidence.
  IF private.attune_environment() = 'production' AND private.is_dev_reference(p_review_ref) THEN -- Spec 2 W10
    RAISE EXCEPTION 'flag:dev_reference'; -- Spec 2 W10
  END IF; -- Spec 2 W10
  UPDATE private.flag_production_gates AS g
     SET review_ref = btrim(p_review_ref),
         recorded_by = coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                                session_user::text),
         recorded_at = now()
   WHERE g.flag_key = p_flag;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'flag:not_gated';
  END IF;
END;
$function$
;

-- public.production_flag_violations()
CREATE OR REPLACE FUNCTION public.production_flag_violations()
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT g.flag_key
    FROM private.flag_production_gates AS g
    JOIN public.feature_flags AS f ON f.key = g.flag_key
   WHERE f.enabled AND NOT private.is_real_reference(g.review_ref) -- Spec 2 W10: a DEV- or blank reference is none
   ORDER BY g.flag_key;
$function$
;

-- private.country_config_checks(public.country_safety_config)
CREATE OR REPLACE FUNCTION private.country_config_checks(p_row country_safety_config)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE
  v_checks text[] := ARRAY[]::text[];
  v_sg jsonb := p_row.legal_checklist -> 'same_gender_reconsideration';
BEGIN
  IF coalesce(p_row.dating_enabled, true) THEN
    IF coalesce(p_row.legal_checklist, '{}'::jsonb) = '{}'::jsonb
       -- I-3: every country needs the baseline references, whatever else
       -- its checklist holds.
       OR NOT (coalesce(p_row.legal_checklist, '{}'::jsonb)
               ?& ARRAY['dpia', 'pen_test', 'safety_owner_and_moderator', 'reviewer_signoffs'])
       OR EXISTS (SELECT 1 FROM jsonb_each(p_row.legal_checklist) AS e
                   WHERE e.key <> 'same_gender_reconsideration'
                     AND (jsonb_typeof(e.value) <> 'string' OR btrim(e.value #>> '{}') = '')) THEN
      v_checks := array_append(v_checks, 'evidence_missing');
    END IF;
    IF p_row.resources_verified_at IS NULL OR p_row.resources_verified_at < now() - interval '90 days' THEN
      v_checks := array_append(v_checks, 'resources_not_verified');
    END IF;
    -- Spec 2 W1b (batch-2 carry, I-5): Dating opens only under a set key
    -- Spec 2 W1b whose stored fingerprint matches it (no key, no stored
    -- Spec 2 W1b fingerprint or a rotated key: not ready).
    IF private.dating_exclusion_key_ready() IS NOT TRUE THEN -- Spec 2 W1b
      v_checks := array_append(v_checks, 'exclusion_key_not_ready'); -- Spec 2 W1b
    END IF; -- Spec 2 W1b
    -- Spec 2 W1d (batch-10 carry): and under a field key whose stored
    -- Spec 2 W1d fingerprint matches it (none, unseeded or replaced: not ready).
    IF private.dating_field_key_ready() IS NOT TRUE THEN -- Spec 2 W1d
      v_checks := array_append(v_checks, 'field_key_not_ready'); -- Spec 2 W1d
    END IF; -- Spec 2 W1d
  END IF;
  IF coalesce(p_row.same_gender_enabled, true) AND coalesce(p_row.tier, 1) IN (1, 2)
     AND (jsonb_typeof(v_sg) IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['legal_opinion', 'lgbtq_consultation', 'tier1_protections']) AS k(key)
                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN
    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  -- Spec 2 W10 (§8 W10): a DEV- reference is never evidence, at any level of the
  -- Spec 2 W10 checklist (the same-gender reconsideration's too).
  IF EXISTS (SELECT 1 FROM jsonb_each(coalesce(p_row.legal_checklist, '{}'::jsonb)) AS e -- Spec 2 W10
              WHERE (jsonb_typeof(e.value) = 'string' AND private.is_dev_reference(e.value #>> '{}')) -- Spec 2 W10
                 OR (jsonb_typeof(e.value) = 'object' -- Spec 2 W10
                     AND EXISTS (SELECT 1 FROM jsonb_each(e.value) AS s -- Spec 2 W10
                                  WHERE jsonb_typeof(s.value) = 'string' -- Spec 2 W10
                                    AND private.is_dev_reference(s.value #>> '{}')))) THEN -- Spec 2 W10
    v_checks := array_append(v_checks, 'dev_reference'); -- Spec 2 W10
  END IF; -- Spec 2 W10
  RETURN v_checks;
END;
$function$
;

-- public.publish_country_config(text,jsonb)
CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v_allowed constant text[] := ARRAY['tier', 'dating_enabled', 'open_regions', 'same_gender_enabled',
    'region_list', 'faith_list', 'id_documents', 'generation_hour_utc', 'reference_tz',
    'resources_verified_at', 'legal_checklist', 'source_url', 'reviewed_at', 'reviewed_by', 'published_by'];
  v_old public.country_safety_config;
  v_new public.country_safety_config;
  v_codes text[];
  v_checks text[];
  v_check_row public.country_safety_config; -- I-2
  v_switch boolean; -- Spec 2 W1d
  v_affected integer; -- Spec 2 W1d
  v_closing boolean; -- Spec 2 W1d (PF-F1, batch-5 M-3)
  v_open_old text[]; -- Spec 2 W1d
  v_open_new text[]; -- Spec 2 W1d
  v_try integer; -- Spec 2 W1d (fix round 1, I-2)
  v_failed text; -- Spec 2 W1d (fix round 1, I-1)
  v_told integer; -- Spec 2 W3a
  v_red text[]; -- Spec 2 W10
BEGIN
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN -- I-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_country');
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:unknown_key');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  SELECT * INTO v_old FROM public.country_safety_config AS c
   WHERE c.country_code = v_code AND c.is_current FOR UPDATE;
  IF NOT FOUND THEN
    v_old := public.dating_country_config(v_code);
  END IF;

  BEGIN
    v_new := jsonb_populate_record(v_old, p_values - 'open_regions');
    IF p_values ? 'open_regions' THEN
      v_new.open_regions := CASE WHEN jsonb_typeof(p_values -> 'open_regions') = 'null' THEN NULL
                                 ELSE ARRAY(SELECT DISTINCT e FROM jsonb_array_elements_text(p_values -> 'open_regions') AS e
                                             ORDER BY e) END; -- M-2: deduplicated
    END IF;
  EXCEPTION WHEN data_exception OR invalid_text_representation OR datatype_mismatch THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END;
  v_new.country_code := v_code;
  v_new.version := v_old.version + 1;
  v_new.is_current := true;
  v_new.published_at := now();
  v_new.published_by := coalesce(nullif(btrim(p_values ->> 'published_by'), ''), 'service_role');
  -- M-3: a country first published as Tier 1/2 starts same-gender off.
  IF v_old.version = 0 AND v_new.tier IN (1, 2) AND NOT p_values ? 'same_gender_enabled' THEN
    v_new.same_gender_enabled := false;
  END IF;

  IF v_new.tier IS NULL OR v_new.tier NOT BETWEEN 1 AND 3
     OR v_new.dating_enabled IS NULL OR v_new.same_gender_enabled IS NULL
     OR v_new.generation_hour_utc IS NULL OR v_new.generation_hour_utc NOT BETWEEN 0 AND 23
     OR v_new.resources_verified_at > now() + interval '1 day' THEN -- M-1
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_new.reference_tz) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_tz');
  END IF;
  IF jsonb_typeof(v_new.region_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.faith_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.id_documents) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.legal_checklist) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_new.region_list) AS r
                 WHERE jsonb_typeof(r) <> 'object' OR coalesce(r ->> 'code', '') !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_lists');
  END IF;
  -- I-3: the checklist only grows (a dropped key is a dropped obligation).
  IF NOT (v_new.legal_checklist ?& ARRAY(SELECT jsonb_object_keys(v_old.legal_checklist))) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:checklist_keys_removed');
  END IF;
  v_codes := ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_new.region_list) AS r);
  IF cardinality(v_codes) <> (SELECT count(DISTINCT c) FROM unnest(v_codes) AS c)
     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes)
     OR (v_new.dating_enabled AND cardinality(v_new.open_regions) = 0) THEN -- M-2: open in no region
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_regions');
  END IF;
  -- Spec 2 W1d (PF-F1, batch-5 M-3): an exposure-reducing publish (closing,
  -- Spec 2 W1d narrowing the open regions, tightening the tier, same-gender
  -- Spec 2 W1d off) widens nothing and adds no ID document; a safety
  -- Spec 2 W1d change is never refused for unrelated lapsed evidence.
  v_open_old := CASE WHEN v_old.dating_enabled IS TRUE -- Spec 2 W1d
                     THEN coalesce(v_old.open_regions, ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_old.region_list) AS r)) -- Spec 2 W1d
                     ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_open_new := CASE WHEN v_new.dating_enabled THEN coalesce(v_new.open_regions, v_codes) ELSE ARRAY[]::text[] END; -- Spec 2 W1d
  v_closing := v_old.version >= 1 -- Spec 2 W1d
    AND coalesce(v_open_new <@ v_open_old, false) -- Spec 2 W1d: no region newly open
    AND NOT (v_new.dating_enabled AND v_old.dating_enabled IS NOT TRUE) -- Spec 2 W1d
    AND v_new.tier <= v_old.tier -- Spec 2 W1d: 1 is the strictest
    AND NOT (v_new.same_gender_enabled AND v_old.same_gender_enabled IS NOT TRUE) -- Spec 2 W1d
    AND coalesce(v_old.id_documents @> v_new.id_documents, false) -- Spec 2 W1d: no ID document added (fix round 1, M-8)
    AND ((v_old.dating_enabled IS TRUE AND NOT v_new.dating_enabled) -- Spec 2 W1d: and something is reduced
         OR NOT coalesce(v_open_old <@ v_open_new, false) -- Spec 2 W1d
         OR v_new.tier < v_old.tier -- Spec 2 W1d
         OR NOT coalesce(v_new.id_documents @> v_old.id_documents, false) -- Spec 2 W1d: an ID document removed (fix round 1, M-8)
         OR (v_old.same_gender_enabled IS TRUE AND NOT v_new.same_gender_enabled)); -- Spec 2 W1d
  v_closing := coalesce(v_closing, false); -- Spec 2 W1d
  -- M-4: a country that restricts anything needs its calling code, or the
  -- phone fallback can't see it.
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled)
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code)
     AND NOT v_closing THEN -- Spec 2 W1d: a reduction is still published (reported below)
    RETURN jsonb_build_object('ok', false, 'reason', 'config:no_calling_code');
  END IF;

  -- Same-gender off: the kill switch runs in this transaction (§2.4).
  -- (Not for a country with no row yet: nobody can have it as their Dating country. M-3)
  v_switch := v_old.version >= 1 AND v_old.same_gender_enabled AND NOT v_new.same_gender_enabled; -- Spec 2 W1d

  -- I-2: the reconsideration is checked at the stricter of the old and new
  -- tiers, and a downgrade needs its own review reference.
  v_check_row := v_new;
  v_check_row.tier := least(v_old.tier, v_new.tier);
  v_checks := private.country_config_checks(v_check_row);
  IF v_old.version >= 1 AND v_new.tier > v_old.tier
     AND (jsonb_typeof(v_new.legal_checklist -> 'tier_review') IS DISTINCT FROM 'string'
          OR btrim(v_new.legal_checklist ->> 'tier_review') = ''
          OR v_new.legal_checklist -> 'tier_review' IS NOT DISTINCT FROM v_old.legal_checklist -> 'tier_review') THEN -- W1 final fix (M-7): each downgrade its own review
    v_checks := array_append(v_checks, 'tier_review_missing');
  END IF;
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled) -- Spec 2 W1d
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code) THEN -- Spec 2 W1d
    v_checks := array_append(v_checks, 'no_calling_code'); -- Spec 2 W1d: only a reduction gets here
  END IF; -- Spec 2 W1d
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production'
     AND NOT v_closing THEN -- Spec 2 W1d (PF-F1): the checks are still returned
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;
  -- Spec 2 W10 (§8 W10): in production a publish that opens a place (the country,
  -- Spec 2 W10 or a region newly open) needs the launch gates green for the row it
  -- Spec 2 W10 publishes; a reduction opens nothing, so it is never refused here.
  -- Spec 2 W10 (fix round 1, M-4): so does one that, with Dating on, turns
  -- Spec 2 W10 same-gender matching on or loosens the tier (1 is the strictest).
  IF private.attune_environment() = 'production' AND v_new.dating_enabled -- Spec 2 W10
     AND (NOT coalesce(v_open_new <@ v_open_old, false) -- Spec 2 W10: a region newly open
          OR (v_new.same_gender_enabled AND v_old.same_gender_enabled IS NOT TRUE) -- Spec 2 W10: same-gender on
          OR NOT coalesce(v_new.tier <= v_old.tier, false)) THEN -- Spec 2 W10: the tier loosened
    v_red := ARRAY(SELECT g ->> 'gate' FROM jsonb_array_elements(private.dating_launch_gates(ARRAY[v_code], v_new)) AS g -- Spec 2 W10
                    WHERE (g ->> 'ok')::boolean IS NOT TRUE ORDER BY 1); -- Spec 2 W10
    IF cardinality(v_red) > 0 THEN -- Spec 2 W10
      RETURN jsonb_build_object('ok', false, 'reason', 'config:launch_not_ready', 'gates', to_jsonb(v_red)); -- Spec 2 W10
    END IF; -- Spec 2 W10
  END IF; -- Spec 2 W10

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  IF v_switch THEN -- Spec 2 W1d
    -- Spec 2 W1d: the switch is published even if the purge can't run; a
    -- Spec 2 W1d deadlock or lock timeout is retried (fix round 1, I-2), and a
    -- Spec 2 W1d purge that still fails is left pending, visibly (I-1).
    FOR v_try IN 1..3 LOOP -- Spec 2 W1d
      BEGIN -- Spec 2 W1d
        v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d
        v_failed := NULL; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d: its locks are released; the other side finishes; try again
        EXIT WHEN SQLERRM = 'dating:busy'; -- W1 final fix (N-M3): an inner retry already ran
      WHEN OTHERS THEN -- Spec 2 W1d
        v_failed := SQLSTATE; -- Spec 2 W1d
        EXIT; -- Spec 2 W1d
      END; -- Spec 2 W1d
    END LOOP; -- Spec 2 W1d
    IF v_failed IS NOT NULL THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d
      PERFORM private.dating_kill_switch_mark(v_code, v_failed); -- Spec 2 W1d
      RAISE WARNING 'publish_country_config:kill_switch_pending:%; re-run select public.apply_same_gender_switch(''%'');', v_failed, v_code; -- Spec 2 W1d
    END IF; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  -- Spec 2 W3a (fix round 1, M-7): after the kill switch, so notice rows
  -- Spec 2 W3a are locked last, as exit locks them (no lock cycle).
  -- Spec 2 W3a (§2.7, R-6): "Tell me when it's here": every pending
  -- Spec 2 W3a request whose place is open after this publish is told once,
  -- Spec 2 W3a then forgotten (fix round 2, RR1-I1). A failure here never
  -- Spec 2 W3a stops the publish (its requests stay for the next publish
  -- Spec 2 W3a that leaves the place open).
  IF v_new.dating_enabled THEN -- Spec 2 W3a
    BEGIN -- Spec 2 W3a
      v_told := private.dating_notify_opened(v_code, v_old.dating_enabled IS TRUE, v_open_old, v_open_new); -- Spec 2 W3a
    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3a
      v_told := NULL; -- Spec 2 W3a
      BEGIN PERFORM private.bump_metric_internal('dating.notify.queue_failed'); EXCEPTION WHEN OTHERS THEN NULL; END; -- Spec 2 W3a
    END; -- Spec 2 W3a
  END IF; -- Spec 2 W3a
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks))
         || CASE WHEN v_switch THEN jsonb_build_object('switched', true, 'affected', v_affected) -- Spec 2 W1d
                 ELSE '{}'::jsonb END -- Spec 2 W1d
         || CASE WHEN v_failed IS NOT NULL THEN jsonb_build_object('pending_sqlstate', v_failed) -- Spec 2 W1d (I-1)
                 ELSE '{}'::jsonb END -- Spec 2 W1d -- Spec 2 W3a (no semicolon)
         || CASE WHEN coalesce(v_told, 0) > 0 THEN jsonb_build_object('notified', v_told) -- Spec 2 W3a
                 ELSE '{}'::jsonb END; -- Spec 2 W3a
END;
$function$
;

-- ---------------------------------------------------------------------
-- Self-revoke (the W6 final pattern); the twin grants.
-- ---------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  private.is_dev_reference(text), private.is_real_reference(text),
  private.dating_launch_gates(text[], public.country_safety_config),
  public.get_dating_launch_readiness(text),
  public.moderation_launch_readiness(uuid, text), public.moderation_metrics(uuid, integer),
  public.moderation_fairness(uuid, integer)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
