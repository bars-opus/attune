// lib/features/forums/presentation/screens/contributing_forums_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/widgets/feedback/empty_state.dart';
import 'package:attune/core/widgets/shop_listview_loading_shimmer.dart';
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
    final contributingAsync = ref.watch(contributingForumsProvider);

    if (!isAuthenticated) {
      return NotificationListener<UserScrollNotification>(
        onNotification:
            (notification) =>
                NavVisibilityScrollHandler.handle(ref, notification),
        child: Center(
          child: EmptyStateWidget(
            icon: Icons.edit,
            title: 'No Contributions',
            subtitle: 'Login and start contributing in forums.',
          ),
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
          loading: () => const ListviewLoadingShimmer(),
          error: (error, stack) => ErrorStateWidget.from(error),
          data: (forums) {
            if (forums.isEmpty) {
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverOverlapInjector(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: EmptyStateWidget(
                        icon: Icons.forum_outlined,
                        title: 'No contributions yet',
                        subtitle:
                            'Vote on a topic or join a debate\nto see it here',
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
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.all(Spacing.md.w),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final forum = forums[index];
                      final userSide =
                          forum.userVote != null
                              ? (forum.userVote == 'up' ? 'FOR' : 'AGAINST')
                              : (forum.userSide ?? 'Browsing');

                      return ForumCard(forum: forum, userSide: userSide);
                    }, childCount: forums.length),
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
