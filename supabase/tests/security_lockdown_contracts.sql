-- supabase/tests/security_lockdown_contracts.sql
-- Spec 3b plan review C3, I4 (2026-10-18): data and functions that were open
-- to the anon key. analysis_sessions had RLS off with anon SELECT (conflict
-- scores, pursuer, suggested insights); six 36-question / import functions
-- kept PostgreSQL's default PUBLIC execute, one of them deleting insights.
BEGIN;
DO $$
DECLARE v_fn text;
BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.analysis_sessions'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: analysis_sessions has RLS off';
  END IF;
  IF has_table_privilege('anon', 'public.analysis_sessions', 'SELECT')
     OR has_table_privilege('authenticated', 'public.analysis_sessions', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can read analysis_sessions';
  END IF;
  FOREACH v_fn IN ARRAY ARRAY['public.forum_topic_tags', 'public.opinion_tags', 'public.tags'] LOOP
    IF has_table_privilege('anon', v_fn, 'INSERT') OR has_table_privilege('authenticated', v_fn, 'INSERT')
       OR has_table_privilege('authenticated', v_fn, 'UPDATE') OR has_table_privilege('authenticated', v_fn, 'DELETE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write % directly', v_fn;
    END IF;
  END LOOP;
  FOREACH v_fn IN ARRAY ARRAY[
    'public.get_thirty_six_seen_map(uuid)',
    'public.mark_thirty_six_questions_seen(uuid,uuid[])',
    'public.mark_thirty_six_round_complete(uuid)',
    'public.complete_thirty_six_chapter(uuid)',
    'public.replace_thirty_six_question(uuid,uuid,text)',
    'public.remove_import_derived_evidence(uuid)'
  ] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: anon can execute %', v_fn;
    END IF;
  END LOOP;
  IF has_function_privilege('authenticated', 'public.remove_import_derived_evidence(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can delete import-derived insights';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.mark_thirty_six_round_complete(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app can no longer complete a 36-question round';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'security_lockdown_contracts: all held'; END $$;
ROLLBACK;
