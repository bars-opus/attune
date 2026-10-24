/// One ring per author who posted on a calendar day (04 #4). Authors,
/// counts and the newest thumbnail come from `list_story_day_counts`,
/// which covers the whole day, not just the first page of
/// `list_story_day_items`. The loaded items fill in when the counts are
/// missing, and supply the partner's unviewed count when they cover the
/// whole day or the server sends none. The larger count per author wins.
library;

import 'dart:math' as math;

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/foundation.dart';

@immutable
class StoryDayAuthorRing {
  const StoryDayAuthorRing({
    required this.authorId,
    required this.count,
    required this.unviewed,
    required this.thumbnailKey,
  });

  final String authorId;
  final int count;
  final int unviewed;
  final String? thumbnailKey;
}

({int total, List<StoryDayAuthorRing> rings}) storyDayAuthorRings({
  required DateTime day,
  required List<StoryDayCount>? counts,
  required List<StoryItem>? items,
  required String? myId,
}) {
  bool sameDay(DateTime d) =>
      d.year == day.year && d.month == day.month && d.day == day.day;
  final countRows = [
    for (final c in counts ?? const <StoryDayCount>[])
      if (sameDay(c.occurredOn)) c,
  ];
  final counted = {
    for (final c in countRows)
      if (c.authorId != null && c.itemCount > 0) c.authorId!: c,
  };
  final loaded = <String, List<StoryItem>>{};
  for (final item in items ?? const <StoryItem>[]) {
    loaded.putIfAbsent(item.authorId, () => []).add(item);
  }
  // Mine first, as on the Conversations rings.
  final authors =
      {...counted.keys, ...loaded.keys}.toList()..sort((x, y) {
        if (x == myId) return -1;
        if (y == myId) return 1;
        return x.compareTo(y);
      });
  final rings = <StoryDayAuthorRing>[
    for (final author in authors)
      () {
        final row = counted[author];
        final theirs = loaded[author] ?? const <StoryItem>[];
        final count = math.max(row?.itemCount ?? 0, theirs.length);
        // My own "viewed" means my partner saw it: my ring is all bright.
        // The partner's: what the loaded items say when they cover the
        // author's whole day (they are the fresher read). Only when they are
        // partial (a day past page one) does the server's whole-day count
        // decide (Wave 5); an older server sends none.
        final serverUnviewed = row?.unviewedCount;
        final loadedCoversDay = theirs.length >= (row?.itemCount ?? 0);
        final loadedUnviewed = theirs.where((i) => !i.hasBeenViewed).length;
        final unviewed =
            author == myId
                ? count
                : (loadedCoversDay || serverUnviewed == null
                        ? loadedUnviewed
                        : serverUnviewed)
                    .clamp(0, count);
        return StoryDayAuthorRing(
          authorId: author,
          count: count,
          unviewed: unviewed,
          thumbnailKey:
              row?.newestThumbnailKey ??
              (theirs.isEmpty ? null : theirs.last.thumbnailKey),
        );
      }(),
  ];
  final dayTotal = countRows.isEmpty ? 0 : countRows.first.dayItemCount;
  final ringTotal = rings.fold<int>(0, (sum, r) => sum + r.count);
  return (total: math.max(dayTotal, ringTotal), rings: rings);
}

/// Newest-thumbnail keys a month re-read no longer shows, other than ones
/// a newer story that day replaced: a past story the partner deleted
/// (05 #6). Its bytes leave the disk cache.
Set<String> storyDayCountDroppedKeys(
  List<StoryDayCount>? previous,
  List<StoryDayCount> next,
) {
  if (previous == null) return const {};
  String slot(StoryDayCount c) =>
      '${c.occurredOn.year}-${c.occurredOn.month}-${c.occurredOn.day}'
      '|${c.authorId}';
  final bySlot = {for (final c in next) slot(c): c};
  final kept = {
    for (final c in next)
      if (c.newestThumbnailKey != null) c.newestThumbnailKey!,
  };
  final dropped = <String>{};
  for (final before in previous) {
    final key = before.newestThumbnailKey;
    if (key == null || kept.contains(key)) continue;
    final after = bySlot[slot(before)]?.newestCreatedAt;
    final was = before.newestCreatedAt;
    final replacedByNewer = after != null && was != null && after.isAfter(was);
    if (!replacedByNewer) dropped.add(key);
  }
  return dropped;
}
