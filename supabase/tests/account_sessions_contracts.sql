-- supabase/tests/account_sessions_contracts.sql
-- "Where you're signed in" (Spec 2 Task 1; research 06 §3 F7 (1)): a member
-- lists only their own live sessions, the current one marked; a device names
-- only its own session; nobody reads session_devices directly. Every check
-- RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('9a100000-0000-0000-0000-0000000000a1'),
  ('9a100000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9a100000-0000-0000-0000-0000000000a1', '+233597100001', 'Device A'),
  ('9a100000-0000-0000-0000-0000000000b2', '+233597100002', 'Device B')
ON CONFLICT (id) DO NOTHING;
INSERT INTO auth.sessions (id, user_id, created_at, updated_at, refreshed_at, not_after) VALUES
  ('9a300000-0000-0000-0000-000000000001', '9a100000-0000-0000-0000-0000000000a1', now() - interval '30 days', now() - interval '2 days', (now() - interval '1 hour') AT TIME ZONE 'UTC', NULL),
  ('9a300000-0000-0000-0000-000000000002', '9a100000-0000-0000-0000-0000000000a1', now() - interval '1 day', now() - interval '1 day', NULL, NULL),
  ('9a300000-0000-0000-0000-000000000003', '9a100000-0000-0000-0000-0000000000a1', now() - interval '90 days', now() - interval '80 days', NULL, now() - interval '1 day'),
  ('9a300000-0000-0000-0000-000000000004', '9a100000-0000-0000-0000-0000000000b2', now(), now(), NULL, NULL);

CREATE FUNCTION pg_temp.as_session(p_user uuid, p_session uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated', 'session_id', p_session)::text, true);
END $$;

-- 1. Grants: the two RPCs for the app; session_devices for nobody.
DO $$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.list_my_sessions()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.register_my_device(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app cannot reach its sessions';
  END IF;
  IF has_function_privilege('anon', 'public.list_my_sessions()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.register_my_device(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can reach sessions';
  END IF;
  IF has_table_privilege('authenticated', 'public.session_devices', 'SELECT')
     OR has_table_privilege('authenticated', 'public.session_devices', 'INSERT')
     OR has_table_privilege('anon', 'public.session_devices', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: session_devices is client-reachable';
  END IF;
END $$;

-- 2. A device names its own session; the list shows A's two live sessions,
--    the current one marked, the expired one gone, newest activity first.
DO $$
DECLARE v_n int; v_current uuid; v_label text; v_first uuid;
BEGIN
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000a1', '9a300000-0000-0000-0000-000000000002');
  PERFORM public.register_my_device('iPhone or iPad · iOS 17.2', 'ios');
  SELECT count(*) INTO v_n FROM public.list_my_sessions();
  SELECT session_id INTO v_current FROM public.list_my_sessions() WHERE is_current;
  SELECT device_label INTO v_label FROM public.list_my_sessions() WHERE session_id = '9a300000-0000-0000-0000-000000000002';
  SELECT session_id INTO v_first FROM public.list_my_sessions() LIMIT 1;
  RESET ROLE;
  IF v_n <> 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: A sees % sessions (want 2 live)', v_n; END IF;
  IF v_current IS DISTINCT FROM '9a300000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the current session is not marked (%)', v_current;
  END IF;
  IF v_label IS DISTINCT FROM 'iPhone or iPad · iOS 17.2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device label was not stored (%)', v_label;
  END IF;
  -- Session 1 refreshed an hour ago: the most recently active.
  IF v_first IS DISTINCT FROM '9a300000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not ordered by last activity (%)', v_first;
  END IF;
END $$;

-- 3. Owner-only: B sees only B; B cannot name A's session.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000b2', '9a300000-0000-0000-0000-000000000004');
  SELECT count(*) INTO v_n FROM public.list_my_sessions()
   WHERE session_id IN ('9a300000-0000-0000-0000-000000000001', '9a300000-0000-0000-0000-000000000002');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: B sees A''s sessions'; END IF;
  -- A claim naming A's session under B's sub is ignored: register keys by sub too.
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000b2', '9a300000-0000-0000-0000-000000000001');
  BEGIN
    PERFORM public.register_my_device('Spoof', 'android');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a device named another account''s session';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'session:unknown' THEN RAISE; END IF;
  END;
  RESET ROLE;
END $$;

-- 4. Input: no session claim, an over-long label, an unknown platform.
DO $$
DECLARE v_msg text;
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', '9a100000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.register_my_device('Phone', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: registered without a session';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:unknown' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM pg_temp.as_session('9a100000-0000-0000-0000-0000000000a1', '9a300000-0000-0000-0000-000000000002');
  BEGIN
    PERFORM public.register_my_device(repeat('x', 61), 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 61-character label was stored';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:invalid_input' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.register_my_device('Phone', 'toaster');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown platform was stored';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'session:invalid_input' THEN RAISE; END IF;
  END;
  RESET ROLE;
END $$;

-- Review M-8: an empty search_path, so nothing resolves through a schema
-- a caller could shadow.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('register_my_device', 'list_my_sessions')
      AND NOT (coalesce(p.proconfig, '{}') @> ARRAY['search_path=""'])
  ) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sessions RPC has a non-empty search_path';
  END IF;
END $$;

-- Review M-9 (c): anon is refused at run time, not only by the grant table.
DO $$
DECLARE v_ok boolean := false;
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  BEGIN
    PERFORM * FROM public.list_my_sessions();
  EXCEPTION WHEN insufficient_privilege THEN
    v_ok := true;
  END;
  RESET ROLE;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon could call list_my_sessions';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'account_sessions_contracts: all held'; END $$;
ROLLBACK;
