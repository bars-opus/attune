-- supabase/tests/push_subscriptions_contracts.sql
-- Chat review #18 (07 H-3): a push reaches only devices the recipient's own
-- signed-in session registered. push_tokens is written through two RPCs as
-- auth.uid(); a client cannot write or read it directly; a device moves to
-- whoever signs in on it; sign-out releases it. Every check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d180000-0000-0000-0000-0000000000a1'), ('8d180000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
-- Each person's live session: register refuses a revoked one (fix round 1
-- addendum, migration 20261019110220), so the JWT carries its session_id.
INSERT INTO auth.sessions (id, user_id) VALUES
  ('8d185e55-0000-4000-8000-0000000000a1', '8d180000-0000-0000-0000-0000000000a1'),
  ('8d185e55-0000-4000-8000-0000000000b2', '8d180000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.session_of(p uuid) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT s.id FROM auth.sessions s WHERE s.user_id = p ORDER BY s.id LIMIT 1 $$;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated',
    'session_id', pg_temp.session_of(p))::text, true) $$;
CREATE FUNCTION pg_temp.owner_of(p_sub text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$
  SELECT user_id FROM public.push_tokens WHERE token = p_sub AND is_active $$;
-- The catalogue guards, as one function so the mutation checks can show each
-- of them trip. Returns the first violation, or NULL when all hold.
CREATE FUNCTION pg_temp.static_violation() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  IF has_table_privilege('authenticated', 'public.push_tokens', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_table_privilege('anon', 'public.push_tokens', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
    RETURN 'a client role holds a privilege on push_tokens';
  END IF;
  -- Column grants survive REVOKE ALL ON TABLE and are invisible to
  -- has_table_privilege, so check them separately.
  IF has_any_column_privilege('authenticated', 'public.push_tokens', 'SELECT,INSERT,UPDATE,REFERENCES')
     OR has_any_column_privilege('anon', 'public.push_tokens', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    RETURN 'a client role holds a column privilege on push_tokens';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'push_tokens') THEN
    RETURN 'a policy exists on push_tokens';
  END IF;
  IF has_function_privilege('anon', 'public.register_push_subscription(text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.unregister_push_subscription(text)', 'EXECUTE') THEN
    RETURN 'anon can execute a push subscription RPC';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.register_push_subscription(text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.unregister_push_subscription(text)', 'EXECUTE') THEN
    RETURN 'authenticated cannot execute a push subscription RPC';
  END IF;
  -- Exactly these two signatures: no overload that takes a user id.
  IF (SELECT array_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' ORDER BY p.proname)
      FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('register_push_subscription', 'unregister_push_subscription'))
     IS DISTINCT FROM ARRAY['register_push_subscription(p_subscription_id text, p_platform text)',
                            'unregister_push_subscription(p_subscription_id text)'] THEN
    RETURN 'the push subscription RPC signatures changed';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace
               AND p.proname IN ('register_push_subscription', 'unregister_push_subscription')
               AND (NOT p.prosecdef OR p.proconfig IS NULL
                    OR NOT ('search_path=""' = ANY (p.proconfig)))) THEN
    RETURN 'a push subscription RPC is not SECURITY DEFINER with search_path pinned to ''''';
  END IF;
  -- Legacy rows were deactivated; every active row is RPC-shaped.
  IF EXISTS (SELECT 1 FROM public.push_tokens
             WHERE is_active
               AND (token !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                    OR platform NOT IN ('ios', 'android'))) THEN
    RETURN 'an active push_tokens row is not a OneSignal subscription id from the RPC';
  END IF;
  RETURN NULL;
END $$;

-- Plan 1b final review M5: the table itself admits only the two platforms
-- the RPC accepts (the CHECK used to allow 'web' as well). True when a
-- 'web' row can be written at all, even by the table owner.
CREATE FUNCTION pg_temp.web_admitted() RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    INSERT INTO public.push_tokens (user_id, token, platform, is_active)
    VALUES ('8d180000-0000-0000-0000-0000000000a1', 'web00000-0000-4000-8000-000000000000', 'web', false);
    DELETE FROM public.push_tokens WHERE token = 'web00000-0000-4000-8000-000000000000';
    RETURN true;
  EXCEPTION WHEN check_violation THEN
    RETURN false;
  END;
END $$;

-- 1. A signs in on a phone: its subscription is hers.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios');
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios'); -- idempotent
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: registering did not attach the device to the caller';
  END IF;
END $$;

-- 2. Nobody writes or reads the table directly, and bad input is refused.
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.push_tokens (user_id, token, platform)
    VALUES ('8d180000-0000-0000-0000-0000000000a1', '99999999-2222-4333-8444-555555555555', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote push_tokens directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM count(*) FROM public.push_tokens;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client read push_tokens directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.register_push_subscription('not-a-subscription-id', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-UUID subscription id was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'web');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown platform was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
END $$;

-- 2b. No session, no write: a request without a signed-in user is refused.
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.register_push_subscription('22222222-2222-4333-8444-555555555555', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request with no signed-in user registered a device';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:not_signed_in' THEN RAISE; END IF;
  END;
END $$;

-- 2c. anon cannot call either RPC or touch the table.
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM public.register_push_subscription('33333333-2222-4333-8444-555555555555', 'ios');
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon registered a device';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.unregister_push_subscription('11111111-2222-4333-8444-555555555555');
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon called unregister_push_subscription';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM count(*) FROM public.push_tokens;
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon read push_tokens';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');

-- 3. The same phone, a new account: the device moves to B; A's unregister
--    of a device that is no longer hers is a no-op.
SELECT public.register_push_subscription('11111111-2222-4333-8444-555555555555', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.unregister_push_subscription('11111111-2222-4333-8444-555555555555');
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000b2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registration did not move the device to the new account (or A released B''s device)';
  END IF;
END $$;

-- 4. Sign-out: B releases the device; nothing targets it any more.
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
SELECT public.unregister_push_subscription('11111111-2222-4333-8444-555555555555');
DO $$
BEGIN
  IF pg_temp.owner_of('11111111-2222-4333-8444-555555555555') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sign-out did not release the device';
  END IF;
END $$;

-- 5. Only the newest ten devices per person stay active.
DO $$
DECLARE i int;
BEGIN
  FOR i IN 1..12 LOOP
    PERFORM public.register_push_subscription(
      format('%s-aaaa-4bbb-8ccc-dddddddddddd', lpad(i::text, 8, '0')), 'android');
  END LOOP;
END $$;
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.push_tokens WHERE user_id = '8d180000-0000-0000-0000-0000000000b2' AND is_active) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: active devices per person are not capped at ten';
  END IF;
  -- All twelve share one updated_at inside this transaction: the device
  -- that just registered must still be the one that survives the cap.
  IF NOT EXISTS (SELECT 1 FROM public.push_tokens
                 WHERE token = '00000012-aaaa-4bbb-8ccc-dddddddddddd' AND is_active) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the device that just registered was capped out';
  END IF;
  IF has_function_privilege('anon', 'public.register_push_subscription(text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.unregister_push_subscription(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can touch push subscriptions';
  END IF;
  IF has_table_privilege('anon', 'public.push_tokens', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can read push_tokens';
  END IF;
END $$;

-- 5b. The cap keeps exactly ten even when every row ties on updated_at and
--     the new device sorts last by id (deterministic form of check 5).
INSERT INTO public.push_tokens (id, user_id, token, platform, is_active, updated_at)
SELECT format('00000000-0000-4000-8000-%s', lpad(i::text, 12, '0'))::uuid,
       '8d180000-0000-0000-0000-0000000000a1',
       format('a0000000-0000-4000-8000-%s', lpad(i::text, 12, '0')), 'ios', true, now()
FROM generate_series(1, 10) i;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.register_push_subscription('ffffffff-0000-4000-8000-000000000001', 'ios');
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.push_tokens WHERE user_id = '8d180000-0000-0000-0000-0000000000a1' AND is_active) <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: on an updated_at tie the cap left % active devices, not ten',
      (SELECT count(*) FROM public.push_tokens WHERE user_id = '8d180000-0000-0000-0000-0000000000a1' AND is_active);
  END IF;
  IF pg_temp.owner_of('ffffffff-0000-4000-8000-000000000001') IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: on an updated_at tie the device that just registered was capped out';
  END IF;
END $$;

-- 5c. The catalogue guards all hold (see pg_temp.static_violation).
DO $$
DECLARE v text := pg_temp.static_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;

-- 5d. push_tokens refuses a 'web' row outright (M5).
DO $$
BEGIN
  IF pg_temp.web_admitted() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: push_tokens admits platform ''web''';
  END IF;
END $$;

-- 6. Mutation check: with the old open policy and grant back, check 2 is violated.
SAVEPOINT mutate;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO authenticated;
CREATE POLICY users_own_tokens ON public.push_tokens FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
INSERT INTO public.push_tokens (user_id, token, platform)
VALUES ('8d180000-0000-0000-0000-0000000000b2', '88888888-2222-4333-8444-555555555555', 'ios');
DO $$ BEGIN RAISE NOTICE 'mutation check: with the old policy a client wrote push_tokens directly (as expected)'; END $$;
RESET ROLE;
DO $$
BEGIN
  IF pg_temp.static_violation() IS NULL THEN
    RAISE EXCEPTION 'mutation check broken: check 5c did not see the reopened table';
  END IF;
END $$;
ROLLBACK TO SAVEPOINT mutate;

-- 7. Mutation check: an unregister that ignores the owner lets A release
--    B's device (check 3 is violated).
SAVEPOINT mutate_unregister;
CREATE OR REPLACE FUNCTION public.unregister_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = lower(p_subscription_id) AND is_active;
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
SELECT public.register_push_subscription('77777777-2222-4333-8444-555555555555', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.unregister_push_subscription('77777777-2222-4333-8444-555555555555');
RESET ROLE;
DO $$
BEGIN
  IF pg_temp.owner_of('77777777-2222-4333-8444-555555555555') IS NOT NULL THEN
    RAISE EXCEPTION 'mutation check broken: A could not release B''s device even without the owner filter';
  END IF;
  RAISE NOTICE 'mutation check: without the auth.uid() owner filter A released B''s device (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_unregister;

-- 8. Mutation check: a register that keeps the old owner leaves the phone
--    receiving the previous account's pushes (check 3 is violated).
SAVEPOINT mutate_move;
CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO public.push_tokens (user_id, token, platform)
  VALUES (auth.uid(), lower(p_subscription_id), p_platform)
  ON CONFLICT (token) DO UPDATE SET is_active = true, updated_at = now();
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.register_push_subscription('66666666-2222-4333-8444-555555555555', 'ios');
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000b2');
SELECT public.register_push_subscription('66666666-2222-4333-8444-555555555555', 'ios');
RESET ROLE;
DO $$
BEGIN
  IF pg_temp.owner_of('66666666-2222-4333-8444-555555555555') IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'mutation check broken: the device moved even without the owner update';
  END IF;
  RAISE NOTICE 'mutation check: without moving the owner the phone stayed with the previous account (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_move;

-- 9. Mutation check: without the cap a person accumulates devices (check 5).
SAVEPOINT mutate_cap;
CREATE OR REPLACE FUNCTION public.register_push_subscription(p_subscription_id text, p_platform text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO public.push_tokens (user_id, token, platform)
  VALUES (auth.uid(), lower(p_subscription_id), p_platform)
  ON CONFLICT (token) DO UPDATE
    SET user_id = EXCLUDED.user_id, is_active = true, updated_at = now();
$$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('8d180000-0000-0000-0000-0000000000a1');
SELECT public.register_push_subscription('55555555-2222-4333-8444-555555555555', 'ios');
RESET ROLE;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.push_tokens WHERE user_id = '8d180000-0000-0000-0000-0000000000a1' AND is_active) <= 10 THEN
    RAISE EXCEPTION 'mutation check broken: the cap held without the cap';
  END IF;
  RAISE NOTICE 'mutation check: without the cap an eleventh device stayed active (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_cap;

-- 10. Mutation check: anon EXECUTE trips check 5c.
SAVEPOINT mutate_anon;
GRANT EXECUTE ON FUNCTION public.register_push_subscription(text, text) TO anon;
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'anon can execute a push subscription RPC' THEN
    RAISE EXCEPTION 'mutation check broken: check 5c did not see anon EXECUTE (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: anon EXECUTE on register_push_subscription is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_anon;

-- 11. Mutation check: an unpinned search_path trips check 5c.
SAVEPOINT mutate_search_path;
ALTER FUNCTION public.unregister_push_subscription(text) RESET search_path;
DO $$
BEGIN
  IF pg_temp.static_violation() NOT LIKE '%search_path pinned%' THEN
    RAISE EXCEPTION 'mutation check broken: check 5c did not see the unpinned search_path (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: an unpinned search_path is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_search_path;

-- 12. Mutation check: a legacy (pre-RPC) active row trips check 5c.
SAVEPOINT mutate_legacy;
INSERT INTO public.push_tokens (user_id, token, platform)
VALUES ('8d180000-0000-0000-0000-0000000000a1', 'apns-hex-token-from-the-old-direct-insert', 'ios');
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'an active push_tokens row is not a OneSignal subscription id from the RPC' THEN
    RAISE EXCEPTION 'mutation check broken: check 5c did not see a legacy active row (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: an active legacy token row is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_legacy;

-- 13. Mutation check: a column-level grant trips check 5c.
SAVEPOINT mutate_column_grant;
GRANT SELECT (token) ON public.push_tokens TO authenticated;
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'a client role holds a column privilege on push_tokens' THEN
    RAISE EXCEPTION 'mutation check broken: check 5c did not see a column grant (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: a column-level SELECT grant to authenticated is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_column_grant;

-- 14. Mutation check: the old CHECK (ios, android, web) trips check 5d.
SAVEPOINT mutate_platform;
ALTER TABLE public.push_tokens DROP CONSTRAINT push_tokens_platform_check;
ALTER TABLE public.push_tokens ADD CONSTRAINT push_tokens_platform_check
  CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text, 'web'::text]));
DO $$
BEGIN
  IF NOT pg_temp.web_admitted() THEN
    RAISE EXCEPTION 'mutation check broken: check 5d did not see the old CHECK admit ''web''';
  END IF;
  RAISE NOTICE 'mutation check: the old platform CHECK admitting ''web'' is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_platform;

DO $$ BEGIN RAISE NOTICE 'push_subscriptions_contracts: all held'; END $$;
ROLLBACK;
