# Together Phase 5: External Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let each partner see Together in the calendar app they already use, through a private subscription link (an ICS feed). Add "Add to my calendar" on any Together event.

**Architecture:**
- **Server:** `list_together_items` is split into an internal `together_items_for(actor, …)` plus the member-checked wrapper, so the feed applies exactly the app's visibility rules.
  - A per-user hashed token in `calendar_feed_tokens` maps to a service-role-only `together_calendar_feed(token_hash)` that returns the user's items over a rolling window.
  - A public edge function `calendar-feed` (JWT verification off) hashes the token from the URL and renders RFC 5545 text with a pure `ics.ts` builder. It answers a uniform 404 to anything it can't serve.
  - Ending a relationship revokes both partners' links (a trigger).
- **Client:** the Together settings sheet gains a "Your calendar app" section to turn the link on, copy or open it, get a new one, or turn it off.
  - The event editor gains "Add to my calendar", backed by `add_2_calendar` behind a fakeable `CalendarExporter`.

**Tech Stack:** Flutter 3.29, Riverpod 2, Supabase Postgres 17, Deno edge functions (std 0.177 `serve`, supabase-js 2.39), `add_2_calendar ^3.0.1`, `url_launcher` (already a dependency).

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (D4, §3 rules 6, 8 and 9, §5.3 `calendar_feed_tokens`, §5.5 unified read, §6.4 External calendars, §8 Phase 5 row, §10 ICS testing).

## Global Constraints

- Supabase is the single source of truth. External calendars only receive data (D4).
- Private events are the creator's alone everywhere, including the ICS feed. A `busy_only` event shows to the partner only as "Busy", with no details (§3.6, §5.5).
- `end-relationship` revokes feed tokens (§3.8).
- The ICS endpoint returns a uniform 404 on any missing, wrong or revoked token, so it never reveals that a relationship exists. Tokens are stored hashed (§3.9).
- In-app copy states that Google refreshes subscribed calendars every 12–24 hours and Apple lets you choose (§6.4).
- Together RPC errors are `together:<code>` via `public.together_fail`. SECURITY DEFINER functions set `search_path = public`.
- Migrations from `20261014100000` on are undeployed, so editing them in place is allowed and must be recorded in the ledger.
- Owner rules:
  - work on `main`;
  - write each test first and watch it fail;
  - commit nothing unless asked;
  - re-read a file before editing it;
  - make surgical changes;
  - no visual regressions, and no overflow at 320pt.

### Rulings this plan makes (record them in spec §8.8 in Task 6)

- **R1: The feed expands occurrences on the server.**
  - It covers a rolling window from 30 days back to 180 days ahead, and emits each occurrence with UTC times (all-day items as dates). There's no RRULE or VTIMEZONE.
  - This is what §5.5 promises ("the app, the push generator and the ICS feed all agree"). It reuses the app's exact visibility code, and it avoids building VTIMEZONE blocks by hand, a classic source of DST bugs. §6.4's "passes RRULEs through" is set aside.
  - Cost if wrong: things beyond 180 days appear only as the window reaches them, and a repeating event shows as separate entries.
- **R2: What the feed contains.**
  - In: confirmed events, reminders and birthdays, and Planning dates.
  - Out: moments, proposals and Planning to-dos.
  - Reminders and Planning dates are marked `TRANSPARENT`, so they don't block time.
- **R3: One live link per user.** Making a new link revokes the old one. Only the hash is stored, so a link is shown once, at creation; "Copy link" later means "Get a new link".
- **R4: The feed follows the user's current active relationship.**
  - Ending a relationship, or archiving its chat, revokes both partners' links through a trigger on `relationships`. That covers every path that ends a relationship, without redefining `end_relationship`.
  - With no active relationship, the feed answers 404.
- **R5: The 404 is uniform**: the same status, body and headers for a malformed, unknown or revoked token, for a user with no active relationship, and for any method other than GET or HEAD. Server errors answer 503, so calendar apps retry.
- **R6: "Add to my calendar" covers Together events.**
  - Repeating events carry their recurrence. One with `BYDAY` exports this occurrence only, and says so.
  - A partner's busy-only event can't be exported.
  - Reminders and Planning dates come later; their screens aren't Together's.
- **R7: Tokens.** Each token is two `gen_random_uuid()` values in hex, 64 characters with 244 random bits. The table stores `sha256` hex. No pgcrypto is needed.

## Review Focus

1. **A partner's private event, or a busy-only event's title and note, must never appear in the partner's feed.** Pinned in the Task 1 contract.
2. **A link must stop working at once when it's revoked, regenerated, or the relationship ends**, and the response must be byte-identical to a never-valid token's. Pinned in the Task 1 contract and the Task 2 handler test.
3. **A multi-day all-day event becomes one calendar entry**, not one per day. A daily repeating all-day event stays separate entries, including a busy-only one whose details are hidden. Pinned in the Task 2 builder test.
4. **Commas, semicolons, newlines, emoji and long titles in event text** must still produce valid, folded ICS lines. Pinned in the Task 2 builder test.
5. **"Add to my calendar" on a repeating event created as "Fri or Sat" (`BYDAY`)** must not silently add the wrong pattern. Pinned in the Task 4 export test.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/20261014110200_list_together_items.sql` | Modify (in place) | Body moves into `together_items_for(actor,…)`; wrapper keeps the member check and the 93-day cap |
| `supabase/migrations/20261014160000_together_calendar_feed.sql` | Create | Tokens table, token RPCs, feed RPC, revoke-on-end trigger |
| `supabase/tests/together_feed_contracts.sql` | Create | Contracts |
| `supabase/functions/calendar-feed/ics.ts` | Create | Pure RFC 5545 builder |
| `supabase/functions/calendar-feed/ics.test.ts` | Create | Builder tests |
| `supabase/functions/calendar-feed/handler.ts` | Create | Request → response, with the feed fetch injected |
| `supabase/functions/calendar-feed/handler.test.ts` | Create | Handler tests |
| `supabase/functions/calendar-feed/index.ts` | Create | `serve` + service-role wiring |
| `supabase/config.toml` | Modify | `[functions.calendar-feed] verify_jwt = false` |
| `lib/features/together/domain/calendar_feed.dart` | Create | `CalendarFeedStatus`, `calendarFeedLinks` |
| `lib/features/together/domain/calendar_export.dart` | Create | `CalendarExport`, `calendarExportFor` |
| `lib/features/together/data/calendar_exporter.dart` | Create | `CalendarExporter` + `Add2CalendarExporter` |
| `lib/features/together/data/together_repository.dart` | Modify | Feed token RPCs |
| `lib/features/together/presentation/together_providers.dart` | Modify | Feed status, Supabase URL, exporter providers |
| `lib/features/together/presentation/widgets/calendar_feed_sheet.dart` | Create | The link sheet (copy, open, explanation) |
| `lib/features/together/presentation/widgets/together_settings_sheet.dart` | Modify | "Your calendar app" section |
| `lib/features/together/presentation/widgets/couple_event_sheet.dart` | Modify | "Add to my calendar" row |
| `pubspec.yaml`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` | Modify | `add_2_calendar` and its platform keys |
| `docs/superpowers/specs/2026-10-14-together-hub-design.md` | Modify | §8.8 rulings |

Harness:
- **Local PG17 harness:**
  - start: `pg_ctl -D <scratchpad>/pg/data -o "-p 55432 -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" start`;
  - run: `<scratchpad>/pg/run.sh <contracts…>`;
  - migrations from `202610141[1-9]*` are picked up automatically.
- **Deno:** `deno test --allow-read supabase/functions/calendar-feed`.

---

### Task 1: The feed on the server

**Files:**
- Modify (in place): `supabase/migrations/20261014110200_list_together_items.sql`
- Create: `supabase/migrations/20261014160000_together_calendar_feed.sql`
- Test: `supabase/tests/together_feed_contracts.sql`

**Interfaces:**
- Produces: `public.together_items_for(p_actor uuid, p_relationship_id uuid, p_start date, p_end date)`, which returns exactly `list_together_items`'s columns. It's internal: executable by no API role.
- Produces: these RPCs:
  - `create_calendar_feed_token() RETURNS text`, the 64-hex plaintext token, shown once. Executable by `authenticated`.
  - `revoke_calendar_feed() RETURNS void`. Executable by `authenticated`.
  - `get_calendar_feed_status() RETURNS TABLE (is_active boolean, since timestamptz)`. Executable by `authenticated`.
  - `together_calendar_feed(p_token_hash text, p_today date DEFAULT current_date) RETURNS jsonb`. Executable by `service_role` only. It returns `NULL` when it can't serve, otherwise `{"items": [{kind, id, date, starts_at, ends_at, all_day, title, note, location, recurring, continuation}]}`.

- [ ] **Step 1: Write the failing contract**

```sql
-- Together Phase 5 contracts: the calendar feed. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f500000-0000-0000-0000-0000000000a1'), ('7f500000-0000-0000-0000-0000000000b2') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f500000-0000-0000-0000-0000000000a1', '+233320000001', 'Ama'),
  ('7f500000-0000-0000-0000-0000000000b2', '+233320000002', 'Kofi') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1',
        '7f500000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_tok (name text PRIMARY KEY, token text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.h(t text) RETURNS text LANGUAGE sql AS $$
  SELECT encode(sha256(convert_to(t, 'UTF8')), 'hex') $$;

-- Fixtures: Ama's shared dinner; Kofi's busy-only and private events; Ama's
-- proposal; a yearly reminder; a moment. All on 2026-11-07.
INSERT INTO public.couple_events (relationship_id, created_by, title, note, all_day, starts_at, ends_at, tz, participant_ids)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'Dinner, at Buka', 'Bring cash', false,
        '2026-11-07T18:00:00Z', '2026-11-07T20:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000a1','7f500000-0000-0000-0000-0000000000b2']::uuid[]);
INSERT INTO public.couple_events (relationship_id, created_by, title, note, all_day, starts_at, ends_at, tz, participant_ids, visibility)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000b2', 'Therapy', 'Room 4', false,
        '2026-11-07T09:00:00Z', '2026-11-07T10:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000b2']::uuid[], 'busy_only'),
       ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000b2', 'Ring shopping', NULL, false,
        '2026-11-07T11:00:00Z', '2026-11-07T12:00:00Z', 'Africa/Accra',
        ARRAY['7f500000-0000-0000-0000-0000000000b2']::uuid[], 'private');
INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids, status, proposed_to, proposal_expires_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'Beach?', true, '2026-11-08',
        ARRAY['7f500000-0000-0000-0000-0000000000a1','7f500000-0000-0000-0000-0000000000b2']::uuid[],
        'proposed', '7f500000-0000-0000-0000-0000000000b2', now() + interval '7 days');
INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'birthday', 'Kofi''s birthday',
        '2020-11-09T00:00:00Z', 'yearly');
INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
VALUES ('7f600000-0000-0000-0000-000000000001', '7f500000-0000-0000-0000-0000000000a1', 'highlight', 'Moment', '2026-11-07');

-- 1. A token is shown once and stored hashed; a new one replaces the old.
DO $$
DECLARE v_t1 text; v_t2 text; v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  v_t1 := public.create_calendar_feed_token();
  IF v_t1 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: token shape %', v_t1; END IF;
  SELECT count(*) INTO v_n FROM public.calendar_feed_tokens WHERE token_hash = pg_temp.h(v_t1) AND revoked_at IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: token not stored as its hash'; END IF;
  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens WHERE token_hash = v_t1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: plaintext token stored';
  END IF;
  v_t2 := public.create_calendar_feed_token();
  IF public.together_calendar_feed(pg_temp.h(v_t1), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the replaced link still works';
  END IF;
  IF NOT (SELECT is_active FROM public.get_calendar_feed_status()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: status not active';
  END IF;
  INSERT INTO t_tok VALUES ('ama', v_t2);
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000b2');
  INSERT INTO t_tok VALUES ('kofi', public.create_calendar_feed_token());
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 2. Ama's feed: her dinner (with details), Kofi's busy block as "Busy" only,
--    never his private event, no proposal, the birthday, no moment.
DO $$
DECLARE v jsonb; v_titles text[]; v_busy jsonb;
BEGIN
  v := public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01');
  SELECT array_agg(i->>'title' ORDER BY i->>'title') INTO v_titles FROM jsonb_array_elements(v->'items') i;
  IF v_titles IS DISTINCT FROM ARRAY['Busy', 'Dinner, at Buka', 'Kofi''s birthday'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ama''s feed has %', v_titles;
  END IF;
  SELECT i INTO v_busy FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Busy';
  IF v_busy->>'note' IS NOT NULL OR v_busy->>'location' IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: busy block leaks details %', v_busy;
  END IF;
  IF (SELECT i->>'note' FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Dinner, at Buka') <> 'Bring cash' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dinner lost its note';
  END IF;
  -- Kofi sees his own private and busy events in full.
  v := public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'kofi')), '2026-11-01');
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Ring shopping')
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i WHERE i->>'title' = 'Therapy' AND i->>'note' = 'Room 4') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Kofi''s own events missing from his feed';
  END IF;
  IF public.together_calendar_feed(pg_temp.h('0000000000000000000000000000000000000000000000000000000000000000'), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown token served a feed';
  END IF;
END $$;

-- 3. Only the service role reads feeds; the app's read keeps its cap.
DO $$
DECLARE v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.together_calendar_feed('x');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user called the feed RPC';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.together_items_for('7f500000-0000-0000-0000-0000000000b2', '7f600000-0000-0000-0000-000000000001', '2026-11-01', '2026-11-30');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user read as someone else';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.list_together_items('7f600000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 93-day cap is gone';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:range' THEN RAISE; END IF;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. Turning it off, and ending the relationship, stop links at once.
DO $$
BEGIN
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000b2');
  PERFORM public.revoke_calendar_feed();
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'kofi')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a revoked link still works';
  END IF;
  IF (SELECT is_active FROM public.get_calendar_feed_status()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: status still active after turning off';
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  UPDATE public.relationships SET status = 'ended', ended_at = now(), chat_archived_at = now()
  WHERE id = '7f600000-0000-0000-0000-000000000001';
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a link outlived the relationship';
  END IF;
  IF EXISTS (SELECT 1 FROM public.calendar_feed_tokens
             WHERE user_id = '7f500000-0000-0000-0000-0000000000a1' AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ending the relationship did not revoke the link';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it and watch it fail**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_feed_contracts.sql`
Expected: FAIL with `function public.create_calendar_feed_token() does not exist`.

- [ ] **Step 3: Split `list_together_items` in place** (`20261014110200`)
  - Rename the function header to `CREATE FUNCTION public.together_items_for(p_actor uuid, p_relationship_id uuid, p_start date, p_end date)`, with the same `RETURNS TABLE (...)`.
  - In its `DECLARE`, change `v_actor uuid := public.together_actor(p_relationship_id);` to `v_actor uuid := p_actor;`.
  - Replace its range check with `IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN PERFORM public.together_fail('range'); END IF;`.
  - Replace the two trailing `REVOKE`/`GRANT` lines with:

```sql
-- Internal: reads as p_actor. Only the member-checked wrapper below and the
-- service-role calendar feed call it (Phase 5).
REVOKE ALL ON FUNCTION public.together_items_for(uuid, uuid, date, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.list_together_items(p_relationship_id uuid, p_start date, p_end date)
RETURNS TABLE (
  item_kind text, item_id uuid, item_date date, starts_at timestamptz, ends_at timestamptz,
  all_day boolean, tz text, title text, participant_ids uuid[], owner_id uuid,
  created_by uuid, visibility text, status text, source_ref jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start OR p_end - p_start > 93 THEN
    PERFORM public.together_fail('range');
  END IF;
  RETURN QUERY SELECT * FROM public.together_items_for(v_actor, p_relationship_id, p_start, p_end);
END;
$$;
REVOKE ALL ON FUNCTION public.list_together_items(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_together_items(uuid, date, date) TO authenticated;
```

- [ ] **Step 4: Write the migration** `20261014160000_together_calendar_feed.sql`

```sql
-- Together Phase 5: a private calendar link per person (spec §6.4, §3.8–3.9;
-- plan R1–R5, R7). Only the token's hash is kept; the feed is read by the
-- calendar-feed edge function with the service role.

CREATE TABLE public.calendar_feed_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE UNIQUE INDEX calendar_feed_tokens_one_live
  ON public.calendar_feed_tokens (user_id) WHERE revoked_at IS NULL;
ALTER TABLE public.calendar_feed_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.calendar_feed_tokens FROM PUBLIC, anon, authenticated;

-- My active couple, if any.
CREATE FUNCTION public.together_active_relationship(p_user uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT r.id FROM public.relationships r
  WHERE r.status = 'active' AND r.chat_archived_at IS NULL
    AND (r.user_a = p_user OR r.user_b = p_user)
  ORDER BY r.started_at DESC NULLS LAST
  LIMIT 1
$$;
REVOKE ALL ON FUNCTION public.together_active_relationship(uuid) FROM PUBLIC, anon, authenticated;

-- A new link (shown once); any older one stops working (R3).
CREATE FUNCTION public.create_calendar_feed_token()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid(); v_token text;
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  IF public.together_active_relationship(v_me) IS NULL THEN PERFORM public.together_fail('not_found'); END IF;
  PERFORM pg_advisory_xact_lock(hashtext('calendar_feed:' || v_me::text));
  UPDATE public.calendar_feed_tokens SET revoked_at = now() WHERE user_id = v_me AND revoked_at IS NULL;
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO public.calendar_feed_tokens (user_id, token_hash)
  VALUES (v_me, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'));
  RETURN v_token;
END;
$$;

CREATE FUNCTION public.revoke_calendar_feed()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  UPDATE public.calendar_feed_tokens SET revoked_at = now() WHERE user_id = v_me AND revoked_at IS NULL;
END;
$$;

CREATE FUNCTION public.get_calendar_feed_status()
RETURNS TABLE (is_active boolean, since timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN PERFORM public.together_fail('unauthenticated'); END IF;
  RETURN QUERY
  SELECT EXISTS (SELECT 1 FROM public.calendar_feed_tokens t WHERE t.user_id = v_me AND t.revoked_at IS NULL),
         (SELECT t.created_at FROM public.calendar_feed_tokens t WHERE t.user_id = v_me AND t.revoked_at IS NULL);
END;
$$;

-- The feed: what this person would see in the app, 30 days back to 180 ahead,
-- one entry per occurrence (R1, R2). NULL when there's nothing to serve (R5).
CREATE FUNCTION public.together_calendar_feed(p_token_hash text, p_today date DEFAULT current_date)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid; v_rel uuid;
BEGIN
  SELECT t.user_id INTO v_user FROM public.calendar_feed_tokens t
  WHERE t.token_hash = p_token_hash AND t.revoked_at IS NULL;
  IF v_user IS NULL THEN RETURN NULL; END IF;
  v_rel := public.together_active_relationship(v_user);
  IF v_rel IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('items', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'kind', i.item_kind, 'id', i.item_id, 'date', i.item_date,
      'starts_at', i.starts_at, 'ends_at', i.ends_at, 'all_day', i.all_day,
      'title', i.title, 'note', i.source_ref->>'note', 'location', i.source_ref->>'location_name',
      'recurring', coalesce(ce.rrule IS NOT NULL, false),
      'continuation', coalesce((i.source_ref->>'continuation')::boolean, false))
      ORDER BY i.item_date, i.starts_at NULLS FIRST, i.title)
    FROM public.together_items_for(v_user, v_rel, p_today - 30, p_today + 180) i
    LEFT JOIN public.couple_events ce ON i.item_kind = 'event' AND ce.id = i.item_id
    WHERE i.item_kind IN ('event', 'reminder', 'planning_date')
  ), '[]'::jsonb));
END;
$$;

-- Ending a couple (any path) ends both partners' links (R4, spec §3.8).
CREATE FUNCTION public.together_revoke_feeds_on_end() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (OLD.status = 'active' AND NEW.status <> 'active')
     OR (OLD.chat_archived_at IS NULL AND NEW.chat_archived_at IS NOT NULL) THEN
    UPDATE public.calendar_feed_tokens SET revoked_at = now()
    WHERE revoked_at IS NULL AND user_id IN (OLD.user_a, OLD.user_b);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trigger_together_revoke_feeds ON public.relationships;
CREATE TRIGGER trigger_together_revoke_feeds
  AFTER UPDATE OF status, chat_archived_at ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.together_revoke_feeds_on_end();

REVOKE ALL ON FUNCTION public.create_calendar_feed_token() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_calendar_feed() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_calendar_feed_status() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.together_calendar_feed(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_calendar_feed_token() TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_calendar_feed() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_calendar_feed_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.together_calendar_feed(text, date) TO service_role;
```

- [ ] **Step 5: Run every Together contract**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`
Expected: seven `PASS` lines. If the harness's stubs lack a `service_role` role, the `GRANT … TO service_role` line fails to apply. In that case, check `<scratchpad>/pg/stubs.sql`, add `CREATE ROLE service_role` there if it's missing (it's scratch), and record that in the ledger.

---

### Task 2: The ICS builder and the feed endpoint

**Files:**
- Create: `supabase/functions/calendar-feed/ics.ts`, `ics.test.ts`, `handler.ts`, `handler.test.ts`, `index.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- Consumes: `together_calendar_feed(p_token_hash)` (Task 1).
- Produces (`ics.ts`):
  - `type FeedItem`
  - `escapeText(s: string): string`
  - `foldLine(line: string): string`
  - `buildCalendar(items: FeedItem[], now: Date): string`
- Produces (`handler.ts`):
  - `tokenFromPath(pathname: string): string | null`
  - `sha256Hex(s: string): Promise<string>`
  - `handleFeedRequest(req: Request, fetchFeed: (hash: string) => Promise<{ items: FeedItem[] } | null>, now?: Date): Promise<Response>`
- The feed URL: `https://<project>.supabase.co/functions/v1/calendar-feed/<token>.ics`, or `webcal://` with the same host and path.

- [ ] **Step 1: Write the failing builder tests** (`ics.test.ts`)

```ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { buildCalendar, escapeText, type FeedItem, foldLine } from "./ics.ts";

const NOW = new Date("2026-11-01T10:00:00Z");
const base: FeedItem = {
  kind: "event", id: "e1", date: "2026-11-07", starts_at: null, ends_at: null,
  all_day: false, title: "Dinner", note: null, location: null, recurring: false, continuation: false,
};
const lines = (ics: string) => ics.replace(/\r\n /g, "").split("\r\n");

Deno.test("an empty feed is still a valid calendar with CRLF line ends", () => {
  const ics = buildCalendar([], NOW);
  assert(ics.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"));
  assert(ics.endsWith("END:VCALENDAR\r\n"));
  assertStringIncludes(ics, "X-WR-CALNAME:Together\r\n");
  assert(!/[^\r]\n/.test(ics), "bare LF found");
});

Deno.test("a timed event is in UTC with a stable id", () => {
  const ics = buildCalendar([{ ...base, starts_at: "2026-11-07T18:00:00+00:00", ends_at: "2026-11-07T20:00:00+00:00" }], NOW);
  const l = lines(ics);
  assert(l.includes("UID:event-e1@together.attune"));
  assert(l.includes("DTSTART:20261107T180000Z"));
  assert(l.includes("DTEND:20261107T200000Z"));
  assert(l.includes("DTSTAMP:20261101T100000Z"));
  assert(l.includes("SUMMARY:Dinner"));
});

Deno.test("a timed event with no end lasts an hour; its later days are skipped", () => {
  const ics = buildCalendar([
    { ...base, starts_at: "2026-11-07T23:00:00Z", ends_at: null },
    { ...base, date: "2026-11-08", starts_at: "2026-11-07T23:00:00Z", continuation: true },
  ], NOW);
  assertEquals(lines(ics).filter((x) => x === "BEGIN:VEVENT").length, 1);
  assert(lines(ics).includes("DTEND:20261108T000000Z"));
});

Deno.test("a multi-day all-day event is one entry; a daily repeat stays separate", () => {
  const trip = ["2026-11-07", "2026-11-08", "2026-11-09"].map((d) => ({ ...base, id: "trip", all_day: true, date: d }));
  const daily = ["2026-11-07", "2026-11-08"].map((d) => ({ ...base, id: "gym", all_day: true, date: d, recurring: true, title: "Busy" }));
  const l = lines(buildCalendar([...trip, ...daily], NOW));
  assert(l.includes("UID:event-trip@together.attune"));
  assert(l.includes("DTSTART;VALUE=DATE:20261107"));
  assert(l.includes("DTEND;VALUE=DATE:20261110"));
  assert(l.includes("UID:event-gym-20261107@together.attune"));
  assert(l.includes("UID:event-gym-20261108@together.attune"));
  assertEquals(l.filter((x) => x === "BEGIN:VEVENT").length, 3);
});

Deno.test("reminders and Planning dates don't block time", () => {
  const l = lines(buildCalendar([
    { ...base, kind: "reminder", id: "r1", all_day: true, title: "Kofi's birthday" },
    { ...base, kind: "planning_date", id: "p1", all_day: true, title: "Trip plan" },
  ], NOW));
  assert(l.includes("UID:reminder-r1-20261107@together.attune"));
  assert(l.includes("UID:planning-p1-20261107@together.attune"));
  assertEquals(l.filter((x) => x === "TRANSP:TRANSPARENT").length, 2);
});

Deno.test("text is escaped and long lines fold without splitting a character", () => {
  assertEquals(escapeText("a,b;c\\d\ne"), "a\\,b\\;c\\\\d\\ne");
  const long = "SUMMARY:" + "🎉".repeat(40);
  const folded = foldLine(long);
  for (const part of folded.split("\r\n")) {
    assert(new TextEncoder().encode(part).length <= 75, `line too long: ${part}`);
  }
  assertEquals(folded.replace(/\r\n /g, ""), long);
  const ics = buildCalendar([{ ...base, starts_at: "2026-11-07T18:00:00Z", title: "Dinner, at Buka; 7pm", note: "Bring cash\nand gift", location: "Osu, Accra" }], NOW);
  const l = lines(ics);
  assert(l.includes("SUMMARY:Dinner\\, at Buka\\; 7pm"));
  assert(l.includes("DESCRIPTION:Bring cash\\nand gift"));
  assert(l.includes("LOCATION:Osu\\, Accra"));
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `deno test --allow-read supabase/functions/calendar-feed/ics.test.ts`
Expected: FAIL with `Module not found "file:///…/ics.ts"`.

- [ ] **Step 3: Write `ics.ts`**

```ts
// RFC 5545 for the Together calendar feed (plan Phase 5 R1, R2). Pure: the
// edge function hands it the rows and the clock.

export type FeedItem = {
  kind: "event" | "reminder" | "planning_date";
  id: string;
  date: string; // YYYY-MM-DD: the day this row falls on
  starts_at: string | null;
  ends_at: string | null;
  all_day: boolean;
  title: string;
  note: string | null;
  location: string | null;
  recurring: boolean;
  continuation: boolean;
};

type VEvent = {
  uid: string;
  start: string; // property value incl. params, e.g. ";VALUE=DATE:20261107" or ":20261107T180000Z"
  end: string;
  title: string;
  note: string | null;
  location: string | null;
  transparent: boolean;
};

export function escapeText(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

// Lines over 75 octets fold with CRLF + space, never inside a character.
export function foldLine(line: string): string {
  const enc = new TextEncoder();
  const parts: string[] = [];
  let cur = "";
  let bytes = 0;
  let limit = 75;
  for (const ch of line) {
    const b = enc.encode(ch).length;
    if (bytes + b > limit) {
      parts.push(cur);
      cur = "";
      bytes = 0;
      limit = 74; // the leading space takes one octet
    }
    cur += ch;
    bytes += b;
  }
  parts.push(cur);
  return parts.join("\r\n ");
}

const utc = (d: Date) => d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const ymd = (date: string) => date.replaceAll("-", "");
function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
const prefix = (kind: FeedItem["kind"]) => kind === "planning_date" ? "planning" : kind;

function toEvents(items: FeedItem[]): VEvent[] {
  const out: VEvent[] = [];
  const allDayRuns = new Map<string, FeedItem[]>();
  for (const i of items) {
    if (!i.all_day) {
      if (i.continuation || !i.starts_at) continue;
      const start = new Date(i.starts_at);
      const end = i.ends_at ? new Date(i.ends_at) : new Date(start.getTime() + 3600_000);
      out.push({
        uid: i.recurring ? `event-${i.id}-${ymd(i.date)}` : `event-${i.id}`,
        start: `:${utc(start)}`,
        end: `:${utc(end)}`,
        title: i.title, note: i.note, location: i.location, transparent: false,
      });
      continue;
    }
    // One-off all-day items: consecutive days of the same item form one entry.
    const key = i.recurring || i.kind === "reminder" ? `${i.kind}:${i.id}:${i.date}` : `${i.kind}:${i.id}`;
    const run = allDayRuns.get(key) ?? [];
    run.push(i);
    allDayRuns.set(key, run);
  }
  for (const rows of allDayRuns.values()) {
    rows.sort((a, b) => a.date.localeCompare(b.date));
    let first = rows[0];
    let last = rows[0];
    const flush = () => {
      const oneOffEvent = first.kind === "event" && !first.recurring;
      out.push({
        uid: oneOffEvent
          ? `event-${first.id}`
          : `${prefix(first.kind)}-${first.id}-${ymd(first.date)}`,
        start: `;VALUE=DATE:${ymd(first.date)}`,
        end: `;VALUE=DATE:${ymd(addDays(last.date, 1))}`,
        title: first.title, note: first.note, location: first.location,
        transparent: first.kind !== "event",
      });
    };
    for (const r of rows.slice(1)) {
      if (r.date === addDays(last.date, 1)) {
        last = r;
      } else {
        flush();
        first = r;
        last = r;
      }
    }
    flush();
  }
  return out;
}

export function buildCalendar(items: FeedItem[], now: Date): string {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Attune//Together//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Together",
    "REFRESH-INTERVAL;VALUE=DURATION:PT6H",
    "X-PUBLISHED-TTL:PT6H",
  ];
  const stamp = utc(now);
  for (const e of toEvents(items)) {
    lines.push(
      "BEGIN:VEVENT",
      `UID:${e.uid}@together.attune`,
      `DTSTAMP:${stamp}`,
      `DTSTART${e.start}`,
      `DTEND${e.end}`,
      `SUMMARY:${escapeText(e.title)}`,
    );
    if (e.location) lines.push(`LOCATION:${escapeText(e.location)}`);
    if (e.note) lines.push(`DESCRIPTION:${escapeText(e.note)}`);
    lines.push(`TRANSP:${e.transparent ? "TRANSPARENT" : "OPAQUE"}`, "END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.map(foldLine).join("\r\n") + "\r\n";
}
```

- [ ] **Step 4: Run the builder tests**

Run: `deno test --allow-read supabase/functions/calendar-feed/ics.test.ts`
Expected: 6 passed.

- [ ] **Step 5: Write the failing handler tests** (`handler.test.ts`)

```ts
import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { handleFeedRequest, sha256Hex, tokenFromPath } from "./handler.ts";

const TOKEN = "a".repeat(64);
const url = (p: string) => `https://x.supabase.co/functions/v1/calendar-feed/${p}`;
const NOW = new Date("2026-11-01T10:00:00Z");

Deno.test("the token comes from the last path segment, with or without .ics", () => {
  assertEquals(tokenFromPath(`/calendar-feed/${TOKEN}.ics`), TOKEN);
  assertEquals(tokenFromPath(`/functions/v1/calendar-feed/${TOKEN}`), TOKEN);
  assertEquals(tokenFromPath("/calendar-feed/not-a-token.ics"), null);
  assertEquals(tokenFromPath("/calendar-feed/"), null);
});

Deno.test("sha256Hex matches Postgres's encode(sha256(...), 'hex')", async () => {
  assertEquals(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

Deno.test("bad, unknown and revoked links get the very same 404", async () => {
  const none = () => Promise.resolve(null);
  const responses = [
    await handleFeedRequest(new Request(url("short.ics")), none, NOW),
    await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), none, NOW),
    await handleFeedRequest(new Request(url(`${TOKEN}.ics`), { method: "POST" }), none, NOW),
  ];
  const bodies = await Promise.all(responses.map((r) => r.text()));
  for (const r of responses) assertEquals(r.status, 404);
  assertEquals(new Set(bodies).size, 1);
  assertEquals(new Set(responses.map((r) => r.headers.get("content-type"))).size, 1);
});

Deno.test("a live link gets the calendar, asking by the token's hash", async () => {
  let asked = "";
  const res = await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), (h) => {
    asked = h;
    return Promise.resolve({ items: [] });
  }, NOW);
  assertEquals(res.status, 200);
  assertEquals(asked, await sha256Hex(TOKEN));
  assert(res.headers.get("content-type")!.startsWith("text/calendar"));
  assert((await res.text()).startsWith("BEGIN:VCALENDAR"));
});

Deno.test("a server failure says try later, not 'no such link'", async () => {
  const res = await handleFeedRequest(new Request(url(`${TOKEN}.ics`)), () => Promise.reject(new Error("db down")), NOW);
  assertEquals(res.status, 503);
});
```

- [ ] **Step 6: Run them and watch them fail**

Run: `deno test --allow-read supabase/functions/calendar-feed/handler.test.ts`
Expected: FAIL with `Module not found "file:///…/handler.ts"`.

- [ ] **Step 7: Write `handler.ts` and `index.ts`**

`handler.ts`:

```ts
// The calendar-feed request path (plan Phase 5 R5): anything it can't serve
// gets one identical 404, so a link never reveals whether a couple exists.
import { buildCalendar, type FeedItem } from "./ics.ts";

export function tokenFromPath(pathname: string): string | null {
  const last = pathname.split("/").filter(Boolean).pop() ?? "";
  const token = last.endsWith(".ics") ? last.slice(0, -4) : last;
  return /^[0-9a-f]{64}$/.test(token) ? token : null;
}

export async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

const notFound = () =>
  new Response("Not found", {
    status: 404,
    headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
  });

export async function handleFeedRequest(
  req: Request,
  fetchFeed: (hash: string) => Promise<{ items: FeedItem[] } | null>,
  now: Date = new Date(),
): Promise<Response> {
  if (req.method !== "GET" && req.method !== "HEAD") return notFound();
  const token = tokenFromPath(new URL(req.url).pathname);
  if (!token) return notFound();
  let feed: { items: FeedItem[] } | null;
  try {
    feed = await fetchFeed(await sha256Hex(token));
  } catch (_) {
    return new Response("Try again later", {
      status: 503,
      headers: { "content-type": "text/plain; charset=utf-8", "retry-after": "3600" },
    });
  }
  if (!feed) return notFound();
  return new Response(req.method === "HEAD" ? null : buildCalendar(feed.items, now), {
    status: 200,
    headers: {
      "content-type": "text/calendar; charset=utf-8",
      "content-disposition": 'inline; filename="together.ics"',
      "cache-control": "private, max-age=900",
    },
  });
}
```

`index.ts`:

```ts
// Together calendar feed (spec §6.4). Public by design (verify_jwt = false):
// the 256-bit link token is the credential; only its hash reaches the DB.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleFeedRequest } from "./handler.ts";
import type { FeedItem } from "./ics.ts";

serve((req) =>
  handleFeedRequest(req, async (hash) => {
    const { data, error } = await serviceRoleClient().rpc("together_calendar_feed", {
      p_token_hash: hash,
    });
    if (error) throw error;
    return (data as { items: FeedItem[] } | null) ?? null;
  })
);
```

Append to `supabase/config.toml`:

```toml

[functions.calendar-feed]
verify_jwt = false
```

- [ ] **Step 8: Run the function tests and type-check**

Run: `deno test --allow-read supabase/functions/calendar-feed && deno check supabase/functions/calendar-feed/index.ts`
Expected: 11 passed; the type-check succeeds. If `deno check` can't fetch remote imports offline, record that in the ledger. The two test files cover `handler.ts` and `ics.ts`.

---

### Task 3: The link in Together settings

**Files:**
- Create: `lib/features/together/domain/calendar_feed.dart`
- Create: `lib/features/together/presentation/widgets/calendar_feed_sheet.dart`
- Modify: `lib/features/together/data/together_repository.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Modify: `lib/features/together/presentation/widgets/together_settings_sheet.dart`
- Test: `test/features/together/calendar_feed_test.dart` (new)

**Interfaces:**
- Consumes: the Task 1 RPC names.
- Produces:
  - `class CalendarFeedStatus { final bool active; final DateTime? since; factory CalendarFeedStatus.fromRow(Map<String, dynamic>) }`
  - `({String https, String webcal}) calendarFeedLinks(String supabaseUrl, String token)`
  - `TogetherRepository.createCalendarFeed() → Future<String>`, `revokeCalendarFeed() → Future<void>`, `getCalendarFeedStatus() → Future<CalendarFeedStatus>`
  - `togetherCalendarFeedProvider`: `FutureProvider.autoDispose<CalendarFeedStatus>`
  - `togetherSupabaseUrlProvider`: `Provider<String>`, defaulting to `Environment.supabaseUrl`
  - `Future<void> showCalendarFeedLinkSheet(BuildContext context, ({String https, String webcal}) links)`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/calendar_feed.dart';
import 'package:attune/features/together/domain/together_prefs.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/together_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<(FakeTogetherGateway, List<String>)> _open(
  WidgetTester t, {
  bool active = false,
}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final copied = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  var isActive = active;
  final g = FakeTogetherGateway({
    'get_together_prefs':
        (_) => {'daily_summary': true, 'care_nudges': true},
    'get_calendar_feed_status':
        (_) => [
          {
            'is_active': isActive,
            'since': isActive ? '2026-10-14T09:00:00Z' : null,
          },
        ],
    'create_calendar_feed_token': (_) {
      isActive = true;
      return _token;
    },
    'revoke_calendar_feed': (_) {
      isActive = false;
      return null;
    },
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherSupabaseUrlProvider.overrideWithValue(
          'https://abc.supabase.co',
        ),
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
  return (g, copied);
}

void main() {
  test('links point at the feed function, https and webcal', () {
    final l = calendarFeedLinks('https://abc.supabase.co/', _token);
    expect(
      l.https,
      'https://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    );
    expect(
      l.webcal,
      'webcal://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    );
    expect(
      CalendarFeedStatus.fromRow({'is_active': false, 'since': null}).active,
      isFalse,
    );
  });

  testWidgets('turning the link on shows it once, with copy and the caveats', (
    t,
  ) async {
    final (g, copied) = await _open(t);
    await t.tap(find.text('Show Together in my calendar app'));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'create_calendar_feed_token'), isTrue);
    expect(find.textContaining('every 12–24 hours'), findsOneWidget);
    expect(find.textContaining('Anyone with this link'), findsOneWidget);
    await t.tap(find.text('Copy link'));
    await t.pumpAndSettle();
    expect(copied, [
      'https://abc.supabase.co/functions/v1/calendar-feed/$_token.ics',
    ]);
  });

  testWidgets('when on: a new link replaces it; turning off asks first', (
    t,
  ) async {
    final (g, _) = await _open(t, active: true);
    expect(find.textContaining('On since'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Turn off'));
    await t.pumpAndSettle();
    expect(g.calls.any((c) => c.$1 == 'revoke_calendar_feed'), isTrue);
    expect(find.text('Show Together in my calendar app'), findsOneWidget);
  });
}
```

The prefs handler's shape must match what `TogetherRepository.getPrefs` expects. Check `test/features/together/together_settings_test.dart` for its fake row and copy it exactly; record any difference in the ledger.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/calendar_feed_test.dart`
Expected: a compile failure because `calendar_feed.dart` doesn't exist.

- [ ] **Step 3: Write `calendar_feed.dart`**

```dart
/// The private calendar link (Together Phase 5).
library;

class CalendarFeedStatus {
  const CalendarFeedStatus({required this.active, this.since});

  factory CalendarFeedStatus.fromRow(Map<String, dynamic> r) =>
      CalendarFeedStatus(
        active: r['is_active'] as bool? ?? false,
        since:
            r['since'] == null
                ? null
                : DateTime.parse(r['since'] as String).toLocal(),
      );

  final bool active;
  final DateTime? since;
}

/// The feed's address: https for Google ("From URL"), webcal to open Apple
/// Calendar straight to "Subscribe".
({String https, String webcal}) calendarFeedLinks(
  String supabaseUrl,
  String token,
) {
  final base = supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  final https = '$base/functions/v1/calendar-feed/$token.ics';
  return (https: https, webcal: https.replaceFirst(RegExp('^https?://'), 'webcal://'));
}
```

- [ ] **Step 4: Add the repository methods and providers**
  - In `TogetherRepository`, import `../domain/calendar_feed.dart` and add:

```dart
  // ── Calendar feed (Phase 5) ──

  /// A new private link; any older one stops working. Shown once.
  Future<String> createCalendarFeed() async =>
      await _call('create_calendar_feed_token', const {}) as String;

  Future<void> revokeCalendarFeed() => _call('revoke_calendar_feed', const {});

  Future<CalendarFeedStatus> getCalendarFeedStatus() async {
    final rows = await _call('get_calendar_feed_status', const {}) as List;
    return rows.isEmpty
        ? const CalendarFeedStatus(active: false)
        : CalendarFeedStatus.fromRow(Map<String, dynamic>.from(rows.first));
  }
```

  - In `together_providers.dart`, import `package:attune/core/config/env.dart` and `../domain/calendar_feed.dart`, and add:

```dart
/// The project URL the calendar link points at.
final togetherSupabaseUrlProvider = Provider<String>(
  (ref) => Environment.supabaseUrl,
);

final togetherCalendarFeedProvider =
    FutureProvider.autoDispose<CalendarFeedStatus>(
      (ref) => ref.watch(togetherRepositoryProvider).getCalendarFeedStatus(),
    );
```

- [ ] **Step 5: Write `calendar_feed_sheet.dart`**

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// The link, right after it's made (it can't be shown again: only its hash
/// is kept). Copy for Google; open for Apple Calendar.
Future<void> showCalendarFeedLinkSheet(
  BuildContext context,
  ({String https, String webcal}) links,
) => BottomSheetUtils.showDocumentationBottomSheet<void>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: _CalendarFeedLinkSheet(links: links),
);

class _CalendarFeedLinkSheet extends StatelessWidget {
  const _CalendarFeedLinkSheet({required this.links});
  final ({String https, String webcal}) links;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          const BottomSheetHeader(title: 'Your calendar link'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: SelectableText(
              links.https,
              maxLines: 3,
              style: text.bodySmall,
            ),
          ),
          Gap(Spacing.sm),
          InfoRowWidget(
            title: 'Copy link',
            subtitle: 'Google Calendar: Other calendars → From URL',
            icon: Icons.copy_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: links.https));
              if (context.mounted) context.showSuccessSnackbar('Link copied.');
            },
          ),
          AppDivider(),
          InfoRowWidget(
            title: 'Open in Calendar',
            subtitle: 'Apple Calendar subscribes straight away',
            icon: Icons.event_available_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () async {
              final ok = await launchUrl(Uri.parse(links.webcal));
              if (!ok && context.mounted) {
                context.showErrorSnackbar('No calendar app could open it.');
              }
            },
          ),
          Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Text(
              'Google refreshes subscribed calendars every 12–24 hours; Apple '
              'lets you choose how often. Anyone with this link can see your '
              'Together calendar, so share it with no one. You can turn it off '
              'or get a new link any time.',
              style: text.bodySmall,
            ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Add the section to the settings sheet** (`together_settings_sheet.dart`)

Watch `togetherCalendarFeedProvider` and keep a `bool _feedBusy = false;` state field. Add these methods to the state class:

```dart
  Future<void> _newLink() async {
    if (_feedBusy) return;
    setState(() => _feedBusy = true);
    try {
      final token =
          await ref.read(togetherRepositoryProvider).createCalendarFeed();
      ref.invalidate(togetherCalendarFeedProvider);
      if (!mounted) return;
      await showCalendarFeedLinkSheet(
        context,
        calendarFeedLinks(ref.read(togetherSupabaseUrlProvider), token),
      );
    } catch (_) {
      if (mounted) context.showErrorSnackbar('Could not do that. Please try again.');
    } finally {
      if (mounted) setState(() => _feedBusy = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Turn off your calendar link?'),
            content: const Text(
              'Your calendar app stops getting Together. The link stops working.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Keep it'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Turn off'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(togetherRepositoryProvider).revokeCalendarFeed();
      ref.invalidate(togetherCalendarFeedProvider);
    } catch (_) {
      if (mounted) context.showErrorSnackbar('Could not do that. Please try again.');
    }
  }
```

In `build`, before the final `Gap(Spacing.xl)`, add the section, keeping the existing rows:

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
              'Your calendar app',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (feed?.active ?? false) ...[
            InfoRowWidget(
              title: 'Together is in your calendar app',
              subtitle:
                  'On since ${DateFormat.MMMd().format(feed!.since ?? DateTime.now())}',
              icon: Icons.event_available_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
            ),
            AppDivider(),
            InfoRowWidget(
              title: 'Get a new link',
              subtitle: 'The old one stops working',
              icon: Icons.link_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _feedBusy ? null : _newLink,
            ),
            AppDivider(),
            InfoRowWidget(
              title: 'Turn off',
              subtitle: '',
              icon: Icons.link_off_rounded,
              iconColor: Theme.of(context).colorScheme.error,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _turnOff,
            ),
          ] else
            InfoRowWidget(
              title: 'Show Together in my calendar app',
              subtitle: 'Google, Apple or Outlook: a private link only you use',
              icon: Icons.calendar_month_outlined,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: _feedBusy ? null : _newLink,
            ),
```

Here `final feed = ref.watch(togetherCalendarFeedProvider).valueOrNull;`. Import `package:intl/intl.dart`, `../../domain/calendar_feed.dart` and `calendar_feed_sheet.dart`. Existing settings tests (`together_settings_test.dart`) need a `get_calendar_feed_status` handler returning `[{'is_active': false, 'since': null}]`. If they fail on the missing handler, add it and record that in the ledger.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 4: "Add to my calendar"

**Files:**
- Modify: `pubspec.yaml` (via `flutter pub add add_2_calendar:^3.0.1`), `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`
- Create: `lib/features/together/domain/calendar_export.dart`
- Create: `lib/features/together/data/calendar_exporter.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart`
- Test: `test/features/together/calendar_export_test.dart` (new) and `test/features/together/couple_event_sheet_test.dart` (extended)

**Interfaces:**
- Produces:
  - `enum ExportFrequency { daily, weekly, monthly, yearly }`
  - `class CalendarExport { String title; String? description; String? location; DateTime start; DateTime end; bool allDay; ExportFrequency? frequency; int interval; DateTime? until; bool onlyThisTime; }`
  - `CalendarExport? calendarExportFor(TogetherItem item, String? me)`, which returns null for anything that isn't an event and for a partner's masked busy event.
  - `abstract class CalendarExporter { Future<bool> add(CalendarExport e); }` and `class Add2CalendarExporter implements CalendarExporter`.
  - `calendarExporterProvider`: `Provider<CalendarExporter>`.

- [ ] **Step 1: Write the failing export tests** (`calendar_export_test.dart`)

```dart
import 'package:attune/features/together/domain/calendar_export.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _item({
  bool allDay = false,
  String? rrule,
  String visibility = 'shared',
  String createdBy = 'ama',
  String title = 'Dinner',
  Map<String, dynamic> extra = const {},
}) => TogetherItem.fromRow({
  'item_kind': 'event',
  'item_id': 'e1',
  'item_date': '2026-11-07',
  'starts_at': allDay ? null : '2026-11-07T18:00:00+00:00',
  'ends_at': allDay ? null : '2026-11-07T20:00:00+00:00',
  'all_day': allDay,
  'tz': allDay ? null : 'Africa/Accra',
  'title': title,
  'participant_ids': ['ama', 'kofi'],
  'owner_id': null,
  'created_by': createdBy,
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {
    'kind': 'event',
    'note': 'Bring cash',
    'location_name': 'Buka',
    if (rrule != null) 'rrule': rrule,
    ...extra,
  },
});

void main() {
  test('a one-off timed event exports as it is', () {
    final e = calendarExportFor(_item(), 'ama')!;
    expect([e.title, e.description, e.location, e.allDay], [
      'Dinner',
      'Bring cash',
      'Buka',
      false,
    ]);
    expect(e.start, DateTime.utc(2026, 11, 7, 18).toLocal());
    expect(e.end, DateTime.utc(2026, 11, 7, 20).toLocal());
    expect(e.frequency, isNull);
  });

  test('a multi-day all-day trip spans its days', () {
    final e =
        calendarExportFor(
          _item(
            allDay: true,
            extra: {'start_date': '2026-11-07', 'end_date': '2026-11-09'},
          ),
          'ama',
        )!;
    expect([e.allDay, e.start, e.end], [
      true,
      DateTime(2026, 11, 7),
      DateTime(2026, 11, 9),
    ]);
  });

  test('a repeating event carries its pattern and end', () {
    final e =
        calendarExportFor(
          _item(
            rrule: 'FREQ=WEEKLY;INTERVAL=2',
            extra: {'recurrence_until': '2027-06-30'},
          ),
          'ama',
        )!;
    expect([e.frequency, e.interval, e.until, e.onlyThisTime], [
      ExportFrequency.weekly,
      2,
      DateTime(2027, 6, 30),
      false,
    ]);
  });

  test('a weekday pattern exports this time only, and says so', () {
    final e =
        calendarExportFor(
          _item(rrule: 'FREQ=WEEKLY;BYDAY=FR,SA'),
          'ama',
        )!;
    expect([e.frequency, e.onlyThisTime], [null, true]);
  });

  test("a partner's busy-only event can't be exported; my own can", () {
    expect(
      calendarExportFor(
        _item(visibility: 'busy_only', createdBy: 'kofi', title: 'Busy'),
        'ama',
      ),
      isNull,
    );
    expect(
      calendarExportFor(_item(visibility: 'busy_only'), 'ama'),
      isNotNull,
    );
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/calendar_export_test.dart`
Expected: a compile failure because `calendar_export.dart` doesn't exist.

- [ ] **Step 3: Write `calendar_export.dart`**

```dart
/// What "Add to my calendar" hands the system editor (Together Phase 5 R6).
library;

import 'together_item.dart';

enum ExportFrequency { daily, weekly, monthly, yearly }

class CalendarExport {
  const CalendarExport({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.description,
    this.location,
    this.frequency,
    this.interval = 1,
    this.until,
    this.onlyThisTime = false,
  });

  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final ExportFrequency? frequency;
  final int interval;
  final DateTime? until;

  /// A pattern the system editor can't express ("Fri and Sat"): just this one.
  final bool onlyThisTime;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

CalendarExport? calendarExportFor(TogetherItem item, String? me) {
  if (item.kind != TogetherItemKind.event) return null;
  if (item.visibility == TogetherVisibility.busyOnly && item.createdBy != me) {
    return null;
  }
  final ref = item.sourceRef;
  final rrule = ref['rrule'] as String?;
  final freq = switch (RegExp(r'FREQ=([A-Z]+)').firstMatch(rrule ?? '')?.group(1)) {
    'DAILY' => ExportFrequency.daily,
    'WEEKLY' => ExportFrequency.weekly,
    'MONTHLY' => ExportFrequency.monthly,
    'YEARLY' => ExportFrequency.yearly,
    _ => null,
  };
  final byDay = rrule != null && rrule.contains('BYDAY');
  final interval =
      int.tryParse(
        RegExp(r'INTERVAL=(\d+)').firstMatch(rrule ?? '')?.group(1) ?? '',
      ) ??
      1;
  final DateTime start;
  final DateTime end;
  if (item.allDay) {
    start = rrule == null ? (_date(ref['start_date']) ?? item.day) : item.day;
    end = rrule == null ? (_date(ref['end_date']) ?? start) : start;
  } else {
    start = item.startsAt!;
    end = item.endsAt ?? start.add(const Duration(hours: 1));
  }
  return CalendarExport(
    title: item.title,
    description: ref['note'] as String?,
    location: ref['location_name'] as String?,
    start: start,
    end: end,
    allDay: item.allDay,
    frequency: byDay ? null : freq,
    interval: interval,
    until: byDay ? null : _date(ref['recurrence_until']),
    onlyThisTime: byDay,
  );
}
```

Check the `TogetherVisibility` enum's case names in `together_item.dart`. The plan assumes `busyOnly` for wire `'busy_only'`. Use the existing name, and record any difference in the ledger.

- [ ] **Step 4: Run the export tests**

Run: `flutter test test/features/together/calendar_export_test.dart`
Expected: 5 pass.

- [ ] **Step 5: Add the dependency and platform keys**
  - Run `flutter pub add add_2_calendar:^3.0.1`. Then open the resolved package's `lib/` (`~/.pub-cache/hosted/pub.dev/add_2_calendar-3.0.1/lib/`) and confirm the names `Event`, `Recurrence`, `Frequency`, `Add2Calendar.addEvent2Cal` and their parameters. The code below uses them; adjust to the real signatures and record any change in the ledger.
  - In `ios/Runner/Info.plist`, add inside the top-level `<dict>`, unless the key already exists:

```xml
	<key>NSCalendarsUsageDescription</key>
	<string>Attune adds Together events to your calendar when you ask it to.</string>
	<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
	<string>Attune adds Together events to your calendar when you ask it to.</string>
	<key>NSContactsUsageDescription</key>
	<string>Your calendar may ask about contacts when you add an event from Attune.</string>
```

  - In `AndroidManifest.xml`, inside the existing `<queries>` element, add:

```xml
        <intent>
            <action android:name="android.intent.action.INSERT" />
            <data android:mimeType="vnd.android.cursor.item/event" />
        </intent>
```

- [ ] **Step 6: Write `calendar_exporter.dart` and the provider**

```dart
import 'package:add_2_calendar/add_2_calendar.dart' as a2c;

import '../domain/calendar_export.dart';

/// Opens the phone's own "new event" editor, prefilled. No calendar read
/// permission is needed (spec §6.4).
abstract class CalendarExporter {
  Future<bool> add(CalendarExport e);
}

class Add2CalendarExporter implements CalendarExporter {
  const Add2CalendarExporter();

  @override
  Future<bool> add(CalendarExport e) => a2c.Add2Calendar.addEvent2Cal(
    a2c.Event(
      title: e.title,
      description: e.description,
      location: e.location,
      startDate: e.start,
      endDate: e.end,
      allDay: e.allDay,
      recurrence:
          e.frequency == null
              ? null
              : a2c.Recurrence(
                frequency: switch (e.frequency!) {
                  ExportFrequency.daily => a2c.Frequency.daily,
                  ExportFrequency.weekly => a2c.Frequency.weekly,
                  ExportFrequency.monthly => a2c.Frequency.monthly,
                  ExportFrequency.yearly => a2c.Frequency.yearly,
                },
                interval: e.interval,
                endDate: e.until,
              ),
    ),
  );
}
```

In `together_providers.dart`:

```dart
final calendarExporterProvider = Provider<CalendarExporter>(
  (ref) => const Add2CalendarExporter(),
);
```

Import `../data/calendar_exporter.dart`.

- [ ] **Step 7: Write the failing event-sheet test** (`couple_event_sheet_test.dart`)
  - Add `class _FakeExporter implements CalendarExporter { final added = <CalendarExport>[]; @override Future<bool> add(CalendarExport e) async { added.add(e); return true; } }`.
  - Give `_open` an optional `CalendarExporter? exporter` parameter. When it's non-null, add the override `calendarExporterProvider.overrideWithValue(exporter)`.

```dart
  testWidgets('a saved event can be added to my own calendar', (t) async {
    final exporter = _FakeExporter();
    await _open(t, item: _item(), exporter: exporter);
    await t.scrollUntilVisible(
      find.text('Add to my calendar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Add to my calendar'));
    await t.pumpAndSettle();
    expect(exporter.added.single.title, 'Dinner');
  });

  testWidgets("a partner's busy block has no Add to my calendar", (t) async {
    await _open(
      t,
      item: _item(
        createdBy: 'kofi',
        visibility: TogetherVisibility.busyOnly,
      ),
      exporter: _FakeExporter(),
    );
    expect(find.text('Add to my calendar'), findsNothing);
  });
```

Run: `flutter test test/features/together/couple_event_sheet_test.dart`
Expected: 2 failures (the texts aren't found).

- [ ] **Step 8: Add the row** (`couple_event_sheet.dart`). In `build`, compute `final export = item == null ? null : calendarExportFor(item, me);`. Add before the `memorable` block:

```dart
            if (export != null) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Add to my calendar',
                subtitle:
                    export.onlyThisTime
                        ? 'This time only: your calendar can’t repeat it the same way'
                        : 'Opens your calendar app, ready to save',
                icon: Icons.event_available_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: () async {
                  try {
                    await ref.read(calendarExporterProvider).add(export);
                  } catch (_) {
                    if (context.mounted) {
                      context.showErrorSnackbar(
                        'Your calendar app could not be opened.',
                      );
                    }
                  }
                },
              ),
            ],
```

Import `../../domain/calendar_export.dart`.

- [ ] **Step 9: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 5: Unlink safety and the app's read, end to end

**Files:**
- Test: `supabase/tests/together_feed_contracts.sql` (one more section)

**Interfaces:** none new.

- [ ] **Step 1: Add the failing check.** Re-pairing must not revive a link: after the relationship ends and a new one starts with the same partner, the old token stays dead. Insert before `ROLLBACK;`:

```sql
-- 5. Re-pairing doesn't revive an old link; a fresh one serves the new couple.
DO $$
DECLARE v_new text;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7f600000-0000-0000-0000-000000000002', '7f500000-0000-0000-0000-0000000000a1',
          '7f500000-0000-0000-0000-0000000000b2', 'active', now(), now());
  IF public.together_calendar_feed(pg_temp.h((SELECT token FROM t_tok WHERE name = 'ama')), '2026-11-01') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an old link came back with the new couple';
  END IF;
  PERFORM pg_temp.as_user('7f500000-0000-0000-0000-0000000000a1');
  v_new := public.create_calendar_feed_token();
  PERFORM set_config('request.jwt.claims', '', true);
  IF public.together_calendar_feed(pg_temp.h(v_new), '2026-11-01') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh link does not serve the new couple';
  END IF;
END $$;
```

- [ ] **Step 2: Run it.** This should already pass, because Task 1's trigger revoked the old token. If it passes the first time, mutate it to watch it bite: comment out the trigger's `UPDATE`, run, see `an old link came back`, then restore. Record the mutation in the ledger.

Run: `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`
Expected: seven `PASS` lines (with the trigger restored).

---

### Task 6: Spec rulings, previews, full suite

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-together-hub-design.md` (add §8.8 after §8.7)

- [ ] **Step 1: Add §8.8**

```markdown
### 8.8 Phase 5 rulings (plan `2026-10-14-together-phase5-export.md`)
- R1: The feed lists each occurrence over a rolling window (30 days back, 180 ahead) in UTC; no RRULE or VTIMEZONE. This keeps §5.5's promise that the app and the feed agree (supersedes "passes RRULEs through" in §6.4).
- R2: The feed has confirmed events, reminders and birthdays, and Planning dates; not moments, proposals or Planning to-dos. Reminders and Planning dates don't block time.
- R3: One live link per person; a new link revokes the old. Only the hash is stored, so a link is shown once.
- R4: The feed follows your current couple; ending it (any path) revokes both partners' links.
- R5: One identical 404 for anything the feed can't serve; server errors are 503.
- R6: "Add to my calendar" is on Together events; a weekday pattern exports that one time; a partner's busy block can't be exported.
- R7: Tokens are 244 random bits, stored as SHA-256.
```

- [ ] **Step 2: Golden previews (throwaway).** Render the settings sheet both off and on, the link sheet, and the event sheet with "Add to my calendar", all at 320pt width. Inspect them for overflow and spacing, then delete the preview test.

- [ ] **Step 3: Full verification**

Run:
- `flutter test`
- `flutter analyze lib/features/together`
- `deno test --allow-read supabase/functions/calendar-feed`
- `<scratchpad>/pg/run.sh supabase/tests/together_*contracts.sql`

Expected: everything passes.
