-- supabase/tests/ask2_state_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/ask2_state_test.sql
BEGIN;


-- public.users.id references auth.users(id); in a test database the
-- auth row does not exist yet, so seed the parents first.
INSERT INTO auth.users (id) VALUES
  ('d1111111-1111-1111-1111-111111111111'),
  ('d2222222-2222-2222-2222-222222222222'),
  ('e0000001-0000-0000-0000-000000000001'),
  ('e0000002-0000-0000-0000-000000000002'),
  ('f3333333-3333-3333-3333-333333333333')
ON CONFLICT (id) DO NOTHING;


INSERT INTO public.users (id, phone, display_name) VALUES
  ('d1111111-1111-1111-1111-111111111111', '+1000000021', 'User D1'),
  ('d2222222-2222-2222-2222-222222222222', '+1000000022', 'User D2');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('e0000001-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111',
   'd2222222-2222-2222-2222-222222222222',
   'active', now()::date);

-- A fresh row defaults to 'pending'.
INSERT INTO public.ask2_state (relationship_id) VALUES ('e0000001-0000-0000-0000-000000000001');

DO $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_status = 'pending', 'new ask2_state row must default to pending';
END $$;

-- An invalid status is rejected by the CHECK constraint.
DO $$
BEGIN
  BEGIN
    UPDATE public.ask2_state SET status = 'not_a_real_status'
    WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'expected CHECK constraint violation for invalid status';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END $$;

-- complete_ask2: a relationship MEMBER can transition prompted -> completed.
-- Supabase's auth.uid() reads request.jwt.claims -> sub; set it directly to
-- simulate an authenticated call from user D1.
-- (UPDATE, not INSERT: the row for this relationship_id already exists from
-- the 'pending' default-row insert above, and relationship_id is the PK.)
UPDATE public.ask2_state SET status = 'prompted', prompted_at = now()
WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';

SELECT set_config('request.jwt.claims', '{"sub":"d1111111-1111-1111-1111-111111111111"}', true);

SELECT public.complete_ask2('e0000001-0000-0000-0000-000000000001');

DO $$
DECLARE v_status text; v_completed_at timestamptz;
BEGIN
  SELECT status, completed_at INTO v_status, v_completed_at
  FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_status = 'completed', 'complete_ask2 must transition prompted -> completed for a member';
  ASSERT v_completed_at IS NOT NULL, 'complete_ask2 must stamp completed_at';
END $$;

-- complete_ask2: a NON-member is rejected.
INSERT INTO public.users (id, phone, display_name) VALUES
  ('f3333333-3333-3333-3333-333333333333', '+1000000023', 'Outsider');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('e0000002-0000-0000-0000-000000000002',
   'd1111111-1111-1111-1111-111111111111',
   'd2222222-2222-2222-2222-222222222222',
   'active', now()::date);
INSERT INTO public.ask2_state (relationship_id, status, prompted_at)
VALUES ('e0000002-0000-0000-0000-000000000002', 'prompted', now());

SELECT set_config('request.jwt.claims', '{"sub":"f3333333-3333-3333-3333-333333333333"}', true);

DO $$
BEGIN
  BEGIN
    PERFORM public.complete_ask2('e0000002-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'expected forbidden error for a non-member calling complete_ask2';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'forbidden' THEN
      RAISE;
    END IF;
  END;
END $$;

-- Deleting the relationship cascades to ask2_state (ON DELETE CASCADE).
DELETE FROM public.relationships WHERE id = 'e0000001-0000-0000-0000-000000000001';

DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_count = 0, 'ask2_state row must be cascade-deleted with its relationship';
END $$;

ROLLBACK;
