// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_tab.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/foundation.dart';
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
        // icon: Icons.rate_review_outlined,
        content: _OpinionsFeedTabs(isAuthenticated: isAuthenticated),
      ),
      AppTabItem(
        label: 'Forums',
        // icon: Icons.forum_outlined,
        content: isAuthenticated ? const ForumsTab() : const ForumScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: colorScheme.neutral,
        leading: AppIconButton(
          icon: Icons.menu,
          onPressed: () {
            if (kDebugMode) {
              context.push(RouteNames.onboarding, extra: true);
            }
          },
        ),
        title: SizedBox(
          width: 30,
          height: 30,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
            child: Image.asset(
              color: colorScheme.primary,
              'assets/images/attune_logo_white.png',
              fit: BoxFit.cover,
            ),
          ),
        ),

        actions: [
          AppIconButton(
            icon: Icons.search,
            onPressed: () {
              if (kDebugMode) {
                context.push(RouteNames.onboarding, extra: true);
              }
            },
          ),
        ],
      ),
      body: TabsWithContent(
        useNestedScrollMode: false,
        tabs: tabs.toList(),
        initialIndex: 0,
        scrollable: false,
        showContent: true,
        // Switching Opinions<->Forums doesn't unmount the previous sub-tree
        // (TabBarView keeps neighbours alive), so a nav bar hidden by scroll
        // on one side would otherwise stay hidden after switching — see the
        // matching reset in home_widget.dart's onTap.
        onTabChanged: (_) {
          ref.read(navVisibilityProvider.notifier).state = true;
        },
      ),
    );
  }
}

class _OpinionsFeedTabs extends ConsumerWidget {
  const _OpinionsFeedTabs({required this.isAuthenticated});

  final bool isAuthenticated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      // Following/Discover are both kept alive as sibling sub-tabs, so a
      // scroll-hidden nav from one side would otherwise persist after
      // switching to the other — see the matching reset in
      // home_widget.dart's onTap.
      onTabChanged: (_) {
        ref.read(navVisibilityProvider.notifier).state = true;
      },
      tabs: const [
        AppTabItem(
          label: 'Following',
          content: FollowingFeedScreen(),

          icon: Icons.person_add_outlined,
        ),
        AppTabItem(
          label: 'Discover',
          content: DiscoverFeedScreen(),
          icon: Icons.rate_review_outlined,
        ),
      ],
    );
  }
}
