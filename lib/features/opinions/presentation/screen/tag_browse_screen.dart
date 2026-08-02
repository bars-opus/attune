// lib/features/opinions/presentation/screen/tag_browse_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/forums/data/models/topic_model.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything carrying one tag, newest first (ATTUNE_MASTER_SPEC.md §8.11
/// "Tag browsing", FORUM.md §7).
///
/// ONE screen with two tabs rather than two separate screens: a tag applies to
/// opinions and forum topics alike, so splitting them into different routes
/// would make the user guess which surface a tag has results on and navigate
/// twice to find out. Tabs put both counts one tap apart.
///
/// Filters by TAG ONLY. There is deliberately no author parameter on this
/// screen, its providers, or the RPCs beneath them, and none may be added:
/// "everyone who used this tag" is safe, but "this author's posts tagged X"
/// would let a viewer narrow in on one person by topic — precisely the
/// deanonymization risk a fixed vocabulary exists to prevent. Cards here still
/// link to an author's anonymous profile (as every feed does), but the reverse
/// direction — starting from an author and filtering to a tag — does not exist.
///
/// A standalone pushed route with its own Scaffold, so it deliberately has NO
/// SliverOverlapInjector (there is no enclosing absorber here, and using one
/// would throw at runtime).
class TagBrowseScreen extends ConsumerStatefulWidget {
  final String tagSlug;

  const TagBrowseScreen({super.key, required this.tagSlug});

  @override
  ConsumerState<TagBrowseScreen> createState() => _TagBrowseScreenState();
}

class _TagBrowseScreenState extends ConsumerState<TagBrowseScreen> {
  bool _handleOpinionScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(opinionsByTagProvider(widget.tagSlug).notifier).loadMore();
    }
    return false;
  }

  bool _handleTopicScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(forumTopicsByTagProvider(widget.tagSlug).notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Access theme for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final opinionsAsync = ref.watch(opinionsByTagProvider(widget.tagSlug));
    final topicsAsync = ref.watch(forumTopicsByTagProvider(widget.tagSlug));

    // Not useNestedScrollMode: this Scaffold has no enclosing NestedScrollView
    // for a collapsing header to absorb into (see the class doc on why this
    // screen deliberately has no SliverOverlapInjector), so the plain
    // SimpleTabs-then-TabBarView layout is the correct fit here, not the
    // NestedScrollView-flavored one Discover/Explore use.
    final tabs = [
      AppTabItem(
        label: 'Opinions',
        icon: Icons.rate_review_outlined,
        content: NotificationListener<ScrollNotification>(
          onNotification: _handleOpinionScroll,
          child: RefreshIndicator(
            onRefresh:
                () =>
                    ref
                        .read(opinionsByTagProvider(widget.tagSlug).notifier)
                        .refresh(),
            child: opinionsAsync.when(
              loading: () => const ListviewLoadingShimmer(),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: _buildOpinionList,
            ),
          ),
        ),
      ),
      AppTabItem(
        label: 'Forums',
        icon: Icons.forum_outlined,
        content: NotificationListener<ScrollNotification>(
          onNotification: _handleTopicScroll,
          child: RefreshIndicator(
            onRefresh:
                () =>
                    ref
                        .read(forumTopicsByTagProvider(widget.tagSlug).notifier)
                        .refresh(),
            child: topicsAsync.when(
              loading: () => const ListviewLoadingShimmer(),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: _buildTopicList,
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        title: Text(
          '#${widget.tagSlug}',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: TabsWithContent(
        tabs: tabs,
        initialIndex: 0,
        scrollable: false,
        showContent: true,
      ),
    );
  }

  Widget _buildOpinionList(List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      return _emptyState(
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

  Widget _buildTopicList(List<TopicModel> topics) {
    if (topics.isEmpty) {
      return _emptyState(
        icon: Icons.forum_outlined,
        title: 'No forums tagged #${widget.tagSlug}',
        subtitle: 'Submit a topic with this tag to start the conversation.',
      );
    }

    final hasMore =
        ref.read(forumTopicsByTagProvider(widget.tagSlug).notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(Spacing.md.w),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == topics.length) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              // No userSide passed: the browse RPC returns no per-viewer vote
              // state, so the card renders without a side indicator rather
              // than guessing one.
              return ForumCard(forum: topics[index]);
            }, childCount: topics.length + (hasMore ? 1 : 0)),
          ),
        ),
      ],
    );
  }

  /// Always-scrollable so pull-to-refresh still works with nothing in the list
  /// — same reason the feed screens use these physics.
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
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
