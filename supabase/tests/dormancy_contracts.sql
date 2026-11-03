-- supabase/tests/dormancy_contracts.sql
-- Spec 1 W6a and W6b (§3.5, §3.15, §4.3 W6a/W6b, §4.4, §4.5, §4.6, §7.1):
-- holds enforced by the Custom Access Token Hook (sections A-C), the hold
-- kind in the home state, the recycled-number challenge and the fresh
-- start, the purge list, the fail-open alerts and identity health (A2,
-- D-G); W6b adds the date-of-birth correction rules (section H).
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dormancy_contracts.sql
-- Fixture ids 5f6a0000-0000-0000-0000-0000000000NN; phones +15558400NN
-- (§7.1's 84xx range), set on auth.users and public.users. Every refusal
-- is checked by its message.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.fresh_start_key', 'w6a-contract-key-0123456789abcdefghijkl', true);
  PERFORM set_config('app.settings.dating_exclusion_key', 'w6a-contract-dating-key', true);
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f6a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
  RETURN SQLERRM;
END $$;

-- An account [p_n] last active [p_idle] ago (NULL: no activity row).
CREATE FUNCTION pg_temp.person(p_n text, p_idle interval) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558400' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at)
  VALUES (pg_temp.id(p_n), '15558400' || p_n, 'Person ' || p_n, 'just_me', now() - interval '400 days');
  IF p_idle IS NOT NULL THEN
    INSERT INTO public.account_activity (user_id, last_active_at)
    VALUES (pg_temp.id(p_n), now() - p_idle)
    ON CONFLICT (user_id) DO UPDATE SET last_active_at = EXCLUDED.last_active_at;
  ELSE
    DELETE FROM public.account_activity WHERE user_id = pg_temp.id(p_n);
  END IF;
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.event(p_user uuid, p_method text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('user_id', p_user, 'authentication_method', p_method,
                            'claims', jsonb_build_object('sub', p_user, 'role', 'authenticated', 'aal', 'aal1'));
$$;

-- The hook as Supabase Auth calls it (supabase_auth_admin).
CREATE FUNCTION pg_temp.hook(p_event jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE supabase_auth_admin';
  v := public.attune_access_token_hook(p_event);
  RESET ROLE;
  RETURN v;
END $$;

-- The hook's answer, or what it raised (a fail-closed hook is a finding,
-- never an aborted contract).
CREATE FUNCTION pg_temp.hook_safe(p_event jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.hook(p_event);
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN jsonb_build_object('raised', SQLERRM);
END $$;

CREATE FUNCTION pg_temp.failures() RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT count(*) FROM private.auth_hook_failures);
END $$;

CREATE FUNCTION pg_temp.flag(p_key text, p_on boolean) RETURNS void LANGUAGE sql AS $$
  UPDATE public.feature_flags SET enabled = p_on WHERE key = p_key;
$$;

CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    EXECUTE p_sql INTO v;
  EXCEPTION WHEN raise_exception OR insufficient_privilege THEN
    RESET ROLE;
    RETURN 'ERROR: ' || SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

DO $$ BEGIN PERFORM pg_temp.flag('dormancy_rule', true); END $$;


-- =====================================================================
-- A. Objects and grants (spec §4.2, §4.3 W6a; W1 M-6).
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regclass('public.account_activity') IS NULL OR to_regclass('public.fresh_start_challenges') IS NULL
     OR to_regclass('private.auth_hook_failures') IS NULL
     OR to_regprocedure('public.attune_access_token_hook(jsonb)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'parked_phone_hmac') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6a objects are missing';
  END IF;

  -- The hook: Supabase Auth only (spec §4.3 W6a).
  IF NOT has_function_privilege('supabase_auth_admin', 'public.attune_access_token_hook(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.attune_access_token_hook(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.attune_access_token_hook(jsonb)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.attune_access_token_hook(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the access-token hook is executable by someone other than supabase_auth_admin';
  END IF;

  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['private.fresh_start_key(text)', 'private.seal_fresh_start(uuid,timestamp with time zone)',
                      'private.open_fresh_start(text)', 'private.access_token_refusal(jsonb)']) AS f
   WHERE has_function_privilege('authenticated', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE')
      OR has_function_privilege('service_role', f, 'EXECUTE') OR has_function_privilege('supabase_auth_admin', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server-only W6a helper is executable by a role: %', v_bad;
  END IF;

  IF has_table_privilege('authenticated', 'public.account_activity', 'SELECT')
     OR has_table_privilege('anon', 'public.account_activity', 'SELECT')
     OR has_table_privilege('authenticated', 'public.fresh_start_challenges', 'SELECT')
     OR has_table_privilege('anon', 'public.fresh_start_challenges', 'SELECT')
     OR has_table_privilege('authenticated', 'private.auth_hook_failures', 'SELECT')
     OR has_table_privilege('service_role', 'private.auth_hook_failures', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.account_activity', 'DELETE')
     OR NOT has_table_privilege('service_role', 'public.fresh_start_challenges', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6a table grants are wrong';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.account_activity'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.fresh_start_challenges'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: RLS is off on a W6a table';
  END IF;

  -- W1 deferred M-6: no client deletes a users row.
  IF has_table_privilege('authenticated', 'public.users', 'DELETE')
     OR has_table_privilege('anon', 'public.users', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client may DELETE users (M-6)';
  END IF;
END $$;

-- =====================================================================
-- B. The hold kind in the home state (W3 batch 5 carry): age_review first,
--    then safety_review, then recovery_hold; 'hold' unchanged.
-- =====================================================================
DO $$
DECLARE
  v_uid constant uuid := pg_temp.person('01', interval '1 day');
  v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.get_my_home_state();
  RESET ROLE;
  IF (v -> 'hold') IS DISTINCT FROM 'false'::jsonb OR (v -> 'hold_kind') IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no hold reads %', v;
  END IF;

  PERFORM public.place_account_hold(v_uid, 'recovery_hold');
  PERFORM public.place_account_hold(v_uid, 'safety_review');
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.get_my_home_state();
  RESET ROLE;
  IF (v -> 'hold') IS DISTINCT FROM 'true'::jsonb OR v ->> 'hold_kind' IS DISTINCT FROM 'safety_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: safety_review must outrank recovery_hold, got %', v -> 'hold_kind';
  END IF;

  PERFORM public.place_account_hold(v_uid, 'age_review');
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.get_my_home_state();
  RESET ROLE;
  IF v ->> 'hold_kind' IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age hold must read age_review first, got %', v -> 'hold_kind';
  END IF;

  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_uid;
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.get_my_home_state();
  RESET ROLE;
  IF (v -> 'hold') IS DISTINCT FROM 'false'::jsonb OR (v -> 'hold_kind') IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resolved holds still read as %', v;
  END IF;
END $$;

-- =====================================================================
-- C. The hook (spec §4.4, R12, S-8).
-- =====================================================================
DO $$
DECLARE
  v_recent constant uuid := pg_temp.person('10', interval '1 hour');
  v_stale constant uuid := pg_temp.person('11', interval '13 hours');
  v_dormant constant uuid := pg_temp.person('12', interval '200 days');
  v_never constant uuid := pg_temp.person('13', NULL);
  v_age constant uuid := pg_temp.person('14', interval '1 hour');
  v_safety constant uuid := pg_temp.person('15', interval '1 hour');
  v_parked constant uuid := pg_temp.person('16', interval '1 hour');
  v_new constant uuid := pg_temp.id('17');
  v_double constant uuid := pg_temp.person('18', interval '1 hour');
  v_dormant_age constant uuid := pg_temp.person('19', interval '200 days');
  v_dormant_safety constant uuid := pg_temp.person('23', interval '200 days');
  v_dormant_parked constant uuid := pg_temp.person('24', interval '200 days');
  v_dormant_age_new constant uuid := pg_temp.person('27', NULL);
  v_before timestamptz;
  v_failures bigint;
  v_metric bigint;
  v jsonb;
  v_nonce text;
  v_open record;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_new, '1555840017', now());
  PERFORM public.place_account_hold(v_age, 'age_review');
  PERFORM public.place_account_hold(v_safety, 'safety_review');
  PERFORM public.place_account_hold(v_parked, 'recovery_hold');
  -- Preflight F3: safety_review placed before age_review, so neither the
  -- heap order nor a reversed rank can pass for the hook's order.
  PERFORM public.place_account_hold(v_double, 'safety_review');
  PERFORM public.place_account_hold(v_double, 'age_review');
  PERFORM public.place_account_hold(v_dormant_age, 'age_review');
  PERFORM public.place_account_hold(v_dormant_safety, 'safety_review');
  PERFORM public.place_account_hold(v_dormant_parked, 'recovery_hold');
  PERFORM public.place_account_hold(v_dormant_age_new, 'age_review');
  v_failures := pg_temp.failures();

  -- In use: the event comes back unchanged; activity under 12 h is left.
  SELECT last_active_at INTO v_before FROM public.account_activity WHERE user_id = v_recent;
  v := pg_temp.hook(pg_temp.event(v_recent, 'otp'));
  IF v IS DISTINCT FROM pg_temp.event(v_recent, 'otp') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recent account''s sign-in was changed: %', v;
  END IF;
  IF (SELECT last_active_at FROM public.account_activity WHERE user_id = v_recent) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activity under 12 hours old was rewritten';
  END IF;

  -- A refresh after 13 hours moves the activity to now.
  v := pg_temp.hook(pg_temp.event(v_stale, 'token_refresh'));
  IF v IS DISTINCT FROM pg_temp.event(v_stale, 'token_refresh')
     OR (SELECT last_active_at FROM public.account_activity WHERE user_id = v_stale) IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refresh after 13 hours did not record activity';
  END IF;
  -- No activity row at all (before the seed reached it): written.
  v := pg_temp.hook(pg_temp.event(v_never, 'token_refresh'));
  IF NOT EXISTS (SELECT 1 FROM public.account_activity WHERE user_id = v_never AND last_active_at = now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a first token wrote no activity';
  END IF;

  -- A recycled number: a code sign-in to an account unused for 180 days.
  v := pg_temp.hook(pg_temp.event(v_dormant, 'otp'));
  IF v #>> '{error,http_code}' IS DISTINCT FROM '403'
     OR v #>> '{error,message}' !~ '^account_dormant:[0-9a-f]{128}$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant OTP sign-in was not challenged: %', v;
  END IF;
  v_nonce := substring(v #>> '{error,message}' FROM 17);
  SELECT * INTO v_open FROM private.open_fresh_start(v_nonce);
  IF v_open.user_id IS DISTINCT FROM v_dormant OR v_open.issued_at > now() OR v_open.issued_at < now() - interval '1 second' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the nonce does not open to the dormant account now (%, %)', v_open.user_id, v_open.issued_at;
  END IF;
  IF position(replace(v_dormant::text, '-', '') IN v_nonce) > 0 OR position(v_dormant::text IN v_nonce) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the nonce shows the old account''s id';
  END IF;
  IF (SELECT last_active_at FROM public.account_activity WHERE user_id = v_dormant) > now() - interval '199 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused sign-in recorded activity';
  END IF;
  -- The same device's refresh passes (spec §7.1) and is activity.
  v := pg_temp.hook(pg_temp.event(v_dormant, 'token_refresh'));
  IF v IS DISTINCT FROM pg_temp.event(v_dormant, 'token_refresh') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant account''s refresh was refused: %', v;
  END IF;
  UPDATE public.account_activity SET last_active_at = now() - interval '200 days' WHERE user_id = v_dormant;
  -- dormancy_rule off: no challenge (holds still apply).
  PERFORM pg_temp.flag('dormancy_rule', false);
  v := pg_temp.hook(pg_temp.event(v_dormant, 'otp'));
  PERFORM pg_temp.flag('dormancy_rule', true);
  IF v ? 'error' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dormancy_rule off still challenged: %', v;
  END IF;
  UPDATE public.account_activity SET last_active_at = now() - interval '200 days' WHERE user_id = v_dormant;

  -- Every hold kind, every way in.
  IF pg_temp.hook(pg_temp.event(v_age, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review:age"}}'::jsonb
     OR pg_temp.hook(pg_temp.event(v_age, 'token_refresh')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review:age"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age hold was not refused with account_review:age';
  END IF;
  IF pg_temp.hook(pg_temp.event(v_safety, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a safety hold was not refused with account_review';
  END IF;
  IF pg_temp.hook(pg_temp.event(v_parked, 'token_refresh')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recovery hold''s refresh was not refused';
  END IF;
  -- Two holds, one of them age (preflight F3, plan P-5): the age hold
  -- answers, so the sign-in H1 blocks the device for a minor.
  IF pg_temp.hook(pg_temp.event(v_double, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review:age"}}'::jsonb
     OR pg_temp.hook(pg_temp.event(v_double, 'token_refresh')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review:age"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account under a safety and an age hold was not refused with account_review:age';
  END IF;
  -- Held and dormant (spec §4.4 order, review I-1): the hold answers,
  -- never the challenge, so DM1 never offers a fresh start
  -- consume_fresh_start refuses. A code sign-in to a dormant age-held
  -- account reads plain account_review (final review I-1): H1, but no
  -- device block, since the phone may be a recycled number's new owner.
  IF pg_temp.hook(pg_temp.event(v_dormant_age, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb
     OR pg_temp.hook(pg_temp.event(v_dormant_safety, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb
     OR pg_temp.hook(pg_temp.event(v_dormant_parked, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held dormant account was challenged instead of refused';
  END IF;
  -- Final review I-1: the device block is never written for a stranger's
  -- hold. No activity row reads from users.created_at (400 days), and
  -- dormancy_rule off changes nothing (holds are never behind a flag).
  IF pg_temp.hook(pg_temp.event(v_dormant_age_new, 'otp')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant age-held account''s code sign-in kept account_review:age';
  END IF;
  PERFORM pg_temp.flag('dormancy_rule', false);
  v := pg_temp.hook(pg_temp.event(v_dormant_age, 'otp'));
  PERFORM pg_temp.flag('dormancy_rule', true);
  IF v IS DISTINCT FROM '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant age-held account''s code sign-in kept account_review:age';
  END IF;
  -- The same device's refresh, and an age hold in use (v_age, v_double
  -- above), keep :age; the hold itself stays.
  IF pg_temp.hook(pg_temp.event(v_dormant_age, 'token_refresh')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review:age"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant age-held account''s refresh lost account_review:age';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_holds
                  WHERE user_id = v_dormant_age AND kind = 'age_review' AND resolved_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dormant account''s age hold was resolved';
  END IF;
  -- A resolved hold no longer refuses.
  UPDATE public.account_holds SET resolved_at = now() WHERE user_id = v_safety;
  IF pg_temp.hook(pg_temp.event(v_safety, 'otp')) ? 'error' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold still refused';
  END IF;

  -- A brand-new sign-up (no users row yet): passes, records nothing.
  v := pg_temp.hook(pg_temp.event(v_new, 'otp'));
  IF v IS DISTINCT FROM pg_temp.event(v_new, 'otp')
     OR EXISTS (SELECT 1 FROM public.account_activity WHERE user_id = v_new) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new sign-up was changed or recorded';
  END IF;
  IF pg_temp.failures() <> v_failures THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deliberate decision was counted as a fail-open';
  END IF;

  -- Malformed events: unchanged, one failure row each (spec §7.1, S-8).
  v_metric := coalesce((SELECT count FROM public.metric_counters
                         WHERE key = 'auth_hook_fail_open' AND day = (now() AT TIME ZONE 'utc')::date), 0);
  IF pg_temp.hook_safe('{}'::jsonb) IS DISTINCT FROM '{}'::jsonb
     OR pg_temp.hook_safe('{"user_id": "not-a-uuid", "claims": {}}'::jsonb) IS DISTINCT FROM '{"user_id": "not-a-uuid", "claims": {}}'::jsonb
     OR pg_temp.hook_safe('[1, 2]'::jsonb) IS DISTINCT FROM '[1, 2]'::jsonb
     OR pg_temp.hook_safe(jsonb_build_object('user_id', v_recent)) IS DISTINCT FROM jsonb_build_object('user_id', v_recent) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed event did not come back unchanged';
  END IF;
  IF pg_temp.failures() <> v_failures + 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: malformed events wrote % failure rows, not 4', pg_temp.failures() - v_failures;
  END IF;
  IF EXISTS (SELECT 1 FROM private.auth_hook_failures WHERE sqlstate IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failure row has no sqlstate';
  END IF;
  IF coalesce((SELECT count FROM public.metric_counters
                WHERE key = 'auth_hook_fail_open' AND day = (now() AT TIME ZONE 'utc')::date), 0) <> v_metric + 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: auth_hook_fail_open did not count each fail-open';
  END IF;

  -- No key configured: the dormant sign-in fails open, counted (never a lock-out).
  PERFORM set_config('app.settings.fresh_start_key', '', true);
  v := pg_temp.hook_safe(pg_temp.event(v_dormant, 'otp'));
  PERFORM set_config('app.settings.fresh_start_key', 'w6a-contract-key-0123456789abcdefghijkl', true);
  IF v IS DISTINCT FROM pg_temp.event(v_dormant, 'otp') OR pg_temp.failures() <> v_failures + 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missing fresh_start_key must fail open and be counted, got %', v;
  END IF;
  IF (SELECT sqlstate FROM private.auth_hook_failures ORDER BY id DESC LIMIT 1) IS DISTINCT FROM 'P0001' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fail-open row does not carry the error''s sqlstate';
  END IF;
END $$;

-- =====================================================================
-- C2. A slow database (spec §4.4, R12; review I-2, M-1): a statement
--     timeout inside the hook fails open and is counted with 57014; a
--     timeout while recording a failure still fails open.
-- =====================================================================
CREATE FUNCTION pg_temp.slow() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(2);
  RETURN NEW;
END $$;

-- The hook, or 'timeout' when a cancel escaped it (failed closed).
CREATE FUNCTION pg_temp.hook_timeout(p_event jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_temp.hook(p_event);
EXCEPTION WHEN query_canceled THEN
  RESET ROLE;
  RETURN '{"raised": "timeout"}'::jsonb;
END $$;

DO $$
BEGIN
  -- Idle 13 hours, so the hook's activity upsert runs (and hits the trigger).
  PERFORM set_config('w6a.slow_user', pg_temp.person('25', interval '13 hours')::text, true);
  PERFORM set_config('w6a.failures_before', pg_temp.failures()::text, true);
END $$;

-- (1) The timeout lands in the decision (the activity upsert).
CREATE TRIGGER w6a_slow BEFORE UPDATE ON public.account_activity
  FOR EACH ROW EXECUTE FUNCTION pg_temp.slow();
SET LOCAL statement_timeout = '500ms';
DO $$
BEGIN
  PERFORM set_config('w6a.timeout_result',
    pg_temp.hook_timeout(pg_temp.event(current_setting('w6a.slow_user')::uuid, 'token_refresh'))::text, true);
END $$;
SET LOCAL statement_timeout = 0;
DROP TRIGGER w6a_slow ON public.account_activity;

-- (2) The timeout lands while the failure is recorded (a malformed event
-- fails first, then the failure row's insert is slow).
CREATE TRIGGER w6a_slow BEFORE INSERT ON private.auth_hook_failures
  FOR EACH ROW EXECUTE FUNCTION pg_temp.slow();
SET LOCAL statement_timeout = '500ms';
DO $$
BEGIN
  PERFORM set_config('w6a.record_timeout_result', pg_temp.hook_timeout('{}'::jsonb)::text, true);
END $$;
SET LOCAL statement_timeout = 0;
DROP TRIGGER w6a_slow ON private.auth_hook_failures;

DO $$
DECLARE
  v_uid constant uuid := current_setting('w6a.slow_user')::uuid;
  v_before constant bigint := current_setting('w6a.failures_before')::bigint;
BEGIN
  IF current_setting('w6a.timeout_result')::jsonb IS DISTINCT FROM pg_temp.event(v_uid, 'token_refresh') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a statement timeout failed closed: %', current_setting('w6a.timeout_result');
  END IF;
  IF pg_temp.failures() <> v_before + 1
     OR (SELECT sqlstate FROM private.auth_hook_failures ORDER BY id DESC LIMIT 1) IS DISTINCT FROM '57014' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a statement timeout was not recorded once with 57014 (% new rows)', pg_temp.failures() - v_before;
  END IF;
  IF current_setting('w6a.record_timeout_result')::jsonb IS DISTINCT FROM '{}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timeout while recording a failure failed the hook closed: %', current_setting('w6a.record_timeout_result');
  END IF;
END $$;

-- =====================================================================
-- A2. The fresh start's objects, grants and crons (spec §4.3 W6a, §4.6).
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regclass('private.fresh_start_attempts') IS NULL
     OR to_regprocedure('public.consume_fresh_start(text,text)') IS NULL
     OR to_regprocedure('public.mark_fresh_start_parked(uuid)') IS NULL
     OR to_regprocedure('public.recovery_hold_candidates()') IS NULL
     OR to_regprocedure('public.is_recovery_hold_due(uuid)') IS NULL
     OR to_regprocedure('public.identity_alerts_due()') IS NULL
     OR to_regprocedure('public.mark_identity_alerts_sent(bigint[])') IS NULL
     OR to_regprocedure('private.identity_health_w6a()') IS NULL
     OR to_regprocedure('private.fresh_start_retention()') IS NULL
     OR to_regclass('private.fresh_start_park_alerts') IS NULL
     OR to_regprocedure('private.fresh_starts_unparked()') IS NULL
     OR to_regprocedure('public.fresh_start_park_alerts_due()') IS NULL
     OR to_regprocedure('public.mark_fresh_start_park_alerts_sent(uuid[])') IS NULL
     OR to_regclass('private.parked_review_alerts') IS NULL
     OR to_regprocedure('private.parked_kept_for_review()') IS NULL
     OR to_regprocedure('public.parked_kept_for_review_alerts_due()') IS NULL
     OR to_regprocedure('public.mark_parked_kept_for_review_alerts_sent(uuid[])') IS NULL
     OR to_regclass('private.recovery_purge_stuck_alerts') IS NULL
     OR to_regprocedure('private.recovery_purge_stuck()') IS NULL
     OR to_regprocedure('public.recovery_purge_stuck_alerts_due()') IS NULL
     OR to_regprocedure('public.mark_recovery_purge_stuck_alerts_sent(uuid[])') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'account_deletion_requests'
                       AND column_name = 'source' AND is_nullable = 'YES') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6a fresh-start objects are missing';
  END IF;

  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['private.identity_health_w6a()', 'private.fresh_start_retention()',
                      'private.fresh_starts_unparked()', 'private.parked_kept_for_review()',
                      'private.recovery_purge_stuck()']) AS f
   WHERE has_function_privilege('authenticated', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE')
      OR has_function_privilege('service_role', f, 'EXECUTE') OR has_function_privilege('supabase_auth_admin', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server-only W6a helper is executable by a role: %', v_bad;
  END IF;

  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['public.consume_fresh_start(text,text)', 'public.mark_fresh_start_parked(uuid)',
                      'public.recovery_hold_candidates()', 'public.is_recovery_hold_due(uuid)',
                      'public.identity_alerts_due()', 'public.mark_identity_alerts_sent(bigint[])',
                      'public.fresh_start_park_alerts_due()', 'public.mark_fresh_start_park_alerts_sent(uuid[])',
                      'public.parked_kept_for_review_alerts_due()',
                      'public.mark_parked_kept_for_review_alerts_sent(uuid[])',
                      'public.recovery_purge_stuck_alerts_due()',
                      'public.mark_recovery_purge_stuck_alerts_sent(uuid[])',
                      'public.get_identity_health()']) AS f
   WHERE has_function_privilege('authenticated', f, 'EXECUTE') OR has_function_privilege('anon', f, 'EXECUTE')
      OR NOT has_function_privilege('service_role', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W6a service function has the wrong grants: %', v_bad;
  END IF;

  IF has_table_privilege('authenticated', 'private.fresh_start_attempts', 'SELECT')
     OR has_table_privilege('service_role', 'private.fresh_start_attempts', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh_start_attempts is readable outside the server';
  END IF;
  IF has_table_privilege('authenticated', 'private.fresh_start_park_alerts', 'SELECT')
     OR has_table_privilege('anon', 'private.fresh_start_park_alerts', 'SELECT')
     OR has_table_privilege('service_role', 'private.fresh_start_park_alerts', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh_start_park_alerts is readable outside the server';
  END IF;
  IF has_table_privilege('authenticated', 'private.parked_review_alerts', 'SELECT')
     OR has_table_privilege('anon', 'private.parked_review_alerts', 'SELECT')
     OR has_table_privilege('service_role', 'private.parked_review_alerts', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_review_alerts is readable outside the server';
  END IF;
  IF has_table_privilege('authenticated', 'private.recovery_purge_stuck_alerts', 'SELECT')
     OR has_table_privilege('anon', 'private.recovery_purge_stuck_alerts', 'SELECT')
     OR has_table_privilege('service_role', 'private.recovery_purge_stuck_alerts', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recovery_purge_stuck_alerts is readable outside the server';
  END IF;

  SELECT string_agg(j, ', ') INTO v_bad
    FROM (VALUES ('fresh-start-retention', '43 * * * *'), ('purge-recovery-holds', '55 3 * * *'),
                 ('identity-health-alert', '*/15 * * * *')) AS w(j, s)
   WHERE NOT EXISTS (SELECT 1 FROM cron.job AS c WHERE c.jobname = w.j AND c.schedule = w.s);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W6a cron is missing or mis-scheduled: %', v_bad;
  END IF;
END $$;

-- =====================================================================
-- D. The fresh start (spec §3.5, §4.3 W6a, §4.5; I-11; plan P-10).
-- =====================================================================
DO $$
DECLARE
  v_old constant uuid := pg_temp.person('20', interval '200 days');
  v_back constant uuid := pg_temp.person('21', interval '200 days');
  v_held constant uuid := pg_temp.person('22', interval '200 days');
  v_nonce text;
  v_got text;
  v_ip constant text := encode(extensions.digest('ip:203.0.113.9', 'sha256'), 'hex');
  v_t text;
  v_rel timestamptz;
  v_new constant uuid := pg_temp.id('26');
  i int;
BEGIN
  v_nonce := substring(pg_temp.hook(pg_temp.event(v_old, 'otp')) #>> '{error,message}' FROM 17);

  -- Not before the number moves: mark refuses.
  v_got := pg_temp.as_service(format('SELECT public.mark_fresh_start_parked(%L)::text', v_old));
  IF v_got IS DISTINCT FROM 'ERROR: fresh_start:not_parked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_fresh_start_parked before any hold or park: %', v_got;
  END IF;

  v_got := pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce));
  IF v_got IS DISTINCT FROM v_old::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh nonce was not taken: %', v_got;
  END IF;
  -- I-11: the REAL number's HMAC, in Spec 2's form, before the park.
  IF (SELECT parked_phone_hmac FROM public.users WHERE id = v_old)
       IS DISTINCT FROM public.dating_phone_hmac('+1555840020') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_phone_hmac is not dating_phone_hmac(''+'' || digits) of the real number';
  END IF;
  IF (SELECT phone FROM auth.users WHERE id = v_old) IS DISTINCT FROM '1555840020' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: consume_fresh_start changed the number itself';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_old AND kind = 'recovery_hold'
                   AND resolved_at IS NULL AND reason_ref = 'fresh_start'
                   AND expires_at BETWEEN now() + interval '179 days' AND now() + interval '181 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no 180-day recovery hold after a fresh start';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fresh_start_challenges
                  WHERE user_id = v_old AND used_at IS NOT NULL
                    AND nonce_hash = encode(extensions.digest(v_nonce, 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the taken challenge was not recorded as used';
  END IF;
  -- The park can be retried with the same nonce while it isn't finished.
  IF pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce)) IS DISTINCT FROM v_old::text THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unfinished park could not be retried';
  END IF;
  -- The parked account's old sessions stop at their next refresh.
  IF pg_temp.hook(pg_temp.event(v_old, 'token_refresh')) IS DISTINCT FROM
       '{"error": {"http_code": 403, "message": "account_review"}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account''s refresh was not refused';
  END IF;

  -- Auth moves the number to +999; the mirror follows; then mark.
  UPDATE auth.users SET phone = '999123456789012' WHERE id = v_old;
  IF (SELECT phone FROM public.users WHERE id = v_old) IS DISTINCT FROM '999123456789012' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked number was not mirrored to public.users';
  END IF;
  -- Batch 2 review I-1: the number moved but the mark failed; the client
  -- retries (Task 3: "already on +999, only mark"). The retry takes the same
  -- account and keeps the REAL number's HMAC, never the +999 one.
  -- (Two statements: one IF expression is one query, whose snapshot would
  -- not see what the consume inside it wrote.)
  v_got := pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce));
  IF v_got IS DISTINCT FROM v_old::text
     OR (SELECT parked_phone_hmac FROM public.users WHERE id = v_old)
          IS DISTINCT FROM public.dating_phone_hmac('+1555840020') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retry after the number moved lost the real number''s HMAC: %', v_got;
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.mark_fresh_start_parked(%L)::text', v_old));
  -- (A void comes back as '' through ::text.)
  IF v_got IS DISTINCT FROM '' OR (SELECT phone_released_at FROM public.users WHERE id = v_old) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: mark_fresh_start_parked did not set phone_released_at: %', v_got;
  END IF;
  -- Review M-3: marking again is a no-op (the edge function may retry it).
  v_rel := (SELECT phone_released_at FROM public.users WHERE id = v_old);
  v_got := pg_temp.as_service(format('SELECT public.mark_fresh_start_parked(%L)::text', v_old));
  IF v_got IS DISTINCT FROM '' OR (SELECT phone_released_at FROM public.users WHERE id = v_old) IS DISTINCT FROM v_rel THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second mark_fresh_start_parked was not a no-op: %', v_got;
  END IF;
  -- Single use: after the park, the nonce takes nothing.
  IF pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a used nonce was taken again after the park';
  END IF;
  IF (SELECT parked_phone_hmac FROM public.users WHERE id = v_old)
       IS DISTINCT FROM public.dating_phone_hmac('+1555840020') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_phone_hmac moved off the real number';
  END IF;

  -- O3: the number's next owner is a new account; nothing of the parked
  -- account (its hold, its HMAC) follows the number to them.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (v_new, '1555840020', now(), now());
  INSERT INTO public.users (id, phone, display_name, path, created_at)
  VALUES (v_new, '1555840020', 'Person 26', 'just_me', now());
  IF pg_temp.hook(pg_temp.event(v_new, 'otp')) IS DISTINCT FROM pg_temp.event(v_new, 'otp')
     OR (SELECT parked_phone_hmac FROM public.users WHERE id = v_new) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked account''s restrictions followed the recycled number (O3)';
  END IF;

  -- 15-minute expiry, a future issue time, tampering, rubbish. The tamper
  -- seals once and flips the tag's last hex character (preflight F2: two
  -- seals have different IVs, so a character read from one is not the
  -- other's).
  v_t := private.seal_fresh_start(v_back, now());
  IF pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text',
                               private.seal_fresh_start(v_back, now() - interval '16 minutes'))) IS NOT NULL
     OR pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text',
                                  private.seal_fresh_start(v_back, now() + interval '5 minutes'))) IS NOT NULL
     OR pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text',
                                  overlay(v_t placing CASE WHEN right(v_t, 1) = '0' THEN '1' ELSE '0' END
                                          FROM 128 FOR 1))) IS NOT NULL
     OR pg_temp.as_service('SELECT public.consume_fresh_start(''deadbeef'')::text') IS NOT NULL
     OR pg_temp.as_service('SELECT public.consume_fresh_start(NULL)::text') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired, future, tampered or malformed nonce was taken';
  END IF;
  -- Its owner came back since the challenge: no fresh start.
  v_nonce := private.seal_fresh_start(v_back, now() - interval '1 minute');
  UPDATE public.account_activity SET last_active_at = now() WHERE user_id = v_back;
  IF pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce)) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_back) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account in use again was parked';
  END IF;
  -- Held for anything: no fresh start.
  PERFORM public.place_account_hold(v_held, 'safety_review');
  IF pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text',
                               private.seal_fresh_start(v_held, now()))) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_held AND kind = 'recovery_hold') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account was parked';
  END IF;

  -- Per IP, 5 an hour; an invalid try still counts (P-10).
  FOR i IN 1..5 LOOP
    IF pg_temp.as_service(format('SELECT public.consume_fresh_start(''deadbeef'', %L)::text', v_ip)) IS NOT NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: rubbish was taken';
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM private.fresh_start_attempts WHERE ip_hash = v_ip) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invalid tries were not counted against the IP';
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.consume_fresh_start(%L, %L)::text',
                                     private.seal_fresh_start(v_held, now()), v_ip));
  IF v_got IS DISTINCT FROM 'ERROR: fresh_start:try_later' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 6th try in an hour from one IP was not refused: %', v_got;
  END IF;
END $$;

-- =====================================================================
-- E. The purge list (spec §4.3 W6a, §4.5 purge-recovery-holds).
-- =====================================================================
DO $$
DECLARE
  v_due constant uuid := pg_temp.person('30', interval '400 days');
  v_waiting constant uuid := pg_temp.person('31', interval '400 days');
  v_resolved constant uuid := pg_temp.person('32', interval '400 days');
  -- Review M-4 (ruling): an open safety or age review is never destroyed by
  -- the expiry purge; a review already resolved doesn't stop it.
  v_safety constant uuid := pg_temp.person('37', interval '400 days');
  v_age constant uuid := pg_temp.person('38', interval '400 days');
  v_reviewed constant uuid := pg_temp.person('39', interval '400 days');
  v_ids uuid[];
BEGIN
  PERFORM public.place_account_hold(v_safety, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_safety, 'safety_review');
  PERFORM public.place_account_hold(v_age, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_age, 'age_review');
  PERFORM public.place_account_hold(v_reviewed, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_reviewed, 'safety_review');
  UPDATE public.account_holds SET resolved_at = now() WHERE user_id = v_reviewed AND kind = 'safety_review';
  UPDATE public.account_holds SET expires_at = now() - interval '1 day'
   WHERE user_id IN (v_safety, v_age, v_reviewed) AND kind = 'recovery_hold';
  PERFORM public.place_account_hold(v_due, 'recovery_hold');
  PERFORM public.place_account_hold(v_waiting, 'recovery_hold');
  PERFORM public.place_account_hold(v_resolved, 'recovery_hold');
  UPDATE public.account_holds SET expires_at = now() - interval '1 day' WHERE user_id IN (v_due, v_resolved);
  UPDATE public.account_holds SET resolved_at = now() WHERE user_id = v_resolved;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c) INTO v_ids FROM public.recovery_hold_candidates() AS c;
  RESET ROLE;
  IF NOT (v_due = ANY (v_ids)) OR v_waiting = ANY (v_ids) OR v_resolved = ANY (v_ids) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recovery_hold_candidates listed the wrong accounts';
  END IF;
  IF NOT public.is_recovery_hold_due(v_due) OR public.is_recovery_hold_due(v_waiting)
     OR public.is_recovery_hold_due(v_resolved) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: is_recovery_hold_due answered wrongly';
  END IF;
  IF v_safety = ANY (v_ids) OR v_age = ANY (v_ids) OR NOT (v_reviewed = ANY (v_ids))
     OR public.is_recovery_hold_due(v_safety) OR public.is_recovery_hold_due(v_age)
     OR NOT public.is_recovery_hold_due(v_reviewed) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account under an open safety or age review is due for the recovery purge';
  END IF;
END $$;

-- =====================================================================
-- E2. Parked accounts kept past 180 days for an open review (batch 2
--     review M-4 ruling; batch 3): support must see them. Counted in
--     identity health and alerted once per hold; section E's fixtures.
-- =====================================================================
DO $$
DECLARE
  -- Still inside its 180 days, under a review: not overdue, not counted.
  v_early constant uuid := pg_temp.person('41', interval '400 days');
  v_kept uuid[];
  v jsonb;
  v_ids uuid[];
BEGIN
  PERFORM public.place_account_hold(v_early, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_early, 'safety_review');
  SELECT array_agg(k.user_id) INTO v_kept FROM private.parked_kept_for_review() AS k;
  IF v_kept IS NULL OR NOT (pg_temp.id('37') = ANY (v_kept)) OR NOT (pg_temp.id('38') = ANY (v_kept))
     OR pg_temp.id('39') = ANY (v_kept) OR pg_temp.id('30') = ANY (v_kept) OR v_early = ANY (v_kept)
     OR pg_temp.id('31') = ANY (v_kept) OR pg_temp.id('32') = ANY (v_kept) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_kept_for_review did not list exactly the accounts kept for a review: %', v_kept;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'parked_kept_for_review')::int IS DISTINCT FROM cardinality(v_kept) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health does not count the parked accounts kept for a review: %', v;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.parked_kept_for_review_alerts_due();
  RESET ROLE;
  SELECT array_agg(x::uuid) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  IF v_ids IS NULL OR NOT (pg_temp.id('37') = ANY (v_ids)) OR NOT (pg_temp.id('38') = ANY (v_ids))
     OR pg_temp.id('39') = ANY (v_ids) OR pg_temp.id('30') = ANY (v_ids)
     OR (v ->> 'count')::int <> cardinality(v_ids) OR v ->> 'first_at' IS NULL OR v ->> 'last_at' IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_kept_for_review_alerts_due listed the wrong accounts: %', v;
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a kept-for-review alert carries more than counts, ids and times';
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_parked_kept_for_review_alerts_sent(v_ids);
  PERFORM public.mark_parked_kept_for_review_alerts_sent(v_ids);  -- twice is a no-op
  v := public.parked_kept_for_review_alerts_due();
  RESET ROLE;
  IF (SELECT count(*) FROM private.parked_review_alerts WHERE user_id = pg_temp.id('37')) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second kept-for-review mark did not leave exactly one mark';
  END IF;
  IF (v ->> 'count')::int <> 0 OR (v -> 'ids') <> '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account kept for a review was alerted again after it was sent: %', v;
  END IF;
  -- Still kept: the health count stays until support resolves the review.
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'parked_kept_for_review')::int IS DISTINCT FROM cardinality(v_kept) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an alerted kept-for-review account dropped out of identity health: %', v;
  END IF;
END $$;

-- =====================================================================
-- E3. The purge's audit rows and a purge that keeps failing (batch 3 fix
--     round 1, M-2 and M-3): a purge row is marked source
--     'recovery_purge' (a person's own deletion leaves it NULL); an
--     account whose purge failed in 3 runs since its hold was placed goes
--     to the back of the list, so it can't block the rest, and is counted
--     in identity health and alerted once.
-- =====================================================================
DO $$
DECLARE
  v_stuck constant uuid := pg_temp.person('42', interval '400 days');
  v_twice constant uuid := pg_temp.person('43', interval '400 days');
  v_own constant uuid := pg_temp.person('44', interval '400 days');
  v_old constant uuid := pg_temp.person('45', interval '400 days');
  v_ids uuid[];
  v_list uuid[];
  v jsonb;
  v_n int;
BEGIN
  -- M-2: the column takes 'recovery_purge' or NULL, nothing else.
  BEGIN
    INSERT INTO public.account_deletion_requests (user_ref, source) VALUES (v_stuck, 'someone');
    RAISE EXCEPTION 'CONTRACT VIOLATED: account_deletion_requests.source takes any value';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  IF pg_temp.as_service($q$INSERT INTO public.account_deletion_requests (user_ref) VALUES ('5f6a0000-0000-0000-0000-000000000044') RETURNING coalesce(source, 'null')$q$)
       IS DISTINCT FROM 'null' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person''s own deletion row is not NULL-sourced';
  END IF;

  PERFORM public.place_account_hold(x, 'recovery_hold', 'fresh_start') FROM unnest(ARRAY[v_stuck, v_twice, v_own, v_old]) AS x;
  UPDATE public.account_holds SET created_at = now() - interval '200 days', expires_at = now() - interval '20 days'
   WHERE user_id IN (v_stuck, v_twice, v_own, v_old) AND kind = 'recovery_hold';
  UPDATE public.users SET phone_released_at = now() - interval '200 days' WHERE id IN (v_stuck, v_twice, v_own, v_old);
  -- Three failed purge runs since the hold; two; three of the person's own
  -- (not the purge's); three from before this hold was placed.
  INSERT INTO public.account_deletion_requests (user_ref, source, requested_at, failure_reason)
  SELECT u, s, now() - d * interval '1 day', 'recovery_purge:delete'
    FROM (VALUES (v_stuck, 'recovery_purge'), (v_twice, 'recovery_purge'), (v_own, NULL), (v_old, 'recovery_purge')) AS f(u, s),
         generate_series(1, 3) AS d
   WHERE NOT (u = v_twice AND d = 3);
  UPDATE public.account_deletion_requests SET requested_at = now() - interval '300 days' WHERE user_ref = v_old;

  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c) INTO v_list FROM public.recovery_hold_candidates() AS c;
  RESET ROLE;
  IF NOT (v_stuck = ANY (v_list)) OR NOT public.is_recovery_hold_due(v_stuck) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge that keeps failing was dropped from the list, not moved back';
  END IF;
  IF array_position(v_list, v_stuck) < greatest(array_position(v_list, v_twice), array_position(v_list, v_own),
                                                array_position(v_list, v_old), array_position(v_list, pg_temp.id('30'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge that failed in 3 runs still blocks the head of the list: %', v_list;
  END IF;

  SELECT array_agg(k.user_id) INTO v_ids FROM private.recovery_purge_stuck() AS k;
  IF v_ids IS NULL OR NOT (v_stuck = ANY (v_ids)) OR v_twice = ANY (v_ids) OR v_own = ANY (v_ids)
     OR v_old = ANY (v_ids) OR pg_temp.id('37') = ANY (v_ids) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recovery_purge_stuck did not list exactly the purge that failed in 3 runs: %', v_ids;
  END IF;
  v_n := cardinality(v_ids);
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'recovery_purge_stuck')::int IS DISTINCT FROM v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health does not count the stuck purges: %', v;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.recovery_purge_stuck_alerts_due();
  RESET ROLE;
  SELECT array_agg(x::uuid) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  IF v_ids IS NULL OR NOT (v_stuck = ANY (v_ids)) OR v_twice = ANY (v_ids)
     OR (v ->> 'count')::int <> cardinality(v_ids) OR v ->> 'first_at' IS NULL OR v ->> 'last_at' IS NULL
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recovery_purge_stuck_alerts_due listed the wrong accounts: %', v;
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_recovery_purge_stuck_alerts_sent(v_ids);
  PERFORM public.mark_recovery_purge_stuck_alerts_sent(v_ids);  -- twice is a no-op
  v := public.recovery_purge_stuck_alerts_due();
  RESET ROLE;
  IF (SELECT count(*) FROM private.recovery_purge_stuck_alerts WHERE user_id = v_stuck) <> 1
     OR (v ->> 'count')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stuck purge was alerted again after it was sent: %', v;
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'recovery_purge_stuck')::int IS DISTINCT FROM v_n THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an alerted stuck purge dropped out of identity health: %', v;
  END IF;
END $$;

-- =====================================================================
-- F. Alerts and identity health (S-8; spec §4.3 W6a; plan P-11).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_ids bigint[];
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.identity_alerts_due();
  RESET ROLE;
  SELECT array_agg(x::bigint) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  IF (v ->> 'count')::int < 5 OR (v ->> 'count')::int <> cardinality(v_ids)
     OR v ->> 'first_at' IS NULL OR v ->> 'last_at' IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity_alerts_due did not list the fail-opens: %', v;
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an alert carries more than counts, ids and times';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_identity_alerts_sent(v_ids);
  PERFORM public.mark_identity_alerts_sent(v_ids);  -- review M-3: twice is a no-op
  v := public.identity_alerts_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 0 OR (v -> 'ids') <> '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: sent alerts are due again: %', v;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF NOT (v ?& ARRAY['accounts_without_birth_date', 'accounts_without_path', 'holds',
                     'unfinished_signups_awaiting_purge', 'fresh_starts_7d', 'parked_accounts',
                     'parked_without_hmac', 'hook_fail_opens_24h', 'hook_fail_opens_unalerted',
                     'fresh_start_key_present', 'fresh_starts_unparked', 'parked_kept_for_review',
                     'recovery_purge_stuck']) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health lost a W1 count or lacks a W6a one: %', v;
  END IF;
  IF (v ->> 'fresh_starts_7d')::int < 1 OR (v ->> 'parked_accounts')::int < 1
     OR (v ->> 'hook_fail_opens_24h')::int < 5 OR (v ->> 'hook_fail_opens_unalerted')::int <> 0
     OR (v -> 'fresh_start_key_present') IS DISTINCT FROM 'true'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health W6a counts are wrong: %', v;
  END IF;
  -- Batch 1 M-2: a key the sealer refuses (under 32 characters) is not
  -- present.
  PERFORM set_config('app.settings.fresh_start_key', repeat('k', 31), true);
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  PERFORM set_config('app.settings.fresh_start_key', 'w6a-contract-key-0123456789abcdefghijkl', true);
  IF (v -> 'fresh_start_key_present') IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh_start_key under 32 characters reads as present: %', v;
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_identity_health()'::regprocedure)
       ~* '(account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_identity_health names a W6 table itself (keep them in private.identity_health_w6a)';
  END IF;
END $$;

-- =====================================================================
-- F2. A fresh start whose park never finished (preflight F4): the old
-- account keeps the real number behind its recovery hold, so the number's
-- new owner sees H1. Counted in identity health and alerted once.
-- =====================================================================
DO $$
DECLARE
  v_stuck constant uuid := pg_temp.person('33', interval '200 days');
  v_recent constant uuid := pg_temp.person('34', interval '200 days');
  v_done constant uuid := pg_temp.person('35', interval '200 days');
  -- Review M-2: a recovery hold support placed (no fresh start, no number
  -- to move) is not a stuck park.
  v_support constant uuid := pg_temp.person('36', interval '200 days');
  v jsonb;
  v_ids uuid[];
  v_before int;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v_before := (public.get_identity_health() ->> 'fresh_starts_unparked')::int;
  RESET ROLE;
  PERFORM public.place_account_hold(v_stuck, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_recent, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_done, 'recovery_hold', 'fresh_start');
  PERFORM public.place_account_hold(v_support, 'recovery_hold', 'support');
  UPDATE public.account_holds SET created_at = now() - interval '20 minutes'
   WHERE user_id IN (v_stuck, v_done, v_support) AND kind = 'recovery_hold';
  UPDATE public.account_holds SET created_at = now() - interval '5 minutes'
   WHERE user_id = v_recent AND kind = 'recovery_hold';
  UPDATE public.users SET phone_released_at = now() WHERE id = v_done;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'fresh_starts_unparked')::int <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh_starts_unparked did not count exactly the stuck park: %', v;
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.fresh_start_park_alerts_due();
  RESET ROLE;
  SELECT array_agg(x::uuid) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  IF v_ids IS NULL OR NOT (v_stuck = ANY (v_ids)) OR v_recent = ANY (v_ids) OR v_done = ANY (v_ids)
     OR v_support = ANY (v_ids)
     OR (v ->> 'count')::int <> cardinality(v_ids) OR v ->> 'first_at' IS NULL OR v ->> 'last_at' IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh_start_park_alerts_due listed the wrong parks: %', v;
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a park alert carries more than counts, ids and times';
  END IF;

  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_fresh_start_park_alerts_sent(v_ids);
  PERFORM public.mark_fresh_start_park_alerts_sent(v_ids);  -- review M-3: twice is a no-op
  v := public.fresh_start_park_alerts_due();
  RESET ROLE;
  IF (SELECT count(*) FROM private.fresh_start_park_alerts WHERE user_id = v_stuck) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second park-alert mark did not leave exactly one mark';
  END IF;
  IF (v ->> 'count')::int <> 0 OR (v -> 'ids') <> '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stuck park was alerted again after it was sent: %', v;
  END IF;
  -- Still stuck: the health count keeps it until support finishes the park.
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF (v ->> 'fresh_starts_unparked')::int <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an alerted stuck park dropped out of identity health: %', v;
  END IF;
END $$;

-- =====================================================================
-- G. Retention (spec §4.6, §4.8).
-- =====================================================================
DO $$
DECLARE
  v_uid constant uuid := pg_temp.person('40', interval '1 day');
BEGIN
  INSERT INTO public.fresh_start_challenges (nonce_hash, user_id, created_at, used_at)
  VALUES (repeat('a', 64), v_uid, now() - interval '61 minutes', now() - interval '60 minutes'),
         (repeat('b', 64), v_uid, now() - interval '59 minutes', now() - interval '58 minutes');
  INSERT INTO private.auth_hook_failures (at, sqlstate)
  VALUES (now() - interval '31 days', 'XX000'), (now() - interval '29 days', 'XX000');
  INSERT INTO private.fresh_start_attempts (ip_hash, created_at)
  VALUES (repeat('c', 64), now() - interval '61 minutes'), (repeat('d', 64), now() - interval '59 minutes');
  INSERT INTO private.fresh_start_park_alerts (user_id, hold_created_at, alerted_at)
  VALUES (v_uid, now() - interval '400 days', now() - interval '182 days'),
         (v_uid, now() - interval '200 days', now() - interval '180 days');
  INSERT INTO private.parked_review_alerts (user_id, hold_expires_at, alerted_at)
  VALUES (v_uid, now() - interval '400 days', now() - interval '182 days'),
         (v_uid, now() - interval '200 days', now() - interval '180 days');
  INSERT INTO private.recovery_purge_stuck_alerts (user_id, hold_created_at, alerted_at)
  VALUES (v_uid, now() - interval '400 days', now() - interval '182 days'),
         (v_uid, now() - interval '200 days', now() - interval '180 days');
  PERFORM private.fresh_start_retention();
  IF EXISTS (SELECT 1 FROM public.fresh_start_challenges WHERE nonce_hash = repeat('a', 64))
     OR NOT EXISTS (SELECT 1 FROM public.fresh_start_challenges WHERE nonce_hash = repeat('b', 64))
     OR EXISTS (SELECT 1 FROM private.auth_hook_failures WHERE at < now() - interval '30 days')
     OR NOT EXISTS (SELECT 1 FROM private.auth_hook_failures WHERE at BETWEEN now() - interval '30 days' AND now() - interval '28 days')
     OR EXISTS (SELECT 1 FROM private.fresh_start_attempts WHERE ip_hash = repeat('c', 64))
     OR NOT EXISTS (SELECT 1 FROM private.fresh_start_attempts WHERE ip_hash = repeat('d', 64))
     OR EXISTS (SELECT 1 FROM private.fresh_start_park_alerts WHERE user_id = v_uid AND alerted_at < now() - interval '181 days')
     OR NOT EXISTS (SELECT 1 FROM private.fresh_start_park_alerts WHERE user_id = v_uid AND alerted_at > now() - interval '181 days')
     OR EXISTS (SELECT 1 FROM private.parked_review_alerts WHERE user_id = v_uid AND alerted_at < now() - interval '181 days')
     OR NOT EXISTS (SELECT 1 FROM private.parked_review_alerts WHERE user_id = v_uid AND alerted_at > now() - interval '181 days')
     OR EXISTS (SELECT 1 FROM private.recovery_purge_stuck_alerts WHERE user_id = v_uid AND alerted_at < now() - interval '181 days')
     OR NOT EXISTS (SELECT 1 FROM private.recovery_purge_stuck_alerts WHERE user_id = v_uid AND alerted_at > now() - interval '181 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fresh-start-retention kept or removed the wrong rows';
  END IF;
END $$;
-- =====================================================================
-- H. W6b: the date-of-birth correction (§3.15, §4.3 W6b; plan P-21,
--    P-22). Once, within 7 days of the declaration, never while Dating is
--    active; the same date spends nothing; under 18 places an age hold
--    that commits; the date itself is never returned.
-- =====================================================================
CREATE FUNCTION pg_temp.dob(p_n text, p_birth date, p_declared interval) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_uid constant uuid := pg_temp.person(p_n, interval '1 hour');
BEGIN
  INSERT INTO public.account_birthdates (user_id, birth_date, declared_at)
  VALUES (v_uid, p_birth, now() - p_declared);
  RETURN v_uid;
END $$;

CREATE FUNCTION pg_temp.correct(p_user uuid, p_date text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    EXECUTE format('SELECT public.correct_my_birth_date(%L::date)::text', p_date) INTO v;
  EXCEPTION WHEN OTHERS THEN
    v := 'ERROR: ' || SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- [p_text] as jsonb, or NULL when it is a refusal.
CREATE FUNCTION pg_temp.as_json(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT CASE WHEN p_text LIKE '{%' THEN p_text::jsonb END;
$$;

-- Batch 6 fix round 1 (I-1): set_my_birth_date as [p_user], the legacy path
-- that places an age_review hold for a self-declared minor.
CREATE FUNCTION pg_temp.declare_dob(p_user uuid, p_date date) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.set_my_birth_date(p_date);
  RESET ROLE;
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.dob_status(p_user uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v := public.get_my_birth_date_status();
  RESET ROLE;
  RETURN v;
END $$;

DO $$
DECLARE
  v_fresh constant uuid := pg_temp.dob('50', DATE '1990-05-01', interval '1 day');
  v_late constant uuid := pg_temp.dob('51', DATE '1990-05-01', interval '8 days');
  v_dating constant uuid := pg_temp.dob('52', DATE '1990-05-01', interval '1 day');
  v_minor constant uuid := pg_temp.dob('53', DATE '1990-05-01', interval '1 day');
  v_none constant uuid := pg_temp.person('54', interval '1 hour');
  v_held constant uuid := pg_temp.person('55', interval '1 hour');
  v_safety constant uuid := pg_temp.dob('56', DATE '1990-05-01', interval '1 day');
  v_kid constant text := ((now() AT TIME ZONE 'utc')::date - interval '15 years')::date::text;
  v jsonb;
  v_got text;
BEGIN
  IF to_regprocedure('public.correct_my_birth_date(date)') IS NULL
     OR to_regprocedure('public.get_my_birth_date_status()') IS NULL
     OR to_regprocedure('private.birth_date_correction_open(uuid)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6b objects are missing';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.correct_my_birth_date(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_birth_date_status()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.correct_my_birth_date(date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_birth_date_status()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.birth_date_correction_open(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W6b grants are wrong';
  END IF;

  v := pg_temp.dob_status(v_fresh);
  IF (v ->> 'can_correct')::boolean IS NOT TRUE OR (v ->> 'age')::int < 30
     OR (v ->> 'correct_until')::timestamptz NOT BETWEEN now() + interval '5 days 23 hours' AND now() + interval '6 days 1 hour'
     OR v::text ~ '1990' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status for a new declaration is wrong (or shows the date): %', v;
  END IF;

  -- Once.
  v_got := pg_temp.correct(v_fresh, '1991-06-02');
  IF (pg_temp.as_json(v_got) ->> 'status') IS DISTINCT FROM 'ok' OR (pg_temp.as_json(v_got) ->> 'changed')::boolean IS NOT TRUE
     OR v_got ~ '1991' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a first correction inside 7 days was refused (or echoed the date): %', v_got;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_fresh AND birth_date = DATE '1991-06-02'
                   AND self_corrections = 1 AND corrected_at IS NOT NULL AND source = 'self_declared') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the correction was not recorded as one self-correction';
  END IF;
  IF pg_temp.correct(v_fresh, '1992-07-03') IS DISTINCT FROM 'ERROR: birth_date:correction_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second correction was allowed';
  END IF;
  -- The same date again: nothing changes, nothing is spent, no refusal.
  IF (pg_temp.as_json(pg_temp.correct(v_fresh, '1991-06-02')) ->> 'changed')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same date again was refused or counted';
  END IF;
  IF (pg_temp.dob_status(v_fresh) ->> 'can_correct')::boolean IS NOT FALSE
     OR (pg_temp.dob_status(v_fresh) ->> 'correct_until') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status still offers a correction after one';
  END IF;

  -- After 7 days; while Dating is active.
  IF pg_temp.correct(v_late, '1991-06-02') IS DISTINCT FROM 'ERROR: birth_date:correction_closed'
     OR (pg_temp.dob_status(v_late) ->> 'can_correct')::boolean IS NOT FALSE
     OR (pg_temp.dob_status(v_late) ->> 'correct_until') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a correction 8 days after the declaration was allowed';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_dating, 'active');
  IF pg_temp.correct(v_dating, '1991-06-02') IS DISTINCT FROM 'ERROR: birth_date:correction_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a correction while Dating is active was allowed';
  END IF;
  UPDATE public.dating_enrollments SET state = 'paused' WHERE user_id = v_dating;
  IF (pg_temp.as_json(pg_temp.correct(v_dating, '1991-06-02')) ->> 'status') IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused Dating enrollment closed the correction';
  END IF;

  -- Under 18: an age hold that commits, and no raise.
  v_got := pg_temp.correct(v_minor, v_kid);
  IF pg_temp.as_json(v_got) IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 correction answered %', v_got;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_minor AND kind = 'age_review'
                   AND resolved_at IS NULL AND reason_ref = 'self_corrected_birth_date')
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_minor AND birth_date = v_kid::date) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 correction did not keep the date and an age hold';
  END IF;
  -- The hook now refuses the account (W6a).
  IF pg_temp.hook(pg_temp.event(v_minor, 'token_refresh')) #>> '{error,message}' IS DISTINCT FROM 'account_review:age' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account corrected to under 18 still gets tokens';
  END IF;

  -- The under-18 correction was the one correction (fix round 1, I-1).
  IF pg_temp.correct(v_minor, '1990-01-01') IS DISTINCT FROM 'ERROR: birth_date:correction_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account corrected to under 18 corrected again';
  END IF;

  -- Batch 7 review I-1: the not_eligible answer was lost (a timeout, a
  -- dropped connection after the commit) and the same date is sent again:
  -- not_eligible again, never ok, the hold still open, nothing spent.
  v_got := pg_temp.correct(v_minor, v_kid);
  IF pg_temp.as_json(v_got) IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_minor AND kind = 'age_review'
                      AND resolved_at IS NULL AND reason_ref = 'self_corrected_birth_date')
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_minor
                      AND birth_date = v_kid::date AND self_corrections = 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a retried under-18 correction answered % (or lost its hold)', v_got;
  END IF;
  -- An under-18 date with no open hold (one resolved without a date fix):
  -- the same date holds the account again and answers not_eligible.
  UPDATE public.account_holds SET resolved_at = now() WHERE user_id = v_minor AND kind = 'age_review';
  v_got := pg_temp.correct(v_minor, v_kid);
  IF pg_temp.as_json(v_got) IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_minor AND kind = 'age_review'
                      AND resolved_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unheld under-18 date sent again answered % (or placed no hold)', v_got;
  END IF;

  -- I-1: an open hold closes the correction, so a self-confessed minor
  -- can't rewrite the date the hold rests on (any kind: age, safety,
  -- recovery; support corrects through support_corrected).
  IF pg_temp.declare_dob(v_held, ((now() AT TIME ZONE 'utc')::date - interval '15 years')::date)
       IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the I-1 fixture is wrong (set_my_birth_date did not hold a minor)';
  END IF;
  PERFORM public.place_account_hold(v_safety, 'safety_review', 'contract_h');
  IF pg_temp.correct(v_held, '1990-01-01') IS DISTINCT FROM 'ERROR: birth_date:correction_closed'
     OR pg_temp.correct(v_safety, '1991-06-02') IS DISTINCT FROM 'ERROR: birth_date:correction_closed'
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_held
                      AND birth_date = ((now() AT TIME ZONE 'utc')::date - interval '15 years')::date
                      AND self_corrections = 0 AND corrected_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_safety
                      AND birth_date = DATE '1990-05-01' AND self_corrections = 0)
     OR pg_temp.dob_status(v_held) ->> 'can_correct' IS DISTINCT FROM 'false'
     OR pg_temp.dob_status(v_held) ->> 'correct_until' IS NOT NULL
     OR pg_temp.dob_status(v_safety) ->> 'can_correct' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account corrected its date of birth';
  END IF;
  -- Batch 7 review I-1: the hold check runs before the same-date answer.
  -- The held minor's own date again is not_eligible (the sign-up hold's
  -- reason kept); a held adult's own date again is closed, never ok.
  v_got := pg_temp.correct(v_held, (((now() AT TIME ZONE 'utc')::date - interval '15 years')::date)::text);
  IF pg_temp.as_json(v_got) IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = v_held AND kind = 'age_review'
                      AND resolved_at IS NULL AND reason_ref = 'self_declared_birth_date')
     OR pg_temp.correct(v_safety, '1990-05-01') IS DISTINCT FROM 'ERROR: birth_date:correction_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a held account sending its own date again answered % (or ok)', v_got;
  END IF;

  -- Rubbish and no date.
  IF pg_temp.correct(v_none, '1990-01-01') IS DISTINCT FROM 'ERROR: birth_date:not_set'
     OR pg_temp.correct(v_late, ((now() AT TIME ZONE 'utc')::date + 2)::text) IS DISTINCT FROM 'ERROR: birth_date:invalid'
     OR pg_temp.correct(v_late, '1899-12-31') IS DISTINCT FROM 'ERROR: birth_date:invalid'
     OR pg_temp.correct(NULL, '1990-01-01') IS DISTINCT FROM 'ERROR: birth_date:not_signed_in' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad correction was not refused by its message';
  END IF;
  IF pg_temp.dob_status(v_none) IS DISTINCT FROM '{"age": null, "can_correct": false, "correct_until": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the status without a date is %', pg_temp.dob_status(v_none);
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dormancy_contracts: all held'; END $$;

ROLLBACK;
