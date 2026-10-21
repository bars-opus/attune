/// Why [ChatCacheBackend.init] failed — it decides whether deleting the
/// store is safe (Spec 16: rebuild the read cache, preserve a recoverable
/// queue).
enum ChatCacheFailureKind {
  /// The file is not a readable database (SQLITE_CORRUPT, SQLITE_NOTADB):
  /// nothing in it can be recovered, so it is deleted and recreated.
  corrupt,

  /// Another connection holds it (SQLITE_BUSY, SQLITE_LOCKED): retried.
  busy,

  /// Anything else (I/O, a schema step, the platform directory): the file
  /// may still hold a recoverable queue, so it is left alone.
  other,
}

/// A classified [ChatCacheBackend.init] failure. Carries only the cause's
/// type in [toString] — never a path or content.
class ChatCacheOpenException implements Exception {
  const ChatCacheOpenException(this.kind, this.cause);

  final ChatCacheFailureKind kind;
  final Object cause;

  @override
  String toString() =>
      'ChatCacheOpenException(${kind.name}, ${cause.runtimeType})';
}

abstract class ChatCacheBackend {
  /// Opens the store. A failure the backend can classify is thrown as a
  /// [ChatCacheOpenException]; anything else counts as
  /// [ChatCacheFailureKind.other].
  Future<void> init();

  /// Closes and deletes the store so the next [init] starts from nothing.
  /// Throws when the store could not be deleted. Used when [init] reports
  /// [ChatCacheFailureKind.corrupt] (the file's queue and drafts were
  /// unreadable anyway; the read cache rebuilds from the server), and to
  /// wipe a store whose rows cannot be cleared at sign-out.
  Future<void> reset();

  /// Persists a marker so the next [init] deletes the store before opening
  /// it — for a sign-out wipe that [reset] cannot do right now. An [init]
  /// that cannot honour the marker fails rather than open the old store.
  Future<void> requestWipeOnNextOpen();

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

  /// The changes-since sync cursor per (user, relationship): the server
  /// `updated_at` (microseconds since epoch) and id of the newest change
  /// applied. A timestamp and a row id, never content. [id] is null for a
  /// cursor seeded from a first page.
  Future<({int micros, String? id})?> readSyncCursor(
    String userId,
    String relationshipId,
  );
  Future<void> writeSyncCursor(
    String userId,
    String relationshipId,
    int micros,
    String? id,
  );
  Future<void> clearSyncCursor(String userId, String relationshipId);

  Future<void> clearAll();
}
