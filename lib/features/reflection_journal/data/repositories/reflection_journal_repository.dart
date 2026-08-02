import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<JournalEntry> getEntry(String entryId) async {
    final response = await _supabase
        .from('reflection_journal_entries')
        .select('*')
        .eq('id', entryId)
        .single();

    return JournalEntry.fromJson(response);
  }

  Future<String> createEntry({
    required String content,
    String? promptUsed,
  }) async {
    final entryId = await _supabase.rpc(
      'create_journal_entry',
      params: {'p_content': content, 'p_prompt_used': promptUsed},
    );
    return entryId as String;
  }

  Future<void> updateEntry({
    required String entryId,
    required String content,
  }) async {
    await _supabase.rpc(
      'update_journal_entry',
      params: {'p_entry_id': entryId, 'p_content': content},
    );
  }

  Future<void> deleteEntry(String entryId) async {
    await _supabase.rpc(
      'delete_journal_entry',
      params: {'p_entry_id': entryId},
    );
  }

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
}
