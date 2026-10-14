import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JournalNotFound implements Exception {
  const JournalNotFound();
}

class JournalLimitReached implements Exception {
  const JournalLimitReached();
}

class JournalTooLong implements Exception {
  const JournalTooLong();
}

class ReflectionJournalRepository {
  ReflectionJournalRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<JournalEntry>> getEntries() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _supabase
        .from('reflection_journal_entries')
        .select('*')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => JournalEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Hidden (soft delete) so Undo can bring it back; purged after.
  Future<void> deleteEntry(String entryId) => _rpc('delete_journal_entry', {'p_entry_id': entryId});

  Future<JournalAnalysis> analyseEntry(String entryId) async {
    final response = await _supabase.functions.invoke(
      'analyse-journal-entry',
      body: {'action': 'analyse_entry', 'entry_id': entryId},
    );
    return JournalAnalysis.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<({String status, String? summary, int entryCount})>
  getPatterns() async {
    final response = await _supabase.functions.invoke(
      'analyse-journal-entry',
      body: {'action': 'get_patterns'},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return (
      status: data['status'] as String,
      summary: data['summary'] as String?,
      entryCount: data['entry_count'] as int? ?? 0,
    );
  }

  Future<dynamic> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      return await _supabase.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      final m = e.message;
      if (m.contains('journal:not_found')) throw const JournalNotFound();
      if (m.contains('journal:limit')) throw const JournalLimitReached();
      if (m.contains('journal:too_long')) throw const JournalTooLong();
      rethrow;
    }
  }

  Map<String, dynamic> _map(dynamic v) => Map<String, dynamic>.from(v as Map);

  Future<JournalListPage> listEntries({DateTime? before, int limit = 30}) async => JournalListPage.fromJson(
    _map(await _rpc('list_journal_entries', {'p_before': before?.toUtc().toIso8601String(), 'p_limit': limit})),
  );

  Future<JournalEntryDetail> createEntryV2({String? promptUsed}) async =>
      JournalEntryDetail.fromJson(_map(await _rpc('create_journal_entry_v2', {'p_prompt_used': promptUsed})));

  Future<JournalEntryDetail> getEntryDetail(String entryId) async =>
      JournalEntryDetail.fromJson(_map(await _rpc('get_journal_entry', {'p_entry_id': entryId})));

  Future<JournalEntry> rename(String entryId, String? title) async =>
      JournalEntry.fromJson(_map(await _rpc('rename_journal_entry', {'p_entry_id': entryId, 'p_title': title})));

  Future<void> setPinned(String entryId, bool pinned) =>
      _rpc('set_journal_pin', {'p_entry_id': entryId, 'p_pinned': pinned});

  Future<({String status, JournalBlock block})> saveText(
    String blockId,
    int version,
    List<Map<String, dynamic>> ops,
  ) async {
    final r = _map(await _rpc('save_journal_text', {'p_block_id': blockId, 'p_version': version, 'p_delta': ops}));
    return (status: r['status'] as String, block: JournalBlock.fromJson(_map(r['block'])));
  }

  Future<JournalBlock> insertBlock(
    String entryId, {
    String? afterId,
    required String kind,
    required Map<String, dynamic> payload,
  }) async => JournalBlock.fromJson(_map(await _rpc('insert_journal_block', {
    'p_entry_id': entryId,
    'p_after': afterId,
    'p_kind': kind,
    'p_payload': payload,
  })));

  Future<void> deleteBlock(String blockId) => _rpc('delete_journal_block', {'p_block_id': blockId});

  Future<void> moveBlock(String blockId, int to) => _rpc('move_journal_block', {'p_block_id': blockId, 'p_to': to});

  Future<void> restoreEntry(String entryId) => _rpc('restore_journal_entry', {'p_entry_id': entryId});

  Future<void> purgeEntry(String entryId) => _rpc('purge_journal_entry', {'p_entry_id': entryId});

  Future<int> purgeMyDeleted() async => (await _rpc('purge_my_deleted_journal_entries', const {}) as num).toInt();
}
