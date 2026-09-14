# Planning — Implementation-ready design

**Status:** reviewed and ready for an implementation plan
**Date:** 2026-09-14
**Review basis:** checked against the current Reminders, Stories, Timeline,
Chat, RLS, and migration conventions in this repository.

## 1. What this is

Planning is one couple-shared space for four kinds of content:

- **Notes** — a flat shared scratchpad.
- **Tasks** — independently completable actions, optionally assigned and due.
- **Goals** — stable containers whose progress and completion are derived from
  their child Tasks.
- **Events** — all-day plans with a date, a note, and optional links to
  independent top-level Tasks.

There is no ownership fence. `created_by` is nullable audit metadata; either
partner may edit, complete, link, unlink, or remove any Planning content while
the relationship is active and its chat is not archived. It becomes null if
that account is deleted so shared content is retained under the anonymized
relationship record rather than cascaded away.

Dated Tasks and Events appear in the existing Timeline by read-time
composition. They are never copied into `timeline_events`, and Planning does
not add another calendar screen.

Planning itself sends no task, due-date, or event notifications. The one chat
side effect is a celebratory system-notice message the first time a Goal is
completed. That message uses the normal native-chat pipeline and can therefore
produce the normal new-message notification; this is the explicit exception to
the no-notification rule.

## 2. Decisions

| Decision | Consequence |
|---|---|
| Fully shared | Either current partner may mutate every row; `created_by` never gates a write |
| Stable Task/Goal identity | `item_kind` is stored and immutable; deleting a Goal's last child cannot silently turn it into a Task |
| Goals contain Tasks | Only Tasks may have `parent_goal_id`; nesting is exactly one level |
| Progress is derived | No percentage or completed-count column is stored |
| Goal completion is server-maintained | Clients complete Tasks; one transaction reconciles the parent and its celebration |
| Events link independent Tasks | Linking never reparents or owns a Task; only top-level Tasks may be linked |
| Events are all-day in v1 | `event_date` is a civil date. Event times and time zones are not partially implemented |
| Notes are flat plain text | No folders, rich text, tags, or attachments in v1 |
| Access is for an active, unarchived relationship | Planning is neither readable nor writable after `status != 'active'` or `chat_archived_at IS NOT NULL` |
| Soft deletion is the app boundary | UI removals set `deleted_at`; relationship/account cascades remain hard deletes |
| No separate calendar | Timeline composes Planning through its own provider and rows, like Reminders and Stories |

The previous draft derived Task versus Goal from child existence. That was
rejected in review: product identity must not change when a child is deleted,
and the derived design could not atomically distinguish a newly created Goal
from a Task through ordinary PostgREST writes. An immutable discriminator is
not redundant here; it is the invariant that gives each lifecycle meaning.

## 3. Data model

There are three content tables, one link table, and one relationship-scoped
change-signal table. Tasks and Goals share a table because most of their fields
and list behavior overlap. Events and Notes have genuinely different
lifecycles and shapes.

All title/body limits below count PostgreSQL characters, and all required text
also rejects blank-after-trim values. RPCs trim leading/trailing whitespace
before persistence. Flutter generates UUIDs for every new content row before
an optimistic create and passes them to the relevant RPC. A retry returns the
existing row only when relationship, creator, kind, and normalized create
payload match; conflicting reuse of an ID is rejected.

### 3.1 `planning_items`

```sql
CREATE TABLE public.planning_items (
  id                uuid PRIMARY KEY,
  relationship_id   uuid NOT NULL REFERENCES public.relationships(id)
                      ON DELETE CASCADE,
  created_by        uuid REFERENCES auth.users(id)
                      ON DELETE SET NULL,

  item_kind         text NOT NULL
                      CHECK (item_kind IN ('task', 'goal')),
  parent_goal_id    uuid,

  title             text NOT NULL
                      CHECK (char_length(btrim(title)) BETWEEN 1 AND 120),
  note              text
                      CHECK (note IS NULL OR char_length(note) <= 500),

  -- Meaningful for Tasks only. The write RPC validates that a non-null
  -- assignee is one of this relationship's two members.
  assigned_to       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  due_date          date,

  -- Tasks are completed directly. A Goal's value is maintained only by
  -- reconcile_planning_goal() inside the mutation transaction.
  completed_at      timestamptz,

  -- Server-owned and never cleared. It makes the one-celebration-per-Goal
  -- rule durable even if a completed Goal is reopened by adding/unchecking
  -- a Task and is completed again later.
  celebrated_at     timestamptz,

  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,

  UNIQUE (id, relationship_id),
  CONSTRAINT planning_item_parent_shape CHECK (
    parent_goal_id IS NULL OR item_kind = 'task'
  ),
  CONSTRAINT planning_goal_task_only_fields CHECK (
    item_kind = 'task'
    OR (parent_goal_id IS NULL AND assigned_to IS NULL AND due_date IS NULL)
  ),
  CONSTRAINT planning_celebration_goal_only CHECK (
    celebrated_at IS NULL OR item_kind = 'goal'
  ),
  CONSTRAINT planning_item_parent_same_relationship
    FOREIGN KEY (parent_goal_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id)
    ON DELETE CASCADE
);

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
```

The composite parent FK guarantees that a child and parent have the same
relationship. The RPC additionally locks and verifies that the parent is a
live Goal. No client may update `item_kind`, `relationship_id`, `created_by`,
`parent_goal_id`, `completed_at`, `celebrated_at`, or timestamps directly.

#### Goal invariants

- A Goal is created together with its first child Task in one RPC.
- Goal creation and child-add RPCs create the new child incomplete; neither
  path can manufacture an instantly completed Goal.
- A live Goal always has between 1 and 100 live children.
- Only Tasks can be children, and a child Task cannot itself have children.
- Deleting a Goal soft-deletes the Goal and all its children atomically.
- Deleting the only live child is rejected. The UI offers “Delete goal” or
  asks the user to add another Task first.
- Adding an incomplete child or uncompleting a child reopens a completed Goal
  by clearing `completed_at`; it does not clear `celebrated_at`.
- A Goal is complete exactly when it has at least one live child and every
  live child has `completed_at IS NOT NULL`.

Progress is returned as `completed_child_count / child_count`. It is computed
by the Goals read RPC, never stored.

### 3.2 `planning_events` and links

```sql
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
  event_date        date NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz,
  UNIQUE (id, relationship_id)
);

CREATE INDEX idx_planning_events_relationship_date
  ON public.planning_events (relationship_id, event_date, id)
  WHERE deleted_at IS NULL;

CREATE TABLE public.planning_event_tasks (
  relationship_id uuid NOT NULL REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  event_id         uuid NOT NULL,
  item_id          uuid NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, item_id),
  FOREIGN KEY (event_id, relationship_id)
    REFERENCES public.planning_events(id, relationship_id) ON DELETE CASCADE,
  FOREIGN KEY (item_id, relationship_id)
    REFERENCES public.planning_items(id, relationship_id) ON DELETE CASCADE
);

CREATE INDEX idx_planning_event_tasks_item
  ON public.planning_event_tasks (item_id, event_id);
```

The repeated `relationship_id` is intentional: the composite foreign keys
make a cross-couple link structurally impossible. The link RPC also requires
both rows to be live and the item to be a top-level Task (`item_kind = 'task'`
and `parent_goal_id IS NULL`). One Event may link at most 100 Tasks.

Soft deletion does not fire an FK cascade. Therefore the delete RPCs explicitly
hard-delete affected link rows in the same transaction:

- deleting a Task deletes its `planning_event_tasks` rows;
- deleting an Event deletes its `planning_event_tasks` rows;
- deleting a Goal deletes links for its children defensively, although child
  Tasks cannot be linked under the v1 contract.

Neither side deletes the other content row.

### 3.3 `planning_notes`

```sql
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
```

Notes use last-write-wins. `updated_at` is assigned by the database, not the
device. The save RPC returns the authoritative row. Concurrent saves do not
merge; the later committed save replaces the earlier body.

### 3.4 `planning_change_signals`

```sql

-- Realtime invalidation signal, following story_change_signals exactly.
CREATE TABLE public.planning_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);
```

The row contains no Planning content. It only tells subscribed clients that
their relationship-scoped Planning reads are stale and should be fetched
again.

### 3.5 Timestamp and delete rules

A Planning-specific `touch_planning_updated_at()` `BEFORE UPDATE` trigger sets
`updated_at = clock_timestamp()` on the three content tables. Do not replace
the repository's global `set_updated_at()` function merely to change Planning's
clock behavior. Clients never provide `created_at`, `updated_at`, `deleted_at`,
completion, or celebration timestamps. All app deletion goes through the
feature RPCs so link cleanup, Goal reconciliation, authorization, and
idempotency cannot be skipped.

Hard `ON DELETE CASCADE` remains only for relationship/account erasure and
physical maintenance. No v1 UI exposes restore or hard delete.

## 4. Security and mutation boundary

### 4.1 RLS

All five Planning tables enable RLS. Authenticated clients receive `SELECT`
only; there are no direct client `INSERT`, `UPDATE`, or `DELETE` grants. Each
content/link SELECT policy requires all of:

```sql
EXISTS (
  SELECT 1
  FROM public.relationships r
  WHERE r.id = <row>.relationship_id
    AND r.status = 'active'
    AND r.chat_archived_at IS NULL
    AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
)
AND <row>.deleted_at IS NULL -- content tables only
```

The link table uses the same active-membership predicate and relies on both
linked content tables' live-row checks in read RPCs. The change-signal policy
uses the membership predicate without a `deleted_at` clause because it has no
soft deletion. There is deliberately no read-after-archive exception. This
matches §2 and the current Stories access boundary.

### 4.2 RPC rules

All mutations use `SECURITY DEFINER SET search_path = public`, immediately
reject `auth.uid() IS NULL`, and repeat the active/unarchived membership check.
Every function is `REVOKE ALL ... FROM PUBLIC, anon` and granted only to
`authenticated`. Internal reconciliation helpers are also revoked from
`authenticated` and are called only by the public mutation RPCs.

The implementation exposes this minimum command surface:

| RPC | Contract |
|---|---|
| `create_planning_task` | Create one top-level Task with a client UUID; server derives creator/timestamps |
| `create_planning_goal` | Create Goal + first child Task atomically with two client UUIDs |
| `add_planning_goal_task` | Lock live Goal, enforce 100-child cap, add child, reconcile Goal |
| `update_planning_item` | Edit allowed kind-specific fields; cannot change kind/parent/relationship |
| `set_planning_task_completion` | Lock Task and parent Goal, set/unset Task completion, reconcile Goal and celebration |
| `delete_planning_item` | Soft-delete Task or Goal; clean links; reconcile parent or delete children atomically |
| `upsert_planning_event` / `delete_planning_event` | Atomically create/edit Event and replace its validated Task-link set, or soft-delete Event and clean links |
| `link_planning_event_task` / `unlink_planning_event_task` | Validate same relationship, live rows, top-level Task, and 100-link cap |
| `upsert_planning_note` / `delete_planning_note` | Create/edit or soft-delete Note with server timestamps |

Creation and delete calls are retry-safe. Deletes return success when the
authorized target is already soft-deleted. Link/unlink use insert-on-conflict
and delete semantics that are naturally idempotent. Goal-child count checks
lock the Goal; Event-link count/replacement checks lock the Event, so concurrent
calls cannot cross either 100-row limit. Each successful mutation calls an
internal `bump_planning_signal(relationship_id)` upsert before commit,
following `bump_story_signal`; that helper is not client-executable.

### 4.3 Goal reconciliation and celebration

`set_planning_task_completion`, `add_planning_goal_task`, and child deletion
call one internal `reconcile_planning_goal(goal_id, actor_id)` helper before
commit. They lock the Goal row (`FOR UPDATE`) so two partners completing the
last Tasks concurrently serialize.

Reconciliation counts live children once:

1. If any live child is incomplete, clear the Goal's `completed_at`.
2. If all live children are complete and the Goal was incomplete, set
   `completed_at = statement_timestamp()`.
3. On that transition, if `celebrated_at IS NULL`, insert exactly one native
   `messages` row and then set `celebrated_at` in the same transaction.
4. If `celebrated_at` is already set, a later recompletion produces no second
   message.

The message insert uses:

```text
relationship_id         = Goal.relationship_id
sender_id                = auth.uid()
client_message_id        = gen_random_uuid()
content                  = "🎉 Goal completed: <normalized title>"
is_system_notice         = true
message_analysis_skipped = true
source                   = "native"
```

The existing `messages` insert trigger remains active, so ordering, chat
refresh, and the normal chat notification outbox continue to work. The RPC
must insert every currently required non-default message field and must be
covered by a database contract test so later changes to `messages` cannot
silently break Goal completion. The client never inserts this notice itself.
Its text is a completion-time snapshot: later renaming or soft-deleting the
Goal does not rewrite or remove the chat message. It remains deletable through
the existing message-action rules.

## 5. Read contracts

Read RPCs are `SECURITY INVOKER`; RLS remains authoritative. `p_limit` is
clamped to `1..100`. Every ordering ends with `id` as a deterministic tie
breaker and every cursor contains all preceding sort values.

| Read | Ordering and pagination |
|---|---|
| `list_planning_goals` | live top-level Goals; incomplete first, then `updated_at DESC, id DESC`; keyset pages of 30; returns `child_count` and `completed_child_count` |
| `list_planning_goal_tasks` | one live Goal's children by `created_at ASC, id ASC`; fetched on expansion; bounded by the enforced 100-child cap |
| `list_planning_tasks` | live top-level Tasks; incomplete first, non-null due dates first, `due_date ASC`, then `updated_at DESC, id DESC`; keyset pages of 50 |
| `list_planning_events` | upcoming uses `event_date >= p_today`, `event_date ASC, id ASC`; past uses `< p_today`, `event_date DESC, id DESC`; separate keyset calls, 50 per page |
| `list_planning_notes` | `updated_at DESC, id DESC`; keyset pages of 30 |
| `list_planning_calendar_entries` | Tasks with due dates plus Events in inclusive `p_start_date..p_end_date`; maximum range 42 days |
| `get_planning_summary` | one deterministic row for the Conversations card (§6.1) |

`p_today`, `p_start_date`, and `p_end_date` are civil dates calculated by the
client. The server does not infer the user's day from its UTC timezone. Invalid
ranges and ranges over 42 days are rejected.

## 6. Product surfaces

### 6.1 Conversations entry row

Add `_PlanningSummaryRow` to the existing conversations information card near
`_LatestReflectionRow` and `_NextCalendarEventRow`. It uses
`get_planning_summary` with this priority:

1. incomplete overdue Task, nearest missed due date first (`due_date DESC`);
2. incomplete Task due today or later, soonest first;
3. next upcoming Event;
4. most recently updated live Goal, Task, Event, or Note;
5. “Start planning together” when empty.

Goal children participate in Task choices; completed Tasks do not. Ties use
`updated_at DESC, id DESC`. The row shows the returned kind and date context
and opens Planning home. It retains its last successful value during refresh,
matching the existing card's no-jump behavior.

### 6.2 Planning home

One screen with three sections, not tabs:

- **Goals** — incomplete first; progress fraction; expand to child Tasks.
- **Tasks** — top-level Tasks only, using the read ordering in §5.
- **Events** — upcoming first; past Events behind a collapsed section.

Each section has its own add action. A separate Notes row opens the Notes list.
Every mutation is optimistic where the inverse is unambiguous (completion,
linking, unlinking, and soft deletion), rolls back on failure, and replaces the
optimistic entity with the authoritative RPC result on success.

Goal creation requires a Goal title and first Task title before Save is enabled.
Deleting the only child shows the choices defined in §3.1 rather than sending a
request known to fail. Assignment offers only the two current relationship
members plus “Either of us.” Goal fields do not show assignment or due date in
v1.

Event create/edit includes title, all-day date, note, and a picker for existing
live top-level Tasks. Unlinking never deletes the Task. Creating a new Task from
inside the Event flow creates a top-level Task and then links it in one server
transaction or compensates by leaving the successfully created Task visible;
it must never create a hidden orphan.

### 6.3 Notes

Notes list uses title plus first body line, newest `updated_at` first. Tapping a
row opens one edit surface; there is no separate read mode. Save is explicit in
v1. If both partners save, the later committed save wins as documented in
§3.3. The UI keeps the user's draft on a failed save and offers retry.

### 6.4 Shared-state refresh

“No push notifications” does not mean stale shared data. Only
`planning_change_signals` is added to the Supabase Realtime publication. A
relationship-scoped subscription to that table invalidates the affected
list/summary/calendar providers whenever either partner successfully mutates
Planning content. This mirrors Stories and avoids relying on a soft-deleted
content row continuing to pass its own SELECT policy. The client also refreshes
on pull-to-refresh, app resume, and every successful Realtime (re)subscription
so changes missed during a network gap are recovered.

During refresh, providers retain the last successful list instead of replacing
it with a full-screen spinner. A spinner/skeleton is allowed only on the first
load when no cached state exists. Realtime events trigger a refetch rather than
being blindly applied, so derived Goal counts remain authoritative.

## 7. Timeline integration

The current code does **not** have a single merged calendar repository model:
`TimelineScreen` reads Timeline events, Reminders, and Stories through separate
providers and renders source-specific widgets. Planning follows that real seam.

Implementation adds a `planningCalendarEntriesProvider(month)` backed by
`list_planning_calendar_entries`. `CalendarStrip` receives Planning dates for
dots/counts, and the selected-day area renders source-specific Planning rows:

- Task: title, assignment, and completed styling (faded/struck through).
- Event: title and event icon.

Do not coerce Planning rows into `TimelineEventModel`; that would require fake
`loggedBy`, `eventType`, `moodScore`, and `occurredAt` values. Planning models
carry a source kind and stable ID, and tapping a row deep-links to the relevant
Planning detail.

The calendar range is the 42-day visible grid, not an unbounded history query.
Changing a Task due date or Event date invalidates both the old and new month
providers. Completed Tasks remain visible on their due date.

## 8. Explicitly out of scope for v1

- Goal target dates. `due_date` is Task-only and enforced as such; a future
  nullable `target_date` for Goals is additive.
- Event times, durations, recurrence, locations, and external calendar sync.
- Due-date/Event push notifications. Users may create a separate Reminder when
  they need notification delivery.
- Recurring Tasks, sub-goals, Tasks nested more than one level, folders, tags,
  rich text, and attachments.
- Presence, live cursors, or text merging in Notes.
- A special “unfinished Tasks from past Event” alert. Linked open Tasks remain
  visible in the ordinary Tasks section while their Event moves to Past.
- Restore UI and hard delete UI.

These are settled v1 exclusions, not implementation questions.

## 9. Failure and lifecycle behavior

| Situation | Required behavior |
|---|---|
| Caller is not authenticated/current active member | Generic authorization failure; no row existence leak |
| Relationship ends or chat archives while screen is open | Next read/mutation fails closed; clear Planning provider state and leave the screen |
| Duplicate create retry | Return the matching existing row; conflicting reuse of an ID fails |
| Two partners complete final Tasks concurrently | Goal row lock produces one completion transition and at most one notice |
| Completed Goal gets a new/incomplete Task | Goal reopens; historical notice stays; later recompletion sends no duplicate |
| Delete sole Goal child | Reject atomically; UI offers deleting Goal or adding another child |
| Soft-delete linked Task/Event | Delete link rows in same RPC; never delete the other content entity |
| Partner edits while local optimistic mutation is pending | Server result/refetch wins; failed optimistic operation rolls back without dropping the partner update |
| Initial load fails | Error state with retry; do not present an empty list as authoritative |
| Refresh fails with cached data | Keep cached data and show a non-blocking error |

## 10. Verification requirements

### Database contract tests

- RLS denies anon, non-members, ended relationships, and archived
  relationships on all five tables.
- Authenticated clients have SELECT but no direct mutation privilege.
- Every public RPC rejects non-members and is executable only by
  `authenticated`; internal helpers are not executable.
- Every successful mutation increments the relationship's Planning change
  signal exactly once; rejected/no-op retries do not emit misleading changes.
- `created_by` is `auth.uid()` on creation and immutable in app writes, but
  becomes null rather than deleting shared content when that account is erased.
- Deleting one partner's account preserves Planning rows under the retained
  relationship record and nulls creator/assignee references as required.
- `assigned_to` must be null or a member of the same relationship.
- Cross-relationship parent and Event/Task links fail.
- A child parent must be a live Goal; nesting under a Task fails.
- Goal creation is atomic and requires a first child.
- The 100-child and 100-event-link limits hold under concurrent calls.
- Sole-child deletion fails; Goal deletion soft-deletes all children.
- Soft-deleting a linked Task/Event removes only link rows.
- Goal progress excludes soft-deleted children.
- Completing, uncompleting, adding, and deleting children reconcile Goal
  completion correctly.
- Concurrent final-child completion inserts exactly one system notice.
- Reopening and recompleting never inserts a second notice.
- The notice satisfies the current `messages` schema, appears in ordinary chat
  reads, is skipped by analysis, and exercises the current downstream trigger.
- Keyset pages have no duplicates/skips when sort values tie; limits and the
  42-day calendar range are server-capped.
- Required text rejects blank strings; length limits, kind-specific fields,
  immutable fields, and database-owned timestamps are enforced server-side.

### Flutter tests

- Repository serialization and every RPC error mapping.
- Optimistic completion/link/delete success and rollback without losing a
  concurrent refetch.
- Providers retain data during refresh and invalidate from Realtime events,
  resume, and local writes.
- Home empty/loading/error/populated states and pagination per section.
- Goal progress, expansion, sole-child deletion UX, reopen behavior, and no
  duplicate celebration in chat.
- Event link picker only offers top-level live Tasks.
- Notes retain an unsaved draft after a failed save.
- Conversations summary priority and empty state.
- Timeline date grouping, completed Task styling, source-specific navigation,
  and old/new month invalidation after date edits.

### Migration verification

Run the local PostgreSQL rebuild/contracts used by this repository, then the
focused Flutter tests and `flutter analyze` for touched files. The migration
must be safe on a clean database and must not rely on the local harness's broad
grants masking production column privileges.

## 11. Implementation order

1. Schema, constraints, indexes, timestamp trigger, RLS, grants, and database
   contract tests.
2. Mutation RPCs plus Goal reconciliation/celebration concurrency tests.
3. Read RPCs, exact cursors, summary query, and range-limit tests.
4. Dart domain models, repository commands/queries, and error mapping.
5. Riverpod paging, optimistic mutation coordination, refresh retention, and
   Realtime invalidation.
6. Planning home, Goal/Task flows, and Event/link flows.
7. Notes list/editor.
8. Conversations summary row.
9. Timeline provider, dots, selected-day rows, navigation, and invalidation.
10. Focused widget/integration tests, full analysis, and manual two-device
    verification for concurrent completion and shared refresh.

## 12. Acceptance criteria

The feature is implementation-complete when both active partners can create,
edit, complete, link, and soft-delete the four v1 content types; all shared
changes refresh without destructive loading transitions; Goals never lose
their identity or drift from child completion; exactly one truthful
celebration is posted per Goal lifetime; Planning data is inaccessible outside
the active unarchived relationship; and dated Tasks/Events render and navigate
correctly in the existing Timeline without writing `timeline_events`.
