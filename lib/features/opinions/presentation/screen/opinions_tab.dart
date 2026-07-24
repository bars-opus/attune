// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/presentation/widgets/logout_action.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_section.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OpinionsTab extends ConsumerStatefulWidget {
  const OpinionsTab({super.key});

  @override
  ConsumerState<OpinionsTab> createState() => _OpinionsTabState();
}

class _OpinionsTabState extends ConsumerState<OpinionsTab>
    with SingleTickerProviderStateMixin {
  late final TabController _outerTabController;

  @override
  void initState() {
    super.initState();
    _outerTabController = TabController(length: 2, vsync: this);
    // Opinions/Forums sections are both kept alive in the IndexedStack, so a
    // scroll-hidden nav from one side would otherwise persist after
    // switching — see the matching reset in home_widget.dart's onTap.
    _outerTabController.addListener(_resetNavVisibilityOnSwitch);
  }

  void _resetNavVisibilityOnSwitch() {
    if (_outerTabController.indexIsChanging) {
      ref.read(navVisibilityProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _outerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _outerTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(currentUserIdProvider) != null;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _outerTabController,
        builder: (context, _) => IndexedStack(
          index: _outerTabController.index,
          children: [
            _OpinionsSection(
              outerTabController: _outerTabController,
              isAuthenticated: isAuthenticated,
            ),
            isAuthenticated
                ? ForumsSection(outerTabController: _outerTabController)
                : const ForumScreen(),
          ],
        ),
      ),
    );
  }
}

class _OpinionsSection extends ConsumerStatefulWidget {
  const _OpinionsSection({
    required this.outerTabController,
    required this.isAuthenticated,
  });

  final TabController outerTabController;
  final bool isAuthenticated;

  @override
  ConsumerState<_OpinionsSection> createState() => _OpinionsSectionState();
}

class _OpinionsSectionState extends ConsumerState<_OpinionsSection>
    with SingleTickerProviderStateMixin {
  late final TabController _innerTabController;

  @override
  void initState() {
    super.initState();
    // Anonymous users follow nobody, so Following can only show them a
    // "unlocks after verification" gate. Land them on Discover — the whole
    // point of the anonymous-browsing rule is that they see real content
    // without an account.
    _innerTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isAuthenticated ? 0 : 1,
    );
    // Following/Discover are both kept alive as sibling sub-tabs, so a
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

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      floatingActionButton: widget.isAuthenticated
          ? AppFab(
              scrollAware: true,
              heroTag: 'opinions-fab',
              icon: Icons.add,
              onPressed: () async {
                final needsRefresh = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OpinionComposeScreen(),
                  ),
                );
                if (needsRefresh == true) {
                  if (_innerTabController.index == 0) {
                    ref.invalidate(followingFeedProvider);
                  } else {
                    ref.invalidate(discoverFeedProvider);
                  }
                }
              },
            )
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              backgroundColor: colorScheme.neutral,
              floating: true,
              pinned: false,
              snap: true,
              leading: AppIconButton(
                icon: Icons.menu,
                onPressed: () => LogoutAction.confirmAndSignOut(context),
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
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
              child: SimpleTabs(
                tabs: const [
                  AppTabItem(label: 'Following'),
                  AppTabItem(label: 'Discover'),
                ],
                controller: _innerTabController,
                scrollable: false,
                style: AppTabsStyle(
                  indicatorColor: colorScheme.primary,
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _innerTabController,
          children: const [FollowingFeedScreen(), DiscoverFeedScreen()],
        ),
      ),
    );
  }
}
