-- supabase/tests/relationships_lockdown_contracts.sql
-- Relationships write lockdown (Spec 1a Task 1). Every check RAISEs on violation.
--
-- Before 20261017110000 either member could UPDATE any column of their row:
-- "relationship members update limited" tested only membership, and
-- 20260724120000 granted table-level UPDATE. Status, user_a/user_b,
-- invite_accepted_at, ended_at, chat_archived_at were all client-writable.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('5a100000-0000-0000-0000-0000000000a1'),
  ('5a100000-0000-0000-0000-0000000000b2'),
  ('5a100000-0000-0000-0000-0000000000c3'),
  ('5a100000-0000-0000-0000-0000000000d4')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('5a100000-0000-0000-0000-0000000000a1', '+233599100001', 'Lock A'),
  ('5a100000-0000-0000-0000-0000000000b2', '+233599100002', 'Lock B'),
  ('5a100000-0000-0000-0000-0000000000c3', '+233599100003', 'Lock C'),
  ('5a100000-0000-0000-0000-0000000000d4', '+233599100004', 'Lock D')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('5a200000-0000-0000-0000-000000000001', '5a100000-0000-0000-0000-0000000000a1',
   '5a100000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z'),
  ('5a200000-0000-0000-0000-000000000002', '5a100000-0000-0000-0000-0000000000c3',
   '5a100000-0000-0000-0000-0000000000d4', 'active', CURRENT_DATE, now(), '2026-10-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- 1. The open UPDATE policy is gone and the privileges with it. SELECT and
--    INSERT (the inviter's pending row) stay.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policy
             WHERE polrelid = 'public.relationships'::regclass AND polcmd IN ('w', '*')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an UPDATE policy still exists on relationships';
  END IF;
  IF has_table_privilege('authenticated', 'public.relationships', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds UPDATE on relationships';
  END IF;
  IF has_table_privilege('authenticated', 'public.relationships', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated holds DELETE on relationships';
  END IF;
  -- Spec 3a (review I1): SELECT is column-level now; who ended it, who
  -- paused and why it was archived are not readable by members.
  IF NOT has_column_privilege('authenticated', 'public.relationships', 'status', 'SELECT')
     OR NOT has_column_privilege('authenticated', 'public.relationships', 'id', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: members can no longer read relationships';
  END IF;
  IF has_column_privilege('authenticated', 'public.relationships', 'ended_by', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: members can read ended_by';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.relationships', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the inviter can no longer insert a pending row';
  END IF;
END $$;

-- 2. A member cannot rewrite any column from the client. Each statement must
--    fail with 42501 specifically; a different error (or success) is a hole.
DO $$
DECLARE v_sql text;
BEGIN
  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000a1');
  FOREACH v_sql IN ARRAY ARRAY[
    $q$UPDATE public.relationships SET status = 'ended' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET status = 'paused' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET user_b = '5a100000-0000-0000-0000-0000000000c3' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET user_a = '5a100000-0000-0000-0000-0000000000b2', user_b = '5a100000-0000-0000-0000-0000000000a1' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET invite_accepted_at = now() WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET ended_at = now(), ended_by = '5a100000-0000-0000-0000-0000000000a1' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET chat_archived_at = now(), chat_archived_reason = 'manual_end' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET chat_name = 'Hijacked' WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$UPDATE public.relationships SET last_overall_pulse = 99 WHERE id = '5a200000-0000-0000-0000-000000000001'$q$,
    $q$DELETE FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001'$q$
  ] LOOP
    BEGIN
      EXECUTE v_sql;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a member ran: %', v_sql;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL; -- expected
    END;
  END LOOP;
  RESET ROLE;
  IF (SELECT status FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001') <> 'active'
     OR (SELECT chat_name FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client write reached the row';
  END IF;
END $$;

-- 3. The RPC paths still write.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000a1');
  PERFORM public.set_relationship_chat_name('5a200000-0000-0000-0000-000000000001', 'Us Two');
  RESET ROLE;
  IF (SELECT chat_name FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000001')
     IS DISTINCT FROM 'Us Two' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_relationship_chat_name no longer writes';
  END IF;

  PERFORM pg_temp.as_user('5a100000-0000-0000-0000-0000000000c3');
  PERFORM public.end_relationship('5a200000-0000-0000-0000-000000000002');
  RESET ROLE;
  IF (SELECT status FROM public.relationships WHERE id = '5a200000-0000-0000-0000-000000000002')
     IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: end_relationship no longer writes';
  END IF;
  RAISE NOTICE 'relationships_lockdown_contracts: all held';
END $$;

ROLLBACK;
