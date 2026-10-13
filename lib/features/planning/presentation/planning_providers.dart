import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/core/utils/timezone_utils.dart';
import 'package:uuid/uuid.dart';

import '../data/planning_error.dart';
import '../data/planning_media.dart';
import '../data/planning_models.dart';
import '../data/planning_repository.dart';
import '../domain/planning_outbox.dart';

const _uuid = Uuid();

/// Feature-local copy of the active relationship id, following the same
/// per-feature convention `reminders_providers.dart`/`story_providers.dart`
/// already use rather than importing across feature boundaries.
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = Supabase.instance.client;
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
      final supabase = Supabase.instance.client;
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


final planningRepositoryProvider = Provider<PlanningRepository>(
  (ref) => PlanningRepository(SupabasePlanningRpcGateway(Supabase.instance.client)),
);

final planningMediaGatewayProvider = Provider<PlanningMediaGateway>(
  (ref) => SupabasePlanningMediaGateway(Supabase.instance.client),
);

/// How long a signed photo URL is reused: re-signed two minutes before its
/// 10-minute life ends, so an image never loads from an expired link.
const planningSignedUrlReuse = Duration(minutes: 8);

/// A signed URL per stored path, reused for most of its life so scrolling a
/// plan does not re-sign every photo.
final planningSignedUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) async {
  final url = await ref.watch(planningMediaGatewayProvider).signedUrl(path);
  final link = ref.keepAlive();
  final timer = Timer(planningSignedUrlReuse, link.close);
  ref.onDispose(timer.cancel);
  return url;
});

/// The device's IANA zone, reported when Planning opens so countdown pushes
/// arrive at 08:00 local (spec §8.2).
final planningDeviceTimezoneProvider = FutureProvider<String?>((ref) => TimezoneUtils.getDeviceTimezone());

/// Minutes ahead of UTC for a zone, refreshed hourly (DST changes).
final planningTimezoneOffsetProvider = FutureProvider.autoDispose.family<int?, String>((ref, tz) async {
  final offset = await ref.watch(planningRepositoryProvider).timezoneOffsetMinutes(tz);
  final link = ref.keepAlive();
  final timer = Timer(const Duration(hours: 1), link.close);
  ref.onDispose(timer.cancel);
  return offset;
});

final planningGalleryProvider = FutureProvider.autoDispose<List<PlanningGalleryTemplate>>(
    (ref) => ref.watch(planningRepositoryProvider).listGallery());

final planningCurrentUserIdProvider =
    Provider<String?>((ref) => Supabase.instance.client.auth.currentUser?.id);

final planningOutboxStoreProvider = Provider<OutboxStore>((ref) => SharedPreferencesOutboxStore());

final planningOutboxSleepProvider =
    Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// One outbox for the app session (not autoDispose): queued ticks must
/// outlive the screen that made them.
final planningOutboxProvider = Provider<PlanningOutbox>((ref) {
  final repo = ref.watch(planningRepositoryProvider);
  return PlanningOutbox(
    store: ref.watch(planningOutboxStoreProvider),
    sleep: ref.watch(planningOutboxSleepProvider),
    send: (op) => switch (op) {
      CheckItemOp() => repo.setItemChecked(id: op.itemId, checked: op.checked, opId: op.opId),
      AddItemOp() => repo.addItem(
          id: op.itemId, blockId: op.blockId, text: op.text, section: op.section, afterId: op.afterId),
    },
  );
});

/// Change signal → refetch. The signal also fires on resubscribe and app
/// resume (planningChangeSignalProvider), which is when connectivity has likely returned,
/// so it is also the outbox replay trigger.
void _refetchOnSignal(Ref ref, String relationshipId, {bool replayOutbox = false}) {
  ref.listen(planningChangeSignalProvider(relationshipId), (_, __) {
    if (replayOutbox) {
      unawaited(ref.read(planningOutboxProvider).replay().then((r) {
        if (r.sent > 0 || r.dropped.isNotEmpty) ref.invalidateSelf();
      }));
    }
    ref.invalidateSelf();
  });
}

final planningHomeProvider =
    FutureProvider.autoDispose.family<List<PlanningCategory>, String>((ref, relationshipId) {
  // Every Planning screen replays the outbox on the signal (resubscribe / resume),
  // so ticks made offline sync on reconnect wherever the user is in
  // Planning, not only inside an entry (final review I2).
  _refetchOnSignal(ref, relationshipId, replayOutbox: true);
  return ref.watch(planningRepositoryProvider).getHome(relationshipId);
});

// ---- feeds ----------------------------------------------------------------

typedef PlanningCalendarRangeArgs = ({String relationshipId, DateTime start, DateTime end});

/// The calendar's Planning rows for a range; refetches on the change signal.
final planningCalendarEntriesProvider =
    FutureProvider.autoDispose.family<List<PlanningCalendarEntry>, PlanningCalendarRangeArgs>((ref, a) {
  _refetchOnSignal(ref, a.relationshipId);
  return ref.watch(planningRepositoryProvider).listCalendarEntries(a.relationshipId, start: a.start, end: a.end);
});

/// The Conversations card's Planning line; refetches on the change signal.
final planningSummaryProvider = FutureProvider.autoDispose.family<PlanningSummary?, String>((ref, relationshipId) {
  _refetchOnSignal(ref, relationshipId);
  final now = DateTime.now();
  return ref.watch(planningRepositoryProvider).getSummary(relationshipId, today: DateTime(now.year, now.month, now.day));
});

// ---- entries list --------------------------------------------------------

typedef PlanningEntriesArgs = ({String relationshipId, String categoryId, String group});

class PlanningEntriesState {
  const PlanningEntriesState({
    required this.entries,
    required this.cursorAt,
    required this.cursorId,
    this.pinned = const [],
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<PlanningEntrySummary> entries;

  /// Pinned plans, shown above [entries]; never also inside [entries].
  final List<PlanningEntrySummary> pinned;
  final DateTime? cursorAt;
  final String? cursorId;
  final bool loadingMore;
  final bool loadMoreFailed;

  bool get hasMore => cursorId != null;

  /// Unset arguments keep their current value — an action never silently
  /// clears another one's in-flight flag (review I2).
  PlanningEntriesState copyWith({
    List<PlanningEntrySummary>? entries,
    List<PlanningEntrySummary>? pinned,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) =>
      PlanningEntriesState(
        entries: entries ?? this.entries,
        pinned: pinned ?? this.pinned,
        cursorAt: cursorAt,
        cursorId: cursorId,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      );
}

/// Keyset pager over a category's plans. Refresh keeps the previous list
/// visible (spec §6.4); AsyncNotifier keeps the old value while reloading.
///
/// Every edit is applied to the CURRENT state when it lands, never to a
/// snapshot taken before an await: a page load, a pin and a delete can all
/// be in flight at once (review I2).
class PlanningEntriesController
    extends AutoDisposeFamilyAsyncNotifier<PlanningEntriesState, PlanningEntriesArgs> {
  PlanningRepository get _repo => ref.read(planningRepositoryProvider);

  /// Plans deleted here whose pages may still be arriving.
  final Set<String> _removed = {};

  @override
  Future<PlanningEntriesState> build(PlanningEntriesArgs arg) async {
    _refetchOnSignal(ref, arg.relationshipId, replayOutbox: true);
    final page = await _repo.listEntries(arg.categoryId, group: arg.group);
    _removed.clear();
    return PlanningEntriesState(
        entries: page.entries, pinned: page.pinned, cursorAt: page.nextCursorAt, cursorId: page.nextCursorId);
  }

  void _update(PlanningEntriesState Function(PlanningEntriesState current) f) {
    final current = state.valueOrNull;
    if (current != null) state = AsyncData(f(current));
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(s.copyWith(loadingMore: true, loadMoreFailed: false));
    try {
      final page = await _repo.listEntries(arg.categoryId, group: arg.group, cursorAt: s.cursorAt, cursorId: s.cursorId);
      _update((cur) {
        final shown = {for (final e in cur.entries) e.id, for (final e in cur.pinned) e.id, ..._removed};
        return PlanningEntriesState(
          entries: [...cur.entries, for (final e in page.entries) if (!shown.contains(e.id)) e],
          pinned: cur.pinned,
          cursorAt: page.nextCursorAt,
          cursorId: page.nextCursorId,
        );
      });
    } on PlanningError {
      _update((cur) => cur.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }

  List<PlanningEntrySummary> _without(List<PlanningEntrySummary> list, String id) =>
      [for (final e in list) if (e.id != id) e];

  /// Optimistic: the plan moves between the pinned group and the list at
  /// once; if the server refuses (e.g. the 20-pin limit) only this plan
  /// moves back.
  Future<void> togglePin(PlanningEntrySummary entry) async {
    final pin = !entry.pinned;
    void place(bool pinned) => _update((cur) {
          final moved = entry.copyWith(pinned: pinned);
          final entries = _without(cur.entries, entry.id);
          final pinnedList = _without(cur.pinned, entry.id);
          return cur.copyWith(
            pinned: pinned ? [moved, ...pinnedList] : pinnedList,
            entries: pinned ? entries : [moved, ...entries],
          );
        });
    place(pin);
    try {
      await _repo.pinEntry(entry.id, pinned: pin);
    } on PlanningError {
      if (!_removed.contains(entry.id)) place(!pin);
      rethrow;
    }
  }

  /// Optimistic delete; the caller offers Undo through [restore].
  Future<void> delete(PlanningEntrySummary entry) async {
    _removed.add(entry.id);
    _update((cur) => cur.copyWith(pinned: _without(cur.pinned, entry.id), entries: _without(cur.entries, entry.id)));
    try {
      await _repo.deleteEntry(entry.id);
    } on PlanningError {
      _removed.remove(entry.id);
      _update((cur) => entry.pinned
          ? cur.copyWith(pinned: [entry, ..._without(cur.pinned, entry.id)])
          : cur.copyWith(entries: [entry, ..._without(cur.entries, entry.id)]));
      rethrow;
    }
  }

  /// Undo for [delete]: the server restores the plan; the list refetches so
  /// it reappears in its true place (pinned or by activity).
  Future<void> restore(String entryId) async {
    await _repo.restoreEntry(entryId);
    _removed.remove(entryId);
    ref.invalidateSelf();
  }
}

final planningEntriesProvider = AsyncNotifierProvider.autoDispose
    .family<PlanningEntriesController, PlanningEntriesState, PlanningEntriesArgs>(PlanningEntriesController.new);

// ---- one entry -----------------------------------------------------------

typedef PlanningEntryArgs = ({String relationshipId, String entryId});

enum TickOutcome { synced, queued }

sealed class TextSaveResult {
  const TextSaveResult();
}

class TextSaved extends TextSaveResult {
  const TextSaved(this.block);
  final PlanningBlock block;
}

class TextConflict extends TextSaveResult {
  const TextConflict(this.theirs);
  final PlanningBlock theirs;
}

class TextGone extends TextSaveResult {
  const TextGone();
}

class PlanningEntryController extends AutoDisposeFamilyAsyncNotifier<PlanningEntryDetail, PlanningEntryArgs> {
  PlanningRepository get _repo => ref.read(planningRepositoryProvider);
  PlanningOutbox get _outbox => ref.read(planningOutboxProvider);

  bool _alive = true;

  @override
  Future<PlanningEntryDetail> build(PlanningEntryArgs arg) async {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _refetchOnSignal(ref, arg.relationshipId, replayOutbox: true);
    final detail = await _repo.getEntry(arg.entryId);
    final pending = [for (final op in await _outbox.pending()) if (op.entryId == arg.entryId) op];
    return _overlay(detail, pending);
  }

  /// Applies queued-but-unsent ops so an offline tick or add never
  /// visually reverts on refetch.
  PlanningEntryDetail _overlay(PlanningEntryDetail d, List<OutboxOp> ops) {
    var out = d;
    for (final op in ops) {
      switch (op) {
        case CheckItemOp():
          for (final b in out.blocks) {
            for (final i in b.items) {
              if (i.id == op.itemId) {
                out = _withItem(out, b.id, op.checked
                    ? i.copyWith(checkedAt: i.checkedAt ?? DateTime.now(), checkedBy: i.checkedBy)
                    : i.copyWith(clearChecked: true));
              }
            }
          }
        case AddItemOp():
          final exists = out.blocks.any((b) => b.items.any((i) => i.id == op.itemId));
          if (!exists && out.blocks.any((b) => b.id == op.blockId)) {
            out = _withBlockItems(out, op.blockId, (items) => [...items, _localItem(op.itemId, op.text, op.section)]);
          }
      }
    }
    return out;
  }

  PlanningItem _localItem(String id, String text, String? section) => PlanningItem(
      id: id, sortKey: '~', text: text, section: section, checkedAt: null, checkedBy: null,
      assignedTo: null, dueDate: null, version: 1);

  PlanningEntryDetail get _current => state.requireValue;
  void _set(PlanningEntryDetail d) => state = AsyncData(d);

  PlanningEntryDetail _withBlocks(PlanningEntryDetail d, List<PlanningBlock> blocks) => d.copyWith(blocks: blocks);

  PlanningEntryDetail _withBlock(PlanningEntryDetail d, PlanningBlock b) =>
      _withBlocks(d, [for (final x in d.blocks) x.id == b.id ? b : x]);

  PlanningEntryDetail _withBlockItems(
          PlanningEntryDetail d, String blockId, List<PlanningItem> Function(List<PlanningItem>) f) =>
      _withBlocks(d, [for (final x in d.blocks) x.id == blockId ? x.copyWith(items: f(x.items)) : x]);

  PlanningEntryDetail _withItem(PlanningEntryDetail d, String blockId, PlanningItem item) =>
      _withBlockItems(d, blockId, (items) => [for (final i in items) i.id == item.id ? item : i]);

  // ---- items ----

  /// Queues [op] behind older queued ops and starts a replay, so the server
  /// sees this entry's actions in the order the user made them.
  Future<TickOutcome> _queue(OutboxOp op, void Function() revert) async {
    try {
      await _outbox.enqueue(op);
    } on OutboxFullException {
      if (state.hasValue) revert();
      rethrow;
    }
    unawaited(_outbox.replay().then((r) {
      if (_alive && (r.sent > 0 || r.dropped.isNotEmpty)) ref.invalidateSelf();
    }));
    return TickOutcome.queued;
  }

  Future<TickOutcome> setChecked(String blockId, PlanningItem item, bool checked) async {
    final me = ref.read(planningCurrentUserIdProvider);
    _set(_withItem(_current, blockId,
        checked ? item.copyWith(checkedAt: DateTime.now(), checkedBy: me) : item.copyWith(clearChecked: true)));
    final opId = _uuid.v4();
    final op = CheckItemOp(
        opId: opId, relationshipId: arg.relationshipId, entryId: arg.entryId, itemId: item.id, checked: checked);
    void revert() => _set(_withItem(_current, blockId, item));
    if (await _outbox.hasPendingFor(arg.entryId)) return _queue(op, revert);
    try {
      final saved = await _repo.setItemChecked(id: item.id, checked: checked, opId: opId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      _refreshProgress();
      return TickOutcome.synced;
    } on PlanningNetwork {
      try {
        await _outbox.enqueue(CheckItemOp(
            opId: opId, relationshipId: arg.relationshipId, entryId: arg.entryId, itemId: item.id, checked: checked));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withItem(_current, blockId, item));
        rethrow;
      }
    } on PlanningError {
      if (state.hasValue) _set(_withItem(_current, blockId, item));
      rethrow;
    }
  }

  Future<TickOutcome> addItem(String blockId, String text, {String? section}) async {
    final id = _uuid.v4();
    final block = _current.blocks.firstWhere((b) => b.id == blockId);
    final afterId = block.items.isEmpty ? null : block.items.last.id;
    _set(_withBlockItems(_current, blockId, (items) => [...items, _localItem(id, text.trim(), section)]));
    if (await _outbox.hasPendingFor(arg.entryId)) {
      return _queue(
        AddItemOp(opId: id, relationshipId: arg.relationshipId, entryId: arg.entryId, itemId: id,
            blockId: blockId, text: text.trim(), section: section, afterId: afterId),
        () => _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i])),
      );
    }
    try {
      final saved = await _repo.addItem(id: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      _refreshProgress();
      return TickOutcome.synced;
    } on PlanningNetwork {
      try {
        await _outbox.enqueue(AddItemOp(opId: id, relationshipId: arg.relationshipId, entryId: arg.entryId,
            itemId: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i]));
        rethrow;
      }
    } on PlanningError {
      if (state.hasValue) _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i]));
      rethrow;
    }
  }

  /// Stale: the partner changed it first — adopt theirs and rethrow so the
  /// UI can say so. Not found: drop it.
  Future<void> updateItem(String blockId, PlanningItem item,
      {required String text, String? section, String? assignedTo, DateTime? dueDate}) async {
    try {
      final saved = await _repo.updateItem(
          id: item.id, version: item.version, text: text, section: section, assignedTo: assignedTo, dueDate: dueDate);
      _set(_withItem(_current, blockId, saved));
    } on PlanningStaleVersion catch (e) {
      _set(_withItem(_current, blockId, PlanningItem.fromJson(e.current)));
      rethrow;
    } on PlanningNotFound {
      _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != item.id) i]));
      rethrow;
    }
  }

  Future<void> deleteItem(String blockId, String itemId) async {
    final before = _current;
    _set(_withBlockItems(before, blockId, (items) => [for (final i in items) if (i.id != itemId) i]));
    try {
      await _repo.deleteItem(itemId);
    } on PlanningError {
      _set(before);
      rethrow;
    }
    if (_isExpenses(blockId)) await _refreshComputedQuietly();
    _refreshProgress();
  }

  Future<void> restoreItem(String blockId, String itemId, {required int index}) async {
    final restored = await _repo.restoreItem(itemId);
    _set(_withBlockItems(_current, blockId, (items) {
      final list = [for (final i in items) if (i.id != itemId) i];
      list.insert(index.clamp(0, list.length), restored);
      return list;
    }));
    if (_isExpenses(blockId)) await _refreshComputedQuietly();
  }

  // ---- blocks ----

  PlanningMediaGateway get _media => ref.read(planningMediaGatewayProvider);

  static Map<String, dynamic> _defaultPayload(PlanningBlockType type) => switch (type) {
        PlanningBlockType.text => {
            'delta': [{'insert': '\n'}]
          },
        PlanningBlockType.table => {
            'columns': [
              {'key': 'c0', 'label': 'Item', 'type': 'text'},
              {'key': 'c1', 'label': 'Notes', 'type': 'text'},
            ]
          },
        _ => <String, dynamic>{},
      };

  /// Link and Place need their [payload] (url / name) from the caller.
  /// Adds a block after [afterId] (where the cursor is), or at the end.
  Future<PlanningBlock> addBlock(PlanningBlockType type, {Map<String, dynamic>? payload, String? afterId}) async {
    final blocks = _current.blocks;
    final after = afterId ?? (blocks.isEmpty ? null : blocks.last.id);
    final block = await _repo.addBlock(
      id: _uuid.v4(),
      entryId: arg.entryId,
      type: type,
      payload: payload ?? _defaultPayload(type),
      afterId: after,
    );
    if (_alive && state.hasValue) {
      final list = [for (final b in _current.blocks) if (b.id != block.id) b];
      final i = after == null ? -1 : list.indexWhere((b) => b.id == after);
      list.insert(after == null ? 0 : (i < 0 ? list.length : i + 1), block);
      _set(_withBlocks(_current, list));
    }
    if (type == PlanningBlockType.link) _askForPreview(block.id);
    return block;
  }

  /// Inserting into the middle of a paragraph, as a word processor does:
  /// the text block keeps what came before the cursor, the new block goes
  /// next, and what came after the cursor follows in a new text block.
  Future<PlanningBlock> insertAtCursor(
    PlanningBlockType type, {
    required String textBlockId,
    required int version,
    required List<Map<String, dynamic>> before,
    required List<Map<String, dynamic>> after,
    Map<String, dynamic>? payload,
  }) async {
    final cut = await saveText(textBlockId, version, before);
    if (cut is! TextSaved) throw const PlanningStaleVersion({});
    final inserted = await addBlock(type, payload: payload, afterId: textBlockId);
    await addBlock(PlanningBlockType.text, payload: {'delta': after}, afterId: inserted.id);
    return inserted;
  }

  void _askForPreview(String blockId) =>
      unawaited(_media.requestLinkPreview(blockId).then((_) {}, onError: (Object _) {}));

  /// Title, table columns, link url/label, place. Stale: adopt theirs and
  /// rethrow so the UI can say so.
  Future<void> updateBlockPayload(PlanningBlock block, Map<String, dynamic> payload) async {
    try {
      final saved = await _repo.updateBlock(
          id: block.id, version: block.version, payload: payload, dateStart: block.dateStart, dateEnd: block.dateEnd);
      if (_alive && state.hasValue) _set(_withBlock(_current, saved));
      // A new address needs a preview; so does one whose preview never came
      // (a site that failed before can work now).
      if (block.type == PlanningBlockType.link &&
          (payload['url'] != block.linkUrl || !(block.linkPreview?.isOk ?? false))) {
        _askForPreview(block.id);
      }
    } on PlanningStaleVersion catch (e) {
      _set(_withBlock(_current, PlanningBlock.fromJson(e.current)));
      rethrow;
    }
  }

  /// Budget or numeric Progress target.
  Future<void> setTarget(PlanningBlock block, int? targetMinor, String? currency) async {
    try {
      final saved = await _repo.updateBlockTarget(
          id: block.id, version: block.version, targetMinor: targetMinor, currency: currency);
      _set(_withBlock(_current, saved));
    } on PlanningStaleVersion catch (e) {
      _set(_withBlock(_current, PlanningBlock.fromJson(e.current)));
      rethrow;
    }
  }

  /// Re-reads the plan so server-computed figures (budget spent, split
  /// balances) follow an expense change.
  Future<void> _refreshComputed() async {
    final fresh = await _repo.getEntry(arg.entryId);
    final pending = [for (final op in await _outbox.pending()) if (op.entryId == arg.entryId) op];
    if (_alive) _set(_overlay(fresh, pending));
  }

  /// Checklist ticks move checklist-mode Progress; re-read it in the
  /// background. Only the server-computed figures are taken from the
  /// re-read: items keep their on-screen state, so a tick made while the
  /// re-read was in flight never flickers back.
  void _refreshProgress() {
    if (!state.hasValue || !_current.blocks.any((b) => b.type == PlanningBlockType.progress)) return;
    unawaited(_repo.getEntry(arg.entryId).then((fresh) {
      if (!_alive || !state.hasValue) return;
      final computed = {for (final b in fresh.blocks) b.id: b.computed};
      _set(_withBlocks(_current, [
        for (final b in _current.blocks) computed.containsKey(b.id) ? b.copyWith(computed: computed[b.id]) : b
      ]));
    }, onError: (Object _) {}));
  }

  /// After a save that already succeeded: a failed re-read must not make
  /// the save look failed (the change signal re-reads again anyway).
  Future<void> _refreshComputedQuietly() async {
    try {
      await _refreshComputed();
    } catch (_) {}
  }

  bool _isExpenses(String blockId) =>
      _current.blocks.any((b) => b.id == blockId && b.type == PlanningBlockType.expenses);

  /// Table rows, expense lines, poll options, contributions. Creates when
  /// [existing] is null. Pass the same [id] when retrying a create so the
  /// server's idempotent create can't save it twice.
  Future<PlanningItem> saveRichItem(String blockId,
      {PlanningItem? existing, String? id, required Map<String, dynamic> fields}) async {
    final block = _current.blocks.firstWhere((b) => b.id == blockId);
    try {
      final saved = await _repo.saveRichItem(
        id: existing?.id ?? id ?? _uuid.v4(),
        blockId: blockId,
        version: existing?.version,
        fields: fields,
        afterId: existing == null && block.items.isNotEmpty ? block.items.last.id : null,
      );
      _set(existing == null && !block.items.any((i) => i.id == saved.id)
          ? _withBlockItems(_current, blockId, (items) => [...items, saved])
          : _withItem(_current, blockId, saved));
      if (block.type == PlanningBlockType.expenses || block.type == PlanningBlockType.progress) {
        await _refreshComputedQuietly();
      }
      return saved;
    } on PlanningStaleVersion catch (e) {
      _set(_withItem(_current, blockId, PlanningItem.fromJson(e.current)));
      rethrow;
    } on PlanningNotFound {
      if (existing != null) {
        _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != existing.id) i]));
      }
      rethrow;
    }
  }

  // ---- photos ----

  /// [jpeg] is already prepared (re-encoded, EXIF stripped) by the caller.
  Future<void> addPhoto(String blockId, Uint8List jpeg) async {
    final path = '${arg.relationshipId}/${arg.entryId}/${_uuid.v4()}.jpg';
    await _media.uploadJpeg(path, jpeg);
    final saved = await _repo.addPhoto(blockId, path);
    if (_alive && state.hasValue) _set(_withBlock(_current, saved));
  }

  Future<void> removePhoto(String blockId, String path) async {
    final saved = await _repo.removePhoto(blockId, path);
    if (_alive && state.hasValue) _set(_withBlock(_current, saved));
  }

  // ---- date poll ----

  /// Optimistic "works for me"; the server's poll replaces it.
  Future<void> vote(String blockId, PlanningItem option, bool works) async {
    final me = ref.read(planningCurrentUserIdProvider);
    final votes = [for (final v in option.votes) if (v != me) v, if (works && me != null) me];
    _set(_withItem(_current, blockId, option.withVotes(votes)));
    try {
      final saved = await _repo.votePoll(option.id, vote: works);
      if (_alive && state.hasValue) _set(_withBlock(_current, saved));
    } on PlanningError {
      if (state.hasValue) _set(_withItem(_current, blockId, option));
      rethrow;
    }
  }

  Future<void> addPollOption(String blockId, DateTime start, DateTime? end) => saveRichItem(blockId, fields: {
        'date_start': planningYmd(start),
        if (end != null && end != start) 'date_end': planningYmd(end),
      });

  /// The poll becomes a Date block; countdowns that follow the plan's date
  /// change with it, so the plan is re-read.
  Future<void> lockPoll(String blockId, String optionId) async {
    final saved = await _repo.lockPoll(blockId, optionId);
    if (!_alive || !state.hasValue) return;
    _set(_withBlock(_current, saved));
    await _refreshComputedQuietly();
  }

  // ---- split ----

  Future<void> setSplit(bool enabled) async {
    final e = await _repo.setEntrySplit(arg.entryId, enabled: enabled);
    if (_alive && state.hasValue) _set(_current.copyWith(entry: e));
  }

  Future<void> settleSplit() async {
    final e = await _repo.settleSplit(arg.entryId);
    if (_alive && state.hasValue) _set(_current.copyWith(entry: e));
  }

  Future<void> deleteBlock(String blockId) async {
    final before = _current;
    _set(_withBlocks(before, [for (final b in before.blocks) if (b.id != blockId) b]));
    try {
      await _repo.deleteBlock(blockId);
    } on PlanningError {
      _set(before);
      rethrow;
    }
  }

  Future<void> restoreBlock(String blockId, {required int index}) async {
    final restored = await _repo.restoreBlock(blockId);
    final list = [for (final b in _current.blocks) if (b.id != blockId) b];
    list.insert(index.clamp(0, list.length), restored);
    _set(_withBlocks(_current, list));
  }

  /// [newIndex] is the block's index after the move.
  Future<void> moveBlock(String blockId, int newIndex) async {
    final before = _current;
    final list = [...before.blocks];
    final moving = list.firstWhere((b) => b.id == blockId);
    list.remove(moving);
    final at = newIndex.clamp(0, list.length);
    list.insert(at, moving);
    _set(_withBlocks(before, list));
    try {
      await _repo.moveBlock(blockId, afterId: at == 0 ? null : list[at - 1].id);
    } on PlanningError {
      _set(before);
      rethrow;
    }
  }

  Future<void> setDate(PlanningBlock block, DateTime? start, DateTime? end) async {
    try {
      final saved = await _repo.updateBlock(
          id: block.id, version: block.version, payload: block.payload, dateStart: start, dateEnd: end);
      _set(_withBlock(_current, saved));
    } on PlanningStaleVersion catch (e) {
      _set(_withBlock(_current, PlanningBlock.fromJson(e.current)));
      rethrow;
    }
  }

  Future<TextSaveResult> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    try {
      final saved = await _repo.updateBlock(id: blockId, version: version, payload: {'delta': ops});
      _set(_withBlock(_current, saved));
      return TextSaved(saved);
    } on PlanningStaleVersion catch (e) {
      final theirs = PlanningBlock.fromJson(e.current);
      _set(_withBlock(_current, theirs));
      return TextConflict(theirs);
    } on PlanningNotFound {
      _set(_withBlocks(_current, [for (final b in _current.blocks) if (b.id != blockId) b]));
      return const TextGone();
    }
  }

  // ---- entry ----

  Future<void> rename(String title) async {
    final e = await _repo.updateEntry(id: arg.entryId, title: title, status: _current.entry.status);
    _set(_current.copyWith(entry: e));
  }

  Future<void> setStatus(String status) async {
    final e = await _repo.updateEntry(id: arg.entryId, title: _current.entry.title, status: status);
    _set(_current.copyWith(entry: e));
  }
}

final planningEntryProvider = AsyncNotifierProvider.autoDispose
    .family<PlanningEntryController, PlanningEntryDetail, PlanningEntryArgs>(PlanningEntryController.new);
