// lib/features/forums/presentation/screens/contributing_forums_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/forums/presentation/providers/forum_providers.dart';
import 'package:attune/features/forums/presentation/widgets/forum_card.dart';
import 'package:attune/home/providers/nav_visibility_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/home/widgets/semantic_container_widget.dart';
import 'package:attune/core/widgets/feedback/error_state.dart';

class ContributingForumsScreen extends ConsumerStatefulWidget {
  const ContributingForumsScreen({super.key});

  @override
  ConsumerState<ContributingForumsScreen> createState() =>
      _ContributingForumsScreenState();
}

class _ContributingForumsScreenState
    extends ConsumerState<ContributingForumsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(contributingForumsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated =
        ref.watch(supabaseClientProvider).auth.currentUser?.id != null;
    final textTheme = Theme.of(context).textTheme;
    final contributingAsync = ref.watch(contributingForumsProvider);

    if (!isAuthenticated) {
      return NotificationListener<UserScrollNotification>(
        onNotification:
            (notification) =>
                NavVisibilityScrollHandler.handle(ref, notification),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(Spacing.lg.w),
                child: SemanticContainerWidget(
                  title: 'Contributing is account-only',
                  content:
                      'Guest browsing stays in Explore. Continue with phone number from Chat to vote, join debates, and track your contributing forums.',
                  icon: Icons.lock_outline,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderColor: Theme.of(context).colorScheme.primary,
                  iconColor: Theme.of(context).colorScheme.primary,
                  textTheme: textTheme,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return NotificationListener<UserScrollNotification>(
      onNotification:
          (notification) =>
              NavVisibilityScrollHandler.handle(ref, notification),
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(contributingForumsProvider);
          await ref.read(contributingForumsProvider.future);
        },
        child: contributingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => ErrorStateWidget.from(error),
          data: (forums) {
            if (forums.isEmpty) {
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverOverlapInjector(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_outlined, size: 64, color: Colors.grey),
                          Gap(Spacing.lg.h),
                          Text(
                            'No contributions yet',
                            style: textTheme.titleMedium,
                          ),
                          Gap(Spacing.sm.h),
                          Text(
                            'Vote on a topic or join a debate\nto see it here',
                            textAlign: TextAlign.center,
                          ),
                          Gap(Spacing.lg.h),
                          ElevatedButton.icon(
                            onPressed: () {
                              // Switch to Explore tab
                              // This would need a tab controller reference
                            },
                            icon: const Icon(Icons.explore),
                            label: const Text('Explore forums'),
                          ),
                        ],
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
                SliverPadding(
                  padding: EdgeInsets.all(Spacing.md.w),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final forum = forums[index];
                        final userSide =
                            forum.userVote != null
                                ? (forum.userVote == 'up' ? 'FOR' : 'AGAINST')
                                : (forum.userSide ?? 'Browsing');

                        return ForumCard(forum: forum, userSide: userSide);
                      },
                      childCount: forums.length,
                    ),
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
