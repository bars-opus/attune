// lib/features/forums/presentation/widgets/forum_post_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


class ForumPostCard extends ConsumerStatefulWidget {
  final ForumPostModel post;
  final String userSide;
  final VoidCallback onReply;

  const ForumPostCard({
    super.key,
    required this.post,
    required this.userSide,
    required this.onReply,
  });

  @override
  ConsumerState<ForumPostCard> createState() => _ForumPostCardState();
}

class _ForumPostCardState extends ConsumerState<ForumPostCard> {
  bool _isLiking = false;

  Future<void> _toggleLike() async {
    if (_isLiking) return;

    setState(() => _isLiking = true);

    try {
      if (widget.post.userLiked) {
        await ref.read(unlikeForumPostProvider(widget.post.id).future);
      } else {
        await ref.read(likeForumPostProvider(widget.post.id).future);
      }
      ref.invalidate(forumPostsProvider(widget.post.topicId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to like: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLiking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isForSide = widget.post.side == 'for';
    final canReply = widget.userSide != 'browse';

    final statusDisplay = _getStatusDisplay(widget.post.relationshipStatus);
    final timeAgo = _formatTimeAgo(widget.post.createdAt);

    // FOR side: left-aligned, left column
    // AGAINST side: right-aligned, right column
    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.sm.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        crossAxisAlignment: isForSide ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // Header (status + time)
          Row(
            mainAxisAlignment: isForSide ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (statusDisplay.isNotEmpty)
                Text(
                  statusDisplay,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isForSide ? colorScheme.primary : colorScheme.error,
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
              // Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 16),
                onSelected: (value) async {
                  if (value == 'report') {
                    _showReportDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'report', child: Text('Report')),
                ],
              ),
            ],
          ),
          // Quoted text (if replying to another post - cross-column quoting)
          if (widget.post.quotedText != null)
            Container(
              margin: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.xs.h),
              padding: EdgeInsets.all(Spacing.xs.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                mainAxisAlignment: isForSide ? MainAxisAlignment.start : MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote, size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
                  Gap(Spacing.xs.w),
                  Expanded(
                    child: Text(
                      widget.post.quotedText!,
                      style: textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: isForSide ? TextAlign.left : TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          Gap(Spacing.xs.h),
          // Content
          Text(
            widget.post.content,
            style: textTheme.bodyMedium,
            textAlign: isForSide ? TextAlign.left : TextAlign.right,
          ),
          Gap(Spacing.sm.h),
          // Actions (like + reply)
          Row(
            mainAxisAlignment: isForSide ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              // Like button
              GestureDetector(
                onTap: _toggleLike,
                child: Row(
                  children: [
                    Icon(
                      widget.post.userLiked ? Icons.favorite : Icons.favorite_border,
                      size: 16,
                      color: widget.post.userLiked ? Colors.red : colorScheme.onSurface.withOpacity(0.6),
                    ),
                    Gap(Spacing.xs.w),
                    if (widget.post.likeCount > 0)
                      Text(
                        '${widget.post.likeCount}',
                        style: TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
              Gap(Spacing.md.w),
              // Reply button (only if user can post)
              if (canReply)
                GestureDetector(
                  onTap: widget.onReply,
                  child: Text(
                    'Reply',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report this post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReportOption('Identifies a real person'),
            _buildReportOption('Harmful or dangerous content'),
            _buildReportOption('Hate speech or discrimination'),
            _buildReportOption('Spam'),
            _buildReportOption('Other'),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(String reason) {
    return ListTile(
      title: Text(reason),
      onTap: () async {
        Navigator.pop(context);
        await ref.read(reportForumPostProvider((postId: widget.post.id, reason: reason)).future);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thank you. We will review this.')),
          );
        }
      },
    );
  }

  String _getStatusDisplay(String? status) {
    switch (status) {
      case 'single': return 'Single';
      case 'taken': return 'Taken';
      case 'figuring_it_out': return 'Figuring it out';
      case 'open': return 'Open';
      default: return '';
    }
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
