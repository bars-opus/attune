import 'story_outbox_backend_base.dart';

/// In-memory backend for platforms without `dart:io` (mirrors
/// `chat_cache_backend_stub.dart`). Not durable across restart by
/// construction — production always resolves to the `dart:io` backend on
/// the platforms this feature ships to (iOS/Android), same as chat's.
class _MemoryStoryOutboxBackend implements StoryOutboxBackend {
  final Map<String, ({String payload, int createdAtMillis})> _rows =
      <String, ({String payload, int createdAtMillis})>{};

  @override
  Future<void> init() async {}

  @override
  Future<List<String>> readAll(String userId) async {
    final entries =
        _rows.entries.where((e) => e.key.startsWith('$userId:')).toList()
          ..sort(
            (a, b) =>
                a.value.createdAtMillis.compareTo(b.value.createdAtMillis),
          );
    return entries.map((e) => e.value.payload).toList();
  }

  @override
  Future<void> put(String userId, String clientStoryId, String payload) async {
    _rows['$userId:$clientStoryId'] = (
      payload: payload,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> remove(String userId, String clientStoryId) async {
    _rows.remove('$userId:$clientStoryId');
  }

  @override
  Future<void> clearAll() async {
    _rows.clear();
  }

  @override
  Future<void> close() async {}
}

StoryOutboxBackend createStoryOutboxBackend() => _MemoryStoryOutboxBackend();
