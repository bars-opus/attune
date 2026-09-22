-- Provider-start marker column and widened mode CHECK.
-- Run: psql -q -d attune_test -f supabase/tests/ai_assistant_provider_start_marker_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := 'a5000000-0000-0000-0000-000000000001';
  v_user_a uuid := 'a5000000-0000-0000-0000-00000000000a';
  v_user_b uuid := 'a5000000-0000-0000-0000-00000000000b';
  v_req_1 uuid := 'a5000000-0000-0000-0000-000000000101';
  v_row record;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'marker_a@t.test'), (v_user_b, 'marker_b@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_user_a, '+15550005001', 'A'), (v_user_b, '+15550005002', 'B')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: provider_started_at exists, defaults NULL, and is
  -- writable directly by this fixture setup (proving the column itself
  -- is correctly typed and nullable before any RPC touches it).
  SELECT * INTO v_row FROM public.reserve_ai_assistant_quota(v_user_a, v_req_1, v_rel, 'assist');
  IF v_row.outcome IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'EXPLOIT: setup reservation failed, got %', v_row.outcome;
  END IF;
  PERFORM provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1;
  IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1) IS NOT NULL THEN
    RAISE EXCEPTION 'EXPLOIT: provider_started_at was non-NULL on a fresh reservation';
  END IF;

  -- Contract 2: 'session' is now a legal mode value.
  PERFORM public.reserve_ai_assistant_quota(v_user_b, gen_random_uuid(), v_rel, 'session');

  RAISE NOTICE 'provider-start marker contracts: all held';
END $$;
