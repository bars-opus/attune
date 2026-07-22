// lib/features/opinions/presentation/widgets/opinion_card.dart

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class OpinionCard extends ConsumerWidget {
  final OpinionModel opinion;
  final bool showFollowButton;
  final VoidCallback? onOpinionTap;
  final VoidCallback? onCommentTap;
  final VoidCallback? onProfileTap;

  const OpinionCard({
    super.key,
    required this.opinion,
    this.showFollowButton = true,
    this.onOpinionTap,
    this.onCommentTap,
    this.onProfileTap,
  });

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

    return GestureDetector(
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
        bottomWidget: Padding(
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
              Gap(Spacing.md.w),
              _buildActionButton(
                icon: Icons.edit,
                label: '${opinion.commentCount}',
                onTap: onCommentTap ?? () {},
              ),
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
              // [⋯] Report / Copy text / Delete (own posts only) — FORUM.md §4.3.
              // This is the moderation entry point the §8 report system depends on.
              _buildOverflowMenu(context, ref, isOwnPost),
            ],
          ),
        ),
      ),

      //    Container(
      //     padding: EdgeInsets.all(Spacing.md.w),
      //     decoration: BoxDecoration(
      //       border: Border(
      //         bottom: BorderSide(
      //           color: colorScheme.outline.withOpacity(0.1),
      //           width: BorderWidthTokens.hairline,
      //         ),
      //       ),
      //     ),
      //     child: Column(
      //       crossAxisAlignment: CrossAxisAlignment.start,
      //       children: [
      //         // Header: blank name + status + time
      //         Row(
      //           children: [
      //             // Name is intentionally empty (nothing rendered)
      //             if (statusDisplay.isNotEmpty)
      //               Text(
      //                 statusDisplay,
      //                 style: textTheme.bodyMedium?.copyWith(
      //                   fontWeight: FontWeight.w600,
      //                   color: colorScheme.primary,
      //                 ),
      //               ),
      //             if (statusDisplay.isNotEmpty) Gap(Spacing.xs.w),
      // Text(
      //   timeAgo,
      //   style: textTheme.bodySmall?.copyWith(
      //     color: colorScheme.onSurface.withOpacity(0.5),
      //   ),
      // ),
      //             const Spacer(),
      //             // Menu button (report, delete)
      //             PopupMenuButton<String>(
      //               icon: const Icon(Icons.more_horiz, size: 20),
      //               onSelected: (value) async {
      //                 if (value == 'report') {
      //                   _showReportDialog(context, ref);
      //                 } else if (value == 'delete' && isOwnPost) {
      //                   await ref.read(deleteOpinionProvider(opinion.id).future);
      //                 } else if (value == 'copy') {
      //                   await Clipboard.setData(
      //                     ClipboardData(text: opinion.content),
      //                   );
      //                   if (context.mounted) {
      //                     context.showInfoSnackbar('Copied to clipboard');
      //                   }
      //                 }
      //               },
      //               itemBuilder:
      //                   (context) => [
      //                     if (!isOwnPost)
      //                       const PopupMenuItem(
      //                         value: 'report',
      //                         child: Text('Report'),
      //                       ),
      //                     if (isOwnPost)
      //                       const PopupMenuItem(
      //                         value: 'delete',
      //                         child: Text('Delete'),
      //                       ),
      //                     const PopupMenuItem(
      //                       value: 'copy',
      //                       child: Text('Copy text'),
      //                     ),
      //                   ],
      //             ),
      //           ],
      //         ),
      //         Gap(Spacing.sm.h),
      //         // Content
      //         Text(opinion.content, style: textTheme.bodyLarge),
      //         Gap(Spacing.md.h),
      //         // Action row
      // Row(
      //   children: [
      //     // Like button
      //     _buildReactionButton(
      //       context: context,
      //       icon: Icons.thumb_up_outlined,
      //       activeIcon: Icons.thumb_up,
      //       count: opinion.likeCount,
      //       isActive: opinion.userReaction == 'like',
      //       onTap: () => _toggleReaction(context, ref, 'like'),
      //     ),
      //     Gap(Spacing.md.w),
      //     // Dislike button
      //     _buildReactionButton(
      //       context: context,
      //       icon: Icons.thumb_down_outlined,
      //       activeIcon: Icons.thumb_down,
      //       count: opinion.dislikeCount,
      //       isActive: opinion.userReaction == 'dislike',
      //       onTap: () => _toggleReaction(context, ref, 'dislike'),
      //     ),
      //     Gap(Spacing.md.w),
      //     // Comment button
      //     _buildActionButton(
      //       icon: Icons.comment_outlined,
      //       label: '${opinion.commentCount}',
      //       onTap: onCommentTap ?? () {},
      //     ),
      //     const Spacer(),
      //     // Follow button (if not own post)
      //     if (showFollowButton && !isOwnPost)
      //       _buildFollowButton(context, ref),
      //   ],
      // ),
      //       ],
      //     ),
      //   ),
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

  Widget _buildOverflowMenu(
    BuildContext context,
    WidgetRef ref,
    bool isOwnPost,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: 18.h,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'report':
            _showReportDialog(context, ref);
          case 'copy':
            await Clipboard.setData(ClipboardData(text: opinion.content));
            if (context.mounted) {
              context.showInfoSnackbar('Copied to clipboard');
            }
          case 'delete':
            if (isOwnPost) {
              await ref.read(deleteOpinionProvider(opinion.id).future);
            }
        }
      },
      itemBuilder: (context) => [
        // You cannot report your own post; you can delete it.
        if (!isOwnPost)
          const PopupMenuItem(value: 'report', child: Text('Report')),
        const PopupMenuItem(value: 'copy', child: Text('Copy text')),
        if (isOwnPost)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref) {
    // Reason list is the FORUM.md §8 set (matches the comment-thread dialog).
    const reasons = [
      'Identifies a real person',
      'Harmful or dangerous content',
      'Explicit sexual content',
      'Hate speech or discrimination',
      'Spam',
      'Other',
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(Spacing.md.w),
              child: Text(
                'Report this opinion',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final reason in reasons)
              ListTile(
                title: Text(reason),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(
                    reportOpinionProvider(
                      (opinionId: opinion.id, reason: reason),
                    ).future,
                  );
                  if (context.mounted) {
                    context.showInfoSnackbar(
                      'Thank you. We will review this within 24 hours.',
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
