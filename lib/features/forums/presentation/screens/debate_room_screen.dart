// lib/features/forums/presentation/screens/debate_room_screen.dart
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/bottom_sheet_header.dart';
import 'package:attune/core/widgets/poll_card.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/forums/data/models/forum_post_model.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_post_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DebateRoomScreen extends ConsumerStatefulWidget {
  final String topicId;
  final String topicTitle;
  final String userSide; // 'for', 'against', or 'browse'

  /// The TopicModel the caller already had in hand — every navigation site
  /// (ForumCard's onTap, SideSelectionScreen) is tapping/acting on a card
  /// that already rendered this exact topic, counts included. Without this,
  /// the pinned ForumCard here re-fetches via topicDetailsProvider and
  /// renders nothing until that completes, which reads as "the whole screen
  /// is loading" even though the caller already had everything needed to
  /// paint it instantly — the same reasoning CommentThreadScreen's
  /// `required this.opinion` constructor param uses for its pinned
  /// OpinionCard. topicDetailsProvider still fetches in the background for
  /// freshness (its counts can have moved since the caller's list last
  /// loaded); this is only what paints on the very first frame.
  final TopicModel? initialTopic;

  const DebateRoomScreen({
    super.key,
    required this.topicId,
    required this.topicTitle,
    required this.userSide,
    this.initialTopic,
  });

  @override
  ConsumerState<DebateRoomScreen> createState() => _DebateRoomScreenState();
}

class _DebateRoomScreenState extends ConsumerState<DebateRoomScreen> {
  /// One controller for the one merged feed. The debate room used to run two
  /// independent columns (FOR left, AGAINST right) with a controller each;
  /// it is now a single chronological thread, so a single controller is all
  /// there is to drive.
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _postController = TextEditingController();
  final FocusNode _postFocusNode = FocusNode();
  String? _replyToPostId;
  String? _replyToQuotedText;
  bool _isSubmitting = false;

  /// One GlobalKey per rendered post, keyed by post id — lets "jump to
  /// replied message" (WhatsApp-style) find where a specific post landed in
  /// the list and scroll it into view via Scrollable.ensureVisible, which
  /// works correctly regardless of each bubble's actual height (unlike a
  /// computed ScrollController offset, which would assume uniform item
  /// heights this feed doesn't have). Built fresh each build from the
  /// current posts list rather than accumulated forever, so it never holds
  /// keys for posts that scrolled out of a since-refetched list.
  ///
  /// Only holds keys for posts SliverList has actually built — a post
  /// scrolled far enough out of view has no entry here at all (its
  /// GlobalKey exists in the delegate but Flutter never called the builder
  /// for it), which is exactly the case _jumpToPost's index-based fallback
  /// below exists to handle.
  final Map<String, GlobalKey> _postKeys = {};

  /// The most recent posts list, kept for _jumpToPost's index-based
  /// fallback (see its doc) — needs each post's position in the flat feed
  /// to estimate a scroll offset when the target isn't already built.
  List<ForumPostModel> _latestPosts = const [];

  /// The post currently flashed as the jump-to target — cleared automatically
  /// after the highlight animation's duration via a timer reset on every tap,
  /// so tapping a second quote before the first flash fades restarts the
  /// flash on the new target instead of leaving two stale highlights.
  String? _highlightedPostId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _recordVisit();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _postController.dispose();
    _postFocusNode.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  /// Scrolls the parent post identified by [parentPostId] into view and
  /// flashes it — WhatsApp/iMessage-style "jump to replied message".
  ///
  /// SliverList only builds the items currently near the viewport (plus a
  /// small cache extent) — a post far enough out of view was never built,
  /// so it has no GlobalKey/context yet and Scrollable.ensureVisible alone
  /// has nothing to scroll to. That was the original bug: this worked when
  /// the parent happened to already be built (near the visible area) and
  /// silently did nothing otherwise.
  ///
  /// Fix: when the fast path (already-built context) isn't available,
  /// estimate the target's scroll offset from its index in the flat post
  /// list — average-extent-per-item × distance from the current scroll
  /// position — and animate there first. That jump doesn't need to be
  /// pixel-accurate; it only needs to land the target inside SliverList's
  /// build window, which lets a follow-up ensureVisible do the exact
  /// alignment once the target is actually mounted.
  Future<void> _jumpToPost(String parentPostId) async {
    if (_tryEnsureVisible(parentPostId)) return;

    final index = _latestPosts.indexWhere((p) => p.id == parentPostId);
    // Not in the current list at all (a stale tap racing a refetch) —
    // nothing to scroll to. Rare: forumPostsProvider fetches every post
    // for the topic unfiltered, so in practice a reply's parent is always
    // present.
    if (index == -1 || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    // +1 accounts for the pinned topic card sliver ahead of the post list.
    final averageExtent =
        position.viewportDimension / (_postKeys.isEmpty ? 8 : _postKeys.length);
    final estimatedOffset = (index + 1) * averageExtent;

    await _scrollController.animateTo(
      estimatedOffset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );

    // The estimate rarely lands exactly on the target, but it lands close
    // enough for SliverList to have built it by now — one more frame for
    // that build to actually land, then the precise pass.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    _tryEnsureVisible(parentPostId);
  }

  /// Scrolls to [postId] and flashes it if its GlobalKey is currently
  /// mounted (built by SliverList). Returns whether it found something to
  /// scroll to — the caller falls back to an index-based jump when this
  /// returns false.
  bool _tryEnsureVisible(String postId) {
    final targetContext = _postKeys[postId]?.currentContext;
    if (targetContext == null) return false;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.5,
    );

    _highlightTimer?.cancel();
    setState(() => _highlightedPostId = postId);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedPostId = null);
    });
    return true;
  }

  void _loadPosts() {
    Future.microtask(() {
      ref.read(forumPostsProvider(widget.topicId));
    });
  }

  /// Marks this topic as visited so §10 #5's "N new posts since your last
  /// visit" counts from now. Silent-fail: the watermark is a notification
  /// nicety, never a reason to break opening a debate.
  void _recordVisit() {
    Future.microtask(() async {
      try {
        await ref.read(recordTopicVisitProvider(widget.topicId).future);
      } catch (e) {
        debugPrint('Failed to record topic visit: $e');
      }
    });
  }

  void _setReplyTarget(String postId, String contentPreview) {
    setState(() {
      _replyToPostId = postId;
      _replyToQuotedText =
          contentPreview.length > 60
              ? '${contentPreview.substring(0, 60)}...'
              : contentPreview;
    });
    _postFocusNode.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToPostId = null;
      _replyToQuotedText = null;
    });
  }

  Future<void> _submitPost() async {
    final content = _postController.text.trim();
    if (content.isEmpty || _isSubmitting) return;
    if (widget.userSide == 'browse') return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        submitForumPostProvider((
          topicId: widget.topicId,
          content: content,
          side: widget.userSide,
          replyToPostId: _replyToPostId,
          quotedText: _replyToQuotedText,
        )).future,
      );

      _postController.clear();
      _clearReplyTarget();
      ref.invalidate(forumPostsProvider(widget.topicId));
      // Wait for the refetch so the new post is actually in the list before
      // scrolling — scrolling immediately after invalidate would animate
      // toward a maxScrollExtent that doesn't include the post yet. Like
      // WhatsApp/iMessage: sending a message while scrolled up in history
      // jumps you back to the bottom to see what you just sent, rather than
      // leaving you stranded wherever you were reading.
      await ref.read(forumPostsProvider(widget.topicId).future);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Scrolls to the newest post — after sending, or after tapping Reply
  /// while scrolled up in history (so typing doesn't happen "blind" far
  /// from where the reply target and the eventual new post will land).
  /// Deferred a frame: the list needs to have laid out the new/target
  /// content before jumping to maxScrollExtent, otherwise it animates to
  /// a stale (too-short) extent.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final postsAsync = ref.watch(forumPostsProvider(widget.topicId));

    final topicAsync = ref.watch(topicDetailsProvider(widget.topicId));
    // Prefers the fresh fetch, falls back to what the caller already had in
    // hand (see widget.initialTopic's doc) — so the pinned card paints on
    // the very first frame instead of blanking out while
    // topicDetailsProvider's own network fetch is in flight.
    final topic = topicAsync.valueOrNull ?? widget.initialTopic;

    // The viewer's own side, tinting everything in the composer area that
    // used to be a fixed colorScheme.primary regardless of side (reply
    // indicator label, composer border, send button) — matches the
    // mine-bubble fill in ForumPostBubble. Meaningless in browse mode (no
    // side picked), where none of these render anyway.
    final userSideColor =
        widget.userSide == 'for' ? colorScheme.primary : colorScheme.against;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: true,
          // Same two-line title CommentThreadScreen uses: bold topic label on
          // top, contributor count underneath — computed from the same posts
          // list the feed below renders, so it never drifts from what's
          // actually showing.
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Forum',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                TextSpan(
                  text: '\n${_formatContributionCount(postsAsync.valueOrNull)}',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(.4),
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          actions: [
            AppIconButton(
              icon: Icons.more_vert_rounded,
              onPressed: () => _showForumMenu(context),
            ),
          ],
        ),
        // Stack, not Column: the reply indicator + composer float over the
        // feed as a Positioned overlay (matching CommentThreadScreen) rather
        // than sitting in a separate flat section of the body — that's what
        // keeps them background-free instead of reading as a solid bar.
        body: Stack(
          children: [
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Topic card (+ poll) — see `topic` above for the
                  // fresh-fetch-with-fallback reasoning. Only truly renders
                  // nothing when NEITHER is available (initialTopic wasn't
                  // passed AND the fetch hasn't resolved yet), which no
                  // longer happens from any in-app navigation site as of
                  // this change — every one of them already had the topic
                  // and now passes it.
                  SliverToBoxAdapter(
                    child:
                        topic == null
                            ? const SizedBox.shrink()
                            : Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.md,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Gap(Spacing.md),
                                  GestureDetector(
                                    onTap: () {
                                      // Same guest gate as the AppBar menu's
                                      // Forum Insight item — Forum Insight
                                      // stays account-only even though the
                                      // debate room itself is readable.
                                      if (_blockedForGuest()) return;
                                      context.pushNamed(
                                        'forumInsight',
                                        extra: widget.topicId,
                                      );
                                    },
                                    child: Text(
                                      topic.content,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // The topic's poll, if it has one (§8.11).
                                  // Separate from the FOR / AGAINST split and
                                  // from the vote that activated this topic —
                                  // this asks readers a question and gates
                                  // nothing. Renders nothing when the topic has
                                  // no poll.
                                  Padding(
                                    padding: EdgeInsets.only(top: Spacing.sm.h),
                                    child: PollCard(
                                      target: PollTarget.topic(widget.topicId),
                                    ),
                                  ),
                                  AppDivider(),
                                ],
                              ),
                            ),
                  ),
                  // One chronological group-chat feed: FOR and AGAINST posts
                  // merged in the order they were written, aligned by
                  // authorship (yours right, everyone else's left) with the
                  // side carried as a badge on each bubble. Only this
                  // section shows a loading indicator (the same
                  // ListviewLoadingShimmer(isComment: true) shimmer
                  // CommentThreadScreen uses) while postsAsync loads —
                  // matches CommentThreadScreen's shape exactly: pinned card
                  // always visible, only the message-list section gated on
                  // its own async state.
                  postsAsync.when(
                    loading:
                        () => const SliverToBoxAdapter(
                          child: ListviewLoadingShimmer(isComment: true),
                        ),
                    error:
                        (error, stack) => SliverToBoxAdapter(
                          child: ErrorStateWidget.from(error),
                        ),
                    data: (posts) {
                      // Read-only bookkeeping for _jumpToPost's index-based
                      // fallback (see its doc) — not a setState, this must
                      // never trigger its own rebuild mid-build.
                      _latestPosts = posts;
                      final repliesByParent = _repliesByParent(posts);
                      // forumPostsProvider already orders by created_at
                      // ascending, so the list is chronological as fetched —
                      // no re-sort here.
                      if (posts.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(Spacing.lg.w),
                            child: Text(
                              widget.userSide == 'browse'
                                  ? 'No posts yet.'
                                  : 'No posts yet. Start the debate.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return SliverPadding(
                        // Bottom padding reserves room so the last post
                        // doesn't sit behind the floating reply
                        // indicator/composer overlaid on top.
                        padding: EdgeInsets.fromLTRB(
                          0,
                          Spacing.sm.h,
                          0,
                          Spacing.xxl.h + Spacing.xl.h,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final post = posts[index];
                            final replies = repliesByParent[post.id];
                            // Registered fresh each build (see
                            // _postKeys' doc) rather than
                            // only-if-absent, so a key never survives
                            // past the post it was created for.
                            final postKey = _postKeys[post.id] = GlobalKey();
                            return KeyedSubtree(
                              key: postKey,
                              child: ForumPostBubble(
                                key: ValueKey(post.id),
                                post: post,
                                userSide: widget.userSide,
                                onReply:
                                    () =>
                                        _setReplyTarget(post.id, post.content),
                                replies: replies,
                                onShowReplies:
                                    replies == null
                                        ? null
                                        : () =>
                                            _showRepliesSheet(post.id, replies),
                                onJumpToParent:
                                    post.replyToPostId == null
                                        ? null
                                        : () =>
                                            _jumpToPost(post.replyToPostId!),
                                isHighlighted: _highlightedPostId == post.id,
                              ),
                            );
                          }, childCount: posts.length),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            // Floating reply indicator + composer, overlaid on the list
            // rather than stacked in flow below it — matches
            // CommentThreadScreen's floating input exactly (no background
            // section behind it, posts keep scrolling visibly behind it).
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
                    0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Reply indicator
                      if (_replyToPostId != null)
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
                                                    color: userSideColor,
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
                      // Composer (only if user is not in browse mode) — same
                      // floating pill + send icon as CommentThreadScreen's
                      // ChatTextField, not a full-width bar with a separate
                      // FOR/AGAINST chip and Post button. Side is already
                      // visible on every bubble via its badge, so the
                      // composer doesn't need to repeat it — but the send
                      // button IS tinted by side, matching the mine-bubble
                      // fill (ForumPostBubble.bubbleColor) so the composer
                      // reads as "you, about to add to YOUR side" rather
                      // than a fixed primary regardless of side.
                      if (widget.userSide != 'browse')
                        ChatTextField(
                          controller: _postController,
                          focusNode: _postFocusNode,
                          onSend: _submitPost,
                          enabled: !_isSubmitting,
                          hintText:
                              widget.userSide == 'for'
                                  ? 'Add to the FOR argument...'
                                  : 'Add to the AGAINST argument...',
                          sendButtonColor: userSideColor,
                          onSendButtonColor: colorScheme.background,
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

  // Unlike CommentThreadScreen's contributor estimate, this is an exact
  // count of the posts themselves (§8.11-style "N comments" phrasing) —
  // no distinct-authors math needed here, just how many contributions the
  // topic has, matching what the feed below actually shows.
  String _formatContributionCount(List<ForumPostModel>? posts) {
    if (posts == null) return '...';
    final count = posts.length;
    return count == 1 ? '1 contribution' : '$count contributions';
  }

  // Groups the flat, chronological posts list by `replyToPostId`, purely to
  // know each post's reply COUNT for its stacked-avatar row — unlike
  // CommentThreadScreen, the main feed itself stays fully flat (every post,
  // replies included, shows inline in chronological order, exactly like a
  // real group chat thread); grouping is only used to drive the "N replies"
  // indicator and the bottom sheet it opens.
  Map<String, List<ForumPostModel>> _repliesByParent(
    List<ForumPostModel> posts,
  ) {
    final byParent = <String, List<ForumPostModel>>{};
    for (final post in posts) {
      final parentId = post.replyToPostId;
      if (parentId != null) {
        byParent.putIfAbsent(parentId, () => []).add(post);
      }
    }
    return byParent;
  }

  // Opens all replies to one post as chat bubbles in a bottom sheet, rather
  // than CommentThreadScreen's in-place batched expansion — the user's
  // explicit call: forum replies look like contributions in the same chat
  // bubble style, and a bubble list reads better filling an Expanded sheet
  // than growing the main thread in place.
  void _showRepliesSheet(String parentPostId, List<ForumPostModel> replies) {
    BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.neutral,
      widget: _RepliesSheet(
        replies: replies,
        userSide: widget.userSide,
        onReply: (postId, content) {
          Navigator.pop(context);
          _setReplyTarget(postId, content);
        },
      ),
    );
  }

  /// Blocks an action a guest cannot perform and tells them why. Mirrors
  /// OpinionCard._blockedForGuest / CommentThreadScreen._blockedForGuest.
  /// widget.userSide == 'browse' is this screen's own guest signal (set by
  /// ForumCard's onTap for a signed-out caller), reused here rather than
  /// re-reading auth state a third way in the same file.
  ///
  /// Returns true when the caller should stop.
  bool _blockedForGuest() {
    if (widget.userSide != 'browse') return false;
    context.showErrorSnackbar('Sign in to perform this action');
    return true;
  }

  // AppBar action — the single entry point (insight/report) for this topic,
  // matching CommentThreadScreen's one AppIconButton(more_vert_rounded)
  // opening everything secondary behind it rather than spreading actions
  // across multiple always-visible icons.
  void _showForumMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Forum insight'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    // Guests can read a debate room but Forum Insight stays
                    // account-only — unlike the other guards in this file
                    // this is a product decision, not a stand-in for a broken
                    // RPC call: topicDetailsProvider itself is anon-readable.
                    if (_blockedForGuest()) return;
                    context.pushNamed('forumInsight', extra: widget.topicId);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Report forum'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (_blockedForGuest()) return;
                    _showReportDialog();
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Report this forum'),
            content: const Text('Report inappropriate topic or content'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await ref.read(reportForumProvider(widget.topicId).future);
                    if (context.mounted) {
                      context.showInfoSnackbar(
                        'Thank you. We will review this.',
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to report: $e')),
                      );
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
    );
  }
}

/// All replies to one post, shown as chat bubbles in a bottom sheet —
/// distinct from CommentThreadScreen's in-place batched expansion. Fits
/// this feature's own request: replies read as contributions in the same
/// bubble style as the main thread, and a bubble list fills an Expanded
/// sheet more naturally than growing in place under the parent post.
class _RepliesSheet extends StatelessWidget {
  final List<ForumPostModel> replies;
  final String userSide;

  /// (postId, content preview) — mirrors DebateRoomScreen._setReplyTarget's
  /// signature exactly, since this just forwards into it after closing the
  /// sheet.
  final void Function(String postId, String content) onReply;

  const _RepliesSheet({
    required this.replies,
    required this.userSide,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BottomSheetHeader(
          title: replies.length == 1 ? '1 reply' : '${replies.length} replies',
        ),
        Gap(Spacing.sm.h),
        // Expanded so the bubble list scrolls within a bounded height
        // instead of trying to size itself to unbounded content — the
        // sheet's own DraggableScrollableSheet supplies that bound.
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: replies.length,
              itemBuilder: (context, index) {
                final reply = replies[index];
                return ForumPostBubble(
                  key: ValueKey(reply.id),
                  post: reply,
                  userSide: userSide,
                  onReply: () => onReply(reply.id, reply.content),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
