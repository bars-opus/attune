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

    // This screen only ever renders for a signed-in user (gated upstream by
    // AuthenticatedChatWorkspace's userId check), so the status fetch is
    // unconditional — unlike OpinionsTab's guest-or-authenticated header,
    // there is no guest branch to account for here.

    final currentUserId = ref.watch(currentUserIdProvider) ?? '';

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
                  // Three children when signed in (add-icon AppIconButton
                  // (48.w min tap target) + gap + the 30.h avatar + gap +
                  // notification AppIconButton (48.w)), two for a guest — the
                  // avatar opens MY OWN profile via get_my_author_handle,
                  // which resolves auth.uid() server-side and has nothing to
                  // resolve for a signed-out caller. leadingWidth must match
                  // whichever set is actually shown or the Row overflows the
                  // fixed-width box AppBar allocates for `leading`.
                  leadingWidth:
                      widget.isAuthenticated
                          ? 48.w + Spacing.sm.w + 30.h + Spacing.sm.w + 48.w
                          : 48.w + Spacing.sm.w + 48.w,
                  leading: Row(
                    children: [
                      AppIconButton(
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
                      Gap(Spacing.sm.w),
                      AppIconButton(
                        icon: Icons.notifications_active_outlined,
                        onPressed: () {
                          if (kDebugMode) {
                            context.push(RouteNames.onboarding, extra: true);
                          }
                        },
                      ),
                      if (widget.isAuthenticated) ...[
                        Gap(Spacing.sm.w),
                        Center(
                          child: GestureDetector(
                            // Same "My Profile" entry point the commented-out
                            // AppIconButton below this used to offer:
                            // get_my_author_handle resolves auth.uid() to the
                            // caller's own anonymous handle server-side (see
                            // myAuthorHandleProvider's doc — it takes no
                            // parameter, so it can only ever resolve the
                            // caller's own handle), same as tapping any other
                            // author's avatar on an OpinionCard navigates to
                            // RouteNames.anonymousProfile.
                            onTap: () async {
                              final handle = await ref.read(
                                myAuthorHandleProvider.future,
                              );
                              if (handle == null || !context.mounted) return;
                              context.pushNamed(
                                'anonymousProfile',
                                extra: handle,
                              );
                            },
                            child: ProfileAvatar(
                              avatarUrl: '',

                              currentUserId: currentUserId,
                              size: 30.h,
                              enableHero: false,
                              icon: statusIconFor(myStatusDisplay),
                              backgroundColor: statusColorFor(
                                myStatusDisplay,
                                colorScheme,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  actions: [
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
