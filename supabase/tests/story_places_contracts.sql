-- supabase/tests/story_places_contracts.sql
-- Couple map story places (spec 2026-10-16 §4.5, §5.2). Every check RAISEs.
-- Runs on $SCRATCH/pg/run6.sh (stories + storage stubs).
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users(id) VALUES
  ('5c000000-0000-0000-0000-0000000000a1'), ('5c000000-0000-0000-0000-0000000000b2'),
  ('5c000000-0000-0000-0000-0000000000c3') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('5c000000-0000-0000-0000-0000000000a1', '+15550005001', 'Ama'),
  ('5c000000-0000-0000-0000-0000000000b2', '+15550005002', 'Kofi'),
  ('5c000000-0000-0000-0000-0000000000c3', '+15550005003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships(id, user_a, user_b, status) VALUES
  ('5c100000-0000-0000-0000-000000000001', '5c000000-0000-0000-0000-0000000000a1',
   '5c000000-0000-0000-0000-0000000000b2', 'active') ON CONFLICT (id) DO NOTHING;
UPDATE public.feature_flags SET enabled = true WHERE key IN ('stories', 'couple_map_enabled');

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

-- Posts one image story as p_user (intents, stamped objects, finalize) and
-- returns create_story_item's jsonb. p_client lets a test replay the same id.
CREATE FUNCTION pg_temp.post_story(p_user uuid, p_place jsonb, p_client uuid DEFAULT gen_random_uuid())
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_rel uuid := '5c100000-0000-0000-0000-000000000001'; r jsonb; mid uuid; mkey text; tid uuid; tkey text;
BEGIN
  PERFORM pg_temp.as_user(p_user);
  r := public.create_story_upload_intent(v_rel, 'media', 'image', 'image/jpeg');
  mid := (r->>'intent_id')::uuid; mkey := r->>'storage_key';
  r := public.create_story_upload_intent(v_rel, 'thumbnail', 'image', 'image/jpeg');
  tid := (r->>'intent_id')::uuid; tkey := r->>'storage_key';
  RESET ROLE;
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES
    ('story-media', mkey, jsonb_build_object('size', 100000, 'mimetype', 'image/jpeg')),
    ('story-media', tkey, jsonb_build_object('size', 10000, 'mimetype', 'image/jpeg'));
  PERFORM pg_temp.as_user(p_user);
  r := public.create_story_item(v_rel, p_client, mid, tid, 1080, 1920, NULL, 0, p_place);
  RESET ROLE;
  RETURN r;
END $$;

-- P1. Shape and lock-down: the table exists, clients can't write it, anon can't call.
DO $$
BEGIN
  IF to_regclass('public.story_places') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story_places missing';
  END IF;
  IF has_table_privilege('authenticated', 'public.story_places', 'INSERT')
     OR has_table_privilege('authenticated', 'public.story_places', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.story_places', 'DELETE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write story_places directly';
  END IF;
  IF has_function_privilege('anon', 'public.list_story_places(uuid,uuid,numeric,numeric,numeric,numeric,int)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.clear_story_place(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon can reach story places';
  END IF;
  IF to_regprocedure('public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 8-argument overload still exists (PGRST203 ambiguity)';
  END IF;
  IF has_function_privilege('authenticated', 'public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can call the core directly (bypassing place rules)';
  END IF;
END $$;

-- P2. A story posted with a place stores it exactly; without one, nothing.
DO $$
DECLARE r jsonb; v public.story_places%ROWTYPE; n int;
BEGIN
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1',
         '{"lat": 5.556123, "lng": -0.196789, "label": "Near Osu, Accra"}');
  SELECT * INTO v FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  IF v.lat IS DISTINCT FROM 5.556123 OR v.lng IS DISTINCT FROM -0.196789 OR v.label IS DISTINCT FROM 'Near Osu, Accra'
     OR v.author_id IS DISTINCT FROM '5c000000-0000-0000-0000-0000000000a1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: place not stored exactly: %', row_to_json(v);
  END IF;
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', NULL);
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a place appeared without one being sent'; END IF;
END $$;

-- P3. No backfill: a replay of the same client id never adds or changes a place.
DO $$
DECLARE c uuid := gen_random_uuid(); r1 jsonb; r2 jsonb; n int; v text;
BEGIN
  r1 := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', NULL, c);
  r2 := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 1, "lng": 1, "label": "Late"}', c);
  IF (r2->>'existing')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'setup: replay did not report existing: %', r2;
  END IF;
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r1->>'story_id')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a replay backfilled a place'; END IF;
  -- And a replay with a different place leaves the original alone.
  c := gen_random_uuid();
  r1 := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 2, "lng": 2, "label": "First"}', c);
  r2 := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 3, "lng": 3, "label": "Second"}', c);
  SELECT label INTO v FROM public.story_places WHERE story_item_id = (r1->>'story_id')::uuid;
  IF v IS DISTINCT FROM 'First' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a replay changed the place to %', v; END IF;
END $$;

-- P4. Malformed places are dropped and the story still posts (never failedPermanent).
DO $$
DECLARE r jsonb; n int; bad jsonb;
BEGIN
  FOREACH bad IN ARRAY ARRAY[
    '{"lat": 91, "lng": 0, "label": "x"}', '{"lat": 0, "lng": 181, "label": "x"}',
    '{"lat": "5", "lng": 0, "label": "x"}', '{"lat": 0, "lng": 0, "label": "   "}',
    '{"lat": 0, "lng": 0}', '[1,2]', '"text"']::jsonb[]
  LOOP
    r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', bad);
    IF (r->>'error') IS NOT DISTINCT FROM 'true' OR (r->>'story_id') IS NULL THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: malformed place % blocked the story: %', bad, r;
    END IF;
    SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
    IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: malformed place % was stored', bad; END IF;
  END LOOP;
  -- A label over 120 characters is trimmed, not refused.
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1',
         jsonb_build_object('lat', 4, 'lng', 4, 'label', repeat('a', 300)));
  IF (SELECT char_length(label) FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid) <> 120 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: long label not trimmed to 120';
  END IF;
END $$;

-- P4b. The parser itself drops out-of-range input (not only the table CHECK).
DO $$
BEGIN
  IF (SELECT lat FROM public.story_place_parse('{"lat": 91, "lng": 0, "label": "x"}')) IS NOT NULL
     OR (SELECT lat FROM public.story_place_parse('{"lat": 0, "lng": -181, "label": "x"}')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: story_place_parse accepted an out-of-range coordinate';
  END IF;
END $$;

-- P5. Flag off: places are dropped (rollback), the story still posts.
DO $$
DECLARE r jsonb; n int;
BEGIN
  UPDATE public.feature_flags SET enabled = false WHERE key = 'couple_map_enabled';
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 5, "lng": 5, "label": "Off"}');
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'couple_map_enabled';
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a place was stored with the flag off'; END IF;
END $$;

-- P6. The partner reads places; the list carries the story fields; an outsider gets nothing.
DO $$
DECLARE n int; m int; sig_before bigint; sig_after bigint; r jsonb;
BEGIN
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000b2', '{"lat": 6.5, "lng": 3.3, "label": "Near Ikoyi, Lagos"}');
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO n FROM public.list_story_places('5c100000-0000-0000-0000-000000000001', NULL, -90, -180, 90, 180);
  SELECT count(*) INTO m FROM public.list_story_places('5c100000-0000-0000-0000-000000000001',
    '5c000000-0000-0000-0000-0000000000b2', -90, -180, 90, 180) WHERE thumbnail_key IS NOT NULL AND media_key IS NOT NULL;
  RESET ROLE;
  IF n < 2 OR m <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner list wrong (all %, Kofi %)', n, m; END IF;
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO n FROM public.list_story_places('5c100000-0000-0000-0000-000000000001', NULL, -90, -180, 90, 180);
  RESET ROLE;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider saw % places', n; END IF;
  -- Clearing bumps the story signal so the partner's map refreshes.
  SELECT version INTO sig_before FROM public.story_change_signals WHERE relationship_id = '5c100000-0000-0000-0000-000000000001';
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000b2');
  PERFORM public.clear_story_place((r->>'story_id')::uuid);
  RESET ROLE;
  SELECT version INTO sig_after FROM public.story_change_signals WHERE relationship_id = '5c100000-0000-0000-0000-000000000001';
  IF sig_after IS NOT DISTINCT FROM sig_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing a place did not bump the story signal';
  END IF;
END $$;

-- P7. Only the author clears; a non-author's call is a silent no-op; clearing is idempotent.
DO $$
DECLARE r jsonb; n int;
BEGIN
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 7, "lng": 7, "label": "Mine"}');
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000b2');
  PERFORM public.clear_story_place((r->>'story_id')::uuid);
  RESET ROLE;
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the partner removed the author''s place'; END IF;
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  PERFORM public.clear_story_place((r->>'story_id')::uuid);
  PERFORM public.clear_story_place((r->>'story_id')::uuid);
  RESET ROLE;
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the author could not remove their place'; END IF;
END $$;

-- P8. Remove all my places removes only mine, and returns how many.
DO $$
DECLARE mine int; theirs_before int; theirs_after int; removed int;
BEGIN
  PERFORM pg_temp.post_story('5c000000-0000-0000-0000-0000000000b2', '{"lat": 8, "lng": 8, "label": "Kofi"}');
  SELECT count(*) INTO theirs_before FROM public.story_places WHERE author_id = '5c000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  removed := public.clear_my_story_places('5c100000-0000-0000-0000-000000000001');
  RESET ROLE;
  SELECT count(*) INTO mine FROM public.story_places WHERE author_id = '5c000000-0000-0000-0000-0000000000a1';
  SELECT count(*) INTO theirs_after FROM public.story_places WHERE author_id = '5c000000-0000-0000-0000-0000000000b2';
  IF mine <> 0 OR theirs_after <> theirs_before OR removed < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: remove-all wrong (mine %, theirs % -> %, removed %)', mine, theirs_before, theirs_after, removed;
  END IF;
END $$;

-- P9. Deleting the story removes its place (soft delete through delete_story_item).
DO $$
DECLARE r jsonb; n int;
BEGIN
  r := pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 9, "lng": 9, "label": "Gone"}');
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  PERFORM public.delete_story_item((r->>'story_id')::uuid);
  RESET ROLE;
  SELECT count(*) INTO n FROM public.story_places WHERE story_item_id = (r->>'story_id')::uuid;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted story kept its place'; END IF;
END $$;

-- P10. The bounding box is required and the list is capped at 500.
DO $$
DECLARE n int;
BEGIN
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO n FROM public.list_story_places('5c100000-0000-0000-0000-000000000001', NULL, NULL, NULL, NULL, NULL);
  RESET ROLE;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a list without a bounding box returned % rows', n; END IF;
  PERFORM pg_temp.as_user('5c000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO n FROM public.list_story_places('5c100000-0000-0000-0000-000000000001', NULL, 6, 3, 7, 4);
  RESET ROLE;
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the bounding box did not filter (% rows)', n; END IF;
  IF position('LEAST(GREATEST(COALESCE(p_limit, 500), 1), 500)' IN pg_get_functiondef('public.list_story_places(uuid,uuid,numeric,numeric,numeric,numeric,int)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: list is not capped at 500';
  END IF;
END $$;

-- P11. EXPLAIN uses the relationship index (checklist 3.3), recorded in the ledger.
-- Before the purge below, on an analysed table.
ANALYZE public.story_places;
-- A handful of rows always plans a seq scan; prove the index is usable.
SET LOCAL enable_seqscan = off;
EXPLAIN SELECT * FROM public.story_places WHERE relationship_id = '5c100000-0000-0000-0000-000000000001' AND lat BETWEEN -90 AND 90;
RESET enable_seqscan;


-- P12. Closing the relationship purges every place (last: it ends the couple).
DO $$
DECLARE n int;
BEGIN
  PERFORM pg_temp.post_story('5c000000-0000-0000-0000-0000000000a1', '{"lat": 10, "lng": 10, "label": "Before"}');
  UPDATE public.relationships SET status = 'ended' WHERE id = '5c100000-0000-0000-0000-000000000001';
  SELECT count(*) INTO n FROM public.story_places WHERE relationship_id = '5c100000-0000-0000-0000-000000000001';
  IF n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: % places survived the relationship ending', n; END IF;
END $$;

ROLLBACK;
