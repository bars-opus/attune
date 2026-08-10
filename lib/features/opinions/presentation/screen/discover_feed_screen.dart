// lib/features/opinions/presentation/screens/discover_feed_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiscoverFeedScreen extends ConsumerStatefulWidget {
  const DiscoverFeedScreen({super.key});

  @override
  ConsumerState<DiscoverFeedScreen> createState() => _DiscoverFeedScreenState();
}

class _DiscoverFeedScreenState extends ConsumerState<DiscoverFeedScreen> {
  // Paginates for guests too: get_discover_opinions is granted to `anon` as of
  // 20260818120000_public_opinion_reads, so signed-out visitors read the same
  // live feed rather than a hardcoded preview. (Before that grant an anon call
  // 42501'd, which is why this used to be gated on being signed in.)
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
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(discoverFeedProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Guests and signed-in users read the same live feed. The RPC personalises
    // itself from auth.uid(), which is simply NULL for a guest — they get an
    // unpersonalised (not unfiltered) feed, with the same moderation rules.
    final opinionsAsync = ref.watch(discoverFeedProvider);

    return NotificationListener<UserScrollNotification>(
      onNotification:
          (notification) =>
              NavVisibilityScrollHandler.handle(ref, notification),
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(discoverFeedProvider);
            await ref.read(discoverFeedProvider.future);
          },
          child: opinionsAsync.when(
            loading: () => const ListviewLoadingShimmer(),
            error: (error, stack) => ErrorStateWidget.from(error),
            data: (opinions) => _buildFeedSliver(context, opinions),
          ),
        ),
      ),
    );
  }

  /// "All" (first, always present) plus one chip per tag in the fixed
  /// vocabulary (§8.11 "Tags"), multi-select, OR-matched. Lives inside the
  /// feed's own CustomScrollView (as a sliver) rather than as fixed chrome
  /// in OpinionsTab's header, so it scrolls away with the rest of Discover
  /// like the rest of this NestedScrollView-based surface.
  Widget _buildTagChipSliver(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = ref.watch(discoverFeedProvider.notifier).selectedTagSlugs;
    return SliverToBoxAdapter(
      child: tagsAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (tags) {
          if (tags.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: EdgeInsets.fromLTRB(
              Spacing.md.w,
              Spacing.lg.w,
              Spacing.md.h,
              0,
            ),
            child: SizedBox(
              height: 36.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tags.length + 1,
                separatorBuilder: (_, __) => SizedBox(width: Spacing.xs.w),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isAllSelected = selected.isEmpty;
                    return AppFilterChip(
                      label: 'All',

                      selectedColor: colorScheme.primary.withOpacity(.8),
                      selected: isAllSelected,
                      onSelected: (_) {
                        ref
                            .read(discoverFeedProvider.notifier)
                            .setTagFilter(const []);
                      },
                    );
                  }
                  final tag = tags[index - 1];
                  final isSelected = selected.contains(tag);
                  return AppFilterChip(
                    label: tag,
                    selectedColor: colorScheme.primary.withOpacity(.8),
                    selected: isSelected,
                    onSelected: (nowSelected) {
                      final next = [...selected];
                      if (nowSelected) {
                        next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      ref
                          .read(discoverFeedProvider.notifier)
                          .setTagFilter(next);
                    },
                  );
                },
              ),
            ),
          );
        },
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
          _buildTagChipSliver(context),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: Icons.rate_review_outlined,
                title: 'No opinions yet',
                subtitle: 'Be the first to share your thoughts',
                onAction: () {
                  CreateContentChooser.show(
                    context: context,
                    backgroundColor: Theme.of(context).colorScheme.neutral,
                    onOpinionPosted: () => ref.invalidate(discoverFeedProvider),
                  );
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
        _buildTagChipSliver(context),
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
}
