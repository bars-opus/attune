import 'dart:async';

import 'package:attune/features/planning/data/repositories/planning_repository.dart'
    show SupabasePlanningRpcGateway;
import 'package:attune/features/planning/presentation/providers/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/planning_v2_error.dart';
import '../data/planning_v2_models.dart';
import '../data/planning_v2_repository.dart';
import '../domain/planning_outbox.dart';

const _uuid = Uuid();

final planningV2RepositoryProvider = Provider<PlanningV2Repository>(
  (ref) => PlanningV2Repository(SupabasePlanningRpcGateway(Supabase.instance.client)),
);

final planningV2CurrentUserIdProvider =
    Provider<String?>((ref) => Supabase.instance.client.auth.currentUser?.id);

final planningV2OutboxStoreProvider = Provider<OutboxStore>((ref) => SharedPreferencesOutboxStore());

final planningV2OutboxSleepProvider =
    Provider<Future<void> Function(Duration)>((ref) => Future<void>.delayed);

/// One outbox for the app session (not autoDispose): queued ticks must
/// outlive the screen that made them.
final planningV2OutboxProvider = Provider<PlanningOutbox>((ref) {
  final repo = ref.watch(planningV2RepositoryProvider);
  return PlanningOutbox(
    store: ref.watch(planningV2OutboxStoreProvider),
    sleep: ref.watch(planningV2OutboxSleepProvider),
    send: (op) => switch (op) {
      CheckItemOp() => repo.setItemChecked(id: op.itemId, checked: op.checked, opId: op.opId),
      AddItemOp() => repo.addItem(
          id: op.itemId, blockId: op.blockId, text: op.text, section: op.section, afterId: op.afterId),
    },
  );
});

/// Change signal → refetch. The signal also fires on resubscribe and app
/// resume (v1 provider), which is when connectivity has likely returned,
/// so it is also the outbox replay trigger.
void _refetchOnSignal(Ref ref, String relationshipId, {bool replayOutbox = false}) {
  ref.listen(planningChangeSignalProvider(relationshipId), (_, __) {
    if (replayOutbox) {
      unawaited(ref.read(planningV2OutboxProvider).replay().then((r) {
        if (r.sent > 0 || r.dropped.isNotEmpty) ref.invalidateSelf();
      }));
    }
    ref.invalidateSelf();
  });
}

final planningV2HomeProvider =
    FutureProvider.autoDispose.family<List<PlanningCategory>, String>((ref, relationshipId) {
  _refetchOnSignal(ref, relationshipId);
  return ref.watch(planningV2RepositoryProvider).getHome(relationshipId);
});

// ---- entries list --------------------------------------------------------

typedef PlanningEntriesArgs = ({String relationshipId, String categoryId, String group});

class PlanningEntriesState {
  const PlanningEntriesState({
    required this.entries,
    required this.cursorAt,
    required this.cursorId,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<PlanningEntrySummary> entries;
  final DateTime? cursorAt;
  final String? cursorId;
  final bool loadingMore;
  final bool loadMoreFailed;

  bool get hasMore => cursorId != null;
}

/// Own pager rather than v1's PlanningKeysetPager: v1's refresh() resets
/// to a bare loading state, which drops visible content; spec §6.4
/// requires retained content during refresh (AsyncNotifier keeps the
/// previous value while reloading).
class PlanningEntriesController
    extends AutoDisposeFamilyAsyncNotifier<PlanningEntriesState, PlanningEntriesArgs> {
  @override
  Future<PlanningEntriesState> build(PlanningEntriesArgs arg) async {
    _refetchOnSignal(ref, arg.relationshipId);
    final page = await ref.read(planningV2RepositoryProvider).listEntries(arg.categoryId, group: arg.group);
    return PlanningEntriesState(entries: page.entries, cursorAt: page.nextCursorAt, cursorId: page.nextCursorId);
  }

  Future<void> loadMore() async {
    final s = state.valueOrNull;
    if (s == null || s.loadingMore || !s.hasMore) return;
    state = AsyncData(PlanningEntriesState(
        entries: s.entries, cursorAt: s.cursorAt, cursorId: s.cursorId, loadingMore: true));
    try {
      final page = await ref.read(planningV2RepositoryProvider).listEntries(
          arg.categoryId, group: arg.group, cursorAt: s.cursorAt, cursorId: s.cursorId);
      state = AsyncData(PlanningEntriesState(
          entries: [...s.entries, ...page.entries], cursorAt: page.nextCursorAt, cursorId: page.nextCursorId));
    } on PlanningV2Error {
      state = AsyncData(PlanningEntriesState(
          entries: s.entries, cursorAt: s.cursorAt, cursorId: s.cursorId, loadMoreFailed: true));
    }
  }
}

final planningV2EntriesProvider = AsyncNotifierProvider.autoDispose
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
  PlanningV2Repository get _repo => ref.read(planningV2RepositoryProvider);
  PlanningOutbox get _outbox => ref.read(planningV2OutboxProvider);

  @override
  Future<PlanningEntryDetail> build(PlanningEntryArgs arg) async {
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

  Future<TickOutcome> setChecked(String blockId, PlanningItem item, bool checked) async {
    final me = ref.read(planningV2CurrentUserIdProvider);
    _set(_withItem(_current, blockId,
        checked ? item.copyWith(checkedAt: DateTime.now(), checkedBy: me) : item.copyWith(clearChecked: true)));
    final opId = _uuid.v4();
    try {
      final saved = await _repo.setItemChecked(id: item.id, checked: checked, opId: opId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      return TickOutcome.synced;
    } on PlanningV2Network {
      try {
        await _outbox.enqueue(CheckItemOp(
            opId: opId, relationshipId: arg.relationshipId, entryId: arg.entryId, itemId: item.id, checked: checked));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withItem(_current, blockId, item));
        rethrow;
      }
    } on PlanningV2Error {
      if (state.hasValue) _set(_withItem(_current, blockId, item));
      rethrow;
    }
  }

  Future<TickOutcome> addItem(String blockId, String text, {String? section}) async {
    final id = _uuid.v4();
    final block = _current.blocks.firstWhere((b) => b.id == blockId);
    final afterId = block.items.isEmpty ? null : block.items.last.id;
    _set(_withBlockItems(_current, blockId, (items) => [...items, _localItem(id, text.trim(), section)]));
    try {
      final saved = await _repo.addItem(id: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId);
      if (state.hasValue) _set(_withItem(_current, blockId, saved));
      return TickOutcome.synced;
    } on PlanningV2Network {
      try {
        await _outbox.enqueue(AddItemOp(opId: id, relationshipId: arg.relationshipId, entryId: arg.entryId,
            itemId: id, blockId: blockId, text: text.trim(), section: section, afterId: afterId));
        return TickOutcome.queued;
      } on OutboxFullException {
        if (state.hasValue) _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != id) i]));
        rethrow;
      }
    } on PlanningV2Error {
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
    } on PlanningV2StaleVersion catch (e) {
      _set(_withItem(_current, blockId, PlanningItem.fromJson(e.current)));
      rethrow;
    } on PlanningV2NotFound {
      _set(_withBlockItems(_current, blockId, (items) => [for (final i in items) if (i.id != item.id) i]));
      rethrow;
    }
  }

  Future<void> deleteItem(String blockId, String itemId) async {
    final before = _current;
    _set(_withBlockItems(before, blockId, (items) => [for (final i in items) if (i.id != itemId) i]));
    try {
      await _repo.deleteItem(itemId);
    } on PlanningV2Error {
      _set(before);
      rethrow;
    }
  }

  Future<void> restoreItem(String blockId, String itemId, {required int index}) async {
    final restored = await _repo.restoreItem(itemId);
    _set(_withBlockItems(_current, blockId, (items) {
      final list = [for (final i in items) if (i.id != itemId) i];
      list.insert(index.clamp(0, list.length), restored);
      return list;
    }));
  }

  // ---- blocks ----

  static Map<String, dynamic> _defaultPayload(PlanningBlockType type) => switch (type) {
        PlanningBlockType.text => {
            'delta': [{'insert': '\n'}]
          },
        _ => <String, dynamic>{},
      };

  Future<PlanningBlock> addBlock(PlanningBlockType type) async {
    final blocks = _current.blocks;
    final block = await _repo.addBlock(
      id: _uuid.v4(),
      entryId: arg.entryId,
      type: type,
      payload: _defaultPayload(type),
      afterId: blocks.isEmpty ? null : blocks.last.id,
    );
    _set(_withBlocks(_current, [..._current.blocks, block]));
    return block;
  }

  Future<void> deleteBlock(String blockId) async {
    final before = _current;
    _set(_withBlocks(before, [for (final b in before.blocks) if (b.id != blockId) b]));
    try {
      await _repo.deleteBlock(blockId);
    } on PlanningV2Error {
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
    } on PlanningV2Error {
      _set(before);
      rethrow;
    }
  }

  Future<void> setDate(PlanningBlock block, DateTime? start, DateTime? end) async {
    try {
      final saved = await _repo.updateBlock(
          id: block.id, version: block.version, payload: block.payload, dateStart: start, dateEnd: end);
      _set(_withBlock(_current, saved));
    } on PlanningV2StaleVersion catch (e) {
      _set(_withBlock(_current, PlanningBlock.fromJson(e.current)));
      rethrow;
    }
  }

  Future<TextSaveResult> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    try {
      final saved = await _repo.updateBlock(id: blockId, version: version, payload: {'delta': ops});
      _set(_withBlock(_current, saved));
      return TextSaved(saved);
    } on PlanningV2StaleVersion catch (e) {
      final theirs = PlanningBlock.fromJson(e.current);
      _set(_withBlock(_current, theirs));
      return TextConflict(theirs);
    } on PlanningV2NotFound {
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

final planningV2EntryProvider = AsyncNotifierProvider.autoDispose
    .family<PlanningEntryController, PlanningEntryDetail, PlanningEntryArgs>(PlanningEntryController.new);
