abstract class ChatCacheBackend {
  Future<void> init();

  Future<String?> readMessages(String userId, String relationshipId);
  Future<void> writeMessages(
    String userId,
    String relationshipId,
    String payload,
  );
  Future<void> deleteMessages(String userId, String relationshipId);

  Future<String?> readConversations(String userId);
  Future<void> writeConversations(String userId, String payload);

  Future<List<String>> readOutbox(String userId, {String? relationshipId});
  Future<void> putOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
    String payload,
    int createdAtMillis,
  );
  Future<void> removeOutbox(
    String userId,
    String relationshipId,
    String clientMessageId,
  );
  Future<List<({String relationshipId, String clientMessageId})>> oldestOutbox(
    String userId,
    int limit,
  );
  Future<void> purgeOutboxForRelationship(String userId, String relationshipId);

  Future<String?> readDraft(String userId, String relationshipId);
  Future<void> writeDraft(String userId, String relationshipId, String draft);
  Future<void> clearDraft(String userId, String relationshipId);

  Future<void> clearAll();
}
