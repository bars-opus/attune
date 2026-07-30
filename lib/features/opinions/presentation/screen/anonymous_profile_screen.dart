// lib/features/opinions/presentation/screens/anonymous_profile_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/providers/profile_providers.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opinions / Reposts / Bookmarks for one anonymous author, keyed by their
/// opaque handle (never a real user_id — FORUM.md §3).
///
/// Bookmarks is own-profile only: saves are private (never exposed to anyone
/// but the saver), so there is no "this author's bookmarks" concept for
/// someone else's profile — the tab does not exist there at all, not merely
/// empty. Reposts DOES exist on both: get_author_reposted_opinions resolves
/// another author's reposts the same handle-comparison way
/// get_author_opinions already resolves their posts.
class AnonymousProfileScreen extends ConsumerStatefulWidget {
  final String authorHandle;

  const AnonymousProfileScreen({super.key, required this.authorHandle});

  @override
  ConsumerState<AnonymousProfileScreen> createState() =>
      _AnonymousProfileScreenState();
}

class _AnonymousProfileScreenState extends ConsumerState<AnonymousProfileScreen>
    with TickerProviderStateMixin {
  // Own-profile has 3 tabs (Opinions/Reposts/Bookmarks); someone else's has 2
  // (Opinions/Reposts, no Bookmarks). The controller's length must match
  // whichever is showing, so it is (re)created once isOwnProfile is known —
  // see _ensureTabController.
  TabController? _tabController;
  bool? _tabControllerIsOwn;

  final ScrollController _outerScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(profileOpinionsProvider(widget.authorHandle).future);
      ref.read(authorProfileProvider(widget.authorHandle).future);
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  void _ensureTabController(bool isOwnProfile) {
    if (_tabControllerIsOwn == isOwnProfile) return;
    _tabController?.dispose();
    _tabController = TabController(
      length: isOwnProfile ? 3 : 2,
      vsync: this,
    );
    _tabControllerIsOwn = isOwnProfile;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final profileAsync = ref.watch(authorProfileProvider(widget.authorHandle));
    final isOwnProfile = profileAsync.valueOrNull?.isMine ?? false;
    _ensureTabController(isOwnProfile);
    final tabController = _tabController!;

    return Scaffold(
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
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text('Profile', style: TextStyle(fontSize: 18)),
                  bottom: PreferredSize(
                    // Header content + tab bar, both scroll away together —
                    // same collapsing-header shape as OpinionsTab.
                    preferredSize: Size.fromHeight(_headerHeight()),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildProfileHeader(
                          context,
                          profileAsync,
                          colorScheme,
                          textTheme,
                        ),
                        SimpleTabs(
                          tabs: [
                            const AppTabItem(
                              label: 'Opinions',
                              icon: Icons.rate_review_outlined,
                            ),
                            const AppTabItem(
                              label: 'Reposts',
                              icon: FontAwesomeIcons.repeat,
                            ),
                            if (isOwnProfile)
                              const AppTabItem(
                                label: 'Bookmarks',
                                icon: Icons.bookmark_border,
                              ),
                          ],
                          controller: tabController,
                          scrollable: false,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
        body: TabBarView(
          controller: tabController,
          children: [
            _OpinionsTabBody(authorHandle: widget.authorHandle),
            isOwnProfile
                ? const _OwnRepostsTabBody()
                : _AuthorRepostsTabBody(authorHandle: widget.authorHandle),
            if (isOwnProfile) const _OwnBookmarksTabBody(),
          ],
        ),
      ),
    );
  }

  // Fixed, not measured: SliverAppBar.bottom needs an exact preferredSize
  // up front, and the header's content (status text, follower count, and an
  // OPTIONAL Follow button) would otherwise make that height vary by
  // profile. Reserving a fixed height and keeping the Follow button's row
  // always present (invisible via Visibility.maintain when not shown, see
  // _buildProfileHeader) turns this into an exact sum instead of a guess:
  // header content (76) + always-reserved button row (36) + tab bar (48).
  static const double _headerContentHeight = 76;
  static const double _followButtonRowHeight = 36;
  static const double _tabBarHeight = 48;

  double _headerHeight() {
    return (_headerContentHeight + _followButtonRowHeight + _tabBarHeight).h;
  }

  Widget _buildProfileHeader(
    BuildContext context,
    AsyncValue<AuthorProfileSummary> profileAsync,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w, vertical: Spacing.sm.h),
      child: SizedBox(
        height: (_headerContentHeight + _followButtonRowHeight).h,
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const SizedBox.shrink(),
          data: (profile) {
            final statusDisplay = statusDisplayFor(profile.relationshipStatus);
            final count = profile.followerCount;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // No avatar, no name — just status and follower count.
                Text(
                  statusDisplay,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                Gap(Spacing.xs.h),
                Text(
                  '$count follower${count != 1 ? 's' : ''}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Gap(Spacing.xs.h),
                // Always reserves its row height (Visibility.maintain), even
                // for isMine, so the header's total height never depends on
                // which profile is showing — see _headerHeight above.
                Visibility(
                  visible: !profile.isMine,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: AppButton(
                    label: profile.isFollowing ? 'Unfollow' : 'Follow',
                    onPressed: () async {
                      if (profile.isFollowing) {
                        await ref.read(
                          unfollowUserProvider(widget.authorHandle).future,
                        );
                      } else {
                        await ref.read(
                          followUserProvider(widget.authorHandle).future,
                        );
                      }
                      ref.invalidate(
                        authorProfileProvider(widget.authorHandle),
                      );
                    },
                    size: ButtonSize.small,
                    customColor:
                        profile.isFollowing
                            ? colorScheme.surfaceContainerHighest
                            : colorScheme.primary,
                    textColor:
                        profile.isFollowing
                            ? colorScheme.onSurface
                            : colorScheme.onPrimary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

void _openThread(BuildContext context, OpinionModel opinion) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
    ),
  );
}

/// Common empty/loading/error/list rendering shared by all three tab bodies,
/// each of which differs only in which provider it watches and which empty
/// state it shows.
Widget _buildOpinionSliverList({
  required BuildContext context,
  required List<OpinionModel> opinions,
  required IconData emptyIcon,
  required String emptyTitle,
  required String emptySubtitle,
}) {
  if (opinions.isEmpty) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyStateWidget(
              icon: emptyIcon,
              title: emptyTitle,
              subtitle: emptySubtitle,
            ),
          ),
        ),
      ],
    );
  }

  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      SliverOverlapInjector(
        handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final opinion = opinions[index];
          return OpinionCard(
            opinion: opinion,
            // isOwnProfile already suppresses the Follow button for your own
            // posts on your own profile; on someone else's profile the card
            // author IS that profile, so a per-card Follow button would be
            // redundant with the header's own Follow/Unfollow button above.
            showFollowButton: false,
            onOpinionTap: () => _openThread(context, opinion),
            onCommentTap: () => _openThread(context, opinion),
            // No profile-tap navigation: every card here already belongs to
            // the profile the viewer is looking at, own or someone else's —
            // there is nowhere new to navigate to.
            onProfileTap: null,
          );
        }, childCount: opinions.length),
      ),
    ],
  );
}

class _OpinionsTabBody extends ConsumerWidget {
  final String authorHandle;

  const _OpinionsTabBody({required this.authorHandle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opinionsAsync = ref.watch(profileOpinionsProvider(authorHandle));
    final isOwnProfile =
        ref.watch(authorProfileProvider(authorHandle)).valueOrNull?.isMine ??
        false;

    return opinionsAsync.when(
      loading: () => const ListviewLoadingShimmer(),
      error: (error, stack) => ErrorStateWidget.from(error),
      data:
          (opinions) => _buildOpinionSliverList(
            context: context,
            opinions: opinions,
            emptyIcon: Icons.forum_outlined,
            emptyTitle:
                isOwnProfile
                    ? 'You haven\'t posted any opinions yet'
                    : 'No opinions yet',
            emptySubtitle: '',
          ),
    );
  }
}

/// Reposts tab on SOMEONE ELSE's profile — get_author_reposted_opinions,
/// resolved by handle. Un-paginated like profileOpinionsProvider (an
/// author's full history, not a page at a time — matches the existing
/// Opinions tab's own no-pagination precedent on this screen).
class _AuthorRepostsTabBody extends ConsumerWidget {
  final String authorHandle;

  const _AuthorRepostsTabBody({required this.authorHandle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repostsAsync = ref.watch(
      profileRepostedOpinionsProvider(authorHandle),
    );

    return repostsAsync.when(
      loading: () => const ListviewLoadingShimmer(),
      error: (error, stack) => ErrorStateWidget.from(error),
      data:
          (opinions) => _buildOpinionSliverList(
            context: context,
            opinions: opinions,
            emptyIcon: FontAwesomeIcons.repeat,
            emptyTitle: 'Nothing reposted yet',
            emptySubtitle: '',
          ),
    );
  }
}

/// Reposts tab on YOUR OWN profile — reuses repostedOpinionsProvider (the
/// same paginated, optimistically-patched provider RepostedOpinionsScreen
/// already used) rather than the by-handle provider above, so pagination,
/// loadMore and the repost/save toggle patches already wired to it keep
/// working exactly as before.
class _OwnRepostsTabBody extends ConsumerStatefulWidget {
  const _OwnRepostsTabBody();

  @override
  ConsumerState<_OwnRepostsTabBody> createState() => _OwnRepostsTabBodyState();
}

class _OwnRepostsTabBodyState extends ConsumerState<_OwnRepostsTabBody> {
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(repostedOpinionsProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final repostedAsync = ref.watch(repostedOpinionsProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: repostedAsync.when(
        loading: () => const ListviewLoadingShimmer(),
        error: (error, stack) => ErrorStateWidget.from(error),
        data: (opinions) => _buildList(context, opinions),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: FontAwesomeIcons.repeat,
                title: 'Nothing reposted yet',
                subtitle:
                    'Tap the repeat icon on any opinion to share it and keep '
                    'it here.',
              ),
            ),
          ),
        ],
      );
    }

    final hasMore = ref.read(repostedOpinionsProvider.notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == opinions.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final opinion = opinions[index];
            return OpinionCard(
              opinion: opinion,
              onOpinionTap: () => _openThread(context, opinion),
              onCommentTap: () => _openThread(context, opinion),
            );
          }, childCount: opinions.length + (hasMore ? 1 : 0)),
        ),
      ],
    );
  }
}

/// Bookmarks tab, own profile only — reuses savedOpinionsProvider exactly as
/// SavedOpinionsScreen did.
class _OwnBookmarksTabBody extends ConsumerStatefulWidget {
  const _OwnBookmarksTabBody();

  @override
  ConsumerState<_OwnBookmarksTabBody> createState() =>
      _OwnBookmarksTabBodyState();
}

class _OwnBookmarksTabBodyState extends ConsumerState<_OwnBookmarksTabBody> {
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      ref.read(savedOpinionsProvider.notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final savedAsync = ref.watch(savedOpinionsProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: savedAsync.when(
        loading: () => const ListviewLoadingShimmer(),
        error: (error, stack) => ErrorStateWidget.from(error),
        data: (opinions) => _buildList(context, opinions),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<OpinionModel> opinions) {
    if (opinions.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: EmptyStateWidget(
                icon: Icons.bookmark_border,
                title: 'Nothing saved yet',
                subtitle:
                    'Tap the bookmark on any opinion to keep it here for later.',
              ),
            ),
          ),
        ],
      );
    }

    final hasMore = ref.read(savedOpinionsProvider.notifier).hasMore;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == opinions.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final opinion = opinions[index];
            return OpinionCard(
              opinion: opinion,
              onOpinionTap: () => _openThread(context, opinion),
              onCommentTap: () => _openThread(context, opinion),
            );
          }, childCount: opinions.length + (hasMore ? 1 : 0)),
        ),
      ],
    );
  }
}
