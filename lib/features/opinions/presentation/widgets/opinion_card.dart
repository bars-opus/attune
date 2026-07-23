// lib/features/opinions/presentation/widgets/opinion_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class OpinionCard extends ConsumerWidget {
  final OpinionModel opinion;
  final bool showFollowButton;
  final VoidCallback? onOpinionTap;
  final VoidCallback? onCommentTap;
  final VoidCallback? onProfileTap;

  /// Hide the comment-count action when this card is embedded in
  /// CommentThreadScreen, which already has a comment textfield below —
  /// tapping it there to re-open the (already open) thread is redundant.
  final bool showCommentAction;

  /// Hide the overflow (⋮) menu when this card is embedded in
  /// CommentThreadScreen, which already has the same report/copy/delete
  /// menu on its AppBar — avoids showing the action twice.
  final bool showMoreButton;

  const OpinionCard({
    super.key,
    required this.opinion,
    this.showFollowButton = true,
    this.onOpinionTap,
    this.onCommentTap,
    this.onProfileTap,
    this.showCommentAction = true,
    this.showMoreButton = true,
  });

  // Shared between the feed card and CommentThreadScreen's header so the
  // opinion (not its actions row) Heroes between the two.
  String get _heroTag => 'opinion-${opinion.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Server-computed: the real user_id never reaches the client (FORUM.md §3).
    final isOwnPost = opinion.isMine;

    final statusDisplay = _getStatusDisplay(opinion.relationshipStatus);
    final statusIcon = _statusIconFor(statusDisplay);
    final statusIconColor = _statusColorFor(
      statusDisplay,
      Theme.of(context).colorScheme,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final timeAgo = _formatTimeAgo(opinion.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero'd between the feed card and CommentThreadScreen's header —
        // the opinion itself transitions, not its actions row below.
        Hero(
          tag: _heroTag,
          child: Material(
            type: MaterialType.transparency,
            child: GestureDetector(
              onTap: onOpinionTap,
              behavior: HitTestBehavior.opaque,
              child: InfoRowWidget(
                title: '',
                subtitle: opinion.content,
                icon: statusIcon,
                iconColor: colorScheme.background,
                backgroundColor: Colors.grey,
                avatarRadius: 20.h,
                iconSize: 18.h,
                onTap: onOpinionTap,
                onAvatarTap: onProfileTap,
                disableTrailing: true,
                showAvatar: true,
                showTrailingArrow: false,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
          child: Row(
            children: [
              _buildReactionButton(
                context: context,
                icon: Icons.favorite_outline,
                activeIcon: Icons.favorite,
                count: opinion.likeCount,
                isActive: opinion.userReaction == 'like',
                onTap: () => _toggleReaction(context, ref, 'like'),
              ),
              Gap(Spacing.md.w),
              _buildReactionButton(
                context: context,
                icon: Icons.thumb_down_outlined,
                activeIcon: Icons.thumb_down,
                count: opinion.dislikeCount,
                isActive: opinion.userReaction == 'dislike',
                onTap: () => _toggleReaction(context, ref, 'dislike'),
              ),
              if (showCommentAction) ...[
                Gap(Spacing.md.w),
                _buildActionButton(
                  context: context,
                  icon: Icons.edit,
                  label: '${opinion.commentCount}',
                  onTap: onCommentTap ?? () {},
                ),
              ],
              Gap(Spacing.md.w),
              // Reshare: icon only for now, no count/backend yet — separate
              // feature, tracked to be implemented later.
              GestureDetector(
                onTap: () {},
                child: const Icon(Icons.repeat, size: 18),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    timeAgo,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),

                  Gap(Spacing.sm.w),

                  Text(
                    statusDisplay,
                    style: textTheme.bodySmall?.copyWith(
                      color: statusIconColor,
                    ),
                  ),
                ],
              ),
              if (showFollowButton && !isOwnPost)
                _buildFollowButton(context, ref),
              if (showMoreButton) _buildMoreButton(context, ref),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMoreButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showOpinionMenu(context, ref),
      child: Icon(
        Icons.more_horiz,
        size: 18.h,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  // Same report/copy/delete menu CommentThreadScreen shows on its AppBar —
  // this card is only responsible for opening it when showMoreButton is
  // true (feed contexts); the detail screen passes showMoreButton: false
  // and owns its own trigger instead of duplicating the action.
  void _showOpinionMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final sections = OpinionMoreData.getSections(
          context: context,
          ref: ref,
          opinion: opinion,
          onReport: () {
            Navigator.pop(sheetContext);
            OpinionMoreData.showReportReasons(
              context: context,
              ref: ref,
              opinionId: opinion.id,
            );
          },
          onDelete: () async {
            Navigator.pop(sheetContext);
            await ref.read(deleteOpinionProvider(opinion.id).future);
          },
        );

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final section in sections)
                for (final item in section.items)
                  SettingsItem(config: item, showDivider: false),
            ],
          ),
        );
      },
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  Widget _buildReactionButton({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            isActive ? activeIcon : icon,
            size: 18,
            color: isActive ? Theme.of(context).colorScheme.primary : null,
          ),
          Gap(Spacing.xs.w),
          Text(
            count > 0 ? '$count' : '',
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18),
          Gap(Spacing.xs.w),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context, WidgetRef ref) {
    final followState = ref.watch(followStatusProvider(opinion.authorHandle));
    final isFollowing = followState.valueOrNull ?? false;

    return AppIconButton(
      icon:
          isFollowing
              ? Icons.person_remove_outlined
              : Icons.person_add_outlined,
      // label: isFollowing ? 'Following' : 'Follow',
      onPressed: () async {
        if (ref.read(currentUserIdProvider) == null) {
          context.showInfoSnackbar(
            'Continue with phone number from Chat to follow people.',
          );
          return;
        }
        if (isFollowing) {
          await ref.read(unfollowUserProvider(opinion.authorHandle).future);
        } else {
          await ref.read(followUserProvider(opinion.authorHandle).future);
        }
      },
    );
  }

  void _toggleReaction(
    BuildContext context,
    WidgetRef ref,
    String newReaction,
  ) {
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to react to opinions.',
      );
      return;
    }
    final current = opinion.userReaction;
    if (current == newReaction) {
      // Remove reaction
      ref.read(removeReactionProvider(opinion.id).future);
    } else {
      // Add or switch reaction
      ref.read(
        addReactionProvider((opinionId: opinion.id, type: newReaction)).future,
      );
    }
  }

  String _getStatusDisplay(String? status) {
    switch (status) {
      case 'single':
        return 'Single';
      case 'taken':
        return 'Taken';
      case 'figuring_it_out':
        return 'Figuring it out';
      case 'open':
        return 'Open';
      default:
        return '';
    }
  }

  IconData _statusIconFor(String statusDisplay) {
    if (statusDisplay.isEmpty) {
      return FontAwesomeIcons.circleQuestion;
    }

    switch (statusDisplay[0].toUpperCase()) {
      case 'S':
        return FontAwesomeIcons.s;
      case 'T':
        return FontAwesomeIcons.t;
      case 'F':
        return FontAwesomeIcons.f;
      case 'O':
        return FontAwesomeIcons.o;
      default:
        return FontAwesomeIcons.circleQuestion;
    }
  }

  Color _statusColorFor(String statusDisplay, ColorScheme colorScheme) {
    switch (statusDisplay) {
      case 'Single':
        return colorScheme.info;
      case 'Taken':
        return colorScheme.success;
      case 'Figuring it out':
        return colorScheme.warning;
      case 'Open':
        return colorScheme.neutral;
      default:
        return colorScheme.error;
    }
  }
}
