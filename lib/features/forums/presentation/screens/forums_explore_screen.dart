// lib/features/forums/presentation/screens/forums_explore_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart'
    show allTagsProvider;
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/forums/presentation/widgets/topic_voting_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumsExploreScreen extends ConsumerStatefulWidget {
  const ForumsExploreScreen({super.key});

  @override
  ConsumerState<ForumsExploreScreen> createState() =>
      _ForumsExploreScreenState();
}

class _ForumsExploreScreenState extends ConsumerState<ForumsExploreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // ForumsSection lands guests on this screen by default (Contributing is
    // empty for them). Within it, Active/Quiet are populated by real debates
    // same as for anyone, but Voting is the tab most likely to have fresh,
    // engaging content a guest can act on immediately — so guests land on
    // Voting (index 1) instead of Active.
    final isAuthenticated =
        ref.read(supabaseClientProvider).auth.currentUser?.id != null;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: isAuthenticated ? 0 : 1,
    );
    // Switching tabs swaps which sliver list renders below (see build()) —
    // that changes this CustomScrollView's total content height, which
    // Flutter would otherwise read as "the user scrolled" and use to nudge
    // the collapsed app bar. Resetting nav visibility on every tab change
    // avoids a stale hidden-app-bar state carrying over, same reason
    // ForumsSection/OpinionsTab reset it on their own inner tab switches.
    _tabController.addListener(_resetNavVisibilityOnSwitch);
    Future.microtask(() {
      ref.read(votingTopicsProvider);
      ref.read(activeForumsProvider);
      ref.read(quietForumsProvider);
    });
  }

  void _resetNavVisibilityOnSwitch() {
    if (_tabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_resetNavVisibilityOnSwitch);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // ONE CustomScrollView, not a TabBarView: a TabBarView needs bounded
    // height from its parent, which this screen does not have — it is
    // itself a page inside ForumsSection's own TabBarView, not the direct
    // body of a NestedScrollView the way ForumsSection is. Reusing the
    // SAME SliverOverlapInjector/PrimaryScrollController chain
    // DiscoverFeedScreen relies on (see its class doc) is what makes this
    // screen's scroll actually collapse/return the shared app bar above —
    // an isolated ListView inside a fixed-height box, which a TabBarView
    // here would have required, cannot do that; nothing bubbles up to the
    // ancestor NestedScrollView from inside it.
    //
    // The tradeoff: switching tabs does not preserve each tab's scroll
    // offset the way a real TabBarView would (ForumsSection's own
    // Contributing/Explore tabs do preserve it, being actual TabBarView
    // pages). Given this screen's caller sets ARE going to keep scrolling
    // one single ambient scroll position, this was the deliberate tradeoff.
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final activeIndex = _tabController.index;
        return NotificationListener<UserScrollNotification>(
          onNotification:
              (notification) =>
                  NavVisibilityScrollHandler.handle(ref, notification),
          child: CustomScrollView(
            slivers: [
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
              SliverToBoxAdapter(
                child: SimpleTabs(
                  tabs: const [
                    AppTabItem(label: 'Active', icon: Icons.forum_outlined),
                    AppTabItem(
                      label: 'Voting',
                      icon: Icons.how_to_vote_outlined,
                    ),
                    AppTabItem(
                      label: 'Quiet',
                      icon: Icons.hourglass_empty_outlined,
                    ),
                  ],
                  controller: _tabController,
                  scrollable: false,
                  style: AppTabsStyle(
                    indicatorColor: colorScheme.primary,
                    activeColor: colorScheme.primary,
                    inactiveColor: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              _buildTagChipSliver(),
              if (activeIndex == 0) ..._buildActiveForumsSlivers(),
              if (activeIndex == 1) ..._buildVotingTopicsSlivers(),
              if (activeIndex == 2) ..._buildQuietForumsSlivers(),
            ],
          ),
        );
      },
    );
  }

  /// "All" (first, always present) plus one chip per tag in the fixed
  /// vocabulary, multi-select, OR-matched — one shared row filters
  /// whichever tab (Active/Voting/Quiet) is open, since Explore has no
  /// single feed to attach a filter to. See forumsExploreTagFilterProvider.
  Widget _buildTagChipSliver() {
    final tagsAsync = ref.watch(allTagsProvider);
    final selected = ref.watch(forumsExploreTagFilterProvider);
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
                      selected: isAllSelected,
                      onSelected: (_) {
                        ref
                            .read(forumsExploreTagFilterProvider.notifier)
                            .state = const [];
                      },
                    );
                  }
                  final tag = tags[index - 1];
                  final isSelected = selected.contains(tag);
                  return AppFilterChip(
                    label: tag,
                    selected: isSelected,
                    onSelected: (nowSelected) {
                      final next = [...selected];
                      if (nowSelected) {
                        next.add(tag);
                      } else {
                        next.remove(tag);
                      }
                      ref.read(forumsExploreTagFilterProvider.notifier).state =
                          next;
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

  /// Always-scrollable so a short/empty tab still generates a scroll
  /// notification from a small drag — same reason DiscoverFeedScreen's
  /// empty state uses SliverFillRemaining rather than a plain Center.
  List<Widget> _emptySlivers({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return [
      SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: EmptyStateWidget(icon: icon, title: title, subtitle: subtitle),
        ),
      ),
    ];
  }

  List<Widget> _buildActiveForumsSlivers() {
    final activeForums = ref.watch(activeForumsProvider);

    return activeForums.when(
      loading:
          () => [const SliverToBoxAdapter(child: ListviewLoadingShimmer())],
      error:
          (error, stack) => [
            SliverToBoxAdapter(child: ErrorStateWidget.from(error)),
          ],
      data: (forums) {
        if (forums.isEmpty) {
          return _emptySlivers(
            icon: Icons.forum_outlined,
            title: 'No active debates yet',
            subtitle: 'Debates would appear here',
          );
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => ForumCard(forum: forums[index]),
              childCount: forums.length,
            ),
          ),
        ];
      },
    );
  }

  List<Widget> _buildVotingTopicsSlivers() {
    final votingTopics = ref.watch(votingTopicsProvider);

    return votingTopics.when(
      loading:
          () => [const SliverToBoxAdapter(child: ListviewLoadingShimmer())],
      error:
          (error, stack) => [
            SliverToBoxAdapter(child: ErrorStateWidget.from(error)),
          ],
      data: (topics) {
        if (topics.isEmpty) {
          return _emptySlivers(
            icon: Icons.how_to_vote_outlined,
            title: 'No topics waiting for votes yet',
            subtitle: 'Debates would appear here',
          );
        }
        return [
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: EdgeInsets.only(bottom: Spacing.md.h),
                  child: TopicVotingCard(topic: topics[index]),
                ),
                childCount: topics.length,
              ),
            ),
          ),
        ];
      },
    );
  }

  List<Widget> _buildQuietForumsSlivers() {
    final quietForums = ref.watch(quietForumsProvider);

    return quietForums.when(
      loading:
          () => [const SliverToBoxAdapter(child: ListviewLoadingShimmer())],
      error:
          (error, stack) => [
            SliverToBoxAdapter(child: ErrorStateWidget.from(error)),
          ],
      data: (forums) {
        if (forums.isEmpty) {
          return _emptySlivers(
            icon: Icons.hourglass_empty_outlined,
            title: 'No quiet forums',
            subtitle: 'Forums that have gone quiet would appear here',
          );
        }
        return [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  ForumCard(forum: forums[index], isQuiet: true),
              childCount: forums.length,
            ),
          ),
        ];
      },
    );
  }
}
