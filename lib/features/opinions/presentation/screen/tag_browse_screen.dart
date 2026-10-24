// lib/features/opinions/presentation/screen/tag_browse_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every opinion carrying one tag, newest first (ATTUNE_MASTER_SPEC.md §8.11
/// "Tag browsing", FORUM.md §7). One list: Forums were retired (Spec 3,
/// 2026-10), so there is no second tab.
///
/// Filters by TAG ONLY. There is deliberately no author parameter on this
/// screen, its providers, or the RPCs beneath them, and none may be added:
/// "everyone who used this tag" is safe, but "this author's posts tagged X"
/// would let a viewer narrow in on one person by topic — precisely the
/// deanonymization risk a fixed vocabulary exists to prevent. Cards here still
/// link to an author's anonymous profile (as every feed does), but the reverse
/// direction — starting from an author and filtering to a tag — does not exist.
///
/// A standalone pushed route with its own Scaffold, built on NestedScrollView
/// + SliverAppBar (the same SliverOverlapAbsorber/Injector pattern OpinionsTab
/// uses) so the title and follow button scroll away together as the list
/// beneath scrolls — see _buildOpinionList for the matching
/// SliverOverlapInjector on the other side.
class TagBrowseScreen extends ConsumerStatefulWidget {
  final String tagSlug;

  const TagBrowseScreen({super.key, required this.tagSlug});

  @override
  ConsumerState<TagBrowseScreen> createState() => _TagBrowseScreenState();
}

class _TagBrowseScreenState extends ConsumerState<TagBrowseScreen> {
  /// Guarded and error-handled the same way OpinionCard._toggleFollow and
  /// AnonymousProfileScreen._toggleFollow are — follow_tag/unfollow_tag are
  /// authenticated-only RPCs with no internal guard, so an unguarded tap
  /// would either throw uncaught or surface a raw permission error.
  Future<void> _toggleTagFollow(bool isFollowing) async {
    if (ref.read(currentUserIdProvider) == null) {
      context.showErrorSnackbar('Sign in to perform this action');
      return;
    }
    try {
      if (isFollowing) {
        await ref.read(unfollowTagProvider(widget.tagSlug).future);
      } else {
        await ref.read(followTagProvider(widget.tagSlug).future);
        if (!context.mounted) return;
        context.showSuccessSnackbar('Following #${widget.tagSlug}.');
      }
    } catch (_) {
      if (!context.mounted) return;
      context.showInfoSnackbar(
        isFollowing
            ? 'Could not unfollow that tag.'
            : 'Could not follow that tag.',
      );
    }
  }

  bool _handleOpinionScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(opinionsByTagProvider(widget.tagSlug).notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Access theme for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final opinionsAsync = ref.watch(opinionsByTagProvider(widget.tagSlug));
    // For a guest, get_followed_tags 42501s (authenticated-only) the same
    // way followStatusProvider already does for author follows — the error
    // is swallowed by valueOrNull's null, and isTagFollowedProvider's ??
    // const [] makes that read as "not followed", which is correct: a guest
    // has no follows. The button still renders (primary, "Follow"); tapping
    // it is what shows the sign-in snackbar via _toggleTagFollow.
    final isFollowing = ref.watch(isTagFollowedProvider(widget.tagSlug));

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
                sliver: SliverAppBar(
                  automaticallyImplyLeading: true,
                  backgroundColor: colorScheme.neutral,
                  floating: true,
                  pinned: false,
                  snap: true,
                  // The title row only: the follow button sits on its own line
                  // in `bottom` below, rather than squeezed beside the title
                  // as AppBar.actions did.
                  toolbarHeight: 56.h,
                  title: Padding(
                    padding: EdgeInsets.only(top: Spacing.xs.h),
                    child: Text(
                      '#${widget.tagSlug}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                  // The Follow row only: a small AppButton (36) inside
                  // Spacing.sm padding on every side.
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(36 + Spacing.sm * 2),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(Spacing.sm),
                          child: AppButton(
                            elevation: 0,
                            label: isFollowing ? 'Unfollow' : 'Follow',
                            onPressed: () => _toggleTagFollow(isFollowing),
                            size: ButtonSize.small,
                            // AppButton defaults to width: double.infinity —
                            // here the title slot gives the Column a bounded
                            // width (the SliverAppBar's own title area), so
                            // Align sizes to the button's natural width
                            // instead of stretching it edge-to-edge. Kept
                            // explicit for the same reason the old
                            // AppBar.actions placement needed one: relying on
                            // an ambient bounded width here is fragile if the
                            // title area's constraints ever change.
                            width: double.infinity,
                            // Same on/off color pairing AnonymousProfileScreen's
                            // own author-follow button uses — a muted "already
                            // following" treatment against the primary-colored
                            // call to action.
                            customColor:
                                isFollowing
                                    ? colorScheme.surfaceContainerHighest
                                    : colorScheme.primary,
                            textColor:
                                isFollowing
                                    ? colorScheme.onSurface
                                    : colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
        // Builder gives this subtree a context BELOW the NestedScrollView,
        // which sliverOverlapAbsorberHandleFor requires to find the
        // handle — the outer build(context) here is above the
        // NestedScrollView, same reason DiscoverFeedScreen gets its own
        // from its own build(context) as a separate widget.
        body: Builder(
          builder:
              (context) => NotificationListener<ScrollNotification>(
                onNotification: _handleOpinionScroll,
                child: RefreshIndicator(
                  onRefresh:
                      () =>
                          ref
                              .read(
                                opinionsByTagProvider(widget.tagSlug).notifier,
                              )
                              .refresh(),
                  child: opinionsAsync.when(
                    loading: () => const ListviewLoadingShimmer(),
                    error: (error, stack) => ErrorStateWidget.from(error),
                    data: (opinions) => _buildOpinionList(context, opinions),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildOpinionList(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      return _emptyState(
        context: context,
        icon: Icons.rate_review_outlined,
        title: 'No opinions tagged #${widget.tagSlug}',
        subtitle: 'Tag an opinion with this when you post to start it off.',
      );
    }

    final hasMore =
        ref.read(opinionsByTagProvider(widget.tagSlug).notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == opinions.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final opinion = opinions[index];
            void openOpinion() {
              context.pushNamed('commentThread', extra: opinion);
            }

            return OpinionCard(
              opinion: opinion,
              onOpinionTap: openOpinion,
              onCommentTap: openOpinion,
              onProfileTap: () {
                context.pushNamed(
                  'anonymousProfile',
                  extra: opinion.authorHandle,
                );
              },
            );
          }, childCount: opinions.length + (hasMore ? 1 : 0)),
        ),
      ],
    );
  }

  /// Always-scrollable so pull-to-refresh still works with nothing in the list
  /// — same reason the feed screens use these physics.
  Widget _emptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyStateWidget(
              icon: icon,
              title: title,
              subtitle: subtitle,
            ),
          ),
        ),
      ],
    );
  }
}
