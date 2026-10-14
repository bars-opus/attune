# Together Phase 0 — Make what exists solid: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the half-wired Timeline so it is trustworthy before the Together hub is built on it:
- moments appear without a manual refresh, and partners see each other's changes live;
- partners get a push for new moments;
- reminders keep their calendar date and can be edited or deleted;
- the calendar shows every reminder in the month;
- deleted moments stop counting toward the verdict.

**Architecture:** The work stays inside the existing Timeline, Reminders and verdict code, with no new product surface.
- **Server:** a DB trigger feeds partner pushes through the existing `scheduled_notifications` pipeline. A `together_change_signals` table, bumped by triggers, drives realtime refetches, copying Planning's change-signal pattern. Phase 1 will reuse that signal table.
- **Client:** fixes in the Timeline and Reminders presentation and data layers, each covered by a widget or unit test.

**Tech Stack:** Flutter 3.29, Riverpod 2, Supabase (Postgres, RLS, Realtime, edge functions in Deno), flutter_test, SQL contract tests (`supabase/tests/*.sql`, run with `scripts/run_sql_contracts.sh`).

**Spec:** `docs/superpowers/specs/2026-10-14-together-hub-design.md` §8.1 (and hard rules §3).

## Global Constraints

- Work directly on `main`. Do not commit unless the owner asks. The owner edits files by hand, so re-read each file right before editing it.
- Conflict moments never notify the partner (spec §3.5; PULSE.md §10).
- Migration filenames use the prefix `20261014` followed by six digits, starting at `20261014100000` and increasing by 100 per file.
- SQL contract tests need a local Supabase (`supabase start` needs Docker). If Docker is unavailable, write the test, record in the ledger "SQL contract written, not run (Docker down)", and continue. Never claim it passed.
- `flutter test` is the full suite; the known pre-existing failure is `test/features/planning/planning_home_screen_test.dart: shows visible categories…`, the Calendar tab height of 41.4.
- Format only the Dart files you touch (`dart format <file>`). Never format `lib/i10n/generated/*`.
- Copy in the UI must use sentence case and plain words, matching nearby strings.

## Rulings (deviations from spec §8.1, decided while planning)

- **R1:** The spec's `reminders.remind_on date` column is replaced by sending and reading `remind_at` as a plain date. The model now normalises to the date the user picked, and the repository sends `YYYY-MM-DD`. Supabase sessions run in UTC, so the server's `remind_at::date` already gives the right day. This needs no schema change or backfill. Cost if wrong: one later migration.
- **R2:** "`_scrollToDate` actually scrolls" is dropped. Tapping a date already opens the day sheet over the list, so scrolling the list underneath would be invisible. The method is renamed `_selectDate` so its name says what it does. Cost if wrong: none.
- **R3:** Passing the log-moment result back through `LogMomentTypeScreen` is dropped. Task 1's key fix and Task 2's live refresh make it redundant. Cost if wrong: one line.
- **R4:** Soft delete moves to a SECURITY DEFINER RPC, `soft_delete_timeline_event`. The current UPDATE only works because PostgREST does not ask for the updated row back; it would fail under the read policy if `.select()` were added. Cost if wrong: none.

## Review Focus

1. **A month key with a time attached** (`DateTime.now()`) must hit the same cache entry as `DateTime(y, m, 1)`. Pinned in Task 1.
2. **A reminder saved in a time zone ahead of or behind UTC** must show on the day the user picked, both after reload and from the offline cache. Pinned in Task 4: a UTC-offset string and a date-only string.
3. **A Feb 29 yearly reminder** viewed in a non-leap February must show on Feb 28, not vanish. Pinned in Task 6.
4. **A partner-push trigger on a relationship that is not active, or has no partner,** must insert nothing and must not error, so the moment still saves. Pinned in Task 3's contract test.
5. **A reminder of a type the picker doesn't offer** (`checkin`, `ai_generated`) must open in the editor without an assertion error. Pinned in Task 5.

---

## File structure

| File | Action | Responsibility |
|---|---|---|
| `lib/features/timeline/presentation/providers/timeline_providers.dart` | Modify | `timelineMonthKey`, signal provider, auto-refresh provider, remove the dead realtime provider |
| `lib/features/timeline/data/repositories/timeline_repository.dart` | Modify | Drop the client-side partner notify; soft delete through the RPC; drop `subscribeToEvents` |
| `lib/features/timeline/presentation/screens/timeline_screen.dart` | Modify | Normalised month key, auto-refresh watch, reminder taps, month dots, partner name, `_selectDate` |
| `lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart` | Modify | `remindersByDateInMonth` |
| `lib/features/timeline/presentation/widgets/moments_list.dart`, `moment_card.dart` | Modify | `partnerName` |
| `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` | Modify | Empty-state gating; reminder rows open the editor |
| `lib/features/reminders/data/models/reminder_model.dart` | Modify | Normalise `remindAt` to the picked date; date-only JSON |
| `lib/features/reminders/data/repositories/reminders_repository.dart` | Modify | Date-only writes; `updateReminder` accepts a type and can clear the note |
| `lib/features/reminders/presentation/providers/reminders_providers.dart` | Modify | `updateReminderProvider` |
| `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart` | Modify | Edit mode, delete, type picker, `showReminderSheet` |
| `supabase/migrations/20261014100000_together_change_signals.sql` | Create | Signal table, RLS, triggers, publication |
| `supabase/migrations/20261014100100_moment_partner_push.sql` | Create | Partner push trigger |
| `supabase/migrations/20261014100200_reminder_custom_type.sql` | Create | Allow `custom` |
| `supabase/migrations/20261014100300_verdict_exclude_deleted_moments.sql` | Create | Redefine `request_verdict_generation` |
| `supabase/migrations/20261014100400_soft_delete_timeline_event.sql` | Create | Soft-delete RPC |
| `supabase/functions/generate-verdict/index.ts` | Modify | Filter `deleted_at` |
| `supabase/tests/together_phase0_contracts.sql` | Create | SQL contracts for Tasks 2, 3, 5, 8, 9 |
| `test/features/timeline/timeline_refresh_test.dart` | Create | Tasks 1–2 |
| `test/features/timeline/reminder_month_dots_test.dart` | Create | Task 6 |
| `test/features/timeline/moment_card_partner_name_test.dart` | Create | Task 7 |
| `test/features/timeline/calendar_day_sheet_empty_test.dart` | Create | Task 7 |
| `test/features/reminders/reminder_model_test.dart` | Modify | Task 4 |
| `test/features/reminders/edit_reminder_sheet_test.dart` | Create | Task 5 |

---

### Task 1: Month cache key that actually matches

**Files:**
- Modify: `lib/features/timeline/presentation/providers/timeline_providers.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart` (line 46 `DateTime _focusedMonth = DateTime.now();`)
- Test: `test/features/timeline/timeline_refresh_test.dart`

**Interfaces:**
- Produces: `DateTime timelineMonthKey(DateTime date)`, which returns `DateTime(date.year, date.month)` (local, first day of the month, midnight).

- [ ] **Step 1: Write the failing test**

Create `test/features/timeline/timeline_refresh_test.dart`:

```dart
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimelineRepository implements TimelineRepository {
  int monthFetches = 0;

  @override
  Future<List<TimelineEventModel>> getEventsForMonth({
    required String relationshipId,
    required DateTime month,
  }) async {
    monthFetches++;
    return const [];
  }

  @override
  Future<TimelineEventModel> createEvent({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
    required DateTime occurredAt,
    String? note,
    int? moodScore,
  }) async => TimelineEventModel.fromJson({
    'id': 'e1',
    'relationship_id': relationshipId,
    'logged_by': loggedBy,
    'event_type': eventType,
    'title': title,
    'note': note,
    'mood_score': moodScore,
    'occurred_at': occurredAt.toIso8601String().split('T')[0],
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': null,
    'deleted_at': null,
  });

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeTimelineRepository repo) {
  final container = ProviderContainer(
    overrides: [
      timelineRepositoryProvider.overrideWithValue(repo),
      currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
      currentUserIdProvider.overrideWithValue('user-1'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('timelineMonthKey drops the day and time', () {
    expect(
      timelineMonthKey(DateTime(2026, 10, 14, 15, 30, 12)),
      DateTime(2026, 10),
    );
  });

  test('logging a moment refreshes the month the screen is showing', () async {
    final repo = _FakeTimelineRepository();
    final container = _container(repo);
    final key = timelineMonthKey(DateTime.now());
    container.listen(timelineEventsProvider(key), (_, __) {});
    await container.read(timelineEventsProvider(key).future);
    expect(repo.monthFetches, 1);

    await container.read(
      createTimelineEventProvider((
        eventType: 'highlight',
        title: 'Picnic',
        occurredAt: DateTime.now(),
        note: null,
        moodScore: null,
      )).future,
    );
    await container.read(timelineEventsProvider(key).future);

    expect(repo.monthFetches, 2, reason: 'the shown month was invalidated');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/timeline/timeline_refresh_test.dart`
Expected: compile error `timelineMonthKey isn't defined`.

- [ ] **Step 3: Implement**

In `timeline_providers.dart`, add above `timelineEventsProvider`:

```dart
/// The cache key for a month of moments: its first day at midnight.
/// Every reader and every invalidation must go through this, or a key
/// carrying a time of day silently misses the refresh.
DateTime timelineMonthKey(DateTime date) => DateTime(date.year, date.month);
```

In `createTimelineEventProvider`, replace

```dart
  final month = DateTime(params.occurredAt.year, params.occurredAt.month, 1);
  ref.invalidate(timelineEventsProvider(month));
```

with

```dart
  ref.invalidate(timelineEventsProvider(timelineMonthKey(params.occurredAt)));
```

In `updateTimelineEventProvider`, replace the `final month = DateTime(...)` block and its invalidate with:

```dart
  if (params.occurredAt != null) {
    ref.invalidate(
      timelineEventsProvider(timelineMonthKey(params.occurredAt!)),
    );
  }
```

In `timeline_screen.dart`, change line 46 to

```dart
  DateTime _focusedMonth = timelineMonthKey(DateTime.now());
```

and in both `onMonthChanged` callbacks, change `_focusedMonth = month;` to `_focusedMonth = timelineMonthKey(month);` and `ref.invalidate(timelineEventsProvider(month));` to `ref.invalidate(timelineEventsProvider(timelineMonthKey(month)));`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/timeline/`
Expected: all pass.

- [ ] **Step 5: Commit only if the owner has asked; otherwise leave the change in the tree**

---

### Task 2: Live refresh via `together_change_signals`

**Files:**
- Create: `supabase/migrations/20261014100000_together_change_signals.sql`
- Create: `supabase/tests/together_phase0_contracts.sql` (section 1)
- Modify: `lib/features/timeline/presentation/providers/timeline_providers.dart`
- Modify: `lib/features/timeline/data/repositories/timeline_repository.dart` (delete `subscribeToEvents`)
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Test: `test/features/timeline/timeline_refresh_test.dart` (add a test)

**Interfaces:**
- Consumes: `timelineMonthKey` (Task 1).
- Produces:
  - table `public.together_change_signals(relationship_id uuid PK, version bigint, updated_at timestamptz)`;
  - `togetherChangeSignalProvider`: `StreamProvider.autoDispose.family<void, String>`, keyed by relationship id;
  - `timelineAutoRefreshProvider`: `Provider.autoDispose.family<void, String>`.
  - Phase 1 will bump the same table from `couple_events`.

- [ ] **Step 1: Write the failing Dart test** (append to `timeline_refresh_test.dart`; add `import 'dart:async';` at the top)

```dart
  test('a Together change signal refetches the moments', () async {
    final repo = _FakeTimelineRepository();
    final signals = StreamController<void>.broadcast();
    addTearDown(signals.close);
    final container = ProviderContainer(
      overrides: [
        timelineRepositoryProvider.overrideWithValue(repo),
        currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
        currentUserIdProvider.overrideWithValue('user-1'),
        togetherChangeSignalProvider.overrideWith((ref, id) => signals.stream),
      ],
    );
    addTearDown(container.dispose);
    final key = timelineMonthKey(DateTime.now());
    container.listen(timelineEventsProvider(key), (_, __) {});
    container.listen(timelineAutoRefreshProvider('rel-1'), (_, __) {});
    await container.read(timelineEventsProvider(key).future);
    expect(repo.monthFetches, 1);

    signals.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(timelineEventsProvider(key).future);

    expect(repo.monthFetches, 2);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/timeline/timeline_refresh_test.dart`
Expected: compile error `togetherChangeSignalProvider isn't defined`.

- [ ] **Step 3: Write the migration** `supabase/migrations/20261014100000_together_change_signals.sql`

```sql
-- Together (spec 2026-10-14 §5.6): a per-couple "something changed"
-- signal that Realtime delivers, so both partners refetch. Copies
-- planning_change_signals. Triggers rather than RPC bumps because
-- timeline_events and reminders are still written by direct table calls.
-- Realtime is a refetch signal only, never a second source of truth.

CREATE TABLE IF NOT EXISTS public.together_change_signals (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id)
                    ON DELETE CASCADE,
  version         bigint NOT NULL DEFAULT 1,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.together_change_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS together_change_signals_select ON public.together_change_signals;
CREATE POLICY together_change_signals_select ON public.together_change_signals
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.relationships r
      WHERE r.id = together_change_signals.relationship_id
        AND r.status = 'active' AND r.chat_archived_at IS NULL
        AND (r.user_a = auth.uid() OR r.user_b = auth.uid())
    )
  );

REVOKE ALL ON public.together_change_signals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.together_change_signals TO authenticated;

CREATE OR REPLACE FUNCTION public.bump_together_signal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_rel := OLD.relationship_id;
  ELSE
    v_rel := NEW.relationship_id;
  END IF;
  IF v_rel IS NULL THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.together_change_signals (relationship_id, version, updated_at)
  VALUES (v_rel, 1, now())
  ON CONFLICT (relationship_id) DO UPDATE
    SET version = together_change_signals.version + 1, updated_at = now();
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.bump_together_signal() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_together_signal_timeline ON public.timeline_events;
CREATE TRIGGER trigger_together_signal_timeline
  AFTER INSERT OR UPDATE OR DELETE ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DROP TRIGGER IF EXISTS trigger_together_signal_reminders ON public.reminders;
CREATE TRIGGER trigger_together_signal_reminders
  AFTER INSERT OR UPDATE OR DELETE ON public.reminders
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DROP TRIGGER IF EXISTS trigger_together_signal_family ON public.couple_family_members;
CREATE TRIGGER trigger_together_signal_family
  AFTER INSERT OR UPDATE OR DELETE ON public.couple_family_members
  FOR EACH ROW EXECUTE FUNCTION public.bump_together_signal();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'together_change_signals'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.together_change_signals;
  END IF;
END $$;
```

- [ ] **Step 4: Write contract section 1** in a new `supabase/tests/together_phase0_contracts.sql`

```sql
-- Together Phase 0 contracts (spec 2026-10-14 §8.1). Self-contained
-- fixtures; every check RAISEs on violation.
BEGIN;

INSERT INTO auth.users (id) VALUES
  ('7a000000-0000-0000-0000-0000000000a1'),
  ('7a000000-0000-0000-0000-0000000000b2'),
  ('7a000000-0000-0000-0000-0000000000c3')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('7a000000-0000-0000-0000-0000000000a1', '+233260000001', 'Ama'),
  ('7a000000-0000-0000-0000-0000000000b2', '+233260000002', 'Kofi'),
  ('7a000000-0000-0000-0000-0000000000c3', '+233260000003', 'Stranger')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
VALUES ('7e000000-0000-0000-0000-000000000001',
        '7a000000-0000-0000-0000-0000000000a1',
        '7a000000-0000-0000-0000-0000000000b2', 'active', now(), now())
ON CONFLICT (id) DO NOTHING;

-- 1. Writing a moment or reminder bumps the couple's signal; members can
--    read it, a stranger cannot.
DO $$
DECLARE v_before bigint; v_after bigint; v_seen int;
BEGIN
  SELECT coalesce(max(version), 0) INTO v_before
  FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';

  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'conflict', 'Signal probe', current_date);
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'anniversary', 'Signal probe', now(), 'yearly');

  SELECT version INTO v_after FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_after IS NULL OR v_after < v_before + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: signal not bumped (before %, after %)', v_before, v_after;
  END IF;

  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000c3', 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_seen FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_seen <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger can read the couple''s signal';
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_seen FROM public.together_change_signals
  WHERE relationship_id = '7e000000-0000-0000-0000-000000000001';
  IF v_seen <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner cannot read the signal';
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

ROLLBACK;
```

(Later tasks insert their sections before `ROLLBACK;`.)

- [ ] **Step 5: Implement the providers**

In `timeline_providers.dart`, add these imports:

```dart
import 'dart:async';

import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    as reminders_providers;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
```

Delete `timelineRealtimeProvider` (the last provider in the file) and add:

```dart
final _togetherSignalChannels = <String, RealtimeChannel>{};

/// Emits when anything Together shows changes for [relationshipId]
/// (moments, reminders, family birthdays), once on every (re)subscribe,
/// and on app resume. Realtime is only a refetch signal here, exactly
/// as planningChangeSignalProvider.
final togetherChangeSignalProvider = StreamProvider.autoDispose
    .family<void, String>((ref, relationshipId) {
      final supabase = ref.read(supabaseClientProvider);
      final controller = StreamController<void>.broadcast();
      void emit() {
        if (!controller.isClosed) controller.add(null);
      }

      final channel = supabase
          .channel('together-signals:$relationshipId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'together_change_signals',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'relationship_id',
              value: relationshipId,
            ),
            callback: (_) => emit(),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) emit();
          });
      _togetherSignalChannels[relationshipId] = channel;
      final lifecycle = AppLifecycleListener(onResume: emit);

      ref.onDispose(() {
        lifecycle.dispose();
        final c = _togetherSignalChannels.remove(relationshipId);
        if (c != null) unawaited(supabase.removeChannel(c));
        controller.close();
      });
      return controller.stream;
    });

/// Watch this while the Timeline is on screen: every Together signal
/// refetches moments (all months) and reminders.
final timelineAutoRefreshProvider = Provider.autoDispose.family<void, String>((
  ref,
  relationshipId,
) {
  ref.listen<AsyncValue<void>>(togetherChangeSignalProvider(relationshipId), (
    _,
    __,
  ) {
    ref.invalidate(timelineEventsProvider);
    ref.invalidate(reminders_providers.remindersListProvider);
  });
});
```

In `timeline_repository.dart`, delete the whole `subscribeToEvents` method and its doc comment.

In `timeline_screen.dart`, inside `relationshipIdAsync.when(data: (relationshipId) {`, right after the `if (relationshipId == null) {…}` block, add:

```dart
        // Live: a partner's new moment or reminder refetches this screen.
        ref.watch(timelineAutoRefreshProvider(relationshipId));
```

Also make pull-to-refresh refetch everything: replace the `onRefresh` body with

```dart
            onRefresh: () async {
              ref.invalidate(timelineEventsProvider);
              ref.invalidate(reminders_providers.remindersListProvider);
            },
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/timeline/` → all pass.
Run: `grep -rn "timelineRealtimeProvider\|subscribeToEvents" lib test` → no matches.
Run (Docker up): `scripts/run_sql_contracts.sh together_phase0` → passes.

---

### Task 3: Partner push for new moments (server-side)

**Files:**
- Create: `supabase/migrations/20261014100100_moment_partner_push.sql`
- Modify: `supabase/tests/together_phase0_contracts.sql` (section 2)
- Modify: `lib/features/timeline/data/repositories/timeline_repository.dart`

**Interfaces:**
- Produces: on every `timeline_events` INSERT that is not a conflict, one pending `scheduled_notifications` row for the partner, with:
  - `notification_type = 'immediate'`;
  - `metadata` holding `title`, `body`, `type = 'moment_logged'` and `relationship_id` (`type` and `relationship_id` are already allowlisted in `process-scheduled-notifications`' `privacySafeData`);
  - `source_key = 'moment:<event_id>:<partner_id>'`.

The existing app route `notification_config.dart:135` (`moment_logged` → timeline) already handles the tap.

- [ ] **Step 1: Write contract section 2** (insert before `ROLLBACK;`)

```sql
-- 2. A non-conflict moment queues exactly one push, for the partner only;
--    a conflict queues none (PULSE.md §10).
DO $$
DECLARE v_id uuid; v_partner int; v_logger int; v_conflict uuid; v_any int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'highlight', 'Beach day', current_date)
  RETURNING id INTO v_id;

  SELECT count(*) INTO v_partner FROM public.scheduled_notifications
  WHERE source_key = 'moment:' || v_id::text || ':7a000000-0000-0000-0000-0000000000b2'
    AND user_id = '7a000000-0000-0000-0000-0000000000b2'
    AND metadata->>'type' = 'moment_logged'
    AND metadata->>'title' = 'Ama added a moment'
    AND metadata->>'body' = 'Beach day';
  IF v_partner <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: expected 1 partner push, got %', v_partner;
  END IF;

  SELECT count(*) INTO v_logger FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_id::text || ':%'
    AND user_id = '7a000000-0000-0000-0000-0000000000a1';
  IF v_logger <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the logger was notified of their own moment';
  END IF;

  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'conflict', 'Argument', current_date)
  RETURNING id INTO v_conflict;
  SELECT count(*) INTO v_any FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_conflict::text || ':%';
  IF v_any <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a conflict moment notified someone';
  END IF;
END $$;

-- 2b. A relationship that is not active (no partner to tell) still saves the moment and queues nothing.
DO $$
DECLARE v_id uuid; v_any int;
BEGIN
  INSERT INTO public.relationships (id, user_a, user_b, status, started_at, created_at)
  VALUES ('7e000000-0000-0000-0000-000000000002',
          '7a000000-0000-0000-0000-0000000000c3', NULL, 'pending', now(), now())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000002',
          '7a000000-0000-0000-0000-0000000000c3', 'first', 'Solo', current_date)
  RETURNING id INTO v_id;
  SELECT count(*) INTO v_any FROM public.scheduled_notifications
  WHERE source_key LIKE 'moment:' || v_id::text || ':%';
  IF v_any <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pushed with no active partner';
  END IF;
END $$;
```

If `relationships.user_b` is `NOT NULL` or `'pending'` isn't an allowed status, check the `relationships` CHECK constraints with `grep -n "status" supabase/migrations/*relationships*` and use the allowed non-active status; keep `user_b` set to an existing user.

- [ ] **Step 2: Write the migration** `supabase/migrations/20261014100100_moment_partner_push.sql`

```sql
-- Partner push for a new moment (PULSE.md §10; Together spec §8.1 #3).
-- Server-side so it can't be skipped by a client: the old client path
-- (AttuneNotificationService.notifyPartnerMomentLogged) only wrote a
-- debug log. Conflicts never notify. Idempotent per moment+recipient.

CREATE OR REPLACE FUNCTION public.notify_partner_moment_logged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partner uuid;
  v_name text;
BEGIN
  IF NEW.event_type = 'conflict' THEN
    RETURN NULL;
  END IF;

  SELECT CASE WHEN r.user_a = NEW.logged_by THEN r.user_b ELSE r.user_a END
  INTO v_partner
  FROM public.relationships r
  WHERE r.id = NEW.relationship_id AND r.status = 'active';

  IF v_partner IS NULL OR v_partner = NEW.logged_by THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(nullif(btrim(display_name), ''), 'Your partner')
  INTO v_name FROM public.users WHERE id = NEW.logged_by;
  v_name := coalesce(v_name, 'Your partner');

  INSERT INTO public.scheduled_notifications (
    user_id, notification_type, scheduled_for, status, metadata,
    source_key, created_at, updated_at
  ) VALUES (
    v_partner, 'immediate', now(), 'pending',
    jsonb_build_object(
      'title', v_name || ' added a moment',
      'body', NEW.title,
      'type', 'moment_logged',
      'relationship_id', NEW.relationship_id
    ),
    'moment:' || NEW.id::text || ':' || v_partner::text,
    now(), now()
  )
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.notify_partner_moment_logged() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trigger_notify_partner_moment_logged ON public.timeline_events;
CREATE TRIGGER trigger_notify_partner_moment_logged
  AFTER INSERT ON public.timeline_events
  FOR EACH ROW EXECUTE FUNCTION public.notify_partner_moment_logged();
```

- [ ] **Step 3: Remove the client stub**

In `timeline_repository.dart`:
- delete the `attune_notification_service.dart` import, the `_notificationService` field and its initialiser (the constructor becomes `TimelineRepository(this._supabase);`);
- delete the `if (eventType != 'conflict') { await _notifyPartner(...); }` block in `createEvent`;
- delete the whole `_notifyPartner` method.

Leave `AttuneNotificationService.notifyPartnerMomentLogged` in place in case other code uses it (`grep -rn notifyPartnerMomentLogged lib`); if nothing else calls it, delete it too.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/features/timeline` → no errors.
Run: `flutter test test/features/timeline/` → pass.
Run (Docker up): `scripts/run_sql_contracts.sh together_phase0` → pass.

---

### Task 4: Reminder dates stay on the picked day

**Files:**
- Modify: `lib/features/reminders/data/models/reminder_model.dart`
- Modify: `lib/features/reminders/data/repositories/reminders_repository.dart`
- Test: `test/features/reminders/reminder_model_test.dart`

**Interfaces:**
- Produces:
  - `ReminderModel.remindAt` is always a local `DateTime(y, m, d)` at midnight, the date the user picked;
  - a top-level `String reminderDateString(DateTime d)` in `reminder_model.dart`, which returns `YYYY-MM-DD`;
  - JSON `remind_at` is written as `YYYY-MM-DD`.

- [ ] **Step 1: Write the failing tests** (append inside `main()`)

```dart
  Map<String, dynamic> json(String remindAt) => {
    'id': 'rem-9',
    'relationship_id': 'rel-1',
    'created_by': 'user-1',
    'reminder_type': 'birthday',
    'title': 'Ama',
    'note': null,
    'remind_at': remindAt,
    'recurrence': 'yearly',
    'sent': false,
    'family_member_id': null,
    'linked_timeline_event_id': null,
    'created_at': '2026-08-02T10:00:00Z',
    'updated_at': '2026-08-02T10:00:00Z',
  };

  test('remindAt is the picked calendar date, whatever offset the server sent', () {
    expect(ReminderModel.fromJson(json('2026-10-20T00:00:00+00:00')).remindAt,
        DateTime(2026, 10, 20));
    expect(ReminderModel.fromJson(json('2026-10-20')).remindAt,
        DateTime(2026, 10, 20));
  });

  test('toJson writes a plain date, and the cache round-trips it', () {
    final r = ReminderModel.fromJson(json('2026-02-28T00:00:00Z'));
    expect(r.toJson()['remind_at'], '2026-02-28');
    expect(ReminderModel.fromJson(r.toJson()).remindAt, DateTime(2026, 2, 28));
  });

  test('reminderDateString pads month and day', () {
    expect(reminderDateString(DateTime(2027, 3, 4, 23, 59)), '2027-03-04');
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/reminders/reminder_model_test.dart`
Expected: compile error `reminderDateString isn't defined`.

- [ ] **Step 3: Implement**

In `reminder_model.dart`, add a top-level function after the imports:

```dart
/// A reminder's date as the plain calendar date the user picked
/// (`YYYY-MM-DD`). Reminders are all-day: sending a time of day lets the
/// date drift across midnight in time zones away from UTC.
String reminderDateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The calendar date in [raw]: a UTC timestamp's own date parts (the
/// server stores midnight UTC), or a plain date. Never shifted to local.
DateTime _reminderDate(String raw) {
  final parsed = DateTime.parse(raw);
  return DateTime(parsed.year, parsed.month, parsed.day);
}
```

In `fromJson`, change the `remindAt` line to `remindAt: _reminderDate(json['remind_at'] as String),`. In `toJson`, change it to `'remind_at': reminderDateString(remindAt),`.

In `reminders_repository.dart`, change `'remind_at': remindAt.toIso8601String(),` (create) and `updates['remind_at'] = remindAt.toIso8601String();` (update) to use `reminderDateString(remindAt)`. Import the model file if it isn't already imported.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/reminders/ test/features/timeline/` → pass.

---

### Task 5: Edit, delete and choose the type of a reminder

**Files:**
- Create: `supabase/migrations/20261014100200_reminder_custom_type.sql`
- Modify: `supabase/tests/together_phase0_contracts.sql` (section 3)
- Modify: `lib/features/reminders/data/repositories/reminders_repository.dart` (`updateReminder`)
- Modify: `lib/features/reminders/presentation/providers/reminders_providers.dart`
- Modify: `lib/features/reminders/presentation/screens/add_edit_reminder_screen.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart` (`_ScheduledTile._onTap`)
- Test: `test/features/reminders/edit_reminder_sheet_test.dart`

**Interfaces:**
- Consumes: `reminderDateString` (Task 4).
- Produces:
  - `RemindersRepository.updateReminder({required String id, String? reminderType, String? title, String? note, bool clearNote = false, DateTime? remindAt, String? recurrence, String? familyMemberId})`;
  - `updateReminderProvider`: `FutureProvider.family<ReminderModel, ({String id, String reminderType, String title, String? note, DateTime remindAt, String recurrence})>`;
  - `AddEditReminderScreen({super.key, this.reminder})`;
  - top-level `Future<void> showReminderSheet(BuildContext context, {ReminderModel? reminder})`.

- [ ] **Step 1: Write the failing widget test** `test/features/reminders/edit_reminder_sheet_test.dart`

```dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/reminders/presentation/screens/add_edit_reminder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RemindersRepository {
  final List<Map<String, Object?>> updates = [];
  final List<String> deleted = [];

  @override
  Future<ReminderModel> updateReminder({
    required String id,
    String? reminderType,
    String? title,
    String? note,
    bool clearNote = false,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
  }) async {
    updates.add({
      'id': id,
      'reminderType': reminderType,
      'title': title,
      'note': note,
      'clearNote': clearNote,
      'remindAt': remindAt,
      'recurrence': recurrence,
    });
    return _reminder(type: reminderType ?? 'anniversary');
  }

  @override
  Future<void> deleteReminder(String id) async => deleted.add(id);

  @override
  Future<List<ReminderModel>> listReminders(String relationshipId) async => [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReminderModel _reminder({String type = 'anniversary'}) => ReminderModel(
  id: 'rem-1',
  relationshipId: 'rel-1',
  createdBy: 'user-1',
  reminderType: type,
  title: 'First date',
  note: 'Jollof place',
  remindAt: DateTime(2026, 11, 2),
  recurrence: 'yearly',
  sent: false,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Future<void> _open(WidgetTester tester, _FakeRepo repo, ReminderModel r) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        remindersRepositoryProvider.overrideWithValue(repo),
        currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddEditReminderScreen(reminder: r),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens prefilled and saves edits, including a new type', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    expect(find.text('Edit reminder'), findsOneWidget);
    expect(find.text('First date'), findsOneWidget);

    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.updates, hasLength(1));
    expect(repo.updates.single['id'], 'rem-1');
    expect(repo.updates.single['reminderType'], 'custom');
    expect(repo.updates.single['recurrence'], 'yearly');
    expect(repo.updates.single['remindAt'], DateTime(2026, 11, 2));
    expect(find.byType(AddEditReminderScreen), findsNothing, reason: 'closed');
  });

  testWidgets('delete asks first, then deletes', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder());
    await tester.tap(find.text('Delete reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['rem-1']);
    expect(find.byType(AddEditReminderScreen), findsNothing);
  });

  testWidgets('a type the picker does not offer still opens (shown as Other)', (tester) async {
    final repo = _FakeRepo();
    await _open(tester, repo, _reminder(type: 'checkin'));
    expect(tester.takeException(), isNull);
    expect(find.text('Edit reminder'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/reminders/edit_reminder_sheet_test.dart`
Expected: compile error, because `AddEditReminderScreen` has no `reminder` parameter and `updateReminder` has no `reminderType`.

- [ ] **Step 3: Write the migration and contract section 3**

`supabase/migrations/20261014100200_reminder_custom_type.sql`:

```sql
-- Reminders the couple names themselves ("Other" in the picker).
ALTER TABLE public.reminders DROP CONSTRAINT IF EXISTS reminders_reminder_type_check;
ALTER TABLE public.reminders ADD CONSTRAINT reminders_reminder_type_check
  CHECK (reminder_type IN ('anniversary', 'birthday', 'checkin', 'ai_generated', 'custom'));
```

Contract section 3 (before `ROLLBACK;`):

```sql
-- 3. 'custom' is an accepted reminder type.
DO $$
BEGIN
  INSERT INTO public.reminders (relationship_id, created_by, reminder_type, title, remind_at, recurrence)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'custom', 'Rent day', now(), 'none');
EXCEPTION WHEN check_violation THEN
  RAISE EXCEPTION 'CONTRACT VIOLATED: custom reminder type rejected';
END $$;
```

- [ ] **Step 4: Repository and provider**

Replace `updateReminder` in `reminders_repository.dart` with:

```dart
  Future<ReminderModel> updateReminder({
    required String id,
    String? reminderType,
    String? title,
    String? note,
    bool clearNote = false,
    DateTime? remindAt,
    String? recurrence,
    String? familyMemberId,
  }) async {
    final updates = <String, dynamic>{};
    if (reminderType != null) updates['reminder_type'] = reminderType;
    if (title != null) updates['title'] = title;
    if (note != null || clearNote) updates['note'] = note;
    if (remindAt != null) updates['remind_at'] = reminderDateString(remindAt);
    if (recurrence != null) updates['recurrence'] = recurrence;
    if (familyMemberId != null) updates['family_member_id'] = familyMemberId;

    final response = await _supabase
        .from('reminders')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return ReminderModel.fromJson(response);
  }
```

In `reminders_providers.dart`, after `createReminderProvider`:

```dart
final updateReminderProvider = FutureProvider.family<
  ReminderModel,
  ({
    String id,
    String reminderType,
    String title,
    String? note,
    DateTime remindAt,
    String recurrence,
  })
>((ref, params) async {
  final reminder = await ref.read(remindersRepositoryProvider).updateReminder(
        id: params.id,
        reminderType: params.reminderType,
        title: params.title,
        note: params.note,
        clearNote: params.note == null,
        remindAt: params.remindAt,
        recurrence: params.recurrence,
      );
  ref.invalidate(remindersListProvider);
  return reminder;
});
```

- [ ] **Step 5: The sheet** (`add_edit_reminder_screen.dart`). Re-read the file first and keep the owner's layout. Make these changes:

1. Constructor and field, plus the sheet opener at the top level of the file:

```dart
/// Opens the reminder sheet: empty to add one, or with [reminder] to
/// edit or delete it.
Future<void> showReminderSheet(BuildContext context, {ReminderModel? reminder}) {
  return BottomSheetUtils.showDocumentationBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.neutral,
    widget: AddEditReminderScreen(reminder: reminder),
  );
}

class AddEditReminderScreen extends ConsumerStatefulWidget {
  const AddEditReminderScreen({super.key, this.reminder});

  /// The reminder being edited; null when adding one.
  final ReminderModel? reminder;
  …
```

   Add `import 'package:attune/features/reminders/data/models/reminder_model.dart';`. If `BottomSheetUtils` or `.neutral` aren't already in scope through `export_screens.dart`, import them the way `timeline_screen.dart` does.

2. State: add `static const _pickerTypes = {'anniversary', 'birthday', 'custom'};` and `bool get _isEditing => widget.reminder != null;`. In `initState`, before the listener:

```dart
    final r = widget.reminder;
    if (r != null) {
      _titleController.text = r.title;
      _noteController.text = r.note ?? '';
      _reminderType = _pickerTypes.contains(r.reminderType) ? r.reminderType : 'custom';
      _remindAt = r.remindAt;
      _isYearly = r.recurrence == 'yearly';
      _dateSelected = true;
    }
```

3. In `_save`, add an edit branch at the top of the `try`:

```dart
      if (_isEditing) {
        await ref.read(
          updateReminderProvider((
            id: widget.reminder!.id,
            reminderType: _reminderType,
            title: _titleController.text.trim(),
            note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
            remindAt: _remindAt,
            recurrence: _isYearly ? 'yearly' : 'none',
          )).future,
        );
        if (!mounted) return;
        context.showSuccessSnackbar('Saved.');
        Navigator.of(context).pop();
        return;
      }
```

4. Add a delete method:

```dart
  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this reminder?'),
        content: const Text('It will be removed for both of you.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(deleteReminderProvider(widget.reminder!.id).future);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not delete that. Please try again.');
    }
  }
```

5. In `build`:
   - the header `InfoRowWidget` title becomes `_isEditing ? 'Edit reminder' : 'Add to calendar'`;
   - after the note field's `Gap(Spacing.md)`, add the type picker:

```dart
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'anniversary', label: Text('Anniversary')),
                  ButtonSegment(value: 'birthday', label: Text('Birthday')),
                  ButtonSegment(value: 'custom', label: Text('Other')),
                ],
                selected: {_reminderType},
                onSelectionChanged: (s) => setState(() => _reminderType = s.first),
              ),
            ),
            Gap(Spacing.md),
```

   - after the last `AppDivider()` (below the yearly toggle), add:

```dart
            if (_isEditing) ...[
              InfoRowWidget(
                title: 'Delete reminder',
                subtitle: '',
                icon: Icons.delete_outline_rounded,
                iconColor: colorScheme.error,
                showAvatar: false,
                showDivider: false,
                disableTrailing: true,
                onTap: _delete,
              ),
              AppDivider(),
            ],
```

   `_offerTimelineLink` keeps its `if (_reminderType != 'anniversary') return;` guard. It runs on create only, so birthday and Other reminders no longer get the "Add to Timeline?" prompt.

- [ ] **Step 6: Wire the taps**

In `timeline_screen.dart`:
- replace the FAB's `AddChoice.reminder` branch body (the `await BottomSheetUtils.showDocumentationBottomSheet(...)` call) with `await showReminderSheet(context);`;
- replace `onReminderTap: (reminder) {},` with:

```dart
                        onReminderTap: (reminder) async {
                          await showReminderSheet(context, reminder: reminder);
                          if (mounted) {
                            ref.invalidate(reminders_providers.remindersListProvider);
                          }
                        },
```

In `calendar_day_sheet.dart` `_ScheduledTile._onTap`, add a case before `_ => null`:

```dart
    ReminderModel reminder => () {
      final navigator = Navigator.of(context);
      final host = navigator.context;
      navigator.pop(); // close the day sheet first
      showReminderSheet(host, reminder: reminder);
    },
```

Import `add_edit_reminder_screen.dart`. Update the doc comment above `_onTap` to say "A Planning row opens its plan; a reminder opens its editor."

- [ ] **Step 7: Run tests**

Run: `flutter test test/features/reminders/ test/features/timeline/` → pass.
Run: `flutter analyze lib/features/reminders lib/features/timeline` → no new errors.

---

### Task 6: Calendar shows every reminder in the focused month

**Files:**
- Modify: `lib/features/timeline/presentation/widgets/upcoming_reminders_section.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart` (`_remindersByDate`)
- Test: `test/features/timeline/reminder_month_dots_test.dart`

**Interfaces:**
- Produces: `Map<DateTime, List<ReminderModel>> remindersByDateInMonth(List<ReminderModel> reminders, DateTime month)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/timeline/presentation/widgets/upcoming_reminders_section.dart';
import 'package:flutter_test/flutter_test.dart';

ReminderModel _r(String id, DateTime at, {String recurrence = 'yearly'}) => ReminderModel(
  id: id, relationshipId: 'rel', createdBy: 'u', reminderType: 'anniversary',
  title: id, remindAt: at, recurrence: recurrence, sent: false,
  createdAt: DateTime(2026), updatedAt: DateTime(2026),
);

void main() {
  test('a yearly reminder shows in its month of any year, even far ahead', () {
    final dots = remindersByDateInMonth([_r('anniv', DateTime(2024, 10, 20))], DateTime(2028, 10));
    expect(dots.keys, [DateTime(2028, 10, 20)]);
  });

  test('a past one-off shows only in its own month', () {
    final r = _r('trip', DateTime(2025, 3, 9), recurrence: 'none');
    expect(remindersByDateInMonth([r], DateTime(2025, 3)).keys, [DateTime(2025, 3, 9)]);
    expect(remindersByDateInMonth([r], DateTime(2026, 3)), isEmpty);
  });

  test('Feb 29 lands on Feb 28 in a non-leap year', () {
    final dots = remindersByDateInMonth([_r('leap', DateTime(2024, 2, 29))], DateTime(2027, 2));
    expect(dots.keys, [DateTime(2027, 2, 28)]);
  });

  test('other months get nothing', () {
    expect(remindersByDateInMonth([_r('a', DateTime(2024, 10, 20))], DateTime(2028, 11)), isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**: `flutter test test/features/timeline/reminder_month_dots_test.dart` → `remindersByDateInMonth isn't defined`.

- [ ] **Step 3: Implement** (in `upcoming_reminders_section.dart`, after `upcomingReminders`)

```dart
/// Every reminder that falls in [month], keyed by its calendar date: a
/// yearly one in any year (Feb 29 → Feb 28 in non-leap years), a one-off
/// only in its own month. Unlike [upcomingReminders] there is no 3-month
/// horizon: the calendar shows whatever month the couple is looking at.
Map<DateTime, List<ReminderModel>> remindersByDateInMonth(
  List<ReminderModel> reminders,
  DateTime month,
) {
  final grouped = <DateTime, List<ReminderModel>>{};
  for (final reminder in reminders) {
    final at = reminder.remindAt;
    final DateTime date;
    if (reminder.isRecurring) {
      if (at.month != month.month) continue;
      final day = at.day.clamp(1, _lastDayOfMonth(month.year, month.month));
      date = DateTime(month.year, month.month, day);
    } else {
      if (at.year != month.year || at.month != month.month) continue;
      date = DateTime(at.year, at.month, at.day);
    }
    grouped.putIfAbsent(date, () => []).add(reminder);
  }
  return grouped;
}
```

In `timeline_screen.dart`, replace the body of `_remindersByDate` with `return remindersByDateInMonth(reminders, _focusedMonth);`.

- [ ] **Step 4: Run tests**: `flutter test test/features/timeline/` → pass.

---

### Task 7: Partner's name on moments, an honest empty day, and `_selectDate`

**Files:**
- Modify: `lib/features/timeline/presentation/widgets/moment_card.dart`, `moments_list.dart`
- Modify: `lib/features/timeline/presentation/screens/timeline_screen.dart`
- Modify: `lib/features/timeline/presentation/widgets/calendar_day_sheet.dart`
- Test: `test/features/timeline/moment_card_partner_name_test.dart`, `test/features/timeline/calendar_day_sheet_empty_test.dart`

**Interfaces:**
- Produces: `MomentCard({…, String partnerName = 'Partner'})` and `MomentsList({…, String partnerName = 'Partner'})`.

- [ ] **Step 1: Write the failing tests**

`moment_card_partner_name_test.dart`:

```dart
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("a partner's moment says who logged it", (tester) async {
    final event = TimelineEventModel.fromJson({
      'id': 'e1', 'relationship_id': 'rel', 'logged_by': 'kofi', 'event_type': 'highlight',
      'title': 'Beach day', 'note': null, 'mood_score': null, 'occurred_at': '2026-10-10',
      'created_at': '2026-10-10T10:00:00Z', 'updated_at': null, 'deleted_at': null,
    });
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: MomentCard(
              event: event,
              currentUserId: 'ama',
              currentMonth: DateTime(2026, 10),
              partnerName: 'Kofi',
            ),
          ),
        ),
      ),
    ));
    expect(find.text('Logged by: Kofi'), findsOneWidget);
  });
}
```

`calendar_day_sheet_empty_test.dart`:
- copy the minimal fake gateway pattern from `test/features/stories/story_calendar_test.dart`, class `_FakeCalendarGateway`, lines 100–190;
- return an empty `StoryItemPage` from `listDayItems`, and have `noSuchMethod` throw for everything else;
- also include any extra overrides that harness uses (`currentUserProvider`).

```dart
// (imports: calendar_day_sheet.dart, story_read_repository.dart, story_providers.dart,
//  auth_provider.dart, flutter_riverpod, flutter_screenutil, flutter_test, material)
testWidgets('an empty day says so even when signed in', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(null),
      storyReadGatewayProvider.overrideWithValue(_EmptyStoryGateway()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: CalendarDaySheet(
            relationshipId: 'rel-1',
            date: DateTime(2026, 10, 14),
            events: const [],
            reminders: const [],
            planningEntries: const [],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('No moments or plans on this day.'), findsOneWidget);
});
```

- [ ] **Step 2: Run them to verify they fail.** Expected: `partnerName` is not a parameter (compile error), and the day-sheet text is not found.

- [ ] **Step 3: Implement**

`moment_card.dart`: add the field `final String partnerName;` and the constructor parameter `this.partnerName = 'Partner',`. Replace

```dart
    final loggedByName =
        _isOwnEvent ? 'You' : 'Partner'; // In real app, fetch partner's name
```

with

```dart
    final loggedByName = _isOwnEvent ? 'You' : widget.partnerName;
```

`moments_list.dart`: add `final String partnerName;` and `this.partnerName = 'Partner',`, then pass `partnerName: partnerName,` into `MomentCard(...)`.

`timeline_screen.dart`:
- import `package:attune/features/quiz/presentation/providers/quiz_providers.dart' as quiz_providers;`;
- in `build`, add `final partnerName = ref.watch(quiz_providers.partnerNameProvider).valueOrNull ?? 'Partner';`;
- pass `partnerName: partnerName,` to both `MomentsList(...)` calls;
- rename `_scrollToDate` to `_selectDate` (ruling R2), remove its placeholder comments, and update every call site, including `onDateSelected: _scrollToDate`.

The method becomes:

```dart
  void _selectDate(DateTime date) => setState(() => _selectedDate = date);
```

`calendar_day_sheet.dart`: change the empty condition to

```dart
              if (events.isEmpty && reminders.isEmpty && planningEntries.isEmpty)
```

and the text to `'No moments or plans on this day.'`. That wording stays true when the day only has stories.

- [ ] **Step 4: Run tests**: `flutter test test/features/timeline/ test/features/stories/` → pass.

---

### Task 8: Deleted moments stop counting toward the verdict

**Files:**
- Create: `supabase/migrations/20261014100300_verdict_exclude_deleted_moments.sql`
- Modify: `supabase/functions/generate-verdict/index.ts` (around line 293)
- Modify: `supabase/tests/together_phase0_contracts.sql` (section 4)

- [ ] **Step 1: Write contract section 4** (before `ROLLBACK;`)

```sql
-- 4. Verdict eligibility ignores soft-deleted moments.
DO $$
DECLARE v_def text; v_hits int;
BEGIN
  SELECT pg_get_functiondef('public.request_verdict_generation'::regproc) INTO v_def;
  SELECT count(*) INTO v_hits
  FROM regexp_matches(v_def, 'te\.deleted_at IS NULL', 'g');
  IF v_hits < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verdict eligibility counts deleted moments (% filters)', v_hits;
  END IF;
END $$;
```

(If `request_verdict_generation` is overloaded, use `'public.request_verdict_generation(<arg types>)'::regprocedure` with the signature from line 235 of `20260703183000_verdict_system_v1_1.sql`.)

- [ ] **Step 2: Write the migration.** Copy the complete `CREATE OR REPLACE FUNCTION public.request_verdict_generation(` definition verbatim from `supabase/migrations/20260703183000_verdict_system_v1_1.sql`. It starts at line 235; take everything through its closing `$$;` and any GRANT/REVOKE lines for it that follow. Paste it into `20261014100300_verdict_exclude_deleted_moments.sql` under this header:

```sql
-- Soft-deleted moments must not make a couple verdict-eligible or count
-- as strength/concern evidence (Together spec §8.1 #10). Verbatim copy of
-- request_verdict_generation from 20260703183000 with two filters added.
```

Then, in both `FROM public.timeline_events te` subqueries, add `AND te.deleted_at IS NULL` directly after `WHERE te.relationship_id = p_relationship_id`. Run `git diff --no-index` between the original function block and the new file to confirm that only those two lines differ.

- [ ] **Step 3: Edge function.** In `supabase/functions/generate-verdict/index.ts`, in the `timeline_events` query (`.from("timeline_events")` around line 293), add `.is("deleted_at", null)` after `.eq("relationship_id", job.relationship_id)`.

- [ ] **Step 4: Verify.** Run `deno check supabase/functions/generate-verdict/index.ts` if Deno is installed. Run `deno test supabase/functions/generate-verdict` if tests exist there; they must pass. Run the SQL contracts with Docker up.

---

### Task 9: Soft delete through an RPC

**Files:**
- Create: `supabase/migrations/20261014100400_soft_delete_timeline_event.sql`
- Modify: `supabase/tests/together_phase0_contracts.sql` (section 5)
- Modify: `lib/features/timeline/data/repositories/timeline_repository.dart` (`deleteEvent`)

**Interfaces:**
- Produces: `public.soft_delete_timeline_event(p_event_id uuid) RETURNS void`. Only the logger may call it; anyone else gets errcode `P0002` ("not found").

- [ ] **Step 1: Write contract section 5** (before `ROLLBACK;`)

```sql
-- 5. Only the logger can delete a moment, and it then disappears for both.
DO $$
DECLARE v_id uuid; v_visible int;
BEGIN
  INSERT INTO public.timeline_events (relationship_id, logged_by, event_type, title, occurred_at)
  VALUES ('7e000000-0000-0000-0000-000000000001',
          '7a000000-0000-0000-0000-0000000000a1', 'first', 'First trip', current_date)
  RETURNING id INTO v_id;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000b2', 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.soft_delete_timeline_event(v_id);
    RAISE EXCEPTION 'CONTRACT VIOLATED: the partner deleted someone else''s moment';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '7a000000-0000-0000-0000-0000000000a1', 'role', 'authenticated')::text, true);
  PERFORM public.soft_delete_timeline_event(v_id);

  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_visible FROM public.timeline_events WHERE id = v_id;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_visible <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deleted moment is still visible';
  END IF;
END $$;
```

- [ ] **Step 2: Write the migration**

```sql
-- Soft delete as an RPC (plan ruling R4): an UPDATE that sets deleted_at
-- only works while PostgREST doesn't read the row back, because the read
-- policy hides deleted rows. The RPC makes it independent of that.
CREATE OR REPLACE FUNCTION public.soft_delete_timeline_event(p_event_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.timeline_events
  SET deleted_at = now(), updated_at = now()
  WHERE id = p_event_id
    AND logged_by = auth.uid()
    AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'moment not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.soft_delete_timeline_event(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.soft_delete_timeline_event(uuid) TO authenticated;
```

- [ ] **Step 3: Client.** Replace the body of `deleteEvent` in `timeline_repository.dart` with:

```dart
  /// Soft delete (logger only), through the RPC so it does not depend on
  /// PostgREST's return mode (the read policy hides deleted rows).
  Future<void> deleteEvent(String eventId) async {
    await _supabase.rpc(
      'soft_delete_timeline_event',
      params: {'p_event_id': eventId},
    );
  }
```

- [ ] **Step 4: Verify.** `flutter test test/features/timeline/` passes; the SQL contracts pass with Docker up.

---

### Task 10: Close out

**Files:**
- Modify: `docs/superpowers/specs/2026-10-14-together-hub-design.md` §8.1 (record rulings R1–R4)

- [ ] **Step 1:** In spec §8.1:
  - item 4 becomes "Reminder dates are sent and read as plain calendar dates (no schema change; ruling R1)";
  - item 9 becomes "`_scrollToDate` is renamed `_selectDate` (ruling R2)";
  - item 11 becomes "Soft delete goes through the `soft_delete_timeline_event` RPC (ruling R4)";
  - item 1 drops "the log-moment flow returns its result" (ruling R3).
- [ ] **Step 2:** Run the full suite: `flutter test > /tmp/phase0.txt 2>&1; tail -3 /tmp/phase0.txt`. Expected: the only failure is the known planning home tab-height test.
- [ ] **Step 3:** Run `flutter analyze lib/features/timeline lib/features/reminders` → no new errors or warnings.
- [ ] **Step 4:** With Docker up, run `scripts/run_sql_contracts.sh together_phase0` → passes. Otherwise report it as not run.
- [ ] **Step 5:** Report to the owner:
  - **Deploys needed:** `supabase db push` for migrations `20261014100000`–`20261014100400`, and deploying the `generate-verdict` function.
  - **Manual check on two devices:** log a moment on phone A; phone B gets the push and the moment appears without a refresh. Edit and delete a reminder. Change a reminder's type to Other.
