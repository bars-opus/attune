// lib/features/forums/presentation/screens/forums_section.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/create_content_chooser.dart';
import 'package:attune/core/widgets/create_content_fab.dart';
import 'package:attune/core/widgets/profile_avatar.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/screens/contributing_forums_screen.dart';
import 'package:attune/features/forums/presentation/screens/forums_explore_screen.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/tag_search_screen.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/foundation.dart';
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
    // A guest's Contributing tab is always the fixed "Login and start
    // contributing" empty state (ContributingForumsScreen's own auth check),
    // so landing a guest there by default shows them nothing. Land guests on
    // Explore instead — same reasoning as OpinionsTab defaulting anonymous
    // users to Discover over Following.
    final isAuthenticated =
        ref.read(supabaseClientProvider).auth.currentUser?.id != null;
    _innerTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: isAuthenticated ? 0 : 1,
    );
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

  void _submitTopic(BuildContext context, ColorScheme colorScheme) {
    CreateContentChooser.show(
      context: context,
      backgroundColor: colorScheme.neutral,
      onTopicSubmitted: () => ref.invalidate(votingTopicsProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;
    // Same status→icon/color mapping OpinionsTab's header avatar uses — this
    // reads as "my status" the same way, and stays the plain placeholder for
    // a guest (no relationship status to show).
    final myStatusAsync =
        isAuthenticated ? ref.watch(userRelationshipStatusProvider) : null;
    final myStatusDisplay = statusDisplayFor(myStatusAsync?.value);
    final currentUserId =
        ref.watch(supabaseClientProvider).auth.currentUser?.id ?? '';

    return Scaffold(
      backgroundColor: colorScheme.background,
      // Shared with Opinions' Following/Discover FAB — same button, same
      // guest gate, same both-type chooser, on every one of the four
      // Opinions/Forums sub-tabs now, not just Explore.
      floatingActionButton: CreateContentFab(
        heroTag: 'forums-explore-fab',
        isAuthenticated: isAuthenticated,
        onTopicSubmitted: () => ref.invalidate(votingTopicsProvider),
      ),
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverOverlapAbsorber(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
                sliver: SliverAppBar(
                  backgroundColor: colorScheme.background,
                  floating: true,
                  pinned: false,
                  snap: true,
                  // Same leading Row shape as OpinionsTab's header: add-icon
                  // AppIconButton (48.w min tap target) + gap + notification
                  // AppIconButton (48.w), plus the 30.h avatar + gap when
                  // signed in. The avatar opens MY OWN profile via
                  // get_my_author_handle, which resolves auth.uid()
                  // server-side and has nothing to resolve for a signed-out
                  // caller. leadingWidth must match whichever set is
                  // actually shown or the Row overflows the fixed-width box
                  // AppBar allocates for `leading`.
                  leadingWidth:
                      isAuthenticated
                          ? 48.w + Spacing.sm.w + 30.h + Spacing.sm.w + 48.w
                          : 48.w + Spacing.sm.w + 48.w,
                  leading: Row(
                    children: [
                      AppIconButton(
                        icon: Icons.add,
                        tooltip: 'submit a topic',
                        onPressed: () {
                          if (!isAuthenticated) {
                            context.showErrorSnackbar(
                              'Sign in to perform this action',
                            );
                            return;
                          }
                          _submitTopic(context, colorScheme);
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
                      if (isAuthenticated) ...[
                        Gap(Spacing.sm.w),
                        Center(
                          child: GestureDetector(
                            // Same "My Profile" entry point OpinionsTab's
                            // header avatar offers — this is the SAME
                            // author-handle identity system, shared across
                            // opinions and forums (FORUM.md §3), not a
                            // second one.
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
                    // Browse the fixed tag vocabulary (§8.11 "Tags") — same
                    // screen OpinionsTab's header opens, since a tag applies
                    // to opinions and forum topics alike (TagBrowseScreen's
                    // own doc comment). Not gated on auth: browsing tag
                    // results follows the same anonymous-browsing rules as
                    // every other read surface here.
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
