-- Planning v2 blocks and items (P1 Task 5). Spec §3.3, §3.4, §6.1, §6.2, §6.4, §7.2.
-- Every mutation locks the ENTRY row first (FOR UPDATE). That single
-- lock serializes all writes inside one entry, which (a) gives the
-- fixed category -> entry -> block -> item order with no cycles, and
-- (b) makes block/item counts for limit checks exact.

CREATE OR REPLACE FUNCTION public.planning_v2_item_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
    'checked_at', i.checked_at, 'checked_by', i.checked_by,
    'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version)
  FROM public.planning_block_items i WHERE i.id = p_id;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_block_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', b.id, 'block_type', b.block_type, 'sort_key', b.sort_key,
    'payload', b.payload, 'plain_text', b.plain_text,
    'date_start', b.date_start, 'date_end', b.date_end,
    'version', b.version, 'updated_at', b.updated_at,
    'items', coalesce((
      SELECT jsonb_agg(public.planning_v2_item_object(i.id) ORDER BY i.sort_key, i.id)
      FROM public.planning_block_items i WHERE i.block_id = b.id AND i.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_blocks b WHERE b.id = p_id;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_item_object(uuid)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_block_object(uuid) FROM PUBLIC, anon, authenticated;

-- Resolves an entry for writing: membership, then FOR UPDATE, then liveness.
CREATE OR REPLACE FUNCTION public.planning_v2_lock_entry(p_entry_id uuid)
RETURNS public.planning_entries LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_entries;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_entry_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_entry_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_lock_entry(uuid) FROM PUBLIC, anon, authenticated;

-- ---- blocks -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_planning_block(
  p_id uuid, p_entry_id uuid, p_block_type text, p_payload jsonb,
  p_date_start date, p_date_end date, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry public.planning_entries := public.planning_v2_lock_entry(p_entry_id);
  v_actor uuid := auth.uid();
  v_row   public.planning_blocks;
  v_plain text;
  v_count int;
BEGIN
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id;
  IF FOUND THEN
    IF v_row.entry_id = p_entry_id AND v_row.block_type = p_block_type AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_block_object(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  v_plain := public.planning_v2_validate_block(p_block_type, coalesce(p_payload, '{}'::jsonb), p_date_start, p_date_end);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = p_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;

  INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
                                      payload, plain_text, date_start, date_end)
  VALUES (p_id, v_entry.relationship_id, p_entry_id, v_actor, p_block_type,
          public.planning_v2_key_after_block(p_entry_id, p_after_id, p_id),
          coalesce(p_payload, '{}'::jsonb), v_plain, p_date_start, p_date_end)
  RETURNING * INTO v_row;
  IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_blocks(p_entry_id); END IF;
  PERFORM public.planning_v2_touch_entry(p_entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_block(
  p_id uuid, p_version int, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry_id uuid;
  v_entry    public.planning_entries;
  v_row      public.planning_blocks;
  v_plain    text;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS DISTINCT FROM v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version',
      jsonb_build_object('current', public.planning_v2_block_object(p_id)));
  END IF;
  v_plain := public.planning_v2_validate_block(v_row.block_type, coalesce(p_payload, '{}'::jsonb), p_date_start, p_date_end);
  UPDATE public.planning_blocks
     SET payload = coalesce(p_payload, '{}'::jsonb), plain_text = v_plain,
         date_start = p_date_start, date_end = p_date_end, version = version + 1
   WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  -- Items keep their own deleted_at NULL: restoring the block restores
  -- them with it. Retention purges them by cascade when the block goes.
  UPDATE public.planning_blocks SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_count int;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = v_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;
  UPDATE public.planning_blocks SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_block(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_key text;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  v_key := public.planning_v2_key_after_block(v_entry_id, p_after_id, p_id);
  UPDATE public.planning_blocks SET sort_key = v_key WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF char_length(v_key) > 32 THEN PERFORM public.planning_v2_rebalance_blocks(v_entry_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- ---- items --------------------------------------------------------------

-- Resolves a LIVE item's block and entry, locks the entry. Returns the block.
CREATE OR REPLACE FUNCTION public.planning_v2_lock_block(p_block_id uuid)
RETURNS public.planning_blocks LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_block public.planning_blocks;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_block_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_lock_entry(v_entry_id);
  SELECT * INTO v_block FROM public.planning_blocks WHERE id = p_block_id FOR UPDATE;
  IF v_block.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  RETURN v_block;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_lock_block(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.add_planning_block_item(
  p_id uuid, p_block_id uuid, p_text text, p_section text,
  p_assigned_to uuid, p_due_date date, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_actor uuid := auth.uid();
  v_row   public.planning_block_items;
  v_count int;
BEGIN
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id;
  IF FOUND THEN
    IF v_row.block_id = p_block_id AND v_row.text = btrim(p_text) AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_item_object(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  PERFORM public.planning_v2_validate_item(v_block.block_type, v_block.relationship_id, p_text, p_section, p_assigned_to);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = p_block_id AND deleted_at IS NULL;
  IF v_count >= 500 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"items_per_block"}'); END IF;

  INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key,
                                           text, section, assigned_to, due_date)
  VALUES (p_id, v_block.relationship_id, p_block_id, v_actor,
          public.planning_v2_key_after_item(p_block_id, p_after_id, p_id),
          btrim(p_text), nullif(btrim(p_section), ''), p_assigned_to, p_due_date)
  RETURNING * INTO v_row;
  IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(p_block_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_block_item(
  p_id uuid, p_version int, p_text text, p_section text, p_assigned_to uuid, p_due_date date
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_row public.planning_block_items;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS DISTINCT FROM v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version',
      jsonb_build_object('current', public.planning_v2_item_object(p_id)));
  END IF;
  PERFORM public.planning_v2_validate_item(v_block.block_type, v_block.relationship_id, p_text, p_section, p_assigned_to);
  UPDATE public.planning_block_items
     SET text = btrim(p_text), section = nullif(btrim(p_section), ''),
         assigned_to = p_assigned_to, due_date = p_due_date, version = version + 1
   WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

-- Idempotent by p_op_id (plan ruling R7): an op already applied returns
-- the item unchanged. Ticking a ticked item keeps the original tick.
CREATE OR REPLACE FUNCTION public.set_planning_block_item_checked(p_id uuid, p_checked boolean, p_op_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_actor uuid;
BEGIN
  IF p_op_id IS NULL OR p_checked IS NULL THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"op_id"}');
  END IF;
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_actor := auth.uid();
  INSERT INTO public.planning_applied_ops (op_id, relationship_id) VALUES (p_op_id, v_block.relationship_id)
  ON CONFLICT (op_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN public.planning_v2_item_object(p_id);
  END IF;
  UPDATE public.planning_block_items
     SET checked_at = CASE WHEN p_checked THEN coalesce(checked_at, clock_timestamp()) ELSE NULL END,
         checked_by = CASE WHEN p_checked THEN coalesce(checked_by, v_actor) ELSE NULL END,
         version = version + 1
   WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  UPDATE public.planning_block_items SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_count int;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = v_block_id AND deleted_at IS NULL;
  IF v_count >= 500 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"items_per_block"}'); END IF;
  UPDATE public.planning_block_items SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_block_item(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_key text;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_key := public.planning_v2_key_after_item(v_block_id, p_after_id, p_id);
  UPDATE public.planning_block_items SET sort_key = v_key WHERE id = p_id AND deleted_at IS NULL;
  IF char_length(v_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(v_block_id); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

REVOKE ALL ON FUNCTION public.add_planning_block(uuid, uuid, text, jsonb, date, date, uuid)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_block(uuid, int, jsonb, date, date)                    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_block(uuid)                                            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_planning_block(uuid)                                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_block(uuid, uuid)                                        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.add_planning_block_item(uuid, uuid, text, text, uuid, date, uuid)      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_block_item(uuid, int, text, text, uuid, date)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_block_item_checked(uuid, boolean, uuid)                   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_block_item(uuid)                                       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_planning_block_item(uuid)                                      FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_block_item(uuid, uuid)                                   FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_planning_block(uuid, uuid, text, jsonb, date, date, uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_block(uuid, int, jsonb, date, date)               TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_block(uuid)                                       TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_planning_block(uuid)                                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_block(uuid, uuid)                                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_planning_block_item(uuid, uuid, text, text, uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_block_item(uuid, int, text, text, uuid, date)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_block_item_checked(uuid, boolean, uuid)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_block_item(uuid)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_planning_block_item(uuid)                                 TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_block_item(uuid, uuid)                              TO authenticated;
