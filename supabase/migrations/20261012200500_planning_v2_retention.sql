-- Planning v2 retention (P1 Task 6). Spec §3.10.
-- Hard-deletes v2 rows soft-deleted more than 30 days ago, and applied
-- op ids older than 7 days. Bounded per run (20 batches x 5000 rows per
-- table) so one run can never hold locks for long; the next night
-- continues. Storage objects are not involved until P3 (plan ruling R1).

CREATE OR REPLACE FUNCTION public.planning_v2_purge()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cutoff timestamptz := now() - interval '30 days';
  v_items int := 0; v_blocks int := 0; v_entries int := 0; v_cats int := 0; v_ops int := 0;
  v_n int;
  v_i int;
BEGIN
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_block_items WHERE id IN (
      SELECT id FROM public.planning_block_items WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_items := v_items + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_blocks WHERE id IN (
      SELECT id FROM public.planning_blocks WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_blocks := v_blocks + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_entries WHERE id IN (
      SELECT id FROM public.planning_entries WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_entries := v_entries + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_categories WHERE id IN (
      SELECT id FROM public.planning_categories WHERE deleted_at < v_cutoff LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_cats := v_cats + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_applied_ops WHERE op_id IN (
      SELECT op_id FROM public.planning_applied_ops WHERE applied_at < now() - interval '7 days' LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_ops := v_ops + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  RETURN jsonb_build_object('items', v_items, 'blocks', v_blocks, 'entries', v_entries,
                            'categories', v_cats, 'ops', v_ops);
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_purge() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('planning_v2_purge', '17 3 * * *', $$SELECT public.planning_v2_purge()$$);
