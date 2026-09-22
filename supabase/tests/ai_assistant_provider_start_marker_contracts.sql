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

  -- Contract 3: the first claim succeeds and sets the marker.
  IF public.claim_ai_assistant_provider_start(v_user_a, v_req_1) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'EXPLOIT: first provider-start claim did not return true';
  END IF;
  IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1) IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: provider_started_at is still NULL after a successful claim';
  END IF;

  -- Contract 4: a second claim on the SAME request_id returns false and
  -- does NOT move provider_started_at forward in time (write-once).
  DECLARE
    v_first_marker timestamptz;
    v_second_claim boolean;
  BEGIN
    SELECT provider_started_at INTO v_first_marker
    FROM public.ai_assistant_usage WHERE request_id = v_req_1;
    PERFORM pg_sleep(0.01);
    v_second_claim := public.claim_ai_assistant_provider_start(v_user_a, v_req_1);
    IF v_second_claim IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'EXPLOIT: second provider-start claim on the same request did not return false';
    END IF;
    IF (SELECT provider_started_at FROM public.ai_assistant_usage WHERE request_id = v_req_1)
        IS DISTINCT FROM v_first_marker THEN
      RAISE EXCEPTION 'EXPLOIT: provider_started_at moved forward on a second claim -- write-once violated';
    END IF;
  END;

  -- Contract 5: a different actor cannot claim someone else's request.
  BEGIN
    PERFORM public.claim_ai_assistant_provider_start(v_user_b, v_req_1);
    RAISE EXCEPTION 'EXPLOIT: user_b claimed user_a''s own request row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: a terminal row can never gain a start marker after the
  -- fact -- claiming on an already-succeeded row must raise, not
  -- silently set the marker (which would let a completed reservation
  -- retroactively look like it had started a provider call it never
  -- made, corrupting the compensation table's own invariant).
  PERFORM public.mark_ai_assistant_usage_outcome(v_user_a, v_req_1, 'succeeded', 1::smallint);
  BEGIN
    PERFORM public.claim_ai_assistant_provider_start(v_user_a, v_req_1);
    RAISE EXCEPTION 'EXPLOIT: provider-start claim succeeded on an already-terminal row';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'provider-start marker contracts: all held';
END $$;
