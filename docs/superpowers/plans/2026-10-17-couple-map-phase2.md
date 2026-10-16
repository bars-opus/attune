# Couple Map Phase 2 (Story places) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stories can be pinned to the couple map at their exact place:
- an opt-in "Pin to our map" switch on the story camera;
- clustered thumbnails on the Map tab, with a Both / Mine / Partner's filter;
- tapping a pin opens the stories;
- the author can remove a place, or all their places, for good.

**Architecture:**
- **Server:** a `story_places` table, written only inside `create_story_item`. The existing 8-argument function is renamed `create_story_item_core` and wrapped by the new 9-argument one, so the long body isn't copied. It's read through a caller-permission `list_story_places`, and cleared through two author-only RPCs.
- **Client:**
  - the outbox carries an optional place;
  - the camera has a `StoryPinController` and a toggle overlay;
  - the map seam gains `setStories` and story taps;
  - the reel gains a places mode with "Remove from map";
  - device-only settings (last pin choice, home area, hint seen) live in secure storage and are cleared by quick exit.

**Tech Stack:** PL/pgSQL (Supabase), Flutter, Riverpod 2.6, `mapbox_maps_flutter` 2.24.3, `geolocator` 14, `geocoding` 4, `flutter_secure_storage`.

**Spec:** `docs/superpowers/specs/2026-10-16-couple-map-design.md`: §2 ruling 2, §3.1 (Stories button), §3.3, §3.4 (stories hint), §3.5 (list story rows), §3.6, §4.5, §5.2, §6.2, §6.4, §8 (`story_places_contracts`), §9.

**Carried forward:** the Phase 0 and Phase 1 ledgers (`.superpowers/sdd/2026-10-16-couple-map-phase0/progress.md`, `…-phase1/progress.md`).

## Global Constraints

- **Pinning is opt-in per story.** The camera switch is off the first time, then remembers the author's last choice (`story_pin_last_choice`).
- The place is looked up **only after the switch is on** (or when the remembered choice is on). The lookup uses `geolocator` with the platform geocoder, never `LocationService`, which calls a third-party HTTP API.
- **Preview:** "Near {neighbourhood}, {city}" (for example "Near Osu, Accra").
- **While my area is paused:** the camera shows **"Your area is paused"** and the switch starts off.
- **Within about 500 m of the device-only home area:** the camera shows **"This looks near your home area"** and the switch turns off. The author may turn it back on.
- **No backfill.** A place is written only on a **fresh** `create_story_item` insert, never on a replay, and never when `couple_map_enabled` is off.
- **A malformed place never blocks the story:** it's dropped and the story still posts. The client also validates before enqueueing.
- **Only the author** can clear a place (`clear_story_place`) or all their places (`clear_my_story_places`). A non-author's call is a silent no-op, so it gives no existence oracle.
- **Deleting a story removes its place.** Ending or archiving the relationship purges every place.
- **Story pins:**
  - round thumbnails with **no dot**, so they never read as live;
  - they cluster as you zoom out;
  - tapping a pin or a cluster opens the reel over those stories, oldest first.
- **Cluster appearance (ruling):** the newest story's thumbnail, enlarged, with a count. Mapbox clusters can't stack several images. The spec's "stacked thumbnails" is amended to match.
- **The Stories filter button** cycles Both → Mine → Partner's, the icon shows the current choice, and it's hidden while no story is pinned.
- **"Remove from map"** is a second icon, shown only to the author, next to Delete in the reel. **"Remove all my places"** is in the Sharing sheet, behind a confirmation.
- **Quick exit** clears the last pin choice, the home area, the stories-hint flag, cached pins and the Mapbox cache. It never touches the server.
- **Never log coordinates, place labels or city names** (checklist 4.4).
- **Known limit (deferred to a minor):** a permanently denied permission and iOS reduced accuracy both show "Couldn't find this place". A dedicated "Allow location for Attune to pin places" notice is a Phase 3 polish item.
- **Fetching (ruling):** `list_story_places` requires a bounding box and caps at 500. The client asks for the world box (−90, −180, 90, 180), the newest 500, because a couple's pins fit easily. The bounding box stays available for later viewport fetching.
- **No commits.** Work on `main`, test first, format only touched files, and filter the analyzer with `grep -E "^\s*(error|warning) "`.
- **SQL contracts** run on `$SCRATCH/pg/run6.sh`, the stories harness built while planning:
  - `stubs2` + `storage_stub.sql` (storage schema, `pgcrypto`, `cron.unschedule(text)`);
  - the location migrations, then `messages_cols_stub.sql`;
  - the `20260938*`/`20260939*`/`20260940120000`/`20260951010000` stories migrations, then `202610141[1-9]*`, `20261015*`, `20261016*` and `20261017*` (the last glob was added to `run6.sh` after the plan review, so this migration is applied);
  - `$SCRATCH` = `/private/tmp/claude-501/-Users-user-attune/ae9d44ca-41d8-47c2-b3e9-e1303709b261/scratchpad`.

## Review Focus

1. **An outbox record queued before this release** (no place field) is replayed after the upgrade. It must decode, post without a place, and never fail. Test: Task 3, "an old record without a place still decodes".
2. **The finalize call is retried after a lost response.** The replay returns `existing: true` and must not write a place a second time or a different one. Contract: Task 1, P3.
3. **Turning the switch on with location permission denied, or no fix within the time limit.** The preview shows "Couldn't find this place", the story still posts without a place, and nothing crashes. Test: Task 5, "no fix: the story posts without a place".
4. **The author removes a place while the partner has the map open.** The partner's pin goes on their next signal or refresh, and the author's pin goes at once. The reel steps off the item. Tests: Task 7, "remove from map takes it off and closes the last one"; Task 1, P6 (the change signal is bumped).
5. **Both filter, then Mine, while clusters are showing.** Cluster counts reflect only the filtered set, because the source data is rebuilt, not filtered by a layer. Test: Task 8, "the filter cycles and rebuilds the story set".

---

## File structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20261017100000_story_places.sql` (new) | Table, RLS, parse helper, `create_story_item` wrapper, delete trigger, clear RPCs, list RPC, purge extension |
| `supabase/tests/story_places_contracts.sql` (new) | P1–P12 contracts |
| `supabase/tests/story_rpc_contracts.sql` (modify) | Signature references updated to the 9-argument function |
| `lib/features/couple_map/domain/story_place.dart` (new) | `StoryPlace`, `StoryPlaceDraft`, `StoryFilter`, `placeLabel`, `HomeArea` |
| `lib/features/couple_map/domain/couple_map_config.dart` (modify) | `homeAreaRadiusM`, `placesLimit`, `storyPinSize`, `placeFixTimeout` |
| `lib/features/stories/data/story_outbox_record.dart` (modify) | Optional `place` |
| `lib/features/stories/data/story_repository.dart` (modify) | `finalizeStory(..., place)` sends `p_place` only when set |
| `lib/features/stories/presentation/state/story_outbox_controller.dart` (modify) | Passes `record.place` |
| `lib/features/couple_map/data/story_places_repository.dart` (new) | list, clear one, clear all, through a gateway |
| `lib/features/couple_map/data/couple_map_local_store.dart` (new) | Device-only key/value (secure storage) and its keys |
| `lib/features/couple_map/data/story_place_resolver.dart` (new) | Fix plus geocode to `StoryPlaceDraft` |
| `lib/features/couple_map/data/couple_map_device_data.dart` (modify) | Also clears the local store |
| `lib/features/couple_map/presentation/providers/story_places_providers.dart` (new) | Gateway, repository, store, resolver, `storyPlacesProvider` |
| `lib/features/couple_map/presentation/camera/story_pin_controller.dart` (new) | Switch state machine |
| `lib/features/couple_map/presentation/camera/story_pin_toggle.dart` (new) | Camera overlay |
| `lib/features/stories/presentation/screens/story_camera_screen.dart` (modify) | Hosts the toggle; attaches the place at enqueue |
| `lib/features/couple_map/presentation/widgets/pin_image_renderer.dart` (modify) | `PinSpec.cacheKey`; `renderRaw` (RGBA) |
| `lib/features/couple_map/domain/couple_map_scene.dart` (modify) | `StoryScenePin`, `storiesGeoJson` |
| `lib/features/couple_map/presentation/map/couple_map_controller.dart` (modify) | `setStories`; builder `onStoriesTapped` |
| `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart` (modify) | Clustered story source and layers, tap query |
| `lib/features/stories/presentation/screens/story_reel_screen.dart` (modify) | `StoryReelScreen.forPlaces`; "Remove from map" |
| `lib/features/couple_map/presentation/screens/couple_map_tab.dart` (modify) | Filter button, story pins, taps, hint |
| `lib/features/couple_map/presentation/widgets/couple_map_list_sheet.dart` (modify) | Story rows by day |
| `lib/features/couple_map/presentation/widgets/sharing_sheet.dart` (modify) | "Remove all my places", home-area rows |
| `test/features/couple_map/support/fakes.dart` (modify) | Fakes for stories, the store and the resolver |

**Regression risk (flagged):**
- `create_story_item` changes for every client. Older apps call the 8-argument form, which PostgREST resolves to the new function because `p_place` defaults to null. The client sends `p_place` only when a place is attached, so a client released before the migration is deployed still works.
- `story_camera_screen.dart` and `story_reel_screen.dart` are shared story surfaces. The toggle renders only with the flag on, so existing camera tests are unaffected. The reel's author and day modes are untouched; places mode is additive.
- `StoryGateway.finalizeStory` gains a parameter, so 4 test fakes need it (listed in Task 3).
- The Phase 1 tab tests need the new providers overridden (Task 8).

---

### Task 1: The `story_places` migration and its contracts

**Files:**
- Create: `supabase/migrations/20261017100000_story_places.sql`, `supabase/tests/story_places_contracts.sql`
- Modify: `supabase/tests/story_rpc_contracts.sql` (the two `has_function_privilege` signature strings, about lines 355 and 359)

**Interfaces:**
- Produces (SQL):
  - `create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb DEFAULT NULL) → jsonb`
  - `clear_story_place(uuid) → void`
  - `clear_my_story_places(uuid) → int`
  - `list_story_places(p_relationship_id uuid, p_author_id uuid, p_min_lat numeric, p_min_lng numeric, p_max_lat numeric, p_max_lng numeric, p_limit int DEFAULT 500)`, which returns `story_item_id, author_id, lat, lng, label, placed_at, client_story_id, media_type, media_key, thumbnail_key, media_width, media_height, duration_ms, occurred_on, created_at, expires_at`
- `p_place` JSON: `{"lat": number, "lng": number, "label": string}`.

- [ ] **Step 1: Write the failing contracts**

```sql
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
EXPLAIN SELECT * FROM public.story_places WHERE relationship_id = '5c100000-0000-0000-0000-000000000001' AND lat BETWEEN -90 AND 90;


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
```

In `story_rpc_contracts.sql`, replace both `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int)'` strings with `'public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb)'`.

- [ ] **Step 2: Run them and confirm they fail.** `bash $SCRATCH/pg/run6.sh supabase/tests/story_places_contracts.sql`. Expected: `FAIL` with `create_story_upload_intent`… or `story_places missing`, depending on order.
- [ ] **Step 3: Write the migration**

```sql
-- supabase/migrations/20261017100000_story_places.sql
-- Couple map, Phase 2: stories pinned at their exact place (spec 2026-10-16
-- §2 ruling 2, §4.5, §5.2). The author chooses each place at post time;
-- nothing is backfilled; the author can remove one or all; deleting the
-- story or closing the relationship removes them.

CREATE TABLE public.story_places (
  story_item_id   uuid PRIMARY KEY REFERENCES public.story_items(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  author_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lat             numeric(9,6) NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng             numeric(9,6) NOT NULL CHECK (lng BETWEEN -180 AND 180),
  label           text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 120),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX story_places_relationship_idx ON public.story_places (relationship_id, lat, lng);
CREATE INDEX story_places_author_idx ON public.story_places (relationship_id, author_id);

ALTER TABLE public.story_places ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.story_places FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.story_places TO authenticated;
CREATE POLICY story_places_read_members ON public.story_places
  FOR SELECT TO authenticated
  USING (public.story_relationship_is_open(relationship_id, auth.uid()));

-- A client place, or NULLs when anything is off. Malformed input is
-- dropped, never raised: the story must still post.
CREATE OR REPLACE FUNCTION public.story_place_parse(
  p_place jsonb, OUT lat numeric, OUT lng numeric, OUT label text)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v_lat double precision; v_lng double precision; v_label text;
BEGIN
  IF p_place IS NULL OR jsonb_typeof(p_place) IS DISTINCT FROM 'object'
     OR jsonb_typeof(p_place->'lat') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_place->'lng') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_place->'label') IS DISTINCT FROM 'string' THEN
    RETURN;
  END IF;
  v_lat := (p_place->>'lat')::double precision;
  v_lng := (p_place->>'lng')::double precision;
  v_label := btrim(p_place->>'label');
  IF v_lat NOT BETWEEN -90 AND 90 OR v_lng NOT BETWEEN -180 AND 180 OR v_label = '' THEN
    RETURN;
  END IF;
  lat := round(v_lat::numeric, 6);
  lng := round(v_lng::numeric, 6);
  label := left(v_label, 120);
END $$;
REVOKE ALL ON FUNCTION public.story_place_parse(jsonb) FROM PUBLIC, anon, authenticated;

-- The 8-argument finalize becomes the core; the public name gains p_place.
-- Renaming (not copying) keeps the long, reviewed body exactly as it is,
-- and leaves no 8-argument overload for PostgREST to find ambiguous
-- (PGRST203). Older apps' 8-parameter calls resolve to the new function,
-- since p_place defaults to null.
ALTER FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int)
  RENAME TO create_story_item_core;
REVOKE ALL ON FUNCTION public.create_story_item_core(uuid, uuid, uuid, uuid, int, int, int, int)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_story_item(
  p_relationship_id     uuid,
  p_client_story_id     uuid,
  p_media_intent_id     uuid,
  p_thumbnail_intent_id uuid,
  p_media_width         int,
  p_media_height        int,
  p_duration_ms         int,
  p_utc_offset_minutes  int,
  p_place               jsonb DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, storage AS $$
DECLARE v_res jsonb; v_place record;
BEGIN
  v_res := public.create_story_item_core(
    p_relationship_id, p_client_story_id, p_media_intent_id, p_thumbnail_intent_id,
    p_media_width, p_media_height, p_duration_ms, p_utc_offset_minutes);
  -- A place only on a FRESH insert: a replay never adds one (no backfill).
  IF p_place IS NULL
     OR (v_res->>'error') IS NOT DISTINCT FROM 'true'
     OR (v_res->>'existing')::boolean IS DISTINCT FROM false THEN
    RETURN v_res;
  END IF;
  -- Behind the couple map flag: turning it off stops new places (rollback).
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key = 'couple_map_enabled' AND enabled) THEN
    RETURN v_res;
  END IF;
  SELECT * INTO v_place FROM public.story_place_parse(p_place);
  IF v_place.lat IS NULL THEN
    RETURN v_res;
  END IF;
  BEGIN
    INSERT INTO public.story_places (story_item_id, relationship_id, author_id, lat, lng, label)
    VALUES ((v_res->>'story_id')::uuid, p_relationship_id, auth.uid(),
            v_place.lat, v_place.lng, v_place.label);
  EXCEPTION WHEN others THEN
    NULL; -- never fatal to the story
  END;
  RETURN v_res;
END $$;
REVOKE ALL ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_story_item(uuid, uuid, uuid, uuid, int, int, int, int, jsonb)
  TO authenticated;

-- Deleting a story (soft delete) removes its place for good.
CREATE OR REPLACE FUNCTION public.story_places_drop_on_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
    DELETE FROM public.story_places WHERE story_item_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.story_places_drop_on_delete() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS story_places_drop_on_delete ON public.story_items;
CREATE TRIGGER story_places_drop_on_delete
  AFTER UPDATE OF deleted_at ON public.story_items
  FOR EACH ROW EXECUTE FUNCTION public.story_places_drop_on_delete();

-- The author removes one place. A non-author's call removes nothing and
-- says nothing (no existence oracle). Idempotent.
CREATE OR REPLACE FUNCTION public.clear_story_place(p_story_item_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rel uuid;
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.story_places
   WHERE story_item_id = p_story_item_id AND author_id = auth.uid()
  RETURNING relationship_id INTO v_rel;
  IF v_rel IS NOT NULL THEN PERFORM public.bump_story_signal(v_rel); END IF;
END $$;

-- The author removes every place they pinned in this couple; returns how many.
CREATE OR REPLACE FUNCTION public.clear_my_story_places(p_relationship_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.story_places
   WHERE relationship_id = p_relationship_id AND author_id = auth.uid();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n > 0 THEN PERFORM public.bump_story_signal(p_relationship_id); END IF;
  RETURN v_n;
END $$;

-- Places in a box, newest first, at most 500. SECURITY INVOKER: RLS on
-- story_places and story_items (deleted_at, open relationship) applies.
CREATE OR REPLACE FUNCTION public.list_story_places(
  p_relationship_id uuid, p_author_id uuid,
  p_min_lat numeric, p_min_lng numeric, p_max_lat numeric, p_max_lng numeric,
  p_limit int DEFAULT 500)
RETURNS TABLE (
  story_item_id uuid, author_id uuid, lat numeric, lng numeric, label text, placed_at timestamptz,
  client_story_id uuid, media_type text, media_key text, thumbnail_key text,
  media_width int, media_height int, duration_ms int, occurred_on date,
  created_at timestamptz, expires_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT sp.story_item_id, sp.author_id, sp.lat, sp.lng, sp.label, sp.created_at,
         si.client_story_id, si.media_type, si.media_key, si.thumbnail_key,
         si.media_width, si.media_height, si.duration_ms, si.occurred_on,
         si.created_at, si.expires_at
    FROM public.story_places sp
    JOIN public.story_items si ON si.id = sp.story_item_id
   WHERE p_min_lat IS NOT NULL AND p_min_lng IS NOT NULL
     AND p_max_lat IS NOT NULL AND p_max_lng IS NOT NULL
     AND sp.relationship_id = p_relationship_id
     AND (p_author_id IS NULL OR sp.author_id = p_author_id)
     AND sp.lat BETWEEN p_min_lat AND p_max_lat
     AND sp.lng BETWEEN p_min_lng AND p_max_lng
   ORDER BY si.created_at DESC, si.id DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 500)
$$;

REVOKE ALL ON FUNCTION public.clear_story_place(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.clear_my_story_places(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_story_places(uuid, uuid, numeric, numeric, numeric, numeric, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clear_story_place(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_my_story_places(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_story_places(uuid, uuid, numeric, numeric, numeric, numeric, int) TO authenticated;

-- Closing the relationship purges presence (Phase 0) and story places.
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
    DELETE FROM public.story_places WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
```

- [ ] **Step 4: Run them and confirm they pass,** together with every story contract and the Phase 0 contracts:

```bash
bash $SCRATCH/pg/run6.sh supabase/tests/story_places_contracts.sql supabase/tests/story_rpc_contracts.sql \
  supabase/tests/story_schema_contracts.sql supabase/tests/story_security_contracts.sql \
  supabase/tests/story_read_contracts.sql supabase/tests/together_story_contracts.sql \
  supabase/tests/couple_map_presence_contracts.sql supabase/tests/location_presence_test.sql
```

Expected: every line is `PASS`. Record P11's EXPLAIN output (an index or bitmap scan on `story_places_relationship_idx`) in the ledger.

- [ ] **Step 5: Mutation checks** (checklist 6.8). Apply each mutation to a scratch copy, rerun, see the named contract fail, then restore:
  - remove the `existing` guard (P3);
  - drop the range check in `story_place_parse` (P4, `lat 91` stored);
  - remove `AND author_id = auth.uid()` in `clear_story_place` (P7);
  - drop the delete trigger (P9);
  - remove the `story_places` DELETE from the purge (P12);
  - remove the flag check (P5).

  Ledger each one as "caught by Pn".

---

### Task 2: Domain (place, draft, filter, label, home area)

**Files:**
- Create: `lib/features/couple_map/domain/story_place.dart`
- Modify: `lib/features/couple_map/domain/couple_map_config.dart`
- Test: `test/features/couple_map/story_place_test.dart`

**Interfaces:**
- Produces:
  - `class StoryPlaceDraft { final double lat, lng; final String label; Map<String, dynamic> toJson(); static StoryPlaceDraft? fromJson(Object?); bool get isValid; }`
  - `class StoryPlace { storyItemId, authorId, lat, lng, label, StoryItem story; factory StoryPlace.fromRow(Map) }`
  - `enum StoryFilter { both, mine, partner } (next, label, icon-free)`
  - `String placeLabel({String? neighbourhood, String? city})`
  - `class HomeArea { final double lat, lng; bool isNear(double lat, double lng) }`
  - `CoupleMapConfig.homeAreaRadiusM = 500`, `placesLimit = 500`, `storyPinSize = 52.0`, `placeFixTimeout = Duration(seconds: 20)`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/story_place_test.dart
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _row({String author = 'kofi'}) => {
      'story_item_id': 's1', 'author_id': author, 'lat': 5.556123, 'lng': -0.196789, 'label': 'Near Osu, Accra',
      'placed_at': '2026-10-16T10:00:00Z', 'client_story_id': 'c1', 'media_type': 'image',
      'media_key': 'r/a/m.jpg', 'thumbnail_key': 'r/a/t.jpg', 'media_width': 1080, 'media_height': 1920,
      'duration_ms': null, 'occurred_on': '2026-10-16', 'created_at': '2026-10-16T09:59:00Z',
      'expires_at': '2026-10-17T09:59:00Z',
    };

void main() {
  test('a row maps to a place carrying a playable story', () {
    final p = StoryPlace.fromRow({..._row(), 'relationship_id': 'r1'});
    expect((p.storyItemId, p.authorId, p.lat, p.lng, p.label), ('s1', 'kofi', 5.556123, -0.196789, 'Near Osu, Accra'));
    expect(p.story.id, 's1');
    expect(p.story.thumbnailKey, 'r/a/t.jpg');
    expect(p.story.relationshipId, 'r1');
  });

  test('the draft round-trips and validates like the server', () {
    const d = StoryPlaceDraft(lat: 5.556123, lng: -0.196789, label: 'Near Osu, Accra');
    expect(StoryPlaceDraft.fromJson(d.toJson())!.label, 'Near Osu, Accra');
    expect(d.isValid, isTrue);
    expect(const StoryPlaceDraft(lat: 91, lng: 0, label: 'x').isValid, isFalse);
    expect(const StoryPlaceDraft(lat: 0, lng: 0, label: '  ').isValid, isFalse);
    expect(StoryPlaceDraft.fromJson({'lat': 'x'}), isNull);
    expect(StoryPlaceDraft.fromJson(null), isNull);
  });

  test('a long label is trimmed to 120 on the device too', () {
    final d = StoryPlaceDraft(lat: 0, lng: 0, label: 'a' * 300);
    expect((d.toJson()['label'] as String).length, 120);
  });

  test('the filter cycles Both → Mine → Partner\'s → Both', () {
    expect(StoryFilter.both.next, StoryFilter.mine);
    expect(StoryFilter.mine.next, StoryFilter.partner);
    expect(StoryFilter.partner.next, StoryFilter.both);
  });

  test('labels are neighbourhood-level', () {
    expect(placeLabel(neighbourhood: 'Osu', city: 'Accra'), 'Near Osu, Accra');
    expect(placeLabel(neighbourhood: null, city: 'Accra'), 'Near Accra');
    expect(placeLabel(neighbourhood: 'Accra', city: 'Accra'), 'Near Accra');
    expect(placeLabel(neighbourhood: null, city: null), 'Pinned place');
  });

  test('home area: within about 500 m is near', () {
    const home = HomeArea(lat: 5.556, lng: -0.197);
    expect(home.isNear(5.559, -0.197), isTrue); // ~330 m
    expect(home.isNear(5.566, -0.197), isFalse); // ~1.1 km
  });

  test('a home area never prints its coordinates (checklist 4.4)', () {
    expect(const HomeArea(lat: 5.556, lng: -0.197).toString(), isNot(contains('5.5')));
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.** `flutter test test/features/couple_map/story_place_test.dart`. Expected: compilation error.

- [ ] **Step 3: Implement.** Append to `CoupleMapConfig`:

```dart
  /// The device-only home-area warning radius (spec §3.3, "about 500 m").
  static const homeAreaRadiusM = 500.0;

  /// list_story_places' server cap (checklist 2.5).
  static const placesLimit = 500;

  /// Story thumbnail pin diameter, logical pixels.
  static const storyPinSize = 52.0;

  /// The story-place fix (only after the switch is on).
  static const placeFixTimeout = Duration(seconds: 20);
```

```dart
// lib/features/couple_map/domain/story_place.dart
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/foundation.dart';

/// A place the author chose to attach at post time (exact, by choice).
@immutable
class StoryPlaceDraft {
  const StoryPlaceDraft({required this.lat, required this.lng, required this.label});
  final double lat;
  final double lng;
  final String label;

  /// Mirrors SQL story_place_parse, so the outbox never carries a place
  /// the server would drop.
  bool get isValid =>
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && label.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    final l = label.trim();
    return {'lat': lat, 'lng': lng, 'label': l.length > 120 ? l.substring(0, 120) : l};
  }

  static StoryPlaceDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final label = json['label'];
    if (lat is! num || lng is! num || label is! String) return null;
    return StoryPlaceDraft(lat: lat.toDouble(), lng: lng.toDouble(), label: label);
  }

  @override
  String toString() => 'StoryPlaceDraft(redacted)';
}

/// A pinned story, as list_story_places returns it.
@immutable
class StoryPlace {
  const StoryPlace({
    required this.storyItemId,
    required this.authorId,
    required this.lat,
    required this.lng,
    required this.label,
    required this.story,
  });
  final String storyItemId;
  final String authorId;
  final double lat;
  final double lng;
  final String label;
  final StoryItem story;

  factory StoryPlace.fromRow(Map<String, dynamic> r) => StoryPlace(
        storyItemId: '${r['story_item_id']}',
        authorId: '${r['author_id']}',
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lng'] as num).toDouble(),
        label: '${r['label']}',
        story: StoryItem.fromRow({
          ...r,
          'id': r['story_item_id'],
          // Map pins are memories, not unread rings.
          'has_been_viewed': true,
        }),
      );

  @override
  String toString() => 'StoryPlace($storyItemId)';
}

enum StoryFilter {
  both,
  mine,
  partner;

  StoryFilter get next => StoryFilter.values[(index + 1) % StoryFilter.values.length];
}

/// Neighbourhood-level label for the preview and the pin (spec §3.3).
String placeLabel({String? neighbourhood, String? city}) {
  final n = neighbourhood?.trim();
  final c = city?.trim();
  if (n != null && n.isNotEmpty && c != null && c.isNotEmpty && n != c) return 'Near $n, $c';
  if (c != null && c.isNotEmpty) return 'Near $c';
  if (n != null && n.isNotEmpty) return 'Near $n';
  return 'Pinned place';
}

/// The optional, device-only home area (spec §3.3). Never leaves the device.
@immutable
class HomeArea {
  const HomeArea({required this.lat, required this.lng});
  final double lat;
  final double lng;

  bool isNear(double lat, double lng) =>
      haversineKm(MapPoint(this.lat, this.lng), MapPoint(lat, lng)) * 1000 <=
      CoupleMapConfig.homeAreaRadiusM;

  @override
  String toString() => 'HomeArea(redacted)';
}
```

(`StoryItem.fromRow` reads `has_been_viewed`, `relationship_id` and `expires_at`, confirmed while planning. `list_story_places` doesn't return `relationship_id`, so the repository adds it (Task 4).)

- [ ] **Step 4: Run it and confirm it passes.**
- [ ] **Step 5: Ledger.**

---

### Task 3: The outbox carries a place; finalize sends it

**Files:**
- Modify: `lib/features/stories/data/story_outbox_record.dart`, `lib/features/stories/data/story_repository.dart`, `lib/features/stories/presentation/state/story_outbox_controller.dart`
- Modify (fakes gain the parameter): `test/features/stories/story_camera_test.dart:199`, `test/features/stories/story_outbox_controller_test.dart:123`, `test/features/stories/story_calendar_test.dart:875`, `test/features/stories/story_rings_test.dart:173`
- Test: `test/features/stories/story_outbox_place_test.dart`

**Interfaces:**
- Consumes: `StoryPlaceDraft` (Task 2).
- Produces:
  - `StoryOutboxRecord({…, StoryPlaceDraft? place})`
  - `StoryGateway.finalizeStory({…, Map<String, dynamic>? place})`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/stories/story_outbox_place_test.dart
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter_test/flutter_test.dart';

StoryOutboxRecord _record({StoryPlaceDraft? place}) => StoryOutboxRecord(
      clientStoryId: 'c1', relationshipId: 'r1', localMediaPath: '/m.jpg', localThumbnailPath: '/t.jpg',
      mediaType: CapturedMediaType.image, mimeType: 'image/jpeg', width: 1080, height: 1920,
      utcOffsetMinutes: 0, createdAt: DateTime.utc(2026, 10, 16), place: place);

void main() {
  test('a place survives the JSON round trip', () {
    final r = StoryOutboxRecord.fromJson(_record(
      place: const StoryPlaceDraft(lat: 5.556123, lng: -0.196789, label: 'Near Osu, Accra'),
    ).toJson());
    expect(r.place!.label, 'Near Osu, Accra');
    expect(r.place!.lat, 5.556123);
  });

  test('an old record without a place still decodes (Review Focus 1)', () {
    final json = _record().toJson()..remove('place');
    expect(StoryOutboxRecord.fromJson(json).place, isNull);
  });

  test('a corrupt place decodes as none rather than failing the record', () {
    final json = _record().toJson()..['place'] = {'lat': 'x'};
    expect(StoryOutboxRecord.fromJson(json).place, isNull);
  });

  test('copyWith keeps the place (retries must not drop it)', () {
    final r = _record(place: const StoryPlaceDraft(lat: 1, lng: 2, label: 'x'))
        .copyWith(attempts: 3, state: StoryOutboxState.finalizing);
    expect(r.place!.lng, 2);
  });
}
```

Add to `test/features/stories/story_repository_test.dart` (in its own style, using its fake Supabase RPC recorder; read the file first for the helper name):
- `finalizeStory` with `place: {'lat': 1.0, 'lng': 2.0, 'label': 'x'}` sends `p_place` equal to that map;
- without a place, the params contain **no** `p_place` key, so a client released before the migration is deployed keeps working.

Add to `test/features/stories/story_outbox_controller_test.dart`: a record enqueued with a place reaches the fake gateway's `finalizeStory` with `place` equal to `record.place!.toJson()`. Make the fake record `place` in its `finalizeCalls` map.

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/stories/`. Expected: compilation errors (`place`).

- [ ] **Step 3: Implement**

`story_outbox_record.dart`:
- add `import 'package:attune/features/couple_map/domain/story_place.dart';`;
- add the constructor parameter `this.place` and the field `/// Chosen at post time (couple map, spec §3.3); null when not pinned. final StoryPlaceDraft? place;`;
- `copyWith` passes `place: place`;
- `toJson` adds `if (place != null) 'place': place!.toJson(),`;
- `fromJson` adds `place: StoryPlaceDraft.fromJson(json['place']),`.

`story_repository.dart`:
- add `Map<String, dynamic>? place,` to the abstract `finalizeStory` and to the implementation;
- in params: `if (place != null) 'p_place': place,`, with the comment `// Only when pinned: a client shipped before the migration deploys must still finalize.`

`story_outbox_controller.dart` at the `finalizeStory` call: `place: current.place?.toJson(),`.

Each of the 4 fakes: add `Map<String, dynamic>? place,` to their `finalizeStory` signature. The controller-test fake also records `'place': place`.

- [ ] **Step 4: Run them and confirm they pass.** `flutter test test/features/stories/`.
- [ ] **Step 5: Ledger.**

---

### Task 4: Places data (repository, local store, resolver, providers, quick exit)

**Files:**
- Create: `lib/features/couple_map/data/story_places_repository.dart`, `lib/features/couple_map/data/couple_map_local_store.dart`, `lib/features/couple_map/data/story_place_resolver.dart`, `lib/features/couple_map/presentation/providers/story_places_providers.dart`
- Modify: `lib/features/couple_map/data/couple_map_device_data.dart`, `test/features/couple_map/support/fakes.dart`, `test/features/couple_map/couple_map_device_data_test.dart`
- Test: `test/features/couple_map/story_places_repository_test.dart`, `test/features/couple_map/couple_map_local_store_test.dart`

**Interfaces:**
- Produces:
  - `abstract class StoryPlacesGateway { Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}); }` (Supabase implementation)
  - `StoryPlacesRepository(StoryPlacesGateway)`:
    - `list(String rel, {String? authorId}) → Future<List<StoryPlace>>` (world box, limit 500, throws on failure)
    - `clear(String storyItemId) → Future<void>`
    - `clearMine(String rel) → Future<int>`
  - `abstract class CoupleMapLocalStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }`, `SecureCoupleMapLocalStore`, `CoupleMapLocalKeys { pinLastChoice, homeArea, storiesHintSeen, all }`
  - Helpers: `Future<bool> readPinLastChoice(store)`, `writePinLastChoice(store, bool)`, `Future<HomeArea?> readHomeArea(store)`, `writeHomeArea(store, HomeArea?)`
  - `abstract class StoryPlaceResolver { Future<StoryPlaceDraft?> resolve(); }`, `GeolocatorStoryPlaceResolver`
  - Providers:
    - `storyPlacesGatewayProvider`, `storyPlacesRepositoryProvider`, `coupleMapLocalStoreProvider`, `storyPlaceResolverProvider`
    - `storyPlacesProvider` (`FutureProvider.autoDispose.family<List<StoryPlace>, StoryPlacesKey>`), refetched on `storyChangeSignalProvider`
    - `class StoryPlacesKey { relationshipId, authorId? }`
  - `clearCoupleMapDeviceData({…, CoupleMapLocalStore? store})` also deletes `CoupleMapLocalKeys.all`
  - Fakes: `FakeStoryPlacesGateway`, `MemoryCoupleMapLocalStore`, `FakeStoryPlaceResolver`

- [ ] **Step 1: Write the failing tests**

Append to `test/features/couple_map/support/fakes.dart`:

```dart
class FakeStoryPlacesGateway implements StoryPlacesGateway {
  FakeStoryPlacesGateway([Map<String, dynamic Function(Map<String, dynamic>)>? handlers])
      : handlers = handlers ?? {};
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params ?? const {}));
    final h = handlers[fn];
    return h == null ? null : h(params ?? const {});
  }
}

class MemoryCoupleMapLocalStore implements CoupleMapLocalStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FakeStoryPlaceResolver implements StoryPlaceResolver {
  FakeStoryPlaceResolver([this.next]);
  StoryPlaceDraft? next;
  int calls = 0;
  Completer<void>? hold;
  @override
  Future<StoryPlaceDraft?> resolve() async {
    calls++;
    await hold?.future;
    return next;
  }
}

Map<String, Object?> storyPlaceRow(String id, {String author = 'kofi', double lat = 5.556, double lng = -0.197, String created = '2026-10-16T09:00:00Z'}) => {
      'story_item_id': id, 'relationship_id': 'r1', 'author_id': author, 'lat': lat, 'lng': lng, 'label': 'Near Osu, Accra',
      'placed_at': created, 'client_story_id': 'c-$id', 'media_type': 'image', 'media_key': 'k/$id.jpg',
      'thumbnail_key': 't/$id.jpg', 'media_width': 1080, 'media_height': 1920, 'duration_ms': null,
      'occurred_on': created.substring(0, 10), 'created_at': created, 'expires_at': '2026-10-17T09:00:00Z',
    };
```

(Add the imports `story_places_repository.dart`, `couple_map_local_store.dart`, `story_place_resolver.dart` and `story_place.dart`.)

```dart
// test/features/couple_map/story_places_repository_test.dart
import 'package:attune/features/couple_map/data/story_places_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('list asks for the world box, capped, optionally one author', () async {
    final g = FakeStoryPlacesGateway({'list_story_places': (_) => [storyPlaceRow('s1')]});
    final r = StoryPlacesRepository(g);
    final places = await r.list('r1', authorId: 'kofi');
    expect(places.single.storyItemId, 's1');
    final p = g.calls.single.$2;
    expect((p['p_relationship_id'], p['p_author_id'], p['p_min_lat'], p['p_min_lng'], p['p_max_lat'], p['p_max_lng'], p['p_limit']),
        ('r1', 'kofi', -90, -180, 90, 180, 500));
  });

  test('a failed list throws (the map keeps its last pins), never reads as empty', () async {
    final g = FakeStoryPlacesGateway({'list_story_places': (_) => throw Exception('offline')});
    await expectLater(StoryPlacesRepository(g).list('r1'), throwsA(isA<Exception>()));
  });

  test('clear one and clear mine call their RPCs', () async {
    final g = FakeStoryPlacesGateway({'clear_my_story_places': (_) => 3});
    final r = StoryPlacesRepository(g);
    await r.clear('s1');
    expect(await r.clearMine('r1'), 3);
    expect(g.calls.map((c) => (c.$1, c.$2.values.single)), [('clear_story_place', 's1'), ('clear_my_story_places', 'r1')]);
  });
}
```

```dart
// test/features/couple_map/couple_map_local_store_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('pin choice: off until chosen, then remembered', () async {
    final s = MemoryCoupleMapLocalStore();
    expect(await readPinLastChoice(s), isFalse);
    await writePinLastChoice(s, true);
    expect(await readPinLastChoice(s), isTrue);
  });

  test('home area round-trips and clears', () async {
    final s = MemoryCoupleMapLocalStore();
    expect(await readHomeArea(s), isNull);
    await writeHomeArea(s, const HomeArea(lat: 5.556, lng: -0.197));
    final h = await readHomeArea(s);
    expect((h!.lat, h.lng), (5.556, -0.197));
    await writeHomeArea(s, null);
    expect(await readHomeArea(s), isNull);
  });

  test('a corrupt home area reads as none', () async {
    final s = MemoryCoupleMapLocalStore()..values[CoupleMapLocalKeys.homeArea] = 'not json';
    expect(await readHomeArea(s), isNull);
  });
}
```

In `couple_map_device_data_test.dart`, extend the first test: pass `store: MemoryCoupleMapLocalStore()..values.addAll({for (final k in CoupleMapLocalKeys.all) k: 'x'})`, then expect `store.values` to be empty.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/data/story_places_repository.dart
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class StoryPlacesGateway {
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params});
}

class SupabaseStoryPlacesGateway implements StoryPlacesGateway {
  SupabaseStoryPlacesGateway(this._supabase);
  final SupabaseClient _supabase;
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) => _supabase.rpc(fn, params: params);
}

/// Story places, through their RPCs only. Logs carry no place (4.4).
class StoryPlacesRepository {
  StoryPlacesRepository(this._gateway);
  final StoryPlacesGateway _gateway;

  /// Newest first, at most 500, in the world box (ruling: a couple's pins
  /// fit; the box stays for later viewport fetching). Throws on failure,
  /// so the map keeps its last pins instead of emptying.
  Future<List<StoryPlace>> list(String relationshipId, {String? authorId}) async {
    try {
      final rows = await _gateway.rpc('list_story_places', params: {
        'p_relationship_id': relationshipId,
        'p_author_id': authorId,
        'p_min_lat': -90,
        'p_min_lng': -180,
        'p_max_lat': 90,
        'p_max_lng': 180,
        'p_limit': CoupleMapConfig.placesLimit,
      });
      if (rows is! List) throw StateError('list_story_places returned ${rows.runtimeType}');
      // The RPC doesn't repeat the relationship; the story model needs it.
      return [
        for (final r in rows)
          StoryPlace.fromRow({...Map<String, dynamic>.from(r as Map), 'relationship_id': relationshipId}),
      ];
    } catch (e) {
      debugPrint('story places: list failed (${e.runtimeType})');
      rethrow;
    }
  }

  Future<void> clear(String storyItemId) =>
      _gateway.rpc('clear_story_place', params: {'p_story_item_id': storyItemId});

  Future<int> clearMine(String relationshipId) async {
    final n = await _gateway.rpc('clear_my_story_places', params: {'p_relationship_id': relationshipId});
    return (n as num?)?.toInt() ?? 0;
  }
}
```

```dart
// lib/features/couple_map/data/couple_map_local_store.dart
import 'dart:convert';

import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-only couple map settings. The home area is the most sensitive
/// place there is, so all of it lives in secure storage and quick exit
/// clears it (spec §3.6).
abstract class CoupleMapLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract final class CoupleMapLocalKeys {
  static const pinLastChoice = 'story_pin_last_choice';
  static const homeArea = 'couple_map_home_area';
  static const storiesHintSeen = 'couple_map_stories_hint_seen';
  static const all = [pinLastChoice, homeArea, storiesHintSeen];
}

class SecureCoupleMapLocalStore implements CoupleMapLocalStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

Future<bool> readPinLastChoice(CoupleMapLocalStore s) async =>
    await s.read(CoupleMapLocalKeys.pinLastChoice) == 'true';

Future<void> writePinLastChoice(CoupleMapLocalStore s, bool on) =>
    s.write(CoupleMapLocalKeys.pinLastChoice, on ? 'true' : 'false');

Future<HomeArea?> readHomeArea(CoupleMapLocalStore s) async {
  final raw = await s.read(CoupleMapLocalKeys.homeArea);
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return HomeArea(lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble());
  } catch (_) {
    return null;
  }
}

Future<void> writeHomeArea(CoupleMapLocalStore s, HomeArea? h) => h == null
    ? s.delete(CoupleMapLocalKeys.homeArea)
    : s.write(CoupleMapLocalKeys.homeArea, jsonEncode({'lat': h.lat, 'lng': h.lng}));
```

```dart
// lib/features/couple_map/data/story_place_resolver.dart
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Where the story is being posted from: a precise fix plus a
/// neighbourhood label. Called ONLY once the author turns the pin switch
/// on (or it starts on from their last choice): never otherwise (§3.3).
abstract class StoryPlaceResolver {
  /// Null when there is no permission, no fix in time, or anything fails.
  Future<StoryPlaceDraft?> resolve();
}

class GeolocatorStoryPlaceResolver implements StoryPlaceResolver {
  @override
  Future<StoryPlaceDraft?> resolve() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var p = await Geolocator.checkPermission();
      // Turning the switch on is an explicit request: asking is fair here.
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) return null;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: CoupleMapConfig.placeFixTimeout,
        ),
      );
      String? neighbourhood;
      String? city;
      try {
        // The platform geocoder (Android Geocoder / iOS CLGeocoder): the
        // app calls no third-party HTTP API, though the OS may ask Google
        // or Apple.
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 10));
        final m = marks.isEmpty ? null : marks.first;
        neighbourhood = m?.subLocality;
        city = (m?.locality?.isNotEmpty ?? false) ? m!.locality : m?.subAdministrativeArea;
      } catch (_) {}
      final draft = StoryPlaceDraft(
        lat: pos.latitude,
        lng: pos.longitude,
        label: placeLabel(neighbourhood: neighbourhood, city: city),
      );
      return draft.isValid ? draft : null;
    } catch (_) {
      return null;
    }
  }
}
```

```dart
// lib/features/couple_map/presentation/providers/story_places_providers.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/data/story_places_repository.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart' show supabaseClientProvider;
import 'package:attune/features/stories/presentation/providers/story_providers.dart' show storyChangeSignalProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final storyPlacesGatewayProvider = Provider<StoryPlacesGateway>(
  (ref) => SupabaseStoryPlacesGateway(ref.watch(supabaseClientProvider)),
);
final storyPlacesRepositoryProvider = Provider<StoryPlacesRepository>(
  (ref) => StoryPlacesRepository(ref.watch(storyPlacesGatewayProvider)),
);
final coupleMapLocalStoreProvider = Provider<CoupleMapLocalStore>((ref) => SecureCoupleMapLocalStore());
final storyPlaceResolverProvider = Provider<StoryPlaceResolver>((ref) => GeolocatorStoryPlaceResolver());

@immutable
class StoryPlacesKey {
  const StoryPlacesKey(this.relationshipId, {this.authorId});
  final String relationshipId;
  final String? authorId;
  @override
  bool operator ==(Object o) => o is StoryPlacesKey && o.relationshipId == relationshipId && o.authorId == authorId;
  @override
  int get hashCode => Object.hash(relationshipId, authorId);
}

/// Pinned stories for the map, refetched whenever the couple's story
/// signal bumps (a new story, a delete, a place cleared on either side).
final storyPlacesProvider = FutureProvider.autoDispose
    .family<List<StoryPlace>, StoryPlacesKey>((ref, key) {
  ref.watch(storyChangeSignalProvider(key.relationshipId));
  return ref.watch(storyPlacesRepositoryProvider).list(key.relationshipId, authorId: key.authorId);
});
```

`couple_map_device_data.dart`: add the parameter `CoupleMapLocalStore? store` and run everything **concurrently**. Quick exit exits 300 ms after starting this, so the store deletes must not delay the tile-cache clear:

```dart
  final s = store ?? SecureCoupleMapLocalStore();
  (pins ?? sharedPinImageRenderer).clear();
  await Future.wait([
    for (final key in CoupleMapLocalKeys.all) s.delete(key),
    (clearMapCache ?? MapboxMapsOptions.clearData)().catchError((Object _) {}),
  ]);
```

(This replaces the existing body's separate clear and `try`.)

Update the doc comment: "…and the last pin choice, the home area and the stories hint".

- [ ] **Step 4: Run them and confirm they pass,** together with `test/features/couple_map/`.
- [ ] **Step 5: Ledger.**

---

### Task 5: The camera's "Pin to our map" switch

**Files:**
- Create: `lib/features/couple_map/presentation/camera/story_pin_controller.dart`, `lib/features/couple_map/presentation/camera/story_pin_toggle.dart`
- Modify: `lib/features/stories/presentation/screens/story_camera_screen.dart`
- Test: `test/features/couple_map/story_pin_controller_test.dart`, `test/features/couple_map/story_pin_toggle_test.dart`, `test/features/stories/story_camera_test.dart` (add one test)

**Interfaces:**
- Consumes: Task 4 (store, resolver); `presenceRepositoryProvider.fetchMapPresence` (Phase 0, read once, which never samples); `coupleMapEnabledProvider`.
- Produces:
  - `class StoryPinController extends ChangeNotifier`:
    - `StoryPinController({required CoupleMapLocalStore store, required StoryPlaceResolver resolver, required bool paused})`
    - `Future<void> init()`
    - `Future<void> setOn(bool on)`
    - getters: `bool on`, `bool resolving`, `StoryPlaceDraft? place`, `StoryPinNotice? notice`
    - `Future<StoryPlaceDraft?> placeForPost()` (waits for a lookup still in flight)
    - `enum StoryPinNotice { paused, nearHome, notFound }`
  - `StoryPinToggle({required String relationshipId, required ValueChanged<StoryPinController?> onController})`
  - `storyPinControllerFactoryProvider` (test seam)

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/couple_map/story_pin_controller_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _osu = StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra');

void main() {
  test('first time: off, and nothing is looked up', () async {
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: r, paused: false);
    await c.init();
    expect(c.on, isFalse);
    expect(r.calls, 0);
    expect(await c.placeForPost(), isNull);
  });

  test('turning it on looks the place up once, previews it, and is remembered', () async {
    final s = MemoryCoupleMapLocalStore();
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(store: s, resolver: r, paused: false);
    await c.init();
    await c.setOn(true);
    expect((c.on, r.calls, c.place?.label), (true, 1, 'Near Osu, Accra'));
    expect((await c.placeForPost())!.label, 'Near Osu, Accra');
    expect(await readPinLastChoice(s), isTrue);
  });

  test('remembered on: starts on and looks up (the author\'s own choice)', () async {
    final s = MemoryCoupleMapLocalStore();
    await writePinLastChoice(s, true);
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(store: s, resolver: r, paused: false);
    await c.init();
    expect((c.on, r.calls), (true, 1));
  });

  test('paused: starts off with the paused notice, even if remembered on, and looks nothing up', () async {
    final s = MemoryCoupleMapLocalStore();
    await writePinLastChoice(s, true);
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(store: s, resolver: r, paused: true);
    await c.init();
    expect((c.on, c.notice, r.calls), (false, StoryPinNotice.paused, 0));
    // Starts off, but stays the author's choice (spec §3.3, §4.5).
    await c.setOn(true);
    expect((c.on, c.notice, r.calls), (true, null, 1));
  });

  test('shutter during the lookup waits for it, so an "on" story is pinned (not silently unpinned)', () async {
    final r = FakeStoryPlaceResolver(_osu)..hold = Completer<void>();
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: r, paused: false);
    await c.init();
    unawaited(c.setOn(true));
    final posted = c.placeForPost();
    r.hold!.complete();
    expect((await posted)?.label, 'Near Osu, Accra');
  });

  test('near the home area: turns off with the notice; turning it back on sticks', () async {
    final s = MemoryCoupleMapLocalStore();
    await writeHomeArea(s, const HomeArea(lat: 5.5561, lng: -0.1971));
    final c = StoryPinController(store: s, resolver: FakeStoryPlaceResolver(_osu), paused: false);
    await c.init();
    await c.setOn(true);
    expect((c.on, c.notice), (false, StoryPinNotice.nearHome));
    expect(await c.placeForPost(), isNull);
    await c.setOn(true); // the author insists
    expect(c.on, isTrue);
    expect(await c.placeForPost(), isNotNull);
  });

  test('no fix: notice, and the story posts without a place (Review Focus 3)', () async {
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: FakeStoryPlaceResolver(null), paused: false);
    await c.init();
    await c.setOn(true);
    expect((c.on, c.notice), (true, StoryPinNotice.notFound));
    expect(await c.placeForPost(), isNull);
  });

  test('turning it off forgets the place and is remembered', () async {
    final s = MemoryCoupleMapLocalStore();
    final c = StoryPinController(store: s, resolver: FakeStoryPlaceResolver(_osu), paused: false);
    await c.init();
    await c.setOn(true);
    await c.setOn(false);
    expect((c.on, c.place), (false, null));
    expect(await readPinLastChoice(s), isFalse);
  });

  test('a slow lookup that finishes after the switch went off is discarded', () async {
    final r = FakeStoryPlaceResolver(_osu)..hold = Completer<void>();
    final c = StoryPinController(store: MemoryCoupleMapLocalStore(), resolver: r, paused: false);
    await c.init();
    final turning = c.setOn(true);
    await c.setOn(false);
    r.hold!.complete();
    await turning;
    expect((c.on, c.place), (false, null));
  });
}
```

(Add `import 'dart:async';` for `Completer`.)

```dart
// test/features/couple_map/story_pin_toggle_test.dart
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_toggle.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart' show FakePresenceGateway, FakeSampler;
import 'support/fakes.dart';

Future<StoryPinController?> _pump(WidgetTester t, {bool flag = true, List<Map<String, Object?>> presence = const [], StoryPlaceDraft? place, FakeSampler? sampler}) async {
  StoryPinController? got;
  await t.pumpWidget(ProviderScope(
    overrides: [
      coupleMapEnabledProvider.overrideWith((ref) async => flag),
      presenceGatewayProvider.overrideWithValue(FakePresenceGateway({'couple_map_presence': (_) => presence})),
      presenceSamplerProvider.overrideWithValue(sampler ?? FakeSampler()),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
      coupleMapLocalStoreProvider.overrideWithValue(MemoryCoupleMapLocalStore()),
      storyPlaceResolverProvider.overrideWithValue(FakeStoryPlaceResolver(place)),
    ],
    child: MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StoryPinToggle(relationshipId: 'r1', onController: (c) => got = c),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return got;
}

void main() {
  testWidgets('flag off: nothing on the camera, no controller', (t) async {
    final c = await _pump(t, flag: false);
    expect(find.text('Pin to our map'), findsNothing);
    expect(c, isNull);
  });

  testWidgets('off by default; turning it on shows the neighbourhood preview', (t) async {
    final c = await _pump(t, place: const StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra'));
    expect(find.text('Pin to our map'), findsOneWidget);
    expect(c!.on, isFalse);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra'), findsOneWidget);
  });

  testWidgets('paused: "Your area is paused", switch off but still the author\'s to turn on', (t) async {
    final c = await _pump(t, presence: const [{'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'}]);
    expect(find.text('Your area is paused'), findsOneWidget);
    expect(c!.on, isFalse);
    expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });

  testWidgets('the camera never samples presence (it only reads my state once)', (t) async {
    final sampler = FakeSampler();
    await _pump(t, presence: const [{'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'}], sampler: sampler);
    expect(sampler.sampled, 0);
  });

  testWidgets('labelled for screen readers, and never below a 44 dp target', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t);
    expect(find.bySemanticsLabel(RegExp('Pin to our map')), findsWidgets);
    expect(t.getSize(find.byType(StoryPinToggle)).height, greaterThanOrEqualTo(44));
    semantics.dispose();
  });
}
```

In `test/features/stories/story_camera_test.dart`, first give `buildContainer` a `List<Override> extra = const []` parameter appended to its overrides. Then add one test in its own style. It uses `buildContainer` overrides plus `coupleMapEnabledProvider` (true), the presence fakes, `MemoryCoupleMapLocalStore` with `writePinLastChoice(true)`, and `FakeStoryPlaceResolver(osu)`. Steps:
1. Run `pumpToReady`, then pump until the preview "Near Osu, Accra" shows.
2. Run `tapShutter`.
3. Expect the stored record's `place?.label` to be `'Near Osu, Accra'`.

Add a second test: with `coupleMapEnabledProvider` overridden to `false`, the record's `place` is null and "Pin to our map" isn't found. That shows existing behaviour is unchanged.

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

```dart
// lib/features/couple_map/presentation/camera/story_pin_controller.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter/foundation.dart';

enum StoryPinNotice { paused, nearHome, notFound }

/// The "Pin to our map" switch (spec §3.3):
/// - off the first time, then the author's last choice;
/// - starts off while my area is paused;
/// - looks the place up only once on;
/// - turns itself off near the device-only home area, once, after which
///   the author's own "on" sticks.
class StoryPinController extends ChangeNotifier {
  StoryPinController({required this.store, required this.resolver, required this.paused});

  final CoupleMapLocalStore store;
  final StoryPlaceResolver resolver;
  final bool paused;

  bool _on = false;
  bool _resolving = false;
  bool _homeWarned = false;
  int _lookup = 0;
  StoryPlaceDraft? _place;
  StoryPinNotice? _notice;
  bool _disposed = false;
  Future<void>? _pending;

  bool get on => _on;
  bool get resolving => _resolving;
  StoryPlaceDraft? get place => _place;
  StoryPinNotice? get notice => _notice;

  /// What to attach at post time: only a resolved place while on. Waits
  /// for a lookup still in flight, so a shutter pressed while "Finding
  /// this place…" still pins the story.
  Future<StoryPlaceDraft?> placeForPost() async {
    if (!_on) return null;
    await _pending;
    return _on ? _place : null;
  }

  Future<void> init() async {
    if (paused) {
      _notice = StoryPinNotice.paused;
      _notify();
      return;
    }
    if (await readPinLastChoice(store)) await _turnOn(remember: false);
  }

  Future<void> setOn(bool on) async {
    if (!on) {
      _lookup++;
      _on = false;
      _resolving = false;
      _place = null;
      _pending = null;
      if (_notice != StoryPinNotice.paused) _notice = null;
      _notify();
      await writePinLastChoice(store, false);
      return;
    }
    await _turnOn(remember: true);
  }

  Future<void> _turnOn({required bool remember}) {
    final f = _lookupPlace(remember: remember);
    _pending = f;
    return f;
  }

  Future<void> _lookupPlace({required bool remember}) async {
    final lookup = ++_lookup;
    _on = true;
    _resolving = true;
    // "Paused" only sets the default; turning it on clears that notice.
    if (_notice != StoryPinNotice.nearHome) _notice = null;
    _notify();
    if (remember) await writePinLastChoice(store, true);
    final draft = await resolver.resolve();
    if (lookup != _lookup || !_on) return; // turned off (or again) meanwhile
    _resolving = false;
    _place = draft;
    if (draft == null) {
      _notice = StoryPinNotice.notFound;
    } else if (!_homeWarned) {
      final home = await readHomeArea(store);
      if (home != null && home.isNear(draft.lat, draft.lng)) {
        _homeWarned = true;
        _on = false;
        _notice = StoryPinNotice.nearHome;
      }
    } else {
      _notice = null;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
```

```dart
// lib/features/couple_map/presentation/camera/story_pin_toggle.dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the controller (seam for tests).
final storyPinControllerFactoryProvider =
    Provider<StoryPinController Function({required bool paused})>((ref) {
  return ({required bool paused}) => StoryPinController(
        store: ref.read(coupleMapLocalStoreProvider),
        resolver: ref.read(storyPlaceResolverProvider),
        paused: paused,
      );
});

/// The camera's "Pin to our map" pill. Renders nothing unless the couple
/// map is enabled. Reads my paused state ONCE (fetchMapPresence), never the
/// sampling provider: the camera must not trigger presence samples (§6.1).
class StoryPinToggle extends ConsumerWidget {
  const StoryPinToggle({super.key, required this.relationshipId, required this.onController});
  final String relationshipId;
  final ValueChanged<StoryPinController?> onController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(coupleMapEnabledProvider).valueOrNull == true;
    if (!enabled) return const SizedBox.shrink();
    return _PinToggleBody(relationshipId: relationshipId, onController: onController);
  }
}

class _PinToggleBody extends ConsumerStatefulWidget {
  const _PinToggleBody({required this.relationshipId, required this.onController});
  final String relationshipId;
  final ValueChanged<StoryPinController?> onController;
  @override
  ConsumerState<_PinToggleBody> createState() => _PinToggleBodyState();
}

class _PinToggleBodyState extends ConsumerState<_PinToggleBody> {
  StoryPinController? _c;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    var paused = false;
    try {
      final p = await ref.read(presenceRepositoryProvider).fetchMapPresence(widget.relationshipId);
      paused = p.state.status == PresenceStatus.paused;
    } catch (_) {}
    if (!mounted) return;
    final c = ref.read(storyPinControllerFactoryProvider)(paused: paused);
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _c = c);
    unawaited(c.init());
    widget.onController(c);
  }

  @override
  void dispose() {
    widget.onController(null);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return const SizedBox.shrink();
    final sub = switch (c.notice) {
      StoryPinNotice.paused => 'Your area is paused',
      StoryPinNotice.nearHome => 'This looks near your home area',
      StoryPinNotice.notFound => "Couldn't find this place",
      null => c.resolving ? 'Finding this place…' : (c.on ? c.place?.label : null),
    };
    return Semantics(
      container: true,
      label: sub == null ? 'Pin to our map' : 'Pin to our map. $sub',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadiusTokens.floatingNavAll,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: Spacing.md, right: Spacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place_outlined, color: Colors.white, size: 18),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pin to our map',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      if (sub != null)
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(value: c.on, onChanged: (v) => c.setOn(v)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

`story_camera_screen.dart`:
- Imports: `package:attune/features/couple_map/presentation/camera/story_pin_controller.dart` and `…/story_pin_toggle.dart`.
- State field: `StoryPinController? _pin;`.
- In `_prepareAndEnqueue`, before building the record: `final place = await _pin?.placeForPost();` (it waits for a lookup in flight, Review Focus 3 and I3). Then add `place: place,` to the `StoryOutboxRecord(...)`.
- Hide the pill while the take is being enqueued, so the switch never looks changeable after the shutter: a `bool _enqueuing` set at the start of `_prepareAndEnqueue` and cleared in `_stayOnCameraAfterFailure`, with the overlay wrapped in `if (!_enqueuing)`.
- Replace the `return CaptureCameraScreen(...)` in `build` with:

```dart
    return Stack(
      children: [
        Positioned.fill(
          child: CaptureCameraScreen(
            key: _captureKey,
            allow: CaptureKinds.photoAndVideo,
            videoPreparerFactory: widget.videoPreparerFactory,
            imagePreparerFactory: widget.imagePreparerFactory,
            onCaptured: _onCaptured,
            onCancelled: _onCaptureCancelled,
          ),
        ),
        // Between the close and flip buttons (both at the top corners).
        Positioned(
          top: Spacing.xxl,
          left: 64,
          right: 64,
          child: Center(
            child: StoryPinToggle(
              relationshipId: widget.relationshipId,
              onController: (c) => _pin = c,
            ),
          ),
        ),
      ],
    );
```

(Import `design_tokens.dart` for `Spacing`. The camera's own Stack still owns its controls; this overlay adds one pill.)

- [ ] **Step 4: Run them and confirm they pass.** `flutter test test/features/couple_map/ test/features/stories/`.
- [ ] **Step 5: Ledger.**

---

### Task 6: Story pins on the map (renderer, scene, seam, Mapbox)

**Files:**
- Modify: `lib/features/couple_map/presentation/widgets/pin_image_renderer.dart`, `lib/features/couple_map/domain/couple_map_scene.dart`, `lib/features/couple_map/presentation/map/couple_map_controller.dart`, `lib/features/couple_map/presentation/map/mapbox_couple_map_view.dart`, `test/features/couple_map/support/fakes.dart`
- Test: `test/features/couple_map/pin_image_renderer_test.dart` (add), `test/features/couple_map/couple_map_scene_test.dart` (add), `test/features/couple_map/mapbox_wiring_test.dart` (add)

**Interfaces:**
- Consumes: `StoryPlace` (Task 2).
- Produces:
  - `PinSpec({…, String? cacheKey})`: equality uses `cacheKey ?? imageUrl`
  - `PinImageRenderer.renderRaw(PinSpec) → Future<RawPin>` (`class RawPin { Uint8List rgba; int width, height; }`, premultiplied RGBA, its own LRU)
  - `class StoryScenePin { final String storyItemId; final MapPoint at; final int rank; }`
  - `List<StoryScenePin> storyScenePins(List<StoryPlace> places)` (rank: oldest 0 … newest n−1)
  - `String storiesGeoJson(List<StoryScenePin> pins)`
  - `CoupleMapController.setStories(List<StoryScenePin> pins, Map<String, RawPin> images)` (images keyed by `storyItemId`)
  - `CoupleMapViewBuilder` gains `required ValueChanged<List<String>> onStoriesTapped` and `required double ornamentTop`. The compass sits that far down, under the tab's right-hand column, whose height changes when the Stories button shows. It replaces the fixed 292.
  - Fake: `FakeCoupleMapController.stories` (list of `(pins, images)`), `FakeCoupleMapView.tapStories(List<String>)`, `FakePinImageRenderer.renderRaw`

- [ ] **Step 1: Write the failing tests**

Add to `pin_image_renderer_test.dart`:

```dart
  testWidgets('raw pins are premultiplied RGBA of 4 × w × h bytes, cached by key', (t) async {
    await t.runAsync(() async {
      var loads = 0;
      final r = PinImageRenderer(loader: (_) async {
        loads++;
        return _photo();
      });
      PinSpec spec(String url) => PinSpec(imageUrl: url, cacheKey: 't/1.jpg', initials: '', ring: Colors.white,
          fill: Colors.black, onFill: Colors.white, sizePx: 20);
      final a = await r.renderRaw(spec('https://signed/1?token=a'));
      final b = await r.renderRaw(spec('https://signed/1?token=b')); // a fresh signature, same thumbnail
      expect(a.rgba.length, 4 * 20 * 20);
      expect((a.width, a.height), (20, 20));
      expect(loads, 1, reason: 'keyed by thumbnail key, not the signed URL (spec §9 3.4)');
      expect(identical(a, b), isTrue);
    });
  });
```

Add to `couple_map_scene_test.dart` (with the imports `story_place.dart` and `../couple_map/support/fakes.dart`; `storyPlaceRow` is there):

```dart
  test('story pins: oldest rank 0, newest highest; GeoJSON points carry id and rank, no time', () {
    final places = [
      StoryPlace.fromRow(storyPlaceRow('new', created: '2026-10-16T10:00:00Z')),
      StoryPlace.fromRow(storyPlaceRow('old', created: '2026-10-01T10:00:00Z')),
    ];
    final pins = storyScenePins(places);
    expect({for (final p in pins) p.storyItemId: p.rank}, {'old': 0, 'new': 1});
    final fc = jsonDecode(storiesGeoJson(pins)) as Map;
    final f = (fc['features'] as List).first as Map;
    expect(f['geometry']['type'], 'Point');
    expect((f['properties'] as Map).keys.toSet(), {'id', 'rank'});
  });
```

Add to `mapbox_wiring_test.dart`:

```dart
  test('stories are a clustered GeoJSON source, rebuilt (not layer-filtered) on change', () {
    final s = _src();
    expect(s.contains('cluster: true'), isTrue);
    expect(s.contains("clusterProperties: {'top': ['max', ['get', 'rank']]}"), isTrue);
    expect(s.contains('_storySource'), isTrue);
  });

  test('a tap resolves a pin or a whole cluster to story ids', () {
    final s = _src();
    expect(s.contains('queryRenderedFeatures('), isTrue);
    expect(s.contains('getGeoJsonClusterLeaves('), isTrue);
    expect(s.contains('widget.onStoriesTapped'), isTrue);
  });

  test('story pins never use a dot layer either', () {
    expect(_src().contains('CircleLayer('), isFalse);
  });
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement**

`pin_image_renderer.dart`:
- `PinSpec` gains `this.cacheKey` (`final String? cacheKey;`). Equality and hash use `cacheKey ?? imageUrl` in place of `imageUrl`.
- Add:

```dart
@immutable
class RawPin {
  const RawPin({required this.rgba, required this.width, required this.height});
  final Uint8List rgba;
  final int width;
  final int height;
}
```

- Refactor `_draw` so the canvas work lives in `Future<({ui.Image image, bool photoFailed})> _paint(PinSpec s)`. `_draw` then encodes PNG from it; the new `_drawRaw` encodes `ui.ImageByteFormat.rawRgba` (premultiplied) into `RawPin`.
- Add a second cache, `_rawCache = <PinSpec, Future<RawPin>>{}`, and `Future<RawPin> renderRaw(PinSpec spec)` with the same LRU and failed-photo eviction as `render`. `clear()` and `length` cover both.

`couple_map_scene.dart`: add

```dart
@immutable
class StoryScenePin {
  const StoryScenePin({required this.storyItemId, required this.at, required this.rank});
  final String storyItemId;
  final MapPoint at;
  final int rank;
}

/// Oldest gets rank 0, so a cluster's "top" (max rank) is its newest story.
List<StoryScenePin> storyScenePins(List<StoryPlace> places) {
  final sorted = [...places]..sort((a, b) => a.story.createdAt.compareTo(b.story.createdAt));
  return [
    for (var i = 0; i < sorted.length; i++)
      StoryScenePin(storyItemId: sorted[i].storyItemId, at: MapPoint(sorted[i].lat, sorted[i].lng), rank: i),
  ];
}

/// Points carrying only an id and a rank: no time, no author, no label.
String storiesGeoJson(List<StoryScenePin> pins) => jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final p in pins)
          {
            'type': 'Feature',
            'properties': {'id': p.storyItemId, 'rank': p.rank},
            'geometry': {'type': 'Point', 'coordinates': [p.at.lng, p.at.lat]},
          },
      ],
    });
```

(Add the import `story_place.dart`.)

`couple_map_controller.dart`:
- add `Future<void> setStories(List<StoryScenePin> pins, Map<String, RawPin> images);`, importing `pin_image_renderer.dart`;
- add `required ValueChanged<List<String>> onStoriesTapped,` to the typedef.

`mapbox_couple_map_view.dart`:
- Builder, widget and constructor gain `onStoriesTapped` (`final ValueChanged<List<String>> onStoriesTapped;`).
- `MapWidget` gains `onTapListener: _onTap,`.
- Constants: `static const _storySource = 'couple-stories'; static const _storyPins = 'couple-stories-pins'; static const _storyClusters = 'couple-stories-clusters';`
- Fields: `({List<StoryScenePin> pins, Map<String, RawPin> images})? _lastStories;`, `int _storyImageCount = 0;` (reset to 0 in `_styleLoaded`, because a new style drops images) and `double _storyScale = 1;` (the images are `storyPinSize × dpr` pixels, so the scale is the device pixel ratio).
- `_styleLoaded` re-applies it after presence: `final s = _lastStories; if (s != null) await _applyStories(s);`
- Add:

```dart
  @override
  Future<void> setStories(List<StoryScenePin> pins, Map<String, RawPin> images) {
    // Read now, while the context is valid; the draw runs after awaits.
    _storyScale = MediaQuery.devicePixelRatioOf(context);
    final s = (pins: pins, images: images);
    _lastStories = s;
    return _applyStories(s);
  }

  /// Serialised with presence draws; a superseded set is skipped. The
  /// source is rebuilt from the filtered set, so cluster counts are right.
  Future<void> _applyStories(({List<StoryScenePin> pins, Map<String, RawPin> images}) s) {
    _queue = _queue.then((_) async {
      if (!identical(s, _lastStories)) return;
      final map = _map;
      if (map == null || !_styleReady) return;
      try {
        final style = map.style;
        for (final layer in [_storyClusters, _storyPins]) {
          if (await style.styleLayerExists(layer)) await style.removeStyleLayer(layer);
        }
        if (await style.styleSourceExists(_storySource)) await style.removeStyleSource(_storySource);
        // Rank-keyed images: drop the ones a smaller set no longer uses.
        for (var i = s.pins.length; i < _storyImageCount; i++) {
          if (await style.hasStyleImage('story-$i')) await style.removeStyleImage('story-$i');
        }
        _storyImageCount = s.pins.length;
        if (s.pins.isEmpty) return;
        for (final pin in s.pins) {
          final img = s.images[pin.storyItemId];
          if (img == null) continue;
          await style.addStyleImage('story-${pin.rank}', _storyScale,
              MbxImage(width: img.width, height: img.height, data: img.rgba), false, [], [], null);
        }
        await style.addSource(GeoJsonSource(
          id: _storySource,
          data: storiesGeoJson(s.pins),
          cluster: true,
          clusterRadius: 50,
          clusterMaxZoom: 14,
          clusterProperties: {'top': ['max', ['get', 'rank']]},
        ));
        await style.addLayer(SymbolLayer(
          id: _storyPins,
          sourceId: _storySource,
          filter: ['!', ['has', 'point_count']],
          iconImageExpression: ['concat', 'story-', ['to-string', ['get', 'rank']]],
          iconAllowOverlap: true,
        ));
        await style.addLayer(SymbolLayer(
          id: _storyClusters,
          sourceId: _storySource,
          filter: ['has', 'point_count'],
          // The newest story's thumbnail, a little larger, with a count.
          iconImageExpression: ['concat', 'story-', ['to-string', ['get', 'top']]],
          iconSize: 1.15,
          iconAllowOverlap: true,
          // On the rim, with a heavy halo, so it reads over any photo.
          textFieldExpression: ['get', 'point_count_abbreviated'],
          textSize: 13,
          textOffset: [1.9, -1.9],
          textColor: 0xFFFFFFFF,
          textHaloColor: 0xE6000000,
          textHaloWidth: 2,
          textAllowOverlap: true,
        ));
      } catch (_) {
        // A style swapped mid-draw: _styleLoaded re-applies. No log.
      }
    });
    return _queue;
  }

  Future<void> _onTap(MapContentGestureContext ctx) async {
    final map = _map;
    if (map == null) return;
    try {
      final hits = await map.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenCoordinate(ctx.touchPosition),
        RenderedQueryOptions(layerIds: [_storyPins, _storyClusters]),
      );
      final feature = hits.whereType<QueriedRenderedFeature>().firstOrNull?.queriedFeature.feature;
      if (feature == null) return;
      final props = Map<String?, Object?>.from(feature['properties'] as Map? ?? const {});
      if (props.containsKey('point_count')) {
        final leaves = await map.getGeoJsonClusterLeaves(_storySource, feature, 500, 0);
        final ids = [
          for (final f in leaves.featureCollection ?? const <Map<String?, Object?>?>[])
            if ((f?['properties'] as Map?)?['id'] case final String id) id,
        ];
        if (ids.isNotEmpty) widget.onStoriesTapped(ids);
      } else if (props['id'] case final String id) {
        widget.onStoriesTapped([id]);
      }
    } catch (_) {}
  }
```

The compass `marginTop` becomes `widget.ornamentTop`; the tab computes it from its column, and the fake records `builtOrnamentTop`. Ledger a device check that `['to-string', ['get', 'top']]` gives `"3"`, not `"3.0"`, for the accumulated value. If it gives `"3.0"`, wrap it in `['to-string', ['round', ['get', 'top']]]`.

(Check each named parameter against the plugin sources while implementing:
- `SymbolLayer`: `iconImageExpression`, `iconSize`, `iconAllowOverlap`, `textFieldExpression`, `textOffset`, `textHaloColor`, `textAllowOverlap`, `filter`;
- `GeoJsonSource`: `cluster`, `clusterRadius`, `clusterMaxZoom`, `clusterProperties`;
- `addStyleImage`'s positional signature;
- `MapContentGestureContext.touchPosition`.

Ledger any rename. Keep `slot: 'top'` for both story layers so they sit above labels.)

Fakes: `FakeCoupleMapController` adds `final stories = <(List<StoryScenePin>, Map<String, RawPin>)>[];` and the override `setStories(...) async => stories.add((pins, images));`. `FakeCoupleMapView` adds `ValueChanged<List<String>>? _tap; void tapStories(List<String> ids) => _tap?.call(ids);`; the builder gains the `onStoriesTapped` parameter and stores it. `FakePinImageRenderer` overrides `renderRaw` to return `RawPin(rgba: Uint8List(4), width: 1, height: 1)` and records the spec in `rawRendered`.

Update every call site of the builder (`couple_map_tab.dart`) with `onStoriesTapped: _openStories`. Task 8 implements `_openStories`; add a temporary no-op here so the build stays green, and ledger it.

- [ ] **Step 4: Run them and confirm they pass.** `flutter test test/features/couple_map/` and `flutter analyze lib/features/couple_map`.
- [ ] **Step 5: Ledger.**

---

### Task 7: The reel over a list of places, with "Remove from map"

**Files:**
- Modify: `lib/features/stories/presentation/screens/story_reel_screen.dart`
- Test: `test/features/couple_map/story_reel_places_test.dart`

**Interfaces:**
- Consumes: `StoryPlace`, `storyPlacesRepositoryProvider`, `storyPlacesProvider` (Task 4).
- Produces: `StoryReelScreen.forPlaces({required String relationshipId, required List<StoryItem> items, …})` (items are shown oldest first, as given)

- [ ] **Step 1: Write the failing test**

```dart
// test/features/couple_map/story_reel_places_test.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/fakes.dart';

// Reuse the stories test fake read gateway if one is exported; otherwise a
// minimal StoryReadGateway fake whose signMediaUrl returns null (the reel
// shows its loading/fallback state; this test is about the controls).
import '../stories/support/fake_story_read_gateway.dart';

User _user(String id) => User(id: id, appMetadata: const {}, userMetadata: const {}, aud: 'authenticated', createdAt: '2026-01-01');

Future<FakeStoryPlacesGateway> _pump(WidgetTester t, {required String me, required List<String> authors}) async {
  final g = FakeStoryPlacesGateway();
  final items = [
    for (var i = 0; i < authors.length; i++)
      StoryPlace.fromRow(storyPlaceRow('s$i', author: authors[i], created: '2026-10-1${i}T10:00:00Z')).story,
  ];
  // Pushed over a base route, as story_reel_test does: _close() pops, and
  // a root route can't pop.
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_user(me)),
      storyPlacesGatewayProvider.overrideWithValue(g),
      storyReadGatewayProvider.overrideWithValue(FakeStoryReadGateway()),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => StoryReelScreen.forPlaces(relationshipId: 'r1', items: items),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return g;
}

void main() {
  testWidgets('the author sees "Remove from map" next to Delete; the partner sees neither', (t) async {
    await _pump(t, me: 'ama', authors: ['ama']);
    expect(find.byKey(const ValueKey('story-reel-remove-place')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);
    await _pump(t, me: 'ama', authors: ['kofi']);
    expect(find.byKey(const ValueKey('story-reel-remove-place')), findsNothing);
    expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
  });

  testWidgets('remove from map takes it off and closes the last one (Review Focus 4)', (t) async {
    final g = await _pump(t, me: 'ama', authors: ['ama']);
    await t.tap(find.byKey(const ValueKey('story-reel-remove-place')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(g.calls.map((c) => c.$1), contains('clear_story_place'));
    expect(find.byType(StoryReelScreen), findsNothing);
  });

  testWidgets('deleting the first of two in places mode shows the survivor, not a close', (t) async {
    await _pump(t, me: 'ama', authors: ['ama', 'ama']);
    await t.tap(find.byKey(const ValueKey('story-reel-delete')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(find.byType(StoryReelScreen), findsOneWidget);
  });

  testWidgets('remove asks first: cancel keeps it', (t) async {
    final g = await _pump(t, me: 'ama', authors: ['ama', 'ama']);
    await t.tap(find.byKey(const ValueKey('story-reel-remove-place')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty);
  });
}
```

**Step 1a: Create `test/features/stories/support/fake_story_read_gateway.dart`.** Every existing fake is private to its own file. `FakeStoryReadGateway implements StoryReadGateway`:
- every list or count method returns an empty result;
- `watchChangeSignal` returns `const Stream.empty()`;
- `disposeChannel` and `disposeAllChannels` do nothing;
- `getReplyTarget` returns null and `markViewed` does nothing;
- `deleteItem` records the id in `deleted`;
- `signMediaUrl` returns null.

Read the interface and implement every member.

- [ ] **Step 2: Run it and confirm it fails.**

- [ ] **Step 3: Implement** in `story_reel_screen.dart`:
- Add a field `final List<StoryItem>? placeItems;`.
- Add the constructor:

```dart
  /// Places mode (couple map, spec §3.3): the stories behind a pin or a
  /// cluster, oldest first, as a fixed list (no pager). Per-item author
  /// checks, like day mode. Adds "Remove from map" for the author.
  const StoryReelScreen.forPlaces({
    super.key,
    required this.relationshipId,
    required List<StoryItem> items,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
  }) : placeItems = items,
       authorId = '',
       isOwnReel = false,
       occurredOn = null;
```

  The other two constructors initialise `placeItems = null`.
- State: `late List<StoryItem> _placeItems = [...?widget.placeItems];` and `bool get _placesMode => widget.placeItems != null;`.
- `_pagerHasMore` returns `false` in places mode, `_pagerLoadMore` returns `Future.value()`, and `_pagerCurrentItems` returns `_placeItems`. Each checks `_placesMode` **first**, before the `occurredOn` branch, so author mode's provider (`StoryReelKey(authorId: '')`) is never instantiated. The same goes for `build`'s `pagesAsync`.
- `_maybeMarkViewed` computes `isOwn` per item when `widget.occurredOn != null || _placesMode`.
- `build`: in places mode, skip the provider watch and use `AsyncValue.data(_placeItems)`. `canDeleteCurrent` and `isCurrentMine` use the per-item author check when `occurredOn != null || _placesMode`. Pass `onRemovePlace: _placesMode && isAuthor ? () => unawaited(_confirmAndRemovePlace(currentItem)) : null`.
- `_confirmAndDelete`: in places mode, after a successful delete, call `ProviderScope.containerOf(context).invalidate(storyPlacesProvider)` (the whole family) and then `_stepOffPlaceItem(item.id)`. It does **not** run the existing step-off: `items` is the same list being mutated, so `items.length` would be read after removal and could index −1. The existing day/author branch is unchanged.
- Add:

```dart
  Future<void> _confirmAndRemovePlace(StoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from our map?'),
        content: const Text('The story stays. Its place is removed for good.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final container = ProviderScope.containerOf(context);
    try {
      await container.read(storyPlacesRepositoryProvider).clear(item.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't remove the place. Try again.")),
        );
      }
      return;
    }
    // The signal bump refreshes every map; this one updates at once.
    container.invalidate(storyPlacesProvider);
    if (!mounted) return;
    _stepOffPlaceItem(item.id);
  }

  /// Places mode: drop [id] from the fixed list and show what's left (the
  /// next item slides into the same index), or close when nothing is.
  void _stepOffPlaceItem(String id) {
    final at = _placeItems.indexWhere((i) => i.id == id);
    if (at == -1) return;
    setState(() => _placeItems.removeAt(at));
    if (_placeItems.isEmpty) {
      _close();
      return;
    }
    _startItem(_placeItems, at.clamp(0, _placeItems.length - 1));
  }
```

- `_ReelBody` gains `this.onRemovePlace` (`final VoidCallback? onRemovePlace;`). In its Stack, next to Delete, add:

```dart
          if (onRemovePlace != null)
            Positioned(
              top: 0,
              left: onDelete != null ? 48 : 0,
              child: SafeArea(
                child: Semantics(
                  label: 'Remove from map',
                  button: true,
                  child: IconButton(
                    key: const ValueKey('story-reel-remove-place'),
                    iconSize: 24,
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const Icon(Icons.wrong_location_outlined, color: Colors.white),
                    tooltip: 'Remove from map',
                    onPressed: onRemovePlace,
                  ),
                ),
              ),
            ),
```

  Note that `container.invalidate(storyPlacesProvider)` invalidates the whole family, which Riverpod 2.6 supports for families.

- [ ] **Step 4: Run it and confirm it passes,** together with `flutter test test/features/stories/` to show that author and day modes are unchanged.
- [ ] **Step 5: Ledger.**

---

### Task 8: The tab (filter button, story pins, taps, hint, list rows)

**Files:**
- Modify: `lib/features/couple_map/presentation/screens/couple_map_tab.dart`, `lib/features/couple_map/presentation/widgets/couple_map_list_sheet.dart`, `test/features/couple_map/couple_map_tab_test.dart` (the harness gains overrides; new tests)

**Interfaces:**
- Consumes: Tasks 4, 6 and 7; `currentUserProvider`.
- Produces: `CoupleMapListContent({…, List<StoryPlace> places = const [], ValueChanged<StoryPlace>? onPlaceTap})`

- [ ] **Step 1: Write the failing tests**

In `couple_map_tab_test.dart`'s `_Harness`, add:
- fields `List<Map<String, Object?>> places = const [];`, `final placesGateway = …` (a `FakeStoryPlacesGateway` whose `list_story_places` handler returns `places`), and `final local = MemoryCoupleMapLocalStore();`;
- overrides:
  - `storyPlacesGatewayProvider.overrideWithValue(placesGateway)`;
  - `storyChangeSignalProvider.overrideWith((ref, rel) => const Stream<void>.empty())`;
  - `coupleMapLocalStoreProvider.overrideWithValue(local)`;
  - `currentUserProvider.overrideWithValue(User(id: 'ama', …))`;
  - `storyReadGatewayProvider.overrideWithValue(FakeStoryReadGateway())` (Task 7).

Add these tests:

```dart
  testWidgets('no pinned stories: no Stories button, no pins, and a one-time hint', (t) async {
    final h = _Harness([_self]);
    await h.pump(t);
    expect(find.byTooltip(RegExp('Stories')), findsNothing);
    expect(find.text('Stories you pin from the camera appear here'), findsOneWidget);
    expect(h.local.values[CoupleMapLocalKeys.storiesHintSeen], 'true');
    // Second visit: no hint.
    await t.pumpWidget(const SizedBox());
    await h.pump(t);
    expect(find.text('Stories you pin from the camera appear here'), findsNothing);
  });

  testWidgets('pinned stories are drawn; the Stories button appears', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1', author: 'kofi'), storyPlaceRow('s2', author: 'ama')];
    await h.pump(t);
    expect(h.view.controller.stories.last.$1.map((p) => p.storyItemId).toSet(), {'s1', 's2'});
    expect(find.byTooltip('Stories: both of you'), findsOneWidget);
  });

  testWidgets('the filter cycles and rebuilds the story set (Review Focus 5)', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1', author: 'kofi'), storyPlaceRow('s2', author: 'ama')];
    await h.pump(t);
    await t.tap(find.byTooltip('Stories: both of you'));
    await t.pumpAndSettle();
    expect(h.view.controller.stories.last.$1.map((p) => p.storyItemId), ['s2']);
    expect(find.byTooltip('Stories: mine'), findsOneWidget);
    await t.tap(find.byTooltip('Stories: mine'));
    await t.pumpAndSettle();
    expect(h.view.controller.stories.last.$1.map((p) => p.storyItemId), ['s1']);
    expect(find.byTooltip("Stories: Kofi's"), findsOneWidget);
  });

  testWidgets('tapping a cluster opens the reel over those stories, oldest first', (t) async {
    final h = _Harness([_self])..places = [
      storyPlaceRow('new', created: '2026-10-16T10:00:00Z'),
      storyPlaceRow('old', created: '2026-10-01T10:00:00Z'),
    ];
    await h.pump(t);
    h.view.tapStories(['new', 'old']);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final reel = t.widget<StoryReelScreen>(find.byType(StoryReelScreen));
    expect(reel.placeItems!.map((i) => i.id), ['old', 'new']);
  });

  testWidgets('the list sheet shows story places by day and opens them', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1', created: '2026-10-16T10:00:00Z')];
    await h.pump(t);
    await t.tap(find.byTooltip('List'));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra'), findsOneWidget);
  });
```

Add two more:

```dart
  testWidgets('recentre includes the visible story pins (spec §3.1)', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1', lat: 6.5, lng: 3.3)];
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$1.length, 2); // my area + one story
  });

  testWidgets('Mine with no own pins keeps the Stories button (no dead end)', (t) async {
    final h = _Harness([_self])..places = [storyPlaceRow('s1', author: 'kofi')];
    await h.pump(t);
    await t.tap(find.byTooltip('Stories: both of you'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Stories: mine'), findsOneWidget);
    expect(h.view.controller.stories.last.$1, isEmpty);
  });
```

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement** in `couple_map_tab.dart`:
- State:
  - `StoryFilter _filter = StoryFilter.both;`
  - `bool _hintShown = false;`
  - `bool? _hintSeen;` (loaded in `initState` from the store, and written as `'true'` the first time the hint shows)
  - `int _storyGen = 0;`
- **One fetch serves all three filters:** always watch `storyPlacesProvider(StoryPlacesKey(rel))` (Both), and filter on the client with `currentUserProvider`'s id:
  - Mine: `authorId == myId`;
  - Partner's: `authorId != myId`.

  So the Stories button's visibility comes from the **unfiltered** list. Cycling to Mine with no own pins can't hide the button and strand the user (spec §3.1: hidden only when no story is pinned).
- `ref.listen` on that provider, and on every filter change: `unawaited(_pushStories(_filtered(all)))`.
- `_pushStories(places)`: generation-guarded; it sets the pins at once, then fills images in chunks of 16 in parallel, re-calling `setStories` after each chunk. Pins without an image are skipped by `_applyStories`, so they appear progressively (spec §7 lists thumbnail volume as the risk). A null signature skips that pin. Also push from `_onReady` when places are already loaded:

```dart
  Future<void> _pushStories(List<StoryPlace> places) async {
    final gen = ++_storyGen;
    final c = _controller;
    if (c == null || !mounted) return;
    final pins = storyScenePins(places);
    final images = <String, RawPin>{};
    await c.setStories(pins, images);
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final px = (CoupleMapConfig.storyPinSize * MediaQuery.devicePixelRatioOf(context)).round();
    final gateway = ref.read(storyReadGatewayProvider);
    final renderer = ref.read(pinImageRendererProvider);
    for (final chunk in places.slices(16)) {
      await Future.wait(chunk.map((p) async {
        final signed = await gateway.signMediaUrl(p.story.thumbnailKey);
        if (signed == null) return;
        images[p.storyItemId] = await renderer.renderRaw(PinSpec(
            imageUrl: signed, cacheKey: p.story.thumbnailKey, initials: '',
            ring: Colors.white, fill: cs.surfaceContainerHighest, onFill: cs.onSurface, sizePx: px));
      }));
      if (!mounted || gen != _storyGen || _controller != c) return;
      await c.setStories(pins, Map.of(images));
    }
  }
```

  (`slices` comes from `package:collection`, already a Flutter dependency.)
- **Recentre** (spec §3.1: "fits both areas and the visible stories"): `_fit` passes `[...areaCentres, for (final p in _filtered(all)) MapPoint(p.lat, p.lng)]`.
- `_openStories(List<String> ids)`: from the current (unfiltered or filtered) list, take the matching places, sort by `story.createdAt` ascending, and push `MaterialPageRoute(builder: (_) => StoryReelScreen.forPlaces(relationshipId: rel, items: [...].map((p) => p.story).toList()))`.
- Top-right column, inserted after the style button only when the current places list is non-empty:

```dart
              GlassIconButton(
                icon: switch (_filter) {
                  StoryFilter.both => Icons.people_outline,
                  StoryFilter.mine => Icons.person_outline,
                  StoryFilter.partner => Icons.person_pin_circle_outlined,
                },
                tooltip: switch (_filter) {
                  StoryFilter.both => 'Stories: both of you',
                  StoryFilter.mine => 'Stories: mine',
                  StoryFilter.partner => "Stories: $partnerName's",
                },
                onPressed: () => setState(() => _filter = _filter.next),
              ),
```

  The builder's `ornamentTop` is `Spacing.md + buttons × 44 + gaps + Spacing.md + Spacing.md`: 292 without the Stories button and 344 with it. Compute it from the same `showStories` flag the column uses, so the compass never overlaps the column or leaves a gap.
- **Hint:** when presence is loaded, places have loaded empty, and `_hintSeen == false`, show a dismissible `NoticeCard`-style `GlassPanel` "Stories you pin from the camera appear here" above the bottom card for this visit, and write the flag.
- **List content:** pass `places` (filtered) and `onPlaceTap: (p) => _openStories([p.storyItemId])`.

In `couple_map_list_sheet.dart`, `CoupleMapListContent` gains `places` and `onPlaceTap`. After the presence rows, group by `story.occurredOn` (newest day first). For each place, an `InfoRowWidget(title: p.label, subtitle: MyDateFormat.join([MyDateFormat.toDate(p.story.occurredOn)]), icon: Icons.photo_outlined, showAvatar: false, showTrailingArrow: true, onTap: () => onPlaceTap?.call(p))`, with no time-of-day and no author line. The sheet variant watches `storyPlacesProvider(StoryPlacesKey(rel))` and passes the places through.

- [ ] **Step 4: Run them and confirm they pass,** together with all of `test/features/couple_map/`. The Phase 1 tab tests must stay green with the new overrides.
- [ ] **Step 5: Ledger.**

---

### Task 9: The Sharing sheet ("Remove all my places", home area) and quick exit

**Files:**
- Modify: `lib/features/couple_map/presentation/widgets/sharing_sheet.dart`, `lib/features/safety/domain/services/quick_exit_service.dart` (none expected: `clearCoupleMapDeviceData` already runs; confirm), `test/features/couple_map/sharing_sheet_test.dart`
- Test: additions in `sharing_sheet_test.dart`

**Interfaces:**
- Consumes: Task 4 (repository, store, `readHomeArea`/`writeHomeArea`); `presenceRepositoryProvider.currentPlace` isn't used. The home area is set from the **presence sampler**'s coarse fix, so no precise location is stored for home.
- Produces: rows "Remove all my places", "Warn me near home" / "Home area set", "Clear home area".

- [ ] **Step 1: Write the failing tests** (add `storyPlacesGatewayProvider` and `coupleMapLocalStoreProvider` overrides to the sheet harness):

```dart
  testWidgets('remove all my places asks first, then calls the RPC and says how many', (t) async {
    final places = FakeStoryPlacesGateway({'clear_my_story_places': (_) => 3});
    await _pump(t, const [_self], placesGateway: places);
    await t.tap(find.text('Remove all my places'));
    await t.pumpAndSettle();
    expect(find.text('Remove all your places from the map? Your stories stay.'), findsOneWidget);
    await t.tap(find.text('Remove all'));
    await t.pumpAndSettle();
    expect(places.calls.single.$1, 'clear_my_story_places');
    expect(find.text('Removed 3 places'), findsOneWidget);
  });

  testWidgets('home area: set from here (device only), then clear', (t) async {
    final local = MemoryCoupleMapLocalStore();
    await _pump(t, const [_self], local: local);
    await t.tap(find.text('Warn me near home'));
    await t.pumpAndSettle();
    expect(local.values[CoupleMapLocalKeys.homeArea], isNotNull);
    expect(find.text('Home area set'), findsOneWidget);
    await t.tap(find.text('Clear home area'));
    await t.pumpAndSettle();
    expect(local.values[CoupleMapLocalKeys.homeArea], isNull);
  });

  testWidgets('home area with no fix says so and stores nothing', (t) async {
    final local = MemoryCoupleMapLocalStore();
    await _pump(t, const [_self], local: local, noFix: true);
    await t.tap(find.text('Warn me near home'));
    await t.pumpAndSettle();
    expect(find.text("Couldn't find where you are. Try again."), findsOneWidget);
    expect(local.values, isEmpty);
  });
```

(Extend `_pump` with `FakeStoryPlacesGateway? placesGateway`, `MemoryCoupleMapLocalStore? local` and `bool noFix = false`. The sampler is `FakeSampler(next: noFix ? null : const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40))`.)

- [ ] **Step 2: Run them and confirm they fail.**

- [ ] **Step 3: Implement** in `sharing_sheet.dart`:
- State: `HomeArea? _home; bool _homeLoaded = false;` (loaded in `initState` via `readHomeArea(ref.read(coupleMapLocalStoreProvider))`).
- Below the existing card, add a second `CardInkWell` with:
  - **Home area**:
    - when unset, `InfoRowWidget(title: 'Warn me near home', subtitle: 'Kept on this phone only. Pins near it start off.', icon: Icons.home_outlined, showAvatar: false, showTrailingArrow: false, disableTrailing: true, showDivider: true, onTap: _setHome)`;
    - when set, two rows: `'Home area set'` (subtitle `'Pins near it start off'`, no tap) and `'Clear home area'` (`onTap: _clearHome`).
  - **Remove all**: `InfoRowWidget(title: 'Remove all my places', subtitle: 'Your stories stay', icon: Icons.wrong_location_outlined, showAvatar: false, showTrailingArrow: false, disableTrailing: true, showDivider: false, onTap: _removeAll)`.
- `_setHome`: `final s = await ref.read(presenceSamplerProvider).sample();`. If null, show the snackbar "Couldn't find where you are. Try again." Otherwise `writeHomeArea(store, HomeArea(lat: s.lat, lng: s.lng))` and `setState`. The sampler never prompts; if permission is missing the sample is null and the snackbar shows.
- `_clearHome`: `writeHomeArea(store, null)` and `setState`.
- `_removeAll`: confirm with an `AlertDialog` (title `'Remove all your places from the map? Your stories stay.'`, actions `Cancel` / `Remove all`). On confirm, `final n = await container.read(storyPlacesRepositoryProvider).clearMine(rel)`, then the snackbar `'Removed $n places'` (`'Removed 1 place'` when n == 1, `'No places to remove'` when n == 0). On error, `sharingErrorCopy`. Finally `container.invalidate(storyPlacesProvider)`. Capture the container before the await, as `_run` does.

Quick exit already calls `clearCoupleMapDeviceData()`, which now also clears the local store (Task 4). Add a source assertion to `couple_map_device_data_test.dart`: `clearCoupleMapDeviceData` references `CoupleMapLocalKeys.all`.

- [ ] **Step 4: Run them and confirm they pass,** together with `flutter test test/features/couple_map/`.
- [ ] **Step 5: Ledger.**

---

## Final verification (Phase 2 exit)

1. **Contracts:** run all of them on `run6.sh`: story places, every story suite, `together_story`, couple map presence, location presence, plus `together_*` and `reminder_*` (run5 or run6). Everything must be PASS.
2. **Full suite:** `flutter test`, green. A flaky test is rerun three times on its own and named.
3. **Analyzer:** `flutter analyze lib test 2>&1 | grep -E "^\s*(error|warning) "`: 0 errors, and nothing in touched files.
4. **Coverage (6.7):** `flutter test --coverage test/features/couple_map test/features/stories`. Targets: couple_map domain ≥ 90%, couple_map data ≥ 70%, widgets ≥ 50%. Record the numbers.
5. **Builds:** `flutter build apk --debug` and `flutter build ios --debug --no-codesign`.
6. **Scans:** secret scan (`pk.`/`sk.` tokens, tracked and untracked); PII grep (`print|debugPrint|log` in `couple_map` and the camera and reel diffs). Neither may interpolate a lat, lng, label or city.
7. **Fable review** of the whole Phase 2 diff against spec §2, §3.3–3.6, §4.5, §5.2, §6.4 and §9, plus this plan's Review Focus. Then one fix pass, each fix with a test that fails first.
8. **Spec amendments** (made in the fix pass if not before):
   - §3.3: cluster appearance (newest thumbnail plus count);
   - §5.2: the client fetches the world box;
   - §6.2 / §6.4 naming: `StoryReelScreen.forPlaces` (was `forItems`), `setStories` (was `setStoryFeatures`), `storyPlacesProvider(StoryPlacesKey(rel))` with client-side filtering (was `key{rel, filter, bbox}`);
   - §3.5: story list rows show the label as the title and the date (`MyDateFormat`) as the subtitle.
9. **Deploy note for the owner:**
   - `supabase db push` applies `20261017100000_story_places.sql`. The rename and wrapper are backward compatible, and older clients keep posting.
   - The `couple_map_enabled` flag still gates places on the server and the switch on the client.
   - **Rollback (checklist 8.1):**

     ```sql
     DROP FUNCTION public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int,jsonb);
     ALTER FUNCTION public.create_story_item_core(uuid,uuid,uuid,uuid,int,int,int,int) RENAME TO create_story_item;
     GRANT EXECUTE ON FUNCTION public.create_story_item(uuid,uuid,uuid,uuid,int,int,int,int) TO authenticated;
     NOTIFY pgrst, 'reload schema';
     ```

     `story_places` may stay; nothing writes it after the rollback.
   - **Smoke test (checklist 8.2), as a fixture couple after deploy:** post one story with a place, `list_story_places` returns it, `clear_story_place` removes it.
11. **Concurrency (checklist 6.3):** add a case to `scripts/concurrency/story_races.sh`. Race 1 (the same client id from two sessions) with the same `p_place` must leave exactly one `story_places` row; with different places, the winner's. Ledger the result.
10. **Manual checks (two devices, flag on):**
    - pin on, then post: the pin appears for both;
    - pin off, then post: nothing;
    - the remembered choice;
    - paused, then "Your area is paused";
    - set the home area, then post nearby: the warning shows and the switch turns off;
    - cluster, then zoom in, then tap: the reel, oldest first;
    - the filter cycle;
    - "Remove from map" for the author only;
    - "Remove all my places";
    - delete a story, and its pin goes;
    - end the relationship (test pair), and every place goes;
    - quick exit, then reopen: the switch is off again, no home area, the hint shows again.

## Checklist v3.1 evidence map (Phase 2)

| Item | Where it's proven |
|---|---|
| 1.1 / 2.18 Idempotency | P3 (replay never adds or changes a place); P7 (clearing twice) |
| 1.2 Timeouts | Place fix 20 s and geocode 10 s (resolver); pin photo 5 s (renderer) |
| 1.3 Graceful degradation | No fix, then posted without a place (Task 5); list failure, then the last pins kept (Task 4); remove failure, then plain copy (Task 7) |
| 1.4 / 1.5 Authorization and authentication | P1 (anon, the core not callable, no direct writes); P6 (outsider gets nothing); P7 (only the author clears) |
| 1.6 / 2.16 Concurrency | Place insert in the finalize transaction; serialised map draws (Task 6); slow lookup discarded after off (Task 5) |
| 1.10 Rollback | Place written inside `create_story_item` (same transaction); its failure never aborts the story (P4) |
| 1.11 Privacy and retention | P9 (delete removes the place); P12 (closing purges); home area device-only and cleared by quick exit (Tasks 4 and 9) |
| 2.1 Input sanitisation | P4 (malformed dropped, label trimmed); `StoryPlaceDraft.isValid` (Task 2) |
| 2.2 Parameterised queries | PL/pgSQL and SQL only; no `EXECUTE format` (grep in final verification) |
| 2.4 / 5.5 Errors don't leak | Plain copy for remove and remove-all failures (Tasks 7 and 9) |
| 2.5 / 3.1 Per-request limits | P10 (box required, 500 cap); client asks for the world box at 500 (Task 4) |
| 2.6 Output sanitisation | Labels as plain `Text` (Tasks 5, 7 and 8) |
| 2.10 Resources released | Pin controller disposed with the toggle; generation-guarded pushes |
| 2.12–2.15 / 3.4 Bounded cache | Raw pin LRU keyed by thumbnail key, not signed URL (Task 6 test) |
| 3.3 Indexes | P11 EXPLAIN recorded (after ANALYZE) |
| 3.10 No retrying permanent errors | A malformed place never makes the outbox `failedPermanent` (P4) |
| 4.4 No PII in logs | `StoryPlaceDraft`/`StoryPlace`/`HomeArea.toString` redacted (Task 2); repository logs `runtimeType` only; PII grep |
| 4.11 Configuration | `CoupleMapConfig.homeAreaRadiusM`, `placesLimit`, `storyPinSize`, `placeFixTimeout`; compass and ornament offsets passed by the tab |
| 5.6 Accessibility | The toggle's label and target (Task 5); "Remove from map" has a label (Task 7); list rows (Task 8) |
| 6.1 / 6.4 Edge and negative cases | P4 (each malformed shape); P5 (flag off); P10 (no box, empty box); no fix (Task 5) |
| 6.7 Coverage | Final verification step 4 |
| 6.8 Mutation checks | Task 1, Step 5 |
| 8.1 Rollback | `couple_map_enabled` off: the server drops places (P5) and the client hides the switch (Task 5) |
