-- Spec 1 W1c, migration 5 of 6 (spec §4.7 #5): spec1_flags_and_public_config.
--   * private.attune_environment(): 'development' while the setting is unset
--     or empty, 'production' for 'production' and for any other value (a
--     typo fails closed). Two sources, the Vault secret and the
--     app.settings.attune_environment GUC (on the managed project
--     ALTER DATABASE ... SET app.settings.* fails with 42501,
--     20260931120000_vault_backed_settings.sql:1-5), read separately: it is
--     development only when every source that is set says development
--     (final review I-1). Vault is read through private.vault_setting_strict,
--     not public.app_setting, so a Vault that is there but unreadable reads
--     production (batch 5 review #4). Nothing here sets it; only the owner
--     does, at launch.
--   * private.assert_development_project(): the dev-script guard; a project
--     URL from either source that isn't the development ref, or an
--     unreadable one, also refuses.
--   * the eleven Spec 1 flags, inserted false (migrations never turn a flag on);
--   * the production flag gate (review R-7): private.flag_production_gates,
--     a feature_flags trigger, record_flag_gate_evidence and
--     production_flag_violations;
--   * app_public_config and the one Dating open-country seam (D15),
--     read by anon through get_public_app_config().
-- Grants in 20261025100410_spec1_flags_and_public_config_grants.sql.
BEGIN;
-- The production gate is a trigger on public.feature_flags (final review
-- M-3): fail fast rather than queue every flag read and write behind it.
SET LOCAL lock_timeout = '5s';

-- Vault's value for a setting, failing closed (batch 5 review #4):
-- public.app_setting falls back to the GUC on any error, and the GUC is unset
-- on the managed project, so an unreadable Vault would read as development
-- there. Here only a database with no vault schema at all has no Vault value;
-- a Vault that is there but fails to read (its view gone, a decrypt error)
-- raises, and each caller refuses. The app.settings GUC is read by each
-- caller on its own (final review I-1): the two sources are never merged, so
-- a value in one can't hide the other. (An earlier draft of this unpushed
-- migration merged them in private.strict_setting, dropped below.)
DROP FUNCTION IF EXISTS private.strict_setting(text);
CREATE OR REPLACE FUNCTION private.vault_setting_strict(p_name text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_value text;
BEGIN
  IF to_regnamespace('vault') IS NULL THEN
    RETURN NULL;  -- no Vault on this database
  END IF;
  BEGIN
    SELECT s.decrypted_secret INTO v_value
      FROM vault.decrypted_secrets AS s
     WHERE s.name = p_name
     LIMIT 1;
  EXCEPTION WHEN invalid_schema_name THEN
    RETURN NULL;  -- the vault schema went away between the check and the read
  END;
  RETURN nullif(btrim(v_value), '');
END;
$$;

-- Development only when every source that is set says exactly
-- 'development', or none is set (final review I-1). Anything else in either
-- the Vault secret or the GUC is production, so a stray Vault 'development'
-- can never hide an ALTER DATABASE ... 'production' flip, nor the reverse.
CREATE OR REPLACE FUNCTION private.attune_environment()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_vault text;
  v_guc constant text := btrim(coalesce(current_setting('app.settings.attune_environment', true), ''));
BEGIN
  BEGIN
    v_vault := coalesce(private.vault_setting_strict('attune_environment'), '');
  EXCEPTION WHEN OTHERS THEN
    RETURN 'production';  -- Vault is there but unreadable: fail closed (review #4)
  END;
  IF v_vault IN ('', 'development') AND v_guc IN ('', 'development') THEN
    RETURN 'development';
  END IF;
  RETURN 'production';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_attune_environment()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.attune_environment();
$$;

-- Development project ref: mrgjtyacrzfylawyzabm (spec §1.3 Q19b).
CREATE OR REPLACE FUNCTION private.assert_development_project()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_vault_url text;
  v_guc_url constant text := nullif(btrim(coalesce(current_setting('app.settings.supabase_url', true), '')), '');
BEGIN
  BEGIN
    v_vault_url := private.vault_setting_strict('supabase_url');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'env:not_development';  -- an unreadable project URL is never the development one (review #4)
  END;
  -- Every project URL that is set, in either source, must name the
  -- development ref (final review I-1).
  IF private.attune_environment() <> 'development' OR (v_vault_url IS NOT NULL AND position('mrgjtyacrzfylawyzabm' IN v_vault_url) = 0) OR (v_guc_url IS NOT NULL AND position('mrgjtyacrzfylawyzabm' IN v_guc_url) = 0) THEN
    RAISE EXCEPTION 'env:not_development';
  END IF;
END;
$$;

-- The production flag gate (spec §2.5). One row per gated flag;
-- flow_couples_v2 has no gate. Spec 2 may add rows.
CREATE TABLE IF NOT EXISTS private.flag_production_gates (
  flag_key text PRIMARY KEY,
  gate text NOT NULL,
  review_ref text,
  recorded_by text,
  recorded_at timestamptz
);
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('flow_signin_v2', 'W2 group gate (W2c): SMS, voice and WhatsApp providers contracted; MTN sender ID; Meta template; real-carrier tests in GH, UK, US, CA; A5 AI line and EULA v2 approved by counsel; webcredentials; store listing'),
  ('flow_paths_v2', 'Spec 2 W2 path trigger live, so Dating -> Just for me pauses Dating (D18)'),
  ('couple_profile', 'W5 gate: the Ghanaian cultural reviewer confirms the stage options and helper text'),
  ('dormancy_rule', 'W6a gate: DV specialist reviewed DM1, DM2 and H1; both auth hooks pass on the development project first'),
  ('platform_age_signals', 'W6b gate: Play Restrict Minor Access on, 18+ ratings in both stores, Declared Age Range entitlement granted'),
  ('support_resources_v2', 'W7a gate: resource entries verified per country by the DV professional and the cultural reviewer; clinician reviewed the grief copy'),
  ('csam_hash_matching', 'W7b gate: hash-vendor contract, escalation runbook approved by counsel, named child-safety contact'),
  ('opinions_safety_v1', 'W9a and W9b gates: reviewed slur and explicit lists signed; a named daily reviewer works review queue v0'),
  ('journal_ai_insights', 'W9c gate: the clinician and the suicide-prevention reviewer sign the journal card and the self-harm corpus'),
  ('text_scale_v2', 'W10 group gate (W10c): the device matrix passes on the chosen cap')
ON CONFLICT (flag_key) DO NOTHING;

CREATE OR REPLACE FUNCTION private.guard_flag_production_gate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.enabled
     AND private.attune_environment() = 'production'
     AND EXISTS (SELECT 1 FROM private.flag_production_gates AS g
                  WHERE g.flag_key = NEW.key AND g.review_ref IS NULL) THEN
    RAISE EXCEPTION 'flag:gate_evidence_required';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS feature_flags_production_gate ON public.feature_flags;
CREATE TRIGGER feature_flags_production_gate
  BEFORE INSERT OR UPDATE ON public.feature_flags
  FOR EACH ROW EXECUTE FUNCTION private.guard_flag_production_gate();

-- The eleven Spec 1 flags, off (spec §2.5). The dev script turns them on.
INSERT INTO public.feature_flags (key, enabled) VALUES
  ('flow_signin_v2', false),
  ('flow_paths_v2', false),
  ('flow_couples_v2', false),
  ('couple_profile', false),
  ('dormancy_rule', false),
  ('platform_age_signals', false),
  ('support_resources_v2', false),
  ('csam_hash_matching', false),
  ('opinions_safety_v1', false),
  ('journal_ai_insights', false),
  ('text_scale_v2', false)
ON CONFLICT (key) DO NOTHING;

-- Owner-only in practice (SQL editor, service role). recorded_by is the JWT
-- role, else the session user: inside a SECURITY DEFINER function
-- current_user is the owner.
CREATE OR REPLACE FUNCTION public.record_flag_gate_evidence(p_flag text, p_review_ref text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_review_ref IS NULL OR btrim(p_review_ref) = '' THEN
    RAISE EXCEPTION 'flag:review_ref_required';
  END IF;
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
$$;

-- Run right after the environment flip: the trigger only sees later writes.
CREATE OR REPLACE FUNCTION public.production_flag_violations()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.flag_key
    FROM private.flag_production_gates AS g
    JOIN public.feature_flags AS f ON f.key = g.flag_key
   WHERE f.enabled AND g.review_ref IS NULL
   ORDER BY g.flag_key;
$$;

-- Public, pre-auth configuration (spec §4.2). Service-role writes only.
CREATE TABLE IF NOT EXISTS public.app_public_config (
  key text PRIMARY KEY
    CONSTRAINT app_public_config_key_check CHECK (key IN ('age_signal_storefronts', 'dating_open_countries')),
  value jsonb NOT NULL CONSTRAINT app_public_config_value_check CHECK (jsonb_typeof(value) = 'array'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_public_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.app_public_config (key, value) VALUES
  ('age_signal_storefronts', '["USA", "BRA"]'::jsonb),
  ('dating_open_countries', '["GH", "GB"]'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- The one reader of the Dating open-country list (D15): ISO 3166-1 alpha-2
-- codes, sorted. Spec 2 W1b re-creates this over country_safety_config with
-- the same shape, then deletes the row.
CREATE OR REPLACE FUNCTION private.dating_open_countries()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(array_agg(c ORDER BY c), ARRAY[]::text[])
    FROM public.app_public_config AS k,
         jsonb_array_elements_text(k.value) AS c
   WHERE k.key = 'dating_open_countries';
$$;

-- Anon and signed in: effective flag values and the two config lists, nothing else.
CREATE OR REPLACE FUNCTION public.get_public_app_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'flags', jsonb_build_object(
      'flow_signin_v2', private.spec1_flag_on('flow_signin_v2'),
      'platform_age_signals', private.spec1_flag_on('platform_age_signals'),
      'support_resources_v2', private.spec1_flag_on('support_resources_v2'),
      'text_scale_v2', private.spec1_flag_on('text_scale_v2')),
    'config', jsonb_build_object(
      'age_signal_storefronts', coalesce(
        (SELECT k.value FROM public.app_public_config AS k WHERE k.key = 'age_signal_storefronts'),
        '[]'::jsonb),
      'dating_open_countries', to_jsonb(private.dating_open_countries())));
$$;

-- Revoked here as well as in the twin (controller ruling after batch 3; the
-- verified_phone precedent): the hosted default privileges grant EXECUTE on
-- a new function, and table rights on a new public table, to anon and
-- authenticated, and a failed or late twin push must not let a client read
-- the environment, pass the dev guard, record gate evidence, or write the
-- public config. get_public_app_config is the one client read and is left
-- to the twin.
REVOKE ALL ON public.app_public_config FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.vault_setting_strict(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.assert_development_project() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_flag_production_gate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_open_countries() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_flag_gate_evidence(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.production_flag_violations() FROM PUBLIC, anon, authenticated;

COMMIT;
