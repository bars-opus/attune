-- supabase/tests/ask2_eligibility_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/ask2_eligibility_test.sql
BEGIN;


-- public.users.id references auth.users(id); in a test database the
-- auth row does not exist yet, so seed the parents first.
INSERT INTO auth.users (id) VALUES
  ('a1111111-1111-1111-1111-111111111111'),
  ('b2222222-2222-2222-2222-222222222222'),
  ('c0000001-0000-0000-0000-000000000001'),
  ('c0000002-0000-0000-0000-000000000002'),
  ('c0000003-0000-0000-0000-000000000003'),
  ('c0000004-0000-0000-0000-000000000004')
ON CONFLICT (id) DO NOTHING;


INSERT INTO public.users (id, phone, display_name) VALUES
  ('a1111111-1111-1111-1111-111111111111', '+1000000011', 'User A'),
  ('b2222222-2222-2222-2222-222222222222', '+1000000012', 'User B');

-- Case 1: relationship not yet linked (user_b IS NULL) -> not eligible.
INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at) VALUES
  ('c0000001-0000-0000-0000-000000000001',
   'a1111111-1111-1111-1111-111111111111',
   'pending', 'TESTCODE1', now() + interval '1 day');

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000001-0000-0000-0000-000000000001');
  ASSERT v_eligible = false, 'unlinked relationship must not be eligible';
END $$;

-- Case 2: linked, but under the 30-messages-each threshold -> not eligible.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000002-0000-0000-0000-000000000002',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000002-0000-0000-0000-000000000002',
       'a1111111-1111-1111-1111-111111111111',
       gen_random_uuid(),
       'msg ' || n, 'positive', now()
FROM generate_series(1, 5) AS n;
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000002-0000-0000-0000-000000000002',
       'b2222222-2222-2222-2222-222222222222',
       gen_random_uuid(),
       'msg ' || n, 'positive', now()
FROM generate_series(1, 5) AS n;

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000002-0000-0000-0000-000000000002');
  ASSERT v_eligible = false, 'under-threshold message count must not be eligible';
END $$;

-- Case 3: 30+ messages each, but all on one day, and no positive sentiment
-- -> not eligible (fails both day-count and sentiment gates).
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000003-0000-0000-0000-000000000003',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000003-0000-0000-0000-000000000003',
       'a1111111-1111-1111-1111-111111111111',
       gen_random_uuid(),
       'msg ' || n, 'neutral', now()
FROM generate_series(1, 30) AS n;
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000003-0000-0000-0000-000000000003',
       'b2222222-2222-2222-2222-222222222222',
       gen_random_uuid(),
       'msg ' || n, 'neutral', now()
FROM generate_series(1, 30) AS n;

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000003-0000-0000-0000-000000000003');
  ASSERT v_eligible = false, 'single-day, no-positive-sentiment case must not be eligible';
END $$;

-- Case 4: fully eligible — 30+ each, spread across 3+ distinct days, with a
-- positive-sentiment message.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000004-0000-0000-0000-000000000004',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', (now() - interval '3 days')::date);

INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000004-0000-0000-0000-000000000004',
       'a1111111-1111-1111-1111-111111111111',
       gen_random_uuid(),
       'msg ' || n,
       CASE WHEN n = 1 THEN 'positive' ELSE 'neutral' END,
       now() - ((n % 3) || ' days')::interval
FROM generate_series(1, 30) AS n;
INSERT INTO public.messages (relationship_id, sender_id, client_message_id, content, sentiment, created_at)
SELECT 'c0000004-0000-0000-0000-000000000004',
       'b2222222-2222-2222-2222-222222222222',
       gen_random_uuid(),
       'msg ' || n, 'neutral',
       now() - ((n % 3) || ' days')::interval
FROM generate_series(1, 30) AS n;

DO $$
DECLARE v_eligible boolean; v_msg_id uuid;
BEGIN
  SELECT eligible, first_positive_message_id INTO v_eligible, v_msg_id
  FROM public.ask2_eligibility('c0000004-0000-0000-0000-000000000004');
  ASSERT v_eligible = true, 'fully-qualifying relationship must be eligible';
  ASSERT v_msg_id IS NOT NULL, 'eligible result must include the first positive message id';
END $$;

ROLLBACK;
