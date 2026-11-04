-- Spec 1 W7a, migration 14 (spec §4.7 #14): support resources v2.
--   * public.support_resources (spec §4.2): one row per checked helpline,
--     by country (ISO 3166-1 alpha-2, or XX for anywhere) and category.
--     RLS on with no policy: read only through get_support_resources.
--     Loaded by scripts/load_support_resources.sh (service role) from
--     assets/support_resources/catalogue.json, the file the app bundles for
--     offline use.
--   * get_support_resources(p_country) (anon, authenticated): the active
--     rows for the country plus XX, emergency first, then the country's own
--     rows before XX, then sort_order, then name (bytewise, COLLATE "C",
--     so every database and the app's bundled copy give one order):
--     {country, country_supported, catalogue_version, resources:[...]}.
--     country_supported is true only when the country has a row of its own.
--   * load_support_resources(p_catalogue) (service role, plan P-3): the
--     catalogue file in one transaction: every entry upserted by id and
--     active, every other row made inactive, refused whole when an entry is
--     bad, an id repeats, or there is no XX entry with a link (the
--     fallback "Find a helpline" always has somewhere to go).
-- Nothing here holds a person's data: the table is a public directory.
-- Grants in 20261103130010_support_resources_v2_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.support_resources (
  id uuid PRIMARY KEY,
  country_code text NOT NULL
    CONSTRAINT support_resources_country_check CHECK (country_code ~ '^([A-Z]{2}|XX)$'),
  category text NOT NULL
    CONSTRAINT support_resources_category_check CHECK (category IN (
      'emergency', 'dv', 'crisis', 'sexual_assault', 'sextortion', 'child_safety',
      'youth', 'lgbtq_legal', 'grief', 'perinatal', 'addiction', 'financial_control')),
  name text NOT NULL
    -- Stored trimmed: the phone sorts Dart's trim() of the name (whitespace
    -- and U+FEFF), so a padded one would order differently offline
    -- (batch-1 review M1).
    CONSTRAINT support_resources_name_check
      CHECK (name !~ '^[\s\uFEFF]|[\s\uFEFF]$' AND char_length(name) BETWEEN 1 AND 120),
  description text
    CONSTRAINT support_resources_description_check CHECK (description IS NULL OR char_length(description) <= 400),
  phone text
    CONSTRAINT support_resources_phone_check CHECK (phone IS NULL OR phone ~ '^[0-9A-Za-z+() .-]{2,40}$'),
  sms text
    CONSTRAINT support_resources_sms_check CHECK (sms IS NULL OR sms ~ '^[0-9A-Za-z+() .-]{2,40}$'),
  whatsapp text
    CONSTRAINT support_resources_whatsapp_check CHECK (whatsapp IS NULL OR whatsapp ~ '^\+[0-9 ]{6,24}$'),
  url text
    CONSTRAINT support_resources_url_check CHECK (url IS NULL OR (url ~ '^https://\S+$' AND char_length(url) <= 300)),
  hours text
    CONSTRAINT support_resources_hours_check CHECK (hours IS NULL OR char_length(hours) <= 120),
  languages text[] NOT NULL DEFAULT '{}',
  is_police boolean NOT NULL DEFAULT false,
  sort_order int NOT NULL DEFAULT 100,
  verified_at date NOT NULL,
  verified_by text NOT NULL
    CONSTRAINT support_resources_verified_by_check CHECK (char_length(btrim(verified_by)) BETWEEN 1 AND 120),
  catalogue_version text NOT NULL
    CONSTRAINT support_resources_version_check CHECK (catalogue_version ~ '^[0-9A-Za-z._-]{1,40}$'),
  active boolean NOT NULL DEFAULT true,
  -- A row with no way to reach anyone helps nobody.
  CONSTRAINT support_resources_reachable_check
    CHECK (phone IS NOT NULL OR sms IS NOT NULL OR whatsapp IS NOT NULL OR url IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS support_resources_country_idx
  ON public.support_resources (country_code) WHERE active;
ALTER TABLE public.support_resources ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_support_resources(p_country text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH c AS (
    SELECT CASE WHEN upper(btrim(coalesce(p_country, ''))) ~ '^[A-Z]{2}$'
                 AND upper(btrim(p_country)) <> 'XX'
                THEN upper(btrim(p_country)) END AS code
  ), picked AS (
    SELECT r.*
      FROM public.support_resources AS r, c
     WHERE r.active AND (r.country_code = c.code OR r.country_code = 'XX')
  )
  SELECT jsonb_build_object(
    'country', (SELECT c.code FROM c),
    'country_supported', EXISTS (SELECT 1 FROM picked AS p, c WHERE p.country_code = c.code),
    'catalogue_version', (SELECT max(r.catalogue_version) FROM public.support_resources AS r WHERE r.active),
    'resources', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'country_code', p.country_code, 'category', p.category,
               'name', p.name, 'description', p.description, 'phone', p.phone,
               'sms', p.sms, 'whatsapp', p.whatsapp, 'url', p.url, 'hours', p.hours,
               'languages', to_jsonb(p.languages), 'is_police', p.is_police,
               'verified_at', p.verified_at)
             ORDER BY (p.category <> 'emergency'), (p.country_code = 'XX'), p.sort_order, p.name COLLATE "C", p.id)
        FROM picked AS p), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.load_support_resources(p_catalogue jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version constant text := btrim(coalesce(p_catalogue ->> 'catalogue_version', ''));
  v_entries constant jsonb := p_catalogue -> 'resources';
  v_loaded int;
  v_inactive int;
BEGIN
  IF v_version = '' OR jsonb_typeof(v_entries) IS DISTINCT FROM 'array' OR jsonb_array_length(v_entries) = 0 THEN
    RAISE EXCEPTION 'support_resources:invalid_catalogue';
  END IF;
  -- Every entry an object with a uuid id (one without is a bad file, not a
  -- duplicate); ids compared as uuids, so letter case is no escape.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_entries) AS e
              WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
                 OR coalesce(e ->> 'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
    RAISE EXCEPTION 'support_resources:invalid_catalogue';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT (e ->> 'id')::uuid) FROM jsonb_array_elements(v_entries) AS e) THEN
    RAISE EXCEPTION 'support_resources:duplicate_id';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_entries) AS e
                  WHERE e ->> 'country_code' = 'XX' AND coalesce(e ->> 'url', '') <> '') THEN
    RAISE EXCEPTION 'support_resources:no_international_directory';
  END IF;

  INSERT INTO public.support_resources AS r
    (id, country_code, category, name, description, phone, sms, whatsapp, url, hours,
     languages, is_police, sort_order, verified_at, verified_by, catalogue_version, active)
  SELECT x.id, x.country_code, x.category, x.name, x.description, x.phone, x.sms, x.whatsapp,
         x.url, x.hours, coalesce(x.languages, '{}'), coalesce(x.is_police, false),
         coalesce(x.sort_order, 100), x.verified_at, x.verified_by, v_version, true
    FROM jsonb_to_recordset(v_entries) AS x(
           id uuid, country_code text, category text, name text, description text,
           phone text, sms text, whatsapp text, url text, hours text, languages text[],
           is_police boolean, sort_order int, verified_at date, verified_by text)
  ON CONFLICT (id) DO UPDATE
    SET country_code = EXCLUDED.country_code, category = EXCLUDED.category, name = EXCLUDED.name,
        description = EXCLUDED.description, phone = EXCLUDED.phone, sms = EXCLUDED.sms,
        whatsapp = EXCLUDED.whatsapp, url = EXCLUDED.url, hours = EXCLUDED.hours,
        languages = EXCLUDED.languages, is_police = EXCLUDED.is_police,
        sort_order = EXCLUDED.sort_order, verified_at = EXCLUDED.verified_at,
        verified_by = EXCLUDED.verified_by, catalogue_version = EXCLUDED.catalogue_version,
        active = true;
  GET DIAGNOSTICS v_loaded = ROW_COUNT;

  UPDATE public.support_resources AS r
     SET active = false
   WHERE r.active
     AND r.id NOT IN (SELECT (e ->> 'id')::uuid FROM jsonb_array_elements(v_entries) AS e);
  GET DIAGNOSTICS v_inactive = ROW_COUNT;

  RETURN jsonb_build_object('catalogue_version', v_version, 'loaded', v_loaded, 'deactivated', v_inactive);
END;
$$;

-- Revoked here as well as in the twin (the W1 precedent): the hosted
-- default privileges grant a new table and function to anon and
-- authenticated, and a late twin must not leave the table writable or the
-- loader callable. get_support_resources is the one client read and is
-- granted in the twin.
REVOKE ALL ON public.support_resources FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.load_support_resources(jsonb) FROM PUBLIC, anon, authenticated;

COMMIT;
