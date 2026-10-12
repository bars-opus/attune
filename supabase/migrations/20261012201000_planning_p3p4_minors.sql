-- Planning P3/P4 deferred minors (final review M2, M4, M6, M7, M9).

-- ---- M7: a whole number, or false — never NULL, never a cast error ---------------
CREATE OR REPLACE FUNCTION public.planning_v2_is_int(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN jsonb_typeof(p) = 'number'
              THEN (p #>> '{}')::numeric = trunc((p #>> '{}')::numeric)
              ELSE false END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rich_item_fields(p_block public.planning_blocks, p_fields jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cell    record;
  v_type    text;
  v_ok      boolean;
  v_amount  numeric;
  v_share   numeric;
  v_paid_by uuid;
  v_cur     text;
  v_start   date;
  v_end     date;
BEGIN
  IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"fields"}');
  END IF;
  CASE p_block.block_type
  WHEN 'table' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['cells'])
       OR jsonb_typeof(p_fields -> 'cells') IS DISTINCT FROM 'object'
       OR octet_length((p_fields -> 'cells')::text) > 4096 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"cells"}');
    END IF;
    FOR v_cell IN SELECT key, value FROM jsonb_each(p_fields -> 'cells') LOOP
      SELECT c ->> 'type' INTO v_type FROM jsonb_array_elements(p_block.payload -> 'columns') c
      WHERE c ->> 'key' = v_cell.key;
      IF v_type IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"cells"}'); END IF;
      -- Assigned first: PL/pgSQL ends an IF condition at the first THEN.
      v_ok := jsonb_typeof(v_cell.value) = 'null' OR CASE v_type
          WHEN 'text'   THEN jsonb_typeof(v_cell.value) = 'string' AND char_length(v_cell.value #>> '{}') <= 200
          WHEN 'number' THEN jsonb_typeof(v_cell.value) = 'number'
          WHEN 'money'  THEN public.planning_v2_is_int(v_cell.value) AND (v_cell.value #>> '{}')::numeric >= 0
          WHEN 'date'   THEN jsonb_typeof(v_cell.value) = 'string' AND (v_cell.value #>> '{}') ~ '^\d{4}-\d{2}-\d{2}$'
          WHEN 'check'  THEN jsonb_typeof(v_cell.value) = 'boolean'
          ELSE false END;
      IF NOT v_ok THEN
        PERFORM public.planning_v2_fail('invalid_input', jsonb_build_object('field', 'cells', 'column', v_cell.key));
      END IF;
      v_type := NULL;
    END LOOP;
    RETURN jsonb_build_object('cells', p_fields -> 'cells');
  WHEN 'expenses' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['label','amount_minor','currency','paid_by','split_share_minor'])
       OR char_length(btrim(coalesce(p_fields ->> 'label', ''))) NOT BETWEEN 1 AND 120
       OR NOT public.planning_v2_is_int(p_fields -> 'amount_minor') THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"expense"}');
    END IF;
    v_amount := (p_fields ->> 'amount_minor')::numeric;
    IF v_amount < 0 OR v_amount > 1000000000000 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    v_cur := coalesce(p_fields ->> 'currency',
      (SELECT currency FROM public.planning_entries WHERE id = p_block.entry_id));
    IF v_cur !~ '^[A-Z]{3}$' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"currency"}'); END IF;
    IF p_fields ? 'paid_by' AND jsonb_typeof(p_fields -> 'paid_by') <> 'null' THEN
      IF NOT public.planning_v2_is_uuid(p_fields -> 'paid_by') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"paid_by"}');
      END IF;
      v_paid_by := (p_fields ->> 'paid_by')::uuid;
      IF NOT public.planning_v2_is_member(p_block.relationship_id, v_paid_by) THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"paid_by"}');
      END IF;
    END IF;
    IF p_fields ? 'split_share_minor' AND jsonb_typeof(p_fields -> 'split_share_minor') <> 'null' THEN
      IF NOT public.planning_v2_is_int(p_fields -> 'split_share_minor') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"split_share_minor"}');
      END IF;
      v_share := (p_fields ->> 'split_share_minor')::numeric;
      IF v_share < 0 OR v_share > v_amount THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"split_share_minor"}');
      END IF;
    END IF;
    RETURN jsonb_build_object('text', btrim(p_fields ->> 'label'), 'amount_minor', v_amount::bigint,
      'currency', v_cur, 'paid_by', v_paid_by, 'split_share_minor', v_share::bigint);
  WHEN 'date_poll' THEN
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['date_start','date_end','label'])
       OR coalesce(p_fields ->> 'date_start', '') !~ '^\d{4}-\d{2}-\d{2}$'
       OR (p_fields ? 'date_end' AND jsonb_typeof(p_fields -> 'date_end') <> 'null'
           AND coalesce(p_fields ->> 'date_end', '') !~ '^\d{4}-\d{2}-\d{2}$')
       OR (p_fields ? 'label' AND char_length(coalesce(p_fields ->> 'label', '')) > 120) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    BEGIN
      v_start := (p_fields ->> 'date_start')::date;
      v_end := (p_fields ->> 'date_end')::date;
    EXCEPTION WHEN others THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END;
    IF v_end IS NOT NULL AND v_end < v_start THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN jsonb_build_object('date_start', v_start, 'date_end', v_end,
      'text', nullif(btrim(coalesce(p_fields ->> 'label', '')), ''));
  WHEN 'progress' THEN
    IF p_block.payload ->> 'mode' <> 'numeric' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"mode"}');
    END IF;
    IF NOT public.planning_v2_keys_within(p_fields, ARRAY['amount_minor','label'])
       OR NOT public.planning_v2_is_int(p_fields -> 'amount_minor')
       OR (p_fields ? 'label' AND char_length(coalesce(p_fields ->> 'label', '')) > 120) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    -- Cast only once it is known to be a whole number (M7).
    IF (p_fields ->> 'amount_minor')::numeric NOT BETWEEN 1 AND 1000000000000 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"amount_minor"}');
    END IF;
    RETURN jsonb_build_object('amount_minor', (p_fields ->> 'amount_minor')::bigint,
      'text', nullif(btrim(coalesce(p_fields ->> 'label', '')), ''));
  ELSE
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END CASE;
  RETURN NULL;
END;
$$;


-- ---- M2 ----
CREATE OR REPLACE FUNCTION public.restore_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_count int; v_limit record;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  -- A locked poll is a Date block now; its old options stay history (M2).
  IF v_block.block_type NOT IN ('checklist', 'table', 'expenses', 'date_poll', 'progress') THEN
    PERFORM public.planning_v2_fail('not_found');
  END IF;
  v_limit := public.planning_v2_item_limit(v_block.block_type);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = v_block_id AND deleted_at IS NULL;
  IF v_count >= v_limit.max_items THEN
    PERFORM public.planning_v2_fail('limit_reached', jsonb_build_object('limit', v_limit.limit_name));
  END IF;
  UPDATE public.planning_block_items SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  IF v_block.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_block.relationship_id, v_block.entry_id, p_id, 'restore',
              NULL, public.planning_v2_item_object(p_id));
  END IF;
  IF v_block.block_type = 'progress' THEN PERFORM public.planning_v2_maybe_celebrate(v_block.entry_id, auth.uid()); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;


-- ---- M9 ----
CREATE OR REPLACE FUNCTION public.set_planning_link_preview(p_block_id uuid, p_url text, p_preview jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block public.planning_blocks; v_clean jsonb; v_old text;
BEGIN
  SELECT * INTO v_block FROM public.planning_blocks WHERE id = p_block_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_block.block_type <> 'link' OR (v_block.payload ->> 'url') IS DISTINCT FROM p_url THEN
    RETURN false;
  END IF;
  v_clean := jsonb_strip_nulls(jsonb_build_object(
    'status', CASE WHEN p_preview ->> 'status' = 'ok' THEN 'ok' ELSE 'failed' END,
    'title', left(p_preview ->> 'title', 200),
    'description', left(p_preview ->> 'description', 500),
    'host', left(p_preview ->> 'host', 255),
    'image_path', CASE WHEN (p_preview ->> 'image_path') ~ ('^' || v_block.relationship_id || '/' || v_block.entry_id || '/[A-Za-z0-9._-]{1,100}$')
                       THEN p_preview ->> 'image_path' END,
    'fetched_at', now()));
  v_old := v_block.payload -> 'preview' ->> 'image_path';
  IF v_old IS NOT NULL AND v_old IS DISTINCT FROM v_clean ->> 'image_path' THEN
    PERFORM public.queue_media_deletion('planning-media', v_old);
  END IF;
  UPDATE public.planning_blocks
     -- No version bump: preview is server-owned and carried over by every
     -- client edit, so it must not make the couple's next edit stale (M9).
     SET payload = payload || jsonb_build_object('preview', v_clean)
   WHERE id = p_block_id;
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN true;
END;
$$;


-- ---- M4 ----
CREATE OR REPLACE FUNCTION public.planning_v2_purge()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cutoff timestamptz := now() - interval '30 days';
  v_items int := 0; v_blocks int := 0; v_entries int := 0; v_cats int := 0; v_ops int := 0;
  v_n int;
  v_i int;
BEGIN
  -- Queue photo and preview files of every block about to be purged
  -- (directly deleted, or deleted with its plan or category).
  PERFORM public.queue_media_deletion('planning-media', f)
  FROM public.planning_blocks b
  CROSS JOIN LATERAL (
    SELECT jsonb_array_elements_text(coalesce(b.payload -> 'paths', '[]'::jsonb)) AS f
    UNION ALL SELECT b.payload -> 'preview' ->> 'image_path') files
  WHERE b.deleted_at < v_cutoff AND files.f IS NOT NULL;

  -- Uploads nothing points at after a day: a photo whose attach failed, a
  -- preview image whose write lost a race (M4). Soft-deleted blocks still
  -- count as pointing, so an Undo never loses its file.
  PERFORM public.queue_media_deletion('planning-media', o.name)
  FROM storage.objects o
  WHERE o.bucket_id = 'planning-media' AND o.created_at < now() - interval '1 day'
    AND o.name NOT IN (
      SELECT r.name FROM (
        SELECT jsonb_array_elements_text(coalesce(payload -> 'paths', '[]'::jsonb)) AS name
        FROM public.planning_blocks WHERE block_type = 'photo'
        UNION
        SELECT payload -> 'preview' ->> 'image_path' FROM public.planning_blocks
        WHERE block_type = 'link' AND payload -> 'preview' ? 'image_path') r
      WHERE r.name IS NOT NULL);

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
  DELETE FROM public.planning_link_preview_requests WHERE requested_at < now() - interval '1 day';
  DELETE FROM public.planning_link_previews WHERE fetched_at < now() - interval '7 days';

  FOR v_i IN 1..20 LOOP
    DELETE FROM public.planning_applied_ops WHERE op_id IN (
      SELECT op_id FROM public.planning_applied_ops WHERE applied_at < now() - interval '7 days' LIMIT 5000);
    GET DIAGNOSTICS v_n = ROW_COUNT; v_ops := v_ops + v_n; EXIT WHEN v_n < 5000;
  END LOOP;
  RETURN jsonb_build_object('items', v_items, 'blocks', v_blocks, 'entries', v_entries,
                            'categories', v_cats, 'ops', v_ops);
END;
$$;


-- The bucket only ever holds the app's re-encoded JPEGs (photos, preview
-- images), each under 10 MB (spec §3.9). Hosted storage has these columns;
-- the local harness's stub does not.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'storage' AND table_name = 'buckets' AND column_name = 'file_size_limit') THEN
    EXECUTE $q$UPDATE storage.buckets SET file_size_limit = 10485760, allowed_mime_types = ARRAY['image/jpeg']
              WHERE id = 'planning-media'$q$;
  END IF;
END $$;

-- ---- M6: the money history can't be truncated or rewritten by any role ---------------
-- Privileges stay as every public table has them (service_role_grants_test:
-- workers must be able to read and update every table). The triggers are
-- what make this table append-only, for every role including the owner:
-- the row trigger refuses UPDATE and DELETE, this one refuses TRUNCATE.

CREATE FUNCTION public.planning_expense_events_no_truncate()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'planning_expense_events is append-only';
END;
$$;
REVOKE ALL ON FUNCTION public.planning_expense_events_no_truncate() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER planning_expense_events_no_truncate
  BEFORE TRUNCATE ON public.planning_expense_events
  FOR EACH STATEMENT EXECUTE FUNCTION public.planning_expense_events_no_truncate();

-- The row trigger's pg_trigger_depth() >= 2 exemption exists for the two
-- foreign-key cascades (relationship deleted -> rows removed; account
-- deleted -> actor set null). No trigger in this schema writes to the
-- audit table, so in practice those cascades are the only writers it admits.
COMMENT ON FUNCTION public.planning_expense_events_append_only() IS
  'Append-only guard; nested (depth >= 2) changes come only from FK cascades on relationships/auth.users.';
