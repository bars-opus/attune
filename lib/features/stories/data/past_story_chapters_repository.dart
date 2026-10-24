// lib/features/stories/data/past_story_chapters_repository.dart
/// After an ending (stories Wave 5, review 05 #3; STORIES.md §3.3): the
/// author's OWN stories in spaces that are closed for stories (paused,
/// ended or archived), and deleting them. Nobody else can read these.
/// Storage stays closed at an ending, so there are dates and kinds here,
/// never thumbnails.
library;

import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class PastStoryChapter {
  const PastStoryChapter({
    required this.relationshipId,
    required this.status,
    required this.endedAt,
    required this.storyCount,
    required this.firstOn,
    required this.lastOn,
    this.canDownload = false,
  });

  factory PastStoryChapter.fromRow(Map<String, dynamic> row) =>
      PastStoryChapter(
        relationshipId: '${row['relationship_id']}',
        status: '${row['status']}',
        endedAt:
            row['ended_at'] == null
                ? null
                : DateTime.parse('${row['ended_at']}').toLocal(),
        storyCount: (row['story_count'] as num).toInt(),
        firstOn: DateTime.parse('${row['first_on']}'),
        lastOn: DateTime.parse('${row['last_on']}'),
        // Absent on an older server: say no, never offer a copy that the
        // export would not hold.
        canDownload: row['can_download'] == true,
      );

  final String relationshipId;
  final String status;
  final DateTime? endedAt;
  final int storyCount;
  final DateTime firstOn;
  final DateTime lastOn;

  /// Still in "Download my data" (ended under 30 days ago, not sealed by
  /// me, not archived): only then may the delete confirm suggest a copy.
  final bool canDownload;

  bool get paused => status == 'paused';
}

@immutable
class PastStoryItem {
  const PastStoryItem({
    required this.id,
    required this.mediaType,
    required this.occurredOn,
    required this.createdAt,
  });

  factory PastStoryItem.fromRow(Map<String, dynamic> row) => PastStoryItem(
    id: '${row['id']}',
    mediaType: '${row['media_type']}',
    occurredOn: DateTime.parse('${row['occurred_on']}'),
    createdAt: DateTime.parse('${row['created_at']}'),
  );

  final String id;
  final String mediaType;
  final DateTime occurredOn;
  final DateTime createdAt;

  bool get isVideo => mediaType == 'video';
}

abstract class PastStoryChaptersGateway {
  /// `list_my_closed_story_chapters`.
  Future<List<PastStoryChapter>> listChapters();

  /// `list_my_closed_story_items`, oldest first, keyset after [after].
  Future<List<PastStoryItem>> listItems(
    String relationshipId, {
    PastStoryItem? after,
    int limit = 50,
  });

  /// `delete_my_closed_story_items`: up to 200 per call; returns how many remain.
  Future<int> deleteAllOnce(String relationshipId);

  /// `delete_story_item`.
  Future<void> deleteOne(String storyItemId);
}

class SupabasePastStoryChaptersGateway implements PastStoryChaptersGateway {
  SupabasePastStoryChaptersGateway(this._supabase);

  final SupabaseClient _supabase;
  static const _timeout = Duration(seconds: 30);

  Map<String, dynamic> _unwrap(Object? response) {
    final data = Map<String, dynamic>.from(response! as Map);
    if (data['error'] == true) throw StoryApiError.fromJson(data);
    return data;
  }

  @override
  Future<List<PastStoryChapter>> listChapters() async {
    final rows = await _supabase
        .rpc('list_my_closed_story_chapters')
        .timeout(_timeout);
    return (rows as List)
        .map(
          (r) => PastStoryChapter.fromRow(Map<String, dynamic>.from(r as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PastStoryItem>> listItems(
    String relationshipId, {
    PastStoryItem? after,
    int limit = 50,
  }) async {
    final rows = await _supabase
        .rpc(
          'list_my_closed_story_items',
          params: {
            'p_relationship_id': relationshipId,
            'p_after_created_at': after?.createdAt.toUtc().toIso8601String(),
            'p_after_id': after?.id,
            'p_limit': limit,
          },
        )
        .timeout(_timeout);
    return (rows as List)
        .map((r) => PastStoryItem.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList(growable: false);
  }

  @override
  Future<int> deleteAllOnce(String relationshipId) async {
    final data = _unwrap(
      await _supabase
          .rpc(
            'delete_my_closed_story_items',
            params: {'p_relationship_id': relationshipId},
          )
          .timeout(_timeout),
    );
    return (data['remaining'] as num).toInt();
  }

  @override
  Future<void> deleteOne(String storyItemId) async {
    _unwrap(
      await _supabase
          .rpc('delete_story_item', params: {'p_story_item_id': storyItemId})
          .timeout(_timeout),
    );
  }
}

final pastStoryChaptersGatewayProvider = Provider<PastStoryChaptersGateway>(
  (ref) => SupabasePastStoryChaptersGateway(Supabase.instance.client),
);

/// My past chapters with stories in them; a new read per account.
final pastStoryChaptersProvider =
    FutureProvider.autoDispose<List<PastStoryChapter>>((ref) async {
      ref.watch(currentUserProvider.select((u) => u?.id));
      return ref.watch(pastStoryChaptersGatewayProvider).listChapters();
    });

/// One chapter's stories, oldest first, up to 1,000 (20 pages).
final pastStoryItemsProvider = FutureProvider.autoDispose
    .family<List<PastStoryItem>, String>((ref, relationshipId) async {
      final gateway = ref.watch(pastStoryChaptersGatewayProvider);
      final all = <PastStoryItem>[];
      PastStoryItem? after;
      for (var page = 0; page < 20; page++) {
        final items = await gateway.listItems(relationshipId, after: after);
        all.addAll(items);
        if (items.length < 50) break;
        after = items.last;
      }
      return all;
    });

/// Deletes every one of my stories in [relationshipId], 200 at a time.
Future<int> deleteAllMyPastStories(
  PastStoryChaptersGateway gateway,
  String relationshipId,
) async {
  var left = 0;
  for (var batch = 0; batch < 100; batch++) {
    left = await gateway.deleteAllOnce(relationshipId);
    if (left <= 0) return 0;
  }
  return left;
}

/// "A space that ended on 12 Sep 2026", "A paused space", "A space that closed".
String pastStoryChapterTitle(PastStoryChapter chapter) {
  if (chapter.paused) return 'A paused space';
  final ended = chapter.endedAt;
  if (ended == null) return 'A space that closed';
  return 'A space that ended on ${MyDateFormat.toDate(ended)}';
}
