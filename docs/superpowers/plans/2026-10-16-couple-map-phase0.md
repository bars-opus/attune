# Couple Map, Phase 0: Foundations (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild location presence on a safe server contract before any map UI exists. The contract covers:
- relationship-scoped rows;
- snapped ~1 km cells with hysteresis;
- a silent symmetric pause that clears the area;
- freshness instead of timestamps;
- purge on close;
- IANA time zones.

On top of the contract, Phase 0 moves every client caller onto it, closes the GPS EXIF leak in the image fallback path, and runs a Mapbox build spike.

**Architecture:**
- **Server:** one migration rebuilds `partner_presence` and replaces direct table writes with SECURITY DEFINER RPCs. The client reads one RPC, `couple_map_presence`, which returns at most a `self` row and a `partner` row with no partner coordinates finer than a cell and no timestamps.
- **Client:** `PresenceRepository` talks to the server only through a `PresenceGateway` seam and gets location only through a `PresenceSampler` seam, so tests use fakes. Providers sample only while the user is sharing.

**Tech stack:**
- App: Flutter 3.29, Riverpod 2.6, `geolocator` 14 (`LocationSettings`), `geocoding` 4 (on-device), `image` 4.3.0, `mapbox_maps_flutter` 2.24.3.
- Database: Supabase Postgres (PL/pgSQL, pg_cron).
- Tests: the PG17 stub harness at `$SCRATCH/pg/run.sh`, where `$SCRATCH` = `/private/tmp/claude-501/-Users-user-attune/ae9d44ca-41d8-47c2-b3e9-e1303709b261/scratchpad`.

**Spec:** `docs/superpowers/specs/2026-10-16-couple-map-design.md`. Read §2, §4, §5.1, §5.3, §6.1 and §9 before starting.

## Global Constraints
- Work on `main`, test first: write each test, run it, and watch it fail before writing the implementation. **No commits** unless the owner asks, so each task's commit step is a ledger line instead.
- The partner's position never reaches the client finer than a snapped cell (`numeric(6,3)`, about 1.1 km). No partner timestamp column ever leaves the server.
- **No partner-visible history.** Exactly one row per `(user_id, relationship_id)`, overwritten on each update.
- **Pause is symmetric and silent.** It also clears the cell, city and country. A partner who is paused looks exactly like stale data or no sharing at all.
- **Never log GPS coordinates, place labels or city names.** This is checklist item 4.4. Log only UUIDs and error categories.
- **The client never asks for location permission on its own.** It asks only after an explicit opt-in tap, and samples only while state = sharing. Use `LocationAccuracy.low`.
- **Configuration values:**

  | Name | Value |
  |---|---|
  | cell | 0.01° |
  | hysteresis | 300 m |
  | accuracy cutoff | 2000 m |
  | fading after | 4 h |
  | stale after | 8 h |
  | max pause | 8 h |
  | rate limit | 60 s |
  | retention | 7 days |

  These are named constants in SQL `presence_config(text)` and Dart `PresenceConfig`.
- **Time zones are IANA.** A zone not found in `pg_timezone_names` is stored as NULL and never rejected.
- **Analyzer check:** `flutter analyze` output must be filtered with `grep -E "^\s*(error|warning) "`, because the analyzer prints these words at the start of the line. Touched files must show zero matches.
- **Copy rules:** use plain words and the `InfoRowWidget` pattern. Nothing in the copy may explain a partner's absence (there is no "waiting for", no "unavailable", no reason given).

## Review Focus
1. **Pause, then resume, then no new sample.** The partner must see nothing until a fresh `record_presence`, so the pause can't be inferred. Covered by contract test C7 (Task 2).
2. **A user with no location permission toggles sharing on.** The row is created and permission is asked exactly once. The user sees no error, and sampling later returns null quietly. Covered by the widget test "toggle on asks once, toggle off deletes" (Task 6).
3. **GPS jitter at a cell boundary over repeated app opens.** The stored cell must not flip-flop. Covered by contract test C3 (Task 1).
4. **An ex-partner after the relationship is archived.** Their `couple_map_presence` returns nothing and both rows are gone. Covered by contract test C11 (Task 3).
5. **The web time zone abbreviation, e.g. "BST".** It is stored as NULL, so the partner gets no local time instead of a wrong one. Covered by contract test C9 (Task 2).

---

## File map

| File | Responsibility |
|---|---|
| `supabase/migrations/20261016100000_presence_v2.sql` (new) | Table rebuild, config, snapping and hysteresis, RPCs, visibility, purge trigger, cron, flag row, `partner_distance` retired |
| `supabase/tests/couple_map_presence_contracts.sql` (new) | Contracts C1–C13 |
| `supabase/tests/location_presence_test.sql` (modify) | Keep only the `place_updates` and haversine checks; the presence checks move to the new file |
| `lib/features/location/domain/couple_map_presence.dart` (new) | `PresenceFreshness`, `PresenceArea`, `PresenceState`, `CoupleMapPresence.fromRows` |
| `lib/features/location/domain/presence_config.dart` (new) | Dart mirror of the config constants |
| `lib/features/location/domain/partner_distance.dart` (modify) | Remove `closing`, `kmClosedSinceYesterday`, `partnerTimezone`, `partnerLocalTime` and `updatedAt`; add `partnerUtcOffsetMinutes` and `together` |
| `lib/features/location/domain/distance_copy.dart` (modify) | Compute local time from the offset and an injectable `now`; drop the `closing` branch |
| `lib/features/location/data/presence_gateway.dart` (new) | `PresenceGateway` plus the Supabase implementation |
| `lib/features/location/data/presence_sampler.dart` (new) | `PresenceSample`, `PresenceSampler`, `GeolocatorPresenceSampler` (low accuracy, check-only permission, timeouts, on-device geocode) |
| `lib/features/location/data/presence_repository.dart` (rewrite) | `startSharing`, `record`, `pause`, `resume`, `stopSharing`, `fetchMapPresence`; `postPlaceUpdate` and `currentPlace` kept |
| `lib/features/location/presentation/providers/presence_providers.dart` (rewrite) | Gateway, sampler and repository providers; `coupleMapPresenceProvider`, `presenceStateProvider`, `partnerDistanceProvider`, `coupleMapEnabledProvider` |
| `lib/features/chat/presentation/widgets/chat_settings_static_rows.dart` (modify) | Toggle scoped to the relationship |
| `lib/features/location/presentation/widgets/partner_distance_row.dart` (modify) | Relationship-scoped API; `closing` removed (the widget stays unused until Phase 1) |
| `lib/features/planning/presentation/widgets/dual_clock_block_view.dart` (modify) | Use `partnerUtcOffsetMinutes` |
| `lib/features/stories/domain/services/capture_image_preparer.dart`, `lib/features/chat/domain/services/chat_image_preparer.dart` (modify) | Clear EXIF in the Dart fallback |
| `lib/main.dart` (modify) | Mapbox token at bootstrap (spike) |
| Tests | `test/features/location/{couple_map_presence_test,presence_repository_test,presence_providers_test,distance_copy_test,location_wiring_test}.dart`, `test/features/chat/chat_settings_location_toggle_test.dart`, `test/features/planning/planning_couple_blocks_screen_test.dart`, `test/features/planning/support/planning_test_app.dart`, `test/features/stories/capture_image_preparer_exif_test.dart`, `test/features/chat/chat_image_preparer_exif_test.dart` |

**Harness setup (before Task 1).**
1. Copy `$SCRATCH/pg/run.sh` to `$SCRATCH/pg/run5.sh` and change the database name to `t5`.
2. In its migration list, after `20260814120000_couples_calendar_reminders`, add:
   ```
   20260932100000_location_presence 20260932110000_partner_distance 20260932130000_location_input_bounds
   ```
3. Before those, apply `$SCRATCH/pg/messages_stub.sql`, which contains:
   ```sql
   CREATE TABLE IF NOT EXISTS public.messages (id uuid PRIMARY KEY DEFAULT gen_random_uuid());
   ```
4. `run5.sh` already applies `20261015*`, so add `20261016*` to its glob as well.
5. Write a ledger line describing the harness.

---

### Task 1: The `presence_v2` schema, configuration, snapping and hysteresis

**Files:**
- Create: `supabase/migrations/20261016100000_presence_v2.sql`
- Test: `supabase/tests/couple_map_presence_contracts.sql`

**Interfaces:**
- Produces:
  - `public.presence_config(text) RETURNS numeric`
  - `public.presence_snap_cell(double precision, double precision, OUT cell_lat numeric, OUT cell_lng numeric)`
  - `public.presence_next_cell(numeric, numeric, double precision, double precision, OUT cell_lat numeric, OUT cell_lng numeric)`
  - the table `partner_presence(user_id, relationship_id, cell_lat, cell_lng, city, country, country_code, timezone, paused_until, updated_at)`

- [ ] **Step 1: Write the failing contracts C1–C3**

```sql
-- supabase/tests/couple_map_presence_contracts.sql
-- Couple Map presence contracts (spec 2026-10-16 §4–§5.1). Every check RAISEs.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO auth.users(id) VALUES
  ('7a000000-0000-0000-0000-0000000000a1'), ('7a000000-0000-0000-0000-0000000000b2'),
  ('7a000000-0000-0000-0000-0000000000c3') ON CONFLICT DO NOTHING;
INSERT INTO public.users(id, phone, display_name) VALUES
  ('7a000000-0000-0000-0000-0000000000a1', '+15550007001', 'Ama'),
  ('7a000000-0000-0000-0000-0000000000b2', '+15550007002', 'Kofi'),
  ('7a000000-0000-0000-0000-0000000000c3', '+15550007003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships(id, user_a, user_b, status) VALUES
  ('7a100000-0000-0000-0000-000000000001', '7a000000-0000-0000-0000-0000000000a1',
   '7a000000-0000-0000-0000-0000000000b2', 'active') ON CONFLICT (id) DO NOTHING;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- C1. Raw coordinates are gone; cells, a relationship key and pause exist.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'partner_presence'
             AND column_name IN ('latitude', 'longitude')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: raw coordinates are still stored';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns WHERE table_name = 'partner_presence'
      AND column_name IN ('cell_lat', 'cell_lng', 'relationship_id', 'paused_until')) <> 4 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: presence_v2 columns missing';
  END IF;
END $$;

-- C2. Snapping is deterministic and lands on a cell centre.
DO $$
DECLARE a record; b record;
BEGIN
  SELECT * INTO a FROM public.presence_snap_cell(5.5603, -0.2057);
  SELECT * INTO b FROM public.presence_snap_cell(5.5609, -0.2051);
  IF a.cell_lat <> 5.565 OR a.cell_lat <> b.cell_lat OR a.cell_lng <> b.cell_lng THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: snapping not deterministic (% % / % %)', a.cell_lat, a.cell_lng, b.cell_lat, b.cell_lng;
  END IF;
  -- The poles never overflow the coordinate system.
  SELECT * INTO a FROM public.presence_snap_cell(90, 180);
  IF a.cell_lat > 90 OR a.cell_lng > 180 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pole snapped outside range (% %)', a.cell_lat, a.cell_lng;
  END IF;
END $$;

-- C3. Hysteresis: jitter across a boundary keeps the stored cell; a real move changes it.
DO $$
DECLARE c record; moved record;
BEGIN
  -- (5.565, -0.208) is Accra's real cell centre; 5.5599 is ~11 m over its southern edge.
  SELECT * INTO c FROM public.presence_next_cell(5.565, -0.208, 5.5599, -0.2080);
  IF c.cell_lat <> 5.565 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 20 m of jitter flipped the cell to %', c.cell_lat;
  END IF;
  SELECT * INTO moved FROM public.presence_next_cell(5.565, -0.208, 5.5450, -0.2080);
  IF moved.cell_lat = 5.565 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 2 km move kept the old cell';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `bash $SCRATCH/pg/run5.sh $PWD/supabase/tests/couple_map_presence_contracts.sql 2>&1 | grep -E "CONTRACT|ERROR|^PASS|^FAIL"`
Expected: FAIL with `CONTRACT VIOLATED: raw coordinates are still stored`.

- [ ] **Step 3: Write the migration's first part**

```sql
-- supabase/migrations/20261016100000_presence_v2.sql
--
-- Couple Map, Phase 0 (spec 2026-10-16 §4–§5.1). Presence becomes
-- relationship-scoped, stored only as a snapped ~1 km cell, written only
-- through RPCs, paused silently and symmetrically, and read through one
-- function that never returns a partner timestamp or anything finer than a
-- cell. Existing rows are dropped: nothing renders them, and users opt in
-- again. partner_distance is retired (the dual clock moves to
-- couple_map_presence).

-- The feature's numbers, in one place (checklist 4.11).
CREATE OR REPLACE FUNCTION public.presence_config(p_key text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
    WHEN 'cell_deg' THEN 0.01
    WHEN 'hysteresis_m' THEN 300
    WHEN 'accuracy_cutoff_m' THEN 2000
    WHEN 'fading_after_h' THEN 4
    WHEN 'stale_after_h' THEN 8
    WHEN 'max_pause_h' THEN 8
    WHEN 'rate_limit_s' THEN 60
    WHEN 'retention_days' THEN 7
  END
$$;

DROP FUNCTION IF EXISTS public.partner_distance(uuid);
DROP TABLE IF EXISTS public.partner_presence;

CREATE TABLE public.partner_presence (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  -- The snapped cell centre, never a raw point. NULL while paused or
  -- when only a city is known (accuracy worse than the cutoff).
  cell_lat numeric(6, 3),
  cell_lng numeric(6, 3),
  city text,
  country text,
  country_code text,
  timezone text,
  paused_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, relationship_id),
  CONSTRAINT partner_presence_cell_paired CHECK ((cell_lat IS NULL) = (cell_lng IS NULL)),
  CONSTRAINT partner_presence_cell_range CHECK (
    cell_lat IS NULL OR (cell_lat BETWEEN -90 AND 90 AND cell_lng BETWEEN -180 AND 180)),
  CONSTRAINT partner_presence_text_lengths CHECK (
    (city IS NULL OR char_length(city) <= 120)
    AND (country IS NULL OR char_length(country) <= 120)
    AND (country_code IS NULL OR char_length(country_code) <= 8)
    AND (timezone IS NULL OR char_length(timezone) <= 64))
);
CREATE INDEX partner_presence_relationship_idx ON public.partner_presence (relationship_id);
CREATE INDEX partner_presence_updated_idx ON public.partner_presence (updated_at);

ALTER TABLE public.partner_presence ENABLE ROW LEVEL SECURITY;
CREATE POLICY partner_presence_self ON public.partner_presence
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY partner_presence_self_delete ON public.partner_presence
  FOR DELETE TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.partner_presence FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.partner_presence TO authenticated;

-- A deterministic ~1 km grid. The longitude step comes from the snapped
-- latitude BAND, so the index can't drift within a band.
CREATE OR REPLACE FUNCTION public.presence_snap_cell(
  p_lat double precision, p_lng double precision,
  OUT cell_lat numeric, OUT cell_lng numeric)
LANGUAGE sql IMMUTABLE AS $$
  WITH b AS (
    SELECT least(floor(p_lat / 0.01), 8999) AS lat_idx
  ), band AS (
    SELECT lat_idx * 0.01 + 0.005 AS band_lat FROM b
  ), step AS (
    SELECT band_lat, 0.01 / greatest(cos(radians(band_lat)), 0.2) AS lng_step FROM band
  )
  SELECT round(band_lat::numeric, 3),
         round(least(greatest(
           floor((p_lng + 180) / lng_step) * lng_step + lng_step / 2 - 180, -180), 180)::numeric, 3)
  FROM step
$$;

-- The next cell to store: the new one only when the raw point is more than
-- the hysteresis distance outside the stored cell, so GPS noise at a
-- boundary never flips the pin (which would reveal movement).
CREATE OR REPLACE FUNCTION public.presence_next_cell(
  p_old_lat numeric, p_old_lng numeric, p_lat double precision, p_lng double precision,
  OUT cell_lat numeric, OUT cell_lng numeric)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v_new record;
  v_half_lng double precision;
  v_near_lat double precision;
  v_near_lng double precision;
BEGIN
  SELECT * INTO v_new FROM public.presence_snap_cell(p_lat, p_lng);
  IF p_old_lat IS NULL OR (v_new.cell_lat = p_old_lat AND v_new.cell_lng = p_old_lng) THEN
    cell_lat := v_new.cell_lat; cell_lng := v_new.cell_lng; RETURN;
  END IF;
  v_half_lng := (0.01 / greatest(cos(radians(p_old_lat::double precision)), 0.2)) / 2;
  v_near_lat := least(greatest(p_lat, p_old_lat - 0.005), p_old_lat + 0.005);
  v_near_lng := least(greatest(p_lng, p_old_lng - v_half_lng), p_old_lng + v_half_lng);
  IF public.haversine_km(p_lat::numeric, p_lng::numeric, v_near_lat::numeric, v_near_lng::numeric) * 1000
       > public.presence_config('hysteresis_m') THEN
    cell_lat := v_new.cell_lat; cell_lng := v_new.cell_lng;
  ELSE
    cell_lat := p_old_lat; cell_lng := p_old_lng;
  END IF;
END
$$;
```

- [ ] **Step 4: Run the contracts and confirm they pass**

Run: the same command as Step 2.
Expected: `PASS …couple_map_presence_contracts.sql`.

- [ ] **Step 5: Ledger.** `Task 1: complete (C1–C3 RED→PASS)`.

---

### Task 2: The presence RPCs, symmetric visibility, pause and rate limit

**Files:**
- Modify: `supabase/migrations/20261016100000_presence_v2.sql` (append)
- Test: `supabase/tests/couple_map_presence_contracts.sql` (append before `ROLLBACK;`)

**Interfaces:**
- Consumes: the Task 1 functions.
- Produces:
  - `start_presence(uuid)`, `stop_presence(uuid)`
  - `record_presence(uuid, double precision, double precision, double precision, text, text, text, text)` with parameters `p_relationship_id, p_lat, p_lng, p_accuracy_m, p_city, p_country, p_country_code, p_timezone`
  - `set_presence_pause(uuid, timestamptz)`
  - `couple_map_presence(uuid) RETURNS TABLE(who text, cell_lat numeric, cell_lng numeric, city text, country text, utc_offset_minutes int, freshness text, my_paused_until timestamptz, distance_km int, together boolean)`

  Only the `self` row ever carries `my_paused_until`. Distance and together appear only on the `partner` row.

- [ ] **Step 1: Write the failing contracts C4–C10**

```sql
-- C4. Opt-in is explicit: record does nothing without start; start then record shows my cell.
DO $$
DECLARE v_rows int; v_self record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 5.5603, -0.2057, 50, 'Accra', 'Ghana', 'GH', 'Africa/Accra');
  SELECT count(*) INTO v_rows FROM public.partner_presence;
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: sampling created sharing without opt-in'; END IF;
  PERFORM public.start_presence('7a100000-0000-0000-0000-000000000001');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 5.5603, -0.2057, 50, 'Accra', 'Ghana', 'GH', 'Africa/Accra');
  SELECT * INTO v_self FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'self';
  IF v_self.cell_lat <> 5.565 OR v_self.city <> 'Accra' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: own area missing %', v_self; END IF;
END $$;

-- C5. Symmetry: no partner row until both share; then a rounded distance.
DO $$
DECLARE v_rows int; v_p record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a partner who never shared appeared'; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.start_presence('7a100000-0000-0000-0000-000000000001');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 51.5074, -0.1278, 30, 'London', 'United Kingdom', 'GB', 'Europe/London');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.city <> 'London' OR v_p.distance_km NOT BETWEEN 5000 AND 5200 OR v_p.distance_km % 10 <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner row/rounding wrong %', v_p;
  END IF;
END $$;

-- C6. No partner timestamp ever leaves the server; my_paused_until is self-only.
DO $$
DECLARE v_p record;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.routines r
             JOIN information_schema.parameters p ON p.specific_name = r.specific_name
             WHERE r.routine_name = 'couple_map_presence' AND p.parameter_mode = 'OUT'
               AND p.parameter_name IN ('updated_at', 'partner_updated_at', 'self_updated_at')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a timestamp column leaves the server';
  END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.my_paused_until IS NOT NULL THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner pause time leaked'; END IF;
END $$;

-- C7. Pause is symmetric and indistinguishable from stale; resume needs a fresh sample.
DO $$
DECLARE v_rows int;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', now() + interval '1 hour');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a paused partner was visible'; END IF;
  -- Symmetric: Kofi, while paused, doesn't see Ama either.
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: the pausing partner could still watch'; END IF;
  -- Resume with no new sample: still nothing (the cell was cleared by pause).
  PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', NULL);
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: resume showed the pre-pause area'; END IF;
  -- A fresh sample brings it back.
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 51.5074, -0.1278, 30, 'London', 'United Kingdom', 'GB', 'Europe/London');
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh sample after resume did not show'; END IF;
END $$;

-- C8. Freshness: fading after 4 h, gone after 8 h; a too-long pause is refused.
DO $$
DECLARE v_p record; v_rows int;
BEGIN
  UPDATE public.partner_presence SET updated_at = now() - interval '5 hours'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT * INTO v_p FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_p.freshness <> 'fading' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: 5 h old should be fading, got %', v_p.freshness; END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '9 hours'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'partner';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a 9 h old area was shown'; END IF;
  UPDATE public.partner_presence SET updated_at = now() - interval '2 minutes'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  BEGIN
    PERFORM public.set_presence_pause('7a100000-0000-0000-0000-000000000001', now() + interval '9 hours');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 9 h pause was accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
END $$;

-- C9. Bad input: an unknown zone is stored NULL; coordinates out of range are refused; low accuracy keeps city only.
DO $$
DECLARE v_self record;
BEGIN
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  UPDATE public.partner_presence SET updated_at = now() - interval '2 minutes'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000a1';
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 5.6, -0.2, 5000, 'Accra', 'Ghana', 'GH', 'BST');
  SELECT * INTO v_self FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001') WHERE who = 'self';
  IF v_self.cell_lat IS NOT NULL OR v_self.city <> 'Accra' OR v_self.utc_offset_minutes IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 5 km accuracy or a bad zone was stored as precise %', v_self;
  END IF;
  BEGIN
    PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 999, 0, 10, NULL, NULL, NULL, NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: latitude 999 accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'CONTRACT VIOLATED%' THEN RAISE; END IF;
  END;
END $$;

-- C10. Rate limit, outsiders and anon.
DO $$
DECLARE v_before numeric; v_after numeric; v_rows int;
BEGIN
  -- now() is fixed within the test transaction: make the stored update 10 s old.
  UPDATE public.partner_presence SET updated_at = now() - interval '10 seconds'
  WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000b2');
  SELECT cell_lat INTO v_before FROM public.partner_presence WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  PERFORM public.record_presence('7a100000-0000-0000-0000-000000000001', 48.8566, 2.3522, 20, 'Paris', 'France', 'FR', 'Europe/Paris');
  SELECT cell_lat INTO v_after FROM public.partner_presence WHERE user_id = '7a000000-0000-0000-0000-0000000000b2';
  IF v_after IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a second record within 60 s was applied'; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000c3');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001');
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an outsider read the couple'; END IF;
  IF has_function_privilege('anon', 'public.couple_map_presence(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon may read presence';
  END IF;
END $$;
```

- [ ] **Step 2: Run them and confirm they fail**

Run: the harness command.
Expected: FAIL with `function public.record_presence(...) does not exist`.

- [ ] **Step 3: Append the RPCs to the migration**

```sql
-- Membership of an ACTIVE, unarchived relationship (paused or ended
-- relationships share nothing; the purge trigger clears them).
CREATE OR REPLACE FUNCTION public.presence_partner_of(p_relationship_id uuid, p_user uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE WHEN r.user_a = p_user THEN r.user_b WHEN r.user_b = p_user THEN r.user_a END
  FROM public.relationships r
  WHERE r.id = p_relationship_id AND r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_user OR r.user_b = p_user)
$$;
REVOKE ALL ON FUNCTION public.presence_partner_of(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.presence_fail(p_code text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'presence:%', p_code USING ERRCODE = 'P0001'; END $$;
REVOKE ALL ON FUNCTION public.presence_fail(text) FROM PUBLIC, anon, authenticated;

-- Opting in creates the (empty) row; sampling only ever updates it.
CREATE OR REPLACE FUNCTION public.start_presence(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR public.presence_partner_of(p_relationship_id, auth.uid()) IS NULL THEN
    PERFORM public.presence_fail('not_found');
  END IF;
  INSERT INTO public.partner_presence (user_id, relationship_id)
  VALUES (auth.uid(), p_relationship_id) ON CONFLICT (user_id, relationship_id) DO NOTHING;
END $$;

-- Turning sharing off deletes the row, silently.
CREATE OR REPLACE FUNCTION public.stop_presence(p_relationship_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  DELETE FROM public.partner_presence WHERE user_id = auth.uid() AND relationship_id = p_relationship_id;
END $$;

CREATE OR REPLACE FUNCTION public.record_presence(
  p_relationship_id uuid, p_lat double precision, p_lng double precision, p_accuracy_m double precision,
  p_city text, p_country text, p_country_code text, p_timezone text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_row public.partner_presence;
  v_cell record;
  v_tz text;
  v_precise boolean;
BEGIN
  IF v_me IS NULL OR public.presence_partner_of(p_relationship_id, v_me) IS NULL THEN
    PERFORM public.presence_fail('not_found');
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
     OR p_accuracy_m IS NULL OR p_accuracy_m < 0 THEN
    PERFORM public.presence_fail('invalid_input');
  END IF;
  SELECT * INTO v_row FROM public.partner_presence
  WHERE user_id = v_me AND relationship_id = p_relationship_id FOR UPDATE;
  -- Not opted in: sampling never creates sharing.
  IF NOT FOUND THEN RETURN; END IF;
  -- Paused: nothing is recorded.
  IF v_row.paused_until IS NOT NULL AND v_row.paused_until > now() THEN RETURN; END IF;
  -- Rate limit (checklist 3.8), only once an area is stored.
  IF v_row.cell_lat IS NOT NULL
     AND v_row.updated_at > now() - make_interval(secs => public.presence_config('rate_limit_s')::int) THEN
    RETURN;
  END IF;
  v_tz := CASE WHEN p_timezone IS NOT NULL
                AND EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_timezone) THEN p_timezone END;
  v_precise := p_accuracy_m <= public.presence_config('accuracy_cutoff_m');
  IF v_precise THEN
    SELECT * INTO v_cell FROM public.presence_next_cell(v_row.cell_lat, v_row.cell_lng, p_lat, p_lng);
  END IF;
  UPDATE public.partner_presence SET
    cell_lat = CASE WHEN v_precise THEN v_cell.cell_lat END,
    cell_lng = CASE WHEN v_precise THEN v_cell.cell_lng END,
    city = left(p_city, 120), country = left(p_country, 120), country_code = left(p_country_code, 8),
    timezone = v_tz, paused_until = NULL, updated_at = now()
  WHERE user_id = v_me AND relationship_id = p_relationship_id;
END $$;

-- Pause clears the area, so a resume can't show the pre-pause cell.
CREATE OR REPLACE FUNCTION public.set_presence_pause(p_relationship_id uuid, p_until timestamptz)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN PERFORM public.presence_fail('not_found'); END IF;
  IF p_until IS NOT NULL AND p_until <> 'infinity'::timestamptz
     AND (p_until <= now() OR p_until > now() + make_interval(hours => public.presence_config('max_pause_h')::int)) THEN
    PERFORM public.presence_fail('invalid_input');
  END IF;
  UPDATE public.partner_presence SET
    paused_until = p_until,
    cell_lat = CASE WHEN p_until IS NULL THEN cell_lat END,
    cell_lng = CASE WHEN p_until IS NULL THEN cell_lng END,
    city = CASE WHEN p_until IS NULL THEN city END,
    country = CASE WHEN p_until IS NULL THEN country END,
    country_code = CASE WHEN p_until IS NULL THEN country_code END
  WHERE user_id = auth.uid() AND relationship_id = p_relationship_id;
  IF NOT FOUND THEN PERFORM public.presence_fail('not_sharing'); END IF;
END $$;

-- Minutes ahead of UTC for an IANA zone, now (NULL if unknown).
CREATE OR REPLACE FUNCTION public.presence_offset_minutes(p_tz text)
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT (extract(epoch FROM (now() AT TIME ZONE p_tz) - (now() AT TIME ZONE 'UTC')) / 60)::int
  WHERE p_tz IS NOT NULL AND EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz)
$$;

CREATE OR REPLACE FUNCTION public.couple_map_presence(p_relationship_id uuid)
RETURNS TABLE (who text, cell_lat numeric, cell_lng numeric, city text, country text,
               utc_offset_minutes int, freshness text, my_paused_until timestamptz,
               distance_km int, together boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_me uuid := auth.uid();
  v_partner uuid;
  s public.partner_presence;
  o public.partner_presence;
  v_km double precision;
  v_step double precision;
BEGIN
  IF v_me IS NULL THEN RETURN; END IF;
  v_partner := public.presence_partner_of(p_relationship_id, v_me);
  IF v_partner IS NULL THEN RETURN; END IF;
  SELECT * INTO s FROM public.partner_presence WHERE user_id = v_me AND relationship_id = p_relationship_id;
  IF NOT FOUND THEN RETURN; END IF;

  RETURN QUERY SELECT 'self'::text, s.cell_lat, s.cell_lng, s.city, s.country,
    public.presence_offset_minutes(s.timezone),
    CASE WHEN s.updated_at > now() - make_interval(hours => public.presence_config('fading_after_h')::int)
         THEN 'fresh' ELSE 'fading' END,
    CASE WHEN s.paused_until > now() THEN s.paused_until END,
    NULL::int, NULL::boolean;

  -- Symmetric: I see my partner only while I share, unpaused, with a fresh cell — and so do they.
  IF s.cell_lat IS NULL OR (s.paused_until IS NOT NULL AND s.paused_until > now())
     OR s.updated_at <= now() - make_interval(hours => public.presence_config('stale_after_h')::int) THEN
    RETURN;
  END IF;
  SELECT * INTO o FROM public.partner_presence WHERE user_id = v_partner AND relationship_id = p_relationship_id;
  IF NOT FOUND OR o.cell_lat IS NULL OR (o.paused_until IS NOT NULL AND o.paused_until > now())
     OR o.updated_at <= now() - make_interval(hours => public.presence_config('stale_after_h')::int) THEN
    RETURN;
  END IF;
  v_km := public.haversine_km(s.cell_lat, s.cell_lng, o.cell_lat, o.cell_lng);
  v_step := 0.01 / greatest(cos(radians(s.cell_lat::double precision)), 0.2);
  RETURN QUERY SELECT 'partner'::text, o.cell_lat, o.cell_lng, o.city, o.country,
    public.presence_offset_minutes(o.timezone),
    CASE WHEN o.updated_at > now() - make_interval(hours => public.presence_config('fading_after_h')::int)
         THEN 'fresh' ELSE 'fading' END,
    NULL::timestamptz,
    CASE WHEN v_km < 50 THEN greatest(2, (round(v_km / 5) * 5)::int) ELSE (round(v_km / 10) * 10)::int END,
    (abs(s.cell_lat - o.cell_lat) <= 0.0101 AND abs(s.cell_lng - o.cell_lng) <= v_step * 1.01);
END $$;

REVOKE ALL ON FUNCTION public.start_presence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.stop_presence(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_presence(uuid, double precision, double precision, double precision, text, text, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_presence_pause(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.couple_map_presence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.stop_presence(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_presence(uuid, double precision, double precision, double precision, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_presence_pause(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.couple_map_presence(uuid) TO authenticated;
```

- [ ] **Step 4: Run the contracts and confirm they pass.** Expected: `PASS`.
- [ ] **Step 5: Mutation-check two rules, then restore and re-run.**
  - Remove `OR (s.paused_until IS NOT NULL AND s.paused_until > now())` from the symmetry check. C7 must fail.
  - Make pause stop clearing `cell_lat`. C7's resume check must fail.

  Ledger both results.

---

### Task 3: Purge on close, retention cron, feature flag, and the old location test migrated

**Files:**
- Modify: `supabase/migrations/20261016100000_presence_v2.sql` (append)
- Modify: `supabase/tests/couple_map_presence_contracts.sql` (append C11–C13)
- Modify: `supabase/tests/location_presence_test.sql`: remove the presence/`partner_distance` blocks (lines 22–116 today); keep the `place_updates` and bounds blocks, and adjust the inserts that referenced old presence columns.

**Interfaces:**
- Produces: the trigger `presence_purge_on_relationship_close`; `presence_purge_stale()`; the cron job `presence_purge_stale`; the feature flag row `couple_map_enabled = false`.

- [ ] **Step 1: Write the failing contracts C11–C13**

```sql
-- C11. Closing the relationship purges both rows; a pause of the relationship does too.
DO $$
DECLARE v_rows int;
BEGIN
  UPDATE public.relationships SET chat_archived_at = now() WHERE id = '7a100000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_rows FROM public.partner_presence WHERE relationship_id = '7a100000-0000-0000-0000-000000000001';
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: archiving left % presence rows', v_rows; END IF;
  PERFORM pg_temp.as_user('7a000000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_rows FROM public.couple_map_presence('7a100000-0000-0000-0000-000000000001');
  IF v_rows <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: an archived couple still reads presence'; END IF;
END $$;

-- C12. Retention: rows untouched for more than 7 days go; fresh ones stay.
DO $$
DECLARE v_rows int;
BEGIN
  INSERT INTO public.relationships(id, user_a, user_b, status) VALUES
    ('7a100000-0000-0000-0000-000000000002', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000c3', 'active');
  INSERT INTO public.partner_presence(user_id, relationship_id, updated_at) VALUES
    ('7a000000-0000-0000-0000-0000000000a1', '7a100000-0000-0000-0000-000000000002', now() - interval '8 days'),
    ('7a000000-0000-0000-0000-0000000000c3', '7a100000-0000-0000-0000-000000000002', now());
  PERFORM public.presence_purge_stale();
  SELECT count(*) INTO v_rows FROM public.partner_presence WHERE relationship_id = '7a100000-0000-0000-0000-000000000002';
  IF v_rows <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: retention kept % rows', v_rows; END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'presence_purge_stale') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retention job not scheduled';
  END IF;
END $$;

-- C13. The old distance function is retired; the flag ships off; no direct writes.
DO $$
BEGIN
  IF to_regprocedure('public.partner_distance(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner_distance still exists';
  END IF;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'couple_map_enabled') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_map_enabled must exist and be off';
  END IF;
  IF has_table_privilege('authenticated', 'public.partner_presence', 'INSERT')
     OR has_table_privilege('authenticated', 'public.partner_presence', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clients can write presence directly';
  END IF;
END $$;
```

- [ ] **Step 2: Run them and confirm they fail** (C11 fails: archiving left rows).

- [ ] **Step 3: Append the purge, cron and flag to the migration**

```sql
CREATE OR REPLACE FUNCTION public.presence_purge_on_relationship_close()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.partner_presence WHERE relationship_id = NEW.id;
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.presence_purge_on_relationship_close() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS presence_purge_on_relationship_close ON public.relationships;
CREATE TRIGGER presence_purge_on_relationship_close
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.presence_purge_on_relationship_close();

CREATE OR REPLACE FUNCTION public.presence_purge_stale()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.partner_presence
  WHERE updated_at < now() - make_interval(days => public.presence_config('retention_days')::int);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.presence_purge_stale() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'presence_purge_stale'; END $$;
SELECT cron.schedule('presence_purge_stale', '17 * * * *', $$ SELECT public.presence_purge_stale(); $$);

INSERT INTO public.feature_flags (key, enabled) VALUES ('couple_map_enabled', false)
ON CONFLICT (key) DO NOTHING;
```

- [ ] **Step 4: Edit `location_presence_test.sql`.** Delete its presence and `partner_distance` blocks and keep the `place_updates` and bounds blocks.
- [ ] **Step 5: Run both contract files, and every other contract that still applies, then confirm they pass.**
  - Run: `bash $SCRATCH/pg/run5.sh $PWD/supabase/tests/couple_map_presence_contracts.sql $PWD/supabase/tests/location_presence_test.sql $(ls $PWD/supabase/tests/together_*_contracts.sql $PWD/supabase/tests/reminder_*_contracts.sql) | grep -E "^PASS|^FAIL|CONTRACT"`
  - Expected: every line is PASS.
- [ ] **Step 6: Mutation check.** Remove the `chat_archived_at` arm of the trigger; C11 must fail. Restore and write a ledger line.
- [ ] **Step 7: EXPLAIN evidence (checklist 3.3).**
  - Run `EXPLAIN SELECT * FROM partner_presence WHERE user_id=$1 AND relationship_id=$2` on the harness; it should be an index scan on the primary key.
  - Run `EXPLAIN DELETE … WHERE updated_at < now()-'7 days'`; it should use `partner_presence_updated_idx`, or a sequential scan on the small table, justified in the ledger.

---

### Task 4: The Dart domain: map presence, distance and copy

**Files:**
- Create: `lib/features/location/domain/presence_config.dart`, `lib/features/location/domain/couple_map_presence.dart`
- Modify: `lib/features/location/domain/partner_distance.dart`, `lib/features/location/domain/distance_copy.dart`
- Test: `test/features/location/couple_map_presence_test.dart` (new), `test/features/location/distance_copy_test.dart` (modify)

**Interfaces:**
- Produces:
  - `PresenceConfig` (constants)
  - `enum PresenceFreshness { fresh, fading }`
  - `class PresenceArea { double? cellLat, cellLng; String? city, country; int? utcOffsetMinutes; PresenceFreshness freshness; }`
  - `enum PresenceStatus { off, sharing, paused }`
  - `class PresenceState { PresenceStatus status; DateTime? pausedUntil; }`
  - `class CoupleMapPresence { PresenceArea? self; PresenceArea? partner; int? distanceKm; bool together; PresenceState state; PartnerDistance? partnerDistance; static CoupleMapPresence fromRows(List<Map<String, dynamic>>); static const none; }`
  - `PartnerDistance({required double km, String? partnerCity, int? partnerUtcOffsetMinutes, int? daysUntilTogether, bool together = false})`
  - `distanceCopy(PartnerDistance d, {String? partnerName, DateTime? now})`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/location/couple_map_presence_test.dart
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(String who, {num? lat = 5.565, String? city = 'Accra', int? offset = 0,
        String freshness = 'fresh', String? pausedUntil, int? km, bool? together}) =>
    {'who': who, 'cell_lat': lat, 'cell_lng': lat == null ? null : -0.205, 'city': city, 'country': 'Ghana',
     'utc_offset_minutes': offset, 'freshness': freshness, 'my_paused_until': pausedUntil,
     'distance_km': km, 'together': together};

void main() {
  test('no rows: not sharing, nothing to show', () {
    final p = CoupleMapPresence.fromRows(const []);
    expect(p.state.status, PresenceStatus.off);
    expect(p.self, isNull);
    expect(p.partner, isNull);
    expect(p.partnerDistance, isNull);
  });

  test('self only: sharing, no partner and no distance', () {
    final p = CoupleMapPresence.fromRows([_row('self')]);
    expect(p.state.status, PresenceStatus.sharing);
    expect(p.self!.city, 'Accra');
    expect(p.partnerDistance, isNull);
  });

  test('a pause shows as paused with its end, self-facing only', () {
    final p = CoupleMapPresence.fromRows([_row('self', lat: null, city: null, pausedUntil: '2026-10-16T12:00:00Z')]);
    expect(p.state.status, PresenceStatus.paused);
    expect(p.state.pausedUntil, DateTime.utc(2026, 10, 16, 12));
  });

  test('both: the partner area, the rounded distance and their offset', () {
    final p = CoupleMapPresence.fromRows([
      _row('self'),
      _row('partner', lat: 51.505, city: 'London', offset: 60, freshness: 'fading', km: 5100, together: false),
    ]);
    expect(p.partner!.freshness, PresenceFreshness.fading);
    expect(p.partnerDistance!.km, 5100);
    expect(p.partnerDistance!.partnerUtcOffsetMinutes, 60);
    expect(p.partnerDistance!.partnerCity, 'London');
  });

  test('adjacent cells read as together', () {
    final p = CoupleMapPresence.fromRows([_row('self'), _row('partner', km: 2, together: true)]);
    expect(p.partnerDistance!.tone, DistanceTone.together);
  });

  test('an unknown freshness value is treated as fading, never as fresh', () {
    final p = CoupleMapPresence.fromRows([_row('self'), _row('partner', freshness: 'weird', km: 10, together: false)]);
    expect(p.partner!.freshness, PresenceFreshness.fading);
  });
}
```

In `distance_copy_test.dart`:
- Delete the three tests that reference `kmClosedSinceYesterday` and `DistanceTone.closing` (lines 50–86 today).
- Replace the clock test with:

```dart
    test('far apart with nothing booked leads with their clock', () {
      final copy = distanceCopy(
        const PartnerDistance(km: 5100, partnerUtcOffsetMinutes: 60),
        now: DateTime.utc(2026, 9, 2, 22, 15),
      );
      expect(copy.headline, '11:15pm where they are');
      expect(copy.detail, '5.1k km apart');
    });
```

- [ ] **Step 2: Run them and confirm they fail.** `flutter test test/features/location/`. Expected: compilation fails, because `couple_map_presence.dart` doesn't exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/location/domain/presence_config.dart
/// The couple map's numbers (spec §9 / checklist 4.11). Mirrors SQL presence_config().
abstract final class PresenceConfig {
  static const fadingAfter = Duration(hours: 4);
  static const staleAfter = Duration(hours: 8);
  static const maxPause = Duration(hours: 8);
  static const refreshEvery = Duration(minutes: 15);
  static const fixTimeout = Duration(seconds: 20);
  static const geocodeTimeout = Duration(seconds: 10);
}
```

```dart
// lib/features/location/domain/couple_map_presence.dart
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter/foundation.dart';

/// How fresh an area is. The server sends only this, never a time:
/// times would read as "when they last opened the app".
enum PresenceFreshness { fresh, fading }

@immutable
class PresenceArea {
  const PresenceArea({this.cellLat, this.cellLng, this.city, this.country,
      this.utcOffsetMinutes, this.freshness = PresenceFreshness.fresh});
  final double? cellLat;
  final double? cellLng;
  final String? city;
  final String? country;
  final int? utcOffsetMinutes;
  final PresenceFreshness freshness;

  factory PresenceArea.fromRow(Map<String, dynamic> r) => PresenceArea(
        cellLat: (r['cell_lat'] as num?)?.toDouble(),
        cellLng: (r['cell_lng'] as num?)?.toDouble(),
        city: r['city'] as String?,
        country: r['country'] as String?,
        utcOffsetMinutes: (r['utc_offset_minutes'] as num?)?.toInt(),
        // Anything unexpected is treated as the less certain state.
        freshness: r['freshness'] == 'fresh' ? PresenceFreshness.fresh : PresenceFreshness.fading,
      );
}

enum PresenceStatus { off, sharing, paused }

/// My own sharing state (self-facing; the partner never sees a reason).
@immutable
class PresenceState {
  const PresenceState(this.status, {this.pausedUntil});
  final PresenceStatus status;
  final DateTime? pausedUntil;
  bool get isOn => status != PresenceStatus.off;
}

/// What couple_map_presence returned: at most my area and my partner's.
@immutable
class CoupleMapPresence {
  const CoupleMapPresence({this.self, this.partner, this.distanceKm, this.together = false,
      this.state = const PresenceState(PresenceStatus.off)});
  final PresenceArea? self;
  final PresenceArea? partner;
  final int? distanceKm;
  final bool together;
  final PresenceState state;

  static const none = CoupleMapPresence();

  static CoupleMapPresence fromRows(List<Map<String, dynamic>> rows) {
    Map<String, dynamic>? selfRow;
    Map<String, dynamic>? partnerRow;
    for (final r in rows) {
      if (r['who'] == 'self') selfRow = r;
      if (r['who'] == 'partner') partnerRow = r;
    }
    if (selfRow == null) return none;
    final pausedRaw = selfRow['my_paused_until'] as String?;
    final paused = pausedRaw == null ? null : DateTime.tryParse(pausedRaw);
    return CoupleMapPresence(
      self: PresenceArea.fromRow(selfRow),
      partner: partnerRow == null ? null : PresenceArea.fromRow(partnerRow),
      distanceKm: (partnerRow?['distance_km'] as num?)?.toInt(),
      together: partnerRow?['together'] == true,
      state: paused != null
          ? PresenceState(PresenceStatus.paused, pausedUntil: paused)
          : const PresenceState(PresenceStatus.sharing),
    );
  }

  /// The distance card's data, or null when there's no honest answer.
  PartnerDistance? get partnerDistance {
    final p = partner;
    final km = distanceKm;
    if (p == null || km == null) return null;
    return PartnerDistance(
      km: km.toDouble(),
      partnerCity: p.city,
      partnerUtcOffsetMinutes: p.utcOffsetMinutes,
      together: together,
    );
  }
}
```

Changes to `partner_distance.dart`:
- Delete the `closing` enum value with its doc, and the `kmClosedSinceYesterday`, `partnerTimezone`, `partnerLocalTime`, `updatedAt` and `notableChangeKm` members.
- Set `togetherKm = 2.0`.
- Replace the class head and `tone` with:

```dart
@immutable
class PartnerDistance {
  const PartnerDistance({
    required this.km,
    this.partnerCity,
    this.partnerUtcOffsetMinutes,
    this.daysUntilTogether,
    this.together = false,
  });

  /// Rounded by the server (5 km under 50, 10 km above, never below 2).
  final double km;
  final String? partnerCity;

  /// Minutes ahead of UTC where they are; the clock is computed from it at
  /// display time so it never goes stale.
  final int? partnerUtcOffsetMinutes;
  final int? daysUntilTogether;

  /// Same or adjacent cell (server-computed).
  final bool together;

  /// Two cells' centres can be ~1–2 km apart for a couple in one place.
  static const togetherKm = 2.0;
  static const nearbyKm = 50.0;
  static const sameCountryKm = 800.0;

  DistanceTone get tone {
    if (together || km < togetherKm) return DistanceTone.together;
    if (km < nearbyKm) return DistanceTone.nearby;
    if (km < sameCountryKm) return DistanceTone.sameCountry;
    if (daysUntilTogether != null) return DistanceTone.countdown;
    return DistanceTone.distant;
  }
}
```

Changes to `distance_copy.dart`:
- The signature becomes `DistanceCopy distanceCopy(PartnerDistance d, {String? partnerName, DateTime? now})`.
- Delete the `closing` case.
- In `distant`, replace `final local = d.partnerLocalTime;` with:

```dart
      final offset = d.partnerUtcOffsetMinutes;
      final local = offset == null
          ? null
          : (now ?? DateTime.now()).toUtc().add(Duration(minutes: offset));
```

- [ ] **Step 4: Run and confirm they pass.** `flutter test test/features/location/couple_map_presence_test.dart test/features/location/distance_copy_test.dart`. Expected: all pass.
- [ ] **Step 5: Ledger.**

---

### Task 5: The gateway, sampler and repository

**Files:**
- Create: `lib/features/location/data/presence_gateway.dart`, `lib/features/location/data/presence_sampler.dart`
- Rewrite: `lib/features/location/data/presence_repository.dart`
- Test: `test/features/location/presence_repository_test.dart`

**Interfaces:**
- Consumes: `CoupleMapPresence.fromRows` (Task 4).
- Produces:
  - `abstract class PresenceGateway { Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}); }`
  - `class PresenceSample { final double lat, lng, accuracyM; final String? city, country, countryCode; }`
  - `abstract class PresenceSampler { Future<PresenceSample?> sample(); Future<bool> requestPermission(); }`
  - `PresenceRepository(PresenceGateway, PresenceSampler, Future<String> Function() timezone, {LocationService? placeService})` with `startSharing(rel) → Future<void>`, `record(rel) → Future<bool>`, `pause(rel, Duration? forHowLong) → Future<void>` (null = until resumed), `resume(rel)`, `stopSharing(rel)`, `fetchMapPresence(rel) → Future<CoupleMapPresence>`; `postPlaceUpdate` and `currentPlace` are unchanged.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/location/presence_repository_test.dart
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePresenceGateway implements PresenceGateway {
  FakePresenceGateway([Map<String, dynamic Function(Map<String, dynamic>)>? handlers])
      : handlers = handlers ?? {};
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    calls.add((fn, params ?? const {}));
    final h = handlers[fn];
    if (h == null) return null;
    return h(params ?? const {});
  }
}

class FakeSampler implements PresenceSampler {
  FakeSampler({this.next, this.grant = true});
  PresenceSample? next;
  bool grant;
  int asked = 0;
  int sampled = 0;
  @override
  Future<PresenceSample?> sample() async { sampled++; return next; }
  @override
  Future<bool> requestPermission() async { asked++; return grant; }
}

const _accra = PresenceSample(lat: 5.5603, lng: -0.2057, accuracyM: 40, city: 'Accra', country: 'Ghana', countryCode: 'GH');

PresenceRepository _repo(FakePresenceGateway g, FakeSampler s) =>
    PresenceRepository(g, s, () async => 'Africa/Accra');

void main() {
  test('start opts in, asks for permission once, then records', () async {
    final g = FakePresenceGateway();
    final s = FakeSampler(next: _accra);
    await _repo(g, s).startSharing('r1');
    expect(g.calls.map((c) => c.$1), ['start_presence', 'record_presence']);
    expect(s.asked, 1);
    final rec = g.calls.last.$2;
    expect(rec['p_relationship_id'], 'r1');
    expect(rec['p_accuracy_m'], 40);
    expect(rec['p_timezone'], 'Africa/Accra');
  });

  test('no fix (permission off, timeout): nothing recorded, no error', () async {
    final g = FakePresenceGateway();
    final ok = await _repo(g, FakeSampler(next: null)).record('r1');
    expect(ok, isFalse);
    expect(g.calls, isEmpty);
  });

  test('pause sends a bounded end, or infinity until resumed; resume sends null', () async {
    final g = FakePresenceGateway();
    final r = _repo(g, FakeSampler());
    await r.pause('r1', const Duration(hours: 1));
    await r.pause('r1', null);
    await r.resume('r1');
    expect(DateTime.parse(g.calls[0].$2['p_until'] as String).isAfter(DateTime.now().toUtc()), isTrue);
    expect(g.calls[1].$2['p_until'], 'infinity');
    expect(g.calls[2].$2['p_until'], isNull);
  });

  test('stop calls stop_presence (deletes, silently)', () async {
    final g = FakePresenceGateway();
    await _repo(g, FakeSampler()).stopSharing('r1');
    expect(g.calls.single.$1, 'stop_presence');
  });

  test('fetchMapPresence maps rows; a failure reads as nothing', () async {
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => [
            {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.205, 'city': 'Accra', 'freshness': 'fresh'},
          ],
    });
    final p = await _repo(g, FakeSampler()).fetchMapPresence('r1');
    expect(p.state.status, PresenceStatus.sharing);
    g.handlers['couple_map_presence'] = (_) => throw Exception('offline');
    expect((await _repo(g, FakeSampler()).fetchMapPresence('r1')).state.status, PresenceStatus.off);
  });

  test('a failed record never logs coordinates or the city (checklist 4.4)', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    addTearDown(() => debugPrint = original);
    final g = FakePresenceGateway({'record_presence': (_) => throw Exception('lat 5.5603 Accra')});
    await _repo(g, FakeSampler(next: _accra)).record('r1');
    expect(logs, isNotEmpty);
    for (final l in logs) {
      expect(l.contains('5.56'), isFalse);
      expect(l.contains('Accra'), isFalse);
    }
  });
}
```

- [ ] **Step 2: Run and confirm they fail** (compilation error: the files don't exist).

- [ ] **Step 3: Implement**

```dart
// lib/features/location/data/presence_gateway.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// The presence RPC seam (tests use a fake; mirrors PlanningRpcGateway).
abstract class PresenceGateway {
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params});
}

class SupabasePresenceGateway implements PresenceGateway {
  SupabasePresenceGateway(this._supabase);
  final SupabaseClient _supabase;
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) =>
      _supabase.rpc(fn, params: params);
}
```

```dart
// lib/features/location/data/presence_sampler.dart
import 'package:attune/features/location/domain/presence_config.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

@immutable
class PresenceSample {
  const PresenceSample({required this.lat, required this.lng, required this.accuracyM,
      this.city, this.country, this.countryCode});
  final double lat;
  final double lng;
  final double accuracyM;
  final String? city;
  final String? country;
  final String? countryCode;
}

/// Where the device roughly is, for ambient presence.
abstract class PresenceSampler {
  /// A low-accuracy fix plus an on-device place name, or null. Never asks
  /// for permission and never throws: presence is ambient.
  Future<PresenceSample?> sample();

  /// Asks for permission. Called only from an explicit opt-in tap.
  Future<bool> requestPermission();
}

class GeolocatorPresenceSampler implements PresenceSampler {
  @override
  Future<PresenceSample?> sample() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }
      // Low accuracy: enough for a ~1 km cell, and iOS never asks for Precise.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: PresenceConfig.fixTimeout,
        ),
      );
      String? city;
      String? country;
      String? code;
      try {
        // On-device geocoding: coordinates never go to a third-party HTTP API.
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(PresenceConfig.geocodeTimeout);
        final m = marks.isEmpty ? null : marks.first;
        city = m?.locality?.isNotEmpty == true ? m!.locality : m?.subAdministrativeArea;
        country = m?.country;
        code = m?.isoCountryCode;
      } catch (_) {}
      return PresenceSample(lat: pos.latitude, lng: pos.longitude,
          accuracyM: pos.accuracy, city: city, country: country, countryCode: code);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.whileInUse || p == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }
}
```

The new `presence_repository.dart` (`postPlaceUpdate` and `currentPlace` keep their behaviour, now through the gateway and `LocationService`):

```dart
// lib/features/location/data/presence_repository.dart
import 'dart:async';

import 'package:attune/core/services/location_service.dart';
import 'package:attune/core/utils/location/models/parsed_address.dart';
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/foundation.dart';

/// Ambient presence for one couple, through the presence RPCs only.
///
/// The client writes its own (server-snapped) area and reads at most the
/// partner's cell — never a raw position, never a time. Nothing here logs a
/// coordinate or a place name (checklist 4.4).
class PresenceRepository {
  PresenceRepository(this._gateway, this._sampler, this._timezone, {LocationService? placeService})
      : _placeService = placeService ?? LocationService();

  final PresenceGateway _gateway;
  final PresenceSampler _sampler;
  final Future<String> Function() _timezone;
  final LocationService _placeService;

  void _log(String what, Object e) => debugPrint('presence: $what failed (${e.runtimeType})');

  /// Opting in: create the row, ask for permission once, then record.
  Future<void> startSharing(String relationshipId) async {
    await _gateway.rpc('start_presence', params: {'p_relationship_id': relationshipId});
    await _sampler.requestPermission();
    await record(relationshipId);
  }

  /// Records my area if I can get a fix; false otherwise. Never throws.
  Future<bool> record(String relationshipId) async {
    final s = await _sampler.sample();
    if (s == null) return false;
    try {
      await _gateway.rpc('record_presence', params: {
        'p_relationship_id': relationshipId,
        'p_lat': s.lat,
        'p_lng': s.lng,
        'p_accuracy_m': s.accuracyM,
        'p_city': s.city,
        'p_country': s.country,
        'p_country_code': s.countryCode,
        'p_timezone': await _timezone(),
      });
      return true;
    } catch (e) {
      _log('record', e);
      return false;
    }
  }

  /// Pauses for [forHowLong], or until resumed when null.
  Future<void> pause(String relationshipId, Duration? forHowLong) =>
      _gateway.rpc('set_presence_pause', params: {
        'p_relationship_id': relationshipId,
        'p_until': forHowLong == null
            ? 'infinity'
            : DateTime.now().toUtc().add(forHowLong).toIso8601String(),
      });

  Future<void> resume(String relationshipId) => _gateway.rpc('set_presence_pause',
      params: {'p_relationship_id': relationshipId, 'p_until': null});

  /// Turning it off deletes the row; the partner is not told.
  Future<void> stopSharing(String relationshipId) =>
      _gateway.rpc('stop_presence', params: {'p_relationship_id': relationshipId});

  /// What the couple map may show; on any failure, nothing.
  Future<CoupleMapPresence> fetchMapPresence(String relationshipId) async {
    try {
      final rows = await _gateway.rpc('couple_map_presence',
          params: {'p_relationship_id': relationshipId});
      if (rows is! List) return CoupleMapPresence.none;
      return CoupleMapPresence.fromRows(
          [for (final r in rows) Map<String, dynamic>.from(r as Map)]);
    } catch (e) {
      _log('read', e);
      return CoupleMapPresence.none;
    }
  }

  /// Shares where you are, right now, on purpose (full precision: chosen).
  Future<bool> postPlaceUpdate({
    required String relationshipId,
    required String label,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? country,
  }) async {
    try {
      await _gateway.rpc('post_place_update', params: {
        'p_relationship_id': relationshipId,
        'p_label': label,
        'p_note': note,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_city': city,
        'p_country': country,
      });
      return true;
    } catch (e) {
      _log('place update', e);
      return false;
    }
  }

  /// Where the user is now, for pre-filling a place update.
  Future<ParsedAddress?> currentPlace() async {
    try {
      return await _placeService.getCurrentLocationWithDetails().timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }
}
```

- [ ] **Step 4: Run and confirm they pass.** `flutter test test/features/location/presence_repository_test.dart`. Expected: all pass.
- [ ] **Step 5: Ledger.**

---

### Task 6: Providers, the feature flag, and the chat settings toggle

**Files:**
- Rewrite: `lib/features/location/presentation/providers/presence_providers.dart`
- Modify: `lib/features/chat/presentation/widgets/chat_settings_static_rows.dart:30-80`
- Test: `test/features/location/presence_providers_test.dart`, `test/features/chat/chat_settings_location_toggle_test.dart`

**Interfaces:**
- Consumes: Tasks 4 and 5.
- Produces:
  - `presenceGatewayProvider`, `presenceSamplerProvider`, `presenceTimezoneProvider`, `presenceRepositoryProvider`
  - `coupleMapPresenceProvider` (`StreamProvider.autoDispose.family<CoupleMapPresence, String>`)
  - `presenceStateProvider` (`Provider.autoDispose.family<AsyncValue<PresenceState>, String>`)
  - `partnerDistanceProvider` (`StreamProvider.autoDispose.family<PartnerDistance?, String>`)
  - `coupleMapEnabledProvider` (`FutureProvider<bool>`)

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/location/presence_providers_test.dart
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

const _accra = PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40, city: 'Accra');

ProviderContainer _container(FakePresenceGateway g, FakeSampler s) {
  final c = ProviderContainer(overrides: [
    presenceGatewayProvider.overrideWithValue(g),
    presenceSamplerProvider.overrideWithValue(s),
    presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('not sharing: never samples and never asks for permission', () async {
    final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    final p = await c.read(coupleMapPresenceProvider('r1').future);
    expect(p.state.status, PresenceStatus.off);
    expect(s.sampled, 0);
    expect(s.asked, 0);
    expect(g.calls.where((x) => x.$1 == 'record_presence'), isEmpty);
  });

  test('sharing: samples once on open, records, then reads the fresh state', () async {
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => const [{'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.205, 'freshness': 'fresh'}],
    });
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    await c.read(coupleMapPresenceProvider('r1').future);
    expect(s.sampled, 1);
    expect(g.calls.map((x) => x.$1), ['couple_map_presence', 'record_presence', 'couple_map_presence']);
  });

  test('paused: no sampling', () async {
    final g = FakePresenceGateway({
      'couple_map_presence': (_) => const [{'who': 'self', 'freshness': 'fresh', 'my_paused_until': '2099-01-01T00:00:00Z'}],
    });
    final s = FakeSampler(next: _accra);
    final c = _container(g, s);
    final state = (await c.read(coupleMapPresenceProvider('r1').future)).state;
    expect(state.status, PresenceStatus.paused);
    expect(s.sampled, 0);
  });
}
```

```dart
// test/features/chat/chat_settings_location_toggle_test.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/providers/chat_experience_providers.dart';
import 'package:attune/features/chat/presentation/widgets/chat_settings_static_rows.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart' show FakePresenceGateway, FakeSampler;

Conversation _conversation() => Conversation(
      id: 'c1',
      relationshipId: 'r1',
      partnerId: 'p1',
      name: 'Partner',
      updatedAt: DateTime.utc(2026, 10, 1),
      relationshipStatus: 'active',
      availability: ConversationAvailability.active,
      unreadCount: 0,
    );

Future<(FakePresenceGateway, FakeSampler)> _pump(WidgetTester t, Conversation? c) async {
  final g = FakePresenceGateway({'couple_map_presence': (_) => const []});
  final s = FakeSampler(next: const PresenceSample(lat: 5.56, lng: -0.2, accuracyM: 40));
  await t.pumpWidget(ProviderScope(
    overrides: [
      presenceGatewayProvider.overrideWithValue(g),
      presenceSamplerProvider.overrideWithValue(s),
      presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
      chatHistoricalImportEnabledProvider.overrideWith((ref) async => false),
    ],
    child: ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ChatSettingsStaticRows(conversation: c))),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return (g, s);
}

InfoRowWidget _toggle(WidgetTester t) =>
    t.widget<InfoRowWidget>(find.widgetWithText(InfoRowWidget, 'Share my location'));

void main() {
  testWidgets('reads off when nothing is shared', (t) async {
    await _pump(t, _conversation());
    expect(_toggle(t).toggleValue, isFalse);
  });

  testWidgets('on: opts in, asks once, records; off: deletes', (t) async {
    final (g, s) = await _pump(t, _conversation());
    await _toggle(t).onToggleChanged!(true);
    await t.pumpAndSettle();
    expect(g.calls.map((c) => c.$1), containsAllInOrder(['start_presence', 'record_presence']));
    expect(s.asked, 1);
    await _toggle(t).onToggleChanged!(false);
    await t.pumpAndSettle();
    expect(g.calls.map((c) => c.$1), contains('stop_presence'));
  });

  testWidgets('with no conversation the toggle is disabled and calls nothing', (t) async {
    final (g, _) = await _pump(t, null);
    expect(_toggle(t).onToggleChanged, isNull);
    expect(g.calls.where((c) => c.$1 != 'couple_map_presence'), isEmpty);
  });
}
```


- [ ] **Step 2: Run and confirm they fail** (the providers don't exist).

- [ ] **Step 3: Implement the providers**

```dart
// lib/features/location/presentation/providers/presence_providers.dart
import 'dart:async';

import 'package:attune/core/utils/timezone_utils.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/domain/presence_config.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final presenceGatewayProvider = Provider<PresenceGateway>(
    (ref) => SupabasePresenceGateway(ref.watch(supabaseClientProvider)));
final presenceSamplerProvider = Provider<PresenceSampler>((ref) => GeolocatorPresenceSampler());
final presenceTimezoneProvider =
    Provider<Future<String> Function()>((ref) => TimezoneUtils.getDeviceTimezone);

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) => PresenceRepository(
      ref.watch(presenceGatewayProvider),
      ref.watch(presenceSamplerProvider),
      ref.watch(presenceTimezoneProvider),
    ));

/// The couple map's presence, refreshed on open, on app resume and every
/// 15 minutes. Samples ONLY while I'm sharing and not paused: someone who
/// never opted in is never sampled or prompted.
final coupleMapPresenceProvider = StreamProvider.autoDispose
    .family<CoupleMapPresence, String>((ref, relationshipId) {
  final repo = ref.watch(presenceRepositoryProvider);
  final controller = StreamController<CoupleMapPresence>();
  var closed = false;
  var running = false;

  Future<void> refresh() async {
    if (closed || running) return;
    running = true;
    try {
      var p = await repo.fetchMapPresence(relationshipId);
      if (!closed && p.state.status == PresenceStatus.sharing && await repo.record(relationshipId)) {
        p = await repo.fetchMapPresence(relationshipId);
      }
      if (!closed && !controller.isClosed) controller.add(p);
    } finally {
      running = false;
    }
  }

  unawaited(refresh());
  final timer = Timer.periodic(PresenceConfig.refreshEvery, (_) => refresh());
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
  ref.onDispose(() {
    closed = true;
    timer.cancel();
    lifecycle.dispose();
    unawaited(controller.close());
  });
  return controller.stream;
});

/// My sharing state for one couple (off / sharing / paused until).
final presenceStateProvider = Provider.autoDispose
    .family<AsyncValue<PresenceState>, String>((ref, relationshipId) =>
        ref.watch(coupleMapPresenceProvider(relationshipId)).whenData((p) => p.state));

/// The distance card's data (null when there's no honest answer).
final partnerDistanceProvider = StreamProvider.autoDispose
    .family<PartnerDistance?, String>((ref, relationshipId) async* {
  final p = await ref.watch(coupleMapPresenceProvider(relationshipId).future);
  yield p.partnerDistance;
});

/// The couple map ships dark until this flag is on (spec §9, rollback).
final coupleMapEnabledProvider = FutureProvider<bool>((ref) => ChatFeatureFlags.isEnabled(
      ref.watch(supabaseClientProvider),
      'couple_map_enabled',
    ));
```

Changes to `chat_settings_static_rows.dart`:
- Replace the `isSharingLocation` line with:

```dart
    final relationshipId = conversation?.relationshipId;
    // A privacy toggle never shows "on" for a state it hasn't confirmed.
    final isSharingLocation = relationshipId == null
        ? false
        : ref.watch(presenceStateProvider(relationshipId)).valueOrNull?.isOn ?? false;
```

- Replace `onToggleChanged` with:

```dart
                  onToggleChanged: relationshipId == null
                      ? null
                      : (value) async {
                          final repository = ref.read(presenceRepositoryProvider);
                          if (value) {
                            await repository.startSharing(relationshipId);
                          } else {
                            await repository.stopSharing(relationshipId);
                          }
                          ref.invalidate(coupleMapPresenceProvider(relationshipId));
                        },
```

- Change the subtitle to `'Shares your neighbourhood, never your address.'`.

- [ ] **Step 4: Run and confirm they pass.** `flutter test test/features/location/presence_providers_test.dart test/features/chat/chat_settings_location_toggle_test.dart`.
- [ ] **Step 5: Ledger.**

---

### Task 7: The remaining callers: distance row, dual clock, test harness, wiring tests

**Files:**
- Modify: `lib/features/location/presentation/widgets/partner_distance_row.dart`, `lib/features/planning/presentation/widgets/dual_clock_block_view.dart`, `test/features/planning/support/planning_test_app.dart`, `test/features/planning/planning_couple_blocks_screen_test.dart`, `test/features/location/location_wiring_test.dart`

**Interfaces:**
- Consumes: `presenceStateProvider`, `partnerDistanceProvider`, `PresenceRepository.startSharing`, `PartnerDistance.partnerUtcOffsetMinutes`.

- [ ] **Step 1: Update the tests first**

`planning_couple_blocks_screen_test.dart` (the dual clock test):

```dart
  testWidgets('dual clock shows the partner\'s city and time when they share, a hint when not', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'dc', type: 'dual_clock', payload: {'title': 'Our time'})]),
    });
    await tester.pumpWidget(_app(g, _screen,
        partner: const PartnerDistance(km: 12000, partnerCity: 'Makassar', partnerUtcOffsetMinutes: 480)));
    await tester.pumpAndSettle();
    expect(find.text('Makassar'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    // The offset now comes with presence: no separate time-zone lookup.
    expect(g.callsTo('planning_timezone_offset_minutes'), isEmpty);
  });
```

`location_wiring_test.dart`:
- Keep the tests "Location attach entry", "renders nothing when there is no honest answer", "toggle reflects real state" and "place photo through the EXIF pipeline" unchanged.
- Replace the rest with:

```dart
  test('stopping deletes through stop_presence', () {
    final source = File('lib/features/location/data/presence_repository.dart').readAsStringSync();
    expect(source.contains("'stop_presence'"), isTrue);
  });

  test('the client reads presence only through couple_map_presence', () {
    final source = File('lib/features/location/data/presence_repository.dart').readAsStringSync();
    expect(source.contains("'couple_map_presence'"), isTrue);
    expect(source.contains("from('partner_presence')"), isFalse,
        reason: 'no direct table access: the RPCs enforce snapping, pause and symmetry');
  });

  test('turning sharing off reaches stopSharing(relationshipId)', () {
    final source = File('lib/features/chat/presentation/widgets/chat_settings_static_rows.dart').readAsStringSync();
    expect(source.contains('repository.stopSharing(relationshipId)'), isTrue);
  });

  test('the sampler is time-bounded and low accuracy', () {
    final source = File('lib/features/location/data/presence_sampler.dart').readAsStringSync();
    expect(source.contains('LocationAccuracy.low'), isTrue);
    expect(source.contains('timeLimit:'), isTrue);
    expect(source.contains('.timeout('), isTrue);
  });

  test('the sampler never asks for permission on its own', () {
    final source = File('lib/features/location/data/presence_sampler.dart').readAsStringSync();
    final sample = source.substring(source.indexOf('Future<PresenceSample?> sample()'),
        source.indexOf('Future<bool> requestPermission()'));
    expect(sample.contains('requestPermission'), isFalse);
  });

  test('a partner who has not shared produces silence, not a prompt', () {
    final source = File('lib/features/location/presentation/widgets/partner_distance_row.dart').readAsStringSync();
    for (final nudge in ['Waiting for', 'has not shared', "hasn't shared", 'Ask ', 'Invite ']) {
      expect(source.contains(nudge), isFalse, reason: nudge);
    }
  });
```

- [ ] **Step 2: Run and confirm they fail.** `flutter test test/features/location/ test/features/planning/planning_couple_blocks_screen_test.dart`.

- [ ] **Step 3: Implement**

`planning_test_app.dart`: the override line stays as written, `partnerDistanceProvider.overrideWith((ref, relationshipId) => Stream.value(partner))`. It still compiles because the provider type is unchanged.

`dual_clock_block_view.dart` `build`:

```dart
    final partner = ref.watch(partnerDistanceProvider(widget.args.relationshipId)).valueOrNull;
    final offset = partner?.partnerUtcOffsetMinutes;
```

Also remove the `planningTimezoneOffsetProvider` line and the import it needs, if that import is now unused.

`partner_distance_row.dart`:
- The sharing read becomes:

```dart
      final sharing = ref.watch(presenceStateProvider(relationshipId)).valueOrNull?.isOn ?? true;
```

- `onTap` becomes:

```dart
        onTap: () async {
          await ref.read(presenceRepositoryProvider).startSharing(relationshipId);
          ref.invalidate(coupleMapPresenceProvider(relationshipId));
        },
```

- In `_withReunion`, rebuild the object as:

```dart
    return PartnerDistance(
      km: distance.km,
      partnerCity: distance.partnerCity,
      partnerUtcOffsetMinutes: distance.partnerUtcOffsetMinutes,
      daysUntilTogether: soonest,
      together: distance.together,
    );
```

- In `_iconFor`, delete the `DistanceTone.closing` arm.

- [ ] **Step 4: Run and confirm they pass,** together with a full analyze. Run `flutter test test/features/location/ test/features/planning/ test/features/chat/`, then `flutter analyze lib test 2>&1 | grep -E "^\s*(error|warning) " | grep -E "location|presence|dual_clock|chat_settings|planning_test_app"`. Expected: tests pass and grep prints nothing.
- [ ] **Step 5: Ledger.**

---

### Task 8: EXIF and GPS stripped in the Dart fallback paths

**Files:**
- Modify: `lib/features/stories/domain/services/capture_image_preparer.dart` (fallback, about line 163), `lib/features/chat/domain/services/chat_image_preparer.dart` (fallback, about line 134)
- Test: `test/features/stories/capture_image_preparer_exif_test.dart`, `test/features/chat/chat_image_preparer_exif_test.dart`

- [ ] **Step 1: Write the failing tests.** The chat test is identical except for the class: `ChatImagePreparer()` with `.file`.

```dart
// test/features/stories/capture_image_preparer_exif_test.dart
import 'dart:io';

import 'package:attune/features/stories/domain/services/capture_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the Dart fallback strips GPS EXIF (no platform compressor in tests)', () async {
    final src = img.Image(width: 64, height: 48);
    src.exif.gpsIfd[0x0001] = 'N'; // GPSLatitudeRef
    src.exif.gpsIfd[0x0003] = 'W'; // GPSLongitudeRef
    final jpeg = img.encodeJpg(src);
    // The fixture really carries GPS, or the test proves nothing.
    expect(img.decodeJpg(jpeg)!.exif.gpsIfd.isEmpty, isFalse);

    final dir = await Directory.systemTemp.createTemp('exif');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/gps.jpg')..writeAsBytesSync(jpeg);

    final out = await const CaptureImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect(decoded.exif.gpsIfd.isEmpty, isTrue, reason: 'GPS must never survive preparation');
  });
}
```

- [ ] **Step 2: Run and confirm they fail.** `flutter test test/features/stories/capture_image_preparer_exif_test.dart test/features/chat/chat_image_preparer_exif_test.dart`. Expected: FAIL on "GPS must never survive preparation". If `path_provider` throws in the test host, override `_tempTargetPath` through the test the same way `streak_camera_photo_test.dart` does, and note it in the ledger.

- [ ] **Step 3: Implement.** In both files, right after `final resized = _resizeLongestEdge(...)`:

```dart
    // The native path drops EXIF (keepExif:false); the pure-Dart encoder
    // would copy it — including GPS — so it's cleared here too.
    resized.exif = img.ExifData();
```

- [ ] **Step 4: Run and confirm they pass.** Also run `flutter test test/features/stories/ test/features/chat/chat_image_preparer_test.dart`, which should still pass.
- [ ] **Step 5: Ledger.**

---

### Task 9: Mapbox build spike (no UI)

**Files:**
- Modify: `lib/main.dart` (bootstrap), `ios/Runner/AppDelegate.swift`, and `android/app/src/main/kotlin/**/MainActivity.kt` (telemetry off)
- Ledger: the results

- [ ] **Step 1: Write a test that bootstrap sets the token only when present**

```dart
// test/core/mapbox_bootstrap_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mapbox is configured at bootstrap from Environment, never hard-coded', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('MapboxOptions.setAccessToken(Environment.mapboxAccessToken)'), isTrue);
    expect(RegExp(r"setAccessToken\('pk\.").hasMatch(main), isFalse, reason: 'no hard-coded token (checklist 2.7)');
  });
}
```

- [ ] **Step 2: Run it and confirm it fails.**

- [ ] **Step 3: Implement.** In `main()`, after `WidgetsFlutterBinding.ensureInitialized()`:

```dart
  // The couple map (spec 2026-10-16 §6.3). Token from the environment,
  // restricted to the app's bundle IDs in the Mapbox console.
  if (Environment.mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(Environment.mapboxAccessToken);
  }
```

Add `import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';` and the `Environment` import if it's missing.

- [ ] **Step 4: Turn telemetry off natively.** The Dart plugin has no switch for it.
  - Find the Mapbox Common telemetry API that ships with the resolved native SDK:
    - iOS: `grep -rn "setEventsCollectionState\|TelemetryUtils" ios/Pods/MapboxCommon` after `pod install`.
    - Android: the Gradle cache for `com.mapbox.common`.
  - Call it once at startup: `TelemetryUtils.setEventsCollectionState(false)` in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, and `TelemetryUtils.setEventsCollectionState(false, null)` in `MainActivity.onCreate`.
  - If no supported API exists in this SDK version, don't guess. Write the ledger line `Ruling: telemetry API not found in SDK <version> — Phase 1 blocker for owner decision` and stop this step.

- [ ] **Step 5: Build both platforms.**
  - Run `flutter build apk --debug` and `flutter build ios --debug --no-codesign`. Expected: both succeed.
  - Record in the ledger whether a `MAPBOX_DOWNLOADS_TOKEN` or secret token was needed. If one was, document it in `README.md` under the existing setup section.
- [ ] **Step 6: Run the test from Step 1 and confirm it passes. Write the ledger line.**

---

## Final verification (Phase 0 exit)

1. **All contracts.** Run `bash $SCRATCH/pg/run5.sh` over `couple_map_presence_contracts.sql`, `location_presence_test.sql`, and every `together_*` and `reminder_*` contract. Every result must be PASS.
2. **Full test suite.** Run `flutter test` and redirect the output to the ledger directory. It must be green, and any flaky test is rerun three times on its own and named.
3. **Analyzer.** Run `flutter analyze lib 2>&1 | grep -E "^\s*(error|warning) "`. Touched files must have zero findings.
4. **Coverage (checklist 6.7).**
   - Run `flutter test --coverage test/features/location`, then `lcov --summary coverage/lcov.info`.
   - Targets: domain ≥ 90%, repository ≥ 70%.
   - Record the numbers in the ledger.
5. **Fable review.** A fresh Fable reviewer checks the whole Phase 0 diff against spec §4, §5.1 and §9. Then one fix pass: each fix gets a test that fails first.
6. **Deploy note for the owner.**
   - `supabase db push` applies `20261016100000_presence_v2.sql`. Existing presence rows are dropped and users opt in again.
   - The `couple_map_enabled` flag stays off.

## Checklist v3.1 evidence map (spec §9)

| Item | Where it's proven |
|---|---|
| 1.4 / 1.5 Authorization and authentication | C4, C10, and C11 (outsider, anon, archived) |
| 2.1 Input sanitisation | C9 |
| 2.4 / 5.5 Errors don't leak | Repository returns `none` or `false`; there are no raw errors in the UI (Task 5 test) |
| 2.5 Per-request resource limits | At most 2 rows returned |
| 2.7–2.9 Secrets | Task 9 test (token from `Environment`) |
| 2.10 Resources released | Provider disposes its timer, lifecycle listener and stream (`ref.onDispose`) |
| 4.4 No PII in logs | Task 5 log test |
| 1.1 / 2.18 Idempotency | `start` uses DO NOTHING; `record` is an upsert-style update; `stop` and `pause` are idempotent (C4 and C7 rerun) |
| 1.2 Timeouts | Sampler 20 s fix and 10 s geocode (Task 7 wiring test) |
| 1.6 / 2.16 Concurrency | `FOR UPDATE` in `record`; separate rows per partner |
| 1.11 Privacy and retention | C12; drop on archive (C11) |
| 3.3 Indexes | Task 3 Step 7 (EXPLAIN) |
| 3.8 Rate limit | C10 |
| 4.11 Configuration | `presence_config()` and `PresenceConfig` |
| 6.1 / 6.4 Edge cases and negative tests | C2 (poles), C3 (jitter), C7 (resume), C8 (pause too long, stale), C9 |
| 6.7 Coverage | Final verification step 4 |
| 8.1 Rollback | `couple_map_enabled` stays off; the migration is replaceable by a follow-up |
