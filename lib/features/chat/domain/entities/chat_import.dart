class ParsedChatImport {
  final String source;
  final String fingerprint;
  final List<String> participantLabels;
  final List<ParsedChatImportMessage> messages;

  const ParsedChatImport({
    required this.source,
    required this.fingerprint,
    required this.participantLabels,
    required this.messages,
  });

  DateTime get firstMessageAt => messages.first.createdAt;
  DateTime get lastMessageAt => messages.last.createdAt;
}

class ParsedChatImportMessage {
  final int sourceLine;
  final DateTime createdAt;
  final String senderLabel;
  final String content;

  const ParsedChatImportMessage({
    required this.sourceLine,
    required this.createdAt,
    required this.senderLabel,
    required this.content,
  });

  Map<String, dynamic> toServerJson(Map<String, String> senderMapping) {
    final senderId = senderMapping[senderLabel];
    if (senderId == null) {
      throw StateError('Every participant label must be mapped explicitly.');
    }
    return {
      'line': sourceLine,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sender_id': senderId,
      'content': content,
    };
  }
}

enum ChatImportRequestState {
  pendingPartnerConsent,
  approved,
  declined,
  processing,
  processingSafety,
  completed,
  failed,
  revoked,
  deleted,
}

class ChatImportRequest {
  final String id;
  final String relationshipId;
  final String uploaderId;
  final String approverId;
  final String policyVersion;
  final String fileFingerprint;
  final int parsedMessageCount;
  final DateTime firstMessageAt;
  final DateTime lastMessageAt;
  final ChatImportRequestState state;
  final DateTime? decidedAt;

  const ChatImportRequest({
    required this.id,
    required this.relationshipId,
    required this.uploaderId,
    required this.approverId,
    required this.policyVersion,
    required this.fileFingerprint,
    required this.parsedMessageCount,
    required this.firstMessageAt,
    required this.lastMessageAt,
    required this.state,
    this.decidedAt,
  });

  factory ChatImportRequest.fromRow(Map<String, dynamic> row) {
    return ChatImportRequest(
      id: row['id'] as String,
      relationshipId: row['relationship_id'] as String,
      uploaderId: row['uploader_id'] as String,
      approverId: row['approver_id'] as String,
      policyVersion: row['policy_version'] as String,
      fileFingerprint: row['file_fingerprint'] as String,
      parsedMessageCount: (row['parsed_message_count'] as num).toInt(),
      firstMessageAt:
          DateTime.parse(row['first_message_at'] as String).toLocal(),
      lastMessageAt: DateTime.parse(row['last_message_at'] as String).toLocal(),
      state: _parseState(row['state'] as String),
      decidedAt:
          row['decided_at'] == null
              ? null
              : DateTime.parse(row['decided_at'] as String).toLocal(),
    );
  }

  static ChatImportRequestState _parseState(String value) {
    return switch (value) {
      'pending_partner_consent' => ChatImportRequestState.pendingPartnerConsent,
      'approved' => ChatImportRequestState.approved,
      'declined' => ChatImportRequestState.declined,
      'processing' => ChatImportRequestState.processing,
      'processing_safety' => ChatImportRequestState.processingSafety,
      'completed' => ChatImportRequestState.completed,
      'failed' => ChatImportRequestState.failed,
      'revoked' => ChatImportRequestState.revoked,
      'deleted' => ChatImportRequestState.deleted,
      _ => throw FormatException('Unknown import request state.'),
    };
  }
}

class ChatImportJob {
  final String id;
  final String requestId;
  final int expectedCount;
  final int importedCount;
  final String state;

  const ChatImportJob({
    required this.id,
    required this.requestId,
    required this.expectedCount,
    required this.importedCount,
    required this.state,
  });

  factory ChatImportJob.fromRow(Map<String, dynamic> row) => ChatImportJob(
    id: row['id'] as String,
    requestId: row['request_id'] as String,
    expectedCount: (row['expected_count'] as num).toInt(),
    importedCount: (row['imported_count'] as num).toInt(),
    state: row['state'] as String,
  );
}

class ChatImportJobProgress {
  final String jobId;
  final int importedCount;
  final String state;

  const ChatImportJobProgress({
    required this.jobId,
    required this.importedCount,
    required this.state,
  });
}
