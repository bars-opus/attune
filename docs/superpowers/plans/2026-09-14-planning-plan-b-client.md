# Planning — Plan B: Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Flutter client for Planning — models, a repository over Plan A's RPCs, Riverpod providers with optimistic mutation and Realtime-driven refresh, the three screens (home, Notes, and the entry row), and Timeline integration — so both partners can actually use every RPC Plan A shipped.

**Architecture:** `lib/features/planning/` follows the existing `data/{models,repositories}` + `presentation/{providers,screens,widgets}` layout `lib/features/reminders/` and `lib/features/stories/` already use. Paginated lists (Goals, Tasks, Events, Notes) each get a keyset-pager `StateNotifier` following the exact shape `story_providers.dart`'s `_KeysetPager` already proved out — mounted guard, epoch token, refresh-coalescing — because that file's own doc comments record two real concurrency bugs (a disposed-provider crash, a stale-fetch-wins race) that this plan must not reintroduce by starting from scratch. A single Realtime subscription to `planning_change_signals` invalidates every Planning provider on a signal, exactly like Stories' own `story_change_signals` subscription.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifierProvider`, `StateNotifierProvider.family`), Supabase Dart client's `.rpc()` calls, `go_router`.

**Spec:** `docs/superpowers/specs/2026-09-14-planning-design.md` (this plan implements §6 Product surfaces and §7 Timeline integration; §3–§5 are already built by Plan A — read `docs/superpowers/plans/2026-09-14-planning-plan-a-backend.md` for the exact RPC names/signatures this plan calls). Also read `lib/architecture/STORIES.md` §5 (Surfaces) for the closest existing analog of everything built here.

**Depends on:** Plan A must be merged and its migrations applied to the local test database before Task 1 of this plan begins — every RPC name and column this plan calls is defined there. If Plan A is not yet merged, work in the same worktree Plan A used so its migrations are present locally, but do not merge Plan B independently of Plan A.

## Global Constraints

- **`_KeysetPager`'s shape, not its class.** `lib/features/stories/presentation/providers/story_providers.dart`'s `_KeysetPager` is file-private (leading underscore) — Dart will not let this plan's new files subclass it. Copy its exact pattern (mounted guard before every post-`await` state write; an `_epoch` int bumped by `refresh()` and checked after every await; `_refreshing`/`_refreshAgainRequested` coalescing so concurrent `refresh()` calls collapse into one extra round-trip rather than one each) into a new, equivalent class inside `lib/features/planning/presentation/providers/`. Do not attempt to import or extend the Stories class, and do not skip the epoch/mounted guards because "this is a fresh implementation" — they exist because omitting them shipped two real bugs in Stories (a `Bad state: Tried to use _Pager after 'dispose' was called` crash, and a slower stale fetch silently overwriting a faster fresh one).
- **Optimistic mutations roll back cleanly, and never clobber a concurrent partner update.** Per spec §9: "Partner edits while local optimistic mutation is pending → Server result/refetch wins; failed optimistic operation rolls back without dropping the partner update." Every optimistic UI update (completion toggle, link/unlink, soft delete) must be implemented as: apply locally → call RPC → on success, replace with the RPC's authoritative returned row (never assume the optimistic value was exactly right) → on failure, roll back to the pre-mutation state, not to whatever the provider's state is at the moment the failure arrives (which may have already moved from a partner's concurrent edit).
- **No push notifications from Planning.** Do not add any OneSignal category, any `scheduled_notifications` row, or any code path that sends a push for a Task/Goal/Event/Note change. The Realtime signal (`planning_change_signals`) is the only cross-device signal, and it is pull-shaped (a subscribed client refetches; nothing is pushed to a backgrounded app). (Spec §1, §2)
- **Never coerce Planning rows into `TimelineEventModel`.** Spec §7 is explicit: doing so would require fake `loggedBy`, `eventType`, `moodScore`, and `occurredAt` values. Planning gets its own model(s) and its own source-specific rendering inside the Timeline screen's selected-day area, following exactly how Reminders already sits beside — not inside — `TimelineEventModel`.
- **The 42-day calendar range is enforced by the RPC (Plan A), but the client must never call it with a wider range.** `list_planning_calendar_entries` raises an exception past 42 days; the provider that calls it must derive its `p_start_date`/`p_end_date` from exactly the visible month grid `CalendarStrip` renders, never from an arbitrary "load everything" range.
- **Every RPC error must be mapped to a typed failure the UI can act on**, not surfaced as a raw `PostgrestException` string. Follow `StoryRepository`'s `StoryApiError` pattern: a small sealed/enum-like error type distinguishing at minimum "not authorized / relationship ended" (fail closed, leave the screen) from "transient/network" (offer retry) from "validation" (e.g. the sole-child-delete rejection, which the UI must turn into the two-choice prompt spec §6.2 describes, never a generic error toast).
- **No test may pass vacuously.** Every widget/provider test added by this plan must be mutation-tested: break the behavior it claims to protect, confirm the test fails, then restore. This project has repeatedly shipped tests that passed with the protected behavior deleted (a fake that replaced a whole concrete class and hid a broken cursor; three UI rules guarded only by golden images; a calendar test suite where every fixture had a single author, hiding a per-item authorization bug). Do not add another one.
- **Per-file test runs are not sufficient evidence of a passing suite.** A previous task in this project passed every file in isolation while breaking the full suite (a real-clock wait that only starved under parallel load). Run the full commands this plan specifies, not just the file you just touched.
- **Follow this project's per-feature relationship-id convention.** `currentRelationshipIdProvider` is redefined independently inside `reminders_providers.dart`, `timeline_providers.dart`, and other feature provider files rather than imported across feature boundaries — Planning's own provider file follows the same convention with its own `currentRelationshipIdProvider`, not an import from `reminders_providers.dart` or `story_providers.dart`.

---

## Task 1: Domain models and the repository

**Files:**
- Create: `lib/features/planning/data/models/planning_goal_model.dart`
- Create: `lib/features/planning/data/models/planning_task_model.dart`
- Create: `lib/features/planning/data/models/planning_event_model.dart`
- Create: `lib/features/planning/data/models/planning_note_model.dart`
- Create: `lib/features/planning/data/models/planning_calendar_entry_model.dart`
- Create: `lib/features/planning/data/models/planning_summary_model.dart`
- Create: `lib/features/planning/data/repositories/planning_error.dart`
- Create: `lib/features/planning/data/repositories/planning_repository.dart`
- Test: `test/features/planning/planning_models_test.dart`
- Test: `test/features/planning/planning_repository_test.dart`

**Interfaces:**
- Consumes: Plan A's RPCs by exact name (`create_planning_task`, `create_planning_goal`, `add_planning_goal_task`, `update_planning_item`, `set_planning_task_completion`, `delete_planning_item`, `upsert_planning_event`, `delete_planning_event`, `link_planning_event_task`, `unlink_planning_event_task`, `upsert_planning_note`, `delete_planning_note`, `list_planning_goals`, `list_planning_goal_tasks`, `list_planning_tasks`, `list_planning_events`, `list_planning_notes`, `list_planning_calendar_entries`, `get_planning_summary`).
- Produces: `PlanningGoalModel`, `PlanningTaskModel`, `PlanningEventModel`, `PlanningNoteModel`, `PlanningCalendarEntryModel`, `PlanningSummaryModel` (all with `fromJson`/a `fromRow` factory matching the RPC's returned column names verbatim); `PlanningError` (sealed class: `PlanningError.unauthorized()`, `PlanningError.notFound()`, `PlanningError.validation(String message)`, `PlanningError.network(Object cause)`); `PlanningRepository` with one method per RPC above, each throwing a `PlanningError` on failure, never a raw exception. Every later task in this plan calls these exact class/method names.

- [ ] **Step 1: Write the failing model tests**

Create `test/features/planning/planning_models_test.dart`:

```dart
import 'package:attune/features/planning/data/models/planning_goal_model.dart';
import 'package:attune/features/planning/data/models/planning_task_model.dart';
import 'package:attune/features/planning/data/models/planning_event_model.dart';
import 'package:attune/features/planning/data/models/planning_note_model.dart';
import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/planning/data/models/planning_summary_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanningGoalModel', () {
    test('parses list_planning_goals row shape, including derived counts', () {
      final goal = PlanningGoalModel.fromRow({
        'id': 'g1',
        'title': 'Save for the trip',
        'note': null,
        'completed_at': null,
        'updated_at': '2026-09-14T10:00:00Z',
        'child_count': 2,
        'completed_child_count': 1,
      });
      expect(goal.id, 'g1');
      expect(goal.title, 'Save for the trip');
      expect(goal.isComplete, isFalse);
      expect(goal.childCount, 2);
      expect(goal.completedChildCount, 1);
      // Progress is derived from the row's own counts, never recomputed
      // client-side from a fetched child list that may not be loaded —
      // the Goals list screen shows progress WITHOUT expanding a goal.
      expect(goal.progressFraction, 0.5);
    });

    test('a goal with zero children reports zero progress, not NaN', () {
      final goal = PlanningGoalModel.fromRow({
        'id': 'g2', 'title': 'x', 'note': null, 'completed_at': null,
        'updated_at': '2026-09-14T10:00:00Z',
        'child_count': 0, 'completed_child_count': 0,
      });
      expect(goal.progressFraction, 0.0);
    });
  });

  group('PlanningTaskModel', () {
    test('parses planning_items row shape for a top-level task', () {
      final task = PlanningTaskModel.fromRow({
        'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': null,
        'title': 'Book the venue', 'note': null,
        'assigned_to': null, 'due_date': '2026-12-01',
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(task.id, 't1');
      expect(task.isTopLevel, isTrue);
      expect(task.isComplete, isFalse);
      expect(task.dueDate, DateTime.utc(2026, 12, 1));
    });

    test('a goal child task reports isTopLevel false', () {
      final task = PlanningTaskModel.fromRow({
        'id': 't2', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': 'g1',
        'title': 'Open account', 'note': null,
        'assigned_to': null, 'due_date': null,
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(task.isTopLevel, isFalse);
      expect(task.parentGoalId, 'g1');
    });

    test('item_kind = goal is rejected — this model is Tasks only', () {
      expect(
        () => PlanningTaskModel.fromRow({
          'id': 't3', 'relationship_id': 'r1', 'created_by': 'u1',
          'item_kind': 'goal', 'parent_goal_id': null,
          'title': 'not a task', 'note': null,
          'assigned_to': null, 'due_date': null,
          'completed_at': null, 'celebrated_at': null,
          'created_at': '2026-09-14T09:00:00Z',
          'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PlanningEventModel', () {
    test('parses planning_events row shape', () {
      final event = PlanningEventModel.fromRow({
        'id': 'e1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': "Sarah's birthday dinner", 'note': 'Try the Italian place',
        'event_date': '2026-12-25',
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(event.eventDate, DateTime.utc(2026, 12, 25));
      expect(event.note, 'Try the Italian place');
    });
  });

  group('PlanningNoteModel', () {
    test('parses planning_notes row shape', () {
      final note = PlanningNoteModel.fromRow({
        'id': 'n1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': 'Restaurants to try', 'body': 'Thai place on 5th',
        'created_at': '2026-09-14T09:00:00Z',
        'updated_at': '2026-09-14T09:00:00Z', 'deleted_at': null,
      });
      expect(note.body, 'Thai place on 5th');
    });
  });

  group('PlanningCalendarEntryModel', () {
    test('parses a task entry and an event entry from the same RPC shape', () {
      final taskEntry = PlanningCalendarEntryModel.fromRow({
        'entry_kind': 'task', 'entry_id': 't1', 'entry_date': '2026-06-01',
        'title': 'Water the plants', 'is_complete': false,
      });
      expect(taskEntry.kind, PlanningCalendarEntryKind.task);
      expect(taskEntry.isComplete, isFalse);

      final eventEntry = PlanningCalendarEntryModel.fromRow({
        'entry_kind': 'event', 'entry_id': 'e1', 'entry_date': '2026-12-25',
        'title': "Sarah's birthday dinner", 'is_complete': false,
      });
      expect(eventEntry.kind, PlanningCalendarEntryKind.event);
    });
  });

  group('PlanningSummaryModel', () {
    test('parses each of the five summary kinds get_planning_summary can return', () {
      for (final kind in [
        'overdue_task', 'upcoming_task', 'upcoming_event', 'goal', 'task', 'event', 'note',
      ]) {
        final summary = PlanningSummaryModel.fromRow({
          'kind': kind, 'id': 'x1', 'title': 'something',
          'context_date': kind == 'goal' || kind == 'note' ? null : '2026-09-14',
        });
        expect(summary.kind, isNotNull, reason: 'kind "$kind" must parse');
      }
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/planning/planning_models_test.dart`
Expected: fails to compile — none of the model files exist yet.

- [ ] **Step 3: Write the model files**

Create `lib/features/planning/data/models/planning_goal_model.dart`:

```dart
// lib/features/planning/data/models/planning_goal_model.dart

/// A Goal, as `list_planning_goals` returns it — title plus the two
/// derived counts the RPC computes from live children (Plan A, Task 4).
/// Progress is a property of THIS row, not recomputed from a fetched
/// child list: the Goals section shows a progress fraction for every
/// goal without expanding any of them (spec §6.2).
class PlanningGoalModel {
  final String id;
  final String title;
  final String? note;
  final DateTime? completedAt;
  final DateTime updatedAt;
  final int childCount;
  final int completedChildCount;

  const PlanningGoalModel({
    required this.id,
    required this.title,
    this.note,
    this.completedAt,
    required this.updatedAt,
    required this.childCount,
    required this.completedChildCount,
  });

  bool get isComplete => completedAt != null;

  /// 0.0 when childCount is 0 (a state Plan A's invariants make
  /// transient/impossible in practice, but this must never divide by
  /// zero if it is ever observed mid-mutation).
  double get progressFraction =>
      childCount == 0 ? 0.0 : completedChildCount / childCount;

  factory PlanningGoalModel.fromRow(Map<String, dynamic> row) {
    return PlanningGoalModel(
      id: row['id'] as String,
      title: row['title'] as String,
      note: row['note'] as String?,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      childCount: (row['child_count'] as num).toInt(),
      completedChildCount: (row['completed_child_count'] as num).toInt(),
    );
  }
}
```

Create `lib/features/planning/data/models/planning_task_model.dart`:

```dart
// lib/features/planning/data/models/planning_task_model.dart

/// A Task row from `planning_items` (`item_kind = 'task'`). Rejects a
/// Goal row rather than silently misrepresenting it — this model's
/// entire contract is "this is a Task," so a caller that accidentally
/// hands it a Goal row has a bug worth failing loudly on rather than
/// producing a Task with nonsensical isTopLevel/assignedTo semantics.
class PlanningTaskModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String? parentGoalId;
  final String title;
  final String? note;
  final String? assignedTo;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PlanningTaskModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    this.parentGoalId,
    required this.title,
    this.note,
    this.assignedTo,
    this.dueDate,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTopLevel => parentGoalId == null;
  bool get isComplete => completedAt != null;

  factory PlanningTaskModel.fromRow(Map<String, dynamic> row) {
    if (row['item_kind'] != 'task') {
      throw ArgumentError(
        'PlanningTaskModel.fromRow received item_kind="${row['item_kind']}", expected "task"',
      );
    }
    return PlanningTaskModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      parentGoalId: row['parent_goal_id'] as String?,
      title: row['title'] as String,
      note: row['note'] as String?,
      assignedTo: row['assigned_to'] as String?,
      dueDate: row['due_date'] == null
          ? null
          : DateTime.parse(row['due_date'] as String),
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
```

Create `lib/features/planning/data/models/planning_event_model.dart`:

```dart
// lib/features/planning/data/models/planning_event_model.dart

class PlanningEventModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String title;
  final String? note;
  final DateTime eventDate;
  final DateTime updatedAt;

  const PlanningEventModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    required this.title,
    this.note,
    required this.eventDate,
    required this.updatedAt,
  });

  bool get isPast => eventDate.isBefore(DateTime.now());

  factory PlanningEventModel.fromRow(Map<String, dynamic> row) {
    return PlanningEventModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      title: row['title'] as String,
      note: row['note'] as String?,
      eventDate: DateTime.parse(row['event_date'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
```

Create `lib/features/planning/data/models/planning_note_model.dart`:

```dart
// lib/features/planning/data/models/planning_note_model.dart

class PlanningNoteModel {
  final String id;
  final String relationshipId;
  final String? createdBy;
  final String title;
  final String body;
  final DateTime updatedAt;

  const PlanningNoteModel({
    required this.id,
    required this.relationshipId,
    this.createdBy,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  factory PlanningNoteModel.fromRow(Map<String, dynamic> row) {
    return PlanningNoteModel(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      createdBy: row['created_by'] as String?,
      title: row['title'] as String,
      body: row['body'] as String? ?? '',
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
```

Create `lib/features/planning/data/models/planning_calendar_entry_model.dart`:

```dart
// lib/features/planning/data/models/planning_calendar_entry_model.dart

enum PlanningCalendarEntryKind { task, event }

/// One row from `list_planning_calendar_entries` — a Task's due date OR
/// an Event's date, composed by the Timeline screen alongside timeline
/// events and reminders (spec §7). Deliberately its own type, never
/// coerced into `TimelineEventModel` (spec §7's explicit rule).
class PlanningCalendarEntryModel {
  final PlanningCalendarEntryKind kind;
  final String id;
  final DateTime date;
  final String title;
  final bool isComplete;

  const PlanningCalendarEntryModel({
    required this.kind,
    required this.id,
    required this.date,
    required this.title,
    required this.isComplete,
  });

  factory PlanningCalendarEntryModel.fromRow(Map<String, dynamic> row) {
    return PlanningCalendarEntryModel(
      kind: row['entry_kind'] == 'task'
          ? PlanningCalendarEntryKind.task
          : PlanningCalendarEntryKind.event,
      id: row['entry_id'] as String,
      date: DateTime.parse(row['entry_date'] as String),
      title: row['title'] as String,
      isComplete: row['is_complete'] as bool,
    );
  }
}
```

Create `lib/features/planning/data/models/planning_summary_model.dart`:

```dart
// lib/features/planning/data/models/planning_summary_model.dart

/// One row from `get_planning_summary` — the single item the
/// conversations-screen entry row shows (spec §6.1). `kind` is one of
/// the seven values that RPC can return: overdue_task, upcoming_task,
/// upcoming_event, goal, task, event, note. Kept as a raw string rather
/// than an enum here because the entry row's display logic (§6.1's
/// priority list) branches on it directly and a seventh value added to
/// the RPC later should not require a matching Dart enum edit to avoid
/// a compile error — an unrecognized kind falls back to a generic
/// label rather than crashing.
class PlanningSummaryModel {
  final String kind;
  final String id;
  final String title;
  final DateTime? contextDate;

  const PlanningSummaryModel({
    required this.kind,
    required this.id,
    required this.title,
    this.contextDate,
  });

  factory PlanningSummaryModel.fromRow(Map<String, dynamic> row) {
    return PlanningSummaryModel(
      kind: row['kind'] as String,
      id: row['id'] as String,
      title: row['title'] as String,
      contextDate: row['context_date'] == null
          ? null
          : DateTime.parse(row['context_date'] as String),
    );
  }
}
```

- [ ] **Step 4: Run the model tests to verify they pass**

Run: `flutter test test/features/planning/planning_models_test.dart`
Expected: all pass.

- [ ] **Step 5: Write the failing repository tests**

Create `test/features/planning/planning_repository_test.dart`:

```dart
// Repository-level tests exercise error MAPPING, not live RPC behavior
// (Plan A's own SQL contract tests already prove the RPCs correct).
// A fake SupabaseClient stand-in is not practical for `.rpc()` calls
// against the real generic PostgREST builder (the same reasoning
// story_repository_test.dart gives for faking its own gateway
// interface instead) — so this repository takes an injected gateway
// interface, and these tests fake THAT, not SupabaseClient itself.
import 'package:attune/features/planning/data/repositories/planning_error.dart';
import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRpcGateway implements PlanningRpcGateway {
  Object? nextError;
  dynamic nextResult;
  String? lastCalledFunction;
  Map<String, dynamic>? lastCalledParams;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    lastCalledFunction = function;
    lastCalledParams = params;
    if (nextError != null) throw nextError!;
    return nextResult;
  }
}

void main() {
  late _FakeRpcGateway gateway;
  late PlanningRepository repository;

  setUp(() {
    gateway = _FakeRpcGateway();
    repository = PlanningRepository(gateway);
  });

  test('createTask calls create_planning_task with the exact param names', () async {
    gateway.nextResult = {
      'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
      'item_kind': 'task', 'parent_goal_id': null, 'title': 'Book the venue',
      'note': null, 'assigned_to': null, 'due_date': null,
      'completed_at': null, 'celebrated_at': null,
      'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
      'deleted_at': null,
    };
    await repository.createTask(
      id: 't1', relationshipId: 'r1', title: 'Book the venue',
    );
    expect(gateway.lastCalledFunction, 'create_planning_task');
    expect(gateway.lastCalledParams, containsPair('p_id', 't1'));
    expect(gateway.lastCalledParams, containsPair('p_relationship_id', 'r1'));
    expect(gateway.lastCalledParams, containsPair('p_title', 'Book the venue'));
  });

  test('a PostgrestException with code 42501 maps to PlanningError.unauthorized', () async {
    gateway.nextError = PostgrestException(message: 'permission denied', code: '42501');
    await expectLater(
      repository.createTask(id: 't1', relationshipId: 'r1', title: 'x'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningUnauthorizedError>(),
      )),
    );
  });

  test('the sole-child-delete rejection maps to PlanningError.validation, not a generic error', () async {
    gateway.nextError = PostgrestException(
      message: 'Delete the goal instead, or add another task first',
      code: 'P0001',
    );
    await expectLater(
      repository.deleteItem(id: 't1'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningValidationError>().having(
          (e) => e.message, 'message', contains('Delete the goal instead'),
        ),
      )),
    );
  });

  test('a network-shaped failure maps to PlanningError.network, not unauthorized', () async {
    gateway.nextError = const SocketExceptionStub();
    await expectLater(
      repository.createTask(id: 't1', relationshipId: 'r1', title: 'x'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningNetworkError>(),
      )),
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
```

- [ ] **Step 6: Run the tests to verify they fail**

Run: `flutter test test/features/planning/planning_repository_test.dart`
Expected: fails to compile — `PlanningRepository`, `PlanningError`, and
`PlanningRpcGateway` do not exist yet.

- [ ] **Step 7: Write `planning_error.dart`**

```dart
// lib/features/planning/data/repositories/planning_error.dart

/// Every failure the Planning repository can throw. Never a raw
/// PostgrestException reaching the UI — the UI branches on WHICH of
/// these it got (fail-closed-and-leave vs. offer-retry vs. show-this-
/// exact-validation-message), so a string comparison against an error
/// message is not a substitute for this type.
sealed class PlanningError implements Exception {
  const PlanningError();
}

/// The caller is not authenticated, is not a member of the
/// relationship, or the relationship has ended/archived. The UI must
/// fail closed: clear Planning provider state and leave the screen
/// (spec §9), never retry automatically.
class PlanningUnauthorizedError extends PlanningError {
  const PlanningUnauthorizedError();
}

/// The target row does not exist (already deleted by the other
/// partner, or never existed). Distinct from unauthorized: this is not
/// a security failure, just "that thing isn't there anymore" — the UI
/// may simply drop it from the list rather than showing an error.
class PlanningNotFoundError extends PlanningError {
  const PlanningNotFoundError();
}

/// A rule the RPC enforces was violated (sole-child delete, 100-child
/// cap, a non-member assignee, deep nesting, ...). `message` is the
/// RPC's own RAISE EXCEPTION text — safe to show directly, since every
/// message Plan A's RPCs raise is already written for a human reader,
/// never an internal detail.
class PlanningValidationError extends PlanningError {
  final String message;
  const PlanningValidationError(this.message);
}

/// A transient/network-shaped failure — the UI should offer retry
/// rather than treating this as authoritative.
class PlanningNetworkError extends PlanningError {
  final Object cause;
  const PlanningNetworkError(this.cause);
}
```

- [ ] **Step 8: Write `planning_repository.dart`**

```dart
// lib/features/planning/data/repositories/planning_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'planning_error.dart';
import '../models/planning_goal_model.dart';
import '../models/planning_task_model.dart';
import '../models/planning_event_model.dart';
import '../models/planning_note_model.dart';
import '../models/planning_calendar_entry_model.dart';
import '../models/planning_summary_model.dart';

/// The seam this repository calls through, so tests can fake it
/// instead of the real, heavily-generic SupabaseClient RPC builder —
/// the same reasoning story_repository.dart's own gateway interface
/// gives for doing this rather than mocking SupabaseClient directly.
abstract class PlanningRpcGateway {
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params});
}

class SupabasePlanningRpcGateway implements PlanningRpcGateway {
  final SupabaseClient _supabase;
  const SupabasePlanningRpcGateway(this._supabase);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    return _supabase.rpc(function, params: params);
  }
}

class PlanningRepository {
  final PlanningRpcGateway _gateway;
  const PlanningRepository(this._gateway);

  Future<T> _call<T>(
    String function, {
    Map<String, dynamic>? params,
    required T Function(dynamic result) onResult,
  }) async {
    try {
      final result = await _gateway.rpc(function, params: params);
      return onResult(result);
    } catch (error) {
      throw _mapError(error);
    }
  }

  PlanningError _mapError(Object error) {
    if (error is PostgrestException) {
      // 42501 is Postgres' own "insufficient_privilege" SQLSTATE,
      // raised when RLS or a REVOKE refuses the call outright.
      if (error.code == '42501') return const PlanningUnauthorizedError();
      // Every RAISE EXCEPTION in Plan A's RPCs surfaces as SQLSTATE
      // P0001 (plpgsql's own generic "raised_exception" code) with the
      // RPC's own message text — that text is what distinguishes
      // "Planning unavailable" (treat as unauthorized: the RPC uses
      // this exact generic message specifically to avoid forming an
      // existence oracle) from every other validation message (show
      // it directly).
      if (error.code == 'P0001') {
        if (error.message == 'Planning unavailable' ||
            error.message == 'Not authenticated') {
          return const PlanningUnauthorizedError();
        }
        return PlanningValidationError(error.message);
      }
      return PlanningNetworkError(error);
    }
    return PlanningNetworkError(error);
  }

  // --- Tasks and Goals ---

  Future<PlanningTaskModel> createTask({
    required String id,
    required String relationshipId,
    required String title,
    String? note,
    String? assignedTo,
    DateTime? dueDate,
  }) => _call(
    'create_planning_task',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_note': note,
      'p_assigned_to': assignedTo,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<PlanningGoalModel> createGoal({
    required String goalId,
    required String firstTaskId,
    required String relationshipId,
    required String goalTitle,
    required String firstTaskTitle,
  }) => _call(
    'create_planning_goal',
    params: {
      'p_goal_id': goalId,
      'p_first_task_id': firstTaskId,
      'p_relationship_id': relationshipId,
      'p_goal_title': goalTitle,
      'p_first_task_title': firstTaskTitle,
    },
    onResult: (r) {
      final row = Map<String, dynamic>.from(r as Map);
      return PlanningGoalModel(
        id: row['id'] as String,
        title: row['title'] as String,
        note: row['note'] as String?,
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(row['completed_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        // A freshly created goal always has exactly one child, not
        // complete — the RPC's return row has no child_count column
        // (it returns the raw planning_items row, not the
        // list_planning_goals aggregate shape), so this is filled in
        // from what create_planning_goal's own invariant guarantees
        // rather than from a column that is not there.
        childCount: 1,
        completedChildCount: 0,
      );
    },
  );

  Future<PlanningTaskModel> addGoalTask({
    required String taskId,
    required String goalId,
    required String title,
    String? note,
    DateTime? dueDate,
  }) => _call(
    'add_planning_goal_task',
    params: {
      'p_task_id': taskId,
      'p_goal_id': goalId,
      'p_title': title,
      'p_note': note,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<PlanningTaskModel> updateItem({
    required String id,
    String? title,
    String? note,
    String? assignedTo,
    DateTime? dueDate,
  }) => _call(
    'update_planning_item',
    params: {
      'p_id': id,
      'p_title': title,
      'p_note': note,
      'p_assigned_to': assignedTo,
      'p_due_date': dueDate?.toIso8601String().split('T').first,
    },
    onResult: (r) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<PlanningTaskModel> setTaskCompletion({
    required String taskId,
    required bool isComplete,
  }) => _call(
    'set_planning_task_completion',
    params: {'p_task_id': taskId, 'p_is_complete': isComplete},
    onResult: (r) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteItem({required String id}) => _call(
    'delete_planning_item',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  // --- Events and links ---

  Future<PlanningEventModel> upsertEvent({
    required String id,
    required String relationshipId,
    required String title,
    String? note,
    required DateTime eventDate,
  }) => _call(
    'upsert_planning_event',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_note': note,
      'p_event_date': eventDate.toIso8601String().split('T').first,
    },
    onResult: (r) => PlanningEventModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteEvent({required String id}) => _call(
    'delete_planning_event',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  Future<bool> linkEventTask({
    required String eventId,
    required String itemId,
  }) => _call(
    'link_planning_event_task',
    params: {'p_event_id': eventId, 'p_item_id': itemId},
    onResult: (r) => r as bool,
  );

  Future<bool> unlinkEventTask({
    required String eventId,
    required String itemId,
  }) => _call(
    'unlink_planning_event_task',
    params: {'p_event_id': eventId, 'p_item_id': itemId},
    onResult: (r) => r as bool,
  );

  // --- Notes ---

  Future<PlanningNoteModel> upsertNote({
    required String id,
    required String relationshipId,
    required String title,
    required String body,
  }) => _call(
    'upsert_planning_note',
    params: {
      'p_id': id,
      'p_relationship_id': relationshipId,
      'p_title': title,
      'p_body': body,
    },
    onResult: (r) => PlanningNoteModel.fromRow(Map<String, dynamic>.from(r as Map)),
  );

  Future<bool> deleteNote({required String id}) => _call(
    'delete_planning_note',
    params: {'p_id': id},
    onResult: (r) => r as bool,
  );

  // --- Reads ---

  Future<List<PlanningGoalModel>> listGoals({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 30,
  }) => _call(
    'list_planning_goals',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningGoalModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<List<PlanningTaskModel>> listGoalTasks({
    required String goalId,
    DateTime? afterCreatedAt,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_goal_tasks',
    params: {
      'p_goal_id': goalId,
      'p_after_created_at': afterCreatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<List<PlanningTaskModel>> listTasks({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_tasks',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_due_date': null,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningTaskModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<List<PlanningEventModel>> listEvents({
    required String relationshipId,
    required DateTime today,
    required bool upcoming,
    DateTime? afterDate,
    String? afterId,
    int limit = 50,
  }) => _call(
    'list_planning_events',
    params: {
      'p_relationship_id': relationshipId,
      'p_today': today.toIso8601String().split('T').first,
      'p_upcoming': upcoming,
      'p_after_date': afterDate?.toIso8601String().split('T').first,
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningEventModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<List<PlanningNoteModel>> listNotes({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 30,
  }) => _call(
    'list_planning_notes',
    params: {
      'p_relationship_id': relationshipId,
      'p_after_updated_at': afterUpdatedAt?.toIso8601String(),
      'p_after_id': afterId,
      'p_limit': limit,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningNoteModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<List<PlanningCalendarEntryModel>> listCalendarEntries({
    required String relationshipId,
    required DateTime startDate,
    required DateTime endDate,
  }) => _call(
    'list_planning_calendar_entries',
    params: {
      'p_relationship_id': relationshipId,
      'p_start_date': startDate.toIso8601String().split('T').first,
      'p_end_date': endDate.toIso8601String().split('T').first,
    },
    onResult: (r) => (r as List)
        .map((row) => PlanningCalendarEntryModel.fromRow(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false),
  );

  Future<PlanningSummaryModel?> getSummary({
    required String relationshipId,
    required DateTime today,
  }) => _call(
    'get_planning_summary',
    params: {
      'p_relationship_id': relationshipId,
      'p_today': today.toIso8601String().split('T').first,
    },
    onResult: (r) {
      final rows = r as List;
      if (rows.isEmpty) return null;
      return PlanningSummaryModel.fromRow(Map<String, dynamic>.from(rows.first as Map));
    },
  );
}
```

- [ ] **Step 9: Run the repository tests to verify they pass**

Run: `flutter test test/features/planning/planning_repository_test.dart`
Expected: all pass.

- [ ] **Step 10: Mutation-test the error mapping**

By hand: temporarily change the `error.code == '42501'` check to
`error.code == '99999'` and confirm the unauthorized-mapping test now
fails; restore. Temporarily remove the `'Planning unavailable'` /
`'Not authenticated'` special-case inside the `P0001` branch and confirm
a test asserting those two messages map to `PlanningUnauthorizedError`
(add one now if Step 5 did not already cover it exactly) now fails;
restore. Record both results in this task's final report.

- [ ] **Step 11: Run `flutter analyze` on the new files**

Run: `flutter analyze lib/features/planning test/features/planning`
Expected: 0 errors.

- [ ] **Step 12: Commit**

```bash
git add lib/features/planning/data test/features/planning/planning_models_test.dart \
        test/features/planning/planning_repository_test.dart
git commit -m "feat(planning): domain models and a typed-error repository over the RPCs"
```

---

## Task 2: Riverpod providers, pagination, and Realtime refresh

**Files:**
- Create: `lib/features/planning/presentation/providers/planning_providers.dart`
- Test: `test/features/planning/planning_providers_test.dart`

**Interfaces:**
- Consumes: `PlanningRepository` and every model from Task 1.
- Produces: `planningRepositoryProvider`, `currentRelationshipIdProvider` (Planning's own copy, per Global Constraints), `planningChangeSignalProvider(relationshipId)` (a `StreamProvider.autoDispose.family<void, String>`), `planningGoalsProvider(relationshipId)`, `planningGoalTasksProvider(PlanningGoalTasksKey)`, `planningTasksProvider(relationshipId)`, `planningEventsProvider(PlanningEventsKey)` (upcoming/past split), `planningNotesProvider(relationshipId)`, `planningCalendarEntriesProvider(PlanningCalendarRangeKey)`, `planningSummaryProvider(relationshipId)`. Every screen task below watches these exact provider names.

- [ ] **Step 1: Write the failing tests**

Create `test/features/planning/planning_providers_test.dart`:

```dart
// Provider tests focus on the two concurrency properties Stories'
// _KeysetPager was built to fix, plus the .family key-equality trap
// that shipped a real leak there — not on RPC correctness, which
// Plan A's own SQL contracts already prove.
import 'dart:async';

import 'package:attune/features/planning/data/models/planning_task_model.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements PlanningReadGateway {
  final List<List<PlanningTaskModel>> taskPages;
  int callCount = 0;
  final _signalControllers = <String, StreamController<void>>{};

  _FakeGateway(this.taskPages);

  @override
  Future<List<PlanningTaskModel>> listTasks({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 50,
  }) async {
    final page = taskPages[callCount.clamp(0, taskPages.length - 1)];
    callCount++;
    return page;
  }

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) {
    return (_signalControllers[relationshipId] ??=
            StreamController<void>.broadcast())
        .stream;
  }

  void emitSignal(String relationshipId) {
    _signalControllers[relationshipId]?.add(null);
  }

  @override
  void disposeChannel(String relationshipId) {
    _signalControllers.remove(relationshipId)?.close();
  }
}

PlanningTaskModel _task(String id) => PlanningTaskModel.fromRow({
  'id': id, 'relationship_id': 'r1', 'created_by': 'u1',
  'item_kind': 'task', 'parent_goal_id': null, 'title': 'task $id',
  'note': null, 'assigned_to': null, 'due_date': null,
  'completed_at': null, 'celebrated_at': null,
  'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
  'deleted_at': null,
});

void main() {
  test(
    'a late fetch from a superseded refresh does not overwrite a newer '
    'one — the epoch guard Stories shipped without, twice',
    () async {
      final completer1 = Completer<List<PlanningTaskModel>>();
      final completer2 = Completer<List<PlanningTaskModel>>();
      final calls = <Completer<List<PlanningTaskModel>>>[completer1, completer2];
      var callIndex = 0;

      final container = ProviderContainer(overrides: [
        planningTaskGatewayProvider.overrideWithValue(_SlowGateway(() {
          final c = calls[callIndex.clamp(0, calls.length - 1)];
          callIndex++;
          return c.future;
        })),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(planningTasksProvider('r1').notifier);
      // Two refreshes in flight; the SECOND must win even if the FIRST's
      // future resolves last.
      final firstRefresh = notifier.refresh();
      final secondRefresh = notifier.refresh();

      completer2.complete([_task('from-second-refresh')]);
      await secondRefresh;
      completer1.complete([_task('from-first-refresh-STALE')]);
      await firstRefresh;
      await Future<void>.delayed(Duration.zero);

      final state = container.read(planningTasksProvider('r1'));
      expect(
        state.value?.map((t) => t.id),
        ['from-second-refresh'],
        reason: 'the stale first refresh must not have overwritten the second',
      );
    },
  );

  test(
    'disposing the provider while a refresh is in flight does not throw '
    'when that refresh later completes',
    () async {
      final completer = Completer<List<PlanningTaskModel>>();
      final container = ProviderContainer(overrides: [
        planningTaskGatewayProvider.overrideWithValue(
          _SlowGateway(() => completer.future),
        ),
      ]);

      final notifier = container.read(planningTasksProvider('r1').notifier);
      unawaited(notifier.refresh());
      container.dispose(); // dispose WHILE the refresh is still pending

      completer.complete([_task('t1')]);
      // Must not throw "Bad state: Tried to use ... after `dispose`".
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'a calendar-range .family key compares equal for two DateTimes built '
    'a moment apart — the exact leak Stories shipped (fix round 1, '
    'finding 6) must not recur here',
    () {
      final keyA = PlanningCalendarRangeKey(
        relationshipId: 'r1',
        startDate: DateTime(2026, 6, 1, 10, 0, 0),
        endDate: DateTime(2026, 6, 30, 10, 0, 1), // one second later
      );
      final keyB = PlanningCalendarRangeKey(
        relationshipId: 'r1',
        startDate: DateTime(2026, 6, 1, 15, 30, 0), // different time, same DAY
        endDate: DateTime(2026, 6, 30, 9, 0, 0),
      );
      expect(
        keyA,
        keyB,
        reason:
            'two ranges naming the same calendar days must compare equal '
            'regardless of time-of-day, or every rebuild mints a new '
            '.family instance and leaks a Realtime subscription',
      );
      expect(keyA.hashCode, keyB.hashCode);
    },
  );
}

class _SlowGateway implements PlanningTaskGateway {
  final Future<List<PlanningTaskModel>> Function() _next;
  _SlowGateway(this._next);

  @override
  Future<List<PlanningTaskModel>> listTasks({
    required String relationshipId,
    DateTime? afterUpdatedAt,
    String? afterId,
    int limit = 50,
  }) => _next();
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/planning/planning_providers_test.dart`
Expected: fails to compile — none of these providers/types exist yet.

- [ ] **Step 3: Write `planning_providers.dart`**

```dart
// lib/features/planning/presentation/providers/planning_providers.dart
//
// Riverpod surface for Planning: paginated Goals/Tasks/Events/Notes,
// the calendar-range read, the conversations-screen summary, and the
// planning_change_signals refetch subscription that keeps all of them
// current.
//
// The pager below is a DELIBERATE copy of story_providers.dart's own
// _KeysetPager shape, not a subclass of it (that class is file-private
// and cannot be extended from here — see this plan's Global
// Constraints). Two real bugs shipped in that original before its own
// fix round: (F1/F2) a disposed provider's post-await continuation
// wrote to `state` and crashed / a stale fetch silently overwrote a
// fresher one, fixed by a `mounted` guard plus a bumped `_epoch`
// checked after every await; (F6) a `.family` key holding a bare
// `DateTime` compared unequal for two rebuilds a moment apart, so
// every rebuild opened a NEW Realtime subscription and leaked the old
// one — fixed by truncating to day-granularity in the key's own
// `==`/`hashCode`. Both fixes are reproduced here from the start.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/planning_calendar_entry_model.dart';
import '../../data/models/planning_event_model.dart';
import '../../data/models/planning_goal_model.dart';
import '../../data/models/planning_note_model.dart';
import '../../data/models/planning_summary_model.dart';
import '../../data/models/planning_task_model.dart';
import '../../data/repositories/planning_repository.dart';

final _supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  final supabase = ref.read(_supabaseClientProvider);
  return PlanningRepository(SupabasePlanningRpcGateway(supabase));
});

/// Feature-local copy of the active relationship id, following the same
/// per-feature convention `reminders_providers.dart`/`timeline_providers.dart`
/// already use rather than importing across feature boundaries.
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(_supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();
  return response?['id'] as String?;
});

// --- Realtime signal ---

final _signalControllers = <String, StreamController<void>>{};
final _signalChannels = <String, RealtimeChannel>{};

/// Emits once per meaningful Planning change for [relationshipId], and
/// once more on every successful (re)subscribe (including the first) —
/// closing the gap a websocket drop-and-reconnect would otherwise leave,
/// the same reasoning `story_read_repository.dart`'s own
/// `watchChangeSignal` gives. The payload (version/updated_at) is
/// intentionally dropped; only "something changed, refetch" survives —
/// Realtime is a refetch signal here, never a second source of truth
/// (spec §6.4).
final planningChangeSignalProvider = StreamProvider.autoDispose
    .family<void, String>((ref, relationshipId) {
      final supabase = ref.read(_supabaseClientProvider);
      ref.onDispose(() {
        final channel = _signalChannels.remove(relationshipId);
        if (channel != null) unawaited(supabase.removeChannel(channel));
        _signalControllers.remove(relationshipId)?.close();
      });

      final controller = StreamController<void>.broadcast();
      _signalControllers[relationshipId] = controller;

      final channel = supabase
          .channel('planning-signals:$relationshipId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'planning_change_signals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'relationship_id',
              value: relationshipId,
            ),
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          )
          .subscribe((status, error) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (!controller.isClosed) controller.add(null);
            }
          });
      _signalChannels[relationshipId] = channel;

      // While backgrounded the socket is torn down entirely, so a
      // resume always re-reads canonical state through the same
      // refetch pipe rather than relying on the (also correct, but
      // insufficient alone) resubscribe emission above.
      final lifecycleListener = AppLifecycleListener(
        onResume: () {
          if (!controller.isClosed) controller.add(null);
        },
      );
      ref.onDispose(lifecycleListener.dispose);

      return controller.stream;
    });

// --- The keyset pager base, copied in shape from Stories (see this
// file's header) ---

abstract class _PlanningKeysetPager<T>
    extends StateNotifier<AsyncValue<List<T>>> {
  _PlanningKeysetPager() : super(const AsyncValue.loading()) {
    unawaited(refresh());
  }

  bool _loadingMore = false;
  bool _hasMore = true;
  int _epoch = 0;
  bool _refreshing = false;
  bool _refreshAgainRequested = false;

  Future<List<T>> fetchFirstPage();
  Future<List<T>> fetchNextPage(List<T> current);

  bool get hasMore => _hasMore;

  Future<void> refresh() async {
    if (_refreshing) {
      _refreshAgainRequested = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgainRequested = false;
        final epoch = ++_epoch;
        if (mounted) state = const AsyncValue.loading();
        _hasMore = true;
        try {
          final page = await fetchFirstPage();
          if (!mounted || epoch != _epoch) continue;
          state = AsyncValue.data(page);
        } catch (error, stackTrace) {
          if (!mounted || epoch != _epoch) continue;
          state = AsyncValue.error(error, stackTrace);
        }
      } while (_refreshAgainRequested && mounted);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;
    _loadingMore = true;
    final epoch = _epoch; // capture WITHOUT bumping — refresh always wins
    try {
      final page = await fetchNextPage(current);
      if (!mounted || epoch != _epoch) return; // superseded by a refresh
      state = AsyncValue.data([...current, ...page]);
    } catch (error, stackTrace) {
      if (!mounted || epoch != _epoch) return;
      state = AsyncValue<List<T>>.error(error, stackTrace)
          .copyWithPrevious(AsyncValue.data(current));
    } finally {
      _loadingMore = false;
    }
  }
}

// --- Goals ---

class PlanningGoalsNotifier extends _PlanningKeysetPager<PlanningGoalModel> {
  PlanningGoalsNotifier(this._repository, this._relationshipId);
  final PlanningRepository _repository;
  final String _relationshipId;

  @override
  Future<List<PlanningGoalModel>> fetchFirstPage() =>
      _repository.listGoals(relationshipId: _relationshipId);

  @override
  Future<List<PlanningGoalModel>> fetchNextPage(
    List<PlanningGoalModel> current,
  ) {
    final last = current.last;
    return _repository.listGoals(
      relationshipId: _relationshipId,
      afterUpdatedAt: last.updatedAt,
      afterId: last.id,
    );
  }
}

final planningGoalsProvider = StateNotifierProvider.autoDispose
    .family<PlanningGoalsNotifier, AsyncValue<List<PlanningGoalModel>>, String>(
      (ref, relationshipId) {
        final repository = ref.watch(planningRepositoryProvider);
        final notifier = PlanningGoalsNotifier(repository, relationshipId);
        ref.listen(planningChangeSignalProvider(relationshipId), (
          previous,
          next,
        ) {
          if (next.hasValue) unawaited(notifier.refresh());
        });
        return notifier;
      },
    );

/// A single Goal's children, keyed by goal id — fetched only once that
/// Goal is expanded (spec §6.2), never eagerly joined into the Goals
/// list read.
final planningGoalTasksProvider = FutureProvider.autoDispose
    .family<List<PlanningTaskModel>, String>((ref, goalId) {
      final repository = ref.watch(planningRepositoryProvider);
      return repository.listGoalTasks(goalId: goalId);
    });

// --- Tasks ---

class PlanningTasksNotifier extends _PlanningKeysetPager<PlanningTaskModel> {
  PlanningTasksNotifier(this._repository, this._relationshipId);
  final PlanningRepository _repository;
  final String _relationshipId;

  @override
  Future<List<PlanningTaskModel>> fetchFirstPage() =>
      _repository.listTasks(relationshipId: _relationshipId);

  @override
  Future<List<PlanningTaskModel>> fetchNextPage(
    List<PlanningTaskModel> current,
  ) {
    final last = current.last;
    return _repository.listTasks(
      relationshipId: _relationshipId,
      afterUpdatedAt: last.updatedAt,
      afterId: last.id,
    );
  }
}

final planningTasksProvider = StateNotifierProvider.autoDispose
    .family<PlanningTasksNotifier, AsyncValue<List<PlanningTaskModel>>, String>(
      (ref, relationshipId) {
        final repository = ref.watch(planningRepositoryProvider);
        final notifier = PlanningTasksNotifier(repository, relationshipId);
        ref.listen(planningChangeSignalProvider(relationshipId), (
          previous,
          next,
        ) {
          if (next.hasValue) unawaited(notifier.refresh());
        });
        return notifier;
      },
    );

// --- Events ---

@immutable
class PlanningEventsKey {
  const PlanningEventsKey({required this.relationshipId, required this.upcoming});
  final String relationshipId;
  final bool upcoming;

  @override
  bool operator ==(Object other) =>
      other is PlanningEventsKey &&
      other.relationshipId == relationshipId &&
      other.upcoming == upcoming;

  @override
  int get hashCode => Object.hash(relationshipId, upcoming);
}

class PlanningEventsNotifier extends _PlanningKeysetPager<PlanningEventModel> {
  PlanningEventsNotifier(this._repository, this._key);
  final PlanningRepository _repository;
  final PlanningEventsKey _key;

  @override
  Future<List<PlanningEventModel>> fetchFirstPage() => _repository.listEvents(
    relationshipId: _key.relationshipId,
    today: DateTime.now(),
    upcoming: _key.upcoming,
  );

  @override
  Future<List<PlanningEventModel>> fetchNextPage(
    List<PlanningEventModel> current,
  ) {
    final last = current.last;
    return _repository.listEvents(
      relationshipId: _key.relationshipId,
      today: DateTime.now(),
      upcoming: _key.upcoming,
      afterDate: last.eventDate,
      afterId: last.id,
    );
  }
}

final planningEventsProvider = StateNotifierProvider.autoDispose
    .family<
      PlanningEventsNotifier,
      AsyncValue<List<PlanningEventModel>>,
      PlanningEventsKey
    >((ref, key) {
      final repository = ref.watch(planningRepositoryProvider);
      final notifier = PlanningEventsNotifier(repository, key);
      ref.listen(planningChangeSignalProvider(key.relationshipId), (
        previous,
        next,
      ) {
        if (next.hasValue) unawaited(notifier.refresh());
      });
      return notifier;
    });

// --- Notes ---

class PlanningNotesNotifier extends _PlanningKeysetPager<PlanningNoteModel> {
  PlanningNotesNotifier(this._repository, this._relationshipId);
  final PlanningRepository _repository;
  final String _relationshipId;

  @override
  Future<List<PlanningNoteModel>> fetchFirstPage() =>
      _repository.listNotes(relationshipId: _relationshipId);

  @override
  Future<List<PlanningNoteModel>> fetchNextPage(
    List<PlanningNoteModel> current,
  ) {
    final last = current.last;
    return _repository.listNotes(
      relationshipId: _relationshipId,
      afterUpdatedAt: last.updatedAt,
      afterId: last.id,
    );
  }
}

final planningNotesProvider = StateNotifierProvider.autoDispose
    .family<PlanningNotesNotifier, AsyncValue<List<PlanningNoteModel>>, String>(
      (ref, relationshipId) {
        final repository = ref.watch(planningRepositoryProvider);
        final notifier = PlanningNotesNotifier(repository, relationshipId);
        ref.listen(planningChangeSignalProvider(relationshipId), (
          previous,
          next,
        ) {
          if (next.hasValue) unawaited(notifier.refresh());
        });
        return notifier;
      },
    );

// --- Calendar range ---

/// **Fix round baked in from the start (see Stories' own fix round 1,
/// finding 6):** truncated to Y/M/D in `==`/`hashCode` rather than
/// comparing `DateTime` at full precision. Two ranges naming the same
/// calendar days but built a moment apart (e.g. one computed at the
/// top of a build method, the other a microsecond later) MUST compare
/// equal, or every rebuild mints a fresh `.family` instance, each
/// opening its own Realtime subscription that the previous one never
/// gets a chance to dispose.
@immutable
class PlanningCalendarRangeKey {
  PlanningCalendarRangeKey({
    required this.relationshipId,
    required DateTime startDate,
    required DateTime endDate,
  }) : startDate = DateTime(startDate.year, startDate.month, startDate.day),
       endDate = DateTime(endDate.year, endDate.month, endDate.day);

  final String relationshipId;
  final DateTime startDate;
  final DateTime endDate;

  @override
  bool operator ==(Object other) =>
      other is PlanningCalendarRangeKey &&
      other.relationshipId == relationshipId &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(relationshipId, startDate, endDate);
}

final planningCalendarEntriesProvider = FutureProvider.autoDispose
    .family<List<PlanningCalendarEntryModel>, PlanningCalendarRangeKey>((
      ref,
      key,
    ) {
      final repository = ref.watch(planningRepositoryProvider);
      ref.listen(planningChangeSignalProvider(key.relationshipId), (
        previous,
        next,
      ) {
        if (next.hasValue) ref.invalidateSelf();
      });
      return repository.listCalendarEntries(
        relationshipId: key.relationshipId,
        startDate: key.startDate,
        endDate: key.endDate,
      );
    });

// --- Conversations-screen summary ---

final planningSummaryProvider = FutureProvider.autoDispose
    .family<PlanningSummaryModel?, String>((ref, relationshipId) {
      final repository = ref.watch(planningRepositoryProvider);
      ref.listen(planningChangeSignalProvider(relationshipId), (
        previous,
        next,
      ) {
        if (next.hasValue) ref.invalidateSelf();
      });
      return repository.getSummary(
        relationshipId: relationshipId,
        today: DateTime.now(),
      );
    });
```

- [ ] **Step 4: Reconcile the test file's fake-gateway seam with the real repository shape**

The test written in Step 1 assumes two narrow gateway interfaces
(`PlanningReadGateway`, `PlanningTaskGateway`, and a
`planningTaskGatewayProvider` override point) that do not match Task
1's actual `PlanningRepository` (which is a concrete class, not an
interface, and is not swapped via a `.family`-independent provider).
Before running the tests, adjust the test file — not the provider file
— to inject a fake at the level that actually exists: override
`planningRepositoryProvider` itself with a fake `PlanningRepository`
built over a fake `PlanningRpcGateway` (Task 1's own seam), the same
way `planning_repository_test.dart` already does. Rewrite the two
concurrency tests' setup to:

```dart
class _SlowRpcGateway implements PlanningRpcGateway {
  final List<Future<dynamic> Function()> responses;
  int _callIndex = 0;
  _SlowRpcGateway(this.responses);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    final next = responses[_callIndex.clamp(0, responses.length - 1)];
    _callIndex++;
    return next();
  }
}
```

and override `planningRepositoryProvider.overrideWithValue(
PlanningRepository(_SlowRpcGateway([...])))` in each test's
`ProviderContainer`. Keep the two concurrency assertions and the
`.family` key-equality test exactly as written — only the injection
seam changes. This reconciliation is deliberately left as a step here
rather than pre-solved, because getting the seam right against the
CONCRETE Task 1 types (not a re-imagined interface) is itself part of
verifying Task 1 and Task 2 fit together.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/planning/planning_providers_test.dart`
Expected: all pass, including the reconciled concurrency tests.

- [ ] **Step 6: Mutation-test the epoch guard and the key-equality fix**

By hand: (a) remove the `epoch != _epoch` check from `refresh()`'s two
post-await branches (keep `mounted`), confirm the stale-refresh test now
fails; restore. (b) Remove the day-truncation in
`PlanningCalendarRangeKey`'s constructor (compare raw `DateTime`s
instead), confirm the key-equality test now fails; restore. Record both
results in this task's final report.

- [ ] **Step 7: Run `flutter analyze`**

Run: `flutter analyze lib/features/planning test/features/planning`
Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/planning/presentation/providers \
        test/features/planning/planning_providers_test.dart
git commit -m "feat(planning): riverpod providers with epoch-guarded pagination and realtime refresh"
```

---

## Task 3: Planning home screen — Goals, Tasks, Events sections

**Files:**
- Create: `lib/features/planning/presentation/screens/planning_home_screen.dart`
- Create: `lib/features/planning/presentation/screens/create_planning_goal_screen.dart`
- Create: `lib/features/planning/presentation/screens/create_planning_task_screen.dart`
- Create: `lib/features/planning/presentation/screens/create_planning_event_screen.dart`
- Create: `lib/features/planning/presentation/widgets/planning_goal_row.dart`
- Create: `lib/features/planning/presentation/widgets/planning_task_row.dart`
- Test: `test/features/planning/planning_home_screen_test.dart`
- Test: `test/features/planning/planning_goal_row_test.dart`

**Interfaces:**
- Consumes: `planningGoalsProvider`, `planningGoalTasksProvider`, `planningTasksProvider`, `planningEventsProvider`, `PlanningEventsKey`, `planningRepositoryProvider`, and every model from Task 1/2.
- Produces: `PlanningHomeScreen({required String relationshipId})`, `PlanningGoalRow({required PlanningGoalModel goal, required VoidCallback onTap})`, `PlanningTaskRow({required PlanningTaskModel task, required ValueChanged<bool> onToggleComplete, VoidCallback? onTap})`. Task 6 (the conversations entry row) pushes `PlanningHomeScreen` by this exact constructor.

- [ ] **Step 1: Write the failing widget test for the Goal row (the sole-child-delete UX, and the checkbox-not-a-toggle requirement)**

Create `test/features/planning/planning_goal_row_test.dart`:

```dart
import 'package:attune/features/planning/data/models/planning_goal_model.dart';
import 'package:attune/features/planning/presentation/widgets/planning_goal_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PlanningGoalModel _goal({
  int childCount = 2,
  int completedChildCount = 1,
  DateTime? completedAt,
}) => PlanningGoalModel(
  id: 'g1', title: 'Save for the trip', note: null,
  completedAt: completedAt, updatedAt: DateTime(2026, 9, 14),
  childCount: childCount, completedChildCount: completedChildCount,
);

void main() {
  testWidgets('shows the title and a progress fraction, not a raw percentage string only', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(goal: _goal(), onTap: () {}),
      ),
    ));
    expect(find.text('Save for the trip'), findsOneWidget);
    expect(find.textContaining('1'), findsOneWidget); // 1 of 2 somewhere
    expect(find.textContaining('2'), findsOneWidget);
  });

  testWidgets('a completed goal shows a completed visual state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(
          goal: _goal(childCount: 2, completedChildCount: 2, completedAt: DateTime(2026, 9, 14)),
          onTap: () {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('tapping the row calls onTap exactly once', (tester) async {
    var tapCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningGoalRow(goal: _goal(), onTap: () => tapCount++),
      ),
    ));
    await tester.tap(find.byType(PlanningGoalRow));
    expect(tapCount, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/planning/planning_goal_row_test.dart`
Expected: fails to compile — `PlanningGoalRow` does not exist.

- [ ] **Step 3: Write `planning_goal_row.dart`**

```dart
// lib/features/planning/presentation/widgets/planning_goal_row.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';

import '../../data/models/planning_goal_model.dart';

/// One row on the Goals section of Planning home. Progress is shown as
/// "N of M" text plus a linear indicator, never a bare toggle — Goal
/// completion is derived from its children (spec §3.1), so this row
/// has no interactive completion control of its own; tapping it expands
/// to the child Task list, which is where completion actually happens.
class PlanningGoalRow extends StatelessWidget {
  const PlanningGoalRow({super.key, required this.goal, required this.onTap});

  final PlanningGoalModel goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InfoRowWidget(
      title: goal.title,
      subtitle: '${goal.completedChildCount} of ${goal.childCount} done',
      subTitleMaxLines: 1,
      showAvatar: false,
      onTap: onTap,
      showTrailingArrow: true,
      leadingWidget: goal.isComplete
          ? Icon(Icons.check_circle, color: colorScheme.primary)
          : SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: goal.progressFraction,
                strokeWidth: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/planning/planning_goal_row_test.dart`
Expected: all pass.

- [ ] **Step 5: Write `planning_task_row.dart`**

```dart
// lib/features/planning/presentation/widgets/planning_task_row.dart
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/planning_task_model.dart';

/// One row for a top-level Task, or a Goal's child Task inside its
/// expanded checklist. A real Checkbox, not InfoRowWidget's own toggle
/// (that renders a Switch, the wrong control for "mark this done").
class PlanningTaskRow extends StatelessWidget {
  const PlanningTaskRow({
    super.key,
    required this.task,
    required this.onToggleComplete,
    this.onTap,
  });

  final PlanningTaskModel task;
  final ValueChanged<bool> onToggleComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[];
    if (task.dueDate != null) {
      subtitleParts.add(DateFormat('MMM d').format(task.dueDate!));
    }

    return InfoRowWidget(
      title: task.title,
      subtitle: subtitleParts.join(' · '),
      subTitleMaxLines: 1,
      showAvatar: false,
      onTap: onTap,
      titleStyle: task.isComplete
          ? TextStyle(
              decoration: TextDecoration.lineThrough,
              color: colorScheme.onSurfaceVariant,
            )
          : null,
      leadingWidget: Checkbox(
        value: task.isComplete,
        onChanged: (value) => onToggleComplete(value ?? false),
      ),
    );
  }
}
```

- [ ] **Step 6: Write the failing home-screen test**

Create `test/features/planning/planning_home_screen_test.dart`:

```dart
import 'package:attune/features/planning/data/models/planning_event_model.dart';
import 'package:attune/features/planning/data/models/planning_goal_model.dart';
import 'package:attune/features/planning/data/models/planning_task_model.dart';
import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements PlanningRpcGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers;
  _FakeGateway(this.handlers);

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    final handler = handlers[function];
    if (handler == null) {
      throw StateError('No fake handler registered for $function');
    }
    return handler(params);
  }
}

Widget _wrap(Widget child, PlanningRepository repository) {
  return ProviderScope(
    overrides: [planningRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows the three sections and an empty state per section', (
    tester,
  ) async {
    final repository = PlanningRepository(_FakeGateway({
      'list_planning_goals': (_) async => <dynamic>[],
      'list_planning_tasks': (_) async => <dynamic>[],
      'list_planning_events': (_) async => <dynamic>[],
    }));

    await tester.pumpWidget(_wrap(
      const PlanningHomeScreen(relationshipId: 'r1'), repository,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
  });

  testWidgets('renders a Goal and a Task once loaded', (tester) async {
    final repository = PlanningRepository(_FakeGateway({
      'list_planning_goals': (_) async => [{
        'id': 'g1', 'title': 'Save for the trip', 'note': null,
        'completed_at': null, 'updated_at': '2026-09-14T09:00:00Z',
        'child_count': 2, 'completed_child_count': 0,
      }],
      'list_planning_tasks': (_) async => [{
        'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
        'item_kind': 'task', 'parent_goal_id': null, 'title': 'Water the plants',
        'note': null, 'assigned_to': null, 'due_date': null,
        'completed_at': null, 'celebrated_at': null,
        'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
        'deleted_at': null,
      }],
      'list_planning_events': (_) async => <dynamic>[],
    }));

    await tester.pumpWidget(_wrap(
      const PlanningHomeScreen(relationshipId: 'r1'), repository,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Save for the trip'), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets(
    'deleting the sole remaining child of a goal offers the two-choice '
    'prompt rather than a generic error (spec §6.2)',
    (tester) async {
      var deleteAttempted = false;
      final repository = PlanningRepository(_FakeGateway({
        'list_planning_goals': (_) async => [{
          'id': 'g1', 'title': 'Solo goal', 'note': null,
          'completed_at': null, 'updated_at': '2026-09-14T09:00:00Z',
          'child_count': 1, 'completed_child_count': 0,
        }],
        'list_planning_goal_tasks': (_) async => [{
          'id': 'c1', 'relationship_id': 'r1', 'created_by': 'u1',
          'item_kind': 'task', 'parent_goal_id': 'g1', 'title': 'Only task',
          'note': null, 'assigned_to': null, 'due_date': null,
          'completed_at': null, 'celebrated_at': null,
          'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
          'deleted_at': null,
        }],
        'list_planning_tasks': (_) async => <dynamic>[],
        'list_planning_events': (_) async => <dynamic>[],
        'delete_planning_item': (_) {
          deleteAttempted = true;
          throw const _RpcValidationException(
            'Delete the goal instead, or add another task first',
          );
        },
      }));

      await tester.pumpWidget(_wrap(
        const PlanningHomeScreen(relationshipId: 'r1'), repository,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solo goal'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Only task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleteAttempted, isTrue);
      expect(
        find.textContaining('Delete the goal instead'),
        findsOneWidget,
        reason: 'the validation message must reach the user, not a generic error',
      );
      expect(find.text('Delete this goal instead'), findsOneWidget);
    },
  );
}

class _RpcValidationException implements Exception {
  const _RpcValidationException(this.message);
  final String message;
}
```

- [ ] **Step 7: Run the tests to verify they fail**

Run: `flutter test test/features/planning/planning_home_screen_test.dart`
Expected: fails to compile — `PlanningHomeScreen` does not exist. Note
the third test's `_RpcValidationException` fake will not actually
produce a `PlanningValidationError` through `PlanningRepository._mapError`
as written in Task 1 (that method only recognizes `PostgrestException`);
adjust this test in Step 8 below to throw a real
`PostgrestException(message: '...', code: 'P0001')` instead once you
reach it, matching what Task 1's repository actually maps.

- [ ] **Step 8: Fix the test's exception fake, then write `planning_home_screen.dart`**

First, edit `test/features/planning/planning_home_screen_test.dart`:
replace `throw const _RpcValidationException(...)` with `throw
PostgrestException(message: 'Delete the goal instead, or add another task first', code: 'P0001')`
(add `import 'package:supabase_flutter/supabase_flutter.dart';` and delete
the now-unused `_RpcValidationException` class).

Then create `lib/features/planning/presentation/screens/planning_home_screen.dart`:

```dart
// lib/features/planning/presentation/screens/planning_home_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_divider.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/planning_error.dart';
import '../../data/models/planning_goal_model.dart';
import '../../data/models/planning_task_model.dart';
import '../providers/planning_providers.dart';
import '../widgets/planning_goal_row.dart';
import '../widgets/planning_task_row.dart';
import 'create_planning_goal_screen.dart';
import 'create_planning_task_screen.dart';
import 'create_planning_event_screen.dart';
import 'planning_notes_screen.dart';

/// Three sections, not tabs (spec §6.2): Goals, Tasks, Events, each
/// with its own "+". A separate Notes row opens the Notes list one
/// level down rather than competing for space here as a fourth
/// section — a scratchpad's content is the least glanceable of the
/// four (spec §5.2 of the design doc's earlier draft, carried into
/// this build).
class PlanningHomeScreen extends ConsumerWidget {
  const PlanningHomeScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planning'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(planningGoalsProvider(relationshipId).notifier).refresh(),
            ref.read(planningTasksProvider(relationshipId).notifier).refresh(),
            ref.read(planningEventsProvider(
              PlanningEventsKey(relationshipId: relationshipId, upcoming: true),
            ).notifier).refresh(),
          ]);
        },
        child: ListView(
          padding: EdgeInsets.all(Spacing.md),
          children: [
            _SectionHeader(
              title: 'Goals',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningGoalScreen(relationshipId: relationshipId),
              )),
            ),
            _GoalsSection(relationshipId: relationshipId),
            Gap(Spacing.md),
            const AppDivider(),
            Gap(Spacing.md),
            _SectionHeader(
              title: 'Tasks',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningTaskScreen(relationshipId: relationshipId),
              )),
            ),
            _TasksSection(relationshipId: relationshipId),
            Gap(Spacing.md),
            const AppDivider(),
            Gap(Spacing.md),
            _SectionHeader(
              title: 'Events',
              onAdd: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CreatePlanningEventScreen(relationshipId: relationshipId),
              )),
            ),
            _EventsSection(relationshipId: relationshipId),
            Gap(Spacing.md),
            const AppDivider(),
            Gap(Spacing.md),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Notes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlanningNotesScreen(relationshipId: relationshipId),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        AppIconButton(icon: Icons.add, onPressed: onAdd, size: 36, iconSize: 20),
      ],
    );
  }
}

class _GoalsSection extends ConsumerWidget {
  const _GoalsSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(planningGoalsProvider(relationshipId));
    return goalsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load goals.',
        onRetry: () => ref.read(planningGoalsProvider(relationshipId).notifier).refresh(),
      ),
      data: (goals) {
        if (goals.isEmpty) {
          return const _EmptySectionText('No goals yet.');
        }
        // Incomplete first (spec §6.2).
        final sorted = [...goals]
          ..sort((a, b) {
            if (a.isComplete != b.isComplete) {
              return a.isComplete ? 1 : -1;
            }
            return b.updatedAt.compareTo(a.updatedAt);
          });
        return Column(
          children: [
            for (final goal in sorted)
              _ExpandableGoal(relationshipId: relationshipId, goal: goal),
          ],
        );
      },
    );
  }
}

class _ExpandableGoal extends ConsumerStatefulWidget {
  const _ExpandableGoal({required this.relationshipId, required this.goal});
  final String relationshipId;
  final PlanningGoalModel goal;

  @override
  ConsumerState<_ExpandableGoal> createState() => _ExpandableGoalState();
}

class _ExpandableGoalState extends ConsumerState<_ExpandableGoal> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PlanningGoalRow(
          goal: widget.goal,
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(left: Spacing.lg),
            child: Consumer(
              builder: (context, ref, _) {
                final tasksAsync = ref.watch(planningGoalTasksProvider(widget.goal.id));
                return tasksAsync.when(
                  loading: () => const SizedBox(
                    height: 32,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (_, __) => const _SectionError(message: 'Could not load tasks.'),
                  data: (tasks) => Column(
                    children: [
                      for (final task in tasks)
                        PlanningTaskRow(
                          task: task,
                          onToggleComplete: (isComplete) => _toggleTask(task, isComplete),
                          onTap: () => _confirmDelete(task),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _toggleTask(PlanningTaskModel task, bool isComplete) async {
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.setTaskCompletion(taskId: task.id, isComplete: isComplete);
      ref.invalidate(planningGoalTasksProvider(widget.goal.id));
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _confirmDelete(PlanningTaskModel task) async {
    // Long-press to delete, matching this project's existing message
    // long-press-to-act convention rather than inventing a swipe
    // gesture for this one list.
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('Delete "${task.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.deleteItem(id: task.id);
      ref.invalidate(planningGoalTasksProvider(widget.goal.id));
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      // The sole-child-delete rejection surfaces here as a
      // PlanningValidationError. Rather than a generic error toast,
      // spec §6.2 requires the two-choice prompt: delete the goal
      // instead, or add another task first.
      if (error is PlanningValidationError &&
          error.message.contains('Delete the goal instead')) {
        await _offerDeleteGoalInstead(error.message);
        return;
      }
      _showError(error);
    }
  }

  Future<void> _offerDeleteGoalInstead(String message) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete_goal'),
            child: const Text('Delete this goal instead'),
          ),
        ],
      ),
    );
    if (choice != 'delete_goal' || !mounted) return;

    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.deleteItem(id: widget.goal.id);
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
    } on PlanningError catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(PlanningError error) {
    final message = switch (error) {
      PlanningValidationError(message: final m) => m,
      PlanningUnauthorizedError() => 'Planning is no longer available.',
      PlanningNotFoundError() => 'That item is no longer there.',
      PlanningNetworkError() => 'Could not reach the server. Try again.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TasksSection extends ConsumerWidget {
  const _TasksSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(planningTasksProvider(relationshipId));
    return tasksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load tasks.',
        onRetry: () => ref.read(planningTasksProvider(relationshipId).notifier).refresh(),
      ),
      data: (tasks) {
        if (tasks.isEmpty) return const _EmptySectionText('No tasks yet.');
        return Column(
          children: [
            for (final task in tasks)
              PlanningTaskRow(
                task: task,
                onToggleComplete: (isComplete) async {
                  final repository = ref.read(planningRepositoryProvider);
                  await repository.setTaskCompletion(
                    taskId: task.id, isComplete: isComplete,
                  );
                  ref.read(planningTasksProvider(relationshipId).notifier).refresh();
                },
              ),
          ],
        );
      },
    );
  }
}

class _EventsSection extends ConsumerWidget {
  const _EventsSection({required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = PlanningEventsKey(relationshipId: relationshipId, upcoming: true);
    final eventsAsync = ref.watch(planningEventsProvider(key));
    return eventsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _SectionError(
        message: 'Could not load events.',
        onRetry: () => ref.read(planningEventsProvider(key).notifier).refresh(),
      ),
      data: (events) {
        if (events.isEmpty) return const _EmptySectionText('No upcoming events.');
        return Column(
          children: [
            for (final event in events)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(event.title),
                dense: true,
              ),
          ],
        );
      },
    );
  }
}

class _EmptySectionText extends StatelessWidget {
  const _EmptySectionText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```

Add `import 'package:gap/gap.dart';` to this file's imports —
`Gap(Spacing.md)` is a real widget from the `gap` package (already a
project dependency, `pubspec.yaml`), the exact same constructor call
`conversations_screen.dart` already uses for its own section spacing.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `flutter test test/features/planning/planning_home_screen_test.dart test/features/planning/planning_goal_row_test.dart`
Expected: all pass.

- [ ] **Step 10: Write `create_planning_goal_screen.dart`**

```dart
// lib/features/planning/presentation/screens/create_planning_goal_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

/// Save is disabled until BOTH the goal title and the first task title
/// are non-blank (spec §6.2) — create_planning_goal (Plan A) requires
/// both in the same call; there is no code path that creates a
/// zero-child goal.
class CreatePlanningGoalScreen extends ConsumerStatefulWidget {
  const CreatePlanningGoalScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningGoalScreen> createState() => _CreatePlanningGoalScreenState();
}

class _CreatePlanningGoalScreenState extends ConsumerState<CreatePlanningGoalScreen> {
  final _goalTitleController = TextEditingController();
  final _firstTaskTitleController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _goalTitleController.dispose();
    _firstTaskTitleController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _goalTitleController.text.trim().isNotEmpty &&
      _firstTaskTitleController.text.trim().isNotEmpty &&
      !_isSaving;

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repository = ref.read(planningRepositoryProvider);
    const uuid = Uuid();
    try {
      await repository.createGoal(
        goalId: uuid.v4(),
        firstTaskId: uuid.v4(),
        relationshipId: widget.relationshipId,
        goalTitle: _goalTitleController.text.trim(),
        firstTaskTitle: _firstTaskTitleController.text.trim(),
      );
      ref.read(planningGoalsProvider(widget.relationshipId).notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the goal. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New goal')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _goalTitleController,
              decoration: const InputDecoration(labelText: 'Goal'),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _firstTaskTitleController,
              decoration: const InputDecoration(labelText: 'First task'),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`uuid: ^3.0.7` is already a project dependency (`pubspec.yaml`), so the
`Uuid().v4()` call above needs no new dependency.

- [ ] **Step 11: Write `create_planning_task_screen.dart`**

`showCupertinoDateTimeSheet` (`lib/core/widgets/cupertino_date_time_sheet.dart`)
is a top-level function, not a widget class — `showCupertinoDateTimeSheet(context: ..., mode: CupertinoDatePickerMode.date, initialDateTime: ..., onChanged: ...)`,
already exported via `export_screens.dart`.

```dart
// lib/features/planning/presentation/screens/create_planning_task_screen.dart
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

class CreatePlanningTaskScreen extends ConsumerStatefulWidget {
  const CreatePlanningTaskScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningTaskScreen> createState() => _CreatePlanningTaskScreenState();
}

class _CreatePlanningTaskScreenState extends ConsumerState<CreatePlanningTaskScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _dueDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSave => _titleController.text.trim().isNotEmpty && !_isSaving;

  Future<void> _pickDueDate() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _dueDate ?? DateTime.now(),
      onChanged: (value) => setState(() => _dueDate = value),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.createTask(
        id: const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        dueDate: _dueDate,
      );
      ref.read(planningTasksProvider(widget.relationshipId).notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the task. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New task')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Task'),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SizedBox(height: Spacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _dueDate == null
                    ? 'No due date'
                    : DateFormat.yMMMd().format(_dueDate!),
              ),
              trailing: TextButton(
                onPressed: _pickDueDate,
                child: Text(_dueDate == null ? 'Set date' : 'Change'),
              ),
            ),
            SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 12: Write `create_planning_event_screen.dart`**

```dart
// lib/features/planning/presentation/screens/create_planning_event_screen.dart
//
// Does not yet offer linking existing Tasks to the Event being
// created — spec §6.2's Event edit flow includes a picker for existing
// live top-level Tasks, which needs list_planning_tasks already loaded
// and a multi-select UI; deferred to a dedicated follow-up on top of
// this plan rather than folded into first creation, since a brand-new
// Event has no Tasks worth linking yet in the common case (create the
// event, add/link tasks afterward from Planning home).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/cupertino_date_time_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../providers/planning_providers.dart';

class CreatePlanningEventScreen extends ConsumerStatefulWidget {
  const CreatePlanningEventScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  ConsumerState<CreatePlanningEventScreen> createState() => _CreatePlanningEventScreenState();
}

class _CreatePlanningEventScreenState extends ConsumerState<CreatePlanningEventScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _eventDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // The date is REQUIRED for an event (upsert_planning_event rejects a
  // null p_event_date), unlike a Task's optional due date.
  bool get _canSave =>
      _titleController.text.trim().isNotEmpty && _eventDate != null && !_isSaving;

  Future<void> _pickEventDate() {
    return showCupertinoDateTimeSheet(
      context: context,
      mode: CupertinoDatePickerMode.date,
      initialDateTime: _eventDate ?? DateTime.now(),
      onChanged: (value) => setState(() => _eventDate = value),
    );
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.upsertEvent(
        id: const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        eventDate: _eventDate!,
      );
      ref.read(planningEventsProvider(
        PlanningEventsKey(relationshipId: widget.relationshipId, upcoming: true),
      ).notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the event. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New event')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Event'),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            SizedBox(height: Spacing.md),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            SizedBox(height: Spacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _eventDate == null
                    ? 'Pick a date'
                    : DateFormat.yMMMd().format(_eventDate!),
              ),
              trailing: TextButton(
                onPressed: _pickEventDate,
                child: Text(_eventDate == null ? 'Set date' : 'Change'),
              ),
            ),
            SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: _canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 13: Run `flutter analyze` on everything written so far**

Run: `flutter analyze lib/features/planning test/features/planning`
Expected: 0 errors.

- [ ] **Step 14: Commit**

```bash
git add lib/features/planning/presentation/screens lib/features/planning/presentation/widgets \
        test/features/planning/planning_home_screen_test.dart \
        test/features/planning/planning_goal_row_test.dart
git commit -m "feat(planning): home screen with goals/tasks/events sections and create flows"
```

---

## Task 4: Notes list and editor

**Files:**
- Create: `lib/features/planning/presentation/screens/planning_notes_screen.dart`
- Create: `lib/features/planning/presentation/screens/planning_note_editor_screen.dart`
- Test: `test/features/planning/planning_notes_screen_test.dart`

**Interfaces:**
- Consumes: `planningNotesProvider`, `planningRepositoryProvider`, `PlanningNoteModel`.
- Produces: `PlanningNotesScreen({required String relationshipId})`, `PlanningNoteEditorScreen({required String relationshipId, PlanningNoteModel? existingNote})`. Task 3 already references `PlanningNotesScreen` by this constructor.

- [ ] **Step 1: Write the failing test**

Create `test/features/planning/planning_notes_screen_test.dart`:

```dart
import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:attune/features/planning/presentation/screens/planning_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements PlanningRpcGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> handlers;
  _FakeGateway(this.handlers);
  Map<String, dynamic>? lastParams;
  String? lastFunction;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    lastFunction = function;
    lastParams = params;
    final handler = handlers[function];
    if (handler == null) throw StateError('No fake handler for $function');
    return handler(params);
  }
}

Widget _wrap(Widget child, PlanningRepository repository) => ProviderScope(
  overrides: [planningRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('shows a note with its title and first body line', (tester) async {
    final gateway = _FakeGateway({
      'list_planning_notes': (_) async => [{
        'id': 'n1', 'relationship_id': 'r1', 'created_by': 'u1',
        'title': 'Restaurants to try', 'body': 'Thai place on 5th\nramen spot',
        'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
        'deleted_at': null,
      }],
    });
    await tester.pumpWidget(_wrap(
      const PlanningNotesScreen(relationshipId: 'r1'),
      PlanningRepository(gateway),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Restaurants to try'), findsOneWidget);
    expect(find.textContaining('Thai place on 5th'), findsOneWidget);
  });

  testWidgets('an unsaved draft survives a failed save, and offers retry', (
    tester,
  ) async {
    var attempts = 0;
    final gateway = _FakeGateway({
      'list_planning_notes': (_) async => <dynamic>[],
      'upsert_planning_note': (params) {
        attempts++;
        throw StateError('network down');
      },
    });
    await tester.pumpWidget(_wrap(
      const PlanningNotesScreen(relationshipId: 'r1'),
      PlanningRepository(gateway),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Packing list');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(attempts, 1);
    // The draft text must still be in the field, not cleared by the
    // failed save — the user should be able to just tap Save again.
    expect(find.text('Packing list'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/planning/planning_notes_screen_test.dart`
Expected: fails to compile — `PlanningNotesScreen` does not exist.

- [ ] **Step 3: Write `planning_notes_screen.dart`**

```dart
// lib/features/planning/presentation/screens/planning_notes_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/planning_note_model.dart';
import '../providers/planning_providers.dart';
import 'planning_note_editor_screen.dart';

/// Newest-`updated_at`-first, title + first body line as the preview —
/// the shared-scratchpad shape (spec §6.3). Tapping opens ONE edit
/// surface; there is no separate read-only mode, matching the "either
/// partner can edit any note at any time" decision (spec §2).
class PlanningNotesScreen extends ConsumerWidget {
  const PlanningNotesScreen({super.key, required this.relationshipId});
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(planningNotesProvider(relationshipId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlanningNoteEditorScreen(relationshipId: relationshipId),
            )).then((_) {
              ref.read(planningNotesProvider(relationshipId).notifier).refresh();
            }),
          ),
        ],
      ),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: TextButton(
            onPressed: () => ref.read(planningNotesProvider(relationshipId).notifier).refresh(),
            child: const Text('Could not load notes. Retry.'),
          ),
        ),
        data: (notes) {
          if (notes.isEmpty) {
            return const Center(child: Text('No notes yet.'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) => _NoteListTile(
              note: notes[index],
              relationshipId: relationshipId,
            ),
          );
        },
      ),
    );
  }
}

class _NoteListTile extends ConsumerWidget {
  const _NoteListTile({required this.note, required this.relationshipId});
  final PlanningNoteModel note;
  final String relationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstLine = note.body.split('\n').first;
    return ListTile(
      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(firstLine, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlanningNoteEditorScreen(
          relationshipId: relationshipId,
          existingNote: note,
        ),
      )).then((_) {
        ref.read(planningNotesProvider(relationshipId).notifier).refresh();
      }),
    );
  }
}
```

- [ ] **Step 4: Write `planning_note_editor_screen.dart`**

```dart
// lib/features/planning/presentation/screens/planning_note_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/planning_note_model.dart';
import '../providers/planning_providers.dart';

/// Save is explicit (spec §6.3) — no autosave-on-every-keystroke. On a
/// failed save, the draft text stays exactly as typed and Save remains
/// available to retry; nothing here clears the TextField on failure.
class PlanningNoteEditorScreen extends ConsumerStatefulWidget {
  const PlanningNoteEditorScreen({
    super.key,
    required this.relationshipId,
    this.existingNote,
  });
  final String relationshipId;
  final PlanningNoteModel? existingNote;

  @override
  ConsumerState<PlanningNoteEditorScreen> createState() => _PlanningNoteEditorScreenState();
}

class _PlanningNoteEditorScreenState extends ConsumerState<PlanningNoteEditorScreen> {
  late final _titleController = TextEditingController(text: widget.existingNote?.title ?? '');
  late final _bodyController = TextEditingController(text: widget.existingNote?.body ?? '');
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final repository = ref.read(planningRepositoryProvider);
    try {
      await repository.upsertNote(
        id: widget.existingNote?.id ?? const Uuid().v4(),
        relationshipId: widget.relationshipId,
        title: _titleController.text.trim(),
        body: _bodyController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      // Draft text is untouched — the controllers still hold exactly
      // what the user typed, ready to retry.
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Could not save. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingNote == null ? 'New note' : 'Edit note'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: widget.existingNote == null,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(labelText: 'Note'),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/planning/planning_notes_screen_test.dart`
Expected: all pass.

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/features/planning test/features/planning`
Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/planning/presentation/screens/planning_notes_screen.dart \
        lib/features/planning/presentation/screens/planning_note_editor_screen.dart \
        test/features/planning/planning_notes_screen_test.dart
git commit -m "feat(planning): notes list and editor, explicit save with draft retention on failure"
```

---

## Task 5: Conversations-screen entry row and route registration

**Files:**
- Modify: `lib/features/chat/presentation/screens/conversations_screen.dart`
- Modify: `lib/app/routing/app_router.dart`
- Test: `test/features/chat/planning_entry_row_wiring_test.dart`

**Interfaces:**
- Consumes: `planningSummaryProvider`, `PlanningSummaryModel`, `PlanningHomeScreen` (Task 3).
- Produces: a `planning` named route taking a relationship id via `state.extra`; a `_PlanningSummaryRow` widget wired into the existing card on `conversations_screen.dart`, matching `_LatestReflectionRow`/`_NextCalendarEventRow`'s exact position and shape.

- [ ] **Step 1: Register the route**

In `lib/app/routing/app_router.dart`, add to `RouteNames`:

```dart
  static const String planning = '/planning';
```

(placed next to `static const String timeline = '/timeline';`). Add the
import near the other feature-screen imports:

```dart
import 'package:attune/features/planning/presentation/screens/planning_home_screen.dart';
```

Add a `GoRoute` next to `timeline`'s own registration:

```dart
      GoRoute(
        path: RouteNames.planning,
        name: 'planning',
        builder: (context, state) {
          final relationshipId = state.extra as String?;
          if (relationshipId == null) {
            return const Scaffold(
              body: Center(child: Text('Planning unavailable.')),
            );
          }
          return PlanningHomeScreen(relationshipId: relationshipId);
        },
      ),
```

- [ ] **Step 2: Add the entry row to `conversations_screen.dart`**

Add the import:

```dart
import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    as planning_providers;
```

Prefixed, because `conversations_screen.dart` already imports
`reminders_providers.dart` UNPREFIXED (`import
'package:attune/features/reminders/presentation/providers/reminders_providers.dart';`),
and that file defines its own top-level `currentRelationshipIdProvider`
— importing Planning's own same-named provider unprefixed here would
be an ambiguous-import compile error, not merely a style mismatch. The
`as planning_providers` prefix is Planning's own accommodation for a
name this file's existing import already owns, not a pattern copied
from an existing prefixed import (there is no such precedent in this
file — confirm with `grep -n "as reminders" conversations_screen.dart`
returning nothing before proceeding, so this reasoning is not silently
stale by the time this task runs).

In the `Column` that currently reads:
```dart
Gap(Spacing.sm.h),
const _LatestReflectionRow(),
Gap(Spacing.sm.h),
AppDivider(),
Gap(Spacing.sm.h),
const _NextCalendarEventRow(),
```

add a new row between the reflection row and the calendar-event row's
divider (i.e. right after `_LatestReflectionRow`, before the
`AppDivider()`/`_NextCalendarEventRow` pair — Planning sits between the
personal-reflection row and the calendar-event row, both existing rows'
own neighbors unchanged):

```dart
Gap(Spacing.sm.h),
const _LatestReflectionRow(),
Gap(Spacing.sm.h),
const _PlanningSummaryRow(),
Gap(Spacing.sm.h),
AppDivider(),
Gap(Spacing.sm.h),
const _NextCalendarEventRow(),
```

Add the new widget class, placed after `_LatestReflectionRow`'s own
class definition (matching this file's existing ordering of one class
per row, in the order they appear):

```dart
/// Summary row for Planning: the single most relevant open item across
/// Goals/Tasks/Events/Notes (spec §6.1's priority order, computed
/// server-side by get_planning_summary so this widget does no ranking
/// of its own). Same "one line, tap through to the full list" shape as
/// _LatestReflectionRow/_NextCalendarEventRow.
class _PlanningSummaryRow extends ConsumerWidget {
  const _PlanningSummaryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final relationshipIdAsync = ref.watch(planning_providers.currentRelationshipIdProvider);
    final relationshipId = relationshipIdAsync.valueOrNull;

    final summaryAsync = relationshipId == null
        ? const AsyncValue<PlanningSummaryModel?>.data(null)
        : ref.watch(planning_providers.planningSummaryProvider(relationshipId));

    // Retains its last successful value during a refresh rather than
    // flashing to a loading state — matching this card's other rows'
    // no-jump behavior (spec §6.4).
    final summary = summaryAsync.valueOrNull;

    final title = switch (summary?.kind) {
      null => 'Start planning together',
      'overdue_task' => '${summary!.title} was due',
      'upcoming_task' => summary!.title,
      'upcoming_event' => summary!.title,
      _ => summary!.title,
    };

    return InfoRowWidget(
      title: title,
      subtitle: 'Planning',
      icon: Icons.checklist_outlined,
      iconColor: colorScheme.onSurfaceVariant.withOpacity(.4),
      subTitleMaxLines: 1,
      titleMaxLines: 1,
      showDivider: false,
      showAvatar: false,
      disableTrailing: false,
      showTrailingArrow: true,
      onTap: relationshipId == null
          ? null
          : () => context.pushNamed('planning', extra: relationshipId),
    );
  }
}
```

Add the model import too:
```dart
import 'package:attune/features/planning/data/models/planning_summary_model.dart';
```

- [ ] **Step 3: Write the wiring test**

Create `test/features/chat/planning_entry_row_wiring_test.dart`, following
`test/features/stories/story_calendar_wiring_test.dart`'s exact precedent
(a source check, because `ConversationsScreen` needs Supabase and a live
relationship to build, the same reason nothing in `test/` mounts it
directly):

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Planning's entry row reaches the actual conversations screen, and
/// the route it opens actually resolves to PlanningHomeScreen.
///
/// Following story_calendar_wiring_test.dart's precedent for the same
/// shape of gap: ConversationsScreen needs Supabase, a relationship,
/// and several live providers to build, so nothing in test/ mounts it.
/// A widget test of `_PlanningSummaryRow` in isolation (if one existed)
/// would prove the row behaves correctly and say nothing about whether
/// ConversationsScreen ever renders it.
void main() {
  final conversationsScreen = File(
    'lib/features/chat/presentation/screens/conversations_screen.dart',
  ).readAsStringSync();
  final appRouter = File('lib/app/routing/app_router.dart').readAsStringSync();

  test('the conversations screen renders the planning summary row', () {
    expect(
      conversationsScreen.contains('_PlanningSummaryRow()'),
      isTrue,
      reason: 'without this the entry point into Planning is unreachable from chat',
    );
  });

  test('the planning route is registered and builds PlanningHomeScreen', () {
    expect(appRouter.contains("name: 'planning'"), isTrue);
    expect(appRouter.contains('PlanningHomeScreen(relationshipId: relationshipId)'), isTrue);
  });

  test('the row passes the relationship id through, not a null/empty extra', () {
    expect(
      RegExp(
        r"pushNamed\('planning', extra: relationshipId\)",
      ).hasMatch(conversationsScreen),
      isTrue,
      reason:
          'the row must be scoped to the current relationship; passing '
          'the wrong id would read as an empty Planning home rather than an error',
    );
  });
}
```

- [ ] **Step 4: Run the test to verify it fails, then re-run after Steps 1–2**

Run: `flutter test test/features/chat/planning_entry_row_wiring_test.dart`
Expected before Steps 1–2: fails (the strings are not in either file
yet). Expected after Steps 1–2: all pass.

- [ ] **Step 5: Mutation-test the wiring guard**

By hand: temporarily remove the `_PlanningSummaryRow()` line from
`conversations_screen.dart`'s widget tree (leave the class definition in
place — this reproduces exactly the "row exists but nothing renders it"
shape the Stories calendar bug had), confirm the first wiring test now
fails, restore.

- [ ] **Step 6: Run the full chat test suite to check for regressions**

Run: `flutter test test/features/chat`
Expected: passes at the same count this project's established baseline
uses for a clean chat suite run — confirm by running it once BEFORE
Step 2's edit and once after, and compare the two counts rather than
assuming a specific number (this project's baseline count has changed
across recent work; re-establish it fresh in this worktree rather than
trusting a number from an earlier session).

- [ ] **Step 7: Run `flutter analyze`**

Run: `flutter analyze lib test`
Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/chat/presentation/screens/conversations_screen.dart \
        lib/app/routing/app_router.dart \
        test/features/chat/planning_entry_row_wiring_test.dart
git commit -m "feat(planning): entry row on the conversations screen, and route registration"
```

---

## Task 6: Timeline integration

**Files:**
- Modify: `lib/features/timeline/presentation/widgets/calendar_strip.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Create: `lib/features/timeline/presentation/widgets/planning_day_section.dart`
- Test: `test/features/timeline/planning_calendar_integration_test.dart`

**Interfaces:**
- Consumes: `planningCalendarEntriesProvider`, `PlanningCalendarRangeKey`, `PlanningCalendarEntryModel`, `PlanningCalendarEntryKind` (Task 2/1).
- Produces: `CalendarStrip`'s new optional `planningEntriesByDate` parameter; `PlanningDaySection({required List<PlanningCalendarEntryModel> entries})`, rendered inside `TimelineScreen`'s selected-day area alongside (never merged into) the existing moments/reminders rendering.

- [ ] **Step 1: Add the dot signal to `CalendarStrip`**

In `lib/features/timeline/presentation/widgets/calendar_strip.dart`, add
a new constructor parameter matching `remindersByDate`'s existing shape
exactly:

```dart
  final Map<DateTime, List<dynamic>> planningEntriesByDate;
```

added to the constructor with `this.planningEntriesByDate = const {},`
right after the existing `this.remindersByDate = const {},` line. In the
day-cell builder, where the file currently reads:

```dart
final remindersOnDate = remindersByDate[date] ?? [];
final hasEvents = eventsOnDate.isNotEmpty || remindersOnDate.isNotEmpty;
```

change to:

```dart
final remindersOnDate = remindersByDate[date] ?? [];
final planningOnDate = planningEntriesByDate[date] ?? [];
final hasEvents = eventsOnDate.isNotEmpty || remindersOnDate.isNotEmpty || planningOnDate.isNotEmpty;
```

and where the file computes `hasReminderDot`:

```dart
final hasReminderDot = remindersOnDate.isNotEmpty;
```

add a sibling:

```dart
final hasReminderDot = remindersOnDate.isNotEmpty;
final hasPlanningDot = planningOnDate.isNotEmpty;
```

Then find where `hasReminderDot` is actually consumed to decide the
hollow-ring rendering (search this file for `hasReminderDot` beyond
its declaration) and extend that same condition to also check
`hasPlanningDot` — a day with a Planning-only entry (no timeline event,
no reminder) must still show a dot, or it silently disappears from the
strip. Do not introduce a THIRD visually distinct dot style for
Planning specifically; spec §7 does not ask for one, and this file
already treats "reminder-shaped" (hollow ring, upcoming) as the right
visual language for "something is coming up on this date that isn't a
logged moment" — a Task due date and an Event date are exactly that
shape, not a "moment that happened."

- [ ] **Step 2: Write `planning_day_section.dart`**

```dart
// lib/features/timeline/presentation/widgets/planning_day_section.dart
import 'package:flutter/material.dart';

import '../../../planning/data/models/planning_calendar_entry_model.dart';

/// Planning's own rendering for the Timeline screen's selected-day area
/// — never coerced into TimelineEventModel (spec §7's explicit rule:
/// that would need fake loggedBy/eventType/moodScore/occurredAt
/// values). Sits BESIDE the existing moments/reminders rendering for
/// that day, not merged into either.
class PlanningDaySection extends StatelessWidget {
  const PlanningDaySection({super.key, required this.entries});
  final List<PlanningCalendarEntryModel> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          ListTile(
            dense: true,
            leading: Icon(
              entry.kind == PlanningCalendarEntryKind.event
                  ? Icons.event_outlined
                  : Icons.check_box_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              entry.title,
              style: entry.isComplete
                  ? TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 3: Wire the provider and the section into `timeline_screen.dart`**

Add the import (prefixed the same way this file already prefixes
`reminders_providers` — confirmed present at this file's own top,
`import '...reminders_providers.dart' as reminders_providers;` — so
Planning's own same-named `currentRelationshipIdProvider` needs the
identical treatment):

```dart
import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    as planning_providers;
import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/timeline/presentation/widgets/planning_day_section.dart';
```

Where `build` currently reads (per this file's own §60-76 shape already
read earlier in this plan):

```dart
final eventsAsync = ref.watch(timelineEventsProvider(_focusedMonth));
final currentUserId = ref.watch(currentUserIdProvider);
final relationshipIdAsync = ref.watch(currentRelationshipIdProvider);
final remindersAsync = ref.watch(reminders_providers.remindersListProvider);
```

add, immediately after:

```dart
final planningEntriesAsync = relationshipIdAsync.valueOrNull == null
    ? const AsyncValue<List<PlanningCalendarEntryModel>>.data([])
    : ref.watch(planning_providers.planningCalendarEntriesProvider(
        PlanningCalendarRangeKey(
          relationshipId: relationshipIdAsync.valueOrNull!,
          startDate: DateTime(_focusedMonth.year, _focusedMonth.month, 1),
          // The 42-day cap (Plan A) bounds this to the visible grid,
          // never a wider "load everything" range — a month plus its
          // leading/trailing partial weeks is at most 42 days, matching
          // exactly what CalendarStrip itself renders.
          endDate: DateTime(_focusedMonth.year, _focusedMonth.month + 1, 12),
        ),
      ));
```

Build a `Map<DateTime, List<PlanningCalendarEntryModel>>` grouped by
day the same way this file already groups reminders (see this file's
own `_remindersByDate` helper for the exact grouping shape to copy),
and pass it to `CalendarStrip` as `planningEntriesByDate: ...`. In the
selected-day rendering area, find where reminders for the selected day
are rendered (via `UpcomingRemindersSection` or equivalent) and add,
as a sibling widget beside it, not inside it:

```dart
PlanningDaySection(
  entries: planningEntriesAsync.valueOrNull
      ?.where((e) => _isSameDay(e.date, _selectedDate))
      .toList() ?? [],
),
```

using this file's own existing `_isSameDay` helper (already used for
the moments grouping above).

- [ ] **Step 4: Write the integration test**

Create `test/features/timeline/planning_calendar_integration_test.dart`:

```dart
import 'package:attune/features/planning/data/models/planning_calendar_entry_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_strip.dart';
import 'package:attune/features/timeline/presentation/widgets/planning_day_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'CalendarStrip shows a dot for a date with ONLY a planning entry '
    '(no timeline event, no reminder)',
    (tester) async {
      final month = DateTime(2026, 6, 1);
      final planningDate = DateTime(2026, 6, 15);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CalendarStrip(
            focusedMonth: month,
            eventsByDate: const {},
            planningEntriesByDate: {
              planningDate: [
                PlanningCalendarEntryModel(
                  kind: PlanningCalendarEntryKind.task,
                  id: 't1', date: planningDate, title: 'Water the plants',
                  isComplete: false,
                ),
              ],
            },
            onDaySelected: (_) {},
            onMonthChanged: (_) {},
          ),
        ),
      ));
      // The day cell for the 15th must render SOME dot indicator — this
      // asserts the day is not visually indistinguishable from an empty
      // one, matching the reminder-dot's existing hollow-ring semantics
      // rather than asserting a brand-new widget type this task
      // deliberately does not introduce.
      expect(find.text('15'), findsOneWidget);
      // A day cell for an entirely empty date (the 16th) must NOT show
      // the same indicator — proves the dot is data-driven, not always-on.
    },
  );

  testWidgets('PlanningDaySection renders a completed task with strikethrough styling', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PlanningDaySection(entries: [
          PlanningCalendarEntryModel(
            kind: PlanningCalendarEntryKind.task,
            id: 't1', date: DateTime(2026, 6, 15),
            title: 'Water the plants', isComplete: true,
          ),
        ]),
      ),
    ));
    final text = tester.widget<Text>(find.text('Water the plants'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('PlanningDaySection renders nothing for an empty entry list', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PlanningDaySection(entries: [])),
    ));
    expect(find.byType(ListTile), findsNothing);
  });
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/features/timeline/planning_calendar_integration_test.dart`
Expected: all pass. If Step 1's dot-rendering change did not actually
make the "planning-only date" case visually distinct in a way this
test can assert cheaply, strengthen the test to inspect the day cell's
own decoration/border rather than only checking the day number renders
— the day number rendering is not, by itself, proof the dot appeared.

- [ ] **Step 6: Run the full timeline and stories test suites to check for regressions**

Run: `flutter test test/features/timeline test/features/stories`
Expected: no new failures versus this worktree's own freshly-established
baseline for both directories (establish it by running the same command
BEFORE Steps 1–3's edits, and compare).

- [ ] **Step 7: Run `flutter analyze`**

Run: `flutter analyze lib test`
Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
git add lib/features/timeline/presentation/widgets/calendar_strip.dart \
        lib/features/timeline/presentation/screens/timeline_screen.dart \
        lib/features/timeline/presentation/widgets/planning_day_section.dart \
        test/features/timeline/planning_calendar_integration_test.dart
git commit -m "feat(planning): timeline integration — calendar dots and the selected-day section"
```

---

## Task 7: Final client review pass

**Files:**
- No new files. A review-and-fix pass over Tasks 1–6's combined output, mirroring Plan A's own Task 5.

- [ ] **Step 1: Run the complete Planning-related Flutter test surface together**

Run: `flutter test test/features/planning test/features/chat test/features/timeline`
Expected: all pass, with the chat and timeline counts matching this
worktree's own freshly-established baselines (not a number carried over
from an earlier session or from Plan A's own report).

- [ ] **Step 2: Run the full Flutter test suite once, not per-directory**

Run: `flutter test`
Expected: no failures beyond whatever this worktree's pre-existing,
already-known failures are (re-establish that baseline count in THIS
worktree before Task 1 of this plan began, per Plan A's own Global
Constraints note on per-file runs not being sufficient evidence —
confirm this task's run matches that pre-established count exactly,
not merely "looks close").

- [ ] **Step 3: Run `flutter analyze` on the whole repo**

Run: `flutter analyze lib test`
Expected: 0 errors.

- [ ] **Step 4: Verify no Planning provider leaks a Realtime subscription**

Manually trace every `.family` provider defined in
`planning_providers.dart` and confirm each one that opens a resource
(a `planningChangeSignalProvider` subscription via `ref.listen`) is
declared `.autoDispose` — grep for `.family<` in that file and confirm
`StateNotifierProvider.autoDispose.family` / `FutureProvider.autoDispose.family`
/ `StreamProvider.autoDispose.family` appear on every one; a bare
`.family` without `.autoDispose` on any of them is a leak this task
must fix before considering itself done.

- [ ] **Step 5: Verify the two concurrency fixes from Task 2 are actually present, not silently reverted**

Run:
```bash
grep -n "epoch != _epoch" lib/features/planning/presentation/providers/planning_providers.dart
grep -n "DateTime(startDate.year, startDate.month, startDate.day)" lib/features/planning/presentation/providers/planning_providers.dart
```
Expected: both return matches. Either returning empty means a fix from
Task 2 was lost during a later edit — restore it and re-run Task 2's own
mutation tests before proceeding.

- [ ] **Step 6: Write the completion note**

No commit needed beyond what Tasks 1–6 already committed. If Steps 1–5
surfaced any fix, commit it now with a message describing exactly what
was wrong and which step caught it, then re-run Steps 1–5 in full before
considering this task done.
