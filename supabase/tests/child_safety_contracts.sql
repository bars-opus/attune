-- supabase/tests/child_safety_contracts.sql
-- Spec 1 W6c (§3.15, §4.2, §4.3 W6c, §6, §7.1): "Report a concern about a
-- child". A report is sent through the RPC only, 5 a person a day, read by
-- the service role only; nothing names, finds or tells the reported
-- person; the safety webhook learns a count and a time, never the words.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/child_safety_contracts.sql
-- Fixture ids 5f6c0000-0000-0000-0000-0000000000NN; phones +15558401NN
-- (§7.1's 84xx range), set on auth.users and public.users. Every refusal
-- is checked by its message.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f6c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (pg_temp.id(p_n), '15558401' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, path)
  VALUES (pg_temp.id(p_n), '15558401' || p_n, 'Person ' || p_n, 'just_me');
  RETURN pg_temp.id(p_n);
END $$;

-- [p_user]'s report: NULL, or the refusal.
CREATE FUNCTION pg_temp.report(p_user uuid, p_where text, p_details text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.report_child_safety_concern(p_where, p_details);
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

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

-- =====================================================================
-- A. Objects, grants, no client read or write (spec §4.2, §7.1).
-- =====================================================================
DO $$
DECLARE
  v_cols text;
BEGIN
  IF to_regclass('public.child_safety_reports') IS NULL
     OR to_regprocedure('public.report_child_safety_concern(text,text)') IS NULL
     OR to_regprocedure('public.child_safety_alerts_due()') IS NULL
     OR to_regprocedure('public.mark_child_safety_alerts_sent(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6c objects are missing';
  END IF;
  SELECT string_agg(c.column_name, ',' ORDER BY c.column_name) INTO v_cols
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.table_name = 'child_safety_reports';
  IF v_cols IS DISTINCT FROM 'alerted_at,created_at,details,id,reporter_user_id,reviewed_at,status,where_seen' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: child_safety_reports has columns beyond the spec (nothing may name the reported person): %', v_cols;
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.child_safety_reports'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: RLS is off on child_safety_reports';
  END IF;
  IF has_table_privilege('authenticated', 'public.child_safety_reports', 'SELECT')
     OR has_table_privilege('authenticated', 'public.child_safety_reports', 'INSERT')
     OR has_table_privilege('authenticated', 'public.child_safety_reports', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.child_safety_reports', 'DELETE')
     OR has_table_privilege('anon', 'public.child_safety_reports', 'SELECT')
     OR has_table_privilege('anon', 'public.child_safety_reports', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.child_safety_reports', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.child_safety_reports', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: child_safety_reports grants are wrong (no client read or write)';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.report_child_safety_concern(text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.report_child_safety_concern(text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.child_safety_alerts_due()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.mark_child_safety_alerts_sent(uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.child_safety_alerts_due()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.mark_child_safety_alerts_sent(uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6c function grants are wrong';
  END IF;
  -- Nothing tells anyone: the RPC writes the report and nothing else.
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.report_child_safety_concern(text,text)'::regprocedure)
       ~* '(notification|push|enqueue|net\.http|invoke_edge_function|relationships|profiles)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: report_child_safety_concern reaches beyond the report (nothing may tell or find anyone)';
  END IF;
  -- Fix round 1 (review M-2): one count at a time per person, so two quick
  -- sends can't both be the 5th.
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.report_child_safety_concern(text,text)'::regprocedure)
       !~ 'pg_advisory_xact_lock\(hashtextextended\(''child-report:'' \|\| v_uid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: report_child_safety_concern takes no per-person lock before counting (two sends could both be the 5th)';
  END IF;
  -- The W1 health body names no W6 table (identity contract I4; plan P-11).
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_identity_health()'::regprocedure) ~* 'child_safety_reports' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_identity_health names child_safety_reports itself (keep it in private.identity_health_w6a)';
  END IF;
END $$;

-- =====================================================================
-- B. Sending: through the RPC only, validated, 5 a day, no client read.
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.person('01');
  v_kofi constant uuid := pg_temp.person('02');
  v_got text;
  i int;
BEGIN
  v_got := pg_temp.report(v_ama, 'chat', '  Someone in a group chat asked a 14-year-old for photos.  ');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid report was refused: %', v_got;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.child_safety_reports
                  WHERE reporter_user_id = v_ama AND where_seen = 'chat' AND status = 'new'
                    AND details = 'Someone in a group chat asked a 14-year-old for photos.'
                    AND reviewed_at IS NULL AND alerted_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report was not stored as sent (trimmed, new)';
  END IF;
  -- Where is optional.
  IF pg_temp.report(v_kofi, NULL, 'Saw it somewhere') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report without a place was refused';
  END IF;

  IF pg_temp.report(v_ama, 'chat', '   ') IS DISTINCT FROM 'child_report:invalid'
     OR pg_temp.report(v_ama, 'chat', NULL) IS DISTINCT FROM 'child_report:invalid'
     OR pg_temp.report(v_ama, 'chat', repeat('x', 2001)) IS DISTINCT FROM 'child_report:invalid'
     OR pg_temp.report(v_ama, 'forum', 'words') IS DISTINCT FROM 'child_report:invalid'
     OR pg_temp.report(NULL, 'chat', 'words') IS DISTINCT FROM 'child_report:not_signed_in' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad report was not refused by its message';
  END IF;
  IF pg_temp.report(v_ama, 'other', repeat('x', 2000)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 2,000 characters were refused';
  END IF;
  -- Fix round 1 (review M-1): newlines and tabs are blank too, and trimmed.
  IF pg_temp.report(v_ama, 'chat', E'\n\t \r\n\t') IS DISTINCT FROM 'child_report:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report of only newlines and tabs was not refused with child_report:invalid';
  END IF;
  v_got := pg_temp.report(v_kofi, 'chat', E'\t\n wrapped in newlines \r\n\t');
  IF v_got IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.child_safety_reports
                     WHERE reporter_user_id = v_kofi AND details = 'wrapped in newlines') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report wrapped in newlines and tabs was not stored trimmed';
  END IF;

  -- 5 a person a day (Ama has sent 2).
  FOR i IN 3..5 LOOP
    v_got := pg_temp.report(v_ama, 'stories', 'report ' || i);
    IF v_got IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: report % of 5 was refused: %', i, v_got;
    END IF;
  END LOOP;
  IF pg_temp.report(v_ama, 'stories', 'report 6') IS DISTINCT FROM 'child_report:limit' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 6th report in a day was not refused with child_report:limit';
  END IF;
  IF pg_temp.report(v_kofi, 'dating', 'still mine to send') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s limit stopped another';
  END IF;
  UPDATE public.child_safety_reports SET created_at = now() - interval '25 hours'
   WHERE reporter_user_id = v_ama AND details = 'report 3';
  IF pg_temp.report(v_ama, 'opinions', 'a day later') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report older than a day still counted';
  END IF;

  -- No client reads or writes the table, even its own reports.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ama, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_ama::text, true);
  IF pg_temp.client_error('authenticated', 'SELECT count(*) FROM public.child_safety_reports') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', format(
          'INSERT INTO public.child_safety_reports (reporter_user_id, details) VALUES (%L, ''x'')', v_ama)) IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT count(*) FROM public.child_safety_reports') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.report_child_safety_concern(''chat'', ''x'')') IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client reached child_safety_reports outside the RPC';
  END IF;

  -- The reporter's account goes; the report stays, unattributed.
  DELETE FROM public.users WHERE id = v_kofi;
  DELETE FROM auth.users WHERE id = v_kofi;
  IF NOT EXISTS (SELECT 1 FROM public.child_safety_reports
                  WHERE details = 'still mine to send' AND reporter_user_id IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report went with its reporter''s account';
  END IF;
END $$;

-- =====================================================================
-- C. The safety webhook learns a count and a time, never the words
--    (plan P-24).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_ids uuid[];
  v_health jsonb;
  v_old bigint;
  v_all bigint;
BEGIN
  -- Fix round 1 (ruling): identity health counts the reports not yet
  -- alerted 15 minutes after they came in, so the team sees them even with
  -- no webhook set. One just past 15 minutes counts, one just under doesn't.
  UPDATE public.child_safety_reports SET created_at = now() - interval '16 minutes'
   WHERE details = 'Saw it somewhere';
  UPDATE public.child_safety_reports SET created_at = now() - interval '14 minutes'
   WHERE details = 'wrapped in newlines';
  SELECT count(*) FILTER (WHERE r.created_at < now() - interval '15 minutes'), count(*)
    INTO v_old, v_all
    FROM public.child_safety_reports AS r WHERE r.alerted_at IS NULL;
  EXECUTE 'SET LOCAL ROLE service_role';
  v_health := public.get_identity_health();
  RESET ROLE;
  IF v_old < 2 OR v_old >= v_all
     OR (v_health ->> 'child_safety_reports_unalerted')::bigint IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health does not count exactly the reports unalerted for over 15 minutes (% of %): %', v_old, v_all, v_health;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.child_safety_alerts_due();
  RESET ROLE;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at']
     OR v::text ~ '(photos|report|mine|xxxx)'
     OR NOT pg_input_is_valid(v ->> 'first_at', 'timestamptz')
     OR NOT pg_input_is_valid(v ->> 'last_at', 'timestamptz') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an alert carries more than ids, a count and times: %', v;
  END IF;
  IF (v ->> 'count')::int < 7 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: new reports were not due for the webhook: %', v;
  END IF;
  SELECT array_agg(x::uuid) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_child_safety_alerts_sent(v_ids);
  v := public.child_safety_alerts_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alerted reports were due again';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v_health := public.get_identity_health();
  RESET ROLE;
  IF (v_health ->> 'child_safety_reports_unalerted')::bigint IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health still counts alerted reports: %', v_health;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'child_safety_contracts: all held'; END $$;

ROLLBACK;
