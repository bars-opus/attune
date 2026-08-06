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
                  subTitleFontSize: 12.h,
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
                        padding: const EdgeInsets.only(
                          top: Spacing.md,
                          bottom: Spacing.sm,
                        ),
                        child: Row(
                          children: [
                            _buildActionButton(
                              context: context,
                              icon: FontAwesomeIcons.heart,
                              activeIcon: FontAwesomeIcons.solidHeart,
                              label: _countLabel(opinion.likeCount),
                              isActive: opinion.userReaction == 'like',
                              onTap:
                                  () => _toggleReaction(context, ref, 'like'),
                            ),
                            Gap(Spacing.md.w),
                            _buildActionButton(
                              context: context,
                              icon: Icons.thumb_down_outlined,
                              activeIcon: Icons.thumb_down,
                              label: _countLabel(opinion.dislikeCount),
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
                                label: _countLabel(opinion.repostCount),
                                isActive: opinion.isRepostedByMe,
                                onTap: () => _toggleRepost(context, ref),
                              ),
                            ],
                            // Save. No label at all: a save is private to the
                            // saver, so unlike the reactions beside it there is
                            // no public count to sit under the icon. Rendered
                            // for your own posts too — bookmarking is a personal
                            // filing action, not a public endorsement.
                            Gap(Spacing.md.w),
                            _buildActionButton(
                              context: context,
                              icon: FontAwesomeIcons.bookmark,
                              activeIcon: FontAwesomeIcons.solidBookmark,
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
                              onTap: () => _openQuoteComposer(context, ref),
                            ),
                            if (showCommentAction) ...[
                              Gap(Spacing.md.w),
                              _buildActionButton(
                                context: context,
                                icon: Icons.edit,
                                label: _countLabel(opinion.commentCount),
                                onTap: onCommentTap ?? () {},
                              ),
                            ],

                            const Spacer(),

                            if (showFollowButton && !isOwnPost)
                              _buildFollowButton(context, ref),
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

  /// Count as it appears under an action icon: blank at zero rather than a
  /// literal "0", but still a non-null label so the Text below the icon keeps
  /// reserving its line and the row's icons stay on one baseline.
  String _countLabel(int count) => count > 0 ? '$count' : '';

  /// The single control used by every button in the actions row — like,
  /// dislike, repost, save, quote and comment. They differ only in whether
  /// they can be active and whether they carry a count, so both are optional
  /// rather than each button owning a near-identical builder.
  ///
  /// [activeIcon] defaults to [icon]: repost has no filled variant in
  /// font_awesome_flutter's free tier (there is no solidRepeat), so its active
  /// state is carried by the primary-color tint alone.
  ///
  /// [label] distinguishes two cases deliberately: null drops the text line
  /// entirely (save and quote have nothing to count — a save is private, and a
  /// quote creates a new opinion rather than incrementing anything here),
  /// while an empty string keeps the line reserved so a zero-count button
  /// still lines up with its neighbours instead of sitting higher in the row.
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
    IconData? activeIcon,
    String? label,
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            isActive ? (activeIcon ?? icon) : icon,
            size: 16.h,
            color: isActive ? colorScheme.primary : null,
          ),
          if (label != null) ...[
            Gap(Spacing.xs.w),
            Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowButton(BuildContext context, WidgetRef ref) {
    final followState = ref.watch(followStatusProvider(opinion.authorHandle));
    final isFollowing = followState.valueOrNull ?? false;

    return AppIconButton(
      size: 18.h,
      icon:
          isFollowing
              ? Icons.person_remove_outlined
              : Icons.person_add_outlined,
      // label: isFollowing ? 'Following' : 'Follow',
      onPressed: () async {
        if (_blockedForGuest(context, ref)) return;
        if (isFollowing) {
          await ref.read(unfollowUserProvider(opinion.authorHandle).future);
        } else {
          await ref.read(followUserProvider(opinion.authorHandle).future);
        }
      },
    );
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
