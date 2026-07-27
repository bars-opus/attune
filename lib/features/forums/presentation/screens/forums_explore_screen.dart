// lib/features/forums/presentation/screens/forums_explore_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:attune/features/forums/presentation/widgets/topic_voting_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumsExploreScreen extends ConsumerStatefulWidget {
  const ForumsExploreScreen({super.key});

  @override
  ConsumerState<ForumsExploreScreen> createState() =>
      _ForumsExploreScreenState();
}

class _ForumsExploreScreenState extends ConsumerState<ForumsExploreScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(votingTopicsProvider);
      ref.read(activeForumsProvider);
      ref.read(quietForumsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<UserScrollNotification>(
      onNotification:
          (notification) =>
              NavVisibilityScrollHandler.handle(ref, notification),
      child: CustomScrollView(
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          // Active Forums section
          SliverToBoxAdapter(
            child: _buildSectionHeader('Active debates', Icons.forum_outlined),
          ),
          _buildActiveForumsList(),

          // Topics waiting for votes section
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              'Topics waiting for votes',
              Icons.how_to_vote_outlined,
            ),
          ),
          _buildVotingTopicsList(),

          // Quiet forums section
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              'Quiet forums',
              Icons.hourglass_empty_outlined,
            ),
          ),
          _buildQuietForumsList(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        Spacing.xs.h,
      ),
      child: Row(
        children: [
          AppIconButton(icon: icon),
          // Icon(icon, size: 20),
          Gap(Spacing.sm.w),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              // fontWeight: FontWeight.w600,
              color: colorScheme.onBackground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveForumsList() {
    final activeForums = ref.watch(activeForumsProvider);

    return activeForums.when(
      loading:
          () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stack) =>
              SliverToBoxAdapter(child: ErrorStateWidget.from(error)),
      data: (forums) {
        if (forums.isEmpty) {
          return const SliverToBoxAdapter(
            child: CardInkWell(
              margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Center(
                child: EmptyStateWidget(
                  icon: Icons.forum_outlined,
                  title: 'No active debates yet',
                  subtitle: 'Debates would appear here',
                ),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => ForumCard(forum: forums[index]),
            childCount: forums.length,
          ),
        );
      },
    );
  }

  Widget _buildVotingTopicsList() {
    final votingTopics = ref.watch(votingTopicsProvider);

    return votingTopics.when(
      loading:
          () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, stack) =>
              SliverToBoxAdapter(child: ErrorStateWidget.from(error)),
      data: (topics) {
        if (topics.isEmpty) {
          return const SliverToBoxAdapter(
            child: CardInkWell(
              margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Center(
                child: EmptyStateWidget(
                  icon: Icons.how_to_vote_outlined,
                  title: 'No topics waiting for votes yet',
                  subtitle: 'Debates would appear here',
                ),
              ),
            ),
          );
        }
        return SliverPadding(
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
        );
      },
    );
  }

  Widget _buildQuietForumsList() {
    final quietForums = ref.watch(quietForumsProvider);

    return quietForums.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error:
          (error, stack) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (forums) {
        if (forums.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => ForumCard(forum: forums[index], isQuiet: true),
            childCount: forums.length,
          ),
        );
      },
    );
  }
}
