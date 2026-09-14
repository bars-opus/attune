# Planning — Design

**Status:** proposed, not implemented
**Date:** 2026-09-14

## 1. What this is

A shared space for a couple to keep notes, tasks, goals, and planned
events together — one place for "what are we thinking about," "what do
we need to do," "what are we working toward," and "what's coming up,"
all editable by either partner with no ownership fence between them.

The calendar is not a separate screen this feature builds — dated items
(task due dates, event dates) surface on the existing Timeline the same
way Reminders already does, composed at read time from their own table,
never copied into `timeline_events`.

This is not a to-do app bolted onto a relationship app. Todoist and
Google Keep already do task lists and scratchpads better than a niche
feature ever will. The reason this belongs in Attune specifically is
that it is unowned by construction — there is no "my list" and "your
list" to reconcile, because there was only ever one list. A couple using
a generic app for this either splits it across two accounts (defeating
the point) or one partner becomes its de facto owner (recreating the
imbalance the feature is supposed to prevent). Attune already has
exactly one identity for the two of them: the relationship row every
other feature in this app hangs off. Planning is what that identity
looks like applied to "what are we doing," the way Stories is what it
looks like applied to "what happened."

## 2. Decisions, and what they rule out

| Decision | Consequence |
|---|---|
| Fully shared, no ownership | Either partner edits or deletes anything; no author-protection, no assignment gate on write access |
| Goals are containers of Tasks | No separate progress-tracking mechanism; a Goal's percentage is derived, never stored |
| Events are plans, not reminders | No overlap with `reminders` (§1's "don't forget a date" vs. Planning's "a plan with substance") — the two tables stay separate and unmerged |
| Notes are a flat scratchpad | No folders, no linking requirement, no rich formatting in v1 |
| Purely pull — no push notifications | No new OneSignal category; the conversations-screen row is the only ambient signal |
| No chat trail, except one exception | Every write is silent except completing a Goal, which posts one system-notice message (§5.4) |
| Access ends with the relationship | `status = 'active' AND chat_archived_at IS NULL`, the same tight rule chat and Stories use, not Timeline's looser one |
| No calendar screen of its own | Dated items surface on the existing Timeline, linked at read time, following `REMINDERS.md` §2's exact precedent |

## 3. Data model

Three tables, not one polymorphic one and not four fully separate ones.
The reasoning, because it is the first thing an implementer or a
reviewer will second-guess:

**Why not one `timeline_events`-shaped table with an `item_type`
column** (the pattern that table itself uses for its five kinds)? Notes
share almost no columns with Tasks/Events — a Note has no due date, no
completion state, no assignee — so a shared table would carry many
always-null columns per row depending on type, and Goal-contains-Task is
a real structural relationship a flat discriminator can't express
without a self-referencing column anyway.

**Why not four fully separate tables** (the cleanest-looking
separation)? Tasks and Goals are the *same shape* — a title, a
completion flag, an optional due date, an optional assignee — except a
Goal can have children and a plain Task cannot. Forcing them into
separate tables means either duplicating that shape twice or adding a
join table (`goal_tasks`) that a self-referencing column already makes
unnecessary, and it means every screen that shows "everything due this
week" queries two tables instead of one.

So: `planning_items` (self-referencing, covers Tasks and Goals),
`planning_events` (a genuinely different shape — a start time, a note,
optional linked tasks), `planning_notes` (shares nothing structural with
the other two, so it gets nothing forced onto it).

### 3.1 `planning_items` — Tasks and Goals

```sql
CREATE TABLE public.planning_items (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  -- NULL = a top-level item (a plain Task, or a Goal). NOT NULL = a
  -- sub-task of the parent Goal. A sub-task's own parent_item_id can
  -- never itself have a parent — enforced by a trigger, not the schema,
  -- since a CHECK constraint cannot see another row. §3.1.1.
  parent_item_id    uuid REFERENCES public.planning_items(id)
                      ON DELETE CASCADE,

  -- A row with children (checked by a partial index, §3.1.2) is
  -- displayed as a Goal; a childless row is displayed as a plain Task.
  -- This is NOT a stored column — see §3.1.3 for why a stored
  -- `item_kind` was rejected.

  title             text NOT NULL CHECK (char_length(title) <= 120),
  note              text CHECK (note IS NULL OR char_length(note) <= 500),

  is_complete       boolean NOT NULL DEFAULT false,
  completed_at      timestamptz,
  CONSTRAINT planning_item_completed_at_matches CHECK (
    (is_complete AND completed_at IS NOT NULL)
    OR (NOT is_complete AND completed_at IS NULL)
  ),

  -- NULL = shared / either partner's job. Non-null = assigned to one
  -- partner, informational only (§2's fully-shared decision means
  -- assignment never gates who can complete or delete).
  assigned_to       uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  due_date          date,

  -- Denormalized rather than a join to `relationships` on every read:
  -- Timeline's own month-range query (§6) filters on this directly, and
  -- a self-referencing table one join deep already costs more than
  -- `timeline_events`'s flat shape.
  sort_order        int NOT NULL DEFAULT 0,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX idx_planning_items_relationship
  ON public.planning_items (relationship_id, parent_item_id, sort_order)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_planning_items_due
  ON public.planning_items (relationship_id, due_date)
  WHERE deleted_at IS NULL AND due_date IS NOT NULL;

-- Lets a read cheaply answer "does this row have children" (§3.1.3)
-- without a COUNT(*) subquery per row.
CREATE INDEX idx_planning_items_parent
  ON public.planning_items (parent_item_id)
  WHERE deleted_at IS NULL AND parent_item_id IS NOT NULL;
```

#### 3.1.0 Deletion is soft in the app, hard only at the cascade boundary

Every table's `deleted_at` column is what the app itself writes:
deleting a Task, Goal, Event, or Note through the UI sets `deleted_at =
now()`, never issues a real `DELETE`. `parent_item_id`'s `ON DELETE
CASCADE` therefore never fires from the app's own delete action — it
exists for the one path that *does* hard-delete, `relationships`'s own
`ON DELETE CASCADE` when an account or relationship row is actually
removed, the same two-tier shape `STORIES.md` §4.5 uses for its
`story_items` table.

Deleting a Goal through the app must explicitly soft-delete its
children in the same statement (`UPDATE planning_items SET deleted_at =
now() WHERE id = $1 OR parent_item_id = $1`) — the FK's hard cascade
does not do this for a soft delete, and leaving a sub-task's
`deleted_at` null while its parent's is set would make it a Task with no
Goal, silently promoted rather than removed. Reads (§6) already filter
on `deleted_at IS NULL`, so this statement is the only place that needs
to remember the parent-child relationship on delete.

#### 3.1.0b A Goal cannot exist with zero children

Deriving "kind" from child-existence (§3.1.3) has a sharp edge: a
brand-new Goal, created before its first sub-task is added, is
momentarily a childless top-level row — indistinguishable from a plain
Task, and invisible to `list_planning_goals` (§6), which only returns
rows that already have a child. Vacuously "every child is complete"
would also be true of it, which would make it eligible for §5.4's
completion RPC the instant it is created, before the user has stated
what it even is a goal about.

**Decision: creating a Goal is one action that creates the parent row
and its first sub-task together, in the same client call, never two
separate steps.** The "New Goal" flow asks for the Goal's title and at
least one sub-task's title before either row is written; there is no
UI path that produces a parentless, childless `planning_items` row that
was ever *intended* to be a Goal. A plain Task, by contrast, is created
with no such requirement — the empty-Goal edge case does not apply to
it because a childless Task is not an edge case, it is what a Task is.

The same edge reappears mid-life if a user deletes a Goal's last
remaining sub-task rather than its first: the parent survives, now
childless, and reverts to reading as a plain Task by §3.1.3's own
derivation — which is the correct outcome, not a bug to guard against.
A Goal that has genuinely lost its entire checklist has lost the thing
that made it a Goal; falling back to "a Task with this title" is more
honest than either resurrecting a phantom child or leaving an
undeletable, kindless row behind. No trigger prevents deleting a last
child, and none should.

#### 3.1.1 Depth is capped at one level

A Goal contains Tasks; a Task does not contain Tasks. This is a product
decision, not a technical limitation — nested sub-goals would need their
own progress-rollup rules (does a sub-goal's completion count fractional
progress on its parent, or only 0/1?) that nothing in this feature's
purpose calls for. A `BEFORE INSERT OR UPDATE` trigger rejects a row
whose `parent_item_id` points at a row that itself has a non-null
`parent_item_id`.

#### 3.1.2 A Goal's progress is derived, never stored

`SELECT count(*) FILTER (WHERE is_complete), count(*) FROM
planning_items WHERE parent_item_id = $1 AND deleted_at IS NULL` — no
`goals.progress` column to keep in sync, no trigger to maintain it, no
way for it to drift from the truth. The read RPC (§6) computes this once
per goal per page, which is cheap at the scale one couple's planning
list will ever reach.

#### 3.1.3 "Kind" is derived from shape, not stored

A tempting alternative is an `item_kind text CHECK (item_kind IN
('task', 'goal'))` column set at creation. Rejected: it can lie. Nothing
stops a plain Task from later gaining a sub-task (the user drags a task
under another one, say, in a future version) — at that point either the
stored kind silently disagrees with reality, or every mutation that adds
or removes a child now also has to remember to flip a flag on the
parent. Deriving "is this a Goal" from "does it have children" makes the
two facts the same fact, so they cannot disagree. The cost is one extra
index-only check per row instead of reading a column — worth it for a
table this size.

### 3.2 `planning_events`

```sql
CREATE TABLE public.planning_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  title             text NOT NULL CHECK (char_length(title) <= 120),
  note              text CHECK (note IS NULL OR char_length(note) <= 500),

  -- A date, not a timestamp: "date night this Friday" rarely needs a
  -- to-the-minute time, and a bare date sidesteps timezone disagreement
  -- the same way STORIES.md §3.5 chose for `occurred_on` — this is a
  -- civil date the couple is planning around, not an instant.
  event_date        date NOT NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX idx_planning_events_relationship
  ON public.planning_events (relationship_id, event_date)
  WHERE deleted_at IS NULL;

-- Linking, not ownership: a linked task still lives in planning_items
-- and is still a top-level item there (its own due date, its own
-- completion, addressable from the plain Tasks list too) — the link
-- only says "this task is part of organizing this event." Deleting the
-- event does not delete the task; deleting the task just un-links it.
CREATE TABLE public.planning_event_tasks (
  event_id  uuid NOT NULL REFERENCES public.planning_events(id)
             ON DELETE CASCADE,
  item_id   uuid NOT NULL REFERENCES public.planning_items(id)
             ON DELETE CASCADE,
  PRIMARY KEY (event_id, item_id)
);
```

An Event is deliberately **not** a `planning_items` row with a
`starts_at` — that would resurrect the always-null-columns problem
inside a single table (an Event has no `assigned_to`, no
`parent_item_id`; a Task has no `event_date`). The link table is the
seam: an Event *organizes* Tasks without *containing* them the way a
Goal does, which matches how they actually differ — a Goal's sub-tasks
have no independent life outside the Goal's checklist, but "buy the
gift" is a real, independently-completable task whether or not it's
tagged to "Sarah's birthday dinner."

### 3.3 `planning_notes`

```sql
CREATE TABLE public.planning_notes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid NOT NULL REFERENCES auth.users(id)
                      ON DELETE CASCADE,

  title             text NOT NULL CHECK (char_length(title) <= 120),
  body              text NOT NULL DEFAULT '' CHECK (char_length(body) <= 4000),

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX idx_planning_notes_relationship
  ON public.planning_notes (relationship_id, updated_at DESC)
  WHERE deleted_at IS NULL;
```

Sorted by `updated_at DESC` rather than `created_at` — a scratchpad you
just edited is the one you want at the top, the same way a note-taking
app surfaces recently-touched entries first.

## 4. Security and RLS

**Fully shared, per §2's decision — but this is a departure from every
other couple-write feature this codebase has shipped, and the departure
needs its own reasoning, not just a reused rule.** `REMINDERS.md` chose
the identical shared-write shape ("a calendar is a shared plan, not a
personal log entry") for the same reason: an item with no personal
author-attachment has no one for an author-only rule to protect. All
three tables get the same policy shape, using the exact predicate chat
media already established for "current member of an active,
unarchived relationship":

```sql
CREATE POLICY planning_items_rw ON public.planning_items
  FOR ALL
  USING (
    relationship_id IN (
      SELECT id FROM public.relationships
      WHERE status = 'active' AND chat_archived_at IS NULL
        AND (user_a = auth.uid() OR user_b = auth.uid())
    )
  )
  WITH CHECK (
    relationship_id IN (
      SELECT id FROM public.relationships
      WHERE status = 'active' AND chat_archived_at IS NULL
        AND (user_a = auth.uid() OR user_b = auth.uid())
    )
  );
-- The same shape, unchanged, for planning_events, planning_event_tasks
-- (via a join to planning_events), and planning_notes.
```

**Why a single `FOR ALL` policy rather than separate
SELECT/INSERT/UPDATE/DELETE ones** (the shape Stories used, §3.3 of
`STORIES.md`)? Stories needed different rules per operation because
mutations there are server-owned (`expires_at`, `occurred_on`, storage
keys) and only an RPC may set them. Nothing here is server-owned — every
column a client writes is one it is also allowed to read and change
later. Splitting the policy four ways would say the same sentence four
times for no gain.

**Once the relationship is archived, the `USING` clause simply stops
matching** — no separate read-only mode to build, no additional column
to check. This is what makes read access after archival "free": a
SELECT still needs `relationship_id IN (...)`, and *that* predicate is
what needs relaxing for read-after-archive to work. So the real rule is
two policies, not one:

```sql
-- Read: relaxed to any relationship the caller was EVER a member of,
-- active or not — matches chat/Stories' own read-after-archive shape.
CREATE POLICY planning_items_read ON public.planning_items
  FOR SELECT
  USING (
    relationship_id IN (
      SELECT id FROM public.relationships
      WHERE (user_a = auth.uid() OR user_b = auth.uid())
    )
  );

-- Write: the tight predicate above, active + unarchived only.
CREATE POLICY planning_items_write ON public.planning_items
  FOR INSERT WITH CHECK (...)  -- active + unarchived, as above
  ...similarly for UPDATE and DELETE...
```

Every table repeats this same read/write split. `authenticated` gets
`SELECT, INSERT, UPDATE, DELETE` on all three tables and the link table
— genuinely fully shared, no `SECURITY DEFINER` RPC standing between the
client and the row, because (§2) there is no server-owned field here for
an RPC to protect. The one exception is goal completion (§5.4), which
does need an RPC — not to protect a column, but because it also inserts
a chat message atomically.

## 5. Surfaces

### 5.1 Entry point

A new row in the existing card on the conversations screen, alongside
`_LatestReflectionRow` and `_NextCalendarEventRow`
(`conversations_screen.dart`). It shows the single most relevant open
item — the soonest-due incomplete Task/Goal-sub-task, or if none has a
due date, the most recently touched item of any kind — the same
"one line, tap through to the full list" shape those two rows already
use. Tapping it pushes the Planning home screen.

```
Existing card:
├─ Reflection row       → journal
├─ Next calendar event  → reminders/calendar
├─ NEW: Planning row    → Planning home screen
└─ Partner-distance row
```

### 5.2 Planning home screen

Three sections, one screen, no tabs: **Goals** (each showing its derived
progress fraction and, expanded, its sub-tasks), **Tasks** (every
top-level, childless `planning_items` row — plain to-dos, sorted
incomplete-first then by due date), **Events** (upcoming first,
`event_date >= today`, with a "past" section collapsed by default).
Notes get their own destination one level down (§5.3) rather than a
fourth section competing for space on the home screen, since a
scratchpad's content is the least glanceable of the four — a note's
value is in opening it, not in a preview line.

Each section has its own "+" to create that type directly, rather than
one generic "add" button that then asks what kind — the four types are
different enough in required fields (a Note needs just a title; a Task
needs a due date decision; an Event needs a date) that a single add flow
would need its own branching UI anyway, so the branch may as well be
"which section did you tap."

### 5.3 Notes list

A simple list, `updated_at DESC`, title + first line of body as the
preview — the shared-Keep shape from the brainstorm. Tapping opens an
edit view; there is no separate "view" vs "edit" mode, since either
partner editing at any time is the whole point (§2).

**Concurrent-edit note, stated rather than silently accepted or
silently broken:** if both partners have the same note open and both
save, last write wins on `updated_at`. No conflict UI, no merge, no
lock. This is deliberately the same shape a shared Google Doc's naive
autosave has at the single-paragraph scale this note size cap (`<=
4000` chars) implies — building real operational-transform conflict
resolution for a couple's shared grocery list is effort this feature's
actual use does not justify. If usage data later shows this causing
real lost edits, that is the trigger to revisit, not a v1 requirement.

### 5.4 Goal completion, and its one chat message

Marking the last incomplete sub-task of a Goal complete flips the
parent's own `is_complete`/`completed_at` too — a Goal is "done" exactly
when every one of its non-deleted children is, derived the same way its
progress fraction is (§3.1.2, and using the same `deleted_at IS NULL`
filter §3.1.0 already requires there): a soft-deleted sub-task is not a
pending obligation, so it does not block completion, the same way it
does not count toward the progress denominator. This is never a
separate manual "mark goal complete" action a user could get out of
sync with its children.

This is the one write in the whole feature that is not silent (§2).
`complete_planning_goal(p_item_id)`, `SECURITY DEFINER`, does three
things in one transaction:

1. Verifies the row is a Goal (has children), belongs to an active,
   unarchived relationship containing the caller, and is not already
   complete — a repeat call is a no-op, not a second celebration.
2. Sets `is_complete = true, completed_at = now()`.
3. Inserts one message into `messages` with `is_system_notice = true`
   and content `"🎉 Goal completed: <title>"`.

**Why an RPC and not a client-side "if all children are now done, also
insert a celebration message" — the pattern the ephemeral-video feature
already accepts for `is_system_notice` (its own documented gap,
`20260902120000_chat_ephemeral_video_final_review_fixes.sql`)?** That
gap is accepted specifically because it is self-limited: a user can only
fake a system-notice label on their *own* sent message, which affects
no one else's data. A fake goal-completion celebration is a different
shape of claim — it announces something about the *shared* Goal's
state, and a client-side insert would let either partner fabricate
"we finished X" whether or not the Goal's children agree. Doing the flip
and the message insert in one server transaction makes the message
provably true of the row it describes.

The message is an ordinary `messages` row after that — it renders,
scrolls, and is deletable through every existing system-notice code
path in `message_bubble.dart`; nothing about the chat pipeline needs to
learn a new message shape.

### 5.5 Calendar integration

Following `REMINDERS.md` §2's precedent exactly: linked, not merged.
`TimelineRepository.getEventsForMonth` (already used to blend timeline
anniversaries with reminders) gains two more sources for the requested
month range — `planning_items` rows with a non-null `due_date`, and
`planning_events` rows by `event_date` — composed at read time into the
same list the Calendar screen already renders, never copied into
`timeline_events`.

A completed Task's due date still shows on the calendar, styled
differently (struck through / faded) rather than disappearing — the
same reasoning Stories' rings use for a viewed segment (faded, not
skipped): a plan you finished on the day you said you would is still
information about that day, not noise to hide.

## 6. Read contracts

No unbounded relationship-history fetch, the same discipline
`STORIES.md` §5.5 holds its own reads to:

| Read | Contract |
|---|---|
| `list_planning_goals` | Top-level items with at least one child, newest-first, keyset pages of 30; each row's children fetched via a second call once expanded, not eagerly joined |
| `list_planning_tasks` | Top-level items with no children, incomplete-first then by `due_date`, keyset pages of 50 |
| `list_planning_events` | `event_date >= today` by default, ascending; a separate call for past events, descending, on demand |
| `list_planning_notes` | `updated_at DESC`, keyset pages of 30 |

All four are `SECURITY INVOKER` — RLS (§4) remains the authority, the
same reasoning `STORIES.md` §5.5 gives for its own read RPCs: reimplementing
the membership check four times is how it eventually disagrees with
itself once. `p_limit` is capped server-side regardless of what a
modified client requests.

## 7. What this does not do, and why

**No shared list of lists, no folders, no tags.** Three sections is
already the whole taxonomy this feature needs; a couple's planning
volume never approaches the scale where folders earn their complexity.

**No due-date push notifications of its own.** `reminders` already owns
"notify me before a date arrives" (its 3-day-before push). Planning
Events deliberately do not duplicate that infrastructure — a couple who
wants a push for a specific planned date can already set a Reminder for
it, linked the same optional way `REMINDERS.md` §2 links an anniversary
Reminder to a Timeline entry. Building a second push path for
essentially the same countdown would be redundant machinery, not a
missing feature.

**No real-time collaborative editing (cursors, live-typing indicators)
on Notes.** §5.3 already states the accepted concurrent-edit shape;
anything richer is speculative complexity for a text box with a
4000-character cap.

**No recurring Tasks or Events.** `reminders.recurrence` already owns
"this repeats" for the one case (yearly dates) this codebase has needed
it for. A recurring Task — "take out the trash every Tuesday" — is a
different, chore-rotation-shaped feature; naming it here would smuggle
in a decision (whose turn is it, what happens on a missed week) this
spec was never asked to make.

## 8. Risks

| Risk | Mitigation |
|---|---|
| A Goal's stored progress drifts from its children's real state | Never stored; always derived from a live count (§3.1.2) |
| A stored `item_kind` disagrees with whether a row actually has children | Not stored at all; derived from the same child-existence check the progress count already needs (§3.1.3) |
| A Goal is created with zero children and reads as vacuously complete | Goal creation is one action that writes the parent and its first sub-task together; no UI path produces an empty Goal (§3.1.0b) |
| Nested sub-goals need progress-rollup rules this spec never defines | Depth capped at one level by a trigger (§3.1.1); relaxing this later is additive, not a breaking change |
| A client fabricates a false "we finished this together" chat message | Goal completion is a `SECURITY DEFINER` RPC that flips the row and inserts the message in one transaction — the message can only exist when the row it describes is actually true (§5.4) |
| A deleted linked Task silently orphans an Event's checklist, or vice versa | The link table's `ON DELETE CASCADE` only removes the LINK row, never the Task or the Event itself (§3.2) |
| Two partners editing the same Note lose each other's changes | Accepted, stated explicitly rather than silently risked (§5.3); revisit only if real usage shows real loss |
| A former partner keeps write access after a breakup | The write policy's predicate is `status = 'active' AND chat_archived_at IS NULL`, identical to chat/Stories (§4); read access is intentionally looser, matching the same feature's own precedent |
| The calendar screen's month query grows a fifth source it must merge and slows down | Both new sources are indexed on `(relationship_id, due_date)` / `(relationship_id, event_date)` exactly the way `idx_story_calendar` and Reminders' own index already are — a bounded-range index scan, not a table scan |

## 9. Testing

| Area | What must be covered |
|---|---|
| RLS | A non-member cannot read or write any of the three tables; a former member (archived relationship) can still SELECT but cannot INSERT/UPDATE/DELETE; either current member can edit or delete an item the OTHER partner created |
| Goal/Task shape | A childless item behaves as a Task; a parented item cannot itself gain a child (depth-1 trigger); a Goal's progress recomputes correctly as children are added, completed, and soft-deleted |
| Goal completion RPC | Completing the last child flips the parent; completing an already-complete goal is a no-op (no second message); the inserted message is `is_system_notice = true` and reads correctly in `message_bubble.dart`'s existing system-notice branch; a non-member cannot call it |
| Event/Task linking | Deleting a linked Task removes only the link row, not the Event; deleting the Event removes only the link row, not the Task; an unlinked Task still appears in the plain Tasks list |
| Calendar composition | A Task due date and an Event date both appear in `getEventsForMonth`'s result for the right month; a completed Task's due date still appears, styled distinctly; nothing here writes into `timeline_events` |
| Notes | Concurrent edits: last `updated_at` wins, no error, no data corruption beyond the accepted overwrite (§5.3) |
| Read RPCs | Keyset paging never re-returns or skips a page; `p_limit` is capped server-side regardless of what is requested |

## 10. Implementation order

1. **Database foundation** — the three tables plus the link table, their
   indexes, the depth-1 trigger, RLS read/write policy pairs.
2. **Read RPCs** — the four listed in §6, `SECURITY INVOKER`.
3. **Goal completion RPC** — `complete_planning_goal`, `SECURITY
   DEFINER`, the one place this feature touches `messages`.
4. **Repository and models** — Flutter data layer for all three tables
   plus the link table, Riverpod providers, the derived-progress and
   derived-kind logic living in the repository, not duplicated in every
   widget that needs it.
5. **Planning home screen** — the three sections (§5.2), create flows
   per section.
6. **Notes screen** — list + edit view (§5.3).
7. **Conversations-screen entry row** — the new row in the existing card
   (§5.1), following `_NextCalendarEventRow`'s exact shape.
8. **Calendar integration** — the two new sources into
   `getEventsForMonth` (§5.5), styling for a completed item's due date.

## 11. Open questions

- **Whether a Goal needs its own optional target date**, distinct from
  any individual sub-task's due date ("finish this by June" as a
  property of the Goal itself, not derived from its latest sub-task).
  Not decided here because it did not come up in the brainstorm and
  is easy to add additively (a nullable `target_date` column on
  `planning_items`, meaningful only for parentless rows) if it turns out
  to matter once the feature is in use.
- **Whether an Event that has passed with unfinished linked Tasks should
  surface differently** (a quiet "3 tasks from a past event are still
  open" signal) versus just aging into the collapsed "past" section
  with its tasks otherwise indistinguishable from any other open Task.
  Deferred as a polish question, not a launch blocker.
- **Whether Notes should support attaching a photo**, the way a Task's
  or Event's `note` field might one day want to. Out of scope for v1 —
  every other new-media surface this codebase has built (Stories) took
  its own dedicated spec to get storage/security right, and nothing
  about Planning's stated purpose (§1) requires media to be useful.
