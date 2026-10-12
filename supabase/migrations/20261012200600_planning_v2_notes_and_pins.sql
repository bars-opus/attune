-- Planning v2: a Notes starter (first, blank sheet), shared pins on entries,
-- and restore for an entry deleted by swipe (Undo).
-- Additive: no existing migration is edited.

-- ---- Notes starter ------------------------------------------------------

ALTER TABLE public.planning_categories DROP CONSTRAINT planning_categories_seed_key_check;
ALTER TABLE public.planning_categories ADD CONSTRAINT planning_categories_seed_key_check
  CHECK (seed_key IN ('notes','goals','trips','date_nights','home_bills','groceries','everyday'));

-- The notepad icon for Notes. The Dart mirror (planning_v2_ui.dart) is
-- compared with the newest definition of this function by a test.
CREATE OR REPLACE FUNCTION public.planning_v2_icons()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['flag','plane','heart','home','cart','sun','star','gift','book',
               'dumbbell','utensils','baby','ring','box','music','paw','note'];
$$;

-- Rank 0: Notes comes before every other starter. Its template is a single
-- empty text block — a blank sheet, with no template choice in the UI.
INSERT INTO public.planning_starter_templates (seed_key, version, name, icon, color, rank, template_title, blocks)
VALUES ('notes', 1, 'Notes', 'note', 'indigo', 0, 'New note',
        $j$[{"type":"text","payload":{"delta":[{"insert":"\n"}]}}]$j$);

-- Seeding no longer indexes planning_even_keys(6) by rank, which failed for
-- a seventh starter (final review M2). A missing starter is placed relative
-- to the couple's existing categories: ranked before all of their starters
-- -> top of the list; otherwise -> after the last category.
CREATE OR REPLACE FUNCTION public.planning_v2_ensure_starters(p_rel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s          public.planning_starter_templates;
  v_cat      uuid;
  v_tpl      public.planning_entries;
  v_new      uuid;
  v_key      text;
  v_min_rank int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(p_rel::text));
  FOR s IN SELECT * FROM public.planning_starter_templates ORDER BY rank LOOP
    SELECT id INTO v_cat FROM public.planning_categories
    WHERE relationship_id = p_rel AND seed_key = s.seed_key;
    IF NOT FOUND THEN
      SELECT min(t.rank) INTO v_min_rank
      FROM public.planning_categories c
      JOIN public.planning_starter_templates t ON t.seed_key = c.seed_key
      WHERE c.relationship_id = p_rel;
      IF v_min_rank IS NOT NULL AND s.rank < v_min_rank THEN
        v_key := public.planning_key_between(NULL,
          (SELECT min(sort_key) FROM public.planning_categories
           WHERE relationship_id = p_rel AND deleted_at IS NULL));
      ELSE
        v_key := public.planning_key_between(
          (SELECT max(sort_key) FROM public.planning_categories
           WHERE relationship_id = p_rel AND deleted_at IS NULL), NULL);
      END IF;
      v_cat := gen_random_uuid();
      INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
      VALUES (v_cat, p_rel, s.seed_key, s.name, s.icon, s.color, v_key);
      IF char_length(v_key) > 32 THEN PERFORM public.planning_v2_rebalance_categories(p_rel); END IF;
      v_new := gen_random_uuid();
      INSERT INTO public.planning_entries (id, relationship_id, category_id, is_template, seed_version, title)
      VALUES (v_new, p_rel, v_cat, true, s.version, s.template_title);
      PERFORM public.planning_v2_instantiate_blocks(p_rel, v_new, NULL, s.blocks);
    ELSE
      SELECT * INTO v_tpl FROM public.planning_entries
      WHERE category_id = v_cat AND is_template AND deleted_at IS NULL FOR UPDATE;
      IF FOUND AND v_tpl.seed_version IS NOT NULL AND v_tpl.seed_version < s.version THEN
        UPDATE public.planning_blocks SET deleted_at = now()
        WHERE entry_id = v_tpl.id AND deleted_at IS NULL;
        PERFORM public.planning_v2_instantiate_blocks(p_rel, v_tpl.id, NULL, s.blocks);
        UPDATE public.planning_entries SET seed_version = s.version, title = s.template_title
        WHERE id = v_tpl.id;
      END IF;
    END IF;
  END LOOP;
END;
$$;

-- ---- Pins ----------------------------------------------------------------

-- Shared by both partners, like everything else in Planning.
ALTER TABLE public.planning_entries ADD COLUMN pinned_at timestamptz;
ALTER TABLE public.planning_entries ADD CONSTRAINT planning_template_never_pinned
  CHECK (pinned_at IS NULL OR NOT is_template);
CREATE INDEX idx_planning_entries_pinned
  ON public.planning_entries (category_id, pinned_at DESC, id DESC)
  WHERE deleted_at IS NULL AND pinned_at IS NOT NULL;

-- Limits gain pinned_per_category (the Dart mirror is compared with the
-- newest definition of this function by a test).
CREATE OR REPLACE FUNCTION public.planning_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"categories":50,"blocks_per_entry":200,"items_per_block":500,"payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,"image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,"entries_page_max":100,"title_chars":120,"category_name_chars":40,"item_text_chars":500,"section_chars":40,"pinned_per_category":20}'::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_entry_object(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'category_id', e.category_id, 'category_name', c.name,
    'category_seed_key', c.seed_key, 'is_template', e.is_template, 'title', e.title,
    'status', e.status, 'currency', e.currency, 'cover_path', e.cover_path,
    'pinned_at', e.pinned_at,
    'last_activity_at', e.last_activity_at, 'created_at', e.created_at, 'updated_at', e.updated_at)
  FROM public.planning_entries e JOIN public.planning_categories c ON c.id = e.category_id
  WHERE e.id = p_entry_id;
$$;

-- One list row: title, status, first date, checklist progress, pin.
CREATE OR REPLACE FUNCTION public.planning_v2_entry_summary(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'title', e.title, 'status', e.status, 'last_activity_at', e.last_activity_at,
    'pinned', e.pinned_at IS NOT NULL,
    'date_start', d.date_start, 'date_end', d.date_end,
    'checklist_done', coalesce(cl.done, 0), 'checklist_total', coalesce(cl.total, 0))
  FROM public.planning_entries e
  LEFT JOIN LATERAL (
    SELECT b.date_start, b.date_end FROM public.planning_blocks b
    WHERE b.entry_id = e.id AND b.deleted_at IS NULL AND b.block_type = 'date' AND b.date_start IS NOT NULL
    ORDER BY b.sort_key, b.id LIMIT 1) d ON true
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE i.checked_at IS NOT NULL) AS done, count(*) AS total
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
    WHERE b.entry_id = e.id AND b.block_type = 'checklist' AND b.deleted_at IS NULL AND i.deleted_at IS NULL) cl ON true
  WHERE e.id = p_entry_id;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_entry_summary(uuid) FROM PUBLIC, anon, authenticated;

-- Pinned entries come back in their own `pinned` group on the first page
-- only (at most pinned_per_category of them), and never in the keyset-paged
-- `entries` stream, so paging stays exact.
CREATE OR REPLACE FUNCTION public.list_planning_entries(
  p_category_id uuid, p_group text, p_cursor_at timestamptz, p_cursor_id uuid, p_limit int
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel     uuid;
  v_limit   int := greatest(1, least(coalesce(p_limit, 30), 100));
  v_entries jsonb;
  v_next    jsonb := 'null'::jsonb;
  v_pinned  jsonb := '[]'::jsonb;
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
    SELECT e.id, e.last_activity_at,
           row_number() OVER (ORDER BY e.last_activity_at DESC, e.id DESC) AS rn
    FROM public.planning_entries e
    WHERE e.category_id = p_category_id AND NOT e.is_template AND e.deleted_at IS NULL
      AND e.pinned_at IS NULL
      AND ((p_group = 'open' AND e.status = 'active')
        OR (p_group = 'closed' AND e.status IN ('done', 'archived')))
      AND (p_cursor_at IS NULL OR (e.last_activity_at, e.id) < (p_cursor_at, p_cursor_id))
    ORDER BY e.last_activity_at DESC, e.id DESC
    LIMIT v_limit + 1
  )
  SELECT
    coalesce(jsonb_agg(public.planning_v2_entry_summary(p.id) ORDER BY p.rn) FILTER (WHERE p.rn <= v_limit), '[]'::jsonb),
    CASE WHEN max(p.rn) > v_limit THEN
      (SELECT jsonb_build_object('at', q.last_activity_at, 'id', q.id) FROM page q WHERE q.rn = v_limit)
    ELSE 'null'::jsonb END
  INTO v_entries, v_next
  FROM page p;

  IF p_cursor_at IS NULL THEN
    SELECT coalesce(jsonb_agg(public.planning_v2_entry_summary(e.id) ORDER BY e.pinned_at DESC, e.id DESC), '[]'::jsonb)
      INTO v_pinned
    FROM (
      SELECT id, pinned_at FROM public.planning_entries
      WHERE category_id = p_category_id AND NOT is_template AND deleted_at IS NULL
        AND pinned_at IS NOT NULL
        AND ((p_group = 'open' AND status = 'active')
          OR (p_group = 'closed' AND status IN ('done', 'archived')))
      ORDER BY pinned_at DESC, id DESC
      LIMIT 20
    ) e;
  END IF;

  RETURN jsonb_build_object('entries', v_entries, 'pinned', v_pinned,
                            'next_cursor', coalesce(v_next, 'null'::jsonb));
END;
$$;

-- Lock order category -> entry (as everywhere). The category row lock also
-- serializes the pin count, so two partners cannot both take the 20th pin.
CREATE OR REPLACE FUNCTION public.pin_planning_entry(p_id uuid, p_pinned boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel    uuid;
  v_cat_id uuid;
  v_row    public.planning_entries;
  v_count  int;
BEGIN
  IF p_pinned IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"pinned"}'); END IF;
  SELECT relationship_id, category_id INTO v_rel, v_cat_id
  FROM public.planning_entries WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  PERFORM 1 FROM public.planning_categories WHERE id = v_cat_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM public.planning_categories WHERE id = v_cat_id AND deleted_at IS NULL) THEN
    PERFORM public.planning_v2_fail('not_found');
  END IF;
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;

  IF p_pinned AND v_row.pinned_at IS NULL THEN
    SELECT count(*) INTO v_count FROM public.planning_entries
    WHERE category_id = v_cat_id AND NOT is_template AND deleted_at IS NULL AND pinned_at IS NOT NULL;
    IF v_count >= 20 THEN
      PERFORM public.planning_v2_fail('limit_reached', '{"limit":"pinned_per_category"}');
    END IF;
    UPDATE public.planning_entries SET pinned_at = clock_timestamp() WHERE id = p_id;
  ELSIF NOT p_pinned AND v_row.pinned_at IS NOT NULL THEN
    UPDATE public.planning_entries SET pinned_at = NULL WHERE id = p_id;
  END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_id));
END;
$$;

-- Undo for a swipe-delete: brings back the entry and exactly the blocks and
-- items that delete_planning_entry removed (they share its deleted_at),
-- never ones the couple deleted earlier on their own. A pin that no longer
-- fits under the 20-pin cap is dropped, so the plan returns to the list
-- instead of falling outside both the pinned group and the paged list
-- (review I1). The category row is locked FOR UPDATE, as in
-- pin_planning_entry, so the cap is counted under the same lock.
CREATE OR REPLACE FUNCTION public.restore_planning_entry(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rel    uuid;
  v_cat_id uuid;
  v_actor  uuid;
  v_row    public.planning_entries;
BEGIN
  SELECT relationship_id, category_id INTO v_rel, v_cat_id
  FROM public.planning_entries WHERE id = p_id AND deleted_at IS NOT NULL AND NOT is_template;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  PERFORM 1 FROM public.planning_categories WHERE id = v_cat_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM public.planning_categories WHERE id = v_cat_id AND deleted_at IS NULL) THEN
    PERFORM public.planning_v2_fail('not_found');
  END IF;
  SELECT * INTO v_row FROM public.planning_entries WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.pinned_at IS NOT NULL AND (
       SELECT count(*) FROM public.planning_entries
       WHERE category_id = v_cat_id AND NOT is_template AND deleted_at IS NULL AND pinned_at IS NOT NULL) >= 20 THEN
    UPDATE public.planning_entries SET pinned_at = NULL WHERE id = p_id;
  END IF;

  UPDATE public.planning_block_items SET deleted_at = NULL
  WHERE deleted_at = v_row.deleted_at
    AND block_id IN (SELECT id FROM public.planning_blocks WHERE entry_id = p_id);
  UPDATE public.planning_blocks SET deleted_at = NULL
  WHERE entry_id = p_id AND deleted_at = v_row.deleted_at;
  UPDATE public.planning_entries SET deleted_at = NULL WHERE id = p_id;
  PERFORM public.planning_v2_touch_entry(p_id, v_actor);
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_id));
END;
$$;

REVOKE ALL ON FUNCTION public.pin_planning_entry(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.restore_planning_entry(uuid)      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_planning_entry(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_planning_entry(uuid)      TO authenticated;
