-- supabase/tests/quiet_state_contracts.sql
-- Spec 7 (B9, A9; plan review C1, M3): a private, per-user quiet state.
-- "Having a hard time" or "Going through a loss", 14 days, ended at will;
-- the once-only line is offered once per activation; nobody else can read
-- or probe it.
BEGIN;
INSERT INTO auth.users (id) VALUES ('9fa00000-0000-0000-0000-0000000000a1'), ('9fa00000-0000-0000-0000-0000000000b2')
ON CONFLICT (id) DO NOTHING;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

DO $$
DECLARE
  v_a uuid := '9fa00000-0000-0000-0000-0000000000a1';
  v_b uuid := '9fa00000-0000-0000-0000-0000000000b2';
  r record; v_n int; v_msg text; v_fn text;
BEGIN
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'quiet_states') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: quiet_states flag not seeded off';
  END IF;
  -- The server refuses while the flag is off (sync_fixes_contracts); on
  -- for the rest of this file.
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('quiet_states');
  -- C1: nobody can probe someone else's state.
  IF has_function_privilege('authenticated', 'public.user_is_quiet(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.user_is_quiet(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can ask whether someone is quiet';
  END IF;
  IF has_table_privilege('authenticated', 'public.quiet_states', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients read quiet_states directly';
  END IF;
  FOREACH v_fn IN ARRAY ARRAY['public.set_my_quiet_state(text)', 'public.end_my_quiet_state()',
                              'public.get_my_quiet_state()', 'public.mark_quiet_line_offered()'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: grants on %', v_fn;
    END IF;
  END LOOP;

  PERFORM pg_temp.as_user(v_a);
  PERFORM public.set_my_quiet_state('hard_time');
  SELECT * INTO r FROM public.get_my_quiet_state();
  RESET ROLE;
  IF r.kind <> 'hard_time' OR r.line_offered OR r.until NOT BETWEEN now() + interval '14 days' - interval '1 minute'
                                                         AND now() + interval '14 days' + interval '1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new quiet state: %', row_to_json(r);
  END IF;
  IF NOT public.user_is_quiet(v_a) OR public.user_is_quiet(v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: user_is_quiet';
  END IF;

  -- The partner sees nothing of it.
  PERFORM pg_temp.as_user(v_b);
  SELECT count(*) INTO v_n FROM public.get_my_quiet_state();
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner reads the quiet state'; END IF;

  -- Offered once per activation: switching kind keeps it; a new activation resets it (M3).
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.mark_quiet_line_offered();
  PERFORM public.set_my_quiet_state('loss');
  SELECT * INTO r FROM public.get_my_quiet_state();
  RESET ROLE;
  IF r.kind <> 'loss' OR NOT r.line_offered THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: switching kind re-offered the line or kept the kind: %', row_to_json(r);
  END IF;
  -- Final review M-1: switching kind keeps the end date.
  UPDATE public.quiet_states SET until = now() + interval '4 days' WHERE user_id = v_a;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.set_my_quiet_state('hard_time');
  SELECT * INTO r FROM public.get_my_quiet_state();
  RESET ROLE;
  IF r.until > now() + interval '4 days' + interval '1 minute' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: switching kind extended the quiet state (M-1): %', r.until;
  END IF;

  -- Ended at will.
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.end_my_quiet_state();
  SELECT count(*) INTO v_n FROM public.get_my_quiet_state();
  RESET ROLE;
  IF v_n <> 0 OR public.user_is_quiet(v_a) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ending did not end it'; END IF;

  -- It runs out on its own; the next activation offers the line again.
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.set_my_quiet_state('hard_time');
  PERFORM public.mark_quiet_line_offered();
  RESET ROLE;
  UPDATE public.quiet_states SET until = now() - interval '1 minute' WHERE user_id = v_a;
  IF public.user_is_quiet(v_a) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an expired state still counts'; END IF;
  PERFORM pg_temp.as_user(v_a);
  SELECT count(*) INTO v_n FROM public.get_my_quiet_state();
  PERFORM public.set_my_quiet_state('hard_time');
  SELECT * INTO r FROM public.get_my_quiet_state();
  RESET ROLE;
  IF v_n <> 0 OR r.line_offered THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expiry: % / %', v_n, row_to_json(r); END IF;

  PERFORM pg_temp.as_user(v_a);
  BEGIN
    PERFORM public.set_my_quiet_state('cheerful');
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown kind was accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    RESET ROLE;
    IF v_msg <> 'quiet:invalid' THEN RAISE; END IF;
  END;
END $$;
DO $$ BEGIN RAISE NOTICE 'quiet_state_contracts: all held'; END $$;
ROLLBACK;
