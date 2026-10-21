import 'package:attune/features/chat/domain/entities/message.dart';

/// How long a recipient may replay a streak after first opening it. Mirrors
/// `streak_clips_for_viewing` / `mark_streak_viewed` on the server, which
/// own the rule; this only keeps the bubble honest between refreshes.
const Duration kStreakReplayWindow = Duration(minutes: 30);

/// Views the RECIPIENT can still take at [now]. The sender's budget is not
/// theirs to spend, so the window never applies to them.
///
/// A [Message.viewedAt] ahead of [now] (server clock ahead of the phone's)
/// reads as inside the window; the server has the final say either way.
int streakViewsAvailable(Message message, DateTime now) {
  final remaining = message.streakViewsRemaining ?? 0;
  if (message.isMine) return remaining;
  final viewedAt = message.viewedAt;
  if (viewedAt != null && now.difference(viewedAt) >= kStreakReplayWindow) {
    return 0;
  }
  return remaining;
}
