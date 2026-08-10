// lib/features/opinions/presentation/widgets/opinion_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/utils/relative_time.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/core/widgets/tag_chip_row.dart';
import 'package:attune/features/opinions/presentation/widgets/quoted_opinion_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/widgets/poll_card.dart';
import 'package:attune/core/polls/presentation/providers/poll_providers.dart';

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

    // Live cross-user counts (see opinionLiveCountsProvider + FORUM.md-safe
    // 20260826120000_realtime_count_broadcasts.sql): every card showing this
    // opinion, including a guest's, ticks up the instant ANY viewer reacts —
    // not just the one who tapped. Falls back to the feed row's own counts
    // until a broadcast actually lands (valueOrNull is null pre-first-event),
    // and again whenever this card is rebuilt with a fresher opinion row
    // (e.g. after a pull-to-refresh) — the broadcast is a live nudge on top
    // of the feed data, not a replacement source of truth for it.
    final liveCounts = ref.watch(opinionLiveCountsProvider(opinion.id)).valueOrNull;
    final effectiveLikeCount = liveCounts?.likeCount ?? opinion.likeCount;
    final effectiveDislikeCount = liveCounts?.dislikeCount ?? opinion.dislikeCount;

    final statusDisplay = statusDisplayFor(opinion.relationshipStatus);
    final statusIcon = statusIconFor(statusDisplay);
    final statusIconColor = statusColorFor(
      statusDisplay,
      Theme.of(context).colorScheme,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // "(edited)" rides on the timestamp rather than being its own element
    // (§8.11 "Visibility"): it is metadata about when/whether this text
    // changed, so it belongs with the time, and appending it to the same
    // muted Text keeps it subtle instead of competing with the actions row.
    // The timestamp itself stays createdAt — an edit never changes it.
    //
    // matchedTagSlug rides the same line for the same reason: it explains
    // WHY this card is on screen (see get_following_opinions' own comment
    // for the precedence rule — set only when a followed tag, not a
    // followed author, is the sole reason), which is exactly the kind of
    // quiet provenance note this line already carries. Only ever non-null
    // on a Following-tab card, so this is a no-op everywhere else.
    final timeAgo =
        formatTimeAgo(opinion.createdAt) +
        (opinion.editedAt != null ? ' · edited' : '') +
        (opinion.matchedTagSlug != null
            ? ' · #${opinion.matchedTagSlug} · followed'
            : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero'd between the feed card and CommentThreadScreen's header —
        // the opinion itself transitions, not its actions row below.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            0,
          ),
          child: Hero(
            tag: _heroTag,
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                onTap: onOpinionTap,
                behavior: HitTestBehavior.opaque,
                child: InfoRowWidget(
                  title: '',
                  subtitle: opinion.content,

                  subTitleFontSize: 20.h,
                  subTitleFontColor: colorScheme.onBackground,

                  icon: statusIcon,

                  iconColor: colorScheme.background,
                  backgroundColor: statusIconColor,
                  avatarRadius: 20.h,
                  subTitleMaxLines: showCommentAction ? 10 : 1000,
                  iconSize: 18.h,
                  onTap: onOpinionTap,
                  showDivider: false,
                  pinAvatar: true,
                  padAvatarTop: true,
                  onAvatarTap: onProfileTap,
                  disableTrailing: true,
                  showAvatar: true,
                  showTrailingArrow: false,
                  bottomWidget: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      PollCard(target: PollTarget.opinion(opinion.id)),
                      // This opinion is a quote: embed the original beneath
                      // its own text (§8.11 "Feed visibility"). Resolved
                      // lazily per card — the feed RPC returns only the id.
                      if (opinion.quotedOpinionId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.sm),
                          child: QuotedOpinionPreview(
                            quotedOpinionId: opinion.quotedOpinionId!,
                          ),
                        ),
                      // Tags sit directly under the content (and under any
                      // quoted original, which belongs to the text above them)
                      // but above the reactions row, so they read as metadata
                      // about the post rather than as another action.
                      // Renders nothing at all when untagged, which is most
                      // posts — TagChipRow collapses to a zero-size box, so no
                      // empty gap appears on the majority of cards.
                      TagChipRow(
                        tags: opinion.tags,
                        fontSize: 14.h,
                        onTagTap:
                            (slug) =>
                                context.pushNamed('tagBrowse', extra: slug),
                      ),

                      Text(
                        timeAgo,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.md),
                        child: Row(
                          // Defaults to center, which sat the bare-icon Follow
                          // and More buttons visibly lower than the labeled
                          // reaction buttons beside them (each of those is a
                          // Column with its icon pinned at the very top, above
                          // a label line — taller than a plain icon, so
                          // centering the row let it sink below their tops).
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildActionButton(
                              context: context,
                              icon: FontAwesomeIcons.heart,
                              activeIcon: FontAwesomeIcons.solidHeart,
                              count: effectiveLikeCount,
                              isActive: opinion.userReaction == 'like',
                              onTap:
                                  () => _toggleReaction(context, ref, 'like'),
                            ),
                            Gap(Spacing.md.w),
                            _buildActionButton(
                              context: context,
                              icon: Icons.thumb_down_outlined,
                              activeIcon: Icons.thumb_down,
                              count: effectiveDislikeCount,
                              isActive: opinion.userReaction == 'dislike',
                              onTap:
                                  () =>
                                      _toggleReaction(context, ref, 'dislike'),
                            ),
                            // Repost. Hidden entirely on your own post: the RPC
                            // raises cannot_repost_own_opinion, and the same
                            // isOwnPost gate already hides the Follow button
                            // below, so a disabled-but-present control would be
                            // the odd one out in this row.
                            if (!isOwnPost) ...[
                              Gap(Spacing.md.w),
                              _buildActionButton(
                                context: context,
                                // font_awesome_flutter's free tier ships `repeat`
                                // as solid-only (there is no solidRepeat), so the
                                // outline/solid swap the heart uses isn't
                                // available — omitting activeIcon falls back to
                                // the same glyph, and the primary-color tint
                                // carries the active state instead.
                                icon: FontAwesomeIcons.repeat,
                                count: opinion.repostCount,
                                isActive: opinion.isRepostedByMe,
                                onTap: () => _toggleRepost(context, ref),
                                onLabelTap:
                                    opinion.repostCount > 0
                                        ? () => _openEngagement(context, 1)
                                        : null,
                              ),
                            ],
                            // Save. The only button here with no number: a save
                            // is private to the saver, so there is no public
                            // count to show (see 20260727140000_opinion_saves
                            // — there is deliberately no saved_count column).
                            // Passes an empty label rather than null so it
                            // still reserves the text line and stays on the
                            // same baseline as the counted buttons beside it.
                            // Rendered for your own posts too — bookmarking is
                            // a personal filing action, not a public
                            // endorsement.
                            Gap(Spacing.md.w),
                            _buildActionButton(
                              context: context,
                              icon: FontAwesomeIcons.bookmark,
                              activeIcon: FontAwesomeIcons.solidBookmark,
                              showEmptyLabel: true,
                              isActive: opinion.isSaved,
                              onTap: () => _toggleSave(context, ref),
                            ),
                            // Quote. Unlike repost above, this is NOT hidden on
                            // your own post: quoting yourself to add a follow-up
                            // thought is an explicitly allowed, distinct action
                            // (§8.11 "Self-quote is allowed"), and the RPC has no
                            // owner check to trip. Uses `quoteLeft` (a bare
                            // open-quote glyph) rather than a filled speech
                            // bubble: the row already spends a bubble-ish glyph
                            // on comments, and a quotation mark is the one mark
                            // readers already parse as "quoting."
                            Gap(Spacing.md.w),
                            _buildActionButton(
                              context: context,
                              icon: FontAwesomeIcons.quoteLeft,
                              count: opinion.quoteCount,
                              onTap: () => _openQuoteComposer(context, ref),
                              onLabelTap:
                                  opinion.quoteCount > 0
                                      ? () => _openEngagement(context, 0)
                                      : null,
                            ),
                            if (showCommentAction) ...[
                              Gap(Spacing.md.w),
                              _buildActionButton(
                                context: context,
                                icon: Icons.edit,
                                count: opinion.commentCount,
                                onTap: onCommentTap ?? () {},
                              ),
                            ],

                            const Spacer(),

                            if (showFollowButton && !isOwnPost)
                              _buildFollowButton(context, ref),
                            Gap(Spacing.md.w),
                            if (showMoreButton) ...[
                              _buildMoreButton(context, ref),
                              Gap(Spacing.md.w),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AppDivider(),
      ],
    );
  }

  /// Blocks an action a guest cannot perform and tells them why.
  ///
  /// Every control on this card stays visible and tappable when signed out —
  /// the affordance is real, the action just needs an account. Each of these
  /// calls an authenticated-only RPC, so without this the tap would surface a
  /// raw permission error instead of an explanation.
  ///
  /// Returns true when the caller should stop.
  bool _blockedForGuest(BuildContext context, WidgetRef ref) {
    if (ref.read(currentUserIdProvider) != null) return false;
    context.showErrorSnackbar('Sign in to perform this action');
    return true;
  }

  Widget _buildMoreButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showOpinionMenu(context, ref),
      child: Icon(
        Icons.more_horiz,
        size: 18.h,
        color: Theme.of(context).colorScheme.onSurface,
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
            // Guarded before the reason sheet rather than on submit: report_opinion
            // is authenticated-only, so a guest would otherwise pick a reason and
            // still be told "we will review this" after the call had failed.
            if (_blockedForGuest(context, ref)) return;
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
          onHide: () {
            Navigator.pop(sheetContext);
            _hideOpinion(context, ref);
          },
          onMute: () {
            Navigator.pop(sheetContext);
            _muteAuthor(context, ref);
          },
          onEdit: () {
            Navigator.pop(sheetContext);
            _openEditor(context, ref);
          },
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final section in sections)
                  for (final item in section.items)
                    SettingsItem(config: item, showDivider: false),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Hides this opinion from the viewer's own feeds (§8.11 "Muting and
  /// hiding").
  ///
  /// The card disappears from Discover/Following on tap — the provider removes
  /// it optimistically and the feed RPCs exclude it from every later fetch.
  /// No undo is offered: this codebase has no undo-snackbar pattern for
  /// content actions today, and hide is deliberately low-stakes and reversible
  /// server-side rather than something to guard with a countdown.
  Future<void> _hideOpinion(BuildContext context, WidgetRef ref) async {
    if (_blockedForGuest(context, ref)) return;
    try {
      await hideOpinionFromFeed(ref, opinionId: opinion.id);
      if (!context.mounted) return;
      context.showInfoSnackbar('Hidden. You will not see this again.');
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar('Could not hide that.');
    }
  }

  /// Mutes this opinion's author, clearing their posts from the viewer's
  /// passive feeds (§8.11).
  ///
  /// Silent and one-directional: the muted author is never told, exactly as
  /// follows are already silent. Keyed on the opaque handle — the client has
  /// no user_id to mute with (FORUM.md §3).
  Future<void> _muteAuthor(BuildContext context, WidgetRef ref) async {
    if (_blockedForGuest(context, ref)) return;
    // Belt-and-braces: the menu item is not rendered when isMine, but muting
    // yourself would empty your own posts out of your feeds for no purpose.
    if (opinion.isMine) return;
    try {
      await muteAuthorFromFeed(ref, authorHandle: opinion.authorHandle);
      if (!context.mounted) return;
      context.showInfoSnackbar("You won't see posts from this person anymore.");
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar('Could not mute that person.');
    }
  }

  /// Opens the quotes/reposts list for this opinion, landing on whichever tab
  /// the tapped count belongs to (0 = Quotes, 1 = Reposts).
  ///
  /// No guest guard: this is a read, and both RPCs behind it are granted to
  /// anon like the feed itself.
  void _openEngagement(BuildContext context, int initialTab) {
    context.pushNamed(
      'opinionEngagement',
      extra: (opinionId: opinion.id, initialTab: initialTab),
    );
  }

  /// The single control used by every button in the actions row — like,
  /// dislike, repost, save, quote and comment. They differ only in whether
  /// they can be active and whether they carry a count, so both are optional
  /// rather than each button owning a near-identical builder.
  ///
  /// [activeIcon] defaults to [icon]: repost has no filled variant in
  /// font_awesome_flutter's free tier (there is no solidRepeat), so its active
  /// state is carried by the primary-color tint alone.
  ///
  /// [count] distinguishes three cases deliberately: null with
  /// [showEmptyLabel] false drops the text line entirely (nothing here has
  /// this today, kept for completeness); null with [showEmptyLabel] true
  /// keeps the line reserved so save (which has no public count — a save is
  /// private to the saver) still lines up with its counted neighbours
  /// instead of sitting higher in the row; a non-null count renders an
  /// AnimatedRollingCounter that animates on change and blanks at zero the
  /// same way the old literal-"0"-hiding label did.
  /// [onLabelTap] makes the NUMBER its own tap target, separate from the icon:
  /// tapping the repeat glyph reposts, tapping the count beside it opens the
  /// list of who did. Without the split there would be no way to reach that
  /// list without also toggling your own repost. Only wired where a list
  /// exists to open, and only when the count is non-zero — a "0" that opens an
  /// empty screen is worse than a "0" that does nothing.
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
    IconData? activeIcon,
    int? count,
    bool showEmptyLabel = false,
    bool isActive = false,
    VoidCallback? onLabelTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final labelStyle = textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface.withValues(alpha: 0.8),
    );

    Widget labelText() {
      final text =
          (count != null && count > 0)
              ? AnimatedRollingCounter(count: count, style: labelStyle)
              : Text('', style: labelStyle);
      if (onLabelTap == null) return text;
      return GestureDetector(
        onTap: onLabelTap,
        // Opaque so the whole (small) number box is tappable, not just the
        // glyph pixels — the counts are 1-2 characters wide.
        behavior: HitTestBehavior.opaque,
        child: text,
      );
    }

    final showLabel = count != null || showEmptyLabel;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            isActive ? (activeIcon ?? icon) : icon,
            size: 16.h,
            color: isActive ? colorScheme.primary : null,
          ),
          if (showLabel) ...[Gap(Spacing.xs.w), labelText()],
        ],
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context, WidgetRef ref) {
    final followState = ref.watch(followStatusProvider(opinion.authorHandle));
    final isFollowing = followState.valueOrNull ?? false;

    return AppIconButton(
      iconSize: 20.h,
      size: 14.h,
      icon:
          isFollowing
              ? Icons.person_remove_outlined
              : Icons.person_add_outlined,
      // label: isFollowing ? 'Following' : 'Follow',
      onPressed: () => _toggleFollow(context, ref, isFollowing),
    );
  }

  /// Neither followUserProvider nor unfollowUserProvider catch their own
  /// errors, unlike toggleOpinionSaved — wrapped here the same way
  /// _toggleSave wraps its own RPC call, so a failure surfaces as a snackbar
  /// instead of an uncaught exception.
  ///
  /// Only a NEW follow gets a success snackbar: the icon swap alone (person-
  /// add to person-remove) is easy to miss, unlike a reaction/save/repost
  /// count visibly changing right next to the tapped icon. Unfollowing stays
  /// silent on success, matching every other toggle-off action on this card.
  Future<void> _toggleFollow(
    BuildContext context,
    WidgetRef ref,
    bool isFollowing,
  ) async {
    if (_blockedForGuest(context, ref)) return;
    try {
      if (isFollowing) {
        await ref.read(unfollowUserProvider(opinion.authorHandle).future);
      } else {
        await ref.read(followUserProvider(opinion.authorHandle).future);
        if (!context.mounted) return;
        context.showSuccessSnackbar('Following.');
      }
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar(
        isFollowing ? 'Could not unfollow.' : 'Could not follow.',
      );
    }
  }

  /// Bookmark toggle.
  ///
  /// Unlike reactions, saving your OWN opinion is allowed: bookmarking is a
  /// personal filing action, not a public endorsement of yourself — which is
  /// why this has no isOwnPost gate.
  Future<void> _toggleSave(BuildContext context, WidgetRef ref) async {
    if (_blockedForGuest(context, ref)) return;
    final isSaved = opinion.isSaved;
    try {
      // Optimistic: the provider flips the row before awaiting the RPC
      // and restores it if the call throws.
      await toggleOpinionSaved(
        ref,
        opinionId: opinion.id,
        isCurrentlySaved: isSaved,
      );
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar(
        isSaved ? 'Could not unsave that.' : 'Could not save that.',
      );
    }
  }

  /// Opens the edit screen for this (own, in-window) opinion.
  ///
  /// Nothing to do on return: unlike the quote composer above, editOpinion has
  /// already patched every feed that holds this row in place, so invalidating
  /// here would only reorder discover and lose the user's scroll position for
  /// no gain.
  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    await context.pushNamed<bool>('editOpinion', extra: opinion);
  }

  Future<void> _openQuoteComposer(BuildContext context, WidgetRef ref) async {
    // Quoting is posting, so it carries the same phone-verified gate (§8.11
    // "Participation gate"). Checked here as well as in the composer so an
    // anonymous tap gets told why instead of opening a screen it cannot
    // submit from.
    if (_blockedForGuest(context, ref)) return;

    final posted = await context.pushNamed<bool>(
      'quoteCompose',
      extra: opinion,
    );

    // Mirrors the FAB in opinions_tab.dart: the composer pops `true` and the
    // caller refreshes, so a quote lands in the feed exactly like a normal
    // opinion does. Scroll-to-top is the tab's affair — this card has no
    // scroll controller and may not even be on that screen.
    if (posted == true) {
      ref.invalidate(discoverFeedProvider);
      ref.invalidate(followingFeedProvider);
    }
  }

  /// Repost toggle. Awaited with a failure snackbar (like the bookmark) rather
  /// than fire-and-forget (like reactions), because toggleOpinionReposted rolls
  /// the optimistic patch back on error — the user needs to be told why the
  /// icon they just filled went hollow again.
  Future<void> _toggleRepost(BuildContext context, WidgetRef ref) async {
    if (_blockedForGuest(context, ref)) return;
    // Belt-and-braces: the button is not rendered at all when isMine, and the
    // RPC raises cannot_repost_own_opinion regardless. This keeps the guard
    // true even if the button is ever shown in a new context.
    if (opinion.isMine) {
      context.showInfoSnackbar('You cannot repost your own opinion.');
      return;
    }
    final wasReposted = opinion.isRepostedByMe;
    try {
      await toggleOpinionReposted(
        ref,
        opinionId: opinion.id,
        isCurrentlyReposted: wasReposted,
      );
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar(
        wasReposted ? 'Could not undo that repost.' : 'Could not repost that.',
      );
    }
  }

  void _toggleReaction(
    BuildContext context,
    WidgetRef ref,
    String newReaction,
  ) {
    if (_blockedForGuest(context, ref)) return;
    // FORUM.md: cannot like/dislike your own post — RLS
    // (opinion_reactions_insert_own) rejects this server-side too, but
    // without this gate the write silently failed with no feedback and
    // likeCount never moved, which is what looked like "the count doesn't
    // show" when reacting to your own opinion.
    if (opinion.isMine) {
      context.showInfoSnackbar('You cannot react to your own opinion.');
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
}
