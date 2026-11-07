-- Spec 2 W1b, migration 4 (spec §4.9 W1b #1, §2.2, §2.3, §2.7; Q1, Q2,
-- Q19b, R-6, I-3): the country model.
--   * country_safety_config: versioned, one current row per country, a
--     published row never changes (only is_current true -> false, by the
--     publisher), never deleted. Seeds: GH (tier 1, Greater Accra + Ashanti
--     open, men-women only, 16 regions, sides), GB (tier 3, 12 ITL1
--     regions, same-gender on) and every Tier 1 and Tier 2 country of
--     research 04 §2.1.6 (same-gender off). EVERY seed has dating_enabled
--     false: a migration never switches anything on (R-6); the dev script
--     opens GH and GB in development.
--   * dating_country_config(code): the current row, or the default for a
--     country with none (tier 3, Dating closed, same-gender allowed).
--   * publish_country_config(code, values) (service role): merges values
--     over the current row and publishes the next version. In production
--     mode (Spec 1's private.attune_environment()) it refuses Dating on
--     without every legal_checklist evidence reference and support
--     resources verified within 90 days, and refuses same-gender on for a
--     Tier 1/2 row without the reconsideration references; in development
--     the same checks are returned, not enforced. Turning same-gender off
--     returns config:kill_switch_pending and publishes nothing (W1d wires
--     apply_same_gender_switch); W3a adds the notify queueing.
--   * get_dating_availability() (anon and signed in): the open countries
--     and their open regions.
--   * dating_session_context (one overwritten row per user, no country
--     codes), dating_effective_context(...) and record_dating_session_context
--     (service role; called by W8b's dating-device-check).
--   * dating_notify_requests (table only; RPCs in W3a).
--   * Flag dating_same_gender_matching (false), and a production gate row
--     for it and for every existing Dating flag.
--   * Spec 1's seam private.dating_open_countries() re-created from its live
--     body (20261025100400) to read the table (same shape: sorted alpha-2
--     codes), then the interim app_public_config row deleted (I-3).
--     get_public_app_config() is not touched.
--   * Fix round 1 (batch-4 review): the service role only reads the table
--     (C-1); a country with rows but no current row reads closed, Tier 1,
--     same-gender off, and a transaction may not end that way (C-1); only
--     assigned ISO 3166-1 codes count as countries (I-1); a tier downgrade
--     keeps the Tier 1/2 reconsideration and needs a tier review (I-2); the
--     legal checklist only grows and needs a baseline (I-3); plus M-1..M-6,
--     M-9 (see the batch-4 report).
-- Grants in 20261106130010_dating_v2_country_config_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.country_safety_config (
  country_code char(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  version integer NOT NULL CHECK (version >= 1),
  is_current boolean NOT NULL DEFAULT true,
  tier smallint NOT NULL CHECK (tier BETWEEN 1 AND 3),
  dating_enabled boolean NOT NULL DEFAULT false,
  open_regions text[],
  same_gender_enabled boolean NOT NULL,
  region_list jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(region_list) = 'array'),
  faith_list jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(faith_list) = 'array'),
  id_documents jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(id_documents) = 'array'),
  generation_hour_utc smallint NOT NULL DEFAULT 3 CHECK (generation_hour_utc BETWEEN 0 AND 23),
  reference_tz text NOT NULL DEFAULT 'UTC',
  resources_verified_at timestamptz,
  legal_checklist jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(legal_checklist) = 'object'),
  source_url text,
  reviewed_at timestamptz,
  reviewed_by text,
  published_at timestamptz NOT NULL DEFAULT now(),
  published_by text NOT NULL,
  PRIMARY KEY (country_code, version)
);
CREATE UNIQUE INDEX IF NOT EXISTS country_safety_config_one_current
  ON public.country_safety_config (country_code) WHERE is_current;
ALTER TABLE public.country_safety_config ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.country_safety_config IS
  'Spec 2 §2.2: per-country Dating configuration, versioned. Published rows are immutable; publish_country_config (service role) writes the next version.';

CREATE OR REPLACE FUNCTION private.country_safety_config_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF TG_OP IN ('DELETE', 'TRUNCATE') THEN -- M-5: TRUNCATE skips row triggers
    RAISE EXCEPTION 'config:immutable';
  END IF;
  -- The only change a published row takes: stop being current.
  IF NOT OLD.is_current OR NEW.is_current
     OR (to_jsonb(NEW) - 'is_current') IS DISTINCT FROM (to_jsonb(OLD) - 'is_current') THEN
    RAISE EXCEPTION 'config:immutable';
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS country_safety_config_immutable ON public.country_safety_config;
CREATE TRIGGER country_safety_config_immutable
  BEFORE UPDATE OR DELETE ON public.country_safety_config
  FOR EACH ROW EXECUTE FUNCTION private.country_safety_config_immutable();
DROP TRIGGER IF EXISTS country_safety_config_no_truncate ON public.country_safety_config;
CREATE TRIGGER country_safety_config_no_truncate
  BEFORE TRUNCATE ON public.country_safety_config
  FOR EACH STATEMENT EXECUTE FUNCTION private.country_safety_config_immutable();

-- C-1: a country that has rows ends every transaction with a current one
-- (checked at commit, so the publisher's un-current-then-insert passes).
CREATE OR REPLACE FUNCTION private.country_safety_config_has_current()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.country_safety_config AS c
                  WHERE c.country_code = NEW.country_code AND c.is_current) THEN
    RAISE EXCEPTION 'config:no_current_row';
  END IF;
  RETURN NULL;
END;
$fn$;
DROP TRIGGER IF EXISTS country_safety_config_has_current ON public.country_safety_config;
CREATE CONSTRAINT TRIGGER country_safety_config_has_current
  AFTER INSERT OR UPDATE ON public.country_safety_config
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION private.country_safety_config_has_current();

-- I-1: the assigned ISO 3166-1 alpha-2 codes (249). Anything else (ZZ, EU,
-- AP, XK, UK, ...) is no country: unknown, never a permissive default.
CREATE OR REPLACE FUNCTION private.dating_iso_country(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT k.code
    FROM unnest(ARRAY[
      'AD', 'AE', 'AF', 'AG', 'AI', 'AL', 'AM', 'AO', 'AQ', 'AR', 'AS', 'AT', 'AU', 'AW', 'AX',
      'AZ', 'BA', 'BB', 'BD', 'BE', 'BF', 'BG', 'BH', 'BI', 'BJ', 'BL', 'BM', 'BN', 'BO', 'BQ',
      'BR', 'BS', 'BT', 'BV', 'BW', 'BY', 'BZ', 'CA', 'CC', 'CD', 'CF', 'CG', 'CH', 'CI', 'CK',
      'CL', 'CM', 'CN', 'CO', 'CR', 'CU', 'CV', 'CW', 'CX', 'CY', 'CZ', 'DE', 'DJ', 'DK', 'DM',
      'DO', 'DZ', 'EC', 'EE', 'EG', 'EH', 'ER', 'ES', 'ET', 'FI', 'FJ', 'FK', 'FM', 'FO', 'FR',
      'GA', 'GB', 'GD', 'GE', 'GF', 'GG', 'GH', 'GI', 'GL', 'GM', 'GN', 'GP', 'GQ', 'GR', 'GS',
      'GT', 'GU', 'GW', 'GY', 'HK', 'HM', 'HN', 'HR', 'HT', 'HU', 'ID', 'IE', 'IL', 'IM', 'IN',
      'IO', 'IQ', 'IR', 'IS', 'IT', 'JE', 'JM', 'JO', 'JP', 'KE', 'KG', 'KH', 'KI', 'KM', 'KN',
      'KP', 'KR', 'KW', 'KY', 'KZ', 'LA', 'LB', 'LC', 'LI', 'LK', 'LR', 'LS', 'LT', 'LU', 'LV',
      'LY', 'MA', 'MC', 'MD', 'ME', 'MF', 'MG', 'MH', 'MK', 'ML', 'MM', 'MN', 'MO', 'MP', 'MQ',
      'MR', 'MS', 'MT', 'MU', 'MV', 'MW', 'MX', 'MY', 'MZ', 'NA', 'NC', 'NE', 'NF', 'NG', 'NI',
      'NL', 'NO', 'NP', 'NR', 'NU', 'NZ', 'OM', 'PA', 'PE', 'PF', 'PG', 'PH', 'PK', 'PL', 'PM',
      'PN', 'PR', 'PS', 'PT', 'PW', 'PY', 'QA', 'RE', 'RO', 'RS', 'RU', 'RW', 'SA', 'SB', 'SC',
      'SD', 'SE', 'SG', 'SH', 'SI', 'SJ', 'SK', 'SL', 'SM', 'SN', 'SO', 'SR', 'SS', 'ST', 'SV',
      'SX', 'SY', 'SZ', 'TC', 'TD', 'TF', 'TG', 'TH', 'TJ', 'TK', 'TL', 'TM', 'TN', 'TO', 'TR',
      'TT', 'TV', 'TW', 'TZ', 'UA', 'UG', 'UM', 'US', 'UY', 'UZ', 'VA', 'VC', 'VE', 'VG', 'VI',
      'VN', 'VU', 'WF', 'WS', 'YE', 'YT', 'ZA', 'ZM', 'ZW'
    ]) AS k(code)
   WHERE k.code = upper(btrim(coalesce(p_code, '')));
$fn$;

-- M-4: calling codes, one table, so a country added later gets its code in
-- the same publish (publish_country_config refuses a restricting country
-- without one). The phone country is the longest matching prefix.
CREATE TABLE IF NOT EXISTS private.dating_calling_codes (
  prefix text PRIMARY KEY CHECK (prefix ~ '^[0-9]{1,4}$'),
  country_code char(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$')
);
ALTER TABLE private.dating_calling_codes ENABLE ROW LEVEL SECURITY;
INSERT INTO private.dating_calling_codes (prefix, country_code) VALUES
  ('233', 'GH'), ('234', 'NG'), ('20', 'EG'), ('216', 'TN'), ('961', 'LB'), ('212', 'MA'),
  ('964', 'IQ'), ('962', 'JO'), ('7', 'RU'), ('62', 'ID'), ('60', 'MY'), ('90', 'TR'),
  ('256', 'UG'), ('221', 'SN'), ('227', 'NE'), ('223', 'ML'), ('226', 'BF'), ('98', 'IR'),
  ('966', 'SA'), ('967', 'YE'), ('93', 'AF'), ('673', 'BN'), ('222', 'MR'), ('252', 'SO'),
  ('974', 'QA'), ('971', 'AE'), ('92', 'PK'), ('963', 'SY'),
  ('213', 'DZ'), ('257', 'BI'), ('237', 'CM'), ('235', 'TD'), ('269', 'KM'), ('291', 'ER'),
  ('268', 'SZ'), ('251', 'ET'), ('224', 'GN'), ('254', 'KE'), ('231', 'LR'), ('218', 'LY'),
  ('265', 'MW'), ('232', 'SL'), ('211', 'SS'), ('249', 'SD'), ('255', 'TZ'), ('220', 'GM'),
  ('228', 'TG'), ('260', 'ZM'), ('263', 'ZW'), ('880', 'BD'), ('965', 'KW'), ('960', 'MV'),
  ('95', 'MM'), ('968', 'OM'), ('970', 'PS'), ('94', 'LK'), ('993', 'TM'), ('998', 'UZ'),
  ('1473', 'GD'), ('592', 'GY'), ('1876', 'JM'), ('1658', 'JM'), ('1784', 'VC'), ('1868', 'TT'),
  ('686', 'KI'), ('675', 'PG'), ('685', 'WS'), ('677', 'SB'), ('676', 'TO'), ('688', 'TV'),
  ('375', 'BY'), ('76', 'KZ'), ('77', 'KZ'), ('86', 'CN'), ('44', 'GB')
ON CONFLICT (prefix) DO NOTHING;

-- Seeds (version 1; all closed). Codes: ISO 3166-2:GH for Ghana's regions,
-- ITL1 for the UK's. name_key values are ARB keys W3b adds.
INSERT INTO public.country_safety_config
  (country_code, version, tier, dating_enabled, open_regions, same_gender_enabled, region_list,
   id_documents, generation_hour_utc, reference_tz, legal_checklist, source_url, reviewed_at,
   reviewed_by, published_by)
VALUES
  ('GH', 1, 1, false, ARRAY['AA', 'AH'], false,
   '[{"code": "AF", "name_key": "dating_region_gh_af", "sides": []},
     {"code": "AH", "name_key": "dating_region_gh_ah", "sides": [
        {"code": "kumasi", "name_key": "dating_side_gh_kumasi"},
        {"code": "outside_kumasi", "name_key": "dating_side_gh_outside_kumasi"}]},
     {"code": "BO", "name_key": "dating_region_gh_bo", "sides": []},
     {"code": "BE", "name_key": "dating_region_gh_be", "sides": []},
     {"code": "CP", "name_key": "dating_region_gh_cp", "sides": []},
     {"code": "EP", "name_key": "dating_region_gh_ep", "sides": []},
     {"code": "AA", "name_key": "dating_region_gh_aa", "sides": [
        {"code": "accra", "name_key": "dating_side_gh_accra"},
        {"code": "tema", "name_key": "dating_side_gh_tema"}]},
     {"code": "NE", "name_key": "dating_region_gh_ne", "sides": []},
     {"code": "NP", "name_key": "dating_region_gh_np", "sides": []},
     {"code": "OT", "name_key": "dating_region_gh_ot", "sides": []},
     {"code": "SV", "name_key": "dating_region_gh_sv", "sides": []},
     {"code": "UE", "name_key": "dating_region_gh_ue", "sides": []},
     {"code": "UW", "name_key": "dating_region_gh_uw", "sides": []},
     {"code": "TV", "name_key": "dating_region_gh_tv", "sides": []},
     {"code": "WP", "name_key": "dating_region_gh_wp", "sides": []},
     {"code": "WN", "name_key": "dating_region_gh_wn", "sides": []}]'::jsonb,
   '[{"code": "ghana_card", "name_key": "dating_id_ghana_card"},
     {"code": "passport", "name_key": "dating_id_passport"}]'::jsonb,
   3, 'Africa/Accra',
   '{"ghana_legal_opinion": null, "dpc_registration": null, "dpia": null, "pen_test": null,
     "safety_owner_and_moderator": null, "reviewer_signoffs": null}'::jsonb,
   'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
   '2026-10-24', 'spec2', 'migration:spec2-w1b'),
  ('GB', 1, 3, false, NULL, true,
   '[{"code": "TLC", "name_key": "dating_region_gb_tlc", "sides": []},
     {"code": "TLD", "name_key": "dating_region_gb_tld", "sides": []},
     {"code": "TLE", "name_key": "dating_region_gb_tle", "sides": []},
     {"code": "TLF", "name_key": "dating_region_gb_tlf", "sides": []},
     {"code": "TLG", "name_key": "dating_region_gb_tlg", "sides": []},
     {"code": "TLH", "name_key": "dating_region_gb_tlh", "sides": []},
     {"code": "TLI", "name_key": "dating_region_gb_tli", "sides": []},
     {"code": "TLJ", "name_key": "dating_region_gb_tlj", "sides": []},
     {"code": "TLK", "name_key": "dating_region_gb_tlk", "sides": []},
     {"code": "TLL", "name_key": "dating_region_gb_tll", "sides": []},
     {"code": "TLM", "name_key": "dating_region_gb_tlm", "sides": []},
     {"code": "TLN", "name_key": "dating_region_gb_tln", "sides": []}]'::jsonb,
   '[{"code": "passport", "name_key": "dating_id_passport"},
     {"code": "uk_photocard_driving_licence", "name_key": "dating_id_uk_driving_licence"}]'::jsonb,
   3, 'Europe/London',
   '{"osa_illegal_harms_assessment": null, "osa_childrens_access_assessment": null,
     "highly_effective_age_assurance": null, "dpia": null, "pen_test": null,
     "safety_owner_and_moderator": null, "reviewer_signoffs": null}'::jsonb,
   'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
   '2026-10-24', 'spec2', 'migration:spec2-w1b')
ON CONFLICT (country_code, version) DO NOTHING;

INSERT INTO public.country_safety_config
  (country_code, version, tier, dating_enabled, same_gender_enabled, source_url, reviewed_at,
   reviewed_by, published_by)
SELECT t.code, 1, t.tier, false, false,
       'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
       '2026-10-24', 'spec2', 'migration:spec2-w1b'
  FROM (VALUES
    ('NG', 1), ('EG', 1), ('TN', 1), ('LB', 1), ('MA', 1), ('IQ', 1), ('JO', 1), ('RU', 1),
    ('ID', 1), ('MY', 1), ('TR', 1), ('UG', 1), ('SN', 1), ('NE', 1), ('ML', 1), ('BF', 1),
    ('IR', 1), ('SA', 1), ('YE', 1), ('AF', 1), ('BN', 1), ('MR', 1), ('SO', 1), ('QA', 1),
    ('AE', 1), ('PK', 1), ('SY', 1), ('DZ', 2), ('BI', 2), ('CM', 2), ('TD', 2), ('KM', 2),
    ('ER', 2), ('SZ', 2), ('ET', 2), ('GN', 2), ('KE', 2), ('LR', 2), ('LY', 2), ('MW', 2),
    ('SL', 2), ('SS', 2), ('SD', 2), ('TZ', 2), ('GM', 2), ('TG', 2), ('ZM', 2), ('ZW', 2),
    ('BD', 2), ('KW', 2), ('MV', 2), ('MM', 2), ('OM', 2), ('PS', 2), ('LK', 2), ('TM', 2),
    ('UZ', 2), ('GD', 2), ('GY', 2), ('JM', 2), ('VC', 2), ('TT', 2), ('KI', 2), ('PG', 2),
    ('WS', 2), ('SB', 2), ('TO', 2), ('TV', 2), ('BY', 2), ('KZ', 2), ('CN', 2)) AS t(code, tier)
ON CONFLICT (country_code, version) DO NOTHING;

-- The current row, or the default for a country with no row (spec §2.2).
-- C-1: a country with rows but none current (orphaned) reads closed, Tier 1,
-- same-gender off (the latest row's lists kept, is_current false). I-1: a
-- code that is no assigned ISO country has no config (NULL).
CREATE OR REPLACE FUNCTION public.dating_country_config(p_country text)
RETURNS public.country_safety_config
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v public.country_safety_config;
BEGIN
  SELECT * INTO v FROM public.country_safety_config AS c WHERE c.country_code = v_code AND c.is_current;
  IF FOUND THEN
    RETURN v;
  END IF;
  SELECT * INTO v FROM public.country_safety_config AS c WHERE c.country_code = v_code
   ORDER BY c.version DESC LIMIT 1;
  IF FOUND THEN
    v.is_current := false;
    v.tier := 1;
    v.dating_enabled := false;
    v.same_gender_enabled := false;
    v.published_by := 'fail_closed:no_current_row';
    RETURN v;
  END IF;
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN
    RETURN NULL;
  END IF;
  v.country_code := v_code;
  v.version := 0;
  v.is_current := true;
  v.tier := 3;
  v.dating_enabled := false;
  v.open_regions := NULL;
  v.same_gender_enabled := true;
  v.region_list := '[]'::jsonb;
  v.faith_list := '[]'::jsonb;
  v.id_documents := '[]'::jsonb;
  v.generation_hour_utc := 3;
  v.reference_tz := 'UTC';
  v.legal_checklist := '{}'::jsonb;
  v.published_at := now();
  v.published_by := 'default';
  RETURN v;
END;
$fn$;

-- The production-mode checks for a row about to be published (spec §2.2,
-- §2.4): the list of failed checks, empty when none. A NULL field is
-- checked as its riskiest value (Dating on, same-gender on, Tier 1, an
-- empty checklist), so a malformed row can never pass (batch 4).
CREATE OR REPLACE FUNCTION private.country_config_checks(p_row public.country_safety_config)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
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
  END IF;
  IF coalesce(p_row.same_gender_enabled, true) AND coalesce(p_row.tier, 1) IN (1, 2)
     AND (jsonb_typeof(v_sg) IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['legal_opinion', 'lgbtq_consultation', 'tier1_protections']) AS k(key)
                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN
    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  RETURN v_checks;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
  -- M-4: a country that restricts anything needs its calling code, or the
  -- phone fallback can't see it.
  IF (v_new.tier IN (1, 2) OR NOT v_new.same_gender_enabled)
     AND NOT EXISTS (SELECT 1 FROM private.dating_calling_codes AS k WHERE k.country_code = v_code) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:no_calling_code');
  END IF;

  -- Same-gender off: the purge (apply_same_gender_switch) arrives in W1d.
  -- (Not for a country with no row yet: nobody can have it as their Dating country. M-3)
  IF v_old.version >= 1 AND v_old.same_gender_enabled AND NOT v_new.same_gender_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:kill_switch_pending');
  END IF;

  -- I-2: the reconsideration is checked at the stricter of the old and new
  -- tiers, and a downgrade needs its own review reference.
  v_check_row := v_new;
  v_check_row.tier := least(v_old.tier, v_new.tier);
  v_checks := private.country_config_checks(v_check_row);
  IF v_old.version >= 1 AND v_new.tier > v_old.tier
     AND (jsonb_typeof(v_new.legal_checklist -> 'tier_review') IS DISTINCT FROM 'string'
          OR btrim(v_new.legal_checklist ->> 'tier_review') = '') THEN
    v_checks := array_append(v_checks, 'tier_review_missing');
  END IF;
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks));
END;
$fn$;

-- Anyone (Welcome, D1, the not-open screens): the open countries and their
-- open regions, sorted.
CREATE OR REPLACE FUNCTION public.get_dating_availability()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object('countries', coalesce(jsonb_agg(jsonb_build_object(
           'code', c.country_code::text,
           -- NULL: every region; a country open in no region is [] (batch 4).
           'open_regions', CASE WHEN c.open_regions IS NULL THEN NULL ELSE coalesce((
             SELECT jsonb_agg(jsonb_build_object('code', r ->> 'code', 'name_key', r ->> 'name_key')
                              ORDER BY r ->> 'code')
               FROM jsonb_array_elements(c.region_list) AS r
              WHERE (r ->> 'code') = ANY (c.open_regions)), '[]'::jsonb) END)
           ORDER BY c.country_code), '[]'::jsonb))
    FROM public.country_safety_config AS c
   WHERE c.is_current AND c.dating_enabled;
$fn$;

-- Spec 1's seam, re-created from its live body (20261025100400) over the
-- table; same shape (sorted ISO alpha-2 codes).
CREATE OR REPLACE FUNCTION private.dating_open_countries()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT coalesce(array_agg(c.country_code::text ORDER BY c.country_code), ARRAY[]::text[]) -- Spec 2 W1b
    FROM public.country_safety_config AS c -- Spec 2 W1b (I-3)
   WHERE c.is_current AND c.dating_enabled; -- Spec 2 W1b
$function$;
DELETE FROM public.app_public_config WHERE key = 'dating_open_countries';
-- M-9: Spec 1's key list loses the interim key, so a stale write can't
-- bring the row back (get_public_app_config() is not touched).
ALTER TABLE public.app_public_config DROP CONSTRAINT IF EXISTS app_public_config_key_check;
ALTER TABLE public.app_public_config ADD CONSTRAINT app_public_config_key_check
  CHECK (key IN ('age_signal_storefronts'));

-- The country a phone number belongs to, from its calling code (longest
-- prefix, private.dating_calling_codes); NULL otherwise.
CREATE OR REPLACE FUNCTION private.dating_phone_country(p_phone text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT p.country_code::text
    FROM private.dating_calling_codes AS p
   WHERE pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') LIKE p.prefix || '%'
   ORDER BY char_length(p.prefix) DESC
   LIMIT 1;
$fn$;

CREATE TABLE IF NOT EXISTS public.dating_session_context (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  effective_tier smallint NOT NULL CHECK (effective_tier BETWEEN 1 AND 3),
  dating_allowed_here boolean NOT NULL,
  same_gender_allowed_here boolean NOT NULL,
  away_from_home boolean NOT NULL,
  ip_resolved boolean NOT NULL,
  mismatch_streak integer NOT NULL DEFAULT 0 CHECK (mismatch_streak >= 0),
  trip_note_shown_at timestamptz,
  checked_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_session_context ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_session_context IS
  'Spec 2 §2.3: one overwritten row per user, no country codes, no history.';

-- Spec 2 §2.3: the context from the four countries (any may be NULL).
CREATE OR REPLACE FUNCTION public.dating_effective_context(p_phone_country text, p_dating_country text,
                                                           p_ip_country text, p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_phone constant text := private.dating_iso_country(p_phone_country); -- I-1
  v_dating constant text := private.dating_iso_country(p_dating_country); -- I-1
  v_ip constant text := private.dating_iso_country(p_ip_country); -- I-1
  v_net constant text := private.dating_iso_country(p_network_country); -- I-1
  -- Where the person is: the IP country, or the phone country when the IP
  -- can't be resolved (VPN, unknown range).
  v_here constant text := coalesce(v_ip, v_phone);
  v_tier smallint;
  v_allowed boolean;
  v_same boolean;
BEGIN
  SELECT coalesce(min(c.tier), 3) INTO v_tier
    FROM unnest(ARRAY[v_phone, v_dating, v_ip, v_net]) AS k(code)
    CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
   WHERE k.code IS NOT NULL;
  -- Not allowed where the place (or the network) is a closed Tier 1/2 country.
  v_allowed := NOT EXISTS (
    SELECT 1 FROM unnest(ARRAY[v_here, v_net]) AS k(code)
      CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
     WHERE k.code IS NOT NULL AND NOT c.dating_enabled AND c.tier IN (1, 2));
  -- Same-gender: the global flag, the Dating country (which must be known),
  -- the place and the network, all allowing it.
  v_same := public.dating_flag_enabled('dating_same_gender_matching')
            AND v_dating IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM unnest(ARRAY[v_dating, v_here, v_net]) AS k(code)
                CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
               WHERE k.code IS NOT NULL AND NOT c.same_gender_enabled);
  RETURN jsonb_build_object(
    'effective_tier', v_tier,
    'dating_allowed_here', v_allowed,
    'same_gender_allowed_here', v_same,
    'away_from_home', v_ip IS NOT NULL AND v_dating IS NOT NULL AND v_ip <> v_dating,
    'ip_resolved', v_ip IS NOT NULL);
END;
$fn$;

-- Service role (W8b's dating-device-check): overwrite the person's row.
-- The phone country comes from Auth's number, the Dating country from the
-- profile (read by name: the column arrives in W1c); nothing about the
-- countries is stored.
CREATE OR REPLACE FUNCTION public.record_dating_session_context(p_user uuid, p_ip_country text,
                                                               p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_phone text;
  v_dating text;
  v_ctx jsonb;
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  SELECT private.dating_phone_country(a.phone) INTO v_phone FROM auth.users AS a WHERE a.id = p_user;
  SELECT to_jsonb(p) ->> 'country_code' INTO v_dating FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_ctx := public.dating_effective_context(v_phone, v_dating, p_ip_country, p_network_country);
  INSERT INTO public.dating_session_context AS s
    (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home,
     ip_resolved, mismatch_streak, checked_at)
  VALUES (p_user, (v_ctx ->> 'effective_tier')::smallint, (v_ctx ->> 'dating_allowed_here')::boolean,
          (v_ctx ->> 'same_gender_allowed_here')::boolean, (v_ctx ->> 'away_from_home')::boolean,
          (v_ctx ->> 'ip_resolved')::boolean, CASE WHEN (v_ctx ->> 'away_from_home')::boolean THEN 1 ELSE 0 END,
          now())
  ON CONFLICT (user_id) DO UPDATE
    SET effective_tier = EXCLUDED.effective_tier,
        dating_allowed_here = EXCLUDED.dating_allowed_here,
        same_gender_allowed_here = EXCLUDED.same_gender_allowed_here,
        away_from_home = EXCLUDED.away_from_home,
        ip_resolved = EXCLUDED.ip_resolved,
        mismatch_streak = CASE WHEN EXCLUDED.away_from_home THEN s.mismatch_streak + 1 ELSE 0 END,
        checked_at = EXCLUDED.checked_at;
  RETURN jsonb_build_object('ok', true) || v_ctx;
END;
$fn$;

CREATE TABLE IF NOT EXISTS public.dating_notify_requests (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  country_code char(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  region_code text CONSTRAINT dating_notify_requests_region_code_check
    CHECK (region_code IS NULL OR region_code ~ '^[A-Z0-9]{2,3}$'), -- M-6
  created_at timestamptz NOT NULL DEFAULT now()
);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'dating_notify_requests_region_code_check'
                    AND conrelid = 'public.dating_notify_requests'::regclass) THEN
    ALTER TABLE public.dating_notify_requests ADD CONSTRAINT dating_notify_requests_region_code_check
      CHECK (region_code IS NULL OR region_code ~ '^[A-Z0-9]{2,3}$');
  END IF;
END $$;
ALTER TABLE public.dating_notify_requests ENABLE ROW LEVEL SECURITY;

-- The new flag (off), and a production gate row for it and for every
-- existing Dating flag, so none can be switched on in production mode
-- without recorded evidence (Spec 1's gate trigger).
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_mode_enabled', 'Spec 2 W10 gate: every W1-W10 gate signed, get_dating_launch_readiness() green, the launch project in production mode'),
  ('dating_candidate_generation', 'Spec 2 W5 gate: dating_exclusion_key provisioned, DV sign-off on never-introduce, introductions_v2 active with real review refs'),
  ('dating_match_messaging', 'Spec 2 W6 gate: DATING_CHAT_SAFETY_SPEC v2 section 12 checked by the safety owner, DV and cultural sign-offs'),
  ('dating_profile_photos', 'Spec 2 W3 gate: process-dating-photo runs the inline CSAM match first (S1 W7b PF-H2) and the W3 reviewers have signed'),
  ('dating_alignment_algorithm_v1', 'Spec 2: retired in W5a; never switched on in production'),
  ('dating_same_gender_matching', 'Spec 2 W3 gate (§2.4): the LGBTQ+ safety reviewer signs the off-country copy and the country note')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_same_gender_matching', false)
ON CONFLICT (key) DO NOTHING;

REVOKE ALL ON public.country_safety_config, public.dating_session_context, public.dating_notify_requests
  FROM PUBLIC, anon, authenticated;
-- C-1: the service role only reads the config; publish_country_config (definer) writes it.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.country_safety_config FROM service_role;
REVOKE ALL ON private.dating_calling_codes FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_safety_config_has_current(), private.dating_iso_country(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.country_safety_config_immutable(), public.dating_country_config(text),
  private.country_config_checks(public.country_safety_config), public.publish_country_config(text, jsonb),
  public.get_dating_availability(), private.dating_open_countries(), private.dating_phone_country(text),
  public.dating_effective_context(text, text, text, text), public.record_dating_session_context(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_availability() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_session_context(uuid, text, text) TO service_role;

COMMIT;
