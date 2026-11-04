-- supabase/tests/opinion_filter_parity_contracts.sql
-- Spec 1 W9a (spec 7.1, review I-17; batch-2 review I-2): the SQL base and
-- match forms agree with the TypeScript port on EVERY code point, not only
-- on the shared goldens. The goldens' parity entry pins the sha256 of the
-- lines "<hex code point>\t<base form>\t<match form>\n" of x<c>x for every
-- code point in its ranges (surrogates excluded), in code point order,
-- UTF-8. supabase/functions/_shared/unicode_normaliser.test.ts checks the
-- same hash, so a PostgreSQL or ICU Unicode upgrade that moves any fold
-- fails one side: pin the character in the fold table's base.compat_pins.
-- One BEGIN ... ROLLBACK, nothing written. Run only on attune_spec3a, from
-- the repo root (the goldens file is read with \set):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_filter_parity_contracts.sql
\set goldens `cat supabase/tests/fixtures/unicode_normaliser_goldens.json`
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('private.normalize_for_filter(text)') IS NULL
     OR to_regprocedure('private.match_form(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W9a normaliser functions are missing';
  END IF;
END $$;

CREATE TEMP TABLE w9a_parity ON COMMIT DROP AS SELECT (:'goldens'::jsonb)->'parity' AS p;

DO $$
DECLARE
  v_p constant jsonb := (SELECT p FROM w9a_parity);
  v_hash text;
BEGIN
  IF v_p IS NULL OR jsonb_array_length(v_p->'ranges') < 2
     OR (v_p #>> '{ranges,0,0}')::int <> 1 OR (v_p #>> '{ranges,0,1}')::int < 262143 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the goldens lost their parity ranges';
  END IF;
  SELECT encode(sha256(convert_to(string_agg(
           to_hex(cp) || E'\t' || private.normalize_for_filter('x' || chr(cp) || 'x')
           || E'\t' || private.match_form('x' || chr(cp) || 'x') || E'\n', '' ORDER BY cp), 'UTF8')), 'hex')
    INTO v_hash
    FROM jsonb_array_elements(v_p->'ranges') AS r,
         generate_series((r->>0)::int, (r->>1)::int) AS cp
   WHERE cp NOT BETWEEN 55296 AND 57343;
  IF v_hash IS DISTINCT FROM v_p->>'sha256' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the per-code-point fold differs from the pinned parity hash (% vs %): pin the moved characters in base.compat_pins',
      v_hash, v_p->>'sha256';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_filter_parity_contracts: all held'; END $$;
ROLLBACK;
