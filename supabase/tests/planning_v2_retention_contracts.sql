-- Planning v2 retention contracts (P1 Task 6). Spec §3.10.
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2f100000-0000-0000-0000-000000000001';
  v_a uuid := '2f100000-0000-0000-0000-0000000000a1';
  v_b uuid := '2f100000-0000-0000-0000-0000000000b1';
  v_cat uuid;
  v_old uuid := '2f100000-0000-0000-0000-00000000e001';
  v_new uuid := '2f100000-0000-0000-0000-00000000e002';
  v_r jsonb;
  v_n int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2r_a@t.test'),(v_b,'v2r_b@t.test') ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES (v_a,'+12600000001','A'),(v_b,'+12600000002','B') ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES (v_rel, v_a, v_b, 'active') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  PERFORM public.get_planning_home(v_rel);
  SELECT id INTO v_cat FROM public.planning_categories WHERE relationship_id = v_rel AND seed_key = 'trips';
  PERFORM public.create_planning_entry(v_old, v_cat, 'Old', true, 'USD');
  PERFORM public.create_planning_entry(v_new, v_cat, 'Recent', true, 'USD');
  PERFORM public.delete_planning_entry(v_old);
  PERFORM public.delete_planning_entry(v_new);
  UPDATE public.planning_entries SET deleted_at = now() - interval '31 days' WHERE id = v_old;
  UPDATE public.planning_blocks  SET deleted_at = now() - interval '31 days' WHERE entry_id = v_old;
  UPDATE public.planning_block_items SET deleted_at = now() - interval '31 days'
  WHERE block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_old);
  INSERT INTO public.planning_applied_ops (op_id, relationship_id, applied_at)
  VALUES (gen_random_uuid(), v_rel, now() - interval '8 days'), (gen_random_uuid(), v_rel, now());

  v_r := public.planning_v2_purge();

  -- Contract 1: rows deleted > 30 days ago are gone; recent soft-deletes stay.
  IF EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_old) THEN RAISE EXCEPTION 'EXPLOIT: old entry kept'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_entries WHERE id = v_new) THEN RAISE EXCEPTION 'EXPLOIT: recent entry purged'; END IF;
  SELECT count(*) INTO v_n FROM public.planning_blocks WHERE entry_id = v_old;
  IF v_n <> 0 THEN RAISE EXCEPTION 'EXPLOIT: old blocks kept'; END IF;
  IF (v_r ->> 'entries')::int <> 1 THEN RAISE EXCEPTION 'EXPLOIT: purge count wrong: %', v_r; END IF;

  -- Contract 2: ops older than 7 days pruned, recent ones kept.
  SELECT count(*) INTO v_n FROM public.planning_applied_ops WHERE relationship_id = v_rel;
  IF v_n <> 1 THEN RAISE EXCEPTION 'EXPLOIT: ops prune wrong (% left)', v_n; END IF;

  -- Contract 3: live data and starters untouched.
  SELECT count(*) INTO v_n FROM public.planning_categories WHERE relationship_id = v_rel;
  IF v_n <> 6 THEN RAISE EXCEPTION 'EXPLOIT: purge touched categories'; END IF;

  -- Contract 4: the job is scheduled and the function is not client-callable.
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'planning_v2_purge') THEN
    RAISE EXCEPTION 'EXPLOIT: purge job not scheduled';
  END IF;
  IF has_function_privilege('authenticated', 'public.planning_v2_purge()', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: purge callable by clients';
  END IF;

  RAISE NOTICE 'planning_v2_retention_contracts: PASS';
END $$;
ROLLBACK;
