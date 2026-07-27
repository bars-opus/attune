// lib/features/opinions/presentation/screens/comment_thread_screen.dart

import 'dart:async';

import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/poll_card.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/opinions/data/models/comment_model.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
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

  // Inline edit state (§8.11 "Editing"). Only ONE comment can be in edit mode
  // at a time — a second Edit replaces the first — so a single id plus a
  // single controller is the whole model here. Editing happens in place
  // rather than on a pushed screen: a comment is at most 280 characters and
  // its meaning depends on the thread around it, so replacing the text with a
  // field keeps the parent comment and sibling replies visible while typing.
  String? _editingCommentId;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  bool _isSavingEdit = false;

  void _startEditingComment(CommentModel comment) {
    setState(() {
      _editingCommentId = comment.id;
      _editController.text = comment.content;
    });
    _editFocusNode.requestFocus();
  }

  void _cancelEditingComment() {
    setState(() {
      _editingCommentId = null;
      _editController.clear();
    });
  }

  /// Saves an inline comment edit. The 15-minute window is enforced by the
  /// RPC, so a window that lapses while the field is open surfaces here as a
  /// snackbar rather than being silently swallowed.
  Future<void> _saveCommentEdit(CommentModel comment) async {
    final content = _editController.text.trim();
    if (content.isEmpty || _isSavingEdit) return;
    // Nothing changed — close the field rather than stamping an "(edited)"
    // marker on a comment nobody actually edited.
    if (content == comment.content.trim()) {
      _cancelEditingComment();
      return;
    }

    setState(() => _isSavingEdit = true);
    try {
      await editComment(
        ref,
        commentId: comment.id,
        content: content,
        opinionId: widget.opinionId,
      );
      if (mounted) _cancelEditingComment();
    } catch (error) {
      if (mounted) {
        final text = error.toString();
        context.showInfoSnackbar(
          text.contains('not_editable')
              ? 'That comment can no longer be edited — the 15-minute '
                  'window has closed.'
              : text.contains('invalid_content')
              ? 'A comment must be between 1 and 280 characters.'
              : 'Could not save that edit.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingEdit = false);
    }
  }

  /// Whether this comment can still be edited: yours, and inside the window.
  /// UX only — edit_opinion_comment re-checks both server-side.
  bool _canEditComment(CommentModel comment) {
    return comment.isMine &&
        DateTime.now().difference(comment.createdAt) < kOpinionEditWindow;
  }

  // Shared with a reply's own InfoRowWidget.avatarRadius, so a reply's
  // leading avatar stays the same size once expanded as it was stacked in
  // the collapsed row above it.
  static const _replyAvatarSize = 22.0;

  // How many of a parent comment's replies are currently visible, keyed by
  // parent comment id. Absent (or 0) means collapsed. Revealed in batches
  // of 5 via "See more" rather than all at once.
  static const _replyBatchSize = 5;
  final Map<String, int> _visibleReplyCounts = {};

  // Ids seen on a prior build, so a freshly-posted comment can be told
  // apart from ones that were already in the list — only ids that show up
  // for the first time after the initial load get the slide-in entrance.
  // Null until the first successful load, so existing comments never
  // animate on first open.
  Set<String>? _knownCommentIds;

  Set<String> _newCommentIds(List<CommentModel> comments) {
    final ids = comments.map((c) => c.id).toSet();
    final previouslyKnown = _knownCommentIds;
    _knownCommentIds = ids;
    if (previouslyKnown == null) return const {};
    return ids.difference(previouslyKnown);
  }

  void _revealFirstReplyBatch(String parentCommentId) {
    setState(() => _visibleReplyCounts[parentCommentId] = _replyBatchSize);
  }

  void _revealMoreReplies(String parentCommentId, int totalReplies) {
    setState(() {
      final current = _visibleReplyCounts[parentCommentId] ?? 0;
      final next = current + _replyBatchSize;
      _visibleReplyCounts[parentCommentId] =
          next > totalReplies ? totalReplies : next;
    });
  }

  void _collapseReplies(String parentCommentId) {
    setState(() => _visibleReplyCounts.remove(parentCommentId));
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
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
      await postComment(
        ref,
        opinionId: widget.opinionId,
        content: content,
        replyToCommentId: _replyToCommentId,
        quotedText: _replyToQuotedText,
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
          // This screen renders the opinion from the immutable `widget.opinion`
          // it was constructed with, not from a provider, so it cannot show
          // the new text in place. Popping back to the feed — whose copy
          // editOpinion has already patched — is what makes the edit visible,
          // and matches what Delete above already does.
          onEdit: () async {
            Navigator.pop(sheetContext);
            final edited = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => EditOpinionScreen(opinion: widget.opinion),
              ),
            );
            if (edited == true && context.mounted) Navigator.pop(context);
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
        body: Stack(
          children: [
            // Opinion + comment list, opinion pinned as the list's first item
            // so it scrolls away with the comments rather than staying fixed.
            // Bottom padding reserves room so the last comment doesn't sit
            // behind the floating input.
            //
            // The opinion card renders from widget.opinion (already
            // available synchronously, not itself async) unconditionally —
            // only the comments section below it swaps for a loading/error
            // state, so a refetch doesn't blank out the already-loaded
            // opinion or the floating input underneath.
            // Pull-to-refresh is the one deliberate way another user's new
            // comments, edits, or likes reach this screen — everything YOUR
            // OWN actions do (post/edit/delete/like) already patches the list
            // locally and instantly, so a refetch here is never a side effect
            // of something the viewer themselves just did.
            RefreshIndicator(
              onRefresh:
                  () =>
                      ref
                          .read(commentsProvider(widget.opinionId).notifier)
                          .refresh(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  Spacing.md.w,
                  Spacing.md.h,
                  Spacing.md.w,
                  Spacing.xxl.h + Spacing.xl.h,
                ),
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
                  // The opinion's poll, if it has one (§8.11). Renders nothing
                  // when there is no poll, which is the common case.
                  PollCard(target: PollTarget.opinion(widget.opinion.id)),
                  Gap(Spacing.md.h),
                  commentsAsync.when(
                    loading:
                        () => const ListviewLoadingShimmer(isComment: true),
                    error: (error, stack) => ErrorStateWidget.from(error),
                    data: (comments) {
                      if (comments.isEmpty) {
                        return Center(
                          child: EmptyStateWidget(
                            icon: Icons.comment,
                            title: 'No comments yet',
                            subtitle:
                                'What do you think? Feel free to drop your opnion',
                          ),
                        );
                      }
                      return Column(
                        children: _buildCommentThread(comments, ref),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Floating input, overlaid on the list rather than stacked in
            // flow below it — comments keep scrolling visibly behind/through
            // it instead of being blocked by an opaque full-width bar.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Spacing.md.w,
                    0,
                    Spacing.md.w,
                    Spacing.sm.h,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Reply indicator
                      if (_replyToCommentId != null)
                        AnimatedScaleFade(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutBack,

                          child: CardInkWell(
                            padding: const EdgeInsets.only(left: Spacing.md),
                            margin: const EdgeInsets.all(0),
                            child: Padding(
                              padding: const EdgeInsets.only(left: Spacing.md),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ShakeTransition(
                                      duration: const Duration(
                                        milliseconds: 800,
                                      ),
                                      curve: Curves.easeOutBack,
                                      child: RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Replying to',
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme.primary,
                                                  ),
                                            ),
                                            TextSpan(
                                              text:
                                                  '\n${_replyToQuotedText?.substring(0, (_replyToQuotedText!.length > 40) ? 40 : _replyToQuotedText!.length)}...',
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme.onSurface
                                                        .withValues(alpha: 0.8),
                                                  ),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                  ),
                                  ShakeTransition(
                                    offset: -140,
                                    curve: Curves.easeOutBack,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      onPressed: _clearReplyTarget,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      // Comment input, floating pill over the list instead
                      // of a full-width opaque bar.
                      ChatTextField(
                        controller: _commentController,
                        focusNode: _commentFocusNode,
                        onSend: _postComment,
                        enabled: !_isSubmitting,
                        hintText: 'Add a comment...',
                      ),
                    ],
                  ),
                ),
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
    final newIds = _newCommentIds(comments);

    // commentsProvider returns oldest-first (needed so each reply group
    // reads top-to-bottom in the order it was actually written). Top-level
    // comments get reversed to newest-first here, client-side, so a
    // freshly-posted comment lands at the top of the list — immediately
    // visible without scrolling — while replies inside a thread keep
    // reading chronologically.
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
    final orderedTopLevel = topLevel.reversed;

    final widgets = <Widget>[];
    for (final comment in orderedTopLevel) {
      final replies = repliesByParent[comment.id];
      widgets.add(
        _buildCommentCard(
          comment,
          ref,
          replies: replies,
          isNew: newIds.contains(comment.id),
          newIds: newIds,
        ),
      );
    }
    return widgets;
  }

  // Heading for the replies section — reply count + expand toggle. Always
  // visible, collapsed or expanded; tapping it toggles between the two
  // (expand reveals the first batch; collapse fully hides all revealed
  // batches). The stacked repliers preview only shows while collapsed —
  // once the actual replies are visible below, the preview is redundant.
  Widget _buildRepliesRow(
    String parentCommentId,
    List<CommentModel> replies, {
    required bool isExpanded,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    const maxAvatars = 5;
    const avatarSize = _replyAvatarSize;
    const overlap = 14.0;
    final shownCount =
        replies.length > maxAvatars ? maxAvatars : replies.length;

    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.sm.h),
      child: GestureDetector(
        onTap:
            () =>
                isExpanded
                    ? _collapseReplies(parentCommentId)
                    : _revealFirstReplyBatch(parentCommentId),
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            if (!isExpanded) ...[
              AnimatedScaleFade(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutBack,

                child: SizedBox(
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
                                replies.length > maxAvatars &&
                                i == maxAvatars - 1,
                            overflowCount: replies.length - (maxAvatars - 1),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Gap(Spacing.sm.w),
            ],
            ShakeTransition(
              offset: -140,
              curve: Curves.easeOutBack,
              child: Text(
                '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
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

  // Row shown under each revealed batch of replies: "See more" (only while
  // more remain) plus a close icon at the far end that always fully
  // re-collapses back to the stacked-avatar row, even on the last batch.
  Widget _buildRepliesBatchFooter(
    String parentCommentId,
    int visibleCount,
    int totalReplies,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasMore = visibleCount < totalReplies;

    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.sm.h),
      child: Row(
        children: [
          if (hasMore)
            GestureDetector(
              onTap: () => _revealMoreReplies(parentCommentId, totalReplies),
              behavior: HitTestBehavior.opaque,
              child: Text(
                'See more',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: () => _collapseReplies(parentCommentId),
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  // The currently-visible batch of reply cards plus the batch footer
  // (See more / close) underneath.
  Widget _buildExpandedReplies(
    String parentCommentId,
    List<CommentModel> replies,
    WidgetRef ref, {
    Set<String> newIds = const {},
  }) {
    final visibleCount = (_visibleReplyCounts[parentCommentId] ?? 0).clamp(
      0,
      replies.length,
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: Spacing.md.w),
      child: Container(
        // Reddit-style thread line connecting this reply group back to its
        // parent comment. A left border on the Column paints along however
        // tall the content naturally ends up, unlike a stretched sibling
        // Container, which needs a bounded height up front and isn't
        // available here (bottomWidget sizes to its own content).
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.outlineVariant, width: .1),
          ),
        ),
        padding: EdgeInsets.only(left: Spacing.sm.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < visibleCount; i++)
              _buildCommentCard(
                replies[i],
                ref,
                showReplyAction: false,
                // No divider on any visible reply — the batch footer
                // below (See more / close) is the visual break for
                // this group, and the parent's own divider (after this
                // whole bottomWidget) separates the group from the
                // next top-level comment.
                showDivider: false,
                isNew: newIds.contains(replies[i].id),
              ),
            _buildRepliesBatchFooter(
              parentCommentId,
              visibleCount,
              replies.length,
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

  /// The in-place editor shown in a comment's own row while it is being
  /// edited: a field pre-filled with the current text, plus Cancel/Save.
  ///
  /// Deliberately plain — no character counter competing with the thread's
  /// existing chrome. The 280-char limit is enforced by maxLength here and by
  /// the RPC's `invalid_content` check regardless.
  Widget _buildInlineCommentEditor(CommentModel comment) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: Spacing.xs.h, bottom: Spacing.sm.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _editController,
            focusNode: _editFocusNode,
            enabled: !_isSavingEdit,
            maxLines: 5,
            minLines: 1,
            maxLength: 280,
            autofocus: true,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(
                horizontal: Spacing.sm.w,
                vertical: Spacing.sm.h,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
            ),
          ),
          Gap(Spacing.xs.h),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _isSavingEdit ? null : _cancelEditingComment,
                child: Text(
                  'Cancel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    _isSavingEdit ? null : () => _saveCommentEdit(comment),
                child: Text(
                  _isSavingEdit ? 'Saving…' : 'Save',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentCard(
    CommentModel comment,
    WidgetRef ref, {
    bool showReplyAction = true,
    bool showDivider = true,
    List<CommentModel>? replies,
    bool isNew = false,
    Set<String> newIds = const {},
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Server-computed; the real user_id never reaches the client (FORUM.md §3).
    final isOwnComment = comment.isMine;
    final canEditComment = _canEditComment(comment);
    final isEditing = _editingCommentId == comment.id;

    final statusDisplay = _getStatusDisplay(comment.relationshipStatus);
    final statusIcon = _statusIconFor(statusDisplay);
    final statusIconColor = _statusColorFor(
      statusDisplay,
      Theme.of(context).colorScheme,
    );
    // Same treatment as OpinionCard: the marker rides on the timestamp, and
    // the timestamp itself stays createdAt — an edit never moves it.
    final timeAgo =
        _formatTimeAgo(comment.createdAt) +
        (comment.editedAt != null ? ' · edited' : '');

    final card = Slidable(
      key: ValueKey(comment.id),
      // Swipe right-to-left reveals Reply, and Edit on your own in-window
      // comments. Same _setReplyTarget the inline "Reply" text already uses —
      // this is an additional way to trigger it, not a replacement.
      // Replies-to-replies aren't a thing here, so a reply card omits Reply
      // (showReplyAction: false) but can still be edited, which is why the
      // pane itself is gated on either action applying rather than on Reply
      // alone. Edit sits here rather than in the end pane because that pane's
      // DismissiblePane treats a full swipe as "delete this" — adding a
      // second, non-destructive action to it would make the same gesture
      // ambiguous.
      startActionPane:
          (!showReplyAction && !canEditComment)
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: canEditComment && showReplyAction ? 0.5 : 0.25,
                children: [
                  if (showReplyAction)
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
                  if (canEditComment)
                    SlidableAction(
                      onPressed: (_) => _startEditingComment(comment),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      foregroundColor: colorScheme.onSurface,
                      icon: Icons.edit_outlined,
                      label: 'Edit',
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
            deleteComment(
              ref,
              commentId: comment.id,
              opinionId: widget.opinionId,
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
                  await deleteComment(
                    ref,
                    commentId: comment.id,
                    opinionId: widget.opinionId,
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
            // Blanked while this comment is being edited — the editable field
            // in bottomWidget below takes its place, so the text appears
            // once, not twice.
            subtitle: isEditing ? '' : comment.content,
            icon: statusIcon,
            iconColor: colorScheme.background,
            backgroundColor: statusIconColor,
            // Replies keep the same avatar size they had stacked in the
            // collapsed row above, instead of jumping to the larger
            // top-level comment size once expanded.
            avatarRadius: showReplyAction ? 15.h : _replyAvatarSize,
            subTitleMaxLines: 10,
            iconSize: showReplyAction ? 12.h : _replyAvatarSize * 0.5,
            pinAvatar: true,
            onTap: () {},
            showDivider: showDivider,
            onAvatarTap: () {},
            disableTrailing: true,
            showAvatar: true,
            showTrailingArrow: false,
            bottomWidget: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inline editor, in place of this comment's text. Kept in the
                // thread rather than on a pushed screen so the parent comment
                // and sibling replies stay visible while revising.
                if (isEditing) _buildInlineCommentEditor(comment),
                Row(
                  children: [
                    _buildCommentReactionButton(
                      icon: Icons.favorite_border_outlined,
                      activeIcon: Icons.favorite,
                      count: comment.likeCount,
                      isActive: comment.likedByMe,
                      onTap: () async {
                        try {
                          await toggleCommentLiked(
                            ref,
                            opinionId: widget.opinionId,
                            commentId: comment.id,
                            isCurrentlyLiked: comment.likedByMe,
                          );
                        } catch (e) {
                          if (mounted) {
                            context.showErrorSnackbar(
                              'Could not update your like.',
                            );
                          }
                        }
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
                        } else if (value == 'edit' && canEditComment) {
                          _startEditingComment(comment);
                        } else if (value == 'delete' && isOwnComment) {
                          await deleteComment(
                            ref,
                            commentId: comment.id,
                            opinionId: widget.opinionId,
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
                            // Own comment, still inside the 15-minute window.
                            // Duplicates the Edit swipe action deliberately —
                            // the swipe is discoverable only if you try it,
                            // same reason Delete appears in both places.
                            if (canEditComment)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
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
                // The heading row stays visible whether collapsed or
                // expanded — it's what tells you you're looking at replies
                // to this comment, not a standalone comment. Revealed in
                // batches of 5 via "See more" rather than all at once.
                if (replies != null && replies.isNotEmpty) ...[
                  _buildRepliesRow(
                    comment.id,
                    replies,
                    isExpanded: (_visibleReplyCounts[comment.id] ?? 0) > 0,
                  ),
                  if ((_visibleReplyCounts[comment.id] ?? 0) > 0)
                    _buildExpandedReplies(
                      comment.id,
                      replies,
                      ref,
                      newIds: newIds,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    // Only the comment that just arrived slides in — everything already on
    // screen renders as normal, unanimated. Comments drop in from above
    // (negative Y), unlike chat/forum content which rises from below —
    // matches how this list already reads top-to-bottom, newest at top.
    return isNew
        ? SlideFadeIn(beginOffset: const Offset(0, -0.15), child: card)
        : card;
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
