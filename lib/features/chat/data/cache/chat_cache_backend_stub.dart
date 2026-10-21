import 'chat_cache_backend_base.dart';

class _MemoryChatCacheBackend implements ChatCacheBackend {
  final Map<String, String> _messages = <String, String>{};
  final Map<String, String> _conversations = <String, String>{};
  final Map<String, ({String payload, int createdAtMillis})> _outbox =
      <String, ({String payload, int createdAtMillis})>{};
  final Map<String, String> _drafts = <String, String>{};
  final Map<String, ({int micros, String? id})> _syncCursors =
      <String, ({int micros, String? id})>{};

  bool _wipeOnOpen = false;

  @override
  Future<void> init() async {
    if (!_wipeOnOpen) return;
    await reset();
    _wipeOnOpen = false;
  }

  @override
  Future<void> requestWipeOnNextOpen() async {
    _wipeOnOpen = true;
  }

  @override
  Future<void> reset() async {
    _messages.clear();
    _conversations.clear();
    _outbox.clear();
    _drafts.clear();
    _syncCursors.clear();
  }

  @override
  Future<String?> readMessages(String userId, String relationshipId) async {
    return _messages[_messageKey(userId, relationshipId)];
  }

  @override
  Future<void> writeMessages(
    String userId,
    String relationshipId,
    String payload,
  ) async {
    _messages[_messageKey(userId, relationshipId)] = payload;
  }

  @override
  Future<void> deleteMessages(String userId, String relationshipId) async {
    _messages.remove(_messageKey(userId, relationshipId));
  }

  @override
  Future<String?> readConversations(String userId) async {
    return _conversations[_conversationKey(userId)];
  }

  @override
  Future<void> writeConversations(String userId, String payload) async {
    _conversations[_conversationKey(userId)] = payload;
  }

  @override
  Future<List<String>> readOutbox(
    String userId, {
    String? relationshipId,
  }) async {
    final prefix =
        relationshipId == null ? '$userId:' : '$userId:$relationshipId:';
    final entries =
        _outbox.entries.where((entry) => entry.key.startsWith(prefix)).toList()
          ..sort(
            (a, b) =>
                a.value.createdAtMillis.compareTo(b.value.createdAtMillis),
          );
    return entries.map((entry) => entry.value.payload).toList();
  }

  @override
  Future<void> putOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
    String payload,
    int createdAtMillis,
  ) async {
    _outbox[_outboxKey(userId, relationshipId, clientMessageId)] = (
      payload: payload,
      createdAtMillis: createdAtMillis,
    );
  }

  @override
  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) async {
    _outbox.remove(_outboxKey(userId, relationshipId, clientMessageId));
  }

  @override
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String userId,
    int limit,
  ) async {
    final rows =
        _outbox.entries
            .where((entry) => entry.key.startsWith('$userId:'))
            .toList()
          ..sort(
            (a, b) =>
                a.value.createdAtMillis.compareTo(b.value.createdAtMillis),
          );
    return rows.take(limit).map((entry) {
      final parts = entry.key.split(':');
      return (relationshipId: parts[1], clientMessageId: parts[2]);
    }).toList();
  }

  @override
  Future<void> purgeOutboxForRelationship(
    String userId,
    String relationshipId,
  ) async {
    final prefix = '$userId:$relationshipId:';
    _outbox.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<String?> readDraft(String userId, String relationshipId) async {
    return _drafts[_draftKey(userId, relationshipId)];
  }

  @override
  Future<void> writeDraft(
    String userId,
    String relationshipId,
    String draft,
  ) async {
    _drafts[_draftKey(userId, relationshipId)] = draft;
  }

  @override
  Future<void> clearDraft(String userId, String relationshipId) async {
    _drafts.remove(_draftKey(userId, relationshipId));
  }

  @override
  Future<({int micros, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  ) async {
    return _syncCursors[_messageKey(userId, relationshipId)];
  }

  @override
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    int micros,
    String? id,
  ) async {
    _syncCursors[_messageKey(userId, relationshipId)] = (
      micros: micros,
      id: id,
    );
  }

  @override
  Future<void> clearSyncCursor(String userId, String relationshipId) async {
    _syncCursors.remove(_messageKey(userId, relationshipId));
  }

  @override
  Future<void> clearAll() async {
    _messages.clear();
    _conversations.clear();
    _outbox.clear();
    _drafts.clear();
    _syncCursors.clear();
  }

  String _messageKey(String userId, String relationshipId) =>
      '$userId:$relationshipId';
  String _conversationKey(String userId) => 'conversations:$userId';
  String _outboxKey(
    String userId,
    String relationshipId,
    String clientMessageId,
  ) => '$userId:$relationshipId:$clientMessageId';
  String _draftKey(String userId, String relationshipId) =>
      'draft:$userId:$relationshipId';
}

ChatCacheBackend createBackend() => _MemoryChatCacheBackend();
