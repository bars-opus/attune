-- Planning v2 categories, starters, ordering helpers (P1 Task 3).
-- Spec §4, §4.1, §5; plan rulings R3, R5, R6.

-- Versioned starter definitions (plan ruling R5). P1 uses only text /
-- checklist / date blocks; P3 and P4 bump `version` with richer blocks,
-- and unedited seeded templates upgrade on the next home read.
CREATE TABLE public.planning_starter_templates (
  seed_key       text PRIMARY KEY,
  version        int  NOT NULL CHECK (version >= 1),
  name           text NOT NULL,
  icon           text NOT NULL,
  color          text NOT NULL,
  rank           int  NOT NULL UNIQUE,
  template_title text NOT NULL,
  blocks         jsonb NOT NULL CHECK (jsonb_typeof(blocks) = 'array')
);
ALTER TABLE public.planning_starter_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_starter_templates FROM PUBLIC, anon, authenticated;

INSERT INTO public.planning_starter_templates (seed_key, version, name, icon, color, rank, template_title, blocks) VALUES
('goals', 1, 'Goals', 'flag', 'rose', 1, 'New goal', $j$[
  {"type":"date","payload":{"title":"Target date"}},
  {"type":"text","payload":{"delta":[{"insert":"Why this matters to us"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"checklist","payload":{"title":"Steps"}}
]$j$),
('trips', 1, 'Trips', 'plane', 'teal', 2, 'New trip', $j$[
  {"type":"date","payload":{"title":"Trip dates"}},
  {"type":"text","payload":{"delta":[{"insert":"Destination & ideas"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"checklist","payload":{"title":"Packing"},"items":[{"text":"Passports"},{"text":"Chargers"},{"text":"Toiletries"}]},
  {"type":"text","payload":{"delta":[{"insert":"Notes"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('date_nights', 1, 'Date nights', 'heart', 'violet', 3, 'New date night', $j$[
  {"type":"date","payload":{"title":"When"}},
  {"type":"text","payload":{"delta":[{"insert":"The plan"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}},
  {"type":"text","payload":{"delta":[{"insert":"What we loved"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('home_bills', 1, 'Home & bills', 'home', 'amber', 4, 'This month', $j$[
  {"type":"checklist","payload":{"title":"Bills"},"items":[{"text":"Rent"},{"text":"Electricity"},{"text":"Water"},{"text":"Internet"},{"text":"TV"}]},
  {"type":"text","payload":{"delta":[{"insert":"Notes"},{"insert":"\n","attributes":{"header":2}},{"insert":"\n"}]}}
]$j$),
('groceries', 1, 'Groceries', 'cart', 'green', 5, 'Shopping run', $j$[
  {"type":"checklist","payload":{"title":"Shopping list"},"items":[
    {"text":"Tomatoes","section":"Produce"},{"text":"Onions","section":"Produce"},
    {"text":"Milk","section":"Dairy"},{"text":"Eggs","section":"Dairy"},
    {"text":"Chicken","section":"Meat & fish"},
    {"text":"Rice","section":"Pantry"},
    {"text":"Soap","section":"Household"}]}
]$j$),
('everyday', 1, 'Everyday', 'sun', 'slate', 6, 'New note', $j$[
  {"type":"text","payload":{"delta":[{"insert":"\n"}]}}
]$j$);

-- ---- ordering helpers --------------------------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_category(p_rel uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_categories
    WHERE id = p_after_id AND relationship_id = p_rel AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_categories
  WHERE relationship_id = p_rel AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_block(p_entry uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_blocks
    WHERE id = p_after_id AND entry_id = p_entry AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_blocks
  WHERE entry_id = p_entry AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_key_after_item(p_block uuid, p_after_id uuid, p_exclude uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_lo text; v_hi text;
BEGIN
  IF p_after_id IS NOT NULL THEN
    IF p_after_id = p_exclude THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
    SELECT sort_key INTO v_lo FROM public.planning_block_items
    WHERE id = p_after_id AND block_id = p_block AND deleted_at IS NULL;
    IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"after_id"}'); END IF;
  END IF;
  SELECT min(sort_key) INTO v_hi FROM public.planning_block_items
  WHERE block_id = p_block AND deleted_at IS NULL AND id IS DISTINCT FROM p_exclude
    AND (v_lo IS NULL OR sort_key > v_lo);
  RETURN public.planning_key_between(v_lo, v_hi);
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_categories(p_rel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_categories
                                       WHERE relationship_id = p_rel AND deleted_at IS NULL));
  UPDATE public.planning_categories c SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_categories WHERE relationship_id = p_rel AND deleted_at IS NULL) o
  WHERE c.id = o.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_blocks(p_entry uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_blocks
                                       WHERE entry_id = p_entry AND deleted_at IS NULL));
  UPDATE public.planning_blocks b SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_blocks WHERE entry_id = p_entry AND deleted_at IS NULL) o
  WHERE b.id = o.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.planning_v2_rebalance_items(p_block uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_keys text[];
BEGIN
  v_keys := public.planning_even_keys((SELECT count(*)::int FROM public.planning_block_items
                                       WHERE block_id = p_block AND deleted_at IS NULL));
  UPDATE public.planning_block_items i SET sort_key = v_keys[o.rn]
  FROM (SELECT id, row_number() OVER (ORDER BY sort_key, id) AS rn
        FROM public.planning_block_items WHERE block_id = p_block AND deleted_at IS NULL) o
  WHERE i.id = o.id;
END;
$$;

-- ---- block instantiation / copy / touch ---------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_instantiate_blocks(
  p_rel uuid, p_entry_id uuid, p_actor uuid, p_blocks jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_def   jsonb;
  v_ord   bigint;
  v_keys  text[];
  v_ikeys text[];
  v_block uuid;
  v_item  jsonb;
  v_iord  bigint;
  v_plain text;
BEGIN
  v_keys := public.planning_even_keys(jsonb_array_length(p_blocks));
  FOR v_def, v_ord IN SELECT value, ordinality FROM jsonb_array_elements(p_blocks) WITH ORDINALITY LOOP
    v_block := gen_random_uuid();
    v_plain := public.planning_v2_validate_block(v_def ->> 'type', coalesce(v_def -> 'payload', '{}'::jsonb), NULL, NULL);
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key, payload, plain_text)
    VALUES (v_block, p_rel, p_entry_id, p_actor, v_def ->> 'type', v_keys[v_ord],
            coalesce(v_def -> 'payload', '{}'::jsonb), v_plain);
    IF jsonb_array_length(coalesce(v_def -> 'items', '[]'::jsonb)) > 0 THEN
      v_ikeys := public.planning_even_keys(jsonb_array_length(v_def -> 'items'));
      FOR v_item, v_iord IN SELECT value, ordinality FROM jsonb_array_elements(v_def -> 'items') WITH ORDINALITY LOOP
        INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section)
        VALUES (gen_random_uuid(), p_rel, v_block, p_actor, v_ikeys[v_iord], v_item ->> 'text', v_item ->> 'section');
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- Copies an entry's live blocks and items. Per spec §4, copies reset
-- per-occasion state: checked_at/checked_by and paid_by are not copied.
CREATE OR REPLACE FUNCTION public.planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_b public.planning_blocks; v_new uuid;
BEGIN
  FOR v_b IN SELECT * FROM public.planning_blocks
             WHERE entry_id = p_src AND deleted_at IS NULL ORDER BY sort_key, id LOOP
    v_new := gen_random_uuid();
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
      payload, plain_text, date_start, date_end, target_minor, target_currency)
    VALUES (v_new, p_rel, p_dst, p_actor, v_b.block_type, v_b.sort_key,
      v_b.payload, v_b.plain_text, v_b.date_start, v_b.date_end, v_b.target_minor, v_b.target_currency);
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells)
    SELECT gen_random_uuid(), p_rel, v_new, p_actor, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells
    FROM public.planning_block_items WHERE block_id = v_b.id AND deleted_at IS NULL;
  END LOOP;
END;
$$;

-- Records activity for the "new" dot, and marks a template as edited
-- (seed_version NULL) so it never auto-upgrades over the couple's edits.
CREATE OR REPLACE FUNCTION public.planning_v2_touch_entry(p_entry_id uuid, p_actor uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.planning_entries
     SET last_activity_at = clock_timestamp(),
         last_activity_by = p_actor,
         seed_version = CASE WHEN is_template THEN NULL ELSE seed_version END
   WHERE id = p_entry_id;
$$;

-- Lazily seeds the six starters and upgrades unedited templates.
-- Serialized per couple, so two partners opening Planning at the same
-- moment produce one set (Review Focus 1).
CREATE OR REPLACE FUNCTION public.planning_v2_ensure_starters(p_rel uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s      public.planning_starter_templates;
  v_cat  uuid;
  v_tpl  public.planning_entries;
  v_new  uuid;
  v_keys text[] := public.planning_even_keys(6);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(p_rel::text));
  FOR s IN SELECT * FROM public.planning_starter_templates ORDER BY rank LOOP
    SELECT id INTO v_cat FROM public.planning_categories
    WHERE relationship_id = p_rel AND seed_key = s.seed_key;
    IF NOT FOUND THEN
      v_cat := gen_random_uuid();
      INSERT INTO public.planning_categories (id, relationship_id, seed_key, name, icon, color, sort_key)
      VALUES (v_cat, p_rel, s.seed_key, s.name, s.icon, s.color, v_keys[s.rank]);
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

REVOKE ALL ON FUNCTION public.planning_v2_key_after_category(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_key_after_block(uuid, uuid, uuid)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_key_after_item(uuid, uuid, uuid)     FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_categories(uuid)           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_blocks(uuid)               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_rebalance_items(uuid)                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_instantiate_blocks(uuid, uuid, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_copy_blocks(uuid, uuid, uuid, uuid)  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_touch_entry(uuid, uuid)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_ensure_starters(uuid)                FROM PUBLIC, anon, authenticated;

-- ---- public RPCs --------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_planning_home(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor  uuid := public.planning_v2_actor(p_relationship_id);
  v_result jsonb;
BEGIN
  PERFORM public.planning_v2_ensure_starters(p_relationship_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'seed_key', c.seed_key, 'name', c.name, 'icon', c.icon,
           'color', c.color, 'sort_key', c.sort_key, 'hidden', c.hidden_at IS NOT NULL,
           'template_entry_id', t.id,
           'entry_count', coalesce(e.cnt, 0),
           'has_new', coalesce(e.partner_at > coalesce(s.seen_at, '-infinity'::timestamptz), false)
         ) ORDER BY c.sort_key, c.id), '[]'::jsonb)
    INTO v_result
  FROM public.planning_categories c
  LEFT JOIN public.planning_entries t
         ON t.category_id = c.id AND t.is_template AND t.deleted_at IS NULL
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt,
           max(x.last_activity_at) FILTER (
             WHERE x.last_activity_by IS NOT NULL AND x.last_activity_by <> v_actor) AS partner_at
    FROM public.planning_entries x
    WHERE x.category_id = c.id AND NOT x.is_template AND x.deleted_at IS NULL
  ) e ON true
  LEFT JOIN public.planning_category_seen s ON s.category_id = c.id AND s.user_id = v_actor
  WHERE c.relationship_id = p_relationship_id AND c.deleted_at IS NULL
    AND (c.seed_key IS DISTINCT FROM 'everyday' OR coalesce(e.cnt, 0) > 0);
  RETURN jsonb_build_object('categories', v_result);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_planning_category(
  p_id uuid, p_relationship_id uuid, p_name text, p_icon text, p_color text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.planning_v2_actor(p_relationship_id);
  v_name  text := btrim(p_name);
  v_row   public.planning_categories;
  v_count int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(p_relationship_id::text));
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  IF FOUND THEN
    IF v_row.relationship_id = p_relationship_id AND v_row.deleted_at IS NULL
       AND v_row.name = v_name AND v_row.icon = p_icon AND v_row.color = p_color THEN
      RETURN to_jsonb(v_row);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"name"}');
  END IF;
  IF p_icon IS NULL OR NOT (p_icon = ANY (public.planning_v2_icons())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"icon"}');
  END IF;
  IF p_color IS NULL OR NOT (p_color = ANY (public.planning_v2_colors())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"color"}');
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_categories
  WHERE relationship_id = p_relationship_id AND deleted_at IS NULL;
  IF v_count >= 50 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"categories"}');
  END IF;

  INSERT INTO public.planning_categories (id, relationship_id, created_by, name, icon, color, sort_key)
  VALUES (p_id, p_relationship_id, v_actor, v_name, p_icon, p_color,
          public.planning_key_between(
            (SELECT max(sort_key) FROM public.planning_categories
             WHERE relationship_id = p_relationship_id AND deleted_at IS NULL), NULL))
  RETURNING * INTO v_row;
  INSERT INTO public.planning_entries (id, relationship_id, category_id, created_by, is_template, title, last_activity_by)
  VALUES (gen_random_uuid(), p_relationship_id, p_id, v_actor, true, v_name, v_actor);
  IF char_length(v_row.sort_key) > 32 THEN
    PERFORM public.planning_v2_rebalance_categories(p_relationship_id);
    SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  END IF;
  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_planning_category(p_id uuid, p_name text, p_icon text, p_color text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories; v_name text := btrim(p_name);
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"name"}');
  END IF;
  IF p_icon IS NULL OR NOT (p_icon = ANY (public.planning_v2_icons())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"icon"}');
  END IF;
  IF p_color IS NULL OR NOT (p_color = ANY (public.planning_v2_colors())) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"color"}');
  END IF;
  UPDATE public.planning_categories SET name = v_name, icon = p_icon, color = p_color
  WHERE id = p_id RETURNING * INTO v_row;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_planning_category_hidden(p_id uuid, p_hidden boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  UPDATE public.planning_categories
     SET hidden_at = CASE WHEN p_hidden THEN coalesce(hidden_at, now()) ELSE NULL END
   WHERE id = p_id AND deleted_at IS NULL RETURNING * INTO v_row;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_planning_category(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories; v_n int; v_now timestamptz := now();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.seed_key IS NOT NULL THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"starter"}');
  END IF;
  -- Lock order is category -> entry -> block -> item. Every block and item
  -- RPC locks its ENTRY first, so take the entries here before touching any
  -- block or item row; updating items/blocks first deadlocked against a
  -- partner's concurrent save (final review I1).
  PERFORM 1 FROM public.planning_entries WHERE category_id = p_id ORDER BY id FOR UPDATE;
  SELECT count(*) INTO v_n FROM public.planning_entries
  WHERE category_id = p_id AND NOT is_template AND deleted_at IS NULL;
  UPDATE public.planning_block_items SET deleted_at = v_now
  WHERE deleted_at IS NULL AND block_id IN (
    SELECT b.id FROM public.planning_blocks b JOIN public.planning_entries e ON e.id = b.entry_id
    WHERE e.category_id = p_id);
  UPDATE public.planning_blocks SET deleted_at = v_now
  WHERE deleted_at IS NULL AND entry_id IN (SELECT id FROM public.planning_entries WHERE category_id = p_id);
  UPDATE public.planning_entries SET deleted_at = v_now WHERE category_id = p_id AND deleted_at IS NULL;
  UPDATE public.planning_categories SET deleted_at = v_now WHERE id = p_id;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN jsonb_build_object('deleted_entries', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.move_planning_category(p_id uuid, p_after_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_row public.planning_categories;
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_rel);
  PERFORM pg_advisory_xact_lock(hashtext('planning_v2_categories'), hashtext(v_rel::text));
  UPDATE public.planning_categories
     SET sort_key = public.planning_v2_key_after_category(v_rel, p_after_id, p_id)
   WHERE id = p_id AND deleted_at IS NULL RETURNING * INTO v_row;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF char_length(v_row.sort_key) > 32 THEN
    PERFORM public.planning_v2_rebalance_categories(v_rel);
    SELECT * INTO v_row FROM public.planning_categories WHERE id = p_id;
  END IF;
  PERFORM public.bump_planning_signal(v_rel);
  RETURN to_jsonb(v_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_planning_category_seen(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_actor uuid; v_at timestamptz := clock_timestamp();
BEGIN
  SELECT relationship_id INTO v_rel FROM public.planning_categories WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_actor := public.planning_v2_actor(v_rel);
  INSERT INTO public.planning_category_seen (category_id, relationship_id, user_id, seen_at)
  VALUES (p_id, v_rel, v_actor, v_at)
  ON CONFLICT (category_id, user_id) DO UPDATE SET seen_at = EXCLUDED.seen_at;
  RETURN jsonb_build_object('seen_at', v_at);
END;
$$;

REVOKE ALL ON FUNCTION public.get_planning_home(uuid)                               FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_planning_category(uuid, uuid, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_category(uuid, text, text, text)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_category_hidden(uuid, boolean)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_planning_category(uuid)                         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.move_planning_category(uuid, uuid)                     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_planning_category_seen(uuid)                      FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_home(uuid)                               TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_planning_category(uuid, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_category(uuid, text, text, text)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_category_hidden(uuid, boolean)            TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_planning_category(uuid)                         TO authenticated;
GRANT EXECUTE ON FUNCTION public.move_planning_category(uuid, uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_planning_category_seen(uuid)                      TO authenticated;
