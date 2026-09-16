// Provider tests focus on the two concurrency properties Stories'
// _KeysetPager was built to fix, plus the .family key-equality trap
// that shipped a real leak there — not on RPC correctness, which
// Plan A's own SQL contracts already prove.
import 'dart:async';

import 'package:attune/features/planning/data/models/planning_task_model.dart';
import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:attune/features/planning/presentation/providers/planning_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PlanningTaskModel _task(String id) => PlanningTaskModel.fromRow({
  'id': id, 'relationship_id': 'r1', 'created_by': 'u1',
  'item_kind': 'task', 'parent_goal_id': null, 'title': 'task $id',
  'note': null, 'assigned_to': null, 'due_date': null,
  'completed_at': null, 'celebrated_at': null,
  'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
  'deleted_at': null,
});

/// A fake at the level that actually exists: Task 1's own
/// `PlanningRpcGateway` seam, matching how `planning_repository_test.dart`
/// injects fakes — not a re-imagined narrower interface. Each entry in
/// [responses] is invoked once per call to `rpc`, in order (clamped to
/// the last entry once exhausted), letting a test control exactly which
/// call resolves when.
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

List<Map<String, dynamic>> _rowsFor(List<PlanningTaskModel> tasks) => [
  for (final t in tasks)
    {
      'id': t.id, 'relationship_id': 'r1', 'created_by': 'u1',
      'item_kind': 'task', 'parent_goal_id': null, 'title': t.title,
      'note': null, 'assigned_to': null, 'due_date': null,
      'completed_at': null, 'celebrated_at': null,
      'created_at': '2026-09-14T09:00:00Z',
      'updated_at': '2026-09-14T09:00:00Z',
      'deleted_at': null,
    },
];

void main() {
  test(
    'a late fetch from a superseded loadMore does not overwrite a newer '
    'refresh — the epoch guard Stories shipped without, twice '
    '(Stories F2: "Worse during loadMore: ... a signal landing mid-'
    'loadMore produced two interleaved walks")',
    () async {
      final initialLoad = Completer<dynamic>();
      final loadMoreCompleter = Completer<dynamic>();
      final refreshCompleter = Completer<dynamic>();

      final container = ProviderContainer(
        overrides: [
          planningRepositoryProvider.overrideWithValue(
            PlanningRepository(
              _SlowRpcGateway([
                () => initialLoad.future,
                () => loadMoreCompleter.future,
                () => refreshCompleter.future,
              ]),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Reading .notifier triggers _PlanningKeysetPager's constructor,
      // which kicks off its own initial refresh() (unawaited) — that
      // consumes the FIRST fake response. Resolve it out of the way
      // before driving the loadMore()/refresh() race this test
      // actually cares about, so the response list lines up with call
      // order.
      // .autoDispose tears the notifier down once nothing is listening
      // to it — keep a listener alive for the duration of this test,
      // the same as a screen's own `ref.watch` would.
      container.listen(planningTasksProvider('r1'), (_, __) {});
      final notifier = container.read(planningTasksProvider('r1').notifier);
      initialLoad.complete(_rowsFor([_task('from-initial-load')]));
      await Future<void>.delayed(Duration.zero);

      // loadMore() captures _epoch WITHOUT bumping it, so it must be
      // supersedable by a refresh() that starts (and finishes) while
      // it's still in flight — even though loadMore's own fetch
      // resolves AFTER the refresh's.
      final loadMoreFuture = notifier.loadMore();
      final refreshFuture = notifier.refresh();

      refreshCompleter.complete(_rowsFor([_task('from-refresh')]));
      await refreshFuture;
      loadMoreCompleter.complete(_rowsFor([_task('from-stale-load-more')]));
      await loadMoreFuture;
      await Future<void>.delayed(Duration.zero);

      final state = container.read(planningTasksProvider('r1'));
      expect(
        state.value?.map((t) => t.id),
        ['from-refresh'],
        reason:
            'the stale loadMore must not have appended onto or replaced '
            "the newer refresh's result",
      );
    },
  );

  test(
    'disposing the provider while a refresh is in flight does not throw '
    'when that refresh later completes',
    () async {
      final initialLoad = Completer<dynamic>();
      final completer = Completer<dynamic>();
      final container = ProviderContainer(
        overrides: [
          planningRepositoryProvider.overrideWithValue(
            PlanningRepository(
              _SlowRpcGateway([
                () => initialLoad.future,
                () => completer.future,
              ]),
            ),
          ),
        ],
      );

      // Resolve the constructor's own initial refresh() first, same
      // reasoning as the test above.
      final notifier = container.read(planningTasksProvider('r1').notifier);
      initialLoad.complete(_rowsFor([_task('from-initial-load')]));
      await Future<void>.delayed(Duration.zero);

      unawaited(notifier.refresh());
      container.dispose(); // dispose WHILE the refresh is still pending

      completer.complete(_rowsFor([_task('t1')]));
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
