-- supabase/tests/message_sentiment_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/message_sentiment_test.sql
BEGIN;

-- A valid sentiment value is accepted.
INSERT INTO public.users (id, phone, display_name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+1000000001', 'Test A'),
  ('22222222-2222-2222-2222-222222222222', '+1000000002', 'Test B');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('33333333-3333-3333-3333-333333333333',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, content, sentiment)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'hello',
  'positive'
);

DO $$
BEGIN
  ASSERT (SELECT sentiment FROM public.messages WHERE content = 'hello') = 'positive',
    'sentiment column did not persist the expected value';
END $$;

-- An invalid sentiment value is rejected by the CHECK constraint.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, content, sentiment)
    VALUES (
      '33333333-3333-3333-3333-333333333333',
      '11111111-1111-1111-1111-111111111111',
      'bad',
      'ecstatic'
    );
    RAISE EXCEPTION 'expected CHECK constraint violation for invalid sentiment';
  EXCEPTION WHEN check_violation THEN
    -- expected
    NULL;
  END;
END $$;

ROLLBACK;
