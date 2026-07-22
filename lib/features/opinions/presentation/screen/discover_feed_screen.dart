// lib/features/opinions/presentation/screens/discover_feed_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'opinion_compose_screen.dart';

class DiscoverFeedScreen extends ConsumerStatefulWidget {
  const DiscoverFeedScreen({super.key});

  @override
  ConsumerState<DiscoverFeedScreen> createState() => _DiscoverFeedScreenState();
}

class _DiscoverFeedScreenState extends ConsumerState<DiscoverFeedScreen> {
  static const _anonymousPreviewOpinions = <({String status, String content})>[
    (
      status: 'Taken',
      content:
          'What has actually helped you repair after the same argument keeps coming back?',
    ),
    (
      status: 'Single',
      content:
          'How do you tell the difference between healthy space and emotional distance?',
    ),
    (
      status: 'Exploring',
      content:
          'What early signs make you feel calm with someone instead of hyper-alert?',
    ),
  ];

  // Guests are shown a static local preview (below) and never a live feed —
  // loadMore must not fire discoverFeedProvider's backend RPC for them. It is
  // granted to `authenticated` only, so an anon call 42501s (this is what
  // produced the "error while scrolling Discover" report for a guest).
  //
  // This reads from the ScrollNotification bubbling through
  // NotificationListener below (metrics.pixels/maxScrollExtent), not a
  // dedicated ScrollController. These CustomScrollViews live inside
  // OpinionsTab's NestedScrollView body, which supplies scroll position via
  // PrimaryScrollController — giving them an explicit controller instead
  // would make each one scroll in total isolation from that ambient
  // controller, so the outer AppBar/tab-bar header would never see the
  // feed's scroll and would stop collapsing/returning with it.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (ref.read(currentUserIdProvider) != null &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
      ref.read(discoverFeedProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAuthenticated = currentUserId != null;
    // Only watch the live feed provider (and so only trigger its backend RPC)
    // once authenticated. Watching it unconditionally previously fired
    // get_discover_opinions for guests every build, well before the
    // isAuthenticated branch below ever chose to render its result — the RPC is
    // granted to `authenticated` only, so that call always 42501s for a guest.
    final opinionsAsync =
        isAuthenticated ? ref.watch(discoverFeedProvider) : null;

    return NotificationListener<UserScrollNotification>(
      onNotification:
          (notification) =>
              NavVisibilityScrollHandler.handle(ref, notification),
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: RefreshIndicator(
          onRefresh: () async {
            if (!isAuthenticated) return;
            ref.invalidate(discoverFeedProvider);
            await ref.read(discoverFeedProvider.future);
          },
          child:
              !isAuthenticated || opinionsAsync == null
                  ? _buildAnonymousPreviewSliver(context)
                  : opinionsAsync.when(
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => ErrorStateWidget.from(error),
                    data: (opinions) => _buildFeedSliver(context, opinions),
                  ),
        ),
      ),
    );
  }

  Widget _buildFeedSliver(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      // Plain Center has nothing to scroll, so no scroll notification ever
      // fires — the ScrollAwareFab (hidden by default, shown only while
      // scrolling) stayed permanently hidden with an empty feed. A
      // scrollable with AlwaysScrollableScrollPhysics still generates scroll
      // notifications from a small drag even though the single child is
      // shorter than the viewport, and also lets RefreshIndicator's
      // pull-to-refresh work.
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
                icon: Icons.rate_review_outlined,
                title: 'No opinions yet',
                subtitle: 'Be the first to share your thoughts',
                onAction: () async {
                  final needsRefresh = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OpinionComposeScreen(),
                    ),
                  );
                  if (needsRefresh == true) {
                    ref.invalidate(discoverFeedProvider);
                  }
                },
                actionLabel: 'Write your first opinion',
              ),
            ),
          ),
        ],
      );
    }

    final hasMore = ref.read(discoverFeedProvider.notifier).hasMore;
    return CustomScrollView(
      // Same reason as the empty-state CustomScrollView above: a short list
      // (1-2 opinions) has no overflow to scroll, so the default physics
      // never generates a scroll notification at all — ScrollAwareFab's
      // reveal gesture had nothing to trigger it. Always-scrollable physics
      // fires notifications from a small drag regardless of overflow.
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommentThreadScreen(
                    opinionId: opinion.id,
                    opinion: opinion,
                  ),
                ),
              );
            }

            return OpinionCard(
              opinion: opinion,
              onOpinionTap: openOpinion,
              onCommentTap: openOpinion,
              onProfileTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => AnonymousProfileScreen(
                          authorHandle: opinion.authorHandle,
                        ),
                  ),
                );
              },
            );
          }, childCount: opinions.length + (hasMore ? 1 : 0)),
        ),
      ],
    );
  }

  Widget _buildAnonymousPreviewSliver(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: Spacing.xl.h),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == 0) {
                return Padding(
                  padding: EdgeInsets.all(Spacing.lg.w),
                  child: SemanticContainerWidget(
                    title: 'Read-only guest preview',
                    content:
                        'You can browse opinions before creating an account. Continue with phone number from Chat to post, reply, follow, or react.',
                    icon: Icons.visibility_outlined,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderColor: Theme.of(context).colorScheme.primary,
                    iconColor: Theme.of(context).colorScheme.primary,
                    textTheme: textTheme,
                  ),
                );
              }
              final opinion = _anonymousPreviewOpinions[index - 1];
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
                child: OpinionCard(
                  opinion: OpinionModel(
                    id: opinion.content,
                    authorHandle: '',
                    isMine: false,
                    content: opinion.content,
                    relationshipStatus: _normalizePreviewStatus(
                      opinion.status,
                    ),
                    likeCount: 0,
                    dislikeCount: 0,
                    commentCount: 0,
                    createdAt: DateTime.now(),
                  ),
                  showFollowButton: false,
                  onCommentTap:
                      () => context.showInfoSnackbar(
                        'Continue with phone number from Chat to join the conversation.',
                      ),
                ),
              );
            }, childCount: _anonymousPreviewOpinions.length + 1),
          ),
        ),
      ],
    );
  }

  String _normalizePreviewStatus(String status) {
    return switch (status) {
      'Taken' => 'taken',
      'Exploring' => 'figuring_it_out',
      _ => 'single',
    };
  }
}
