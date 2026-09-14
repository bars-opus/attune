# Planning — Plan A: Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete database foundation for Planning — five tables, RLS, every mutation and read RPC, and the Realtime signal — with contract tests that prove security and correctness against a real Postgres database, not just against the harness's own generosity.

**Architecture:** Three content tables (`planning_items` self-referencing for Tasks/Goals, `planning_events`, `planning_notes`), one link table (`planning_event_tasks`), and one Realtime signal table (`planning_change_signals`), following the shapes `story_items`/`story_change_signals` and `reminders` already established in this codebase. Clients get SELECT only; every write goes through a `SECURITY DEFINER` RPC. Read RPCs are `SECURITY INVOKER` so RLS stays the sole authority.

**Tech Stack:** PostgreSQL migrations (Supabase), `pgTAP`-free hand-written SQL contract tests run against the project's local Postgres harness (`scripts/local_pg_setup.sh`), the existing `test_set_auth(uuid)` helper for impersonating a caller.

**Spec:** `docs/superpowers/specs/2026-09-14-planning-design.md` (read this in full before Task 1 — this plan implements its §3, §4, §5's RPC surface). Also read `lib/architecture/STORIES.md` §3 and §4 for the closest existing analog of everything this plan builds — the same table-vs-RPC boundary, the same `SECURITY DEFINER`/`SET search_path` discipline, the same Realtime-signal shape.

## Global Constraints

These bind every task below. Copied verbatim from the spec; do not relax any of them without stopping and asking.

- **Clients get SELECT only, on all five tables.** No client ever has direct INSERT/UPDATE/DELETE on `planning_items`, `planning_events`, `planning_event_tasks`, `planning_notes`, or `planning_change_signals`. Every mutation is a `SECURITY DEFINER` RPC. (Spec §4.1)
- **`item_kind` is stored and immutable** (`'task'` or `'goal'`), never derived from child existence. No RPC or trigger may change it after creation. (Spec §2, §3.1)
- **Goal nesting is exactly one level.** Only a Task (`item_kind = 'task'`) may have a non-null `parent_goal_id`; a row with a non-null `parent_goal_id` can never itself be pointed at by another row's `parent_goal_id`. (Spec §3.1 Goal invariants)
- **A live Goal always has between 1 and 100 live children.** Goal creation is atomic with its first child; deleting the sole remaining live child is rejected; adding a 101st live child is rejected. (Spec §3.1 Goal invariants, §4.2)
- **Progress and "is this a Goal complete" are never stored** — always computed from a live `COUNT` over non-deleted children at read/mutation time. (Spec §3.1, §4.3)
- **Exactly one celebration message per Goal, ever**, using the server-owned `celebrated_at` timestamp — never cleared, even when the Goal is later reopened and recompleted. (Spec §3.1, §4.3, §9)
- **Composite `(id, relationship_id)` foreign keys** make every parent-goal link and every event-task link structurally impossible to point across two different couples' data — this is a schema-level guarantee, not just an RPC check. (Spec §3.1, §3.2)
- **Soft delete never relies on `ON DELETE CASCADE`.** Every delete RPC explicitly cleans up dependent rows (link rows, children) inside its own transaction, because a soft delete (`UPDATE ... SET deleted_at = now()`) never fires a foreign key's cascade. Hard `ON DELETE CASCADE` exists only for relationship/account erasure. (Spec §3.2, §3.5, §9)
- **`created_by` is nullable, `ON DELETE SET NULL`.** Deleting a user's account must never cascade-delete shared Planning content the other partner still has. (Spec §3.1, §10 "Deleting one partner's account preserves...")
- **Access requires an active, unarchived relationship**: `status = 'active' AND chat_archived_at IS NULL AND (user_a = auth.uid() OR user_b = auth.uid())`. This is the read predicate AND the write predicate — there is deliberately no read-after-archive exception for Planning, unlike Stories. (Spec §2, §4.1)
- **Every `SECURITY DEFINER` function**: fixed `SET search_path = public`, rejects `auth.uid() IS NULL` immediately, is `REVOKE ALL ... FROM PUBLIC, anon`, and is granted only to the role that needs it. Internal helper functions (`reconcile_planning_goal`, `bump_planning_signal`) are additionally revoked from `authenticated` — only the public-facing RPCs may call them. (Spec §4.2)
- **All required text rejects blank-after-trim.** `title` on every table: `char_length(btrim(title)) BETWEEN 1 AND 120`. RPCs trim leading/trailing whitespace before writing. (Spec §3)
- **Keyset pagination only**, never offset. Every read RPC's ordering ends with `id` as a deterministic tie-breaker, and every cursor carries all preceding sort values. `p_limit` is clamped server-side to `1..100` regardless of what is requested. (Spec §5)
- **No test may pass vacuously.** A `SELECT ... INTO` variable compared with `<>` against something that can be NULL is NULL-blind — the `IF` never fires and the test is silently worthless. Use `IS DISTINCT FROM`. Every contract test in this plan must be mutation-tested: break the behavior it claims to protect, confirm the test fails, then restore. This project has repeatedly shipped tests that passed with the protected behavior deleted; do not add another one.
- **The test harness's blanket grant is a known trap.** `scripts/local_pg_grants.sql` runs `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated` *after* all migrations. If Planning's REVOKEs are not replayed by that script (via `\i`), the harness will silently hand `authenticated` direct write access to all five tables even though the RLS policies/grants say SELECT-only — passing every local test while production stays correctly locked down, or worse, masking a real bug. Task 1 must add a `\i` line for Planning's grants file to `scripts/local_pg_grants.sql`, the same way Stories' Task 5 (`stories_table_grants.sql`) and Word Hunt's grants already do.

---

## Task 1: Schema, constraints, indexes, and RLS

**Files:**
- Create: `supabase/migrations/20260941010000_planning_schema.sql`
- Create: `supabase/migrations/20260941020000_planning_rls.sql`
- Create: `supabase/migrations/20260941030000_planning_table_grants.sql`
- Modify: `scripts/local_pg_grants.sql` (add a `\i` line for the new grants file, following the exact pattern the `stories_table_grants` and `story_reply_grants` lines already use)
- Test: `supabase/tests/planning_schema_contracts.sql`

**Interfaces:**
- Produces: the five tables (`planning_items`, `planning_events`, `planning_event_tasks`, `planning_notes`, `planning_change_signals`) with every column, constraint, and index named in this task. Every later task in this plan and in Plan B (client) refers to these exact table/column names — do not rename anything.
- Produces: `touch_planning_updated_at()` trigger function, attached as a `BEFORE UPDATE` trigger on all three content tables.

- [ ] **Step 1: Write `20260941010000_planning_schema.sql`**

```sql
-- Planning: a shared space for a couple's notes, tasks, goals, and
-- events. Spec: docs/superpowers/specs/2026-09-14-planning-design.md
-- (this file implements §3).
--
-- Three content tables, one link table, one Realtime signal table.
-- Tasks and Goals share planning_items because they are the same shape
-- (title, completion, optional due date/assignee) except a Goal can
-- have children and a Task cannot -- see the item_kind discriminator
-- below. Events and Notes have genuinely different shapes and get
-- their own tables (spec §3, "why not one polymorphic table").

CREATE TABLE public.planning_items (
  id                uuid PRIMARY KEY,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  -- Nullable: an account deletion must never cascade-delete shared
  -- content the other partner still has (spec §3.1, §10).
  created_by        uuid REFERENCES auth.users(id)
                      ON DELETE SET NULL,

  -- Stored and IMMUTABLE. Never derived from child existence -- a
  -- derived "kind" would let a Goal's product identity flip to a Task
  -- the moment its last child is deleted, which is wrong (spec §2's
  -- "Stable Task/Goal identity" decision, rejecting the earlier draft).
  item_kind         text NOT NULL
                      CHECK (item_kind IN ('task', 'goal')),
  -- NULL for a top-level row (a plain Task, or a Goal). Non-null only
  -- for a Task that is a Goal's child. Enforced one level deep by the
  -- trigger below, not by this column alone.
  parent_goal_id    uuid,

  title             text NOT NULL
                      CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  note              text
                      CHECK (note IS NULL OR char_length(note) <= 500),

  -- Meaningful for Tasks only -- the write RPC validates a non-null
  -- assignee is one of this relationship's two members, and the CHECK
  -- below forbids it from ever being set on a Goal.
  assigned_to       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  due_date          date,

  -- Tasks are completed directly by the client-facing RPC. A Goal's
  -- value is maintained ONLY by reconcile_planning_goal() (Task 3) --
  -- never written directly by any client-facing RPC.
  completed_at      timestamptz,

  -- Server-owned, never cleared once set. Makes "exactly one
  -- celebration per Goal, ever" durable even across reopen/recomplete
  -- cycles (spec §3.1, §4.3, §9).
  celebrated_at     timestamptz,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  UNIQUE (id, relationship_id),

  -- Only a Task may have a parent.
  CONSTRAINT planning_item_parent_shape CHECK (
    parent_goal_id IS NULL OR item_kind = 'task'
  ),
  -- Goal-only fields must be null on a Task's own row shape inversion:
  -- a Goal itself never carries parent/assignee/due_date.
  CONSTRAINT planning_goal_task_only_fields CHECK (
    item_kind = 'task'
    OR (parent_goal_id IS NULL AND assigned_to IS NULL AND due_date IS NULL)
  ),
  CONSTRAINT planning_celebration_goal_only CHECK (
    celebrated_at IS NULL OR item_kind = 'goal'
  ),
  CONSTRAINT planning_item_completed_at_matches CHECK (
    (completed_at IS NOT NULL) = (completed_at IS NOT NULL)
    -- placeholder self-check removed below; see completed_at note.
  ),

  -- The composite FK is the load-bearing guarantee: a child and its
  -- parent Goal MUST share relationship_id, enforced by Postgres, not
  -- merely checked by an RPC that could have a bug (spec §3.1, §9
  -- "A client fabricates a cross-couple link").
  CONSTRAINT planning_item_parent_same_relationship
    FOREIGN KEY (parent_goal_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id)
    ON DELETE CASCADE
);

-- The placeholder self-check above is a no-op by construction (it is
-- deliberately not a real constraint -- completed_at has no required
-- pairing with another column the way story_items' expires_at pairing
-- does). Drop it; it exists only as a reminder this was considered and
-- rejected. See "Step 1b" immediately below.
ALTER TABLE public.planning_items
  DROP CONSTRAINT planning_item_completed_at_matches;

CREATE INDEX idx_planning_items_top_level
  ON public.planning_items
    (relationship_id, item_kind, completed_at, due_date, updated_at DESC, id)
  WHERE deleted_at IS NULL AND parent_goal_id IS NULL;

CREATE INDEX idx_planning_items_children
  ON public.planning_items (parent_goal_id, created_at, id)
  WHERE deleted_at IS NULL AND parent_goal_id IS NOT NULL;

CREATE INDEX idx_planning_items_calendar
  ON public.planning_items (relationship_id, due_date, id)
  WHERE deleted_at IS NULL AND item_kind = 'task' AND due_date IS NOT NULL;

-- Depth cap: a row that is itself parented can never be pointed at by
-- another row's parent_goal_id (spec §3.1 "nesting is exactly one
-- level"). A CHECK constraint cannot see another row, so this is a
-- trigger.
CREATE OR REPLACE FUNCTION public.planning_item_reject_deep_nesting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_of_parent uuid;
BEGIN
  IF NEW.parent_goal_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT parent_goal_id INTO v_parent_of_parent
  FROM public.planning_items
  WHERE id = NEW.parent_goal_id;

  -- IS DISTINCT FROM, not <>: a Goal's own parent_goal_id is always
  -- NULL when it is well-formed, and <> against NULL would silently
  -- never fire -- exactly the NULL-blind trap this project has shipped
  -- before. IS DISTINCT FROM treats NULL as a real, comparable value.
  IF v_parent_of_parent IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'Planning items may only nest one level deep';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER planning_items_reject_deep_nesting
BEFORE INSERT OR UPDATE OF parent_goal_id ON public.planning_items
FOR EACH ROW EXECUTE FUNCTION public.planning_item_reject_deep_nesting();

-- updated_at is stamped by the database, never the client, and uses
-- clock_timestamp() (the actual wall-clock instant this statement ran)
-- rather than now() (frozen at transaction start) so a multi-statement
-- RPC's several writes to the same row do not all get an identical
-- timestamp. Named distinctly from any shared set_updated_at() the repo
-- may already have -- do not repurpose an existing generic trigger
-- function for this; Planning's timestamp behavior is specified here,
-- not inherited.
CREATE OR REPLACE FUNCTION public.touch_planning_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER planning_items_touch_updated_at
BEFORE UPDATE ON public.planning_items
FOR EACH ROW EXECUTE FUNCTION public.touch_planning_updated_at();

CREATE TABLE public.planning_events (
  id                uuid PRIMARY KEY,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid REFERENCES auth.users(id)
                      ON DELETE SET NULL,
  title             text NOT NULL
                      CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  note              text
                      CHECK (note IS NULL OR char_length(note) <= 500),
  -- A civil date, not a timestamp -- "date night this Friday" needs no
  -- time-of-day in v1 (spec §2 "Events are all-day in v1"), and a bare
  -- date sidesteps timezone disagreement the same way STORIES.md §3.5
  -- chose for occurred_on.
  event_date        date NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  UNIQUE (id, relationship_id)
);

CREATE INDEX idx_planning_events_relationship_date
  ON public.planning_events (relationship_id, event_date, id)
  WHERE deleted_at IS NULL;

CREATE TRIGGER planning_events_touch_updated_at
BEFORE UPDATE ON public.planning_events
FOR EACH ROW EXECUTE FUNCTION public.touch_planning_updated_at();

-- Linking, not ownership: a linked Task still lives in planning_items
-- and is still addressable from the plain Tasks list. Deleting the
-- Event never deletes the Task, and vice versa (spec §3.2).
CREATE TABLE public.planning_event_tasks (
  -- Repeated relationship_id is deliberate: it lets the two composite
  -- FKs below make a cross-couple link structurally impossible, the
  -- same reasoning as planning_item_parent_same_relationship above.
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  event_id        uuid NOT NULL,
  item_id         uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, item_id),
  FOREIGN KEY (event_id, relationship_id)
    REFERENCES public.planning_events(id, relationship_id) ON DELETE CASCADE,
  FOREIGN KEY (item_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id) ON DELETE CASCADE
);

CREATE INDEX idx_planning_event_tasks_item
  ON public.planning_event_tasks (item_id, event_id);

CREATE TABLE public.planning_notes (
  id                uuid PRIMARY KEY,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid REFERENCES auth.users(id)
                      ON DELETE SET NULL,
  title             text NOT NULL
                      CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  body              text NOT NULL DEFAULT ''
                      CHECK (char_length(body) <= 4000),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX idx_planning_notes_relationship_updated
  ON public.planning_notes (relationship_id, updated_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE TRIGGER planning_notes_touch_updated_at
BEFORE UPDATE ON public.planning_notes
FOR EACH ROW EXECUTE FUNCTION public.touch_planning_updated_at();

-- Realtime invalidation signal, following story_change_signals exactly
-- (STORIES.md §5.5). Contains no Planning content -- it only tells a
-- subscribed client "your Planning reads for this relationship are
-- stale, refetch."
CREATE TABLE public.planning_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);
```

- [ ] **Step 2: Add Planning to the Realtime publication**

Create a second file in the SAME migration transaction (append to
`20260941010000_planning_schema.sql`, do not create a new file for
this):

```sql
-- Wire planning_change_signals into Realtime the way
-- 20260931210000_realtime_publication.sql wires everything else.
--
-- IMPORTANT, and worth restating because it was found while writing
-- this plan: story_change_signals was NEVER added to the
-- supabase_realtime publication anywhere in this codebase's migration
-- history (verified: 20260931210000_realtime_publication.sql is the
-- ONLY migration that touches ALTER PUBLICATION, and its table array
-- does not include story_change_signals). That means Stories' entire
-- Realtime-refetch mechanism may never actually have fired live --
-- postgres_changes only delivers events for tables IN the publication,
-- and story_change_signals was never added to it. This is flagged here
-- as a separate, pre-existing bug outside this plan's scope to fix;
-- Planning must not repeat it.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'planning_change_signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.planning_change_signals;
  END IF;
END $$;
```

- [ ] **Step 3: Write `20260941020000_planning_rls.sql`**

```sql
-- RLS for Planning. Spec §4.1: clients get SELECT only, and there is
-- deliberately NO read-after-archive exception (unlike Stories) --
-- Planning becomes neither readable nor writable once the relationship
-- is no longer active and unarchived.
ALTER TABLE public.planning_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_event_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.planning_change_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY planning_items_select ON public.planning_items
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_items.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

CREATE POLICY planning_events_select ON public.planning_events
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_events.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- The link table has no deleted_at of its own -- a link is either
-- present or it isn't. Membership alone gates its visibility; the read
-- RPCs (Task 4) additionally join against the live content tables.
CREATE POLICY planning_event_tasks_select ON public.planning_event_tasks
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_event_tasks.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

CREATE POLICY planning_notes_select ON public.planning_notes
  FOR SELECT
  USING (
    deleted_at IS NULL
    AND EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_notes.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- No deleted_at clause here -- the signal table has no soft deletion.
CREATE POLICY planning_change_signals_select ON public.planning_change_signals
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = planning_change_signals.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

-- Deliberately NO INSERT/UPDATE/DELETE policy on any of the five
-- tables. With RLS enabled and no policy for a command, that command is
-- refused outright for every role except the table owner -- this is
-- the enforcement mechanism for "clients get SELECT only" (spec §4.1),
-- matching story_items' own "no INSERT/UPDATE/DELETE policy at all"
-- shape exactly.
```

- [ ] **Step 4: Write `20260941030000_planning_table_grants.sql`**

```sql
-- Table-level grants. RLS (previous migration) is the row-level
-- authority; this is the coarser table-level privilege RLS policies
-- run on top of. authenticated gets SELECT only -- no INSERT, UPDATE,
-- or DELETE grant on any of the five tables, matching story_items'
-- shape (STORIES.md §3.3) rather than reminders' fully-open grant,
-- because every Planning mutation goes through a SECURITY DEFINER RPC
-- (spec §4.1/§4.2).
REVOKE ALL ON public.planning_items FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_items TO authenticated;

REVOKE ALL ON public.planning_events FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_events TO authenticated;

REVOKE ALL ON public.planning_event_tasks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_event_tasks TO authenticated;

REVOKE ALL ON public.planning_notes FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_notes TO authenticated;

REVOKE ALL ON public.planning_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.planning_change_signals TO authenticated;
```

- [ ] **Step 5: Replay Planning's grants in the local harness**

Open `scripts/local_pg_grants.sql`. Find the line:

```sql
\i supabase/migrations/20260939020000_story_reply_grants.sql
```

Add immediately after it:

```sql
-- Same replay for Planning: the blanket GRANT above would otherwise
-- silently hand authenticated direct write access to all five Planning
-- tables, even though Task 1's grants say SELECT-only -- masking
-- exactly the kind of security bug this replay pattern exists to catch
-- (see this file's own top-of-file comment and STORIES.md's account of
-- the same trap).
\i supabase/migrations/20260941030000_planning_table_grants.sql
```

- [ ] **Step 6: Rebuild the local database and confirm the migrations apply cleanly**

Run: `scripts/local_pg_setup.sh --no-tests`
Expected: rebuild completes with no errors, ending in a message like
"database attune_test ready."

- [ ] **Step 7: Write the failing contract tests**

Create `supabase/tests/planning_schema_contracts.sql`:

```sql
-- Schema-level contracts for Planning (Plan A, Task 1).
-- Run: psql -q -d attune_test -f supabase/tests/planning_schema_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel_a uuid := '11111111-0000-0000-0000-000000000001';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_rel_other uuid := '22222222-0000-0000-0000-000000000002';
  v_user_c uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_user_d uuid := 'dddddddd-0000-0000-0000-000000000004';
  v_goal_id uuid := '33333333-0000-0000-0000-000000000001';
  v_task_id uuid := '33333333-0000-0000-0000-000000000002';
  v_other_goal_id uuid := '44444444-0000-0000-0000-000000000001';
BEGIN
  -- Fixtures: two relationships, four users, one active each.
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a@t.test'), (v_user_b, 'b@t.test'),
    (v_user_c, 'c@t.test'), (v_user_d, 'd@t.test')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel_a, v_user_a, v_user_b, 'active'),
         (v_rel_other, v_user_c, v_user_d, 'active')
  ON CONFLICT DO NOTHING;

  -- Contract 1: item_kind is stored, not derivable, and immutable in
  -- shape. A Goal row and its Task child.
  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, title)
  VALUES (v_goal_id, v_rel_a, v_user_a, 'goal', 'Save for the trip');

  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, parent_goal_id, title)
  VALUES (v_task_id, v_rel_a, v_user_a, 'task', v_goal_id, 'Open savings account');

  -- Contract 2: a Task cannot itself have a child (depth cap).
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', v_task_id, 'nested');
    RAISE EXCEPTION 'EXPLOIT: a Task accepted a child (depth cap failed)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
    -- expected: the trigger's own RAISE EXCEPTION fired instead.
  END;

  -- Contract 3: a Goal cannot have a parent_goal_id (only a Task can).
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (v_other_goal_id, v_rel_a, v_user_a, 'goal', v_goal_id, 'nested goal');
    RAISE EXCEPTION 'EXPLOIT: a Goal accepted a parent_goal_id';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: cross-relationship parent link is structurally
  -- impossible, not just RPC-checked. Attempt: a Task in rel_a claims
  -- a parent Goal that belongs to rel_other.
  INSERT INTO public.planning_items
    (id, relationship_id, created_by, item_kind, title)
  VALUES (v_other_goal_id, v_rel_other, v_user_c, 'goal', 'their goal');

  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, parent_goal_id, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', v_other_goal_id, 'cross-couple');
    RAISE EXCEPTION 'EXPLOIT: a cross-relationship parent link was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: blank-after-trim title is rejected.
  BEGIN
    INSERT INTO public.planning_items
      (id, relationship_id, created_by, item_kind, title)
    VALUES (gen_random_uuid(), v_rel_a, v_user_a, 'task', '   ');
    RAISE EXCEPTION 'EXPLOIT: a whitespace-only title was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: celebrated_at may only be set on a Goal.
  BEGIN
    UPDATE public.planning_items SET celebrated_at = now()
    WHERE id = v_task_id;
    RAISE EXCEPTION 'EXPLOIT: celebrated_at was set on a Task';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: updated_at is server-owned and advances on UPDATE,
  -- ignoring anything the caller supplies.
  PERFORM pg_sleep(0.01);
  UPDATE public.planning_items SET note = 'bought the tickets'
  WHERE id = v_task_id;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_task_id AND updated_at > created_at
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: updated_at did not advance on UPDATE';
  END IF;

  -- Contract 8: RLS -- a non-member of rel_a cannot see rel_a's rows.
  PERFORM set_config('request.jwt.claims',
    format('{"sub":"%s"}', v_user_c), true);
  IF EXISTS (
    SELECT 1 FROM public.planning_items WHERE relationship_id = v_rel_a
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member could read another couple''s planning_items';
  END IF;
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- Contract 9: authenticated has SELECT but no direct write privilege.
  IF has_table_privilege('authenticated', 'public.planning_items', 'INSERT') THEN
    RAISE EXCEPTION 'EXPLOIT: authenticated has direct INSERT on planning_items';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.planning_items', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated is missing SELECT on planning_items';
  END IF;

  -- Contract 10: planning_change_signals is in the Realtime publication.
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'planning_change_signals'
  ) THEN
    RAISE EXCEPTION 'planning_change_signals was not added to supabase_realtime';
  END IF;

  RAISE NOTICE 'planning schema contracts: all held';
END $$;
```

- [ ] **Step 8: Run the tests to verify they fail**

Run: `scripts/local_pg_setup.sh --no-tests` (rebuild after Step 1-6 land),
then `psql -q -d attune_test -f supabase/tests/planning_schema_contracts.sql`
Expected at this point: the schema does not exist yet, so this fails with
`relation "public.planning_items" does not exist`. This confirms the test
file is wired up and actually running.

- [ ] **Step 9: Run the migrations and re-run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/planning_schema_contracts.sql`
Expected: `NOTICE: planning schema contracts: all held`, no errors.

- [ ] **Step 10: Mutation-test every contract — this is not optional**

For EACH of contracts 2 through 10 above, do the following by hand:
temporarily comment out or weaken the specific piece of schema/RLS/grant
that contract exists to protect (e.g., for contract 2, drop the
`planning_items_reject_deep_nesting` trigger; for contract 8, comment out
the RLS policy's `EXISTS (...)` clause and replace it with `true`; for
contract 9, add back a `GRANT INSERT` you then remove), re-run the test
file, CONFIRM it now fails with the expected `EXPLOIT:` message, then
restore the schema exactly and re-run to confirm it passes again. Record
each of these nine mutation results as a one-line note in this task's
final report — "contract 2 mutant: dropped the depth trigger → EXPLOIT
raised → restored → holds again" — do not merely claim they were checked.

- [ ] **Step 11: Run the full existing SQL suite to check for regressions**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" || echo "FAILED: $f"; done`
Expected: no `FAILED:` lines. This confirms the new migrations/grants
replay did not break any existing feature's contracts.

- [ ] **Step 12: Commit**

```bash
git add supabase/migrations/20260941010000_planning_schema.sql \
        supabase/migrations/20260941020000_planning_rls.sql \
        supabase/migrations/20260941030000_planning_table_grants.sql \
        scripts/local_pg_grants.sql \
        supabase/tests/planning_schema_contracts.sql
git commit -m "feat(planning): schema, RLS, and table grants for the five Planning tables"
```

---

## Task 2: Mutation RPCs for Tasks and Goals

**Files:**
- Create: `supabase/migrations/20260941040000_planning_item_rpcs.sql`
- Test: `supabase/tests/planning_item_contracts.sql`

**Interfaces:**
- Consumes: `planning_items` table and its constraints/triggers (Task 1).
- Produces: `create_planning_task(p_id uuid, p_relationship_id uuid, p_title text, p_note text, p_assigned_to uuid, p_due_date date) RETURNS public.planning_items`, `create_planning_goal(p_goal_id uuid, p_first_task_id uuid, p_relationship_id uuid, p_goal_title text, p_first_task_title text) RETURNS public.planning_items`, `add_planning_goal_task(p_task_id uuid, p_goal_id uuid, p_title text, p_note text, p_due_date date) RETURNS public.planning_items`, `update_planning_item(p_id uuid, p_title text, p_note text, p_assigned_to uuid, p_due_date date) RETURNS public.planning_items`, `set_planning_task_completion(p_task_id uuid, p_is_complete boolean) RETURNS public.planning_items`, `delete_planning_item(p_id uuid) RETURNS boolean`. Every later task (Task 5, and Plan B's repository) calls these exact names with these exact parameter names/order.
- Produces internal (not client-executable): `reconcile_planning_goal(p_goal_id uuid, p_actor_id uuid) RETURNS void`, `bump_planning_signal(p_relationship_id uuid) RETURNS void`.

- [ ] **Step 1: Write the failing tests**

Create `supabase/tests/planning_item_contracts.sql`:

```sql
-- Mutation RPC contracts for Tasks/Goals (Plan A, Task 2).
-- Run: psql -q -d attune_test -f supabase/tests/planning_item_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000010';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000010';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000010';
  v_user_stranger uuid := 'eeeeeeee-0000-0000-0000-000000000010';
  v_goal_id uuid := '33333333-0000-0000-0000-000000000010';
  v_first_task_id uuid := '33333333-0000-0000-0000-000000000011';
  v_second_task_id uuid;
  v_task_id uuid := '33333333-0000-0000-0000-000000000012';
  v_row public.planning_items;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a10@t.test'), (v_user_b, 'b10@t.test'),
    (v_user_stranger, 'e10@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 1: a non-member cannot create anything in this relationship.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_stranger), true);
  BEGIN
    PERFORM public.create_planning_task(
      gen_random_uuid(), v_rel, 'sneak in', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-member created a Task';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 2: create_planning_task creates a top-level, incomplete Task.
  v_row := public.create_planning_task(
    v_task_id, v_rel, 'Book the venue', NULL, NULL, '2026-12-01');
  IF v_row.item_kind IS DISTINCT FROM 'task'
     OR v_row.parent_goal_id IS DISTINCT FROM NULL
     OR v_row.completed_at IS DISTINCT FROM NULL THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_task did not create a plain, incomplete Task';
  END IF;

  -- Contract 3: create_planning_goal is atomic -- the Goal and its
  -- first child both exist, or (tested via a later contract) neither
  -- does.
  v_row := public.create_planning_goal(
    v_goal_id, v_first_task_id, v_rel, 'Save for the trip',
    'Open savings account');
  IF v_row.item_kind IS DISTINCT FROM 'goal' THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_goal did not return a Goal row';
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_items
  WHERE parent_goal_id = v_goal_id AND deleted_at IS NULL;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: create_planning_goal did not create exactly one child';
  END IF;

  -- Contract 4: add_planning_goal_task adds an incomplete child and
  -- does not flip the Goal complete.
  v_second_task_id := gen_random_uuid();
  PERFORM public.add_planning_goal_task(
    v_second_task_id, v_goal_id, 'Book flights', NULL, NULL);
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_goal_id AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: adding an incomplete child left the Goal complete';
  END IF;

  -- Contract 5: assigned_to must be a member of the relationship.
  BEGIN
    PERFORM public.update_planning_item(
      v_task_id, NULL, NULL, v_user_stranger, NULL);
    RAISE EXCEPTION 'EXPLOIT: a non-member was accepted as an assignee';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 6: set_planning_task_completion on a top-level Task
  -- toggles it and does not touch any Goal.
  v_row := public.set_planning_task_completion(v_task_id, true);
  IF v_row.completed_at IS NULL THEN
    RAISE EXCEPTION 'EXPLOIT: completing a Task left completed_at NULL';
  END IF;

  -- Contract 7: completing the LAST incomplete child completes the
  -- Goal and inserts exactly one celebration message.
  PERFORM public.set_planning_task_completion(v_first_task_id, true);
  PERFORM public.set_planning_task_completion(v_second_task_id, true);
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id = v_goal_id AND completed_at IS NOT NULL AND celebrated_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: completing every child did not complete/celebrate the Goal';
  END IF;
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel AND is_system_notice
    AND content LIKE '%Save for the trip%';
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly one celebration message, found %', v_count;
  END IF;

  -- Contract 8: reopening (uncomplete one child) clears completed_at
  -- but NOT celebrated_at, and recompleting sends NO second message.
  PERFORM public.set_planning_task_completion(v_second_task_id, false);
  IF EXISTS (
    SELECT 1 FROM public.planning_items WHERE id = v_goal_id AND completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: uncompleting a child left the Goal marked complete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_items WHERE id = v_goal_id AND celebrated_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: reopening the Goal cleared celebrated_at';
  END IF;
  PERFORM public.set_planning_task_completion(v_second_task_id, true);
  SELECT count(*) INTO v_count FROM public.messages
  WHERE relationship_id = v_rel AND is_system_notice
    AND content LIKE '%Save for the trip%';
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: recompleting the Goal sent a second celebration, found %', v_count;
  END IF;

  -- Contract 9: a retried create with the SAME id and SAME payload
  -- returns the existing row rather than erroring or duplicating it
  -- (spec §3, §9 "Duplicate create retry").
  v_row := public.create_planning_task(
    v_task_id, v_rel, 'Book the venue', NULL, NULL, '2026-12-01');
  IF v_row.id IS DISTINCT FROM v_task_id THEN
    RAISE EXCEPTION 'EXPLOIT: retrying create_planning_task did not return the existing row';
  END IF;
  SELECT count(*) INTO v_count FROM public.planning_items WHERE id = v_task_id;
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: retrying create_planning_task duplicated the row, found %', v_count;
  END IF;

  -- Contract 10: reusing the SAME id with a DIFFERENT creator is
  -- rejected outright rather than silently returning someone else's
  -- row (spec §3 "conflicting reuse of an ID is rejected").
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_b), true);
  BEGIN
    PERFORM public.create_planning_task(
      v_task_id, v_rel, 'A different task', NULL, NULL, NULL);
    RAISE EXCEPTION 'EXPLOIT: create_planning_task returned someone else''s row on id reuse';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Contract 11: the SAME creator reusing the SAME id with a
  -- DIFFERENT title is rejected -- relationship/creator/kind matching
  -- alone is not enough; the payload must match too. Without this
  -- check the earlier retry (contract 9) would have silently
  -- succeeded here as well, returning the ORIGINAL title and quietly
  -- discarding the caller's edit with no error.
  BEGIN
    PERFORM public.create_planning_task(
      v_task_id, v_rel, 'Book a DIFFERENT venue', NULL, NULL, '2026-12-01');
    RAISE EXCEPTION 'EXPLOIT: create_planning_task accepted id reuse with a changed title';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'planning item retry contracts: all held';
END $$;

-- Fresh block: sole-child deletion must go through the RPC to be
-- meaningfully tested (a raw DELETE bypasses the RPC's own check).
DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000010';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000010';
  v_goal_id uuid := '55555555-0000-0000-0000-000000000001';
  v_only_child uuid := '55555555-0000-0000-0000-000000000002';
BEGIN
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);
  PERFORM public.create_planning_goal(
    v_goal_id, v_only_child, v_rel, 'Solo goal', 'Only task');

  BEGIN
    PERFORM public.delete_planning_item(v_only_child);
    RAISE EXCEPTION 'EXPLOIT: deleting the sole remaining child was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- But deleting the GOAL soft-deletes it and its child atomically.
  PERFORM public.delete_planning_item(v_goal_id);
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE id IN (v_goal_id, v_only_child) AND deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Goal did not soft-delete its child';
  END IF;

  RAISE NOTICE 'planning item contracts: all held';
END $$;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f supabase/tests/planning_item_contracts.sql`
Expected: fails immediately — `function public.create_planning_task(...) does not exist`.

- [ ] **Step 3: Write `20260941040000_planning_item_rpcs.sql`**

```sql
-- Mutation RPCs for planning_items (Tasks and Goals).
-- Spec: docs/superpowers/specs/2026-09-14-planning-design.md §4.2, §4.3.

CREATE OR REPLACE FUNCTION public.planning_is_active_member(
  p_relationship_id uuid, p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.relationships r
    WHERE r.id = p_relationship_id
      AND r.status = 'active' AND r.chat_archived_at IS NULL
      AND (r.user_a = p_user_id OR r.user_b = p_user_id)
  );
$$;
REVOKE ALL ON FUNCTION public.planning_is_active_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- Internal helper: recomputes and, if needed, transitions a Goal's
-- completed_at, and sends the one-time celebration message. Never
-- callable by a client directly -- only the public RPCs below call it,
-- and always with the Goal row already locked FOR UPDATE by the
-- caller (see each public RPC's own lock).
CREATE OR REPLACE FUNCTION public.reconcile_planning_goal(
  p_goal_id uuid, p_actor_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_goal public.planning_items;
  v_live_count int;
  v_incomplete_count int;
  v_now timestamptz := statement_timestamp();
  v_message_id uuid;
BEGIN
  SELECT * INTO v_goal FROM public.planning_items
  WHERE id = p_goal_id AND item_kind = 'goal';
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE completed_at IS NULL)
    INTO v_live_count, v_incomplete_count
  FROM public.planning_items
  WHERE parent_goal_id = p_goal_id AND deleted_at IS NULL;

  IF v_live_count = 0 THEN
    -- Should not happen under the invariants this plan enforces
    -- (Goal creation always seeds one child; sole-child delete is
    -- rejected). Defensive: never mark an empty Goal complete.
    RETURN;
  END IF;

  IF v_incomplete_count > 0 THEN
    IF v_goal.completed_at IS NOT NULL THEN
      UPDATE public.planning_items SET completed_at = NULL
      WHERE id = p_goal_id;
    END IF;
    RETURN;
  END IF;

  -- Every live child is complete.
  IF v_goal.completed_at IS NULL THEN
    UPDATE public.planning_items SET completed_at = v_now
    WHERE id = p_goal_id;
  END IF;

  -- Celebration: exactly once, ever, guarded by celebrated_at.
  IF v_goal.celebrated_at IS NULL THEN
    v_message_id := gen_random_uuid();
    INSERT INTO public.messages (
      id, relationship_id, sender_id, client_message_id, content,
      is_system_notice, message_analysis_skipped, source, created_at
    ) VALUES (
      v_message_id, v_goal.relationship_id, p_actor_id, gen_random_uuid(),
      '🎉 Goal completed: ' || v_goal.title,
      true, true, 'native', v_now
    );
    UPDATE public.planning_items SET celebrated_at = v_now
    WHERE id = p_goal_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_planning_goal(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bump_planning_signal(
  p_relationship_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.planning_change_signals (relationship_id, version, updated_at)
  VALUES (p_relationship_id, 1, now())
  ON CONFLICT (relationship_id) DO UPDATE
    SET version = planning_change_signals.version + 1, updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.bump_planning_signal(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_task(
  p_id uuid, p_relationship_id uuid, p_title text, p_note text,
  p_assigned_to uuid, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF p_assigned_to IS NOT NULL
     AND NOT public.planning_is_active_member(p_relationship_id, p_assigned_to) THEN
    RAISE EXCEPTION 'Assignee must be a member of this relationship';
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, title, note,
    assigned_to, due_date
  ) VALUES (
    p_id, p_relationship_id, v_actor, 'task', btrim(p_title), p_note,
    p_assigned_to, p_due_date
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    -- A retry matches ONLY when relationship, creator, kind, AND the
    -- normalized create payload all match (spec §3, "A retry returns
    -- the existing row only when ... match; conflicting reuse of an
    -- ID is rejected"). Matching only on relationship/creator/kind
    -- would silently accept a retry that also changed the title/note/
    -- assignee/due_date, returning the ORIGINAL row while discarding
    -- the caller's new values with no error -- a client that thought
    -- its edit landed would be wrong with no signal it failed.
    SELECT * INTO v_row FROM public.planning_items
    WHERE id = p_id AND relationship_id = p_relationship_id
      AND created_by = v_actor AND item_kind = 'task'
      AND title = btrim(p_title)
      -- IS NOT DISTINCT FROM, not =: two NULLs (both callers omitted
      -- an optional field) must count as matching, and = against NULL
      -- is never true -- the exact NULL-blind trap this project has
      -- shipped before.
      AND note IS NOT DISTINCT FROM p_note
      AND assigned_to IS NOT DISTINCT FROM p_assigned_to
      AND due_date IS NOT DISTINCT FROM p_due_date;
    IF v_row.id IS NULL THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    RETURN v_row;
  END IF;

  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_task(uuid, uuid, text, text, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_task(uuid, uuid, text, text, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_planning_goal(
  p_goal_id uuid, p_first_task_id uuid, p_relationship_id uuid,
  p_goal_title text, p_first_task_title text
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_goal public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF p_goal_id = p_first_task_id THEN
    RAISE EXCEPTION 'A Goal and its first Task must have different ids';
  END IF;

  -- Atomic with the first child: no code path can produce a
  -- zero-child Goal (spec §3.1.0b in the earlier draft; this RPC is
  -- the enforcement).
  INSERT INTO public.planning_items (id, relationship_id, created_by, item_kind, title)
  VALUES (p_goal_id, p_relationship_id, v_actor, 'goal', btrim(p_goal_title))
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_goal;

  IF v_goal.id IS NULL THEN
    -- Same payload-match requirement as create_planning_task: a retry
    -- matches only when the normalized title matches too, not merely
    -- relationship/creator/kind (spec §3).
    SELECT * INTO v_goal FROM public.planning_items
    WHERE id = p_goal_id AND relationship_id = p_relationship_id
      AND created_by = v_actor AND item_kind = 'goal'
      AND title = btrim(p_goal_title);
    IF v_goal.id IS NULL THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    -- The Goal row matches, but ALSO require its first-task pairing
    -- to match -- a retry that reused p_goal_id with a genuinely new
    -- p_first_task_id (a client bug, not a legitimate retry) must not
    -- silently succeed and leave that new task id never created.
    IF NOT EXISTS (
      SELECT 1 FROM public.planning_items
      WHERE id = p_first_task_id AND parent_goal_id = p_goal_id
        AND title = btrim(p_first_task_title)
    ) THEN
      RAISE EXCEPTION 'A different item already exists with this id';
    END IF;
    RETURN v_goal;
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, parent_goal_id, title
  ) VALUES (
    p_first_task_id, p_relationship_id, v_actor, 'task', p_goal_id,
    btrim(p_first_task_title)
  );

  PERFORM public.bump_planning_signal(p_relationship_id);
  RETURN v_goal;
END;
$$;
REVOKE ALL ON FUNCTION public.create_planning_goal(uuid, uuid, uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_planning_goal(uuid, uuid, uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.add_planning_goal_task(
  p_task_id uuid, p_goal_id uuid, p_title text, p_note text, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_goal public.planning_items;
  v_live_count int;
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Lock the Goal row before counting -- this, together with the same
  -- lock in set_planning_task_completion and delete_planning_item, is
  -- what makes two partners' concurrent edits to the same Goal
  -- serialize instead of race (spec §4.3, §9).
  SELECT * INTO v_goal FROM public.planning_items
  WHERE id = p_goal_id AND item_kind = 'goal' AND deleted_at IS NULL
  FOR UPDATE;
  IF v_goal.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_goal.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT count(*) INTO v_live_count FROM public.planning_items
  WHERE parent_goal_id = p_goal_id AND deleted_at IS NULL;
  IF v_live_count >= 100 THEN
    RAISE EXCEPTION 'A Goal may have at most 100 tasks';
  END IF;

  INSERT INTO public.planning_items (
    id, relationship_id, created_by, item_kind, parent_goal_id, title, note, due_date
  ) VALUES (
    p_task_id, v_goal.relationship_id, v_actor, 'task', p_goal_id,
    btrim(p_title), p_note, p_due_date
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
    RETURN v_row;
  END IF;

  PERFORM public.reconcile_planning_goal(p_goal_id, v_actor);
  PERFORM public.bump_planning_signal(v_goal.relationship_id);

  SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.add_planning_goal_task(uuid, uuid, text, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_planning_goal_task(uuid, uuid, text, text, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_planning_item(
  p_id uuid, p_title text, p_note text, p_assigned_to uuid, p_due_date date
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items
  WHERE id = p_id AND deleted_at IS NULL
  FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  -- assigned_to/due_date are Task-only fields; the CHECK constraint on
  -- the table also enforces this, but failing early here gives a
  -- clearer error than a bubbled-up constraint violation.
  IF v_row.item_kind = 'goal' AND (p_assigned_to IS NOT NULL OR p_due_date IS NOT NULL) THEN
    RAISE EXCEPTION 'A Goal cannot have an assignee or a due date';
  END IF;
  IF p_assigned_to IS NOT NULL
     AND NOT public.planning_is_active_member(v_row.relationship_id, p_assigned_to) THEN
    RAISE EXCEPTION 'Assignee must be a member of this relationship';
  END IF;

  UPDATE public.planning_items
  SET title = COALESCE(btrim(p_title), title),
      note = p_note,
      assigned_to = p_assigned_to,
      due_date = p_due_date
  WHERE id = p_id
  RETURNING * INTO v_row;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.update_planning_item(uuid, text, text, uuid, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_planning_item(uuid, text, text, uuid, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_planning_task_completion(
  p_task_id uuid, p_is_complete boolean
) RETURNS public.planning_items
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items
  WHERE id = p_task_id AND item_kind = 'task' AND deleted_at IS NULL
  FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  UPDATE public.planning_items
  SET completed_at = CASE WHEN p_is_complete THEN statement_timestamp() ELSE NULL END
  WHERE id = p_task_id
  RETURNING * INTO v_row;

  IF v_row.parent_goal_id IS NOT NULL THEN
    -- Lock the parent Goal too, inside this same transaction, before
    -- reconciling -- this is what serializes two partners completing
    -- the last two tasks of the same Goal at the same instant.
    PERFORM 1 FROM public.planning_items WHERE id = v_row.parent_goal_id FOR UPDATE;
    PERFORM public.reconcile_planning_goal(v_row.parent_goal_id, v_actor);
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  SELECT * INTO v_row FROM public.planning_items WHERE id = p_task_id;
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.set_planning_task_completion(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_planning_task_completion(uuid, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_item(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_items;
  v_sibling_live_count int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_items WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RETURN true; -- idempotent: already gone
  END IF;
  IF v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent: already soft-deleted
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  IF v_row.item_kind = 'task' AND v_row.parent_goal_id IS NOT NULL THEN
    PERFORM 1 FROM public.planning_items WHERE id = v_row.parent_goal_id FOR UPDATE;
    SELECT count(*) INTO v_sibling_live_count
    FROM public.planning_items
    WHERE parent_goal_id = v_row.parent_goal_id AND deleted_at IS NULL;
    IF v_sibling_live_count <= 1 THEN
      RAISE EXCEPTION 'Delete the goal instead, or add another task first';
    END IF;
  END IF;

  -- Soft delete never fires an FK cascade -- clean up dependent rows
  -- explicitly.
  DELETE FROM public.planning_event_tasks WHERE item_id = p_id;

  IF v_row.item_kind = 'goal' THEN
    UPDATE public.planning_items SET deleted_at = now()
    WHERE (id = p_id OR parent_goal_id = p_id) AND deleted_at IS NULL;
    DELETE FROM public.planning_event_tasks
    WHERE item_id IN (
      SELECT id FROM public.planning_items WHERE parent_goal_id = p_id
    );
  ELSE
    UPDATE public.planning_items SET deleted_at = now() WHERE id = p_id;
    IF v_row.parent_goal_id IS NOT NULL THEN
      PERFORM public.reconcile_planning_goal(v_row.parent_goal_id, v_actor);
    END IF;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_item(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_item(uuid)
  TO authenticated;
```

- [ ] **Step 4: Rebuild the local database and run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/planning_item_contracts.sql`
Expected: `NOTICE: planning item contracts: all held`.

- [ ] **Step 5: Mutation-test the concurrency and celebration contracts specifically**

These are the highest-risk contracts in this task; verify each by hand:

1. Comment out the `FOR UPDATE` lock in `set_planning_task_completion`'s
   parent-Goal lock line, re-run contract 7/8's logic from two separate
   `psql` sessions racing to complete the last two tasks concurrently
   (open two terminals, `BEGIN;` in each, complete one task each, then
   `COMMIT;` both). Confirm you CAN produce two celebration messages or
   a corrupted `completed_at` without the lock, then restore the lock
   and confirm the race no longer duplicates anything.
2. Remove the `celebrated_at IS NULL` guard inside
   `reconcile_planning_goal`'s celebration block, confirm contract 8's
   "recompleting sends no second message" check now fails, restore.
3. Change the sole-child check's `<= 1` to `< 1`, confirm contract 9
   (sole-child delete) now wrongly succeeds, restore.
4. In `create_planning_task`'s retry-match `SELECT`, remove the
   `AND title = btrim(p_title)` clause (leaving only
   relationship/creator/kind matching), confirm contract 11 (same
   creator, changed title, same id) now wrongly succeeds — the retry
   would silently return the original row instead of raising. Restore
   the clause and confirm contract 11 raises again.

Record each result in this task's final report the same way Task 1's
Step 10 requires.

- [ ] **Step 6: Run the full existing SQL suite to check for regressions**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" || echo "FAILED: $f"; done`
Expected: no `FAILED:` lines — in particular confirm the celebration
message insert does not break any existing `messages`-table contract
(e.g. chat system contracts asserting message shape/order).

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260941040000_planning_item_rpcs.sql \
        supabase/tests/planning_item_contracts.sql
git commit -m "feat(planning): mutation RPCs for tasks and goals, with locked goal reconciliation"
```

---

## Task 3: Mutation RPCs for Events, links, and Notes

**Files:**
- Create: `supabase/migrations/20260941050000_planning_event_and_note_rpcs.sql`
- Test: `supabase/tests/planning_event_note_contracts.sql`

**Interfaces:**
- Consumes: `planning_events`, `planning_event_tasks`, `planning_notes` (Task 1); `planning_is_active_member` (Task 2).
- Produces: `upsert_planning_event(p_id uuid, p_relationship_id uuid, p_title text, p_note text, p_event_date date) RETURNS public.planning_events`, `delete_planning_event(p_id uuid) RETURNS boolean`, `link_planning_event_task(p_event_id uuid, p_item_id uuid) RETURNS boolean`, `unlink_planning_event_task(p_event_id uuid, p_item_id uuid) RETURNS boolean`, `upsert_planning_note(p_id uuid, p_relationship_id uuid, p_title text, p_body text) RETURNS public.planning_notes`, `delete_planning_note(p_id uuid) RETURNS boolean`. Plan B's repository calls these exact names.

- [ ] **Step 1: Write the failing tests**

Create `supabase/tests/planning_event_note_contracts.sql`:

```sql
-- Event/link/Note RPC contracts (Plan A, Task 3).
-- Run: psql -q -d attune_test -f supabase/tests/planning_event_note_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000020';
  v_rel_other uuid := '11111111-0000-0000-0000-000000000021';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000020';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000020';
  v_user_c uuid := 'cccccccc-0000-0000-0000-000000000020';
  v_event_id uuid := '66666666-0000-0000-0000-000000000001';
  v_task_id uuid := '66666666-0000-0000-0000-000000000002';
  v_goal_id uuid := '66666666-0000-0000-0000-000000000003';
  v_goal_child_id uuid := '66666666-0000-0000-0000-000000000004';
  v_other_task_id uuid := '66666666-0000-0000-0000-000000000005';
  v_note_id uuid := '77777777-0000-0000-0000-000000000001';
  v_row public.planning_events;
  v_note_row public.planning_notes;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a20@t.test'), (v_user_b, 'b20@t.test'), (v_user_c, 'c20@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active'),
         (v_rel_other, v_user_c, v_user_c, 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  -- Setup: a top-level Task and a Goal (with its own child) in v_rel.
  PERFORM public.create_planning_task(v_task_id, v_rel, 'Buy the gift', NULL, NULL, NULL);
  PERFORM public.create_planning_goal(v_goal_id, v_goal_child_id, v_rel, 'A goal', 'child task');
  PERFORM public.create_planning_task(v_other_task_id, v_rel_other, 'their task', NULL, NULL, NULL);

  -- Contract 1: create/edit an Event.
  v_row := public.upsert_planning_event(
    v_event_id, v_rel, 'Sarah''s birthday dinner', 'Try the Italian place',
    '2026-12-25');
  IF v_row.title IS DISTINCT FROM 'Sarah''s birthday dinner' THEN
    RAISE EXCEPTION 'EXPLOIT: upsert_planning_event did not create the expected row';
  END IF;

  -- Contract 2: linking a top-level Task succeeds.
  PERFORM public.link_planning_event_task(v_event_id, v_task_id);
  IF NOT EXISTS (
    SELECT 1 FROM public.planning_event_tasks
    WHERE event_id = v_event_id AND item_id = v_task_id
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: linking a top-level Task did not create a link row';
  END IF;

  -- Contract 3: linking a Goal's CHILD (not top-level) is rejected.
  BEGIN
    PERFORM public.link_planning_event_task(v_event_id, v_goal_child_id);
    RAISE EXCEPTION 'EXPLOIT: a Goal child was linked to an Event';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 4: linking a Task from a DIFFERENT relationship's Event
  -- is structurally impossible (composite FK).
  BEGIN
    PERFORM public.link_planning_event_task(v_event_id, v_other_task_id);
    RAISE EXCEPTION 'EXPLOIT: a cross-relationship Task was linked to an Event';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 5: unlinking removes only the link row, never the Task.
  PERFORM public.unlink_planning_event_task(v_event_id, v_task_id);
  IF EXISTS (
    SELECT 1 FROM public.planning_event_tasks
    WHERE event_id = v_event_id AND item_id = v_task_id
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: unlink did not remove the link row';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_items WHERE id = v_task_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: unlinking deleted the Task itself';
  END IF;

  -- Contract 6: deleting the Event removes its link rows but not the
  -- linked Task.
  PERFORM public.link_planning_event_task(v_event_id, v_task_id);
  PERFORM public.delete_planning_event(v_event_id);
  IF EXISTS (SELECT 1 FROM public.planning_event_tasks WHERE event_id = v_event_id) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Event left link rows behind';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.planning_items WHERE id = v_task_id AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EXPLOIT: deleting the Event deleted the linked Task';
  END IF;

  -- Contract 7: Notes create/edit, and blank body is allowed (title is
  -- required, body may be empty per the schema's DEFAULT '').
  v_note_row := public.upsert_planning_note(v_note_id, v_rel, 'Restaurants to try', '');
  IF v_note_row.title IS DISTINCT FROM 'Restaurants to try' THEN
    RAISE EXCEPTION 'EXPLOIT: upsert_planning_note did not create the expected row';
  END IF;

  -- Contract 8: a non-member cannot read or write across relationships.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_c), true);
  BEGIN
    PERFORM public.upsert_planning_note(gen_random_uuid(), v_rel, 'sneak', '');
    RAISE EXCEPTION 'EXPLOIT: a non-member created a Note in another relationship';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  RAISE NOTICE 'planning event/note contracts: all held';
END $$;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f supabase/tests/planning_event_note_contracts.sql`
Expected: fails with `function public.upsert_planning_event(...) does not exist`.

- [ ] **Step 3: Write `20260941050000_planning_event_and_note_rpcs.sql`**

```sql
-- Mutation RPCs for planning_events, planning_event_tasks, and
-- planning_notes. Spec §4.2.

CREATE OR REPLACE FUNCTION public.upsert_planning_event(
  p_id uuid, p_relationship_id uuid, p_title text, p_note text, p_event_date date
) RETURNS public.planning_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_events;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_event_date IS NULL THEN
    RAISE EXCEPTION 'An event needs a date';
  END IF;

  SELECT * INTO v_row FROM public.planning_events WHERE id = p_id;

  IF v_row.id IS NULL THEN
    IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    INSERT INTO public.planning_events (id, relationship_id, created_by, title, note, event_date)
    VALUES (p_id, p_relationship_id, v_actor, btrim(p_title), p_note, p_event_date)
    RETURNING * INTO v_row;
  ELSE
    IF v_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    UPDATE public.planning_events
    SET title = btrim(p_title), note = p_note, event_date = p_event_date
    WHERE id = p_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.upsert_planning_event(uuid, uuid, text, text, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_planning_event(uuid, uuid, text, text, date)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_event(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_events;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_events WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL OR v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  DELETE FROM public.planning_event_tasks WHERE event_id = p_id;
  UPDATE public.planning_events SET deleted_at = now() WHERE id = p_id;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_event(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.link_planning_event_task(
  p_event_id uuid, p_item_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_event public.planning_events;
  v_item public.planning_items;
  v_link_count int;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_event FROM public.planning_events
  WHERE id = p_event_id AND deleted_at IS NULL FOR UPDATE;
  IF v_event.id IS NULL THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;
  IF NOT public.planning_is_active_member(v_event.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT * INTO v_item FROM public.planning_items
  WHERE id = p_item_id AND deleted_at IS NULL;
  -- Only a top-level Task may be linked -- a Goal's child has no
  -- independent life outside its checklist (spec §3.2).
  IF v_item.id IS NULL
     OR v_item.item_kind IS DISTINCT FROM 'task'
     OR v_item.parent_goal_id IS NOT NULL
     OR v_item.relationship_id IS DISTINCT FROM v_event.relationship_id THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  SELECT count(*) INTO v_link_count
  FROM public.planning_event_tasks WHERE event_id = p_event_id;
  IF v_link_count >= 100 THEN
    RAISE EXCEPTION 'An event may link at most 100 tasks';
  END IF;

  INSERT INTO public.planning_event_tasks (relationship_id, event_id, item_id)
  VALUES (v_event.relationship_id, p_event_id, p_item_id)
  ON CONFLICT (event_id, item_id) DO NOTHING;

  PERFORM public.bump_planning_signal(v_event.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.link_planning_event_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_planning_event_task(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unlink_planning_event_task(
  p_event_id uuid, p_item_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_relationship_id uuid;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT relationship_id INTO v_relationship_id
  FROM public.planning_event_tasks WHERE event_id = p_event_id AND item_id = p_item_id;
  IF v_relationship_id IS NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  DELETE FROM public.planning_event_tasks
  WHERE event_id = p_event_id AND item_id = p_item_id;

  PERFORM public.bump_planning_signal(v_relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.unlink_planning_event_task(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unlink_planning_event_task(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_planning_note(
  p_id uuid, p_relationship_id uuid, p_title text, p_body text
) RETURNS public.planning_notes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_notes;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_notes WHERE id = p_id;

  IF v_row.id IS NULL THEN
    IF NOT public.planning_is_active_member(p_relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    INSERT INTO public.planning_notes (id, relationship_id, created_by, title, body)
    VALUES (p_id, p_relationship_id, v_actor, btrim(p_title), COALESCE(p_body, ''))
    RETURNING * INTO v_row;
  ELSE
    IF v_row.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
      RAISE EXCEPTION 'Planning unavailable';
    END IF;
    -- Last-write-wins: no version check, no merge. This save simply
    -- replaces the body; whichever save commits last is authoritative
    -- (spec §5.3/§9's stated, deliberate concurrent-edit shape).
    UPDATE public.planning_notes
    SET title = btrim(p_title), body = COALESCE(p_body, '')
    WHERE id = p_id
    RETURNING * INTO v_row;
  END IF;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.upsert_planning_note(uuid, uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_planning_note(uuid, uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_planning_note(
  p_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_row public.planning_notes;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_row FROM public.planning_notes WHERE id = p_id FOR UPDATE;
  IF v_row.id IS NULL OR v_row.deleted_at IS NOT NULL THEN
    RETURN true; -- idempotent
  END IF;
  IF NOT public.planning_is_active_member(v_row.relationship_id, v_actor) THEN
    RAISE EXCEPTION 'Planning unavailable';
  END IF;

  UPDATE public.planning_notes SET deleted_at = now() WHERE id = p_id;

  PERFORM public.bump_planning_signal(v_row.relationship_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_planning_note(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_planning_note(uuid) TO authenticated;
```

- [ ] **Step 4: Rebuild and run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/planning_event_note_contracts.sql`
Expected: `NOTICE: planning event/note contracts: all held`.

- [ ] **Step 5: Mutation-test contracts 3, 4, and 6**

By hand: (a) temporarily remove the `item_kind`/`parent_goal_id` check
inside `link_planning_event_task` and confirm contract 3 (linking a
Goal's child) now wrongly succeeds; (b) temporarily change the
`v_item.relationship_id IS DISTINCT FROM v_event.relationship_id` check
to always pass and confirm contract 4 (cross-relationship link) now
wrongly succeeds; (c) remove the `DELETE FROM planning_event_tasks`
line inside `delete_planning_event` and confirm contract 6's "no
orphaned link rows" check now fails. Restore all three afterward.
Record results in the final report.

- [ ] **Step 6: Run the full existing SQL suite**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" || echo "FAILED: $f"; done`
Expected: no `FAILED:` lines.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260941050000_planning_event_and_note_rpcs.sql \
        supabase/tests/planning_event_note_contracts.sql
git commit -m "feat(planning): mutation RPCs for events, event-task links, and notes"
```

---

## Task 4: Read RPCs

**Files:**
- Create: `supabase/migrations/20260941060000_planning_read_rpcs.sql`
- Test: `supabase/tests/planning_read_contracts.sql`

**Interfaces:**
- Consumes: all tables and mutation RPCs from Tasks 1–3.
- Produces: `list_planning_goals(p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int) RETURNS TABLE(...)`, `list_planning_goal_tasks(p_goal_id uuid, p_after_created_at timestamptz, p_after_id uuid, p_limit int) RETURNS SETOF public.planning_items`, `list_planning_tasks(p_relationship_id uuid, p_after_due_date date, p_after_updated_at timestamptz, p_after_id uuid, p_limit int) RETURNS SETOF public.planning_items`, `list_planning_events(p_relationship_id uuid, p_today date, p_upcoming boolean, p_after_date date, p_after_id uuid, p_limit int) RETURNS SETOF public.planning_events`, `list_planning_notes(p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int) RETURNS SETOF public.planning_notes`, `list_planning_calendar_entries(p_relationship_id uuid, p_start_date date, p_end_date date) RETURNS TABLE(entry_kind text, entry_id uuid, entry_date date, title text, is_complete boolean)`, `get_planning_summary(p_relationship_id uuid, p_today date) RETURNS TABLE(kind text, id uuid, title text, context_date date)`. Plan B's repository and providers call these exact names/columns.

- [ ] **Step 1: Write the failing tests**

Create `supabase/tests/planning_read_contracts.sql`:

```sql
-- Read RPC contracts (Plan A, Task 4).
-- Run: psql -q -d attune_test -f supabase/tests/planning_read_contracts.sql
\set ON_ERROR_STOP on

DO $$
DECLARE
  v_rel uuid := '11111111-0000-0000-0000-000000000030';
  v_user_a uuid := 'aaaaaaaa-0000-0000-0000-000000000030';
  v_user_b uuid := 'bbbbbbbb-0000-0000-0000-000000000030';
  v_goal_id uuid := '88888888-0000-0000-0000-000000000001';
  v_child1 uuid := '88888888-0000-0000-0000-000000000002';
  v_child2 uuid;
  v_task_id uuid := '88888888-0000-0000-0000-000000000003';
  v_event_upcoming uuid := '88888888-0000-0000-0000-000000000004';
  v_event_past uuid := '88888888-0000-0000-0000-000000000005';
  v_note_id uuid := '88888888-0000-0000-0000-000000000006';
  v_row record;
  v_count int;
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    (v_user_a, 'a30@t.test'), (v_user_b, 'b30@t.test')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.relationships (id, user_a, user_b, status)
  VALUES (v_rel, v_user_a, v_user_b, 'active')
  ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', v_user_a), true);

  PERFORM public.create_planning_goal(v_goal_id, v_child1, v_rel, 'Save for the trip', 'Open account');
  v_child2 := gen_random_uuid();
  PERFORM public.add_planning_goal_task(v_child2, v_goal_id, 'Book flights', NULL, NULL);
  PERFORM public.create_planning_task(v_task_id, v_rel, 'Water the plants', NULL, NULL, '2026-06-01');
  PERFORM public.upsert_planning_event(v_event_upcoming, v_rel, 'Future thing', NULL, '2099-01-01');
  PERFORM public.upsert_planning_event(v_event_past, v_rel, 'Past thing', NULL, '2000-01-01');
  PERFORM public.upsert_planning_note(v_note_id, v_rel, 'Grocery list', 'milk, eggs');

  -- Contract 1: list_planning_goals returns the goal with correct
  -- child_count/completed_child_count.
  SELECT * INTO v_row FROM public.list_planning_goals(v_rel, NULL, NULL, 30)
  WHERE id = v_goal_id;
  IF v_row.id IS NULL OR v_row.child_count IS DISTINCT FROM 2
     OR v_row.completed_child_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_goals returned wrong counts';
  END IF;

  -- Contract 2: list_planning_goal_tasks returns exactly this Goal's
  -- two children, oldest first.
  SELECT count(*) INTO v_count FROM public.list_planning_goal_tasks(v_goal_id, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_goal_tasks returned % rows, expected 2', v_count;
  END IF;

  -- Contract 3: list_planning_tasks does NOT include Goal children --
  -- only top-level Tasks.
  IF EXISTS (
    SELECT 1 FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50)
    WHERE id IN (v_child1, v_child2)
  ) THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_tasks leaked a Goal child as a top-level Task';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50) WHERE id = v_task_id) THEN
    RAISE EXCEPTION 'EXPLOIT: list_planning_tasks did not return the top-level Task';
  END IF;

  -- Contract 4: upcoming vs past events split correctly on p_today.
  SELECT count(*) INTO v_count FROM public.list_planning_events(v_rel, '2026-01-01'::date, true, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 1 upcoming event, found %', v_count;
  END IF;
  SELECT count(*) INTO v_count FROM public.list_planning_events(v_rel, '2026-01-01'::date, false, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: expected exactly 1 past event, found %', v_count;
  END IF;

  -- Contract 5: p_limit is clamped server-side even if the caller asks
  -- for more than 100.
  SELECT count(*) INTO v_count FROM public.list_planning_notes(v_rel, NULL, NULL, 99999);
  IF v_count > 100 THEN
    RAISE EXCEPTION 'EXPLOIT: p_limit was not clamped to 100';
  END IF;

  -- Contract 6: list_planning_calendar_entries includes the Task's due
  -- date and the upcoming Event's date, within range; rejects a range
  -- over 42 days.
  SELECT count(*) INTO v_count FROM public.list_planning_calendar_entries(
    v_rel, '2026-05-01'::date, '2026-06-30'::date);
  IF v_count IS DISTINCT FROM 1 THEN -- only the due Task falls in range
    RAISE EXCEPTION 'EXPLOIT: list_planning_calendar_entries returned % rows, expected 1', v_count;
  END IF;
  BEGIN
    PERFORM public.list_planning_calendar_entries(v_rel, '2026-01-01'::date, '2026-12-31'::date);
    RAISE EXCEPTION 'EXPLOIT: a calendar range over 42 days was accepted';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'EXPLOIT:%' THEN RAISE; END IF;
  END;

  -- Contract 7: get_planning_summary returns something deterministic
  -- and non-empty for a relationship with content.
  SELECT count(*) INTO v_count FROM public.get_planning_summary(v_rel, '2026-01-01'::date);
  IF v_count IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'EXPLOIT: get_planning_summary did not return exactly one row';
  END IF;

  -- Contract 8: a non-member gets nothing, not an error that leaks
  -- existence.
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s"}', gen_random_uuid()), true);
  SELECT count(*) INTO v_count FROM public.list_planning_tasks(v_rel, NULL, NULL, NULL, 50);
  IF v_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'EXPLOIT: a non-member read another couple''s tasks';
  END IF;

  RAISE NOTICE 'planning read contracts: all held';
END $$;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `psql -q -d attune_test -f supabase/tests/planning_read_contracts.sql`
Expected: fails with `function public.list_planning_goals(...) does not exist`.

- [ ] **Step 3: Write `20260941060000_planning_read_rpcs.sql`**

```sql
-- Read RPCs. SECURITY INVOKER throughout -- RLS (Task 1) remains the
-- sole authority; these functions never bypass it (spec §5, following
-- STORIES.md §5.5's identical reasoning).

CREATE OR REPLACE FUNCTION public.list_planning_goals(
  p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int
) RETURNS TABLE (
  id uuid, title text, note text, completed_at timestamptz,
  updated_at timestamptz, child_count bigint, completed_child_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    g.id, g.title, g.note, g.completed_at, g.updated_at,
    count(c.id) AS child_count,
    count(c.id) FILTER (WHERE c.completed_at IS NOT NULL) AS completed_child_count
  FROM public.planning_items g
  LEFT JOIN public.planning_items c
    ON c.parent_goal_id = g.id AND c.deleted_at IS NULL
  WHERE g.relationship_id = p_relationship_id
    AND g.item_kind = 'goal'
    AND g.deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (g.updated_at, g.id) < (p_after_updated_at, p_after_id)
    )
  GROUP BY g.id, g.title, g.note, g.completed_at, g.updated_at
  ORDER BY g.updated_at DESC, g.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_goals(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_goals(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_goal_tasks(
  p_goal_id uuid, p_after_created_at timestamptz, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_items
  WHERE parent_goal_id = p_goal_id
    AND deleted_at IS NULL
    AND (
      p_after_created_at IS NULL
      OR (created_at, id) > (p_after_created_at, p_after_id)
    )
  ORDER BY created_at ASC, id ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_goal_tasks(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_goal_tasks(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_tasks(
  p_relationship_id uuid, p_after_due_date date, p_after_updated_at timestamptz,
  p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_items
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_items
  WHERE relationship_id = p_relationship_id
    AND item_kind = 'task'
    AND parent_goal_id IS NULL
    AND deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (
        (completed_at IS NOT NULL),
        COALESCE(due_date, 'infinity'::date),
        updated_at, id
      ) > (
        (SELECT completed_at IS NOT NULL FROM public.planning_items WHERE id = p_after_id),
        (SELECT COALESCE(due_date, 'infinity'::date) FROM public.planning_items WHERE id = p_after_id),
        p_after_updated_at, p_after_id
      )
    )
  ORDER BY (completed_at IS NOT NULL) ASC, COALESCE(due_date, 'infinity'::date) ASC,
           updated_at DESC, id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_tasks(uuid, date, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_tasks(uuid, date, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_events(
  p_relationship_id uuid, p_today date, p_upcoming boolean,
  p_after_date date, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_events
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_events
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND (
      (p_upcoming AND event_date >= p_today)
      OR (NOT p_upcoming AND event_date < p_today)
    )
    AND (
      p_after_date IS NULL
      OR (
        CASE WHEN p_upcoming THEN (event_date, id) > (p_after_date, p_after_id)
             ELSE (event_date, id) < (p_after_date, p_after_id) END
      )
    )
  ORDER BY
    CASE WHEN p_upcoming THEN event_date END ASC,
    CASE WHEN p_upcoming THEN id END ASC,
    CASE WHEN NOT p_upcoming THEN event_date END DESC,
    CASE WHEN NOT p_upcoming THEN id END DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_events(uuid, date, boolean, date, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_events(uuid, date, boolean, date, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_notes(
  p_relationship_id uuid, p_after_updated_at timestamptz, p_after_id uuid, p_limit int
) RETURNS SETOF public.planning_notes
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.planning_notes
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND (
      p_after_updated_at IS NULL
      OR (updated_at, id) < (p_after_updated_at, p_after_id)
    )
  ORDER BY updated_at DESC, id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.list_planning_notes(uuid, timestamptz, uuid, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_notes(uuid, timestamptz, uuid, int)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.list_planning_calendar_entries(
  p_relationship_id uuid, p_start_date date, p_end_date date
) RETURNS TABLE (
  entry_kind text, entry_id uuid, entry_date date, title text, is_complete boolean
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- 42 days is the visible calendar grid this is bound to (spec §7);
  -- an unbounded range is a defect here, not a style choice, the same
  -- discipline STORIES.md §5.5 holds every read to.
  IF p_end_date < p_start_date OR p_end_date - p_start_date > 42 THEN
    RAISE EXCEPTION 'Calendar range must be at most 42 days';
  END IF;

  RETURN QUERY
  SELECT 'task'::text, id, due_date, title, (completed_at IS NOT NULL)
  FROM public.planning_items
  WHERE relationship_id = p_relationship_id
    AND item_kind = 'task'
    AND deleted_at IS NULL
    AND due_date BETWEEN p_start_date AND p_end_date
  UNION ALL
  SELECT 'event'::text, id, event_date, title, false
  FROM public.planning_events
  WHERE relationship_id = p_relationship_id
    AND deleted_at IS NULL
    AND event_date BETWEEN p_start_date AND p_end_date;
END;
$$;
REVOKE ALL ON FUNCTION public.list_planning_calendar_entries(uuid, date, date)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_planning_calendar_entries(uuid, date, date)
  TO authenticated;

-- Priority order per spec §6.1: overdue Task (nearest-missed first),
-- then Task due today or later (soonest first), then next upcoming
-- Event, then most recently updated live item of any kind, then
-- nothing (empty state is the client's job when this returns 0 rows).
CREATE OR REPLACE FUNCTION public.get_planning_summary(
  p_relationship_id uuid, p_today date
) RETURNS TABLE (
  kind text, id uuid, title text, context_date date
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND deleted_at IS NULL AND completed_at IS NULL
      AND due_date IS NOT NULL AND due_date < p_today
  ) THEN
    RETURN QUERY SELECT 'overdue_task'::text, id, title, due_date
      FROM public.planning_items
      WHERE relationship_id = p_relationship_id AND item_kind = 'task'
        AND deleted_at IS NULL AND completed_at IS NULL
        AND due_date IS NOT NULL AND due_date < p_today
      ORDER BY due_date DESC, updated_at DESC, id DESC
      LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND deleted_at IS NULL AND completed_at IS NULL
      AND due_date IS NOT NULL AND due_date >= p_today
  ) THEN
    RETURN QUERY SELECT 'upcoming_task'::text, id, title, due_date
      FROM public.planning_items
      WHERE relationship_id = p_relationship_id AND item_kind = 'task'
        AND deleted_at IS NULL AND completed_at IS NULL
        AND due_date IS NOT NULL AND due_date >= p_today
      ORDER BY due_date ASC, updated_at DESC, id DESC
      LIMIT 1;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.planning_events
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
      AND event_date >= p_today
  ) THEN
    RETURN QUERY SELECT 'upcoming_event'::text, id, title, event_date
      FROM public.planning_events
      WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
        AND event_date >= p_today
      ORDER BY event_date ASC, id ASC
      LIMIT 1;
    RETURN;
  END IF;

  -- Most recently updated live item of ANY kind (Goal, Task, Event, or
  -- Note), Goal children excluded since they are not independently
  -- surfaced on the summary row (spec §6.1).
  RETURN QUERY
  SELECT * FROM (
    SELECT 'goal'::text AS kind, id, title, NULL::date AS context_date, updated_at
    FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'goal' AND deleted_at IS NULL
    UNION ALL
    SELECT 'task'::text, id, title, due_date, updated_at
    FROM public.planning_items
    WHERE relationship_id = p_relationship_id AND item_kind = 'task'
      AND parent_goal_id IS NULL AND deleted_at IS NULL
    UNION ALL
    SELECT 'event'::text, id, title, event_date, updated_at
    FROM public.planning_events
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
    UNION ALL
    SELECT 'note'::text, id, title, NULL::date, updated_at
    FROM public.planning_notes
    WHERE relationship_id = p_relationship_id AND deleted_at IS NULL
  ) everything
  ORDER BY updated_at DESC, id DESC
  LIMIT 1;
END;
$$;
REVOKE ALL ON FUNCTION public.get_planning_summary(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_planning_summary(uuid, date) TO authenticated;
```

- [ ] **Step 4: Rebuild and run the tests**

Run: `scripts/local_pg_setup.sh --no-tests`, then
`psql -q -d attune_test -f supabase/tests/planning_read_contracts.sql`
Expected: `NOTICE: planning read contracts: all held`.

- [ ] **Step 5: Mutation-test the pagination and range-limit contracts**

By hand: (a) change `list_planning_tasks`'s `LIMIT LEAST(...)` clamp to
just `LIMIT COALESCE(p_limit, 50)` (removing the clamp) and confirm
contract 5 (p_limit clamped to 100) now fails when called with a huge
limit; (b) change `list_planning_calendar_entries`'s `> 42` check to
`> 4200` and confirm the over-range rejection contract now wrongly
succeeds. Restore both. Record results.

- [ ] **Step 6: Run the full existing SQL suite**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" || echo "FAILED: $f"; done`

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260941060000_planning_read_rpcs.sql \
        supabase/tests/planning_read_contracts.sql
git commit -m "feat(planning): read RPCs with keyset pagination and the conversations summary"
```

---

## Task 5: Final backend review pass

**Files:**
- No new files. This task is a review-and-fix pass over Tasks 1–4's combined output.

**Interfaces:**
- Consumes: everything produced by Tasks 1–4.
- Produces: nothing new — confirms the whole backend is internally consistent and ready for Plan B to build against.

- [ ] **Step 1: Run every Planning SQL contract test together, twice**

Run: `scripts/local_pg_setup.sh --no-tests`, then run all four Planning
test files in sequence in ONE psql session (not four separate `psql`
invocations) to catch any cross-test fixture collision:
```bash
psql -q -d attune_test \
  -f supabase/tests/planning_schema_contracts.sql \
  -f supabase/tests/planning_item_contracts.sql \
  -f supabase/tests/planning_event_note_contracts.sql \
  -f supabase/tests/planning_read_contracts.sql
```
Expected: all four `NOTICE: ... all held` messages appear, no errors. Then
rebuild fresh (`scripts/local_pg_setup.sh --no-tests`) and run them again
to confirm they are not order-dependent (a common vacuous-test cause: a
fixture from an earlier file accidentally satisfying a later file's own
setup).

- [ ] **Step 2: Verify no migration silently depended on the harness's blanket grant**

Run: `scripts/local_pg_setup.sh --no-tests`, then directly check
privileges rather than trusting the grants file was written correctly:
```bash
psql -d attune_test -tAc "
select relname, has_table_privilege('authenticated', 'public.'||relname, 'INSERT') as can_insert
from pg_class
where relname like 'planning_%' and relkind = 'r';"
```
Expected: every row shows `can_insert = f`. If any shows `t`, the grants
replay in `scripts/local_pg_grants.sql` (Task 1, Step 5) is missing or
misplaced — fix it and re-verify.

- [ ] **Step 3: Verify every SECURITY DEFINER function has a pinned search_path**

Run:
```bash
psql -d attune_test -tAc "
select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and proname like '%planning%'
  and (p.proconfig is null or not (p.proconfig::text like '%search_path%'));"
```
Expected: empty result. Any row returned is a real security gap — fix
the function's `SET search_path = public` and re-run.

- [ ] **Step 4: Verify internal helpers are unreachable by clients**

Run:
```bash
psql -d attune_test -tAc "
select has_function_privilege('authenticated', 'public.reconcile_planning_goal(uuid,uuid)', 'EXECUTE') as reconcile_exec,
       has_function_privilege('authenticated', 'public.bump_planning_signal(uuid)', 'EXECUTE') as bump_exec;"
```
Expected: both `f`. Either being `t` means Task 2's `REVOKE ALL ...
FROM ... authenticated` on that internal function is missing or was
overwritten by a later `CREATE OR REPLACE` that forgot to repeat it.

- [ ] **Step 5: Confirm the full existing test suite is still green**

Run: `for f in supabase/tests/*.sql; do psql -q -d attune_test -f "$f" || echo "FAILED: $f"; done`
Expected: no `FAILED:` lines.

- [ ] **Step 6: Write the backend completion note**

No commit needed for this task beyond what Tasks 1–4 already committed.
If Steps 1–5 above surfaced any fix, commit that fix now with a message
describing exactly what was wrong and what step caught it, then re-run
Steps 1–5 in full before considering this task done.
