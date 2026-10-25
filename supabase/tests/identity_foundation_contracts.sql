-- supabase/tests/identity_foundation_contracts.sql
-- Spec 1 W1 (identity foundation) §7.1: users and profiles lockdown (W1a),
-- metrics, birth dates, holds, paths and home state (W1b), environment,
-- flags, public config and identity health (W1c). One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql
-- Fixture ids 5f1a0000-0000-0000-0000-0000000000NN (relationships ...00000001NN);
-- phones +15558100NN, set on auth.users and public.users. Plain INSERTs, so a
-- leftover fixture fails loudly instead of being skipped. Every refusal is
-- checked by its exact message.
BEGIN;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_anon() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
END $$;

-- An Auth user with a verified phone; with a name, also its users row.
CREATE FUNCTION pg_temp.make_account(p_id uuid, p_phone text, p_name text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (p_id, p_phone, now());
  IF p_name IS NOT NULL THEN
    INSERT INTO public.users (id, phone, display_name) VALUES (p_id, p_phone, p_name);
  END IF;
END $$;

-- Runs p_sql as the current role and returns the refusal's message, or NULL
-- when it succeeded. Only the refusals these contracts expect are caught.
CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege OR check_violation THEN
  RETURN SQLERRM;
END $$;

-- =====================================================================
-- A. users (W1a; Q5, research 10 F-1): the client changes only its name,
--    avatar and time zone; it never inserts its own row; phone is copied
--    from auth.users. Fixtures 01-03.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.verified_phone(uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'path') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1a objects are missing (users.path, public.verified_phone)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000001', '+15558100001', 'Ama W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000002', '+15558100002', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000003', '+15558100003', 'Kofi W1');
END $$;

DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000001';
  v_new constant uuid := '5f1a0000-0000-0000-0000-000000000002';
  v_col text;
  v_bad text;
  v_msg text;
  v_n int;
BEGIN
  -- Grants: UPDATE on exactly three columns; INSERT on none; SELECT kept.
  SELECT string_agg(a.attname, ', ' ORDER BY a.attname) INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND a.attname NOT IN ('display_name', 'avatar_url', 'timezone')
     AND has_column_privilege('authenticated', 'public.users', a.attname, 'UPDATE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated may UPDATE users.%', v_bad;
  END IF;
  SELECT string_agg(a.attname, ', ' ORDER BY a.attname) INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND (has_column_privilege('authenticated', 'public.users', a.attname, 'INSERT')
          OR has_column_privilege('anon', 'public.users', a.attname, 'INSERT'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client may INSERT users.%', v_bad;
  END IF;
  -- anon writes no users row at all (P-10; the hosted default privileges
  -- would otherwise give it table DML).
  SELECT string_agg(a.attname, ', ' ORDER BY a.attname) INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND has_column_privilege('anon', 'public.users', a.attname, 'UPDATE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may UPDATE users.%', v_bad;
  END IF;
  IF has_table_privilege('anon', 'public.users', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may DELETE users';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.users', 'display_name', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.users', 'avatar_url', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.users', 'timezone', 'UPDATE')
     OR NOT has_table_privilege('authenticated', 'public.users', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the client lost a users grant it still needs';
  END IF;

  -- Behaviour: each server-owned column is refused by the grant itself.
  FOREACH v_col IN ARRAY ARRAY['phone', 'mode', 'path', 'path_previous', 'path_chosen_at',
                               'phone_released_at', 'eula_version', 'eula_accepted_at'] LOOP
    PERFORM pg_temp.as_user(v_me);
    v_msg := pg_temp.error_of(format('UPDATE public.users SET %I = %s WHERE id = %L', v_col,
      CASE v_col
        WHEN 'phone' THEN quote_literal('+15558100099')
        WHEN 'mode' THEN quote_literal('dating')
        WHEN 'path' THEN quote_literal('dating')
        WHEN 'path_previous' THEN quote_literal('dating')
        WHEN 'eula_version' THEN quote_literal('2')
        ELSE 'now()'
      END, v_me));
    RESET ROLE;
    IF v_msg IS DISTINCT FROM 'permission denied for table users' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote users.% directly (got %)', v_col, coalesce(v_msg, 'no error');
    END IF;
  END LOOP;

  -- The three self-service columns still work for the owner of the row.
  PERFORM pg_temp.as_user(v_me);
  UPDATE public.users
     SET display_name = 'Ama Renamed', avatar_url = 'https://example.invalid/a.png', timezone = 'Africa/Accra'
   WHERE id = v_me;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner could not update name, avatar and time zone (% rows)', v_n;
  END IF;

  -- No client creates its own users row.
  PERFORM pg_temp.as_user(v_new);
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.users (id, phone, display_name) VALUES (%L, %L, %L)', v_new, '+15558100002', 'Kwame W1'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'permission denied for table users' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client inserted its own users row (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- display_name: 40 characters at most for every new write.
  v_msg := pg_temp.error_of(format('UPDATE public.users SET display_name = repeat(%L, 41) WHERE id = %L', 'a', v_me));
  IF v_msg IS DISTINCT FROM 'new row for relation "users" violates check constraint "users_display_name_length"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 41-character users.display_name was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- users.mode is retired, and says so.
  IF coalesce(col_description('public.users'::regclass,
       (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.users'::regclass AND attname = 'mode')::int), '')
     NOT LIKE 'Retired (Spec 1 W1).%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: users.mode is not marked retired';
  END IF;
END $$;

-- =====================================================================
-- B. The phone is Auth's (W1a): users.phone follows the verified Auth phone
--    and is NULL whenever there is none (batch 1 re-review 2, R2-1: a
--    removed, blank or unconfirmed Auth phone clears it, confirming one
--    writes it), and verified_phone reads only a confirmed phone.
-- =====================================================================
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000003';
BEGIN
  UPDATE auth.users SET phone = '+15558100093' WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Auth phone change did not reach public.users';
  END IF;
  UPDATE auth.users SET phone = NULL WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a removed Auth phone stayed in public.users.phone';
  END IF;
  -- A blank Auth phone is no phone: it clears the mirror to NULL, never '',
  -- so a second blank account doesn't hit users_phone_key (fix round 1,
  -- minor #2).
  UPDATE auth.users SET phone = '+15558100093' WHERE id = v_me;
  UPDATE auth.users SET phone = '' WHERE id = v_me;
  BEGIN
    UPDATE auth.users SET phone = '  ' WHERE id = '5f1a0000-0000-0000-0000-000000000001';
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second blank Auth phone failed the mirror (%)', SQLERRM;
  END;
  IF (SELECT count(*) FROM public.users
       WHERE id IN (v_me, '5f1a0000-0000-0000-0000-000000000001') AND phone IS NULL) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blank Auth phone did not clear public.users.phone';
  END IF;

  -- An unconfirmed Auth phone is no phone; confirming it writes it.
  UPDATE auth.users SET phone = '+15558100093', phone_confirmed_at = NULL WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed Auth phone reached public.users.phone';
  END IF;
  UPDATE auth.users SET phone_confirmed_at = now() WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: confirming the Auth phone did not reach public.users.phone';
  END IF;
  IF public.verified_phone(v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verified_phone did not return the confirmed Auth phone';
  END IF;
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_me;
  IF public.verified_phone(v_me) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verified_phone returned an unconfirmed phone';
  END IF;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed Auth phone stayed in public.users.phone';
  END IF;
  -- Confirmed again for the drift sections below.
  UPDATE auth.users SET phone_confirmed_at = now() WHERE id = v_me;

  IF has_function_privilege('authenticated', 'public.verified_phone(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.verified_phone(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can run verified_phone';
  END IF;
END $$;

-- B2. Drift (fix round 1, minor #3): before W1a users.phone was client-
--     writable and Auth changes weren't mirrored, so a users row can hold a
--     number its own Auth account doesn't have. That stale copy must not make
--     the real owner's Auth phone change fail with 23505; a row whose Auth
--     phone really is the number is never touched. Fixtures 60-64.
DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000060', '+15558100060', 'Afua W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000061', '+15558100061', 'Kwesi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000062', '+15558100062', 'Akosua W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000063', '+15558100063', 'Fiifi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000064', '+15558100064', 'Adjoa W1');
  -- 60 holds a stale number but has its own Auth phone; 61 holds one and has
  -- none; 63 holds one and its own Auth phone is held (stale) by 64.
  UPDATE public.users SET phone = '+15558100094' WHERE id = '5f1a0000-0000-0000-0000-000000000060';
  UPDATE auth.users SET phone = NULL WHERE id = '5f1a0000-0000-0000-0000-000000000061';
  UPDATE public.users SET phone = '+15558100095' WHERE id = '5f1a0000-0000-0000-0000-000000000061';
  UPDATE public.users SET phone = '+15558100096' WHERE id = '5f1a0000-0000-0000-0000-000000000063';
  UPDATE public.users SET phone = '+15558100063' WHERE id = '5f1a0000-0000-0000-0000-000000000064';
END $$;

DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000003';
  v_stale_own constant uuid := '5f1a0000-0000-0000-0000-000000000060';
  v_stale_none constant uuid := '5f1a0000-0000-0000-0000-000000000061';
  v_holder constant uuid := '5f1a0000-0000-0000-0000-000000000062';
  v_msg text;
BEGIN
  -- 1. A stale holder with its own Auth phone is moved back to it.
  BEGIN
    UPDATE auth.users SET phone = '+15558100094' WHERE id = v_me;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale users.phone made the Auth phone change fail (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100094'
     OR (SELECT phone FROM public.users WHERE id = v_stale_own) IS DISTINCT FROM '+15558100060' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: drift was not reconciled (me %, stale holder %)',
      (SELECT phone FROM public.users WHERE id = v_me), (SELECT phone FROM public.users WHERE id = v_stale_own);
  END IF;

  -- 2. A stale holder with no Auth phone is parked on +999 (the W6a form).
  BEGIN
    UPDATE auth.users SET phone = '+15558100095' WHERE id = v_me;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale users.phone made the Auth phone change fail (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100095'
     OR (SELECT phone FROM public.users WHERE id = v_stale_none) !~ '^\+999[0-9]{12}$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: drift was not reconciled (me %, phoneless stale holder %)',
      (SELECT phone FROM public.users WHERE id = v_me), (SELECT phone FROM public.users WHERE id = v_stale_none);
  END IF;

  -- 2b. A stale holder whose own Auth phone another stale row holds: that
  --     row is moved to its own number first, then the holder gets its own
  --     (fix round 2, R-3: never park an account while a stale row keeps its
  --     number).
  BEGIN
    UPDATE auth.users SET phone = '+15558100096' WHERE id = v_me;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale users.phone made the Auth phone change fail (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100096'
     OR (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000063') IS DISTINCT FROM '+15558100063'
     OR (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000064') IS DISTINCT FROM '+15558100064' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: chained drift was not reconciled';
  END IF;

  -- 3. A row whose own Auth phone is the number keeps it; the change fails.
  --    (Auth's own UNIQUE refuses this first in production.)
  BEGIN
    UPDATE auth.users SET phone = '+15558100062' WHERE id = v_me;
    v_msg := NULL;
  EXCEPTION WHEN unique_violation THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'duplicate key value violates unique constraint "users_phone_key"'
     OR (SELECT phone FROM public.users WHERE id = v_holder) IS DISTINCT FROM '+15558100062'
     OR (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100096' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the mirror took a phone from the account whose Auth phone it is (got %)',
      coalesce(v_msg, 'no error');
  END IF;
END $$;

-- The drift park number for p_id on try p_try (same derivation as
-- private.release_stale_users_phone).
CREATE FUNCTION pg_temp.park(p_id uuid, p_try int) RETURNS text LANGUAGE sql AS $$
  SELECT '+999' || lpad(((('x' || left(md5(p_id::text || ':' || p_try), 12))::bit(48)::bigint)
                         % 1000000000000)::text, 12, '0');
$$;

-- B3. A park number is never the number being claimed (fix round 2, R-2;
--     re-review probe P3): when an Auth phone is set to a number a drift-
--     parked row holds (a W6a-style park), that row is parked again on its
--     next try and the mirror succeeds. Fixtures 65-67, 82-84.
DO $$
DECLARE
  v_stale constant uuid := '5f1a0000-0000-0000-0000-000000000065';
  v_changer constant uuid := '5f1a0000-0000-0000-0000-000000000066';
  v_parker constant uuid := '5f1a0000-0000-0000-0000-000000000067';
BEGIN
  PERFORM pg_temp.make_account(v_stale, '+15558100065', 'Ekow W1');
  PERFORM pg_temp.make_account(v_changer, '+15558100066', 'Efua W1');
  PERFORM pg_temp.make_account(v_parker, '+15558100067', 'Kojo W1');
  UPDATE auth.users SET phone = NULL WHERE id = v_stale;
  UPDATE public.users SET phone = '+15558100190' WHERE id = v_stale;

  UPDATE auth.users SET phone = '+15558100190' WHERE id = v_changer;
  IF (SELECT phone FROM public.users WHERE id = v_stale) IS DISTINCT FROM pg_temp.park(v_stale, 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the phoneless stale row was not parked on its first try';
  END IF;

  BEGIN
    UPDATE auth.users SET phone = pg_temp.park(v_stale, 1) WHERE id = v_parker;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Auth phone equal to a drift-parked number failed the mirror (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_parker) IS DISTINCT FROM pg_temp.park(v_stale, 1)
     OR (SELECT phone FROM public.users WHERE id = v_stale) IS DISTINCT FROM pg_temp.park(v_stale, 2) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked row was not re-parked on its next try';
  END IF;

  -- A park number another row already holds is skipped for the next try.
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000082', '+15558100082', 'Abla W1');
  UPDATE public.users SET phone = pg_temp.park('5f1a0000-0000-0000-0000-000000000083', 1)
   WHERE id = '5f1a0000-0000-0000-0000-000000000082';
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000083', '+15558100083', 'Selorm W1');
  UPDATE auth.users SET phone = NULL WHERE id = '5f1a0000-0000-0000-0000-000000000083';
  UPDATE public.users SET phone = '+15558100197' WHERE id = '5f1a0000-0000-0000-0000-000000000083';
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000084', '+15558100084', 'Edem W1');
  BEGIN
    UPDATE auth.users SET phone = '+15558100197' WHERE id = '5f1a0000-0000-0000-0000-000000000084';
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a taken park number failed the mirror (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000083')
       IS DISTINCT FROM pg_temp.park('5f1a0000-0000-0000-0000-000000000083', 2)
     OR (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000084') IS DISTINCT FROM '+15558100197' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a taken park number was not skipped';
  END IF;
END $$;

-- B4. A chain never parks the verified account (fix round 2, R-3; probe
--     P6): V's stale row holds the claimed number while a squatter Q holds
--     V's real number. Q is moved off first, then V gets its own number back.
--     Fixtures 68-70.
DO $$
DECLARE
  v_victim constant uuid := '5f1a0000-0000-0000-0000-000000000068';
  v_squatter constant uuid := '5f1a0000-0000-0000-0000-000000000069';
  v_changer constant uuid := '5f1a0000-0000-0000-0000-000000000070';
BEGIN
  PERFORM pg_temp.make_account(v_victim, '+15558100068', 'Yaa W1');
  UPDATE public.users SET phone = '+15558100191' WHERE id = v_victim;
  PERFORM pg_temp.make_account(v_squatter, '+15558100069', 'Kweku W1');
  UPDATE public.users SET phone = '+15558100068' WHERE id = v_squatter;
  PERFORM pg_temp.make_account(v_changer, '+15558100070', 'Nana W1');

  BEGIN
    UPDATE auth.users SET phone = '+15558100191' WHERE id = v_changer;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale users.phone made the Auth phone change fail (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_changer) IS DISTINCT FROM '+15558100191'
     OR (SELECT phone FROM public.users WHERE id = v_victim) IS DISTINCT FROM '+15558100068'
     OR (SELECT phone FROM public.users WHERE id = v_squatter) IS DISTINCT FROM '+15558100069' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified account was parked while a stale row kept its number (victim %, squatter %)',
      (SELECT phone FROM public.users WHERE id = v_victim), (SELECT phone FROM public.users WHERE id = v_squatter);
  END IF;
END $$;

-- B4b. A stale holder is moved back only onto its own verified Auth phone
--      (R2-1, the helper's branch): one whose own Auth phone is unconfirmed
--      is parked, never handed an unverified number. Fixtures 88-89.
DO $$
DECLARE
  v_stale constant uuid := '5f1a0000-0000-0000-0000-000000000088';
  v_changer constant uuid := '5f1a0000-0000-0000-0000-000000000089';
BEGIN
  PERFORM pg_temp.make_account(v_stale, '+15558100088', 'Kafui W1');
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_stale;
  UPDATE public.users SET phone = '+15558100198' WHERE id = v_stale;
  PERFORM pg_temp.make_account(v_changer, '+15558100089', 'Senam W1');

  BEGIN
    UPDATE auth.users SET phone = '+15558100198' WHERE id = v_changer;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale users.phone made the Auth phone change fail (%)', SQLERRM;
  END;
  IF (SELECT phone FROM public.users WHERE id = v_changer) IS DISTINCT FROM '+15558100198'
     OR (SELECT phone FROM public.users WHERE id = v_stale) IS DISTINCT FROM pg_temp.park(v_stale, 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale holder was moved onto its unverified Auth phone (changer %, stale %)',
      (SELECT phone FROM public.users WHERE id = v_changer), (SELECT phone FROM public.users WHERE id = v_stale);
  END IF;
END $$;

-- B5. Sign-up on a squatted number (fix round 2, R-1/(b); probe P1): every
--     users insert takes the phone from the verified Auth phone and moves a
--     stale holder off it first, so the real owner's first row is written
--     (record_eula_acceptance, and the invite functions' service-role
--     upsert; complete_sign_up in W1b). Fixtures 71-75.
DO $$
DECLARE
  v_squat1 constant uuid := '5f1a0000-0000-0000-0000-000000000071';
  v_owner1 constant uuid := '5f1a0000-0000-0000-0000-000000000072';
  v_squat2 constant uuid := '5f1a0000-0000-0000-0000-000000000073';
  v_owner2 constant uuid := '5f1a0000-0000-0000-0000-000000000074';
BEGIN
  PERFORM pg_temp.make_account(v_squat1, '+15558100071', 'Esi B W1');
  UPDATE auth.users SET phone = NULL WHERE id = v_squat1;
  UPDATE public.users SET phone = '+15558100192' WHERE id = v_squat1;
  PERFORM pg_temp.make_account(v_owner1, '+15558100192', NULL);
  PERFORM pg_temp.make_account(v_squat2, '+15558100073', 'Kwabena W1');
  UPDATE auth.users SET phone = NULL WHERE id = v_squat2;
  UPDATE public.users SET phone = '+15558100193' WHERE id = v_squat2;
  PERFORM pg_temp.make_account(v_owner2, '+15558100193', NULL);

  -- 1. record_eula_acceptance, as the real owner.
  PERFORM pg_temp.as_user(v_owner1);
  BEGIN
    PERFORM public.record_eula_acceptance('1');
  EXCEPTION WHEN unique_violation THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a squatted number blocked the real owner''s sign-up (%)', SQLERRM;
  END;
  RESET ROLE;
  IF (SELECT phone FROM public.users WHERE id = v_owner1) IS DISTINCT FROM '+15558100192'
     OR (SELECT phone FROM public.users WHERE id = v_squat1) IS DISTINCT FROM pg_temp.park(v_squat1, 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sign-up did not take the Auth phone from the squatter (owner %, squatter %)',
      (SELECT phone FROM public.users WHERE id = v_owner1), (SELECT phone FROM public.users WHERE id = v_squat1);
  END IF;

  -- 2. The invite functions' upsert (service role, ignoreDuplicates), even
  --    when it passes a different phone: the Auth phone wins.
  SET LOCAL ROLE service_role;
  BEGIN
    INSERT INTO public.users (id, phone, display_name, mode)
    VALUES (v_owner2, '+15558100194', 'Kwame B W1', 'couples')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN unique_violation THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a squatted number blocked the real owner''s sign-up (%)', SQLERRM;
  END;
  RESET ROLE;
  IF (SELECT phone FROM public.users WHERE id = v_owner2) IS DISTINCT FROM '+15558100193'
     OR (SELECT phone FROM public.users WHERE id = v_squat2) IS DISTINCT FROM pg_temp.park(v_squat2, 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a users insert did not take the verified Auth phone (owner %, squatter %)',
      (SELECT phone FROM public.users WHERE id = v_owner2), (SELECT phone FROM public.users WHERE id = v_squat2);
  END IF;

  -- 3. An unverified Auth phone is no phone: the row is written with NULL.
  INSERT INTO auth.users (id, phone) VALUES ('5f1a0000-0000-0000-0000-000000000075', '+15558100075');
  SET LOCAL ROLE service_role;
  INSERT INTO public.users (id, phone, display_name)
  VALUES ('5f1a0000-0000-0000-0000-000000000075', '+15558100075', 'Adwoa W1');
  RESET ROLE;
  IF (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000075') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a users insert stored an unverified Auth phone';
  END IF;

  -- 4. A phoneless Auth account is no phone (batch 1 re-review 2, R2-2):
  --    GoTrue reports its phone as "" and ensureUserRow passes that on, so a
  --    stored '' would make the next phoneless account fail users_phone_key.
  --    Every such row is written, with NULL. Fixtures 85-87.
  INSERT INTO auth.users (id, phone) VALUES
    ('5f1a0000-0000-0000-0000-000000000085', NULL),
    ('5f1a0000-0000-0000-0000-000000000086', ''),
    ('5f1a0000-0000-0000-0000-000000000087', NULL);
  SET LOCAL ROLE service_role;
  BEGIN
    INSERT INTO public.users (id, phone, display_name)
    VALUES ('5f1a0000-0000-0000-0000-000000000085', '', '')
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.users (id, phone, display_name)
    VALUES ('5f1a0000-0000-0000-0000-000000000086', '', '')
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.users (id, phone, display_name)
    VALUES ('5f1a0000-0000-0000-0000-000000000087', '  ', '')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN unique_violation THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second phoneless account could not get a users row (%)', SQLERRM;
  END;
  RESET ROLE;
  IF (SELECT count(*) FROM public.users
       WHERE id IN ('5f1a0000-0000-0000-0000-000000000085', '5f1a0000-0000-0000-0000-000000000086',
                    '5f1a0000-0000-0000-0000-000000000087')
         AND phone IS NULL) <> 3 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phoneless account''s users row stored a blank phone';
  END IF;
END $$;

-- B6. The one-time reconciliation migration 1 runs (fix round 2, R-1/(a)):
--     phase 1 clears every users.phone that isn't its own verified Auth
--     phone, phase 2 writes each verified Auth phone. Re-running it changes
--     nothing. (It runs over the whole table, inside this file's rollback.)
--     Fixtures 76-81.
DO $$
BEGIN
  IF to_regprocedure('private.reconcile_users_phones()') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the one-time users.phone reconciliation is missing';
  END IF;
END $$;

DO $$
DECLARE
  v_squatter constant uuid := '5f1a0000-0000-0000-0000-000000000076';
  v_stale constant uuid := '5f1a0000-0000-0000-0000-000000000077';
  v_unverified constant uuid := '5f1a0000-0000-0000-0000-000000000078';
  v_clean constant uuid := '5f1a0000-0000-0000-0000-000000000079';
  v_chain constant uuid := '5f1a0000-0000-0000-0000-000000000080';
  v_again int;
BEGIN
  -- Legacy drift, written the way pre-W1a clients and fixtures could.
  PERFORM pg_temp.make_account(v_squatter, '+15558100076', 'Kofi C W1');
  UPDATE auth.users SET phone = NULL WHERE id = v_squatter;
  UPDATE public.users SET phone = '+15558100195' WHERE id = v_squatter;
  PERFORM pg_temp.make_account(v_stale, '+15558100077', 'Ama C W1');
  UPDATE public.users SET phone = '+15558100196' WHERE id = v_stale;
  PERFORM pg_temp.make_account(v_unverified, '+15558100078', 'Yaw C W1');
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_unverified;
  PERFORM pg_temp.make_account(v_clean, '+15558100079', 'Akua C W1');
  PERFORM pg_temp.make_account(v_chain, '+15558100080', 'Kojo C W1');
  UPDATE public.users SET phone = '+15558100077' WHERE id = v_chain;  -- holds v_stale's real number
  UPDATE public.users SET phone = '+15558100078' WHERE id = v_unverified;

  PERFORM private.reconcile_users_phones();

  IF (SELECT phone FROM public.users WHERE id = v_squatter) IS NOT NULL
     OR (SELECT phone FROM public.users WHERE id = v_unverified) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reconciliation kept a phone that is not a verified Auth phone';
  END IF;
  IF (SELECT phone FROM public.users WHERE id = v_stale) IS DISTINCT FROM '+15558100077'
     OR (SELECT phone FROM public.users WHERE id = v_chain) IS DISTINCT FROM '+15558100080'
     OR (SELECT phone FROM public.users WHERE id = v_clean) IS DISTINCT FROM '+15558100079' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reconciliation did not restore verified Auth phones (stale %, chain %, clean %)',
      (SELECT phone FROM public.users WHERE id = v_stale), (SELECT phone FROM public.users WHERE id = v_chain),
      (SELECT phone FROM public.users WHERE id = v_clean);
  END IF;
  IF EXISTS (SELECT 1 FROM public.users u
              WHERE u.phone IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM auth.users a
                                 WHERE a.id = u.id AND a.phone = u.phone AND a.phone_confirmed_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the reconciliation a users.phone is not its verified Auth phone';
  END IF;

  v_again := private.reconcile_users_phones();
  IF v_again <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reconciliation is not idempotent (% rows changed on a re-run)', v_again;
  END IF;

  -- P1 after the pass: the real owner of the squatted number signs up.
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES ('5f1a0000-0000-0000-0000-000000000081', '+15558100195', now());
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000081');
  PERFORM public.record_eula_acceptance('1');
  RESET ROLE;
  IF (SELECT phone FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000081') IS DISTINCT FROM '+15558100195' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the real owner could not sign up after the reconciliation';
  END IF;
END $$;

-- =====================================================================
-- C. profiles moderation guard (W1a; D5, review S-1). A client can't clear
--    a ban, reset or change its strike count, arrive pre-banned, or delete
--    its profile at all (the guard also locks one with strikes or a live
--    ban). Everything else a client writes still works, and the server still
--    writes both columns. Fixtures 04-07.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('private.guard_profile_moderation_columns()') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger
                     WHERE tgrelid = 'public.profiles'::regclass
                       AND tgname = 'profiles_guard_moderation_columns' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the profiles moderation guard is missing (D5, S-1)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000004', '+15558100004', 'Kofi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000005', '+15558100005', 'Esi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000006', '+15558100006', 'Yaw W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000007', '+15558100007', 'Abena W1');
END $$;

-- Stands in for a SECURITY DEFINER server function (complete_sign_up,
-- set_user_path_internal, admin_confirm_content_removal's callers).
CREATE FUNCTION pg_temp.definer_clear_ban(p uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE public.profiles SET banned_until = NULL WHERE id = p;
$$;

DO $$
DECLARE
  v_struck constant uuid := '5f1a0000-0000-0000-0000-000000000004';
  v_banned constant uuid := '5f1a0000-0000-0000-0000-000000000005';
  v_clean constant uuid := '5f1a0000-0000-0000-0000-000000000006';
  v_new constant uuid := '5f1a0000-0000-0000-0000-000000000007';
  v_msg text;
  v_n int;
  v_count int;
  v_ban timestamptz;
  v_name text;
BEGIN
  -- Seeded by the owner, the way the service-role moderation function writes them.
  INSERT INTO public.profiles (id, display_name, confirmed_violation_count, banned_until) VALUES
    (v_struck, 'Kofi', 2, NULL),
    (v_banned, 'Esi', 0, now() + interval '3 days'),
    (v_clean, 'Yaw', 0, NULL);

  -- 1. No client write to either column.
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET banned_until = NULL WHERE id = %L', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client cleared its own Opinions ban (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET confirmed_violation_count = 0 WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client reset its own strike count (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET confirmed_violation_count = 7 WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client changed its own strike count (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_clean);
  v_msg := pg_temp.error_of(format(
    'UPDATE public.profiles SET banned_until = now() + interval %L WHERE id = %L', '1 day', v_clean));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client set a ban on itself (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- An upsert that names banned_until is an update of it.
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.profiles (id, banned_until) VALUES (%L, NULL) '
    'ON CONFLICT (id) DO UPDATE SET banned_until = EXCLUDED.banned_until', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upsert cleared a ban (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 2. Everything else still works, for a struck author too (R6).
  PERFORM pg_temp.as_user(v_struck);
  UPDATE public.profiles SET preferred_location = 'Accra', last_location_update = now() WHERE id = v_struck;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO public.profiles (id, display_name, relationship_status, updated_at)
  VALUES (v_struck, 'Kofi A.', 'taken', now())
  ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        relationship_status = EXCLUDED.relationship_status,
        updated_at = EXCLUDED.updated_at;
  RESET ROLE;
  SELECT confirmed_violation_count, display_name INTO v_count, v_name FROM public.profiles WHERE id = v_struck;
  IF v_n <> 1 OR v_count <> 2 OR v_name <> 'Kofi A.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary profile write broke (location rows %, strikes %, name %)',
      v_n, v_count, v_name;
  END IF;

  -- 3. A client INSERT can't arrive pre-banned or pre-struck.
  PERFORM pg_temp.as_user(v_new);
  INSERT INTO public.profiles (id, display_name, banned_until, confirmed_violation_count)
  VALUES (v_new, 'Abena', now() + interval '9 days', 5);
  RESET ROLE;
  SELECT banned_until, confirmed_violation_count INTO v_ban, v_count FROM public.profiles WHERE id = v_new;
  IF v_ban IS NOT NULL OR v_count <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client insert stored banned_until %, strikes %', v_ban, v_count;
  END IF;

  -- 4. No client deletes a profile (fix round 1, Important #1): the strike
  --    writer only UPDATEs an existing row, so a clean author who deleted
  --    theirs would never collect a strike. Account deletion still cascades
  --    from auth.users, as the table owner.
  IF has_table_privilege('authenticated', 'public.profiles', 'DELETE')
     OR has_table_privilege('anon', 'public.profiles', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client may DELETE profiles';
  END IF;
  PERFORM pg_temp.as_user(v_clean);
  v_msg := pg_temp.error_of(format('DELETE FROM public.profiles WHERE id = %L', v_clean));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'permission denied for table profiles'
     OR NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_clean) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client deleted a clean profile, so its later strikes would be lost (got %)',
      coalesce(v_msg, 'no error');
  END IF;

  -- 4b. Defence in depth: were DELETE ever granted again, the guard still
  --     keeps a profile with strikes or a live ban. The grant is undone below
  --     (and the whole file rolls back).
  GRANT DELETE ON public.profiles TO authenticated;
  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('DELETE FROM public.profiles WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_locked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client deleted a profile with strikes (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format('DELETE FROM public.profiles WHERE id = %L', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_locked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client deleted a profile with a live ban (got %)', coalesce(v_msg, 'no error');
  END IF;
  REVOKE DELETE ON public.profiles FROM authenticated;

  -- 5. The server still writes both: the service role, and a definer function
  --    called by a client.
  SET LOCAL ROLE service_role;
  UPDATE public.profiles SET confirmed_violation_count = 3, banned_until = now() + interval '7 days'
   WHERE id = v_struck;
  RESET ROLE;
  SELECT confirmed_violation_count, banned_until INTO v_count, v_ban FROM public.profiles WHERE id = v_struck;
  IF v_count <> 3 OR v_ban IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role could not record a strike and a ban';
  END IF;
  PERFORM pg_temp.as_user(v_banned);
  PERFORM pg_temp.definer_clear_ban(v_banned);
  RESET ROLE;
  IF (SELECT banned_until FROM public.profiles WHERE id = v_banned) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a definer function could not clear a ban';
  END IF;
END $$;

-- =====================================================================
-- D. users.mode has no writer left (W1a; D3), and the five dating functions
--    still do everything else they did. Fixtures 08-09, 90-91. Every state
--    check is NULL-safe (batch 2 review M2): a function that deleted the row
--    instead would leave NULLs, and `<>` would let that pass.
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND (p.prosrc ~* 'update\s+(public\.)?users\M[^;]*\mmode\M\s*='
          OR p.prosrc ~* 'insert\s+into\s+(public\.)?users\s*\([^)]*\mmode\M'
          -- an upsert that writes mode only in its DO UPDATE (batch 2 review #4)
          OR p.prosrc ~* 'insert\s+into\s+(public\.)?users\M[^;]*do\s+update\s+set[^;]*\mmode\M\s*=');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: functions still write users.mode: %', v_bad;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.activate_dating_profile(text)'::regprocedure,
                   'public.pause_dating_mode(text)'::regprocedure,
                   'public.exit_dating_mode(text)'::regprocedure,
                   'public.pause_dating_for_relationship_user(uuid)'::regprocedure,
                   'public.delete_dating_profile(text)'::regprocedure)
     AND p.proconfig IS DISTINCT FROM ARRAY['search_path=""'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating functions without search_path = '''': %', v_bad;
  END IF;
  IF has_function_privilege('authenticated', 'public.pause_dating_for_relationship_user(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.pause_dating_mode(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.exit_dating_mode(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.activate_dating_profile(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.delete_dating_profile(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating function''s grants changed';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000008', '+15558100008', 'Dating W1 A');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000009', '+15558100009', 'Dating W1 B');
END $$;

DO $$
DECLARE
  v_a constant uuid := '5f1a0000-0000-0000-0000-000000000008';
  v_b constant uuid := '5f1a0000-0000-0000-0000-000000000009';
  v_state text;
  v_mode text;
BEGIN
  UPDATE public.users SET mode = 'dating' WHERE id IN (v_a, v_b);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_a, 'active'), (v_b, 'active');

  PERFORM public.pause_dating_for_relationship_user(v_a);
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_a;
  IF v_state IS DISTINCT FROM 'paused' OR v_mode IS DISTINCT FROM 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause_dating_for_relationship_user left state %, mode %', v_state, v_mode;
  END IF;

  PERFORM pg_temp.as_user(v_b);
  PERFORM public.pause_dating_mode('w1-contract-pause-0001');
  RESET ROLE;
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_b;
  IF v_state IS DISTINCT FROM 'paused' OR v_mode IS DISTINCT FROM 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause_dating_mode left state %, mode %', v_state, v_mode;
  END IF;

  PERFORM pg_temp.as_user(v_b);
  PERFORM public.exit_dating_mode('w1-contract-exit-0001');
  RESET ROLE;
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_b;
  IF v_state IS DISTINCT FROM 'exited' OR v_mode IS DISTINCT FROM 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit_dating_mode left state %, mode %', v_state, v_mode;
  END IF;
END $$;

-- D2. The two dating functions no contract ran before (batch 2 review M1):
--     their bodies run under search_path = '', so an unqualified name fails
--     only when called, and proconfig alone can't show it. activate runs
--     with the flag and every gate really met (inside this file's rollback),
--     delete on a profile with a photo and preferences. Fixtures 90-91.
DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000090', '+15558100090', 'Dating W1 C');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000091', '+15558100091', 'Dating W1 D');
END $$;

DO $$
DECLARE
  v_c constant uuid := '5f1a0000-0000-0000-0000-000000000090';
  v_d constant uuid := '5f1a0000-0000-0000-0000-000000000091';
  v_journey uuid;
  v_ret public.dating_enrollments;
  v_msg text;
  v_state text;
  v_profile_state text;
  v_mode text;
  v_activated timestamptz;
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, adults_only_confirmed_at) VALUES
    (v_c, 'profile_draft', now()), (v_d, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, city_region_code, relationship_intention,
                                      moderation_state, profile_state) VALUES
    (v_c, 'Dating C', 'GH-AA', 'long_term', 'approved', 'draft'),
    (v_d, 'Dating D', 'GH-AA', 'long_term', 'approved', 'active');
  INSERT INTO public.dating_preferences (user_id, min_age, max_age, gender_preferences, region_preferences,
                                         intention_preferences) VALUES
    (v_c, 18, 40, '["woman"]', '["GH-AA"]', '["long_term"]'),
    (v_d, 18, 40, '["man"]', '["GH-AA"]', '["long_term"]');
  INSERT INTO public.dating_profile_photos (user_id, position, storage_key) VALUES
    (v_d, 1, 'w1-contract/d1.jpg');

  -- 1. The flag off: refused by its gate, after the rate limit ran.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.as_user(v_c);
  BEGIN
    PERFORM public.activate_dating_profile('w1-contract-activate-0000');
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'activation_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activate_dating_profile with the flag off gave %', coalesce(v_msg, 'no error');
  END IF;

  -- 2. The flag on and every gate met (adult age check, Healing readiness,
  --    good standing, no relationship): it activates and leaves users.mode.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_c, DATE '1990-01-01', 'w1_contract', now());
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status,
                                       reflection_completed_at, post_mortem_completed_at,
                                       pattern_awareness_completed_at, portrait_completed_at,
                                       readiness_stage_completed_at, eligible_for_dating_opt_in_at)
  VALUES (v_c, now() - interval '10 weeks', 'relationship', 'eligible_for_dating_opt_in',
          now(), now(), now(), now(), now(), now())
  RETURNING id INTO v_journey;
  INSERT INTO public.healing_readiness_attempts (journey_id, user_id, answers, score, scoring_version)
  VALUES (v_journey, v_c, '{}', 80, 'w1_contract');
  PERFORM pg_temp.as_user(v_c);
  BEGIN
    v_ret := public.activate_dating_profile('w1-contract-activate-0001');
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  SELECT e.state, p.profile_state, u.mode, e.activated_at INTO v_state, v_profile_state, v_mode, v_activated
    FROM public.users u
    LEFT JOIN public.dating_enrollments e ON e.user_id = u.id
    LEFT JOIN public.dating_profiles p ON p.user_id = u.id
   WHERE u.id = v_c;
  IF v_msg IS NOT NULL OR v_ret.state IS DISTINCT FROM 'active' OR v_state IS DISTINCT FROM 'active'
     OR v_profile_state IS DISTINCT FROM 'active' OR v_activated IS NULL OR v_mode IS DISTINCT FROM 'personal' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activate_dating_profile on a fully gated account gave % (enrollment %, profile %, mode %)',
      coalesce(v_msg, 'no error'), v_state, v_profile_state, v_mode;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';

  -- 3. delete_dating_profile: photo, preferences and profile go; the
  --    enrollment is back to profile_draft.
  PERFORM pg_temp.as_user(v_d);
  BEGIN
    PERFORM public.delete_dating_profile('w1-contract-delete-0001');
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_d)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_d) IS DISTINCT FROM 'profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete_dating_profile gave % (enrollment %)',
      coalesce(v_msg, 'no error'), (SELECT state FROM public.dating_enrollments WHERE user_id = v_d);
  END IF;
END $$;

-- =====================================================================
-- E. Metrics (W1b; review S-2): exact client keys, anon only for the
--    pre-auth funnel, server prefixes only for definer callers and the
--    service role, blanked report cells, a daily row cap. Fixture 10.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.metric_counters') IS NULL
     OR to_regprocedure('public.bump_metric(text)') IS NULL
     OR to_regprocedure('private.bump_metric_internal(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b metric objects are missing (metric_counters, bump_metric, bump_metric_internal)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000010', '+15558100010', 'Metric W1');
END $$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT count FROM public.metric_counters
                    WHERE day = (now() AT TIME ZONE 'utc')::date AND key = p_key), 0);
$$;

DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000010';
  v_day constant date := (now() AT TIME ZONE 'utc')::date;
  v_key text;
  v_before bigint;
  v_rows int;
  v_bad text;
  v_msg text;
BEGIN
  -- Privileges.
  IF has_function_privilege('anon', 'public.bump_metric_server(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.bump_metric_server(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.bump_metric_internal(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.bump_metric_internal(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.metric_increment(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.metric_increment(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can run a server metric writer';
  END IF;
  IF NOT has_function_privilege('anon', 'public.bump_metric(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.bump_metric(text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.bump_metric_server(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a metric entry point lost its grant';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['public.metric_counters', 'public.metric_key_prefixes',
                               'public.metric_client_keys', 'public.metric_counters_report'] LOOP
    IF has_table_privilege('anon', v_key, 'SELECT') OR has_table_privilege('authenticated', v_key, 'SELECT')
       OR has_table_privilege('authenticated', v_key, 'INSERT') OR has_table_privilege('authenticated', v_key, 'UPDATE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can read or write %', v_key;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('service_role', 'public.metric_counters_report', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role cannot read the metric report';
  END IF;

  -- Seeds: 26 exact client keys (9 pre-auth), 10 server prefixes.
  IF (SELECT count(*) FROM public.metric_client_keys WHERE owner_spec = 'spec1') <> 26
     OR (SELECT count(*) FROM public.metric_client_keys WHERE owner_spec = 'spec1' AND anon_ok) <> 9
     OR (SELECT count(*) FROM public.metric_key_prefixes WHERE owner_spec = 'spec1') <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Spec 1 metric seeds are wrong';
  END IF;
  -- No client key sits under a server prefix (P-12; batch 3 fix round 1,
  -- M-4): a client could otherwise inflate a server event. Any spec's seeds.
  SELECT string_agg(c.key, ', ' ORDER BY c.key) INTO v_bad
    FROM public.metric_client_keys AS c
    JOIN public.metric_key_prefixes AS p ON left(c.key, char_length(p.prefix)) = p.prefix;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client metric keys under a server prefix: %', v_bad;
  END IF;

  -- anon: a signed-in-only key and unlisted keys write nothing; a pre-auth key counts.
  v_before := pg_temp.metric('signup_started');
  PERFORM pg_temp.as_anon();
  PERFORM public.bump_metric('invite_shared:whatsapp');
  PERFORM public.bump_metric('signup_completed');
  PERFORM public.bump_metric('invite_accepted');
  PERFORM public.bump_metric('x_y');
  PERFORM public.bump_metric('signup_started');
  RESET ROLE;
  IF pg_temp.metric('invite_shared:whatsapp') + pg_temp.metric('signup_completed')
     + pg_temp.metric('invite_accepted') + pg_temp.metric('x_y') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon bumped a signed-in-only or unlisted key';
  END IF;
  IF pg_temp.metric('signup_started') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed pre-auth key did not count once';
  END IF;

  -- authenticated: unlisted keys, including a server prefix, write nothing.
  PERFORM pg_temp.as_user(v_me);
  PERFORM public.bump_metric('signup_completed');
  PERFORM public.bump_metric('invite_accepted');
  PERFORM public.bump_metric('x_y');
  PERFORM public.bump_metric('path_chosen:dating');
  PERFORM public.bump_metric('invite_shared:whatsapp');
  RESET ROLE;
  IF pg_temp.metric('signup_completed') + pg_temp.metric('invite_accepted')
     + pg_temp.metric('x_y') + pg_temp.metric('path_chosen:dating') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated bumped an unlisted key';
  END IF;
  IF pg_temp.metric('invite_shared:whatsapp') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed signed-in key did not count once';
  END IF;

  -- Server side: a prefix counts, anything else is ignored, nothing raises.
  PERFORM private.bump_metric_internal('invite_accepted_24h');
  PERFORM private.bump_metric_internal('x_y');
  PERFORM private.bump_metric_internal('Not A Key');
  PERFORM private.bump_metric_internal(NULL);
  SET LOCAL ROLE service_role;
  PERFORM public.bump_metric_server('otp_sent:gh:sms:ghana_direct');
  RESET ROLE;
  IF pg_temp.metric('invite_accepted_24h') <> 1 OR pg_temp.metric('x_y') <> 0
     OR pg_temp.metric('otp_sent:gh:sms:ghana_direct') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the server prefix rule is wrong';
  END IF;

  -- A server key never carries an id or a phone number (batch 3 fix round 1,
  -- M-5): uuid-shaped (dashed or not) and phone-shaped (7+ digits, single
  -- separators allowed) keys write nothing, and the table refuses them too.
  PERFORM private.bump_metric_internal('dormancy_5f1a0000-0000-0000-0000-000000000010');
  PERFORM private.bump_metric_internal('dormancy_5f1a00000000000000000000000000010');
  PERFORM private.bump_metric_internal('otp_sent:233244123456');
  PERFORM private.bump_metric_internal('otp_sent:gh:233-244-123-456');
  SELECT string_agg(key, ', ' ORDER BY key) INTO v_bad FROM public.metric_counters
   WHERE day = v_day AND key IN ('dormancy_5f1a0000-0000-0000-0000-000000000010',
                                 'dormancy_5f1a00000000000000000000000000010',
                                 'otp_sent:233244123456', 'otp_sent:gh:233-244-123-456');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server metric key carried an id or a phone number: %', v_bad;
  END IF;
  v_msg := pg_temp.error_of(format('INSERT INTO public.metric_counters (day, key, count) VALUES (%L, %L, 1)',
                                   v_day, 'otp_sent:233244123456'));
  IF v_msg IS DISTINCT FROM 'new row for relation "metric_counters" violates check constraint "metric_counters_key_check"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: metric_counters stored a phone-shaped key (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- The report blanks every cell under 50.
  INSERT INTO public.metric_counters (day, key, count) VALUES
    (v_day - 1, 'path_chosen:just_me', 49), (v_day - 1, 'path_chosen:dating', 50);
  IF (SELECT count FROM public.metric_counters_report WHERE day = v_day - 1 AND key = 'path_chosen:just_me') IS NOT NULL
     OR (SELECT count FROM public.metric_counters_report WHERE day = v_day - 1 AND key = 'path_chosen:dating') IS DISTINCT FROM 50 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report shows a cell under 50 or hides one at 50';
  END IF;

  -- The daily row cap: past 5,000 keys a new key isn't created; existing keys keep counting.
  SELECT count(*) INTO v_rows FROM public.metric_counters WHERE day = v_day AND key <> 'metric_cap_reached';
  INSERT INTO public.metric_counters (day, key, count)
  SELECT v_day, 'path_chosen:cap' || g, 1 FROM generate_series(1, 5000 - v_rows) AS g;
  v_before := pg_temp.metric('metric_cap_reached');
  PERFORM private.bump_metric_internal('signup_completed');
  IF EXISTS (SELECT 1 FROM public.metric_counters WHERE day = v_day AND key = 'signup_completed') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new key was created past the daily cap';
  END IF;
  IF pg_temp.metric('metric_cap_reached') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: metric_cap_reached did not move past the cap';
  END IF;
  PERFORM private.bump_metric_internal('invite_accepted_24h');
  IF pg_temp.metric('invite_accepted_24h') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing key stopped counting at the cap';
  END IF;
  -- At the cap an id-shaped key is still ignored by the writer's own guard,
  -- not counted as metric_cap_reached (fix round 1, M-5).
  v_before := pg_temp.metric('metric_cap_reached');
  PERFORM private.bump_metric_internal('dormancy_5f1a0000-0000-0000-0000-000000000010');
  IF pg_temp.metric('metric_cap_reached') <> v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an id-shaped key reached the capped writer';
  END IF;
  DELETE FROM public.metric_counters WHERE day = v_day AND key LIKE 'path_chosen:cap%';

  -- Retention runs as its own job.
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'metric-counters-retention' AND schedule = '12 4 * * *'
                    AND command LIKE '%DELETE FROM public.metric_counters WHERE day < current_date - 400%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: metric-counters-retention is not scheduled';
  END IF;
END $$;

-- =====================================================================
-- F. Sign-up, birth dates and holds (W1b; D8, Q4, I-7). Under 18 writes
--    nothing; the phone is Auth's; a replay is idempotent; a DOB is
--    write-once; a legacy minor gets a hold that commits. Fixtures 11-19,
--    43-46 (batch 3 fix round 1).
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.account_birthdates') IS NULL OR to_regclass('public.account_holds') IS NULL
     OR to_regprocedure('public.complete_sign_up(text,date,text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b birth-date objects are missing (account_birthdates, account_holds, complete_sign_up)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000011', '+15558100011', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000012', '+15558100012', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000013', '+15558100013', 'Legacy W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000014', '+15558100014', 'Legacy Minor W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000015', '+15558100015', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000016', '+15558100016', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000017', '+15558100017', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000018', '+15558100018', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000019', '+15558100019', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000043', '+15558100043', 'Legacy Teen W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000044', '+15558100044', 'Legacy Eighteen W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000045', '+15558100045', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000046', '+15558100046', NULL);
END $$;
UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = '5f1a0000-0000-0000-0000-000000000015';

DO $$
DECLARE
  v_adult constant uuid := '5f1a0000-0000-0000-0000-000000000011';
  v_minor constant uuid := '5f1a0000-0000-0000-0000-000000000012';
  v_legacy constant uuid := '5f1a0000-0000-0000-0000-000000000013';
  v_legacy_minor constant uuid := '5f1a0000-0000-0000-0000-000000000014';
  v_unverified constant uuid := '5f1a0000-0000-0000-0000-000000000015';
  v_birthday constant uuid := '5f1a0000-0000-0000-0000-000000000016';
  v_tomorrow constant uuid := '5f1a0000-0000-0000-0000-000000000017';
  v_twi constant uuid := '5f1a0000-0000-0000-0000-000000000018';
  v_arabic constant uuid := '5f1a0000-0000-0000-0000-000000000019';
  v_legacy_teen constant uuid := '5f1a0000-0000-0000-0000-000000000043';
  v_legacy_eighteen constant uuid := '5f1a0000-0000-0000-0000-000000000044';
  v_prerow constant uuid := '5f1a0000-0000-0000-0000-000000000045';
  v_tabbed constant uuid := '5f1a0000-0000-0000-0000-000000000046';
  v_today constant date := (now() AT TIME ZONE 'utc')::date;
  v_eighteen constant date := ((now() AT TIME ZONE 'utc')::date - interval '18 years')::date;
  v_res jsonb;
  v_msg text;
  v_n int;
  v_before bigint;
  v_tbl text;
  v_role text;
BEGIN
  -- Privileges: a DOB and a hold are never reachable from a client.
  IF has_function_privilege('authenticated', 'public.account_age(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.account_age(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.place_account_hold(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.complete_sign_up(text,date,text)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.account_birthdates', 'SELECT')
     OR has_table_privilege('authenticated', 'public.account_holds', 'SELECT')
     OR has_table_privilege('anon', 'public.account_birthdates', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach a birth date or a hold directly';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.complete_sign_up(text,date,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_my_birth_date(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_age()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up RPC lost its grant';
  END IF;
  -- Every table privilege, for both client roles; anon runs no birth-date
  -- RPC at all (fix round 1, M-7).
  FOREACH v_tbl IN ARRAY ARRAY['public.account_birthdates', 'public.account_holds'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF has_table_privilege(v_role, v_tbl, 'SELECT') OR has_table_privilege(v_role, v_tbl, 'INSERT')
         OR has_table_privilege(v_role, v_tbl, 'UPDATE') OR has_table_privilege(v_role, v_tbl, 'DELETE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can read or write %', v_role, v_tbl;
      END IF;
    END LOOP;
  END LOOP;
  IF has_function_privilege('anon', 'public.get_my_age()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_my_birth_date(date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can run a birth-date RPC';
  END IF;

  -- 1. Under 18: refused, and nothing at all is written (D8).
  PERFORM pg_temp.as_user(v_minor);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)',
    'Kwame', (v_today - interval '17 years')::date, '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 sign-up was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  SELECT (SELECT count(*) FROM public.users WHERE id = v_minor)
       + (SELECT count(*) FROM public.profiles WHERE id = v_minor)
       + (SELECT count(*) FROM public.account_birthdates WHERE user_id = v_minor) INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 sign-up wrote % row(s)', v_n;
  END IF;

  -- 2. An adult: one transaction; phone from auth.users; name collapsed.
  v_before := pg_temp.metric('signup_completed');
  PERFORM pg_temp.as_user(v_adult);
  v_res := public.complete_sign_up('  Ama   Mensah ', DATE '1996-03-27', '2');
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('age', extract(year FROM age(v_today, DATE '1996-03-27'))::int, 'created', true) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first sign-up returned %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users u JOIN auth.users a ON a.id = u.id
                  WHERE u.id = v_adult AND u.phone = a.phone AND u.display_name = 'Ama Mensah'
                    AND u.eula_version = '2' AND u.eula_accepted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the users row is not (Auth phone, collapsed name, EULA 2)';
  END IF;
  IF (SELECT display_name FROM public.profiles WHERE id = v_adult) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT birth_date FROM public.account_birthdates WHERE user_id = v_adult AND source = 'self_declared')
        IS DISTINCT FROM DATE '1996-03-27' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the profile name or the DOB was not written';
  END IF;
  IF pg_temp.metric('signup_completed') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: signup_completed did not count once';
  END IF;

  -- 3. The offline replay: idempotent; the stored DOB, both names and the
  --    consent time win. NULL-safe throughout (fix round 1, M-7); the
  --    consent time is moved back first, since now() is fixed in this file.
  UPDATE public.users SET eula_accepted_at = now() - interval '1 day' WHERE id = v_adult;
  PERFORM pg_temp.as_user(v_adult);
  v_res := public.complete_sign_up('Someone Else', DATE '1980-01-01', '2');
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('age', extract(year FROM age(v_today, DATE '1996-03-27'))::int, 'created', false)
     OR (SELECT birth_date FROM public.account_birthdates WHERE user_id = v_adult) IS DISTINCT FROM DATE '1996-03-27'
     OR (SELECT display_name FROM public.users WHERE id = v_adult) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT display_name FROM public.profiles WHERE id = v_adult) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT eula_accepted_at FROM public.users WHERE id = v_adult) IS DISTINCT FROM now() - interval '1 day'
     OR pg_temp.metric('signup_completed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed sign-up overwrote or recounted (%)', v_res;
  END IF;

  -- 3b. A users row someone else created first (record_eula_acceptance, the
  --     invite functions' ensureUserRow) is still a first sign-up: created
  --     and signup_completed follow the DOB this call wrote, which the PK
  --     serialises against a racing replay (fix round 1, M-2).
  SET LOCAL ROLE service_role;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_prerow, '+15558100045', '')
  ON CONFLICT (id) DO NOTHING;
  RESET ROLE;
  v_before := pg_temp.metric('signup_completed');
  PERFORM pg_temp.as_user(v_prerow);
  v_res := public.complete_sign_up('Esi Prerow', DATE '1992-02-02', '2');
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('age', extract(year FROM age(v_today, DATE '1992-02-02'))::int, 'created', true)
     OR pg_temp.metric('signup_completed') IS DISTINCT FROM v_before + 1
     OR (SELECT display_name FROM public.users WHERE id = v_prerow) IS DISTINCT FROM 'Esi Prerow' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a first sign-up on a pre-created users row gave % (signup_completed % -> %)',
      v_res, v_before, pg_temp.metric('signup_completed');
  END IF;
  PERFORM pg_temp.as_user(v_prerow);
  v_res := public.complete_sign_up('Esi Prerow', DATE '1992-02-02', '2');
  RESET ROLE;
  IF v_res ->> 'created' IS DISTINCT FROM 'false' OR pg_temp.metric('signup_completed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay after a pre-created row recounted (%)', v_res;
  END IF;

  -- 3c. Consent never goes down (fix round 1, M-3): a replay with an older
  --     version keeps the newer one and its time; a newer one moves both.
  UPDATE public.users SET eula_version = '3', eula_accepted_at = now() - interval '2 days' WHERE id = v_adult;
  PERFORM pg_temp.as_user(v_adult);
  PERFORM public.complete_sign_up('Ama Mensah', DATE '1996-03-27', '2');
  RESET ROLE;
  IF (SELECT eula_version FROM public.users WHERE id = v_adult) IS DISTINCT FROM '3'
     OR (SELECT eula_accepted_at FROM public.users WHERE id = v_adult) IS DISTINCT FROM now() - interval '2 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replay lowered the EULA version (now %, accepted %)',
      (SELECT eula_version FROM public.users WHERE id = v_adult), (SELECT eula_accepted_at FROM public.users WHERE id = v_adult);
  END IF;
  PERFORM pg_temp.as_user(v_adult);
  PERFORM public.complete_sign_up('Ama Mensah', DATE '1996-03-27', '10');
  RESET ROLE;
  IF (SELECT eula_version FROM public.users WHERE id = v_adult) IS DISTINCT FROM '10'
     OR (SELECT eula_accepted_at FROM public.users WHERE id = v_adult) IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a newer EULA version (10 after 3, by number) was not recorded with its time';
  END IF;

  -- 4. Refusals that name the problem.
  PERFORM pg_temp.as_user(v_unverified);
  v_msg := pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', '2')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified phone was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_twi);
  FOREACH v_msg IN ARRAY ARRAY[
    pg_temp.error_of($q$SELECT public.complete_sign_up('12 !! --', DATE '1990-05-05', '2')$q$),
    pg_temp.error_of($q$SELECT public.complete_sign_up('   ', DATE '1990-05-05', '2')$q$),
    pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', repeat('a', 41), DATE '1990-05-05', '2'))] LOOP
    IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a bad name was not refused (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  FOREACH v_msg IN ARRAY ARRAY[
    pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', 'Efua', v_today + 1, '2')),
    pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1899-12-31', '2')$q$)] LOOP
    IF v_msg IS DISTINCT FROM 'signup:invalid_birth_date' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a bad DOB was not refused (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  v_msg := pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', NULL)$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:eula_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up without consent was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  -- A5 is EULA v2: an older or malformed version is no consent (fix round 1, M-3).
  PERFORM pg_temp.as_user(v_twi);
  FOREACH v_msg IN ARRAY ARRAY[
    pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', '1')$q$),
    pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', '0')$q$),
    pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', 'v2')$q$)] LOOP
    IF v_msg IS DISTINCT FROM 'signup:eula_required' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: an older or malformed EULA version was accepted (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.users WHERE id = v_twi) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused sign-up wrote a users row';
  END IF;

  -- 5. Review Focus 2: a name in any script is a name.
  PERFORM pg_temp.as_user(v_twi);
  PERFORM public.complete_sign_up('Ɛsi  Ɔbɛng', DATE '1990-05-05', '2');
  RESET ROLE;
  PERFORM pg_temp.as_user(v_arabic);
  PERFORM public.complete_sign_up('عائشة', DATE '1990-05-05', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_twi) IS DISTINCT FROM 'Ɛsi Ɔbɛng'
     OR (SELECT display_name FROM public.users WHERE id = v_arabic) IS DISTINCT FROM 'عائشة' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-Latin or West African name was not kept as typed';
  END IF;
  -- Tabs and newlines are whitespace too, at the edges as inside (fix
  -- round 1, M-1): "1-40 after trim".
  PERFORM pg_temp.as_user(v_tabbed);
  PERFORM public.complete_sign_up(E'\tAma  Mensah\n', DATE '1990-05-05', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_tabbed) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT display_name FROM public.profiles WHERE id = v_tabbed) IS DISTINCT FROM 'Ama Mensah' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: edge whitespace survived in a name (users %, profiles %)',
      quote_literal((SELECT display_name FROM public.users WHERE id = v_tabbed)),
      quote_literal((SELECT display_name FROM public.profiles WHERE id = v_tabbed));
  END IF;

  -- 6. Review Focus 1: the 18th birthday (UTC date) is in; the day after that DOB is not.
  PERFORM pg_temp.as_user(v_birthday);
  v_res := public.complete_sign_up('Kojo', v_eighteen, '2');
  RESET ROLE;
  IF (v_res ->> 'age')::int IS DISTINCT FROM 18 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an 18th-birthday sign-up gave %', v_res;
  END IF;
  PERFORM pg_temp.as_user(v_tomorrow);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', 'Akua', v_eighteen + 1, '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone turning 18 tomorrow was let in (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 7. Legacy accounts: a DOB once; under 18 places a hold that commits.
  PERFORM pg_temp.as_user(v_legacy);
  v_res := public.set_my_birth_date(DATE '1990-01-01');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_birth_date(DATE '1991-01-01')$q$);
  v_n := public.get_my_age();
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('status', 'ok', 'age', extract(year FROM age(v_today, DATE '1990-01-01'))::int)
     OR v_msg IS DISTINCT FROM 'birth_date:already_set'
     OR v_n IS DISTINCT FROM extract(year FROM age(v_today, DATE '1990-01-01'))::int THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy DOB: first %, second %, age %', v_res, v_msg, v_n;
  END IF;
  PERFORM pg_temp.as_user(v_legacy_minor);
  BEGIN
    v_res := public.set_my_birth_date((v_today - interval '16 years')::date);
  EXCEPTION WHEN OTHERS THEN
    -- A raise would roll the hold and the DOB back (fix round 1, N-1).
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_birth_date raised for a minor (%)', SQLERRM;
  END;
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds
                     WHERE user_id = v_legacy_minor AND kind = 'age_review' AND resolved_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_legacy_minor) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy minor got % without a kept hold and DOB', v_res;
  END IF;

  -- 7b. A held minor can't get past A5 by typing an adult date: sign-up
  --     judges the stored DOB, and nothing changes (fix round 1, I-1).
  PERFORM pg_temp.as_user(v_legacy_minor);
  v_msg := pg_temp.error_of($q$SELECT public.complete_sign_up('Grown Up', DATE '1990-01-01', '2')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:not_eligible'
     OR (SELECT birth_date FROM public.account_birthdates WHERE user_id = v_legacy_minor)
        IS DISTINCT FROM (v_today - interval '16 years')::date
     OR NOT EXISTS (SELECT 1 FROM public.account_holds
                     WHERE user_id = v_legacy_minor AND kind = 'age_review' AND resolved_at IS NULL)
     OR (SELECT eula_version FROM public.users WHERE id = v_legacy_minor) IS NOT NULL
     OR (SELECT display_name FROM public.users WHERE id = v_legacy_minor) IS DISTINCT FROM 'Legacy Minor W1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held minor got past sign-up with an adult date (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 7c. The legacy line is the same UTC-date rule as sign-up (fix round 1,
  --     I-1): turning 18 tomorrow is held; turning 18 today is in, unheld.
  PERFORM pg_temp.as_user(v_legacy_teen);
  v_res := public.set_my_birth_date(v_eighteen + 1);
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds
                     WHERE user_id = v_legacy_teen AND kind = 'age_review' AND resolved_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy account turning 18 tomorrow got % and no hold', v_res;
  END IF;
  PERFORM pg_temp.as_user(v_legacy_eighteen);
  v_res := public.set_my_birth_date(v_eighteen);
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('status', 'ok', 'age', 18)
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_legacy_eighteen) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy account turning 18 today got % (or a hold)', v_res;
  END IF;
  PERFORM pg_temp.as_user(v_unverified);
  IF public.get_my_age() IS NOT NULL THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_age returned an age with no DOB';
  END IF;
  RESET ROLE;

  -- 8. Holds: the two-argument call (I-7); a resolved hold re-opens; recovery expires in 180 days.
  PERFORM public.place_account_hold(v_legacy, 'safety_review');
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = v_legacy AND kind = 'safety_review';
  PERFORM public.place_account_hold(v_legacy, 'safety_review', 'case-1');
  IF NOT EXISTS (SELECT 1 FROM public.account_holds
                  WHERE user_id = v_legacy AND kind = 'safety_review'
                    AND resolved_at IS NULL AND resolved_by IS NULL AND reason_ref = 'case-1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold did not re-open';
  END IF;
  PERFORM public.place_account_hold(v_legacy, 'recovery_hold');
  IF (SELECT expires_at FROM public.account_holds WHERE user_id = v_legacy AND kind = 'recovery_hold')
     NOT BETWEEN now() + interval '179 days' AND now() + interval '181 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recovery hold does not expire in 180 days';
  END IF;
  -- A resolved, lapsed recovery hold placed again gets a fresh 180 days, not
  -- its stale expiry (fix round 1, M-7; else W6a's purge would act at once).
  UPDATE public.account_holds
     SET expires_at = now() - interval '1 day', resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = v_legacy AND kind = 'recovery_hold';
  PERFORM public.place_account_hold(v_legacy, 'recovery_hold');
  IF ((SELECT expires_at FROM public.account_holds WHERE user_id = v_legacy AND kind = 'recovery_hold')
      BETWEEN now() + interval '179 days' AND now() + interval '181 days') IS NOT TRUE
     OR (SELECT resolved_at FROM public.account_holds WHERE user_id = v_legacy AND kind = 'recovery_hold') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a re-opened recovery hold kept its old expiry';
  END IF;
  v_msg := pg_temp.error_of(format('SELECT public.place_account_hold(%L, %L)', v_legacy, 'banned'));
  IF v_msg IS DISTINCT FROM 'new row for relation "account_holds" violates check constraint "account_holds_kind_check"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown hold kind was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- =====================================================================
-- G. Paths and home state (W1b; Q6, Q7, D14, D18, I-6). Fixtures 20-39,
--    relationships 5f1a0000-0000-0000-0000-0000000001NN.
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regprocedure('public.set_my_path(text,boolean)') IS NULL
     OR to_regprocedure('public.get_my_home_state()') IS NULL
     OR to_regprocedure('public.set_user_path_internal(uuid,text)') IS NULL
     OR to_regprocedure('public.withdraw_my_pending_invites(boolean)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b path objects are missing (set_my_path, get_my_home_state, set_user_path_internal)';
  END IF;

  -- I-6: no W1 function names a table or column that a later wave creates.
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.verified_phone(uuid)'::regprocedure,
                   'private.metric_increment(text)'::regprocedure,
                   'private.bump_metric_internal(text)'::regprocedure,
                   'public.bump_metric(text)'::regprocedure,
                   'public.bump_metric_server(text)'::regprocedure,
                   'public.complete_sign_up(text,date,text)'::regprocedure,
                   'public.set_my_birth_date(date)'::regprocedure,
                   'public.account_age(uuid)'::regprocedure,
                   'public.place_account_hold(uuid,text,text)'::regprocedure,
                   'private.spec1_flag_on(text)'::regprocedure,
                   'private.dating_home_summary(uuid)'::regprocedure,
                   'public.set_user_path_internal(uuid,text)'::regprocedure,
                   'public.set_my_path(text,boolean)'::regprocedure,
                   'public.get_my_home_state()'::regprocedure,
                   'public.withdraw_my_pending_invites(boolean)'::regprocedure)
     AND p.prosrc ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
  END IF;

  -- Privileges.
  IF has_function_privilege('authenticated', 'public.set_user_path_internal(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.spec1_flag_on(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_home_summary(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_home_state()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_my_path(text,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_home_state()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_my_path(text,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites(boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: path function grants are wrong';
  END IF;

  -- onboarding_profiles.mode is gone (W1b; its client writer goes in the same release).
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'onboarding_profiles' AND column_name = 'mode') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: onboarding_profiles.mode still exists';
  END IF;
END $$;

-- An adult with a DOB, a v2 consent and (optionally) a path.
CREATE FUNCTION pg_temp.adult(p_id uuid, p_phone text, p_name text, p_eula text, p_path text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.make_account(p_id, p_phone, p_name);
  UPDATE public.users SET eula_version = p_eula, eula_accepted_at = now(), path = p_path,
                          path_chosen_at = CASE WHEN p_path IS NULL THEN NULL ELSE now() - interval '1 day' END
   WHERE id = p_id;
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (p_id, DATE '1990-01-01');
END $$;

DO $$
BEGIN
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000020', '+15558100020', 'Esi Path', '2', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000021', '+15558100021', 'No DOB W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000022', '+15558100022', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000023', '+15558100023', 'Adwoa Linked', '2', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000024', '+15558100024', 'Kojo Asante', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000025', '+15558100025', 'Akosua Paused', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000026', '+15558100026', '+15558100026', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000027', '+15558100027', 'Efua Ended', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000028', '+15558100028', 'Kwabena Ended', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000029', '+15558100029', 'Ama Long Ago', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000030', '+15558100030', 'Yaw Long Ago', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000031', '+15558100031', 'Abena First', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000032', '+15558100032', 'Dating Spy', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000033', '+15558100033', 'Just Me', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000034', '+15558100034', 'Held W1', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000035', '+15558100035', 'Old Consent', '1', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000036', '+15558100036', 'Dating To Couple', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000037', '+15558100037', 'Dating To Me', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000038', '+15558100038', 'Pending Invite', '2', 'relationship');
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, created_at) VALUES
  ('5f1a0000-0000-0000-0000-000000000101', '5f1a0000-0000-0000-0000-000000000023',
   '5f1a0000-0000-0000-0000-000000000024', 'active', current_date, now() - interval '10 days', now() - interval '10 days');
INSERT INTO public.relationships (id, user_a, user_b, status, created_at, paused_at, paused_by) VALUES
  ('5f1a0000-0000-0000-0000-000000000102', '5f1a0000-0000-0000-0000-000000000025',
   '5f1a0000-0000-0000-0000-000000000026', 'paused', now() - interval '20 days', now() - interval '1 day',
   '5f1a0000-0000-0000-0000-000000000025');
INSERT INTO public.relationships (id, user_a, user_b, status, created_at, ended_at, ended_by) VALUES
  ('5f1a0000-0000-0000-0000-000000000103', '5f1a0000-0000-0000-0000-000000000027',
   '5f1a0000-0000-0000-0000-000000000028', 'ended', now() - interval '60 days', now() - interval '2 days',
   '5f1a0000-0000-0000-0000-000000000027'),
  ('5f1a0000-0000-0000-0000-000000000104', '5f1a0000-0000-0000-0000-000000000029',
   '5f1a0000-0000-0000-0000-000000000030', 'ended', now() - interval '90 days', now() - interval '40 days',
   '5f1a0000-0000-0000-0000-000000000029');
INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at) VALUES
  ('5f1a0000-0000-0000-0000-000000000105', '5f1a0000-0000-0000-0000-000000000031', 'pending', 'W1PND5',
   now() + interval '6 days', now() - interval '1 day'),
  ('5f1a0000-0000-0000-0000-000000000106', '5f1a0000-0000-0000-0000-000000000038', 'pending', 'W1PND6',
   now() + interval '5 days', now() - interval '2 days');
INSERT INTO public.dating_enrollments (user_id, state) VALUES
  ('5f1a0000-0000-0000-0000-000000000032', 'active'),
  ('5f1a0000-0000-0000-0000-000000000036', 'active'),
  ('5f1a0000-0000-0000-0000-000000000037', 'active');
DO $$
BEGIN
  PERFORM public.place_account_hold('5f1a0000-0000-0000-0000-000000000034', 'safety_review');
END $$;

CREATE FUNCTION pg_temp.home_of(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user(p);
  v := public.get_my_home_state();
  RESET ROLE;
  RETURN v;
END $$;

-- G1. Who may choose a path, and the refusals by name.
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000021');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a path without a DOB was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000022');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a path without an account was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- With flow_signin_v2 effectively on, EULA 2 is required.
  INSERT INTO public.feature_flags (key, enabled) VALUES ('flow_signin_v2', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000035');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_signin_v2';
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 consent chose a path under flow_signin_v2 (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000020');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('couples')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown path was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000023');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:relationship_open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a linked member left Relationship (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000025');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('dating')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:relationship_open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member left Relationship (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- A pending invite: confirm first, then the invite goes in the same call.
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000038');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:confirm_withdraw' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving with a pending invite did not ask first (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000038');
  PERFORM public.set_my_path('just_me', true);
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.relationships WHERE id = '5f1a0000-0000-0000-0000-000000000106')
     OR (SELECT path FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000038') <> 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a confirmed switch kept the invite or the old path';
  END IF;
END $$;

-- G2. The first choice, then a switch: path_previous, relationship_status
--     once (D14), onboarding_profiles, metrics, tab.
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000020';
  v_res jsonb;
  v_chosen_before bigint := pg_temp.metric('path_chosen:just_me');
  v_switch_before bigint := pg_temp.metric('path_switch_7d:just_me>relationship');
BEGIN
  IF pg_temp.home_of(v_me) -> 'needs' IS DISTINCT FROM '["path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no path did not need one: %', pg_temp.home_of(v_me);
  END IF;
  PERFORM pg_temp.as_user(v_me);
  v_res := public.set_my_path('just_me');
  RESET ROLE;
  IF v_res ->> 'path' IS DISTINCT FROM 'just_me' OR v_res ->> 'tab' IS DISTINCT FROM 'me'
     OR v_res -> 'needs' IS DISTINCT FROM '[]'::jsonb OR v_res -> 'path_previous' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_path did not return the new home state: %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.onboarding_profiles WHERE user_id = v_me)
     OR (SELECT relationship_status FROM public.profiles WHERE id = v_me) IS DISTINCT FROM 'figuring_it_out'
     OR (SELECT path_chosen_at FROM public.users WHERE id = v_me) IS NULL
     OR pg_temp.metric('path_chosen:just_me') <> v_chosen_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first path choice did not record onboarding, status, time and metric';
  END IF;

  PERFORM pg_temp.as_user(v_me);
  v_res := public.set_my_path('relationship');
  RESET ROLE;
  IF v_res ->> 'path' IS DISTINCT FROM 'relationship' OR v_res ->> 'path_previous' IS DISTINCT FROM 'just_me'
     OR v_res ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch did not keep path_previous or map Relationship to Chat: %', v_res;
  END IF;
  IF (SELECT relationship_status FROM public.profiles WHERE id = v_me) IS DISTINCT FROM 'figuring_it_out' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_status was re-synced on a switch (D14)';
  END IF;
  IF pg_temp.metric('path_switch_7d:just_me>relationship') <> v_switch_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch within 7 days was not counted';
  END IF;

  -- Cancel the invite and go back where they came from (Q7).
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000107', v_me, 'pending', 'W1PND7', now() + interval '7 days');
  PERFORM pg_temp.as_user(v_me);
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw did not remove the pending invite';
  END IF;
  RESET ROLE;
  IF (SELECT path FROM public.users WHERE id = v_me) IS DISTINCT FROM 'just_me'
     OR (SELECT path_previous FROM public.users WHERE id = v_me) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw-with-return did not restore the previous path';
  END IF;
END $$;

-- G3. Review Focus 4: cancelling with no previous path keeps Relationship.
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000031';
  v_home jsonb;
BEGIN
  PERFORM pg_temp.as_user(v_me);
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw did not remove the first-time inviter''s invite';
  END IF;
  RESET ROLE;
  v_home := pg_temp.home_of(v_me);
  IF v_home ->> 'path' IS DISTINCT FROM 'relationship' OR v_home -> 'link' ->> 'state' IS DISTINCT FROM 'none'
     OR v_home ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancelling with no previous path left %', v_home;
  END IF;
END $$;

-- G4. get_my_home_state: link states, partner names, tab, needs, hold, dating.
DO $$
DECLARE
  v jsonb;
BEGIN
  -- Review Focus 3: a legacy linked member with no path keeps Chat.
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000023');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked' OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Kojo'
     OR v ->> 'tab' IS DISTINCT FROM 'chat' OR v -> 'needs' IS DISTINCT FROM '["path"]'::jsonb
     OR v -> 'link' ->> 'relationship_id' IS DISTINCT FROM '5f1a0000-0000-0000-0000-000000000101' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linked (legacy, no path): %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000024');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked' OR v ->> 'tab' IS DISTINCT FROM 'chat'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Adwoa' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linked: %', v;
  END IF;
  -- A phone stored as a name is never shown.
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000025');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'paused' OR v -> 'link' -> 'partner_first_name' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000026');
  IF v -> 'needs' IS DISTINCT FROM '["name"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone stored as a name did not need a name: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000027');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'ended_window'
     OR (v -> 'link' ->> 'window_ends_at')::timestamptz
        IS DISTINCT FROM (SELECT ended_at + interval '30 days' FROM public.relationships
                           WHERE id = '5f1a0000-0000-0000-0000-000000000103') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ended inside the window: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000029');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'after_ending' OR v -> 'link' -> 'window_ends_at' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ended after the window: %', v;
  END IF;
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000108', '5f1a0000-0000-0000-0000-000000000033', 'pending', 'W1PND8',
          now() + interval '7 days');
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000033');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'pending' OR v -> 'link' -> 'invite_expires_at' = 'null'::jsonb
     OR v -> 'link' -> 'partner_first_name' IS DISTINCT FROM 'null'::jsonb OR v ->> 'tab' IS DISTINCT FROM 'me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pending (on Just for me): %', v;
  END IF;
  DELETE FROM public.relationships WHERE id = '5f1a0000-0000-0000-0000-000000000108';
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000033');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'none' OR v -> 'link' -> 'relationship_id' IS DISTINCT FROM 'null'::jsonb
     OR v ->> 'tab' IS DISTINCT FROM 'me' OR (v ->> 'hold')::boolean
     OR v -> 'dating' IS DISTINCT FROM jsonb_build_object('enabled', public.dating_flag_enabled('dating_mode_enabled'), 'enrolled', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: none: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000034');
  IF NOT (v ->> 'hold')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unresolved hold was not reported: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000036');
  IF NOT (v -> 'dating' ->> 'enrolled')::boolean OR v ->> 'tab' IS DISTINCT FROM 'me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating enrollment was not summarised: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000035');
  IF v -> 'needs' IS DISTINCT FROM '["consent", "path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 consent did not need consent: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000022');
  IF (v ->> 'has_account')::boolean OR v -> 'needs' IS DISTINCT FROM '["consent", "birth_date", "name", "path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no account: %', v;
  END IF;
END $$;

-- G5. D18: Spec 1 pauses Dating only on a change to Relationship, exactly once.
DO $$
DECLARE
  v_dating constant uuid := '5f1a0000-0000-0000-0000-000000000032';
  v_def constant text := pg_get_functiondef('public.pause_dating_for_relationship_user(uuid)'::regprocedure);
  v_msg text;
BEGIN
  PERFORM set_config('w1.pause_calls', '0', true);
  EXECUTE $spy$
    CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
    RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $body$
    BEGIN
      PERFORM set_config('w1.pause_calls',
        (coalesce(nullif(current_setting('w1.pause_calls', true), ''), '0')::int + 1)::text, true);
    END
    $body$
  $spy$;

  PERFORM pg_temp.as_user(v_dating);
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF current_setting('w1.pause_calls') <> '0' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Just for me called the Dating pause (Spec 2 W2 owns that, D18)';
  END IF;

  UPDATE public.users SET path = 'dating' WHERE id = v_dating;
  PERFORM pg_temp.as_user(v_dating);
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('relationship')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:confirm_pause_dating' OR current_setting('w1.pause_calls') <> '0' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed Dating -> Relationship gave % with % pause call(s)',
      coalesce(v_msg, 'no error'), current_setting('w1.pause_calls');
  END IF;

  PERFORM pg_temp.as_user(v_dating);
  PERFORM public.set_my_path('relationship', true);
  RESET ROLE;
  IF current_setting('w1.pause_calls') <> '1' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Relationship made % pause call(s), expected exactly 1',
      current_setting('w1.pause_calls');
  END IF;
  EXECUTE v_def;
END $$;

-- G6. D18 with the real pause: Relationship pauses Dating; Just for me doesn't.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000036');
  PERFORM public.set_my_path('relationship', true);
  RESET ROLE;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000037');
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = '5f1a0000-0000-0000-0000-000000000036') <> 'paused'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = '5f1a0000-0000-0000-0000-000000000037') <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the D18 pause rule is wrong with the real pause function';
  END IF;
END $$;

-- G7. Effective flags (§2.5): a flag is on only with everything it needs.
DO $$
BEGIN
  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('flow_signin_v2', false), ('flow_paths_v2', true), ('flow_couples_v2', true), ('couple_profile', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
  IF private.spec1_flag_on('flow_paths_v2') OR private.spec1_flag_on('flow_couples_v2')
     OR private.spec1_flag_on('couple_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a flag was effective without flow_signin_v2';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'flow_signin_v2';
  IF NOT (private.spec1_flag_on('flow_paths_v2') AND private.spec1_flag_on('flow_couples_v2')
          AND private.spec1_flag_on('couple_profile')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the whole chain on did not read on';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_paths_v2';
  IF private.spec1_flag_on('flow_couples_v2') OR private.spec1_flag_on('couple_profile')
     OR NOT private.spec1_flag_on('flow_signin_v2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a flag stayed effective after what it needs went off';
  END IF;
  IF private.spec1_flag_on('no_such_spec1_flag') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missing flag read as on';
  END IF;
  UPDATE public.feature_flags SET enabled = false
   WHERE key IN ('flow_signin_v2', 'flow_paths_v2', 'flow_couples_v2', 'couple_profile');
END $$;

-- G8. Batch 4 extras (each closes a mutant that section G let through):
--     a resolved hold lifts H1; withdraw(false) keeps the path; a minor
--     with a stored DOB can't choose a path; the 30-day switch bucket.
--     Fixtures 39 and 47, relationship ...0109.
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000039';
  v_minor constant uuid := '5f1a0000-0000-0000-0000-000000000047';
  v_30d_before bigint := pg_temp.metric('path_switch_30d:just_me>relationship');
  v_7d_before bigint := pg_temp.metric('path_switch_7d:just_me>relationship');
  v_msg text;
BEGIN
  -- A resolved hold is not a hold: H1 lifts.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = '5f1a0000-0000-0000-0000-000000000034' AND resolved_at IS NULL;
  IF (pg_temp.home_of('5f1a0000-0000-0000-0000-000000000034') ->> 'hold')::boolean IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold was still reported: %',
      pg_temp.home_of('5f1a0000-0000-0000-0000-000000000034');
  END IF;

  -- A switch 8-30 days after the last choice lands in the 30-day bucket only.
  PERFORM pg_temp.adult(v_me, '+15558100039', 'Thirty Days', '2', 'just_me');
  UPDATE public.users SET path_chosen_at = now() - interval '10 days' WHERE id = v_me;
  PERFORM pg_temp.as_user(v_me);
  PERFORM public.set_my_path('relationship');
  RESET ROLE;
  IF pg_temp.metric('path_switch_30d:just_me>relationship') <> v_30d_before + 1
     OR pg_temp.metric('path_switch_7d:just_me>relationship') <> v_7d_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch after 10 days was not counted in the 30-day bucket only (30d % -> %, 7d % -> %)',
      v_30d_before, pg_temp.metric('path_switch_30d:just_me>relationship'),
      v_7d_before, pg_temp.metric('path_switch_7d:just_me>relationship');
  END IF;

  -- withdraw_my_pending_invites(false) withdraws and keeps the path.
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000109', v_me, 'pending', 'W1PND9', now() + interval '7 days');
  PERFORM pg_temp.as_user(v_me);
  IF public.withdraw_my_pending_invites(false) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw(false) did not remove the pending invite';
  END IF;
  RESET ROLE;
  IF (SELECT path FROM public.users WHERE id = v_me) IS DISTINCT FROM 'relationship'
     OR (SELECT path_previous FROM public.users WHERE id = v_me) IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw(false) changed the path (path %, previous %)',
      (SELECT path FROM public.users WHERE id = v_me), (SELECT path_previous FROM public.users WHERE id = v_me);
  END IF;

  -- A minor whose DOB is stored (a legacy set_my_birth_date) gets no path.
  PERFORM pg_temp.make_account(v_minor, '+15558100047', 'Young W1');
  UPDATE public.users SET eula_version = '2', eula_accepted_at = now() WHERE id = v_minor;
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_minor, ((now() AT TIME ZONE 'utc')::date - interval '17 years')::date);
  PERFORM pg_temp.as_user(v_minor);
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:needs_signup'
     OR (SELECT path FROM public.users WHERE id = v_minor) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a minor with a stored DOB chose a path (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;

-- G9. Fix round 0 (batch 4, concern 1): the EULA version is read as a number
--     of at most three digits, the same way complete_sign_up reads it. A long
--     digit string never throws and counts as not accepted; a later version
--     ('3') counts as accepted. Fixtures 48 and 49.
DO $$
DECLARE
  v_future constant uuid := '5f1a0000-0000-0000-0000-000000000049';
  v_home jsonb;
  v_res jsonb;
  v_msg text;
BEGIN
  PERFORM pg_temp.adult(v_future, '+15558100049', 'Later Consent', '3', NULL);
  v_home := pg_temp.home_of(v_future);
  IF v_home -> 'needs' IS DISTINCT FROM '["path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: EULA ''3'' did not count as accepted: %', v_home;
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('flow_signin_v2', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  PERFORM pg_temp.as_user(v_future);
  BEGIN
    v_res := public.set_my_path('just_me');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_signin_v2';
  IF v_msg IS NOT NULL OR v_res ->> 'path' IS DISTINCT FROM 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: EULA ''3'' could not choose a path under flow_signin_v2 (got %)',
      coalesce(v_msg, v_res::text);
  END IF;
END $$;

DO $$
DECLARE
  v_long constant uuid := '5f1a0000-0000-0000-0000-000000000048';
  v_home jsonb;
  v_msg text;
BEGIN
  PERFORM pg_temp.adult(v_long, '+15558100048', 'Long Consent', '99999999999', NULL);
  BEGIN
    v_home := pg_temp.home_of(v_long);
  EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a long EULA version made get_my_home_state throw (%)', SQLERRM;
  END;
  IF v_home -> 'needs' IS DISTINCT FROM '["consent", "path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a long EULA version counted as accepted: %', v_home;
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('flow_signin_v2', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  PERFORM pg_temp.as_user(v_long);
  BEGIN
    PERFORM public.set_my_path('just_me');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_signin_v2';
  IF v_msg IS DISTINCT FROM 'path:needs_signup'
     OR (SELECT path FROM public.users WHERE id = v_long) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a long EULA version chose a path under flow_signin_v2 (got %)',
      coalesce(v_msg, 'no error');
  END IF;
END $$;

-- G10 (review #1, #2): a linked member who still has their own pending
-- invite (legacy accept-invite keeps it until W4a) reads linked, and
-- cancelling that stale invite never moves them off Relationship.
DO $$
DECLARE
  v_x constant uuid := '5f1a0000-0000-0000-0000-000000000050';
  v_y constant uuid := '5f1a0000-0000-0000-0000-000000000051';
  v jsonb;
BEGIN
  PERFORM pg_temp.adult(v_x, '+15558100050', 'Xorla Mutual', '2', 'relationship');
  PERFORM pg_temp.adult(v_y, '+15558100051', 'Yao Mutual', '2', 'relationship');
  UPDATE public.users SET path_previous = 'just_me' WHERE id = v_x;
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at) VALUES
    ('5f1a0000-0000-0000-0000-000000000110', v_y, 'pending', 'W1PNDA', now() + interval '6 days', now() - interval '2 hours'),
    ('5f1a0000-0000-0000-0000-000000000111', v_x, 'pending', 'W1PNDB', now() + interval '6 days', now() - interval '1 hour');
  UPDATE public.relationships SET user_b = v_x, status = 'active', invite_code = NULL, invite_accepted_at = now()
   WHERE id = '5f1a0000-0000-0000-0000-000000000110';

  v := pg_temp.home_of(v_x);
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked'
     OR v -> 'link' ->> 'relationship_id' IS DISTINCT FROM '5f1a0000-0000-0000-0000-000000000110'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Yao' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a linked member with a stale own invite did not read linked: %', v;
  END IF;

  PERFORM pg_temp.as_user(v_x);
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stale own invite was not withdrawn';
  END IF;
  RESET ROLE;
  IF (SELECT path FROM public.users WHERE id = v_x) IS DISTINCT FROM 'relationship'
     OR pg_temp.home_of(v_x) ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw(true) moved a linked member off Relationship (path %)',
      (SELECT path FROM public.users WHERE id = v_x);
  END IF;
END $$;

-- G11. Fix round 1 minors (batch 4 review #3, #5, #6, #7): a linked member on
--      another path keeps Chat; D14 keeps a legacy status; the ex's name only
--      inside the ending window; a sealed or archived ending inside 30 days is
--      still the window. Fixtures 52-59, relationships ...0112-0115. The
--      paused arm (batch 4 re-review C): fixtures 5f1a0000-0000-0000-0003-
--      000000000001/02, relationships ...0003-000000000101/102.
DO $$
DECLARE
  v jsonb;
BEGIN
  -- #3: linked through legacy accept-invite after choosing Just for me.
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000052', '+15558100052', 'Kofi Elsewhere', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000053', '+15558100053', 'Esi Inviter', '2', 'relationship');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, created_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000112', '5f1a0000-0000-0000-0000-000000000053',
          '5f1a0000-0000-0000-0000-000000000052', 'active', current_date, now(), now() - interval '1 day');
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000052');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked' OR v ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a linked member on Just for me was not given Chat: %', v;
  END IF;

  -- P-3, pending: a legacy inviter with no path keeps Chat while the invite
  -- waits (the #3 rule covers only linked and paused).
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000059', '+15558100059', 'Legacy Inviter', '2', NULL);
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000115', '5f1a0000-0000-0000-0000-000000000059', 'pending', 'W1PNDC',
          now() + interval '7 days');
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000059');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'pending' OR v ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy inviter with no path was not given Chat: %', v;
  END IF;

  -- #5 (D14): a status legacy onboarding wrote is kept at the first path choice.
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000054', '+15558100054', 'Legacy Status', '2', NULL);
  INSERT INTO public.profiles (id, relationship_status) VALUES ('5f1a0000-0000-0000-0000-000000000054', 'taken')
  ON CONFLICT (id) DO UPDATE SET relationship_status = 'taken';
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000054');
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF (SELECT relationship_status FROM public.profiles WHERE id = '5f1a0000-0000-0000-0000-000000000054')
     IS DISTINCT FROM 'taken' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first path choice overwrote a legacy relationship_status (now %)',
      (SELECT relationship_status FROM public.profiles WHERE id = '5f1a0000-0000-0000-0000-000000000054');
  END IF;

  -- #6: the ex's name only inside the ending window (as the lifecycle card).
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000029');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'after_ending'
     OR v -> 'link' -> 'partner_first_name' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ex''s name came back after the window: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000027');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'ended_window'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Kwabena' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ending window lost the partner''s name: %', v;
  END IF;

  -- #7: sealed by me, or archived (a new chapter), inside 30 days of the end
  --     is still the window: no "More ways" row, and the gentle-wait date.
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000055', '+15558100055', 'Ama Sealed', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000056', '+15558100056', 'Kwesi Sealed', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000057', '+15558100057', 'Afia Archived', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000058', '+15558100058', 'Yaw Moved On', '2', 'relationship');
  INSERT INTO public.relationships (id, user_a, user_b, status, created_at, ended_at, ended_by) VALUES
    ('5f1a0000-0000-0000-0000-000000000113', '5f1a0000-0000-0000-0000-000000000055',
     '5f1a0000-0000-0000-0000-000000000056', 'ended', now() - interval '80 days', now() - interval '3 days',
     '5f1a0000-0000-0000-0000-000000000055');
  INSERT INTO public.relationship_seals (relationship_id, user_id)
  VALUES ('5f1a0000-0000-0000-0000-000000000113', '5f1a0000-0000-0000-0000-000000000055');
  INSERT INTO public.relationships (id, user_a, user_b, status, created_at, ended_at, ended_by,
                                    chat_archived_at, chat_archived_reason) VALUES
    ('5f1a0000-0000-0000-0000-000000000114', '5f1a0000-0000-0000-0000-000000000057',
     '5f1a0000-0000-0000-0000-000000000058', 'archived', now() - interval '100 days', now() - interval '5 days',
     '5f1a0000-0000-0000-0000-000000000058', now() - interval '1 day', 'partner_new_relationship');
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000055');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'ended_window'
     OR (v -> 'link' ->> 'window_ends_at')::timestamptz IS DISTINCT FROM now() - interval '3 days' + interval '30 days'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Kwesi' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ending I sealed inside 30 days was not the window: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000057');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'ended_window'
     OR (v -> 'link' ->> 'window_ends_at')::timestamptz IS DISTINCT FROM now() - interval '5 days' + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an archived ending inside 30 days was not the window: %', v;
  END IF;

  -- The paused arm (batch 4 re-review C): G10 and the lines above use active
  -- only. A member who chose Just for me, was linked through legacy
  -- accept-invite, then paused, and still has their own (newer) stale
  -- invite: the paused relationship ranks first, the tab follows the link,
  -- and the partner's name is there while paused.
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0003-000000000001', '+15558103001', 'Adjoa Paused', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0003-000000000002', '+15558103002', 'Nana Partner', '2', 'relationship');
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, created_at,
                                    paused_at, paused_by) VALUES
    ('5f1a0000-0000-0000-0003-000000000101', '5f1a0000-0000-0000-0003-000000000002',
     '5f1a0000-0000-0000-0003-000000000001', 'paused', current_date - 20, now() - interval '20 days',
     now() - interval '20 days', now() - interval '1 day', '5f1a0000-0000-0000-0003-000000000002');
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at) VALUES
    ('5f1a0000-0000-0000-0003-000000000102', '5f1a0000-0000-0000-0003-000000000001', 'pending', 'W1PNDE',
     now() + interval '6 days', now() - interval '1 hour');
  v := pg_temp.home_of('5f1a0000-0000-0000-0003-000000000001');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'paused'
     OR v -> 'link' ->> 'relationship_id' IS DISTINCT FROM '5f1a0000-0000-0000-0003-000000000101'
     OR v ->> 'tab' IS DISTINCT FROM 'chat'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Nana' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member on Just for me with a stale own invite did not read paused, with Chat and the partner''s name: %', v;
  END IF;

  -- The same member on Relationship with a previous path: cancelling the
  -- stale invite with withdraw(true) never moves a paused member off it.
  UPDATE public.users SET path = 'relationship', path_previous = 'just_me'
   WHERE id = '5f1a0000-0000-0000-0003-000000000001';
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0003-000000000001');
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member''s stale own invite was not withdrawn';
  END IF;
  RESET ROLE;
  IF (SELECT path FROM public.users WHERE id = '5f1a0000-0000-0000-0003-000000000001') IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw(true) moved a paused member off Relationship (path %)',
      (SELECT path FROM public.users WHERE id = '5f1a0000-0000-0000-0003-000000000001');
  END IF;
END $$;

-- H0. Clean slate for section H (batch 5): app_setting reads Vault first, so
--     a database whose Vault holds attune_environment or supabase_url (a
--     local cron set-up, say) would override every set_config below. Both
--     are removed inside this transaction only, as settings_accessor_test
--     does; the final ROLLBACK puts them back.
DELETE FROM vault.decrypted_secrets WHERE name IN ('attune_environment', 'supabase_url');

-- =====================================================================
-- H. Environment, production flag gate, public config (W1c; reviews R-6,
--    R-7, A-6, D15). The setting is changed only with set_config inside
--    this transaction; nothing here persists it.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('private.attune_environment()') IS NULL
     OR to_regprocedure('private.assert_development_project()') IS NULL
     OR to_regprocedure('public.get_public_app_config()') IS NULL
     OR to_regclass('private.flag_production_gates') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1c environment objects are missing (attune_environment, assert_development_project, get_public_app_config)';
  END IF;
END $$;

DO $$
DECLARE
  v_bad text;
  v_msg text;
  v_cfg jsonb;
BEGIN
  -- I-6 for the W1c functions.
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('private.attune_environment()'::regprocedure,
                   'private.assert_development_project()'::regprocedure,
                   'private.guard_flag_production_gate()'::regprocedure,
                   'private.dating_open_countries()'::regprocedure,
                   'public.get_public_app_config()'::regprocedure,
                   'public.record_flag_gate_evidence(text,text)'::regprocedure,
                   'public.production_flag_violations()'::regprocedure)
     AND p.prosrc ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports|country_safety_config)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
  END IF;

  -- Privileges: only get_public_app_config reaches anon.
  IF has_function_privilege('anon', 'public.get_attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.production_flag_violations()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.assert_development_project()', 'EXECUTE')
     OR has_table_privilege('anon', 'public.app_public_config', 'SELECT')
     OR has_table_privilege('authenticated', 'public.app_public_config', 'SELECT')
     OR NOT has_function_privilege('anon', 'public.get_public_app_config()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_public_app_config()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_attune_environment()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: environment and config grants are wrong';
  END IF;

  -- private.attune_environment(): unset or development -> development; a typo fails closed.
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unset environment did not read development';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production did not read production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'prodution', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a typo did not fail closed to production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'development', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not read development';
  END IF;

  -- The dev-script guard.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', 'https://abcdefghijklmnopqrst.supabase.co', true);
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed on another project (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.supabase_url', 'https://mrgjtyacrzfylawyzabm.supabase.co', true);
  PERFORM private.assert_development_project();
  PERFORM set_config('app.settings.supabase_url', '', true);
  PERFORM private.assert_development_project();

  -- The eleven flags exist, off; ten carry a gate (flow_couples_v2 has none).
  IF (SELECT count(*) FROM public.feature_flags
       WHERE key IN ('flow_signin_v2', 'flow_paths_v2', 'flow_couples_v2', 'couple_profile', 'dormancy_rule',
                     'platform_age_signals', 'support_resources_v2', 'csam_hash_matching',
                     'opinions_safety_v1', 'journal_ai_insights', 'text_scale_v2')
         AND NOT enabled) <> 11 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the eleven Spec 1 flags are not all present and off';
  END IF;
  IF (SELECT count(*) FROM private.flag_production_gates WHERE review_ref IS NULL) < 10
     OR EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'flow_couples_v2')
     OR NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'journal_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the production gate rows are wrong';
  END IF;

  -- The gate: nothing in development; a gated enable needs evidence in production.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF NOT EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'journal_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production_flag_violations missed a gated flag that is on';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'journal_ai_insights';
  v_msg := pg_temp.error_of($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gated flag was enabled in production without evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  DELETE FROM public.feature_flags WHERE key = 'text_scale_v2';
  v_msg := pg_temp.error_of($q$INSERT INTO public.feature_flags (key, enabled) VALUES ('text_scale_v2', true)$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gated flag was inserted on in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('text_scale_v2', false)
  ON CONFLICT (key) DO UPDATE SET enabled = false;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'flow_couples_v2';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_couples_v2';

  SET LOCAL ROLE service_role;
  v_msg := pg_temp.error_of($q$SELECT public.record_flag_gate_evidence('flow_couples_v2', 'REF-1')$q$);
  IF v_msg IS DISTINCT FROM 'flag:not_gated' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: evidence for an ungated flag was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of($q$SELECT public.record_flag_gate_evidence('journal_ai_insights', '  ')$q$);
  IF v_msg IS DISTINCT FROM 'flag:review_ref_required' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank evidence was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM public.record_flag_gate_evidence('journal_ai_insights', 'W9C-CLINICIAN-2026-11');
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights';
  IF EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'journal_ai_insights')
     OR (SELECT recorded_at FROM private.flag_production_gates WHERE flag_key = 'journal_ai_insights') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recorded evidence did not clear the gate';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'journal_ai_insights';
  PERFORM set_config('app.settings.attune_environment', '', true);

  -- get_public_app_config: anon gets the listed keys only, effective flags,
  -- and the open countries through the seam.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'support_resources_v2';
  PERFORM pg_temp.as_anon();
  v_cfg := public.get_public_app_config();
  RESET ROLE;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg) AS k) <> ARRAY['config', 'flags']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg -> 'flags') AS k)
        <> ARRAY['flow_signin_v2', 'platform_age_signals', 'support_resources_v2', 'text_scale_v2']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg -> 'config') AS k)
        <> ARRAY['age_signal_storefronts', 'dating_open_countries'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_public_app_config returned other keys: %', v_cfg;
  END IF;
  IF v_cfg -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GB", "GH"]'::jsonb
     OR v_cfg -> 'config' -> 'age_signal_storefronts' IS DISTINCT FROM '["USA", "BRA"]'::jsonb
     OR v_cfg -> 'flags' -> 'support_resources_v2' IS DISTINCT FROM 'true'::jsonb
     OR v_cfg -> 'flags' -> 'flow_signin_v2' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_public_app_config values are wrong: %', v_cfg;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'support_resources_v2';
  UPDATE public.app_public_config SET value = '["GH"]' WHERE key = 'dating_open_countries';
  IF public.get_public_app_config() -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GH"]'::jsonb
     OR private.dating_open_countries() IS DISTINCT FROM ARRAY['GH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open-country list does not come through the one seam';
  END IF;
END $$;

-- H1. Fix round 1 (batch 5 review #9, #4): dating_mode_enabled has no gate
--     row (controller ruling: D2 toggles it in development, and Spec 2
--     decides its gate); the fail-closed Vault reader is server-only.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_mode_enabled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_mode_enabled carries a production gate (ruling: it stays out)';
  END IF;
  IF to_regprocedure('private.vault_setting_strict(text)') IS NULL
     OR has_function_privilege('anon', 'private.vault_setting_strict(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.vault_setting_strict(text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.vault_setting_strict(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: private.vault_setting_strict is missing or reachable by a client';
  END IF;
END $$;

-- H2. P-1 (batch 5 extras; closes mutants 113 and 114): both settings are
--     read through public.app_setting, Vault first. The owner's launch flip
--     is a Vault secret (plan P-1), so Vault 'production' wins over a GUC
--     that says development, and a Vault URL naming another project stops
--     the dev script. A clean slate first, as settings_accessor_test does;
--     every secret here is created and deleted inside this transaction.
DO $$
DECLARE
  v_msg text;
BEGIN
  DELETE FROM vault.decrypted_secrets WHERE name IN ('attune_environment', 'supabase_url');

  PERFORM set_config('app.settings.attune_environment', 'development', true);
  PERFORM vault.create_secret('production', 'attune_environment');
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Vault production setting did not read production (P-1)';
  END IF;
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed with Vault reading production (got %)', coalesce(v_msg, 'no error');
  END IF;
  DELETE FROM vault.decrypted_secrets WHERE name = 'attune_environment';

  PERFORM set_config('app.settings.supabase_url', 'https://mrgjtyacrzfylawyzabm.supabase.co', true);
  PERFORM vault.create_secret('https://abcdefghijklmnopqrst.supabase.co', 'supabase_url');
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed with Vault naming another project (got %)', coalesce(v_msg, 'no error');
  END IF;
  DELETE FROM vault.decrypted_secrets WHERE name = 'supabase_url';

  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', '', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the environment did not return to development after H2';
  END IF;
  PERFORM private.assert_development_project();
END $$;

-- H2b. Final review I-1: mixed sources read production. Development only
--      when every source that is set says exactly 'development', or none is
--      set; either source holding anything else (production, a typo) is
--      production, so a Vault 'development' never hides a GUC 'production'.
--      The dev guard applies the same rule to the project URL: either source
--      naming another project refuses.
DO $$
DECLARE
  v_msg text;
BEGIN
  DELETE FROM vault.decrypted_secrets WHERE name IN ('attune_environment', 'supabase_url');
  PERFORM vault.create_secret('development', 'attune_environment');
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Vault development with the GUC production read % (final review I-1)', private.attune_environment();
  END IF;
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed with the GUC production under a Vault development (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'prodution', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Vault development with a GUC typo did not fail closed to production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'development', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both sources development did not read development';
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Vault development with the GUC unset did not read development';
  END IF;
  DELETE FROM vault.decrypted_secrets WHERE name = 'attune_environment';

  PERFORM vault.create_secret('https://mrgjtyacrzfylawyzabm.supabase.co', 'supabase_url');
  PERFORM set_config('app.settings.supabase_url', 'https://abcdefghijklmnopqrst.supabase.co', true);
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed with the GUC naming another project under a Vault development URL (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.supabase_url', 'https://mrgjtyacrzfylawyzabm.supabase.co', true);
  PERFORM private.assert_development_project();
  DELETE FROM vault.decrypted_secrets WHERE name = 'supabase_url';
  PERFORM set_config('app.settings.supabase_url', '', true);
END $$;

-- H3. Controller ruling (batch 3, carried to Task 9): section H leaves no
--     environment setting behind for the sections after it. Both settings
--     go back to unset (development, no project URL); they were only ever
--     set with set_config inside this transaction.
DO $$
BEGIN
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', '', true);
  IF private.attune_environment() <> 'development' OR public.app_setting('supabase_url') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: section H left an environment setting behind';
  END IF;
END $$;

-- =====================================================================
-- I. Identity health and unfinished sign-ups (W1c; §4.3, §4.6, §4.8).
--    Fixtures 40-42.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.get_identity_health()') IS NULL
     OR to_regprocedure('public.unfinished_signup_candidates()') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1c health objects are missing (get_identity_health, unfinished_signup_candidates)';
  END IF;
END $$;

DO $$
DECLARE
  v_old_unfinished constant uuid := '5f1a0000-0000-0000-0000-000000000040';
  v_new_unfinished constant uuid := '5f1a0000-0000-0000-0000-000000000041';
  v_finished constant uuid := '5f1a0000-0000-0000-0000-000000000042';
  v_before jsonb;
  v_after jsonb;
BEGIN
  IF has_function_privilege('authenticated', 'public.get_identity_health()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_identity_health()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.unfinished_signup_candidates()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_identity_health()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.unfinished_signup_candidates()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health grants are wrong';
  END IF;

  SET LOCAL ROLE service_role;
  v_before := public.get_identity_health();
  RESET ROLE;

  -- updated_at is set with created_at (fix round 1): the local auth stub
  -- defaults it to now(), and the purge reads activity, not age.
  INSERT INTO auth.users (id, phone, created_at, updated_at) VALUES
    (v_old_unfinished, '+15558100040', timestamptz '2001-01-01 00:00+00', timestamptz '2001-01-01 00:00+00'),
    (v_new_unfinished, '+15558100041', now(), now()),
    (v_finished, '+15558100042', now() - interval '30 hours', now() - interval '30 hours');
  INSERT INTO public.users (id, phone, display_name) VALUES (v_finished, '+15558100042', 'Finished W1');
  PERFORM public.place_account_hold(v_finished, 'age_review');

  SET LOCAL ROLE service_role;
  v_after := public.get_identity_health();
  IF NOT EXISTS (SELECT 1 FROM public.unfinished_signup_candidates() AS c WHERE c = v_old_unfinished)
     OR EXISTS (SELECT 1 FROM public.unfinished_signup_candidates() AS c WHERE c IN (v_new_unfinished, v_finished)) THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: unfinished_signup_candidates picked the wrong accounts';
  END IF;
  RESET ROLE;

  IF (v_after ->> 'accounts_without_birth_date')::int <> (v_before ->> 'accounts_without_birth_date')::int + 1
     OR (v_after ->> 'accounts_without_path')::int <> (v_before ->> 'accounts_without_path')::int + 1
     OR (v_after -> 'holds' ->> 'age_review')::int <> (v_before -> 'holds' ->> 'age_review')::int + 1
     OR (v_after ->> 'unfinished_signups_awaiting_purge')::int <> (v_before ->> 'unfinished_signups_awaiting_purge')::int + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health counts did not move: % -> %', v_before, v_after;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'purge-unfinished-signups' AND schedule = '41 * * * *'
                    AND command LIKE '%invoke_edge_function(''purge-unfinished-signups'')%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: purge-unfinished-signups is not scheduled';
  END IF;
END $$;

-- I2. Batch 5 extras (each closes a mutant that section I let through):
--     anon can't list the purge candidates; the list is capped at 500 a run,
--     oldest first; each hold kind is counted on its own, and a resolved
--     hold isn't counted; an account with a birth date and a path adds to
--     neither "without" count. Fixtures 92 and 97, plus 501 throwaway
--     unfinished Auth users 5f1a0000-0000-0000-0002-*, deleted at the end.
DO $$
DECLARE
  v_old_unfinished constant uuid := '5f1a0000-0000-0000-0000-000000000040';
  v_held constant uuid := '5f1a0000-0000-0000-0000-000000000092';
  v_resolved constant uuid := '5f1a0000-0000-0000-0000-000000000097';
  v_before jsonb;
  v_after jsonb;
  v_count int;
  v_first uuid;
  v_newest_in boolean;
BEGIN
  IF has_function_privilege('anon', 'public.unfinished_signup_candidates()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can list the unfinished sign-ups';
  END IF;

  -- 500 a run, oldest first.
  INSERT INTO auth.users (id, created_at, updated_at)
  SELECT ('5f1a0000-0000-0000-0002-' || lpad(n::text, 12, '0'))::uuid,
         timestamptz '2002-01-01 00:00+00' + n * interval '1 minute',
         timestamptz '2002-01-01 00:00+00' + n * interval '1 minute'
    FROM generate_series(1, 501) AS n;
  SET LOCAL ROLE service_role;
  SELECT count(*) INTO v_count FROM public.unfinished_signup_candidates();
  SELECT c INTO v_first FROM public.unfinished_signup_candidates() WITH ORDINALITY AS t(c, i) WHERE i = 1;
  v_newest_in := EXISTS (SELECT 1 FROM public.unfinished_signup_candidates() AS c
                          WHERE c = '5f1a0000-0000-0000-0002-000000000501'::uuid);
  RESET ROLE;
  IF v_count <> 500 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge run listed % accounts, expected the 500 cap', v_count;
  END IF;
  IF v_first IS DISTINCT FROM v_old_unfinished OR v_newest_in THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge list is not oldest first (first %, newest listed %)', v_first, v_newest_in;
  END IF;
  DELETE FROM auth.users WHERE id::text LIKE '5f1a0000-0000-0000-0002-%';

  -- Holds by kind, resolved ones not counted; DOB and path counted per account.
  SET LOCAL ROLE service_role;
  v_before := public.get_identity_health();
  RESET ROLE;
  INSERT INTO auth.users (id, phone) VALUES (v_held, '+15558100092'), (v_resolved, '+15558100097');
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_held, '+15558100092', 'Held W1'), (v_resolved, '+15558100097', 'Resolved W1');
  UPDATE public.users SET path = 'just_me' WHERE id IN (v_held, v_resolved);
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_held, '1990-01-01'), (v_resolved, '1991-01-01');
  PERFORM public.place_account_hold(v_held, 'recovery_hold');
  PERFORM public.place_account_hold(v_held, 'safety_review');
  PERFORM public.place_account_hold(v_resolved, 'age_review');
  PERFORM public.place_account_hold(v_resolved, 'recovery_hold');
  PERFORM public.place_account_hold(v_resolved, 'safety_review');
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_resolved;
  SET LOCAL ROLE service_role;
  v_after := public.get_identity_health();
  RESET ROLE;
  IF (v_after -> 'holds' ->> 'age_review')::int <> (v_before -> 'holds' ->> 'age_review')::int
     OR (v_after -> 'holds' ->> 'recovery_hold')::int <> (v_before -> 'holds' ->> 'recovery_hold')::int + 1
     OR (v_after -> 'holds' ->> 'safety_review')::int <> (v_before -> 'holds' ->> 'safety_review')::int + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: holds were not counted by kind, open only: % -> %', v_before -> 'holds', v_after -> 'holds';
  END IF;
  IF (v_after ->> 'accounts_without_birth_date')::int <> (v_before ->> 'accounts_without_birth_date')::int
     OR (v_after ->> 'accounts_without_path')::int <> (v_before ->> 'accounts_without_path')::int THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with a birth date and a path was counted as without: % -> %', v_before, v_after;
  END IF;
END $$;


-- I3. Fix round 1 (batch 5 review #1, #2): a purge candidate is an Auth user
--     with no users row and no activity for 24 hours, activity being the
--     latest of created_at, last_sign_in_at and updated_at (controller
--     ruling: this narrows spec §4.3's "created more than 24 h ago"). An old
--     Auth user signing in again (a retried code reuses it) is never listed,
--     counted or confirmed by is_unfinished_signup, which the purge re-checks
--     before each delete. Boundaries: idle 23 hours is not listed or
--     counted, idle 25 hours is. Fixtures 93-96 and 98, no phone.
DO $$
DECLARE
  v_signing_in constant uuid := '5f1a0000-0000-0000-0000-000000000093';
  v_idle_23h constant uuid := '5f1a0000-0000-0000-0000-000000000094';
  v_idle_25h constant uuid := '5f1a0000-0000-0000-0000-000000000095';
  v_active_23h constant uuid := '5f1a0000-0000-0000-0000-000000000096';
  v_updated_1h constant uuid := '5f1a0000-0000-0000-0000-000000000098';
  v_finished constant uuid := '5f1a0000-0000-0000-0000-000000000042';
  v_before jsonb;
  v_after jsonb;
  v_listed uuid[];
  v_bad text;
BEGIN
  SET LOCAL ROLE service_role;
  v_before := public.get_identity_health();
  RESET ROLE;

  INSERT INTO auth.users (id, created_at, updated_at, last_sign_in_at) VALUES
    (v_signing_in, now() - interval '30 hours', now() - interval '30 hours', now() - interval '2 minutes'),
    (v_idle_23h, now() - interval '23 hours', now() - interval '23 hours', NULL),
    (v_idle_25h, now() - interval '25 hours', now() - interval '25 hours', NULL),
    (v_active_23h, now() - interval '30 hours', now() - interval '30 hours', now() - interval '23 hours'),
    (v_updated_1h, now() - interval '30 hours', now() - interval '1 hour', NULL);

  SET LOCAL ROLE service_role;
  v_after := public.get_identity_health();
  SELECT array_agg(c ORDER BY c) INTO v_listed FROM public.unfinished_signup_candidates() AS c
   WHERE c IN (v_signing_in, v_idle_23h, v_idle_25h, v_active_23h, v_updated_1h);
  RESET ROLE;

  IF v_signing_in = ANY (coalesce(v_listed, '{}')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Auth user created 30 hours ago and signed in 2 minutes ago was listed for the purge';
  END IF;
  IF v_listed IS DISTINCT FROM ARRAY[v_idle_25h] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge list is not "no activity for 24 hours" (listed %; only the 25-hour fixture belongs)', v_listed;
  END IF;
  IF (v_after ->> 'unfinished_signups_awaiting_purge')::int <> (v_before ->> 'unfinished_signups_awaiting_purge')::int + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the awaiting-purge count is not "no activity for 24 hours" (% -> %, expected +1)',
      v_before ->> 'unfinished_signups_awaiting_purge', v_after ->> 'unfinished_signups_awaiting_purge';
  END IF;

  IF to_regprocedure('public.is_unfinished_signup(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: public.is_unfinished_signup(uuid), the purge re-check, is missing';
  END IF;
  IF has_function_privilege('anon', 'public.is_unfinished_signup(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.is_unfinished_signup(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.is_unfinished_signup(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: is_unfinished_signup grants are wrong';
  END IF;
  SET LOCAL ROLE service_role;
  SELECT string_agg(f.label, ', ') INTO v_bad
    FROM (VALUES ('idle 25h', v_idle_25h, true), ('signing in', v_signing_in, false),
                 ('idle 23h', v_idle_23h, false), ('active 23h ago', v_active_23h, false),
                 ('updated 1h ago', v_updated_1h, false), ('finished', v_finished, false),
                 ('unknown', '5f1a0000-0000-0000-0000-0000000000ff'::uuid, false)) AS f(label, id, expected)
   WHERE public.is_unfinished_signup(f.id) IS DISTINCT FROM f.expected;
  RESET ROLE;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: is_unfinished_signup answered wrongly for: %', v_bad;
  END IF;
END $$;

-- I4. Fix round 1 (batch 5 review #6): the W1c health bodies, the purge
--     predicate and the strict Vault reader name no later wave's table
--     (I-6). W6a re-creates get_identity_health from this live body.
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(x.name, ', ' ORDER BY x.name) INTO v_bad
    FROM (SELECT p.oid::regprocedure::text AS name, p.prosrc AS body
            FROM pg_proc p
           WHERE p.oid IN ('public.get_identity_health()'::regprocedure,
                           'public.unfinished_signup_candidates()'::regprocedure,
                           'public.is_unfinished_signup(uuid)'::regprocedure,
                           'private.vault_setting_strict(text)'::regprocedure)
          UNION ALL
          SELECT 'private.unfinished_signups', pg_get_viewdef('private.unfinished_signups'::regclass)) AS x
   WHERE x.body ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports|country_safety_config)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
  END IF;
END $$;


-- =====================================================================
-- J. Final fix wave (final review M-1; controller ruling, as corrected): a
--    display name loses the characters it never needs (U+200B, U+200E,
--    U+200F, U+202A-U+202E, U+2060-U+2064, U+2066-U+2069, U+FEFF) before
--    any name check and on every write to users.display_name, so a partner
--    never sees a blank or a spoofed name. ZWNJ (U+200C) and ZWJ (U+200D)
--    stay exactly as typed. A name with nothing visible left, once spaces,
--    ZWNJ and ZWJ are set aside, is refused like an empty one. Fixtures
--    5f1a0000-0000-0000-0004-0000000000NN (relationships ...0004-0000000001NN),
--    phones +155581040NN.
-- =====================================================================
DO $$
DECLARE
  v_blank constant uuid := '5f1a0000-0000-0000-0004-000000000001';
  v_all constant uuid := '5f1a0000-0000-0000-0004-000000000002';
  v_override constant uuid := '5f1a0000-0000-0000-0004-000000000003';
  v_legacy constant uuid := '5f1a0000-0000-0000-0004-000000000004';
  v_me_a constant uuid := '5f1a0000-0000-0000-0004-000000000005';
  v_partner_a constant uuid := '5f1a0000-0000-0000-0004-000000000006';
  v_me_b constant uuid := '5f1a0000-0000-0000-0004-000000000007';
  v_partner_b constant uuid := '5f1a0000-0000-0000-0004-000000000008';
  v_isolate constant uuid := '5f1a0000-0000-0000-0004-000000000009';
  v_persian constant uuid := '5f1a0000-0000-0000-0004-000000000010';
  v_family constant uuid := '5f1a0000-0000-0000-0004-000000000011';
  v_zwj constant uuid := '5f1a0000-0000-0000-0004-000000000012';
  v_zwnj constant uuid := '5f1a0000-0000-0000-0004-000000000013';
  -- Every character a name may not consist of: the stripped set plus ZWNJ and ZWJ.
  v_invisible constant text := U&'\200B\200C\200D\200E\200F\202A\202B\202C\202D\202E\2060\2061\2062\2063\2064\2066\2067\2068\2069\FEFF';
  -- 'مهر‌سا' (Mehrsa, with the ZWNJ Persian writes inside it) and
  -- '👨‍👩‍👧 Ama' (a ZWJ family emoji): both kept byte for byte.
  v_persian_name constant text := U&'\0645\0647\0631\200C\0633\0627';
  v_family_name constant text := U&'\+01F468\200D\+01F469\200D\+01F467 Ama';
  v_msg text;
  v_n int;
  v_home jsonb;
  v_bad text;
BEGIN
  PERFORM pg_temp.make_account(v_blank, '+15558104001', NULL);
  PERFORM pg_temp.make_account(v_all, '+15558104002', NULL);
  PERFORM pg_temp.make_account(v_override, '+15558104003', NULL);
  PERFORM pg_temp.make_account(v_isolate, '+15558104009', NULL);
  PERFORM pg_temp.make_account(v_persian, '+15558104010', NULL);
  PERFORM pg_temp.make_account(v_family, '+15558104011', NULL);
  PERFORM pg_temp.make_account(v_zwj, '+15558104012', NULL);
  PERFORM pg_temp.make_account(v_zwnj, '+15558104013', NULL);

  -- 1. U+200B alone is no name: refused like an empty one, nothing written.
  PERFORM pg_temp.as_user(v_blank);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', U&'\200B', DATE '1990-05-01', '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a U+200B-only name was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  SELECT (SELECT count(*) FROM public.users WHERE id = v_blank)
       + (SELECT count(*) FROM public.profiles WHERE id = v_blank)
       + (SELECT count(*) FROM public.account_birthdates WHERE user_id = v_blank) INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused invisible name wrote % row(s)', v_n;
  END IF;

  -- 2. Every invisible character, between spaces, is still no name.
  PERFORM pg_temp.as_user(v_all);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', ' ' || v_invisible || ' ', DATE '1990-05-01', '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name of only invisible and bidi characters was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 2b. ZWJ alone, and ZWNJ between spaces, are no name either (correction).
  PERFORM pg_temp.as_user(v_zwj);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', U&'\200D', DATE '1990-05-01', '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a U+200D-only name was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_zwnj);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', U&'  \200C ', DATE '1990-05-01', '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a U+200C-and-spaces name was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 2c. ZWNJ and ZWJ inside a real name are kept byte for byte (correction).
  PERFORM pg_temp.as_user(v_persian);
  PERFORM public.complete_sign_up(v_persian_name, DATE '1990-05-01', '2');
  PERFORM pg_temp.as_user(v_family);
  PERFORM public.complete_sign_up(v_family_name, DATE '1990-05-01', '2');
  RESET ROLE;
  IF (SELECT convert_to(display_name, 'UTF8') FROM public.users WHERE id = v_persian) IS DISTINCT FROM convert_to(v_persian_name, 'UTF8')
     OR (SELECT convert_to(display_name, 'UTF8') FROM public.profiles WHERE id = v_persian) IS DISTINCT FROM convert_to(v_persian_name, 'UTF8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Persian name lost its ZWNJ (users %, profiles %)',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_persian),
      (SELECT to_jsonb(display_name) FROM public.profiles WHERE id = v_persian);
  END IF;
  IF (SELECT convert_to(display_name, 'UTF8') FROM public.users WHERE id = v_family) IS DISTINCT FROM convert_to(v_family_name, 'UTF8')
     OR (SELECT convert_to(display_name, 'UTF8') FROM public.profiles WHERE id = v_family) IS DISTINCT FROM convert_to(v_family_name, 'UTF8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ZWJ family emoji was split (users %, profiles %)',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_family),
      (SELECT to_jsonb(display_name) FROM public.profiles WHERE id = v_family);
  END IF;

  -- 3. An embedded U+202E (and a trailing U+200F) is dropped from both stores.
  PERFORM pg_temp.as_user(v_override);
  PERFORM public.complete_sign_up('Ama ' || U&'\202E' || 'Mensah' || U&'\200F', DATE '1990-05-01', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_override) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT display_name FROM public.profiles WHERE id = v_override) IS DISTINCT FROM 'Ama Mensah' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an embedded U+202E was stored (users %, profiles %)',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_override),
      (SELECT to_jsonb(display_name) FROM public.profiles WHERE id = v_override);
  END IF;

  -- 3a. An embedded bidi isolate (U+2067) is dropped too (correction).
  PERFORM pg_temp.as_user(v_isolate);
  PERFORM public.complete_sign_up('Kofi' || U&'\2067' || ' Boateng', DATE '1990-05-01', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_isolate) IS DISTINCT FROM 'Kofi Boateng'
     OR (SELECT display_name FROM public.profiles WHERE id = v_isolate) IS DISTINCT FROM 'Kofi Boateng' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an embedded U+2067 was stored (users %, profiles %)',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_isolate),
      (SELECT to_jsonb(display_name) FROM public.profiles WHERE id = v_isolate);
  END IF;

  -- 3b. Every write to users.display_name is cleaned by the users trigger, a
  --     client's direct UPDATE included (correction); a name without any of
  --     those characters is stored exactly as written, and a write to another
  --     column leaves the name alone.
  PERFORM pg_temp.as_user(v_override);
  UPDATE public.users SET display_name = 'A' || U&'\202E' || 'b' WHERE id = v_override;
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_override) IS DISTINCT FROM 'Ab' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client write stored a U+202E: %',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_override);
  END IF;
  PERFORM pg_temp.as_user(v_override);
  UPDATE public.users SET display_name = U&'\200D' WHERE id = v_override;
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_override) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct client write stored a name with nothing visible: %',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_override);
  END IF;
  PERFORM pg_temp.as_user(v_override);
  UPDATE public.users SET display_name = ' Ama  Mensah ' WHERE id = v_override;
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_override) IS DISTINCT FROM ' Ama  Mensah ' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the users trigger changed a name with no control characters: %',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_override);
  END IF;
  PERFORM pg_temp.as_user(v_persian);
  UPDATE public.users SET timezone = 'Asia/Tehran' WHERE id = v_persian;
  UPDATE public.users SET display_name = v_persian_name WHERE id = v_persian;
  RESET ROLE;
  IF (SELECT convert_to(display_name, 'UTF8') FROM public.users WHERE id = v_persian) IS DISTINCT FROM convert_to(v_persian_name, 'UTF8') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a direct write of a Persian name lost its ZWNJ: %',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_persian);
  END IF;

  -- 4. Legacy data from before W1 is written with the trigger off (the
  --    names it would have cleaned are already stored): a name of invisible
  --    characters only still needs a name, and the partner names below keep
  --    their stored characters for the read-side checks.
  ALTER TABLE public.users DISABLE TRIGGER users_display_name_clean;
  PERFORM pg_temp.make_account(v_legacy, '+15558104004', U&'\200B\FEFF');
  INSERT INTO public.profiles (id, display_name) VALUES (v_legacy, U&'\200B');
  PERFORM pg_temp.make_account(v_me_a, '+15558104005', 'Esi');
  PERFORM pg_temp.make_account(v_partner_a, '+15558104006', U&'\202E' || 'Kofi Boateng');
  PERFORM pg_temp.make_account(v_me_b, '+15558104007', 'Yaa');
  PERFORM pg_temp.make_account(v_partner_b, '+15558104008', U&'\200B\200D');
  ALTER TABLE public.users ENABLE TRIGGER users_display_name_clean;
  IF (SELECT display_name FROM public.users WHERE id = v_partner_a) IS DISTINCT FROM U&'\202E' || 'Kofi Boateng' THEN
    RAISE EXCEPTION 'CONTRACT SETUP: the legacy partner name was cleaned on insert';
  END IF;
  PERFORM pg_temp.as_user(v_legacy);
  v_home := public.get_my_home_state();
  RESET ROLE;
  IF NOT (v_home -> 'needs') ? 'name' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invisible-only legacy name did not need a name: %', v_home -> 'needs';
  END IF;

  -- 5. The replay over that legacy name writes the new one (an invisible
  --    name counts as no name), in users and in profiles.
  PERFORM pg_temp.as_user(v_legacy);
  PERFORM public.complete_sign_up('Akosua', DATE '1991-02-03', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_legacy) IS DISTINCT FROM 'Akosua'
     OR (SELECT display_name FROM public.profiles WHERE id = v_legacy) IS DISTINCT FROM 'Akosua' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sign-up kept an invisible-only legacy name (users %, profiles %)',
      (SELECT to_jsonb(display_name) FROM public.users WHERE id = v_legacy),
      (SELECT to_jsonb(display_name) FROM public.profiles WHERE id = v_legacy);
  END IF;

  -- 6. partner_first_name: a legacy partner's U+202E is dropped, and a
  --    partner name with nothing visible (ZWSP + ZWJ) reads as no name.
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, created_at) VALUES
    ('5f1a0000-0000-0000-0004-000000000101', v_me_a, v_partner_a, 'active', current_date, now() - interval '1 day', now() - interval '1 day'),
    ('5f1a0000-0000-0000-0004-000000000102', v_me_b, v_partner_b, 'active', current_date, now() - interval '1 day', now() - interval '1 day');
  PERFORM pg_temp.as_user(v_me_a);
  v_home := public.get_my_home_state();
  RESET ROLE;
  IF v_home -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Kofi' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a partner name kept its U+202E: %', v_home -> 'link' -> 'partner_first_name';
  END IF;
  PERFORM pg_temp.as_user(v_me_b);
  v_home := public.get_my_home_state();
  RESET ROLE;
  IF v_home -> 'link' ->> 'partner_first_name' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invisible-only partner name was shown: %', v_home -> 'link' -> 'partner_first_name';
  END IF;

  -- 7. The normaliser itself: each stripped character goes, one by one;
  --    ZWNJ, ZWJ, letters and a normal space stay.
  SELECT string_agg(to_hex(c), ', ') INTO v_bad
    FROM unnest(ARRAY[x'200B', x'200E', x'200F', x'202A', x'202B', x'202C', x'202D', x'202E',
                      x'2060', x'2061', x'2062', x'2063', x'2064', x'2066', x'2067', x'2068',
                      x'2069', x'FEFF']::int[]) AS c
   WHERE private.normalize_display_name('A' || chr(c) || 'B') IS DISTINCT FROM 'AB';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the name normaliser kept U+%', v_bad;
  END IF;
  IF private.normalize_display_name(U&'  \0190si \200C\200D \0186b\025Bng ') IS DISTINCT FROM U&'\0190si \200C\200D \0186b\025Bng' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the name normaliser changed what it should keep';
  END IF;

  -- 8. The helpers are server-only.
  SELECT string_agg(f || ':' || r, ', ') INTO v_bad
    FROM unnest(ARRAY['private.normalize_display_name(text)', 'private.strip_name_controls(text)',
                      'private.name_is_blank(text)', 'private.users_display_name_clean()']) AS f,
         unnest(ARRAY['anon', 'authenticated']) AS r
   WHERE has_function_privilege(r, f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name helper is reachable by a client: %', v_bad;
  END IF;
END $$;

ROLLBACK;
