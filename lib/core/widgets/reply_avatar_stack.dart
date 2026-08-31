// lib/core/widgets/reply_avatar_stack.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';

/// One overlapping circle in a [ReplyAvatarStack] — a status-colored circle
/// with the status icon, or an overflow "+N" tile once the stack runs out
/// of room. Shared by CommentThreadScreen's reply preview and
/// ForumPostBubble's reply row, which rendered byte-identical copies of
/// this before.
class ReplyAvatar extends StatelessWidget {
  final String? relationshipStatus;
  final double size;
  final bool showOverflow;
  final int overflowCount;

  const ReplyAvatar({
    super.key,
    required this.relationshipStatus,
    required this.size,
    this.showOverflow = false,
    this.overflowCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusDisplay = statusDisplayFor(relationshipStatus);
    final statusColor = statusColorFor(statusDisplay, colorScheme);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: showOverflow ? colorScheme.surfaceContainerHighest : statusColor,
        border: Border.all(color: colorScheme.surface, width: 1.5),
      ),
      alignment: Alignment.center,
      child:
          showOverflow
              ? Text(
                '$overflowCount+',
                style: TextStyle(
                  fontSize: size * 0.35,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              )
              : Icon(
                statusIconFor(statusDisplay),
                size: size * 0.5,
                color: colorScheme.background,
              ),
    );
  }
}

/// The overlapping-circles layout itself: up to [maxAvatars] [ReplyAvatar]s,
/// left-to-right, each overlapping the last by [overlap] — with the final
/// slot becoming an overflow "+N" tile once [statuses] has more entries
/// than fit. Takes relationship-status strings directly rather than a
/// concrete reply model (CommentModel and ForumPostModel are unrelated
/// types that both happen to expose one), so this has no dependency on
/// either feature's data layer.
class ReplyAvatarStack extends StatelessWidget {
  final List<String?> statuses;
  final double avatarSize;
  final double overlap;
  final int maxAvatars;

  const ReplyAvatarStack({
    super.key,
    required this.statuses,
    this.avatarSize = 20,
    this.overlap = 14,
    this.maxAvatars = 5,
  });

  @override
  Widget build(BuildContext context) {
    final shownCount =
        statuses.length > maxAvatars ? maxAvatars : statuses.length;

    return SizedBox(
      height: avatarSize,
      width: avatarSize + (shownCount - 1) * overlap,
      child: Stack(
        children: [
          for (var i = 0; i < shownCount; i++)
            Positioned(
              left: i * overlap,
              child: ReplyAvatar(
                relationshipStatus: statuses[i],
                size: avatarSize,
                showOverflow:
                    statuses.length > maxAvatars && i == maxAvatars - 1,
                overflowCount: statuses.length - (maxAvatars - 1),
              ),
            ),
        ],
      ),
    );
  }
}

/// The tappable "N replies" row itself — [ReplyAvatarStack] + count label,
/// shared by CommentThreadScreen's in-place expand/collapse and
/// ForumPostBubble's open-a-bottom-sheet shortcut, which rendered separate
/// copies of this same Row before.
///
/// The two call sites diverge on what tapping does and how the row reads
/// while that's happening, so those bits stay parameters rather than baked
/// in:
///   * [isExpanded] is comments-only — null (the default) means "no
///     expand/collapse concept", which drops the chevron and always shows
///     the avatar stack. Non-null adds the expand_more/expand_less chevron
///     and hides the stack while expanded (the replies are visible inline
///     instead, so repeating their avatars here would be redundant).
///   * [alignEnd] is forums-only — ForumPostBubble right-aligns this row
///     to match its bubble's `isMine` alignment; comments always left-align.
class RepliesRow extends StatelessWidget {
  final List<String?> replyStatuses;
  final int replyCount;
  final VoidCallback onTap;
  final bool? isExpanded;
  final bool alignEnd;
  final double avatarSize;
  final double overlap;
  final int maxAvatars;

  /// Color for the "N replies" text and expand chevron, otherwise
  /// colorScheme.primary. Null (the default) keeps that default —
  /// CommentThreadScreen has no notion of "side" to tint by. ForumPostBubble
  /// passes its post's sideColor (primary for FOR, error for AGAINST) so
  /// this row matches the bubble it belongs to, the same way the bubble
  /// fill itself and DebateRoomScreen's composer are side-tinted rather
  /// than fixed primary.
  final Color? accentColor;

  const RepliesRow({
    super.key,
    required this.replyStatuses,
    required this.replyCount,
    required this.onTap,
    this.isExpanded,
    this.alignEnd = false,
    this.avatarSize = 20,
    this.overlap = 14,
    this.maxAvatars = 5,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccentColor = accentColor ?? colorScheme.primary;
    final showAvatars = isExpanded != true;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (showAvatars) ...[
            AnimatedScaleFade(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutBack,
              child: ReplyAvatarStack(
                statuses: replyStatuses,
                avatarSize: avatarSize,
                overlap: overlap,
                maxAvatars: maxAvatars,
              ),
            ),
            Gap(Spacing.xs.w),
          ],

          ShakeTransition(
            offset: -140,
            curve: Curves.easeOutBack,
            child: Text(
              '$replyCount ${replyCount == 1 ? 'reply' : 'replies'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: effectiveAccentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isExpanded != null) ...[
            Gap(Spacing.xs.w),
            Icon(
              isExpanded! ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: effectiveAccentColor,
            ),
          ],
        ],
      ),
    );
  }
}
