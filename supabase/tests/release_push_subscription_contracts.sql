-- supabase/tests/release_push_subscription_contracts.sql
-- Contracts for migrations 20261019110330/110335 (plan 1b final review I1).
-- A phone signed out offline could not tell the server to forget it, and no
-- session remains to do it later, so its push_tokens row stayed active and
-- the previous account's pushes could still reach it. The app keeps an
-- "owed release" (the subscription id) and sends it on the next start:
-- release_push_subscription deactivates exactly that id, for anon or a
-- signed-in caller, says nothing back, never moves the device, and push
-- tokens stay unreadable. Every check RAISEs.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('8d180000-0000-0000-0000-0000000000e1'), ('8d180000-0000-0000-0000-0000000000f2')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.row_of(p_sub text) RETURNS public.push_tokens LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM public.push_tokens WHERE token = p_sub $$;

-- The catalogue guards. Returns the first violation, or NULL.
CREATE FUNCTION pg_temp.static_violation() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT count(*) FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'release_push_subscription') <> 1
     OR NOT EXISTS (SELECT 1 FROM pg_proc p
                    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'release_push_subscription'
                      AND pg_get_function_identity_arguments(p.oid) = 'p_subscription_id text') THEN
    RETURN 'release_push_subscription is not exactly (p_subscription_id text)';
  END IF;
  IF (SELECT p.prorettype FROM pg_proc p
      WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'release_push_subscription')
     <> 'void'::regtype THEN
    RETURN 'release_push_subscription returns something (it must reveal nothing)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
             WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'release_push_subscription'
               AND (NOT p.prosecdef OR p.proconfig IS NULL
                    OR NOT ('search_path=""' = ANY (p.proconfig)))) THEN
    RETURN 'release_push_subscription is not SECURITY DEFINER with search_path pinned to ''''';
  END IF;
  IF NOT has_function_privilege('anon', 'public.release_push_subscription(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.release_push_subscription(text)', 'EXECUTE') THEN
    RETURN 'anon or authenticated cannot execute release_push_subscription';
  END IF;
  -- Releasing must not open the table: still no client privilege at all.
  IF has_table_privilege('anon', 'public.push_tokens', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
     OR has_any_column_privilege('anon', 'public.push_tokens', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    RETURN 'anon holds a privilege on push_tokens';
  END IF;
  RETURN NULL;
END $$;

-- The behaviour, run as anon against fresh rows. Returns the first
-- violation, or NULL.
CREATE FUNCTION pg_temp.behaviour_violation() RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  r public.push_tokens;
  v_count int;
BEGIN
  DELETE FROM public.push_tokens
  WHERE user_id IN ('8d180000-0000-0000-0000-0000000000e1', '8d180000-0000-0000-0000-0000000000f2');
  -- E's phone (released below) and E's other phone and F's phone (kept).
  INSERT INTO public.push_tokens (user_id, token, platform, is_active, updated_at) VALUES
    ('8d180000-0000-0000-0000-0000000000e1', 'e1000000-0000-4000-8000-0000000000a1', 'ios', true, now() - interval '1 day'),
    ('8d180000-0000-0000-0000-0000000000e1', 'e1000000-0000-4000-8000-0000000000a2', 'android', true, now() - interval '1 day'),
    ('8d180000-0000-0000-0000-0000000000f2', 'f2000000-0000-4000-8000-0000000000b1', 'ios', true, now() - interval '1 day');

  PERFORM set_config('role', 'anon', true);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  -- The device id as the SDK reports it (upper case): still that device.
  PERFORM public.release_push_subscription('E1000000-0000-4000-8000-0000000000A1');
  -- Idempotent: a retried owed release is not an error.
  PERFORM public.release_push_subscription('e1000000-0000-4000-8000-0000000000a1');
  -- An id nobody holds: no error, nothing changes, nothing said.
  PERFORM public.release_push_subscription('00000000-0000-4000-8000-000000000000');
  BEGIN
    PERFORM public.release_push_subscription('not-a-subscription-id');
    PERFORM set_config('role', 'none', true);
    RETURN 'a non-UUID subscription id was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.release_push_subscription(NULL);
    PERFORM set_config('role', 'none', true);
    RETURN 'a NULL subscription id was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'push_subscription:invalid' THEN RAISE; END IF;
  END;
  -- No read leak: anon still cannot see the table.
  BEGIN
    PERFORM count(*) FROM public.push_tokens;
    PERFORM set_config('role', 'none', true);
    RETURN 'anon read push_tokens';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('role', 'none', true);

  r := pg_temp.row_of('e1000000-0000-4000-8000-0000000000a1');
  IF r.is_active THEN RETURN 'the released device is still active'; END IF;
  IF r.user_id IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000e1' THEN
    RETURN 'releasing moved the device to another person';
  END IF;
  IF NOT (pg_temp.row_of('e1000000-0000-4000-8000-0000000000a2')).is_active THEN
    RETURN 'releasing one device stopped another device of the same person';
  END IF;
  IF NOT (pg_temp.row_of('f2000000-0000-4000-8000-0000000000b1')).is_active THEN
    RETURN 'releasing one device stopped someone else''s device';
  END IF;
  SELECT count(*) INTO v_count FROM public.push_tokens
  WHERE token = '00000000-0000-4000-8000-000000000000';
  IF v_count <> 0 THEN RETURN 'releasing an unknown id created a row'; END IF;

  -- A signed-in caller may release too (the owed release of the previous
  -- account, sent after someone signed in on this phone).
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '8d180000-0000-0000-0000-0000000000f2', 'role', 'authenticated')::text, true);
  PERFORM public.release_push_subscription('e1000000-0000-4000-8000-0000000000a2');
  PERFORM set_config('role', 'none', true);
  r := pg_temp.row_of('e1000000-0000-4000-8000-0000000000a2');
  IF r.is_active OR r.user_id IS DISTINCT FROM '8d180000-0000-0000-0000-0000000000e1' THEN
    RETURN 'a signed-in caller''s release did not just deactivate that device';
  END IF;
  RETURN NULL;
END $$;

-- 1. The catalogue guards hold.
DO $$
DECLARE v text := pg_temp.static_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;

-- 2. The behaviour holds.
DO $$
DECLARE v text := pg_temp.behaviour_violation();
BEGIN
  IF v IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: %', v; END IF;
END $$;

-- 3. Mutation check: a release that ignores the id stops every device.
SAVEPOINT mutate_any;
CREATE OR REPLACE FUNCTION public.release_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false, updated_at = now() WHERE is_active;
$$;
DO $$
BEGIN
  IF pg_temp.behaviour_violation() IS NULL THEN
    RAISE EXCEPTION 'mutation check broken: check 2 did not see a release that stops every device';
  END IF;
  RAISE NOTICE 'mutation check: a release without the id filter is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_any;

-- 3b. Mutation check: an owner filter (unregister's auth.uid() rule) means a
--     signed-out phone (anon, no uid) can never pay its owed release.
SAVEPOINT mutate_owner;
CREATE OR REPLACE FUNCTION public.release_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_subscription_id IS NULL
     OR p_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = lower(p_subscription_id) AND user_id = auth.uid() AND is_active;
END $$;
DO $$
BEGIN
  IF pg_temp.behaviour_violation() IS DISTINCT FROM 'the released device is still active' THEN
    RAISE EXCEPTION 'mutation check broken: check 2 did not see an owner-filtered release (got %)', pg_temp.behaviour_violation();
  END IF;
  RAISE NOTICE 'mutation check: an owner-filtered release is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_owner;

-- 4. Mutation check: without lower() the SDK's upper-case id misses.
SAVEPOINT mutate_case;
CREATE OR REPLACE FUNCTION public.release_push_subscription(p_subscription_id text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_subscription_id IS NULL
     OR p_subscription_id !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RAISE EXCEPTION 'push_subscription:invalid';
  END IF;
  UPDATE public.push_tokens SET is_active = false, updated_at = now()
  WHERE token = p_subscription_id AND is_active;
END $$;
-- The idempotent lower-case retry in check 2 would still release it, so
-- drive the upper-case call alone.
DO $$
BEGIN
  DELETE FROM public.push_tokens WHERE token = 'e1000000-0000-4000-8000-0000000000c1';
  INSERT INTO public.push_tokens (user_id, token, platform)
  VALUES ('8d180000-0000-0000-0000-0000000000e1', 'e1000000-0000-4000-8000-0000000000c1', 'ios');
  PERFORM set_config('role', 'anon', true);
  PERFORM public.release_push_subscription('E1000000-0000-4000-8000-0000000000C1');
  PERFORM set_config('role', 'none', true);
  IF NOT (pg_temp.row_of('e1000000-0000-4000-8000-0000000000c1')).is_active THEN
    RAISE EXCEPTION 'mutation check broken: an upper-case id was released without lower()';
  END IF;
  RAISE NOTICE 'mutation check: without lower() the upper-case id stays active (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_case;

-- 5. Mutation check: a release that answers with the owner trips check 1.
SAVEPOINT mutate_reveal;
DROP FUNCTION public.release_push_subscription(text);
CREATE FUNCTION public.release_push_subscription(p_subscription_id text)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.push_tokens SET is_active = false WHERE token = lower(p_subscription_id) RETURNING user_id;
$$;
GRANT EXECUTE ON FUNCTION public.release_push_subscription(text) TO anon, authenticated;
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'release_push_subscription returns something (it must reveal nothing)' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see a revealing return (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: a release that returns the owner is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_reveal;

-- 6. Mutation check: an unpinned search_path trips check 1.
SAVEPOINT mutate_search_path;
ALTER FUNCTION public.release_push_subscription(text) RESET search_path;
DO $$
BEGIN
  IF pg_temp.static_violation() NOT LIKE '%search_path pinned%' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see the unpinned search_path (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: an unpinned search_path is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_search_path;

-- 7. Mutation check: without the anon grant a signed-out phone can never
--    pay its owed release (check 1).
SAVEPOINT mutate_anon;
REVOKE EXECUTE ON FUNCTION public.release_push_subscription(text) FROM anon;
DO $$
BEGIN
  IF pg_temp.static_violation() IS DISTINCT FROM 'anon or authenticated cannot execute release_push_subscription' THEN
    RAISE EXCEPTION 'mutation check broken: check 1 did not see the missing anon grant (got %)', pg_temp.static_violation();
  END IF;
  RAISE NOTICE 'mutation check: a missing anon grant is caught (as expected)';
END $$;
ROLLBACK TO SAVEPOINT mutate_anon;

DO $$ BEGIN RAISE NOTICE 'release_push_subscription_contracts: all held'; END $$;
ROLLBACK;
