-- Together Phase 7 contracts: AI availability. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f900000-0000-0000-0000-0000000000a1'), ('7f900000-0000-0000-0000-0000000000b2'), ('7f900000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f900000-0000-0000-0000-0000000000a1', '+233340000001', 'Ama Mensah'),
  ('7f900000-0000-0000-0000-0000000000b2', '+233340000002', 'Kofi Boateng'),
  ('7f900000-0000-0000-0000-0000000000c3', '+233340000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7fa00000-0000-0000-0000-000000000001', '7f900000-0000-0000-0000-0000000000a1',
        '7f900000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

DO $$
DECLARE v jsonb; v_msg text;
BEGIN
  -- Off by default (the flag is seeded false), whatever consent says.
  -- Both partners consent at the current policy (sync audit K-5: the real
  -- consent events, not the old test stub).
  INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key)
  SELECT '7fa00000-0000-0000-0000-000000000001', u, public.ai_current_consent_policy_version(), 'granted', gen_random_uuid()
  FROM unnest(ARRAY['7f900000-0000-0000-0000-0000000000a1', '7f900000-0000-0000-0000-0000000000b2']::uuid[]) u;
  PERFORM pg_temp.as_user('7f900000-0000-0000-0000-0000000000a1');
  v := public.get_together_ai_status('7fa00000-0000-0000-0000-000000000001');
  IF (v->>'available')::boolean THEN RAISE EXCEPTION 'CONTRACT VIOLATED: AI available with the flag off'; END IF;
  IF v->>'partner_name' <> 'Kofi' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner first name %', v->>'partner_name'; END IF;

  -- Flag on + both consented → available; without consent → not.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'ai_together_enabled';
  IF NOT (public.get_together_ai_status('7fa00000-0000-0000-0000-000000000001')->>'available')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: AI unavailable with flag on and consent';
  END IF;
  INSERT INTO public.ai_processing_consent_events (relationship_id, user_id, policy_version, action, idempotency_key, created_at)
  VALUES ('7fa00000-0000-0000-0000-000000000001', '7f900000-0000-0000-0000-0000000000b2',
          public.ai_current_consent_policy_version(), 'withdrawn', gen_random_uuid(), now() + interval '1 second');
  IF (public.get_together_ai_status('7fa00000-0000-0000-0000-000000000001')->>'available')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: AI available without both partners'' consent';
  END IF;

  -- A stranger learns nothing.
  PERFORM pg_temp.as_user('7f900000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.get_together_ai_status('7fa00000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger read AI status';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
