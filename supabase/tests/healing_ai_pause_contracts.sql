-- Spec 1 W9e (spec 2.5, 7.1, 8 W9e; owner approval O2): healing_ai_insights
-- exists and is off; production refuses to switch it on without the W9c
-- clinician gate's evidence and lists it if it is on; clients read it and
-- never write it; the development script turns it on.
-- Run from the repo root (section E reads the dev script):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/healing_ai_pause_contracts.sql
\set dev_script `cat supabase/sql/dev_enable_spec1_flags.sql`
BEGIN;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text
LANGUAGE plpgsql AS $fn$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$fn$;

SELECT set_config('w9e.dev_script', :'dev_script', true) AS dev_script_loaded \g /dev/null

DO $$
DECLARE
  v_msg text;
BEGIN
  -- A. The flag row exists, off.
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags
                  WHERE key = 'healing_ai_insights' AND enabled = false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights is missing or on';
  END IF;

  -- B. Its production gate row: the W9c clinician gate, no evidence yet.
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates
                  WHERE flag_key = 'healing_ai_insights'
                    AND gate LIKE 'W9e gate (the W9c clinician gate):%'
                    AND review_ref IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights has no clinician gate row';
  END IF;

  -- C. Production refuses it without evidence; on in development is
  -- listed the moment the project reads production.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_msg := pg_temp.error_of($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'healing_ai_insights'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: healing_ai_insights went on in production without evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'healing_ai_insights';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF NOT EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'healing_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production_flag_violations missed healing_ai_insights';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'healing_ai_insights';

  -- D. Clients read flags and never write them; the gate table is the owner's.
  IF NOT has_table_privilege('authenticated', 'public.feature_flags', 'SELECT')
     OR has_table_privilege('authenticated', 'public.feature_flags', 'INSERT, UPDATE, DELETE, TRUNCATE')
     OR has_table_privilege('anon', 'public.feature_flags', 'SELECT, INSERT, UPDATE, DELETE')
     OR has_table_privilege('authenticated', 'private.flag_production_gates', 'SELECT, INSERT, UPDATE, DELETE')
     OR has_table_privilege('anon', 'private.flag_production_gates', 'SELECT, INSERT, UPDATE, DELETE')
     -- Fix round 1 (batch-1-review.md M-2): column grants, anon's other
     -- table rights, and service_role on the gate table (the twin revokes it).
     OR has_any_column_privilege('authenticated', 'public.feature_flags', 'INSERT, UPDATE')
     OR has_any_column_privilege('anon', 'public.feature_flags', 'SELECT, INSERT, UPDATE')
     OR has_table_privilege('anon', 'public.feature_flags', 'TRUNCATE, REFERENCES, TRIGGER')
     OR has_table_privilege('service_role', 'private.flag_production_gates', 'SELECT, INSERT, UPDATE, DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the flag tables'' grants are wrong';
  END IF;

  -- E. The development script turns it on with the other Spec 1 flags.
  IF position($t$('healing_ai_insights', true)$t$ IN current_setting('w9e.dev_script')) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dev_enable_spec1_flags.sql does not turn healing_ai_insights on';
  END IF;

  RAISE NOTICE 'healing_ai_pause_contracts: PASS';
END $$;

ROLLBACK;
