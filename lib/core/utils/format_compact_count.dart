// lib/core/utils/format_compact_count.dart

/// "1.2K"/"3.4M"-style abbreviation for a count too large to show digit by
/// digit — shared so opinion reaction counts, comment counts, forum vote
/// counts and follower counts all read the same way instead of each screen
/// growing its own near-identical formatter (as comment_thread_screen's
/// _formatCommentCount and notification_bell_icon's _formatCount had).
String formatCompactCount(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(count % 1000000 == 0 ? 0 : 1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}K';
  }
  return '$count';
}
