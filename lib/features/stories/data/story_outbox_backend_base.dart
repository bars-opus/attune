/// Storage seam for [StoryOutboxStore] (spec §6.1), mirroring
/// `chat_cache_backend_base.dart`'s split: a platform-agnostic interface,
/// a `dart:io` Drift/SQLite implementation, and an in-memory stub for
/// platforms/tests without it.
abstract class StoryOutboxBackend {
  Future<void> init();

  /// All records for [userId], oldest first by `createdAt` — the order a
  /// single-item-at-a-time queue should process them in.
  Future<List<String>> readAll(String userId);

  /// Insert-or-replace keyed on `(userId, clientStoryId)`. `clientStoryId`
  /// is the whole point: the same id across retries updates the same row
  /// rather than creating a new one. [createdAtMillis] is the record's own
  /// domain `createdAt` (epoch millis) — the ordering column Task 6's FIFO
  /// drain relies on — not wall-clock write time; a retry's `put` reuses
  /// the same value the record was enqueued with, same as `chat_outbox`
  /// (`chat_cache_service.dart:154` passes `send.createdAt...`, not
  /// `DateTime.now()`).
  Future<void> put(
    String userId,
    String clientStoryId,
    String payload,
    int createdAtMillis,
  );

  Future<void> remove(String userId, String clientStoryId);

  Future<void> clearAll();

  /// Closes the backend's connection, if it holds one. The `dart:io`
  /// backend closes its Drift/SQLite connection; the in-memory stub is a
  /// no-op. Exists so a durability test can close-and-reopen a real
  /// connection against the same file rather than proving persistence
  /// against a connection that was simply never dropped.
  Future<void> close();
}
