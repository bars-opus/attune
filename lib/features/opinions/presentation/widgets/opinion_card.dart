// lib/features/opinions/presentation/widgets/opinion_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/utils/relative_time.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/opinion_more_data.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/core/widgets/tag_chip_row.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/tag_browse_screen.dart';
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
    final timeAgo =
        formatTimeAgo(opinion.createdAt) +
        (opinion.editedAt != null ? ' · edited' : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero'd between the feed card and CommentThreadScreen's header —
        // the opinion itself transitions, not its actions row below.
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
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
                  icon: statusIcon,

                  iconColor: colorScheme.background,
                  backgroundColor: statusIconColor,
                  avatarRadius: 20.h,
                  subTitleMaxLines: showCommentAction ? 10 : 1000,
                  iconSize: 18.h,
                  onTap: onOpinionTap,
                  showDivider: false,
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
                        onTagTap:
                            (slug) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TagBrowseScreen(tagSlug: slug),
                              ),
                            ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Spacing.md,
                          bottom: Spacing.sm,
                        ),
                        child: Row(
                          children: [
                            _buildReactionButton(
                              context: context,
                              icon: FontAwesomeIcons.heart,
                              activeIcon: FontAwesomeIcons.solidHeart,
                              count: opinion.likeCount,
                              isActive: opinion.userReaction == 'like',
                              onTap:
                                  () => _toggleReaction(context, ref, 'like'),
                            ),
                            Gap(Spacing.md.w),
                            _buildReactionButton(
                              context: context,
                              icon: Icons.thumb_down_outlined,
                              activeIcon: Icons.thumb_down,
                              count: opinion.dislikeCount,
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
                              _buildReactionButton(
                                context: context,
                                // font_awesome_flutter's free tier ships `repeat`
                                // as solid-only (there is no solidRepeat), so the
                                // outline/solid swap the heart uses isn't
                                // available — _buildReactionButton's primary-color
                                // tint carries the active state instead.
                                icon: FontAwesomeIcons.repeat,
                                activeIcon: FontAwesomeIcons.repeat,
                                count: opinion.repostCount,
                                isActive: opinion.isRepostedByMe,
                                onTap: () => _toggleRepost(context, ref),
                              ),
                            ],
                            Gap(Spacing.md.w),
                            _buildSaveButton(context, ref),
                            // Quote. Unlike repost above, this is NOT hidden on
                            // your own post: quoting yourself to add a follow-up
                            // thought is an explicitly allowed, distinct action
                            // (§8.11 "Self-quote is allowed"), and the RPC has no
                            // owner check to trip.
                            Gap(Spacing.md.w),
                            _buildQuoteButton(context, ref),
                            if (showCommentAction) ...[
                              Gap(Spacing.md.w),
                              _buildActionButton(
                                context: context,
                                icon: Icons.edit,
                                label:
                                    opinion.commentCount > 0
                                        ? '${opinion.commentCount}'
                                        : '',
                                onTap: onCommentTap ?? () {},
                              ),
                            ],

                            const Spacer(),

                            Text(
                              timeAgo,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            Gap(Spacing.sm.w),

                            if (showFollowButton && !isOwnPost)
                              _buildFollowButton(context, ref),
                            if (showMoreButton) _buildMoreButton(context, ref),
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

  Widget _buildMoreButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showOpinionMenu(context, ref),
      child: Icon(
        Icons.more_horiz,
        size: 18.h,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to hide opinions.',
      );
      return;
    }
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
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to mute people.',
      );
      return;
    }
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

  Widget _buildReactionButton({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            isActive ? activeIcon : icon,
            size: 18.h,
            color: isActive ? colorScheme.primary : null,
          ),
          Gap(Spacing.xs.w),
          Text(
            count > 0 ? '$count' : '',
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18),
          Gap(Spacing.xs.w),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
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

  /// Bookmark toggle. Uses the same bare-icon treatment as the reaction
  /// buttons beside it (FontAwesome, 18.h, primary when active) rather than an
  /// AppIconButton, so the actions row stays visually uniform.
  ///
  /// A save is private to the saver, so there is no count to show and — unlike
  /// reactions — saving your OWN opinion is allowed: bookmarking is a personal
  /// filing action, not a public endorsement of yourself.
  Widget _buildSaveButton(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSaved = opinion.isSaved;

    return GestureDetector(
      onTap: () async {
        if (ref.read(currentUserIdProvider) == null) {
          context.showInfoSnackbar(
            'Continue with phone number from Chat to save opinions.',
          );
          return;
        }
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
      },
      child: Icon(
        isSaved ? FontAwesomeIcons.solidBookmark : FontAwesomeIcons.bookmark,
        size: 18.h,
        color: isSaved ? colorScheme.primary : null,
      ),
    );
  }

  /// Quote entry point: opens the quote composer for this opinion.
  ///
  /// Not a toggle and carries no count — a quote is a new opinion of its own,
  /// so there is nothing on THIS card to flip. Rendered for your own posts too
  /// (§8.11 "Self-quote is allowed"), which is why it sits outside the
  /// isOwnPost gate the repost button uses.
  ///
  /// Uses `quoteLeft` (a bare open-quote glyph) rather than a filled speech
  /// bubble: the row already spends a bubble-ish glyph on comments, and a
  /// quotation mark is the one mark readers already parse as "quoting."
  Widget _buildQuoteButton(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _openQuoteComposer(context, ref),
      child: Icon(FontAwesomeIcons.quoteLeft, size: 16.h),
    );
  }

  /// Opens the edit screen for this (own, in-window) opinion.
  ///
  /// Nothing to do on return: unlike the quote composer above, editOpinion has
  /// already patched every feed that holds this row in place, so invalidating
  /// here would only reorder discover and lose the user's scroll position for
  /// no gain.
  Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditOpinionScreen(opinion: opinion)),
    );
  }

  Future<void> _openQuoteComposer(BuildContext context, WidgetRef ref) async {
    // Quoting is posting, so it carries the same phone-verified gate (§8.11
    // "Participation gate"). Checked here as well as in the composer so an
    // anonymous tap gets told why instead of opening a screen it cannot
    // submit from.
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to quote opinions.',
      );
      return;
    }

    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QuoteComposeScreen(quotedOpinion: opinion),
      ),
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
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to repost opinions.',
      );
      return;
    }
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
    if (ref.read(currentUserIdProvider) == null) {
      context.showInfoSnackbar(
        'Continue with phone number from Chat to react to opinions.',
      );
      return;
    }
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
