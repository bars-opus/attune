// lib/features/opinions/presentation/screens/following_feed_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
import 'opinion_compose_screen.dart';

class FollowingFeedScreen extends ConsumerStatefulWidget {
  const FollowingFeedScreen({super.key});

  @override
  ConsumerState<FollowingFeedScreen> createState() =>
      _FollowingFeedScreenState();
}

class _FollowingFeedScreenState extends ConsumerState<FollowingFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more if pagination is needed (future enhancement)
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUserId = ref.watch(currentUserIdProvider);
    final isAuthenticated = currentUserId != null;
    // Only watch (and so only trigger) the live feed provider once
    // authenticated — see discover_feed_screen.dart for why an unconditional
    // watch 42501s for a guest (the RPC is granted to `authenticated` only).
    final followingAsync =
        isAuthenticated ? ref.watch(followingFeedProvider) : null;

    return Scaffold(
      floatingActionButton:
          isAuthenticated
              ? FloatingActionButton(
                // See discover_feed_screen.dart's matching comment: sibling
                // tabs are kept alive together, so default-tagged FABs
                // collide. Distinct tags disambiguate them.
                heroTag: 'opinions-following-fab',
                onPressed: () async {
                  final needsRefresh = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OpinionComposeScreen(),
                    ),
                  );
                  if (needsRefresh == true) {
                    ref.invalidate(followingFeedProvider);
                  }
                },
                child: const Icon(Icons.add),
              )
              : null,
      body: RefreshIndicator(
        onRefresh: () async {
          if (!isAuthenticated) return;
          await ref.read(followingFeedProvider.notifier).refresh();
        },
        child:
            !isAuthenticated || followingAsync == null
                ? ListView(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(Spacing.lg.h),
                      child: SemanticContainerWidget(
                        title: 'Following unlocks after verification',
                        content:
                            'Guest browsing is available in Discover. Continue with phone number from Chat to follow voices and build a personal feed.',
                        icon: Icons.person_add_alt_1_outlined,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        borderColor: Theme.of(context).colorScheme.primary,
                        iconColor: Theme.of(context).colorScheme.primary,
                        textTheme: Theme.of(context).textTheme,
                      ),
                    ),
                  ],
                )
                : followingAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => ErrorStateWidget.from(error),
                  data: (opinions) {
                    if (opinions.isEmpty) {
                      return Center(
                        child: EmptyStateWidget(
                          icon: Icons.person_add_outlined,
                          title: 'You are not following anyone yet',
                          subtitle:
                              'Head to Discover to find voices you connect with',
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: opinions.length,
                      itemBuilder: (context, index) {
                        final opinion = opinions[index];
                        return OpinionCard(
                          opinion: opinion,
                          onCommentTap: () {
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
}
