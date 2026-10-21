-- Each person's own order for the movable cards on Conversations
-- (2026-10-18): user_preferences.home_card_order, private to its owner like
-- the rest of the row; short card ids only.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7fea0000-0000-0000-0000-0000000000a1'), ('7fea0000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 1. Saving my order, and reading it back.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
INSERT INTO public.user_preferences (user_id, home_card_order)
VALUES ('7fea0000-0000-0000-0000-0000000000a1', ARRAY['together', 'journals'])
ON CONFLICT (user_id) DO UPDATE SET home_card_order = EXCLUDED.home_card_order;
DO $$
BEGIN
  IF (SELECT home_card_order FROM public.user_preferences WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1')
     IS DISTINCT FROM ARRAY['together', 'journals'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: my order did not save';
  END IF;
END $$;

-- 2. Nobody else sees it, or can set it for me.
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000b2');
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.user_preferences WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person read my order';
  END IF;
  UPDATE public.user_preferences SET home_card_order = ARRAY['journals']
  WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1';
  BEGIN
    INSERT INTO public.user_preferences (user_id, home_card_order)
    VALUES ('7fea0000-0000-0000-0000-0000000000a1', ARRAY['journals']);
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person wrote my order';
  EXCEPTION WHEN insufficient_privilege OR unique_violation OR check_violation THEN NULL;
  END;
END $$;
SELECT pg_temp.as_user('7fea0000-0000-0000-0000-0000000000a1');
DO $$
BEGIN
  IF (SELECT home_card_order FROM public.user_preferences WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1')
     IS DISTINCT FROM ARRAY['together', 'journals'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person changed my order';
  END IF;
END $$;

-- 3. Only short card ids, and not too many.
DO $$
BEGIN
  BEGIN
    UPDATE public.user_preferences SET home_card_order = ARRAY['<script>']
    WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1';
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strange card id accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.user_preferences SET home_card_order = array_fill('journals'::text, ARRAY[21])
    WHERE user_id = '7fea0000-0000-0000-0000-0000000000a1';
    RAISE EXCEPTION 'CONTRACT VIOLATED: 21 cards accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
