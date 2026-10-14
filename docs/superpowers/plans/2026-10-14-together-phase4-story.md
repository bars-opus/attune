# Together Phase 4: Story Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Together its "Remember" pillar:
- a conflict moment can be kept private;
- a lived event can be turned into a memory;
- "On this day" brings back earlier years;
- the full memories archive pages properly;
- each ritual collects its memories.

**Architecture:**
- **Server:** `timeline_events` gains `visibility` (conflicts only) and `couple_event_id`, which links a memory to the event it remembers. Everything the partner can read filters private conflicts out, as do Pulse and the verdict. New SECURITY DEFINER RPCs serve memory prompts, "On this day", ritual memories and a keyset-paged archive.
- **Client:** the Dart side adds a `together_story.dart` domain, repository methods and providers. The Together screen gets a memory prompt row in Today and an "On this day" block in Our story. It also gains a memories archive screen and a memories list in the ritual sheet. The moment form gets a "Just for me" switch for conflicts.

**Tech Stack:** Flutter 3.29, Riverpod 2, GoRouter, Supabase Postgres 17 (plpgsql, RLS), Deno edge functions.

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` (§3 rules 1, 2 and 5, §4.1 Our story, §4.4 "Add a memory", §6.3 Remember, D10, §8 Phase 4 row).

## Global Constraints

- No scorecards: no RPC returns per-user counts or aggregates of who did what (§3.1).
- No progress gamification: no streaks, counters or "N memories" badges (§3.2, D8). Ritual memories are a plain list.
- Conflict moments never notify the partner, and a private conflict is never readable by the partner (§3.5).
- The memory prompt is in-app only, never a push (§6.3).
- "On this day" excludes conflicts (§4.1, §6.3).
- Errors from Together RPCs are raised as `together:<code>`, through `public.together_fail(code)`.
- Every SECURITY DEFINER function sets `search_path = public` and checks membership through `public.together_actor(relationship_id)`.
- All migrations from `20261014100000` on are undeployed, so editing them in place is allowed and must be recorded in the ledger.
- Owner rules:
  - work on `main`;
  - write each test first and watch it fail;
  - commit nothing unless the owner asks;
  - re-read a file before editing it, because the owner edits by hand;
  - make surgical changes.
- UI: reuse `InfoRowWidget`, `TogetherSection`, `BottomSheetHeader`, `SchimmerSkeleton` and `EmptyStateWidget`. No overflow at 320pt width.

### Rulings this plan makes (record them in spec §8.7 in Task 9)

- **R1: Private conflicts are left out of Pulse and the verdict entirely.**
  - D10 says a private conflict "still feeds its logger's own Pulse". But `pulse_scores` is one row per couple per week, read by both partners (compute-pulse reads relationship-wide), so a private conflict feeding it would leak through the shared score.
  - Rule §3.5 outranks D10.
  - Cost if wrong: a per-user Pulse would be a separate project.
- **R2: A memory is a line of text; photos wait.** Moments have no media column, and Planning's storage write policy only accepts `planning_entries` paths. Cost if wrong: a later "add a photo" task (a column, a bucket policy, and a `MomentCard` image).
- **R3: The link lives on the moment.**
  - `timeline_events.couple_event_id` lets each partner add their own memory of the same event.
  - The unused `couple_events.memory_event_id` is dropped in place from `20261014110000`; it was also a circular foreign key.
  - Cost if wrong: none while undeployed.
- **R4: Memory prompts.** An event gets a prompt when all of these hold:
  - confirmed, `shared` and non-recurring;
  - both partners are in it;
  - I'm one of them;
  - it ended within the last 3 days, judged in my device zone for all-day events;
  - I haven't added a memory of it or tapped "Not now" on it.

  Today shows one prompt at a time, and "Not now" hides it for good, for me only. Cost if wrong: copy and window tweaks.
- **R5: Memory moments are `highlight` moments.**
  - The title is the event's title, cut to 80 characters.
  - `occurred_at` is the event's own local day.
  - There's no new `event_type`, so Pulse, verdict, partner push and Dart displays are unchanged.
  - Cost if wrong: a new type plus display mapping.
- **R6: "On this day".**
  - Items: moments other than conflicts that I can see, plus confirmed, shared, non-recurring events from earlier years that don't already have a memory visible to me.
  - Dates: the same month and day; Feb 29 items show on Feb 28 in non-leap years.
  - Limit: newest first, up to 5.
  - Today's date: the client sends its local date.
- **R7: Only conflicts can be private** (a CHECK constraint).
  - The default stays `shared`, today's behaviour.
  - A private conflict still bumps the couple's change signal. That's a contentless refetch ping; the refetch returns nothing new to the partner.
- **R8: The archive pages by keyset** on `(occurred_at DESC, id DESC)` through `list_together_moments`, 30 per page.
- **R9: The ritual sheet lists that ritual's memories**: the moments linked to its weeks, newest 20, with no count.
- **R10: Migration order.**
  - The visibility column goes in a new `20261014100500` migration, so that `20261014100300` (verdict) and `20261014110200` (`list_together_items`), which are edited in place, run after it.
  - `couple_event_id` goes in `20261014150000`, after `couple_events` exists.

## Review Focus

1. **A partner's private conflict must not show up anywhere for the partner:** the month view (a direct table select under RLS), `list_together_items`, "On this day", the archive or ritual memories. Pinned in the Task 1 and Task 3 contracts.
2. **Editing a private conflict keeps it private.** The edit screen gets the current visibility through `initialData`. Pinned in Task 4.
3. **All-day and cross-zone events get their prompt in the viewer's zone**, not UTC: an Accra all-day event seen from Toronto. Pinned in the Task 3 contract.
4. **After I add a memory, my prompt goes away but my partner's stays**, and adding to a deleted, cancelled or private event fails with `not_found`. Pinned in the Task 3 contract.
5. **Archive pages don't skip or repeat moments that share a date.** Pinned in the Task 3 contract (three moments on one day, page size 2).

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `supabase/migrations/20261014100500_timeline_conflict_visibility.sql` | Create | Visibility column, CHECK, read policy |
| `supabase/migrations/20261014100300_verdict_exclude_deleted_moments.sql` | Modify (in place) | Verdict eligibility counts shared moments only |
| `supabase/migrations/20261014110200_list_together_items.sql` | Modify (in place) | Moment branch: private only for its logger |
| `supabase/migrations/20261014110000_couple_events.sql` | Modify (in place) | Drop `memory_event_id` |
| `supabase/migrations/20261014150000_together_story.sql` | Create | `couple_event_id`, dismissals, story RPCs |
| `supabase/tests/together_story_contracts.sql` | Create | Contracts for Tasks 1 and 3 |
| `supabase/functions/compute-pulse/index.ts` | Modify | Read shared moments only |
| `supabase/functions/compute-pulse/private_conflicts.test.ts` | Create | Source test |
| `supabase/functions/generate-verdict/index.ts` | Modify | Read shared moments only |
| `supabase/functions/generate-verdict/private_conflicts.test.ts` | Create | Source test |
| `lib/features/timeline/data/models/timeline_event_model.dart` | Modify | `visibility`, `coupleEventId`, `isPrivate` |
| `lib/features/timeline/data/repositories/timeline_repository.dart` | Modify | Send `visibility` |
| `lib/features/timeline/presentation/providers/timeline_providers.dart` | Modify | `visibility` in the create and update records |
| `lib/features/timeline/presentation/screens/log_moment_details_screen.dart` | Modify | "Just for me" switch for conflicts |
| `lib/features/timeline/presentation/widgets/moment_card.dart` | Modify | Lock line; pass visibility when editing |
| `lib/features/together/domain/together_story.dart` | Create | `MemoryPrompt`, `OnThisDayItem`, `RitualMemory` |
| `lib/features/together/data/together_repository.dart` | Modify | Story RPC methods |
| `lib/features/together/presentation/together_providers.dart` | Modify | Story providers |
| `lib/features/together/presentation/widgets/memory_sheets.dart` | Create | Add-a-memory sheet, prompt question copy |
| `lib/features/together/presentation/screens/together_screen.dart` | Modify | Prompt row in Today, "On this day", archive entry |
| `lib/features/together/presentation/widgets/couple_event_sheet.dart` | Modify | "Add a memory" on a past shared event |
| `lib/features/together/presentation/screens/together_memories_screen.dart` | Create | Paged archive |
| `lib/features/together/presentation/widgets/ritual_sheets.dart` | Modify | Memories list in the manage sheet |
| `docs/superpowers/specs/2026-10-14-together-hub-design.md` | Modify | §8.7 rulings; D10 note |

Harness:
- **Local PG17 harness (Docker is down):**
  - `pg_ctl -D <scratchpad>/pg/data -o "-p 55432 -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" start`
  - then `<scratchpad>/pg/run.sh <contract files…>`, which applies the stubs and all migrations and prints `PASS`/`FAIL` per file.
- **Deno source tests:** `deno test --allow-read <file>`.

---

### Task 1: Private conflicts on the server

**Files:**
- Create: `supabase/migrations/20261014100500_timeline_conflict_visibility.sql`
- Modify (in place): `supabase/migrations/20261014100300_verdict_exclude_deleted_moments.sql` (both eligibility subqueries, around lines 86–108)
- Modify (in place): `supabase/migrations/20261014110200_list_together_items.sql` (moment branch, around lines 102–111)
- Test: `supabase/tests/together_story_contracts.sql`

**Interfaces:**
- Produces: `timeline_events.visibility text NOT NULL DEFAULT 'shared'` with values `shared` and `private`; `private` is allowed only for `event_type = 'conflict'`.
- Produces: `list_together_items` moment rows carry `visibility = te.visibility`, and a private row is returned only to its logger.

- [ ] **Step 1: Write the failing contract** (create the file with the fixtures and section 1)

```sql
-- Together Phase 4 contracts: the story layer. Every check RAISEs on violation.
BEGIN;
INSERT INTO auth.users (id) VALUES ('7f300000-0000-0000-0000-0000000000a1'), ('7f300000-0000-0000-0000-0000000000b2'), ('7f300000-0000-0000-0000-0000000000c3') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('7f300000-0000-0000-0000-0000000000a1', '+233310000001', 'Ama'),
  ('7f300000-0000-0000-0000-0000000000b2', '+233310000002', 'Kofi'),
  ('7f300000-0000-0000-0000-0000000000c3', '+233310000003', 'Stranger') ON CONFLICT (id) DO NOTHING;
INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
        '7f300000-0000-0000-0000-0000000000b2', 'active', now(), now()) ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE t_ids (name text PRIMARY KEY, id uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true) $$;

-- 1. A private conflict is its logger's alone: the table, the hub read, the verdict.
DO $$
DECLARE v_priv uuid; v_n int; v_def text;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
          'conflict', 'Money talk', '2026-10-10', 'private') RETURNING id INTO v_priv;
  INSERT INTO t_ids VALUES ('priv', v_priv);

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.timeline_events WHERE id = v_priv;
  RESET ROLE;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: partner can read a private conflict'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7f400000-0000-0000-0000-000000000001', '2026-10-01', '2026-10-31')
  WHERE item_id = v_priv;
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: hub read leaks a private conflict'; END IF;

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_n FROM public.timeline_events WHERE id = v_priv;
  RESET ROLE;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: logger cannot read their private conflict'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_items('7f400000-0000-0000-0000-000000000001', '2026-10-01', '2026-10-31')
  WHERE item_id = v_priv AND visibility = 'private';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: logger hub read lost the private conflict'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);

  BEGIN
    INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility)
    VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1',
            'highlight', 'Beach', '2026-10-11', 'private');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a private highlight was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  SELECT pg_get_functiondef('public.request_verdict_generation(uuid)'::regprocedure) INTO v_def;
  SELECT count(*) INTO v_n FROM regexp_matches(v_def, 'te\.visibility = ''shared''', 'g');
  IF v_n < 2 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: verdict eligibility counts private moments (% filters)', v_n; END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it and watch it fail**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_story_contracts.sql`
Expected: FAIL with `column "visibility" of relation "timeline_events" does not exist`.

- [ ] **Step 3: Write the migration**

```sql
-- Together Phase 4: a conflict moment can be kept private (spec §6.3, §3.5;
-- plan R1, R7). Only conflicts can be private; the default is shared.
ALTER TABLE public.timeline_events
  ADD COLUMN visibility text NOT NULL DEFAULT 'shared'
    CHECK (visibility IN ('shared', 'private')),
  ADD CONSTRAINT timeline_events_private_conflicts_only
    CHECK (visibility = 'shared' OR event_type = 'conflict');

-- Both partners read shared, non-deleted moments; a private one only its logger.
DROP POLICY IF EXISTS timeline_relationship_members ON public.timeline_events;
CREATE POLICY timeline_relationship_members
ON public.timeline_events FOR SELECT TO authenticated
USING (
  deleted_at IS NULL
  AND (visibility = 'shared' OR logged_by = auth.uid())
  AND relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);
```

- [ ] **Step 4: Edit `request_verdict_generation` in place** (`20261014100300`). In both eligibility subqueries, add one line directly after `AND te.deleted_at IS NULL`:

```sql
      AND te.visibility = 'shared'
```

- [ ] **Step 5: Edit the `list_together_items` moment branch in place** (`20261014110200`). Replace the branch's `'shared'::text, 'confirmed'::text,` line with `te.visibility, 'confirmed'::text,`, and its `WHERE` with:

```sql
  WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
    AND te.occurred_at BETWEEN p_start AND p_end
    -- A private conflict is its logger's alone (Phase 4 R7).
    AND (te.visibility = 'shared' OR te.logged_by = v_actor)
```

- [ ] **Step 6: Run the contracts**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_phase0_contracts.sql supabase/tests/together_events_contracts.sql supabase/tests/together_proposals_contracts.sql supabase/tests/together_daily_contracts.sql supabase/tests/together_rituals_contracts.sql supabase/tests/together_story_contracts.sql`
Expected: six `PASS` lines.

- [ ] **Step 7: Ledger.** Record that `100300` and `110200` were edited in place (R10).

---

### Task 2: Pulse and verdict read shared moments only

**Files:**
- Modify: `supabase/functions/compute-pulse/index.ts` (the `timeline_events` query, around lines 106–111)
- Modify: `supabase/functions/generate-verdict/index.ts` (the `timeline_events` query, around lines 292–300)
- Create: `supabase/functions/compute-pulse/private_conflicts.test.ts`
- Create: `supabase/functions/generate-verdict/private_conflicts.test.ts`

**Interfaces:**
- Consumes: `timeline_events.visibility` (Task 1).

- [ ] **Step 1: Write both failing source tests**

`supabase/functions/compute-pulse/private_conflicts.test.ts`:

```ts
// Pulse is one score per couple that both partners read, so a private
// conflict must not feed it (Together plan Phase 4 R1). The function runs
// as the service role, so the query has to filter for itself.

import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("compute-pulse reads only shared moments", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const query = source.slice(source.indexOf(".from('timeline_events')"));
  const statement = query.slice(0, query.indexOf("// 2."));
  assertMatch(statement, /\.eq\('visibility', 'shared'\)/);
});
```

`supabase/functions/generate-verdict/private_conflicts.test.ts`:

```ts
// The verdict is shared by the couple, so a private conflict is never
// evidence (Together spec §3.5, plan Phase 4 R1).

import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

Deno.test("generate-verdict reads only shared moments", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );
  const query = source.slice(source.indexOf('.from("timeline_events")'));
  const statement = query.slice(0, query.indexOf(";"));
  assertMatch(statement, /\.eq\("visibility", "shared"\)/);
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `deno test --allow-read supabase/functions/compute-pulse/private_conflicts.test.ts supabase/functions/generate-verdict/private_conflicts.test.ts`
Expected: 2 failed (`Expected actual ... to match`).

- [ ] **Step 3: Add the filters.** In compute-pulse, directly after `.eq('relationship_id', relationshipId)` in the `timeline_events` query:

```ts
    // A private conflict never feeds the couple's shared score (Phase 4 R1).
    .eq('visibility', 'shared')
```

In generate-verdict, directly after `.eq("relationship_id", job.relationship_id)` in the `timeline_events` query:

```ts
    .eq("visibility", "shared")
```

- [ ] **Step 4: Run all function tests in both folders**

Run: `deno test --allow-read supabase/functions/compute-pulse supabase/functions/generate-verdict`
Expected: all pass. That includes the existing `deleted_moments.test.ts`, which still finds `.is("deleted_at", null)` before the `;`. If `compute-pulse/index.test.ts` needs network or env access and errors for that reason only, record it in the ledger and run the two new files plus `deleted_moments.test.ts`.

---

### Task 3: Story RPCs on the server

**Files:**
- Modify (in place): `supabase/migrations/20261014110000_couple_events.sql`. Delete the line `memory_event_id uuid REFERENCES public.timeline_events(id) ON DELETE SET NULL,`.
- Create: `supabase/migrations/20261014150000_together_story.sql`
- Test: `supabase/tests/together_story_contracts.sql` (add sections 2–6 before `ROLLBACK;`)

**Interfaces:**
- Produces (all `GRANT EXECUTE … TO authenticated`):
  - `add_event_memory(p_event_id uuid, p_line text) RETURNS uuid`. Returns the new moment's id.
  - `dismiss_memory_prompt(p_event_id uuid) RETURNS void`.
  - `list_together_memory_prompts(p_relationship_id uuid, p_tz text, p_now timestamptz DEFAULT now())` returns `TABLE (event_id uuid, title text, event_day date, ended_at timestamptz, ritual_id uuid)`, newest first, at most 3.
  - `list_together_on_this_day(p_relationship_id uuid, p_today date)` returns `TABLE (item_kind text, item_id uuid, item_date date, title text, note text, event_type text, years_ago int)`. `item_kind` is `'moment'` or `'event'`; at most 5.
  - `list_together_ritual_memories(p_ritual_id uuid)` returns `TABLE (moment_id uuid, occurred_at date, title text, note text, logged_by uuid)`, newest first, at most 20.
  - `list_together_moments(p_relationship_id uuid, p_before_date date DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit int DEFAULT 30) RETURNS SETOF public.timeline_events`.
- Produces: `timeline_events.couple_event_id uuid NULL`, which references `couple_events`.

- [ ] **Step 1: Write the failing contract sections** (insert before `ROLLBACK;`)

```sql
-- Story fixtures (dated in the past: a memory needs an event that has begun
-- by the real clock): a lived shared dinner (Accra, timed), a Toronto-zoned all-day
-- picnic, and a private event.
DO $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Dinner at Buka', false,
          '2026-10-03T18:00:00Z', '2026-10-03T20:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[])
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('dinner', v);
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, start_date, participant_ids)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'Picnic', true, '2026-10-04',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[])
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('picnic', v);
  INSERT INTO public.couple_events (relationship_id, created_by, title, all_day, starts_at, ends_at, tz, participant_ids, visibility)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Ring shopping', false,
          '2026-10-03T10:00:00Z', '2026-10-03T11:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1']::uuid[], 'private')
  RETURNING id INTO v; INSERT INTO t_ids VALUES ('secret', v);
END $$;

-- 2. Prompts: after the dinner ends, both get one; not before, not after 3 days;
--    an all-day picnic ends at midnight in the viewer's zone (Review Focus 3).
DO $$
DECLARE v_n int;
BEGIN
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T19:00:00Z');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt before the event ended'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no prompt after the dinner'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-07T21:00:00Z');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt older than 3 days'; END IF;
  -- Picnic on Oct 4: over at Oct 5 00:00 Toronto (EDT) = 04:00Z; not yet at 03:00Z.
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'America/Toronto', '2026-10-05T03:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'picnic');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: all-day prompt used UTC, not the viewer zone'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'America/Toronto', '2026-10-05T05:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'picnic');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: no all-day prompt after its day'; END IF;
  -- a private event never prompts (not both of us)
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'secret');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: private event prompted'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 3. Adding a memory: a highlight linked to the event on its local day; my prompt
--    goes, my partner's stays; bad lines and hidden events refused (Review Focus 4).
DO $$
DECLARE v_m uuid; v_type text; v_day date; v_link uuid; v_n int; v_msg text;
BEGIN
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  v_m := public.add_event_memory((SELECT id FROM t_ids WHERE name = 'dinner'), '  The jollof was perfect  ');
  INSERT INTO t_ids VALUES ('memory', v_m);
  SELECT event_type, occurred_at, couple_event_id INTO v_type, v_day, v_link FROM public.timeline_events WHERE id = v_m;
  IF v_type <> 'highlight' OR v_day <> '2026-10-03' OR v_link <> (SELECT id FROM t_ids WHERE name = 'dinner') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: memory saved as % on % linked %', v_type, v_day, v_link;
  END IF;
  IF (SELECT note FROM public.timeline_events WHERE id = v_m) <> 'The jollof was perfect' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: memory line not trimmed';
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: prompt stayed after I added a memory'; END IF;
  BEGIN
    PERFORM public.add_event_memory((SELECT id FROM t_ids WHERE name = 'dinner'), '   ');
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank memory accepted';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:invalid_input' THEN RAISE; END IF;
  END;

  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: my memory removed my partner''s prompt'; END IF;
  BEGIN
    PERFORM public.add_event_memory((SELECT id FROM t_ids WHERE name = 'secret'), 'peek');
    RAISE EXCEPTION 'CONTRACT VIOLATED: partner added a memory to a private event';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  -- "Not now" hides it for good, for me only
  PERFORM public.dismiss_memory_prompt((SELECT id FROM t_ids WHERE name = 'dinner'));
  SELECT count(*) INTO v_n FROM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'Africa/Accra', '2026-10-03T21:00:00Z')
  WHERE event_id = (SELECT id FROM t_ids WHERE name = 'dinner');
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: dismissed prompt came back'; END IF;
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000c3');
  BEGIN
    PERFORM public.list_together_memory_prompts('7f400000-0000-0000-0000-000000000001', 'UTC');
    RAISE EXCEPTION 'CONTRACT VIOLATED: stranger read prompts';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'together:not_found' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 4. On this day: earlier years, same day; no conflicts; no private conflict of my
--    partner's; an event with a memory shows once (as the memory); Feb 29 on Feb 28.
DO $$
DECLARE v_n int; v_kinds text[];
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'first', 'First date', '2024-10-03'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'conflict', 'Big fight', '2025-10-03'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'highlight', 'Leap day', '2024-02-29');
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at, visibility) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000b2', 'conflict', 'Kofi private', '2025-10-03', 'private');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT array_agg(item_kind || ':' || title ORDER BY item_date DESC, title) INTO v_kinds
  FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-10-03');
  IF v_kinds IS DISTINCT FROM ARRAY['moment:Dinner at Buka', 'moment:First date'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: on this day returned %', v_kinds;
  END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-10-03')
  WHERE title = 'First date' AND years_ago = 3;
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: years_ago wrong'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2026-10-03');
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: this year''s items counted as on-this-day (%)', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2027-02-28')
  WHERE title = 'Leap day';
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 not shown on Feb 28 of a common year'; END IF;
  SELECT count(*) INTO v_n FROM public.list_together_on_this_day('7f400000-0000-0000-0000-000000000001', '2028-02-28')
  WHERE title = 'Leap day';
  IF v_n <> 0 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: Feb 29 shown on Feb 28 of a leap year'; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 5. Ritual memories: moments on that ritual's weeks only; partner's private never.
DO $$
DECLARE v_rit uuid; v_ev uuid; v_n int;
BEGIN
  INSERT INTO public.couple_rituals (relationship_id, created_by, title, cadence, weekday, local_time, duration_min, tz, status)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'Date night', 'weekly', 6,
          '19:00', 120, 'Africa/Accra', 'active') RETURNING id INTO v_rit;
  INSERT INTO public.couple_events (relationship_id, created_by, kind, title, all_day, starts_at, ends_at, tz, participant_ids, ritual_id, ritual_date)
  VALUES ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'ritual_occurrence', 'Date night', false,
          '2026-10-03T19:00:00Z', '2026-10-03T21:00:00Z', 'Africa/Accra',
          ARRAY['7f300000-0000-0000-0000-0000000000a1','7f300000-0000-0000-0000-0000000000b2']::uuid[], v_rit, '2026-10-03')
  RETURNING id INTO v_ev;
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  PERFORM public.add_event_memory(v_ev, 'Dancing after');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000a1');
  SELECT count(*) INTO v_n FROM public.list_together_ritual_memories(v_rit);
  IF v_n <> 1 THEN RAISE EXCEPTION 'CONTRACT VIOLATED: ritual memories %', v_n; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- 6. Archive pages: no skips or repeats across same-day ties; private stays private
--    (Review Focus 1, 5).
DO $$
DECLARE r record; v_seen uuid[] := '{}'; v_date date; v_id uuid; v_pages int := 0; v_total int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at) VALUES
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 1', '2026-09-01'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 2', '2026-09-01'),
    ('7f400000-0000-0000-0000-000000000001', '7f300000-0000-0000-0000-0000000000a1', 'highlight', 'Tie 3', '2026-09-01');
  PERFORM pg_temp.as_user('7f300000-0000-0000-0000-0000000000b2');
  LOOP
    v_pages := v_pages + 1;
    EXIT WHEN v_pages > 50;
    v_total := 0;
    FOR r IN SELECT * FROM public.list_together_moments('7f400000-0000-0000-0000-000000000001', v_date, v_id, 2) LOOP
      IF r.id = ANY (v_seen) THEN RAISE EXCEPTION 'CONTRACT VIOLATED: archive repeated %', r.title; END IF;
      IF r.visibility = 'private' AND r.logged_by <> '7f300000-0000-0000-0000-0000000000b2' THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: archive leaked a private conflict';
      END IF;
      v_seen := v_seen || r.id; v_date := r.occurred_at; v_id := r.id; v_total := v_total + 1;
    END LOOP;
    EXIT WHEN v_total < 2;
  END LOOP;
  IF cardinality(v_seen) <> (SELECT count(*) FROM public.timeline_events
      WHERE relationship_id = '7f400000-0000-0000-0000-000000000001' AND deleted_at IS NULL
        AND (visibility = 'shared' OR logged_by = '7f300000-0000-0000-0000-0000000000b2')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: archive skipped moments (% seen)', cardinality(v_seen);
  END IF;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
```

- [ ] **Step 2: Run it and watch it fail**

Run: `<scratchpad>/pg/run.sh supabase/tests/together_story_contracts.sql`
Expected: FAIL with `function public.list_together_memory_prompts(...) does not exist`.

- [ ] **Step 3: Write the migration** `supabase/migrations/20261014150000_together_story.sql`

```sql
-- Together Phase 4: the story layer (spec §6.3; plan R2–R9).

-- A memory points at the event it remembers; each partner can add their own (R3).
ALTER TABLE public.timeline_events
  ADD COLUMN couple_event_id uuid REFERENCES public.couple_events(id) ON DELETE SET NULL;
CREATE INDEX idx_timeline_couple_event ON public.timeline_events (couple_event_id)
  WHERE couple_event_id IS NOT NULL AND deleted_at IS NULL;

-- "Not now" on a memory prompt: per person, for good (R4).
CREATE TABLE public.together_memory_dismissals (
  event_id uuid NOT NULL REFERENCES public.couple_events(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.together_memory_dismissals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.together_memory_dismissals FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.together_safe_tz(p_tz text) RETURNS text
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz) THEN p_tz ELSE 'UTC' END
$$;

-- The day an event happened, in its own zone.
CREATE FUNCTION public.together_event_day(e public.couple_events) RETURNS date
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN e.all_day THEN e.start_date ELSE (e.starts_at AT TIME ZONE e.tz)::date END
$$;

-- When an event is over: timed → its end (or an hour after it starts);
-- all-day → midnight after its last day, in the viewer's zone.
CREATE FUNCTION public.together_event_end(e public.couple_events, p_tz text) RETURNS timestamptz
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE WHEN e.all_day
    THEN (coalesce(e.end_date, e.start_date) + 1)::timestamp AT TIME ZONE p_tz
    ELSE coalesce(e.ends_at, e.starts_at + interval '1 hour') END
$$;
REVOKE ALL ON FUNCTION public.together_safe_tz(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_event_day(public.couple_events) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.together_event_end(public.couple_events, text) FROM PUBLIC, anon, authenticated;

-- A lived, shared event of both of ours that I'm in (R4).
CREATE FUNCTION public.together_memorable(e public.couple_events, p_me uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT e.deleted_at IS NULL AND e.status = 'confirmed' AND e.visibility = 'shared'
     AND e.rrule IS NULL AND cardinality(e.participant_ids) = 2 AND p_me = ANY (e.participant_ids)
$$;
REVOKE ALL ON FUNCTION public.together_memorable(public.couple_events, uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.add_event_memory(p_event_id uuid, p_line text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events; v_me uuid; v_line text := btrim(p_line); v_id uuid;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_me := public.together_actor(v.relationship_id);
  IF v.status <> 'confirmed' OR v.visibility <> 'shared' OR NOT (v_me = ANY (v.participant_ids)) THEN
    PERFORM public.together_fail('not_found');
  END IF;
  -- A memory is of something that has begun (a day's grace for all-day across zones).
  IF (v.all_day AND v.start_date > current_date + 1) OR (NOT v.all_day AND v.starts_at > now()) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  IF v_line IS NULL OR v_line = '' OR char_length(v_line) > 300 THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, note, occurred_at, couple_event_id)
  VALUES (v.relationship_id, v_me, 'highlight', left(btrim(v.title), 80), v_line,
          public.together_event_day(v), v.id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION public.dismiss_memory_prompt(p_event_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.couple_events; v_me uuid;
BEGIN
  SELECT * INTO v FROM public.couple_events WHERE id = p_event_id AND deleted_at IS NULL;
  IF NOT FOUND THEN PERFORM public.together_fail('not_found'); END IF;
  v_me := public.together_actor(v.relationship_id);
  IF NOT (v_me = ANY (v.participant_ids)) THEN PERFORM public.together_fail('not_found'); END IF;
  INSERT INTO public.together_memory_dismissals (event_id, user_id) VALUES (v.id, v_me)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE FUNCTION public.list_together_memory_prompts(p_relationship_id uuid, p_tz text, p_now timestamptz DEFAULT now())
RETURNS TABLE (event_id uuid, title text, event_day date, ended_at timestamptz, ritual_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v_me uuid := public.together_actor(p_relationship_id); v_tz text := public.together_safe_tz(p_tz);
BEGIN
  RETURN QUERY
  SELECT ce.id, ce.title, public.together_event_day(ce), public.together_event_end(ce, v_tz), ce.ritual_id
  FROM public.couple_events ce
  WHERE ce.relationship_id = p_relationship_id AND public.together_memorable(ce, v_me)
    AND public.together_event_end(ce, v_tz) <= p_now
    AND public.together_event_end(ce, v_tz) > p_now - interval '3 days'
    AND NOT EXISTS (SELECT 1 FROM public.timeline_events te
                    WHERE te.couple_event_id = ce.id AND te.logged_by = v_me AND te.deleted_at IS NULL)
    AND NOT EXISTS (SELECT 1 FROM public.together_memory_dismissals d
                    WHERE d.event_id = ce.id AND d.user_id = v_me)
  ORDER BY 4 DESC
  LIMIT 3;
END;
$$;

CREATE FUNCTION public.list_together_on_this_day(p_relationship_id uuid, p_today date)
RETURNS TABLE (item_kind text, item_id uuid, item_date date, title text, note text, event_type text, years_ago int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  v_me uuid := public.together_actor(p_relationship_id);
  v_m int := extract(month FROM p_today)::int;
  v_d int := extract(day FROM p_today)::int;
  v_y int := extract(year FROM p_today)::int;
  -- Feb 28 of a common year also brings back Feb 29 (R6).
  v_leap_gap boolean := v_m = 2 AND v_d = 28
    AND extract(day FROM make_date(v_y, 3, 1) - 1)::int = 28;
BEGIN
  IF p_today IS NULL THEN PERFORM public.together_fail('invalid_input'); END IF;
  RETURN QUERY
  WITH moments AS (
    SELECT 'moment'::text AS k, te.id, te.occurred_at AS d, te.title AS t, te.note AS n, te.event_type AS et
    FROM public.timeline_events te
    WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
      AND te.event_type <> 'conflict'
      AND (te.visibility = 'shared' OR te.logged_by = v_me)
  ), events AS (
    SELECT 'event'::text AS k, ce.id, public.together_event_day(ce) AS d, ce.title AS t, NULL::text AS n, NULL::text AS et
    FROM public.couple_events ce
    WHERE ce.relationship_id = p_relationship_id AND ce.deleted_at IS NULL
      AND ce.status = 'confirmed' AND ce.visibility = 'shared' AND ce.rrule IS NULL
      -- an event that has its own memory shows as that memory
      AND NOT EXISTS (SELECT 1 FROM public.timeline_events te
                      WHERE te.couple_event_id = ce.id AND te.deleted_at IS NULL
                        AND (te.visibility = 'shared' OR te.logged_by = v_me))
  )
  SELECT x.k, x.id, x.d, x.t, x.n, x.et, v_y - extract(year FROM x.d)::int
  FROM (SELECT * FROM moments UNION ALL SELECT * FROM events) x
  WHERE extract(year FROM x.d)::int < v_y
    AND ((extract(month FROM x.d)::int = v_m AND extract(day FROM x.d)::int = v_d)
         OR (v_leap_gap AND extract(month FROM x.d)::int = 2 AND extract(day FROM x.d)::int = 29))
  ORDER BY x.d DESC, x.t
  LIMIT 5;
END;
$$;

CREATE FUNCTION public.list_together_ritual_memories(p_ritual_id uuid)
RETURNS TABLE (moment_id uuid, occurred_at date, title text, note text, logged_by uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE v public.couple_rituals := public.together_ritual_row(p_ritual_id); v_me uuid := auth.uid();
BEGIN
  RETURN QUERY
  SELECT te.id, te.occurred_at, te.title, te.note, te.logged_by
  FROM public.timeline_events te
  JOIN public.couple_events ce ON ce.id = te.couple_event_id
  WHERE ce.ritual_id = v.id AND te.relationship_id = v.relationship_id AND te.deleted_at IS NULL
    AND (te.visibility = 'shared' OR te.logged_by = v_me)
  ORDER BY te.occurred_at DESC, te.created_at DESC
  LIMIT 20;
END;
$$;

CREATE FUNCTION public.list_together_moments(p_relationship_id uuid,
  p_before_date date DEFAULT NULL, p_before_id uuid DEFAULT NULL, p_limit int DEFAULT 30)
RETURNS SETOF public.timeline_events
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_me uuid := public.together_actor(p_relationship_id);
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR (p_before_date IS NULL) <> (p_before_id IS NULL) THEN
    PERFORM public.together_fail('invalid_input');
  END IF;
  RETURN QUERY
  SELECT te.* FROM public.timeline_events te
  WHERE te.relationship_id = p_relationship_id AND te.deleted_at IS NULL
    AND (te.visibility = 'shared' OR te.logged_by = v_me)
    AND (p_before_date IS NULL OR (te.occurred_at, te.id) < (p_before_date, p_before_id))
  ORDER BY te.occurred_at DESC, te.id DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.add_event_memory(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dismiss_memory_prompt(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_memory_prompts(uuid, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_on_this_day(uuid, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_ritual_memories(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_together_moments(uuid, date, uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_event_memory(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dismiss_memory_prompt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_memory_prompts(uuid, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_on_this_day(uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_ritual_memories(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_together_moments(uuid, date, uuid, int) TO authenticated;
```

- [ ] **Step 4: Delete `memory_event_id`** from `20261014110000_couple_events.sql`. First check with `grep -rn memory_event_id lib supabase test` that nothing else uses it; expect only the migration line.

- [ ] **Step 5: Run every Together contract**

Run: the six-file command from Task 1, Step 6.
Expected: six `PASS` lines. If section 4's expected array differs only in order, the RPC's `ORDER BY x.d DESC, x.t` is the authority. Fix the test's `ORDER BY` to match, and record it in the ledger.

---

### Task 4: "Just for me" on a conflict moment

**Files:**
- Modify: `lib/features/timeline/data/models/timeline_event_model.dart`
- Modify: `lib/features/timeline/data/repositories/timeline_repository.dart`
- Modify: `lib/features/timeline/presentation/providers/timeline_providers.dart` (the `createTimelineEventProvider` and `updateTimelineEventProvider` records)
- Modify: `lib/features/timeline/presentation/screens/log_moment_details_screen.dart`
- Modify: `lib/features/timeline/presentation/widgets/moment_card.dart`
- Test: `test/features/timeline/moment_privacy_test.dart` (new)

**Interfaces:**
- Produces: these new fields on `TimelineEventModel`:
  - `final String visibility;` (default `'shared'`);
  - `final String? coupleEventId;`;
  - `bool get isPrivate => visibility == 'private';`.

  `fromJson` reads `json['visibility'] ?? 'shared'` and `json['couple_event_id']`.
- Produces: `TimelineRepository.createEvent(..., String visibility = 'shared')` and `updateEvent(..., String? visibility)`.
- Produces: both provider records gain the field `String? visibility`. Create sends `params.visibility ?? 'shared'`; update sends it only when it's non-null.
- Produces: `LogMomentDetailsScreen` reads `initialData['visibility']`.

- [ ] **Step 1: Write the failing tests** in `test/features/timeline/moment_privacy_test.dart`

```dart
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({String type = 'conflict', String? visibility}) => {
  'id': 'e1',
  'relationship_id': 'rel',
  'logged_by': 'ama',
  'event_type': type,
  'title': 'Money talk',
  'note': null,
  'mood_score': null,
  'occurred_at': '2026-10-10',
  'created_at': '2026-10-10T10:00:00Z',
  'updated_at': null,
  'deleted_at': null,
  if (visibility != null) 'visibility': visibility,
};

Future<List<String?>> _pumpForm(
  WidgetTester t, {
  required String type,
  Map<String, dynamic>? initialData,
  String? editId,
}) async {
  final sent = <String?>[];
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        createTimelineEventProvider.overrideWith((ref, p) async {
          sent.add(p.visibility);
          return TimelineEventModel.fromJson(_row(type: p.eventType));
        }),
        updateTimelineEventProvider.overrideWith((ref, p) async {
          sent.add(p.visibility);
          return TimelineEventModel.fromJson(_row(type: type));
        }),
      ],
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => LogMomentDetailsScreen(
                eventType: type,
                editEventId: editId,
                initialData: initialData,
              ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return sent;
}

void main() {
  test('a moment row maps its visibility; old rows are shared', () {
    expect(TimelineEventModel.fromJson(_row()).isPrivate, isFalse);
    expect(
      TimelineEventModel.fromJson(_row(visibility: 'private')).isPrivate,
      isTrue,
    );
  });

  testWidgets('a conflict can be kept just for me', (t) async {
    final sent = await _pumpForm(t, type: 'conflict');
    await t.enterText(find.byType(TextFormField).first, 'Money talk');
    await t.tap(find.text('Just for me'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save moment'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(sent, ['private']);
  });

  testWidgets('other moments have no privacy switch', (t) async {
    await _pumpForm(t, type: 'highlight');
    expect(find.text('Just for me'), findsNothing);
  });

  testWidgets('editing a private conflict keeps it private', (t) async {
    final sent = await _pumpForm(
      t,
      type: 'conflict',
      editId: 'e1',
      initialData: {
        'title': 'Money talk',
        'occurred_at': DateTime(2026, 10, 10),
        'visibility': 'private',
      },
    );
    await t.tap(find.text('Save changes'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(sent, ['private']);
  });

  testWidgets('my private conflict says only I can see it', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: MomentCard(
                    event: TimelineEventModel.fromJson(
                      _row(visibility: 'private'),
                    ),
                    currentUserId: 'ama',
                    currentMonth: DateTime(2026, 10),
                    partnerName: 'Kofi',
                  ),
                ),
              ),
        ),
      ),
    );
    expect(find.text('Only you can see this'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/timeline/moment_privacy_test.dart`
Expected: a compile failure on `isPrivate` and `p.visibility`.

- [ ] **Step 3: Implement the model and repository**
  - In `TimelineEventModel`, add the fields (constructor `this.visibility = 'shared', this.coupleEventId`), plus `fromJson` (`visibility: json['visibility'] as String? ?? 'shared'`, `coupleEventId: json['couple_event_id'] as String?`), `toJson` (`'visibility': visibility, 'couple_event_id': coupleEventId`) and `isPrivate`.
  - In `TimelineRepository.createEvent`, add the parameter `String visibility = 'shared'` and send `'visibility': visibility`.
  - In `updateEvent`, add `String? visibility` and `if (visibility != null) updates['visibility'] = visibility;`.
  - In `timeline_providers.dart`, add `String? visibility` to both records and pass it on: create sends `visibility: params.visibility ?? 'shared'`, update sends `visibility: params.visibility`.
  - Run `grep -rn "createTimelineEventProvider((\|updateTimelineEventProvider((" lib test` and add `visibility:` to every record literal it finds. Expect only `log_moment_details_screen.dart`.

- [ ] **Step 4: Implement the form**
  - In `_LogMomentDetailsScreenState`, add `bool _private = false;`, and in `initState`, inside the `initialData` block, add `_private = widget.initialData!['visibility'] == 'private';`.
  - Above the Save button, after the note field's `Gap`, add:

```dart
            if (widget.eventType == 'conflict') ...[
              InfoRowWidget(
                title: 'Just for me',
                subtitle:
                    "Kept off your partner's timeline. It still helps you look back.",
                icon: Icons.lock_outline_rounded,
                showAvatar: false,
                showDivider: false,
                isToggleItem: true,
                toggleValue: _private,
                onTap: () => setState(() => _private = !_private),
              ),
              Gap(Spacing.lg.h),
            ],
```

  - Pass `visibility: widget.eventType == 'conflict' ? (_private ? 'private' : 'shared') : null` in the update record, and the same expression with `'shared'` as the non-conflict value in the create record.
  - Check `InfoRowWidget`'s toggle API (`isToggleItem`, `toggleValue`, and the toggle's own callback) in `lib/core/widgets/info_row_widget.dart`. If the switch has its own callback parameter, wire both that and `onTap` to the same `setState`.

- [ ] **Step 5: Implement the card**
  - In `MomentCard._editMoment`'s `initialData`, add `'visibility': widget.event.visibility`.
  - In `build`, after the header row, add:

```dart
          if (widget.event.isPrivate && _isOwnEvent)
            Padding(
              padding: EdgeInsets.only(top: Spacing.xs.h),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  Gap(Spacing.xs.w),
                  Text(
                    'Only you can see this',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/timeline`
Expected: all pass, including the new file and `log_moment_details_screen_reminder_offer_test.dart`.

---

### Task 5: Story domain, repository and providers

**Files:**
- Create: `lib/features/together/domain/together_story.dart`
- Modify: `lib/features/together/data/together_repository.dart`
- Modify: `lib/features/together/presentation/together_providers.dart`
- Test: `test/features/together/together_story_test.dart` (new)

**Interfaces:**
- Consumes: the Task 3 RPC names and columns, and `TimelineEventModel.fromJson` (Task 4).
- Produces (`together_story.dart`):
  - `class MemoryPrompt { String eventId; String title; DateTime day; String? ritualId; factory MemoryPrompt.fromRow(Map<String, dynamic>) }`
  - `class OnThisDayItem { bool isMoment; String id; DateTime date; String title; String? note; String? eventType; int yearsAgo; String get lead; factory OnThisDayItem.fromRow(Map<String, dynamic>) }`. `lead` is `'1 year ago'` or `'$n years ago'`.
  - `class RitualMemory { String momentId; DateTime day; String title; String? note; String loggedBy; factory RitualMemory.fromRow(Map<String, dynamic>) }`
- Produces (`TogetherRepository`):
  - `Future<List<MemoryPrompt>> listMemoryPrompts(String relationshipId, {required String tz})`
  - `Future<String> addEventMemory(String eventId, String line)`
  - `Future<void> dismissMemoryPrompt(String eventId)`
  - `Future<List<OnThisDayItem>> listOnThisDay(String relationshipId, DateTime today)`
  - `Future<List<RitualMemory>> listRitualMemories(String ritualId)`
  - `Future<List<TimelineEventModel>> listMoments(String relationshipId, {DateTime? beforeDate, String? beforeId, int limit = 30})`
- Produces (providers):
  - `togetherMemoryPromptsProvider`: `FutureProvider.autoDispose.family<List<MemoryPrompt>, String>`
  - `togetherOnThisDayProvider`: `FutureProvider.autoDispose.family<List<OnThisDayItem>, String>`
  - `togetherRitualMemoriesProvider`: `FutureProvider.autoDispose.family<List<RitualMemory>, String>`, keyed by ritual id.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_story.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('memory prompts send my zone and map rows', () async {
    final g = FakeTogetherGateway({
      'list_together_memory_prompts':
          (_) => [
            {
              'event_id': 'e1',
              'title': 'Dinner at Buka',
              'event_day': '2026-11-07',
              'ended_at': '2026-11-07T20:00:00+00:00',
              'ritual_id': null,
            },
          ],
    });
    final p = await TogetherRepository(
      g,
    ).listMemoryPrompts('r1', tz: 'Africa/Accra');
    expect(g.calls.single.$2, {
      'p_relationship_id': 'r1',
      'p_tz': 'Africa/Accra',
    });
    expect([p.single.eventId, p.single.title, p.single.day], [
      'e1',
      'Dinner at Buka',
      DateTime(2026, 11, 7),
    ]);
  });

  test('adding and dismissing send the event', () async {
    final g = FakeTogetherGateway({
      'add_event_memory': (_) => 'm1',
      'dismiss_memory_prompt': (_) => null,
    });
    final repo = TogetherRepository(g);
    expect(await repo.addEventMemory('e1', 'So good'), 'm1');
    await repo.dismissMemoryPrompt('e1');
    expect(g.calls.map((c) => c.$2).toList(), [
      {'p_event_id': 'e1', 'p_line': 'So good'},
      {'p_event_id': 'e1'},
    ]);
  });

  test('on this day sends my local date and reads naturally', () async {
    final g = FakeTogetherGateway({
      'list_together_on_this_day':
          (_) => [
            {
              'item_kind': 'moment',
              'item_id': 'm1',
              'item_date': '2025-11-07',
              'title': 'First date',
              'note': null,
              'event_type': 'first',
              'years_ago': 1,
            },
            {
              'item_kind': 'event',
              'item_id': 'e2',
              'item_date': '2023-11-07',
              'title': 'Trip',
              'note': null,
              'event_type': null,
              'years_ago': 3,
            },
          ],
    });
    final items = await TogetherRepository(
      g,
    ).listOnThisDay('r1', DateTime(2026, 11, 7, 22, 30));
    expect(g.calls.single.$2, {
      'p_relationship_id': 'r1',
      'p_today': '2026-11-07',
    });
    expect(items.map((i) => (i.isMoment, i.lead)).toList(), [
      (true, '1 year ago'),
      (false, '3 years ago'),
    ]);
  });

  test('ritual memories and archive pages map rows', () async {
    final g = FakeTogetherGateway({
      'list_together_ritual_memories':
          (_) => [
            {
              'moment_id': 'm1',
              'occurred_at': '2026-11-07',
              'title': 'Date night',
              'note': 'Dancing after',
              'logged_by': 'kofi',
            },
          ],
      'list_together_moments':
          (_) => [
            {
              'id': 'm1',
              'relationship_id': 'r1',
              'logged_by': 'kofi',
              'event_type': 'highlight',
              'title': 'Date night',
              'note': 'Dancing after',
              'mood_score': null,
              'occurred_at': '2026-11-07',
              'created_at': '2026-11-07T21:00:00Z',
              'updated_at': '2026-11-07T21:00:00Z',
              'deleted_at': null,
              'visibility': 'shared',
              'couple_event_id': 'e1',
            },
          ],
    });
    final repo = TogetherRepository(g);
    final m = await repo.listRitualMemories('rit-1');
    expect([m.single.note, m.single.day], ['Dancing after', DateTime(2026, 11, 7)]);
    final page = await repo.listMoments(
      'r1',
      beforeDate: DateTime(2026, 12, 1),
      beforeId: 'm9',
      limit: 30,
    );
    expect(g.calls.last.$2, {
      'p_relationship_id': 'r1',
      'p_before_date': '2026-12-01',
      'p_before_id': 'm9',
      'p_limit': 30,
    });
    expect(page.single.coupleEventId, 'e1');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_story_test.dart`
Expected: a compile failure because `together_story.dart` doesn't exist.

- [ ] **Step 3: Write `together_story.dart`**

```dart
/// The story layer (Together Phase 4): memory prompts, On this day and
/// ritual memories. No counts anywhere (spec §3.1–3.2).
library;

DateTime _day(Object? v) {
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

/// A lived shared event I haven't remembered yet (plan R4).
class MemoryPrompt {
  const MemoryPrompt({
    required this.eventId,
    required this.title,
    required this.day,
    this.ritualId,
  });

  factory MemoryPrompt.fromRow(Map<String, dynamic> r) => MemoryPrompt(
    eventId: r['event_id'] as String,
    title: r['title'] as String? ?? '',
    day: _day(r['event_day']),
    ritualId: r['ritual_id'] as String?,
  );

  final String eventId;
  final String title;
  final DateTime day;
  final String? ritualId;
}

/// Something from this date in an earlier year (plan R6).
class OnThisDayItem {
  const OnThisDayItem({
    required this.isMoment,
    required this.id,
    required this.date,
    required this.title,
    required this.yearsAgo,
    this.note,
    this.eventType,
  });

  factory OnThisDayItem.fromRow(Map<String, dynamic> r) => OnThisDayItem(
    isMoment: r['item_kind'] == 'moment',
    id: r['item_id'] as String,
    date: _day(r['item_date']),
    title: r['title'] as String? ?? '',
    note: r['note'] as String?,
    eventType: r['event_type'] as String?,
    yearsAgo: (r['years_ago'] as num).toInt(),
  );

  final bool isMoment;
  final String id;
  final DateTime date;
  final String title;
  final String? note;
  final String? eventType;
  final int yearsAgo;

  String get lead => yearsAgo == 1 ? '1 year ago' : '$yearsAgo years ago';
}

/// A moment from one of a ritual's weeks (plan R9).
class RitualMemory {
  const RitualMemory({
    required this.momentId,
    required this.day,
    required this.title,
    required this.loggedBy,
    this.note,
  });

  factory RitualMemory.fromRow(Map<String, dynamic> r) => RitualMemory(
    momentId: r['moment_id'] as String,
    day: _day(r['occurred_at']),
    title: r['title'] as String? ?? '',
    note: r['note'] as String?,
    loggedBy: r['logged_by'] as String,
  );

  final String momentId;
  final DateTime day;
  final String title;
  final String? note;
  final String loggedBy;
}
```

- [ ] **Step 4: Add the repository methods** at the end of `TogetherRepository`, and import `../domain/together_story.dart` and `package:attune/features/timeline/data/models/timeline_event_model.dart`.

```dart
  // ── Story (Phase 4) ──

  Future<List<MemoryPrompt>> listMemoryPrompts(
    String relationshipId, {
    required String tz,
  }) async {
    final rows =
        await _call('list_together_memory_prompts', {
              'p_relationship_id': relationshipId,
              'p_tz': tz,
            })
            as List;
    return [
      for (final r in rows) MemoryPrompt.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<String> addEventMemory(String eventId, String line) async =>
      await _call('add_event_memory', {'p_event_id': eventId, 'p_line': line})
          as String;

  Future<void> dismissMemoryPrompt(String eventId) =>
      _call('dismiss_memory_prompt', {'p_event_id': eventId});

  Future<List<OnThisDayItem>> listOnThisDay(
    String relationshipId,
    DateTime today,
  ) async {
    final rows =
        await _call('list_together_on_this_day', {
              'p_relationship_id': relationshipId,
              'p_today': _ymd(today),
            })
            as List;
    return [
      for (final r in rows) OnThisDayItem.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  Future<List<RitualMemory>> listRitualMemories(String ritualId) async {
    final rows =
        await _call('list_together_ritual_memories', {'p_ritual_id': ritualId})
            as List;
    return [
      for (final r in rows) RitualMemory.fromRow(Map<String, dynamic>.from(r)),
    ];
  }

  /// One page of the memories archive, newest first (plan R8).
  Future<List<TimelineEventModel>> listMoments(
    String relationshipId, {
    DateTime? beforeDate,
    String? beforeId,
    int limit = 30,
  }) async {
    final rows =
        await _call('list_together_moments', {
              'p_relationship_id': relationshipId,
              'p_before_date': beforeDate == null ? null : _ymd(beforeDate),
              'p_before_id': beforeId,
              'p_limit': limit,
            })
            as List;
    return [
      for (final r in rows)
        TimelineEventModel.fromJson(Map<String, dynamic>.from(r)),
    ];
  }
```

The test for `listMoments` expects the null-free map when a cursor is given. For the first page, `null` values are sent, which matches PostgREST's handling of the RPC's defaults.

- [ ] **Step 5: Add the providers** at the end of `together_providers.dart`, and import `../domain/together_story.dart`.

```dart
/// Lived shared events I could add a line about (Phase 4 R4).
final togetherMemoryPromptsProvider = FutureProvider.autoDispose
    .family<List<MemoryPrompt>, String>((ref, relationshipId) async {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      final tz = await ref.watch(togetherDeviceTimezoneProvider.future);
      return ref
          .watch(togetherRepositoryProvider)
          .listMemoryPrompts(relationshipId, tz: tz);
    });

/// Earlier years on today's date (Phase 4 R6).
final togetherOnThisDayProvider = FutureProvider.autoDispose
    .family<List<OnThisDayItem>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      final now = ref.watch(togetherClockProvider)();
      return ref
          .watch(togetherRepositoryProvider)
          .listOnThisDay(relationshipId, DateTime(now.year, now.month, now.day));
    });

/// A ritual's memories (Phase 4 R9).
final togetherRitualMemoriesProvider = FutureProvider.autoDispose
    .family<List<RitualMemory>, String>(
      (ref, ritualId) =>
          ref.watch(togetherRepositoryProvider).listRitualMemories(ritualId),
    );
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/features/together/together_story_test.dart && flutter analyze lib/features/together`
Expected: 4 pass; no analyzer issues.

---

### Task 6: Memory prompt, "Add a memory" and "On this day" on the hub

**Files:**
- Create: `lib/features/together/presentation/widgets/memory_sheets.dart`
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (Today section around line 440; Our story around line 520)
- Modify: `lib/features/together/presentation/widgets/couple_event_sheet.dart` (the actions list near "Skip this week" and "Delete event")
- Test: `test/features/together/memory_sheets_test.dart` (new) and `test/features/together/together_screen_test.dart` (extended)

**Interfaces:**
- Consumes: Task 5 providers and repository.
- Produces:
  - `Future<void> showAddMemorySheet(BuildContext context, {required String eventId, required String title})`
  - `String memoryPromptQuestion(MemoryPrompt p, DateTime now)`, which returns `'Add a line about today?'`, `'… yesterday?'`, `'… Saturday?'` (when under 7 days ago) or `'… Nov 7?'`.
  - `bool canAddMemory(TogetherItem item, DateTime now, String? me)`, which is true for a confirmed, shared, two-person event I'm in, once it has started.

- [ ] **Step 1: Write the failing sheet tests** in `test/features/together/memory_sheets_test.dart`

```dart
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_story.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/memory_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('the prompt question names the day plainly', () {
    MemoryPrompt on(DateTime d) =>
        MemoryPrompt(eventId: 'e', title: 'Dinner', day: d);
    final now = DateTime(2026, 11, 9, 10); // a Monday
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 9)), now),
      'Add a line about today?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 8)), now),
      'Add a line about yesterday?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 7)), now),
      'Add a line about Saturday?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 10, 20)), now),
      'Add a line about Oct 20?',
    );
  });

  testWidgets('a line becomes a memory; a blank one is not sent', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final g = FakeTogetherGateway({'add_event_memory': (_) => 'm1'});
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: Builder(
                    builder:
                        (c) => TextButton(
                          onPressed:
                              () => showAddMemorySheet(
                                c,
                                eventId: 'e1',
                                title: 'Dinner at Buka',
                              ),
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
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty);
    await t.enterText(find.byType(TextField).first, 'The jollof was perfect');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {
      'p_event_id': 'e1',
      'p_line': 'The jollof was perfect',
    });
    expect(find.text('Added to your story.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Write the failing screen tests** in `together_screen_test.dart`
  - Add two parameters to `_pump`, `List<Map<String, dynamic>> prompts = const []` and `List<Map<String, dynamic>> onThisDay = const []`, plus the handlers `'list_together_memory_prompts': (_) => prompts`, `'list_together_on_this_day': (_) => onThisDay` and `'dismiss_memory_prompt': (_) => null`.
  - Then add:

```dart
  testWidgets('a lived event asks for one line in Today; Not now hides it', (
    t,
  ) async {
    final g = await _pump(
      t,
      prompts: [
        {
          'event_id': 'e1',
          'title': 'Dinner at Buka',
          'event_day': '2026-11-01',
          'ended_at': '2026-11-01T20:00:00+00:00',
          'ritual_id': null,
        },
      ],
    );
    expect(find.text('Add a line about yesterday?'), findsOneWidget);
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(g.calls.last.$1, 'dismiss_memory_prompt');
    expect(find.text('Add a line about yesterday?'), findsNothing);
  });

  testWidgets('On this day opens Our story, without a count', (t) async {
    await _pump(
      t,
      onThisDay: [
        {
          'item_kind': 'moment',
          'item_id': 'm1',
          'item_date': '2025-11-02',
          'title': 'First date',
          'note': null,
          'event_type': 'first',
          'years_ago': 1,
        },
      ],
    );
    await t.scrollUntilVisible(
      find.text('First date'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Our story'), findsOneWidget);
    expect(find.text('On this day · 1 year ago'), findsOneWidget);
  });
```

- [ ] **Step 3: Write the failing event-sheet test** in `couple_event_sheet_test.dart`. Use the file's `_item` helper; its event starts `2026-11-06T19:00Z`. Check what clock that test file's `_open` overrides. If `togetherClockProvider` isn't overridden there, add `togetherClockProvider.overrideWithValue(() => DateTime(2026, 11, 8, 9))` to `_open`'s overrides.

```dart
  testWidgets('after a shared event, I can add a memory of it', (t) async {
    final g = await _open(t, item: _item());
    await t.scrollUntilVisible(
      find.text('Add a memory'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Add a memory'));
    await t.pumpAndSettle();
    expect(find.text('A line to remember it by'), findsOneWidget);
    expect(g.calls.where((c) => c.$1 == 'add_event_memory'), isEmpty);
  });
```

- [ ] **Step 4: Run them and watch them fail**

Run: `flutter test test/features/together/memory_sheets_test.dart test/features/together/together_screen_test.dart test/features/together/couple_event_sheet_test.dart`
Expected: a compile failure because `memory_sheets.dart` is missing. Once that file exists, the screen and event-sheet tests fail because they can't find the new texts.

- [ ] **Step 5: Write `memory_sheets.dart`**

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/together_item.dart';
import '../../domain/together_story.dart';
import '../together_providers.dart';

/// "Add a line about Saturday?" (spec §6.3).
String memoryPromptQuestion(MemoryPrompt p, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final ago = today.difference(p.day).inDays;
  final when = switch (ago) {
    <= 0 => 'today',
    1 => 'yesterday',
    < 7 => DateFormat.EEEE().format(p.day),
    _ => DateFormat.MMMd().format(p.day),
  };
  return 'Add a line about $when?';
}

/// A confirmed, shared event of both of ours that I'm in, once it has
/// started (the server checks the same, plan R4).
bool canAddMemory(TogetherItem item, DateTime now, String? me) {
  if (item.kind != TogetherItemKind.event || me == null) return false;
  if (item.status != 'confirmed') return false;
  if (item.visibility != TogetherVisibility.shared) return false;
  if (item.participantIds.length != 2 || !item.participantIds.contains(me)) {
    return false;
  }
  final start = item.startsAt;
  return start != null ? !start.isAfter(now) : !item.day.isAfter(now);
}

Future<void> showAddMemorySheet(
  BuildContext context, {
  required String eventId,
  required String title,
}) async {
  final message = await BottomSheetUtils.showDocumentationBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: _AddMemorySheet(eventId: eventId, title: title),
  );
  if (message != null && context.mounted) context.showSuccessSnackbar(message);
}

class _AddMemorySheet extends ConsumerStatefulWidget {
  const _AddMemorySheet({required this.eventId, required this.title});
  final String eventId;
  final String title;

  @override
  ConsumerState<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends ConsumerState<_AddMemorySheet> {
  final _line = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final line = _line.text.trim();
    if (line.isEmpty) {
      context.showErrorSnackbar('Write a line first');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(togetherRepositoryProvider)
          .addEventMemory(widget.eventId, line);
      ref.invalidate(togetherMemoryPromptsProvider);
      ref.invalidate(togetherOnThisDayProvider);
      ref.invalidate(togetherRangeProvider);
      if (mounted) Navigator.of(context).pop('Added to your story.');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackbar('Could not save that. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          BottomSheetHeader(
            title: 'Add a memory',
            actionLabel: 'Save',
            onPressed: _busy ? null : _save,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Gap(Spacing.sm),
          AppTextFormField(
            controller: _line,
            label: 'A line to remember it by',
            maxLines: 3,
            maxLength: 300,
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
```

Before writing it, check the `TogetherItem` field names this uses (`status`, `visibility`, `participantIds`, `startsAt`, `day`, `kind`) in `lib/features/together/domain/together_item.dart`. If `status` is an enum or named differently, use the existing name and record the deviation in the ledger.

- [ ] **Step 6: Wire the hub** (`together_screen.dart`)
  - Watch `togetherMemoryPromptsProvider(relationshipId)` and `togetherOnThisDayProvider(relationshipId)` next to the agenda. Read their `valueOrNull ?? const []`: they're optional extras, so a failed load hides them quietly.
  - Keep a `final Set<String> _dismissed = {};` in state. Take the first prompt not in it.
  - In the Today section, after the care rows, add `if (prompt != null) _memoryPromptRow(prompt, now)`. Count the prompt as content in the "Nothing planned today." condition, so add `&& prompt == null`.

```dart
  Widget _memoryPromptRow(MemoryPrompt p, DateTime now) {
    final colorScheme = Theme.of(context).colorScheme;
    return InfoRowWidget(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      icon: Icons.edit_note_rounded,
      iconColor: colorScheme.primary,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      title: memoryPromptQuestion(p, now),
      subtitle: p.title,
      titleMaxLines: 1,
      subTitleMaxLines: 1,
      showDivider: true,
      trailing: TextButton(
        onPressed: () async {
          setState(() => _dismissed.add(p.eventId));
          try {
            await ref
                .read(togetherRepositoryProvider)
                .dismissMemoryPrompt(p.eventId);
          } catch (_) {
            // Best effort: it is hidden for this visit either way.
          }
        },
        child: const Text('Not now'),
      ),
      onTap: () => showAddMemorySheet(
        context,
        eventId: p.eventId,
        title: p.title,
      ),
    );
  }
```

  - **Our story:** render the section when `agenda.recentMoments.isNotEmpty || onThisDay.isNotEmpty`. Before the recent-moment rows, add one row per "On this day" item:

```dart
  Widget _onThisDayRow(OnThisDayItem i) => InfoRowWidget(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.md,
      vertical: Spacing.xs,
    ),
    icon: Icons.history_rounded,
    title: i.title,
    subtitle: 'On this day · ${i.lead}',
    titleMaxLines: 1,
    subTitleMaxLines: 1,
    showDivider: true,
    disableTrailing: true,
  );
```

  - Make "All memories" call `_openMemories(relationshipId)`. Until Task 7 adds the archive screen, keep its current body (`setState(() => _view = _View.month)`) inside that method.

- [ ] **Step 7: Wire the event sheet** (`couple_event_sheet.dart`). In `build`, compute `final now = ref.watch(togetherClockProvider)();` and `final memorable = item != null && canAddMemory(item, now, me);`. Then add before the `ritualWeek` block:

```dart
            if (memorable) ...[
              AppDivider(),
              InfoRowWidget(
                title: 'Add a memory',
                subtitle: 'A line about how it went',
                icon: Icons.edit_note_rounded,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap:
                    _busy
                        ? null
                        : () {
                          final navigator = Navigator.of(context);
                          final host = navigator.context;
                          navigator.pop();
                          showAddMemorySheet(
                            host,
                            eventId: item.id,
                            title: item.title,
                          );
                        },
              ),
            ],
```

Import `memory_sheets.dart` with `show canAddMemory, showAddMemorySheet`.

- [ ] **Step 8: Fix the other harnesses that pump the hub.** Run `grep -rln "list_together_rituals" test`. In every harness it finds (for example the planning test app and a golden helper), add the two new list handlers returning `[]`. Without them the hub still renders, because the extras fail quietly, but `FakeTogetherGateway.calls` assertions elsewhere may count the extra calls. Run each touched file.

- [ ] **Step 9: Run the tests**

Run: `flutter test test/features/together test/features/planning && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 7: The memories archive

**Files:**
- Create: `lib/features/together/presentation/screens/together_memories_screen.dart`
- Modify: `lib/features/together/presentation/screens/together_screen.dart` (`_openMemories`)
- Test: `test/features/together/together_memories_screen_test.dart` (new)

**Interfaces:**
- Consumes: `TogetherRepository.listMoments` (Task 5), `MomentsList` (`lib/features/timeline/presentation/widgets/moments_list.dart`), `togetherMeProvider`, `quiz.partnerNameProvider` and `togetherChangeSignalProvider`.
- Produces: `class TogetherMemoriesScreen extends ConsumerStatefulWidget { const TogetherMemoriesScreen({super.key, required this.relationshipId}); }`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/screens/together_memories_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _m(int i) => {
  'id': 'm$i',
  'relationship_id': 'r1',
  'logged_by': i.isEven ? 'ama' : 'kofi',
  'event_type': 'highlight',
  'title': 'Moment $i',
  'note': null,
  'mood_score': null,
  'occurred_at': DateTime(2026, 10, 30 - i).toIso8601String().split('T')[0],
  'created_at': '2026-10-01T10:00:00Z',
  'updated_at': null,
  'deleted_at': null,
  'visibility': 'shared',
  'couple_event_id': null,
};

Future<FakeTogetherGateway> _pump(
  WidgetTester t,
  dynamic Function(Map<String, dynamic>) page,
) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({'list_together_moments': page});
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherMeProvider.overrideWithValue('ama'),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        timeline.togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => const MaterialApp(
              home: TogetherMemoriesScreen(relationshipId: 'r1'),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('pages back through memories as I scroll, without repeats', (
    t,
  ) async {
    final g = await _pump(t, (p) {
      if (p['p_before_id'] == null) return [for (var i = 0; i < 30; i++) _m(i)];
      if (p['p_before_id'] == 'm29') return [_m(30), _m(31)];
      return [];
    });
    expect(find.text('Moment 0'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Moment 31'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(g.calls[1].$2['p_before_id'], 'm29');
    expect(g.calls[1].$2['p_before_date'], _m(29)['occurred_at']);
    expect(find.text('Moment 31'), findsOneWidget);
    expect(g.calls.length, 2); // a short page means the end: no more calls
  });

  testWidgets('no memories yet shows the story empty state', (t) async {
    await _pump(t, (_) => []);
    expect(find.text('Your relationship story starts here.'), findsOneWidget);
  });

  testWidgets('a failed first page offers Try again', (t) async {
    var fail = true;
    final g = await _pump(t, (_) {
      if (fail) throw Exception('offline');
      return [_m(0)];
    });
    expect(find.text('Try again'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Moment 0'), findsOneWidget);
    expect(g.calls.length, 2);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/together_memories_screen_test.dart`
Expected: a compile failure because the screen doesn't exist.

- [ ] **Step 3: Write the screen**

```dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/schimmer_skeleton.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz_providers;
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/features/timeline/presentation/widgets/moments_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../together_providers.dart';

/// Every moment, newest first, a page at a time (spec §6.3; plan R8).
class TogetherMemoriesScreen extends ConsumerStatefulWidget {
  const TogetherMemoriesScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<TogetherMemoriesScreen> createState() =>
      _TogetherMemoriesScreenState();
}

class _TogetherMemoriesScreenState
    extends ConsumerState<TogetherMemoriesScreen> {
  static const _page = 30;
  final List<TimelineEventModel> _items = [];
  bool _loading = false;
  bool _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (_done && !reset)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _done = false;
      }
    });
    try {
      final last = _items.isEmpty ? null : _items.last;
      final page = await ref
          .read(togetherRepositoryProvider)
          .listMoments(
            widget.relationshipId,
            beforeDate: last?.occurredAt,
            beforeId: last?.id,
            limit: _page,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _done = page.length < _page;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Edits, deletes and new moments elsewhere: start again from the top.
    ref.listen(
      togetherChangeSignalProvider(widget.relationshipId),
      (_, __) => _load(reset: true),
    );
    final me = ref.watch(togetherMeProvider) ?? '';
    final partner =
        ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';
    final Widget body;
    if (_items.isEmpty && _loading) {
      body = ListView(
        padding: EdgeInsets.all(Spacing.md.w),
        children: [
          for (var i = 0; i < 4; i++) ...[
            SchimmerSkeleton(height: 96.h),
            Gap(Spacing.sm.h),
          ],
        ],
      );
    } else if (_items.isEmpty && _error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load your memories.'),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _load();
          return false;
        },
        child: ListView(
          padding: EdgeInsets.all(Spacing.md.w),
          children: [
            MomentsList(
              events: _items,
              currentUserId: me,
              currentMonth: DateTime.now(),
              onDateSelected: (_) {},
              partnerName: partner,
            ),
            if (_loading)
              Padding(
                padding: EdgeInsets.all(Spacing.md.w),
                child: const Center(child: CircularProgressIndicator()),
              ),
            if (_error != null && _items.isNotEmpty)
              TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('All memories')), body: body);
  }
}
```

If `MomentsList`'s `onDateSelected` type is `Function(DateTime)`, the closure above matches it. Do not change `MomentsList`.

- [ ] **Step 4: Open it from the hub.** In `together_screen.dart`:

```dart
  void _openMemories(String relationshipId) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TogetherMemoriesScreen(relationshipId: relationshipId),
    ),
  );
```

Add the import. Then update the existing screen test that expected "All memories" to switch to the month view, if one exists (`grep -n "All memories" test/features/together`). It should now expect the archive's app bar title, with a `list_together_moments` handler added to `_pump`. Record that in the ledger.

- [ ] **Step 5: Run the tests**

Run: `flutter test test/features/together && flutter analyze lib/features/together`
Expected: all pass; no issues.

---

### Task 8: A ritual's memories

**Files:**
- Modify: `lib/features/together/presentation/widgets/ritual_sheets.dart` (`_RitualSheet.build`, before the trailing `Gap(Spacing.xl)`)
- Test: `test/features/together/ritual_sheets_test.dart` (extended)

**Interfaces:**
- Consumes: `togetherRitualMemoriesProvider(ritualId)` (Task 5).

- [ ] **Step 1: Write the failing test.** In `_host`, add the handler `'list_together_ritual_memories': (_) => memories`, with a new optional `List<Map<String, dynamic>> memories = const []` parameter, and the override `togetherMeProvider.overrideWithValue('ama')`. Then:

```dart
  testWidgets("a ritual's sheet lists its memories, with no count", (t) async {
    await _host(
      t,
      (c) => showRitualSheet(c, 'r1', _ritual),
      memories: [
        {
          'moment_id': 'm1',
          'occurred_at': '2026-10-30',
          'title': 'Date night',
          'note': 'Dancing after',
          'logged_by': 'kofi',
        },
      ],
    );
    expect(find.text('Memories'), findsOneWidget);
    expect(find.text('Dancing after'), findsOneWidget);
    expect(find.textContaining('memories ('), findsNothing);
  });

  testWidgets('with no memories yet, the sheet just says how to add one', (
    t,
  ) async {
    await _host(t, (c) => showRitualSheet(c, 'r1', _ritual));
    expect(
      find.text('After a week, add a line about it from Together.'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/together/ritual_sheets_test.dart`
Expected: 2 failures (the texts aren't found).

- [ ] **Step 3: Implement.** `_RitualSheet` is a `ConsumerWidget`. In `build`, read `final memories = ref.watch(togetherRitualMemoriesProvider(ritual.id)).valueOrNull ?? const <RitualMemory>[];` and append before the last `Gap(Spacing.xl)`:

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
              'Memories',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (memories.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: Text(
                'After a week, add a line about it from Together.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final m in memories)
            InfoRowWidget(
              title: m.note ?? m.title,
              subtitle: DateFormat.MMMEd().format(m.day),
              icon: Icons.favorite_border_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              titleMaxLines: 2,
            ),
```

Import `../../domain/together_story.dart`. No count, no "N weeks".

- [ ] **Step 4: Run the tests**

Run: `flutter test test/features/together/ritual_sheets_test.dart`
Expected: all pass.

---

### Task 9: Spec rulings, previews, full suite

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-together-hub-design.md` (add §8.7 after §8.6; add a note to the D10 row)

- [ ] **Step 1: Add §8.7**

```markdown
### 8.7 Phase 4 rulings (plan `2026-10-14-together-phase4-story.md`)
- R1: Private conflicts stay out of Pulse and the verdict entirely. Pulse is one score per couple that both read, so a private conflict feeding it would leak (amends D10).
- R2: A memory is a line of text; photos come later.
- R3: A memory links to its event from the moment (`timeline_events.couple_event_id`), so each partner can add their own.
- R4: One in-app prompt at a time, for a confirmed, shared, non-recurring event of both partners that ended in the last 3 days. "Not now" hides it for good.
- R5: Memory moments are highlights, dated to the event's own day.
- R6: On this day covers earlier years on the same date (Feb 29 shows on Feb 28 in common years), no conflicts, up to 5.
- R7: Only conflicts can be private; the default is shared.
- R8: The archive pages 30 at a time by date and id.
- R9: A ritual's sheet lists its memories, newest 20, without a count.
```

In the D10 row, append: ` *Amended by §8.7 R1: a private conflict stays out of the shared Pulse.*`

- [ ] **Step 2: Golden previews (throwaway).** Render these to the scratchpad and inspect them for overflow and spacing, then delete the preview test:
  - the Agenda, with a memory prompt in Today and two "On this day" rows in Our story;
  - the add-a-memory sheet;
  - the archive with two months;
  - the ritual sheet with memories;
  - the moment form for a conflict, with "Just for me" on.

- [ ] **Step 3: Full verification**

Run, saving the output in the plan workspace:
- `flutter test`
- `flutter analyze lib/features/together lib/features/timeline`
- `deno test --allow-read supabase/functions/compute-pulse/private_conflicts.test.ts supabase/functions/generate-verdict`
- the six-file contract command

Expected: everything passes.
