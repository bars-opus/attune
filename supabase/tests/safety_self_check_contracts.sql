-- supabase/tests/safety_self_check_contracts.sql
-- Spec 8 (research 06 F14; plan review C1, I1, I2, I3, I10, M1): a private
-- safety check, per person per relationship. Answers are never stored; a
-- positive result is sticky for 180 days; nothing a member can call or read
-- depends on their partner's check; suppression is the server's alone.
BEGIN;
INSERT INTO auth.users (id) VALUES ('9ff00000-0000-0000-0000-0000000000a1'), ('9ff00000-0000-0000-0000-0000000000b2'),
  ('9ff00000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9ff00000-0000-0000-0000-0000000000a1', '+233599640001', 'Efua'),
  ('9ff00000-0000-0000-0000-0000000000b2', '+233599640002', 'Kwame'),
  ('9ff00000-0000-0000-0000-0000000000c3', '+233599640003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at, invite_accepted_at) VALUES
  ('9ff10000-0000-0000-0000-000000000001', '9ff00000-0000-0000-0000-0000000000a1', '9ff00000-0000-0000-0000-0000000000b2', 'active', CURRENT_DATE - 50, now() - interval '50 days', now());

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

DO $$
DECLARE
  v_rel uuid := '9ff10000-0000-0000-0000-000000000001';
  v_a uuid := '9ff00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9ff00000-0000-0000-0000-0000000000b2';
  v_c uuid := '9ff00000-0000-0000-0000-0000000000c3';
  v_res jsonb; r record; v_n int; v_fn text; v_msg text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'private_safety_check') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: private_safety_check not seeded off';
  END IF;
  -- The server refuses while the flag is off (sync_fixes_contracts); on
  -- for the rest of this file.
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('private_safety_check');
  -- C1: nothing a client can call depends on the partner's check.
  FOREACH v_fn IN ARRAY ARRAY['public.user_safety_flagged(uuid,uuid)', 'public.relationship_ai_suppressed(uuid)'] LOOP
    IF has_function_privilege('authenticated', v_fn, 'EXECUTE') OR has_function_privilege('anon', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must be service-role only', v_fn;
    END IF;
  END LOOP;
  IF to_regprocedure('public.relationship_conjoint_hidden(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a member-callable either-partner predicate exists (C1)';
  END IF;
  IF has_table_privilege('authenticated', 'public.safety_self_checks', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients read safety_self_checks directly';
  END IF;
  -- No answers column anywhere: nothing to leak (I1).
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'safety_self_checks'
             AND column_name IN ('answers', 'positive', 'q1', 'q2', 'q3', 'q4')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the check stores answers';
  END IF;

  -- A positive check: the card once, sticky (I2), and never visible to the client after.
  PERFORM pg_temp.as_user(v_a);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"no","q2":"yes","q3":"prefer_not","q4":"no"}');
  SELECT * INTO r FROM public.get_my_safety_check(v_rel);
  RESET ROLE;
  IF v_res->>'card' <> 'resources' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a positive check showed %', v_res; END IF;
  -- Only when it was answered and until when it holds; even "resources
  -- shown" would say it was once positive (stricter than review I1).
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(to_jsonb(r)) k) IS DISTINCT FROM ARRAY['answered_at', 'until'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_safety_check returns more than its two dates: %', to_jsonb(r);
  END IF;
  IF NOT public.user_safety_flagged(v_a, v_rel) OR public.user_safety_flagged(v_b, v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: user_safety_flagged';
  END IF;
  IF NOT public.relationship_ai_suppressed(v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a positive check did not suppress AI for the relationship';
  END IF;
  -- Final review C-1: the card is a function of the answers just given and
  -- nothing else. A "yes" on an already-positive row must look exactly like
  -- a "yes" on a fresh one, or the card tells whoever holds the phone that
  -- this person was positive before.
  PERFORM pg_temp.as_user(v_a);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"yes","q2":"no","q3":"no","q4":"no"}');
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"card": "resources"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a yes on a positive row gave % (C-1)', v_res;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
             AND table_name = 'safety_self_checks' AND column_name = 'resources_shown') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the row still remembers whether the card was shown';
  END IF;
  -- A coerced "no" four times clears nothing.
  PERFORM pg_temp.as_user(v_a);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"no","q2":"no","q3":"no","q4":"no"}');
  RESET ROLE;
  IF NOT public.user_safety_flagged(v_a, v_rel) OR v_res IS DISTINCT FROM '{"card": "none"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a later "no" cleared a positive check (I2): %', v_res;
  END IF;
  -- Expiry after 180 days.
  UPDATE public.safety_self_checks SET positive_until = now() - interval '1 minute', until = now() - interval '1 minute'
  WHERE user_id = v_a;
  IF public.user_safety_flagged(v_a, v_rel) OR public.relationship_ai_suppressed(v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired check still counts';
  END IF;
  -- ...and a yes on the expired row gives the same card as ever.
  PERFORM pg_temp.as_user(v_a);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"yes","q2":"no","q3":"no","q4":"no"}');
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"card": "resources"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a yes on an expired row gave %', v_res;
  END IF;
  UPDATE public.safety_self_checks SET positive_until = now() - interval '1 minute', until = now() - interval '1 minute'
  WHERE user_id = v_a;

  -- The partner: all "prefer not" shows the plain link (M1); nothing positive.
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.get_my_safety_check(v_rel);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"prefer_not","q2":"prefer_not","q3":"prefer_not","q4":"prefer_not"}');
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner sees a check before answering'; END IF;
  IF v_res->>'card' <> 'plain' OR public.user_safety_flagged(v_b, v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: prefer-not: %', v_res;
  END IF;

  -- Suppression also follows a safety event of any tier within 180 days (I10).
  INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
  VALUES (v_rel, v_a, 'spec8:test', 3, 'test', 'test');
  IF NOT public.relationship_ai_suppressed(v_rel) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a tier-3 event did not suppress'; END IF;
  UPDATE public.safety_events SET created_at = now() - interval '181 days' WHERE source_event_key = 'spec8:test';
  IF public.relationship_ai_suppressed(v_rel) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a 181-day-old event still suppresses'; END IF;

  -- Refused input; strangers.
  PERFORM pg_temp.as_user(v_a);
  BEGIN
    PERFORM public.submit_my_safety_check(v_rel, '{"q1":"maybe","q2":"no","q3":"no","q4":"no"}');
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an invalid answer was accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT; RESET ROLE;
    IF v_msg <> 'safety_check:invalid' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.as_user(v_c);
  BEGIN
    PERFORM public.submit_my_safety_check(v_rel, '{"q1":"no","q2":"no","q3":"no","q4":"no"}');
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger submitted a check';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT; RESET ROLE;
    IF v_msg <> 'safety_check:not_allowed' THEN RAISE; END IF;
  END;

  -- Final review m-9: the check is about the person, so a paused chapter
  -- still takes it; an ended one does not.
  UPDATE public.relationships SET status = 'paused' WHERE id = v_rel;
  PERFORM pg_temp.as_user(v_b);
  v_res := public.submit_my_safety_check(v_rel, '{"q1":"no","q2":"no","q3":"no","q4":"no"}');
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"card": "none"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: refused in a paused relationship: %', v_res;
  END IF;
  UPDATE public.relationships SET status = 'ended' WHERE id = v_rel;
  PERFORM pg_temp.as_user(v_b);
  BEGIN
    PERFORM public.submit_my_safety_check(v_rel, '{"q1":"no","q2":"no","q3":"no","q4":"no"}');
    RESET ROLE; RAISE EXCEPTION 'CONTRACT VIOLATED: an ended relationship took a check';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT; RESET ROLE;
    IF v_msg <> 'safety_check:not_allowed' THEN RAISE; END IF;
  END;

  -- I3: scoped to the relationship; goes with it.
  DELETE FROM public.relationships WHERE id = v_rel;
  IF EXISTS (SELECT 1 FROM public.safety_self_checks WHERE relationship_id = v_rel) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check outlived its relationship';
  END IF;
END $$;
DO $$ BEGIN RAISE NOTICE 'safety_self_check_contracts: all held'; END $$;
ROLLBACK;
