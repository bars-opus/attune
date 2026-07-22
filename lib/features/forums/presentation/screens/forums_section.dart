// lib/features/forums/presentation/screens/forums_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/contributing_forums_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_explore_screen.dart';
import 'package:attune/features/forums/presentation/screens/submit_topic_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ForumsSection extends ConsumerStatefulWidget {
  const ForumsSection({super.key, required this.outerTabController});

  final TabController outerTabController;

  @override
  ConsumerState<ForumsSection> createState() => _ForumsSectionState();
}

class _ForumsSectionState extends ConsumerState<ForumsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTabController;

  @override
  void initState() {
    super.initState();
    _innerTabController = TabController(length: 2, vsync: this);
    // Contributing/Explore are both kept alive as sibling sub-tabs, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _innerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_innerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _innerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _innerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;

    return Scaffold(
      floatingActionButton: AnimatedBuilder(
        animation: _innerTabController,
        builder: (context, _) {
          // Contributing has no FAB today — only show it while Explore
          // (index 1) is active, matching the original per-screen FAB
          // placement (ForumsExploreScreen owned its own FAB; Contributing
          // never had one).
          if (_innerTabController.index != 1) return const SizedBox.shrink();
          return AppFab(
            scrollAware: true,
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
          );
        },
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              floating: true,
              pinned: false,
              snap: true,
              title: const Text('Forums'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(48.h),
                child: SimpleTabs(
                  tabs: const [
                    AppTabItem(
                      label: 'Opinions',
                      icon: Icons.rate_review_outlined,
                    ),
                    AppTabItem(label: 'Forums', icon: Icons.forum_outlined),
                  ],
                  controller: widget.outerTabController,
                  scrollable: false,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SimpleTabs(
              tabs: const [
                AppTabItem(label: 'Contributing'),
                AppTabItem(label: 'Explore'),
              ],
              controller: _innerTabController,
              scrollable: false,
              style: AppTabsStyle(
                indicatorColor: colorScheme.primary,
                activeColor: colorScheme.primary,
                inactiveColor: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _innerTabController,
          children: const [ContributingForumsScreen(), ForumsExploreScreen()],
        ),
      ),
    );
  }
}
