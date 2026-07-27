// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/presentation/widgets/logout_action.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_section.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/muted_authors_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/reposted_opinions_screen.dart';
import 'package:attune/features/opinions/presentation/screen/saved_opinions_screen.dart';
import 'package:attune/features/opinions/presentation/screen/tag_search_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

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
        builder:
            (context, _) => IndexedStack(
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
  // Owns the NestedScrollView's outer position so a freshly-posted opinion
  // (feeds already return newest-first from the RPC) can be scrolled into
  // view — without this, the new item exists at the top of the data but
  // stays off-screen above wherever the user had scrolled to.
  final ScrollController _outerScrollController = ScrollController();

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

  Future<void> _scrollToTop() {
    if (!_outerScrollController.hasClients) return Future.value();
    return _outerScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _innerTabController.removeListener(_resetNavVisibilityOnSwitch);
    _innerTabController.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      floatingActionButton:
          widget.isAuthenticated
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
                    // The feed RPCs already return newest-first — scroll back
                    // to the top so the opinion just posted is actually
                    // visible instead of existing off-screen above wherever
                    // the user had scrolled to.
                    await _scrollToTop();
                  }
                },
              )
              : null,
      body: NestedScrollView(
        controller: _outerScrollController,
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
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
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md,
                      ),
                      child: Image.asset(
                        color: colorScheme.primary,
                        'assets/images/attune_logo_white.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  actions: [
                    // "My saved opinions" lives on the Opinions app bar
                    // because this tab is the user's opinions surface and
                    // the bookmark toggle that fills the list is on the
                    // cards below it. Authenticated-only: get_saved_opinions
                    // is granted to `authenticated`, so a guest tapping it
                    // would only ever get a 42501.
                    if (widget.isAuthenticated)
                      AppIconButton(
                        icon: Icons.bookmark_border,
                        tooltip: 'Saved',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SavedOpinionsScreen(),
                            ),
                          );
                        },
                      ),
                    // "My reposts", same authenticated-only gate and the same
                    // reasoning as Saved above: get_reposted_opinions is
                    // granted to `authenticated` only.
                    if (widget.isAuthenticated)
                      AppIconButton(
                        icon: FontAwesomeIcons.repeat,
                        tooltip: 'Reposted',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RepostedOpinionsScreen(),
                            ),
                          );
                        },
                      ),
                    // "Muted accounts", the only place a mute can be undone.
                    // Same authenticated-only gate as Saved/Reposted above:
                    // get_muted_authors is granted to `authenticated` only,
                    // and a guest has no mute list to manage.
                    if (widget.isAuthenticated)
                      AppIconButton(
                        icon: Icons.volume_off_outlined,
                        tooltip: 'Muted',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MutedAuthorsScreen(),
                            ),
                          );
                        },
                      ),
                    // Browse the fixed tag vocabulary (§8.11 "Tags"). Not
                    // gated on auth, unlike Saved/Reposted/Muted above:
                    // browsing tag results follows the same anonymous-browsing
                    // rules as every other read surface — only ATTACHING a tag
                    // requires phone-verified auth, and that happens in the
                    // composer, not here.
                    AppIconButton(
                      icon: Icons.sell_outlined,
                      tooltip: 'Tags',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TagSearchScreen(),
                          ),
                        );
                      },
                    ),
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
                      inactiveColor: colorScheme.onSurface.withValues(
                        alpha: 0.6,
                      ),
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
