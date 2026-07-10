// lib/features/opinions/presentation/screens/discover_feed_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/widgets/buttons/app_button.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:attune/features/opinions/presentation/screen/anonymous_profile_screen.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/opinion_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(discoverFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final opinionsAsync = ref.watch(discoverFeedProvider);
    final isAuthenticated = currentUserId != null;

    return Scaffold(
      floatingActionButton:
          isAuthenticated
              ? FloatingActionButton(
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
            !isAuthenticated
                ? _buildAnonymousPreview(context)
                : opinionsAsync.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                  data: (opinions) {
                    if (opinions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 64,
                              color: Colors.grey,
                            ),
                            Gap(Spacing.md.h),
                            Text(
                              'No opinions yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Gap(Spacing.sm.h),
                            Text('Be the first to share your thoughts'),
                            Gap(Spacing.lg.h),
                            AppButton(
                              label: 'Write your first opinion',
                              onPressed: () async {
                                final needsRefresh = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => const OpinionComposeScreen(),
                                  ),
                                );
                                if (needsRefresh == true) {
                                  ref.invalidate(discoverFeedProvider);
                                }
                              },
                            ),
                          ],
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
                                      userId: opinion.userId,
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
                userId: '',
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
