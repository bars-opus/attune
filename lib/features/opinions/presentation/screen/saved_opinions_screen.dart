// lib/features/opinions/presentation/screen/saved_opinions_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current user's bookmarked opinions, newest save first.
///
/// Unlike DiscoverFeedScreen/FollowingFeedScreen this is a standalone pushed
/// route with its own Scaffold + AppBar rather than a body inside OpinionsTab's
/// NestedScrollView — so it deliberately has NO SliverOverlapInjector. An
/// injector requires an enclosing SliverOverlapAbsorber; using one here would
/// throw at runtime looking for a handle that does not exist.
class SavedOpinionsScreen extends ConsumerStatefulWidget {
  const SavedOpinionsScreen({super.key});

  @override
  ConsumerState<SavedOpinionsScreen> createState() =>
      _SavedOpinionsScreenState();
}

class _SavedOpinionsScreenState extends ConsumerState<SavedOpinionsScreen> {
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(savedOpinionsProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final savedAsync = ref.watch(savedOpinionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved', style: TextStyle(fontSize: 18)),
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: RefreshIndicator(
          onRefresh: () => ref.read(savedOpinionsProvider.notifier).refresh(),
          child: savedAsync.when(
            loading: () => const ListviewLoadingShimmer(),
            error: (error, stack) => ErrorStateWidget.from(error),
            data: (opinions) => _buildList(context, opinions),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      // Always-scrollable so pull-to-refresh still works with nothing in the
      // list — same reason the feed screens use these physics.
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: Icons.bookmark_border,
                title: 'Nothing saved yet',
                subtitle:
                    'Tap the bookmark on any opinion to keep it here for later.',
              ),
            ),
          ),
        ],
      );
    }

    final hasMore = ref.read(savedOpinionsProvider.notifier).hasMore;
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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CommentThreadScreen(
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
}
