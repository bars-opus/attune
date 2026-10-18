-- supabase/tests/translator_limit_contracts.sql
-- Spec 8 (plan review I9): the translator has a per-person daily limit,
-- counted by the server against the caller only.
BEGIN;
INSERT INTO auth.users (id) VALUES ('9fa10000-0000-0000-0000-0000000000a1'), ('9fa10000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
DO $$
DECLARE v_ok boolean; v_n int := 0;
BEGIN
  IF has_function_privilege('anon', 'public.reserve_translator_use()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.reserve_translator_use()', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.translator_daily_use', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: translator limit grants';
  END IF;
  PERFORM pg_temp.as_user('9fa10000-0000-0000-0000-0000000000a1');
  FOR i IN 1..31 LOOP
    v_ok := public.reserve_translator_use();
    IF v_ok THEN v_n := v_n + 1; END IF;
  END LOOP;
  RESET ROLE;
  IF v_n <> 30 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % uses allowed, not 30', v_n; END IF;
  -- Someone else's count is their own.
  PERFORM pg_temp.as_user('9fa10000-0000-0000-0000-0000000000b2');
  v_ok := public.reserve_translator_use();
  RESET ROLE;
  IF NOT v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: one person''s use counted against another'; END IF;
  -- A new day starts fresh.
  UPDATE public.translator_daily_use SET day = day - 1 WHERE user_id = '9fa10000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.as_user('9fa10000-0000-0000-0000-0000000000a1');
  v_ok := public.reserve_translator_use();
  RESET ROLE;
  IF NOT v_ok THEN RAISE EXCEPTION 'CONTRACT VIOLATED: yesterday''s uses counted today'; END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'translator_limit_contracts: all held'; END $$;
ROLLBACK;
