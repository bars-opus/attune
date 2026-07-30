// lib/features/opinions/presentation/screens/opinions_tab.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/auth/presentation/widgets/logout_action.dart';
import 'package:attune/features/forums/presentation/screens/forum_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_section.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/discover_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/following_feed_screen.dart';
import 'package:attune/features/opinions/presentation/screen/tag_search_screen.dart';
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
    // Same status→icon/color mapping OpinionCard uses (see its
    // _getStatusDisplay/_statusIconFor/_statusColorFor), so this avatar
    // reads as "my status" the same way every opinion card's leading icon
    // does. Guests have no relationship status to show, so they keep the
    // plain person placeholder instead of a status glyph.
    final myStatusAsync =
        widget.isAuthenticated
            ? ref.watch(userRelationshipStatusProvider)
            : null;
    final myStatusDisplay = statusDisplayFor(myStatusAsync?.value);

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      floatingActionButton:
          widget.isAuthenticated
              ? AppFab(
                scrollAware: true,
                heroTag: 'opinions-fab',
                icon: Icons.add,
                onPressed: () {
                  CreateContentChooser.show(
                    context: context,
                    backgroundColor: colorScheme.neutral,
                    onOpinionPosted: () async {
                      if (_innerTabController.index == 0) {
                        ref.invalidate(followingFeedProvider);
                      } else {
                        ref.invalidate(discoverFeedProvider);
                      }
                      // The feed RPCs already return newest-first — scroll
                      // back to the top so the opinion just posted is
                      // actually visible instead of existing off-screen
                      // above wherever the user had scrolled to.
                      await _scrollToTop();
                    },
                  );
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
                    icon: Icons.add,
                    tooltip: 'add opinions',
                    onPressed: () {
                      CreateContentChooser.show(
                        context: context,
                        backgroundColor: colorScheme.neutral,
                        onOpinionPosted: () async {
                          if (_innerTabController.index == 0) {
                            ref.invalidate(followingFeedProvider);
                          } else {
                            ref.invalidate(discoverFeedProvider);
                          }
                          await _scrollToTop();
                        },
                      );
                    },
                  ),

                  // ProfileAvatar(
                  //   avatarUrl: '',
                  //   currentUserId: '',
                  //   size: 25.h,
                  //   enableHero: false,
                  //   icon:
                  //       widget.isAuthenticated
                  //           ? statusIconFor(myStatusDisplay)
                  //           : null,
                  //   backgroundColor:
                  //       widget.isAuthenticated
                  //           ? statusColorFor(myStatusDisplay, colorScheme)
                  //           : null,
                  // ),
                  //  AppIconButton(
                  //   icon: Icons.menu,
                  //   onPressed: () => LogoutAction.confirmAndSignOut(context),
                  // ),
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
                    // // "My Profile" — Opinions/Reposts/Bookmarks now live as
                    // // tabs on AnonymousProfileScreen rather than as separate
                    // // icons here, so this is the one entry point to all
                    // // three. get_my_author_handle resolves auth.uid() to the
                    // // caller's own handle server-side — it takes no
                    // // parameter, so it can only ever return the caller's own
                    // // handle, never anyone else's (see the migration's own
                    // // comment on why this does not weaken the
                    // // handle-mapping's one-directional guarantee).
                    // // Authenticated-only: an anonymous browsing user has no
                    // // handle of their own to view.
                    // if (widget.isAuthenticated)
                    //   AppIconButton(
                    //     icon: Icons.person_outline,
                    //     tooltip: 'My Profile',
                    //     onPressed: () async {
                    //       final handle = await ref.read(
                    //         myAuthorHandleProvider.future,
                    //       );
                    //       if (handle == null || !context.mounted) return;
                    //       Navigator.push(
                    //         context,
                    //         MaterialPageRoute(
                    //           builder:
                    //               (_) => AnonymousProfileScreen(
                    //                 authorHandle: handle,
                    //               ),
                    //         ),
                    //       );
                    //     },
                    //   ),
                    // Muted accounts now lives in Settings, alongside Block
                    // (they're distinct systems — block is real-identity,
                    // mute is anonymous-handle — but both belong under
                    // account moderation, not in this feed's app bar).
                    //
                    // Browse the fixed tag vocabulary (§8.11 "Tags"). Not
                    // gated on auth, unlike Saved/Reposted/Muted above:
                    // browsing tag results follows the same anonymous-browsing
                    // rules as every other read surface — only ATTACHING a tag
                    // requires phone-verified auth, and that happens in the
                    // composer, not here.
                    AppIconButton(
                      icon: Icons.tag_sharp,
                      tooltip: 'Tags',
                      onPressed: () {
                        BottomSheetUtils.showDocumentationBottomSheet(
                          widget: TagSearchScreen(),

                          backgroundColor: colorScheme.neutral,
                          context: context,
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
