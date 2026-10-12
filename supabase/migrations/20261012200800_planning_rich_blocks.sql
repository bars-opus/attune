-- Planning P3: rich blocks — table, photo, link, place, expenses, budget
-- (spec §3.4–3.6, §3.9, §6.3, §6.7–6.12, §7.1).
--
-- Money is integer minor units + ISO 4217 code (checklist 2.19). Every
-- expense mutation writes planning_expense_events in the same transaction
-- (checklist 2.22). A partner balance exists only inside a plan with split
-- turned on, never summed across plans (spec D6/D13).

-- ---- Expense audit ---------------------------------------------------------

-- No foreign key to planning_entries on purpose: the money history outlives
-- the nightly purge of deleted plans and is removed only with the
-- relationship itself (spec §3.6).
CREATE TABLE public.planning_expense_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  entry_id        uuid NOT NULL,
  item_id         uuid,
  actor_id        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action          text NOT NULL CHECK (action IN
                    ('create','update','delete','restore','split_on','split_off','settle')),
  before          jsonb,
  after           jsonb,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX idx_planning_expense_events_entry ON public.planning_expense_events (entry_id, created_at);
ALTER TABLE public.planning_expense_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_expense_events FROM PUBLIC, anon, authenticated;

-- Append-only. The only changes allowed are the ones a foreign-key cascade
-- makes (relationship deleted -> rows removed; account deleted -> actor
-- set null), which run one trigger level deeper than any direct statement.
CREATE FUNCTION public.planning_expense_events_append_only()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF pg_trigger_depth() < 2 THEN
    RAISE EXCEPTION 'planning_expense_events is append-only';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_expense_events_append_only() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER planning_expense_events_no_rewrite
  BEFORE UPDATE OR DELETE ON public.planning_expense_events
  FOR EACH ROW EXECUTE FUNCTION public.planning_expense_events_append_only();

CREATE FUNCTION public.planning_v2_audit_expense(
  p_rel uuid, p_entry uuid, p_item uuid, p_action text, p_before jsonb, p_after jsonb
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.planning_expense_events (relationship_id, entry_id, item_id, actor_id, action, before, after)
  VALUES (p_rel, p_entry, p_item, auth.uid(), p_action, p_before, p_after);
$$;
REVOKE ALL ON FUNCTION public.planning_v2_audit_expense(uuid, uuid, uuid, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- ---- Link preview cache (service role only) ---------------------------------

CREATE TABLE public.planning_link_previews (
  url_hash   text PRIMARY KEY,
  preview    jsonb NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.planning_link_previews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_link_previews FROM PUBLIC, anon, authenticated;

-- One row per preview fetch a user asks for; the last minute's rows are
-- the rate limit (30/min/user, spec §7.1). Purged after a day.
CREATE TABLE public.planning_link_preview_requests (
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX idx_planning_link_preview_requests ON public.planning_link_preview_requests (user_id, requested_at);
ALTER TABLE public.planning_link_preview_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.planning_link_preview_requests FROM PUBLIC, anon, authenticated;

-- ---- Validation --------------------------------------------------------------

CREATE FUNCTION public.planning_v2_keys_within(p jsonb, p_allowed text[])
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE NOT (k = ANY (p_allowed)));
$$;

CREATE FUNCTION public.planning_v2_is_int(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_typeof(p) = 'number' AND (p #>> '{}')::numeric = trunc((p #>> '{}')::numeric);
$$;

CREATE FUNCTION public.planning_v2_title_ok(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT (p ? 'title') OR (jsonb_typeof(p -> 'title') = 'string'
    AND char_length(btrim(p ->> 'title')) BETWEEN 1 AND 80);
$$;
REVOKE ALL ON FUNCTION public.planning_v2_keys_within(jsonb, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_is_int(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_title_ok(jsonb) FROM PUBLIC, anon, authenticated;

-- Per-type block validation. Replaces P1's (text / checklist / date) and
-- adds the P3 types; P4 replaces it again for its own.
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
  IF p_type NOT IN ('date') AND (p_date_start IS NOT NULL OR p_date_end IS NOT NULL) THEN
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
  WHEN 'checklist', 'expenses', 'budget' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
  WHEN 'date' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['title']) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
    END IF;
    IF p_date_end IS NOT NULL AND (p_date_start IS NULL OR p_date_end < p_date_start) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
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
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['url','label','preview'])
       OR jsonb_typeof(p_payload -> 'url') IS DISTINCT FROM 'string'
       OR char_length(p_payload ->> 'url') > 2048
       OR (p_payload ->> 'url') !~* '^https?://[^[:space:]]+$'
       OR (p_payload ? 'label' AND char_length(btrim(coalesce(p_payload ->> 'label', ''))) NOT BETWEEN 1 AND 80) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"url"}');
    END IF;
  WHEN 'place' THEN
    IF NOT public.planning_v2_keys_within(p_payload, ARRAY['name','address','lat','lng'])
       OR char_length(btrim(coalesce(p_payload ->> 'name', ''))) NOT BETWEEN 1 AND 120
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

-- Validates and normalizes a rich item's fields for its block type and
-- returns them as the columns to write. P4 extends this for its types.
CREATE FUNCTION public.planning_v2_rich_item_fields(p_block public.planning_blocks, p_fields jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_col     jsonb;
  v_cell    record;
  v_type    text;
  v_amount  numeric;
  v_share   numeric;
  v_paid_by uuid;
  v_cur     text;
  v_ok      boolean;
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
  ELSE
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END CASE;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_rich_item_fields(public.planning_blocks, jsonb) FROM PUBLIC, anon, authenticated;

-- ---- JSON shapes ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.planning_v2_item_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', i.id, 'sort_key', i.sort_key, 'text', i.text, 'section', i.section,
    'checked_at', i.checked_at, 'checked_by', i.checked_by,
    'assigned_to', i.assigned_to, 'due_date', i.due_date, 'version', i.version,
    'amount_minor', i.amount_minor, 'currency', i.currency, 'paid_by', i.paid_by,
    'split_share_minor', i.split_share_minor, 'cells', i.cells,
    'date_start', i.date_start, 'date_end', i.date_end, 'created_by', i.created_by)
  FROM public.planning_block_items i WHERE i.id = p_id;
$$;

-- Server-computed figures a block shows (budget spent per currency).
CREATE FUNCTION public.planning_v2_block_computed(p_block public.planning_blocks)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN p_block.block_type = 'budget' THEN (
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
  ELSE NULL END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_block_computed(public.planning_blocks) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_block_object(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', b.id, 'block_type', b.block_type, 'sort_key', b.sort_key,
    'payload', b.payload, 'plain_text', b.plain_text,
    'date_start', b.date_start, 'date_end', b.date_end,
    'target_minor', b.target_minor, 'target_currency', b.target_currency,
    'version', b.version, 'updated_at', b.updated_at,
    'computed', public.planning_v2_block_computed(b),
    'items', coalesce((
      SELECT jsonb_agg(public.planning_v2_item_object(i.id) ORDER BY i.sort_key, i.id)
      FROM public.planning_block_items i WHERE i.block_id = b.id AND i.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_blocks b WHERE b.id = p_id;
$$;

-- Net "to even out" per currency inside one split plan. An equal split
-- leaves the odd minor unit with the payer; lines added after the last
-- settle count from zero.
CREATE FUNCTION public.planning_v2_split_balances(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH e AS (SELECT * FROM public.planning_entries WHERE id = p_entry_id),
  m AS (SELECT r.user_a, r.user_b FROM public.relationships r JOIN e ON e.relationship_id = r.id),
  lines AS (
    SELECT i.currency, i.paid_by, coalesce(i.split_share_minor, i.amount_minor / 2) AS other_share
    FROM public.planning_block_items i JOIN public.planning_blocks b ON b.id = i.block_id, e
    WHERE b.entry_id = e.id AND b.block_type = 'expenses' AND b.deleted_at IS NULL
      AND i.deleted_at IS NULL AND i.paid_by IS NOT NULL AND i.amount_minor IS NOT NULL
      AND (e.split_settled_at IS NULL OR i.created_at > e.split_settled_at)),
  net AS (
    SELECT l.currency, sum(CASE WHEN l.paid_by = m.user_a THEN l.other_share ELSE -l.other_share END) AS a_is_owed
    FROM lines l, m GROUP BY l.currency)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'currency', net.currency, 'minor', abs(net.a_is_owed),
           'owed_to', CASE WHEN net.a_is_owed > 0 THEN m.user_a ELSE m.user_b END,
           'owed_by', CASE WHEN net.a_is_owed > 0 THEN m.user_b ELSE m.user_a END)
         ORDER BY net.currency), '[]'::jsonb)
  FROM net, m WHERE net.a_is_owed <> 0;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_split_balances(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_entry_object(p_entry_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'category_id', e.category_id, 'category_name', c.name,
    'category_seed_key', c.seed_key, 'is_template', e.is_template, 'title', e.title,
    'status', e.status, 'currency', e.currency, 'cover_path', e.cover_path,
    'pinned_at', e.pinned_at,
    'split', CASE WHEN e.split_enabled THEN jsonb_build_object(
               'settled_at', e.split_settled_at,
               'balances', public.planning_v2_split_balances(e.id))
             ELSE 'null'::jsonb END,
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
      SELECT jsonb_agg(public.planning_v2_block_object(b.id) ORDER BY b.sort_key, b.id)
      FROM public.planning_blocks b WHERE b.entry_id = e.id AND b.deleted_at IS NULL), '[]'::jsonb))
  FROM public.planning_entries e WHERE e.id = p_entry_id;
$$;

-- ---- Blocks: server-owned payload keys ---------------------------------------

-- photo.paths and link.preview are written only by their own RPCs. On a
-- client write they are stripped (create) or carried over (update); a link
-- whose url changes drops its old preview and queues its image.
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
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- Budget (and, in P4, Progress) targets live in typed columns.
CREATE FUNCTION public.update_planning_block_target(
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
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- Deleting or restoring an expenses block records each of its lines, so
-- the money history has no gaps.
CREATE OR REPLACE FUNCTION public.delete_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_row public.planning_blocks;
BEGIN
  SELECT entry_id INTO v_entry_id FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  UPDATE public.planning_blocks SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL RETURNING * INTO v_row;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_row.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_entry.relationship_id, v_entry_id, i.id, 'delete',
              public.planning_v2_item_object(i.id), NULL)
    FROM public.planning_block_items i WHERE i.block_id = p_id AND i.deleted_at IS NULL;
  END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry_id uuid; v_entry public.planning_entries; v_count int; v_type text;
BEGIN
  SELECT entry_id, block_type INTO v_entry_id, v_type FROM public.planning_blocks WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_entry := public.planning_v2_lock_entry(v_entry_id);
  SELECT count(*) INTO v_count FROM public.planning_blocks WHERE entry_id = v_entry_id AND deleted_at IS NULL;
  IF v_count >= 200 THEN PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}'); END IF;
  UPDATE public.planning_blocks SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  IF v_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_entry.relationship_id, v_entry_id, i.id, 'restore',
              NULL, public.planning_v2_item_object(i.id))
    FROM public.planning_block_items i WHERE i.block_id = p_id AND i.deleted_at IS NULL;
  END IF;
  PERFORM public.planning_v2_touch_entry(v_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN public.planning_v2_block_object(p_id);
END;
$$;

-- ---- Rich items (table rows, expense lines; P4 adds poll options, contributions)

-- Create (p_version NULL) or update (p_version = the version read). Creates
-- are idempotent by item id.
CREATE FUNCTION public.save_planning_rich_item(
  p_id uuid, p_block_id uuid, p_version int, p_fields jsonb, p_after_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block  public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_actor  uuid := auth.uid();
  v_row    public.planning_block_items;
  v_cols   jsonb;
  v_before jsonb;
  v_count  int;
  v_limit  int;
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
    v_limit := CASE v_block.block_type WHEN 'table' THEN 50 ELSE 500 END;
    SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = p_block_id AND deleted_at IS NULL;
    IF v_count >= v_limit THEN
      PERFORM public.planning_v2_fail('limit_reached',
        jsonb_build_object('limit', CASE v_block.block_type WHEN 'table' THEN 'table_rows' ELSE 'items_per_block' END));
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
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, v_actor);
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

-- Item delete/restore: unchanged, plus the expense audit.
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
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN jsonb_build_object('deleted', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_planning_block_item(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block_id uuid; v_block public.planning_blocks; v_count int; v_limit int;
BEGIN
  SELECT block_id INTO v_block_id FROM public.planning_block_items WHERE id = p_id AND deleted_at IS NOT NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  v_block := public.planning_v2_lock_block(v_block_id);
  SELECT count(*) INTO v_count FROM public.planning_block_items WHERE block_id = v_block_id AND deleted_at IS NULL;
  v_limit := CASE v_block.block_type WHEN 'table' THEN 50 ELSE 500 END;
  IF v_count >= v_limit THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"items_per_block"}');
  END IF;
  UPDATE public.planning_block_items SET deleted_at = NULL, version = version + 1 WHERE id = p_id;
  IF v_block.block_type = 'expenses' THEN
    PERFORM public.planning_v2_audit_expense(v_block.relationship_id, v_block.entry_id, p_id, 'restore',
              NULL, public.planning_v2_item_object(p_id));
  END IF;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_item_object(p_id);
END;
$$;

-- ---- Split -------------------------------------------------------------------

CREATE FUNCTION public.set_planning_entry_split(p_entry_id uuid, p_enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries;
BEGIN
  IF p_enabled IS NULL THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"enabled"}'); END IF;
  v_entry := public.planning_v2_lock_entry(p_entry_id);
  IF v_entry.is_template THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"template"}'); END IF;
  IF v_entry.split_enabled IS DISTINCT FROM p_enabled THEN
    UPDATE public.planning_entries SET split_enabled = p_enabled WHERE id = p_entry_id;
    PERFORM public.planning_v2_audit_expense(v_entry.relationship_id, p_entry_id, NULL,
      CASE WHEN p_enabled THEN 'split_on' ELSE 'split_off' END, NULL, NULL);
    PERFORM public.planning_v2_touch_entry(p_entry_id, auth.uid());
    PERFORM public.bump_planning_signal(v_entry.relationship_id);
  END IF;
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_entry_id));
END;
$$;

CREATE FUNCTION public.settle_planning_split(p_entry_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_entry public.planning_entries;
BEGIN
  v_entry := public.planning_v2_lock_entry(p_entry_id);
  IF NOT v_entry.split_enabled THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"split"}'); END IF;
  PERFORM public.planning_v2_audit_expense(v_entry.relationship_id, p_entry_id, NULL, 'settle',
    jsonb_build_object('balances', public.planning_v2_split_balances(p_entry_id)), NULL);
  UPDATE public.planning_entries SET split_settled_at = clock_timestamp() WHERE id = p_entry_id;
  PERFORM public.planning_v2_touch_entry(p_entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_entry.relationship_id);
  RETURN jsonb_build_object('entry', public.planning_v2_entry_object(p_entry_id));
END;
$$;

-- ---- Photos ------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public) VALUES ('planning-media', 'planning-media', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- Object paths are "<relationship_id>/<entry_id>/<file>". Storage policies
-- ask these two functions; both resolve the caller from auth.uid().
CREATE FUNCTION public.planning_storage_can_write(p_name text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid; v_entry uuid;
BEGIN
  IF p_name IS NULL OR p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,100}$' THEN RETURN false; END IF;
  v_rel := split_part(p_name, '/', 1)::uuid;
  v_entry := split_part(p_name, '/', 2)::uuid;
  RETURN EXISTS (
    SELECT 1 FROM public.relationships r JOIN public.planning_entries e ON e.relationship_id = r.id
    WHERE r.id = v_rel AND e.id = v_entry AND e.deleted_at IS NULL
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid()));
END;
$$;

CREATE FUNCTION public.planning_storage_can_read(p_name text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid;
BEGIN
  IF p_name IS NULL OR p_name !~ '^[0-9a-f-]{36}/' THEN RETURN false; END IF;
  v_rel := split_part(p_name, '/', 1)::uuid;
  RETURN EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = v_rel AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = auth.uid() OR r.user_b = auth.uid()));
END;
$$;
REVOKE ALL ON FUNCTION public.planning_storage_can_write(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.planning_storage_can_read(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.planning_storage_can_write(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.planning_storage_can_read(text) TO authenticated;

DROP POLICY IF EXISTS planning_media_insert ON storage.objects;
CREATE POLICY planning_media_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'planning-media' AND public.planning_storage_can_write(name));
DROP POLICY IF EXISTS planning_media_select ON storage.objects;
CREATE POLICY planning_media_select ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'planning-media' AND public.planning_storage_can_read(name));

CREATE FUNCTION public.add_planning_photo(p_block_id uuid, p_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_block public.planning_blocks := public.planning_v2_lock_block(p_block_id);
  v_meta  jsonb;
  v_paths jsonb;
BEGIN
  IF v_block.block_type <> 'photo' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}'); END IF;
  IF p_path IS NULL OR p_path !~ ('^' || v_block.relationship_id || '/' || v_block.entry_id || '/[A-Za-z0-9._-]{1,100}\.jpg$') THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"path"}');
  END IF;
  SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'planning-media' AND name = p_path;
  IF NOT FOUND OR coalesce(v_meta ->> 'mimetype', '') <> 'image/jpeg'
     OR coalesce((v_meta ->> 'size')::bigint, 0) NOT BETWEEN 1 AND 10485760 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"path"}');
  END IF;
  v_paths := coalesce(v_block.payload -> 'paths', '[]'::jsonb);
  IF v_paths ? p_path THEN RETURN public.planning_v2_block_object(p_block_id); END IF;
  IF jsonb_array_length(v_paths) >= 10 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"photos_per_block"}');
  END IF;
  UPDATE public.planning_blocks
     SET payload = payload || jsonb_build_object('paths', v_paths || to_jsonb(p_path)), version = version + 1
   WHERE id = p_block_id;
  PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN public.planning_v2_block_object(p_block_id);
END;
$$;

CREATE FUNCTION public.remove_planning_photo(p_block_id uuid, p_path text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block public.planning_blocks := public.planning_v2_lock_block(p_block_id);
BEGIN
  IF v_block.block_type <> 'photo' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}'); END IF;
  IF coalesce(v_block.payload -> 'paths', '[]'::jsonb) ? p_path THEN
    UPDATE public.planning_blocks
       SET payload = payload || jsonb_build_object('paths', (
             SELECT coalesce(jsonb_agg(p), '[]'::jsonb) FROM jsonb_array_elements_text(payload -> 'paths') p WHERE p <> p_path)),
           version = version + 1
     WHERE id = p_block_id;
    PERFORM public.queue_media_deletion('planning-media', p_path);
    PERFORM public.planning_v2_touch_entry(v_block.entry_id, auth.uid());
    PERFORM public.bump_planning_signal(v_block.relationship_id);
  END IF;
  RETURN public.planning_v2_block_object(p_block_id);
END;
$$;

-- ---- Link previews -----------------------------------------------------------

-- Called by the planning-link-preview edge function WITH the user's JWT, so
-- membership is checked as that user before anything is fetched.
CREATE FUNCTION public.planning_link_preview_target(p_block_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_block public.planning_blocks;
BEGIN
  SELECT * INTO v_block FROM public.planning_blocks WHERE id = p_block_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  PERFORM public.planning_v2_actor(v_block.relationship_id);
  IF v_block.block_type <> 'link' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}'); END IF;
  -- Serialize this user's count-then-insert so parallel calls can't all pass.
  PERFORM pg_advisory_xact_lock(hashtext('planning_link_preview:' || auth.uid()));
  IF (SELECT count(*) FROM public.planning_link_preview_requests
      WHERE user_id = auth.uid() AND requested_at > clock_timestamp() - interval '1 minute') >= 30 THEN
    PERFORM public.planning_v2_fail('rate_limited', '{"retry_after":60}');
  END IF;
  INSERT INTO public.planning_link_preview_requests (user_id) VALUES (auth.uid());
  RETURN jsonb_build_object('block_id', v_block.id, 'url', v_block.payload ->> 'url',
    'relationship_id', v_block.relationship_id, 'entry_id', v_block.entry_id);
END;
$$;

-- Service role only. Writes a sanitized preview if the block still points at
-- the url that was fetched (a later url edit wins) and returns whether it
-- did, so the caller can delete an image nobody will reference. A replaced
-- preview image is queued for deletion.
CREATE FUNCTION public.set_planning_link_preview(p_block_id uuid, p_url text, p_preview jsonb)
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
     SET payload = payload || jsonb_build_object('preview', v_clean), version = version + 1
   WHERE id = p_block_id;
  PERFORM public.bump_planning_signal(v_block.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.set_planning_link_preview(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_link_preview(uuid, text, jsonb) TO service_role;

-- ---- Retention: purged blocks take their stored files with them ----------------

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

-- ---- Grants for the new public RPCs -----------------------------------------------

REVOKE ALL ON FUNCTION public.save_planning_rich_item(uuid, uuid, int, jsonb, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_planning_block_target(uuid, int, bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_planning_entry_split(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.settle_planning_split(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.add_planning_photo(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_planning_photo(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.planning_link_preview_target(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_planning_rich_item(uuid, uuid, int, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_planning_block_target(uuid, int, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_planning_entry_split(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.settle_planning_split(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_planning_photo(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_planning_photo(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.planning_link_preview_target(uuid) TO authenticated;
