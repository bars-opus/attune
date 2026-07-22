// lib/features/opinions/presentation/screens/discover_feed_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'opinion_compose_screen.dart';

class DiscoverFeedScreen extends ConsumerStatefulWidget {
  const DiscoverFeedScreen({super.key});

  @override
  ConsumerState<DiscoverFeedScreen> createState() => _DiscoverFeedScreenState();
}

class _DiscoverFeedScreenState extends ConsumerState<DiscoverFeedScreen> {
  final ScrollController _scrollController = ScrollController();
  static const _anonymousPreviewOpinions = <({String status, String content})>[
    (
      status: 'Taken',
      content:
          'What has actually helped you repair after the same argument keeps coming back?',
    ),
    (
      status: 'Single',
      content:
          'How do you tell the difference between healthy space and emotional distance?',
    ),
    (
      status: 'Exploring',
      content:
          'What early signs make you feel calm with someone instead of hyper-alert?',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Guests are shown a static local preview (below) and never a live feed —
    // loadMore must not fire discoverFeedProvider's backend RPC for them. It is
    // granted to `authenticated` only, so an anon call 42501s (this is what
    // produced the "error while scrolling Discover" report for a guest).
    if (ref.read(currentUserIdProvider) == null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(discoverFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAuthenticated = currentUserId != null;
    // Only watch the live feed provider (and so only trigger its backend RPC)
    // once authenticated. Watching it unconditionally previously fired
    // get_discover_opinions for guests every build, well before the
    // isAuthenticated branch below ever chose to render its result — the RPC is
    // granted to `authenticated` only, so that call always 42501s for a guest.
    final opinionsAsync =
        isAuthenticated ? ref.watch(discoverFeedProvider) : null;

    return Scaffold(
      floatingActionButton:
          isAuthenticated
              ? FloatingActionButton(
                // Discover and Following are sibling tabs kept alive
                // simultaneously (AutomaticKeepAliveClientMixin), so their
                // default-tagged FABs collide as soon as both are mounted —
                // "multiple heroes share the same tag" the instant either
                // pushes a route. Distinct tags disambiguate them.
                heroTag: 'opinions-discover-fab',
                onPressed: () async {
                  final needsRefresh = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OpinionComposeScreen(),
                    ),
                  );
                  if (needsRefresh == true) {
                    ref.invalidate(discoverFeedProvider);
                  }
                },
                child: const Icon(Icons.add),
              )
              : null,
      body: RefreshIndicator(
        onRefresh: () async {
          if (!isAuthenticated) return;
          ref.invalidate(discoverFeedProvider);
          await ref.read(discoverFeedProvider.future);
        },
        child:
            !isAuthenticated || opinionsAsync == null
                ? _buildAnonymousPreview(context)
                : opinionsAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => ErrorStateWidget.from(error),
                  data: (opinions) {
                    if (opinions.isEmpty) {
                      return Center(
                        child: EmptyStateWidget(
                          icon: Icons.rate_review_outlined,
                          title: 'No opinions yet',
                          subtitle: 'Be the first to share your thoughts',
                          onAction: () async {
                            final needsRefresh = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const OpinionComposeScreen(),
                              ),
                            );
                            if (needsRefresh == true) {
                              ref.invalidate(discoverFeedProvider);
                            }
                          },

                          actionLabel: 'Write your first opinion',
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount:
                          opinions.length +
                          (ref.read(discoverFeedProvider.notifier).hasMore
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == opinions.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final opinion = opinions[index];
                        return OpinionCard(
                          opinion: opinion,
                          onCommentTap: () {
                            // Navigate to comment thread
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => CommentThreadScreen(
                                      opinionId: opinion.id,
                                    ),
                              ),
                            );
                          },
                          onProfileTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => AnonymousProfileScreen(
                                      authorHandle: opinion.authorHandle,
                                    ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
      ),
    );
  }

  Widget _buildAnonymousPreview(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: Spacing.xl.h),
      children: [
        Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: SemanticContainerWidget(
            title: 'Read-only guest preview',
            content:
                'You can browse opinions before creating an account. Continue with phone number from Chat to post, reply, follow, or react.',
            icon: Icons.visibility_outlined,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.1),
            borderColor: Theme.of(context).colorScheme.primary,
            iconColor: Theme.of(context).colorScheme.primary,
            textTheme: textTheme,
          ),
        ),
        ..._anonymousPreviewOpinions.map(
          (opinion) => Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.lg.w),
            child: OpinionCard(
              opinion: OpinionModel(
                id: opinion.content,
                authorHandle: '',
                isMine: false,
                content: opinion.content,
                relationshipStatus: _normalizePreviewStatus(opinion.status),
                likeCount: 0,
                dislikeCount: 0,
                commentCount: 0,
                createdAt: DateTime.now(),
              ),
              showFollowButton: false,
              onCommentTap:
                  () => context.showInfoSnackbar(
                    'Continue with phone number from Chat to join the conversation.',
                  ),
            ),
          ),
        ),
      ],
    );
  }

  String _normalizePreviewStatus(String status) {
    return switch (status) {
      'Taken' => 'taken',
      'Exploring' => 'figuring_it_out',
      _ => 'single',
    };
  }
}
