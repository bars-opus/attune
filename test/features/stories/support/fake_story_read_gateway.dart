import 'package:attune/features/stories/data/story_read_repository.dart';

/// A do-nothing [StoryReadGateway] for widget tests that mount story
/// surfaces (the reel over map places, the couple map tab) without caring
/// about reads: everything is empty and signing returns null.
class FakeStoryReadGateway implements StoryReadGateway {
  final deleted = <String>[];
  final viewed = <String>[];
  final signed = <String>[];

  /// What signMediaUrl returns (null by default: signing "fails").
  String? Function(String key)? sign;

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => const [];

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<void> markViewed({required String storyItemId}) async =>
      viewed.add(storyItemId);

  @override
  Future<void> deleteItem({required String storyItemId}) async =>
      deleted.add(storyItemId);

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

  @override
  Future<String?> signMediaUrl(String storageKey) async {
    signed.add(storageKey);
    return sign?.call(storageKey);
  }

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}
