// lib/features/opinions/presentation/screens/comment_thread_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/app_text_form_field.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';


class CommentThreadScreen extends ConsumerStatefulWidget {
  final String opinionId;

  const CommentThreadScreen({super.key, required this.opinionId});

  @override
  ConsumerState<CommentThreadScreen> createState() => _CommentThreadScreenState();
}

class _CommentThreadScreenState extends ConsumerState<CommentThreadScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  String? _replyToCommentId;
  String? _replyToQuotedText;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  void _setReplyTarget(String? commentId, String? quotedText) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToQuotedText = quotedText;
    });
    _commentFocusNode.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToCommentId = null;
      _replyToQuotedText = null;
    });
  }

  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(postCommentProvider(
        (
          opinionId: widget.opinionId,
          content: content,
          replyToCommentId: _replyToCommentId,
          quotedText: _replyToQuotedText,
        ),
      ).future);

      _commentController.clear();
      _clearReplyTarget();
      setState(() => _isSubmitting = false);
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final commentsAsync = ref.watch(commentsProvider(widget.opinionId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Comments', style: textTheme.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Comment list
          Expanded(
            child: commentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: (comments) {
                if (comments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_outlined, size: 48, color: Colors.grey),
                        Gap(Spacing.md.h),
                        Text(
                          'No comments yet',
                          style: textTheme.titleMedium,
                        ),
                        Gap(Spacing.sm.h),
                        Text('Be the first to comment'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(Spacing.md.w),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    final comment = comments[index];
                    return _buildCommentCard(comment, comments, ref);
                  },
                );
              },
            ),
          ),
          // Reply indicator
          if (_replyToCommentId != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w, vertical: Spacing.sm.h),
              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to: ${_replyToQuotedText?.substring(0, (_replyToQuotedText!.length > 40) ? 40 : _replyToQuotedText!.length)}...',
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearReplyTarget,
                  ),
                ],
              ),
            ),
          // Comment input
          Container(
            padding: EdgeInsets.all(Spacing.md.w),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outline.withOpacity(0.1),
                  width: BorderWidthTokens.hairline,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: _commentController,
                    focusNode: _commentFocusNode,
                    hintText: 'Add a comment...',
                    maxLines: 3,
                    maxLength: 280,
                    // buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                    enabled: !_isSubmitting, label: '',
                  ),
                ),
                Gap(Spacing.sm.w),
                AppButton(
                  label: 'Post',
                  onPressed: _commentController.text.trim().isNotEmpty && !_isSubmitting
                      ? _postComment
                      : null,
                  size: ButtonSize.small,
                  isLoading: _isSubmitting,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentCard(CommentModel comment, List<CommentModel> allComments, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Server-computed; the real user_id never reaches the client (FORUM.md §3).
    final isOwnComment = comment.isMine;

    final statusDisplay = _getStatusDisplay(comment.relationshipStatus);
    final timeAgo = _formatTimeAgo(comment.createdAt);

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.sm.w),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              if (statusDisplay.isNotEmpty)
                Text(
                  statusDisplay,
                  style: textTheme.bodySmall?.copyWith(
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
              // Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 16),
                onSelected: (value) async {
                  if (value == 'report') {
                    _showReportDialog(context, ref, comment.id);
                  } else if (value == 'delete' && isOwnComment) {
                    await ref.read(deleteCommentProvider((commentId: comment.id, opinionId: widget.opinionId)).future);
                  }
                },
                itemBuilder: (context) => [
                  if (!isOwnComment)
                    const PopupMenuItem(value: 'report', child: Text('Report')),
                  if (isOwnComment)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          // Quoted text (if replying)
          if (comment.quotedText != null)
            Container(
              margin: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.xs.h),
              padding: EdgeInsets.all(Spacing.xs.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote, size: 14, color: colorScheme.onSurface.withOpacity(0.5)),
                  Gap(Spacing.xs.w),
                  Expanded(
                    child: Text(
                      comment.quotedText!,
                      style: textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Gap(Spacing.xs.h),
          // Content
          Text(
            comment.content,
            style: textTheme.bodyMedium,
          ),
          Gap(Spacing.sm.h),
          // Actions
          Row(
            children: [
              // Like button (simplified - no dislike for comments in v1? Spec allows both)
              _buildCommentReactionButton(
                icon: Icons.thumb_up_outlined,
                activeIcon: Icons.thumb_up,
                count: comment.likeCount,
                isActive: false, // Would need userReaction field on CommentModel
                onTap: () {
                  // Implement like/unlike
                },
              ),
              Gap(Spacing.md.w),
              // Reply button
              GestureDetector(
                onTap: () => _setReplyTarget(
                  comment.id,
                  comment.content.length > 60 ? '${comment.content.substring(0, 60)}...' : comment.content,
                ),
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

  Widget _buildCommentReactionButton({
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
            size: 14,
          ),
          Gap(Spacing.xs.w),
          if (count > 0)
            Text(
              '$count',
              style: const TextStyle(fontSize: 11),
            ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context, WidgetRef ref, String commentId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report this comment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReportOption(context, ref, commentId, 'Identifies a real person'),
            _buildReportOption(context, ref, commentId, 'Harmful or dangerous content'),
            _buildReportOption(context, ref, commentId, 'Explicit sexual content'),
            _buildReportOption(context, ref, commentId, 'Hate speech or discrimination'),
            _buildReportOption(context, ref, commentId, 'Spam'),
            _buildReportOption(context, ref, commentId, 'Other'),
          ],
        ),
      ),
    );
  }

  Widget _buildReportOption(BuildContext context, WidgetRef ref, String commentId, String reason) {
    return ListTile(
      title: Text(reason),
      onTap: () async {
        Navigator.pop(context);
        // Implement comment report provider
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you. We will review this within 24 hours.')),
        );
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
