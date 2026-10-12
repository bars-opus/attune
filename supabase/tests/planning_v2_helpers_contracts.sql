-- Planning v2 helper contracts (P1 Task 2).
\set ON_ERROR_STOP on

BEGIN;
DO $$
DECLARE
  v_rel uuid := '2b000000-0000-0000-0000-000000000001';
  v_ended uuid := '2b000000-0000-0000-0000-000000000002';
  v_a uuid := '2b000000-0000-0000-0000-0000000000a1';
  v_b uuid := '2b000000-0000-0000-0000-0000000000b1';
  v_x uuid := '2b000000-0000-0000-0000-0000000000e1';
  v_keys text[];
  v_k text;
  v_lo text;
  v_hi text;
  v_i int;
  v_plain text;
  v_msg text;
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_a,'v2h_a@t.test'),(v_b,'v2h_b@t.test'),(v_x,'v2h_x@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.users (id, phone, display_name) VALUES
    (v_a,'+12100000001','A'),(v_b,'+12100000002','B'),(v_x,'+12100000003','X')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status) VALUES
    (v_rel, v_a, v_b, 'active'), (v_ended, v_a, v_x, 'ended')
  ON CONFLICT DO NOTHING;

  -- Contract 1: limits are exactly the spec's values.
  IF public.planning_limits() <> '{"categories":50,"blocks_per_entry":200,"items_per_block":500,
      "payload_bytes":16384,"table_columns":12,"table_rows":50,"photos_per_block":10,
      "image_bytes":10485760,"text_plain_chars":10000,"entries_page_default":30,
      "entries_page_max":100,"title_chars":120,"category_name_chars":40,
      "item_text_chars":500,"section_chars":40,"pinned_per_category":20}'::jsonb THEN
    RAISE EXCEPTION 'EXPLOIT: planning_limits drifted from spec';
  END IF;

  -- Contract 2: actor resolution. Unauthenticated, stranger, ended, member.
  PERFORM set_config('request.jwt.claims', '{}', true);
  BEGIN PERFORM public.planning_v2_actor(v_rel); RAISE EXCEPTION 'EXPLOIT: anon resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:unauthenticated' THEN RAISE EXCEPTION 'EXPLOIT: wrong code %', SQLERRM; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_x), true);
  BEGIN PERFORM public.planning_v2_actor(v_rel); RAISE EXCEPTION 'EXPLOIT: stranger resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:not_found' THEN RAISE EXCEPTION 'EXPLOIT: stranger got %', SQLERRM; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_a), true);
  BEGIN PERFORM public.planning_v2_actor(v_ended); RAISE EXCEPTION 'EXPLOIT: ended resolved';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:inactive' THEN RAISE EXCEPTION 'EXPLOIT: ended got %', SQLERRM; END IF;
  END;
  IF public.planning_v2_actor(v_rel) <> v_a THEN RAISE EXCEPTION 'EXPLOIT: member not resolved'; END IF;

  -- Contract 3: the HINT carries the detail as JSON.
  BEGIN
    PERFORM public.planning_v2_fail('limit_reached', '{"limit":"blocks_per_entry"}');
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = PG_EXCEPTION_HINT;
    IF v_msg::jsonb ->> 'limit' IS DISTINCT FROM 'blocks_per_entry' THEN
      RAISE EXCEPTION 'EXPLOIT: hint lost detail: %', v_msg;
    END IF;
  END;

  -- Contract 4 (property, checklist 6.5): 1000 random insertions always
  -- produce a key strictly between its neighbours, never ending in '0',
  -- never longer than 64.
  v_keys := ARRAY[public.planning_key_between(NULL, NULL)];
  FOR v_i IN 1..1000 LOOP
    DECLARE v_pos int := floor(random() * (array_length(v_keys,1) + 1))::int; BEGIN
      v_lo := CASE WHEN v_pos = 0 THEN NULL ELSE v_keys[v_pos] END;
      v_hi := CASE WHEN v_pos = array_length(v_keys,1) THEN NULL ELSE v_keys[v_pos+1] END;
      v_k := public.planning_key_between(v_lo, v_hi);
      IF (v_lo IS NOT NULL AND NOT (v_k COLLATE "C" > v_lo COLLATE "C"))
         OR (v_hi IS NOT NULL AND NOT (v_k COLLATE "C" < v_hi COLLATE "C"))
         OR right(v_k, 1) = '0' OR char_length(v_k) > 64 THEN
        RAISE EXCEPTION 'EXPLOIT: key % not between % and %', v_k, v_lo, v_hi;
      END IF;
      v_keys := v_keys[1:v_pos] || v_k || v_keys[v_pos+1:];
    END;
  END LOOP;

  -- Contract 5: worst case, 500 inserts always at the top stay ≤ 64 chars
  -- only with rebalancing; key_between alone must at least stay valid.
  v_k := public.planning_key_between(NULL, NULL);
  FOR v_i IN 1..60 LOOP v_k := public.planning_key_between(NULL, v_k); END LOOP;
  IF char_length(v_k) > 20 THEN RAISE EXCEPTION 'EXPLOIT: top-insert growth too fast: %', char_length(v_k); END IF;

  -- Contract 6: even keys are strictly increasing, 2 chars, none ends in '0'.
  v_keys := public.planning_even_keys(700);
  FOR v_i IN 2..700 LOOP
    IF NOT (v_keys[v_i] COLLATE "C" > v_keys[v_i-1] COLLATE "C")
       OR char_length(v_keys[v_i]) <> 2 OR right(v_keys[v_i],1) = '0' THEN
      RAISE EXCEPTION 'EXPLOIT: even key % invalid at %', v_keys[v_i], v_i;
    END IF;
  END LOOP;

  -- Contract 7: valid Delta → plain text; trailing newline trimmed.
  v_plain := public.planning_validate_delta(
    '[{"insert":"Bali "},{"insert":"trip","attributes":{"bold":true,"background":"yellow"}},
      {"insert":"\n","attributes":{"header":2,"align":"center"}}]');
  IF v_plain <> 'Bali trip' THEN RAISE EXCEPTION 'EXPLOIT: plain projection wrong: %', v_plain; END IF;

  -- Contract 8: every forbidden shape is rejected as invalid_input.
  FOREACH v_k IN ARRAY ARRAY[
    '[{"insert":{"image":"x.png"}},{"insert":"\n"}]',                    -- embed
    '[{"insert":"a","attributes":{"font":"serif"}},{"insert":"\n"}]',    -- unknown attribute
    '[{"insert":"a","attributes":{"background":"#ff0000"}},{"insert":"\n"}]', -- hex colour
    '[{"insert":"a","attributes":{"link":"javascript:alert(1)"}},{"insert":"\n"}]',
    '[{"insert":"a","attributes":{"list":"checked"}},{"insert":"\n"}]',
    '[{"insert":"a","attributes":{"header":4}},{"insert":"\n"}]',
    '[{"insert":"no trailing newline"}]',
    '[{"insert":"a","retain":1},{"insert":"\n"}]',
    '{"ops":[]}',
    '[]'
  ] LOOP
    BEGIN
      PERFORM public.planning_validate_delta(v_k::jsonb);
      RAISE EXCEPTION 'EXPLOIT: delta accepted: %', v_k;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM NOT IN ('planning:invalid_input') THEN RAISE; END IF;
    END;
  END LOOP;

  -- Contract 9: plain length limit counts characters (emoji = 1 char each).
  v_plain := public.planning_validate_delta(jsonb_build_array(
    jsonb_build_object('insert', repeat('😀', 10000) || E'\n')));
  IF char_length(v_plain) <> 10000 THEN RAISE EXCEPTION 'EXPLOIT: emoji counted as bytes'; END IF;
  BEGIN
    PERFORM public.planning_validate_delta(jsonb_build_array(
      jsonb_build_object('insert', repeat('a', 10001) || E'\n')));
    RAISE EXCEPTION 'EXPLOIT: 10001 chars accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'planning:limit_reached' THEN RAISE; END IF;
  END;

  -- Contract 10 (unicode_lengths): an RTL + combining-mark section of 40
  -- characters is accepted by item validation.
  PERFORM public.planning_v2_validate_item('checklist', v_rel,
    'שלום עולם', repeat('é', 40), v_b);

  -- Contract 11: item validation rejects a non-member assignee and blank text.
  BEGIN PERFORM public.planning_v2_validate_item('checklist', v_rel, 'x', NULL, v_x);
    RAISE EXCEPTION 'EXPLOIT: stranger assignee accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.planning_v2_validate_item('checklist', v_rel, '   ', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: blank item accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 12: block validation: P1 types accepted, P3/P4 types refused.
  PERFORM public.planning_v2_validate_block('checklist', '{"title":"Packing"}', NULL, NULL);
  PERFORM public.planning_v2_validate_block('date', '{}', '2026-11-01', '2026-11-05');
  BEGIN PERFORM public.planning_v2_validate_block('budget', '{}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: P3 block type accepted in P1';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;
  BEGIN PERFORM public.planning_v2_validate_block('checklist', '{"title":"x","extra":1}', NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: unknown payload key accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'planning:invalid_input' THEN RAISE; END IF; END;

  -- Contract 13: helpers are not callable by clients; limits is.
  IF has_function_privilege('authenticated', 'public.planning_v2_actor(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.planning_validate_delta(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.planning_limits()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.planning_limits()', 'EXECUTE') THEN
    RAISE EXCEPTION 'EXPLOIT: helper grants wrong';
  END IF;

  RAISE NOTICE 'planning_v2_helpers_contracts: PASS';
END $$;
ROLLBACK;
