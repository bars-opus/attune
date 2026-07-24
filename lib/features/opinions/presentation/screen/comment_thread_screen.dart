// lib/features/opinions/presentation/screens/comment_thread_screen.dart

import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
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

  // Parent comment ids whose replies are currently expanded inline.
  final Set<String> _expandedReplies = {};

  void _toggleRepliesExpanded(String parentCommentId) {
    setState(() {
      if (!_expandedReplies.add(parentCommentId)) {
        _expandedReplies.remove(parentCommentId);
      }
    });
  }

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

  // Bridges ConfirmationDialog's VoidCallback onto the Future<bool>
  // DismissiblePane.confirmDismiss expects, so a full swipe past Delete
  // still asks before removing the comment rather than firing instantly.
  Future<bool> _confirmDeleteComment(BuildContext context) {
    final completer = Completer<bool>();
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 320.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.destructive,
        title: 'Delete this comment?',
        confirmText: 'Delete',
        message: 'This cannot be undone.',
        onConfirm: () => completer.complete(true),
        onCancel: () => completer.complete(false),
      ),
    ).then((_) {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
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
                        ..._buildCommentThread(comments, ref),
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

  // Groups the flat comment list into top-level comments with their replies
  // nested underneath, instead of every reply rendering as its own
  // top-level comment mixed into the thread.
  List<Widget> _buildCommentThread(List<CommentModel> comments, WidgetRef ref) {
    final repliesByParent = <String, List<CommentModel>>{};
    final topLevel = <CommentModel>[];
    for (final comment in comments) {
      final parentId = comment.replyToCommentId;
      if (parentId == null) {
        topLevel.add(comment);
      } else {
        repliesByParent.putIfAbsent(parentId, () => []).add(comment);
      }
    }

    final widgets = <Widget>[];
    for (final comment in topLevel) {
      final replies = repliesByParent[comment.id];
      widgets.add(_buildCommentCard(comment, ref, replies: replies));
    }
    return widgets;
  }

  // Stacked circular status-icon avatars representing repliers, up to 5 —
  // the 5th slot shows "5+" when there are more. Tap to expand/collapse the
  // actual reply cards underneath.
  Widget _buildRepliesRow(
    String parentCommentId,
    List<CommentModel> replies, {
    required bool isExpanded,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const maxAvatars = 5;
    const avatarSize = 22.0;
    const overlap = 14.0;
    final shownCount =
        replies.length > maxAvatars ? maxAvatars : replies.length;

    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.sm.h),
      child: GestureDetector(
        onTap: () => _toggleRepliesExpanded(parentCommentId),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            SizedBox(
              height: avatarSize,
              width: avatarSize + (shownCount - 1) * overlap,
              child: Stack(
                children: [
                  for (var i = 0; i < shownCount; i++)
                    Positioned(
                      left: i * overlap,
                      child: _buildReplyAvatar(
                        replies[i],
                        size: avatarSize,
                        colorScheme: colorScheme,
                        showOverflow:
                            replies.length > maxAvatars && i == maxAvatars - 1,
                        overflowCount: replies.length - (maxAvatars - 1),
                      ),
                    ),
                ],
              ),
            ),
            Gap(Spacing.sm.w),
            Text(
              '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.xs.w),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyAvatar(
    CommentModel reply, {
    required double size,
    required ColorScheme colorScheme,
    required bool showOverflow,
    required int overflowCount,
  }) {
    final statusDisplay = _getStatusDisplay(reply.relationshipStatus);
    final statusColor = _statusColorFor(statusDisplay, colorScheme);

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
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              )
              : Icon(
                _statusIconFor(statusDisplay),
                size: size * 0.5,
                color: colorScheme.background,
              ),
    );
  }

  Widget _buildCommentCard(
    CommentModel comment,
    WidgetRef ref, {
    bool showReplyAction = true,
    List<CommentModel>? replies,
  }) {
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

    return Slidable(
      key: ValueKey(comment.id),
      // Swipe right-to-left reveals Reply. Same _setReplyTarget the inline
      // "Reply" text already uses — this is an additional way to trigger it,
      // not a replacement. Replies-to-replies aren't a thing here, so a
      // reply card omits this pane entirely (showReplyAction: false).
      startActionPane:
          !showReplyAction
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                children: [
                  SlidableAction(
                    onPressed:
                        (_) => _setReplyTarget(
                          comment.id,
                          comment.content.length > 60
                              ? '${comment.content.substring(0, 60)}...'
                              : comment.content,
                        ),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    icon: Icons.reply,
                    label: 'Reply',
                  ),
                ],
              ),
      // Swipe left-to-right reveals Report (others' comments) or Delete
      // (own comments) — same actions already in the ⋮ menu below. A full
      // swipe past the button fires the action on release, same as iOS
      // Mail — Delete asks for confirmation first since it has none
      // anywhere else in this flow; Report just opens the same reason
      // picker a tap does, so nothing destructive fires without a
      // deliberate follow-up choice either way.
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        dismissible: DismissiblePane(
          confirmDismiss: () async {
            if (!isOwnComment) return false; // Report: no instant dismiss.
            return _confirmDeleteComment(context);
          },
          onDismissed: () {
            ref.read(
              deleteCommentProvider((
                commentId: comment.id,
                opinionId: widget.opinionId,
              )).future,
            );
          },
        ),
        children: [
          if (!isOwnComment)
            SlidableAction(
              onPressed: (_) => _showReportDialog(context, ref, comment.id),
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.flag_outlined,
              label: 'Report',
            ),
          if (isOwnComment)
            SlidableAction(
              onPressed: (_) async {
                if (await _confirmDeleteComment(context)) {
                  await ref.read(
                    deleteCommentProvider((
                      commentId: comment.id,
                      opinionId: widget.opinionId,
                    )).future,
                  );
                }
              },
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            bottomWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Like button (simplified - no dislike for comments in v1? Spec allows both)
                    _buildCommentReactionButton(
                      icon: Icons.favorite_border_outlined,
                      activeIcon: Icons.favorite,
                      count: comment.likeCount,
                      isActive:
                          false, // Would need userReaction field on CommentModel
                      onTap: () {
                        // Implement like/unlike
                      },
                    ),
                    if (showReplyAction) ...[
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
                    ],
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
                // Replies: stacked avatars + expand toggle, inside this
                // comment's own bottomWidget (ahead of InfoRowWidget's
                // divider) so they read as belonging to this comment rather
                // than looking like a separate section below the divider.
                if (replies != null && replies.isNotEmpty) ...[
                  _buildRepliesRow(
                    comment.id,
                    replies,
                    isExpanded: _expandedReplies.contains(comment.id),
                  ),
                  if (_expandedReplies.contains(comment.id))
                    Padding(
                      padding: EdgeInsets.only(left: Spacing.lg.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final reply in replies)
                            _buildCommentCard(
                              reply,
                              ref,
                              showReplyAction: false,
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
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
          Icon(
            isActive ? activeIcon : icon,
            size: 14,
            color: isActive ? Colors.pink : Colors.grey,
          ),
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
