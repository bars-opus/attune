// lib/features/opinions/presentation/screen/opinion_engagement_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who engaged with one opinion: the opinions that quote it, and the people
/// who reposted it. This is what the quote and repost counts on a card open
/// into — before this they were numbers with nothing behind them.
///
/// ONE screen with two tabs rather than two routes, for the same reason
/// TagBrowseScreen pairs Opinions and Forums: both answer "who engaged with
/// this", and splitting them would make the user guess which tab a number
/// lives on and navigate twice to find out. [initialTab] lands them on
/// whichever count they actually tapped.
///
/// "Who" here means an anonymous author_handle, never an identity — the same
/// handle already shown on every card (FORUM.md §3). Reposters are listed by
/// handle for exactly that reason: it is not a user list, it is the set of
/// handles that reposted.
///
/// A standalone pushed route with its own Scaffold, so like TagBrowseScreen it
/// deliberately has NO SliverOverlapInjector — there is no enclosing absorber
/// here and using one would throw at runtime.
class OpinionEngagementScreen extends ConsumerStatefulWidget {
  const OpinionEngagementScreen({
    super.key,
    required this.opinionId,
    this.initialTab = 0,
  });

  final String opinionId;

  /// 0 = Quotes, 1 = Reposts. Set from whichever count was tapped.
  final int initialTab;

  @override
  ConsumerState<OpinionEngagementScreen> createState() =>
      _OpinionEngagementScreenState();
}

class _OpinionEngagementScreenState
    extends ConsumerState<OpinionEngagementScreen> {
  bool _handleQuoteScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(quotesOfOpinionProvider(widget.opinionId).notifier).loadMore();
    }
    return false;
  }

  bool _handleRepostScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref
          .read(repostersOfOpinionProvider(widget.opinionId).notifier)
          .loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quotesAsync = ref.watch(quotesOfOpinionProvider(widget.opinionId));
    final repostsAsync = ref.watch(
      repostersOfOpinionProvider(widget.opinionId),
    );

    final tabs = [
      AppTabItem(
        label: 'Quotes',
        icon: Icons.format_quote_outlined,
        content: NotificationListener<ScrollNotification>(
          onNotification: _handleQuoteScroll,
          child: RefreshIndicator(
            onRefresh:
                () =>
                    ref
                        .read(
                          quotesOfOpinionProvider(widget.opinionId).notifier,
                        )
                        .refresh(),
            child: quotesAsync.when(
              loading: () => const ListviewLoadingShimmer(),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: _buildQuoteList,
            ),
          ),
        ),
      ),
      AppTabItem(
        label: 'Reposts',
        icon: Icons.repeat,
        content: NotificationListener<ScrollNotification>(
          onNotification: _handleRepostScroll,
          child: RefreshIndicator(
            onRefresh:
                () =>
                    ref
                        .read(
                          repostersOfOpinionProvider(widget.opinionId).notifier,
                        )
                        .refresh(),
            child: repostsAsync.when(
              loading: () => const ListviewLoadingShimmer(),
              error: (error, stack) => ErrorStateWidget.from(error),
              data: _buildRepostList,
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
          'Engagement',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
      body: TabsWithContent(
        tabs: tabs,
        initialIndex: widget.initialTab,
        scrollable: false,
        showContent: true,
      ),
    );
  }

  Widget _buildQuoteList(List<OpinionModel> quotes) {
    if (quotes.isEmpty) {
      return _emptyState(
        icon: Icons.format_quote_outlined,
        title: 'No quotes yet',
        subtitle:
            'When someone quotes this opinion to add their own thought, it '
            'shows up here.',
      );
    }

    final hasMore =
        ref.read(quotesOfOpinionProvider(widget.opinionId).notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == quotes.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final quote = quotes[index];
            void openQuote() {
              context.pushNamed('commentThread', extra: quote);
            }

            return OpinionCard(
              opinion: quote,
              onOpinionTap: openQuote,
              onCommentTap: openQuote,
              onProfileTap: () {
                context.pushNamed(
                  'anonymousProfile',
                  extra: quote.authorHandle,
                );
              },
            );
          }, childCount: quotes.length + (hasMore ? 1 : 0)),
        ),
      ],
    );
  }

  /// Every row here is the SAME opinion, repeated once per reposter — a repost
  /// has no content of its own. The card is rendered without its actions row
  /// (showCommentAction/showMoreButton false) because reacting to the same
  /// opinion once per row would be meaningless; the handle and the repost time
  /// are what distinguish the rows.
  Widget _buildRepostList(List<OpinionModel> reposts) {
    if (reposts.isEmpty) {
      return _emptyState(
        icon: Icons.repeat,
        title: 'No reposts yet',
        subtitle: 'When someone reposts this opinion, they show up here.',
      );
    }

    final hasMore =
        ref.read(repostersOfOpinionProvider(widget.opinionId).notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == reposts.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final repost = reposts[index];
            return OpinionCard(
              opinion: repost,
              showFollowButton: true,
              showCommentAction: false,
              showMoreButton: false,
              onProfileTap: () {
                context.pushNamed(
                  'anonymousProfile',
                  extra: repost.authorHandle,
                );
              },
            );
          }, childCount: reposts.length + (hasMore ? 1 : 0)),
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
