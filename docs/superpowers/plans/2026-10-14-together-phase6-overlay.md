# Together Phase 6: Busy Overlay and Free-Time Finder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each partner can opt in to lend only *when* they're busy from their phone calendar. Together then shows when you're both free, and one tap turns a free window into a date proposal. A second, owner-set level also shows the partner your busy times.

**Architecture:**
- **Phone side:** the phone reads its own calendars through `device_calendar_plus`. It keeps only start and end times, rounds them outward to 30 minutes, and uploads at most 14 days ahead into `couple_busy_blocks`.
- **Server side:**
  - The mutual-free finder runs on the server (`list_together_free_windows`). It intersects both partners' free time within each partner's waking hours in their own zone, and removes Together events using the app's own visibility rules (`together_items_for`).
  - A partner's raw busy blocks therefore never reach the other phone, unless their owner chose the strips level (`list_together_busy_strips`).
  - Turning the overlay off deletes the user's blocks in the same call. A daily cron purges past blocks, and ending the relationship purges everything.
- **Hub:** "Both free" rows in Today, a "Free together" section for the week ahead, and a free window that opens the event editor in propose mode.

**Tech Stack:** Flutter 3.29, Riverpod 2, Supabase Postgres 17 (plpgsql, pg_cron), `device_calendar_plus ^0.8.1`.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (D5, §3.3 overlay safety, §3.6 private events in the finder, §3.8 unlink purges busy blocks, §4.1 Today chip and This week windows, §5.3 `couple_busy_blocks` and the `together_member_prefs` overlay level, §6.4 busy overlay and finder, §7.2 and §7.5 scenarios, §8 Phase 6 row).

## Global Constraints

- Opt-in for each partner; the finder needs both partners opted in (§3.3).
- Busy-only: no titles, locations or attendees leave the device (§3.3).
- Times rounded to 30 minutes, covering a rolling 14 days, with past blocks purged daily (§3.3).
- Revoking deletes the user's rows on the server in the same call and sends the partner nothing (§3.3).
- Overlay default is free windows only. Seeing the other partner's busy strips needs a second toggle, set by the person whose blocks they are (D5).
- Private events are the creator's alone. Only the creator's own finder counts them as busy (§3.6).
- `end-relationship` purges busy blocks (§3.8).
- The finder returns windows of at least 60 minutes, within each partner's waking hours in their own zone, with Together events removed (§6.4).
- The app never nags a partner to turn the overlay on (§7.1). Copy never says whether the partner has turned it on.
- OS keys: iOS 17+ `NSCalendarsFullAccessUsageDescription` (keep `NSCalendarsUsageDescription` for older iOS); Android `READ_CALENDAR` (§6.4).
- Together RPC errors are `together:<code>`. SECURITY DEFINER functions pin `search_path = public` and check membership through `together_actor`.
- Owner rules:
  - work on `main`;
  - write each test first and watch it fail;
  - commit nothing unless asked;
  - re-read a file before editing it;
  - make surgical changes;
  - no overflow at 320pt.

### Rulings this plan makes (record them in spec §8.9 in Task 6)

- **R1: The finder runs on the server.**
  - §6.4 asks for a pure Dart finder. But computing free windows on the partner's phone would need the partner's raw busy blocks on that phone, so a modified app could draw them as strips. That breaks D5's "free windows only" default.
  - The server version keeps D5 enforceable. It's pinned by contracts across zones and a clock change, plus pure Dart tests for the device-side rounding.
  - Cost if wrong: moving the finder later means shipping blocks to clients.
- **R2: Waking hours are 08:00–22:00 in each partner's own zone**, the zone Planning and Together already store, defaulting to UTC. Windows are made of 30-minute slots on the UTC grid; a slot counts when both partners' local start times fall between 08:00 and 21:30. Cost if wrong: a later per-person waking-hours setting.
- **R3: What counts as busy.**
  - Busy: both partners' uploaded blocks, and every confirmed timed Together event the finder's viewer can see (including their own private events, never the partner's).
  - All-day events count only when they're trips (a whole day away).
  - Not busy: an all-day "Pay rent", birthdays, reminders and Planning dates.
- **R4: Reading the phone calendar.** These are skipped: all-day entries, entries marked "free", and cancelled ones. Times are rounded outward to 30 minutes, then overlaps are merged.
  - Upload happens when the overlay is turned on, and once per visit to Together while it's on.
  - Busy uploads don't ping the partner's realtime signal, so the partner can't tell when someone opens the app.
- **R5: Levels are `off`, `free_windows` and `strips`, default `off`.** These are the spec's three values.
  - `strips` means your partner sees *your* busy times, but only while they've opted in too.
  - Nobody is told the other's level.
- **R6: Where it shows.**
  - Today: today's "Both free" windows (up to 2), each with the partner's local time when it differs, plus a muted "Kofi is busy …" line at the strips level.
  - A "Free together" section: the next windows over the coming 6 days, up to 5.
  - Tapping a window opens the event editor in propose mode, prefilled with that time.
  - Month-view hatching and fitting rituals into free time wait for a later phase.
- **R7: Android minSdk becomes 24**, set explicitly in `build.gradle.kts`. `device_calendar_plus` requires it. The app currently inherits Flutter's default of 21 while `record_android` already declares 23. Cost if wrong: Android 7.0 (API 24) becomes the floor.

## Review Focus

1. **The partner's raw busy blocks, at the free-windows level, must not reach my phone through any RPC.** Pinned in the Task 1 contract.
2. **A couple 5 hours apart (London and Toronto) gets windows only inside both partners' waking hours, including across Toronto's clock change on 1 November.** Pinned in the Task 1 contract.
3. **A partner's private event doesn't shrink my windows, but mine shrinks my own.** Pinned in the Task 1 contract.
4. **Turning off deletes my rows in the same call, and ending the relationship deletes both partners' rows.** Pinned in the Task 1 contract.
5. **Denying calendar permission leaves the overlay off and says how to turn access on.** It doesn't silently show an "on" state with nothing uploaded. Pinned in the Task 4 test.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/20261014170000_together_busy_overlay.sql` | Create | Level column, blocks table, overlay/upload/finder/strips RPCs, purge cron, unlink purge |
| `supabase/tests/together_overlay_contracts.sql` | Create | Contracts |
| `lib/features/together/domain/together_overlay.dart` | Create | `OverlayLevel`, `FreeWindow`, `BusyStrip`, `DeviceBusy`, `busyBlocksFrom` |
| `lib/features/together/data/device_busy_source.dart` | Create | `DeviceBusySource` + `DeviceCalendarPlusSource` |
| `lib/features/together/data/together_repository.dart` | Modify | Overlay RPCs |
| `lib/features/together/presentation/together_providers.dart` | Modify | Overlay, windows, strips, source providers; `syncBusyTimes` |
| `lib/features/together/presentation/widgets/together_settings_sheet.dart` | Modify | "Free time together" section |
| `lib/features/together/presentation/widgets/couple_event_sheet.dart` | Modify | `proposeWindow` parameter |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | Today rows, strips line, "Free together" section, per-visit sync |
| `pubspec.yaml`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts` | Modify | Package, keys, permission, minSdk 24 |
| `docs/superpowers/specs/2026-10-14-together-hub-design.md` | Modify | §8.9 |

Harness:
- **Contracts:** `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`. Start PG first with `pg_ctl -D <scratchpad>/pg/data -o "-p 55432 -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" start`.

---

### Task 1: The overlay on the server

**Files:**
- Create: `supabase/migrations/20261014170000_together_busy_overlay.sql`
- Test: `supabase/tests/together_overlay_contracts.sql`

**Interfaces:**
- Produces (all executable by `authenticated`):
  - `get_together_overlay(p_relationship_id uuid) RETURNS jsonb`, returning `{"level": "off"|"free_windows"|"strips"}`.
  - `set_together_overlay(p_relationship_id uuid, p_level text) RETURNS jsonb`. Turning it `off` deletes my blocks.
  - `replace_my_busy_blocks(p_relationship_id uuid, p_blocks jsonb) RETURNS int`. `p_blocks` is a JSON array of `{starts_at, ends_at}` objects; the result is the number of blocks stored. It fails with `together:invalid_input` while my level is `off`, or with more than 300 blocks.
  - `list_together_free_windows(p_relationship_id uuid, p_now timestamptz DEFAULT now())` returns `TABLE (starts_at timestamptz, ends_at timestamptz, partner_from text, partner_to text, partner_differs boolean)`. It's empty unless both partners' levels aren't `off`.
  - `list_together_busy_strips(p_relationship_id uuid, p_now timestamptz DEFAULT now())` returns `TABLE (is_mine boolean, starts_at timestamptz, ends_at timestamptz)`.

- [ ] **Step 1: Write the failing contract**

```sql
-- Together Phase 6 contracts: busy overlay + finder. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f700000-0000-0000-0000-0000000000a1'), ('7f700000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f700000-0000-0000-0000-0000000000a1', '+233330000001', 'Ana'),
  ('7f700000-0000-0000-0000-0000000000b2', '+233330000002', 'Luca') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1',
        '7f700000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
-- Ana is in London, Luca in Toronto (5 hours behind in November).
INSERT INTO public.planning_member_settings (relationship_id, user_id, timezone) VALUES
  ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'Europe/London'),
  ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', 'America/Toronto');
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.windows(p_now timestamptz, p_day date) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(to_char(starts_at AT TIME ZONE 'UTC', 'HH24:MI') || '-' || to_char(ends_at AT TIME ZONE 'UTC', 'HH24:MI'), ',' ORDER BY starts_at), '')
  FROM public.list_together_free_windows('7f800000-0000-0000-0000-000000000001', p_now)
  WHERE (starts_at AT TIME ZONE 'UTC')::date = p_day $$;

-- 0. Busy-only by construction: the table has no room for details.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'couple_busy_blocks'
             AND column_name NOT IN ('id', 'relationship_id', 'user_id', 'starts_at', 'ends_at', 'uploaded_at')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: couple_busy_blocks can hold more than times';
  END IF;
END $$;

-- 1. Off by default; uploading while off is refused; nothing until both opt in.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  IF public.get_together_overlay('7f800000-0000-0000-0000-000000000001')->>'level' <> 'off' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: overlay not off by default';
  END IF;
  BEGIN
    PERFORM public.replace_my_busy_blocks('7f800000-0000-0000-0000-000000000001', '[]'::jsonb);
    RAISE EXCEPTION 'CONTRACT VIOLATED: upload accepted while off';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
  END;
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  IF pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10') <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: windows shown before both opted in';
  END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Waking hours in each zone: London 08-22 UTC, Toronto 13-03 UTC → 13:00-22:00.
--    Luca's busy 15:10-15:40 rounds out to 15:00-16:00 and splits the day.
--    An all-day "Pay rent" doesn't block; a trip does.
DO $$
DECLARE v_n int; v text;
BEGIN
  -- Stored as of Nov 10 (the RPC itself always uses the real clock).
  v_n := public.together_store_busy_blocks('7f800000-0000-0000-0000-000000000001',
    '7f700000-0000-0000-0000-0000000000b2',
    '[{"starts_at":"2026-11-10T15:10:00Z","ends_at":"2026-11-10T15:40:00Z"},
      {"starts_at":"2026-12-30T10:00:00Z","ends_at":"2026-12-30T11:00:00Z"}]'::jsonb,
    '2026-11-10T00:00:00Z');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a block beyond 14 days was kept (% stored)', v_n; END IF;
  IF (SELECT count(*) FROM public.couple_busy_blocks
      WHERE user_id = '7f700000-0000-0000-0000-0000000000b2'
        AND starts_at = '2026-11-10T15:00:00Z' AND ends_at = '2026-11-10T16:00:00Z') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy time not rounded outward to 30 minutes';
  END IF;
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'Pay rent', true, '2026-11-10',
          ARRAY['7f700000-0000-0000-0000-0000000000a1','7f700000-0000-0000-0000-0000000000b2']::uuid[]);
  INSERT INTO public.couple_events (relationship_id, created_by, kind, title, all_day, start_date, participant_ids)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000a1', 'trip', 'Lisbon', true, '2026-11-11',
          ARRAY['7f700000-0000-0000-0000-0000000000a1']::uuid[]);
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Nov 10 windows %', v; END IF;
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-11');
  IF v <> '' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a trip day had windows %', v; END IF;
  -- partner-local times come back for display
  IF (SELECT partner_from || '-' || partner_to FROM public.list_together_free_windows('7f800000-0000-0000-0000-000000000001', '2026-11-10T00:00:00Z')
      ORDER BY starts_at LIMIT 1) <> '08:00-10:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner-local window times wrong';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Across Toronto's clock change (Oct 31 is EDT, UTC-4): overlap is 12:00-22:00 UTC
--    (London is already UTC+0 after Oct 25), an hour earlier than Nov 10's 13:00.
DO $$
DECLARE v text;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-10-31T00:00:00Z', '2026-10-31');
  IF v <> '12:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Oct 31 (EDT) windows %', v; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Private events: Luca's private 18:00-19:00 doesn't shrink Ana's windows,
--    but shrinks his own (spec §3.6).
DO $$
DECLARE v text;
BEGIN
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids, visibility)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', 'Ring shopping', false,
          '2026-11-10T18:00:00Z', '2026-11-10T19:00:00Z', 'America/Toronto',
          ARRAY['7f700000-0000-0000-0000-0000000000b2']::uuid[], 'private');
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner private event leaked into my windows %', v; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  v := pg_temp.windows('2026-11-10T00:00:00Z', '2026-11-10');
  IF v <> '13:00-15:00,16:00-18:00,19:00-22:00' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: my private event ignored %', v; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. Strips: at free_windows nobody sees the other's blocks; at strips the
--    partner (if opted in) sees them; I always see my own.
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE NOT is_mine;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner blocks reached me at free_windows'; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000b2');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'strips');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE is_mine;
  IF v_n < 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: I cannot see my own blocks'; END IF;
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z') WHERE NOT is_mine;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: strips level not shared (%)', v_n; END IF;
  -- if Ana turns off, she sees nothing of Luca's either (same rules for both)
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'off');
  SELECT count(*) INTO v_n FROM public.list_together_busy_strips('7f800000-0000-0000-0000-000000000001', '2026-11-09T00:00:00Z');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: strips shown to someone opted out'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Turning off deletes my rows at once; the daily purge removes past blocks;
--    ending the relationship removes everyone's.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f700000-0000-0000-0000-0000000000a1');
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'free_windows');
  PERFORM public.together_store_busy_blocks('7f800000-0000-0000-0000-000000000001',
    '7f700000-0000-0000-0000-0000000000a1',
    '[{"starts_at":"2026-11-12T09:00:00Z","ends_at":"2026-11-12T10:00:00Z"}]'::jsonb, '2026-11-11T00:00:00Z');
  IF NOT EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE user_id = '7f700000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: fixture block not stored';
  END IF;
  PERFORM public.set_together_overlay('7f800000-0000-0000-0000-000000000001', 'off');
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE user_id = '7f700000-0000-0000-0000-0000000000a1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning off left my busy times on the server';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  INSERT INTO public.couple_busy_blocks (relationship_id, user_id, starts_at, ends_at)
  VALUES ('7f800000-0000-0000-0000-000000000001', '7f700000-0000-0000-0000-0000000000b2', now() - interval '3 days', now() - interval '3 days' + interval '30 minutes');
  PERFORM public.together_purge_busy_blocks();
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE ends_at < now()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past blocks survived the purge';
  END IF;

  UPDATE public.relationships SET status = 'ended', chat_archived_at = now()
  WHERE id = '7f800000-0000-0000-0000-000000000001';
  IF EXISTS (SELECT 1 FROM public.couple_busy_blocks WHERE relationship_id = '7f800000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy times outlived the relationship';
  END IF;
END $$;

ROLLBACK;
```

Storing goes through the internal `together_store_busy_blocks(…, p_now)`, so the contract doesn't depend on the day it runs. The client-facing `replace_my_busy_blocks` always passes the real `now()`.

- [ ] **Step 2: Run it and watch it fail**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_overlay_contracts.sql`
Expected: FAIL in section 0 or 1, because `couple_busy_blocks` / `get_together_overlay` don't exist.

- [ ] **Step 3: Write the migration**

```sql
-- Together Phase 6: lend only *when* you're busy, opt-in per person (spec
-- §3.3, D5, §6.4; plan R1–R5). Times only, rounded to 30 minutes, 14 days.

ALTER TABLE public.together_member_prefs
  ADD COLUMN overlay text NOT NULL DEFAULT 'off'
    CHECK (overlay IN ('off', 'free_windows', 'strips'));

CREATE TABLE public.couple_busy_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  CHECK (extract(epoch FROM starts_at)::bigint % 1800 = 0 AND extract(epoch FROM ends_at)::bigint % 1800 = 0)
);
CREATE INDEX idx_couple_busy_blocks_rel ON public.couple_busy_blocks (relationship_id, starts_at);
ALTER TABLE public.couple_busy_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.couple_busy_blocks FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_overlay_level(p_relationship_id uuid, p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT p.overlay FROM public.together_member_prefs p
                   WHERE p.relationship_id = p_relationship_id AND p.user_id = p_user), 'off')
$$;
CREATE FUNCTION public.together_member_tz(p_relationship_id uuid, p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce((SELECT s.timezone FROM public.planning_member_settings s
                   WHERE s.relationship_id = p_relationship_id AND s.user_id = p_user), 'UTC')
$$;
REVOKE ALL ON FUNCTION public.together_overlay_level(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_member_tz(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.get_together_overlay(p_relationship_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  RETURN jsonb_build_object('level', public.together_overlay_level(p_relationship_id, v_me));
END;
$$;

-- Turning it off deletes my busy times in the same call; the partner is told nothing.
CREATE FUNCTION public.set_together_overlay(p_relationship_id uuid, p_level text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_level IS NULL OR p_level NOT IN ('off', 'free_windows', 'strips') THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  INSERT INTO public.together_member_prefs (relationship_id, user_id, overlay, updated_at)
  VALUES (p_relationship_id, v_me, p_level, now())
  ON CONFLICT (relationship_id, user_id) DO UPDATE SET overlay = EXCLUDED.overlay, updated_at = now();
  IF p_level = 'off' THEN
    DELETE FROM public.couple_busy_blocks WHERE relationship_id = p_relationship_id AND user_id = v_me;
  END IF;
  RETURN jsonb_build_object('level', p_level);
END;
$$;

-- Replace someone's busy times as of p_now: rounded outward to 30 minutes,
-- clipped to p_now..p_now+14 days, anything outside dropped. Internal.
CREATE FUNCTION public.together_store_busy_blocks(p_relationship_id uuid, p_user uuid, p_blocks jsonb, p_now timestamptz)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  DELETE FROM public.couple_busy_blocks WHERE relationship_id = p_relationship_id AND user_id = p_user;
  BEGIN
    INSERT INTO public.couple_busy_blocks (relationship_id, user_id, starts_at, ends_at)
    SELECT p_relationship_id, p_user, s, e
    FROM (
      SELECT to_timestamp(floor(extract(epoch FROM greatest((b->>'starts_at')::timestamptz, p_now)) / 1800) * 1800) AS s,
             to_timestamp(ceil(extract(epoch FROM least((b->>'ends_at')::timestamptz, p_now + interval '14 days')) / 1800) * 1800) AS e
      FROM jsonb_array_elements(p_blocks) b
    ) r
    WHERE e > s;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow OR invalid_text_representation THEN
    PERFORM public.together_fail('invalid_input');
  END;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION public.together_store_busy_blocks(uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon, authenticated;

-- My busy times for the next 14 days, replacing what was there (only while on).
CREATE FUNCTION public.replace_my_busy_blocks(p_relationship_id uuid, p_blocks jsonb)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF public.together_overlay_level(p_relationship_id, v_me) = 'off'
     OR p_blocks IS NULL OR jsonb_typeof(p_blocks) <> 'array' OR jsonb_array_length(p_blocks) > 300 THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  RETURN public.together_store_busy_blocks(p_relationship_id, v_me, p_blocks, now());
END;
$$;

-- When we're both free (R1–R3): 30-minute slots on the UTC grid over 14 days,
-- inside both partners' waking hours, clear of both partners' busy blocks and
-- of every Together event I can see; runs of ≥ 60 minutes. Empty unless both opted in.
CREATE FUNCTION public.list_together_free_windows(p_relationship_id uuid, p_now timestamptz DEFAULT now())
RETURNS TABLE (starts_at timestamptz, ends_at timestamptz, partner_from text, partner_to text, partner_differs boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
  v_tz_me text; v_tz_p text;
  v_from timestamptz := to_timestamp(ceil(extract(epoch FROM p_now) / 1800) * 1800);
BEGIN
  IF v_partner IS NULL
     OR public.together_overlay_level(p_relationship_id, v_me) = 'off'
     OR public.together_overlay_level(p_relationship_id, v_partner) = 'off' THEN
    RETURN;
  END IF;
  v_tz_me := public.together_member_tz(p_relationship_id, v_me);
  v_tz_p := public.together_member_tz(p_relationship_id, v_partner);
  RETURN QUERY
  WITH busy_events AS (
    SELECT CASE WHEN i.all_day THEN NULL ELSE i.starts_at END AS s,
           CASE WHEN i.all_day THEN NULL ELSE coalesce(i.ends_at, i.starts_at + interval '1 hour') END AS e,
           CASE WHEN i.all_day THEN i.item_date END AS d
    FROM public.together_items_for(v_me, p_relationship_id,
           (v_from AT TIME ZONE 'UTC')::date - 1, (v_from AT TIME ZONE 'UTC')::date + 15) i
    WHERE i.item_kind = 'event' AND (NOT i.all_day OR i.source_ref->>'kind' = 'trip')
  ), slots AS (
    SELECT g AS s, g + interval '30 minutes' AS e
    FROM generate_series(v_from, v_from + interval '14 days' - interval '30 minutes', interval '30 minutes') g
  ), free AS (
    SELECT sl.s, sl.e FROM slots sl
    WHERE (sl.s AT TIME ZONE v_tz_me)::time BETWEEN time '08:00' AND time '21:30'
      AND (sl.s AT TIME ZONE v_tz_p)::time BETWEEN time '08:00' AND time '21:30'
      AND NOT EXISTS (SELECT 1 FROM public.couple_busy_blocks b
                      WHERE b.relationship_id = p_relationship_id AND b.user_id IN (v_me, v_partner)
                        AND b.starts_at < sl.e AND b.ends_at > sl.s)
      AND NOT EXISTS (SELECT 1 FROM busy_events x
                      WHERE (x.s IS NOT NULL AND x.s < sl.e AND x.e > sl.s)
                         OR (x.d IS NOT NULL AND x.d IN ((sl.s AT TIME ZONE v_tz_me)::date,
                                                         (sl.s AT TIME ZONE v_tz_p)::date)))
  ), runs AS (
    SELECT f.s, f.e, f.s - (row_number() OVER (ORDER BY f.s)) * interval '30 minutes' AS grp FROM free f
  ), windows AS (
    SELECT min(r.s) AS ws, max(r.e) AS we FROM runs r GROUP BY r.grp
    HAVING max(r.e) - min(r.s) >= interval '60 minutes'
  )
  SELECT w.ws, w.we,
         to_char(w.ws AT TIME ZONE v_tz_p, 'HH24:MI'), to_char(w.we AT TIME ZONE v_tz_p, 'HH24:MI'),
         to_char(w.ws AT TIME ZONE v_tz_p, 'HH24:MI') <> to_char(w.ws AT TIME ZONE v_tz_me, 'HH24:MI')
  FROM windows w ORDER BY w.ws;
END;
$$;

-- Busy strips (D5): mine always; my partner's only at their 'strips' level,
-- and only while I'm opted in too (same rules for both).
CREATE FUNCTION public.list_together_busy_strips(p_relationship_id uuid, p_now timestamptz DEFAULT now())
RETURNS TABLE (is_mine boolean, starts_at timestamptz, ends_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_partner uuid := public.together_partner(p_relationship_id, v_me);
BEGIN
  IF public.together_overlay_level(p_relationship_id, v_me) = 'off' THEN RETURN; END IF;
  RETURN QUERY
  SELECT b.user_id = v_me, b.starts_at, b.ends_at
  FROM public.couple_busy_blocks b
  WHERE b.relationship_id = p_relationship_id AND b.ends_at > p_now
    AND (b.user_id = v_me
         OR (b.user_id = v_partner AND public.together_overlay_level(p_relationship_id, v_partner) = 'strips'))
  ORDER BY b.starts_at;
END;
$$;

CREATE FUNCTION public.together_purge_busy_blocks() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.couple_busy_blocks WHERE ends_at < now()
$$;
REVOKE ALL ON FUNCTION public.together_purge_busy_blocks() FROM PUBLIC, anon, authenticated;
SELECT cron.schedule('together_busy_purge', '45 3 * * *', $$ SELECT public.together_purge_busy_blocks(); $$);

-- Ending a couple (any path) purges its busy times (spec §3.8).
CREATE FUNCTION public.together_purge_busy_on_end() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (OLD.status = 'active' AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    DELETE FROM public.couple_busy_blocks WHERE relationship_id = OLD.id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trigger_together_purge_busy ON public.relationships;
CREATE TRIGGER trigger_together_purge_busy
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.together_purge_busy_on_end();

REVOKE ALL ON FUNCTION public.get_together_overlay(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_together_overlay(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.replace_my_busy_blocks(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_free_windows(uuid, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_busy_strips(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_together_overlay(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_together_overlay(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replace_my_busy_blocks(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_free_windows(uuid, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_busy_strips(uuid, timestamptz) TO authenticated;
```

- [ ] **Step 4: Run every Together contract**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`
Expected: eight `PASS` lines. If an expected string disagrees only because of a wrong hand calculation in the test (for example the London/Toronto offsets), recompute it from the zones, fix the test and record it in the ledger. Don't bend the function to the test.

---

### Task 2: Device-side rounding (pure Dart)

**Files:**
- Create: `lib/features/together/domain/together_overlay.dart`
- Test: `test/features/together/together_overlay_test.dart`

**Interfaces:**
- Produces:
  - `enum OverlayLevel { off('off'), freeWindows('free_windows'), strips('strips'); final String wire; static OverlayLevel fromWire(String?) }`
  - `class FreeWindow { DateTime start, end; String partnerFrom, partnerTo; bool partnerDiffers; factory FreeWindow.fromRow(Map) }`
  - `class BusyStrip { bool isMine; DateTime start, end; factory BusyStrip.fromRow(Map) }`
  - `class DeviceBusy { DateTime start, end; bool allDay, free, cancelled; }`
  - `List<({DateTime start, DateTime end})> busyBlocksFrom(Iterable<DeviceBusy> events, DateTime now)`, which returns UTC values, sorted and merged.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceBusy _e(
  DateTime s,
  DateTime e, {
  bool allDay = false,
  bool free = false,
  bool cancelled = false,
}) => DeviceBusy(start: s, end: e, allDay: allDay, free: free, cancelled: cancelled);

void main() {
  final now = DateTime.utc(2026, 11, 10, 8, 5);

  test('times round outward to 30 minutes and overlaps merge', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 10, 9, 10), DateTime.utc(2026, 11, 10, 9, 40)),
      _e(DateTime.utc(2026, 11, 10, 9, 50), DateTime.utc(2026, 11, 10, 10, 20)),
      _e(DateTime.utc(2026, 11, 10, 14, 0), DateTime.utc(2026, 11, 10, 15, 0)),
    ], now);
    expect(b.map((x) => '${x.start.toIso8601String()}/${x.end.toIso8601String()}'), [
      '2026-11-10T09:00:00.000Z/2026-11-10T10:30:00.000Z',
      '2026-11-10T14:00:00.000Z/2026-11-10T15:00:00.000Z',
    ]);
  });

  test('all-day, free and cancelled entries are not busy', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 11), DateTime.utc(2026, 11, 12), allDay: true),
      _e(DateTime.utc(2026, 11, 10, 12), DateTime.utc(2026, 11, 10, 13), free: true),
      _e(DateTime.utc(2026, 11, 10, 16), DateTime.utc(2026, 11, 10, 17), cancelled: true),
    ], now);
    expect(b, isEmpty);
  });

  test('only now to 14 days ahead, clipped at both ends', () {
    final b = busyBlocksFrom([
      _e(DateTime.utc(2026, 11, 9, 9), DateTime.utc(2026, 11, 9, 10)), // past
      _e(DateTime.utc(2026, 11, 10, 7), DateTime.utc(2026, 11, 10, 9)), // started
      _e(DateTime.utc(2026, 11, 24, 7), DateTime.utc(2026, 11, 24, 23)), // runs past 14 days
      _e(DateTime.utc(2026, 12, 1), DateTime.utc(2026, 12, 1, 1)), // beyond
    ], now);
    expect(b.first.start, DateTime.utc(2026, 11, 10, 8));
    expect(b.last.end, DateTime.utc(2026, 11, 24, 8, 30));
    expect(b.length, 2);
  });

  test('a :45 zone (Nepal) still rounds on the UTC half-hour grid', () {
    final kathmandu = DateTime.utc(2026, 11, 10, 3, 15); // 09:00 local
    final b = busyBlocksFrom([
      _e(kathmandu, kathmandu.add(const Duration(minutes: 30))),
    ], now.subtract(const Duration(hours: 6)));
    expect([b.single.start, b.single.end], [
      DateTime.utc(2026, 11, 10, 3),
      DateTime.utc(2026, 11, 10, 4),
    ]);
  });

  test('rows map; levels read from the wire', () {
    final w = FreeWindow.fromRow({
      'starts_at': '2026-11-10T13:00:00+00:00',
      'ends_at': '2026-11-10T15:00:00+00:00',
      'partner_from': '08:00',
      'partner_to': '10:00',
      'partner_differs': true,
    });
    expect([w.start, w.partnerFrom, w.partnerDiffers], [
      DateTime.utc(2026, 11, 10, 13).toLocal(),
      '08:00',
      true,
    ]);
    expect(OverlayLevel.fromWire('strips'), OverlayLevel.strips);
    expect(OverlayLevel.fromWire(null), OverlayLevel.off);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_overlay_test.dart`
Expected: a compile failure because `together_overlay.dart` doesn't exist.

- [ ] **Step 3: Write `together_overlay.dart`**

```dart
/// The busy overlay (Together Phase 6): only *when* someone is busy ever
/// leaves their phone, rounded outward to 30 minutes, 14 days ahead.
library;

enum OverlayLevel {
  off('off'),
  freeWindows('free_windows'),
  strips('strips');

  const OverlayLevel(this.wire);
  final String wire;

  static OverlayLevel fromWire(String? s) =>
      values.firstWhere((v) => v.wire == s, orElse: () => off);
}

DateTime _local(Object v) => DateTime.parse(v as String).toLocal();

/// A time we're both free (computed on the server, plan R1).
class FreeWindow {
  const FreeWindow({
    required this.start,
    required this.end,
    required this.partnerFrom,
    required this.partnerTo,
    required this.partnerDiffers,
  });

  factory FreeWindow.fromRow(Map<String, dynamic> r) => FreeWindow(
    start: _local(r['starts_at']),
    end: _local(r['ends_at']),
    partnerFrom: r['partner_from'] as String? ?? '',
    partnerTo: r['partner_to'] as String? ?? '',
    partnerDiffers: r['partner_differs'] as bool? ?? false,
  );

  final DateTime start;
  final DateTime end;

  /// The window in my partner's own clock ("08:00"), for long distance.
  final String partnerFrom;
  final String partnerTo;
  final bool partnerDiffers;
}

class BusyStrip {
  const BusyStrip({required this.isMine, required this.start, required this.end});

  factory BusyStrip.fromRow(Map<String, dynamic> r) => BusyStrip(
    isMine: r['is_mine'] as bool? ?? false,
    start: _local(r['starts_at']),
    end: _local(r['ends_at']),
  );

  final bool isMine;
  final DateTime start;
  final DateTime end;
}

/// One entry read from the phone's calendar: times and flags only.
class DeviceBusy {
  const DeviceBusy({
    required this.start,
    required this.end,
    this.allDay = false,
    this.free = false,
    this.cancelled = false,
  });

  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool free;
  final bool cancelled;
}

const _slotMs = 30 * 60 * 1000;

DateTime _floor(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
  (t.millisecondsSinceEpoch ~/ _slotMs) * _slotMs,
  isUtc: true,
);

DateTime _ceil(DateTime t) {
  final ms = t.millisecondsSinceEpoch;
  final up = ms % _slotMs == 0 ? ms : (ms ~/ _slotMs + 1) * _slotMs;
  return DateTime.fromMillisecondsSinceEpoch(up, isUtc: true);
}

/// What we upload (plan R4): timed, busy, not cancelled; now..now+14 days;
/// rounded outward to the UTC half-hour; overlaps merged.
List<({DateTime start, DateTime end})> busyBlocksFrom(
  Iterable<DeviceBusy> events,
  DateTime now,
) {
  final from = _floor(now.toUtc());
  final to = now.toUtc().add(const Duration(days: 14));
  final raw = <({DateTime start, DateTime end})>[];
  for (final e in events) {
    if (e.allDay || e.free || e.cancelled) continue;
    final s = e.start.toUtc().isBefore(from) ? from : e.start.toUtc();
    final en = e.end.toUtc().isAfter(to) ? to : e.end.toUtc();
    if (!en.isAfter(s)) continue;
    raw.add((start: _floor(s), end: _ceil(en)));
  }
  raw.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({DateTime start, DateTime end})>[];
  for (final b in raw) {
    if (merged.isNotEmpty && !b.start.isAfter(merged.last.end)) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: b.end.isAfter(last.end) ? b.end : last.end,
      ));
    } else {
      merged.add(b);
    }
  }
  return merged;
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/together_overlay_test.dart`
Expected: 5 pass. The clip test expects the started event's start floored from `now` (08:05) to 08:00. Its 14-day end `now + 14d` = 2026-11-24 08:05 ceils to 08:30, which matches the test.

---

### Task 3: Reading the phone, uploading, and the app's data layer

**Files:**
- Modify: `pubspec.yaml` (`flutter pub add device_calendar_plus:^0.8.1`), `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`
- Create: `lib/features/together/data/device_busy_source.dart`
- Modify: `lib/features/together/data/together_repository.dart`, `lib/features/together/presentation/together_providers.dart`
- Test: `test/features/together/busy_sync_test.dart` (new)

**Interfaces:**
- Produces:
  - `abstract class DeviceBusySource { Future<bool> hasAccess(); Future<bool> requestAccess(); Future<List<DeviceBusy>> read(DateTime from, DateTime to); Future<void> openSettings(); }`
  - `class DeviceCalendarPlusSource implements DeviceBusySource`
  - `TogetherRepository`:
    - `getOverlay(String rel) → Future<OverlayLevel>`
    - `setOverlay(String rel, OverlayLevel level) → Future<void>`
    - `replaceBusyBlocks(String rel, List<({DateTime start, DateTime end})> blocks) → Future<int>`
    - `listFreeWindows(String rel) → Future<List<FreeWindow>>`
    - `listBusyStrips(String rel) → Future<List<BusyStrip>>`
  - Providers:
    - `deviceBusySourceProvider`: `Provider<DeviceBusySource>`
    - `togetherOverlayProvider`: `FutureProvider.autoDispose.family<OverlayLevel, String>`
    - `togetherFreeWindowsProvider`: `FutureProvider.autoDispose.family<List<FreeWindow>, String>`
    - `togetherBusyStripsProvider`: `FutureProvider.autoDispose.family<List<BusyStrip>, String>`
  - `Future<bool> syncBusyTimes(Ref | WidgetRef ref, String relationshipId)`, written as `Future<bool> syncBusyTimes(TogetherRepository repo, DeviceBusySource source, String relationshipId, DateTime now)`. It returns whether it uploaded.

- [ ] **Step 1: Write the failing tests** (`busy_sync_test.dart`)

```dart
import 'package:attune/features/together/data/device_busy_source.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

class FakeBusySource implements DeviceBusySource {
  FakeBusySource({this.access = true, this.events = const []});
  bool access;
  final List<DeviceBusy> events;
  @override
  Future<bool> hasAccess() async => access;
  @override
  Future<bool> requestAccess() async => access;
  @override
  Future<List<DeviceBusy>> read(DateTime from, DateTime to) async => events;
  @override
  Future<void> openSettings() async {}
}

void main() {
  final now = DateTime.utc(2026, 11, 10, 8);

  test('when on, only rounded times are uploaded', () async {
    final g = FakeTogetherGateway({
      'get_together_overlay': (_) => {'level': 'free_windows'},
      'replace_my_busy_blocks': (_) => 1,
    });
    final ok = await syncBusyTimes(
      TogetherRepository(g),
      FakeBusySource(
        events: [
          DeviceBusy(
            start: DateTime.utc(2026, 11, 10, 9, 10),
            end: DateTime.utc(2026, 11, 10, 9, 40),
          ),
        ],
      ),
      'r1',
      now,
    );
    expect(ok, isTrue);
    expect(g.calls.last.$2, {
      'p_relationship_id': 'r1',
      'p_blocks': [
        {
          'starts_at': '2026-11-10T09:00:00.000Z',
          'ends_at': '2026-11-10T10:00:00.000Z',
        },
      ],
    });
  });

  test('off, or no calendar access: nothing is read or sent', () async {
    for (final (level, access) in [('off', true), ('free_windows', false)]) {
      final g = FakeTogetherGateway({
        'get_together_overlay': (_) => {'level': level},
        'replace_my_busy_blocks': (_) => 0,
      });
      final ok = await syncBusyTimes(
        TogetherRepository(g),
        FakeBusySource(access: access),
        'r1',
        now,
      );
      expect(ok, isFalse);
      expect(g.calls.any((c) => c.$1 == 'replace_my_busy_blocks'), isFalse);
    }
  });

  test('windows and strips map from the server', () async {
    final g = FakeTogetherGateway({
      'list_together_free_windows':
          (_) => [
            {
              'starts_at': '2026-11-10T13:00:00+00:00',
              'ends_at': '2026-11-10T15:00:00+00:00',
              'partner_from': '08:00',
              'partner_to': '10:00',
              'partner_differs': true,
            },
          ],
      'list_together_busy_strips':
          (_) => [
            {
              'is_mine': false,
              'starts_at': '2026-11-10T09:00:00+00:00',
              'ends_at': '2026-11-10T12:00:00+00:00',
            },
          ],
      'set_together_overlay': (_) => {'level': 'off'},
    });
    final repo = TogetherRepository(g);
    expect((await repo.listFreeWindows('r1')).single.partnerTo, '10:00');
    expect((await repo.listBusyStrips('r1')).single.isMine, isFalse);
    await repo.setOverlay('r1', OverlayLevel.off);
    expect(g.calls.last.$2, {'p_relationship_id': 'r1', 'p_level': 'off'});
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/busy_sync_test.dart`
Expected: a compile failure because `device_busy_source.dart` doesn't exist.

- [ ] **Step 3: Add the package and platform setup**
  - Run `flutter pub add device_calendar_plus:^0.8.1`.
  - Confirm these names in `~/.pub-cache/hosted/pub.dev/device_calendar_plus-0.8.1/lib/`:
    - `DeviceCalendar.instance`;
    - `hasPermissions()` / `requestPermissions()` → `CalendarPermissionStatus.granted`;
    - `openAppSettings()`;
    - `listEvents(DateTime, DateTime)` → `List<Event>`;
    - `Event.isAllDay`, `.availability` (`EventAvailability.free`), `.status` (`EventStatus.canceled`), `.startDate` and `.endDate`.
  - In `Info.plist`, add `NSCalendarsFullAccessUsageDescription`. Then reword the existing `NSCalendarsUsageDescription` to cover both uses, keeping the plist's rule of naming the feature:

```xml
		<key>NSCalendarsFullAccessUsageDescription</key>
		<string>With Free time together on, Attune reads only when you're busy in your calendar (never titles, places or people) to show when you and your partner are both free.</string>
```

    Set the `NSCalendarsUsageDescription` string to: `Attune adds a Together event to your calendar when you ask, and, with Free time together on, reads only when you're busy (never titles) to find time you're both free.`
  - In `AndroidManifest.xml`, before `<application`, add `<uses-permission android:name="android.permission.READ_CALENDAR" />`.
  - In `android/app/build.gradle.kts`, change `minSdk = flutter.minSdkVersion` to:

```kotlin
        // device_calendar_plus (Together free time) needs API 24; record_android
        // already required 23.
        minSdk = 24
```

- [ ] **Step 4: Write `device_busy_source.dart`**

```dart
import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;

import '../domain/together_overlay.dart';

/// The phone's own calendars, read for busy times only (plan R4). A seam so
/// tests never touch the platform.
abstract class DeviceBusySource {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<List<DeviceBusy>> read(DateTime from, DateTime to);
  Future<void> openSettings();
}

class DeviceCalendarPlusSource implements DeviceBusySource {
  const DeviceCalendarPlusSource();

  dc.DeviceCalendar get _cal => dc.DeviceCalendar.instance;

  @override
  Future<bool> hasAccess() async =>
      await _cal.hasPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<bool> requestAccess() async =>
      await _cal.requestPermissions() == dc.CalendarPermissionStatus.granted;

  @override
  Future<List<DeviceBusy>> read(DateTime from, DateTime to) async {
    final events = await _cal.listEvents(from, to);
    // Titles, places and people are dropped here, on the phone.
    return [
      for (final e in events)
        DeviceBusy(
          start: e.startDate,
          end: e.endDate,
          allDay: e.isAllDay,
          free: e.availability == dc.EventAvailability.free,
          cancelled: e.status == dc.EventStatus.canceled,
        ),
    ];
  }

  @override
  Future<void> openSettings() => _cal.openAppSettings();
}
```

- [ ] **Step 5: Add the repository methods** (import `../domain/together_overlay.dart`)

```dart
  // ── Busy overlay (Phase 6) ──

  Future<OverlayLevel> getOverlay(String relationshipId) async {
    final j = await _call('get_together_overlay', {
      'p_relationship_id': relationshipId,
    });
    return OverlayLevel.fromWire(
      (Map<String, dynamic>.from(j as Map))['level'] as String?,
    );
  }

  /// Off deletes my busy times on the server in the same call.
  Future<void> setOverlay(String relationshipId, OverlayLevel level) =>
      _call('set_together_overlay', {
        'p_relationship_id': relationshipId,
        'p_level': level.wire,
      });

  Future<int> replaceBusyBlocks(
    String relationshipId,
    List<({DateTime start, DateTime end})> blocks,
  ) async =>
      (await _call('replace_my_busy_blocks', {
                'p_relationship_id': relationshipId,
                'p_blocks': [
                  for (final b in blocks)
                    {
                      'starts_at': b.start.toUtc().toIso8601String(),
                      'ends_at': b.end.toUtc().toIso8601String(),
                    },
                ],
              })
              as num)
          .toInt();

  Future<List<FreeWindow>> listFreeWindows(String relationshipId) async {
    final rows =
        await _call('list_together_free_windows', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [for (final r in rows) FreeWindow.fromRow(Map<String, dynamic>.from(r))];
  }

  Future<List<BusyStrip>> listBusyStrips(String relationshipId) async {
    final rows =
        await _call('list_together_busy_strips', {
              'p_relationship_id': relationshipId,
            })
            as List;
    return [for (final r in rows) BusyStrip.fromRow(Map<String, dynamic>.from(r))];
  }
```

- [ ] **Step 6: Add the providers and `syncBusyTimes`** to `together_providers.dart` (import `../data/device_busy_source.dart` and `../domain/together_overlay.dart`)

```dart
final deviceBusySourceProvider = Provider<DeviceBusySource>(
  (ref) => const DeviceCalendarPlusSource(),
);

final togetherOverlayProvider = FutureProvider.autoDispose
    .family<OverlayLevel, String>(
      (ref, relationshipId) =>
          ref.watch(togetherRepositoryProvider).getOverlay(relationshipId),
    );

/// When we're both free (empty unless both of us opted in).
final togetherFreeWindowsProvider = FutureProvider.autoDispose
    .family<List<FreeWindow>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      return ref.watch(togetherRepositoryProvider).listFreeWindows(relationshipId);
    });

final togetherBusyStripsProvider = FutureProvider.autoDispose
    .family<List<BusyStrip>, String>(
      (ref, relationshipId) =>
          ref.watch(togetherRepositoryProvider).listBusyStrips(relationshipId),
    );

/// Reads my calendar's busy times and replaces what's on the server, if my
/// overlay is on and the phone lets us read (plan R4). Never throws.
Future<bool> syncBusyTimes(
  TogetherRepository repo,
  DeviceBusySource source,
  String relationshipId,
  DateTime now,
) async {
  try {
    if (await repo.getOverlay(relationshipId) == OverlayLevel.off) return false;
    if (!await source.hasAccess()) return false;
    final events = await source.read(now, now.add(const Duration(days: 14)));
    await repo.replaceBusyBlocks(relationshipId, busyBlocksFrom(events, now));
    return true;
  } catch (_) {
    return false;
  }
}
```

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/together/busy_sync_test.dart && flutter analyze lib/features/together`
Expected: 3 pass; no issues. Also check that `flutter build apk --debug --target-platform android-arm64` still configures, with no manifest-merger minSdk error. If that build needs network or an SDK that isn't present, record that in the ledger and leave it for the owner's device check.

---

### Task 4: "Free time together" in settings

**Files:**
- Modify: `lib/features/together/presentation/widgets/together_settings_sheet.dart`
- Test: `test/features/together/overlay_settings_test.dart` (new)

**Interfaces:**
- Consumes: the Task 3 providers and repository methods, and `FakeBusySource` (from `busy_sync_test.dart`).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'busy_sync_test.dart' show FakeBusySource;
import 'together_repository_test.dart' show FakeTogetherGateway;

Future<FakeTogetherGateway> _open(
  WidgetTester t,
  FakeBusySource source, {
  String level = 'off',
}) async {
  t.view.physicalSize = const Size(1170, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  var current = level;
  final g = FakeTogetherGateway({
    'get_together_prefs': (_) => {'daily_summary': true, 'care_nudges': true},
    'get_calendar_feed_status': (_) => [{'is_active': false, 'since': null}],
    'get_together_overlay': (_) => {'level': current},
    'set_together_overlay': (p) {
      current = p['p_level'] as String;
      return {'level': current};
    },
    'replace_my_busy_blocks': (_) => 0,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        deviceBusySourceProvider.overrideWithValue(source),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed: () => showTogetherSettingsSheet(c, 'r1'),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('turning it on asks for the calendar, then saves and uploads', (
    t,
  ) async {
    final g = await _open(t, FakeBusySource());
    expect(find.textContaining('never titles'), findsOneWidget);
    await t.tap(find.text("Show when we're both free"));
    await t.pumpAndSettle();
    expect(
      g.calls.where((c) => c.$1 == 'set_together_overlay').single.$2['p_level'],
      'free_windows',
    );
    expect(g.calls.any((c) => c.$1 == 'replace_my_busy_blocks'), isTrue);
  });

  testWidgets('no calendar access: it stays off and says where to allow it', (
    t,
  ) async {
    final g = await _open(t, FakeBusySource(access: false));
    await t.tap(find.text("Show when we're both free"));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'set_together_overlay'), isFalse);
    expect(find.textContaining('Calendar access is off'), findsOneWidget);
  });

  testWidgets('turning it off deletes, with no partner wording', (t) async {
    final g = await _open(t, FakeBusySource(), level: 'strips');
    await t.tap(find.text('Off'));
    await t.pumpAndSettle();
    expect(g.calls.last.$2, {'p_relationship_id': 'r1', 'p_level': 'off'});
    expect(find.textContaining('turned this on'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/overlay_settings_test.dart`
Expected: 3 failures (the texts aren't found).

- [ ] **Step 3: Implement the section.** In the settings state, add `bool _overlayBusy = false;` and:

```dart
  Future<void> _setOverlay(OverlayLevel next, OverlayLevel current) async {
    if (_overlayBusy || next == current) return;
    setState(() => _overlayBusy = true);
    final repo = ref.read(togetherRepositoryProvider);
    final source = ref.read(deviceBusySourceProvider);
    try {
      if (current == OverlayLevel.off && !await source.requestAccess()) {
        if (mounted) {
          context.showErrorSnackbar(
            'Calendar access is off. You can allow it in Settings.',
          );
        }
        return;
      }
      await repo.setOverlay(widget.relationshipId, next);
      ref.invalidate(togetherOverlayProvider(widget.relationshipId));
      if (next != OverlayLevel.off) {
        await syncBusyTimes(repo, source, widget.relationshipId, DateTime.now());
      }
      ref.invalidate(togetherFreeWindowsProvider(widget.relationshipId));
      ref.invalidate(togetherBusyStripsProvider(widget.relationshipId));
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not save that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _overlayBusy = false);
    }
  }
```

In `build`, read `final overlay = ref.watch(togetherOverlayProvider(widget.relationshipId));` and add a section before the calendar-link section:

```dart
          AppDivider(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.md,
              Spacing.md.w,
              Spacing.xs,
            ),
            child: Text(
              'Free time together',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              'Only when you’re busy leaves your phone — never titles, places '
              'or people. Free times show once you’ve both chosen to. Turning '
              'it off deletes your busy times straight away.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          overlay.when(
            loading:
                () => const Padding(
                  padding: EdgeInsets.all(Spacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (_, __) => InfoRowWidget(
                  title: "Couldn't load this",
                  subtitle: 'Tap to try again',
                  icon: Icons.refresh_rounded,
                  showAvatar: false,
                  showDivider: false,
                  disableTrailing: true,
                  onTap:
                      () => ref.invalidate(
                        togetherOverlayProvider(widget.relationshipId),
                      ),
                ),
            data:
                (level) => Column(
                  children: [
                    for (final (value, title) in [
                      (OverlayLevel.off, 'Off'),
                      (OverlayLevel.freeWindows, "Show when we're both free"),
                      (OverlayLevel.strips, 'Also show $partner my busy times'),
                    ])
                      RadioListTile<OverlayLevel>(
                        value: value,
                        groupValue: level,
                        title: Text(title),
                        onChanged:
                            _overlayBusy
                                ? null
                                : (v) => _setOverlay(v!, level),
                      ),
                  ],
                ),
          ),
```

Import `../../domain/together_overlay.dart`. The existing settings tests (`together_settings_test.dart`, `calendar_feed_test.dart`) have no `get_together_overlay` handler; the section's error row then shows, which those tests don't assert against. Run them, and if any fails on layout, add the handler there and record it in the ledger.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 5: Free time on the hub, and a window becomes a proposal

**Files:**
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart`
- Modify: `lib/features/together/presentation/screens/together_screen.dart`
- Test: `test/features/together/couple_event_sheet_test.dart`, `test/features/together/together_screen_test.dart`

**Interfaces:**
- Produces: `showCoupleEventSheet(context, {required relationshipId, TogetherItem? item, ({DateTime start, DateTime end})? proposeWindow})`.

- [ ] **Step 1: Write the failing event-sheet test.** Use the file's `_open` helper; give it an optional `({DateTime start, DateTime end})? window` that's passed through to `showCoupleEventSheet`, and add a `'propose_couple_event': (_) => 'p1'` handler. Then:

```dart
  testWidgets('a free window opens as a suggestion for that time', (t) async {
    final s = DateTime(2026, 11, 10, 19);
    final g = await _open(
      t,
      window: (start: s, end: s.add(const Duration(hours: 3))),
    );
    await t.enterText(find.byType(TextField).first, 'Dinner');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.singleWhere((c) => c.$1 == 'propose_couple_event');
    final first = (call.$2['p_options'] as List).first as Map;
    expect(DateTime.parse(first['starts_at'] as String), s.toUtc());
    expect(
      DateTime.parse(first['ends_at'] as String),
      s.add(const Duration(hours: 2)).toUtc(),
    );
  });
```

If the header's action label in propose mode isn't "Save", use the label propose mode actually shows; check `_CoupleEventSheetState.build` and record it in the ledger.

- [ ] **Step 2: Write the failing hub tests** (`together_screen_test.dart`)
  - Add `List<Map<String, dynamic>> windows = const []` and `List<Map<String, dynamic>> strips = const []` to `_pump`.
  - Add the handlers:
    - `'list_together_free_windows': (_) => windows`
    - `'list_together_busy_strips': (_) => strips`
    - `'get_together_overlay': (_) => {'level': 'free_windows'}`
    - `'replace_my_busy_blocks': (_) => 0`
  - Override `deviceBusySourceProvider` with `FakeBusySource(access: false)`.
  - Then add:

```dart
  testWidgets("today's free window shows both clocks and opens a suggestion", (
    t,
  ) async {
    await _pump(
      t,
      windows: [
        {
          'starts_at': DateTime(2026, 11, 2, 19).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 2, 22).toUtc().toIso8601String(),
          'partner_from': '14:00',
          'partner_to': '17:00',
          'partner_differs': true,
        },
        {
          'starts_at': DateTime(2026, 11, 4, 18).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 4, 21).toUtc().toIso8601String(),
          'partner_from': '13:00',
          'partner_to': '16:00',
          'partner_differs': true,
        },
      ],
    );
    expect(find.textContaining('Both free'), findsWidgets);
    expect(find.text("That's 14:00–17:00 for Kofi"), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Free together'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Free together'), findsOneWidget);
  });

  testWidgets("at the strips level I see when my partner is busy today", (
    t,
  ) async {
    await _pump(
      t,
      strips: [
        {
          'is_mine': false,
          'starts_at': DateTime(2026, 11, 2, 9).toUtc().toIso8601String(),
          'ends_at': DateTime(2026, 11, 2, 12).toUtc().toIso8601String(),
        },
      ],
    );
    expect(find.textContaining('Kofi is busy'), findsOneWidget);
  });
```

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/features/together/couple_event_sheet_test.dart test/features/together/together_screen_test.dart`
Expected: a compile failure on `window:` / `proposeWindow`, then failures because the texts aren't found.

- [ ] **Step 4: Implement the event-sheet parameter**
  - Add `({DateTime start, DateTime end})? proposeWindow` to `showCoupleEventSheet` and `_CoupleEventSheet`.
  - In `initState`'s `item == null` branch, after the defaults:

```dart
      final w = widget.proposeWindow;
      if (w != null) {
        // A free window (Phase 6): suggest its start, for up to two hours.
        final length = w.end.difference(w.start);
        _start = w.start;
        _end = w.start.add(
          length > const Duration(hours: 2) ? const Duration(hours: 2) : length,
        );
        _propose = true;
        _times = [(start: _start, end: _end)];
      }
```

- [ ] **Step 5: Implement the hub**
  - In `_agenda`, read these, all optional, so a failure just hides them:
    - `final windows = ref.watch(togetherFreeWindowsProvider(relationshipId)).valueOrNull ?? const <FreeWindow>[];`
    - `final strips = ref.watch(togetherBusyStripsProvider(relationshipId)).valueOrNull ?? const <BusyStrip>[];`
  - Split `windows` into `todayWindows` (start on `today`, up to 2) and `laterWindows` (start after today and within 6 days, up to 5). Take `partnerStripsToday` from the non-mine strips whose start falls on `today`.
  - In Today, after the memory prompt row:

```dart
                                for (final w in todayWindows)
                                  _freeWindowRow(w, partnerName, today: true),
                                if (partnerStripsToday.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.md,
                                      vertical: Spacing.xs,
                                    ),
                                    child: Text(
                                      '$partnerName is busy ${partnerStripsToday.map((s) => '${DateFormat.jm().format(s.start)}–${DateFormat.jm().format(s.end)}').join(', ')}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
```

  - Count windows as content in the "Nothing planned today." condition, so add `&& todayWindows.isEmpty`.
  - After the This week section:

```dart
                            if (laterWindows.isNotEmpty)
                              TogetherSection(
                                title: 'Free together',
                                children: [
                                  for (final w in laterWindows)
                                    _freeWindowRow(w, partnerName),
                                ],
                              ),
```

  - The row:

```dart
  Widget _freeWindowRow(
    FreeWindow w,
    String partnerName, {
    bool today = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final time =
        '${DateFormat.jm().format(w.start)}–${DateFormat.jm().format(w.end)}';
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.event_available_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title:
          today
              ? 'Both free $time'
              : '${DateFormat.MMMEd().format(w.start)} · $time',
      subtitle:
          w.partnerDiffers
              ? "That's ${w.partnerFrom}–${w.partnerTo} for $partnerName"
              : 'Tap to suggest something',
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: true,
      disableTrailing: true,
      onTap:
          () => showCoupleEventSheet(
            context,
            relationshipId:
                ref
                    .read(timeline_providers.currentRelationshipIdProvider)
                    .valueOrNull!,
            proposeWindow: (start: w.start, end: w.end),
          ),
    );
  }
```

  - The busy sync runs once per visit, next to `_reportZone`: add `bool _busySynced = false;`. In `build`, when `relationshipId != null && !_busySynced`, set it and schedule this microtask:

```dart
      Future.microtask(() async {
        final uploaded = await syncBusyTimes(
          ref.read(togetherRepositoryProvider),
          ref.read(deviceBusySourceProvider),
          relationshipId,
          DateTime.now(),
        );
        if (uploaded && mounted) {
          ref.invalidate(togetherFreeWindowsProvider(relationshipId));
        }
      });
```

  - Import `../../domain/together_overlay.dart`.
  - Other harnesses that pump the hub fail quietly on the new RPCs: missing handlers hide the extras. But `syncBusyTimes` reads `deviceBusySourceProvider`, which in tests would reach the real plugin. Override it with a fake wherever `TogetherScreen` is pumped: `grep -rln "TogetherScreen(" test`. Record the files in the ledger.

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/together test/features/planning && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 6: Spec rulings, previews, full suite

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-together-hub-design.md` (add §8.9 after §8.8)

- [ ] **Step 1: Add §8.9**

```markdown
### 8.9 Phase 6 rulings (plan `2026-10-14-together-phase6-overlay.md`)
- R1: The finder runs on the server, so a partner's busy times never reach the other phone below the strips level (supersedes "a pure Dart function" in §6.4).
- R2: Waking hours are 08:00–22:00 in each partner's own zone; windows are 30-minute slots, at least 60 minutes long.
- R3: Busy means uploaded busy times plus every confirmed timed Together event the viewer can see (their own private ones included). Of all-day events only trips count.
- R4: The phone skips all-day, "free" and cancelled entries, rounds outward to 30 minutes and uploads 14 days ahead: on turning it on, and once per visit. Uploads don't ping the partner.
- R5: Levels are off, free windows, and strips (also show my busy times). Default off. Nobody is told the other's level.
- R6: Today shows today's free windows (with the partner's clock when it differs) and, at the strips level, when the partner is busy; "Free together" lists the coming week's windows. A window opens a suggestion for that time. Month hatching and ritual fitting come later.
- R7: Android's minimum becomes API 24 (device_calendar_plus).
```

- [ ] **Step 2: Golden previews (throwaway).** Render these at 320pt width, inspect them for overflow and spacing, then delete the preview test:
  - the settings sheet with the overlay section off, and at strips;
  - Today with two windows and a strips line;
  - the "Free together" section;
  - the event sheet opened from a window.

- [ ] **Step 3: Full verification**

Run:
- `flutter test`
- `flutter analyze lib/features/together`
- `deno test --allow-read supabase/functions/calendar-feed`
- `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`

Expected: everything passes, with eight contract files.
