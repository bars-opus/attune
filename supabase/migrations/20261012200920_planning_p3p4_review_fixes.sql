-- Planning P3/P4 final-review fixes (I1, I3, I5, I7).

-- ---- I5: a settle is a snapshot of the net, not a cut-off on line age ------------

-- Net "Partner A is owed" per currency over every live, paid line.
ALTER TABLE public.planning_entries ADD COLUMN split_settled_net jsonb;

CREATE FUNCTION public.planning_v2_split_net(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH e AS (SELECT * FROM public.planning_entries WHERE id = p_entry_id),
  m AS (SELECT r.user_a FROM public.relationships r JOIN e ON e.relationship_id = r.id)
  SELECT coalesce(jsonb_object_agg(x.currency, x.net), '{}'::jsonb) FROM (
    SELECT i.currency,
           sum(CASE WHEN i.paid_by = m.user_a THEN 1 ELSE -1 END
               * coalesce(i.split_share_minor, i.amount_minor / 2)) AS net
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id, e, m
    WHERE b.entry_id = e.id AND b.block_type = 'expenses' AND b.deleted_at IS NULL
      AND i.deleted_at IS NULL AND i.paid_by IS NOT NULL AND i.amount_minor IS NOT NULL
    GROUP BY i.currency) x;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_split_net(uuid) FROM PUBLIC, anon, authenticated;

-- What is still to even out: the net now minus the net at the last settle.
-- Money entered after settling counts on any line, old or new; an equal
-- split of an odd amount still leaves the extra unit with the payer.
CREATE OR REPLACE FUNCTION public.planning_v2_split_balances(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH e AS (SELECT * FROM public.planning_entries WHERE id = p_entry_id),
  m AS (SELECT r.user_a, r.user_b FROM public.relationships r JOIN e ON e.relationship_id = r.id),
  now_net AS (SELECT key AS currency, value::text::numeric AS net FROM jsonb_each(public.planning_v2_split_net(p_entry_id))),
  base AS (SELECT key AS currency, value::text::numeric AS net FROM e, jsonb_each(coalesce(e.split_settled_net, '{}'::jsonb))),
  net AS (SELECT coalesce(n.currency, b.currency) AS currency, coalesce(n.net, 0) - coalesce(b.net, 0) AS a_is_owed
          FROM now_net n FULL JOIN base b ON b.currency = n.currency)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'currency', net.currency, 'minor', abs(net.a_is_owed),
           'owed_to', CASE WHEN net.a_is_owed > 0 THEN m.user_a ELSE m.user_b END,
           'owed_by', CASE WHEN net.a_is_owed > 0 THEN m.user_b ELSE m.user_a END)
         ORDER BY net.currency), '[]'::jsonb)
  FROM net, m WHERE net.a_is_owed <> 0;
$$;

CREATE OR REPLACE FUNCTION public.settle_planning_split(p_entry_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries;
BEGIN
  v_entry := public.planning_v2_lock_entry(p_entry_id);
  IF NOT v_entry.split_enabled THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"split"}'); END IF;
  PERFORM public.planning_v2_audit_expense(v_entry.relationship_id, p_entry_id, NULL, 'settle',
    jsonb_build_object('balances', public.planning_v2_split_balances(p_entry_id)),
    jsonb_build_object('net', public.planning_v2_split_net(p_entry_id)));
  UPDATE public.planning_entries
     SET split_settled_at = clock_timestamp(), split_settled_net = public.planning_v2_split_net(p_entry_id)
   WHERE id = p_entry_id;
  PERFORM public.planning_v2_touch_entry(p_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_entry_id));
END;
$$;

-- ---- I7: deleting or restoring a whole plan records its expense lines -----------

-- Plan delete/restore and category delete mark the lines first, then the
-- plan; this fires on the plan and records each line that moved with it.
CREATE FUNCTION public.planning_v2_audit_entry_lines()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.is_template THEN RETURN NEW; END IF;
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    PERFORM public.planning_v2_audit_expense(NEW.relationship_id, NEW.id, i.id, 'delete',
              public.planning_v2_item_object(i.id), NULL)
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = NEW.id AND b.block_type = 'expenses' AND i.deleted_at = NEW.deleted_at;
  ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    PERFORM public.planning_v2_audit_expense(NEW.relationship_id, NEW.id, i.id, 'restore',
              NULL, public.planning_v2_item_object(i.id))
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = NEW.id AND b.block_type = 'expenses' AND b.deleted_at IS NULL AND i.deleted_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_audit_entry_lines() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER planning_entries_audit_lines
  AFTER UPDATE OF deleted_at ON public.planning_entries
  FOR EACH ROW WHEN (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
  EXECUTE FUNCTION public.planning_v2_audit_entry_lines();

-- ---- I1 + I7: copies start a new occasion, and their expense lines are recorded -----

CREATE OR REPLACE FUNCTION public.planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_b       public.planning_blocks;
  v_new     uuid;
  v_payload jsonb;
  v_map     jsonb := '{}'::jsonb;
  v_ref     text;
  v_checks  text[];
  v_tpl     boolean := (SELECT is_template FROM public.planning_entries WHERE id = p_dst);
BEGIN
  FOR v_b IN SELECT * FROM public.planning_blocks
             WHERE entry_id = p_src AND deleted_at IS NULL ORDER BY sort_key, id LOOP
    v_new := gen_random_uuid();
    v_map := v_map || jsonb_build_object(v_b.id::text, v_new::text);
    v_payload := v_b.payload;
    IF v_b.block_type = 'photo' THEN v_payload := v_payload || '{"paths":[]}'::jsonb; END IF;
    IF v_b.block_type = 'link' AND v_payload ? 'preview' THEN
      v_payload := jsonb_set(v_payload, '{preview}', (v_payload -> 'preview') - 'image_path');
    END IF;
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
      payload, plain_text, date_start, date_end, target_minor, target_currency)
    VALUES (v_new, p_rel, p_dst, p_actor, v_b.block_type, v_b.sort_key,
      v_payload, v_b.plain_text, v_b.date_start, v_b.date_end, v_b.target_minor, v_b.target_currency);
    -- Contributions belong to the occasion they were made for.
    CONTINUE WHEN v_b.block_type = 'progress';
    -- So do yes/no cells ("Paid ✓"); the rest of a row is the plan's shape.
    v_checks := CASE WHEN v_b.block_type = 'table' THEN ARRAY(
                  SELECT c ->> 'key' FROM jsonb_array_elements(v_b.payload -> 'columns') c WHERE c ->> 'type' = 'check')
                ELSE '{}'::text[] END;
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells)
    SELECT gen_random_uuid(), p_rel, v_new, p_actor, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end,
      CASE WHEN cells IS NULL THEN NULL ELSE cells - v_checks END
    FROM public.planning_block_items WHERE block_id = v_b.id AND deleted_at IS NULL;
    IF v_b.block_type = 'expenses' AND NOT v_tpl THEN
      PERFORM public.planning_v2_audit_expense(p_rel, p_dst, i.id, 'create', NULL, public.planning_v2_item_object(i.id))
      FROM public.planning_block_items i WHERE i.block_id = v_new;
    END IF;
  END LOOP;
  FOREACH v_ref IN ARRAY ARRAY['date_block_id', 'checklist_block_id'] LOOP
    UPDATE public.planning_blocks d
       SET payload = CASE WHEN v_map ? (d.payload ->> v_ref)
                          THEN jsonb_set(d.payload, ARRAY[v_ref], v_map -> (d.payload ->> v_ref))
                          ELSE d.payload - v_ref END
     WHERE d.entry_id = p_dst AND d.payload ? v_ref;
  END LOOP;
END;
$$;

-- ---- I3: a column whose type changes or that is removed takes its cells with it -----

CREATE OR REPLACE FUNCTION public.update_planning_block(
  p_id uuid, p_version int, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry_id uuid;
  v_entry    public.planning_entries;
  v_row      public.planning_blocks;
  v_plain    text;
  v_payload  jsonb := coalesce(p_payload, '{}'::jsonb);
  v_stale    text[];
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
  IF v_row.block_type = 'photo' THEN
    v_payload := (v_payload - 'paths') || jsonb_build_object('paths', coalesce(v_row.payload -> 'paths', '[]'::jsonb));
  ELSIF v_row.block_type = 'date' THEN
    v_payload := v_payload - 'poll_history';
    IF v_row.payload ? 'poll_history' THEN
      v_payload := v_payload || jsonb_build_object('poll_history', v_row.payload -> 'poll_history');
    END IF;
  ELSIF v_row.block_type = 'link' THEN
    v_payload := v_payload - 'preview';
    IF (v_payload ->> 'url') IS NOT DISTINCT FROM (v_row.payload ->> 'url') THEN
      IF v_row.payload ? 'preview' THEN
        v_payload := v_payload || jsonb_build_object('preview', v_row.payload -> 'preview');
      END IF;
    ELSIF v_row.payload -> 'preview' ->> 'image_path' IS NOT NULL THEN
      PERFORM public.queue_media_deletion('planning-media', v_row.payload -> 'preview' ->> 'image_path');
    END IF;
  END IF;
  v_plain := public.planning_v2_validate_block(v_row.block_type, v_payload, p_date_start, p_date_end);
  IF v_row.block_type = 'table' THEN
    SELECT array_agg(o ->> 'key') INTO v_stale FROM jsonb_array_elements(v_row.payload -> 'columns') o
    WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_payload -> 'columns') n
                      WHERE n ->> 'key' = o ->> 'key' AND n ->> 'type' = o ->> 'type');
    IF v_stale IS NOT NULL THEN
      -- Deleted rows too, so an Undo can't bring stale values back.
      UPDATE public.planning_block_items SET cells = cells - v_stale, version = version + 1
      WHERE block_id = p_id AND cells ?| v_stale;
    END IF;
  END IF;
  UPDATE public.planning_blocks
     SET payload = v_payload, plain_text = v_plain,
         date_start = p_date_start, date_end = p_date_end, version = version + 1
   WHERE id = p_id;
  IF v_row.block_type = 'progress' THEN PERFORM public.planning_v2_maybe_celebrate(v_entry_id, auth.uid()); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;
