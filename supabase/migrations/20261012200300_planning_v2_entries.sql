-- Planning v2 entries (P1 Task 4). Spec §4, §5; plan ruling R2.

CREATE OR REPLACE FUNCTION public.planning_v2_entry_object(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'category_id', e.category_id, 'category_name', c.name,
    'category_seed_key', c.seed_key, 'is_template', e.is_template, 'title', e.title,
    'status', e.status, 'currency', e.currency, 'cover_path', e.cover_path,
    'last_activity_at', e.last_activity_at, 'created_at', e.created_at, 'updated_at', e.updated_at)
  FROM public.planning_entries e JOIN public.planning_categories c ON c.id = e.category_id
  WHERE e.id = p_entry_id;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_entry_detail(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'entry', public.planning_v2_entry_object(e.id),
    'members', (
      SELECT jsonb_agg(jsonb_build_object('id', u.id, 'display_name', u.display_name) ORDER BY u.id)
      FROM public.relationships r JOIN public.users u ON u.id IN (r.user_a, r.user_b)
      WHERE r.id = e.relationship_id),
    'blocks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', b.id, 'block_type', b.block_type, 'sort_key', b.sort_key,
               'payload', b.payload, 'plain_text', b.plain_text,
               'date_start', b.date_start, 'date_end', b.date_end,
               'version', b.version, 'updated_at', b.updated_at,
               'items', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                          'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
                          'checked_at', i.checked_at, 'checked_by', i.checked_by,
                          'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version)
                        ORDER BY i.sort_key, i.id)
                 FROM public.planning_block_items i
                 WHERE i.block_id = b.id AND i.deleted_at IS NULL), '[]'::jsonb))
             ORDER BY b.sort_key, b.id)
      FROM public.planning_blocks b
      WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_entries e WHERE e.id = p_entry_id;
$$;

REVOKE ALL ON FUNCTION public.planning_v2_entry_object(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_entry_detail(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_entry(
  p_id uuid, p_category_id uuid, p_title text, p_use_template boolean, p_currency text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_cat   public.planning_categories;
  v_row   public.planning_entries;
  v_tpl   uuid;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  -- FOR SHARE, not just the FK's implicit KEY SHARE: delete_planning_category
  -- updates a non-key column (deleted_at), which KEY SHARE does not block.
  SELECT * INTO v_cat FROM public.planning_categories WHERE id = p_category_id FOR SHARE;
  IF v_cat.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;

  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id;
  IF FOUND THEN
    IF v_row.relationship_id = v_rel AND v_row.category_id = p_category_id
       AND v_row.title = v_title AND v_row.deleted_at IS NULL AND NOT v_row.is_template THEN
      RETURN public.planning_v2_entry_detail(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"currency"}');
  END IF;

  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, title, currency,
                                       last_activity_at, last_activity_by)
  VALUES (p_id, v_rel, p_category_id, v_actor, v_title, p_currency, clock_timestamp(), v_actor);
  IF coalesce(p_use_template, false) THEN
    SELECT id INTO v_tpl FROM public.planning_entries
    WHERE category_id = p_category_id AND is_template AND deleted_at IS NULL;
    IF v_tpl IS NOT NULL THEN
      PERFORM public.planning_v2_copy_blocks(v_rel, v_tpl, p_id, v_actor);
    END IF;
  END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.duplicate_planning_entry(p_source_id uuid, p_new_id uuid, p_title text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_src   public.planning_entries;
  v_row   public.planning_entries;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_source_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_src FROM public.planning_entries WHERE id = p_source_id FOR SHARE;
  IF v_src.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_src.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;
  PERFORM 1 FROM public.planning_categories WHERE id = v_src.category_id AND deleted_at IS NULL FOR SHARE;

  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_new_id;
  IF FOUND THEN
    IF v_row.relationship_id = v_rel AND v_row.category_id = v_src.category_id
       AND v_row.title = v_title AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_entry_detail(p_new_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;

  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, title, currency,
                                       cover_path, last_activity_at, last_activity_by)
  VALUES (p_new_id, v_rel, v_src.category_id, v_actor, v_title, v_src.currency,
          v_src.cover_path, clock_timestamp(), v_actor);
  PERFORM public.planning_v2_copy_blocks(v_rel, p_source_id, p_new_id, v_actor);
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(p_new_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_entry(p_id uuid, p_title text, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_row   public.planning_entries;
  v_title text := btrim(p_title);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_title IS NULL OR char_length(v_title) NOT BETWEEN 1 AND 120 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('active','done','archived')
     OR (v_row.is_template AND p_status <> 'active') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"status"}');
  END IF;
  UPDATE public.planning_entries SET title = v_title, status = p_status WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(p_id, v_actor);
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_entries; v_now timestamptz := now();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;
  UPDATE public.planning_block_items SET deleted_at = v_now
  WHERE deleted_at IS NULL AND block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = p_id);
  UPDATE public.planning_blocks SET deleted_at = v_now WHERE entry_id = p_id AND deleted_at IS NULL;
  UPDATE public.planning_entries SET deleted_at = v_now WHERE id = p_id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  RETURN public.planning_v2_entry_detail(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.list_planning_entries(
  p_category_id uuid, p_group text, p_cursor_at timestamptz, p_cursor_id uuid, p_limit int
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel     uuid;
  v_limit   int := greatest(1, least(coalesce(p_limit, 30), 100));
  v_entries jsonb;
  v_next    jsonb := 'null'::jsonb;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  IF p_group IS NULL OR p_group NOT IN ('open', 'closed') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"group"}');
  END IF;
  IF (p_cursor_at IS NULL) <> (p_cursor_id IS NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"cursor"}');
  END IF;

  WITH page AS (
    SELECT e.id, e.title, e.status, e.last_activity_at,
           row_number() OVER (ORDER BY e.last_activity_at DESC, e.id DESC) AS rn
    FROM public.planning_entries e
    WHERE e.category_id = p_category_id AND NOT e.is_template AND e.deleted_at IS NULL
      AND ((p_group = 'open' AND e.status = 'active')
        OR (p_group = 'closed' AND e.status IN ('done', 'archived')))
      AND (p_cursor_at IS NULL OR (e.last_activity_at, e.id) < (p_cursor_at, p_cursor_id))
    ORDER BY e.last_activity_at DESC, e.id DESC
    LIMIT v_limit + 1
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'title', p.title, 'status', p.status, 'last_activity_at', p.last_activity_at,
      'date_start', d.date_start, 'date_end', d.date_end,
      'checklist_done', coalesce(cl.done, 0), 'checklist_total', coalesce(cl.total, 0))
      ORDER BY p.rn) FILTER (WHERE p.rn <= v_limit), '[]'::jsonb),
    CASE WHEN max(p.rn) > v_limit THEN
      (SELECT jsonb_build_object('at', q.last_activity_at, 'id', q.id) FROM page q WHERE q.rn = v_limit)
    ELSE 'null'::jsonb END
  INTO v_entries, v_next
  FROM page p
  LEFT JOIN LATERAL (
    SELECT b.date_start, b.date_end FROM public.planning_blocks b
    WHERE b.entry_id = p.id AND b.deleted_at IS NULL AND b.block_type = 'date' AND b.date_start IS NOT NULL
    ORDER BY b.sort_key, b.id LIMIT 1) d ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE i.checked_at IS NOT NULL) AS done, count(*) AS total
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = p.id AND b.block_type = 'checklist' AND b.deleted_at IS NULL AND i.deleted_at IS NULL) cl ON true;

  RETURN jsonb_build_object('entries', v_entries, 'next_cursor', coalesce(v_next, 'null'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_planning_template(p_category_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel   uuid;
  v_actor uuid;
  v_cat   public.planning_categories;
  v_tpl   public.planning_entries;
  s       public.planning_starter_templates;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_category_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  SELECT * INTO v_cat FROM public.planning_categories WHERE id = p_category_id FOR SHARE;
  IF v_cat.seed_key IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"starter"}'); END IF;
  SELECT * INTO s FROM public.planning_starter_templates WHERE seed_key = v_cat.seed_key;
  SELECT * INTO v_tpl FROM public.planning_entries
  WHERE category_id = p_category_id AND is_template AND deleted_at IS NULL FOR UPDATE;
  UPDATE public.planning_block_items SET deleted_at = now()
  WHERE deleted_at IS NULL AND block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = v_tpl.id);
  UPDATE public.planning_blocks SET deleted_at = now() WHERE entry_id = v_tpl.id AND deleted_at IS NULL;
  PERFORM public.planning_v2_instantiate_blocks(v_rel, v_tpl.id, v_actor, s.blocks);
  UPDATE public.planning_entries
     SET seed_version = s.version, title = s.template_title,
         last_activity_at = clock_timestamp(), last_activity_by = v_actor
   WHERE id = v_tpl.id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN public.planning_v2_entry_detail(v_tpl.id);
END;
$$;

REVOKE ALL ON FUNCTION public.create_planning_entry(uuid, uuid, text, boolean, text)              FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.duplicate_planning_entry(uuid, uuid, text)                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_entry(uuid, text, text)                            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_entry(uuid)                                        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_planning_entry(uuid)                                           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_planning_entries(uuid, text, timestamptz, uuid, int)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reset_planning_template(uuid)                                      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_entry(uuid, uuid, text, boolean, text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.duplicate_planning_entry(uuid, uuid, text)                TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_entry(uuid, text, text)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_entry(uuid)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_planning_entry(uuid)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_planning_entries(uuid, text, timestamptz, uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_planning_template(uuid)                             TO authenticated;
