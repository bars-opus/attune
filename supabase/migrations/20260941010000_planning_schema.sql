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
--
-- Also enforces item_kind immutability (folded into this same trigger
-- rather than a second one, since both are "reject this UPDATE outright"
-- checks on planning_items and the trigger already fires on every
-- INSERT/UPDATE this table cares about protecting).
--
-- Two directions of the depth cap, both required -- a fix landed after
-- initial review found the first version only checked one of them:
--   1. Forward: NEW.parent_goal_id must not itself be a parented row
--      (checked by v_parent_of_parent below -- this was already here).
--   2. Reverse: NEW.id must not currently be SOMEONE ELSE's parent when
--      it is about to acquire a parent_goal_id of its own. Without this
--      check, re-parenting a Goal that already has a child (UPDATE ...
--      SET item_kind = 'task', parent_goal_id = <other top-level goal>
--      WHERE id = <goal-with-a-child>) slipped through: the forward
--      check only looks at the NEW parent's shape, never at whether the
--      row being updated is itself already relied upon as a parent by
--      some third row. That produced a live 3-level chain
--      (child -> this row -> its new parent), directly violating "nest
--      exactly one level, structurally."
CREATE OR REPLACE FUNCTION public.planning_item_reject_deep_nesting()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_of_parent uuid;
BEGIN
  -- item_kind is stored and immutable (see planning_items.item_kind's
  -- own comment) -- a Goal's product identity must never flip to a
  -- Task or back via UPDATE, only via delete-and-recreate. Checked here
  -- rather than a CHECK constraint because a CHECK cannot see OLD.
  IF TG_OP = 'UPDATE' AND OLD.item_kind IS DISTINCT FROM NEW.item_kind THEN
    RAISE EXCEPTION 'planning_items.item_kind is immutable once set';
  END IF;

  IF NEW.parent_goal_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Reverse check: this row cannot become a child if some other row
  -- already depends on it being a parent. IS DISTINCT FROM/EXISTS here
  -- deliberately does not special-case an UPDATE where NEW.id = the
  -- referencing row's own id -- a row can never be its own
  -- parent_goal_id in the first place (parent_goal_id, relationship_id)
  -- FK requires a distinct existing row, so no self-reference is
  -- reachable to worry about excluding.
  IF EXISTS (
    SELECT 1 FROM public.planning_items
    WHERE parent_goal_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'Planning items may only nest one level deep';
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
BEFORE INSERT OR UPDATE OF parent_goal_id, item_kind ON public.planning_items
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
