// lib/features/opinions/presentation/screens/following_feed_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';

class FollowingFeedScreen extends ConsumerStatefulWidget {
  const FollowingFeedScreen({super.key});

  @override
  ConsumerState<FollowingFeedScreen> createState() =>
      _FollowingFeedScreenState();
}

class _FollowingFeedScreenState extends ConsumerState<FollowingFeedScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAuthenticated = currentUserId != null;
    // Only watch (and so only trigger) the live feed provider once
    // authenticated — see discover_feed_screen.dart for why an unconditional
    // watch 42501s for a guest (the RPC is granted to `authenticated` only).
    final followingAsync =
        isAuthenticated ? ref.watch(followingFeedProvider) : null;

    return NotificationListener<UserScrollNotification>(
      onNotification:
          (notification) =>
              NavVisibilityScrollHandler.handle(ref, notification),
      child: RefreshIndicator(
        onRefresh: () async {
          if (!isAuthenticated) return;
          await ref.read(followingFeedProvider.notifier).refresh();
        },
        child:
            !isAuthenticated || followingAsync == null
                ? _buildUnauthenticatedSliver(context)
                : followingAsync.when(
                  loading: () => const ListviewLoadingShimmer(),
                  error: (error, stack) => ErrorStateWidget.from(error),
                  data: (opinions) => _buildFeedSliver(context, opinions),
                ),
      ),
    );
  }

  Widget _buildUnauthenticatedSliver(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: EdgeInsets.all(Spacing.lg.h),
              child: SemanticContainerWidget(
                title: 'Following unlocks after verification',
                content:
                    'Guest browsing is available in Discover. Continue with phone number from Chat to follow voices and build a personal feed.',
                icon: Icons.person_add_alt_1_outlined,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderColor: Theme.of(context).colorScheme.primary,
                iconColor: Theme.of(context).colorScheme.primary,
                textTheme: Theme.of(context).textTheme,
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildFeedSliver(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      // See discover_feed_screen.dart's matching comment: a plain Center
      // never scrolls, so ScrollAwareFab (hidden until the user scrolls)
      // stayed permanently hidden on an empty feed. AlwaysScrollableScrollPhysics
      // still fires scroll notifications from a small drag even though the
      // content is shorter than the viewport.
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
                icon: Icons.person_add_outlined,
                title: 'You are not following anyone yet',
                subtitle: 'Head to Discover to find voices you connect with',
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      // See discover_feed_screen.dart's matching comment: a short list has no
      // overflow, so default physics never fires a scroll notification,
      // leaving ScrollAwareFab with nothing to trigger its reveal.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
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
          }, childCount: opinions.length),
        ),
      ],
    );
  }
}
