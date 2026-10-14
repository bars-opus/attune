import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/planning/domain/delta_sanitizer.dart';
import 'package:attune/features/reflection_journal/data/journal_media.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:attune/features/reflection_journal/data/repositories/reflection_journal_repository.dart';

const fakeJournalUser = 'user-ama';

/// An in-memory journal with the server's rules (owner-only by
/// construction: there is only one person here).
class FakeJournalRepository implements ReflectionJournalRepository {
  FakeJournalRepository({DateTime? now}) : now = now ?? DateTime(2026, 11, 20, 15);
  final DateTime now;
  final entries = <String, JournalEntry>{};
  final blocks = <String, List<JournalBlock>>{};
  final softDeleted = <String>{};
  final purged = <String>[];
  final analysed = <String>[];
  final saves = <String>[];
  int sweeps = 0;
  bool conflictNext = false;

  /// When set, text saves wait for it (a slow network).
  Completer<void>? saveGate;
  JournalAnalysis? analysisFor;
  var _n = 0;
  String _id(String p) => '$p-${++_n}';

  JournalEntry addEntry({String? title, required String text, DateTime? createdAt, bool pinned = false, bool photo = false}) {
    final id = _id('e');
    final at = createdAt ?? now;
    entries[id] = JournalEntry(
      id: id, userId: fakeJournalUser, content: text.trim(), createdAt: at, updatedAt: at,
      title: title, pinnedAt: pinned ? at : null,
    );
    blocks[id] = [
      _text(id, 0, [{'insert': '$text\n'}]),
      if (photo) JournalBlock(id: _id('b'), entryId: id, position: 1, kind: 'photo',
          payload: {'path': '$fakeJournalUser/$id/p.jpg'}, version: 1),
    ];
    return entries[id]!;
  }

  JournalBlock _text(String entryId, int position, List<Map<String, dynamic>> ops, {int version = 1}) =>
      JournalBlock(id: _id('b'), entryId: entryId, position: position, kind: 'text',
          payload: {'delta': ops}, plainText: deltaPlainText(ops), version: version);

  void _renumber(String entryId) {
    final list = blocks[entryId]!;
    blocks[entryId] = [for (var i = 0; i < list.length; i++) list[i].withPosition(i)];
    final text = [
      for (final b in blocks[entryId]!)
        if (b.isText && (b.plainText ?? '').trim().isNotEmpty) b.plainText!.trimRight(),
    ].join('\n\n');
    entries[entryId] = entries[entryId]!.copyWith(content: text);
  }

  JournalEntrySummary _summary(JournalEntry e) => JournalEntrySummary(
    id: e.id, title: e.title, snippet: journalSnippet(e.content),
    hasPhoto: blocks[e.id]!.any((b) => b.isPhoto), pinned: e.pinnedAt != null, tone: e.tone,
    createdAt: e.createdAt, updatedAt: e.updatedAt,
  );

  Iterable<JournalEntry> get _live => entries.values.where((e) => !softDeleted.contains(e.id));

  @override
  Future<JournalListPage> listEntries({DateTime? before, int limit = 30}) async {
    final rows = _live.where((e) => e.pinnedAt == null && (before == null || e.createdAt.isBefore(before))).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return JournalListPage(
      pinned: before != null ? const [] : [for (final e in _live.where((e) => e.pinnedAt != null)) _summary(e)],
      entries: [for (final e in rows.take(limit)) _summary(e)],
      hasMore: rows.length > limit,
    );
  }

  @override
  Future<JournalEntryDetail> createEntryV2({String? promptUsed}) async {
    final id = _id('e');
    entries[id] = JournalEntry(id: id, userId: fakeJournalUser, content: '', promptUsed: promptUsed, createdAt: now, updatedAt: now);
    blocks[id] = [_text(id, 0, [{'insert': '\n'}])];
    return getEntryDetail(id);
  }

  @override
  Future<JournalEntryDetail> getEntryDetail(String entryId) async {
    if (!entries.containsKey(entryId) || softDeleted.contains(entryId)) throw const JournalNotFound();
    return JournalEntryDetail(entry: entries[entryId]!, blocks: List.of(blocks[entryId]!), analysis: analysisFor);
  }

  @override
  Future<JournalEntry> rename(String entryId, String? title) async {
    final t = title?.trim();
    entries[entryId] = entries[entryId]!.copyWith(title: t, clearTitle: t == null || t.isEmpty);
    return entries[entryId]!;
  }

  @override
  Future<void> setPinned(String entryId, bool pinned) async {
    entries[entryId] = entries[entryId]!.copyWith(pinnedAt: pinned ? now : null, clearPinned: !pinned);
  }

  @override
  Future<({String status, JournalBlock block})> saveText(String blockId, int version, List<Map<String, dynamic>> ops) async {
    await saveGate?.future;
    final entryId = blocks.entries.firstWhere((x) => x.value.any((b) => b.id == blockId), orElse: () => throw const JournalNotFound()).key;
    final list = blocks[entryId]!;
    final i = list.indexWhere((b) => b.id == blockId);
    if (conflictNext) {
      conflictNext = false;
      final theirs = _text(entryId, i, [{'insert': 'From my other phone\n'}], version: list[i].version + 1);
      list[i] = JournalBlock(id: blockId, entryId: entryId, position: i, kind: 'text', payload: theirs.payload,
          plainText: theirs.plainText, version: theirs.version);
      return (status: 'conflict', block: list[i]);
    }
    list[i] = JournalBlock(id: blockId, entryId: entryId, position: i, kind: 'text', payload: {'delta': ops},
        plainText: deltaPlainText(ops), version: version + 1);
    saves.add(deltaPlainText(ops).trim());
    _renumber(entryId);
    return (status: 'saved', block: blocks[entryId]![i]);
  }

  @override
  Future<JournalBlock> insertBlock(String entryId, {String? afterId, required String kind, required Map<String, dynamic> payload}) async {
    final list = blocks[entryId]!;
    if (list.length >= 50 || (kind == 'photo' && list.where((b) => b.isPhoto).length >= 10)) throw const JournalLimitReached();
    final at = afterId == null ? list.length : list.indexWhere((b) => b.id == afterId) + 1;
    final b = kind == 'text'
        ? _text(entryId, at, [for (final op in payload['delta'] as List) Map<String, dynamic>.from(op as Map)])
        : JournalBlock(id: _id('b'), entryId: entryId, position: at, kind: 'photo', payload: payload, version: 1);
    list.insert(at, b);
    _renumber(entryId);
    return b;
  }

  @override
  Future<void> deleteBlock(String blockId) async {
    for (final e in blocks.entries) {
      e.value.removeWhere((b) => b.id == blockId);
      _renumber(e.key);
    }
  }

  @override
  Future<void> moveBlock(String blockId, int to) async {
    for (final e in blocks.entries) {
      final i = e.value.indexWhere((b) => b.id == blockId);
      if (i < 0) continue;
      final b = e.value.removeAt(i);
      e.value.insert(to.clamp(0, e.value.length), b);
      _renumber(e.key);
    }
  }

  @override
  Future<void> deleteEntry(String entryId) async => softDeleted.add(entryId);
  @override
  Future<void> restoreEntry(String entryId) async => softDeleted.remove(entryId);
  @override
  Future<void> purgeEntry(String entryId) async {
    purged.add(entryId);
    entries.remove(entryId);
    blocks.remove(entryId);
    softDeleted.remove(entryId);
  }

  @override
  Future<int> purgeMyDeleted() async {
    sweeps++;
    return 0;
  }

  @override
  Future<JournalAnalysis> analyseEntry(String entryId) async {
    analysed.add(entryId);
    return JournalAnalysis.fromJson(const {'status': 'pending'});
  }

  @override
  Future<List<JournalEntry>> getEntries() async => _live.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<({String status, String? summary, int entryCount})> getPatterns() async =>
      (status: 'insufficient_evidence', summary: null, entryCount: entries.length);
}

class FakeJournalMedia implements JournalMediaGateway {
  final uploads = <String>[];
  bool fail = false;
  @override
  Future<void> uploadJpeg(String path, Uint8List bytes) async {
    if (fail) throw Exception('offline');
    uploads.add(path);
  }

  @override
  Future<String> signedUrl(String path) async => 'https://example.invalid/$path';
}
