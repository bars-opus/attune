-- supabase/tests/support_resources_contracts.sql
-- Spec 1 W7a (§4.2, §4.3 W7a, §7.1): support resources v2. Anyone reads the
-- directory through get_support_resources (anon too); emergency first,
-- then the country's own rows, then anywhere (XX); only active rows; no
-- client writes the table; the service-role loader replaces the catalogue
-- whole or not at all. Fixture rows only, never the shipped catalogue.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/support_resources_contracts.sql
-- Fixture ids 5f7a0000-0000-0000-0000-0000000000NN (spec §7.1's W7 range;
-- no person is needed, so no phone). Every refusal is checked by its
-- message or SQLSTATE.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f7a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- get_support_resources as [p_role] (anon or authenticated).
CREATE FUNCTION pg_temp.read_as(p_role text, p_country text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  v := public.get_support_resources(p_country);
  RESET ROLE;
  RETURN v;
END $$;

-- The SQLSTATE (or NULL) of [p_sql] run as [p_role].
CREATE FUNCTION pg_temp.client_error(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLSTATE;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- The loader as the service role: NULL, or the refusal's message.
CREATE FUNCTION pg_temp.load(p_catalogue jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    PERFORM public.load_support_resources(p_catalogue);
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- One catalogue entry (the file's shape).
CREATE FUNCTION pg_temp.entry(p_n text, p_country text, p_category text, p_name text,
                              p_sort int DEFAULT 100, p_url text DEFAULT NULL, p_phone text DEFAULT '0800 000 000')
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', pg_temp.id(p_n), 'country_code', p_country, 'category', p_category,
                            'name', p_name, 'phone', p_phone, 'url', p_url, 'languages', jsonb_build_array('en'),
                            'is_police', p_category = 'emergency', 'sort_order', p_sort,
                            'verified_at', '2026-11-03', 'verified_by', 'contract fixture');
$$;

-- Fixture rows only: whatever the scratch database holds is set aside
-- (rolled back with the rest).
DO $$
BEGIN
  IF to_regclass('public.support_resources') IS NOT NULL THEN
    DELETE FROM public.support_resources;
  END IF;
END $$;

-- =====================================================================
-- A. Objects and grants: anon and signed-in read through the function
--    only; nobody but the service role writes (spec §4.2, §7.1).
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.support_resources') IS NULL
     OR to_regprocedure('public.get_support_resources(text)') IS NULL
     OR to_regprocedure('public.load_support_resources(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W7a objects are missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.support_resources'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'support_resources') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: support_resources must have RLS on and no policy (read through the function only)';
  END IF;
  IF has_table_privilege('anon', 'public.support_resources', 'SELECT')
     OR has_table_privilege('anon', 'public.support_resources', 'INSERT')
     OR has_table_privilege('anon', 'public.support_resources', 'UPDATE')
     OR has_table_privilege('anon', 'public.support_resources', 'DELETE')
     OR has_table_privilege('authenticated', 'public.support_resources', 'SELECT')
     OR has_table_privilege('authenticated', 'public.support_resources', 'INSERT')
     OR has_table_privilege('authenticated', 'public.support_resources', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.support_resources', 'DELETE')
     OR NOT has_table_privilege('service_role', 'public.support_resources', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: support_resources table grants are wrong (no client write)';
  END IF;
  IF NOT has_function_privilege('anon', 'public.get_support_resources(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_support_resources(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_support_resources is not readable by anon and authenticated';
  END IF;
  IF has_function_privilege('anon', 'public.load_support_resources(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.load_support_resources(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.load_support_resources(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: load_support_resources must be the service role''s only';
  END IF;
END $$;

-- =====================================================================
-- B. Reading: emergency first, the country before anywhere, sort_order,
--    active rows only, never another country's (spec §4.3 W7a).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_names text;
BEGIN
  IF pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-1', 'resources', jsonb_build_array(
       pg_temp.entry('01', 'GH', 'dv', 'GH DV line', 10),
       pg_temp.entry('02', 'GH', 'emergency', 'GH emergency', 90),
       pg_temp.entry('03', 'GH', 'crisis', 'GH crisis line', 5),
       pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL),
       pg_temp.entry('05', 'GB', 'dv', 'GB DV line', 1),
       pg_temp.entry('06', 'GH', 'grief', 'GH grief line', 20),
       -- Same sort_order, mixed case: names sort bytewise (COLLATE "C",
       -- pre-flight PF-M3), so upper case comes first on every database
       -- and the bundled catalogue on the phone gives the same order.
       pg_temp.entry('08', 'GH', 'youth', 'GH apple line', 50),
       pg_temp.entry('09', 'GH', 'youth', 'GH Zulu line', 50)))) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid fixture catalogue was refused';
  END IF;
  UPDATE public.support_resources SET active = false WHERE id = pg_temp.id('06');

  v := pg_temp.read_as('anon', ' gh ');
  SELECT string_agg(x ->> 'name', ' | ' ORDER BY o) INTO v_names
    FROM jsonb_array_elements(v -> 'resources') WITH ORDINALITY AS t(x, o);
  IF v_names IS DISTINCT FROM 'GH emergency | GH crisis line | GH DV line | GH Zulu line | GH apple line | Anywhere directory' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s list is not emergency first, then the country by sort_order, then anywhere (inactive and other countries left out): %', v_names;
  END IF;
  IF (v ->> 'country') IS DISTINCT FROM 'GH' OR (v -> 'country_supported') IS DISTINCT FROM 'true'::jsonb
     OR (v ->> 'catalogue_version') IS DISTINCT FROM 'fixture-1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s answer has the wrong header: %', v - 'resources';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k)
       <> ARRAY['catalogue_version', 'country', 'country_supported', 'resources']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v -> 'resources' -> 0) AS k)
       <> ARRAY['category', 'country_code', 'description', 'hours', 'id', 'is_police', 'languages',
                'name', 'phone', 'sms', 'url', 'verified_at', 'whatsapp'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_support_resources returns other keys: %', v -> 'resources' -> 0;
  END IF;

  -- Signed in reads the same.
  IF pg_temp.read_as('authenticated', 'GH') IS DISTINCT FROM v THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in read differs from an anon one';
  END IF;

  -- A country with no list: anywhere only, and said so.
  FOREACH v_names IN ARRAY ARRAY['ZZ', 'zz', 'XX', '', 'Ghana'] LOOP
    v := pg_temp.read_as('anon', v_names);
    IF (v -> 'country_supported') IS DISTINCT FROM 'false'::jsonb
       OR jsonb_array_length(v -> 'resources') <> 1
       OR (v -> 'resources' -> 0 ->> 'country_code') IS DISTINCT FROM 'XX' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % without a list did not answer anywhere-only and unsupported: %', quote_literal(v_names), v;
    END IF;
  END LOOP;
  v := pg_temp.read_as('anon', NULL);
  IF (v -> 'country_supported') IS DISTINCT FROM 'false'::jsonb OR (v -> 'country') <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no country did not answer anywhere-only: %', v;
  END IF;
END $$;

-- =====================================================================
-- C. No client writes the directory, or reaches the loader (spec §7.1).
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.client_error('anon', format(
       'INSERT INTO public.support_resources (id, country_code, category, name, phone, verified_at, verified_by, catalogue_version) VALUES (%L, ''GH'', ''dv'', ''Fake line'', ''0800'', current_date, ''x'', ''x'')',
       pg_temp.id('90'))) IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'UPDATE public.support_resources SET phone = ''0800 999'' WHERE true') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'DELETE FROM public.support_resources WHERE true') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT count(*) FROM public.support_resources') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT public.load_support_resources(''{}''::jsonb)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.load_support_resources(''{}''::jsonb)') IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote the directory or reached the loader';
  END IF;
  IF (SELECT phone FROM public.support_resources WHERE id = pg_temp.id('01')) IS DISTINCT FROM '0800 000 000' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client changed a helpline number';
  END IF;
END $$;

-- =====================================================================
-- D. The loader: the whole file or nothing; a row the file drops goes
--    inactive; a bad file is refused by its message (plan P-3).
-- =====================================================================
DO $$
DECLARE
  v_got text;
BEGIN
  -- Version 2 drops GH crisis (03) and changes GH DV's number.
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-2', 'resources', jsonb_build_array(
             pg_temp.entry('01', 'GH', 'dv', 'GH DV line', 10, NULL, '0800 111 111'),
             pg_temp.entry('02', 'GH', 'emergency', 'GH emergency', 90),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: version 2 was refused: %', v_got;
  END IF;
  IF (SELECT active FROM public.support_resources WHERE id = pg_temp.id('03'))
     OR (SELECT active FROM public.support_resources WHERE id = pg_temp.id('05'))
     OR (SELECT phone FROM public.support_resources WHERE id = pg_temp.id('01')) IS DISTINCT FROM '0800 111 111'
     OR EXISTS (SELECT 1 FROM public.support_resources WHERE active AND catalogue_version <> 'fixture-2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a row the new catalogue dropped is still shown, or a change did not land';
  END IF;
  IF (pg_temp.read_as('anon', 'GH') ->> 'catalogue_version') IS DISTINCT FROM 'fixture-2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the answer does not name the loaded version';
  END IF;

  -- Refusals, each by its message, each leaving version 2 in place.
  IF pg_temp.load('{"resources": []}'::jsonb) IS DISTINCT FROM 'support_resources:invalid_catalogue'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
          pg_temp.entry('01', 'GH', 'dv', 'GH DV line'), pg_temp.entry('01', 'GH', 'dv', 'GH DV line twice'),
          pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))))
          IS DISTINCT FROM 'support_resources:duplicate_id'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
          pg_temp.entry('01', 'GH', 'dv', 'GH DV line'))))
          IS DISTINCT FROM 'support_resources:no_international_directory' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad catalogue was not refused by its message';
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'astrology', 'Not a category'),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_category_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown category was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'gh', 'dv', 'Lower-case country'),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_country_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lower-case country was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', 'Plain http', 1, 'http://example.org', NULL),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_url_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a link that is not https was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', 'No way to reach', 1, NULL, NULL),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_reachable_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an entry with no number or link was not refused by its check: %', v_got;
  END IF;
  -- A padded name would sort on its spaces here but trimmed on the phone
  -- (batch-1 review M1): refused, so both sides sort the same string.
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', ' Padded name '),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_name_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name with leading or trailing spaces was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', E'Tab after\t'),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF coalesce(v_got, '') !~ 'support_resources_name_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name with a trailing tab was not refused by its check: %', v_got;
  END IF;
  -- An entry without a usable id is a bad file, not a duplicate; the same
  -- uuid in two letter cases is a duplicate (review M2).
  IF pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
       pg_temp.entry('07', 'GH', 'dv', 'No id') - 'id',
       pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))))
       IS DISTINCT FROM 'support_resources:invalid_catalogue'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
       jsonb_set(pg_temp.entry('07', 'GH', 'dv', 'Not a uuid'), '{id}', '"line-7"'),
       pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))))
       IS DISTINCT FROM 'support_resources:invalid_catalogue'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
       pg_temp.entry('07', 'GH', 'dv', 'Lower-case id'),
       jsonb_set(pg_temp.entry('07', 'GH', 'dv', 'Upper-case id'), '{id}', to_jsonb(upper(pg_temp.id('07')::text))),
       pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))))
       IS DISTINCT FROM 'support_resources:duplicate_id' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an entry without a usable id, or an id in two cases, was not refused by its own message';
  END IF;
  IF EXISTS (SELECT 1 FROM public.support_resources WHERE active AND catalogue_version <> 'fixture-2')
     OR EXISTS (SELECT 1 FROM public.support_resources WHERE id = pg_temp.id('07')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused catalogue changed the directory';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'support_resources_contracts: all held'; END $$;

ROLLBACK;
