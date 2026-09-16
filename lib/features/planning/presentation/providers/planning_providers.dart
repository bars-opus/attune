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
//
// Realtime is a refetch signal, never data (spec §6.4/§9): every
// provider below that depends on planningChangeSignalProvider reacts
// to a bump by re-invoking the relevant RPC through PlanningRepository
// — never by reading the change row's own payload, which this
// provider drops entirely. Nothing here adds a push-notification path
// (no OneSignal category, no scheduled_notifications row) — a
// backgrounded app simply refetches on resume via the same pipe.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
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
/// per-feature convention `reminders_providers.dart`/`story_providers.dart`
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
//
// Not file-private (no leading underscore), unlike Stories' own
// `_KeysetPager` — this is a package-internal implementation detail
// (never in this file's "Produces" list, never exported for a screen
// to touch directly), but it is given a plain name specifically so
// `planning_providers_test.dart` can reach it for one white-box
// regression test of `refresh()`'s own `epoch != _epoch` checks (see
// [debugBumpEpochForTest]'s doc comment for why that test needs to
// reach in this deep). Every other consumer still only ever sees this
// through a subclass, the same as if it were file-private.
abstract class PlanningKeysetPager<T>
    extends StateNotifier<AsyncValue<List<T>>> {
  PlanningKeysetPager() : super(const AsyncValue.loading()) {
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

  /// Test-only escape hatch: advances [_epoch] exactly as a concurrent
  /// [refresh] call would, WITHOUT going through [refresh] itself.
  ///
  /// No real caller can do this — every production path that bumps
  /// [_epoch] does so only from inside [refresh]'s own do-while loop,
  /// which is gated by the synchronous `_refreshing` check running
  /// before [refresh]'s first `await`. That gate, combined with the
  /// loop's strictly serial iteration, means no sequence of ordinary
  /// [refresh] calls — however many are stacked, in whatever
  /// completion order — can ever have two fetches genuinely in flight
  /// at once; coalescing (`_refreshAgainRequested`) always fully
  /// serializes them first. So [refresh]'s own two
  /// `epoch != _epoch` checks (as opposed to [loadMore]'s, which
  /// covers a real, reachable race against a concurrent [refresh] —
  /// see the black-box tests in `planning_providers_test.dart`) are
  /// unreachable through the public API in this design, exactly like
  /// the identical structure in `story_providers.dart`'s own
  /// `_KeysetPager`, which has no test of this exact branch either.
  ///
  /// The checks are still correct, load-bearing documentation of the
  /// loop's serialization invariant, and correct defensive code
  /// against a FUTURE change that breaks it (e.g., splitting the
  /// `_refreshing` check across an `await`, or "optimizing" the
  /// do-while into genuinely concurrent fetches) — so rather than
  /// leave that branch permanently uncovered, this lets a test
  /// simulate exactly the effect such a future bug would have on
  /// [_epoch], in isolation from whether today's call graph can
  /// trigger it.
  @visibleForTesting
  void debugBumpEpochForTest() => _epoch++;

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

class PlanningGoalsNotifier extends PlanningKeysetPager<PlanningGoalModel> {
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

class PlanningTasksNotifier extends PlanningKeysetPager<PlanningTaskModel> {
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

class PlanningEventsNotifier extends PlanningKeysetPager<PlanningEventModel> {
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

class PlanningNotesNotifier extends PlanningKeysetPager<PlanningNoteModel> {
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
