-- Planning v2 internal helpers (P1 Task 2).
-- Spec §3.7 (ordering), §3.11 (limits), §6.1 (rich-text whitelist), §7.2 (errors).

-- Limits: the single source of truth. lib/features/planning/v2/domain/
-- planning_v2_limits.dart mirrors this literal; a Dart test parses this
-- file and asserts equality, so neither can drift alone.
CREATE OR REPLACE FUNCTION public.planning_limits()
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT '{"categories":50,"blocks_per_entry":200,"items_per_block":500,"payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,"image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,"entries_page_max":100,"title_chars":120,"category_name_chars":40,"item_text_chars":500,"section_chars":40}'::jsonb;
$$;
REVOKE ALL ON FUNCTION public.planning_limits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.planning_limits() TO authenticated;

-- The only way a v2 RPC fails. Message is a stable machine code; HINT
-- is JSON detail. The Dart repository maps on the message, never on
-- free text (planning_v2_error.dart).
CREATE OR REPLACE FUNCTION public.planning_v2_fail(p_code text, p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION USING
    ERRCODE = 'P0001',
    MESSAGE = 'planning:' || p_code,
    HINT = coalesce(p_detail, '{}'::jsonb)::text;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_fail(text, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_is_member(p_relationship_id uuid, p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id AND (r.user_a = p_user OR r.user_b = p_user));
$$;
REVOKE ALL ON FUNCTION public.planning_v2_is_member(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- Resolves the caller. not_found for "not yours" (no existence oracle);
-- inactive only when the caller IS a member of an ended/archived couple.
CREATE OR REPLACE FUNCTION public.planning_v2_actor(p_relationship_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rel public.relationships;
BEGIN
  IF v_uid IS NULL THEN PERFORM public.planning_v2_fail('unauthenticated'); END IF;
  SELECT * INTO v_rel FROM public.relationships
  WHERE id = p_relationship_id AND (user_a = v_uid OR user_b = v_uid);
  IF NOT FOUND THEN PERFORM public.planning_v2_fail('not_found'); END IF;
  IF v_rel.status <> 'active' OR v_rel.chat_archived_at IS NOT NULL THEN
    PERFORM public.planning_v2_fail('inactive');
  END IF;
  RETURN v_uid;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_actor(uuid) FROM PUBLIC, anon, authenticated;

-- Fractional base-62 keys (spec §3.7). Keys never end in '0', so there
-- is always room below. Returns a key strictly between p_a and p_b.
CREATE OR REPLACE FUNCTION public.planning_key_between(p_a text, p_b text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  c_digits constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_a  text := coalesce(p_a, '');
  v_n  int := 0;
  v_da int;
  v_db int;
BEGIN
  IF p_b IS NOT NULL AND v_a COLLATE "C" >= p_b COLLATE "C" THEN
    RAISE EXCEPTION 'planning_key_between: % >= %', p_a, p_b;
  END IF;
  IF p_b IS NOT NULL THEN
    WHILE v_n < char_length(p_b)
      AND coalesce(nullif(substr(v_a, v_n + 1, 1), ''), '0') = substr(p_b, v_n + 1, 1) LOOP
      v_n := v_n + 1;
    END LOOP;
    IF v_n > 0 THEN
      RETURN substr(p_b, 1, v_n)
        || public.planning_key_between(substr(v_a, v_n + 1), substr(p_b, v_n + 1));
    END IF;
  END IF;
  v_da := CASE WHEN v_a = '' THEN 0 ELSE strpos(c_digits, substr(v_a, 1, 1)) - 1 END;
  v_db := CASE WHEN p_b IS NULL THEN 62 ELSE strpos(c_digits, substr(p_b, 1, 1)) - 1 END;
  IF v_db - v_da > 1 THEN
    RETURN substr(c_digits, ((v_da + v_db + 1) / 2) + 1, 1);
  END IF;
  IF p_b IS NOT NULL AND char_length(p_b) > 1 THEN
    RETURN substr(p_b, 1, 1);
  END IF;
  RETURN substr(c_digits, v_da + 1, 1) || public.planning_key_between(substr(v_a, 2), NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.planning_key_between(text, text) FROM PUBLIC, anon, authenticated;

-- n evenly spaced 2-char keys (3844 slots). Used for seeding and for
-- rebalancing a sibling set whose keys grew past 32 chars.
CREATE OR REPLACE FUNCTION public.planning_even_keys(p_n int)
RETURNS text[] LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  c_digits constant text := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  v_out text[] := '{}';
  v_val int;
  v_i int;
BEGIN
  IF p_n < 0 OR p_n > 700 THEN RAISE EXCEPTION 'planning_even_keys: n=% out of range', p_n; END IF;
  FOR v_i IN 1..p_n LOOP
    v_val := (v_i * 3844) / (p_n + 1);
    IF v_val % 62 = 0 THEN v_val := v_val + 1; END IF;
    v_out := v_out || (substr(c_digits, (v_val / 62) + 1, 1) || substr(c_digits, (v_val % 62) + 1, 1));
  END LOOP;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_even_keys(int) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_v2_icons()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['flag','plane','heart','home','cart','sun','star','gift','book',
               'dumbbell','utensils','baby','ring','box','music','paw'];
$$;
CREATE OR REPLACE FUNCTION public.planning_v2_colors()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['rose','amber','teal','indigo','green','slate','violet','orange'];
$$;
REVOKE ALL ON FUNCTION public.planning_v2_icons() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.planning_v2_colors() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.planning_delta_attribute_ok(p_key text, p_val jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
    WHEN 'bold'       THEN p_val = 'true'::jsonb
    WHEN 'italic'     THEN p_val = 'true'::jsonb
    WHEN 'underline'  THEN p_val = 'true'::jsonb
    WHEN 'strike'     THEN p_val = 'true'::jsonb
    WHEN 'blockquote' THEN p_val = 'true'::jsonb
    WHEN 'background' THEN p_val IN ('"yellow"','"green"','"blue"','"pink"','"purple"')
    WHEN 'color'      THEN p_val IN ('"yellow"','"green"','"blue"','"pink"','"purple"')
    WHEN 'header'     THEN p_val IN ('1','2','3')
    WHEN 'align'      THEN p_val IN ('"center"','"right"','"justify"')
    WHEN 'list'       THEN p_val IN ('"bullet"','"ordered"')
    WHEN 'link'       THEN jsonb_typeof(p_val) = 'string'
                           AND char_length(p_val #>> '{}') <= 2048
                           AND (p_val #>> '{}') ~* '^https?://[^[:space:]]+$'
    ELSE false
  END;
$$;
REVOKE ALL ON FUNCTION public.planning_delta_attribute_ok(text, jsonb) FROM PUBLIC, anon, authenticated;

-- Validates a Quill Delta against the spec §6.1 whitelist and returns
-- its plain-text projection (trailing newlines trimmed).
CREATE OR REPLACE FUNCTION public.planning_validate_delta(p_delta jsonb)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_op    jsonb;
  v_key   text;
  v_val   jsonb;
  v_plain text := '';
  v_last  text := '';
BEGIN
  IF p_delta IS NULL OR jsonb_typeof(p_delta) <> 'array'
     OR jsonb_array_length(p_delta) = 0 OR jsonb_array_length(p_delta) > 2000 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
  END IF;
  FOR v_op IN SELECT value FROM jsonb_array_elements(p_delta) LOOP
    IF jsonb_typeof(v_op) <> 'object' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(v_op) LOOP
      IF v_key NOT IN ('insert', 'attributes') THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
      END IF;
    END LOOP;
    IF jsonb_typeof(v_op -> 'insert') IS DISTINCT FROM 'string' THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"embed"}');
    END IF;
    IF v_op ? 'attributes' THEN
      IF jsonb_typeof(v_op -> 'attributes') <> 'object' THEN
        PERFORM public.planning_v2_fail('invalid_input', '{"field":"attribute"}');
      END IF;
      FOR v_key, v_val IN SELECT key, value FROM jsonb_each(v_op -> 'attributes') LOOP
        IF NOT public.planning_delta_attribute_ok(v_key, v_val) THEN
          PERFORM public.planning_v2_fail('invalid_input',
            jsonb_build_object('field', 'attribute', 'attribute', v_key));
        END IF;
      END LOOP;
    END IF;
    v_last := v_op ->> 'insert';
    v_plain := v_plain || v_last;
  END LOOP;
  IF right(v_last, 1) <> E'\n' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"delta"}');
  END IF;
  v_plain := regexp_replace(v_plain, E'\n+$', '');
  IF char_length(v_plain) > 10000 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"text_plain_chars"}');
  END IF;
  RETURN v_plain;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_validate_delta(jsonb) FROM PUBLIC, anon, authenticated;

-- Per-type block validation. P1 accepts text / checklist / date only;
-- P3 and P4 extend this function (CREATE OR REPLACE) for their types.
CREATE OR REPLACE FUNCTION public.planning_v2_validate_block(
  p_type text, p_payload jsonb, p_date_start date, p_date_end date
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_key text;
BEGIN
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}');
  END IF;
  IF octet_length(p_payload::text) > 16384 THEN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"payload_bytes"}');
  END IF;

  IF p_type = 'text' THEN
    FOR v_key IN SELECT jsonb_object_keys(p_payload) LOOP
      IF v_key <> 'delta' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}'); END IF;
    END LOOP;
    IF p_date_start IS NOT NULL OR p_date_end IS NOT NULL THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN public.planning_validate_delta(p_payload -> 'delta');
  ELSIF p_type IN ('checklist', 'date') THEN
    FOR v_key IN SELECT jsonb_object_keys(p_payload) LOOP
      IF v_key <> 'title' THEN PERFORM public.planning_v2_fail('invalid_input', '{"field":"payload"}'); END IF;
    END LOOP;
    IF p_payload ? 'title' AND (
         jsonb_typeof(p_payload -> 'title') <> 'string'
         OR char_length(btrim(p_payload ->> 'title')) NOT BETWEEN 1 AND 80) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"title"}');
    END IF;
    IF p_type = 'checklist' AND (p_date_start IS NOT NULL OR p_date_end IS NOT NULL) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    IF p_type = 'date' AND p_date_end IS NOT NULL
       AND (p_date_start IS NULL OR p_date_end < p_date_start) THEN
      PERFORM public.planning_v2_fail('invalid_input', '{"field":"date"}');
    END IF;
    RETURN NULL;
  END IF;

  PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_validate_block(text, jsonb, date, date) FROM PUBLIC, anon, authenticated;

-- Per-block-type item validation. P1: checklist items only.
CREATE OR REPLACE FUNCTION public.planning_v2_validate_item(
  p_block_type text, p_relationship_id uuid, p_text text, p_section text, p_assigned_to uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_block_type <> 'checklist' THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"block_type"}');
  END IF;
  IF p_text IS NULL OR char_length(btrim(p_text)) NOT BETWEEN 1 AND 500 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"text"}');
  END IF;
  IF p_section IS NOT NULL AND char_length(btrim(p_section)) NOT BETWEEN 1 AND 40 THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"section"}');
  END IF;
  IF p_assigned_to IS NOT NULL AND NOT public.planning_v2_is_member(p_relationship_id, p_assigned_to) THEN
    PERFORM public.planning_v2_fail('invalid_input', '{"field":"assigned_to"}');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.planning_v2_validate_item(text, uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
