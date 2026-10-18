-- supabase/tests/user_timezone_contracts.sql
-- Recipient time zone (Spec 1b Task 1): users.timezone is self-only and
-- set through a validating RPC; notification_recipient_tz returns a valid
-- zone from the user's own report, then Planning/Together's, then the
-- couple map's, else NULL (unknown -- never a guess). Every check RAISEs.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('8b100000-0000-0000-0000-0000000000a1'),
  ('8b100000-0000-0000-0000-0000000000b2'),
  ('8b100000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('8b100000-0000-0000-0000-0000000000a1', '+233598100001', 'Zone A'),
  ('8b100000-0000-0000-0000-0000000000b2', '+233598100002', 'Zone B'),
  ('8b100000-0000-0000-0000-0000000000c3', '+233598100003', 'Zone C')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at) VALUES
  ('8b200000-0000-0000-0000-000000000001', '8b100000-0000-0000-0000-0000000000a1',
   '8b100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now())
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The column exists; the app may call the setter; nobody but the server
--    reaches the resolver.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'timezone') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: users.timezone does not exist';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.set_my_timezone(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the app cannot report its zone';
  END IF;
  IF has_function_privilege('anon', 'public.set_my_timezone(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.notification_recipient_tz(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.notification_recipient_tz(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the setter or the resolver is open to the wrong role';
  END IF;
END $$;

-- 2. The app reports a zone; the resolver uses it.
DO $$
DECLARE v text;
BEGIN
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_my_timezone('Africa/Accra');
  RESET ROLE;
  SELECT timezone INTO v FROM public.users WHERE id = '8b100000-0000-0000-0000-0000000000a1';
  IF v IS DISTINCT FROM 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_timezone stored %', v;
  END IF;
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000a1') <> 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the resolver ignored the user''s own zone';
  END IF;
END $$;

-- 3. Abbreviations, offsets, legacy names, blanks, NULL and made-up zones
--    are refused, and the stored zone is unchanged.
DO $$
DECLARE v_zone text; v_msg text;
BEGIN
  FOREACH v_zone IN ARRAY ARRAY['BST', 'UTC+3', 'Japan', '', 'Mars/Olympus'] LOOP
    PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
    BEGIN
      PERFORM public.set_my_timezone(v_zone);
      RAISE EXCEPTION 'CONTRACT VIOLATED: "%" accepted as a zone', v_zone;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'timezone:invalid_input' THEN RAISE; END IF;
    END;
    RESET ROLE;
  END LOOP;
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
  BEGIN
    PERFORM public.set_my_timezone(NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: NULL accepted as a zone';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'timezone:invalid_input' THEN RAISE; END IF;
  END;
  RESET ROLE;
  IF (SELECT timezone FROM public.users WHERE id = '8b100000-0000-0000-0000-0000000000a1') <> 'Africa/Accra' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused zone changed the stored one';
  END IF;
END $$;

-- 4. A zone is coarse location: the partner can never read it.
DO $$
DECLARE v int;
BEGIN
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v FROM public.users
   WHERE id = '8b100000-0000-0000-0000-0000000000a1' AND timezone IS NOT NULL;
  RESET ROLE;
  IF v <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner can read my time zone'; END IF;
END $$;

-- 5. Fallbacks, each validated: Planning's zone, then the couple map's,
--    else unknown (NULL, never a UTC guess); a garbage value anywhere is
--    skipped.
DO $$
BEGIN
  -- B never reported; Planning stored a zone.
  INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone)
  VALUES ('8b200000-0000-0000-0000-000000000001', '8b100000-0000-0000-0000-0000000000b2', 'Europe/London');
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000b2') <> 'Europe/London' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Planning''s zone was not used';
  END IF;
  -- Planning's row turns to garbage; the couple map knows better.
  UPDATE public.planning_member_settings SET timezone = 'Mars/Olympus'
   WHERE user_id = '8b100000-0000-0000-0000-0000000000b2';
  INSERT INTO public.partner_presence (user_id, relationship_id, timezone)
  VALUES ('8b100000-0000-0000-0000-0000000000b2', '8b200000-0000-0000-0000-000000000001', 'Asia/Tokyo');
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000b2') <> 'Asia/Tokyo' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a garbage Planning zone was used, or the map''s was skipped';
  END IF;
  -- C has nothing anywhere: unknown, not a guess.
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no zone resolved to a guess (%), not NULL',
      public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3');
  END IF;
  -- A client can write users.timezone directly (table-level UPDATE on its own
  -- row); garbage there is skipped too.
  UPDATE public.users SET timezone = 'Nope/Zone' WHERE id = '8b100000-0000-0000-0000-0000000000c3';
  IF public.notification_recipient_tz('8b100000-0000-0000-0000-0000000000c3') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a garbage users.timezone was trusted';
  END IF;
END $$;

-- 6. A signed-in user whose profile row does not exist yet (the report runs
--    at sign-in; the users row comes later, with the EULA or onboarding):
--    the setter refuses, so the app does not remember the zone as sent and
--    reports it again on the next open (final review C1).
DO $$
DECLARE v_msg text;
BEGIN
  INSERT INTO auth.users (id) VALUES ('8b100000-0000-0000-0000-0000000000d4') ON CONFLICT (id) DO NOTHING;
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000d4');
  BEGIN
    PERFORM public.set_my_timezone('Africa/Accra');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a zone was "stored" for a user with no profile row';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'timezone:no_profile' THEN RAISE; END IF;
  END;
  RESET ROLE;
  -- An unchanged zone for an existing user is still a success, not a refusal.
  PERFORM pg_temp.as_user('8b100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_my_timezone('Africa/Accra');
  RESET ROLE;
END $$;

DO $$ BEGIN RAISE NOTICE 'user_timezone_contracts: all held'; END $$;
ROLLBACK;
