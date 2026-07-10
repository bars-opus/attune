// lib/features/opinions/presentation/widgets/opinion_card.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';

class OpinionCard extends ConsumerWidget {
  final OpinionModel opinion;
  final bool showFollowButton;
  final VoidCallback? onCommentTap;
  final VoidCallback? onProfileTap;

  OpinionCard({
    super.key,
    required this.opinion,
    this.showFollowButton = true,
    this.onCommentTap,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentUserId = ref.read(currentUserIdProvider);
    final isOwnPost = currentUserId != null && opinion.userId == currentUserId;

    final statusDisplay = _getStatusDisplay(opinion.relationshipStatus);
    final timeAgo = DateFormat('yMd').add_jm().format(
      opinion.createdAt,
    ); // Simplified; use timeago package in real impl

    return GestureDetector(
      onTap: onProfileTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outline.withOpacity(0.1),
              width: BorderWidthTokens.hairline,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: blank name + status + time
            Row(
              children: [
                // Name is intentionally empty (nothing rendered)
                if (statusDisplay.isNotEmpty)
                  Text(
                    statusDisplay,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                if (statusDisplay.isNotEmpty) Gap(Spacing.xs.w),
                Text(
                  timeAgo,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const Spacer(),
                // Menu button (report, delete)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (value) async {
                    if (value == 'report') {
                      _showReportDialog(context, ref);
                    } else if (value == 'delete' && isOwnPost) {
                      await ref.read(deleteOpinionProvider(opinion.id).future);
                    } else if (value == 'copy') {
                      await Clipboard.setData(
                        ClipboardData(text: opinion.content),
                      );
                      if (context.mounted) {
                        context.showInfoSnackbar('Copied to clipboard');
                      }
                    }
                  },
                  itemBuilder:
                      (context) => [
                        if (!isOwnPost)
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('Report'),
                          ),
                        if (isOwnPost)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('Copy text'),
                        ),
                      ],
                ),
              ],
            ),
            Gap(Spacing.sm.h),
            // Content
            Text(opinion.content, style: textTheme.bodyLarge),
            Gap(Spacing.md.h),
            // Action row
            Row(
              children: [
                // Like button
                _buildReactionButton(
                  context: context,
                  icon: Icons.thumb_up_outlined,
                  activeIcon: Icons.thumb_up,
                  count: opinion.likeCount,
                  isActive: opinion.userReaction == 'like',
                  onTap: () => _toggleReaction(context, ref, 'like'),
                ),
                Gap(Spacing.md.w),
                // Dislike button
                _buildReactionButton(
                  context: context,
                  icon: Icons.thumb_down_outlined,
                  activeIcon: Icons.thumb_down,
                  count: opinion.dislikeCount,
                  isActive: opinion.userReaction == 'dislike',
                  onTap: () => _toggleReaction(context, ref, 'dislike'),
                ),
                Gap(Spacing.md.w),
                // Comment button
                _buildActionButton(
                  icon: Icons.comment_outlined,
                  label: '${opinion.commentCount}',
                  onTap: onCommentTap ?? () {},
                ),
                const Spacer(),
                // Follow button (if not own post)
                if (showFollowButton && !isOwnPost)
                  _buildFollowButton(context, ref),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionButton({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
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
          Text(count > 0 ? '$count' : '', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18),
          Gap(Spacing.xs.w),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context, WidgetRef ref) {
    final followState = ref.watch(followStatusProvider(opinion.userId));
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
          await ref.read(unfollowUserProvider(opinion.userId).future);
        } else {
          await ref.read(followUserProvider(opinion.userId).future);
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

  void _showReportDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Report this post'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReportOption(context, ref, 'Identifies a real person'),
                _buildReportOption(
                  context,
                  ref,
                  'Harmful or dangerous content',
                ),
                _buildReportOption(context, ref, 'Explicit sexual content'),
                _buildReportOption(
                  context,
                  ref,
                  'Hate speech or discrimination',
                ),
                _buildReportOption(context, ref, 'Spam'),
                _buildReportOption(context, ref, 'Other'),
              ],
            ),
          ),
    );
  }

  Widget _buildReportOption(
    BuildContext context,
    WidgetRef ref,
    String reason,
  ) {
    return ListTile(
      title: Text(reason),
      onTap: () async {
        Navigator.pop(context);
        if (ref.read(currentUserIdProvider) == null) {
          context.showInfoSnackbar(
            'Continue with phone number from Chat to report content.',
          );
          return;
        }
        await ref.read(
          reportOpinionProvider((opinionId: opinion.id, reason: reason)).future,
        );
        if (context.mounted) {
          context.showInfoSnackbar(
            'Thank you. We will review this within 24 hours.',
          );
        }
      },
    );
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
}
