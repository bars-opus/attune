// lib/features/opinions/presentation/screens/comment_thread_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CommentThreadScreen extends ConsumerStatefulWidget {
  final String opinionId;
  final OpinionModel opinion;

  const CommentThreadScreen({
    super.key,
    required this.opinionId,
    required this.opinion,
  });

  @override
  ConsumerState<CommentThreadScreen> createState() =>
      _CommentThreadScreenState();
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
      await ref.read(
        postCommentProvider((
          opinionId: widget.opinionId,
          content: content,
          replyToCommentId: _replyToCommentId,
          quotedText: _replyToQuotedText,
        )).future,
      );

      _commentController.clear();
      _clearReplyTarget();
      setState(() => _isSubmitting = false);
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        print(e);
        context.showErrorSnackbar('Failed to post comment: $e');
      }
    }
  }

  // AppBar action — the single moderation entry point (report/copy/delete)
  // for the opinion, built from OpinionMoreData's SettingsConfig list so it
  // renders with the same SettingsItem row ProfileMoreData uses elsewhere.
  void _showOpinionMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        // Each action closes this sheet first (Navigator.pop(sheetContext))
        // before running, so a follow-up UI action (report reasons, a
        // snackbar, popping the detail screen after delete) doesn't stack
        // on top of an already-dismissed sheet.
        final sections = OpinionMoreData.getSections(
          context: context,
          ref: ref,
          opinion: widget.opinion,
          onReport: () {
            Navigator.pop(sheetContext);
            OpinionMoreData.showReportReasons(
              context: context,
              ref: ref,
              opinionId: widget.opinion.id,
            );
          },
          onDelete: () async {
            Navigator.pop(sheetContext);
            await ref.read(deleteOpinionProvider(widget.opinion.id).future);
            if (context.mounted) Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final commentsAsync = ref.watch(commentsProvider(widget.opinionId));

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: true,
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Opinion',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                TextSpan(
                  text:
                      '\n${_formatCommentCount(commentsAsync.valueOrNull?.length ?? widget.opinion.commentCount)} Comments',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(.4),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          // Text(
          //   'Opinion',
          //   style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600,

          //   color: colorScheme.onBackground,

          // ),

          // ),
          actions: [
            AppIconButton(
              icon: Icons.more_vert_rounded,
              onPressed: () => _showOpinionMenu(context, ref),
            ),
          ],
        ),
        body: Column(
          children: [
            // Opinion + comment list, opinion pinned as the list's first item
            // so it scrolls away with the comments rather than staying fixed.
            Expanded(
              child: commentsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => ErrorStateWidget.from(error),
                data: (comments) {
                  return ListView(
                    padding: EdgeInsets.all(Spacing.md.w),
                    children: [
                      OpinionCard(
                        opinion: widget.opinion,
                        showFollowButton: false,
                        // The comment textfield below replaces the need to
                        // tap into a thread, and the AppBar already carries
                        // the same report/copy/delete menu as showMoreButton.
                        showCommentAction: false,
                        showMoreButton: false,
                      ),

                      Gap(Spacing.md.h),
                      if (comments.isEmpty)
                        Center(
                          child: EmptyStateWidget(
                            icon: Icons.comment,
                            title: 'No comments yet',
                            subtitle:
                                'What do you think? Feel free to drop your opnion',
                          ),
                        )
                      else
                        for (final comment in comments)
                          _buildCommentCard(comment, comments, ref),
                    ],
                  );
                },
              ),
            ),
            // Reply indicator
            if (_replyToCommentId != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: Spacing.md.w,
                  vertical: Spacing.sm.h,
                ),
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
            // Comment input, styled like chat's message input.
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outline.withOpacity(0.1),
                    width: BorderWidthTokens.hairline,
                  ),
                ),
              ),
              child: ChatTextField(
                controller: _commentController,
                onSend: _postComment,
                enabled: !_isSubmitting,
                hintText: 'Add a comment...',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentCard(
    CommentModel comment,
    List<CommentModel> allComments,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Server-computed; the real user_id never reaches the client (FORUM.md §3).
    final isOwnComment = comment.isMine;

    final statusDisplay = _getStatusDisplay(comment.relationshipStatus);
    final statusIcon = _statusIconFor(statusDisplay);
    final statusIconColor = _statusColorFor(
      statusDisplay,
      Theme.of(context).colorScheme,
    );
    final timeAgo = _formatTimeAgo(comment.createdAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                Icon(
                  Icons.format_quote,
                  size: 14,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
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
        InfoRowWidget(
          title: '',
          subtitle: comment.content,
          icon: statusIcon,
          iconColor: colorScheme.background,
          backgroundColor: statusIconColor,
          avatarRadius: 15.h,
          subTitleMaxLines: 10,
          iconSize: 12.h,
          onTap: () {},
          showDivider: true,
          onAvatarTap: () {},
          disableTrailing: true,
          showAvatar: true,
          showTrailingArrow: false,
          bottomWidget: Row(
            children: [
              // Like button (simplified - no dislike for comments in v1? Spec allows both)
              _buildCommentReactionButton(
                icon: Icons.thumb_up_outlined,
                activeIcon: Icons.thumb_up,
                count: comment.likeCount,
                isActive:
                    false, // Would need userReaction field on CommentModel
                onTap: () {
                  // Implement like/unlike
                },
              ),
              Gap(Spacing.md.w),
              // Reply button
              GestureDetector(
                onTap:
                    () => _setReplyTarget(
                      comment.id,
                      comment.content.length > 60
                          ? '${comment.content.substring(0, 60)}...'
                          : comment.content,
                    ),
                child: Text(
                  'Reply',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),

              Text(
                timeAgo,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onBackground.withOpacity(0.5),
                ),
              ),
              Gap(Spacing.md.w),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 16),
                onSelected: (value) async {
                  if (value == 'report') {
                    _showReportDialog(context, ref, comment.id);
                  } else if (value == 'delete' && isOwnComment) {
                    await ref.read(
                      deleteCommentProvider((
                        commentId: comment.id,
                        opinionId: widget.opinionId,
                      )).future,
                    );
                  }
                },
                itemBuilder:
                    (context) => [
                      if (!isOwnComment)
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('Report'),
                        ),
                      if (isOwnComment)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
              ),
            ],
          ),
        ),
      ],
    );
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
        return colorScheme.error;
      case 'Figuring it out':
        return colorScheme.warning;
      case 'Open':
        return colorScheme.neutral;
      default:
        return colorScheme.error;
    }
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
          Icon(isActive ? activeIcon : icon, size: 14),
          Gap(Spacing.xs.w),
          if (count > 0) Text('$count', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  void _showReportDialog(
    BuildContext context,
    WidgetRef ref,
    String commentId,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Report this comment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Identifies a real person',
                ),
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Harmful or dangerous content',
                ),
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Explicit sexual content',
                ),
                _buildReportOption(
                  context,
                  ref,
                  commentId,
                  'Hate speech or discrimination',
                ),
                _buildReportOption(context, ref, commentId, 'Spam'),
                _buildReportOption(context, ref, commentId, 'Other'),
              ],
            ),
          ),
    );
  }

  Widget _buildReportOption(
    BuildContext context,
    WidgetRef ref,
    String commentId,
    String reason,
  ) {
    return ListTile(
      title: Text(reason),
      onTap: () async {
        Navigator.pop(context);
        // Implement comment report provider
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you. We will review this within 24 hours.'),
          ),
        );
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

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  String _formatCommentCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(count % 1000000 == 0 ? 0 : 1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 1)}K';
    }
    return '$count';
  }
}
