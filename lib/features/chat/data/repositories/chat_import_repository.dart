import 'package:attune/features/chat/domain/entities/chat_import.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chatImportRepositoryProvider = Provider<ChatImportRepository>((ref) {
  return ChatImportRepository(ref.watch(supabaseClientProvider));
});

class ChatImportRepository {
  ChatImportRepository(this._supabase);

  final SupabaseClient _supabase;

  Future<List<ChatImportRequest>> listRequests(String relationshipId) async {
    final rows = await _supabase
        .from('chat_import_requests')
        .select(
          'id,relationship_id,uploader_id,approver_id,policy_version,'
          'file_fingerprint,parsed_message_count,first_message_at,last_message_at,'
          'state,decided_at',
        )
        .eq('relationship_id', relationshipId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => ChatImportRequest.fromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ChatImportJob>> listJobs(String relationshipId) async {
    final rows = await _supabase
        .from('chat_import_jobs')
        .select('id,request_id,expected_count,imported_count,state')
        .eq('relationship_id', relationshipId)
        .order('started_at', ascending: false);
    return rows
        .map((row) => ChatImportJob.fromRow(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<String> createRequest({
    required String relationshipId,
    required String policyVersion,
    required ParsedChatImport parsed,
  }) async {
    final result = await _supabase.rpc(
      'create_chat_import_request',
      params: {
        'p_relationship_id': relationshipId,
        'p_policy_version': policyVersion,
        'p_file_fingerprint': parsed.fingerprint,
        'p_message_count': parsed.messages.length,
        'p_first_message_at': parsed.firstMessageAt.toUtc().toIso8601String(),
        'p_last_message_at': parsed.lastMessageAt.toUtc().toIso8601String(),
      },
    );
    return result as String;
  }

  Future<void> respond({
    required String requestId,
    required String policyVersion,
    required bool approve,
  }) async {
    await _supabase.rpc(
      'respond_to_chat_import_request',
      params: {
        'p_request_id': requestId,
        'p_action': approve ? 'granted' : 'declined',
        'p_policy_version': policyVersion,
      },
    );
  }

  Future<ChatImportJobProgress> uploadParsedMessages({
    required String requestId,
    required ParsedChatImport parsed,
    required Map<String, String> senderMapping,
    int batchSize = 250,
  }) async {
    // The sender mapping is confirmed explicitly by the uploader in the
    // preview UI (Spec 11.6) — the two export labels are each bound to a
    // distinct Attune member here. The server (ingest_chat_import_batch) can
    // only verify each mapped sender is one of the two relationship members;
    // it cannot detect a *swapped* mapping, because the true speaker of a
    // third-party export is unverifiable ground truth. That residual risk is
    // covered by the Spec 11.12 four-account gate test and by the reduced
    // interpretive confidence applied to import-sourced evidence (Spec 11.10),
    // not by a runtime check.
    if (senderMapping.keys.toSet().length != 2 ||
        !senderMapping.keys.toSet().containsAll(parsed.participantLabels) ||
        senderMapping.values.toSet().length != 2) {
      throw ArgumentError(
        'Map both participant labels to different Attune users.',
      );
    }

    ChatImportJobProgress? progress;
    for (var start = 0; start < parsed.messages.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, parsed.messages.length);
      final batch = parsed.messages
          .sublist(start, end)
          .map((message) => message.toServerJson(senderMapping))
          .toList(growable: false);
      final response = await _supabase.rpc(
        'ingest_chat_import_batch',
        params: {
          'p_request_id': requestId,
          'p_messages': batch,
          'p_is_final_batch': end == parsed.messages.length,
        },
      );
      final raw = response is List ? response.first : response;
      final row = Map<String, dynamic>.from(raw as Map);
      progress = ChatImportJobProgress(
        jobId: row['job_id'] as String,
        importedCount: (row['imported_count'] as num).toInt(),
        state: row['state'] as String,
      );
    }
    return progress!;
  }

  Future<void> deleteImport(String jobId, {bool revoke = false}) async {
    await _supabase.rpc(
      'delete_chat_import',
      params: {'p_job_id': jobId, 'p_revoke': revoke},
    );
  }

  Future<void> revokeRequest(String requestId) async {
    await _supabase.rpc(
      'revoke_chat_import_request',
      params: {'p_request_id': requestId},
    );
  }
}
