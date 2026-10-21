-- supabase/tests/deactivate_other_push_subscriptions_contracts.sql
-- Contracts for migration 20261019110220. Checks 4b-4d: register refuses a
-- revoked session.
-- Chat review #18 (fix I2): "sign out other devices" revokes their refresh
-- tokens, but a revoked phone only notices on its next token refresh (~1 h)
-- and keeps receiving pushes meanwhile. deactivate_other_push_subscriptions
-- stops every other device of the caller at once: only the caller's rows,
-- never the device asked to keep, bad input refused, anon denied. Every
-- check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d180000-0000-0000-0000-0000000000c1'), ('8d180000-0000-0000-0000-0000000000d2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO auth.sessions (id, user_id) VALUES
  ('8d185e55-0000-4000-8000-0000000000c1', '8d180000-0000-0000-0000-0000000000c1'),
  ('8d185e55-0000-4000-8000-0000000000d2', '8d180000-0000-0000-0000-0000000000d2')
ON CONFLICT (id) DO NOTHING;
-- C's time-boxed session that has run out (not_after in the past).
INSERT INTO auth.sessions (id, user_id, not_after) VALUES
  ('8d185e55-0000-4000-8000-0000000000f1', '8d180000-0000-0000-0000-0000000000c1', now() - interval '1 minute')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.session_of(p uuid) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT s.id FROM auth.sessions s WHERE s.user_id = p ORDER BY s.id LIMIT 1 $$;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated',
    'session_id', pg_temp.session_of(p))::text, true) $$;
-- A request on a given session (live, revoked, or none in the token).
CREATE FUNCTION pg_temp.as_session(p uuid, p_session text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    (jsonb_build_object('sub', p, 'role', 'authenticated')
     || CASE WHEN p_session IS NULL THEN '{}'::jsonb
             ELSE jsonb_build_object('session_id', p_session) END)::text, true) $$;
-- register on a revoked session, a missing session_id, an expired session
-- and a live one. Returns the first violation, or NULL.
CREATE FUNCTION pg_temp.session_violation() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  -- Revoked ("sign out other devices" deleted its auth.sessions row).
  PERFORM pg_temp.as_session('8d180000-0000-0000-0000-0000000000c1', '8d185e55-0000-4000-8000-00000000dead');
  BEGIN
    PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000e1', 'ios');
    PERFORM set_config('role', 'none', true);
    RETURN 'a revoked session registered a device';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:session_revoked' THEN RAISE; END IF;
  END;
  -- Another person's session id does not count as the caller's.
  PERFORM pg_temp.as_session('8d180000-0000-0000-0000-0000000000c1', '8d185e55-0000-4000-8000-0000000000d2');
  BEGIN
    PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000e2', 'ios');
    PERFORM set_config('role', 'none', true);
    RETURN 'someone else''s session registered a device';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:session_revoked' THEN RAISE; END IF;
  END;
  -- An expired session.
  PERFORM pg_temp.as_session('8d180000-0000-0000-0000-0000000000c1', '8d185e55-0000-4000-8000-0000000000f1');
  BEGIN
    PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000e5', 'ios');
    PERFORM set_config('role', 'none', true);
    RETURN 'an expired session registered a device';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:session_revoked' THEN RAISE; END IF;
  END;
  -- No session_id in the token: fail closed.
  PERFORM pg_temp.as_session('8d180000-0000-0000-0000-0000000000c1', NULL);
  BEGIN
    PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000e3', 'ios');
    PERFORM set_config('role', 'none', true);
    RETURN 'a token without session_id registered a device';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:session_revoked' THEN RAISE; END IF;
  END;
  -- Live session: registers.
  PERFORM pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
  PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000e4', 'ios');
  PERFORM set_config('role', 'none', true);
  IF NOT pg_temp.active('c1000000-0000-4000-8000-0000000000e4') THEN
    RETURN 'a live session could not register';
  END IF;
  IF pg_temp.active('c1000000-0000-4000-8000-0000000000e1')
     OR pg_temp.active('c1000000-0000-4000-8000-0000000000e2')
     OR pg_temp.active('c1000000-0000-4000-8000-0000000000e3') THEN
    RETURN 'a refused register left an active row';
  END IF;
  RETURN NULL;
END $$;
CREATE FUNCTION pg_temp.active(p_sub text) RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT coalesce((SELECT is_active FROM public.push_tokens WHERE token = p_sub), false) $$;
-- The scenario, as one function so each mutation check can replay it.
-- Returns the first violation, or NULL when every rule holds.
CREATE FUNCTION pg_temp.scenario_violation() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  -- C has three phones, D one.
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
  PERFORM public.register_push_subscription('c1000000-0000-4000-8000-000000000001', 'ios');
  PERFORM public.register_push_subscription('c1000000-0000-4000-8000-000000000002', 'android');
  PERFORM public.register_push_subscription('c1000000-0000-4000-8000-000000000003', 'ios');
  PERFORM pg_temp.as_user('8d180000-0000-0000-0000-0000000000d2');
  PERFORM public.register_push_subscription('d2000000-0000-4000-8000-000000000001', 'ios');
  -- C signs out her other devices from phone 1 (id sent in upper case).
  PERFORM pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
  PERFORM public.deactivate_other_push_subscriptions('C1000000-0000-4000-8000-000000000001');
  PERFORM set_config('role', 'none', true);
  IF NOT pg_temp.active('c1000000-0000-4000-8000-000000000001') THEN
    RETURN 'the device asked to keep was deactivated';
  END IF;
  IF pg_temp.active('c1000000-0000-4000-8000-000000000002')
     OR pg_temp.active('c1000000-0000-4000-8000-000000000003') THEN
    RETURN 'another device of the caller is still active';
  END IF;
  IF NOT pg_temp.active('d2000000-0000-4000-8000-000000000001') THEN
    RETURN 'another person''s device was deactivated';
  END IF;
  RETURN NULL;
END $$;
CREATE FUNCTION pg_temp.static_violation() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  IF has_function_privilege('anon', 'public.deactivate_other_push_subscriptions(text)', 'EXECUTE') THEN
    RETURN 'anon can execute deactivate_other_push_subscriptions';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.deactivate_other_push_subscriptions(text)', 'EXECUTE') THEN
    RETURN 'authenticated cannot execute deactivate_other_push_subscriptions';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace
               AND p.proname = 'deactivate_other_push_subscriptions'
               AND (NOT p.prosecdef OR p.proconfig IS NULL
                    OR NOT ('search_path=""' = ANY (p.proconfig)))) THEN
    RETURN 'deactivate_other_push_subscriptions is not SECURITY DEFINER with search_path pinned to ''''';
  END IF;
  IF (SELECT array_agg(pg_get_function_identity_arguments(p.oid))
      FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname = 'deactivate_other_push_subscriptions')
     IS DISTINCT FROM ARRAY['p_keep_subscription_id text'] THEN
    RETURN 'the deactivate_other_push_subscriptions signature changed (no user-id overload)';
  END IF;
  RETURN NULL;
END $$;

-- 1. Only the caller's other devices stop; the kept one and other people's stay.
SAVEPOINT s1;
DO $$
DECLARE v text := pg_temp.scenario_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;
ROLLBACK TO SAVEPOINT s1;

-- 2. No device to keep (this phone has no push subscription): all of the
--    caller's devices stop, nobody else's.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
SELECT public.register_push_subscription('c1000000-0000-4000-8000-000000000009', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000d2');
SELECT public.register_push_subscription('d2000000-0000-4000-8000-000000000009', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
SELECT public.deactivate_other_push_subscriptions(NULL);
RESET ROLE;
DO $$
BEGIN
  IF pg_temp.active('c1000000-0000-4000-8000-000000000009') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with nothing to keep, a device of the caller stayed active';
  END IF;
  IF NOT pg_temp.active('d2000000-0000-4000-8000-000000000009') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with nothing to keep, another person''s device was deactivated';
  END IF;
END $$;

-- 3. Bad input and no session are refused; anon cannot call it.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
DO $$
BEGIN
  BEGIN
    PERFORM public.deactivate_other_push_subscriptions('not-a-subscription-id');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-UUID keep id was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
END $$;
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.deactivate_other_push_subscriptions(NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request with no signed-in user was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:not_signed_in' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM public.deactivate_other_push_subscriptions(NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon called deactivate_other_push_subscriptions';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

-- 4. The catalogue guards hold.
DO $$
DECLARE v text := pg_temp.static_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;

-- 4b. register refuses a revoked, foreign, expired or missing session and
--     accepts a live one (fix round 1 addendum: a phone signed out from
--     another device cannot re-register while its access token lives).
SAVEPOINT s4b;
DO $$
DECLARE v text := pg_temp.session_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;
ROLLBACK TO SAVEPOINT s4b;

-- 4c. Mutation check: Task 6's register (no session check) lets the revoked
--     phone back in (check 4b trips). Body as in 20261019110200.
SAVEPOINT mutate_session;
CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at, updated_at)
  VALUES (v_uid, lower(p_subscription_id), p_platform, true, now(), now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        is_active = true, updated_at = now();
END;
$$;
DO $$
BEGIN
  IF pg_temp.session_violation() IS DISTINCT FROM 'a revoked session registered a device' THEN
    RAISE EXCEPTION 'mutation check broken: check 4b did not see the missing session check (got %)', pg_temp.session_violation();
  END IF;
  RAISE NOTICE 'mutation check: without the session check a revoked phone re-registered (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_session;

-- 4d. Mutation check: failing open on a token without session_id (check 4b trips).
SAVEPOINT mutate_fail_open;
CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_session text := auth.jwt()->>'session_id';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  IF v_session IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM auth.sessions s
       WHERE s.id::text = v_session AND s.user_id = v_uid
         AND (s.not_after IS NULL OR s.not_after > now())) THEN
    RAISE EXCEPTION 'push_subscription:session_revoked';
  END IF;
  INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at, updated_at)
  VALUES (v_uid, lower(p_subscription_id), p_platform, true, now(), now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
        is_active = true, updated_at = now();
END;
$$;
DO $$
BEGIN
  IF pg_temp.session_violation() IS DISTINCT FROM 'a token without session_id registered a device' THEN
    RAISE EXCEPTION 'mutation check broken: check 4b did not see the fail-open (got %)', pg_temp.session_violation();
  END IF;
  RAISE NOTICE 'mutation check: failing open on a missing session_id let a token in (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_fail_open;

-- 4e. A revoked (or session-less) phone cannot silence the owner's live
--     phones: deactivate_other_push_subscriptions needs a live session
--     too (fix round 2 #2).
CREATE FUNCTION pg_temp.revoked_deactivate_violation() RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_session text;
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM pg_temp.as_user('8d180000-0000-0000-0000-0000000000c1');
  PERFORM public.register_push_subscription('c1000000-0000-4000-8000-0000000000a7', 'ios');
  FOREACH v_session IN ARRAY ARRAY['8d185e55-0000-4000-8000-00000000dead',
                                   '8d185e55-0000-4000-8000-0000000000f1', NULL] LOOP
    PERFORM pg_temp.as_session('8d180000-0000-0000-0000-0000000000c1', v_session);
    BEGIN
      PERFORM public.deactivate_other_push_subscriptions('c1000000-0000-4000-8000-0000000000b7');
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'push_subscription:session_revoked' THEN RAISE; END IF;
    END;
  END LOOP;
  PERFORM set_config('role', 'none', true);
  IF NOT pg_temp.active('c1000000-0000-4000-8000-0000000000a7') THEN
    RETURN 'a revoked session silenced the owner''s live phone';
  END IF;
  RETURN NULL;
END $$;
SAVEPOINT s4e;
DO $$
DECLARE v text := pg_temp.revoked_deactivate_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;
ROLLBACK TO SAVEPOINT s4e;

-- 4f. Mutation check: without the session check the revoked phone stops
--     the owner's live phone (check 4e trips). Body as before round 2.
SAVEPOINT mutate_deactivate_session;
CREATE OR REPLACE FUNCTION public.deactivate_other_push_subscriptions(p_keep_subscription_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'push_subscription:not_signed_in'; END IF;
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE user_id = v_uid AND is_active
    AND token IS DISTINCT FROM lower(p_keep_subscription_id);
END;
$$;
DO $$
BEGIN
  IF pg_temp.revoked_deactivate_violation() IS DISTINCT FROM 'a revoked session silenced the owner''s live phone' THEN
    RAISE EXCEPTION 'mutation check broken: check 4e did not see the missing session check (got %)', pg_temp.revoked_deactivate_violation();
  END IF;
  RAISE NOTICE 'mutation check: without the session check a revoked phone silenced the owner''s phone (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_deactivate_session;

-- 5. Mutation check: without the owner filter the caller stops someone
--    else's phone (check 1 trips).
SAVEPOINT mutate_owner;
CREATE OR REPLACE FUNCTION public.deactivate_other_push_subscriptions(p_keep_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE is_active AND token IS DISTINCT FROM lower(p_keep_subscription_id);
$$;
DO $$
BEGIN
  IF pg_temp.scenario_violation() IS DISTINCT FROM 'another person''s device was deactivated' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see the missing owner filter (got %)', pg_temp.scenario_violation();
  END IF;
  RAISE NOTICE 'mutation check: without the auth.uid() filter another person''s device stopped (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_owner;

-- 6. Mutation check: ignoring the keep id stops this phone too (check 1 trips).
SAVEPOINT mutate_keep;
CREATE OR REPLACE FUNCTION public.deactivate_other_push_subscriptions(p_keep_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE user_id = auth.uid() AND is_active;
$$;
DO $$
BEGIN
  IF pg_temp.scenario_violation() IS DISTINCT FROM 'the device asked to keep was deactivated' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see the ignored keep id (got %)', pg_temp.scenario_violation();
  END IF;
  RAISE NOTICE 'mutation check: ignoring the keep id stopped this phone too (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_keep;

-- 7. Mutation check: a no-op leaves the revoked phones receiving (check 1 trips).
SAVEPOINT mutate_noop;
CREATE OR REPLACE FUNCTION public.deactivate_other_push_subscriptions(p_keep_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT $$;
DO $$
BEGIN
  IF pg_temp.scenario_violation() IS DISTINCT FROM 'another device of the caller is still active' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see the no-op (got %)', pg_temp.scenario_violation();
  END IF;
  RAISE NOTICE 'mutation check: a no-op left the other devices active (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_noop;

-- 8. Mutation check: anon EXECUTE trips check 4.
SAVEPOINT mutate_anon;
GRANT EXECUTE ON FUNCTION public.deactivate_other_push_subscriptions(text) TO anon;
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'anon can execute deactivate_other_push_subscriptions' THEN
    RAISE EXCEPTION 'mutation check broken: check 4 did not see anon EXECUTE (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: anon EXECUTE is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_anon;

-- 9. Mutation check: an unpinned search_path trips check 4.
SAVEPOINT mutate_search_path;
ALTER FUNCTION public.deactivate_other_push_subscriptions(text) RESET search_path;
DO $$
BEGIN
  IF pg_temp.static_violation() NOT LIKE '%search_path pinned%' THEN
    RAISE EXCEPTION 'mutation check broken: check 4 did not see the unpinned search_path (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: an unpinned search_path is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_search_path;

DO $$ BEGIN RAISE NOTICE 'deactivate_other_push_subscriptions_contracts: all held'; END $$;
ROLLBACK;
