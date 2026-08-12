// lib/features/forums/presentation/widgets/forum_post_bubble.dart

import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/utils/relative_time.dart';
import 'package:attune/core/widgets/reply_avatar_stack.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

/// A single forum post rendered as a chat bubble in the debate room's one
/// chronological feed.
///
/// Two axes that used to be conflated are now separate:
///   * ALIGNMENT is authorship — `post.isMine` puts the bubble right, everyone
///     else's left. This mirrors [MessageBubble] in the 1:1 chat feature
///     exactly, so the debate room reads like the group-chat thread it is.
///   * SIDE (for/against) is a badge dot on the bubble, primary for FOR and
///     colorScheme.against for AGAINST — the same token pair the rest of the
///     forums feature uses (forum_card.dart, forum_card_subdetails.dart).
///     Side no longer moves the bubble, so you can see your own AGAINST post
///     sitting on the right next to someone else's AGAINST post on the left.
///     The bubble fill itself stays authorship-only (never side-tinted) —
///     alignment already says "mine," so recoloring the fill by side too
///     was a redundant, inconsistent second signal (see conversation).
///
/// Deliberately does NOT borrow chat's read-receipt/status-chip machinery:
/// forum posts have no delivery or read concept.
class ForumPostBubble extends ConsumerStatefulWidget {
  final ForumPostModel post;
  final String userSide;
  final VoidCallback onReply;

  /// Replies to THIS post, or null when it has none. Unlike
  /// CommentThreadScreen, these are never rendered inline here — they stay
  /// in the main chronological feed at their own position (a real group
  /// chat doesn't hide a message just because it was a reply). This is only
  /// used to show the stacked-avatar "N replies" row and, via
  /// [onShowReplies], open them in a bottom sheet.
  final List<ForumPostModel>? replies;

  /// Opens the replies sheet for this post. Null when [replies] is null —
  /// the row that would trigger it doesn't render at all in that case, so
  /// there is nothing to wire.
  final VoidCallback? onShowReplies;

  /// Scrolls the main feed to this post's parent and briefly highlights it —
  /// WhatsApp-style "jump to replied message." Wired from the quoted-text
  /// preview block, which only renders when post.quotedText != null (i.e.
  /// this post IS a reply). Null in every context that can't jump — the
  /// replies bottom sheet (_RepliesSheet) has no independent scroll target
  /// of its own to jump within, so it leaves this null and the quoted block
  /// renders without a tap affordance there.
  final VoidCallback? onJumpToParent;

  /// True while this specific post is the current jump-to target — flashes
  /// the bubble border briefly so the viewer's eye lands on the right
  /// message after the scroll completes, the same visual cue WhatsApp gives.
  final bool isHighlighted;

  const ForumPostBubble({
    super.key,
    required this.post,
    required this.userSide,
    required this.onReply,
    this.replies,
    this.onShowReplies,
    this.onJumpToParent,
    this.isHighlighted = false,
  });

  @override
  ConsumerState<ForumPostBubble> createState() => _ForumPostBubbleState();
}

class _ForumPostBubbleState extends ConsumerState<ForumPostBubble> {
  bool _isLiking = false;

  Future<void> _toggleLike() async {
    if (_isLiking) return;
    // likeForumPostProvider/unlikeForumPostProvider already throw
    // 'Not authenticated' for a guest, but unguarded that surfaces as the raw
    // "Failed to like: Exception: Not authenticated" in the catch block below
    // — this stops it before the call instead.
    if (ref.read(supabaseClientProvider).auth.currentUser?.id == null) {
      context.showErrorSnackbar('Sign in to perform this action');
      return;
    }

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLiking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final post = widget.post;
    // Live cross-user like count (20260826120000_realtime_count_broadcasts.sql
    // — see opinionLiveCountsProvider's doc for the full rationale): every
    // viewer's bubble, including a guest's, ticks up the instant ANY viewer
    // likes this post, not just the one who tapped. Falls back to the post's
    // own likeCount until a broadcast lands.
    final effectiveLikeCount =
        ref.watch(postLikeLiveCountProvider(post.id)).valueOrNull ??
        post.likeCount;
    final isMine = post.isMine;
    final isForSide = post.side == 'for';
    final canReply = widget.userSide != 'browse';
    final sideColor =
        isForSide ? colorScheme.primary : colorScheme.against.withOpacity(.9);

    // Bubble fill: authorship only — your own bubble is colorScheme.primary,
    // everyone else's is colorScheme.onBackground, paired with
    // colorScheme.background for the content painted on top of it, the same
    // content/fill pairing InfoRowWidget's comment avatar already uses
    // (iconColor: colorScheme.background against a colored backgroundColor).
    // Side lives on the badge dot alone (sideColor, below) — alignment
    // already says "mine," so tinting the fill by side too was a redundant,
    // inconsistent second signal (only your own bubbles got it, not
    // everyone else's) rather than a real reinforcement. See conversation:
    // reverted after review.
    final bubbleColor = isMine ? colorScheme.primary : colorScheme.onBackground;
    final onBubbleColor =
        isMine ? colorScheme.onPrimary : colorScheme.background;

    final statusDisplay = statusDisplayFor(post.relationshipStatus);
    final statusIcon = statusIconFor(statusDisplay);
    final statusIconColor = statusColorFor(statusDisplay, colorScheme);
    // Same "(edited)" treatment as OpinionCard and the comment cards
    // (FORUM.md §7 "Editing"): rides on the timestamp, muted, no history.
    // Live now that `public_forum_posts` projects `edited_at`
    // (20260730140000_forum_post_edit_view_columns.sql).
    final timeAgo =
        formatTimeAgo(post.createdAt) +
        (post.editedAt != null ? ' · edited' : '');

    return UniversalBubble(
      isMine: isMine,
      bubbleColor: bubbleColor,
      onBubbleColor: onBubbleColor,
      quotedText: post.quotedText,
      onJumpToParent: widget.onJumpToParent,
      isHighlighted: widget.isHighlighted,
      // Restores the pre-refactor (UniversalBubble extraction) quote-block
      // look exactly — UniversalBubble's own defaults are chat's newer
      // styling, which is a visual regression for forums since forums had
      // this exact quote-block appearance before the extraction.
      quoteBackgroundColor: colorScheme.onBackground.withOpacity(0.5),
      quoteForegroundColor: colorScheme.background,
      quoteTextStyle: textTheme.bodySmall?.copyWith(
        color: colorScheme.background,
      ),
      quoteIconSize: 30.h,
      // Highlight-flash ring uses sideColor (for/against), not bubbleColor —
      // a ring drawn in the bubble's own fill is invisible against that
      // fill. This is the same sideColor the pre-refactor AnimatedContainer
      // border used directly.
      highlightColor: sideColor,
      // Preserves per-post slide-open/closed identity in the chronological
      // feed list, same as the pre-refactor Slidable's own key.
      slidableKey: ValueKey(post.id),
      // Status avatar — same statusIcon/statusColorFor pairing InfoRowWidget
      // uses for a comment's leading avatar in CommentThreadScreen. Only
      // shown for other contributors: your own bubble is already picked out
      // by sitting on the right in `colorScheme.primary`, so repeating your
      // own status here would be redundant with the alignment that already
      // marks it as yours.
      leading:
          isMine
              ? null
              : CircleAvatar(
                radius: 14.r,
                backgroundColor: statusIconColor,
                child: Icon(
                  statusIcon,
                  size: 14.r,
                  color: colorScheme.background,
                ),
              ),
      // Swipe right-to-left reveals Reply (only when canReply — browse mode
      // has nothing to reply with, so there is no pane at all). A FULL swipe
      // past the threshold fires Reply directly (DismissiblePane) instead of
      // requiring a tap once revealed — same interchange
      // CommentThreadScreen's cards just got: Reply is non-destructive, so
      // it's safe on release.
      startActionPane:
          !canReply
              ? null
              : ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.25,
                // Reply doesn't remove the post from the feed, so this must
                // NEVER actually dismiss — see
                // CommentThreadScreen._buildCommentCard's identical pattern
                // for why: firing widget.onReply from confirmDismiss and
                // vetoing (returning false) gets DismissiblePane's
                // past-threshold drag detection without entering its
                // resize/removal flow, which would otherwise throw "A
                // dismissed Slidable widget is still part of the tree" once
                // the post survives to the next build.
                dismissible: DismissiblePane(
                  confirmDismiss: () async {
                    widget.onReply();
                    return false;
                  },
                  onDismissed: () {},
                  // closeOnCancel defaults to false, which leaves a vetoed
                  // dismiss wherever the drag ended instead of snapping the
                  // pane shut — explicit true so the full-swipe-to-reply
                  // gesture always closes afterward, matching
                  // CommentThreadScreen.
                  closeOnCancel: true,
                ),
                children: [
                  SlidableAction(
                    onPressed: (_) => widget.onReply(),
                    backgroundColor: sideColor,
                    foregroundColor:
                        isForSide ? colorScheme.onPrimary : colorScheme.onAgainst,
                    icon: Icons.reply,
                    label: 'Reply',
                  ),
                ],
              ),
      // Swipe left-to-right reveals Report (others' posts) or Delete (your
      // own) — tap-only, no DismissiblePane: Delete is destructive, so a
      // full swipe just reveals the pane instead of auto-firing, matching
      // CommentThreadScreen's end pane after the same interchange. Delete
      // confirms first either way.
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          if (!isMine)
            SlidableAction(
              onPressed: (_) => _showReportDialog(),
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              icon: Icons.flag_outlined,
              label: 'Report',
            ),
          if (isMine)
            SlidableAction(
              onPressed: (_) async {
                if (await _confirmDeletePost(context)) {
                  await deleteForumPost(
                    ref,
                    postId: post.id,
                    topicId: post.topicId,
                    side: post.side,
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
      content: Text(
        post.content,
        style: textTheme.bodyMedium?.copyWith(color: onBubbleColor),
      ),
      // Meta row below the bubble (chat puts its time label here too): time,
      // like, reply, report, side badge. Kept outside the bubble so a
      // compact bubble stays readable. Stacked reply avatars (when present)
      // append below it — same overlapping-circle language
      // CommentThreadScreen uses, but tapping opens all replies in a bottom
      // sheet (as bubbles) instead of expanding in place. Replies themselves
      // stay inline in the main feed at their own chronological position;
      // this row is just a shortcut into that subset.
      footer: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment:
                isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                timeAgo,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Gap(Spacing.sm.w),
              // Like
              InkWell(
                onTap: _toggleLike,
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                child: Padding(
                  padding: EdgeInsets.all(Spacing.xs.w),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        post.userLiked ? Icons.favorite : Icons.favorite_border,
                        size: 16,
                        color:
                            post.userLiked
                                ? colorScheme.error
                                : colorScheme.onSurface.withOpacity(0.6),
                      ),
                      if (effectiveLikeCount > 0) ...[
                        Gap(Spacing.xs.w),
                        AnimatedRollingCounter(
                          count: effectiveLikeCount,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (canReply) ...[
                Gap(Spacing.sm.w),
                InkWell(
                  onTap: widget.onReply,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.xs.w),
                    child: Text(
                      'Reply',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              Gap(Spacing.xs.w),
              _SideBadge(sideColor: sideColor),
              SizedBox(
                height: 24.h,
                width: 24.w,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'More',
                  icon: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  onSelected: (value) {
                    if (value == 'report') _showReportDialog();
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('Report'),
                        ),
                      ],
                ),
              ),
            ],
          ),
          if (widget.replies != null && widget.replies!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: Spacing.xs.h,
                right: Spacing.xl,
                left: Spacing.xl,
              ),
              child: RepliesRow(
                replyStatuses: [
                  for (final reply in widget.replies!) reply.relationshipStatus,
                ],
                replyCount: widget.replies!.length,
                alignEnd: isMine,
                avatarSize: 18,
                overlap: 12,
                maxAvatars: 3,
                accentColor: colorScheme.primary,
                onTap: widget.onShowReplies!,
              ),
            ),
        ],
      ),
    );
  }

  // Bridges ConfirmationDialog's VoidCallback onto the Future<bool>
  // DismissiblePane.confirmDismiss / tap-path expect — same bridge
  // CommentThreadScreen._confirmDeleteComment uses, so a swipe-to-reveal +
  // tap on Delete still asks before removing the post.
  Future<bool> _confirmDeletePost(BuildContext context) {
    final completer = Completer<bool>();
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 320.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.destructive,
        title: 'Delete this contribution?',
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

  void _showReportDialog() {
    // Guarded before the reason list opens, not on submit: report_forum_post
    // is authenticated-only, so a guest would otherwise pick a reason and hit
    // an unhandled exception from reportForumPostProvider's own
    // 'Not authenticated' throw instead of an explanation.
    if (ref.read(supabaseClientProvider).auth.currentUser?.id == null) {
      context.showErrorSnackbar('Sign in to perform this action');
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
        await ref.read(
          reportForumPostProvider((
            postId: widget.post.id,
            reason: reason,
          )).future,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thank you. We will review this.')),
          );
        }
      },
    );
  }
}

/// The FOR / AGAINST tag carried by every bubble, mine included — a small
/// dot in the side's own color (sideColor: primary for FOR, against for
/// AGAINST). Bubble fill is authorship-only (ForumPostBubble.bubbleColor:
/// primary if mine, onBackground otherwise), never side-tinted, so the dot
/// always sits on a neutral-enough background and never needs a
/// contrast-color swap.
class _SideBadge extends StatelessWidget {
  const _SideBadge({required this.sideColor});

  final Color sideColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: Container(
        height: 10.h,
        width: 10.h,
        decoration: BoxDecoration(color: sideColor, shape: BoxShape.circle),
      ),
    );
  }
}
