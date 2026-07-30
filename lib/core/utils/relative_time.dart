// lib/core/utils/relative_time.dart

/// "N ago" relative-time label shared by every card/bubble that shows a
/// post's age (OpinionCard, comment cards, ForumCard, ForumPostBubble). Was
/// three near-identical private copies before this — two byte-identical,
/// one (ForumCard's) additionally rolling days over into weeks past a week,
/// which is the more complete behavior and produces the same output as the
/// other two for anything under 7 days, so this is that superset rather
/// than a lowest-common-denominator merge.
String formatTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}
