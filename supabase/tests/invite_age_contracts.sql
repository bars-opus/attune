-- supabase/tests/invite_age_contracts.sql
-- Spec 5 (R5-9, R5-10; plan review C2, C3): how long the person has been
-- waiting comes from the server, from their oldest pending invite (expired
-- ones too, so a re-mint never resets it); "use Attune on my own" removes
-- only their own never-accepted invites.
BEGIN;
INSERT INTO auth.users (id) VALUES
  ('9f900000-0000-0000-0000-0000000000a1'), ('9f900000-0000-0000-0000-0000000000b2'),
  ('9f900000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f900000-0000-0000-0000-0000000000a1', '+233599900001', 'Waiting'),
  ('9f900000-0000-0000-0000-0000000000b2', '+233599900002', 'Other'),
  ('9f900000-0000-0000-0000-0000000000c3', '+233599900003', 'Partner')
ON CONFLICT (id) DO NOTHING;
SET LOCAL session_replication_role = replica;
INSERT INTO public.relationships (id, user_a, user_b, status, invite_code, invite_expires_at, created_at) VALUES
  ('9f910000-0000-0000-0000-000000000001', '9f900000-0000-0000-0000-0000000000a1', NULL, 'pending', 'AGE00001', now() - interval '2 days', now() - interval '9 days'),
  ('9f910000-0000-0000-0000-000000000002', '9f900000-0000-0000-0000-0000000000a1', NULL, 'pending', 'AGE00002', now() + interval '6 days', now() - interval '1 day'),
  ('9f910000-0000-0000-0000-000000000003', '9f900000-0000-0000-0000-0000000000b2', NULL, 'pending', 'AGE00003', now() + interval '6 days', now() - interval '3 days'),
  ('9f910000-0000-0000-0000-000000000004', '9f900000-0000-0000-0000-0000000000a1', '9f900000-0000-0000-0000-0000000000c3', 'ended', NULL, NULL, now() - interval '400 days');
SET LOCAL session_replication_role = origin;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

DO $$
DECLARE v_age int; v_n int;
BEGIN
  IF has_function_privilege('anon', 'public.get_my_invite_age()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.withdraw_my_pending_invites()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_invite_age()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invite age grants';
  END IF;
  PERFORM pg_temp.as_user('9f900000-0000-0000-0000-0000000000a1');
  v_age := public.get_my_invite_age();
  RESET ROLE;
  IF v_age NOT BETWEEN 9 * 86400 - 60 AND 9 * 86400 + 60 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wait is % s, not 9 days (the oldest, expired included)', v_age;
  END IF;

  PERFORM pg_temp.as_user('9f900000-0000-0000-0000-0000000000a1');
  v_n := public.withdraw_my_pending_invites();
  v_age := public.get_my_invite_age();
  RESET ROLE;
  IF v_n <> 2 OR v_age IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrew % (want 2), age after %', v_n, v_age;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.relationships WHERE id = '9f910000-0000-0000-0000-000000000003')
     OR NOT EXISTS (SELECT 1 FROM public.relationships WHERE id = '9f910000-0000-0000-0000-000000000004') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw touched someone else''s invite or a real relationship';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'invite_age_contracts: all held'; END $$;
ROLLBACK;
