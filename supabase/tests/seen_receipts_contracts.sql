-- supabase/tests/seen_receipts_contracts.sql
-- "Show when we've seen things" (Spec 1a Task 2; research 06 §3 F4; SOUL §8;
-- SPEC §11.12). Every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5b100000-0000-0000-0000-000000000001'), ('5b100000-0000-0000-0000-000000000002'),
  ('5b100000-0000-0000-0000-000000000003'), ('5b100000-0000-0000-0000-000000000004'),
  ('5b100000-0000-0000-0000-000000000005'), ('5b100000-0000-0000-0000-000000000006'),
  ('5b100000-0000-0000-0000-000000000007')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5b100000-0000-0000-0000-000000000001', '+233599200001', 'Seen 1'),
  ('5b100000-0000-0000-0000-000000000002', '+233599200002', 'Seen 2'),
  ('5b100000-0000-0000-0000-000000000003', '+233599200003', 'Seen 3'),
  ('5b100000-0000-0000-0000-000000000004', '+233599200004', 'Seen 4'),
  ('5b100000-0000-0000-0000-000000000005', '+233599200005', 'Seen 5'),
  ('5b100000-0000-0000-0000-000000000006', '+233599200006', 'Seen 6'),
  ('5b100000-0000-0000-0000-000000000007', '+233599200007', 'Seen 7')
ON CONFLICT (id) DO NOTHING;
-- R1 linked before the cutoff, R2 linked exactly at it, R3 has no link time
-- (a legacy row). u7 is in no relationship.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5b200000-0000-0000-0000-000000000001', '5b100000-0000-0000-0000-000000000001',
   '5b100000-0000-0000-0000-000000000002', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z'),
  ('5b200000-0000-0000-0000-000000000002', '5b100000-0000-0000-0000-000000000003',
   '5b100000-0000-0000-0000-000000000004', 'active', CURRENT_DATE, now(), '2026-10-24T00:00:00Z'),
  ('5b200000-0000-0000-0000-000000000003', '5b100000-0000-0000-0000-000000000005',
   '5b100000-0000-0000-0000-000000000006', 'active', CURRENT_DATE, now(), NULL)
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_nobody() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
CREATE FUNCTION pg_temp.expect_fail(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'CONTRACT VIOLATED: % succeeded (expected %)', p_sql, p_msg;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
    IF v_msg <> p_msg THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % raised "%" (expected "%")', p_sql, v_msg, p_msg;
    END IF;
  END;
END $$;

-- 1. The table is RPC-only.
DO $$
DECLARE v int;
BEGIN
  IF has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'SELECT')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'INSERT')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.seen_receipt_prefs', 'DELETE')
     OR has_table_privilege('anon', 'public.seen_receipt_prefs', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client role holds a privilege on seen_receipt_prefs';
  END IF;
  IF has_function_privilege('authenticated', 'public.seen_receipts_effective(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.seen_receipts_member(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.seen_receipts_backfill_defaults(timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an internal seen_receipts function is client-executable';
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  BEGIN
    SELECT count(*) INTO v FROM public.seen_receipt_prefs;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member read seen_receipt_prefs directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    INSERT INTO public.seen_receipt_prefs (relationship_id, user_id, seen_on)
    VALUES ('5b200000-0000-0000-0000-000000000001', '5b100000-0000-0000-0000-000000000001', true);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member wrote seen_receipt_prefs directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
END $$;

-- 2. Default by link date: before the cutoff (or no link time) is on for both;
--    on/after the cutoff is off. The backfill is idempotent. (In production
--    the cutoff is the deploy moment itself: the migration calls the
--    function with its DEFAULT now().)
DO $$
DECLARE v_n int; v jsonb;
BEGIN
  -- Explicit cutoff: the migration used now() at deploy; the fixtures sit
  -- either side of this date on purpose.
  v_n := public.seen_receipts_backfill_defaults('2026-10-24T00:00:00Z');
  IF v_n < 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: backfill inserted % rows, expected at least 4 (R1 and R3)', v_n;
  END IF;
  IF (SELECT count(*) FROM public.seen_receipt_prefs
      WHERE relationship_id IN ('5b200000-0000-0000-0000-000000000001', '5b200000-0000-0000-0000-000000000003')
        AND seen_on) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pre-cutoff couples were not defaulted on';
  END IF;
  IF EXISTS (SELECT 1 FROM public.seen_receipt_prefs WHERE relationship_id = '5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a couple linked at the cutoff got default rows';
  END IF;
  IF public.seen_receipts_backfill_defaults('2026-10-24T00:00:00Z') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill is not idempotent';
  END IF;

  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000001');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an older couple is not on by default: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000002');
  IF (v->>'mine') IS DISTINCT FROM 'false' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new couple is not off by default: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000005');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000003');
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy couple without a link time is not on: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 3. Either off disables for both; the partner sees only the effective state.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', false);
  IF (v->>'mine') IS DISTINCT FROM 'false' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turning off did not turn it off: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000002');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000001');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner does not see effective off (own vote intact): %', v;
  END IF;
  IF v ? 'partner' OR v ? 'user_a' OR v ? 'user_b' OR v ? 'updated_at' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_seen_receipts exposes more than mine/effective: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 4. Turning on requires both.
DO $$
DECLARE v jsonb;
BEGIN
  -- R1: u2 is still on, so u1 alone brings it back.
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', true);
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: both on did not become effective: %', v;
  END IF;
  -- R2: the first vote alone changes nothing visible.
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one partner turned it on alone: %', v;
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000004');
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'effective') IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the second vote did not turn it on: %', v;
  END IF;
  RESET ROLE;
END $$;

-- 5. Outsiders, the unauthenticated, ended couples and bad input.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000007');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000001')$q$, 'seen_receipts:not_found');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', true)$q$, 'seen_receipts:not_found');
  PERFORM pg_temp.as_nobody();
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000001')$q$, 'seen_receipts:unauthenticated');
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000001');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.set_seen_receipts('5b200000-0000-0000-0000-000000000001', NULL)$q$, 'seen_receipts:invalid_input');
  RESET ROLE;
  UPDATE public.relationships SET status = 'ended', ended_at = now(), chat_archived_at = now(), chat_archived_reason = 'manual_end'
   WHERE id = '5b200000-0000-0000-0000-000000000003';
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000005');
  PERFORM pg_temp.expect_fail(
    $q$SELECT public.get_seen_receipts('5b200000-0000-0000-0000-000000000003')$q$, 'seen_receipts:not_found');
  RESET ROLE;
END $$;

-- 6. Paused (Review Focus 7): receipts stop flowing even with both votes on,
--    and a paused member can still turn theirs off (and back on).
DO $$
DECLARE v jsonb;
BEGIN
  -- R2 is on for both after block 4.
  UPDATE public.relationships SET status = 'paused' WHERE id = '5b200000-0000-0000-0000-000000000002';
  IF public.seen_receipts_effective('5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: receipts stay effective while paused';
  END IF;
  PERFORM pg_temp.as_user('5b100000-0000-0000-0000-000000000003');
  v := public.get_seen_receipts('5b200000-0000-0000-0000-000000000002');
  IF (v->>'mine') IS DISTINCT FROM 'true' OR (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member sees the wrong state: %', v;
  END IF;
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', false);
  IF (v->>'mine') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member could not turn receipts off: %', v;
  END IF;
  v := public.set_seen_receipts('5b200000-0000-0000-0000-000000000002', true);
  IF (v->>'effective') IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning on while paused became effective: %', v;
  END IF;
  RESET ROLE;
  UPDATE public.relationships SET status = 'active' WHERE id = '5b200000-0000-0000-0000-000000000002';
  IF NOT public.seen_receipts_effective('5b200000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: receipts did not resume on unpause with both votes on';
  END IF;
  RAISE NOTICE 'seen_receipts_contracts: all held';
END $$;

ROLLBACK;
