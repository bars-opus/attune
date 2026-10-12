-- Planning P4: couple blocks — date poll, countdown, progress, dual clock
-- (spec §3.5, §4.1, §6.5, §6.6, §6.9, §6.13, §8). Also: per-member time
-- zones, the debounced poll push and the hourly countdown push, gallery
-- templates, and the starters' full block lists.
--
-- Blocks that point at other blocks (a countdown's Date, a progress
-- block's Checklist) store the id when the couple picks one; otherwise they
-- follow the plan's first Date / Checklist. Copies re-point the ids.

-- ---- Tables ------------------------------------------------------------------

-- A row = "works for me". Unvoting deletes it (votes carry no content).
CREATE TABLE public.planning_poll_votes (
  item_id         uuid NOT NULL,
  relationship_id uuid NOT NULL,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, user_id),
  CONSTRAINT planning_vote_item_same_relationship FOREIGN KEY (item_id, relationship_id)
    REFERENCES public.planning_block_items(id, relationship_id) ON DELETE CASCADE
);
ALTER TABLE public.planning_poll_votes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_poll_votes FROM PUBLIC, anon, authenticated;

-- The IANA zone each partner's device reports when Planning opens.
CREATE TABLE public.planning_member_settings (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  timezone        text NOT NULL CHECK (char_length(timezone) BETWEEN 1 AND 64),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (relationship_id, user_id)
);
ALTER TABLE public.planning_member_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_member_settings FROM PUBLIC, anon, authenticated;

-- Versioned gallery definitions (spec §4.1: data in a migration, not client code).
CREATE TABLE public.planning_gallery_templates (
  key            text PRIMARY KEY,
  version        int NOT NULL CHECK (version >= 1),
  rank           int NOT NULL UNIQUE,
  name           text NOT NULL,
  icon           text NOT NULL,
  color          text NOT NULL,
  description    text NOT NULL,
  blocks         jsonb NOT NULL CHECK (jsonb_typeof(blocks) = 'array')
);
ALTER TABLE public.planning_gallery_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_gallery_templates FROM PUBLIC, anon, authenticated;

-- The hourly countdown sweep reads only live countdowns.
CREATE INDEX idx_planning_blocks_countdown ON public.planning_blocks (entry_id)
  WHERE block_type = 'countdown' AND deleted_at IS NULL;

-- ---- Limits -------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.planning_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"categories":50,"blocks_per_entry":200,"items_per_block":500,"payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,"image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,"entries_page_max":100,"title_chars":120,"category_name_chars":40,"item_text_chars":500,"section_chars":40,"pinned_per_category":20,"poll_options":20}'::jsonb;
$$;

-- (limit, its name) for items in a block of this type.
CREATE FUNCTION public.planning_v2_item_limit(p_block_type text, OUT max_items int, OUT limit_name text)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_block_type WHEN 'table' THEN 50 WHEN 'date_poll' THEN 20 ELSE 500 END,
         CASE p_block_type WHEN 'table' THEN 'table_rows' WHEN 'date_poll' THEN 'poll_options' ELSE 'items_per_block' END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_item_limit(text) FROM PUBLIC, anon, authenticated;

-- ---- Validation (all 13 types) ---------------------------------------------------

CREATE FUNCTION public.planning_v2_is_uuid(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_typeof(p) = 'string'
     AND (p #>> '{}') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;
REVOKE ALL ON FUNCTION public.planning_v2_is_uuid(jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_validate_block(
  p_type text, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_col  jsonb;
  v_keys text[] := '{}';
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
  END IF;
  IF octet_length(p_payload::text) > 16384 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"payload_bytes"}');
  END IF;
  IF p_type <> 'date' AND (p_date_start IS NOT NULL OR p_date_end IS NOT NULL) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
  END IF;
  IF NOT public.planning_v2_title_ok(p_payload) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
  END IF;

  CASE p_type
  WHEN 'text' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['delta']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
    RETURN public.planning_validate_delta(p_payload -> 'delta');
  WHEN 'checklist', 'expenses', 'budget', 'date_poll', 'dual_clock' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
  WHEN 'date' THEN
    -- poll_history is written only by lock_planning_poll.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','poll_history'])
       OR (p_payload ? 'poll_history' AND (jsonb_typeof(p_payload -> 'poll_history') <> 'array'
           OR jsonb_array_length(p_payload -> 'poll_history') > 20)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
    IF p_date_end IS NOT NULL AND (p_date_start IS NULL OR p_date_end < p_date_start) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
  WHEN 'countdown' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','date_block_id'])
       OR (p_payload ? 'date_block_id' AND jsonb_typeof(p_payload -> 'date_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'date_block_id')) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date_block_id"}');
    END IF;
  WHEN 'progress' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','mode','unit','checklist_block_id'])
       OR coalesce(p_payload ->> 'mode', '') NOT IN ('numeric', 'checklist')
       OR coalesce(p_payload ->> 'unit', 'count') NOT IN ('count', 'money')
       OR (p_payload ? 'checklist_block_id' AND jsonb_typeof(p_payload -> 'checklist_block_id') <> 'null'
           AND NOT public.planning_v2_is_uuid(p_payload -> 'checklist_block_id')) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"progress"}');
    END IF;
  WHEN 'table' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','columns'])
       OR jsonb_typeof(p_payload -> 'columns') IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_payload -> 'columns') NOT BETWEEN 1 AND 12 THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"columns"}');
    END IF;
    FOR v_col IN SELECT value FROM jsonb_array_elements(p_payload -> 'columns') LOOP
      IF jsonb_typeof(v_col) <> 'object'
         OR NOT public.planning_v2_keys_within(v_col, ARRAY['key','label','type'])
         OR coalesce(v_col ->> 'key', '') !~ '^c[0-9]{1,2}$'
         OR (v_col ->> 'key') = ANY (v_keys)
         OR char_length(btrim(coalesce(v_col ->> 'label', ''))) NOT BETWEEN 1 AND 40
         OR coalesce(v_col ->> 'type', '') NOT IN ('text','number','money','date','check') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"columns"}');
      END IF;
      v_keys := v_keys || (v_col ->> 'key');
    END LOOP;
  WHEN 'photo' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','paths'])
       OR (p_payload ? 'paths' AND (jsonb_typeof(p_payload -> 'paths') <> 'array'
           OR jsonb_array_length(p_payload -> 'paths') > 10)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"paths"}');
    END IF;
  WHEN 'link' THEN
    -- A template's link has only a label until the couple adds the address.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['url','label','preview'])
       OR (p_payload ? 'url' AND (jsonb_typeof(p_payload -> 'url') <> 'string'
           OR char_length(p_payload ->> 'url') > 2048
           OR (p_payload ->> 'url') !~* '^https?://[^[:space:]]+$'))
       OR (p_payload ? 'label' AND char_length(btrim(coalesce(p_payload ->> 'label', ''))) NOT BETWEEN 1 AND 80) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"url"}');
    END IF;
  WHEN 'place' THEN
    -- A template's place has only a title until the couple picks one.
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title','name','address','lat','lng'])
       OR (p_payload ? 'name' AND char_length(btrim(coalesce(p_payload ->> 'name', ''))) NOT BETWEEN 1 AND 120)
       OR (NOT p_payload ? 'name' AND (p_payload ? 'address' OR p_payload ? 'lat' OR p_payload ? 'lng'))
       OR char_length(coalesce(p_payload ->> 'address', '')) > 300
       OR (p_payload ? 'lat' AND (jsonb_typeof(p_payload -> 'lat') <> 'number'
           OR (p_payload ->> 'lat')::numeric NOT BETWEEN -90 AND 90))
       OR (p_payload ? 'lng' AND (jsonb_typeof(p_payload -> 'lng') <> 'number'
           OR (p_payload ->> 'lng')::numeric NOT BETWEEN -180 AND 180)) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"place"}');
    END IF;
  ELSE
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END CASE;
  RETURN NULL;
END;
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
       OR (p_fields ->> 'amount_minor')::numeric NOT BETWEEN 1 AND 1000000000000
       OR (p_fields ? 'label' AND char_length(coalesce(p_fields ->> 'label', '')) > 120) THEN
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

-- ---- JSON shapes ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_item_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
    'checked_at', i.checked_at, 'checked_by', i.checked_by,
    'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version,
    'amount_minor', i.amount_minor, 'currency', i.currency, 'paid_by', i.paid_by,
    'split_share_minor', i.split_share_minor, 'cells', i.cells,
    'date_start', i.date_start, 'date_end', i.date_end, 'created_by', i.created_by,
    'votes', coalesce((SELECT jsonb_agg(v.user_id ORDER BY v.user_id)
                       FROM public.planning_poll_votes v WHERE v.item_id = i.id), '[]'::jsonb))
  FROM public.planning_block_items i WHERE i.id = p_id;
$$;

-- The Date block a countdown counts to: the one it names, if still live in
-- the same plan with a date; otherwise the plan's first dated Date block.
CREATE FUNCTION public.planning_v2_countdown_target(p_block public.planning_blocks)
RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT d.date_start FROM public.planning_blocks d
     WHERE public.planning_v2_is_uuid(p_block.payload -> 'date_block_id')
       AND d.id = (p_block.payload ->> 'date_block_id')::uuid
       AND d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL),
    (SELECT d.date_start FROM public.planning_blocks d
     WHERE d.entry_id = p_block.entry_id AND d.block_type = 'date' AND d.deleted_at IS NULL
       AND d.date_start IS NOT NULL
     ORDER BY d.sort_key, d.id LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_countdown_target(public.planning_blocks) FROM PUBLIC, anon, authenticated;

-- The checklist a checklist-mode progress block follows (same rule).
CREATE FUNCTION public.planning_v2_progress_checklist(p_block public.planning_blocks)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT c.id FROM public.planning_blocks c
     WHERE public.planning_v2_is_uuid(p_block.payload -> 'checklist_block_id')
       AND c.id = (p_block.payload ->> 'checklist_block_id')::uuid
       AND c.entry_id = p_block.entry_id AND c.block_type = 'checklist' AND c.deleted_at IS NULL),
    (SELECT c.id FROM public.planning_blocks c
     WHERE c.entry_id = p_block.entry_id AND c.block_type = 'checklist' AND c.deleted_at IS NULL
     ORDER BY c.sort_key, c.id LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_progress_checklist(public.planning_blocks) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_block_computed(p_block public.planning_blocks)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE p_block.block_type
  WHEN 'budget' THEN (
    WITH spent AS (
      SELECT i.currency, sum(i.amount_minor) AS minor
      FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id
      WHERE b.entry_id = p_block.entry_id AND b.block_type = 'expenses' AND b.deleted_at IS NULL
        AND i.deleted_at IS NULL AND i.amount_minor IS NOT NULL
      GROUP BY i.currency)
    SELECT jsonb_build_object(
      'spent_minor', coalesce((SELECT minor FROM spent WHERE currency = p_block.target_currency), 0),
      'other_currencies', coalesce((
        SELECT jsonb_agg(jsonb_build_object('currency', currency, 'minor', minor) ORDER BY currency)
        FROM spent WHERE currency IS DISTINCT FROM p_block.target_currency), '[]'::jsonb)))
  WHEN 'countdown' THEN jsonb_build_object('target_date', public.planning_v2_countdown_target(p_block))
  WHEN 'progress' THEN
    CASE WHEN p_block.payload ->> 'mode' = 'checklist' THEN (
      SELECT jsonb_build_object('mode', 'checklist',
               'done', count(*) FILTER (WHERE i.checked_at IS NOT NULL), 'total', count(*))
      FROM public.planning_block_items i
      WHERE i.block_id = public.planning_v2_progress_checklist(p_block) AND i.deleted_at IS NULL)
    ELSE (
      SELECT jsonb_build_object('mode', 'numeric', 'current', coalesce(sum(i.amount_minor), 0))
      FROM public.planning_block_items i WHERE i.block_id = p_block.id AND i.deleted_at IS NULL)
    END
  ELSE NULL END;
$$;

-- ---- Celebration (spec §8.3) ------------------------------------------------------

-- The first time any Progress block in a Goals plan reaches 100%, one chat
-- system notice, guarded by planning_entries.celebrated_at. Callers hold
-- the entry lock.
CREATE FUNCTION public.planning_v2_maybe_celebrate(p_entry_id uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries; v_seed text;
BEGIN
  SELECT * INTO v_entry FROM public.planning_entries WHERE id = p_entry_id;
  SELECT seed_key INTO v_seed FROM public.planning_categories WHERE id = v_entry.category_id;
  IF v_entry.id IS NULL OR v_entry.celebrated_at IS NOT NULL OR v_entry.is_template OR v_seed IS DISTINCT FROM 'goals'
     OR p_actor IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_blocks b, LATERAL (SELECT public.planning_v2_block_computed(b) AS c) x
    WHERE b.entry_id = p_entry_id AND b.block_type = 'progress' AND b.deleted_at IS NULL
      AND CASE WHEN x.c ->> 'mode' = 'checklist'
               THEN (x.c ->> 'total')::int > 0 AND (x.c ->> 'done')::int = (x.c ->> 'total')::int
               ELSE coalesce(b.target_minor, 0) > 0 AND (x.c ->> 'current')::bigint >= b.target_minor END) THEN
    RETURN;
  END IF;
  INSERT INTO public.messages (id, relationship_id, sender_id, client_message_id, content,
                               is_system_notice, message_analysis_skipped, source, created_at)
  VALUES (gen_random_uuid(), v_entry.relationship_id, p_actor, gen_random_uuid(),
          '🎉 Goal reached: ' || v_entry.title, true, true, 'native', clock_timestamp());
  UPDATE public.planning_entries SET celebrated_at = clock_timestamp() WHERE id = p_entry_id;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_maybe_celebrate(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ---- Notifications (spec §8) ---------------------------------------------------------

-- "Ama suggested dates for Bali" to the other partner, at most one per poll
-- per hour (source_key is unique).
CREATE FUNCTION public.planning_v2_notify_poll(p_block public.planning_blocks, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries; v_partner uuid; v_name text;
BEGIN
  SELECT * INTO v_entry FROM public.planning_entries WHERE id = p_block.entry_id;
  IF v_entry.is_template OR p_actor IS NULL THEN RETURN; END IF;
  SELECT CASE WHEN r.user_a = p_actor THEN r.user_b ELSE r.user_a END INTO v_partner
  FROM public.relationships r WHERE r.id = p_block.relationship_id;
  SELECT coalesce(nullif(btrim(display_name), ''), 'Your partner') INTO v_name FROM public.users WHERE id = p_actor;
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  VALUES (v_partner, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'planning_entry', 'relationship_id', p_block.relationship_id,
            'entry_id', p_block.entry_id, 'title', 'New dates to vote on',
            'body', left(coalesce(v_name, 'Your partner') || ' suggested dates for ' || v_entry.title, 160)),
          'planning_poll:' || p_block.id || ':' || v_partner || ':'
            || to_char(date_trunc('hour', clock_timestamp() AT TIME ZONE 'UTC'), 'YYYYMMDDHH24'))
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_notify_poll(public.planning_blocks, uuid) FROM PUBLIC, anon, authenticated;

-- Hourly: a countdown whose date is today in a partner's zone pushes to that
-- partner from 08:00 local, once per (countdown, partner, local date).
CREATE FUNCTION public.planning_enqueue_countdown_pushes(p_now timestamptz DEFAULT now())
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata, source_key)
  SELECT m.user_id, 'immediate', p_now, 'pending',
         jsonb_build_object('type', 'planning_entry', 'relationship_id', e.relationship_id, 'entry_id', e.id,
           'title', 'Today''s the day', 'body', left(e.title, 160)),
         'planning_countdown:' || b.id || ':' || m.user_id || ':' || (p_now AT TIME ZONE m.tz)::date
  FROM public.planning_blocks b
  JOIN public.planning_entries e ON e.id = b.entry_id
   AND e.deleted_at IS NULL AND NOT e.is_template AND e.status = 'active'
  JOIN public.relationships r ON r.id = e.relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
  CROSS JOIN LATERAL (
    SELECT u AS user_id,
           coalesce((SELECT s.timezone FROM public.planning_member_settings s
                     WHERE s.relationship_id = r.id AND s.user_id = u), 'UTC') AS tz
    FROM unnest(ARRAY[r.user_a, r.user_b]) u) m
  WHERE b.block_type = 'countdown' AND b.deleted_at IS NULL
    AND public.planning_v2_countdown_target(b) = (p_now AT TIME ZONE m.tz)::date
    AND (p_now AT TIME ZONE m.tz)::time >= time '08:00'
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_enqueue_countdown_pushes(timestamptz) FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('planning_countdown_pushes', '5 * * * *', $$SELECT public.planning_enqueue_countdown_pushes()$$);

CREATE FUNCTION public.set_planning_timezone(p_relationship_id uuid, p_timezone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid := public.planning_v2_actor(p_relationship_id);
BEGIN
  IF p_timezone IS NULL OR char_length(p_timezone) NOT BETWEEN 1 AND 64
     OR NOT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"timezone"}');
  END IF;
  INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone, updated_at)
  VALUES (p_relationship_id, v_actor, p_timezone, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE SET timezone = EXCLUDED.timezone, updated_at = now()
  WHERE planning_member_settings.timezone IS DISTINCT FROM EXCLUDED.timezone;
  RETURN jsonb_build_object('timezone', p_timezone);
END;
$$;

-- Minutes ahead of UTC for an IANA zone right now (null if unknown). The
-- dual clock gets the partner's zone from presence, which already gates it
-- on the partner sharing; this only does the arithmetic.
CREATE FUNCTION public.planning_timezone_offset_minutes(p_timezone text)
RETURNS int LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT (extract(epoch FROM (now() AT TIME ZONE p_timezone) - (now() AT TIME ZONE 'UTC')) / 60)::int
  WHERE EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone);
$$;
REVOKE ALL ON FUNCTION public.planning_timezone_offset_minutes(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.planning_timezone_offset_minutes(text) TO authenticated;

-- ---- Blocks: server-owned keys -------------------------------------------------------

CREATE OR REPLACE FUNCTION public.add_planning_block(
  p_id uuid, p_entry_id uuid, p_block_type text, p_payload jsonb,
  p_date_start date, p_date_end date, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_entry   public.planning_entries := public.planning_v2_lock_entry(p_entry_id);
  v_actor   uuid := auth.uid();
  v_row     public.planning_blocks;
  v_plain   text;
  v_count   int;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
BEGIN
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id;
  IF FOUND THEN
    IF v_row.entry_id = p_entry_id AND v_row.block_type = p_block_type AND v_row.deleted_at IS NULL THEN
      RETURN public.planning_v2_block_object(p_id);
    END IF;
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF p_block_type = 'photo' THEN v_payload := (v_payload - 'paths') || '{"paths":[]}'::jsonb; END IF;
  IF p_block_type = 'link' THEN v_payload := v_payload - 'preview'; END IF;
  IF p_block_type = 'date' THEN v_payload := v_payload - 'poll_history'; END IF;
  v_plain := public.planning_v2_validate_block(p_block_type, v_payload, p_date_start, p_date_end);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = p_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;

  INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key,
                                      payload, plain_text, date_start, date_end)
  VALUES (p_id, v_entry.relationship_id, p_entry_id, v_actor, p_block_type,
          public.planning_v2_key_after_block(p_entry_id, p_after_id, p_id),
          v_payload, v_plain, p_date_start, p_date_end)
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
  v_payload  jsonb := coalesce(p_payload, '{}'::jsonb);
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

CREATE OR REPLACE FUNCTION public.update_planning_block_target(
  p_id uuid, p_version int, p_target_minor bigint, p_currency text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_row public.planning_blocks;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT * INTO v_row FROM public.planning_blocks WHERE id = p_id FOR UPDATE;
  IF v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.block_type NOT IN ('budget', 'progress') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END IF;
  IF p_version IS DISTINCT FROM v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version', jsonb_build_object('current', public.planning_v2_block_object(p_id)));
  END IF;
  IF p_target_minor IS NOT NULL AND (p_target_minor < 0 OR p_target_minor > 1000000000000) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"target_minor"}');
  END IF;
  IF p_currency IS NOT NULL AND p_currency !~ '^[A-Z]{3}$' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"currency"}');
  END IF;
  UPDATE public.planning_blocks
     SET target_minor = p_target_minor, target_currency = p_currency, version = version + 1
   WHERE id = p_id;
  IF v_row.block_type = 'progress' THEN PERFORM public.planning_v2_maybe_celebrate(v_entry_id, auth.uid()); END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- ---- Items -------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_planning_rich_item(
  p_id uuid, p_block_id uuid, p_version int, p_fields jsonb, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block  public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_actor  uuid := auth.uid();
  v_row    public.planning_block_items;
  v_cols   jsonb;
  v_before jsonb;
  v_count  int;
  v_limit  record;
BEGIN
  SELECT * INTO v_row FROM public.planning_block_items WHERE id = p_id FOR UPDATE;
  IF FOUND AND v_row.block_id <> p_block_id THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"id"}');
  END IF;
  IF FOUND AND v_row.deleted_at IS NOT NULL THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS NULL AND FOUND THEN
    RETURN public.planning_v2_item_object(p_id);         -- create retried
  END IF;
  IF p_version IS NOT NULL AND NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF p_version IS NOT NULL AND p_version <> v_row.version THEN
    PERFORM public.planning_v2_fail('stale_version', jsonb_build_object('current', public.planning_v2_item_object(p_id)));
  END IF;

  v_cols := public.planning_v2_rich_item_fields(v_block, p_fields);

  IF p_version IS NULL THEN
    v_limit := public.planning_v2_item_limit(v_block.block_type);
    SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = p_block_id AND deleted_at IS NULL;
    IF v_count >= v_limit.max_items THEN
      PERFORM public.planning_v2_fail('limit_reached', jsonb_build_object('limit', v_limit.limit_name));
    END IF;
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, created_at,
      text, amount_minor, currency, paid_by, split_share_minor, cells, date_start, date_end)
    VALUES (p_id, v_block.relationship_id, p_block_id, v_actor,
      public.planning_v2_key_after_item(p_block_id, p_after_id, p_id), clock_timestamp(),
      v_cols ->> 'text', (v_cols ->> 'amount_minor')::bigint, v_cols ->> 'currency',
      (v_cols ->> 'paid_by')::uuid, (v_cols ->> 'split_share_minor')::bigint, v_cols -> 'cells',
      (v_cols ->> 'date_start')::date, (v_cols ->> 'date_end')::date)
    RETURNING * INTO v_row;
    IF char_length(v_row.sort_key) > 32 THEN PERFORM public.planning_v2_rebalance_items(p_block_id); END IF;
    IF v_block.block_type = 'date_poll' THEN PERFORM public.planning_v2_notify_poll(v_block, v_actor); END IF;
  ELSE
    v_before := public.planning_v2_item_object(p_id);
    UPDATE public.planning_block_items SET
      text = CASE WHEN v_cols ? 'text' THEN v_cols ->> 'text' ELSE text END,
      amount_minor = CASE WHEN v_cols ? 'amount_minor' THEN (v_cols ->> 'amount_minor')::bigint ELSE amount_minor END,
      currency = CASE WHEN v_cols ? 'currency' THEN v_cols ->> 'currency' ELSE currency END,
      paid_by = CASE WHEN v_cols ? 'paid_by' THEN (v_cols ->> 'paid_by')::uuid ELSE paid_by END,
      split_share_minor = CASE WHEN v_cols ? 'split_share_minor' THEN (v_cols ->> 'split_share_minor')::bigint ELSE split_share_minor END,
      cells = CASE WHEN v_cols ? 'cells' THEN coalesce(cells, '{}'::jsonb) || (v_cols -> 'cells') ELSE cells END,
      date_start = CASE WHEN v_cols ? 'date_start' THEN (v_cols ->> 'date_start')::date ELSE date_start END,
      date_end = CASE WHEN v_cols ? 'date_end' THEN (v_cols ->> 'date_end')::date ELSE date_end END,
      version = version + 1
    WHERE id = p_id;
  END IF;

  IF v_block.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_block.relationship_id, v_block.entry_id, p_id,
      CASE WHEN p_version IS NULL THEN 'create' ELSE 'update' END, v_before, public.planning_v2_item_object(p_id));
  END IF;
  IF v_block.block_type = 'progress' THEN PERFORM public.planning_v2_maybe_celebrate(v_block.entry_id, v_actor); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_count int; v_limit record;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
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

-- Deleting an unticked item can complete a checklist goal.
CREATE OR REPLACE FUNCTION public.delete_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_before jsonb;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_before := public.planning_v2_item_object(p_id);
  UPDATE public.planning_block_items SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_block.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_block.relationship_id, v_block.entry_id, p_id, 'delete', v_before, NULL);
  END IF;
  IF v_block.block_type = 'checklist' THEN PERFORM public.planning_v2_maybe_celebrate(v_block.entry_id, auth.uid()); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

-- Unchanged from P1 apart from the celebration check after a tick.
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
  IF p_checked THEN PERFORM public.planning_v2_maybe_celebrate(v_block.entry_id, v_actor); END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

-- ---- Date poll ---------------------------------------------------------------------

CREATE FUNCTION public.vote_planning_poll(p_item_id uuid, p_vote boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_actor uuid;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_item_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  v_actor := auth.uid();
  IF v_block.block_type <> 'date_poll' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}'); END IF;
  IF p_vote IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"vote"}'); END IF;
  IF p_vote THEN
    INSERT INTO public.planning_poll_votes (item_id, relationship_id, user_id)
    VALUES (p_item_id, v_block.relationship_id, v_actor) ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.planning_poll_votes WHERE item_id = p_item_id AND user_id = v_actor;
  END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_block_object(v_block.id);
END;
$$;

-- "Lock it in": only an option both partners voted for. The poll becomes a
-- Date block with that range; the options are kept as history.
CREATE FUNCTION public.lock_planning_poll(p_block_id uuid, p_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block   public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_item    public.planning_block_items;
  v_votes   int;
  v_history jsonb;
BEGIN
  IF v_block.block_type <> 'date_poll' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}'); END IF;
  SELECT * INTO v_item FROM public.planning_block_items
  WHERE id = p_item_id AND block_id = p_block_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  SELECT count(*) INTO v_votes FROM public.planning_poll_votes v JOIN public.relationships r ON r.id = v_block.relationship_id
  WHERE v.item_id = p_item_id AND v.user_id IN (r.user_a, r.user_b);
  IF v_votes < 2 THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"votes"}'); END IF;

  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'date_start', i.date_start, 'date_end', i.date_end, 'label', i.text,
           'votes', (SELECT count(*) FROM public.planning_poll_votes v WHERE v.item_id = i.id),
           'chosen', i.id = p_item_id)) ORDER BY i.sort_key, i.id), '[]'::jsonb)
    INTO v_history
  FROM public.planning_block_items i WHERE i.block_id = p_block_id AND i.deleted_at IS NULL;

  UPDATE public.planning_block_items SET deleted_at = now() WHERE block_id = p_block_id AND deleted_at IS NULL;
  UPDATE public.planning_blocks
     SET block_type = 'date', date_start = v_item.date_start, date_end = v_item.date_end, plain_text = NULL,
         payload = jsonb_build_object('title', coalesce(payload ->> 'title', 'Dates'), 'poll_history', v_history),
         version = version + 1
   WHERE id = p_block_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_block_object(p_block_id);
END;
$$;

-- ---- Templates: instantiate and copy -------------------------------------------------

-- Template JSON: {type, payload, items?: [{text, section, cells}], target_minor?, target_currency?}
CREATE OR REPLACE FUNCTION public.planning_v2_instantiate_blocks(p_rel uuid, p_entry_id uuid, p_actor uuid, p_blocks jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    INSERT INTO public.planning_blocks (id, relationship_id, entry_id, created_by, block_type, sort_key, payload,
                                        plain_text, target_minor, target_currency)
    VALUES (v_block, p_rel, p_entry_id, p_actor, v_def ->> 'type', v_keys[v_ord],
            coalesce(v_def -> 'payload', '{}'::jsonb), v_plain,
            (v_def ->> 'target_minor')::bigint, v_def ->> 'target_currency');
    IF jsonb_array_length(coalesce(v_def -> 'items', '[]'::jsonb)) > 0 THEN
      v_ikeys := public.planning_even_keys(jsonb_array_length(v_def -> 'items'));
      FOR v_item, v_iord IN SELECT value, ordinality FROM jsonb_array_elements(v_def -> 'items') WITH ORDINALITY LOOP
        INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section, cells)
        VALUES (gen_random_uuid(), p_rel, v_block, p_actor, v_ikeys[v_iord],
                v_item ->> 'text', v_item ->> 'section', v_item -> 'cells');
      END LOOP;
    END IF;
  END LOOP;
END;
$$;

-- Copies a plan's blocks (new plan from template, "Start next one").
-- References are re-pointed at the copies. Stored files are not shared
-- between plans: photos stay with the original, a link keeps its preview
-- text without the image.
CREATE OR REPLACE FUNCTION public.planning_v2_copy_blocks(p_rel uuid, p_src uuid, p_dst uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_b public.planning_blocks; v_new uuid; v_payload jsonb; v_map jsonb := '{}'::jsonb; v_ref text;
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
    INSERT INTO public.planning_block_items (id, relationship_id, block_id, created_by, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells)
    SELECT gen_random_uuid(), p_rel, v_new, p_actor, sort_key, text, section,
      assigned_to, due_date, amount_minor, currency, split_share_minor, date_start, date_end, cells
    FROM public.planning_block_items WHERE block_id = v_b.id AND deleted_at IS NULL;
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

-- ---- Gallery ---------------------------------------------------------------------------

CREATE FUNCTION public.list_planning_gallery()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.planning_v2_fail('unauthenticated'); END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
            'key', g.key, 'name', g.name, 'icon', g.icon, 'color', g.color, 'description', g.description,
            'block_types', (SELECT jsonb_agg(b ->> 'type') FROM jsonb_array_elements(g.blocks) b))
          ORDER BY g.rank), '[]'::jsonb)
          FROM public.planning_gallery_templates g);
END;
$$;

-- A custom category whose template starts from a gallery definition.
-- Retrying with the same id returns the category without adding blocks.
CREATE FUNCTION public.create_planning_category_from_gallery(p_id uuid, p_relationship_id uuid, p_gallery_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor uuid := public.planning_v2_actor(p_relationship_id);
  g       public.planning_gallery_templates;
  v_cat   jsonb;
  v_tpl   uuid;
BEGIN
  SELECT * INTO g FROM public.planning_gallery_templates WHERE key = p_gallery_key;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"gallery_key"}'); END IF;
  IF EXISTS (SELECT 1 FROM public.planning_categories WHERE id = p_id) THEN
    RETURN public.create_planning_category(p_id, p_relationship_id, g.name, g.icon, g.color);
  END IF;
  v_cat := public.create_planning_category(p_id, p_relationship_id, g.name, g.icon, g.color);
  SELECT id INTO v_tpl FROM public.planning_entries WHERE category_id = p_id AND is_template AND deleted_at IS NULL;
  PERFORM public.planning_v2_instantiate_blocks(p_relationship_id, v_tpl, v_actor, g.blocks);
  RETURN v_cat;
END;
$$;

-- Text block helper for the definitions below: a level-2 heading and a blank line.
CREATE FUNCTION pg_temp.heading(p_text text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('type', 'text', 'payload', jsonb_build_object('delta', jsonb_build_array(
    jsonb_build_object('insert', p_text),
    jsonb_build_object('insert', E'\n', 'attributes', jsonb_build_object('header', 2)),
    jsonb_build_object('insert', E'\n'))));
$$;

INSERT INTO public.planning_gallery_templates (key, version, rank, name, icon, color, description, blocks) VALUES
('next_visit', 1, 1, 'Next visit', 'plane', 'indigo', 'Long distance: count down, pick dates, see both clocks.',
 jsonb_build_array(
   '{"type":"countdown","payload":{"title":"Until we''re together"}}'::jsonb,
   '{"type":"date_poll","payload":{"title":"When works?"}}'::jsonb,
   '{"type":"dual_clock","payload":{"title":"Our time"}}'::jsonb,
   '{"type":"expenses","payload":{"title":"Travel costs"},"items":[{"text":"Flight there"},{"text":"Flight back"}]}'::jsonb,
   '{"type":"checklist","payload":{"title":"Things to do together"}}'::jsonb,
   '{"type":"checklist","payload":{"title":"Packing"}}'::jsonb)),
('diet', 1, 2, 'Diet', 'utensils', 'green', 'Plan the week''s meals and cook at home more.',
 jsonb_build_array(
   '{"type":"table","payload":{"title":"Meal plan","columns":[{"key":"c0","label":"Day","type":"text"},{"key":"c1","label":"Breakfast","type":"text"},{"key":"c2","label":"Lunch","type":"text"},{"key":"c3","label":"Dinner","type":"text"}]},"items":[{"cells":{"c0":"Mon"}},{"cells":{"c0":"Tue"}},{"cells":{"c0":"Wed"}},{"cells":{"c0":"Thu"}},{"cells":{"c0":"Fri"}},{"cells":{"c0":"Sat"}},{"cells":{"c0":"Sun"}}]}'::jsonb,
   '{"type":"checklist","payload":{"title":"Shopping"}}'::jsonb,
   '{"type":"progress","payload":{"title":"Cook at home","mode":"numeric","unit":"count"},"target_minor":5}'::jsonb)),
('wishlist', 1, 3, 'Wishlist', 'gift', 'rose', 'Things we want, what they cost, and what we''ve got.',
 jsonb_build_array(
   '{"type":"table","payload":{"title":"Wishlist","columns":[{"key":"c0","label":"Item","type":"text"},{"key":"c1","label":"Price","type":"money"},{"key":"c2","label":"Where","type":"text"},{"key":"c3","label":"Got it","type":"check"}]}}'::jsonb,
   '{"type":"budget","payload":{}}'::jsonb)),
('moving_house', 1, 4, 'Moving house', 'box', 'amber', 'Moving day, the to-dos, and what it costs.',
 jsonb_build_array(
   '{"type":"date","payload":{"title":"Moving day"}}'::jsonb,
   '{"type":"countdown","payload":{}}'::jsonb,
   '{"type":"place","payload":{"title":"New home"}}'::jsonb,
   '{"type":"checklist","payload":{"title":"Before the move"},"items":[{"text":"Boxes and tape","section":"Packing"},{"text":"Change our address","section":"Admin"},{"text":"Move the internet","section":"Utilities"},{"text":"Final meter readings","section":"Utilities"}]}'::jsonb,
   '{"type":"table","payload":{"title":"Rooms","columns":[{"key":"c0","label":"Room","type":"text"},{"key":"c1","label":"What goes there","type":"text"}]}}'::jsonb,
   '{"type":"budget","payload":{}}'::jsonb,
   '{"type":"expenses","payload":{}}'::jsonb)),
('wedding', 1, 5, 'Wedding', 'ring', 'violet', 'The day, the guest list, the bookings and the budget.',
 jsonb_build_array(
   '{"type":"date","payload":{"title":"The day"}}'::jsonb,
   '{"type":"countdown","payload":{}}'::jsonb,
   '{"type":"budget","payload":{}}'::jsonb,
   '{"type":"expenses","payload":{}}'::jsonb,
   '{"type":"checklist","payload":{"title":"To book"},"items":[{"text":"Venue"},{"text":"Photographer"},{"text":"Catering"},{"text":"Music"},{"text":"Flowers"},{"text":"Rings"}]}'::jsonb,
   '{"type":"table","payload":{"title":"Guests","columns":[{"key":"c0","label":"Name","type":"text"},{"key":"c1","label":"Invited","type":"check"},{"key":"c2","label":"Coming","type":"check"},{"key":"c3","label":"Plus one","type":"check"}]}}'::jsonb,
   '{"type":"link","payload":{"label":"Inspiration"}}'::jsonb)),
('baby', 1, 6, 'Baby', 'baby', 'teal', 'Due date, the bag, the nursery and names.',
 jsonb_build_array(
   '{"type":"date","payload":{"title":"Due date"}}'::jsonb,
   '{"type":"countdown","payload":{}}'::jsonb,
   '{"type":"checklist","payload":{"title":"Hospital bag"}}'::jsonb,
   '{"type":"checklist","payload":{"title":"Nursery"}}'::jsonb,
   '{"type":"table","payload":{"title":"Names we like","columns":[{"key":"c0","label":"Name","type":"text"},{"key":"c1","label":"We both love it","type":"check"}]}}'::jsonb,
   '{"type":"budget","payload":{}}'::jsonb,
   pg_temp.heading('Notes')));

-- Starters: the full block lists of spec §4.1. Unedited templates upgrade
-- on the next home read (planning_v2_ensure_starters); edited ones keep
-- the couple's version.
UPDATE public.planning_starter_templates SET version = 2, blocks = jsonb_build_array(
  '{"type":"progress","payload":{"mode":"checklist"}}'::jsonb,
  '{"type":"date","payload":{"title":"Target date"}}'::jsonb,
  pg_temp.heading('Why this matters to us'),
  '{"type":"checklist","payload":{"title":"Steps"}}'::jsonb)
WHERE seed_key = 'goals';

UPDATE public.planning_starter_templates SET version = 2, blocks = jsonb_build_array(
  '{"type":"photo","payload":{"title":"Cover"}}'::jsonb,
  '{"type":"date_poll","payload":{"title":"Pick dates"}}'::jsonb,
  '{"type":"countdown","payload":{}}'::jsonb,
  '{"type":"place","payload":{"title":"Destination"}}'::jsonb,
  '{"type":"budget","payload":{}}'::jsonb,
  '{"type":"expenses","payload":{},"items":[{"text":"Flights"},{"text":"Stay"}]}'::jsonb,
  '{"type":"link","payload":{"label":"Places to stay"}}'::jsonb,
  '{"type":"table","payload":{"title":"Itinerary","columns":[{"key":"c0","label":"Day","type":"text"},{"key":"c1","label":"Plan","type":"text"},{"key":"c2","label":"Where","type":"text"},{"key":"c3","label":"Cost","type":"money"}]}}'::jsonb,
  '{"type":"checklist","payload":{"title":"Packing"},"items":[{"text":"Passports"},{"text":"Chargers"},{"text":"Toiletries"}]}'::jsonb,
  pg_temp.heading('Notes'))
WHERE seed_key = 'trips';

UPDATE public.planning_starter_templates SET version = 2, blocks = jsonb_build_array(
  '{"type":"date","payload":{"title":"When"}}'::jsonb,
  '{"type":"place","payload":{"title":"Where"}}'::jsonb,
  pg_temp.heading('The plan'),
  '{"type":"budget","payload":{}}'::jsonb,
  '{"type":"link","payload":{"label":"Ideas"}}'::jsonb,
  pg_temp.heading('What we loved'))
WHERE seed_key = 'date_nights';

UPDATE public.planning_starter_templates SET version = 2, blocks = jsonb_build_array(
  '{"type":"table","payload":{"title":"Bills","columns":[{"key":"c0","label":"Bill","type":"text"},{"key":"c1","label":"Amount","type":"money"},{"key":"c2","label":"Due day","type":"number"},{"key":"c3","label":"Paid","type":"check"},{"key":"c4","label":"Paid by","type":"text"}]},"items":[{"cells":{"c0":"Rent"}},{"cells":{"c0":"Electricity"}},{"cells":{"c0":"Water"}},{"cells":{"c0":"Internet"}},{"cells":{"c0":"TV"}}]}'::jsonb,
  '{"type":"budget","payload":{}}'::jsonb,
  pg_temp.heading('Notes'))
WHERE seed_key = 'home_bills';

UPDATE public.planning_starter_templates SET version = 2,
  blocks = blocks || jsonb_build_array('{"type":"budget","payload":{"title":"Estimated total"}}'::jsonb)
WHERE seed_key = 'groceries' AND version = 1;

-- ---- Grants -------------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.vote_planning_poll(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.lock_planning_poll(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_timezone(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_planning_gallery() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_planning_category_from_gallery(uuid, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.vote_planning_poll(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lock_planning_poll(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_timezone(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_planning_gallery() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_planning_category_from_gallery(uuid, uuid, text) TO authenticated;
