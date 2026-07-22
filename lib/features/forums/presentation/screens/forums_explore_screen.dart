// lib/features/forums/presentation/screens/forums_explore_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:attune/features/forums/presentation/widgets/topic_voting_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'submit_topic_screen.dart';

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
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;

    return Scaffold(
      floatingActionButton: AppFab(
        scrollAware: true,
        // See discover_feed_screen.dart's matching comment — sibling tabs
        // under the Opinions shell can be kept alive together, so every FAB
        // in that tab group needs a distinct tag to avoid a Hero collision.
        heroTag: 'forums-explore-fab',
        icon: Icons.add,
        label: 'Submit a topic',
        onPressed: () async {
          if (!isAuthenticated) {
            context.showInfoSnackbar(
              'Continue with phone number from Chat to submit a topic.',
            );
            return;
          }
          final needsRefresh = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SubmitTopicScreen()),
          );
          if (needsRefresh == true) {
            ref.invalidate(votingTopicsProvider);
          }
        },
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification:
            (notification) =>
                NavVisibilityScrollHandler.handle(ref, notification),
        child: CustomScrollView(
          slivers: [
            // Active Forums section
            SliverToBoxAdapter(
              child: _buildSectionHeader(
                'Active debates',
                Icons.forum_outlined,
              ),
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
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        Spacing.sm.h,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          Gap(Spacing.sm.w),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text('No active debates yet')),
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
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text('No topics waiting for votes yet')),
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
