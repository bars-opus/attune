// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_tab.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/home/widgets/dummy_search_container.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpinionsTab extends ConsumerWidget {
  const OpinionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;
    final tabs = [
      AppTabItem(
        label: 'Opinions',
        icon: Icons.rate_review_outlined,
        content: _OpinionsFeedTabs(isAuthenticated: isAuthenticated),
      ),
      AppTabItem(
        label: 'Forums',
        icon: Icons.forum_outlined,
        content: isAuthenticated ? const ForumsTab() : const ForumScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: colorScheme.neutral,
        title: DummySearchContainer(
          hintText: 'Search',
          onTap: () {},
          elevation: ElevationTokens.xs,
          showBorder: true,
        ),
      ),
      body: TabsWithContent(
        useNestedScrollMode: true,
        tabs: tabs.toList(),
        initialIndex: 0,
        scrollable: false,
        showContent: true,
      ),
    );
  }
}

class _OpinionsFeedTabs extends StatelessWidget {
  const _OpinionsFeedTabs({required this.isAuthenticated});

  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TabsWithContent(
      scrollable: false,
      padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
      style: AppTabsStyle(
        indicatorColor: colorScheme.primary,
        activeColor: colorScheme.primary,
        inactiveColor: colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      // Anonymous users follow nobody, so Following can only show them a
      // "unlocks after verification" gate. Land them on Discover — the whole
      // point of the anonymous-browsing rule is that they see real content
      // without an account.
      initialIndex: isAuthenticated ? 0 : 1,
      tabs: const [
        AppTabItem(label: 'Following', content: FollowingFeedScreen()),
        AppTabItem(label: 'Discover', content: DiscoverFeedScreen()),
      ],
    );
  }
}
